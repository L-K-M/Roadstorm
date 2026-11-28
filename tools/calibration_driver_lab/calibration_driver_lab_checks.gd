class_name CalibrationDriverLabChecks
extends RefCounted
## Assertion collectors and authored fixtures for the M1.7 calibration-driver
## CONTROL laboratory.
##
## These checks exercise the real `CalibrationDriver` only. They do not run the
## motor, integrate physics, build a course or produce a lap record. The two
## example profiles use explicit test-only speeds taken from the BENCHMARKS
## fixture table (the straight fixture's 30 m/s rolling-start entry and the
## sweeper fixture's 30 m/s entry); they are not measured or tuned calibration
## references. See README.md for the missing ordinary-motor, fixture,
## line-calibration and lap-evidence gates.

const DriverScript = preload("res://src/calibration/calibration_driver.gd")
const CarStateScript = preload("res://src/simulation/car_state.gd")

const FLOAT_TOLERANCE := 1e-9
const VECTOR_TOLERANCE := 1e-7

const TEST_PATH_VERSION := "roadstorm.calibration.lab.test_path.v1"
const EXAMPLE_STRAIGHT_VERSION := (
	"roadstorm.calibration.example_straight_500m.v1_test_only"
)
const EXAMPLE_SWEEPER_VERSION := (
	"roadstorm.calibration.example_sweeper_r120_90deg.v1_test_only"
)
const EXAMPLE_SPEED_M_S := 30.0
const EXAMPLE_STATUS := "authored_test_only_not_measured_or_tuned"


## One named case with its own counters so the runner can report exact totals.
class Case extends RefCounted:
	var name := ""
	var checks := 0
	var failures: Array[String] = []
	var measurements: Dictionary = {}


	func check(condition: bool, message: String) -> void:
		checks += 1
		if not condition:
			failures.append(message)


	func close(
		actual: float, expected: float, tolerance: float, message: String
	) -> void:
		checks += 1
		if absf(actual - expected) > tolerance:
			failures.append(
				"%s (got %.10f expected %.10f tol %.3f)"
				% [message, actual, expected, tolerance]
			)


	func equal(actual, expected, message: String) -> void:
		checks += 1
		if actual != expected:
			failures.append(
				"%s (got %s expected %s)" % [message, str(actual), str(expected)]
			)


	func vector_close(
		actual: Vector2, expected: Vector2, tolerance: float, message: String
	) -> void:
		close(actual.x, expected.x, tolerance, message + " x")
		close(actual.y, expected.y, tolerance, message + " y")


	func result() -> Dictionary:
		return {
			"case": name,
			"pass": failures.is_empty(),
			"checks": checks,
			"checks_failed": failures.size(),
			"failures": failures.duplicate(),
			"measurements": measurements.duplicate(),
		}


var cases_run := 0
var total_checks := 0
var total_failures := 0
var case_results: Array[Dictionary] = []


func run_all() -> Dictionary:
	var calls := [
		Callable(self, "_case_profile_validation"),
		Callable(self, "_case_steering_sign_and_matched_straight"),
		Callable(self, "_case_speed_control_and_exclusivity"),
		Callable(self, "_case_lookahead_interpolation_and_end_clamping"),
		Callable(self, "_case_invalid_inputs_return_refusals"),
		Callable(self, "_case_determinism_nonmutation_and_output_contract"),
		Callable(self, "_case_example_profiles_authored_smoke"),
	]
	for call in calls:
		var result: Dictionary = call.call()
		case_results.append(result)
		cases_run += 1
		total_checks += int(result["checks"])
		total_failures += int(result["checks_failed"])
		print(
			"CALIBRATION_DRIVER_LAB_CASE ",
			JSON.stringify({
				"case": result["case"],
				"checks": result["checks"],
				"checks_failed": result["checks_failed"],
				"pass": result["pass"],
			})
		)
	return {
		"schema": "roadstorm.calibration_driver_lab.summary.v1",
		"driver_id": CalibrationDriver.DRIVER_ID,
		"driver_version": CalibrationDriver.DRIVER_VERSION,
		"pass": total_failures == 0,
		"cases": cases_run,
		"cases_passed": cases_run - _failed_case_count(),
		"checks": total_checks,
		"checks_failed": total_failures,
		"case_results": case_results.duplicate(),
	}


func _failed_case_count() -> int:
	var failed := 0
	for result in case_results:
		if not bool(result["pass"]):
			failed += 1
	return failed


# --- Fixtures ----------------------------------------------------------------


static func make_straight_path(
	p_length_m := 500.0,
	p_step_m := 25.0,
	p_speed_m_s := EXAMPLE_SPEED_M_S,
	p_version := TEST_PATH_VERSION
) -> CalibrationDriver.CalibrationPath:
	var s_values: Array[float] = []
	var positions: Array[Vector2] = []
	var speeds: Array[float] = []
	var count := int(round(p_length_m / p_step_m))
	for index in range(count + 1):
		var station := p_step_m * float(index)
		s_values.append(station)
		positions.append(Vector2(0.0, station))
		speeds.append(p_speed_m_s)
	return CalibrationDriver.CalibrationPath.from_arrays(
		s_values, positions, speeds, p_version
	)


## Authored right/left sweeper: 50 m approach, a constant-radius 90-degree arc,
## and a 50 m tangent exit. Geometry matches the BENCHMARKS sweeper fixture
## (120 m centerline radius, 90 degrees, 50 m approach/exit); the speed is an
## explicit test-only 30 m/s, not a measured cornering limit.
static func make_sweeper_path(
	p_radius_m := 120.0,
	p_turn_degrees := 90.0,
	p_approach_m := 50.0,
	p_exit_m := 50.0,
	p_arc_step_m := 10.0,
	p_speed_m_s := EXAMPLE_SPEED_M_S,
	p_turn_right := true,
	p_version := EXAMPLE_SWEEPER_VERSION
) -> CalibrationDriver.CalibrationPath:
	var sign := 1.0 if p_turn_right else -1.0
	var s_values: Array[float] = []
	var positions: Array[Vector2] = []
	var speeds: Array[float] = []

	var approach_step_m := 25.0
	var approach_count := int(round(p_approach_m / approach_step_m))
	for index in range(approach_count + 1):
		var station := approach_step_m * float(index)
		s_values.append(station)
		positions.append(Vector2(0.0, station))
		speeds.append(p_speed_m_s)

	var turn_rad := deg_to_rad(p_turn_degrees)
	var arc_length_m := p_radius_m * turn_rad
	var arc_count := int(round(arc_length_m / p_arc_step_m))
	for index in range(1, arc_count + 1):
		var theta := turn_rad * float(index) / float(arc_count)
		var station := p_approach_m + p_radius_m * theta
		# Right turn: centre is +X of the tangent start, so x grows with theta.
		# Left turn mirrors x and the later heading.
		var position := Vector2(
			sign * p_radius_m * (1.0 - cos(theta)),
			p_approach_m + p_radius_m * sin(theta)
		)
		s_values.append(station)
		positions.append(position)
		speeds.append(p_speed_m_s)

	var arc_end_station := p_approach_m + arc_length_m
	var exit_step_m := 25.0
	var exit_count := int(round(p_exit_m / exit_step_m))
	for index in range(1, exit_count + 1):
		var station := arc_end_station + exit_step_m * float(index)
		var position := Vector2(
			sign * (p_radius_m + exit_step_m * float(index)),
			p_approach_m + p_radius_m
		)
		s_values.append(station)
		positions.append(position)
		speeds.append(p_speed_m_s)
	return CalibrationDriver.CalibrationPath.from_arrays(
		s_values, positions, speeds, p_version
	)


static func make_state(
	p_position: Vector2,
	p_velocity: Vector2,
	p_heading_rad: float,
	p_grounded := true
) -> CarState:
	var state := CarStateScript.new()
	state.position_m = p_position
	state.velocity_m_s = p_velocity
	state.heading_rad = p_heading_rad
	state.grounded = p_grounded
	return state


static func forward_velocity(p_speed_m_s: float, p_heading_rad: float) -> Vector2:
	return Vector2(sin(p_heading_rad), cos(p_heading_rad)) * p_speed_m_s


func default_tuning() -> CalibrationDriver.Tuning:
	return CalibrationDriver.Tuning.make()


# --- Cases -------------------------------------------------------------------


func _case_profile_validation() -> Dictionary:
	var c := Case.new()
	c.name = "profile_validation_and_interpolation"

	var path := make_straight_path(500.0, 25.0, EXAMPLE_SPEED_M_S)
	c.check(path != null and path.is_valid(), "authored straight profile validates")
	if path == null or not path.is_valid():
		return c.result()

	c.equal(path.version, TEST_PATH_VERSION, "path version preserved")
	c.close(path.length_m(), 500.0, FLOAT_TOLERANCE, "straight length is 500 m")
	c.close(path.first_s_m(), 0.0, FLOAT_TOLERANCE, "first station is 0 m")
	c.close(path.last_s_m(), 500.0, FLOAT_TOLERANCE, "last station is 500 m")

	var mid := path.interpolate_at(250.0)
	c.vector_close(
		mid.position_m, Vector2(0.0, 250.0), FLOAT_TOLERANCE, "midpoint position"
	)
	c.close(mid.target_speed_m_s, 30.0, FLOAT_TOLERANCE, "midpoint speed")
	# Station 250 m is an authored sample, so the selected segment starts
	# there and its local blend is zero. A fractional station exercises the
	# interpolation half-way between authored samples.
	c.close(mid.blend_t, 0.0, FLOAT_TOLERANCE, "authored sample blend")
	var between := path.interpolate_at(262.5)
	c.vector_close(
		between.position_m,
		Vector2(0.0, 262.5),
		FLOAT_TOLERANCE,
		"fractional station position"
	)
	c.close(between.blend_t, 0.5, FLOAT_TOLERANCE, "fractional station blend")

	c.equal(path.segment_index_for_progress_m(0.0), 0, "start selects first segment")
	c.equal(path.segment_index_for_progress_m(250.0), 10, "mid station segment")
	c.equal(
		path.segment_index_for_progress_m(500.0),
		19,
		"final station selects last open segment"
	)
	c.close(path.clamp_progress_m(-10.0), 0.0, FLOAT_TOLERANCE, "low end clamp")
	c.close(path.clamp_progress_m(600.0), 500.0, FLOAT_TOLERANCE, "high end clamp")

	_expect_invalid(c, "empty profile", [], [], [])
	_expect_invalid(c, "single-sample profile", [0.0], [Vector2.ZERO], [30.0])
	_expect_invalid(
		c,
		"duplicate station profile",
		[0.0, 10.0, 10.0, 20.0],
		[Vector2.ZERO, Vector2(0, 10), Vector2(0, 10), Vector2(0, 20)],
		[30.0, 30.0, 30.0, 30.0]
	)
	_expect_invalid(
		c,
		"decreasing station profile",
		[0.0, 20.0, 10.0],
		[Vector2.ZERO, Vector2(0, 20), Vector2(0, 10)],
		[30.0, 30.0, 30.0]
	)
	_expect_invalid(
		c,
		"NaN station profile",
		[0.0, NAN],
		[Vector2.ZERO, Vector2(0, 1)],
		[30.0, 30.0]
	)
	_expect_invalid(
		c,
		"Inf station profile",
		[0.0, INF],
		[Vector2.ZERO, Vector2(0, 1)],
		[30.0, 30.0]
	)
	_expect_invalid(
		c,
		"negative station profile",
		[-1.0, 0.0],
		[Vector2(0, -1), Vector2.ZERO],
		[30.0, 30.0]
	)
	_expect_invalid(
		c,
		"NaN position profile",
		[0.0, 1.0],
		[Vector2.ZERO, Vector2(NAN, 1.0)],
		[30.0, 30.0]
	)
	_expect_invalid(
		c,
		"Inf position profile",
		[0.0, 1.0],
		[Vector2.ZERO, Vector2(INF, 1.0)],
		[30.0, 30.0]
	)
	_expect_invalid(
		c,
		"NaN target-speed profile",
		[0.0, 1.0],
		[Vector2.ZERO, Vector2(0, 1)],
		[30.0, NAN]
	)
	_expect_invalid(
		c,
		"negative target-speed profile",
		[0.0, 1.0],
		[Vector2.ZERO, Vector2(0, 1)],
		[30.0, -1.0]
	)
	_expect_invalid(
		c,
		"Inf target-speed profile",
		[0.0, 1.0],
		[Vector2.ZERO, Vector2(0, 1)],
		[30.0, INF]
	)
	_expect_invalid(
		c,
		"mismatched-array profile",
		[0.0, 1.0],
		[Vector2.ZERO],
		[30.0, 30.0]
	)
	_expect_invalid(
		c,
		"malformed station type profile",
		[0.0, "10"],
		[Vector2.ZERO, Vector2(0, 10)],
		[30.0, 30.0]
	)
	c.measurements["validated_profile_count"] = 1
	c.measurements["invalid_profile_cases"] = 14
	return c.result()


func _case_steering_sign_and_matched_straight() -> Dictionary:
	var c := Case.new()
	c.name = "steering_sign_and_matched_straight"
	var path := make_straight_path(500.0, 25.0, EXAMPLE_SPEED_M_S)
	var tuning := default_tuning()
	var lookahead := tuning.lookahead_base_m + tuning.lookahead_speed_gain_s * 30.0

	# Matched straight: on the line, aligned nose, speed equal to the profile.
	var matched := CalibrationDriver.decide(
		make_state(Vector2.ZERO, forward_velocity(30.0, 0.0), 0.0),
		path,
		0.0,
		tuning
	)
	c.check(matched.accepted, "matched straight accepted")
	if matched.command != null:
		c.close(matched.command.steer, 0.0, FLOAT_TOLERANCE, "matched straight steer is zero")
		c.close(matched.command.throttle, 0.0, FLOAT_TOLERANCE, "matched straight coast throttle")
		c.close(matched.command.brake, 0.0, FLOAT_TOLERANCE, "matched straight coast brake")
		c.check(matched.command.is_normalized(), "matched straight command normalized")

	# Left of the line, target ahead-right: positive steer turns the nose right.
	var right_offset := CalibrationDriver.decide(
		make_state(Vector2(-5.0, 0.0), forward_velocity(30.0, 0.0), 0.0),
		path,
		0.0,
		tuning
	)
	var expected_right := clampf(
		tuning.steer_gain_per_rad * atan2(5.0, lookahead),
		-tuning.max_steer,
		tuning.max_steer
	)
	c.check(right_offset.accepted, "right-offset case accepted")
	if right_offset.command != null:
		c.check(right_offset.command.steer > 0.0, "target right steers right (positive)")
		c.close(
			right_offset.command.steer,
			expected_right,
			FLOAT_TOLERANCE,
			"right-offset steer follows declared bearing law"
		)

	# Right of the line, target ahead-left: negative steer turns the nose left.
	var left_offset := CalibrationDriver.decide(
		make_state(Vector2(5.0, 0.0), forward_velocity(30.0, 0.0), 0.0),
		path,
		0.0,
		tuning
	)
	var expected_left := clampf(
		tuning.steer_gain_per_rad * atan2(-5.0, lookahead),
		-tuning.max_steer,
		tuning.max_steer
	)
	c.check(left_offset.accepted, "left-offset case accepted")
	if left_offset.command != null:
		c.check(left_offset.command.steer < 0.0, "target left steers left (negative)")
		c.close(
			left_offset.command.steer,
			expected_left,
			FLOAT_TOLERANCE,
			"left-offset steer follows declared bearing law"
		)

	c.measurements["lookahead_m"] = lookahead
	c.measurements["right_offset_steer"] = (
		right_offset.command.steer if right_offset.command != null else null
	)
	c.measurements["left_offset_steer"] = (
		left_offset.command.steer if left_offset.command != null else null
	)
	return c.result()


func _case_speed_control_and_exclusivity() -> Dictionary:
	var c := Case.new()
	c.name = "speed_control_and_exclusivity"
	var path := make_straight_path(500.0, 25.0, EXAMPLE_SPEED_M_S)
	var tuning := CalibrationDriver.Tuning.make(
		0.0, 0.0, 10.0, 1.5, 1.0, 0.4, 0.8, 0.25
	)
	c.check(tuning.is_valid(), "explicit speed-control tuning validates")

	var samples := [
		{"label": "under", "speed": 10.0},
		{"label": "over", "speed": 40.0},
		{"label": "inside band", "speed": 30.1},
		# 29.625 and 30.375 are exactly representable in the Vector2-based
		# CarState, so the partial-command expectations stay bit-precise.
		{"label": "below band", "speed": 29.625},
		{"label": "above band", "speed": 30.375},
	]
	for sample in samples:
		var decision := CalibrationDriver.decide(
			make_state(
				Vector2.ZERO, forward_velocity(float(sample["speed"]), 0.0), 0.0
			),
			path,
			250.0,
			tuning
		)
		c.check(decision.accepted, sample["label"] + ": accepted")
		if decision.command == null:
			continue
		var command := decision.command
		c.check(command.is_normalized(), sample["label"] + ": normalized")
		c.check(
			command.handbrake == 0.0,
			sample["label"] + ": no handbrake"
		)
		c.check(
			not command.reset_requested and not command.reset_held,
			sample["label"] + ": no reset request"
		)
		c.check(
			not (command.throttle > 0.0 and command.brake > 0.0),
			sample["label"] + ": throttle/brake exclusive"
		)
		match sample["label"]:
			"under":
				c.close(command.throttle, 1.0, FLOAT_TOLERANCE, "under target full throttle")
				c.close(command.brake, 0.0, FLOAT_TOLERANCE, "under target no brake")
			"over":
				c.close(command.brake, 1.0, FLOAT_TOLERANCE, "over target full brake")
				c.close(command.throttle, 0.0, FLOAT_TOLERANCE, "over target no throttle")
			"inside band":
				c.close(command.throttle, 0.0, FLOAT_TOLERANCE, "band coast throttle")
				c.close(command.brake, 0.0, FLOAT_TOLERANCE, "band coast brake")
			"below band":
				c.close(command.throttle, 0.15, FLOAT_TOLERANCE, "small under target throttle")
				c.close(command.brake, 0.0, FLOAT_TOLERANCE, "small under target no brake")
			"above band":
				c.close(command.brake, 0.3, FLOAT_TOLERANCE, "small over target brake")
				c.close(command.throttle, 0.0, FLOAT_TOLERANCE, "small over target no throttle")

	c.measurements["deadband_m_s"] = tuning.speed_deadband_m_s
	return c.result()


func _case_lookahead_interpolation_and_end_clamping() -> Dictionary:
	var c := Case.new()
	c.name = "lookahead_interpolation_and_end_clamping"
	var path := CalibrationDriver.CalibrationPath.from_arrays(
		[0.0, 10.0],
		[Vector2(0.0, 0.0), Vector2(0.0, 10.0)],
		[10.0, 20.0],
		TEST_PATH_VERSION
	)
	c.check(path.is_valid(), "two-sample varying profile validates")
	if not path.is_valid():
		return c.result()

	var zero_look := CalibrationDriver.Tuning.make(0.0, 0.0, 50.0)
	var midpoint := CalibrationDriver.decide(
		make_state(Vector2.ZERO, forward_velocity(10.0, 0.0), 0.0),
		path,
		5.0,
		zero_look
	)
	c.check(midpoint.accepted, "midpoint case accepted")
	c.close(midpoint.telemetry.lookahead_m, 0.0, FLOAT_TOLERANCE, "zero lookahead")
	c.close(midpoint.telemetry.target_s_m, 5.0, FLOAT_TOLERANCE, "midpoint station")
	c.vector_close(
		midpoint.telemetry.target_position_m,
		Vector2(0.0, 5.0),
		FLOAT_TOLERANCE,
		"interpolated target position"
	)
	c.close(midpoint.telemetry.target_speed_m_s, 15.0, FLOAT_TOLERANCE, "interpolated speed")
	c.close(midpoint.telemetry.local_target_speed_m_s, 15.0, FLOAT_TOLERANCE, "local speed")

	var quarter_look := CalibrationDriver.Tuning.make(2.5, 0.0, 50.0)
	var quarter := CalibrationDriver.decide(
		make_state(Vector2.ZERO, forward_velocity(10.0, 0.0), 0.0),
		path,
		5.0,
		quarter_look
	)
	c.close(quarter.telemetry.lookahead_m, 2.5, FLOAT_TOLERANCE, "declared lookahead")
	c.close(quarter.telemetry.target_s_m, 7.5, FLOAT_TOLERANCE, "lookahead station")
	c.vector_close(
		quarter.telemetry.target_position_m,
		Vector2(0.0, 7.5),
		FLOAT_TOLERANCE,
		"lookahead target position"
	)
	c.close(quarter.telemetry.target_speed_m_s, 17.5, FLOAT_TOLERANCE, "lookahead speed")
	c.close(
		quarter.telemetry.local_target_speed_m_s,
		15.0,
		FLOAT_TOLERANCE,
		"local speed stays at current station"
	)

	# Speed-scaled lookahead is capped; the target clamps to the final sample.
	var capped := CalibrationDriver.Tuning.make(5.0, 10.0, 40.0)
	var capped_decision := CalibrationDriver.decide(
		make_state(Vector2.ZERO, forward_velocity(30.0, 0.0), 0.0),
		path,
		5.0,
		capped
	)
	c.close(capped_decision.telemetry.lookahead_m, 40.0, FLOAT_TOLERANCE, "lookahead cap")
	c.close(
		capped_decision.telemetry.target_s_m,
		10.0,
		FLOAT_TOLERANCE,
		"target station clamps at final sample"
	)
	c.vector_close(
		capped_decision.telemetry.target_position_m,
		Vector2(0.0, 10.0),
		FLOAT_TOLERANCE,
		"clamped target position"
	)

	# Explicit low/high clamping with the clamp flags visible in telemetry.
	var clamped_low := CalibrationDriver.decide(
		make_state(Vector2.ZERO, forward_velocity(10.0, 0.0), 0.0),
		path,
		-5.0,
		zero_look
	)
	c.equal(
		clamped_low.telemetry.progress_used_m,
		0.0,
		"low progress clamps to first station"
	)
	c.check(clamped_low.telemetry.progress_clamped_low, "low clamp flag set")
	c.check(
		not clamped_low.telemetry.progress_clamped_high,
		"low clamp leaves high flag clear"
	)

	var clamped_high := CalibrationDriver.decide(
		make_state(Vector2.ZERO, forward_velocity(10.0, 0.0), 0.0),
		path,
		20.0,
		zero_look
	)
	c.equal(
		clamped_high.telemetry.progress_used_m,
		10.0,
		"high progress clamps to last station"
	)
	c.check(clamped_high.telemetry.progress_clamped_high, "high clamp flag set")
	c.check(
		not clamped_high.telemetry.progress_clamped_low,
		"high clamp leaves low flag clear"
	)

	var exact_end := CalibrationDriver.decide(
		make_state(Vector2(0.0, 10.0), forward_velocity(10.0, 0.0), 0.0),
		path,
		10.0,
		zero_look
	)
	c.equal(
		exact_end.telemetry.progress_used_m,
		10.0,
		"progress exactly at last station accepted"
	)
	c.check(
		not exact_end.telemetry.progress_clamped_high,
		"progress exactly at last station is not clamped high"
	)
	c.equal(
		exact_end.telemetry.segment_index,
		0,
		"final station uses the last open segment"
	)
	return c.result()


func _case_invalid_inputs_return_refusals() -> Dictionary:
	var c := Case.new()
	c.name = "invalid_inputs_return_refusals"
	var path := make_straight_path(500.0, 25.0, EXAMPLE_SPEED_M_S)
	var tuning := default_tuning()
	var good_state := make_state(
		Vector2.ZERO, forward_velocity(30.0, 0.0), 0.0
	)

	var baseline := CalibrationDriver.decide(good_state, path, 0.0, tuning)
	c.check(baseline.accepted, "valid baseline accepted")

	# State refusals.
	var null_state := CalibrationDriver.decide(null, path, 0.0, tuning)
	_expect_refusal(c, null_state, "null_or_wrong_state", "null state")
	var wrong_state := CalibrationDriver.decide(RefCounted.new(), path, 0.0, tuning)
	_expect_refusal(c, wrong_state, "null_or_wrong_state", "wrong state type")
	var nan_position := CalibrationDriver.decide(
		make_state(Vector2(NAN, 0.0), Vector2.ZERO, 0.0), path, 0.0, tuning
	)
	_expect_refusal(c, nan_position, "nonfinite_state", "NaN position")
	var inf_velocity := CalibrationDriver.decide(
		make_state(Vector2.ZERO, Vector2(INF, 0.0), 0.0), path, 0.0, tuning
	)
	_expect_refusal(c, inf_velocity, "nonfinite_state", "Inf velocity")
	var nan_heading := CalibrationDriver.decide(
		make_state(Vector2.ZERO, Vector2.ZERO, NAN), path, 0.0, tuning
	)
	_expect_refusal(c, nan_heading, "nonfinite_state", "NaN heading")
	var airborne := CalibrationDriver.decide(
		make_state(Vector2.ZERO, Vector2.ZERO, 0.0, false), path, 0.0, tuning
	)
	_expect_refusal(
		c, airborne, "airborne_state_not_supported", "ungrounded committed state"
	)

	# Path refusals.
	var null_path := CalibrationDriver.decide(good_state, null, 0.0, tuning)
	_expect_refusal(c, null_path, "null_or_wrong_path", "null path")
	var wrong_path := CalibrationDriver.decide(
		good_state, RefCounted.new(), 0.0, tuning
	)
	_expect_refusal(c, wrong_path, "null_or_wrong_path", "wrong path type")
	var duplicate_path := CalibrationDriver.CalibrationPath.from_arrays(
		[0.0, 1.0, 1.0],
		[Vector2.ZERO, Vector2(0, 1), Vector2(0, 1)],
		[30.0, 30.0, 30.0],
		TEST_PATH_VERSION
	)
	var duplicate := CalibrationDriver.decide(good_state, duplicate_path, 0.0, tuning)
	_expect_refusal(c, duplicate, "invalid_path", "duplicate station path")
	var malformed_path := CalibrationDriver.CalibrationPath.from_arrays(
		[0.0, NAN], [Vector2.ZERO, Vector2(0, 1)], [30.0, 30.0], TEST_PATH_VERSION
	)
	var malformed := CalibrationDriver.decide(good_state, malformed_path, 0.0, tuning)
	_expect_refusal(c, malformed, "invalid_path", "malformed station path")

	# Tuning refusals.
	var null_tuning := CalibrationDriver.decide(good_state, path, 0.0, null)
	_expect_refusal(c, null_tuning, "null_or_wrong_tuning", "null tuning")
	var wrong_tuning := CalibrationDriver.decide(
		good_state, path, 0.0, RefCounted.new()
	)
	_expect_refusal(c, wrong_tuning, "null_or_wrong_tuning", "wrong tuning type")
	var bad_tunings := [
		CalibrationDriver.Tuning.make(-1.0),
		CalibrationDriver.Tuning.make(3.0, 0.6, 2.0),
		CalibrationDriver.Tuning.make(3.0, 0.6, 25.0, -1.0),
		CalibrationDriver.Tuning.make(3.0, 0.6, 25.0, 1.5, 0.0),
		CalibrationDriver.Tuning.make(3.0, 0.6, 25.0, 1.5, 1.0, -1.0),
		CalibrationDriver.Tuning.make(3.0, 0.6, 25.0, 1.5, 1.0, 0.4, -1.0),
		CalibrationDriver.Tuning.make(3.0, 0.6, 25.0, 1.5, 1.0, 0.4, 0.8, -0.1),
	]
	for bad in bad_tunings:
		var decision := CalibrationDriver.decide(good_state, path, 0.0, bad)
		_expect_refusal(c, decision, "invalid_tuning", "out-of-bounds tuning")

	# Progress refusals.
	var nan_progress := CalibrationDriver.decide(good_state, path, NAN, tuning)
	_expect_refusal(c, nan_progress, "nonfinite_progress", "NaN progress")
	var inf_progress := CalibrationDriver.decide(good_state, path, INF, tuning)
	_expect_refusal(c, inf_progress, "nonfinite_progress", "Inf progress")
	var text_progress := CalibrationDriver.decide(good_state, path, "0", tuning)
	_expect_refusal(c, text_progress, "nonfinite_progress", "non-numeric progress")

	c.measurements["refusal_cases"] = 22
	return c.result()


func _case_determinism_nonmutation_and_output_contract() -> Dictionary:
	var c := Case.new()
	c.name = "determinism_nonmutation_and_output_contract"
	var path := make_straight_path(500.0, 25.0, EXAMPLE_SPEED_M_S)
	var tuning := CalibrationDriver.Tuning.make(
		4.0, 0.5, 30.0, 1.25, 0.9, 0.35, 0.7, 0.2
	)
	var state := make_state(Vector2(2.0, -3.0), forward_velocity(27.0, 0.4), 0.4)
	var progress := 123.4

	var state_before := state.copy()
	var sample_snapshot := []
	for sample in path.samples:
		sample_snapshot.append([sample.s_m, sample.position_m, sample.target_speed_m_s])
	var tuning_before := {
		"lookahead_base_m": tuning.lookahead_base_m,
		"lookahead_speed_gain_s": tuning.lookahead_speed_gain_s,
		"lookahead_max_m": tuning.lookahead_max_m,
		"steer_gain_per_rad": tuning.steer_gain_per_rad,
		"max_steer": tuning.max_steer,
		"throttle_gain_per_m_s": tuning.throttle_gain_per_m_s,
		"brake_gain_per_m_s": tuning.brake_gain_per_m_s,
		"speed_deadband_m_s": tuning.speed_deadband_m_s,
	}

	var first := CalibrationDriver.decide(state, path, progress, tuning)
	var second := CalibrationDriver.decide(state, path, progress, tuning)
	c.check(first.accepted and second.accepted, "repeated decisions accepted")
	if first.command == null or second.command == null:
		c.check(false, "determinism commands present")
		return c.result()
	c.check(first.command != second.command, "each decision returns a distinct command")

	_commands_equal(c, first.command, second.command, "repeat call")
	_telemetry_equal(c, first.telemetry, second.telemetry, "repeat call")

	# Input nonmutation.
	_states_equal(c, state, state_before, "committed state")
	var tuning_now := {
		"lookahead_base_m": tuning.lookahead_base_m,
		"lookahead_speed_gain_s": tuning.lookahead_speed_gain_s,
		"lookahead_max_m": tuning.lookahead_max_m,
		"steer_gain_per_rad": tuning.steer_gain_per_rad,
		"max_steer": tuning.max_steer,
		"throttle_gain_per_m_s": tuning.throttle_gain_per_m_s,
		"brake_gain_per_m_s": tuning.brake_gain_per_m_s,
		"speed_deadband_m_s": tuning.speed_deadband_m_s,
	}
	c.equal(tuning_now, tuning_before, "tuning fields unchanged")
	for index in path.samples.size():
		var sample = path.samples[index]
		var snapshot = sample_snapshot[index]
		c.equal(sample.s_m, snapshot[0], "sample %d station unchanged" % index)
		c.equal(sample.position_m, snapshot[1], "sample %d position unchanged" % index)
		c.equal(
			sample.target_speed_m_s,
			snapshot[2],
			"sample %d target speed unchanged" % index
		)

	# Mutating one returned command cannot affect a later decision.
	first.command.steer = 0.99
	first.command.throttle = 0.5
	var third := CalibrationDriver.decide(state, path, progress, tuning)
	_commands_equal(c, third.command, second.command, "after caller mutation")

	# Output contract across a bounded input sweep.
	var sweep_states := [
		make_state(Vector2.ZERO, forward_velocity(0.0, 0.0), 0.0),
		make_state(Vector2(1.0, 10.0), forward_velocity(5.0, 0.2), 0.2),
		make_state(Vector2(-2.0, 250.0), forward_velocity(30.0, 1.57079632679), 1.57079632679),
		make_state(Vector2(0.0, 499.0), forward_velocity(60.0, 0.0), 0.0),
	]
	for index in sweep_states.size():
		var decision := CalibrationDriver.decide(
			sweep_states[index], path, 250.0, tuning
		)
		c.check(decision.accepted, "sweep %d accepted" % index)
		if decision.command == null:
			continue
		var command := decision.command
		c.check(command.is_normalized(), "sweep %d normalized" % index)
		c.check(
			not (command.throttle > 0.0 and command.brake > 0.0),
			"sweep %d throttle/brake exclusive" % index
		)
		c.check(command.handbrake == 0.0, "sweep %d no handbrake" % index)
		c.check(
			not command.reset_requested and not command.reset_held,
			"sweep %d no reset request" % index
		)
		c.check(
			decision.telemetry.driver_id == CalibrationDriver.DRIVER_ID
			and decision.telemetry.driver_version == CalibrationDriver.DRIVER_VERSION,
			"sweep %d versioned telemetry" % index
		)

	c.measurements["repeat_calls_compared"] = 2
	c.measurements["sweep_cases"] = sweep_states.size()
	return c.result()


func _case_example_profiles_authored_smoke() -> Dictionary:
	var c := Case.new()
	c.name = "example_profiles_authored_smoke"

	var straight := make_straight_path(
		500.0, 25.0, EXAMPLE_SPEED_M_S, EXAMPLE_STRAIGHT_VERSION
	)
	c.check(straight.is_valid(), "authored 500 m straight example validates")
	c.check(
		straight.version.find("test_only") != -1,
		"straight example version is marked test-only"
	)
	c.close(straight.length_m(), 500.0, FLOAT_TOLERANCE, "straight example length")

	var tuning := default_tuning()
	var start := CalibrationDriver.decide(
		make_state(Vector2.ZERO, forward_velocity(EXAMPLE_SPEED_M_S, 0.0), 0.0),
		straight,
		0.0,
		tuning
	)
	c.check(start.accepted, "straight example start accepted")
	c.close(
		start.telemetry.target_speed_m_s,
		EXAMPLE_SPEED_M_S,
		FLOAT_TOLERANCE,
		"straight example target speed is the explicit test-only speed"
	)
	var mid_straight := CalibrationDriver.decide(
		make_state(
			Vector2(0.0, 250.0),
			forward_velocity(EXAMPLE_SPEED_M_S, 0.0),
			0.0
		),
		straight,
		250.0,
		tuning
	)
	c.check(mid_straight.accepted, "straight example midpoint accepted")
	if mid_straight.command != null:
		c.close(
			mid_straight.command.steer, 0.0, FLOAT_TOLERANCE, "straight example tracks centre"
		)
		c.close(
			mid_straight.command.throttle,
			0.0,
			FLOAT_TOLERANCE,
			"straight example at test speed coasts"
		)

	var sweeper := make_sweeper_path()
	c.check(sweeper.is_valid(), "authored 90-degree 120 m sweeper example validates")
	c.check(
		sweeper.version.find("test_only") != -1,
		"sweeper example version is marked test-only"
	)
	c.close(
		sweeper.length_m(),
		100.0 + 120.0 * PI * 0.5,
		1e-6,
		"sweeper example length is approach + quarter arc + exit"
	)
	var sweeper_start := CalibrationDriver.decide(
		make_state(Vector2.ZERO, forward_velocity(EXAMPLE_SPEED_M_S, 0.0), 0.0),
		sweeper,
		0.0,
		tuning
	)
	c.check(sweeper_start.accepted, "sweeper example start accepted")
	if sweeper_start.command != null:
		c.close(
			sweeper_start.command.steer,
			0.0,
			FLOAT_TOLERANCE,
			"sweeper example enters on the tangent"
		)

	# Mid-corner poses placed directly on the authored arc, with progress equal
	# to the arc station. The right-hand example must steer right; its mirror
	# must steer left. This proves the sign on real curved geometry.
	var theta := PI * 0.25
	var station := 50.0 + 120.0 * theta
	# Place the car exactly on the authored polyline, not on the ideal circle.
	var position := sweeper.interpolate_at(station).position_m
	var right_mid := CalibrationDriver.decide(
		make_state(position, forward_velocity(EXAMPLE_SPEED_M_S, theta), theta),
		sweeper,
		station,
		tuning
	)
	c.check(right_mid.accepted, "right sweeper mid-corner accepted")
	if right_mid.command != null:
		c.check(
			right_mid.command.steer > 0.0,
			"right-hand sweeper steers right through the corner"
		)
		c.check(right_mid.command.is_normalized(), "right sweeper command normalized")

	var left_sweeper := make_sweeper_path(120.0, 90.0, 50.0, 50.0, 10.0, EXAMPLE_SPEED_M_S, false)
	c.check(left_sweeper.is_valid(), "mirrored left sweeper validates")
	var left_position := Vector2(-position.x, position.y)
	var left_mid := CalibrationDriver.decide(
		make_state(left_position, forward_velocity(EXAMPLE_SPEED_M_S, -theta), -theta),
		left_sweeper,
		station,
		tuning
	)
	c.check(left_mid.accepted, "left sweeper mid-corner accepted")
	if left_mid.command != null:
		c.check(
			left_mid.command.steer < 0.0,
			"left-hand sweeper steers left through the corner"
		)
		c.check(left_mid.command.is_normalized(), "left sweeper command normalized")

	c.measurements["profile_status"] = EXAMPLE_STATUS
	c.measurements["example_speed_source"] = (
		"BENCHMARKS handling fixture 30 m/s entries; test-only, not measured or tuned"
	)
	c.measurements["straight_length_m"] = straight.length_m()
	c.measurements["sweeper_length_m"] = sweeper.length_m()
	c.measurements["right_mid_corner_steer"] = (
		right_mid.command.steer if right_mid.command != null else null
	)
	c.measurements["left_mid_corner_steer"] = (
		left_mid.command.steer if left_mid.command != null else null
	)
	return c.result()


# --- Helpers -----------------------------------------------------------------


func _expect_invalid(
	c: Case,
	p_label: String,
	p_s: Array,
	p_positions: Array,
	p_speeds: Array
) -> void:
	var built := CalibrationDriver.CalibrationPath.from_arrays(
		p_s, p_positions, p_speeds, TEST_PATH_VERSION
	)
	c.check(
		built == null or not built.is_valid(),
		"invalid profile refused: " + p_label
	)
	c.check(
		built == null or not built.validation_error().is_empty(),
		"invalid profile has a specific diagnostic: " + p_label
	)


func _expect_refusal(c: Case, p_decision: CalibrationDriver.Decision, p_label: String, p_case: String) -> void:
	c.check(not p_decision.accepted, p_case + ": refused")
	c.check(p_decision.command == null, p_case + ": no command on refusal")
	c.equal(p_decision.refusal_label, p_label, p_case + ": refusal label")
	c.check(
		p_decision.refusal_code != CalibrationDriver.Refusal.NONE,
		p_case + ": refusal code set"
	)
	c.check(
		not p_decision.refusal_detail.is_empty(),
		p_case + ": refusal detail present"
	)
	c.check(
		not p_decision.telemetry.accepted,
		p_case + ": telemetry reports refusal"
	)


func _commands_equal(
	c: Case, p_a: DriverCommand, p_b: DriverCommand, p_label: String
) -> void:
	c.equal(p_a.steer, p_b.steer, p_label + ": steer identical")
	c.equal(p_a.throttle, p_b.throttle, p_label + ": throttle identical")
	c.equal(p_a.brake, p_b.brake, p_label + ": brake identical")
	c.equal(p_a.handbrake, p_b.handbrake, p_label + ": handbrake identical")
	c.equal(
		p_a.reset_requested, p_b.reset_requested, p_label + ": reset edge identical"
	)
	c.equal(p_a.reset_held, p_b.reset_held, p_label + ": reset held identical")


func _telemetry_equal(
	c: Case, p_a: CalibrationDriver.Telemetry, p_b: CalibrationDriver.Telemetry, p_label: String
) -> void:
	c.equal(p_a.path_version, p_b.path_version, p_label + ": path version")
	c.equal(
		p_a.progress_requested_m, p_b.progress_requested_m, p_label + ": requested progress"
	)
	c.equal(p_a.progress_used_m, p_b.progress_used_m, p_label + ": used progress")
	c.equal(
		p_a.progress_clamped_low, p_b.progress_clamped_low, p_label + ": low clamp flag"
	)
	c.equal(
		p_a.progress_clamped_high, p_b.progress_clamped_high, p_label + ": high clamp flag"
	)
	c.equal(p_a.segment_index, p_b.segment_index, p_label + ": segment index")
	c.equal(p_a.lookahead_m, p_b.lookahead_m, p_label + ": lookahead")
	c.equal(p_a.target_s_m, p_b.target_s_m, p_label + ": target station")
	c.equal(p_a.target_position_m, p_b.target_position_m, p_label + ": target position")
	c.equal(p_a.target_speed_m_s, p_b.target_speed_m_s, p_label + ": target speed")
	c.equal(
		p_a.local_target_speed_m_s,
		p_b.local_target_speed_m_s,
		p_label + ": local target speed"
	)
	c.equal(p_a.forward_speed_m_s, p_b.forward_speed_m_s, p_label + ": forward speed")
	c.equal(p_a.speed_error_m_s, p_b.speed_error_m_s, p_label + ": speed error")
	c.equal(p_a.bearing_rad, p_b.bearing_rad, p_label + ": bearing")
	c.equal(p_a.steer_command, p_b.steer_command, p_label + ": steer command")
	c.equal(p_a.throttle_command, p_b.throttle_command, p_label + ": throttle command")
	c.equal(p_a.brake_command, p_b.brake_command, p_label + ": brake command")


func _states_equal(c: Case, p_a: CarState, p_b: CarState, p_label: String) -> void:
	c.equal(p_a.position_m, p_b.position_m, p_label + ": position unchanged")
	c.equal(p_a.velocity_m_s, p_b.velocity_m_s, p_label + ": velocity unchanged")
	c.equal(p_a.heading_rad, p_b.heading_rad, p_label + ": heading unchanged")
	c.equal(p_a.grounded, p_b.grounded, p_label + ": grounded unchanged")
	c.equal(p_a.surface_id, p_b.surface_id, p_label + ": surface unchanged")
	c.equal(p_a.reverse_engaged, p_b.reverse_engaged, p_label + ": reverse unchanged")
	c.equal(p_a.reverse_hold_s, p_b.reverse_hold_s, p_label + ": reverse hold unchanged")
	c.equal(p_a.gear_index, p_b.gear_index, p_label + ": gear unchanged")
	c.equal(p_a.valid_progress_m, p_b.valid_progress_m, p_label + ": progress unchanged")
	c.equal(
		p_a.drift_active, p_b.drift_active, p_label + ": drift active unchanged"
	)
	c.equal(p_a.drafting_active, p_b.drafting_active, p_label + ": drafting unchanged")
