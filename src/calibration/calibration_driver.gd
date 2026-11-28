class_name CalibrationDriver
extends RefCounted
## Pure, versioned fixed-path follower for the M1.7 calibration contract.
##
## This is a CONTROL component only. It consumes a committed `CarState`, an
## externally authored 2D road-plane line profile and externally validated route
## progress, and returns one normalized `DriverCommand` plus bounded telemetry.
## It never integrates physics, mutates its inputs, touches a Godot body, scene
## tree, clock, RNG or input device, and it has no tactical planner, difficulty
## scaling or deliberate driver noise.
##
## Progress is supplied by the caller. This driver deliberately does not search
## for the nearest Euclidean point on the line: a nearest-point query cannot
## distinguish a hairpin, overpass or repeated route section, and BENCHMARKS
## makes validated ordered progress authoritative. The caller's progress selects
## the segment; this driver only clamps it to the profile's declared station
## range and reports that clamping in telemetry.
##
## Coordinate convention matches `CarState`: +Y forward, +X right, positive
## steer turns the nose right. The control law is a fixed bearing pursuit:
##   * the lookahead station is `clamp(progress_used + lookahead, first, last)`;
##   * the target point and the control speed target are linearly interpolated
##     at that station (local target speed at the car's own station is also
##     reported, but does not drive the throttle/brake decision);
##   * steer is `steer_gain_per_rad * atan2(right_error, forward_error)`,
##     clamped to the declared maximum;
##   * throttle and brake are mutually exclusive, with a declared deadband.
##
## Every refusal leaves `command` null. Refusals are path/state/tuning/progress
## specific and carry a stable code plus detail; a refused call never emits a
## partial command.

const DRIVER_ID := &"calibration_driver"
const DRIVER_VERSION := "1.0.0"
## Documented fixed cadence. The follower itself is stateless: callers sample
## once per 60 Hz logical tick and the same committed inputs always produce the
## same output.
const FIXED_STEP_S := 1.0 / 60.0

enum Refusal {
	NONE = 0,
	NULL_OR_WRONG_STATE,
	NONFINITE_STATE,
	AIRBORNE_STATE_NOT_SUPPORTED,
	NULL_OR_WRONG_PATH,
	INVALID_PATH,
	NULL_OR_WRONG_TUNING,
	INVALID_TUNING,
	NONFINITE_PROGRESS,
	INVALID_OUTPUT,
}


## Explicit follower tuning. The defaults are readable laboratory defaults, not
## measured handling or calibrated pace values. Every field is validated; the
## calibration gates that would freeze real values are named in the lab README.
class Tuning extends RefCounted:
	## Minimum lookahead distance in metres.
	var lookahead_base_m := 3.0
	## Additional lookahead in metres per m/s of signed forward speed (seconds).
	var lookahead_speed_gain_s := 0.6
	## Hard cap on the computed lookahead distance in metres.
	var lookahead_max_m := 25.0
	## Normalized steer per radian of target-bearing error.
	var steer_gain_per_rad := 1.5
	## Maximum absolute normalized steer; must stay within [0, 1].
	var max_steer := 1.0
	## Normalized throttle per m/s of under-target speed error.
	var throttle_gain_per_m_s := 0.4
	## Normalized brake per m/s of over-target speed error.
	var brake_gain_per_m_s := 0.8
	## Symmetric speed band in m/s inside which neither throttle nor brake acts.
	var speed_deadband_m_s := 0.25


	static func make(
		p_lookahead_base_m := 3.0,
		p_lookahead_speed_gain_s := 0.6,
		p_lookahead_max_m := 25.0,
		p_steer_gain_per_rad := 1.5,
		p_max_steer := 1.0,
		p_throttle_gain_per_m_s := 0.4,
		p_brake_gain_per_m_s := 0.8,
		p_speed_deadband_m_s := 0.25
	) -> Tuning:
		var tuning := Tuning.new()
		tuning.lookahead_base_m = p_lookahead_base_m
		tuning.lookahead_speed_gain_s = p_lookahead_speed_gain_s
		tuning.lookahead_max_m = p_lookahead_max_m
		tuning.steer_gain_per_rad = p_steer_gain_per_rad
		tuning.max_steer = p_max_steer
		tuning.throttle_gain_per_m_s = p_throttle_gain_per_m_s
		tuning.brake_gain_per_m_s = p_brake_gain_per_m_s
		tuning.speed_deadband_m_s = p_speed_deadband_m_s
		return tuning


	func is_valid() -> bool:
		# Inner classes do not inherit outer statics unqualified; qualify them.
		if not CalibrationDriver._finite(lookahead_base_m) or lookahead_base_m < 0.0:
			return false
		if (
			not CalibrationDriver._finite(lookahead_speed_gain_s)
			or lookahead_speed_gain_s < 0.0
		):
			return false
		if not CalibrationDriver._finite(lookahead_max_m) or lookahead_max_m <= 0.0:
			return false
		if lookahead_max_m < lookahead_base_m:
			return false
		if not CalibrationDriver._positive_finite(steer_gain_per_rad):
			return false
		if not CalibrationDriver._positive_finite(max_steer) or max_steer > 1.0:
			return false
		if not CalibrationDriver._positive_finite(throttle_gain_per_m_s):
			return false
		if not CalibrationDriver._positive_finite(brake_gain_per_m_s):
			return false
		if (
			not CalibrationDriver._finite(speed_deadband_m_s)
			or speed_deadband_m_s < 0.0
		):
			return false
		return true


## One authored open-line sample. `s_m` is monotonic arclength along the line.
class PathSample extends RefCounted:
	var s_m := 0.0
	var position_m := Vector2.ZERO
	var target_speed_m_s := 0.0


	static func make(
		p_s_m: float, p_position_m: Vector2, p_target_speed_m_s: float
	) -> PathSample:
		var sample := PathSample.new()
		sample.s_m = p_s_m
		sample.position_m = p_position_m
		sample.target_speed_m_s = p_target_speed_m_s
		return sample


## An interpolated point on the profile. `blend_t` is the position/speed blend
## between the selected segment's low and high samples.
class PathPoint extends RefCounted:
	var s_m := 0.0
	var position_m := Vector2.ZERO
	var target_speed_m_s := 0.0
	var segment_index := 0
	var blend_t := 0.0


## Versioned authored line profile. Construct through `from_arrays` or assign a
## validated `samples` array; `is_valid()`/`validation_error()` re-check the
## current contents on every call so post-construction mutation is caught.
class CalibrationPath extends RefCounted:
	var version := "calibration_path.v1"
	var samples: Array[PathSample] = []


	static func from_arrays(
		p_s: Array,
		p_positions: Array,
		p_speeds: Array,
		p_version := "calibration_path.v1"
	) -> CalibrationPath:
		var path := CalibrationPath.new()
		path.version = p_version if typeof(p_version) == TYPE_STRING else ""
		if p_s.size() != p_positions.size() or p_s.size() != p_speeds.size():
			return path
		var built: Array[PathSample] = []
		for index in p_s.size():
			if not CalibrationDriver._is_number(p_s[index]):
				return path
			if typeof(p_positions[index]) != TYPE_VECTOR2:
				return path
			if not CalibrationDriver._is_number(p_speeds[index]):
				return path
			built.append(
				PathSample.make(
					float(p_s[index]), p_positions[index], float(p_speeds[index])
				)
			)
		path.samples = built
		return path


	func is_valid() -> bool:
		return validation_error().is_empty()


	func validation_error() -> String:
		if version.is_empty():
			return "missing path version"
		if samples.size() < 2:
			return "fewer than two samples"
		var previous_s := -INF
		for index in samples.size():
			var sample: PathSample = samples[index]
			if not CalibrationDriver._finite(sample.s_m):
				return "sample %d has nonfinite s" % index
			if sample.s_m < 0.0:
				return "sample %d has negative s" % index
			# Strictly increasing rejects duplicate stations as well as
			# decreasing ones; the comparison is only reached for finite s.
			if sample.s_m <= previous_s:
				return "sample %d has non-monotonic or duplicate s" % index
			if not CalibrationDriver._vector2_finite(sample.position_m):
				return "sample %d has nonfinite position" % index
			if not CalibrationDriver._finite(sample.target_speed_m_s):
				return "sample %d has nonfinite target speed" % index
			if sample.target_speed_m_s < 0.0:
				return "sample %d has negative target speed" % index
			previous_s = sample.s_m
		return ""


	func first_s_m() -> float:
		return samples[0].s_m


	func last_s_m() -> float:
		return samples[samples.size() - 1].s_m


	## Declared open-profile length in metres (`last_s - first_s`).
	func length_m() -> float:
		return last_s_m() - first_s_m()


	## Explicit end clamping. Callers can see what the driver used in telemetry;
	## progress outside the declared station range is clamped, never treated as
	## authoritative beyond the line.
	func clamp_progress_m(progress_m: float) -> float:
		return clampf(progress_m, first_s_m(), last_s_m())


	## Segment selected by externally validated progress. The largest sample
	## station at or below the clamped progress chooses the segment; the final
	## sample is never a segment start.
	func segment_index_for_progress_m(progress_m: float) -> int:
		var count := samples.size()
		var station := clamp_progress_m(progress_m)
		if station <= samples[0].s_m:
			return 0
		if station >= samples[count - 1].s_m:
			return count - 2
		var low := 0
		var high := count - 1
		while low + 1 < high:
			var middle := (low + high) / 2
			if samples[middle].s_m <= station:
				low = middle
			else:
				high = middle
		return low


	## Linear interpolation in arclength, with explicit end clamping.
	func interpolate_at(progress_m: float) -> PathPoint:
		var station := clamp_progress_m(progress_m)
		var index := segment_index_for_progress_m(station)
		var low: PathSample = samples[index]
		var high: PathSample = samples[index + 1]
		var span := high.s_m - low.s_m
		var blend := 0.0
		if span > 0.0:
			blend = (station - low.s_m) / span
		var point := PathPoint.new()
		point.s_m = station
		point.position_m = low.position_m.lerp(high.position_m, blend)
		point.target_speed_m_s = lerpf(
			low.target_speed_m_s, high.target_speed_m_s, blend
		)
		point.segment_index = index
		point.blend_t = blend
		return point


## Fixed-field telemetry record. No dictionaries, node references or unbounded
## arrays: the record is bounded by construction. Numeric fields are zero on a
## refusal unless a value was already known.
class Telemetry extends RefCounted:
	var driver_id := &"calibration_driver"
	var driver_version := "1.0.0"
	var path_version := ""
	var progress_requested_m := 0.0
	var progress_used_m := 0.0
	var progress_clamped_low := false
	var progress_clamped_high := false
	var segment_index := -1
	var lookahead_m := 0.0
	var target_s_m := 0.0
	var target_position_m := Vector2.ZERO
	var target_speed_m_s := 0.0
	var local_target_speed_m_s := 0.0
	var forward_speed_m_s := 0.0
	var speed_error_m_s := 0.0
	var bearing_rad := 0.0
	var steer_command := 0.0
	var throttle_command := 0.0
	var brake_command := 0.0
	var accepted := false
	var refusal_code := 0
	var refusal_label := "none"


## One follower decision. On refusal `accepted` is false and `command` is null.
class Decision extends RefCounted:
	var accepted := false
	var command: DriverCommand = null
	var refusal_code := Refusal.NONE
	var refusal_label := "none"
	var refusal_detail := ""
	var telemetry := Telemetry.new()


## Evaluate one fixed-tick follower decision.
##
## `state_in` must be a finite, grounded committed `CarState`; `path_in` a valid
## `CalibrationPath`; `progress_m` a finite externally validated station; and
## `tuning_in` a valid `Tuning`. A refusal returns a Decision with no command.
static func decide(state_in, path_in, progress_m, tuning_in) -> Decision:
	var decision := Decision.new()
	var telemetry := decision.telemetry
	telemetry.driver_id = DRIVER_ID
	telemetry.driver_version = DRIVER_VERSION

	if state_in == null or not state_in is CarState:
		return _refuse(
			decision, Refusal.NULL_OR_WRONG_STATE, "state must be a committed CarState"
		)
	if not state_in.is_finite():
		return _refuse(
			decision, Refusal.NONFINITE_STATE, "CarState contains NaN or Inf"
		)
	if path_in == null or not path_in is CalibrationPath:
		return _refuse(
			decision, Refusal.NULL_OR_WRONG_PATH, "path must be a CalibrationPath"
		)
	telemetry.path_version = path_in.version
	var path_error: String = path_in.validation_error()
	if not path_error.is_empty():
		return _refuse(decision, Refusal.INVALID_PATH, path_error)
	if tuning_in == null or not tuning_in is Tuning:
		return _refuse(
			decision,
			Refusal.NULL_OR_WRONG_TUNING,
			"tuning must be CalibrationDriver.Tuning"
		)
	if not tuning_in.is_valid():
		return _refuse(
			decision, Refusal.INVALID_TUNING, "tuning outside declared bounds"
		)
	if not _is_number(progress_m):
		return _refuse(
			decision, Refusal.NONFINITE_PROGRESS, "progress must be numeric"
		)
	var requested_progress := float(progress_m)
	if not _finite(requested_progress):
		return _refuse(
			decision, Refusal.NONFINITE_PROGRESS, "progress must be finite"
		)
	telemetry.progress_requested_m = requested_progress
	if not state_in.grounded:
		return _refuse(
			decision,
			Refusal.AIRBORNE_STATE_NOT_SUPPORTED,
			"calibration follower requires a grounded car"
		)

	var progress_used: float = path_in.clamp_progress_m(requested_progress)
	telemetry.progress_used_m = progress_used
	telemetry.progress_clamped_low = requested_progress < path_in.first_s_m()
	telemetry.progress_clamped_high = requested_progress > path_in.last_s_m()

	var forward_speed: float = state_in.forward_speed_m_s()
	var lookahead := clampf(
		tuning_in.lookahead_base_m
		+ tuning_in.lookahead_speed_gain_s * forward_speed,
		tuning_in.lookahead_base_m,
		tuning_in.lookahead_max_m
	)
	telemetry.lookahead_m = lookahead

	var local_point: CalibrationDriver.PathPoint = path_in.interpolate_at(progress_used)
	telemetry.local_target_speed_m_s = local_point.target_speed_m_s

	var target: CalibrationDriver.PathPoint = path_in.interpolate_at(
		progress_used + lookahead
	)
	telemetry.target_s_m = target.s_m
	telemetry.target_position_m = target.position_m
	telemetry.target_speed_m_s = target.target_speed_m_s
	telemetry.segment_index = target.segment_index

	var forward: Vector2 = state_in.forward_vector()
	var right: Vector2 = state_in.right_vector()
	var to_target: Vector2 = target.position_m - state_in.position_m
	var bearing := atan2(to_target.dot(right), to_target.dot(forward))
	telemetry.bearing_rad = bearing
	var steer := clampf(
		tuning_in.steer_gain_per_rad * bearing,
		-tuning_in.max_steer,
		tuning_in.max_steer
	)
	telemetry.steer_command = steer

	# The control speed target is interpolated at the lookahead station, so an
	# authored braking-zone profile reaches the throttle/brake decision before
	# the car arrives. This follower adds no braking-distance model of its own;
	# conservative line/speed calibration is a separate M1.7 gate.
	var speed_error: float = target.target_speed_m_s - forward_speed
	telemetry.forward_speed_m_s = forward_speed
	telemetry.speed_error_m_s = speed_error
	var throttle := 0.0
	var brake := 0.0
	if speed_error > tuning_in.speed_deadband_m_s:
		throttle = clampf(tuning_in.throttle_gain_per_m_s * speed_error, 0.0, 1.0)
	elif speed_error < -tuning_in.speed_deadband_m_s:
		brake = clampf(tuning_in.brake_gain_per_m_s * (-speed_error), 0.0, 1.0)
	telemetry.throttle_command = throttle
	telemetry.brake_command = brake

	var command := DriverCommand.create(steer, throttle, brake, 0.0, false, false)
	if command == null:
		return _refuse(
			decision, Refusal.INVALID_OUTPUT, "command construction failed"
		)
	decision.accepted = true
	decision.command = command
	telemetry.accepted = true
	telemetry.refusal_code = Refusal.NONE
	telemetry.refusal_label = "none"
	return decision


static func refusal_label(code: int) -> String:
	match code:
		Refusal.NONE:
			return "none"
		Refusal.NULL_OR_WRONG_STATE:
			return "null_or_wrong_state"
		Refusal.NONFINITE_STATE:
			return "nonfinite_state"
		Refusal.AIRBORNE_STATE_NOT_SUPPORTED:
			return "airborne_state_not_supported"
		Refusal.NULL_OR_WRONG_PATH:
			return "null_or_wrong_path"
		Refusal.INVALID_PATH:
			return "invalid_path"
		Refusal.NULL_OR_WRONG_TUNING:
			return "null_or_wrong_tuning"
		Refusal.INVALID_TUNING:
			return "invalid_tuning"
		Refusal.NONFINITE_PROGRESS:
			return "nonfinite_progress"
		Refusal.INVALID_OUTPUT:
			return "invalid_output"
	return "unknown_refusal"


static func _refuse(decision: Decision, code: int, detail: String) -> Decision:
	decision.accepted = false
	decision.command = null
	decision.refusal_code = code
	decision.refusal_label = refusal_label(code)
	decision.refusal_detail = detail
	decision.telemetry.accepted = false
	decision.telemetry.refusal_code = code
	decision.telemetry.refusal_label = refusal_label(code)
	return decision


static func _is_number(value) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT


static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)


static func _positive_finite(value: float) -> bool:
	return _finite(value) and value > 0.0


static func _vector2_finite(value: Vector2) -> bool:
	return _finite(value.x) and _finite(value.y)
