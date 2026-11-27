class_name ArcadeMotor
extends RefCounted
## Pure, stateless 60 Hz arcade motor kernel (M1.1 first slice).
##
## `propose(state, command, tuning, dt)` consumes a validated
## `DriverCommand`, a committed `CarState` and explicit `MotorTuning`, and
## returns a proposed new `CarState`, road-plane displacement and yaw delta.
## It never mutates its inputs, never touches a Godot body, scene tree,
## physics server or RNG, and produces no side effects. Calling it repeatedly
## is not evidence of world steps; the simulation coordinator owns commits,
## clocks, contacts and events (docs/TECHNICAL_DESIGN.md:63-67).
##
## Covered in this slice:
##   * forward acceleration from one explicitly supplied speed/acceleration
##     curve (the schema's duplicate `engine`/`handling` curve question is
##     deferred: the kernel accepts exactly one curve and does not read the
##     handling resource);
##   * braking, aerodynamic/rolling drag and coasting;
##   * the design's reverse transition (below 1 m/s after a 0.3 s brake hold,
##     docs/GAME_DESIGN.md:11) using explicit tuning values;
##   * basic speed-scaled grip yaw and exponential lateral damping.
##
## Deferred seams are documented on `CarState`: drift, surface modifiers,
## transmission/gear selection, surge, drafting, contact immunity and route
## progress are carried but not interpreted. Airborne integration is also out
## of scope: an ungrounded car keeps its momentum and receives no yaw in this
## slice. No handling coefficient is frozen here; every physical number is a
## field on `MotorTuning` supplied by the caller.
##
## Fixed-step contract: callers pass `ArcadeMotor.DT` (1/60 s). Other positive
## step sizes are refused rather than silently integrated.

const DT := 1.0 / 60.0
## Absolute tolerance for accepting a caller-supplied step size as 60 Hz.
const DT_TOLERANCE_S := 1e-6


## One point of a piecewise-linear speed/acceleration curve.
class SpeedAccelerationPoint extends RefCounted:
	var speed_m_s := 0.0
	var acceleration_m_s2 := 0.0

	static func make(p_speed_m_s: float, p_acceleration_m_s2: float) -> SpeedAccelerationPoint:
		var point := SpeedAccelerationPoint.new()
		point.speed_m_s = p_speed_m_s
		point.acceleration_m_s2 = p_acceleration_m_s2
		return point


## Explicit tuning values for one evaluation. Every physical coefficient is
## supplied by the caller; the defaults are deliberately inert zeros (plus the
## two control-semantic constants from docs/GAME_DESIGN.md:11) and are not a
## frozen handling specification.
##
##   * `acceleration_curve`: piecewise-linear forward acceleration (m/s^2) versus
##     ground-speed magnitude (m/s); strictly increasing speeds;
##   * `braking_acceleration_m_s2`: maximum brake deceleration;
##   * `drag_aerodynamic`: deceleration contribution `k * |v|^2`;
##   * `drag_rolling`: constant deceleration contribution;
##   * `yaw_gain_grip`: yaw rate per unit steer per m/s of ground speed;
##   * `max_yaw_rate_rad_s`: absolute yaw-rate cap (`INF` disables the cap);
##   * `lateral_damping_grip_per_s`: exponential lateral-velocity decay rate;
##   * `reverse_trigger_speed_m_s`: brake becomes reverse at or below this speed;
##   * `reverse_hold_time_s`: required brake hold at/below the trigger speed;
##   * `reverse_acceleration_m_s2` and `reverse_top_speed_m_s`: explicit reverse
##     drive parameters (the game design does not fix a reverse top speed).
class MotorTuning extends RefCounted:
	var acceleration_curve: Array[SpeedAccelerationPoint] = []
	var braking_acceleration_m_s2 := 0.0
	var drag_aerodynamic := 0.0
	var drag_rolling := 0.0
	var yaw_gain_grip := 0.0
	var max_yaw_rate_rad_s := INF
	var lateral_damping_grip_per_s := 0.0
	var reverse_trigger_speed_m_s := 1.0
	var reverse_hold_time_s := 0.3
	var reverse_acceleration_m_s2 := 0.0
	var reverse_top_speed_m_s := 0.0


	static func make(
		p_curve: Array = [],
		p_braking_acceleration_m_s2 := 0.0,
		p_drag_aerodynamic := 0.0,
		p_drag_rolling := 0.0,
		p_yaw_gain_grip := 0.0,
		p_max_yaw_rate_rad_s := INF,
		p_lateral_damping_grip_per_s := 0.0,
		p_reverse_trigger_speed_m_s := 1.0,
		p_reverse_hold_time_s := 0.3,
		p_reverse_acceleration_m_s2 := 0.0,
		p_reverse_top_speed_m_s := 0.0
	) -> MotorTuning:
		var tuning := MotorTuning.new()
		var typed_curve: Array[SpeedAccelerationPoint] = []
		for point in p_curve:
			typed_curve.append(point)
		tuning.acceleration_curve = typed_curve
		tuning.braking_acceleration_m_s2 = p_braking_acceleration_m_s2
		tuning.drag_aerodynamic = p_drag_aerodynamic
		tuning.drag_rolling = p_drag_rolling
		tuning.yaw_gain_grip = p_yaw_gain_grip
		tuning.max_yaw_rate_rad_s = p_max_yaw_rate_rad_s
		tuning.lateral_damping_grip_per_s = p_lateral_damping_grip_per_s
		tuning.reverse_trigger_speed_m_s = p_reverse_trigger_speed_m_s
		tuning.reverse_hold_time_s = p_reverse_hold_time_s
		tuning.reverse_acceleration_m_s2 = p_reverse_acceleration_m_s2
		tuning.reverse_top_speed_m_s = p_reverse_top_speed_m_s
		return tuning


	func is_valid() -> bool:
		if acceleration_curve.is_empty():
			return false
		var previous_speed := -1.0
		for point in acceleration_curve:
			if point == null or not point is SpeedAccelerationPoint:
				return false
			if not _finite(point.speed_m_s) or not _finite(point.acceleration_m_s2):
				return false
			if point.speed_m_s < 0.0 or point.acceleration_m_s2 < 0.0:
				return false
			if point.speed_m_s <= previous_speed:
				return false
			previous_speed = point.speed_m_s
		if not _non_negative_finite(braking_acceleration_m_s2):
			return false
		if not _non_negative_finite(drag_aerodynamic):
			return false
		if not _non_negative_finite(drag_rolling):
			return false
		if not _non_negative_finite(yaw_gain_grip):
			return false
		if not _positive_finite_or_inf(max_yaw_rate_rad_s):
			return false
		if not _non_negative_finite(lateral_damping_grip_per_s):
			return false
		if not _non_negative_finite(reverse_trigger_speed_m_s):
			return false
		if not _non_negative_finite(reverse_hold_time_s):
			return false
		if not _non_negative_finite(reverse_acceleration_m_s2):
			return false
		if not _non_negative_finite(reverse_top_speed_m_s):
			return false
		if reverse_acceleration_m_s2 > 0.0 and reverse_top_speed_m_s <= 0.0:
			return false
		return true


	## Piecewise-linear interpolation of the declared curve at `speed_abs`.
	## Requires `is_valid()`; clamping outside the declared range is intended.
	func evaluate_acceleration(speed_abs: float) -> float:
		var first: SpeedAccelerationPoint = acceleration_curve[0]
		if speed_abs <= first.speed_m_s:
			return first.acceleration_m_s2
		var last: SpeedAccelerationPoint = acceleration_curve[acceleration_curve.size() - 1]
		if speed_abs >= last.speed_m_s:
			return last.acceleration_m_s2
		for index in range(acceleration_curve.size() - 1):
			var low: SpeedAccelerationPoint = acceleration_curve[index]
			var high: SpeedAccelerationPoint = acceleration_curve[index + 1]
			if speed_abs >= low.speed_m_s and speed_abs <= high.speed_m_s:
				var span := high.speed_m_s - low.speed_m_s
				if span <= 0.0:
					return high.acceleration_m_s2
				var blend := (speed_abs - low.speed_m_s) / span
				return lerpf(low.acceleration_m_s2, high.acceleration_m_s2, blend)
		return last.acceleration_m_s2


	static func _finite(value: float) -> bool:
		return not is_nan(value) and not is_inf(value)


	static func _non_negative_finite(value: float) -> bool:
		return _finite(value) and value >= 0.0


	static func _positive_finite_or_inf(value: float) -> bool:
		if is_inf(value):
			return value > 0.0
		return _finite(value) and value > 0.0


## Result of one pure motor evaluation. `state` is a new object; `state_in`,
## `command` and `tuning` are never mutated.
class MotorProposal extends RefCounted:
	var state := CarState.new()
	var displacement_m := Vector2(0.0, 0.0)
	var yaw_delta_rad := 0.0


## Evaluate one fixed 60 Hz motor step. Returns `null` for invalid input:
## nonfinite state/command/tuning/dt, a tuning curve that is empty, unsorted or
## out of range, or a step size that is not the declared 60 Hz tick.
static func propose(
	state_in: CarState,
	command: DriverCommand,
	tuning: MotorTuning,
	dt: float = DT
) -> MotorProposal:
	if state_in == null or command == null or tuning == null:
		return null
	if not state_in.is_finite() or not command.is_normalized() or not tuning.is_valid():
		return null
	if not _finite(dt) or dt <= 0.0 or absf(dt - DT) > DT_TOLERANCE_S:
		return null

	var proposed := state_in.copy()
	var forward := state_in.forward_vector()
	var right := state_in.right_vector()
	var forward_speed := state_in.velocity_m_s.dot(forward)
	var lateral_speed := state_in.velocity_m_s.dot(right)

	var reverse_engaged := state_in.reverse_engaged
	var reverse_hold_s := state_in.reverse_hold_s

	if state_in.grounded:
		# Reverse transition: brake held at/below the trigger speed for the
		# configured hold time engages reverse; throttle or releasing the brake
		# leaves reverse. It can never engage while above the trigger speed.
		if not reverse_engaged:
			if command.brake > 0.0 and forward_speed <= tuning.reverse_trigger_speed_m_s:
				reverse_hold_s += dt
				if reverse_hold_s >= tuning.reverse_hold_time_s:
					reverse_engaged = true
					reverse_hold_s = 0.0
			else:
				reverse_hold_s = 0.0
		elif command.throttle > 0.0 or command.brake <= 0.0:
			reverse_engaged = false
			reverse_hold_s = 0.0

		# Longitudinal forces. Engine and reverse drive are applied first;
		# brake (outside reverse) and drag are opposing deltas that cannot push
		# the car through zero in one step.
		var speed_abs := absf(forward_speed)
		if command.throttle > 0.0:
			forward_speed += command.throttle * tuning.evaluate_acceleration(speed_abs) * dt
		if command.brake > 0.0 and not reverse_engaged and forward_speed != 0.0:
			forward_speed = _apply_opposing_delta(
				forward_speed,
				-signf(forward_speed) * command.brake * tuning.braking_acceleration_m_s2 * dt
			)
		if reverse_engaged and command.brake > 0.0:
			forward_speed -= command.brake * tuning.reverse_acceleration_m_s2 * dt
			if tuning.reverse_top_speed_m_s > 0.0:
				forward_speed = maxf(forward_speed, -tuning.reverse_top_speed_m_s)
		var drag := tuning.drag_rolling + tuning.drag_aerodynamic * speed_abs * speed_abs
		if drag > 0.0 and forward_speed != 0.0:
			forward_speed = _apply_opposing_delta(
				forward_speed, -signf(forward_speed) * drag * dt
			)

	# Basic grip yaw: speed-scaled steer authority with an optional absolute cap.
	# Airborne cars receive no yaw in this slice; momentum is preserved.
	var yaw_rate := 0.0
	if state_in.grounded:
		var ground_speed := Vector2(forward_speed, lateral_speed).length()
		yaw_rate = command.steer * tuning.yaw_gain_grip * ground_speed
		if not is_inf(tuning.max_yaw_rate_rad_s):
			yaw_rate = clampf(
				yaw_rate, -tuning.max_yaw_rate_rad_s, tuning.max_yaw_rate_rad_s
			)

	# Exponential lateral damping in the current frame. Zero damping disables
	# the decay; no surface modifier is applied yet (deferred seam).
	if state_in.grounded and tuning.lateral_damping_grip_per_s > 0.0:
		lateral_speed *= exp(-tuning.lateral_damping_grip_per_s * dt)

	var heading_new := state_in.heading_rad + yaw_rate * dt
	var forward_new := Vector2(sin(heading_new), cos(heading_new))
	var right_new := Vector2(forward_new.y, -forward_new.x)
	var velocity_new := forward_new * forward_speed + right_new * lateral_speed
	var displacement := (state_in.velocity_m_s + velocity_new) * 0.5 * dt

	proposed.position_m = state_in.position_m + displacement
	proposed.velocity_m_s = velocity_new
	proposed.heading_rad = heading_new
	proposed.reverse_engaged = reverse_engaged
	proposed.reverse_hold_s = reverse_hold_s

	var proposal := MotorProposal.new()
	proposal.state = proposed
	proposal.displacement_m = displacement
	proposal.yaw_delta_rad = yaw_rate * dt
	return proposal


## Add `opposing_delta` to `value` without crossing zero this step.
static func _apply_opposing_delta(value: float, opposing_delta: float) -> float:
	var result := value + opposing_delta
	if value > 0.0 and result < 0.0:
		return 0.0
	if value < 0.0 and result > 0.0:
		return 0.0
	return result


static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)
