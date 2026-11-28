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
const CAR_CAR_OTHER_EVENT_ID := "evt-car-car-0004"
const PRIMARY_CAR_ID := "car-alpha"
const OTHER_CAR_ID := "car-beta"
const WALL_TICK := 42
const CAR_CAR_TICK := 7
## Shared identity linking the two per-primary records of one car-car contact.
## Distinct from either record's `event_id`, which is per perspective.
const CAR_CAR_CONTACT_ID := "contact-car-car-0003"

## Counterexample identities for the pairing rule. `car-gamma`/`car-delta` are a
## second, unrelated car pair that shares the car-car `contact_id` and tick, so
## only reciprocal participant IDs can tell it apart from a real pair.
const UNRELATED_PRIMARY_CAR_ID := "car-gamma"
const UNRELATED_OTHER_CAR_ID := "car-delta"
const UNRELATED_PAIR_EVENT_ID := "evt-unrelated-pair-0005"
const WALL_LINKED_ALPHA_EVENT_ID := "evt-wall-linked-alpha-0006"
const WALL_LINKED_BETA_EVENT_ID := "evt-wall-linked-beta-0007"
const NONRECIPROCAL_EVENT_ID := "evt-nonreciprocal-0008"
const DUPLICATE_PERSPECTIVE_EVENT_ID := "evt-car-car-duplicate-0009"

## The duplicate-perspective retry reuses the retained pair but allocates a new
## event ID, which is exactly the producer mistake the ledger must refuse.
const DUPLICATE_PERSPECTIVE_SEVERITY := 4.50

## Ambiguous-separator pair control. The contract forbids no character in a
## semantic ID, so these two valid perspectives encode identically under any
## single-separator join of (contact_id, primary_car_id): the first is
## ("a\u001fb", "c") and the second is ("a", "b\u001fc"). A separator-joined
## pair key would refuse the second record and lose it; an unambiguous key
## must publish both.
const AMBIGUOUS_SEPARATOR := "\u001f"
const AMBIGUOUS_CONTACT_A := "a" + AMBIGUOUS_SEPARATOR + "b"
const AMBIGUOUS_CONTACT_B := "a"
const AMBIGUOUS_PRIMARY_A := "c"
const AMBIGUOUS_PRIMARY_B := "b" + AMBIGUOUS_SEPARATOR + "c"
const AMBIGUOUS_OTHER_CAR_ID := "car-epsilon"
const AMBIGUOUS_FIRST_EVENT_ID := "evt-ambiguous-0001"
const AMBIGUOUS_SECOND_EVENT_ID := "evt-ambiguous-0002"
const AMBIGUOUS_COMPLEMENT_EVENT_ID := "evt-ambiguous-0003"
const AMBIGUOUS_RETRY_EVENT_ID := "evt-ambiguous-retry-0004"
const AMBIGUOUS_RETRY_B_EVENT_ID := "evt-ambiguous-retry-0005"
const AMBIGUOUS_TICK := 11
const AMBIGUOUS_SEVERITY := 5.25
const AMBIGUOUS_RETRY_SEVERITY := 6.75

## Expected front-wall fixture values, authored here rather than read back from
## the builder so a field mix-up cannot pass both sides.
const FRONT_WORLD_POINT := Vector3(0.80, 0.60, 1.90)
const FRONT_LOCAL_POINT := Vector3(0.30, 0.35, -1.90)
const FRONT_NORMAL := Vector3(-1.0, 0.0, 0.0)
const FRONT_SEVERITY := 4.25
const FRONT_POST_VELOCITY := Vector3(12.5, 0.0, -3.0)
const FRONT_IMPARTED_MOTION := Vector3(0.12, -0.01, 0.40)

## Expected values for the opposite (car-beta) perspective of the same
## car-car contact. The world point is shared; the local point, normal and
## imparted motion are mirrored because they describe the other car.
const CAR_CAR_WORLD_POINT := Vector3(0.90, 0.60, 0.20)
const CAR_CAR_OTHER_LOCAL_POINT := Vector3(-0.90, 0.35, 0.20)
const CAR_CAR_OTHER_NORMAL := Vector3(1.0, 0.0, 0.0)
const CAR_CAR_OTHER_SEVERITY := 3.00
const CAR_CAR_OTHER_POST_VELOCITY := Vector3(-9.0, 0.0, 4.0)
const CAR_CAR_OTHER_IMPARTED_MOTION := Vector3(-0.20, 0.0, 0.10)

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


func check_relative_close(
	actual: float,
	expected: float,
	relative_tolerance: float,
	message: String
) -> void:
	checks += 1
	var scale := absf(expected)
	if is_nan(actual) or is_inf(actual) or absf(actual - expected) > relative_tolerance * scale:
		failures.append(
			"%s (actual=%s expected=%s rel_tol=%s)" % [
				message, actual, expected, relative_tolerance,
			]
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


## Every component finite. `Vector3` has no whole-vector finiteness test, and a
## component that became INF or NaN is invisible to `distance_to` comparisons
## against a finite expectation.
func check_finite_vector(actual: Vector3, message: String) -> void:
	checks += 1
	if not (is_finite(actual.x) and is_finite(actual.y) and is_finite(actual.z)):
		failures.append("%s (actual=%s)" % [message, actual])


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
	builder.contact_id = CAR_CAR_CONTACT_ID
	builder.contact_point_world_m = CAR_CAR_WORLD_POINT
	builder.contact_point_local_m = Vector3(0.90, 0.35, -0.20)
	builder.contact_normal_world_m = Vector3(-1.0, 0.0, 0.0)
	builder.severity_m_s = 3.00
	builder.post_contact_velocity_world_m_s = Vector3(9.0, 0.0, 4.0)
	builder.imparted_motion_m = Vector3(0.20, 0.0, 0.10)
	builder.region = ImpactEvent.ContactRegion.RIGHT
	return builder


## The complementary record for the other car in the same physical contact.
## Authored independently rather than mirrored in code, so a field mix-up
## cannot pass both sides.
func make_car_car_other_builder() -> ImpactEvent.Builder:
	var builder := make_front_builder()
	builder.event_id = CAR_CAR_OTHER_EVENT_ID
	builder.tick_index = CAR_CAR_TICK
	builder.primary_car_id = OTHER_CAR_ID
	builder.other_car_id = PRIMARY_CAR_ID
	builder.contact_id = CAR_CAR_CONTACT_ID
	builder.contact_point_world_m = CAR_CAR_WORLD_POINT
	builder.contact_point_local_m = CAR_CAR_OTHER_LOCAL_POINT
	builder.contact_normal_world_m = CAR_CAR_OTHER_NORMAL
	builder.severity_m_s = CAR_CAR_OTHER_SEVERITY
	builder.post_contact_velocity_world_m_s = CAR_CAR_OTHER_POST_VELOCITY
	builder.imparted_motion_m = CAR_CAR_OTHER_IMPARTED_MOTION
	builder.region = ImpactEvent.ContactRegion.LEFT
	return builder


func make_ledger(
	per_tick_capacity: int = ImpactEvent.Ledger.DEFAULT_PER_TICK_CAPACITY,
	max_retained_ticks: int = ImpactEvent.Ledger.DEFAULT_MAX_RETAINED_TICKS
) -> ImpactEvent.Ledger:
	return ImpactEvent.Ledger.new(per_tick_capacity, max_retained_ticks)


## A second, unrelated car pair that happens to share the car-car
## `contact_id`, tick and link status. Direct negative counterexample: sharing a
## contact link is not a pair, because the participants are not reciprocal.
func make_unrelated_pair_builder() -> ImpactEvent.Builder:
	var builder := make_front_builder()
	builder.event_id = UNRELATED_PAIR_EVENT_ID
	builder.tick_index = CAR_CAR_TICK
	builder.primary_car_id = UNRELATED_PRIMARY_CAR_ID
	builder.other_car_id = UNRELATED_OTHER_CAR_ID
	builder.contact_id = CAR_CAR_CONTACT_ID
	builder.contact_point_world_m = CAR_CAR_WORLD_POINT
	builder.contact_point_local_m = Vector3(0.90, 0.35, -0.20)
	builder.contact_normal_world_m = Vector3(-1.0, 0.0, 0.0)
	builder.severity_m_s = CAR_CAR_OTHER_SEVERITY
	builder.post_contact_velocity_world_m_s = Vector3(-9.0, 0.0, 4.0)
	builder.imparted_motion_m = CAR_CAR_OTHER_IMPARTED_MOTION
	builder.region = ImpactEvent.ContactRegion.RIGHT
	return builder


## A non-reciprocal chain: `car-beta` as primary with a third car as other.
## It shares the primary of one real perspective and the tick and link, so only
## the reciprocal-ID rule rejects it.
func make_nonreciprocal_builder() -> ImpactEvent.Builder:
	var builder := make_unrelated_pair_builder()
	builder.event_id = NONRECIPROCAL_EVENT_ID
	builder.primary_car_id = OTHER_CAR_ID
	builder.other_car_id = UNRELATED_PRIMARY_CAR_ID
	builder.region = ImpactEvent.ContactRegion.LEFT
	return builder


## A wall record that carries the shared car-car `contact_id`. A record with no
## second car has no opposite perspective, whatever its link says; two such
## records with different primaries are the second mispairing path.
func make_wall_linked_builder(event_id: String, primary_car_id: String) -> ImpactEvent.Builder:
	var builder := make_front_builder()
	builder.event_id = event_id
	builder.tick_index = CAR_CAR_TICK
	builder.primary_car_id = primary_car_id
	builder.other_car_id = ""
	builder.contact_id = CAR_CAR_CONTACT_ID
	builder.contact_point_world_m = CAR_CAR_WORLD_POINT
	builder.contact_normal_world_m = CAR_CAR_OTHER_NORMAL
	builder.severity_m_s = CAR_CAR_OTHER_SEVERITY
	builder.post_contact_velocity_world_m_s = Vector3(-9.0, 0.0, 4.0)
	builder.imparted_motion_m = CAR_CAR_OTHER_IMPARTED_MOTION
	builder.region = ImpactEvent.ContactRegion.LEFT
	return builder


## The same (contact, primary car) perspective as `make_car_car_builder()`
## published again under a NEW `event_id`: the duplicate-producer retry the
## ledger must refuse instead of retaining two records of one perspective.
func make_duplicate_perspective_builder() -> ImpactEvent.Builder:
	var builder := make_car_car_builder()
	builder.event_id = DUPLICATE_PERSPECTIVE_EVENT_ID
	builder.severity_m_s = DUPLICATE_PERSPECTIVE_SEVERITY
	return builder


## One valid car-car record for the ambiguous-separator pair control. Both the
## first and second fixture carry full valid geometry; only the identity
## fields differ, and the (contact_id, primary_car_id) pairs are the classic
## single-separator collision.
func make_ambiguous_pair_builder(
	event_id: String, contact_id: String, primary_car_id: String
) -> ImpactEvent.Builder:
	var builder := make_front_builder()
	builder.event_id = event_id
	builder.tick_index = AMBIGUOUS_TICK
	builder.primary_car_id = primary_car_id
	builder.other_car_id = AMBIGUOUS_OTHER_CAR_ID
	builder.contact_id = contact_id
	builder.contact_point_world_m = CAR_CAR_WORLD_POINT
	builder.contact_point_local_m = Vector3(0.15, 0.35, -0.25)
	builder.contact_normal_world_m = Vector3(-1.0, 0.0, 0.0)
	builder.severity_m_s = AMBIGUOUS_SEVERITY
	builder.post_contact_velocity_world_m_s = Vector3(8.0, 0.0, 3.0)
	builder.imparted_motion_m = Vector3(0.18, 0.0, 0.12)
	builder.region = ImpactEvent.ContactRegion.RIGHT
	return builder


## The first ambiguous pair published again under a NEW `event_id` and a
## different severity: a true same-pair retry the ledger must refuse while
## leaving the retained content unchanged.
func make_ambiguous_retry_builder() -> ImpactEvent.Builder:
	var builder := make_ambiguous_pair_builder(
		AMBIGUOUS_RETRY_EVENT_ID, AMBIGUOUS_CONTACT_A, AMBIGUOUS_PRIMARY_A
	)
	builder.severity_m_s = AMBIGUOUS_RETRY_SEVERITY
	return builder


## The second ambiguous pair published again under a NEW `event_id` and a
## different severity: the symmetric retry of the other colliding pair.
func make_ambiguous_retry_b_builder() -> ImpactEvent.Builder:
	var builder := make_ambiguous_pair_builder(
		AMBIGUOUS_RETRY_B_EVENT_ID, AMBIGUOUS_CONTACT_B, AMBIGUOUS_PRIMARY_B
	)
	builder.severity_m_s = AMBIGUOUS_RETRY_SEVERITY
	return builder


## The complementary perspective of the first ambiguous pair: the other car as
## primary under the same contact link, so the pair index must still admit it.
func make_ambiguous_complement_builder() -> ImpactEvent.Builder:
	var builder := make_ambiguous_pair_builder(
		AMBIGUOUS_COMPLEMENT_EVENT_ID, AMBIGUOUS_CONTACT_A, AMBIGUOUS_OTHER_CAR_ID
	)
	builder.other_car_id = AMBIGUOUS_PRIMARY_A
	builder.contact_normal_world_m = Vector3(1.0, 0.0, 0.0)
	builder.region = ImpactEvent.ContactRegion.LEFT
	return builder


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
