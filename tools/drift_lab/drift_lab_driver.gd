class_name DriftLabDriver
extends RefCounted
## Black-box helpers shared by the M1.3 drift-phase checks.
##
## This driver never re-implements drift-phase math. It builds explicit
## `CarState`, `DriverCommand`, `DriftPhaseModel.State` and `Tuning` values,
## calls the real `DriftPhaseModel.propose()`, and compares measured
## invariants, paired runs and replays. Failures are collected rather than
## pushed through engine errors so the validator can emit machine-readable
## results and control its exit code.

const DriftModel = preload("res://src/simulation/drift_phase_model.gd")
const CarStateScript = preload("res://src/simulation/car_state.gd")
const DriverCommandScript = preload("res://src/simulation/driver_command.gd")

var checks := 0
var failures: Array[String] = []
var measured: Dictionary = {}


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func check_eq(actual, expected, message: String) -> void:
	checks += 1
	if actual != expected:
		failures.append("%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func check_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	checks += 1
	if is_nan(actual) or is_inf(actual) or absf(actual - expected) > tolerance:
		failures.append(
			"%s (actual=%s expected=%s tol=%s)" % [message, actual, expected, tolerance]
		)


func check_between(value: float, low: float, high: float, message: String) -> void:
	checks += 1
	if is_nan(value) or is_inf(value) or value < low - 1e-9 or value > high + 1e-9:
		failures.append(
			"%s (value=%s range=[%s,%s])" % [message, value, low, high]
		)


func measure(key: String, value) -> void:
	measured[key] = value


# --- Input builders ---------------------------------------------------------


func default_tuning():
	return DriftModel.Tuning.new()


func make_car(
	forward_speed_m_s: float = 20.0,
	lateral_speed_m_s: float = 0.0,
	heading_rad: float = 0.0,
	grounded: bool = true
):
	var state := CarStateScript.new()
	state.velocity_m_s = Vector2(lateral_speed_m_s, forward_speed_m_s)
	state.heading_rad = heading_rad
	state.grounded = grounded
	return state


## Car at heading 0 whose road-plane velocity has the requested signed slip
## angle and ground-speed magnitude. Positive slip points right of the nose.
func make_car_with_slip(slip_deg: float, speed_m_s: float):
	var angle := deg_to_rad(slip_deg)
	var state := CarStateScript.new()
	state.velocity_m_s = Vector2(sin(angle), cos(angle)) * speed_m_s
	return state


func command(
	steer: float = 0.0,
	throttle: float = 0.0,
	brake: float = 0.0,
	handbrake: float = 0.0
):
	return DriverCommandScript.create(steer, throttle, brake, handbrake)


func fresh_drift_state():
	return DriftModel.State.new()


## One real model evaluation.
func advance(car, cmd, drift, tuning, impact_speed_loss_m_s: float = 0.0):
	return DriftModel.propose(
		car, cmd, drift, tuning, DriftModel.DT, impact_speed_loss_m_s
	)


## Run a command schedule against one fixed car, feeding each proposal state
## into the next call. Returns every proposal (null on refusal).
func run_commands(car, commands: Array, drift, tuning, ticks_each: int = 1) -> Array:
	var proposals := []
	for cmd in commands:
		for _tick in range(ticks_each):
			var proposal = advance(car, cmd, drift, tuning)
			proposals.append(proposal)
			if proposal != null:
				drift = proposal.state
	return proposals


# --- Snapshots --------------------------------------------------------------


func snapshot_state(state) -> Dictionary:
	if state == null:
		return {}
	return {
		"phase": int(state.phase),
		"phase_time_s": state.phase_time_s,
		"drift_sign": state.drift_sign,
		"drift_blend": state.drift_blend,
		"previous_handbrake": state.previous_handbrake,
		"previous_brake": state.previous_brake,
		"unwind_hold_s": state.unwind_hold_s,
		"low_speed_hold_s": state.low_speed_hold_s,
		"airborne_time_s": state.airborne_time_s,
		"airborne_start_blend": state.airborne_start_blend,
		"recovery_start_blend": state.recovery_start_blend,
	}


func snapshot_tuning(tuning) -> Dictionary:
	if tuning == null:
		return {}
	return {
		"min_entry_forward_speed_m_s": tuning.min_entry_forward_speed_m_s,
		"entry_steer_min": tuning.entry_steer_min,
		"handbrake_tap_min": tuning.handbrake_tap_min,
		"assist_brake_tap_min": tuning.assist_brake_tap_min,
		"entry_blend_time_s": tuning.entry_blend_time_s,
		"recovery_blend_time_s": tuning.recovery_blend_time_s,
		"unwind_steer_max": tuning.unwind_steer_max,
		"unwind_hold_s": tuning.unwind_hold_s,
		"sustain_exit_speed_m_s": tuning.sustain_exit_speed_m_s,
		"low_speed_hold_s": tuning.low_speed_hold_s,
		"impact_exit_speed_loss_m_s": tuning.impact_exit_speed_loss_m_s,
		"target_slip_deg_min": tuning.target_slip_deg_min,
		"target_slip_deg_max": tuning.target_slip_deg_max,
		"stability_start_deg": tuning.stability_start_deg,
		"stability_full_deg": tuning.stability_full_deg,
		"stability_floor_factor": tuning.stability_floor_factor,
		"airborne_drain_time_s": tuning.airborne_drain_time_s,
		"assist_mode": int(tuning.assist_mode),
	}


func snapshot_car(car) -> Dictionary:
	if car == null:
		return {}
	return {
		"position_m": car.position_m,
		"velocity_m_s": car.velocity_m_s,
		"heading_rad": car.heading_rad,
		"grounded": car.grounded,
	}


func snapshot_proposal(proposal) -> Dictionary:
	if proposal == null:
		return {}
	return {
		"phase": int(proposal.phase),
		"drift_blend": proposal.drift_blend,
		"stability_factor": proposal.stability_factor,
		"event": int(proposal.event),
		"drift_sign": proposal.drift_sign,
		"slip_deg": proposal.slip_deg,
		"useful_slip": proposal.useful_slip,
		"rewards_suppressed": proposal.rewards_suppressed,
		"state": snapshot_state(proposal.state),
	}


func snapshots_equal(a: Dictionary, b: Dictionary) -> bool:
	return a == b
