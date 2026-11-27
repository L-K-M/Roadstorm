class_name DriveLabChecks
extends RefCounted
## Assertion collectors and explicit fixtures for the M1 one-car drive lab.
##
## This helper never re-implements motor or adapter math. It builds explicit
## tuning, state and command values and compares measured invariants from the
## real laboratory scene. Failures are collected so the driver can emit
## machine-readable results and control its exit code.

const AdapterScript := preload("res://src/simulation/motor_body_adapter.gd")
const ArcadeMotorScript := preload("res://src/simulation/arcade_motor.gd")
const CarStateScript := preload("res://src/simulation/car_state.gd")
const DriverCommandScript := preload("res://src/simulation/driver_command.gd")

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


func check_exact_float(actual: float, expected: float, message: String) -> void:
	checks += 1
	if actual != expected:
		failures.append("%s (actual=%s expected=%s)" % [message, actual, expected])


func check_vector_close(
	actual: Vector3,
	expected: Vector3,
	tolerance: float,
	message: String
) -> void:
	checks += 1
	if actual.distance_to(expected) > tolerance:
		failures.append(
			"%s (actual=%s expected=%s tol=%s)" % [message, actual, expected, tolerance]
		)


func check_number_finite(value: float, message: String) -> void:
	checks += 1
	if is_nan(value) or is_inf(value):
		failures.append("%s (value=%s)" % [message, value])


# --- Fixtures --------------------------------------------------------------


func make_config() -> MotorBodyAdapter.Config:
	var config := MotorBodyAdapter.Config.new()
	config.hull_size_m = Vector3(1.8, 1.0, 3.8)
	config.substep_max_length_m = 0.25
	config.max_substeps = 16
	config.sweep_margin_m = 0.0
	config.commit_safe_margin_m = 0.0
	config.envelope_epsilon_m = 1e-6
	config.contact_stop_epsilon_m = 1e-6
	config.wall_normal_max_up_alignment = 0.5
	config.wall_restitution = 0.0
	config.wall_tangential_keep = 1.0
	return config


func make_tuning() -> ArcadeMotor.MotorTuning:
	var curve: Array = [
		ArcadeMotorScript.SpeedAccelerationPoint.make(0.0, 8.0),
		ArcadeMotorScript.SpeedAccelerationPoint.make(10.0, 6.5),
		ArcadeMotorScript.SpeedAccelerationPoint.make(20.0, 4.0),
		ArcadeMotorScript.SpeedAccelerationPoint.make(32.0, 1.2),
		ArcadeMotorScript.SpeedAccelerationPoint.make(45.0, 0.0),
	]
	return ArcadeMotorScript.MotorTuning.make(
		curve, 12.0, 0.0, 0.05, 0.05, 1.5, 5.0, 1.0, 0.3, 4.0, 8.0
	)


func make_state(position := Vector2.ZERO, velocity := Vector2.ZERO, heading := 0.0):
	var state := CarStateScript.new()
	state.position_m = position
	state.velocity_m_s = velocity
	state.heading_rad = heading
	state.grounded = true
	return state


func idle_command() -> DriverCommand:
	return DriverCommandScript.create(0.0, 0.0, 0.0, 0.0)


func throttle_command(amount := 1.0) -> DriverCommand:
	return DriverCommandScript.create(0.0, amount, 0.0, 0.0)


func brake_command(amount := 1.0) -> DriverCommand:
	return DriverCommandScript.create(0.0, 0.0, amount, 0.0)


func steer_command(steer: float, throttle := 0.0) -> DriverCommand:
	return DriverCommandScript.create(steer, throttle, 0.0, 0.0)


# --- Snapshots and geometry helpers ---------------------------------------


func snapshot_state(state) -> Dictionary:
	if state == null:
		return {}
	return {
		"position_m": state.position_m,
		"velocity_m_s": state.velocity_m_s,
		"heading_rad": state.heading_rad,
		"grounded": state.grounded,
		"reverse_engaged": state.reverse_engaged,
		"reverse_hold_s": state.reverse_hold_s,
	}


func check_state_unchanged(state, snapshot: Dictionary, message: String) -> void:
	check(state.position_m == snapshot["position_m"], message + ": position unchanged")
	check(state.velocity_m_s == snapshot["velocity_m_s"], message + ": velocity unchanged")
	check_exact_float(state.heading_rad, snapshot["heading_rad"], message + ": heading unchanged")
	check(state.grounded == snapshot["grounded"], message + ": grounded unchanged")
	check(
		state.reverse_engaged == snapshot["reverse_engaged"],
		message + ": reverse flag unchanged"
	)
	check_exact_float(
		state.reverse_hold_s,
		snapshot["reverse_hold_s"],
		message + ": reverse hold unchanged"
	)


func snapshot_command(command) -> Dictionary:
	if command == null:
		return {}
	return {
		"steer": command.steer,
		"throttle": command.throttle,
		"brake": command.brake,
		"handbrake": command.handbrake,
		"reset_requested": command.reset_requested,
	}


func check_command_unchanged(command, snapshot: Dictionary, message: String) -> void:
	check_exact_float(command.steer, snapshot["steer"], message + ": steer unchanged")
	check_exact_float(command.throttle, snapshot["throttle"], message + ": throttle unchanged")
	check_exact_float(command.brake, snapshot["brake"], message + ": brake unchanged")
	check_exact_float(command.handbrake, snapshot["handbrake"], message + ": handbrake unchanged")
	check(
		command.reset_requested == snapshot["reset_requested"],
		message + ": reset flag unchanged"
	)


## Lowest world Y of an oriented box at `transform` with `size` extents.
func aabb_min_y(transform: Transform3D, size: Vector3) -> float:
	var half := size * 0.5
	var basis := transform.basis
	return transform.origin.y - (
		absf(basis.x.y) * half.x
		+ absf(basis.y.y) * half.y
		+ absf(basis.z.y) * half.z
	)
