extends SceneTree
## Headless black-box runner for the M1.1 pure-motor slice.
##
## Run with the pinned Godot 4.7.2 from an isolated scratch project copy, e.g.:
##   godot --headless --path <scratch> --script res://tests/handling/pure_motor_entry.gd
## Optional `--case=<id>` selects one case; the default runs every case.
## `--case=intentional_failure` always exits nonzero to demonstrate failure
## detection. Each case prints one machine-readable `SLICE_RESULT <json>` line;
## the runner prints one `SLICE_SUMMARY <json>` line and exits 0 only when every
## selected case passes.
##
## These are pure-kernel checks only: no scene, body, physics query, clock or
## gameplay claim. They use explicit test tuning values and assert invariants,
## paired direction, immutability and replay equality rather than re-implementing
## motor formulas.

const DriverCommandScript = preload("res://src/simulation/driver_command.gd")
const CarStateScript = preload("res://src/simulation/car_state.gd")
const ArcadeMotorScript = preload("res://src/simulation/arcade_motor.gd")
const PureMotorDriverScript = preload("res://tests/handling/pure_motor_driver.gd")

const CASE_IDS := [
	"command_validation",
	"invalid_refusal",
	"acceleration_from_rest",
	"coast_drag_decrease",
	"brake_and_reverse",
	"steering_symmetry",
	"lateral_damping",
	"input_immutability",
	"deterministic_replay",
]

var d := PureMotorDriverScript.new()
var measurements: Dictionary = {}


func _initialize() -> void:
	var requested := _requested_case()
	if requested == "all":
		var results := []
		for case_id in CASE_IDS:
			results.append(_run_case(case_id))
		var failed := 0
		var total_checks := 0
		for result in results:
			total_checks += int(result["checks"])
			if not result["pass"]:
				failed += 1
		var summary := {
			"cases": results.size(),
			"checks": total_checks,
			"failed_cases": failed,
			"pass": failed == 0,
		}
		print("SLICE_SUMMARY " + JSON.stringify(summary))
		quit(0 if failed == 0 else 1)
	elif CASE_IDS.has(requested):
		var result := _run_case(requested)
		var summary := {
			"cases": 1,
			"checks": result["checks"],
			"failed_cases": 0 if result["pass"] else 1,
			"pass": result["pass"],
		}
		print("SLICE_SUMMARY " + JSON.stringify(summary))
		quit(0 if result["pass"] else 1)
	elif requested == "intentional_failure":
		var result := _run_intentional_failure()
		var summary := {
			"cases": 1,
			"checks": result["checks"],
			"failed_cases": 0 if result["pass"] else 1,
			"pass": result["pass"],
		}
		print("SLICE_SUMMARY " + JSON.stringify(summary))
		quit(1)
	else:
		printerr("unknown case '%s'; use all, one of %s, or intentional_failure" % [requested, str(CASE_IDS)])
		quit(2)


func _requested_case() -> String:
	for argument in OS.get_cmdline_args():
		if argument.begins_with("--case="):
			return argument.substr(7)
	var from_environment := OS.get_environment("PURE_MOTOR_CASE")
	if from_environment != "":
		return from_environment
	return "all"


func _run_case(case_id: String) -> Dictionary:
	d = PureMotorDriverScript.new()
	measurements = {}
	match case_id:
		"command_validation":
			_case_command_validation()
		"invalid_refusal":
			_case_invalid_refusal()
		"acceleration_from_rest":
			_case_acceleration_from_rest()
		"coast_drag_decrease":
			_case_coast_drag_decrease()
		"brake_and_reverse":
			_case_brake_and_reverse()
		"steering_symmetry":
			_case_steering_symmetry()
		"lateral_damping":
			_case_lateral_damping()
		"input_immutability":
			_case_input_immutability()
		"deterministic_replay":
			_case_deterministic_replay()
	var result := {
		"case": case_id,
		"pass": d.failures.is_empty(),
		"checks": d.checks,
		"failures": d.failures.duplicate(),
		"measurements": measurements.duplicate(),
	}
	print("SLICE_RESULT " + JSON.stringify(result))
	return result


func _run_intentional_failure() -> Dictionary:
	d = PureMotorDriverScript.new()
	measurements = {"intentional": true}
	d.check(false, "intentional failure mode: this assertion always fails")
	d.check(true, "intentional-failure control check")
	var result := {
		"case": "intentional_failure",
		"pass": d.failures.is_empty(),
		"checks": d.checks,
		"failures": d.failures.duplicate(),
		"measurements": measurements.duplicate(),
	}
	print("SLICE_RESULT " + JSON.stringify(result))
	return result


# ---------------------------------------------------------------------------
# Cases
# ---------------------------------------------------------------------------


func _case_command_validation() -> void:
	var clamped = DriverCommandScript.create(2.0, -0.5, 7.0, -1.0)
	d.check(clamped != null, "finite out-of-range command is accepted")
	if clamped != null:
		d.check_close(clamped.steer, 1.0, 1e-12, "steer clamped high")
		d.check_close(clamped.throttle, 0.0, 1e-12, "throttle clamped low")
		d.check_close(clamped.brake, 1.0, 1e-12, "brake clamped high")
		d.check_close(clamped.handbrake, 0.0, 1e-12, "handbrake clamped low")

	d.check(DriverCommandScript.create(NAN, 0.0, 0.0, 0.0) == null, "NaN steer refused")
	d.check(DriverCommandScript.create(0.0, INF, 0.0, 0.0) == null, "Inf throttle refused")
	d.check(DriverCommandScript.create(0.0, 0.0, NAN, 0.0) == null, "NaN brake refused")
	d.check(DriverCommandScript.create(0.0, 0.0, 0.0, NAN) == null, "NaN handbrake refused")

	var preset = DriverCommandScript.create(0.25, 0.0, 0.0, 0.0)
	var applied = preset.set_from_raw(NAN, 1.0, 1.0, 1.0, false)
	d.check(not applied, "nonfinite set_from_raw reports failure")
	d.check_close(preset.steer, 0.25, 1e-12, "rejected update leaves stored command intact")
	d.check_close(preset.throttle, 0.0, 1e-12, "rejected update does not set later fields")

	var tuning = d.handling_tuning()
	var state = d.make_state(Vector2(0.0, 0.0), Vector2(0.0, 10.0))
	var proposal = d.advance(state, clamped, tuning)
	d.check(proposal != null and proposal.state.is_finite(), "clamped command reaches the motor")

	var unnormalized = DriverCommandScript.new()
	unnormalized.steer = 1.5
	d.check(d.advance(state, unnormalized, tuning) == null, "directly assigned out-of-range steer refused")
	unnormalized.steer = 0.0
	unnormalized.throttle = -0.25
	d.check(d.advance(state, unnormalized, tuning) == null, "directly assigned negative throttle refused")

	var reset_only = DriverCommandScript.create(0.0, 0.0, 0.0, 0.0, true)
	var moved = d.advance(d.make_state(Vector2(0.0, 0.0), Vector2(0.0, 10.0)), reset_only, tuning)
	d.check(
		moved != null and moved.state.position_m.length() > 0.0,
		"reset_requested is carried, not executed by the pure motor"
	)
	measurements["clamped_steer"] = clamped.steer if clamped != null else null


func _case_invalid_refusal() -> void:
	var tuning = d.handling_tuning()
	var command = DriverCommandScript.create(0.0, 0.5, 0.0, 0.0)
	var good_state = d.make_state(Vector2(0.0, 0.0), Vector2(0.0, 5.0))

	d.check(
		ArcadeMotorScript.propose(good_state, command, tuning, 0.0) == null,
		"zero dt refused"
	)
	d.check(
		ArcadeMotorScript.propose(good_state, command, tuning, -ArcadeMotorScript.DT) == null,
		"negative dt refused"
	)
	d.check(
		ArcadeMotorScript.propose(good_state, command, tuning, NAN) == null,
		"NaN dt refused"
	)
	d.check(
		ArcadeMotorScript.propose(good_state, command, tuning, 1.0 / 30.0) == null,
		"non-60 Hz dt refused"
	)

	var nan_velocity = d.make_state(Vector2(0.0, 0.0), Vector2(NAN, 0.0))
	d.check(ArcadeMotorScript.propose(nan_velocity, command, tuning) == null, "NaN velocity refused")
	var inf_heading = d.make_state(Vector2(0.0, 0.0), Vector2(0.0, 0.0), INF)
	d.check(ArcadeMotorScript.propose(inf_heading, command, tuning) == null, "Inf heading refused")

	var nan_drag = d.handling_tuning()
	nan_drag.drag_aerodynamic = NAN
	d.check(ArcadeMotorScript.propose(good_state, command, nan_drag) == null, "NaN drag refused")
	var unsorted_curve = d.make_tuning(
		[[0.0, 9.0], [20.0, 6.0], [20.0, 3.0]],
		12.0, 0.0009, 0.25, 0.12, 1.6, 4.0, 1.0, 0.3, 4.0, 8.0
	)
	d.check(ArcadeMotorScript.propose(good_state, command, unsorted_curve) == null, "unsorted curve refused")
	var empty_curve = d.make_tuning(
		[], 12.0, 0.0009, 0.25, 0.12, 1.6, 4.0, 1.0, 0.3, 4.0, 8.0
	)
	d.check(ArcadeMotorScript.propose(good_state, command, empty_curve) == null, "empty curve refused")

	d.check(ArcadeMotorScript.propose(null, command, tuning) == null, "null state refused")
	d.check(ArcadeMotorScript.propose(good_state, null, tuning) == null, "null command refused")
	d.check(ArcadeMotorScript.propose(good_state, command, null) == null, "null tuning refused")


func _case_acceleration_from_rest() -> void:
	var tuning = d.handling_tuning()
	var command = DriverCommandScript.create(0.0, 1.0, 0.0, 0.0)
	var states = d.trace_states(d.make_state(), command, tuning, 300)
	d.check(states.size() == 300, "acceleration trace has 300 ticks")
	var speeds = d.forward_speeds(states)
	var previous := 0.0
	var strict_early := 0
	for index in range(speeds.size()):
		var speed = speeds[index]
		d.check_finite(speed, "finite acceleration speed at tick %d" % (index + 1))
		d.check(speed >= previous - 1e-9, "nondecreasing speed at tick %d" % (index + 1))
		if index < 120 and speed > previous + 1e-12:
			strict_early += 1
		d.check(absf(states[index].lateral_speed_m_s()) < 1e-9, "no lateral motion without steer")
		previous = speed
	d.check(strict_early >= 115, "speed increases strictly through early acceleration")
	d.check(previous > 1.0, "car accelerates from rest")

	var target := 100.0 / 3.6
	var crossing_tick := -1
	for index in range(speeds.size()):
		if speeds[index] >= target:
			crossing_tick = index + 1
			break
	measurements["ticks"] = states.size()
	measurements["final_speed_mps"] = previous
	measurements["strict_increase_ticks_first_120"] = strict_early
	measurements["time_to_100_kmh_s"] = crossing_tick * ArcadeMotorScript.DT if crossing_tick > 0 else null


func _case_coast_drag_decrease() -> void:
	# Explicit test-only coast tuning with stronger drag so a 15 s coast shows a
	# clear decrease; not a project coefficient.
	var tuning = d.make_tuning(
		[[0.0, 9.0], [20.0, 6.0], [45.0, 3.0], [60.0, 0.0]],
		12.0, 0.002, 1.0, 0.12, 1.6, 4.0, 1.0, 0.3, 4.0, 8.0
	)
	var initial_speed := 30.0
	var states = d.trace_states(
		d.make_state(Vector2(0.0, 0.0), Vector2(0.0, initial_speed)),
		DriverCommandScript.create(),
		tuning,
		900
	)
	d.check(states.size() == 900, "coast trace has 900 ticks")
	var previous := initial_speed
	for index in range(states.size()):
		var speed = states[index].speed_m_s()
		d.check_finite(speed, "finite coast speed at tick %d" % (index + 1))
		d.check(speed <= previous + 1e-9, "coast speed nonincreasing at tick %d" % (index + 1))
		d.check(speed >= 0.0, "coast never reverses direction")
		previous = speed
	d.check(previous < initial_speed * 0.5, "coast/drag reduces speed substantially")
	measurements["initial_speed_mps"] = initial_speed
	measurements["final_speed_mps"] = previous
	measurements["fraction_remaining"] = previous / initial_speed


func _case_brake_and_reverse() -> void:
	var tuning = d.handling_tuning()
	var brake_command = DriverCommandScript.create(0.0, 0.0, 1.0, 0.0)
	var current = d.make_state(Vector2(0.0, 0.0), Vector2(0.0, 12.0))
	var engaged_tick := -1
	var engagement_previous_speed := INF
	var first_negative_tick := -1
	for index in range(300):
		var previous_state = current
		var proposal = d.advance(current, brake_command, tuning)
		if proposal == null:
			d.check(false, "brake/reverse proposal returned null at tick %d" % (index + 1))
			break
		var state = proposal.state
		d.check_state_finite(state, "finite brake/reverse state at tick %d" % (index + 1))
		if state.reverse_engaged and not previous_state.reverse_engaged:
			engaged_tick = index + 1
			engagement_previous_speed = previous_state.forward_speed_m_s()
		if first_negative_tick < 0 and state.forward_speed_m_s() < -1.0:
			first_negative_tick = index + 1
		d.check(
			state.forward_speed_m_s() >= -tuning.reverse_top_speed_m_s - 1e-9,
			"reverse speed stays within declared top"
		)
		current = state
	d.check(engaged_tick > 0, "brake hold engages reverse below the trigger speed")
	if engaged_tick > 0:
		d.check(
			engagement_previous_speed <= tuning.reverse_trigger_speed_m_s + 1e-9,
			"reverse engagement never happens above the trigger speed"
		)
	d.check(first_negative_tick > 0, "reverse drives the car backward")
	d.check(current.forward_speed_m_s() <= -7.9, "reverse approaches its declared top speed")

	var fast = d.make_state(Vector2(0.0, 0.0), Vector2(0.0, 20.0))
	var fast_states = d.trace_states(fast, brake_command, tuning, 12)
	d.check(
		not fast_states[-1].reverse_engaged,
		"reversing never initiates at road speed"
	)
	measurements["reverse_engagement_s"] = engaged_tick * ArcadeMotorScript.DT if engaged_tick > 0 else null
	measurements["engagement_speed_mps"] = engagement_previous_speed
	measurements["first_negative_tick"] = first_negative_tick
	measurements["final_forward_speed_mps"] = current.forward_speed_m_s()


func _case_steering_symmetry() -> void:
	var tuning = d.handling_tuning()
	var left_initial = d.make_state(Vector2(0.0, 0.0), Vector2(0.0, 20.0))
	var right_initial = d.make_state(Vector2(0.0, 0.0), Vector2(0.0, 20.0))
	var left_command = DriverCommandScript.create(-1.0, 0.0, 0.0, 0.0)
	var right_command = DriverCommandScript.create(1.0, 0.0, 0.0, 0.0)
	var left_states = d.trace_states(left_initial, left_command, tuning, 60)
	var right_states = d.trace_states(right_initial, right_command, tuning, 60)
	d.check(left_states.size() == 60 and right_states.size() == 60, "steering traces complete")
	var tolerance := 1e-8
	for index in range(left_states.size()):
		var left = left_states[index]
		var right = right_states[index]
		d.check_state_finite(left, "finite left steering state")
		d.check_state_finite(right, "finite right steering state")
		d.check_close(left.forward_speed_m_s(), right.forward_speed_m_s(), tolerance, "paired forward speed")
		d.check_close(left.lateral_speed_m_s(), -right.lateral_speed_m_s(), tolerance, "paired mirrored lateral speed")
		d.check_close(left.speed_m_s(), right.speed_m_s(), tolerance, "paired total speed")
		d.check_close(left.heading_rad, -right.heading_rad, tolerance, "paired mirrored heading")
	var last_left = left_states[-1]
	var last_right = right_states[-1]
	d.check(last_left.heading_rad < -0.1 and last_right.heading_rad > 0.1, "positive steer turns right")
	d.check_close(last_left.position_m.x, -last_right.position_m.x, 1e-7, "mirrored lateral displacement")
	d.check_close(last_left.position_m.y, last_right.position_m.y, 1e-7, "equal forward displacement")
	measurements["left_final_heading_rad"] = last_left.heading_rad
	measurements["right_final_heading_rad"] = last_right.heading_rad


func _case_lateral_damping() -> void:
	var curve_pairs := [[0.0, 9.0], [20.0, 6.0], [45.0, 3.0], [60.0, 0.0]]
	var damped = d.make_tuning(
		curve_pairs, 12.0, 0.0, 0.0, 0.12, 1.6, 4.0, 1.0, 0.3, 4.0, 8.0
	)
	var undamped = d.make_tuning(
		curve_pairs, 12.0, 0.0, 0.0, 0.12, 1.6, 0.0, 1.0, 0.3, 4.0, 8.0
	)
	var initial = d.make_state(Vector2(0.0, 0.0), Vector2(5.0, 10.0))
	var command = DriverCommandScript.create()
	var states = d.trace_states(initial, command, damped, 60)
	d.check(states.size() == 60, "lateral damping trace complete")
	var previous_lateral := 5.0
	for index in range(states.size()):
		var state = states[index]
		var lateral = state.lateral_speed_m_s()
		d.check_finite(lateral, "finite lateral speed at tick %d" % (index + 1))
		d.check(lateral <= previous_lateral + 1e-12, "lateral speed does not grow")
		d.check(lateral > 0.0, "lateral sign is preserved while damping")
		d.check_close(state.forward_speed_m_s(), 10.0, 1e-9, "damping does not change the forward component")
		previous_lateral = lateral
	d.check(previous_lateral < 0.5, "lateral velocity decays substantially")
	var undamped_states = d.trace_states(initial, command, undamped, 60)
	d.check_close(
		undamped_states[-1].lateral_speed_m_s(),
		5.0,
		1e-9,
		"zero-damping control preserves lateral velocity"
	)
	measurements["final_lateral_damped_mps"] = previous_lateral
	measurements["final_lateral_undamped_mps"] = undamped_states[-1].lateral_speed_m_s()


func _case_input_immutability() -> void:
	var state = d.make_state(Vector2(1.5, 2.5), Vector2(3.0, 8.0), 0.3)
	state.surface_id = &"gravel"
	state.gear_index = 2
	state.drift_active = true
	state.drift_timer_s = 0.25
	state.reverse_hold_s = 0.1
	state.valid_progress_m = 12.5
	var command = DriverCommandScript.create(0.4, 0.7, 0.2, 0.1, true)
	var snapshot := {
		"position_m": state.position_m,
		"velocity_m_s": state.velocity_m_s,
		"heading_rad": state.heading_rad,
		"grounded": state.grounded,
		"surface_id": state.surface_id,
		"gear_index": state.gear_index,
		"drift_active": state.drift_active,
		"drift_timer_s": state.drift_timer_s,
		"reverse_hold_s": state.reverse_hold_s,
		"valid_progress_m": state.valid_progress_m,
	}
	var command_snapshot := {
		"steer": command.steer,
		"throttle": command.throttle,
		"brake": command.brake,
		"handbrake": command.handbrake,
		"reset_requested": command.reset_requested,
	}
	var proposal = d.advance(state, command, d.handling_tuning())
	d.check(proposal != null, "immutability scenario produced a proposal")
	if proposal != null:
		d.check(proposal.state != state, "proposal returns a new state object")
		d.check(state.position_m == snapshot["position_m"], "input position unchanged")
		d.check(state.velocity_m_s == snapshot["velocity_m_s"], "input velocity unchanged")
		d.check(state.heading_rad == snapshot["heading_rad"], "input heading unchanged")
		d.check(state.grounded == snapshot["grounded"], "input grounded unchanged")
		d.check(state.surface_id == snapshot["surface_id"], "input surface unchanged")
		d.check(state.gear_index == snapshot["gear_index"], "input gear seam unchanged")
		d.check(state.drift_active == snapshot["drift_active"], "input drift seam unchanged")
		d.check(state.drift_timer_s == snapshot["drift_timer_s"], "input drift timer unchanged")
		d.check(state.reverse_hold_s == snapshot["reverse_hold_s"], "input reverse hold unchanged")
		d.check(state.valid_progress_m == snapshot["valid_progress_m"], "input progress seam unchanged")
	d.check(command.steer == command_snapshot["steer"], "input steer unchanged")
	d.check(command.throttle == command_snapshot["throttle"], "input throttle unchanged")
	d.check(command.brake == command_snapshot["brake"], "input brake unchanged")
	d.check(command.handbrake == command_snapshot["handbrake"], "input handbrake unchanged")
	d.check(
		command.reset_requested == command_snapshot["reset_requested"],
		"input reset flag unchanged"
	)
	measurements["state_object_reused"] = proposal != null and proposal.state == state


func _case_deterministic_replay() -> void:
	var tuning = d.handling_tuning()
	var initial = d.make_state(Vector2(0.0, 0.0), Vector2(0.0, 15.0), 0.1)
	var schedule := [
		DriverCommandScript.create(0.0, 1.0, 0.0, 0.0),
		DriverCommandScript.create(0.6, 1.0, 0.0, 0.0),
		DriverCommandScript.create(-0.4, 0.0, 0.8, 0.0),
	]
	var first = d.trace_schedule_proposals(initial, schedule, tuning, 60)
	var second = d.trace_schedule_proposals(initial, schedule, tuning, 60)
	var third = d.trace_schedule_proposals(initial, schedule, tuning, 60)
	d.check(first.size() == 180 and second.size() == 180 and third.size() == 180, "replay traces complete")
	var mismatches := 0
	var first_mismatch := ""
	for index in range(min(first.size(), second.size())):
		var a = first[index]
		var b = second[index]
		var same = (
			a.displacement_m == b.displacement_m
			and a.yaw_delta_rad == b.yaw_delta_rad
			and a.state.position_m == b.state.position_m
			and a.state.velocity_m_s == b.state.velocity_m_s
			and a.state.heading_rad == b.state.heading_rad
			and a.state.reverse_engaged == b.state.reverse_engaged
			and a.state.reverse_hold_s == b.state.reverse_hold_s
			and a.state.grounded == b.state.grounded
			and a.state.surface_id == b.state.surface_id
		)
		if not same:
			mismatches += 1
			if first_mismatch == "":
				first_mismatch = "tick %d differs" % (index + 1)
	d.check(mismatches == 0, "deterministic replay is bit-identical (%s)" % first_mismatch)
	# A third run after unrelated allocations must still match the first.
	var third_matches := true
	for index in range(min(first.size(), third.size())):
		if first[index].state.velocity_m_s != third[index].state.velocity_m_s:
			third_matches = false
			break
	d.check(third_matches, "later replay still matches")
	measurements["ticks"] = first.size()
	measurements["mismatches"] = mismatches
	measurements["final_position_m"] = [first[-1].state.position_m.x, first[-1].state.position_m.y]
