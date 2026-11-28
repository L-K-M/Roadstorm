class_name WallImpactLabChecks
extends RefCounted
## Assertion collectors and explicit synthetic fixtures for the M1.8
## wall-impact publication laboratory.
##
## This helper never re-implements producer, adapter or builder math. It
## constructs explicit `MotorBodyAdapter.Result`/`Config` records, calls the
## real `WallImpactProducer`, the real `ImpactEvent.Builder` and the real
## `ImpactEvent.Ledger`, and compares measured invariants against independently
## authored expectations. Failures are collected so the driver can emit
## machine-readable results and control its exit code.
##
## The Result fixtures here are synthetic. They prove the producer's
## publication contract; they are not proof that a witness came from a real
## committed physics response. The real pinned-Jolt integration is a separate
## driver case.

const AdapterScript = preload("res://src/simulation/motor_body_adapter.gd")
const CarStateScript = preload("res://src/simulation/car_state.gd")

## Laboratory hull, identical to the body laboratory default. Explicit so the
## region expectations below are readable.
const HULL_SIZE_M := Vector3(1.8, 1.0, 3.8)
const HALF_EXTENTS_M := HULL_SIZE_M * 0.5

const PRIMARY_CAR_ID := "car-wall-alpha"
const EVENT_ID := "evt-wall-0001"
const OTHER_EVENT_ID := "evt-wall-0002"
const CONTACT_ID := "contact-wall-0001"
const TICK_INDEX := 42

## Severity/oracle tolerances. These compare exact float arithmetic on small
## laboratory values, so they stay far tighter than any physical measurement.
const FLOAT_TOLERANCE := 1e-9
## Vector tolerances for reconstructed transforms and published vectors.
const VECTOR_TOLERANCE := 1e-6
## Stable-norm comparisons for oblique severity values.
const NORM_TOLERANCE := 1e-6

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


func check_vector_finite(value: Vector3, message: String) -> void:
	checks += 1
	if not (is_finite(value.x) and is_finite(value.y) and is_finite(value.z)):
		failures.append("%s (%s)" % [message, value])


func check_string(actual: String, expected: String, message: String) -> void:
	checks += 1
	if actual != expected:
		failures.append("%s (actual=%s expected=%s)" % [message, actual, expected])


func check_reason_contains(reason: String, fragment: String, message: String) -> void:
	checks += 1
	if not reason.contains(fragment):
		failures.append(
			"%s (reason=%s expected fragment=%s)" % [message, reason, fragment]
		)


# --- Fixtures -------------------------------------------------------------


## Valid laboratory config, written field by field like the body laboratory.
func make_config() -> MotorBodyAdapter.Config:
	var config := MotorBodyAdapter.Config.new()
	config.hull_size_m = HULL_SIZE_M
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


## Synthetic committed wall-witness Result.
##
## The collision-time frame is `basis_from_heading(heading_rad)` at
## `frame_origin`; the world point is the frame applied to `local_point`, so
## `frame.affine_inverse() * world_point` recovers `local_point`. The committed
## planar velocity is the post velocity mapped through the fixed road-plane
## mapping, matching what the real adapter publishes. Every witness flag the
## producer requires is set explicitly.
func make_result(
	local_point: Vector3 = Vector3(0.0, 0.0, -HALF_EXTENTS_M.z),
	hull_size_m: Vector3 = HULL_SIZE_M,
	heading_rad: float = 0.0,
	frame_origin: Vector3 = Vector3.ZERO,
	pre_velocity_world_m_s: Vector3 = Vector3(0.0, 0.0, -20.0),
	post_velocity_world_m_s: Vector3 = Vector3.ZERO,
	wall_normal_world_m: Vector3 = Vector3(0.0, 0.0, 1.0),
	accepted_motion_m: Vector3 = Vector3(0.25, 0.0, 0.1)
) -> MotorBodyAdapter.Result:
	var result := MotorBodyAdapter.Result.new()
	result.status = MotorBodyAdapter.Status.COMMITTED
	result.committed_state = CarStateScript.new()
	result.committed_state.position_m = Vector2(0.0, 0.0)
	result.committed_state.velocity_m_s = (
		AdapterScript.world_vector_to_road(post_velocity_world_m_s)
	)
	result.committed_state.heading_rad = heading_rad
	result.wall_contact_normal = wall_normal_world_m
	result.wall_contact_transform = Transform3D(
		AdapterScript.basis_from_heading(heading_rad), frame_origin
	)
	result.wall_contact_point = result.wall_contact_transform * local_point
	result.has_wall_contact_point = true
	result.wall_pre_response_velocity_world_m_s = pre_velocity_world_m_s
	result.wall_post_response_velocity_world_m_s = post_velocity_world_m_s
	result.has_wall_response_witness = true
	result.wall_contact = true
	result.contact = true
	result.accepted_motion_m = accepted_motion_m
	result.proposed_motion_m = accepted_motion_m
	result.predicted_motion_m = accepted_motion_m
	result.test_move_predicted_motion_m = accepted_motion_m
	result.remainder_m = 0.0
	result.contact_limited_remainder = false
	result.substeps = 1
	result.start_transform = result.wall_contact_transform
	result.committed_transform = result.wall_contact_transform
	return result


## Compact positional form of `make_result()` for the common laboratory case:
## hull, identity flags and committed velocity follow from the four physical
## arguments. Kept here so callers never rely on GDScript keyword arguments,
## which the language does not have.
func make_witness(
	local_point: Vector3,
	pre_velocity_world_m_s: Vector3 = Vector3(0.0, 0.0, -20.0),
	post_velocity_world_m_s: Vector3 = Vector3.ZERO,
	wall_normal_world_m: Vector3 = Vector3(0.0, 0.0, 1.0),
	accepted_motion_m: Vector3 = Vector3(0.25, 0.0, 0.1)
) -> MotorBodyAdapter.Result:
	return make_result(
		local_point, HULL_SIZE_M, 0.0, Vector3.ZERO,
		pre_velocity_world_m_s, post_velocity_world_m_s,
		wall_normal_world_m, accepted_motion_m
	)


# --- Snapshots ------------------------------------------------------------


func snapshot_config(config: MotorBodyAdapter.Config) -> Dictionary:
	return {
		"hull_size_m": config.hull_size_m,
		"substep_max_length_m": config.substep_max_length_m,
		"max_substeps": config.max_substeps,
		"sweep_margin_m": config.sweep_margin_m,
		"commit_safe_margin_m": config.commit_safe_margin_m,
		"envelope_epsilon_m": config.envelope_epsilon_m,
		"contact_stop_epsilon_m": config.contact_stop_epsilon_m,
		"orientation_contact_tolerance_m": config.orientation_contact_tolerance_m,
		"wall_normal_max_up_alignment": config.wall_normal_max_up_alignment,
		"wall_restitution": config.wall_restitution,
		"wall_tangential_keep": config.wall_tangential_keep,
	}


func snapshot_state(state: CarState) -> Dictionary:
	if state == null:
		return {}
	return {
		"position_m": state.position_m,
		"velocity_m_s": state.velocity_m_s,
		"heading_rad": state.heading_rad,
		"grounded": state.grounded,
		"reverse_engaged": state.reverse_engaged,
		"reverse_hold_s": state.reverse_hold_s,
		"gear_index": state.gear_index,
		"drift_active": state.drift_active,
		"drift_timer_s": state.drift_timer_s,
		"drift_slip_deg": state.drift_slip_deg,
		"surge_cooldown_s": state.surge_cooldown_s,
		"drafting_active": state.drafting_active,
		"contact_immunity_s": state.contact_immunity_s,
		"valid_progress_m": state.valid_progress_m,
	}


## Every producer-relevant and neighbouring Result field, so a purity check
## can detect an unexpected write anywhere the result is read or copied.
func snapshot_result(result: MotorBodyAdapter.Result) -> Dictionary:
	if result == null:
		return {}
	return {
		"status": result.status,
		"rejection_reason": result.rejection_reason,
		"proposed_state_null": result.proposed_state == null,
		"committed_state": snapshot_state(result.committed_state),
		"proposed_motion_m": result.proposed_motion_m,
		"predicted_motion_m": result.predicted_motion_m,
		"test_move_predicted_motion_m": result.test_move_predicted_motion_m,
		"accepted_motion_m": result.accepted_motion_m,
		"remainder_m": result.remainder_m,
		"contact_limited_remainder": result.contact_limited_remainder,
		"prediction_commit_discrepancy_m": result.prediction_commit_discrepancy_m,
		"test_move_commit_discrepancy_m": result.test_move_commit_discrepancy_m,
		"heading_constrained": result.heading_constrained,
		"contact": result.contact,
		"wall_contact": result.wall_contact,
		"wall_contact_normal": result.wall_contact_normal,
		"wall_contact_point": result.wall_contact_point,
		"has_wall_contact_point": result.has_wall_contact_point,
		"has_wall_response_witness": result.has_wall_response_witness,
		"wall_pre_response_velocity_world_m_s": (
			result.wall_pre_response_velocity_world_m_s
		),
		"wall_post_response_velocity_world_m_s": (
			result.wall_post_response_velocity_world_m_s
		),
		"wall_contact_transform": result.wall_contact_transform,
		"contact_normal": result.contact_normal,
		"contact_point": result.contact_point,
		"substeps": result.substeps,
		"start_transform": result.start_transform,
		"committed_transform": result.committed_transform,
		"motor_yaw_delta_rad": result.motor_yaw_delta_rad,
	}
