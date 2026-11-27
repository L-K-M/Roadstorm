class_name BodyLabChecks
extends RefCounted
## Assertion collectors and explicit laboratory fixtures for the M1.1
## motor/body adapter slice.
##
## This helper never re-implements adapter or motor math. It builds explicit
## tuning/state/command values, calls the real classes, and compares measured
## invariants. Failures are collected so the driver can emit machine-readable
## results and control its exit code.

const AdapterScript = preload("res://src/simulation/motor_body_adapter.gd")
const ArcadeMotorScript = preload("res://src/simulation/arcade_motor.gd")
const CarStateScript = preload("res://src/simulation/car_state.gd")
const DriverCommandScript = preload("res://src/simulation/driver_command.gd")

## Support height of the body origin above the flat ground plane in the lab.
const BODY_SUPPORT_Y := 0.55

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


func check_state_mapping(
	body: CharacterBody3D,
	state: CarState,
	tolerance: float,
	message: String
) -> void:
	# Fixed road-plane to world mapping: CarState x -> world +X,
	# CarState y -> world -Z. The support height is caller-owned.
	check_close(body.global_position.x, state.position_m.x, tolerance, message + ": x")
	check_close(body.global_position.z, -state.position_m.y, tolerance, message + ": z")


func snapshot_state(state: CarState) -> Dictionary:
	return {
		"position_m": state.position_m,
		"velocity_m_s": state.velocity_m_s,
		"heading_rad": state.heading_rad,
		"grounded": state.grounded,
		"reverse_engaged": state.reverse_engaged,
		"reverse_hold_s": state.reverse_hold_s,
	}


func check_state_unchanged(state: CarState, snapshot: Dictionary, message: String) -> void:
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


func snapshot_command(command: DriverCommand) -> Dictionary:
	return {
		"steer": command.steer,
		"throttle": command.throttle,
		"brake": command.brake,
		"handbrake": command.handbrake,
		"reset_requested": command.reset_requested,
	}


func check_command_unchanged(command: DriverCommand, snapshot: Dictionary, message: String) -> void:
	check_exact_float(command.steer, snapshot["steer"], message + ": steer unchanged")
	check_exact_float(command.throttle, snapshot["throttle"], message + ": throttle unchanged")
	check_exact_float(command.brake, snapshot["brake"], message + ": brake unchanged")
	check_exact_float(command.handbrake, snapshot["handbrake"], message + ": handbrake unchanged")
	check(
		command.reset_requested == snapshot["reset_requested"],
		message + ": reset flag unchanged"
	)


## Laboratory adapter config. Every field is written explicitly here so the
## test records the exact envelope and contact-response values it used; these
## are not frozen product coefficients.
func make_config() -> MotorBodyAdapter.Config:
	var config := MotorBodyAdapter.Config.new()
	config.hull_size_m = Vector3(1.8, 1.0, 3.8)
	config.substep_max_length_m = 0.25
	config.max_substeps = 16
	config.sweep_margin_m = 0.0
	config.commit_safe_margin_m = 0.0
	config.envelope_epsilon_m = 1e-6
	config.contact_stop_epsilon_m = 1e-6
	config.orientation_contact_tolerance_m = AdapterScript.ORIENTATION_CONTACT_TOLERANCE_M
	config.wall_normal_max_up_alignment = 0.5
	config.wall_restitution = 0.0
	config.wall_tangential_keep = 1.0
	return config


func make_constrained_config(max_substeps: int) -> MotorBodyAdapter.Config:
	var config := make_config()
	config.max_substeps = max_substeps
	return config


## Config sitting exactly on every absolute work/epsilon bound. Used as a
## positive control that the conservative caps still admit the 65 m/s case.
func make_absolute_limit_config() -> MotorBodyAdapter.Config:
	var config := make_config()
	config.substep_max_length_m = AdapterScript.ABSOLUTE_MAX_SUBSTEP_LENGTH_M
	config.max_substeps = AdapterScript.ABSOLUTE_MAX_SUBSTEPS
	config.envelope_epsilon_m = minf(
		config.substep_max_length_m * AdapterScript.MAX_ENVELOPE_EPSILON_FRACTION,
		AdapterScript.MAX_ENVELOPE_EPSILON_M
	)
	config.contact_stop_epsilon_m = (
		config.substep_max_length_m * AdapterScript.MAX_CONTACT_STOP_EPSILON_FRACTION
	)
	return config


## Explicit laboratory tuning: modest acceleration, zero drag, grip yaw and
## lateral damping. These are test inputs, not project handling.
func make_tuning() -> ArcadeMotorScript.MotorTuning:
	var curve := []
	curve.append(ArcadeMotorScript.SpeedAccelerationPoint.make(0.0, 8.0))
	curve.append(ArcadeMotorScript.SpeedAccelerationPoint.make(20.0, 4.0))
	curve.append(ArcadeMotorScript.SpeedAccelerationPoint.make(60.0, 0.0))
	return ArcadeMotorScript.MotorTuning.make(
		curve, 12.0, 0.0, 0.0, 0.12, 1.6, 4.0, 1.0, 0.3, 4.0, 8.0
	)


func make_idle_command() -> DriverCommand:
	return DriverCommandScript.create(0.0, 0.0, 0.0, 0.0, false)


func make_throttle_command(amount: float = 1.0) -> DriverCommand:
	return DriverCommandScript.create(0.0, amount, 0.0, 0.0, false)


func make_steer_command(steer: float, throttle: float = 0.0) -> DriverCommand:
	return DriverCommandScript.create(steer, throttle, 0.0, 0.0, false)


func make_brake_command(amount: float) -> DriverCommand:
	return DriverCommandScript.create(0.0, 0.0, amount, 0.0, false)


func make_state(
	position := Vector2(0.0, 0.0),
	velocity := Vector2(0.0, 0.0),
	heading := 0.0,
	grounded := true
) -> CarState:
	var state := CarStateScript.new()
	state.position_m = position
	state.velocity_m_s = velocity
	state.heading_rad = heading
	state.grounded = grounded
	return state


## Hull vertex farthest along `direction` (world space). Used to prove the
## committed hull never crosses a wall plane.
func box_support_point(
	transform: Transform3D,
	size: Vector3,
	direction: Vector3
) -> Vector3:
	var local := transform.basis.inverse() * direction
	var offset := Vector3(
		(sign(local.x) if local.x != 0.0 else 1.0) * size.x * 0.5,
		(sign(local.y) if local.y != 0.0 else 1.0) * size.y * 0.5,
		(sign(local.z) if local.z != 0.0 else 1.0) * size.z * 0.5
	)
	return transform.origin + transform.basis * offset
