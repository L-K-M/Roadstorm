extends Node
## Bounded physical bridge from CalibrationDriver to the real DriveLab.
##
## The laboratory instantiates scenes/laboratory/drive_lab.tscn unchanged,
## disables its automatic tick path, settles the physics scene, samples the
## committed CarState plus DriveLab's validated straight-road station once per
## logical 60 Hz tick, asks CalibrationDriver for one command, and feeds that
## exact command to DriveLab.step_once(). It uses the laboratory's ordinary
## ArcadeMotor, AutomaticGearbox and MotorBodyAdapter path; no motion is
## integrated here. The straight speed profile is explicitly provisional and
## is not a tuned, benchmark or reference-lap value.

const ChecksScript := preload(
	"res://tools/calibration_physics_lab/calibration_physics_lab_checks.gd"
)
const AdapterScript := preload("res://src/simulation/motor_body_adapter.gd")

const DRIVE_LAB_SCENE_PATH := "res://scenes/laboratory/drive_lab.tscn"
const SETTLE_FRAMES := 10
const CLEANUP_FRAMES := 8
const BRIDGE_TICKS := 120
const STRAIGHT_LENGTH_M := 500.0
const STRAIGHT_STEP_M := 25.0
## Test-only lane offset exercising lateral correction while remaining well
## inside the committed straight's asphalt width.
const LANE_OFFSET_M := 0.25
## Provisional bridge speed only. It is deliberately not drawn from a tuned
## calibration, benchmark or reference-lap claim.
const PROVISIONAL_TARGET_SPEED_M_S := 12.0
const PATH_VERSION := "roadstorm.calibration_physics.straight_provisional.v1"
const MIN_FORWARD_PROGRESS_M := 4.0
const LATERAL_ERROR_BOUND_M := 0.6
const STATION_VALID_LOW_M := -0.001
const STATION_VALID_HIGH_MARGIN_M := 0.001
## Declared same-host repeat tolerance. The committed DriveLab trace is
## expected to be deterministic; this tolerance only covers floating-point
## roundoff in independently recorded JSON-facing numbers.
const REPEAT_TOLERANCE := 1e-9

var _holder: Node3D = null
var _case_results: Array = []
var _total_checks := 0
var _total_failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_holder = Node3D.new()
	_holder.name = "CalibrationPhysicsLabHolder"
	add_child(_holder)
	_run()


func _run() -> void:
	var bridge_case := ChecksScript.Case.new()
	bridge_case.name = "physical_straight_bridge_repeat"
	await _case_physical_bridge_repeat(bridge_case)
	_record_case(bridge_case)

	var refusal_case := ChecksScript.Case.new()
	refusal_case.name = "invalid_path_refusal_no_motor_call"
	await _case_invalid_path_refusal(refusal_case)
	_record_case(refusal_case)

	var failed_cases := 0
	for result in _case_results:
		if not bool(result["pass"]):
			failed_cases += 1
	var summary := {
		"schema": "roadstorm.calibration_physics_lab.summary.v1",
		"bridge_scope": "physical straight-line CalibrationDriver to ordinary DriveLab integration only",
		"profile_status": "provisional_not_tuned_not_benchmark_not_reference",
		"backend": str(ProjectSettings.get_setting("physics/3d/physics_engine")),
		"engine_version": Engine.get_version_info(),
		"ticks_per_run": BRIDGE_TICKS,
		"repeat_tolerance": REPEAT_TOLERANCE,
		"cases": _case_results.size(),
		"cases_passed": _case_results.size() - failed_cases,
		"checks": _total_checks,
		"checks_failed": _total_failures,
		"pass": failed_cases == 0,
		"case_results": _case_results.duplicate(true),
	}
	print("CALIBRATION_PHYSICS_SUMMARY ", JSON.stringify(summary))
	print("CHECKS_TOTAL=", _total_checks, " CHECKS_FAILED=", _total_failures)
	get_tree().quit(0 if failed_cases == 0 else 1)


func _record_case(c) -> void:
	var result: Dictionary = c.result()
	_case_results.append(result)
	_total_checks += int(result["checks"])
	_total_failures += int(result["checks_failed"])
	print("CALIBRATION_PHYSICS_CASE ", JSON.stringify(result))


# --- Cases -------------------------------------------------------------------


func _case_physical_bridge_repeat(c) -> void:
	var first: Dictionary = await _run_physical_bridge(c, "first")
	var second: Dictionary = await _run_physical_bridge(c, "second")
	c.check(bool(first.get("completed", false)), "first bridge run completed")
	c.check(bool(second.get("completed", false)), "second bridge run completed")
	if not (bool(first.get("completed", false)) and bool(second.get("completed", false))):
		return

	var first_trace: Array = first.get("trace", [])
	var second_trace: Array = second.get("trace", [])
	c.equal(first_trace.size(), BRIDGE_TICKS, "first recorded trace length")
	c.equal(second_trace.size(), BRIDGE_TICKS, "second recorded trace length")
	c.equal(first_trace.size(), second_trace.size(), "repeat trace lengths match")
	if first_trace.size() != second_trace.size():
		return

	var compared_fields: Array = [
		"station_before_m",
		"station_after_m",
		"position_x_m",
		"position_y_m",
		"velocity_x_m_s",
		"velocity_y_m_s",
		"speed_m_s",
		"forward_speed_m_s",
		"lateral_error_m",
		"heading_rad",
		"steer",
		"throttle",
		"brake",
		"lookahead_m",
		"target_s_m",
	]
	var max_diffs := {}
	for field in compared_fields:
		max_diffs[field] = 0.0
	var gear_mismatches := 0
	var status_mismatches := 0
	for index in range(first_trace.size()):
		var a: Dictionary = first_trace[index]
		var b: Dictionary = second_trace[index]
		for field in compared_fields:
			var diff := absf(float(a[field]) - float(b[field]))
			max_diffs[field] = maxf(float(max_diffs[field]), diff)
		if int(a["gear_index"]) != int(b["gear_index"]):
			gear_mismatches += 1
		if int(a["result_status"]) != int(b["result_status"]):
			status_mismatches += 1

	var worst := 0.0
	var worst_field := ""
	for field in compared_fields:
		var value := float(max_diffs[field])
		if value > worst:
			worst = value
			worst_field = String(field)
	c.check(
		worst <= REPEAT_TOLERANCE,
		"same-host repeat traces within declared tolerance (worst %s=%s tol=%s)"
			% [worst_field, str(worst), str(REPEAT_TOLERANCE)]
	)
	c.equal(gear_mismatches, 0, "repeat gear indications identical")
	c.equal(status_mismatches, 0, "repeat physical result statuses identical")
	c.measurements["repeat_compared_fields"] = compared_fields.duplicate()
	c.measurements["repeat_max_diffs"] = max_diffs.duplicate()
	c.measurements["repeat_worst_field"] = worst_field
	c.measurements["repeat_worst_diff"] = worst
	c.measurements["repeat_tolerance"] = REPEAT_TOLERANCE
	c.measurements["first_final"] = first.get("final", {})
	c.measurements["second_final"] = second.get("final", {})
	c.measurements["first_selected_samples"] = _selected_samples(first_trace)
	c.measurements["second_selected_samples"] = _selected_samples(second_trace)


func _case_invalid_path_refusal(c) -> void:
	var lab = _make_lab(c, "invalid")
	if lab == null:
		return
	await _settle()
	lab.set_auto_tick(false)
	c.check(not lab.is_auto_tick(), "invalid.auto_tick_disabled")
	if lab.state == null:
		c.check(false, "invalid.state_present")
		await _teardown_lab(lab)
		return

	var steps_before := int(lab.steps_called)
	var commits_before := int(lab.ticks_committed)
	var position_before: Vector2 = lab.state.position_m
	var velocity_before: Vector2 = lab.state.velocity_m_s
	var heading_before: float = lab.state.heading_rad
	var invalid_path := CalibrationDriver.CalibrationPath.from_arrays(
		[0.0, 10.0, 10.0],
		[Vector2.ZERO, Vector2(0.0, 10.0), Vector2(0.0, 10.0)],
		[PROVISIONAL_TARGET_SPEED_M_S, PROVISIONAL_TARGET_SPEED_M_S, PROVISIONAL_TARGET_SPEED_M_S],
		PATH_VERSION + ".invalid_duplicate_station"
	)
	c.check(invalid_path != null, "invalid.path_object_built")
	c.check(
		invalid_path == null or not invalid_path.is_valid(),
		"invalid.duplicate_station_path_rejected_by_validation"
	)
	var tuning := CalibrationDriver.Tuning.make()
	c.check(tuning != null and tuning.is_valid(), "invalid.tuning_valid")
	var decision := CalibrationDriver.decide(
		lab.state, invalid_path, lab.get_road_station_m(), tuning
	)
	c.check(not decision.accepted, "invalid.decision_refused")
	c.check(decision.command == null, "invalid.refusal_has_no_command")
	c.equal(
		int(decision.refusal_code),
		int(CalibrationDriver.Refusal.INVALID_PATH),
		"invalid.refusal_code"
	)
	c.equal(decision.refusal_label, "invalid_path", "invalid.refusal_label")
	c.check(not decision.refusal_detail.is_empty(), "invalid.refusal_detail_present")
	# The bridge contract is explicit: a refused decision is never submitted to
	# step_once. The unchanged adapter counters and committed state prove this
	# case did not call the ordinary motor path.
	c.equal(int(lab.steps_called), steps_before, "invalid.no_additional_adapter_step")
	c.equal(int(lab.ticks_committed), commits_before, "invalid.no_additional_commit")
	c.check(lab.state.position_m == position_before, "invalid.position_unchanged")
	c.check(lab.state.velocity_m_s == velocity_before, "invalid.velocity_unchanged")
	c.check(lab.state.heading_rad == heading_before, "invalid.heading_unchanged")
	c.measurements["steps_before"] = steps_before
	c.measurements["steps_after"] = int(lab.steps_called)
	c.measurements["refusal_detail"] = decision.refusal_detail
	await _teardown_lab(lab)


# --- Physical bridge ---------------------------------------------------------


func _run_physical_bridge(c, label: String) -> Dictionary:
	var out := {
		"label": label,
		"completed": false,
		"trace": [],
		"final": {},
	}
	var lab = _make_lab(c, label)
	if lab == null:
		return out
	await _settle()
	lab.set_auto_tick(false)
	c.check(not lab.is_auto_tick(), label + ".auto_tick_disabled")
	c.check(not lab.failed, label + ".laboratory_not_failed_after_settle")
	c.check(not lab.halted, label + ".laboratory_not_halted_after_settle")
	c.equal(int(lab.steps_called), 0, label + ".settle_made_no_adapter_calls")
	if lab.state == null or not lab.state.is_finite():
		c.check(false, label + ".initial_committed_state_finite")
		await _teardown_lab(lab)
		return out

	var start_position: Vector2 = lab.start_position_m
	var axis: Vector2 = lab.state.forward_vector()
	var right: Vector2 = lab.state.right_vector()
	c.check(axis.length() > 0.999999 and axis.length() < 1.000001, label + ".straight_axis_unit")
	var initial_station: float = lab.get_road_station_m()
	c.close(initial_station, 0.0, 1e-7, label + ".initial_station_zero")

	var path := _make_straight_path(start_position, axis, right)
	c.check(path != null and path.is_valid(), label + ".straight_path_valid")
	var tuning := CalibrationDriver.Tuning.make()
	c.check(tuning != null and tuning.is_valid(), label + ".driver_tuning_valid")
	if path == null or not path.is_valid() or tuning == null or not tuning.is_valid():
		await _teardown_lab(lab)
		return out

	var trace: Array = []
	var accepted_decisions := 0
	var physical_commits := 0
	var finite_states := 0
	var validated_stations := 0
	var exclusivity_violations := 0
	var normalization_violations := 0
	var step_count_mismatches := 0
	var max_abs_lateral_error := 0.0
	var max_speed := 0.0
	var max_abs_heading := 0.0
	var min_station_delta := INF
	var final_station := initial_station
	var final_state = lab.state

	for tick in range(BRIDGE_TICKS):
		if lab.failed or lab.halted:
			c.check(false, label + ".laboratory_alive_at_tick_%d" % tick)
			break
		var committed_state = lab.state
		if committed_state == null or not committed_state.is_finite():
			c.check(false, label + ".finite_committed_input_state_tick_%d" % tick)
			break
		var station: float = lab.get_road_station_m()
		var station_valid := (
			_finite(station)
			and station >= STATION_VALID_LOW_M
			and station <= STRAIGHT_LENGTH_M + STATION_VALID_HIGH_MARGIN_M
		)
		if not station_valid:
			c.check(false, label + ".validated_straight_station_tick_%d" % tick)
			break
		validated_stations += 1

		var decision: CalibrationDriver.Decision = CalibrationDriver.decide(
			committed_state, path, station, tuning
		)
		if not decision.accepted or decision.command == null:
			c.check(false, label + ".decision_accepted_tick_%d" % tick)
			break
		accepted_decisions += 1
		var command = decision.command
		if not command.is_normalized():
			normalization_violations += 1
		if command.throttle > 0.0 and command.brake > 0.0:
			exclusivity_violations += 1

		var steps_before := int(lab.steps_called)
		var commits_before := int(lab.ticks_committed)
		var result: MotorBodyAdapter.Result = lab.step_once(command)
		if result == null:
			c.check(false, label + ".physical_result_present_tick_%d" % tick)
			break
		if int(result.status) != int(AdapterScript.Status.COMMITTED):
			c.check(false, label + ".physical_commit_tick_%d" % tick)
			break
		physical_commits += 1
		if int(lab.steps_called) != steps_before + 1:
			step_count_mismatches += 1
		if int(lab.ticks_committed) != commits_before + 1:
			step_count_mismatches += 1

		var post_state = lab.state
		if post_state == null or not post_state.is_finite():
			c.check(false, label + ".finite_committed_output_state_tick_%d" % tick)
			break
		finite_states += 1
		final_state = post_state
		var post_station: float = lab.get_road_station_m()
		final_station = post_station
		var station_delta := post_station - station
		min_station_delta = minf(min_station_delta, station_delta)
		var lateral_error: float = (post_state.position_m - start_position).dot(right) - LANE_OFFSET_M
		max_abs_lateral_error = maxf(max_abs_lateral_error, absf(lateral_error))
		max_speed = maxf(max_speed, post_state.speed_m_s())
		max_abs_heading = maxf(max_abs_heading, absf(post_state.heading_rad))
		trace.append({
			"tick": tick,
			"station_before_m": station,
			"station_after_m": post_station,
			"station_delta_m": station_delta,
			"position_x_m": post_state.position_m.x,
			"position_y_m": post_state.position_m.y,
			"velocity_x_m_s": post_state.velocity_m_s.x,
			"velocity_y_m_s": post_state.velocity_m_s.y,
			"speed_m_s": post_state.speed_m_s(),
			"forward_speed_m_s": post_state.forward_speed_m_s(),
			"lateral_error_m": lateral_error,
			"heading_rad": post_state.heading_rad,
			"gear_index": int(post_state.gear_index),
			"steer": command.steer,
			"throttle": command.throttle,
			"brake": command.brake,
			"lookahead_m": decision.telemetry.lookahead_m,
			"target_s_m": decision.telemetry.target_s_m,
			"target_speed_m_s": decision.telemetry.target_speed_m_s,
			"result_status": int(result.status),
		})
		await get_tree().physics_frame

	c.equal(accepted_decisions, BRIDGE_TICKS, label + ".all_decisions_accepted")
	c.equal(physical_commits, BRIDGE_TICKS, label + ".all_ticks_physically_committed")
	c.equal(finite_states, BRIDGE_TICKS, label + ".all_committed_states_finite")
	c.equal(validated_stations, BRIDGE_TICKS, label + ".all_stations_validated")
	c.equal(exclusivity_violations, 0, label + ".throttle_brake_mutually_exclusive")
	c.equal(normalization_violations, 0, label + ".commands_normalized")
	c.equal(step_count_mismatches, 0, label + ".exactly_one_adapter_step_and_commit_per_tick")
	c.check(
		final_station - initial_station >= MIN_FORWARD_PROGRESS_M,
		label + ".forward_progress_at_least_" + str(MIN_FORWARD_PROGRESS_M) + "_m"
	)
	c.check(
		max_abs_lateral_error <= LATERAL_ERROR_BOUND_M,
		label + ".lateral_error_bounded_" + str(LATERAL_ERROR_BOUND_M) + "_m"
	)
	c.check(not lab.failed, label + ".laboratory_not_failed_after_run")
	c.check(not lab.halted, label + ".laboratory_not_halted_after_run")
	c.equal(int(lab.steps_called), BRIDGE_TICKS, label + ".adapter_steps_exact")
	c.equal(int(lab.ticks_committed), BRIDGE_TICKS, label + ".committed_ticks_exact")

	var completed: bool = (
		accepted_decisions == BRIDGE_TICKS
		and physical_commits == BRIDGE_TICKS
		and finite_states == BRIDGE_TICKS
		and validated_stations == BRIDGE_TICKS
		and exclusivity_violations == 0
		and normalization_violations == 0
		and step_count_mismatches == 0
		and final_station - initial_station >= MIN_FORWARD_PROGRESS_M
		and max_abs_lateral_error <= LATERAL_ERROR_BOUND_M
		and not lab.failed
		and not lab.halted
	)
	var final := {
		"station_m": final_station,
		"forward_progress_m": final_station - initial_station,
		"speed_m_s": final_state.speed_m_s(),
		"forward_speed_m_s": final_state.forward_speed_m_s(),
		"position_x_m": final_state.position_m.x,
		"position_y_m": final_state.position_m.y,
		"heading_rad": final_state.heading_rad,
		"gear_index": int(final_state.gear_index),
		"max_speed_m_s": max_speed,
		"max_abs_lateral_error_m": max_abs_lateral_error,
		"max_abs_heading_rad": max_abs_heading,
		"min_station_delta_m": 0.0 if min_station_delta == INF else min_station_delta,
		"gear_shift_events": int(lab.gear_shift_events.size()),
		"steps_called": int(lab.steps_called),
		"ticks_committed": int(lab.ticks_committed),
	}
	out["completed"] = completed
	out["trace"] = trace
	out["final"] = final
	print(
		"CALIBRATION_PHYSICS_TRACE ",
		JSON.stringify({
			"schema": "roadstorm.calibration_physics_lab.trace.v1",
			"run": label,
			"profile_status": "provisional_not_tuned_not_benchmark_not_reference",
			"ticks": trace.size(),
			"records": trace,
		})
	)
	c.measurements[label + "_final"] = final.duplicate()
	c.measurements[label + "_trace_ticks"] = trace.size()
	await _teardown_lab(lab)
	return out


# --- Construction and comparison helpers -------------------------------------


func _make_lab(c, label: String):
	var packed: PackedScene = load(DRIVE_LAB_SCENE_PATH)
	if packed == null:
		c.check(false, label + ".drive_lab_scene_load")
		return null
	var lab = packed.instantiate()
	if lab == null:
		c.check(false, label + ".drive_lab_scene_instantiate")
		return null
	# Use the laboratory's own ordinary tuning/config factories. They are the
	# same ArcadeMotor, AutomaticGearbox and MotorBodyAdapter integration path
	# exercised by the committed drive-lab validator.
	var configured: bool = lab.configure(
		lab.make_laboratory_tuning(), lab.make_laboratory_config(), []
	)
	c.check(configured, label + ".ordinary_drive_lab_configuration_accepted")
	if not configured:
		lab.free()
		return null
	_holder.add_child(lab)
	return lab


func _make_straight_path(
	start_position: Vector2, axis: Vector2, right: Vector2
) -> CalibrationDriver.CalibrationPath:
	var s_values: Array = []
	var positions: Array = []
	var speeds: Array = []
	var count := int(round(STRAIGHT_LENGTH_M / STRAIGHT_STEP_M))
	for index in range(count + 1):
		var station := STRAIGHT_STEP_M * float(index)
		s_values.append(station)
		positions.append(start_position + axis * station + right * LANE_OFFSET_M)
		speeds.append(PROVISIONAL_TARGET_SPEED_M_S)
	return CalibrationDriver.CalibrationPath.from_arrays(
		s_values, positions, speeds, PATH_VERSION
	)


func _selected_samples(trace: Array) -> Array:
	var wanted := [0, 30, 60, 90, BRIDGE_TICKS - 1]
	var out: Array = []
	for index in wanted:
		if index >= 0 and index < trace.size():
			out.append(trace[index])
	return out


func _settle() -> void:
	for _index in range(SETTLE_FRAMES):
		await get_tree().physics_frame


func _teardown_lab(lab) -> void:
	if lab != null and is_instance_valid(lab):
		lab.queue_free()
	for _index in range(CLEANUP_FRAMES):
		await get_tree().physics_frame


func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)
