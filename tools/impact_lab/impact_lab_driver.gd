extends Node
## Headless M1.8 impact-event contract validator.
##
## Builds explicit fixtures, calls the real `ImpactEvent.Builder` and
## `ImpactEvent.Ledger`, and prints one machine-readable
## `IMPACT_LAB_RESULT <json>` per case plus a final `IMPACT_LAB_SUMMARY`.
## Exit 0 means every case passed; 1 means at least one check failed.
##
## Scope: pure event-record validation, publication, bounding and isolation.
## It does not integrate the motor/body adapter, select physical contact
## points, drive cosmetic damage or prove gameplay.

const ChecksScript := preload("res://tools/impact_lab/impact_lab_checks.gd")

const CASE_IDS: Array[String] = [
	"valid_front_and_rear",
	"valid_car_car",
	"duplicate_event_id_coalesced",
	"invalid_and_nonfinite_atomic_refusal",
	"bounded_capacity",
	"contact_only_severity_distinction",
	"copy_isolation",
	"floor_first_wall_point_contract",
	"no_authority_mutation_surface",
	"normalization_rule",
	"uncommitted_source_refusal",
]

## Deliberate geometric seam fixture: a floor contact arrives before a wall
## contact in the same substep sequence, mirroring the adapter's documented
## generic first-contact hazard.
const FLOOR_FIRST_POINT := Vector3(0.0, 0.0, -1.0)
const FLOOR_NORMAL := Vector3(0.0, 1.0, 0.0)
const WALL_POINT := Vector3(0.90, 0.50, -2.0)
const WALL_NORMAL := Vector3(-1.0, 0.0, 0.0)

var d := ImpactLabChecks.new()
var measurements: Dictionary = {}
var _results: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _run() -> void:
	for case_id in CASE_IDS:
		_results.append(_run_case(case_id))
	var total_checks := 0
	var total_failures := 0
	var failed_cases := 0
	for result in _results:
		total_checks += int(result["checks"])
		total_failures += int(result["checks_failed"])
		if not bool(result["pass"]):
			failed_cases += 1
	var summary := {
		"schema": "roadstorm.impact_lab.summary.v1",
		"cases": _results.size(),
		"checks": total_checks,
		"checks_failed": total_failures,
		"failed_cases": failed_cases,
		"pass": failed_cases == 0,
	}
	print("IMPACT_LAB_SUMMARY ", JSON.stringify(summary))
	print("CHECKS_TOTAL=", total_checks, " CHECKS_FAILED=", total_failures)
	get_tree().quit(0 if failed_cases == 0 else 1)


func _run_case(case_id: String) -> Dictionary:
	d = ImpactLabChecks.new()
	measurements = {}
	match case_id:
		"valid_front_and_rear":
			_case_valid_front_and_rear()
		"valid_car_car":
			_case_valid_car_car()
		"duplicate_event_id_coalesced":
			_case_duplicate_event_id()
		"invalid_and_nonfinite_atomic_refusal":
			_case_invalid_atomic_refusal()
		"bounded_capacity":
			_case_bounded_capacity()
		"contact_only_severity_distinction":
			_case_contact_only_severity()
		"copy_isolation":
			_case_copy_isolation()
		"floor_first_wall_point_contract":
			_case_floor_first_contract()
		"no_authority_mutation_surface":
			_case_no_authority_surface()
		"normalization_rule":
			_case_normalization_rule()
		"uncommitted_source_refusal":
			_case_uncommitted_source()
		_:
			d.check(false, "unknown case %s" % case_id)
	var result := {
		"case": case_id,
		"pass": d.failures.is_empty(),
		"checks": d.checks,
		"checks_failed": d.failures.size(),
		"failures": d.failures.duplicate(),
		"measurements": measurements.duplicate(),
	}
	print("IMPACT_LAB_RESULT ", JSON.stringify(result))
	return result


# --- Cases ----------------------------------------------------------------


func _case_valid_front_and_rear() -> void:
	for required in ["severity_m_s", "post_contact_velocity_world_m_s",
			"contact_point_world_m", "contact_normal_world_m",
			"contact_point_local_m", "imparted_motion_m", "region"]:
		d.check(
			required in ImpactEvent.INTEGRATOR_SUPPLIED_FIELDS,
			"integrator authority list includes %s" % required
		)

	var front := d.make_front_builder().build()
	d.check(front != null, "front.build_returns_event")
	if front != null:
		d.check_front_event_fields(front)

	var rear := d.make_rear_builder().build()
	d.check(rear != null, "rear.build_returns_event")
	if rear != null:
		d.check_string(rear.event_id, ImpactLabChecks.REAR_EVENT_ID, "rear.event_id")
		d.check(not rear.has_other_car(), "rear.has_no_other_car")
		d.check(
			rear.region == ImpactEvent.ContactRegion.REAR, "rear.region"
		)
		d.check_exact_float(rear.severity_m_s, 2.50, "rear.severity")
		d.check_vector_close(
			rear.contact_point_world_m, Vector3(-0.50, 0.60, -1.80),
			ImpactLabChecks.VECTOR_TOLERANCE, "rear.world_contact_point"
		)

	var ledger := d.make_ledger()
	if front != null:
		d.check(ledger.publish(front).is_published(), "front.published")
	if rear != null:
		d.check(ledger.publish(rear).is_published(), "rear.published")
	d.check(ledger.event_count() == 2, "front_rear.event_count")
	d.check(ledger.tick_count() == 1, "front_rear.single_tick_bucket")
	var snapshot := ledger.events_for_tick(ImpactLabChecks.WALL_TICK)
	d.check(snapshot.size() == 2, "front_rear.snapshot_size")
	if snapshot.size() == 2:
		d.check_string(snapshot[0].event_id, ImpactLabChecks.FRONT_EVENT_ID, "front_rear.order_front")
		d.check_string(snapshot[1].event_id, ImpactLabChecks.REAR_EVENT_ID, "front_rear.order_rear")


func _case_valid_car_car() -> void:
	var car_car := d.make_car_car_builder().build()
	d.check(car_car != null, "car_car.build_returns_event")
	if car_car == null:
		return
	d.check_string(car_car.event_id, ImpactLabChecks.CAR_CAR_EVENT_ID, "car_car.event_id")
	d.check(car_car.tick_index == ImpactLabChecks.CAR_CAR_TICK, "car_car.tick_index")
	d.check_string(car_car.primary_car_id, ImpactLabChecks.PRIMARY_CAR_ID, "car_car.primary")
	d.check_string(car_car.other_car_id, ImpactLabChecks.OTHER_CAR_ID, "car_car.other")
	d.check(car_car.has_other_car(), "car_car.has_other_car")
	d.check(car_car.region == ImpactEvent.ContactRegion.RIGHT, "car_car.region")
	d.check_exact_float(car_car.severity_m_s, 3.00, "car_car.severity")
	d.check_vector_close(
		car_car.post_contact_velocity_world_m_s, Vector3(9.0, 0.0, 4.0),
		ImpactLabChecks.VECTOR_TOLERANCE, "car_car.post_contact_velocity"
	)
	d.check(car_car.is_valid(), "car_car.is_valid")

	var ledger := d.make_ledger()
	var outcome := ledger.publish(car_car)
	d.check(outcome.is_published(), "car_car.published")
	d.check(ledger.event_count() == 1, "car_car.event_count")
	var snapshot := ledger.events_for_tick(ImpactLabChecks.CAR_CAR_TICK)
	d.check(snapshot.size() == 1, "car_car.snapshot_size")
	if snapshot.size() == 1:
		d.check(snapshot[0].has_other_car(), "car_car.snapshot_preserves_pair")
		d.check_string(snapshot[0].other_car_id, ImpactLabChecks.OTHER_CAR_ID, "car_car.snapshot_other")


func _case_duplicate_event_id() -> void:
	var first := d.make_front_builder().build()
	var second := d.make_front_builder().build()
	if second != null:
		second.event_id = ImpactLabChecks.FRONT_EVENT_ID
		second.severity_m_s = 9.50

	var ledger := d.make_ledger()
	var first_outcome := ledger.publish(first)
	d.check(first_outcome.is_published(), "duplicate.first_published")
	var second_outcome := ledger.publish(second)
	d.check(second_outcome.is_coalesced(), "duplicate.second_coalesced_not_added")
	d.check(ledger.coalesced_count == 1, "duplicate.coalesced_count")
	d.check(ledger.event_count() == 1, "duplicate.event_count_stays_one")
	var retained := ledger.find_by_id(ImpactLabChecks.FRONT_EVENT_ID)
	d.check(retained != null, "duplicate.retained_lookup")
	if retained != null:
		d.check_exact_float(retained.severity_m_s, ImpactLabChecks.FRONT_SEVERITY, "duplicate.first_wins")

	var third_outcome := ledger.publish(second)
	d.check(third_outcome.is_coalesced(), "duplicate.repeat_still_coalesced")
	d.check(ledger.coalesced_count == 2, "duplicate.coalesced_count_stable")
	d.check(ledger.event_count() == 1, "duplicate.repeat_adds_nothing")


func _case_invalid_atomic_refusal() -> void:
	var ledger := d.make_ledger()
	var corruptions: Array[Dictionary] = [
		{"name": "nan_severity", "property": "severity_m_s", "value": NAN},
		{"name": "infinite_severity", "property": "severity_m_s", "value": INF},
		{"name": "negative_severity", "property": "severity_m_s", "value": -0.5},
		{
			"name": "nan_world_point",
			"property": "contact_point_world_m",
			"value": Vector3(NAN, 0.0, 0.0),
		},
		{
			"name": "infinite_local_point",
			"property": "contact_point_local_m",
			"value": Vector3(0.0, INF, 0.0),
		},
		{
			"name": "nan_normal",
			"property": "contact_normal_world_m",
			"value": Vector3(NAN, 0.0, 0.0),
		},
		{
			"name": "zero_normal",
			"property": "contact_normal_world_m",
			"value": Vector3.ZERO,
		},
		{
			"name": "near_zero_normal",
			"property": "contact_normal_world_m",
			"value": Vector3(1e-9, 0.0, 0.0),
		},
		{
			"name": "nonunit_normal",
			"property": "contact_normal_world_m",
			"value": Vector3(2.0, 0.0, 0.0),
		},
		{
			"name": "nan_post_velocity",
			"property": "post_contact_velocity_world_m_s",
			"value": Vector3(0.0, NAN, 0.0),
		},
		{
			"name": "infinite_imparted_motion",
			"property": "imparted_motion_m",
			"value": Vector3(INF, 0.0, 0.0),
		},
		{"name": "empty_event_id", "property": "event_id", "value": ""},
		{"name": "empty_primary_id", "property": "primary_car_id", "value": ""},
		{
			"name": "duplicate_car_id",
			"property": "other_car_id",
			"value": ImpactLabChecks.PRIMARY_CAR_ID,
		},
		{"name": "invalid_region", "property": "region", "value": 999},
		{"name": "uncommitted_source", "property": "source_committed", "value": false},
	]

	for corruption in corruptions:
		var label: String = corruption["name"]
		var builder := d.make_front_builder()
		builder.set(corruption["property"], corruption["value"])
		var before_content := ledger.content_digest()
		var event := builder.build()
		if event == null:
			d.check(
				not builder.rejection_reason.is_empty(),
				"%s.builder_refusal_has_reason" % label
			)
		else:
			var before_refusals := ledger.refused_count
			var outcome := ledger.publish(event)
			d.check(outcome.is_refused(), "%s.ledger_refuses" % label)
			d.check(
				ledger.refused_count == before_refusals + 1,
				"%s.refusal_count_advances_once" % label
			)
		d.check(
			ledger.content_digest() == before_content,
			"%s.ledger_content_unchanged" % label
		)
		d.check(ledger.published_count == 0, "%s.nothing_published" % label)

	# Direct ledger refusals for records that never went through the builder.
	var base_content := ledger.content_digest()
	var null_outcome := ledger.publish(null)
	d.check(null_outcome.is_refused(), "null_event.refused")
	var default_outcome := ledger.publish(ImpactEvent.new())
	d.check(default_outcome.is_refused(), "default_event.refused")
	var uncommitted := d.make_front_builder().build()
	if uncommitted != null:
		uncommitted.committed = false
		var uncommitted_outcome := ledger.publish(uncommitted)
		d.check(uncommitted_outcome.is_refused(), "hand_uncommitted_event.refused")
	d.check(ledger.content_digest() == base_content, "direct_refusals.content_unchanged")
	d.check(ledger.published_count == 0, "direct_refusals.nothing_published")


func _case_bounded_capacity() -> void:
	var ledger := d.make_ledger(2, 2)
	var tick_one: Array[String] = ["cap-1a", "cap-1b", "cap-1c"]
	var tick_two: Array[String] = ["cap-2a", "cap-2b", "cap-2c"]

	for index in range(tick_one.size()):
		var outcome := ledger.publish(d.make_lab_event(tick_one[index], 1))
		var should_publish: bool = index < 2
		d.check(
			outcome.is_published() == should_publish,
			"capacity.tick_one_%s_%s" % [tick_one[index], "published" if should_publish else "refused"]
		)
	d.check(ledger.event_count() == 2, "capacity.tick_one_bounded")
	d.check(ledger.tick_count() == 1, "capacity.tick_one_single_bucket")

	for index in range(tick_two.size()):
		var outcome := ledger.publish(d.make_lab_event(tick_two[index], 2))
		var should_publish: bool = index < 2
		d.check(
			outcome.is_published() == should_publish,
			"capacity.tick_two_%s_%s" % [tick_two[index], "published" if should_publish else "refused"]
		)
	d.check(ledger.event_count() == 4, "capacity.two_ticks_bounded")
	d.check(ledger.tick_count() == 2, "capacity.two_buckets")

	var pruned := ledger.publish(d.make_lab_event("cap-3a", 3))
	d.check(pruned.is_published(), "capacity.tick_three_published")
	d.check(ledger.tick_count() == 2, "capacity.oldest_tick_pruned")
	d.check(ledger.event_count() == 3, "capacity.total_bounded_after_prune")
	d.check(ledger.events_for_tick(1).is_empty(), "capacity.pruned_tick_empty")
	d.check(not ledger.has_event_id("cap-1a"), "capacity.pruned_id_forgotten")
	d.check(ledger.has_event_id("cap-2a"), "capacity.retained_tick_id_present")
	d.check(ledger.has_event_id("cap-3a"), "capacity.new_tick_id_present")


func _case_contact_only_severity() -> void:
	var pre_contact := Vector3(20.0, 0.0, 0.0)
	var post_contact := Vector3(15.0, 0.0, 0.0)
	var contact_delta := (post_contact - pre_contact).length()
	d.check_close(contact_delta, 5.0, ImpactLabChecks.FLOAT_TOLERANCE, "severity.contact_delta_oracle")

	# A throttle/motor acceleration proposal over the same window would imply
	# a different delta. The event must carry the contact-only value instead.
	var proposed_with_throttle := Vector3(23.0, 0.0, 0.0)
	var naive_motor_delta := (post_contact - proposed_with_throttle).length()
	d.check_close(naive_motor_delta, 8.0, ImpactLabChecks.FLOAT_TOLERANCE, "severity.motor_delta_oracle")
	d.check(absf(naive_motor_delta - contact_delta) > 1.0, "severity.oracles_differ")

	var builder := d.make_front_builder()
	builder.severity_m_s = contact_delta
	builder.post_contact_velocity_world_m_s = post_contact
	var event := builder.build()
	d.check(event != null, "severity.build_returns_event")
	if event != null:
		d.check_exact_float(event.severity_m_s, contact_delta, "severity.published_contact_only_value")
		d.check(
			absf(event.severity_m_s - naive_motor_delta) > 1.0,
			"severity.not_motor_acceleration_delta"
		)
		d.check_vector_close(
			event.post_contact_velocity_world_m_s, post_contact,
			ImpactLabChecks.VECTOR_TOLERANCE, "severity.post_contact_velocity"
		)
		measurements["contact_delta_m_s"] = contact_delta
		measurements["motor_delta_m_s"] = naive_motor_delta
		measurements["published_severity_m_s"] = event.severity_m_s


func _case_copy_isolation() -> void:
	var ledger := d.make_ledger()
	var original := d.make_front_builder().build()
	var outcome := ledger.publish(original)
	d.check(outcome.is_published(), "copy.published")
	if original == null:
		return

	original.severity_m_s = 999.0
	original.event_id = "mutated-original"
	var reread := ledger.events_for_tick(original.tick_index)
	d.check(reread.size() == 1, "copy.snapshot_size")
	if reread.size() == 1:
		d.check_exact_float(
			reread[0].severity_m_s, ImpactLabChecks.FRONT_SEVERITY,
			"copy.ledger_stores_private_copy"
		)
		d.check_string(
			reread[0].event_id, ImpactLabChecks.FRONT_EVENT_ID,
			"copy.ledger_stores_original_identity"
		)

	var snapshot := ledger.events_for_tick(ImpactLabChecks.WALL_TICK)
	if snapshot.size() == 1:
		snapshot[0].severity_m_s = 777.0
		snapshot[0].region = ImpactEvent.ContactRegion.LEFT
	var after_snapshot := ledger.events_for_tick(ImpactLabChecks.WALL_TICK)
	d.check(after_snapshot.size() == 1, "copy.resnapshot_size")
	if after_snapshot.size() == 1:
		d.check_exact_float(
			after_snapshot[0].severity_m_s, ImpactLabChecks.FRONT_SEVERITY,
			"copy.snapshot_mutation_does_not_reach_ledger"
		)
		d.check(
			after_snapshot[0].region == ImpactEvent.ContactRegion.FRONT,
			"copy.snapshot_region_does_not_reach_ledger"
		)

	if outcome.event != null:
		outcome.event.severity_m_s = 555.0
	var after_outcome := ledger.events_for_tick(ImpactLabChecks.WALL_TICK)
	if after_outcome.size() == 1:
		d.check_exact_float(
			after_outcome[0].severity_m_s, ImpactLabChecks.FRONT_SEVERITY,
			"copy.outcome_handle_does_not_reach_ledger"
		)

	var copy := original.copy()
	if copy != null:
		copy.severity_m_s = 123.0
		d.check_exact_float(
			original.severity_m_s, 999.0, "copy.copy_is_independent_of_source"
		)


func _case_floor_first_contract() -> void:
	# Deterministic two-contact ordering: floor first, wall second. The generic
	# first contact reports the floor point, which cannot locate the wall.
	var generic_first_point: Vector3 = FLOOR_FIRST_POINT
	var generic_first_normal: Vector3 = FLOOR_NORMAL
	d.check(
		generic_first_normal.is_equal_approx(Vector3(0.0, 1.0, 0.0)),
		"floor_first.generic_normal_is_floor_up"
	)
	d.check(
		not generic_first_normal.is_equal_approx(WALL_NORMAL),
		"floor_first.generic_normal_is_not_wall_normal"
	)
	d.check(
		generic_first_point.distance_to(WALL_POINT) > 0.25,
		"floor_first.generic_point_is_not_wall_point"
	)
	d.check(
		absf(generic_first_point.y - WALL_POINT.y) > 0.25,
		"floor_first.generic_point_height_is_floor_height"
	)

	var adapter_source := d.read_source(ImpactLabChecks.ADAPTER_SOURCE_PATH)
	d.check(not adapter_source.is_empty(), "floor_first.adapter_source_readable")
	d.check(
		adapter_source.contains("result.contact_point = hit_point"),
		"floor_first.adapter_publishes_generic_contact_point"
	)
	d.check(
		adapter_source.contains("generic_point"),
		"floor_first.adapter_labels_generic_first_contact"
	)
	d.check(
		not adapter_source.contains("wall_contact_point"),
		"floor_first.adapter_exposes_no_authoritative_wall_point"
	)
	d.check(
		adapter_source.contains("floor or ceiling"),
		"floor_first.adapter_documents_floor_hazard"
	)

	var event_code := d.strip_full_line_comments(
		d.read_source(ImpactLabChecks.EVENT_SOURCE_PATH)
	)
	d.check(
		not event_code.contains("contact_point ="),
		"floor_first.event_module_does_not_alias_generic_point_as_wall_point"
	)


func _case_no_authority_surface() -> void:
	var source := d.read_source(ImpactLabChecks.EVENT_SOURCE_PATH)
	d.check(not source.is_empty(), "surface.event_source_readable")
	var code := d.strip_full_line_comments(source)
	var forbidden: Array[String] = [
		"CarState",
		"ArcadeMotor",
		"MotorBodyAdapter",
		"CharacterBody3D",
		"PhysicsServer",
		"RandomNumberGenerator",
		"randi(",
		"randf(",
		"_ready(",
		"_process(",
		"_physics_process(",
		"acceleration",
	]
	for token in forbidden:
		d.check(
			not code.contains(token),
			"surface.code_avoids_%s" % token.replace("(", "").replace(")", "")
		)
	d.check(code.contains("severity_m_s"), "surface.severity_field_present")
	d.check(
		code.contains("INTEGRATOR_SUPPLIED_FIELDS"),
		"surface.authority_contract_machine_readable"
	)


func _case_normalization_rule() -> void:
	var builder := d.make_front_builder()
	builder.contact_normal_world_m = Vector3(0.0, 0.0, -2.5)
	builder.normal_mode = ImpactEvent.NormalMode.PRESERVE
	var preserved := builder.build()
	d.check(preserved == null, "normalize.preserve_refuses_nonunit")
	d.check_string(builder.rejection_reason, "nonunit contact normal", "normalize.preserve_reason")

	builder.normal_mode = ImpactEvent.NormalMode.NORMALIZE
	var normalized := builder.build()
	d.check(normalized != null, "normalize.normalize_accepts_nonzero")
	if normalized != null:
		d.check_close(
			normalized.contact_normal_world_m.length(), 1.0, 1e-6,
			"normalize.result_is_unit_length"
		)
		d.check_vector_close(
			normalized.contact_normal_world_m, Vector3(0.0, 0.0, -1.0), 1e-6,
			"normalize.direction_preserved"
		)
		d.check(normalized.is_valid(), "normalize.result_valid")

	builder.contact_normal_world_m = Vector3.ZERO
	var zero := builder.build()
	d.check(zero == null, "normalize.zero_normal_refused")
	d.check_string(builder.rejection_reason, "zero contact normal", "normalize.zero_reason")


func _case_uncommitted_source() -> void:
	var builder := d.make_front_builder()
	builder.source_committed = false
	var event := builder.build()
	d.check(event == null, "uncommitted.builder_refuses")
	d.check_string(builder.rejection_reason, "uncommitted source", "uncommitted.builder_reason")

	var ledger := d.make_ledger()
	var committed_event := d.make_front_builder().build()
	if committed_event != null:
		committed_event.committed = false
	var before := ledger.content_digest()
	var outcome := ledger.publish(committed_event)
	d.check(outcome.is_refused(), "uncommitted.ledger_refuses")
	d.check(ledger.content_digest() == before, "uncommitted.ledger_content_unchanged")
	d.check(ledger.published_count == 0, "uncommitted.nothing_published")
