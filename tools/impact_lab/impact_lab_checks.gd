class_name ImpactLabChecks
extends RefCounted
## Assertion collectors and independent fixtures for the M1.8 impact-event
## contract laboratory.
##
## This helper never re-implements the builder, ledger or validation math. It
## builds explicit event fixtures, calls the real `ImpactEvent.Builder` and
## `ImpactEvent.Ledger`, and compares measured invariants against independently
## authored expectations. Failures are collected so the driver can emit
## machine-readable results and control its exit code.

const ADAPTER_SOURCE_PATH := "res://src/simulation/motor_body_adapter.gd"
const EVENT_SOURCE_PATH := "res://src/simulation/impact_event.gd"

## Identifiers for the shared fixtures. Stable and unique within a run.
const FRONT_EVENT_ID := "evt-front-0001"
const REAR_EVENT_ID := "evt-rear-0002"
const CAR_CAR_EVENT_ID := "evt-car-car-0003"
const PRIMARY_CAR_ID := "car-alpha"
const OTHER_CAR_ID := "car-beta"
const WALL_TICK := 42
const CAR_CAR_TICK := 7

## Expected front-wall fixture values, authored here rather than read back from
## the builder so a field mix-up cannot pass both sides.
const FRONT_WORLD_POINT := Vector3(0.80, 0.60, 1.90)
const FRONT_LOCAL_POINT := Vector3(0.30, 0.35, -1.90)
const FRONT_NORMAL := Vector3(-1.0, 0.0, 0.0)
const FRONT_SEVERITY := 4.25
const FRONT_POST_VELOCITY := Vector3(12.5, 0.0, -3.0)
const FRONT_IMPARTED_MOTION := Vector3(0.12, -0.01, 0.40)

## Tolerances for pure float/vector equality. These are contract records, not
## physics measurements, so they are deliberately tight.
const FLOAT_TOLERANCE := 1e-9
const VECTOR_TOLERANCE := 1e-9

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


func check_string(actual: String, expected: String, message: String) -> void:
	checks += 1
	if actual != expected:
		failures.append("%s (actual=%s expected=%s)" % [message, actual, expected])


# --- Fixtures -------------------------------------------------------------


func make_front_builder() -> ImpactEvent.Builder:
	var builder := ImpactEvent.Builder.new()
	builder.event_id = FRONT_EVENT_ID
	builder.tick_index = WALL_TICK
	builder.primary_car_id = PRIMARY_CAR_ID
	builder.other_car_id = ""
	builder.contact_point_world_m = FRONT_WORLD_POINT
	builder.contact_point_local_m = FRONT_LOCAL_POINT
	builder.contact_normal_world_m = FRONT_NORMAL
	builder.severity_m_s = FRONT_SEVERITY
	builder.post_contact_velocity_world_m_s = FRONT_POST_VELOCITY
	builder.imparted_motion_m = FRONT_IMPARTED_MOTION
	builder.region = ImpactEvent.ContactRegion.FRONT
	builder.source_committed = true
	return builder


func make_rear_builder() -> ImpactEvent.Builder:
	var builder := make_front_builder()
	builder.event_id = REAR_EVENT_ID
	builder.other_car_id = ""
	builder.contact_point_world_m = Vector3(-0.50, 0.60, -1.80)
	builder.contact_point_local_m = Vector3(-0.20, 0.35, 1.80)
	builder.contact_normal_world_m = Vector3(1.0, 0.0, 0.0)
	builder.severity_m_s = 2.50
	builder.post_contact_velocity_world_m_s = Vector3(-6.0, 0.0, 2.0)
	builder.imparted_motion_m = Vector3(-0.08, 0.0, -0.25)
	builder.region = ImpactEvent.ContactRegion.REAR
	return builder


func make_car_car_builder() -> ImpactEvent.Builder:
	var builder := make_front_builder()
	builder.event_id = CAR_CAR_EVENT_ID
	builder.tick_index = CAR_CAR_TICK
	builder.primary_car_id = PRIMARY_CAR_ID
	builder.other_car_id = OTHER_CAR_ID
	builder.contact_point_world_m = Vector3(0.90, 0.60, 0.20)
	builder.contact_point_local_m = Vector3(0.90, 0.35, -0.20)
	builder.contact_normal_world_m = Vector3(-1.0, 0.0, 0.0)
	builder.severity_m_s = 3.00
	builder.post_contact_velocity_world_m_s = Vector3(9.0, 0.0, 4.0)
	builder.imparted_motion_m = Vector3(0.20, 0.0, 0.10)
	builder.region = ImpactEvent.ContactRegion.RIGHT
	return builder


func make_ledger(
	per_tick_capacity: int = ImpactEvent.Ledger.DEFAULT_PER_TICK_CAPACITY,
	max_retained_ticks: int = ImpactEvent.Ledger.DEFAULT_MAX_RETAINED_TICKS
) -> ImpactEvent.Ledger:
	return ImpactEvent.Ledger.new(per_tick_capacity, max_retained_ticks)


## Minimal valid lab event with an explicit identity and tick, used by the
## capacity and duplicate cases.
func make_lab_event(event_id: String, tick_index: int) -> ImpactEvent:
	var builder := make_front_builder()
	builder.event_id = event_id
	builder.tick_index = tick_index
	builder.severity_m_s = 1.0 + float(tick_index)
	return builder.build()


# --- Source inspection helpers --------------------------------------------


func read_source(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


## Drops full-line comments (including `##` documentation) so contract scans
## inspect executable source rather than prose. Inline comments remain; the
## owned module keeps them free of the scanned tokens.
func strip_full_line_comments(source: String) -> String:
	var kept := ""
	for line in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		kept += line + "\n"
	return kept


# --- Shared field assertions ----------------------------------------------


func check_front_event_fields(event: ImpactEvent) -> void:
	check_string(event.event_id, FRONT_EVENT_ID, "front.event_id")
	check(event.tick_index == WALL_TICK, "front.tick_index")
	check_string(event.primary_car_id, PRIMARY_CAR_ID, "front.primary_car_id")
	check(not event.has_other_car(), "front.has_no_other_car")
	check_vector_close(
		event.contact_point_world_m, FRONT_WORLD_POINT, VECTOR_TOLERANCE,
		"front.world_contact_point"
	)
	check_vector_close(
		event.contact_point_local_m, FRONT_LOCAL_POINT, VECTOR_TOLERANCE,
		"front.local_contact_point"
	)
	check_vector_close(
		event.contact_normal_world_m, FRONT_NORMAL, VECTOR_TOLERANCE,
		"front.contact_normal"
	)
	check_exact_float(event.severity_m_s, FRONT_SEVERITY, "front.severity")
	check_vector_close(
		event.post_contact_velocity_world_m_s, FRONT_POST_VELOCITY, VECTOR_TOLERANCE,
		"front.post_contact_velocity"
	)
	check_vector_close(
		event.imparted_motion_m, FRONT_IMPARTED_MOTION, VECTOR_TOLERANCE,
		"front.imparted_motion"
	)
	check(event.region == ImpactEvent.ContactRegion.FRONT, "front.region")
	check_string(event.region_name(), "front", "front.region_name")
	check(event.is_committed(), "front.is_committed")
	check(event.is_valid(), "front.is_valid")
