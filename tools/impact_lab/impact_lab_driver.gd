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
## points, drive cosmetic damage or prove gameplay. In particular it cannot
## prove that a published `severity_m_s` was physically derived from the
## contact response: it only proves that the record carries whatever value
## the integrator supplied, and that a contact-only value is distinguishable
## from a motor-acceleration value by construction.

const ChecksScript := preload("res://tools/impact_lab/impact_lab_checks.gd")

const CASE_IDS: Array[String] = [
	"valid_front_and_rear",
	"valid_car_car",
	"two_perspective_car_car",
	"opposite_perspective_pairing",
	"duplicate_event_id_coalesced",
	"conflicting_duplicate_refused",
	"duplicate_perspective_pair_refused",
	"ambiguous_separator_pair_keys",
	"duplicate_retention_window",
	"invalid_and_nonfinite_atomic_refusal",
	"digest_covers_every_field",
	"required_field_omission",
	"bounded_capacity",
	"contact_only_severity_distinction",
	"copy_isolation",
	"floor_first_wall_point_contract",
	"no_authority_mutation_surface",
	"normalization_rule",
	"large_finite_vector_domain",
	"ledger_settings_immutable",
	"uncommitted_source_refusal",
]

## Deliberate geometric seam fixture: a floor contact arrives before a wall
## contact in the same substep sequence, mirroring the adapter's documented
## generic first-contact hazard.
const FLOOR_FIRST_POINT := Vector3(0.0, 0.0, -1.0)
const FLOOR_NORMAL := Vector3(0.0, 1.0, 0.0)
const WALL_POINT := Vector3(0.90, 0.50, -2.0)
const WALL_NORMAL := Vector3(-1.0, 0.0, 0.0)

## Every published field including the event ID, used to prove that both the
## payload comparison and the content digest cover the whole record rather
## than a sampled subset.
const PAYLOAD_PROBES: Array[Dictionary] = [
	{"field": "event_id", "value": "evt-probe-other"},
] + CONFLICT_PROBES

## Every builder field with the fixture value the omission and zero-legality
## controls assign. Used to construct a record with exactly one field left at
## its default, so an omission test exercises the real default rather than a
## value the test itself supplied.
const FIELD_VALUES: Array[Dictionary] = [
	{"field": "event_id", "value": ImpactLabChecks.FRONT_EVENT_ID},
	{"field": "tick_index", "value": ImpactLabChecks.WALL_TICK},
	{"field": "primary_car_id", "value": ImpactLabChecks.PRIMARY_CAR_ID},
	{"field": "other_car_id", "value": ""},
	{"field": "contact_id", "value": ""},
	{"field": "contact_point_world_m", "value": ImpactLabChecks.FRONT_WORLD_POINT},
	{"field": "contact_point_local_m", "value": ImpactLabChecks.FRONT_LOCAL_POINT},
	{"field": "contact_normal_world_m", "value": ImpactLabChecks.FRONT_NORMAL},
	{"field": "severity_m_s", "value": ImpactLabChecks.FRONT_SEVERITY},
	{"field": "post_contact_velocity_world_m_s", "value": ImpactLabChecks.FRONT_POST_VELOCITY},
	{"field": "imparted_motion_m", "value": ImpactLabChecks.FRONT_IMPARTED_MOTION},
	{"field": "region", "value": ImpactEvent.ContactRegion.FRONT},
	{"field": "normal_mode", "value": ImpactEvent.NormalMode.PRESERVE},
	{"field": "source_committed", "value": true},
]

## Required builder fields and the exact refusal reason each unset field must
## produce. A legal explicit value for these fields is indistinguishable from
## the default, so each omission needs its own case.
const OMISSION_REASONS: Array[Dictionary] = [
	{"field": "event_id", "reason": "empty event id"},
	{"field": "tick_index", "reason": "negative tick index"},
	{"field": "primary_car_id", "reason": "empty primary car id"},
	{"field": "contact_point_world_m", "reason": "nonfinite world contact point"},
	{"field": "contact_point_local_m", "reason": "nonfinite local contact point"},
	{"field": "contact_normal_world_m", "reason": "zero contact normal"},
	{"field": "severity_m_s", "reason": "nonfinite severity"},
	{"field": "post_contact_velocity_world_m_s", "reason": "nonfinite post-contact velocity"},
	{"field": "imparted_motion_m", "reason": "nonfinite imparted motion"},
	{"field": "region", "reason": "invalid contact region"},
	{"field": "source_committed", "reason": "uncommitted source"},
]

## Required physical fields for which an explicit zero is a legal, valid
## publication. The builder must accept the zero and refuse only the omission.
const ZERO_LEGAL_FIELDS: Array[Dictionary] = [
	{"field": "severity_m_s", "value": 0.0},
	{"field": "contact_point_world_m", "value": Vector3.ZERO},
	{"field": "contact_point_local_m", "value": Vector3.ZERO},
	{"field": "post_contact_velocity_world_m_s", "value": Vector3.ZERO},
	{"field": "imparted_motion_m", "value": Vector3.ZERO},
	{"field": "region", "value": ImpactEvent.ContactRegion.FRONT},
	{"field": "tick_index", "value": 0},
]

## Every authoritative field except the event ID, with a differing value used
## to prove that a conflicting payload under a retained ID is refused for each
## of them. The ID itself cannot be probed here: changing it is a different
## record, not a conflict.
const CONFLICT_PROBES: Array[Dictionary] = [
	{"field": "tick_index", "value": ImpactLabChecks.WALL_TICK + 5},
	{"field": "primary_car_id", "value": "car-probe"},
	{"field": "other_car_id", "value": "car-probe-other"},
	{"field": "contact_id", "value": "contact-probe"},
	{"field": "contact_point_world_m", "value": Vector3(1.5, 2.5, 3.5)},
	{"field": "contact_point_local_m", "value": Vector3(-1.5, 0.5, -3.5)},
	{"field": "contact_normal_world_m", "value": Vector3(0.0, 1.0, 0.0)},
	{"field": "severity_m_s", "value": 7.75},
	{"field": "post_contact_velocity_world_m_s", "value": Vector3(4.0, 5.0, 6.0)},
	{"field": "imparted_motion_m", "value": Vector3(0.25, 0.5, 0.75)},
	{"field": "region", "value": ImpactEvent.ContactRegion.REAR},
]

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
		"two_perspective_car_car":
			_case_two_perspective_car_car()
		"opposite_perspective_pairing":
			_case_opposite_perspective_pairing()
		"duplicate_event_id_coalesced":
			_case_duplicate_event_id()
		"conflicting_duplicate_refused":
			_case_conflicting_duplicate_refused()
		"duplicate_perspective_pair_refused":
			_case_duplicate_perspective_pair_refused()
		"ambiguous_separator_pair_keys":
			_case_ambiguous_separator_pair_keys()
		"duplicate_retention_window":
			_case_duplicate_retention_window()
		"invalid_and_nonfinite_atomic_refusal":
			_case_invalid_atomic_refusal()
		"digest_covers_every_field":
			_case_digest_covers_every_field()
		"required_field_omission":
			_case_required_field_omission()
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
		"large_finite_vector_domain":
			_case_large_finite_vector_domain()
		"ledger_settings_immutable":
			_case_ledger_settings_immutable()
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
	d.check_string(car_car.contact_id, ImpactLabChecks.CAR_CAR_CONTACT_ID, "car_car.contact_id")
	d.check(car_car.has_contact_link(), "car_car.has_contact_link")
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


func _case_two_perspective_car_car() -> void:
	# One physical car-car contact produces two complementary records, one per
	# primary car. Each carries its own event_id; the shared contact_id links
	# them. Both must publish; neither may coalesce or refuse the other.
	var alpha := d.make_car_car_builder().build()
	var beta := d.make_car_car_other_builder().build()
	d.check(alpha != null, "two_perspective.alpha_built")
	d.check(beta != null, "two_perspective.beta_built")
	if alpha == null or beta == null:
		return

	d.check(alpha.event_id != beta.event_id, "two_perspective.distinct_event_ids")
	d.check(alpha.contact_id == beta.contact_id, "two_perspective.shared_contact_id")
	d.check(
		alpha.primary_car_id == beta.other_car_id
		and beta.primary_car_id == alpha.other_car_id,
		"two_perspective.primary_and_other_swap"
	)
	d.check(
		alpha.contact_point_world_m == beta.contact_point_world_m,
		"two_perspective.shared_world_contact_point"
	)
	d.check(
		alpha.contact_point_local_m != beta.contact_point_local_m,
		"two_perspective.local_points_are_per_car"
	)
	d.check(not alpha.same_payload(beta), "two_perspective.payloads_differ")
	d.check(alpha.is_opposite_perspective(beta), "two_perspective.alpha_sees_opposite")
	d.check(beta.is_opposite_perspective(alpha), "two_perspective.beta_sees_opposite")

	var ledger := d.make_ledger()
	var alpha_outcome := ledger.publish(alpha)
	var beta_outcome := ledger.publish(beta)
	d.check(alpha_outcome.is_published(), "two_perspective.alpha_published")
	d.check(beta_outcome.is_published(), "two_perspective.beta_published")
	d.check(ledger.event_count() == 2, "two_perspective.both_retained")
	d.check(ledger.tick_count() == 1, "two_perspective.single_tick_bucket")
	d.check(ledger.coalesced_count == 0, "two_perspective.nothing_coalesced")
	d.check(ledger.conflict_count == 0, "two_perspective.nothing_conflicted")

	var retained_alpha := ledger.find_by_id(ImpactLabChecks.CAR_CAR_EVENT_ID)
	var retained_beta := ledger.find_by_id(ImpactLabChecks.CAR_CAR_OTHER_EVENT_ID)
	d.check(retained_alpha != null, "two_perspective.alpha_retained")
	d.check(retained_beta != null, "two_perspective.beta_retained")
	if retained_alpha != null and retained_beta != null:
		d.check_string(
			retained_alpha.primary_car_id, ImpactLabChecks.PRIMARY_CAR_ID,
			"two_perspective.retained_alpha_primary"
		)
		d.check_string(
			retained_beta.primary_car_id, ImpactLabChecks.OTHER_CAR_ID,
			"two_perspective.retained_beta_primary"
		)

	# The historical failure mode: reusing one contact-wide ID for both sides
	# must now be an explicit conflict, not a silent coalesce.
	var colliding := d.make_car_car_other_builder().build()
	if colliding != null:
		colliding.event_id = ImpactLabChecks.CAR_CAR_EVENT_ID
	var collision_outcome := ledger.publish(colliding)
	d.check(collision_outcome.is_refused(), "two_perspective.reused_id_refused")
	d.check(ledger.conflict_count == 1, "two_perspective.reused_id_counted")
	d.check(ledger.event_count() == 2, "two_perspective.reused_id_adds_nothing")


func _case_opposite_perspective_pairing() -> void:
	# Direct counterexamples for the pairing predicate. Each one is a fully
	# built, valid record handed to `is_opposite_perspective()` itself, so a
	# regression inside the predicate fails here rather than in a nearby
	# assertion about publication order or IDs.
	var alpha := d.make_car_car_builder().build()
	var beta := d.make_car_car_other_builder().build()
	d.check(alpha != null and beta != null, "pairing.fixtures_built")
	if alpha == null or beta == null:
		return
	var negative_controls: Array[String] = []

	# Positive path: reciprocal participants under one shared link and tick.
	d.check(alpha.is_opposite_perspective(beta), "pairing.reciprocal_pair_accepted")
	d.check(beta.is_opposite_perspective(alpha), "pairing.reciprocal_pair_is_symmetric")

	# A record is never its own opposite, and a missing record is not one.
	d.check(not alpha.is_opposite_perspective(alpha), "pairing.record_is_not_its_own_opposite")
	d.check(not alpha.is_opposite_perspective(null), "pairing.null_other_refused")

	# Unrelated pair sharing the link, tick and link status: A->B beside C->D.
	# Differing primaries alone used to be enough to call this a pair.
	var unrelated := d.make_unrelated_pair_builder().build()
	d.check(unrelated != null, "pairing.unrelated_pair_built")
	if unrelated != null:
		negative_controls.append("unrelated_pair_sharing_link")
	if unrelated != null:
		d.check(
			unrelated.contact_id == alpha.contact_id and unrelated.tick_index == alpha.tick_index,
			"pairing.unrelated_pair_shares_link_and_tick"
		)
		d.check(
			unrelated.primary_car_id != alpha.primary_car_id
				and unrelated.event_id != alpha.event_id,
			"pairing.unrelated_pair_differs_only_in_identity"
		)
		d.check(not alpha.is_opposite_perspective(unrelated), "pairing.unrelated_pair_refused")
		d.check(not unrelated.is_opposite_perspective(alpha), "pairing.unrelated_pair_refused_reverse")
		d.check(not beta.is_opposite_perspective(unrelated), "pairing.unrelated_pair_not_a_pair_of_beta")

	# Non-reciprocal chain: one real primary, a third car as other.
	var nonreciprocal := d.make_nonreciprocal_builder().build()
	d.check(nonreciprocal != null, "pairing.nonreciprocal_built")
	if nonreciprocal != null:
		negative_controls.append("nonreciprocal_participants")
	if nonreciprocal != null:
		d.check(
			not beta.is_opposite_perspective(nonreciprocal),
			"pairing.nonreciprocal_primary_refused"
		)
		d.check(
			not nonreciprocal.is_opposite_perspective(beta),
			"pairing.nonreciprocal_other_refused"
		)

	# Two wall records that share the contact link and tick. Neither has a
	# second car, so neither has an opposite perspective.
	var wall_alpha := d.make_wall_linked_builder(
		ImpactLabChecks.WALL_LINKED_ALPHA_EVENT_ID, ImpactLabChecks.PRIMARY_CAR_ID
	).build()
	var wall_beta := d.make_wall_linked_builder(
		ImpactLabChecks.WALL_LINKED_BETA_EVENT_ID, ImpactLabChecks.OTHER_CAR_ID
	).build()
	d.check(wall_alpha != null and wall_beta != null, "pairing.wall_linked_built")
	if wall_alpha != null and wall_beta != null:
		negative_controls.append("two_wall_records_sharing_link")
		d.check(wall_alpha.has_contact_link(), "pairing.wall_record_carries_the_link")
		d.check(not wall_alpha.has_other_car(), "pairing.wall_record_has_no_other_car")
		d.check(
			wall_alpha.contact_id == wall_beta.contact_id
				and wall_alpha.tick_index == wall_beta.tick_index,
			"pairing.wall_records_share_link_and_tick"
		)
		d.check(
			not wall_alpha.is_opposite_perspective(wall_beta),
			"pairing.two_wall_records_refused"
		)
		d.check(
			not wall_beta.is_opposite_perspective(wall_alpha),
			"pairing.two_wall_records_refused_reverse"
		)
		d.check(not alpha.is_opposite_perspective(wall_alpha), "pairing.car_and_wall_refused")
		d.check(not wall_beta.is_opposite_perspective(alpha), "pairing.wall_and_car_refused")

	# The tick and link rules survive: a true pair at another tick, or without a
	# shared link, is still refused.
	var later_beta := beta.copy()
	later_beta.tick_index = ImpactLabChecks.CAR_CAR_TICK + 1
	negative_controls.append("different_tick")
	d.check(not alpha.is_opposite_perspective(later_beta), "pairing.different_tick_refused")
	var unlinked_beta := beta.copy()
	unlinked_beta.contact_id = ""
	negative_controls.append("missing_contact_link")
	d.check(not alpha.is_opposite_perspective(unlinked_beta), "pairing.missing_link_refused")
	d.check(not alpha.is_opposite_perspective(unlinked_beta.copy()), "pairing.unlinked_records_refused")
	var reused_id_beta := beta.copy()
	reused_id_beta.event_id = alpha.event_id
	negative_controls.append("shared_event_id")
	d.check(not alpha.is_opposite_perspective(reused_id_beta), "pairing.same_event_id_refused")

	# A record whose other car is its own primary cannot pair with anything,
	# including a mirror of itself, even though it is directly constructible.
	var self_paired := alpha.copy()
	self_paired.other_car_id = self_paired.primary_car_id
	negative_controls.append("self_perspective")
	d.check(not self_paired.is_opposite_perspective(self_paired.copy()), "pairing.self_perspective_refused")

	negative_controls.append("null_other")
	measurements["pairing_negative_controls"] = negative_controls.size()


func _case_duplicate_perspective_pair_refused() -> void:
	# A producer retry that keeps the (contact_id, primary_car_id) pair but
	# allocates a new event_id must be refused explicitly, not published twice.
	var ledger := d.make_ledger()
	var first := d.make_car_car_builder().build()
	var retry := d.make_duplicate_perspective_builder().build()
	d.check(first != null and retry != null, "dup_pair.fixtures_built")
	if first == null or retry == null:
		return
	d.check(retry.event_id != first.event_id, "dup_pair.retry_uses_a_new_event_id")
	d.check(retry.contact_id == first.contact_id, "dup_pair.retry_shares_the_contact")
	d.check(retry.primary_car_id == first.primary_car_id, "dup_pair.retry_shares_the_primary")
	d.check(not retry.same_payload(first), "dup_pair.retry_is_a_distinct_record")
	d.check(not ledger.has_event_id(retry.event_id), "dup_pair.retry_id_is_unretained")

	d.check(ledger.publish(first).is_published(), "dup_pair.first_published")
	var base_digest := ledger.content_digest()
	var before_refused := ledger.refused_count
	var outcome := ledger.publish(retry)
	d.check(outcome.is_refused(), "dup_pair.retry_refused")
	d.check(
		outcome.reason.begins_with("duplicate perspective for contact"),
		"dup_pair.reason_names_the_pair"
	)
	d.check(outcome.event == null, "dup_pair.refusal_returns_no_record")
	d.check(ledger.refused_count == before_refused + 1, "dup_pair.refusal_counted")
	d.check(ledger.conflict_count == 0, "dup_pair.not_counted_as_an_id_conflict")
	d.check(ledger.published_count == 1, "dup_pair.nothing_new_published")
	d.check(ledger.coalesced_count == 0, "dup_pair.nothing_coalesced")
	d.check(ledger.event_count() == 1, "dup_pair.no_second_record")
	d.check(ledger.content_digest() == base_digest, "dup_pair.retained_content_unchanged")
	d.check(ledger.has_event_id(first.event_id), "dup_pair.first_id_still_retained")
	d.check(not ledger.has_event_id(retry.event_id), "dup_pair.refused_id_not_retained")
	var retained := ledger.find_by_id(first.event_id)
	d.check(retained != null, "dup_pair.first_record_retained")
	if retained != null:
		d.check_string(
			retained.event_id, first.event_id, "dup_pair.retained_identity_unchanged"
		)
		d.check_exact_float(
			retained.severity_m_s, first.severity_m_s, "dup_pair.retained_payload_unchanged"
		)

	# The complementary record of the other primary car still publishes: the
	# rule keys on the pair, not on the contact.
	var other := d.make_car_car_other_builder().build()
	d.check(other != null, "dup_pair.complementary_built")
	if other != null:
		d.check(ledger.publish(other).is_published(), "dup_pair.complementary_published")
		d.check(ledger.event_count() == 2, "dup_pair.both_perspectives_retained")

	# An identical retry of the retained ID still coalesces: ID duplicate
	# detection runs before the pair check, so the safe retry path is unchanged.
	var identical := d.make_car_car_builder().build()
	var identical_outcome := ledger.publish(identical)
	d.check(identical_outcome.is_coalesced(), "dup_pair.identical_retry_still_coalesces")
	d.check(ledger.event_count() == 2, "dup_pair.coalesce_adds_nothing")
	d.check(ledger.coalesced_count == 1, "dup_pair.coalesce_counted_once")

	# Records without a contact link never enter the pair index, so two wall
	# records of the same primary car cannot collide with each other.
	var wall_first := d.make_front_builder().build()
	var wall_second := d.make_rear_builder().build()
	d.check(wall_first != null and wall_second != null, "dup_pair.unlinked_fixtures_built")
	if wall_first != null and wall_second != null:
		d.check(ledger.publish(wall_first).is_published(), "dup_pair.unlinked_first_publishes")
		d.check(ledger.publish(wall_second).is_published(), "dup_pair.unlinked_second_publishes")
		d.check(ledger.event_count() == 4, "dup_pair.unlinked_records_do_not_collide")

	# The pair key is bounded by the retained window exactly like the ID set.
	var bounded := d.make_ledger(4, 2)
	var bounded_first := d.make_car_car_builder().build()
	d.check(bounded_first != null, "dup_pair.bounded_first_built")
	if bounded_first != null:
		d.check(bounded.publish(bounded_first).is_published(), "dup_pair.bounded_first_published")
		var bounded_retry := d.make_duplicate_perspective_builder().build()
		d.check(
			bounded.publish(bounded_retry).is_refused(),
			"dup_pair.bounded_retry_refused_while_retained"
		)
		d.check(bounded.event_count() == 1, "dup_pair.bounded_no_second_record")
		# Push the contact tick out of the retained window.
		d.check(bounded.publish(d.make_lab_event("pair-tick8-a", 8)).is_published(), "dup_pair.tick_eight_first")
		d.check(bounded.publish(d.make_lab_event("pair-tick8-b", 8)).is_published(), "dup_pair.tick_eight_second")
		d.check(bounded.publish(d.make_lab_event("pair-tick9-a", 9)).is_published(), "dup_pair.tick_nine_published")
		d.check(bounded.tick_count() == 2, "dup_pair.window_bounded")
		d.check(not bounded.has_event_id(first.event_id), "dup_pair.pruned_id_forgotten")
		# The same pair, at the current tick, now publishes as a fresh record.
		var replayed := d.make_duplicate_perspective_builder().build()
		if replayed != null:
			replayed.tick_index = 9
		var replay_outcome := bounded.publish(replayed)
		d.check(replay_outcome.is_published(), "dup_pair.pruned_pair_publishes_fresh")
		d.check(
			bounded.publish(replayed.copy()).is_coalesced(),
			"dup_pair.replayed_pair_retained_again"
		)

	# A reset forgets the pair key as well, so the pair publishes again.
	bounded.reset()
	d.check(bounded.event_count() == 0, "dup_pair.reset_clears_records")
	var after_reset := d.make_duplicate_perspective_builder().build()
	if after_reset != null:
		after_reset.tick_index = 9
	d.check(bounded.publish(after_reset).is_published(), "dup_pair.reset_pair_publishes_fresh")

	measurements["duplicate_perspective_refusals"] = ledger.refused_count


func _case_ambiguous_separator_pair_keys() -> void:
	# Direct negative ledger control for the pair-key encoding. The contract
	# forbids no character in a semantic ID, so two valid, distinct
	# perspectives encode identically under any single-separator join of
	# (contact_id, primary_car_id): ("a\u001fb", "c") and ("a", "b\u001fc").
	# A separator-joined key refuses the second record as a duplicate
	# perspective and loses it; an unambiguous key publishes both.
	var ledger := d.make_ledger()
	var first := d.make_ambiguous_pair_builder(
		ImpactLabChecks.AMBIGUOUS_FIRST_EVENT_ID,
		ImpactLabChecks.AMBIGUOUS_CONTACT_A,
		ImpactLabChecks.AMBIGUOUS_PRIMARY_A
	).build()
	var second := d.make_ambiguous_pair_builder(
		ImpactLabChecks.AMBIGUOUS_SECOND_EVENT_ID,
		ImpactLabChecks.AMBIGUOUS_CONTACT_B,
		ImpactLabChecks.AMBIGUOUS_PRIMARY_B
	).build()
	d.check(first != null and second != null, "ambig.fixtures_built")
	if first == null or second == null:
		return
	d.check(first.is_valid(), "ambig.first_valid")
	d.check(second.is_valid(), "ambig.second_valid")
	d.check(
		first.contact_id != second.contact_id
			or first.primary_car_id != second.primary_car_id,
		"ambig.pairs_are_distinct"
	)
	# The collision a single-separator encoding would have: joining either
	# pair with one U+001F produces the same string, so the encoding under
	# test must not be a plain join.
	d.check(
		(first.contact_id + "\u001f" + first.primary_car_id)
			== (second.contact_id + "\u001f" + second.primary_car_id),
		"ambig.separator_encoding_would_collide"
	)

	d.check(ledger.publish(first).is_published(), "ambig.first_published")
	var after_first := ledger.content_digest()
	d.check(ledger.publish(second).is_published(), "ambig.second_published")
	d.check(ledger.event_count() == 2, "ambig.both_retained")
	d.check(ledger.coalesced_count == 0, "ambig.nothing_coalesced")
	d.check(ledger.conflict_count == 0, "ambig.nothing_conflicted")
	d.check(
		ledger.content_digest() != after_first,
		"ambig.second_record_reaches_the_content_digest"
	)

	var retained_first := ledger.find_by_id(ImpactLabChecks.AMBIGUOUS_FIRST_EVENT_ID)
	var retained_second := ledger.find_by_id(ImpactLabChecks.AMBIGUOUS_SECOND_EVENT_ID)
	d.check(retained_first != null, "ambig.first_retained")
	d.check(retained_second != null, "ambig.second_retained")
	if retained_first != null:
		d.check_string(
			retained_first.contact_id, ImpactLabChecks.AMBIGUOUS_CONTACT_A,
			"ambig.retained_first_contact"
		)
		d.check_string(
			retained_first.primary_car_id, ImpactLabChecks.AMBIGUOUS_PRIMARY_A,
			"ambig.retained_first_primary"
		)
	if retained_second != null:
		d.check_string(
			retained_second.contact_id, ImpactLabChecks.AMBIGUOUS_CONTACT_B,
			"ambig.retained_second_contact"
		)
		d.check_string(
			retained_second.primary_car_id, ImpactLabChecks.AMBIGUOUS_PRIMARY_B,
			"ambig.retained_second_primary"
		)

	# A true retry of the FIRST pair under a new event ID is still a duplicate
	# perspective: refused, counted once in refused_count only, and the
	# retained content digest is unchanged.
	var retry := d.make_ambiguous_retry_builder().build()
	d.check(retry != null, "ambig.retry_built")
	if retry != null:
		d.check(retry.event_id != first.event_id, "ambig.retry_uses_a_new_event_id")
		d.check(
			retry.contact_id == first.contact_id
				and retry.primary_car_id == first.primary_car_id,
			"ambig.retry_is_the_same_pair"
		)
		var before_digest := ledger.content_digest()
		var before_refused := ledger.refused_count
		var retry_outcome := ledger.publish(retry)
		d.check(retry_outcome.is_refused(), "ambig.retry_refused")
		d.check(
			retry_outcome.reason.begins_with("duplicate perspective for contact"),
			"ambig.retry_reason_names_the_pair"
		)
		d.check(
			ledger.refused_count == before_refused + 1,
			"ambig.retry_counted_once"
		)
		d.check(ledger.conflict_count == 0, "ambig.retry_not_an_id_conflict")
		d.check(ledger.event_count() == 2, "ambig.retry_adds_nothing")
		d.check(
			ledger.content_digest() == before_digest,
			"ambig.retry_leaves_content_unchanged"
		)
		d.check(not ledger.has_event_id(retry.event_id), "ambig.retry_id_not_retained")

	# The symmetric retry of the SECOND pair is refused the same way, so the
	# unambiguous key refuses neither pair's genuine retry.
	var retry_b := d.make_ambiguous_retry_b_builder().build()
	d.check(retry_b != null, "ambig.retry_b_built")
	if retry_b != null:
		var before_b_digest := ledger.content_digest()
		var retry_b_outcome := ledger.publish(retry_b)
		d.check(retry_b_outcome.is_refused(), "ambig.retry_b_refused")
		d.check(ledger.event_count() == 2, "ambig.retry_b_adds_nothing")
		d.check(
			ledger.content_digest() == before_b_digest,
			"ambig.retry_b_leaves_content_unchanged"
		)

	# The complementary perspective of the first pair still publishes: the pair
	# index distinguishes perspectives, it does not block the second car.
	var complement := d.make_ambiguous_complement_builder().build()
	d.check(complement != null, "ambig.complement_built")
	if complement != null:
		d.check(
			complement.is_opposite_perspective(first),
			"ambig.complement_is_the_opposite_perspective"
		)
		d.check(ledger.publish(complement).is_published(), "ambig.complement_published")
		d.check(ledger.event_count() == 3, "ambig.complement_retained")

	measurements["ambiguous_pairs_retained"] = ledger.event_count()


func _case_duplicate_event_id() -> void:
	# An identical retry, same ID and the same payload in every field, is a
	# safe producer retry and coalesces against the retained record.
	var first := d.make_front_builder().build()
	var retry := d.make_front_builder().build()
	d.check(first != null and retry != null, "duplicate.fixtures_built")
	if first == null or retry == null:
		return
	d.check(first.same_payload(retry), "duplicate.retry_is_identical")

	var ledger := d.make_ledger()
	var first_outcome := ledger.publish(first)
	d.check(first_outcome.is_published(), "duplicate.first_published")
	var second_outcome := ledger.publish(retry)
	d.check(second_outcome.is_coalesced(), "duplicate.second_coalesced_not_added")
	d.check(ledger.coalesced_count == 1, "duplicate.coalesced_count")
	d.check(ledger.conflict_count == 0, "duplicate.no_conflict_for_identical_retry")
	d.check(ledger.event_count() == 1, "duplicate.event_count_stays_one")
	var retained := ledger.find_by_id(ImpactLabChecks.FRONT_EVENT_ID)
	d.check(retained != null, "duplicate.retained_lookup")
	if retained != null:
		d.check_exact_float(retained.severity_m_s, ImpactLabChecks.FRONT_SEVERITY, "duplicate.first_wins")

	var third_outcome := ledger.publish(d.make_front_builder().build())
	d.check(third_outcome.is_coalesced(), "duplicate.repeat_still_coalesced")
	d.check(ledger.coalesced_count == 2, "duplicate.coalesced_count_stable")
	d.check(ledger.event_count() == 1, "duplicate.repeat_adds_nothing")


func _case_conflicting_duplicate_refused() -> void:
	# A conflicting payload under a retained ID must refuse and be counted. It
	# is never silently discarded and never overwrites the retained record.
	var ledger := d.make_ledger()
	var first := d.make_front_builder().build()
	d.check(first != null, "conflict.base_built")
	if first == null:
		return
	d.check(ledger.publish(first).is_published(), "conflict.base_published")
	var base_digest := ledger.content_digest()
	var expected_conflicts := 0

	for probe in CONFLICT_PROBES:
		var field: String = probe["field"]
		var value: Variant = probe["value"]
		var conflicting := d.make_front_builder().build()
		if conflicting == null:
			d.check(false, "conflict.%s.built" % field)
			continue
		conflicting.set(field, value)
		var outcome := ledger.publish(conflicting)
		expected_conflicts += 1
		d.check(outcome.is_refused(), "conflict.%s.refused" % field)
		d.check(
			outcome.reason.begins_with("conflicting payload for event id"),
			"conflict.%s.reason_names_conflict" % field
		)
		d.check(
			ledger.conflict_count == expected_conflicts,
			"conflict.%s.conflict_count" % field
		)
		d.check(
			ledger.refused_count == expected_conflicts,
			"conflict.%s.refused_count" % field
		)
		d.check(ledger.event_count() == 1, "conflict.%s.no_second_record" % field)
		d.check(
			ledger.content_digest() == base_digest,
			"conflict.%s.retained_unchanged" % field
		)

	# Cross-tick conflict: the same ID published at a later tick is a
	# different record, not a retry.
	var later := d.make_front_builder().build()
	if later != null:
		later.tick_index = ImpactLabChecks.WALL_TICK + 1
	var later_outcome := ledger.publish(later)
	expected_conflicts += 1
	d.check(later_outcome.is_refused(), "conflict.cross_tick_refused")
	d.check(
		later_outcome.reason.begins_with("conflicting payload for event id"),
		"conflict.cross_tick_reason_names_conflict"
	)
	d.check(
		ledger.conflict_count == expected_conflicts,
		"conflict.cross_tick_conflict_count"
	)
	d.check(ledger.event_count() == 1, "conflict.cross_tick_no_second_record")

	# A record that is not even valid is refused as invalid, not as a
	# conflict, so the two refusal classes stay distinguishable.
	var invalid := d.make_front_builder().build()
	if invalid != null:
		invalid.committed = false
	var invalid_outcome := ledger.publish(invalid)
	d.check(invalid_outcome.is_refused(), "conflict.invalid_variant_refused")
	d.check(
		not invalid_outcome.reason.begins_with("conflicting payload"),
		"conflict.invalid_variant_not_reported_as_conflict"
	)
	d.check(
		ledger.conflict_count == expected_conflicts,
		"conflict.invalid_variant_does_not_raise_conflict_count"
	)

	d.check(
		ledger.state_digest().contains("conflicts=%d" % expected_conflicts),
		"conflict.state_digest_reports_conflicts"
	)
	measurements["conflicting_payloads_refused"] = expected_conflicts


func _case_duplicate_retention_window() -> void:
	# Duplicate detection is bounded by the retained window, not all-time.
	# An identical retry still coalesces at capacity; an ID that has been
	# pruned or reset publishes again as a fresh record.
	var ledger := d.make_ledger(2, 2)
	var first := d.make_lab_event("ret-1a", 1)
	var second := d.make_lab_event("ret-1b", 1)
	d.check(first != null and second != null, "retention.fixtures_built")
	if first == null or second == null:
		return
	d.check(ledger.publish(first).is_published(), "retention.first_published")
	d.check(ledger.publish(second).is_published(), "retention.second_published")

	# Identical retry at capacity coalesces rather than being refused.
	var retry := d.make_lab_event("ret-1a", 1)
	var retry_outcome := ledger.publish(retry)
	d.check(retry_outcome.is_coalesced(), "retention.identical_retry_coalesces_at_capacity")
	d.check(ledger.coalesced_count == 1, "retention.retry_counted_once")
	d.check(ledger.event_count() == 2, "retention.capacity_unchanged_by_retry")

	# Push tick 1 out of the retained window.
	d.check(ledger.publish(d.make_lab_event("ret-2a", 2)).is_published(), "retention.tick_two_first")
	d.check(ledger.publish(d.make_lab_event("ret-2b", 2)).is_published(), "retention.tick_two_second")
	d.check(ledger.publish(d.make_lab_event("ret-3a", 3)).is_published(), "retention.tick_three_published")
	d.check(ledger.tick_count() == 2, "retention.window_bounded")
	d.check(not ledger.has_event_id("ret-1a"), "retention.pruned_id_forgotten")
	d.check(ledger.has_event_id("ret-2a"), "retention.retained_id_remembered")

	# The forgotten ID now publishes as a fresh record instead of coalescing.
	var replayed := d.make_lab_event("ret-1a", 3)
	var replay_outcome := ledger.publish(replayed)
	d.check(replay_outcome.is_published(), "retention.pruned_id_publishes_fresh")
	d.check(
		ledger.coalesced_count == 1,
		"retention.replay_after_prune_is_not_coalesced"
	)
	d.check(ledger.event_count() == 4, "retention.replay_adds_a_record")

	# Reset forgets every retained ID as well.
	ledger.reset()
	d.check(not ledger.has_event_id("ret-2a"), "retention.reset_forgets_ids")
	var after_reset := d.make_lab_event("ret-2a", 3)
	var reset_outcome := ledger.publish(after_reset)
	d.check(reset_outcome.is_published(), "retention.reset_id_publishes_fresh")
	d.check(ledger.conflict_count == 0, "retention.reset_clears_conflict_count")
	d.check(ledger.coalesced_count == 0, "retention.reset_clears_coalesced_count")
	measurements["retained_ticks"] = ledger.tick_count()


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


func _case_digest_covers_every_field() -> void:
	# The content digest and the payload comparison must cover the whole
	# record, so an atomic-refusal control detects mutation of any published
	# field rather than a sampled subset.
	var base := d.make_front_builder().build()
	d.check(base != null, "digest.base_built")
	if base == null:
		return

	var reference := d.make_ledger()
	d.check(reference.publish(base).is_published(), "digest.base_published")
	var reference_digest := reference.content_digest()
	d.check(not reference_digest.is_empty(), "digest.nonempty_for_retained_event")

	var twin := d.make_ledger()
	d.check(twin.publish(base.copy()).is_published(), "digest.twin_published")
	d.check(
		twin.content_digest() == reference_digest,
		"digest.stable_for_identical_content"
	)

	for probe in PAYLOAD_PROBES:
		var field: String = probe["field"]
		var value: Variant = probe["value"]
		var variant := base.copy()
		variant.set(field, value)
		d.check(
			not base.same_payload(variant),
			"digest.payload_comparison_detects_%s" % field
		)
		var variant_ledger := d.make_ledger()
		d.check(
			variant_ledger.publish(variant).is_published(),
			"digest.variant_%s_published" % field
		)
		d.check(
			variant_ledger.content_digest() != reference_digest,
			"digest.detects_%s" % field
		)

	# The committed flag cannot differ inside a publishable record, so cover
	# it directly on the payload comparison instead.
	var uncommitted_copy := base.copy()
	uncommitted_copy.committed = false
	d.check(
		not base.same_payload(uncommitted_copy),
		"digest.payload_comparison_detects_committed"
	)


func _case_required_field_omission() -> void:
	# A completely default builder must report every required field as unset
	# and must refuse to build, so a forgotten field can never publish a
	# plausible-looking event.
	var pristine := ImpactEvent.Builder.new()
	var pristine_missing := pristine.missing_fields()
	for omission in OMISSION_REASONS:
		var required_field: String = omission["field"]
		d.check(
			pristine_missing.has(required_field),
			"omission.%s.default_is_unset" % required_field
		)
	d.check(pristine.build() == null, "omission.pristine_builder_refuses")
	d.check(
		not pristine.rejection_reason.is_empty(),
		"omission.pristine_refusal_has_reason"
	)

	# Each required field must refuse when it alone is left at its default,
	# even though a legal explicit value for the same field is valid. The
	# probed field is never assigned, so the test observes the shipped default
	# rather than a sentinel the test wrote itself.
	for omission in OMISSION_REASONS:
		var field: String = omission["field"]
		var expected_reason: String = omission["reason"]
		var builder := ImpactEvent.Builder.new()
		for entry in FIELD_VALUES:
			if String(entry["field"]) != field:
				_set_builder_field(builder, String(entry["field"]), entry["value"])
		d.check(
			builder.missing_fields().has(field),
			"omission.%s.reported_missing" % field
		)
		var event := builder.build()
		d.check(event == null, "omission.%s.refused" % field)
		d.check_string(
			builder.rejection_reason, expected_reason,
			"omission.%s.reason" % field
		)

	# The same field with an explicit legal zero must publish.
	for legal in ZERO_LEGAL_FIELDS:
		var legal_field: String = legal["field"]
		var legal_value: Variant = legal["value"]
		var zero_builder := ImpactEvent.Builder.new()
		for entry in FIELD_VALUES:
			var zero_field := String(entry["field"])
			_set_builder_field(
				zero_builder,
				zero_field,
				legal_value if zero_field == legal_field else entry["value"]
			)
		d.check(
			not zero_builder.missing_fields().has(legal_field),
			"omission.%s.zero_is_not_missing" % legal_field
		)
		var zero_event := zero_builder.build()
		d.check(zero_event != null, "omission.%s.zero_accepted" % legal_field)
		if zero_event != null:
			var ledger := d.make_ledger()
			d.check(
				ledger.publish(zero_event).is_published(),
				"omission.%s.zero_publishes" % legal_field
			)

	# A zero normal is not legal, so it must still refuse.
	var zero_normal_builder := d.make_front_builder()
	zero_normal_builder.contact_normal_world_m = Vector3.ZERO
	d.check(
		zero_normal_builder.build() == null,
		"omission.zero_normal_still_refused"
	)

	measurements["omission_fields"] = OMISSION_REASONS.size()
	measurements["zero_legal_fields"] = ZERO_LEGAL_FIELDS.size()


## Assigns one builder field from the shared fixture table. Every field the
## omission control can probe must appear here, so a field left out of the
## table fails loudly instead of silently passing.
func _set_builder_field(
	builder: ImpactEvent.Builder, field: String, value: Variant
) -> void:
	match field:
		"event_id":
			builder.event_id = String(value)
		"tick_index":
			builder.tick_index = int(value)
		"primary_car_id":
			builder.primary_car_id = String(value)
		"other_car_id":
			builder.other_car_id = String(value)
		"contact_id":
			builder.contact_id = String(value)
		"contact_point_world_m":
			builder.contact_point_world_m = value
		"contact_point_local_m":
			builder.contact_point_local_m = value
		"contact_normal_world_m":
			builder.contact_normal_world_m = value
		"severity_m_s":
			builder.severity_m_s = float(value)
		"post_contact_velocity_world_m_s":
			builder.post_contact_velocity_world_m_s = value
		"imparted_motion_m":
			builder.imparted_motion_m = value
		"region":
			builder.region = value
		"normal_mode":
			builder.normal_mode = value
		"source_committed":
			builder.source_committed = bool(value)
		_:
			d.check(false, "unknown builder field %s" % field)


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
		# Scope note: this proves the record carries the value the integrator
		# supplied, and that a contact-only value is distinguishable from a
		# motor-acceleration value. It does not and cannot prove that the
		# integrator derived the value from the committed contact response.
		measurements["derivation_verified"] = false


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
	# The wall-point job adds an authoritative wall contact point, so the old
	# tripwire that forbade the token outright is retired: the seam is
	# accepted. What stays refused is any claim that an impact publisher
	# already exists, because the adapter is a contact-response component,
	# not an event producer, and the seam still has no consumer here.
	d.check(
		adapter_source.contains("wall_contact_normal"),
		"floor_first.adapter_exposes_authoritative_wall_normal"
	)
	var has_wall_point: bool = adapter_source.contains("wall_contact_point")
	measurements["adapter_wall_contact_point_present"] = has_wall_point
	if has_wall_point:
		# A zero default must never be mistaken for an authoritative contact,
		# so the point has to carry an explicit witness flag.
		d.check(
			adapter_source.contains("has_wall_contact_point"),
			"floor_first.wall_point_carries_explicit_witness_flag"
		)
	else:
		d.check(
			adapter_source.contains("floor or ceiling"),
			"floor_first.adapter_documents_missing_wall_point_hazard"
		)
	for publisher_token in ["ImpactEvent", "impact_event", "ImpactLab", "event_id"]:
		d.check(
			not adapter_source.contains(publisher_token),
			"floor_first.adapter_is_not_an_impact_publisher_%s"
				% publisher_token.to_lower()
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
		"add_child(",
		"get_tree()",
		"move_and_slide",
		"ResourceLoader",
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
	d.check(
		code.contains("COORDINATOR_ASSIGNED_FIELDS"),
		"surface.coordinator_assigned_fields_machine_readable"
	)
	# Commitment is documented as a caller assertion, not as proof.
	d.check(
		source.contains("caller assertion"),
		"surface.commitment_documented_as_caller_assertion"
	)
	d.check(
		code.contains("source_committed"),
		"surface.commitment_flag_is_a_plain_boolean"
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

	# An out-of-domain normal mode must refuse rather than fall through to a
	# default branch.
	builder.contact_normal_world_m = ImpactLabChecks.FRONT_NORMAL
	builder.normal_mode = 99
	var bad_mode := builder.build()
	d.check(bad_mode == null, "normalize.unknown_mode_refused")
	d.check_string(builder.rejection_reason, "invalid normal mode", "normalize.unknown_mode_reason")


func _case_large_finite_vector_domain() -> void:
	# Finite admitted vectors must never produce INF or NaN in an exported
	# derived magnitude or in normalization, even where squaring a component
	# overflows the engine's 32-bit float vector range.
	var huge := Vector3(1e20, 0.0, 0.0)
	var huge_norm := ImpactEvent.stable_norm(huge)
	d.check(is_finite(huge_norm), "domain.scaled_norm_is_finite")
	# `Vector3` stores 32-bit floats, so 1e20 is already rounded on entry. The
	# scaled norm must return that stored component exactly, with no overflow.
	d.check_exact_float(huge_norm, huge.x, "domain.scaled_norm_matches_component")
	d.check_relative_close(huge_norm, 1e20, 1e-6, "domain.scaled_norm_value")
	d.check(
		not is_finite(huge.length()),
		"domain.plain_length_would_overflow"
	)
	var mixed := Vector3(1e20, 1e20, 0.0)
	var mixed_norm := ImpactEvent.stable_norm(mixed)
	d.check(is_finite(mixed_norm), "domain.mixed_scaled_norm_is_finite")
	d.check_relative_close(
		mixed_norm, sqrt(2.0) * 1e20, 1e-6, "domain.mixed_scaled_norm_value"
	)

	var probe := ImpactEvent.new()
	probe.imparted_motion_m = huge
	var magnitude := probe.imparted_motion_magnitude_m()
	d.check(is_finite(magnitude), "domain.exported_magnitude_is_finite")
	d.check_exact_float(magnitude, huge.x, "domain.exported_magnitude_matches_component")
	d.check_relative_close(magnitude, 1e20, 1e-6, "domain.exported_magnitude_value")

	var builder := d.make_front_builder()
	builder.severity_m_s = 0.0
	builder.imparted_motion_m = huge
	builder.post_contact_velocity_world_m_s = Vector3(1e19, 0.0, -1e19)
	builder.contact_point_world_m = Vector3(1e18, 1e18, 1e18)
	builder.contact_point_local_m = Vector3(-1e18, 0.0, 1e18)
	var event := builder.build()
	d.check(event != null, "domain.large_finite_event_builds")
	if event != null:
		var exported: Variant = event.to_dict()["imparted_motion_magnitude_m"]
		d.check(is_finite(float(exported)), "domain.exported_dict_magnitude_is_finite")
		var ledger := d.make_ledger()
		d.check(ledger.publish(event).is_published(), "domain.large_finite_event_publishes")

	# NORMALIZE must accept a very large finite normal instead of overflowing
	# into a zero vector.
	var normalize_builder := d.make_front_builder()
	normalize_builder.contact_normal_world_m = huge
	normalize_builder.normal_mode = ImpactEvent.NormalMode.NORMALIZE
	var normalized_huge := normalize_builder.build()
	d.check(normalized_huge != null, "domain.huge_normal_normalizes")
	if normalized_huge != null:
		d.check_vector_close(
			normalized_huge.contact_normal_world_m, Vector3(1.0, 0.0, 0.0), 1e-6,
			"domain.huge_normal_direction_preserved"
		)

	# PRESERVE must report a genuinely nonunit normal, not a spurious zero.
	var preserve_builder := d.make_front_builder()
	preserve_builder.contact_normal_world_m = huge
	preserve_builder.normal_mode = ImpactEvent.NormalMode.PRESERVE
	var preserved_huge := preserve_builder.build()
	d.check(preserved_huge == null, "domain.huge_normal_preserve_refused")
	d.check_string(
		preserve_builder.rejection_reason, "nonunit contact normal",
		"domain.huge_normal_preserve_reason_is_nonunit"
	)

	# Diagonal huge finite values: the edge an axis-aligned control cannot
	# reach. Every component fits the engine's 32-bit float vector range, but
	# the norm is about sqrt(2) times larger and stays finite only as a 64-bit
	# script scalar.
	var diagonal := Vector3(3e38, 3e38, 0.0)
	var diagonal_norm := ImpactEvent.stable_norm(diagonal)
	d.check(is_finite(diagonal_norm), "domain.diagonal_scaled_norm_is_finite")
	d.check(diagonal_norm > 3.4e38, "domain.diagonal_norm_exceeds_float32_range")
	d.check_relative_close(
		diagonal_norm, sqrt(2.0) * 3e38, 1e-6, "domain.diagonal_norm_value"
	)
	# Engine control for the hazard being defended against: on the pinned build
	# the vector division converts that divisor to a 32-bit float first, which
	# overflows to INF and collapses the quotient to zero. A build whose
	# Vector3 division keeps the wider scalar would fail this control, and the
	# control would then need re-deriving rather than deleting.
	d.check_vector_close(
		diagonal / diagonal_norm, Vector3.ZERO, 0.0,
		"domain.vector_division_by_scaled_norm_collapses"
	)

	var diagonal_builder := d.make_front_builder()
	diagonal_builder.contact_normal_world_m = diagonal
	diagonal_builder.normal_mode = ImpactEvent.NormalMode.NORMALIZE
	var diagonal_event := diagonal_builder.build()
	d.check(diagonal_event != null, "domain.diagonal_huge_normal_normalizes")
	if diagonal_event != null:
		var unit: Vector3 = diagonal_event.contact_normal_world_m
		d.check_finite_vector(unit, "domain.diagonal_normal_is_finite")
		d.check_close(unit.length(), 1.0, 1e-6, "domain.diagonal_normal_is_unit_length")
		d.check_vector_close(
			unit, Vector3(1.0 / sqrt(2.0), 1.0 / sqrt(2.0), 0.0), 1e-6,
			"domain.diagonal_normal_direction_preserved"
		)
		d.check(diagonal_event.is_valid(), "domain.diagonal_normal_event_valid")
		d.check_string(
			diagonal_event.validation_error(), "",
			"domain.diagonal_normal_has_no_validation_error"
		)

	# Mixed signs: the direction rule must carry the sign of each component.
	var signed := Vector3(-3e38, 3e38, 0.0)
	var signed_builder := d.make_front_builder()
	signed_builder.contact_normal_world_m = signed
	signed_builder.normal_mode = ImpactEvent.NormalMode.NORMALIZE
	var signed_event := signed_builder.build()
	d.check(signed_event != null, "domain.signed_diagonal_normal_normalizes")
	if signed_event != null:
		var signed_unit: Vector3 = signed_event.contact_normal_world_m
		d.check_finite_vector(signed_unit, "domain.signed_diagonal_normal_is_finite")
		d.check_vector_close(
			signed_unit, Vector3(-1.0 / sqrt(2.0), 1.0 / sqrt(2.0), 0.0), 1e-6,
			"domain.signed_diagonal_normal_direction_preserved"
		)

	# PRESERVE must still classify the diagonal as nonunit, never as zero.
	var diagonal_preserve := d.make_front_builder()
	diagonal_preserve.contact_normal_world_m = diagonal
	diagonal_preserve.normal_mode = ImpactEvent.NormalMode.PRESERVE
	var preserved_diagonal := diagonal_preserve.build()
	d.check(preserved_diagonal == null, "domain.diagonal_normal_preserve_refused")
	d.check_string(
		diagonal_preserve.rejection_reason, "nonunit contact normal",
		"domain.diagonal_normal_preserve_reason_is_nonunit"
	)
	measurements["scaled_norm_of_diagonal_3e38"] = diagonal_norm
	measurements["scaled_norm_of_1e20"] = huge_norm


func _case_ledger_settings_immutable() -> void:
	# The capacity settings must not be mutable public properties after
	# construction, and their effective values must be revalidated so a
	# post-init change cannot report a publication that is pruned at once.
	var ledger := d.make_ledger(4, 3)
	d.check(ledger.per_tick_capacity() == 4, "settings.constructed_capacity")
	d.check(ledger.max_retained_ticks() == 3, "settings.constructed_retained_ticks")
	var property_names := _property_names(ledger)
	d.check(
		not property_names.has("per_tick_capacity"),
		"settings.capacity_has_no_public_property"
	)
	d.check(
		not property_names.has("max_retained_ticks"),
		"settings.retained_ticks_has_no_public_property"
	)
	d.check(ledger.per_tick_capacity() == 4, "settings.capacity_unchanged")
	d.check(ledger.max_retained_ticks() == 3, "settings.retained_ticks_unchanged")

	var event := d.make_lab_event("settings-1", 1)
	d.check(event != null, "settings.event_built")
	if event != null:
		d.check(ledger.publish(event).is_published(), "settings.published")
		d.check(
			ledger.event_count() == 1,
			"settings.publication_is_not_pruned_immediately"
		)
		d.check(ledger.tick_count() == 1, "settings.tick_retained")

	# Degenerate constructor arguments clamp instead of disabling the ledger.
	var degenerate := d.make_ledger(-5, -7)
	d.check(degenerate.per_tick_capacity() == 0, "settings.negative_capacity_clamped")
	d.check(degenerate.max_retained_ticks() == 1, "settings.zero_retained_ticks_clamped")
	var degenerate_outcome := degenerate.publish(d.make_lab_event("settings-2", 1))
	d.check(
		degenerate_outcome.is_refused(),
		"settings.zero_capacity_refuses_rather_than_publishing"
	)
	measurements["retained_tick_lower_bound"] = degenerate.max_retained_ticks()


## Names of the settable properties a ledger currently exposes. Used to prove
## the capacity settings are not part of that surface after construction.
func _property_names(ledger: ImpactEvent.Ledger) -> Array[String]:
	var names: Array[String] = []
	for property in ledger.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(String(property["name"]))
	return names


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
