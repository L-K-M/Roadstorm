class_name PureMotorDriver
extends RefCounted
## Black-box helpers shared by the M1.1 pure-motor checks.
##
## This driver never re-implements motor math: it constructs explicit tuning
## values and commands, calls the real `ArcadeMotor.propose()`, and compares
## measured invariants, paired runs and replays. Failures are collected rather
## than asserted through the engine's push_error path so the runner can emit
## machine-readable results and control its exit code.

const ArcadeMotorScript = preload("res://src/simulation/arcade_motor.gd")
const CarStateScript = preload("res://src/simulation/car_state.gd")

var checks := 0
var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func check_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	checks += 1
	if is_nan(actual) or is_inf(actual) or absf(actual - expected) > tolerance:
		failures.append(
			"%s (actual=%s expected=%s tol=%s)" % [message, actual, expected, tolerance]
		)


func check_finite(value: float, message: String) -> void:
	checks += 1
	if is_nan(value) or is_inf(value):
		failures.append("%s (value=%s)" % [message, value])


func check_state_finite(state, message: String) -> void:
	checks += 1
	if state == null or not state.is_finite():
		failures.append(message)


func make_curve(pairs: Array) -> Array:
	var curve := []
	for pair in pairs:
		curve.append(ArcadeMotorScript.SpeedAccelerationPoint.make(pair[0], pair[1]))
	return curve


## Copy of the shared test tuning with explicit reverse trigger and hold
## values, for boundary checks. Returns a fresh tuning each call.
func reverse_tuning(trigger_speed_m_s: float, hold_time_s: float):
	var tuning = handling_tuning()
	tuning.reverse_trigger_speed_m_s = trigger_speed_m_s
	tuning.reverse_hold_time_s = hold_time_s
	return tuning


## Explicit tuning values used by the acceleration/coast/brake/steering cases.
## These are test inputs, not frozen project coefficients.
func handling_tuning():
	return make_tuning(
		[[0.0, 9.0], [20.0, 6.0], [45.0, 3.0], [60.0, 0.0]],
		12.0,
		0.0009,
		0.25,
		0.12,
		1.6,
		4.0,
		1.0,
		0.3,
		4.0,
		8.0
	)


func make_tuning(
	curve_pairs: Array,
	braking_acceleration_m_s2: float,
	drag_aerodynamic: float,
	drag_rolling: float,
	yaw_gain_grip: float,
	max_yaw_rate_rad_s: float,
	lateral_damping_grip_per_s: float,
	reverse_trigger_speed_m_s: float,
	reverse_hold_time_s: float,
	reverse_acceleration_m_s2: float,
	reverse_top_speed_m_s: float
):
	return ArcadeMotorScript.MotorTuning.make(
		make_curve(curve_pairs),
		braking_acceleration_m_s2,
		drag_aerodynamic,
		drag_rolling,
		yaw_gain_grip,
		max_yaw_rate_rad_s,
		lateral_damping_grip_per_s,
		reverse_trigger_speed_m_s,
		reverse_hold_time_s,
		reverse_acceleration_m_s2,
		reverse_top_speed_m_s
	)


func make_state(
	position := Vector2(0.0, 0.0),
	velocity := Vector2(0.0, 0.0),
	heading := 0.0,
	grounded := true
):
	var state := CarStateScript.new()
	state.position_m = position
	state.velocity_m_s = velocity
	state.heading_rad = heading
	state.grounded = grounded
	return state


func advance(state, command, tuning):
	return ArcadeMotorScript.propose(state, command, tuning, ArcadeMotorScript.DT)


## Apply one command for `ticks` steps, returning every proposed state.
func trace_states(state, command, tuning, ticks: int) -> Array:
	var states := []
	var current = state
	for _index in ticks:
		var proposal = advance(current, command, tuning)
		if proposal == null:
			return states
		states.append(proposal.state)
		current = proposal.state
	return states


## Apply a repeating command schedule, holding each command for `ticks_each`.
func trace_schedule(initial_state, schedule: Array, tuning, ticks_each: int) -> Array:
	var states := []
	var current = initial_state
	for command in schedule:
		for _tick in ticks_each:
			var proposal = advance(current, command, tuning)
			if proposal == null:
				return states
			states.append(proposal.state)
			current = proposal.state
	return states


## Same schedule as `trace_schedule`, retaining every proposal (state,
## displacement and yaw delta) for exact replay comparison.
func trace_schedule_proposals(initial_state, schedule: Array, tuning, ticks_each: int) -> Array:
	var proposals := []
	var current = initial_state
	for command in schedule:
		for _tick in ticks_each:
			var proposal = advance(current, command, tuning)
			if proposal == null:
				return proposals
			proposals.append(proposal)
			current = proposal.state
	return proposals


func forward_speeds(states: Array) -> Array:
	var speeds := []
	for state in states:
		speeds.append(state.forward_speed_m_s())
	return speeds
