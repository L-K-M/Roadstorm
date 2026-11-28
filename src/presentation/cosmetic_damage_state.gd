class_name CosmeticDamageState
extends RefCounted
## Pure cosmetic part-state reducer for Roadstorm Racer! (M1.8/M5.9 slice).
##
## This component consumes already-committed `ImpactEvent` records after
## simulation commit and owns only the per-car cosmetic part state that a future
## presentation/debris/audio director would read: front bumper, rear bumper and
## an optional rear wing, each `intact`, `loose` or `detached`, plus the
## per-part accumulated contact severity. It returns bounded deterministic
## action records (`LOOSE`/`DETACH`) so a later visual debris/audio director can
## spawn cues; it does not implement debris, sparks, audio, meshes, scene nodes
## or physics.
##
## Authority boundary. The reducer never sees authoritative car state,
## `CarState`, motor/body adapters, physics bodies, collision shapes, mass,
## scene nodes, race RNG or clocks. Its only inputs are caller-supplied
## `ImpactEvent` values and explicit local impact-region configuration. Every
## physical field is trusted exactly as the committed event publishes it; this
## module cannot verify that severity, point, region or normal came from the
## authoritative contact response. It never writes simulation state and cannot
## feed a second impulse into any contact response.
##
## Consumption contract:
##
##   * Only valid committed events are consumed. `event.is_valid()` is checked
##     first, which requires `committed == true`, nonempty stable IDs, finite
##     vectors, a unit response normal, nonnegative severity and an in-domain
##     `ContactRegion`.
##   * Unknown primary cars and unknown/unmatched parts refuse atomically.
##   * Ticks must not move backwards for one car. Equal ticks are allowed, so
##     several committed impacts in one tick can each affect their own part.
##   * Event identity is idempotent within a bounded retention window. An exact
##     payload retry under a retained `event_id` coalesces; a conflicting
##     payload under that ID refuses.
##   * A nonempty `contact_id` is a physical-contact identity for this primary
##     car. Repeated notifications of that contact coalesce, so one physical
##     contact can loosen/detach at most one part once.
##   * Struck-part selection uses configured local impact boxes and the event's
##     `contact_point_local_m` together with its `ContactRegion`. Selection
##     never falls back to an arbitrary part: no matching configured part means
##     refusal with no mutation.
##
## Thresholds (provisional M5 tuning from `docs/GAME_DESIGN.md:57`; these are
## cosmetic rules, not collision-response calculations):
##
##   * `LOOSEN_SEVERITY_M_S` 2.0: a single accepted hit at or above this
##     loosens an intact struck part.
##   * `SINGLE_DETACH_SEVERITY_M_S` 5.0: a single accepted hit at or above this
##     detaches the struck part regardless of accumulation.
##   * `ACCUMULATED_DETACH_SEVERITY_M_S` 8.0: accumulated severity for that
##     part at or above this detaches it.
##   * `EFFECT_COOLDOWN_TICKS` 30 (0.5 s at 60 Hz): after a transition, no
##     further `LOOSE`/`DETACH` cue is emitted for that car until 30 ticks have
##     elapsed. Delta exactly 30 emits.
##
## Provisional choices that callers/reviewers must know because the design docs
## do not pin them down:
##
##   * Local impact boxes are axis-aligned in the event's primary-car local
##     frame (local -Z forward, +X right, +Y up). Defaults describe a
##     representative compact hull of about 1.8 x 1.0 x 3.8 m and are not car
##     measurements. Real attachment transforms and per-car impact regions must
##     replace them from the Car content contract before M5.9 closure.
##   * Default part/region compatibility: front bumper accepts FRONT/LEFT/RIGHT
##     points inside its box, rear bumper accepts REAR/LEFT/RIGHT points inside
##     its box, wing accepts REAR points inside its box. The wing box is checked
##     before the rear box, so a high rear hit selects the wing when one is
##     configured. Side hits on the wing volume select the rear bumper instead.
##   * Accumulated severity sums every accepted distinct-event severity for the
##     struck part, including hits below the 2 m/s loosen threshold. The design
##     says "8 m/s accumulated across that part's hits" without qualifying the
##     hits; this reducer therefore lets sub-loosen contacts contribute to the
##     accumulated detach total. This is provisional and easy to change.
##   * Cooldown suppresses cue emission only. Part conditions, accumulated
##     severity and the cooldown watermark advance whether or not effects are
##     enabled, so disabling effects never changes part-state results.
##   * Effects-disabled transitions still start/advance the cooldown watermark.
##     Re-enabling effects does not replay suppressed historical cues.
##   * Bounded retention: idempotency/contact coalescing windows are capped per
##     car (default 512 entries each), evicting oldest first. Duplicate
##     detection is therefore windowed, not all-time; a session should reset or
##     the coordinator should regenerate identities if a repeat arrives after
##     eviction.
##   * `contact_id` is treated as one physical contact for one primary car. The
##     reducer has no geometry, so it cannot detect a producer that reuses a
##     contact ID for a genuinely new contact; that remains a producer/contract
##     obligation.
##
## This is not M1.8 acceptance, not M5.9 completion and not release readiness.
## There is no integrated coordinator, no visual debris pool, no audio and no
## measured four-view behaviour here.

## Detachable cosmetic slots. Order is the default selection scan order only
## when explicit configs are not supplied; custom configs carry their own
## order.
enum PartSlot { FRONT_BUMPER, REAR_BUMPER, WING }

## Visual condition of one part.
enum PartCondition { INTACT, LOOSE, DETACHED, UNKNOWN }

## Cue record kind. One consume emits at most one action.
enum ActionType { NONE, LOOSE, DETACH }

## Stable refusal codes. A refusal never mutates part/visual state.
enum RefusalCode {
	NONE,
	NULL_EVENT,
	INVALID_EVENT,
	UNKNOWN_CAR,
	TICK_OUT_OF_ORDER,
	DUPLICATE_EVENT_CONFLICT,
	NO_PART_AT_CONTACT,
}

const PART_SLOT_NAMES: Array[String] = ["front_bumper", "rear_bumper", "wing"]
const PART_CONDITION_NAMES: Array[String] = [
	"intact", "loose", "detached", "unknown",
]
const ACTION_TYPE_NAMES: Array[String] = ["none", "loose", "detach"]

const REFUSAL_NAMES: Dictionary = {
	RefusalCode.NONE: "none",
	RefusalCode.NULL_EVENT: "null_event",
	RefusalCode.INVALID_EVENT: "invalid_event",
	RefusalCode.UNKNOWN_CAR: "unknown_car",
	RefusalCode.TICK_OUT_OF_ORDER: "tick_out_of_order",
	RefusalCode.DUPLICATE_EVENT_CONFLICT: "duplicate_event_conflict",
	RefusalCode.NO_PART_AT_CONTACT: "no_part_at_contact",
}

## Provisional loosen threshold, m/s.
const LOOSEN_SEVERITY_M_S := 2.0
## Provisional single-hit detach threshold, m/s.
const SINGLE_DETACH_SEVERITY_M_S := 5.0
## Provisional accumulated detach threshold, m/s.
const ACCUMULATED_DETACH_SEVERITY_M_S := 8.0
## Per-car effect cooldown in logical ticks (0.5 s at 60 Hz).
const EFFECT_COOLDOWN_TICKS := 30

## Default bounded retention per car for event-id idempotency.
const DEFAULT_MAX_RETAINED_EVENTS_PER_CAR := 512
## Default bounded retention per car for physical-contact coalescing.
const DEFAULT_MAX_RETAINED_CONTACTS_PER_CAR := 512

## Provisional default local boxes, metres, in the primary-car local frame
## (-Z forward, +X right, +Y up) for a representative compact hull. The wing
## box overlaps the top of the rear box; the default scan checks wing first.
const DEFAULT_FRONT_BOX_MIN := Vector3(-1.0, -0.5, -2.0)
const DEFAULT_FRONT_BOX_MAX := Vector3(1.0, 0.35, -0.95)
const DEFAULT_REAR_BOX_MIN := Vector3(-1.0, -0.5, 0.95)
const DEFAULT_REAR_BOX_MAX := Vector3(1.0, 0.35, 2.0)
const DEFAULT_WING_BOX_MIN := Vector3(-0.9, 0.35, 1.0)
const DEFAULT_WING_BOX_MAX := Vector3(0.9, 1.1, 2.0)

## One configured local impact/attachment region for one part.
##
## Selection requires the event region to be in `allowed_regions` and the
## event local point to be inside the inclusive box. Configs are scanned in
## array order; the first match wins, so a config author controls overlap
## priority explicitly.
class PartRegion extends RefCounted:
	var slot: int = PartSlot.FRONT_BUMPER
	var local_min := Vector3.ZERO
	var local_max := Vector3.ZERO
	var allowed_regions: Array[int] = []

	func contains_point(point: Vector3) -> bool:
		return (
			point.x >= local_min.x
			and point.x <= local_max.x
			and point.y >= local_min.y
			and point.y <= local_max.y
			and point.z >= local_min.z
			and point.z <= local_max.z
		)

	func allows_region(region: int) -> bool:
		return allowed_regions.has(region)

	func to_dictionary() -> Dictionary:
		return {
			"slot": CosmeticDamageState.PART_SLOT_NAMES[slot],
			"local_min": local_min,
			"local_max": local_max,
			"allowed_regions": allowed_regions.duplicate(),
		}

	## Empty string when the spec is usable, otherwise a stable reason.
	static func validate(region: PartRegion) -> String:
		if region == null:
			return "null part region"
		if region.slot < PartSlot.FRONT_BUMPER or region.slot > PartSlot.WING:
			return "invalid part slot"
		if not CosmeticDamageState._finite_vector(region.local_min) or not CosmeticDamageState._finite_vector(region.local_max):
			return "nonfinite local bounds"
		if (
			region.local_min.x > region.local_max.x
			or region.local_min.y > region.local_max.y
			or region.local_min.z > region.local_max.z
		):
			return "inverted local bounds"
		if region.allowed_regions.is_empty():
			return "empty allowed contact regions"
		for region_value in region.allowed_regions:
			if (
				region_value < ImpactEvent.ContactRegion.FRONT
				or region_value > ImpactEvent.ContactRegion.RIGHT
			):
				return "invalid allowed contact region"
		return ""


## Immutable-ish per-car visual state. Instances live only inside the reducer;
## `to_dictionary()` is the inspection surface and copies every value.
class CarVisualState extends RefCounted:
	var car_id := ""
	var regions: Array[PartRegion] = []
	var conditions: Dictionary = {}
	var accumulated_severity: Dictionary = {}
	var last_tick := -1
	var last_effect_tick := -1

	func has_slot(slot: int) -> bool:
		return conditions.has(slot)

	func condition(slot: int) -> int:
		return conditions.get(slot, PartCondition.UNKNOWN)

	func accumulated(slot: int) -> float:
		return float(accumulated_severity.get(slot, 0.0))

	func has_wing() -> bool:
		return conditions.has(PartSlot.WING)

	func copy() -> CarVisualState:
		var cloned := CarVisualState.new()
		cloned.car_id = car_id
		cloned.regions = regions.duplicate()
		cloned.conditions = conditions.duplicate()
		cloned.accumulated_severity = accumulated_severity.duplicate()
		cloned.last_tick = last_tick
		cloned.last_effect_tick = last_effect_tick
		return cloned

	func to_dictionary() -> Dictionary:
		var parts := {}
		for slot_value in [PartSlot.FRONT_BUMPER, PartSlot.REAR_BUMPER, PartSlot.WING]:
			if not conditions.has(slot_value):
				continue
			parts[PART_SLOT_NAMES[slot_value]] = {
				"condition": PART_CONDITION_NAMES[conditions[slot_value]],
				"accumulated_severity_m_s": accumulated(slot_value),
			}
		return {
			"car_id": car_id,
			"has_wing": has_wing(),
			"last_tick": last_tick,
			"last_effect_tick": last_effect_tick,
			"parts": parts,
		}


## One bounded deterministic cue record for a future debris/audio director.
class CosmeticAction extends RefCounted:
	var car_id := ""
	var slot: int = PartSlot.FRONT_BUMPER
	var action_type: int = ActionType.NONE
	var previous_condition: int = PartCondition.UNKNOWN
	var condition: int = PartCondition.UNKNOWN
	var severity_m_s := 0.0
	var accumulated_severity_m_s := 0.0
	var tick_index := -1
	var event_id := ""
	var contact_id := ""

	func describe() -> String:
		return "%s:%s:%s:%s:tick=%d:event=%s" % [
			car_id,
			PART_SLOT_NAMES[slot],
			ACTION_TYPE_NAMES[action_type],
			PART_CONDITION_NAMES[condition],
			tick_index,
			event_id,
		]

	func to_dictionary() -> Dictionary:
		return {
			"car_id": car_id,
			"slot": PART_SLOT_NAMES[slot],
			"action_type": ACTION_TYPE_NAMES[action_type],
			"previous_condition": PART_CONDITION_NAMES[previous_condition],
			"condition": PART_CONDITION_NAMES[condition],
			"severity_m_s": severity_m_s,
			"accumulated_severity_m_s": accumulated_severity_m_s,
			"tick_index": tick_index,
			"event_id": event_id,
			"contact_id": contact_id,
		}


## Result of one `consume()` call. Exactly one of accepted/coalesced/refused is
## true. `actions` holds at most one record.
class ConsumeOutcome extends RefCounted:
	var accepted := false
	var coalesced := false
	var refused := false
	var code: int = RefusalCode.NONE
	var reason := ""
	var car_id := ""
	var actions: Array[CosmeticAction] = []
	var transitioned := false
	var effect_suppressed := false

	func is_accepted() -> bool:
		return accepted

	func is_coalesced() -> bool:
		return coalesced

	func is_refused() -> bool:
		return refused

	func action_count() -> int:
		return actions.size()

	func first_action() -> CosmeticAction:
		return actions[0] if not actions.is_empty() else null

	func to_dictionary() -> Dictionary:
		var action_dicts := []
		for action in actions:
			action_dicts.append(action.to_dictionary())
		return {
			"accepted": accepted,
			"coalesced": coalesced,
			"refused": refused,
			"code": CosmeticDamageState.REFUSAL_NAMES.get(code, "unknown"),
			"reason": reason,
			"car_id": car_id,
			"transitioned": transitioned,
			"effect_suppressed": effect_suppressed,
			"actions": action_dicts,
		}


var _cars := {}
var _events_by_car := {}
var _event_order_by_car := {}
var _contacts_by_car := {}
var _contact_order_by_car := {}

var _max_retained_events := DEFAULT_MAX_RETAINED_EVENTS_PER_CAR
var _max_retained_contacts := DEFAULT_MAX_RETAINED_CONTACTS_PER_CAR
var _effects_enabled := true
var _last_configuration_error := ""

var accepted_count := 0
var coalesced_count := 0
var refused_count := 0
var loosen_action_count := 0
var detach_action_count := 0


func _init(
	max_retained_events_per_car: int = DEFAULT_MAX_RETAINED_EVENTS_PER_CAR,
	max_retained_contacts_per_car: int = DEFAULT_MAX_RETAINED_CONTACTS_PER_CAR
) -> void:
	_max_retained_events = maxi(max_retained_events_per_car, 1)
	_max_retained_contacts = maxi(max_retained_contacts_per_car, 1)


## Configures one car exactly once. With empty `regions`, the provisional
## defaults for `has_wing` are used. Custom regions must include front and rear
## bumpers; the wing is optional. Returns false and leaves the reducer unchanged
## when the id or region set is invalid. `configuration_error()` reports why.
func configure_car(
	car_id: String,
	has_wing: bool = false,
	regions: Array[PartRegion] = []
) -> bool:
	_last_configuration_error = ""
	if car_id.is_empty():
		_last_configuration_error = "empty car id"
		return false
	if _cars.has(car_id):
		_last_configuration_error = "car already configured"
		return false
	var specs: Array[PartRegion]
	var error := ""
	if regions.is_empty():
		specs = default_regions(has_wing)
		error = _validate_regions(specs)
	else:
		# Validate the caller's objects first, then retain only copies. The
		# reducer never keeps a caller-owned PartRegion or allowed_regions
		# array, so later caller mutation cannot change selection, state or
		# content digests.
		error = _validate_regions(regions)
		if error.is_empty():
			specs = _clone_regions(regions)
	if not error.is_empty():
		_last_configuration_error = error
		return false
	var state := CarVisualState.new()
	state.car_id = car_id
	state.regions = specs
	for region in specs:
		state.conditions[region.slot] = PartCondition.INTACT
		state.accumulated_severity[region.slot] = 0.0
	_cars[car_id] = state
	_events_by_car[car_id] = {}
	_event_order_by_car[car_id] = []
	_contacts_by_car[car_id] = {}
	_contact_order_by_car[car_id] = []
	return true


func configuration_error() -> String:
	return _last_configuration_error


## Independent copies of caller-supplied regions, including each nested
## `allowed_regions` array. Slots and vectors are value types and are copied
## directly.
static func _clone_regions(regions: Array[PartRegion]) -> Array[PartRegion]:
	var cloned: Array[PartRegion] = []
	for region in regions:
		var copy := PartRegion.new()
		copy.slot = region.slot
		copy.local_min = region.local_min
		copy.local_max = region.local_max
		copy.allowed_regions = region.allowed_regions.duplicate()
		cloned.append(copy)
	return cloned


## Provisional default local impact regions. Scan order is wing, front, rear:
## the wing box overlaps the top of the rear box, so a high rear hit selects
## the wing when one exists. Coordinates are in the primary-car local frame
## (-Z forward, +X right, +Y up).
static func default_regions(has_wing: bool) -> Array[PartRegion]:
	var regions: Array[PartRegion] = []
	if has_wing:
		var wing := PartRegion.new()
		wing.slot = PartSlot.WING
		wing.local_min = DEFAULT_WING_BOX_MIN
		wing.local_max = DEFAULT_WING_BOX_MAX
		wing.allowed_regions = [ImpactEvent.ContactRegion.REAR]
		regions.append(wing)
	var front := PartRegion.new()
	front.slot = PartSlot.FRONT_BUMPER
	front.local_min = DEFAULT_FRONT_BOX_MIN
	front.local_max = DEFAULT_FRONT_BOX_MAX
	front.allowed_regions = [
		ImpactEvent.ContactRegion.FRONT,
		ImpactEvent.ContactRegion.LEFT,
		ImpactEvent.ContactRegion.RIGHT,
	]
	regions.append(front)
	var rear := PartRegion.new()
	rear.slot = PartSlot.REAR_BUMPER
	rear.local_min = DEFAULT_REAR_BOX_MIN
	rear.local_max = DEFAULT_REAR_BOX_MAX
	rear.allowed_regions = [
		ImpactEvent.ContactRegion.REAR,
		ImpactEvent.ContactRegion.LEFT,
		ImpactEvent.ContactRegion.RIGHT,
	]
	regions.append(rear)
	return regions


## Consumes one committed event. All validation and duplicate/contact checks
## run before mutation, so a refusal or coalescence leaves part/visual state
## byte-for-byte unchanged apart from diagnostic counters.
func consume(event: ImpactEvent) -> ConsumeOutcome:
	if event == null:
		return _refuse(RefusalCode.NULL_EVENT, "null event")
	if not event.is_valid():
		return _refuse(
			RefusalCode.INVALID_EVENT,
			"invalid event: %s" % event.validation_error()
		)

	var car_id := event.primary_car_id
	if not _cars.has(car_id):
		return _refuse(
			RefusalCode.UNKNOWN_CAR,
			"unknown primary car id %s" % car_id,
			car_id
		)
	var car: CarVisualState = _cars[car_id]

	# Exact retry detection first: an identical payload coalesces, a changed
	# payload under the same retained event ID refuses. This ordering makes a
	# retry idempotent even if a caller replays it out of tick order.
	var retained_events: Dictionary = _events_by_car[car_id]
	if retained_events.has(event.event_id):
		var retained: ImpactEvent = retained_events[event.event_id]
		if retained != null and retained.same_payload(event):
			return _coalesced(
				car_id,
				"duplicate event id %s" % event.event_id
			)
		return _refuse(
			RefusalCode.DUPLICATE_EVENT_CONFLICT,
			"conflicting payload for event id %s" % event.event_id,
			car_id
		)

	if event.tick_index < car.last_tick:
		return _refuse(
			RefusalCode.TICK_OUT_OF_ORDER,
			"tick %d precedes car watermark %d" % [event.tick_index, car.last_tick],
			car_id
		)

	# Physical-contact coalescing: repeated notifications of one contact for
	# this primary car never accumulate twice and never detach twice.
	if event.has_contact_link():
		var contacts: Dictionary = _contacts_by_car[car_id]
		if contacts.has(event.contact_id):
			return _coalesced(
				car_id,
				"duplicate physical contact %s" % event.contact_id
			)

	var slot := _select_part(car, event)
	if slot < 0:
		return _refuse(
			RefusalCode.NO_PART_AT_CONTACT,
			"no configured part at local point %s for region %s" % [
				str(event.contact_point_local_m),
				ImpactEvent.REGION_NAMES[event.region],
			],
			car_id
		)

	return _apply_accepted(car, event, slot)


## Repairs every configured car and clears its idempotency/contact windows.
## Grid starts, restarts and full-session resets use this. Diagnostic counters
## are lifetime totals and intentionally survive reset.
func reset() -> void:
	for car_id in _cars:
		_reset_car_locked(car_id)


## Repairs one configured car, leaving other cars untouched. Returns false for
## an unknown car id without mutating anything.
func reset_car(car_id: String) -> bool:
	if not _cars.has(car_id):
		return false
	_reset_car_locked(car_id)
	return true


## Whether visual cue emission is enabled. Disabling suppresses action records
## only; part conditions, accumulators and cooldown bookkeeping are identical.
func set_effects_enabled(enabled: bool) -> void:
	_effects_enabled = enabled


func effects_enabled() -> bool:
	return _effects_enabled


## Sorted configured car ids.
func car_ids() -> Array[String]:
	var ids: Array[String] = []
	for car_id in _cars:
		ids.append(car_id)
	ids.sort()
	return ids


## Inspection snapshot for one car; `configured: false` for an unknown id.
## Deliberately excludes the global effects toggle so a disabled-effects run
## can be compared byte-for-byte against an enabled one.
func snapshot(car_id: String) -> Dictionary:
	if not _cars.has(car_id):
		return {"car_id": car_id, "configured": false}
	return (_cars[car_id] as CarVisualState).to_dictionary()


func part_condition(car_id: String, slot: int) -> int:
	if not _cars.has(car_id):
		return PartCondition.UNKNOWN
	return (_cars[car_id] as CarVisualState).condition(slot)


## Lifetime diagnostic counters, excluded from `content_digest()`.
func diagnostics() -> Dictionary:
	return {
		"configured_cars": _cars.size(),
		"accepted_events": accepted_count,
		"coalesced_events": coalesced_count,
		"refused_events": refused_count,
		"loosen_actions": loosen_action_count,
		"detach_actions": detach_action_count,
	}


## Deterministic fingerprint of every piece of retained visual/identity state,
## ignoring diagnostic counters and the effects toggle. Atomic-refusal tests
## compare this before and after a rejected input. Not cryptographic.
func content_digest() -> String:
	var parts: Array[String] = []
	for car_id in car_ids():
		parts.append(_car_content_digest(car_id))
	return _join(parts)


func _apply_accepted(
	car: CarVisualState,
	event: ImpactEvent,
	slot: int
) -> ConsumeOutcome:
	var prior_condition: int = car.condition(slot)
	# Accumulate only while the part can still change. Once detached the
	# condition is final, and summing further accepted severities could
	# overflow the finite retained accumulator (and any emitted action).
	var accumulated := car.accumulated(slot)
	if prior_condition != PartCondition.DETACHED:
		accumulated += event.severity_m_s
	var new_condition := prior_condition
	var action_type := ActionType.NONE

	if prior_condition != PartCondition.DETACHED:
		if (
			event.severity_m_s >= SINGLE_DETACH_SEVERITY_M_S
			or accumulated >= ACCUMULATED_DETACH_SEVERITY_M_S
		):
			new_condition = PartCondition.DETACHED
			action_type = ActionType.DETACH
		elif (
			prior_condition == PartCondition.INTACT
			and event.severity_m_s >= LOOSEN_SEVERITY_M_S
		):
			new_condition = PartCondition.LOOSE
			action_type = ActionType.LOOSE

	car.accumulated_severity[slot] = accumulated
	car.conditions[slot] = new_condition
	car.last_tick = maxi(car.last_tick, event.tick_index)

	# Store after every check has passed. Copies keep caller mutation from
	# reaching retained identity/payload state.
	_store_event(car.car_id, event.copy())
	if event.has_contact_link():
		_store_contact(car.car_id, event.contact_id)

	accepted_count += 1
	var outcome := ConsumeOutcome.new()
	outcome.accepted = true
	outcome.car_id = car.car_id
	outcome.transitioned = action_type != ActionType.NONE

	if action_type != ActionType.NONE:
		var cooldown_ready := (
			car.last_effect_tick < 0
			or event.tick_index - car.last_effect_tick >= EFFECT_COOLDOWN_TICKS
		)
		# The watermark advances whether or not the cue is emitted, so a
		# toggle cannot manufacture extra effects or change part state.
		car.last_effect_tick = event.tick_index
		if _effects_enabled and cooldown_ready:
			var action := CosmeticAction.new()
			action.car_id = car.car_id
			action.slot = slot
			action.action_type = action_type
			action.previous_condition = prior_condition
			action.condition = new_condition
			action.severity_m_s = event.severity_m_s
			action.accumulated_severity_m_s = accumulated
			action.tick_index = event.tick_index
			action.event_id = event.event_id
			action.contact_id = event.contact_id
			outcome.actions.append(action)
			if action_type == ActionType.DETACH:
				detach_action_count += 1
			else:
				loosen_action_count += 1
		else:
			outcome.effect_suppressed = true

	return outcome


func _select_part(car: CarVisualState, event: ImpactEvent) -> int:
	for region in car.regions:
		if (
			region.allows_region(event.region)
			and region.contains_point(event.contact_point_local_m)
		):
			return region.slot
	return -1


func _store_event(car_id: String, event: ImpactEvent) -> void:
	var retained: Dictionary = _events_by_car[car_id]
	var order: Array = _event_order_by_car[car_id]
	retained[event.event_id] = event
	order.append(event.event_id)
	while order.size() > _max_retained_events:
		var oldest: String = order.pop_front()
		retained.erase(oldest)


func _store_contact(car_id: String, contact_id: String) -> void:
	var retained: Dictionary = _contacts_by_car[car_id]
	var order: Array = _contact_order_by_car[car_id]
	retained[contact_id] = true
	order.append(contact_id)
	while order.size() > _max_retained_contacts:
		var oldest: String = order.pop_front()
		retained.erase(oldest)


func _reset_car_locked(car_id: String) -> void:
	var car: CarVisualState = _cars[car_id]
	for region in car.regions:
		car.conditions[region.slot] = PartCondition.INTACT
		car.accumulated_severity[region.slot] = 0.0
	car.last_tick = -1
	car.last_effect_tick = -1
	(_events_by_car[car_id] as Dictionary).clear()
	(_event_order_by_car[car_id] as Array).clear()
	(_contacts_by_car[car_id] as Dictionary).clear()
	(_contact_order_by_car[car_id] as Array).clear()


func _refuse(code: int, reason: String, car_id := "") -> ConsumeOutcome:
	refused_count += 1
	var outcome := ConsumeOutcome.new()
	outcome.refused = true
	outcome.code = code
	outcome.reason = reason
	outcome.car_id = car_id
	return outcome


func _coalesced(car_id: String, reason: String) -> ConsumeOutcome:
	coalesced_count += 1
	var outcome := ConsumeOutcome.new()
	outcome.coalesced = true
	outcome.car_id = car_id
	outcome.reason = reason
	return outcome


func _validate_regions(regions: Array[PartRegion]) -> String:
	if regions.is_empty():
		return "no part regions"
	var seen_slots := {}
	for region in regions:
		if region == null:
			return "null part region"
		var error := PartRegion.validate(region)
		if not error.is_empty():
			return error
		if seen_slots.has(region.slot):
			return "duplicate part slot %s" % PART_SLOT_NAMES[region.slot]
		seen_slots[region.slot] = true
	if not seen_slots.has(PartSlot.FRONT_BUMPER):
		return "missing front bumper region"
	if not seen_slots.has(PartSlot.REAR_BUMPER):
		return "missing rear bumper region"
	return ""


func _car_content_digest(car_id: String) -> String:
	var car: CarVisualState = _cars[car_id]
	var parts: Array[String] = []
	parts.append("car=%s" % car_id)
	parts.append("last_tick=%d" % car.last_tick)
	parts.append("last_effect_tick=%d" % car.last_effect_tick)
	for slot_value in [PartSlot.FRONT_BUMPER, PartSlot.REAR_BUMPER, PartSlot.WING]:
		if not car.conditions.has(slot_value):
			continue
		parts.append(
			"%s=%s/%s" % [
				PART_SLOT_NAMES[slot_value],
				PART_CONDITION_NAMES[car.conditions[slot_value]],
				ImpactEvent.encode_for_digest(car.accumulated_severity[slot_value]),
			]
		)
	for region in car.regions:
		parts.append(
			"region=%d:%s:%s:%s" % [
				region.slot,
				ImpactEvent.encode_for_digest(region.local_min),
				ImpactEvent.encode_for_digest(region.local_max),
				encode_int_array(region.allowed_regions),
			]
		)
	var retained_events: Dictionary = _events_by_car[car_id]
	var event_order: Array = _event_order_by_car[car_id]
	for event_id in event_order:
		var event: ImpactEvent = retained_events[event_id]
		parts.append("event=%s:%s" % [event_id, _event_content_digest(event)])
	# FIFO retention order, not sorted id order: the order decides which
	# contact id a later eviction removes, so two reducers with different
	# insertion orders have different continuation behavior. Hash iteration
	# would be nondeterministic across runs; the array is explicit.
	var contact_order: Array = _contact_order_by_car[car_id]
	var contact_ids: Array[String] = []
	for contact_id in contact_order:
		contact_ids.append(contact_id)
	parts.append("contacts=%s" % encode_string_array(contact_ids))
	return _join(parts)


static func _event_content_digest(event: ImpactEvent) -> String:
	var parts: Array[String] = [
		ImpactEvent.encode_for_digest(event.event_id),
		ImpactEvent.encode_for_digest(event.tick_index),
		ImpactEvent.encode_for_digest(event.primary_car_id),
		ImpactEvent.encode_for_digest(event.other_car_id),
		ImpactEvent.encode_for_digest(event.contact_id),
		ImpactEvent.encode_for_digest(event.contact_point_world_m),
		ImpactEvent.encode_for_digest(event.contact_point_local_m),
		ImpactEvent.encode_for_digest(event.contact_normal_world_m),
		ImpactEvent.encode_for_digest(event.severity_m_s),
		ImpactEvent.encode_for_digest(event.post_contact_velocity_world_m_s),
		ImpactEvent.encode_for_digest(event.imparted_motion_m),
		ImpactEvent.encode_for_digest(event.region),
		ImpactEvent.encode_for_digest(event.committed),
	]
	return _join(parts)


static func encode_int_array(values: Array[int]) -> String:
	var parts: Array[String] = []
	for value in values:
		parts.append(str(value))
	return _join(parts)


static func encode_string_array(values: Array[String]) -> String:
	var encoded: Array[String] = []
	for value in values:
		encoded.append("%d:%s" % [value.length(), value])
	return _join(encoded)


static func _join(parts: Array[String]) -> String:
	var joined := ""
	for index in range(parts.size()):
		if index > 0:
			joined += "|"
		joined += parts[index]
	return joined


static func _finite_vector(value: Vector3) -> bool:
	return (
		is_finite(value.x)
		and is_finite(value.y)
		and is_finite(value.z)
	)
