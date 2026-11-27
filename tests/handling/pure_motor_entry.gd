extends SceneTree
## Headless black-box runner for the M1.1 pure-motor slice.
##
## Run with the pinned Godot 4.7.2 from an isolated scratch project copy. A
## headless import must run first so global script classes are registered:
##   godot --headless --path <scratch> --import
##   godot --headless --path <scratch> --script res://tests/handling/pure_motor_entry.gd
## or use tools/motor_test_support/run_pure_motor_entry.sh, which imports first,
## requires a `SLICE_SUMMARY` line containing `"pass":true`, rejects engine
## `ERROR`/`SCRIPT ERROR` lines, and enforces a wall-clock timeout.
##
## Optional `--case=<id>` selects one case; the default runs every case.
## On this engine the argument must follow the script path directly
## (`... --script res://... --case=<id>`); arguments after a bare `--` are not
## visible to `OS.get_cmdline_args()`.
## `--case=intentional_failure` always exits nonzero to demonstrate failure
## detection. Each case prints one machine-readable `SLICE_RESULT <json>` line;
## the runner prints one `SLICE_SUMMARY <json>` line and calls `quit` on every
## path. Exit status alone is not proof of success: the pinned engine can exit
## 0 after a parse error, so the wrapper also gates the log and summary marker.
##
## These are pure-kernel checks only: no scene, body, physics query, clock or
## gameplay claim. They use explicit test tuning values and assert invariants,
## paired direction, immutability and replay equality rather than re-implementing
## motor formulas.

const DriverCommandScript = preload("res://src/simulation/driver_command.gd")
const CarStateScript = preload("res://src/simulation/car_state.gd")
const ArcadeMotorScript = preload("res://src/simulation/arcade_motor.gd")
const PureMotorDriverScript = preload("res://tools/motor_test_support/pure_motor_driver.gd")

const CASE_IDS := [
	"command_validation",
	"invalid_refusal",
	"car_state_helpers",
	"acceleration_from_rest",
	"coast_drag_decrease",
	"lateral_drag",
	"brake_and_reverse",
	"reverse_input_priority",
	"reverse_hold_timing",
	"reverse_road_speed",
	"reverse_top_speed",
	"steering_symmetry",
	"signed_longitudinal_steering",
	"lateral_damping",
	"input_immutability",
	"deterministic_replay",
	"nonfinite_refusal",
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
		"car_state_helpers":
			_case_car_state_helpers()
		"acceleration_from_rest":
			_case_acceleration_from_rest()
		"coast_drag_decrease":
			_case_coast_drag_decrease()
		"lateral_drag":
			_case_lateral_drag()
		"brake_and_reverse":
			_case_brake_and_reverse()
		"reverse_input_priority":
			_case_reverse_input_priority()
		"reverse_hold_timing":
			_case_reverse_hold_timing()
		"reverse_road_speed":
			_case_reverse_road_speed()
		"reverse_top_speed":
			_case_reverse_top_speed()
		"steering_symmetry":
			_case_steering_symmetry()
		"signed_longitudinal_steering":
			_case_signed_longitudinal_steering()
		"lateral_damping":
			_case_lateral_damping()
		"input_immutability":
			_case_input_immutability()
		"deterministic_replay":
			_case_deterministic_replay()
		"nonfinite_refusal":
			_case_nonfinite_refusal()
	var result := {
		"case": case_id,
		"pass": d.failures.is_empty(),
		"checks": d.checks,
		"failures": d.failures.duplicate(),
		"measurements": measurements.duplicate(),
	}
	print("SLICE_RESULT " + JSON.stringify(result))
	return result


## First tick (1-based) whose state reports reverse engaged, or -1.
func _first_engaged_tick(states: Array) -> int:
	for index in range(states.size()):
		if states[index].reverse_engaged:
			return index + 1
	return -1


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

	# Zero drag and no throttle mean a correctly inert reset flag cannot move a
	# stationary car; equality is observable, unlike the old position-length
	# check that any coasting motion would satisfy.
	var quiet = d.make_tuning(
		[[0.0, 9.0], [20.0, 9.0]], 12.0, 0.0, 0.0, 0.0, INF, 0.0, 1.0, 0.3, 4.0, 8.0
	)
	var still = d.make_state(Vector2(3.0, 4.0), Vector2(0.0, 0.0))
	var reset_only = DriverCommandScript.create(0.0, 0.0, 0.0, 0.0, true)
	var reset_proposal = d.advance(still, reset_only, quiet)
	d.check(reset_proposal != null, "reset-only command reaches the motor")
	if reset_proposal != null:
		d.check(
			reset_proposal.state.position_m == still.position_m,
			"reset_requested does not move the car"
		)
		d.check(
			reset_proposal.state.velocity_m_s == still.velocity_m_s,
			"reset_requested does not change velocity"
		)
		d.check(
			reset_proposal.state.heading_rad == still.heading_rad,
			"reset_requested does not rotate the car"
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
	var mistyped_curve = ArcadeMotorScript.MotorTuning.make(
		[Vector2(0.0, 9.0), Vector2(20.0, 6.0)]
	)
	d.check(
		not mistyped_curve.is_valid(),
		"mistyped curve elements refused without typed-array engine errors"
	)

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


func _case_signed_longitudinal_steering() -> void:
	# Explicit yaw-only tuning: unit yaw gain, no force, drag or damping, so
	# one tick of steer 1 at signed forward speed v gives yaw v*DT.
	var tuning = d.make_tuning(
		[[0.0, 9.0], [20.0, 0.0]], 0.0, 0.0, 0.0, 1.0, INF, 0.0, 1.0, 0.3, 0.0, 0.0
	)
	var right = DriverCommandScript.create(1.0, 0.0, 0.0, 0.0)
	var expected_full := 10.0 * ArcadeMotorScript.DT

	var forward = d.make_state(Vector2.ZERO, Vector2(0.0, 10.0))
	var forward_proposal = d.advance(forward, right, tuning)
	d.check(forward_proposal != null, "forward steering produced a proposal")
	if forward_proposal != null:
		d.check_close(
			forward_proposal.yaw_delta_rad,
			expected_full,
			1e-12,
			"right steer while moving forward yaws the nose right"
		)
		d.check(
			forward_proposal.state.heading_rad > forward.heading_rad,
			"positive yaw increases heading while moving forward"
		)

	var backward = d.make_state(Vector2.ZERO, Vector2(0.0, -10.0))
	var backward_proposal = d.advance(backward, right, tuning)
	d.check(backward_proposal != null, "backward steering produced a proposal")
	if backward_proposal != null:
		d.check_close(
			backward_proposal.yaw_delta_rad,
			-expected_full,
			1e-12,
			"right steer while reversing yaws the nose left"
		)
		d.check(
			backward_proposal.state.heading_rad < backward.heading_rad,
			"negative yaw decreases heading while reversing"
		)
		# The rear points opposite the nose; a left-rotating nose in reverse
		# swings the rear right (positive road-plane x).
		d.check(
			-sin(backward_proposal.state.heading_rad) > 0.0,
			"left-rotating nose in reverse puts the rear to the right"
		)
		if forward_proposal != null:
			d.check_close(
				forward_proposal.yaw_delta_rad,
				-backward_proposal.yaw_delta_rad,
				1e-12,
				"equal forward and backward magnitudes give mirrored yaw"
			)
			d.check_close(
				forward_proposal.state.heading_rad - forward.heading_rad,
				-(backward_proposal.state.heading_rad - backward.heading_rad),
				1e-12,
				"equal forward and backward magnitudes give mirrored heading delta"
			)

	# Zero forward projection: lateral travel alone must not yaw, even with
	# full right steer.
	var lateral = d.make_state(Vector2.ZERO, Vector2(10.0, 0.0))
	var lateral_proposal = d.advance(lateral, right, tuning)
	d.check(lateral_proposal != null, "lateral steering produced a proposal")
	if lateral_proposal != null:
		d.check_close(
			lateral_proposal.yaw_delta_rad,
			0.0,
			1e-12,
			"pure lateral motion supplies no steering yaw"
		)
		d.check_close(
			lateral_proposal.state.heading_rad,
			lateral.heading_rad,
			1e-12,
			"pure lateral motion does not rotate the car"
		)

	# A small positive longitudinal component keeps the normal sign and scales
	# linearly toward zero.
	var slow_forward = d.make_state(Vector2.ZERO, Vector2(0.0, 1.0))
	var slow_proposal = d.advance(slow_forward, right, tuning)
	d.check(slow_proposal != null, "slow forward steering produced a proposal")
	if slow_proposal != null:
		d.check_close(
			slow_proposal.yaw_delta_rad,
			1.0 * ArcadeMotorScript.DT,
			1e-12,
			"small forward speed still steers right proportionally"
		)

	measurements["forward_yaw_delta_rad"] = (
		forward_proposal.yaw_delta_rad if forward_proposal != null else null
	)
	measurements["backward_yaw_delta_rad"] = (
		backward_proposal.yaw_delta_rad if backward_proposal != null else null
	)
	measurements["lateral_yaw_delta_rad"] = (
		lateral_proposal.yaw_delta_rad if lateral_proposal != null else null
	)


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
	state.reverse_engaged = true
	state.drift_active = true
	state.drift_timer_s = 0.25
	state.drift_slip_deg = 12.5
	state.reverse_hold_s = 0.1
	state.surge_cooldown_s = 0.75
	state.drafting_active = true
	state.contact_immunity_s = 0.5
	state.valid_progress_m = 12.5
	var command = DriverCommandScript.create(0.4, 0.7, 0.2, 0.1, true)
	var snapshot := {
		"position_m": state.position_m,
		"velocity_m_s": state.velocity_m_s,
		"heading_rad": state.heading_rad,
		"grounded": state.grounded,
		"surface_id": state.surface_id,
		"gear_index": state.gear_index,
		"reverse_engaged": state.reverse_engaged,
		"drift_active": state.drift_active,
		"drift_timer_s": state.drift_timer_s,
		"drift_slip_deg": state.drift_slip_deg,
		"reverse_hold_s": state.reverse_hold_s,
		"surge_cooldown_s": state.surge_cooldown_s,
		"drafting_active": state.drafting_active,
		"contact_immunity_s": state.contact_immunity_s,
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
		d.check(
			state.reverse_engaged == snapshot["reverse_engaged"],
			"input reverse flag unchanged"
		)
		d.check(state.drift_active == snapshot["drift_active"], "input drift seam unchanged")
		d.check(state.drift_timer_s == snapshot["drift_timer_s"], "input drift timer unchanged")
		d.check(state.drift_slip_deg == snapshot["drift_slip_deg"], "input slip seam unchanged")
		d.check(state.reverse_hold_s == snapshot["reverse_hold_s"], "input reverse hold unchanged")
		d.check(
			state.surge_cooldown_s == snapshot["surge_cooldown_s"],
			"input surge seam unchanged"
		)
		d.check(
			state.drafting_active == snapshot["drafting_active"],
			"input drafting seam unchanged"
		)
		d.check(
			state.contact_immunity_s == snapshot["contact_immunity_s"],
			"input contact immunity seam unchanged"
		)
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


func _case_car_state_helpers() -> void:
	var headings := [0.0, 0.3, -0.7, 1.9, -2.5]
	for heading in headings:
		var state = d.make_state(Vector2.ZERO, Vector2.ZERO, heading)
		var forward = state.forward_vector()
		var right = state.right_vector()
		# Vector2 stores 32-bit components, so compare against that precision.
		d.check_close(forward.x, sin(heading), 1e-6, "forward x follows sin(heading)")
		d.check_close(forward.y, cos(heading), 1e-6, "forward y follows cos(heading)")
		d.check_close(right.x, cos(heading), 1e-6, "right x follows cos(heading)")
		d.check_close(right.y, -sin(heading), 1e-6, "right y follows -sin(heading)")
		d.check_close(forward.length(), 1.0, 1e-6, "forward unit length")
		d.check_close(right.length(), 1.0, 1e-6, "right unit length")
		d.check_close(forward.dot(right), 0.0, 1e-6, "forward and right are orthogonal")

	var axis_state = d.make_state(Vector2.ZERO, Vector2(3.0, 4.0), 0.0)
	d.check_close(axis_state.speed_m_s(), 5.0, 1e-12, "ground speed magnitude")
	d.check_close(axis_state.forward_speed_m_s(), 4.0, 1e-12, "longitudinal component")
	d.check_close(axis_state.lateral_speed_m_s(), 3.0, 1e-12, "lateral component")
	d.check_close(
		axis_state.slip_deg(),
		rad_to_deg(atan2(3.0, 4.0)),
		1e-9,
		"slip angle of (3,4) at zero heading"
	)
	var zero_velocity = d.make_state(Vector2.ZERO, Vector2.ZERO, 0.4)
	d.check_close(zero_velocity.slip_deg(), 0.0, 1e-12, "zero velocity has zero slip")
	var reverse_travel = d.make_state(Vector2.ZERO, Vector2(0.0, -10.0), 0.0)
	d.check(absf(reverse_travel.slip_deg()) > 179.9, "reversing travel reports about 180 degrees")
	var right_travel = d.make_state(Vector2.ZERO, Vector2(10.0, 0.0), 0.0)
	d.check_close(right_travel.slip_deg(), 90.0, 1e-9, "rightward travel is +90 degrees of slip")
	var left_travel = d.make_state(Vector2.ZERO, Vector2(-10.0, 0.0), 0.0)
	d.check_close(left_travel.slip_deg(), -90.0, 1e-9, "leftward travel is -90 degrees of slip")

	var original = d.make_state(Vector2(1.5, 2.5), Vector2(3.0, 8.0), 0.3)
	original.surface_id = &"gravel"
	original.gear_index = 2
	original.reverse_engaged = true
	original.drift_active = true
	original.drift_timer_s = 0.25
	original.drift_slip_deg = 12.5
	original.surge_cooldown_s = 0.75
	original.drafting_active = true
	original.contact_immunity_s = 0.5
	original.valid_progress_m = 12.5
	var duplicate = original.copy()
	d.check(duplicate != original, "copy returns a new object")
	d.check(duplicate.position_m == original.position_m, "copy position")
	d.check(duplicate.velocity_m_s == original.velocity_m_s, "copy velocity")
	d.check(duplicate.heading_rad == original.heading_rad, "copy heading")
	d.check(duplicate.grounded == original.grounded, "copy grounded")
	d.check(duplicate.surface_id == original.surface_id, "copy surface")
	d.check(duplicate.reverse_engaged == original.reverse_engaged, "copy reverse flag")
	d.check(duplicate.gear_index == original.gear_index, "copy gear seam")
	d.check(duplicate.drift_slip_deg == original.drift_slip_deg, "copy slip seam")
	d.check(duplicate.valid_progress_m == original.valid_progress_m, "copy progress seam")
	duplicate.position_m = Vector2(9.0, 9.0)
	duplicate.velocity_m_s = Vector2(1.0, 1.0)
	duplicate.heading_rad = 1.0
	duplicate.gear_index = 7
	d.check(original.position_m == Vector2(1.5, 2.5), "mutating the copy leaves original position")
	d.check(original.velocity_m_s == Vector2(3.0, 8.0), "mutating the copy leaves original velocity")
	d.check(original.heading_rad == 0.3, "mutating the copy leaves original heading")
	d.check(original.gear_index == 2, "mutating the copy leaves original seams")


func _case_lateral_drag() -> void:
	var curve_pairs := [[0.0, 9.0], [20.0, 0.0], [60.0, 0.0]]
	var aero = d.make_tuning(curve_pairs, 12.0, 1.0, 0.0, 0.0, INF, 0.0, 1.0, 0.3, 4.0, 8.0)
	var rolling = d.make_tuning(curve_pairs, 12.0, 0.0, 1.0, 0.0, INF, 0.0, 1.0, 0.3, 4.0, 8.0)
	var no_drag = d.make_tuning(curve_pairs, 12.0, 0.0, 0.0, 0.0, INF, 0.0, 1.0, 0.3, 4.0, 8.0)
	var idle = DriverCommandScript.create()

	var lateral_initial = d.make_state(Vector2.ZERO, Vector2(10.0, 0.0))
	var lateral_proposal = d.advance(lateral_initial, idle, aero)
	d.check(lateral_proposal != null, "lateral drag produced a proposal")
	var straight_proposal = d.advance(
		d.make_state(Vector2.ZERO, Vector2(0.0, 10.0)), idle, aero
	)
	d.check(straight_proposal != null, "straight drag produced a proposal")
	if lateral_proposal != null and straight_proposal != null:
		var expected := 10.0 - 1.0 * 10.0 * 10.0 * ArcadeMotorScript.DT
		d.check_close(
			lateral_proposal.state.speed_m_s(),
			expected,
			1e-6,
			"aerodynamic drag decays pure lateral velocity"
		)
		d.check_close(
			lateral_proposal.state.forward_speed_m_s(),
			0.0,
			1e-9,
			"lateral drag does not create longitudinal motion"
		)
		d.check_close(
			lateral_proposal.state.lateral_speed_m_s(),
			expected,
			1e-6,
			"drag opposes lateral velocity without reversing it"
		)
		d.check_close(
			straight_proposal.state.speed_m_s(),
			lateral_proposal.state.speed_m_s(),
			1e-9,
			"equal-speed lateral and straight states decay equally"
		)

	var roll_proposal = d.advance(
		d.make_state(Vector2.ZERO, Vector2(0.0, 10.0)), idle, rolling
	)
	d.check(roll_proposal != null, "rolling drag produced a proposal")
	if roll_proposal != null:
		d.check_close(
			roll_proposal.state.speed_m_s(),
			10.0 - 1.0 * ArcadeMotorScript.DT,
			1e-6,
			"rolling drag decays pure longitudinal velocity"
		)

	# The curve takes ground-speed magnitude, not the longitudinal component:
	# at 20 m/s ground speed this curve is zero, so lateral-only 20 m/s gains
	# no engine force.
	var throttle = DriverCommandScript.create(0.0, 1.0, 0.0, 0.0)
	var ground_keyed = d.advance(
		d.make_state(Vector2.ZERO, Vector2(20.0, 0.0)), throttle, no_drag
	)
	d.check(ground_keyed != null, "ground-speed curve probe produced a proposal")
	if ground_keyed != null:
		d.check_close(
			ground_keyed.state.forward_speed_m_s(),
			0.0,
			1e-9,
			"curve is keyed to ground speed, not the zero longitudinal component"
		)
		d.check_close(
			ground_keyed.state.speed_m_s(),
			20.0,
			1e-9,
			"zero ground-speed acceleration adds no speed"
		)

	var trace = d.trace_states(lateral_initial, idle, aero, 60)
	d.check(trace.size() == 60, "lateral decay trace complete")
	var previous := 10.0
	for index in range(trace.size()):
		var speed = trace[index].speed_m_s()
		d.check_finite(speed, "finite lateral decay speed at tick %d" % (index + 1))
		d.check(speed <= previous + 1e-9, "lateral speed never grows under drag")
		d.check(speed >= 0.0, "drag never reverses the car")
		previous = speed
	d.check(previous < 1.0, "sustained drag decays lateral velocity substantially")
	measurements["lateral_after_one_tick_mps"] = (
		lateral_proposal.state.speed_m_s() if lateral_proposal != null else null
	)
	measurements["lateral_after_60_ticks_mps"] = previous


func _case_reverse_input_priority() -> void:
	var tuning = d.handling_tuning()
	var paired = DriverCommandScript.create(0.0, 1.0, 1.0, 0.0)
	var current = d.make_state()
	var flag_changes := 0
	var observed_engaged := false
	for index in range(90):
		var previous = current
		var proposal = d.advance(current, paired, tuning)
		if proposal == null:
			d.check(false, "paired input produced null at tick %d" % (index + 1))
			break
		current = proposal.state
		if current.reverse_engaged != previous.reverse_engaged:
			flag_changes += 1
		if current.reverse_engaged:
			observed_engaged = true
	d.check(not observed_engaged, "throttle+brake together never engages reverse")
	d.check(flag_changes == 0, "reverse flag stays stable under paired input for 90 ticks")

	var brake_only = DriverCommandScript.create(0.0, 0.0, 1.0, 0.0)
	var brake_states = d.trace_states(d.make_state(), brake_only, tuning, 60)
	var brake_engaged := false
	for state in brake_states:
		if state.reverse_engaged:
			brake_engaged = true
			break
	d.check(brake_engaged, "control: brake alone engages reverse")

	var engaged = d.make_state(Vector2.ZERO, Vector2(0.0, -3.0))
	engaged.reverse_engaged = true
	var released = d.advance(engaged, paired, tuning)
	d.check(
		released != null and not released.state.reverse_engaged,
		"throttle releases an engaged reverse"
	)
	measurements["paired_flag_changes_90_ticks"] = flag_changes


func _case_reverse_hold_timing() -> void:
	var tuning = d.handling_tuning()
	d.check(
		tuning.reverse_hold_time_s >= ArcadeMotorScript.REVERSE_HOLD_TIME_MIN_S - 1e-9,
		"test tuning respects the design minimum hold"
	)
	var zero_hold = d.reverse_tuning(tuning.reverse_trigger_speed_m_s, 0.0)
	d.check(not zero_hold.is_valid(), "zero reverse hold refused by validation")
	var below_minimum = d.reverse_tuning(
		tuning.reverse_trigger_speed_m_s,
		ArcadeMotorScript.REVERSE_HOLD_TIME_MIN_S - 1e-3
	)
	d.check(not below_minimum.is_valid(), "hold below 0.3 s refused by validation")
	var minimum = d.reverse_tuning(
		tuning.reverse_trigger_speed_m_s, ArcadeMotorScript.REVERSE_HOLD_TIME_MIN_S
	)
	d.check(minimum.is_valid(), "exactly 0.3 s hold accepted")

	var brake_command = DriverCommandScript.create(0.0, 0.0, 1.0, 0.0)
	var states = d.trace_states(d.make_state(), brake_command, tuning, 60)
	d.check(states.size() == 60, "timing trace complete")
	var engaged_tick := -1
	for index in range(states.size()):
		if states[index].reverse_engaged:
			engaged_tick = index + 1
			break
	d.check(engaged_tick > 0, "brake hold eventually engages reverse")
	var min_ticks := int(
		ceil((ArcadeMotorScript.REVERSE_HOLD_TIME_MIN_S - 1e-9) / ArcadeMotorScript.DT)
	)
	if engaged_tick > 0:
		d.check(
			engaged_tick >= min_ticks,
		"engagement waits at least the %.3fs hold (tick %d, min %d)" % [
				ArcadeMotorScript.REVERSE_HOLD_TIME_MIN_S, engaged_tick, min_ticks
			]
		)
		d.check(
			not states[min_ticks - 2].reverse_engaged,
			"no engagement on the tick before the hold elapses"
		)
	d.check(not states[0].reverse_engaged, "brake does not engage reverse on the first tick")
	measurements["hold_engaged_tick"] = engaged_tick
	measurements["hold_engagement_time_s"] = (
		engaged_tick * ArcadeMotorScript.DT if engaged_tick > 0 else null
	)
	measurements["hold_min_ticks"] = min_ticks

	# Hold continuity across an airborne branch. A released brake must clear a
	# partial hold in the air so a later press starts fresh on landing; a
	# continuous brake hold carries across the hop without advancing.
	var continuity_tuning = d.make_tuning(
		[[0.0, 9.0], [20.0, 0.0]], 0.0, 0.0, 0.0, 0.0, INF, 0.0, 1.0, 0.3, 0.0, 0.0
	)
	var interrupted = d.make_state()
	for _index in range(min_ticks - 6):
		var proposal = d.advance(interrupted, brake_command, continuity_tuning)
		if proposal == null:
			d.check(false, "continuity setup returned null")
			break
		interrupted = proposal.state
	d.check(
		interrupted.reverse_hold_s > 0.0 and not interrupted.reverse_engaged,
		"partial hold accumulated before airtime"
	)
	var airborne = interrupted.copy()
	airborne.grounded = false
	var released_command = DriverCommandScript.create()
	for _index in range(5):
		var proposal = d.advance(airborne, released_command, continuity_tuning)
		if proposal == null:
			d.check(false, "airborne release returned null")
			break
		airborne = proposal.state
	d.check(not airborne.reverse_engaged, "release during airtime does not engage reverse")
	d.check(
		airborne.reverse_hold_s == 0.0,
		"releasing the brake in airtime clears the partial hold"
	)
	var landed = airborne.copy()
	landed.grounded = true
	var landed_states = d.trace_states(landed, brake_command, continuity_tuning, 60)
	var landed_engaged_tick := -1
	for index in range(landed_states.size()):
		if landed_states[index].reverse_engaged:
			landed_engaged_tick = index + 1
			break
	d.check(landed_engaged_tick > 0, "brake hold after landing eventually engages reverse")
	if landed_engaged_tick > 0:
		d.check(
			landed_engaged_tick >= min_ticks,
		"landing engagement waits for a fresh full hold (tick %d, min %d)" % [landed_engaged_tick, min_ticks]
		)
		measurements["airborne_interrupted_engaged_tick"] = landed_engaged_tick

	var continuous = d.make_state()
	for _index in range(min_ticks - 6):
		var proposal = d.advance(continuous, brake_command, continuity_tuning)
		if proposal == null:
			d.check(false, "continuous-hold setup returned null")
			break
		continuous = proposal.state
	var carried_hold_s = continuous.reverse_hold_s
	var continuous_air = continuous.copy()
	continuous_air.grounded = false
	for _index in range(5):
		var proposal = d.advance(continuous_air, brake_command, continuity_tuning)
		if proposal == null:
			d.check(false, "airborne continuous hold returned null")
			break
		continuous_air = proposal.state
	d.check(
		is_equal_approx(continuous_air.reverse_hold_s, carried_hold_s),
		"a brake held through airtime preserves the accumulated hold"
	)
	var continuous_landed = continuous_air.copy()
	continuous_landed.grounded = true
	var continuous_states = d.trace_states(
		continuous_landed, brake_command, continuity_tuning, 60
	)
	var continuous_engaged_tick := -1
	for index in range(continuous_states.size()):
		if continuous_states[index].reverse_engaged:
			continuous_engaged_tick = index + 1
			break
	d.check(
		continuous_engaged_tick > 0 and continuous_engaged_tick < min_ticks,
		"a carried hold completes sooner than a fresh one (tick %d, min %d)" % [continuous_engaged_tick, min_ticks]
	)
	measurements["airborne_carried_hold_s"] = carried_hold_s


func _case_reverse_road_speed() -> void:
	var tuning = d.handling_tuning()
	d.check(
		tuning.reverse_trigger_speed_m_s <= ArcadeMotorScript.REVERSE_TRIGGER_SPEED_MAX_M_S + 1e-9,
		"test tuning respects the design trigger bound"
	)
	var road_trigger = d.reverse_tuning(20.0, tuning.reverse_hold_time_s)
	d.check(not road_trigger.is_valid(), "20 m/s reverse trigger refused by validation")
	var over_trigger = d.reverse_tuning(
		ArcadeMotorScript.REVERSE_TRIGGER_SPEED_MAX_M_S + 0.001, tuning.reverse_hold_time_s
	)
	d.check(not over_trigger.is_valid(), "trigger above 1 m/s refused by validation")
	var at_trigger = d.reverse_tuning(
		ArcadeMotorScript.REVERSE_TRIGGER_SPEED_MAX_M_S, tuning.reverse_hold_time_s
	)
	d.check(at_trigger.is_valid(), "exactly 1 m/s trigger accepted")

	var brake_command = DriverCommandScript.create(0.0, 0.0, 1.0, 0.0)
	var current = d.make_state(Vector2.ZERO, Vector2(0.0, 20.0))
	var engaged_tick := -1
	var engagement_previous_speed := INF
	for index in range(300):
		var previous = current
		var proposal = d.advance(current, brake_command, tuning)
		if proposal == null:
			d.check(false, "road-speed probe returned null at tick %d" % (index + 1))
			break
		current = proposal.state
		if current.reverse_engaged and not previous.reverse_engaged:
			engaged_tick = index + 1
			engagement_previous_speed = previous.forward_speed_m_s()
			break
	d.check(engaged_tick > 0, "braking from 20 m/s eventually engages reverse")
	if engaged_tick > 0:
		d.check(
			engagement_previous_speed <= ArcadeMotorScript.REVERSE_TRIGGER_SPEED_MAX_M_S + 1e-9,
			"engagement happens at or below 1 m/s (previous speed %s)" % engagement_previous_speed
		)
	var high_states = d.trace_states(
		d.make_state(Vector2.ZERO, Vector2(0.0, 20.0)), brake_command, tuning, 30
	)
	var high_engaged := false
	for state in high_states:
		if state.reverse_engaged:
			high_engaged = true
			break
	d.check(not high_engaged, "one second of braking from 20 m/s does not engage reverse")

	# New engagement is gated by road-plane speed magnitude, not signed
	# longitudinal speed: a backward roll and a lateral-dominant slide at road
	# speed are both above the trigger and must not engage. An already-engaged
	# reverse is unaffected by the new gate.
	var inert = d.make_tuning(
		[[0.0, 9.0], [20.0, 0.0]], 0.0, 0.0, 0.0, 0.0, INF, 0.0, 1.0, 0.3, 0.0, 0.0
	)
	var backward_fast = d.trace_states(
		d.make_state(Vector2.ZERO, Vector2(0.0, -5.0)), brake_command, inert, 60
	)
	d.check(not backward_fast[-1].reverse_engaged, "-5 m/s backward roll does not engage reverse")
	var lateral_dominant = d.trace_states(
		d.make_state(Vector2.ZERO, Vector2(-20.0, 0.0)), brake_command, inert, 60
	)
	d.check(
		not lateral_dominant[-1].reverse_engaged,
		"pure lateral slide at 20 m/s does not engage reverse"
	)
	var already_engaged = d.make_state(Vector2.ZERO, Vector2(0.0, -5.0))
	already_engaged.reverse_engaged = true
	var kept = d.advance(already_engaged, brake_command, tuning)
	d.check(
		kept != null and kept.state.reverse_engaged,
		"an already-engaged reverse at -5 m/s stays engaged"
	)

	# With braking, a backward roll decelerates into the allowed range and
	# engages only after a full hold measured from that crossing.
	var min_ticks := int(
		ceil((ArcadeMotorScript.REVERSE_HOLD_TIME_MIN_S - 1e-9) / ArcadeMotorScript.DT)
	)
	var rolling_back = d.make_state(Vector2.ZERO, Vector2(0.0, -5.0))
	var decel_states = d.trace_states(rolling_back, brake_command, tuning, 300)
	var gate_open_tick := -1
	for index in range(decel_states.size()):
		var pre_state = rolling_back if index == 0 else decel_states[index - 1]
		if pre_state.speed_m_s() <= tuning.reverse_trigger_speed_m_s + 1e-9:
			gate_open_tick = index + 1
			break
	var decel_engaged_tick := -1
	for index in range(decel_states.size()):
		if decel_states[index].reverse_engaged:
			decel_engaged_tick = index + 1
			break
	d.check(gate_open_tick > 0, "backward roll reaches the allowed speed range")
	d.check(
		decel_engaged_tick > gate_open_tick,
		"backward roll engages only after entering the range"
	)
	if gate_open_tick > 0 and decel_engaged_tick > 0:
		var pre_engagement = (
			rolling_back if decel_engaged_tick == 1 else decel_states[decel_engaged_tick - 2]
		)
		d.check(
			pre_engagement.speed_m_s() <= tuning.reverse_trigger_speed_m_s + 1e-9,
			"engagement pre-state is at or below 1 m/s"
		)
		d.check(
			decel_engaged_tick >= gate_open_tick + min_ticks - 1,
		"backward engagement waits for the full hold after deceleration (tick %d, gate tick %d, min %d)" % [
				decel_engaged_tick, gate_open_tick, min_ticks
			]
		)

	# Strict threshold boundary with zero forces keeps the speed fixed at its
	# initial value, so these probes isolate the comparison itself: exactly
	# 1 m/s in either travel direction must not even accumulate hold, just below
	# must wait the full configured uninterrupted hold, and just above never
	# engages.
	var offset := 1e-6
	var boundary_hold_ticks := int(
		ceil((inert.reverse_hold_time_s - 1e-9) / ArcadeMotorScript.DT)
	)
	var exact_forward = d.trace_states(
		d.make_state(Vector2.ZERO, Vector2(0.0, 1.0)), brake_command, inert, 60
	)
	var exact_backward = d.trace_states(
		d.make_state(Vector2.ZERO, Vector2(0.0, -1.0)), brake_command, inert, 60
	)
	var below_forward = d.trace_states(
		d.make_state(Vector2.ZERO, Vector2(0.0, 1.0 - offset)), brake_command, inert, 60
	)
	var below_backward = d.trace_states(
		d.make_state(Vector2.ZERO, Vector2(0.0, -(1.0 - offset))), brake_command, inert, 60
	)
	var above_forward = d.trace_states(
		d.make_state(Vector2.ZERO, Vector2(0.0, 1.0 + offset)), brake_command, inert, 60
	)
	var above_backward = d.trace_states(
		d.make_state(Vector2.ZERO, Vector2(0.0, -(1.0 + offset))), brake_command, inert, 60
	)

	var exact_forward_max_hold := 0.0
	for state in exact_forward:
		d.check(not state.reverse_engaged, "exactly +1 m/s forward never engages reverse")
		exact_forward_max_hold = maxf(exact_forward_max_hold, state.reverse_hold_s)
	var exact_backward_max_hold := 0.0
	for state in exact_backward:
		d.check(not state.reverse_engaged, "exactly -1 m/s backward never engages reverse")
		exact_backward_max_hold = maxf(exact_backward_max_hold, state.reverse_hold_s)
	d.check(exact_forward_max_hold == 0.0, "exactly +1 m/s forward accumulates no reverse hold")
	d.check(exact_backward_max_hold == 0.0, "exactly -1 m/s backward accumulates no reverse hold")

	var below_forward_tick := _first_engaged_tick(below_forward)
	var below_backward_tick := _first_engaged_tick(below_backward)
	d.check(
		below_forward_tick == boundary_hold_ticks,
		"just below +1 m/s engages only after the configured hold (tick %d, expected %d)" % [
			below_forward_tick, boundary_hold_ticks
		]
	)
	d.check(
		below_backward_tick == boundary_hold_ticks,
		"just below -1 m/s engages only after the configured hold (tick %d, expected %d)" % [
			below_backward_tick, boundary_hold_ticks
		]
	)
	d.check(not above_forward[-1].reverse_engaged, "just above +1 m/s never engages reverse")
	d.check(not above_backward[-1].reverse_engaged, "just above -1 m/s never engages reverse")

	measurements["road_speed_engaged_tick"] = engaged_tick
	measurements["road_speed_at_engagement_mps"] = engagement_previous_speed
	measurements["backward_decel_gate_open_tick"] = gate_open_tick
	measurements["backward_decel_engaged_tick"] = decel_engaged_tick
	measurements["boundary_exact_forward_max_hold_s"] = exact_forward_max_hold
	measurements["boundary_exact_backward_max_hold_s"] = exact_backward_max_hold
	measurements["boundary_below_forward_tick"] = below_forward_tick
	measurements["boundary_below_backward_tick"] = below_backward_tick


func _case_reverse_top_speed() -> void:
	var tuning = d.handling_tuning()
	var brake_command = DriverCommandScript.create(0.0, 0.0, 1.0, 0.0)

	var committed = d.make_state(Vector2.ZERO, Vector2(0.0, -20.0))
	committed.reverse_engaged = true
	var committed_proposal = d.advance(committed, brake_command, tuning)
	d.check(committed_proposal != null, "committed fast reverse produced a proposal")
	if committed_proposal != null:
		var speed = committed_proposal.state.forward_speed_m_s()
		d.check(
			speed < -tuning.reverse_top_speed_m_s - 1.0,
			"committed -20 m/s is not snapped toward the %.1f m/s cap" % tuning.reverse_top_speed_m_s
		)
		d.check(speed > -20.0 - 1e-6, "committed -20 m/s only decays under drag")
		measurements["committed_reverse_after_mps"] = speed

	# The cap still limits newly applied reverse drive when approaching the top.
	var strong = d.handling_tuning()
	strong.reverse_acceleration_m_s2 = 40.0
	var approaching = d.make_state(Vector2.ZERO, Vector2(0.0, -7.99))
	approaching.reverse_engaged = true
	var capped_proposal = d.advance(approaching, brake_command, strong)
	d.check(capped_proposal != null, "capped approach produced a proposal")
	if capped_proposal != null:
		var capped_speed = capped_proposal.state.forward_speed_m_s()
		d.check(
			capped_speed >= -strong.reverse_top_speed_m_s - 1e-9,
			"newly applied reverse drive never exceeds the cap"
		)
		d.check(
			capped_speed > -strong.reverse_top_speed_m_s - 0.1,
			"the cap holds a strong approach near the top instead of allowing %s" % capped_speed
		)
		measurements["capped_reverse_speed_mps"] = capped_speed


func _case_nonfinite_refusal() -> void:
	var tuning = d.handling_tuning()
	# Exact coordinator negative control: finite extreme inputs validate, but
	# the uncapped yaw math overflows to Inf/NaN.
	var extreme = tuning
	extreme.yaw_gain_grip = 1e300
	extreme.max_yaw_rate_rad_s = INF
	extreme.drag_aerodynamic = 0.0
	extreme.drag_rolling = 0.0
	d.check(extreme.is_valid(), "negative-control tuning validates")
	var huge_velocity = d.make_state(Vector2.ZERO, Vector2(0.0, 1e20))
	var steering = DriverCommandScript.create(1.0, 0.0, 0.0, 0.0)
	var overflow = ArcadeMotorScript.propose(huge_velocity, steering, extreme)
	d.check(overflow == null, "nonfinite yaw proposal from finite extreme inputs refused")

	var extreme_curve = d.make_tuning(
		[[0.0, 1e308], [60.0, 0.0]], 12.0, 0.0, 0.0, 0.0, INF, 0.0, 1.0, 0.3, 4.0, 8.0
	)
	d.check(extreme_curve.is_valid(), "extreme curve tuning validates")
	var curve_overflow = ArcadeMotorScript.propose(
		d.make_state(), DriverCommandScript.create(0.0, 1.0, 0.0, 0.0), extreme_curve
	)
	d.check(curve_overflow == null, "overflowing acceleration-curve proposal refused")

	var normal = ArcadeMotorScript.propose(
		d.make_state(Vector2.ZERO, Vector2(0.0, 10.0)),
		DriverCommandScript.create(0.0, 1.0, 0.0, 0.0),
		d.handling_tuning()
	)
	d.check(normal != null and normal.state.is_finite(), "ordinary proposal remains available")
	measurements["overflow_refused"] = overflow == null
	measurements["curve_overflow_refused"] = curve_overflow == null
