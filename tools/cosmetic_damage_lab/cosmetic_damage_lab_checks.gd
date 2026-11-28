class_name CosmeticDamageLabChecks
extends RefCounted
## Discriminatory checks for the cosmetic damage part-state reducer.
## Uses real ImpactEvent records and the real CosmeticDamageState API only.

const CAR_A := "car-a"
const CAR_B := "car-b"
const CAR_C := "car-c"

const FRONT := CosmeticDamageState.PartSlot.FRONT_BUMPER
const REAR := CosmeticDamageState.PartSlot.REAR_BUMPER
const WING := CosmeticDamageState.PartSlot.WING
const INTACT := CosmeticDamageState.PartCondition.INTACT
const LOOSE := CosmeticDamageState.PartCondition.LOOSE
const DETACHED := CosmeticDamageState.PartCondition.DETACHED
const NONE_ACTION := CosmeticDamageState.ActionType.NONE
const LOOSE_ACTION := CosmeticDamageState.ActionType.LOOSE
const DETACH_ACTION := CosmeticDamageState.ActionType.DETACH
const NO_PART := CosmeticDamageState.RefusalCode.NO_PART_AT_CONTACT
const DUPLICATE_CONFLICT := CosmeticDamageState.RefusalCode.DUPLICATE_EVENT_CONFLICT
const TICK_OUT_OF_ORDER := CosmeticDamageState.RefusalCode.TICK_OUT_OF_ORDER

class Case extends RefCounted:
	var name := ""
	var checks := 0
	var failures: Array[String] = []
	var measurements: Dictionary = {}

	func check(condition: bool, message: String) -> void:
		checks += 1
		if not condition:
			failures.append(message)

	func equal(actual, expected, message: String) -> void:
		checks += 1
		if actual != expected:
			failures.append("%s (got %s expected %s)" % [message, str(actual), str(expected)])

	func result() -> Dictionary:
		return {
			"case": name,
			"pass": failures.is_empty(),
			"checks": checks,
			"checks_failed": failures.size(),
			"failures": failures.duplicate(),
			"measurements": measurements.duplicate(),
		}

var cases_run := 0
var total_checks := 0
var total_failures := 0
var case_results: Array[Dictionary] = []

func run_all() -> Dictionary:
	for call in [
		Callable(self, "_case_loosen_boundary"),
		Callable(self, "_case_single_detach_boundary"),
		Callable(self, "_case_accumulated_detach"),
		Callable(self, "_case_configure_copies_caller_regions"),
		Callable(self, "_case_post_detach_no_overflow"),
		Callable(self, "_case_part_selection"),
		Callable(self, "_case_no_part_atomic"),
		Callable(self, "_case_exact_replay_and_conflict"),
		Callable(self, "_case_contact_coalescing"),
		Callable(self, "_case_out_of_order"),
		Callable(self, "_case_effect_cooldown"),
		Callable(self, "_case_reset"),
		Callable(self, "_case_effects_toggle"),
	]:
		var result: Dictionary = call.call()
		case_results.append(result)
		cases_run += 1
		total_checks += int(result["checks"])
		total_failures += int(result["checks_failed"])
		print(
			"COSMETIC_DAMAGE_LAB_CASE ",
			JSON.stringify({
				"case": result["case"],
				"checks": result["checks"],
				"checks_failed": result["checks_failed"],
				"pass": result["pass"],
			})
		)
	return {
		"schema": "roadstorm.cosmetic_damage_lab.summary.v1",
		"pass": total_failures == 0,
		"cases": cases_run,
		"cases_passed": cases_run - _failed_case_count(),
		"checks": total_checks,
		"checks_failed": total_failures,
		"case_results": case_results.duplicate(),
	}

func _failed_case_count() -> int:
	var failed := 0
	for result in case_results:
		if not bool(result["pass"]):
			failed += 1
	return failed

static func _make_event(
	event_id: String,
	car_id: String,
	tick: int,
	severity: float,
	local_point: Vector3,
	region: int,
	contact_id: String = ""
) -> ImpactEvent:
	var builder := ImpactEvent.Builder.new()
	builder.event_id = event_id
	builder.tick_index = tick
	builder.primary_car_id = car_id
	builder.contact_point_world_m = Vector3.ZERO
	builder.contact_point_local_m = local_point
	builder.contact_normal_world_m = Vector3(-1.0, 0.0, 0.0)
	builder.severity_m_s = severity
	builder.post_contact_velocity_world_m_s = Vector3.ZERO
	builder.imparted_motion_m = Vector3.ZERO
	builder.region = region
	builder.source_committed = true
	if not contact_id.is_empty():
		builder.contact_id = contact_id
	return builder.build()

static func _make_reducer(has_wing: bool) -> CosmeticDamageState:
	var reducer := CosmeticDamageState.new()
	reducer.configure_car(CAR_A, has_wing)
	return reducer

static func _region_with_slot(slot: int) -> CosmeticDamageState.PartRegion:
	var region := CosmeticDamageState.PartRegion.new()
	region.slot = slot
	if slot == FRONT:
		region.local_min = Vector3(-1.0, -0.5, -2.0)
		region.local_max = Vector3(1.0, 0.35, -0.95)
		region.allowed_regions = [ImpactEvent.ContactRegion.FRONT]
	elif slot == REAR:
		region.local_min = Vector3(-1.0, -0.5, 0.95)
		region.local_max = Vector3(1.0, 0.35, 2.0)
		region.allowed_regions = [ImpactEvent.ContactRegion.REAR]
	return region

func _case_loosen_boundary() -> Dictionary:
	var case := Case.new()
	case.name = "loosen_boundary_1_99_vs_2_0"
	var r1 := CosmeticDamageState.new()
	r1.configure_car(CAR_A, false)
	var e1 := _make_event("e1", CAR_A, 1, 1.99, Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT)
	var o1 := r1.consume(e1)
	case.check(o1.is_accepted(), "1.99 hit is accepted")
	case.check(not o1.transitioned, "1.99 hit does not transition")
	case.check(r1.part_condition(CAR_A, FRONT) == INTACT, "1.99 hit leaves part intact")
	case.check(o1.action_count() == 0, "1.99 hit emits no cue")
	var r2 := CosmeticDamageState.new()
	r2.configure_car(CAR_A, false)
	var e2 := _make_event("e2", CAR_A, 1, 2.0, Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT)
	var o2 := r2.consume(e2)
	case.check(o2.is_accepted(), "2.0 hit is accepted")
	case.check(o2.transitioned, "2.0 hit transitions")
	case.check(r2.part_condition(CAR_A, FRONT) == LOOSE, "2.0 hit loosens part")
	case.check(o2.first_action() != null and o2.first_action().action_type == LOOSE_ACTION, "2.0 hit emits loose cue")
	return case.result()

func _case_single_detach_boundary() -> Dictionary:
	var case := Case.new()
	case.name = "single_detach_boundary_4_99_vs_5_0"
	var r1 := CosmeticDamageState.new()
	r1.configure_car(CAR_A, false)
	var e1 := _make_event("e1", CAR_A, 1, 4.99, Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT)
	var o1 := r1.consume(e1)
	case.check(o1.is_accepted(), "4.99 hit is accepted")
	case.check(r1.part_condition(CAR_A, FRONT) == LOOSE, "4.99 hit loosens but does not detach")
	case.check(not o1.transitioned or r1.part_condition(CAR_A, FRONT) != DETACHED, "4.99 hit does not detach")
	var r2 := CosmeticDamageState.new()
	r2.configure_car(CAR_A, false)
	var e2 := _make_event("e2", CAR_A, 1, 5.0, Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT)
	var o2 := r2.consume(e2)
	case.check(o2.is_accepted(), "5.0 hit is accepted")
	case.check(r2.part_condition(CAR_A, FRONT) == DETACHED, "5.0 hit detaches part")
	case.check(o2.first_action() != null and o2.first_action().action_type == DETACH_ACTION, "5.0 hit emits detach cue")
	return case.result()

func _case_accumulated_detach() -> Dictionary:
	var case := Case.new()
	case.name = "accumulated_detach_8_0"
	var r := CosmeticDamageState.new()
	r.configure_car(CAR_A, false)
	var e1 := _make_event("e1", CAR_A, 0, 4.0, Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT)
	var o1 := r.consume(e1)
	case.check(o1.is_accepted() and r.part_condition(CAR_A, FRONT) == LOOSE, "first 4.0 hit loosens")
	var e2 := _make_event("e2", CAR_A, 30, 4.0, Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT)
	var o2 := r.consume(e2)
	case.check(o2.is_accepted(), "second 4.0 hit is accepted")
	case.check(o2.transitioned, "accumulated 8.0 transitions")
	case.check(r.part_condition(CAR_A, FRONT) == DETACHED, "accumulated 8.0 detaches")
	case.check(o2.first_action() != null and o2.first_action().action_type == DETACH_ACTION, "accumulated detach emits detach cue")
	return case.result()

func _case_part_selection() -> Dictionary:
	var case := Case.new()
	case.name = "part_selection_front_rear_wing_side"
	var check_selection := func(slot_expected: int, event: ImpactEvent, label: String) -> void:
		var r := CosmeticDamageState.new()
		r.configure_car(CAR_A, true)
		var o := r.consume(event)
		case.check(o.first_action() != null and o.first_action().slot == slot_expected, label)
	var ef := _make_event("ef", CAR_A, 1, 2.0, Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT)
	check_selection.call(FRONT, ef, "front point selects front bumper")
	var er := _make_event("er", CAR_A, 2, 2.0, Vector3(0.0, 0.0, 1.5), ImpactEvent.ContactRegion.REAR)
	check_selection.call(REAR, er, "rear point selects rear bumper")
	var ew := _make_event("ew", CAR_A, 3, 2.0, Vector3(0.0, 0.5, 1.5), ImpactEvent.ContactRegion.REAR)
	check_selection.call(WING, ew, "high rear point selects wing")
	var es := _make_event("es", CAR_A, 4, 2.0, Vector3(-0.5, 0.0, -1.5), ImpactEvent.ContactRegion.LEFT)
	check_selection.call(FRONT, es, "side point selects front bumper")
	var esr := _make_event("esr", CAR_A, 5, 2.0, Vector3(-0.5, 0.0, 1.5), ImpactEvent.ContactRegion.LEFT)
	check_selection.call(REAR, esr, "side point selects rear bumper")
	var esw := _make_event("esw", CAR_A, 6, 2.0, Vector3(0.0, 0.35, 1.5), ImpactEvent.ContactRegion.LEFT)
	check_selection.call(REAR, esw, "side point on wing volume selects rear bumper")
	return case.result()

func _case_no_part_atomic() -> Dictionary:
	var case := Case.new()
	case.name = "no_part_at_contact_atomic"
	var r := CosmeticDamageState.new()
	r.configure_car(CAR_A, false)
	var before := r.content_digest()
	var e := _make_event("en", CAR_A, 1, 2.0, Vector3(0.0, 0.0, 0.0), ImpactEvent.ContactRegion.FRONT)
	var o := r.consume(e)
	case.check(o.is_refused(), "contact with no part is refused")
	case.check(o.code == NO_PART, "refusal code is no_part_at_contact")
	case.check(r.content_digest() == before, "refusal leaves state unchanged")
	return case.result()

func _case_exact_replay_and_conflict() -> Dictionary:
	var case := Case.new()
	case.name = "exact_replay_and_conflicting_duplicate_id"
	var r := CosmeticDamageState.new()
	r.configure_car(CAR_A, false)
	var e := _make_event("dup", CAR_A, 1, 2.0, Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT)
	var o := r.consume(e)
	case.check(o.is_accepted(), "original event is accepted")
	var before := r.content_digest()
	var replay := _make_event("dup", CAR_A, 1, 2.0, Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT)
	var orp := r.consume(replay)
	case.check(orp.is_coalesced(), "exact replay coalesces")
	case.check(r.content_digest() == before, "exact replay leaves state unchanged")
	var conflict := _make_event("dup", CAR_A, 1, 2.5, Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT)
	var ocf := r.consume(conflict)
	case.check(ocf.is_refused(), "conflicting duplicate is refused")
	case.check(ocf.code == DUPLICATE_CONFLICT, "conflicting duplicate code")
	case.check(r.content_digest() == before, "conflict leaves state unchanged")
	return case.result()

func _case_contact_coalescing() -> Dictionary:
	var case := Case.new()
	case.name = "same_contact_id_coalescing"
	var r := CosmeticDamageState.new()
	r.configure_car(CAR_A, false)
	var e1 := _make_event("e1", CAR_A, 1, 2.0, Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT, "contact-1")
	var o1 := r.consume(e1)
	case.check(o1.is_accepted(), "first contact notification is accepted")
	var before := r.content_digest()
	var e2 := _make_event("e2", CAR_A, 1, 2.0, Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT, "contact-1")
	var o2 := r.consume(e2)
	case.check(o2.is_coalesced(), "second same contact coalesces")
	case.check(r.content_digest() == before, "coalesced contact leaves state unchanged")
	return case.result()

func _case_out_of_order() -> Dictionary:
	var case := Case.new()
	case.name = "out_of_order_and_equal_tick"
	var r := CosmeticDamageState.new()
	r.configure_car(CAR_A, false)
	var e1 := _make_event("e1", CAR_A, 5, 2.0, Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT)
	case.check(r.consume(e1).is_accepted(), "first tick 5 is accepted")
	var before := r.content_digest()
	var e2 := _make_event("e2", CAR_A, 3, 2.0, Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT)
	var o2 := r.consume(e2)
	case.check(o2.is_refused(), "earlier tick is refused")
	case.check(o2.code == TICK_OUT_OF_ORDER, "out-of-order code")
	case.check(r.content_digest() == before, "refusal leaves state unchanged")
	var e3 := _make_event("e3", CAR_A, 5, 2.0, Vector3(0.0, 0.0, 1.5), ImpactEvent.ContactRegion.REAR)
	case.check(r.consume(e3).is_accepted(), "equal tick is accepted")
	return case.result()

func _case_effect_cooldown() -> Dictionary:
	var case := Case.new()
	case.name = "effect_cooldown_30_ticks"
	var r1 := CosmeticDamageState.new()
	r1.configure_car(CAR_A, true)
	var a := _make_event("a", CAR_A, 0, 2.0, Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT)
	var oa := r1.consume(a)
	case.check(oa.first_action() != null, "first transition emits cue")
	var b := _make_event("b", CAR_A, 29, 2.0, Vector3(0.0, 0.0, 1.5), ImpactEvent.ContactRegion.REAR)
	var ob := r1.consume(b)
	case.check(ob.transitioned, "29-tick transition occurs")
	case.check(ob.effect_suppressed, "29-tick transition suppresses cue")
	case.check(ob.action_count() == 0, "29-tick transition emits no cue")
	var r2 := CosmeticDamageState.new()
	r2.configure_car(CAR_A, true)
	var c := _make_event("c", CAR_A, 0, 2.0, Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT)
	r2.consume(c)
	var d := _make_event("d", CAR_A, 30, 2.0, Vector3(0.0, 0.0, 1.5), ImpactEvent.ContactRegion.REAR)
	var od := r2.consume(d)
	case.check(od.first_action() != null, "30-tick transition emits cue")
	return case.result()

func _case_reset() -> Dictionary:
	var case := Case.new()
	case.name = "reset_and_per_car_reset"
	var r := CosmeticDamageState.new()
	r.configure_car(CAR_A, false)
	var e := _make_event("e", CAR_A, 4, 2.0, Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT)
	r.consume(e)
	r.reset()
	case.check(r.part_condition(CAR_A, FRONT) == INTACT, "reset repairs condition")
	case.check(r.snapshot(CAR_A)["parts"]["front_bumper"]["accumulated_severity_m_s"] == 0.0, "reset clears accumulator")
	var replay := _make_event("e", CAR_A, 4, 2.0, Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT)
	case.check(r.consume(replay).is_accepted(), "reset clears idempotency window")
	var r2 := CosmeticDamageState.new()
	r2.configure_car(CAR_A, false)
	r2.configure_car(CAR_B, false)
	var ea := _make_event("ea", CAR_A, 1, 2.0, Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT)
	var eb := _make_event("eb", CAR_B, 1, 2.0, Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT)
	r2.consume(ea)
	r2.consume(eb)
	case.check(r2.reset_car(CAR_A), "per-car reset succeeds")
	case.check(r2.part_condition(CAR_A, FRONT) == INTACT, "per-car reset repairs selected car")
	case.check(r2.part_condition(CAR_B, FRONT) == LOOSE, "per-car reset leaves other car damaged")
	case.check(not r2.reset_car("missing"), "unknown car reset fails")
	return case.result()

func _case_effects_toggle() -> Dictionary:
	var case := Case.new()
	case.name = "effects_enabled_disabled_identical_part_state"
	var enabled := CosmeticDamageState.new()
	enabled.configure_car(CAR_A, false)
	enabled.set_effects_enabled(true)
	var disabled := CosmeticDamageState.new()
	disabled.configure_car(CAR_A, false)
	disabled.set_effects_enabled(false)
	var events: Array[ImpactEvent] = []
	events.append(_make_event("e1", CAR_A, 1, 2.0, Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT))
	events.append(_make_event("e2", CAR_A, 31, 5.0, Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT))
	var enabled_actions := 0
	var disabled_actions := 0
	var disabled_suppressed := 0
	for ev in events:
		var oe := enabled.consume(ev)
		var od := disabled.consume(ev.copy())
		if oe.action_count() > 0:
			enabled_actions += oe.action_count()
		if od.action_count() > 0:
			disabled_actions += od.action_count()
		if od.effect_suppressed:
			disabled_suppressed += 1
	case.check(enabled.content_digest() == disabled.content_digest(), "effects toggle does not change part state")
	case.check(enabled_actions > 0, "enabled run emits cues")
	case.check(disabled_actions == 0, "disabled run emits no cues")
	case.check(disabled_suppressed > 0, "disabled run records suppression")
	return case.result()

func _case_configure_copies_caller_regions() -> Dictionary:
	var case := Case.new()
	case.name = "configure_car_copies_caller_regions"
	var regions: Array[CosmeticDamageState.PartRegion] = [
		_region_with_slot(FRONT),
		_region_with_slot(REAR),
	]

	var r := CosmeticDamageState.new()
	case.check(r.configure_car(CAR_A, false, regions), "custom region set configures")
	var first := _make_event(
		"own1", CAR_A, 1, 2.0,
		Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT,
	)
	var first_outcome := r.consume(first)
	case.check(first_outcome.is_accepted(), "pre-mutation hit accepted")
	case.check(
		first_outcome.first_action() != null
		and first_outcome.first_action().slot == FRONT,
		"pre-mutation hit selects front bumper",
	)
	var digest_after_first := r.content_digest()
	var snapshot_after_first := r.snapshot(CAR_A)

	# Mutate every caller-owned surface after configure returned true.
	regions[0].slot = WING
	regions[0].local_min = Vector3(5.0, 5.0, 5.0)
	regions[0].local_max = Vector3(6.0, 6.0, 6.0)
	regions[0].allowed_regions.clear()
	regions[0].allowed_regions.append(ImpactEvent.ContactRegion.LEFT)
	regions[1].slot = WING
	regions[1].local_min = Vector3(7.0, 7.0, 7.0)
	regions[1].local_max = Vector3(8.0, 8.0, 8.0)
	regions[1].allowed_regions = [ImpactEvent.ContactRegion.LEFT]
	regions.append(regions[1])
	regions.clear()

	case.check(
		r.content_digest() == digest_after_first,
		"caller region mutation leaves digest unchanged",
	)
	case.check(
		r.snapshot(CAR_A) == snapshot_after_first,
		"caller region mutation leaves snapshot unchanged",
	)
	case.check(
		r.part_condition(CAR_A, FRONT) == LOOSE,
		"caller slot mutation does not affect conditions",
	)

	# A detach past the cooldown exposes the selected slot in the emitted cue,
	# so a retained caller reference would select nothing or the wrong part.
	var second := _make_event(
		"own2", CAR_A, 31, 5.0,
		Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT,
	)
	var second_outcome := r.consume(second)
	case.check(second_outcome.is_accepted(), "post-mutation hit accepted")
	case.check(second_outcome.transitioned, "post-mutation hit still transitions")
	case.check(
		second_outcome.first_action() != null
		and second_outcome.first_action().slot == FRONT,
		"post-mutation selection uses copied front region",
	)
	case.check(
		second_outcome.first_action() != null
		and second_outcome.first_action().action_type == DETACH_ACTION,
		"post-mutation front hit detaches",
	)

	# Identical unmutated inputs must produce identical retained state and
		# consumption results, proving the mutation changed nothing internally.
	var control := CosmeticDamageState.new()
	case.check(
		control.configure_car(
			CAR_A,
			false,
			[_region_with_slot(FRONT), _region_with_slot(REAR)],
		),
		"control configures",
	)
	control.consume(_make_event(
		"own1", CAR_A, 1, 2.0,
		Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT,
	))
	control.consume(second.copy())
	case.check(
		r.content_digest() == control.content_digest(),
		"mutated input matches unmutated control digest",
	)
	case.check(
		r.snapshot(CAR_A) == control.snapshot(CAR_A),
		"mutated input matches unmutated control snapshot",
	)
	return case.result()

func _case_post_detach_no_overflow() -> Dictionary:
	var case := Case.new()
	case.name = "post_detach_accumulation_stays_finite"
	var huge := 1e308
	var r := CosmeticDamageState.new()
	r.configure_car(CAR_A, false)

	var e1 := _make_event(
		"huge1", CAR_A, 1, huge,
		Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT,
	)
	var o1 := r.consume(e1)
	case.check(o1.is_accepted(), "first 1e308 hit accepted")
	case.check(
		o1.first_action() != null
		and o1.first_action().action_type == DETACH_ACTION,
		"first 1e308 hit emits detach cue",
	)
	case.check(r.part_condition(CAR_A, FRONT) == DETACHED, "first 1e308 hit detaches")
	var retained1 := float(
		r.snapshot(CAR_A)["parts"]["front_bumper"]["accumulated_severity_m_s"]
	)
	case.check(is_finite(retained1), "first accumulator stays finite")
	case.equal(retained1, huge, "first accumulator equals 1e308")

	# Distinct event id at a later tick, beyond the cooldown, so a regression
	# that re-detached or accumulated further would be observable.
	var e2 := _make_event(
		"huge2", CAR_A, 31, huge,
		Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT,
	)
	var o2 := r.consume(e2)
	case.check(o2.is_accepted(), "second distinct 1e308 hit accepted")
	case.check(not o2.transitioned, "second detached hit does not transition again")
	case.check(o2.action_count() == 0, "second detached hit emits no detach cue")
	case.check(r.part_condition(CAR_A, FRONT) == DETACHED, "part remains detached")
	var retained2 := float(
		r.snapshot(CAR_A)["parts"]["front_bumper"]["accumulated_severity_m_s"]
	)
	case.check(is_finite(retained2), "retained accumulator stays finite")
	case.equal(retained2, huge, "detached accumulator does not accumulate further")
	case.equal(int(r.diagnostics()["accepted_events"]), 2, "both distinct events accepted")

	# Idempotency must still coalesce an exact replay without touching state.
	var replay := _make_event(
		"huge2", CAR_A, 31, huge,
		Vector3(0.0, 0.0, -1.5), ImpactEvent.ContactRegion.FRONT,
	)
	var replay_outcome := r.consume(replay)
	case.check(replay_outcome.is_coalesced(), "exact replay of detached hit coalesces")
	var retained3 := float(
		r.snapshot(CAR_A)["parts"]["front_bumper"]["accumulated_severity_m_s"]
	)
	case.check(is_finite(retained3), "coalesced replay leaves accumulator finite")
	case.equal(retained3, huge, "coalesced replay leaves accumulator unchanged")
	return case.result()
