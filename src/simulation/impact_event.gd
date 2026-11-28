class_name ImpactEvent
extends RefCounted
## Committed impact-event record, pure validating builder and bounded per-tick
## ledger for Roadstorm Racer! (M1.8 contract).
##
## This file owns only the event record and its validation/publication rules.
## It deliberately imports and references no motor, body adapter, `CarState`,
## physics server, scene node or race RNG type. Cosmetic consumers receive
## copies and have no path back into authoritative simulation state.
##
## Authority contract (what the future integrator must supply)
##
## Every physical value below must come from the authoritative committed
## post-contact simulation state, never from presentation interpolation,
## visual meshes or cosmetic code:
##
##   * `severity_m_s`: magnitude of the contact-induced velocity change,
##     measured across the contact response itself (committed velocity
##     immediately before the response versus committed velocity immediately
##     after it). It is never derived from the motor's proposed acceleration
##     delta, throttle input or a presentation speed. Deriving it correctly is
##     an integrator obligation that this pure module cannot verify: the
##     laboratory only proves the record carries whatever value the integrator
##     supplied, never that the value came from the contact response.
##   * `post_contact_velocity_world_m_s`: committed world velocity after the
##     contact response, from the same authoritative state that owns the body
##     transform.
##   * `contact_normal_world_m`: unit physical contact normal used by the
##     contact response.
##   * `contact_point_world_m`: authoritative physical contact point of the
##     wall or car-car contact that produced this event.
##   * `contact_point_local_m`: `contact_point_world_m` expressed in the
##     primary car's committed local frame (local -Z forward, +X right,
##     +Y up) at the tick of commitment.
##   * `imparted_motion_m`: contact-induced displacement of the primary car
##     during the response, in metres.
##   * `region`: classification of the local contact point against the
##     committed hull as front/rear/left/right.
##   * `event_id`, `contact_id` and `tick_index`: coordinator/event-bus
##     assigned identity and logical tick or sequence index.
##
## Identity is per (physical contact, primary car) perspective, not per
## physical contact. Region, local point, severity, imparted motion and
## post-contact velocity all describe one car only, so a car-car contact
## produces two complementary records: (primary A, other B) and
## (primary B, other A). Each carries its own `event_id`; when the producer
## knows both sides it may also set the shared `contact_id` so a consumer can
## pair them. A producer that reused one contact-wide `event_id` for both
## perspectives would lose the second car's record, so the contract forbids
## it: the two perspectives are distinct records, not duplicates.
##
## Authoritative wall-contact seam: `MotorBodyAdapter.Result` exposes
## `wall_contact_normal` and, since the wall-point job, an authoritative
## `wall_contact_point` with an explicit `has_wall_contact_point` witness
## flag. Its generic `contact_point` remains the first reported contact of
## the last colliding substep and can be floor-first even when a later wall
## contact drove the response, so a truthful `contact_point_world_m` must
## come from the wall witness. This module is not yet wired to the adapter:
## the producer that turns a committed adapter result into an impact event
## is integration work, and this file neither performs that wiring nor
## claims it exists.
##
## Commitment is a caller assertion, not proof of authority. `committed` and
## `Builder.source_committed` are ordinary booleans: any caller can set them
## on a directly constructed record, and no field in this module can prove
## the value came from a committed authoritative source. The coordinator owns
## the write side of publication (which record is built, from which
## committed state, and when it enters the ledger); presentation consumers
## receive copies and must not publish. The record shape and the validation
## below make that assertion checkable and auditable, not true by
## construction.
##
## Immutability is by convention: `Builder.build()` returns a committed
## record that consumers must treat as read-only. The ledger stores and
## returns copies, so consumer mutation cannot reach retained events.

## Contact region of the struck part relative to the committed car hull.
enum ContactRegion { FRONT, REAR, LEFT, RIGHT }

## How the builder treats the supplied world contact normal.
enum NormalMode {
	## Publish the normal unchanged; a non-unit normal is refused.
	PRESERVE,
	## Normalize a finite normal whose length is at least NORMAL_MIN_LENGTH.
	NORMALIZE,
}

## Names parallel to `ContactRegion`, for logs and machine-readable reports.
const REGION_NAMES: Array[String] = ["front", "rear", "left", "right"]

## Builder sentinel for a region the caller has not supplied. It is outside the
## `ContactRegion` domain, so an omitted region refuses instead of silently
## publishing the first enum value as if it had been chosen.
const REGION_UNSET := -1

## Sentinel default for a vector field the builder has not supplied. Infinity
## compares equal to itself in `Vector3` equality, so presence can be tested
## exactly, and every finiteness check already refuses it.
const UNSET_VECTOR := Vector3(INF, INF, INF)

## Published normals must be unit length within this absolute tolerance.
const NORMAL_UNIT_TOLERANCE := 1e-4
## A normal shorter than this is treated as zero/invalid and refused.
const NORMAL_MIN_LENGTH := 1e-6

## Field names the integrator must fill from authoritative simulation state.
## Kept machine-readable so contract checks can assert the published surface.
## Every one of them must be supplied explicitly: a legal explicit zero is
## indistinguishable from a forgotten field unless the builder refuses the
## unset sentinel first.
const INTEGRATOR_SUPPLIED_FIELDS: Array[String] = [
	"severity_m_s",
	"post_contact_velocity_world_m_s",
	"contact_point_world_m",
	"contact_normal_world_m",
	"contact_point_local_m",
	"imparted_motion_m",
	"region",
]

## Field names the coordinator/event bus assigns. They are not physical
## measurements, so the laboratory cannot derive or verify them.
const COORDINATOR_ASSIGNED_FIELDS: Array[String] = [
	"event_id",
	"contact_id",
	"tick_index",
	"primary_car_id",
	"other_car_id",
]

## Stable unique identity of this (physical contact, primary car) perspective.
## Empty is invalid. Two perspectives of one car-car contact must carry two
## different IDs; reusing one ID across perspectives loses a record.
var event_id := ""
## Logical tick or sequence index at which the contact was committed.
var tick_index := -1
## Semantic ID of the primary (striken/own) car. Never empty.
var primary_car_id := ""
## Semantic ID of the other car in a car-car contact. Empty means wall,
## scenery, self-contact or a contact with no second car.
var other_car_id := ""
## Optional shared identity of the physical contact, linking the per-primary
## records of both sides of one car-car contact. Empty is allowed and means
## "no link supplied"; it never identifies a record on its own.
var contact_id := ""
## Authoritative physical contact point in world axes, metres.
var contact_point_world_m := Vector3.ZERO
## The same contact point in the primary car's committed local frame, metres.
var contact_point_local_m := Vector3.ZERO
## Unit physical contact normal in world axes.
var contact_normal_world_m := Vector3.ZERO
## Contact-induced velocity-change magnitude in m/s. Never negative.
var severity_m_s := 0.0
## Committed world velocity after the contact response, m/s.
var post_contact_velocity_world_m_s := Vector3.ZERO
## Contact-induced displacement during the response, world axes, metres.
var imparted_motion_m := Vector3.ZERO
## Named struck region selected from the committed hull and local point.
var region: ContactRegion = REGION_UNSET
## Caller assertion that this record was built from an authoritative
## committed source. It is not proof: any caller can set it on a directly
## constructed record. See the authority contract above.
var committed := false


## Whether a second car participates in this contact.
func has_other_car() -> bool:
	return not other_car_id.is_empty()


## Whether this record is linked to the other perspective of the same
## physical contact through a shared `contact_id`.
func has_contact_link() -> bool:
	return not contact_id.is_empty()


## Whether `other` is the opposite perspective of the same physical contact:
## the same shared `contact_id`, the same tick, two different records, and
## reciprocal participants, meaning this record's primary car is `other`'s
## other car and this record's other car is `other`'s primary car.
##
## Reciprocity is required rather than assumed. `contact_id` is an optional
## link the producer may set, so two unrelated records that merely carry the
## same `contact_id` (A->B beside C->D) or two wall records that share a wall
## contact label must not be mistaken for a pair. Wall and other unpaired
## records are refused explicitly: a record with no second car has no opposite
## perspective, whatever its `contact_id` says.
func is_opposite_perspective(other: ImpactEvent) -> bool:
	if other == null:
		return false
	if not has_contact_link() or not other.has_contact_link():
		return false
	if contact_id != other.contact_id:
		return false
	if tick_index != other.tick_index:
		return false
	if event_id == other.event_id:
		return false
	if not has_other_car() or not other.has_other_car():
		return false
	if primary_car_id == other.primary_car_id:
		return false
	return (
		primary_car_id == other.other_car_id
		and other_car_id == other.primary_car_id
	)


## Whether this record came from a committed authoritative source.
func is_committed() -> bool:
	return committed


## Magnitude of the imparted contact displacement, metres.
##
## Uses the scaled norm in `stable_norm`, so a finite displacement always
## yields a finite magnitude even when squaring its largest component would
## overflow the engine's 32-bit float vector range.
func imparted_motion_magnitude_m() -> float:
	return stable_norm(imparted_motion_m)


## Region name for logs and reports; "invalid" when the enum is out of range.
func region_name() -> String:
	if region < ContactRegion.FRONT or region >= REGION_NAMES.size():
		return "invalid"
	return REGION_NAMES[region]


## Independent deep-enough copy. Strings and vectors are value types here.
func copy() -> ImpactEvent:
	var event := ImpactEvent.new()
	event.event_id = event_id
	event.tick_index = tick_index
	event.primary_car_id = primary_car_id
	event.other_car_id = other_car_id
	event.contact_id = contact_id
	event.contact_point_world_m = contact_point_world_m
	event.contact_point_local_m = contact_point_local_m
	event.contact_normal_world_m = contact_normal_world_m
	event.severity_m_s = severity_m_s
	event.post_contact_velocity_world_m_s = post_contact_velocity_world_m_s
	event.imparted_motion_m = imparted_motion_m
	event.region = region
	event.committed = committed
	return event


## Machine-readable view of the record. Consumers must not treat the
## returned dictionary as a live handle on simulation state.
func to_dict() -> Dictionary:
	return {
		"event_id": event_id,
		"tick_index": tick_index,
		"primary_car_id": primary_car_id,
		"other_car_id": other_car_id,
		"has_other_car": has_other_car(),
		"contact_id": contact_id,
		"has_contact_link": has_contact_link(),
		"contact_point_world_m": contact_point_world_m,
		"contact_point_local_m": contact_point_local_m,
		"contact_normal_world_m": contact_normal_world_m,
		"severity_m_s": severity_m_s,
		"post_contact_velocity_world_m_s": post_contact_velocity_world_m_s,
		"imparted_motion_m": imparted_motion_m,
		"imparted_motion_magnitude_m": imparted_motion_magnitude_m(),
		"region": region_name(),
		"committed": committed,
	}


## Returns an empty string when the record satisfies the published contract,
## otherwise a stable, deterministic refusal reason.
func validation_error() -> String:
	if event_id.is_empty():
		return "empty event id"
	if tick_index < 0:
		return "negative tick index"
	if primary_car_id.is_empty():
		return "empty primary car id"
	if not other_car_id.is_empty() and other_car_id == primary_car_id:
		return "duplicate car id"
	if not _finite_vector(contact_point_world_m):
		return "nonfinite world contact point"
	if not _finite_vector(contact_point_local_m):
		return "nonfinite local contact point"
	if not _finite_vector(contact_normal_world_m):
		return "nonfinite contact normal"
	var normal_length := stable_norm(contact_normal_world_m)
	if not is_finite(normal_length) or normal_length < NORMAL_MIN_LENGTH:
		return "zero contact normal"
	if absf(normal_length - 1.0) > NORMAL_UNIT_TOLERANCE:
		return "nonunit contact normal"
	if not is_finite(severity_m_s):
		return "nonfinite severity"
	if severity_m_s < 0.0:
		return "negative severity"
	if not _finite_vector(post_contact_velocity_world_m_s):
		return "nonfinite post-contact velocity"
	if not _finite_vector(imparted_motion_m):
		return "nonfinite imparted motion"
	if region < ContactRegion.FRONT or region > ContactRegion.RIGHT:
		return "invalid contact region"
	if not committed:
		return "uncommitted source"
	return ""


## Convenience predicate mirroring `validation_error()`.
func is_valid() -> bool:
	return validation_error().is_empty()


## Whether `other` carries the same authoritative payload as this record in
## every published field, including identity, geometry, severity, committed
## state and region. Used to tell an exact retry (which may coalesce) from a
## conflicting record that reuses an ID (which must be refused).
func same_payload(other: ImpactEvent) -> bool:
	if other == null:
		return false
	return (
		event_id == other.event_id
		and tick_index == other.tick_index
		and primary_car_id == other.primary_car_id
		and other_car_id == other.other_car_id
		and contact_id == other.contact_id
		and contact_point_world_m == other.contact_point_world_m
		and contact_point_local_m == other.contact_point_local_m
		and contact_normal_world_m == other.contact_normal_world_m
		and severity_m_s == other.severity_m_s
		and post_contact_velocity_world_m_s == other.post_contact_velocity_world_m_s
		and imparted_motion_m == other.imparted_motion_m
		and region == other.region
		and committed == other.committed
	)


## Exact, loss-free textual encoding of one value for content digests. Uses
## the engine's binary variant encoding so no float or vector precision is
## lost, which an atomic-refusal digest needs to detect arbitrary retained
## field mutation.
static func encode_for_digest(value: Variant) -> String:
	var bytes := var_to_bytes(value)
	var text := ""
	for index in range(bytes.size()):
		text += "%02x" % bytes[index]
	return text


static func _finite_vector(value: Vector3) -> bool:
	return (
		is_finite(value.x)
		and is_finite(value.y)
		and is_finite(value.z)
	)


## Euclidean norm computed by scaling, so a finite vector always produces a
## finite result.
##
## `Vector3.length()` squares each component first, which overflows the
## engine's 32-bit float range for components above roughly 1.8e19 and
## returns INF. Scaling by the largest absolute component keeps every
## intermediate in range, so the result is finite for every finite input and
## is never silently INF or NaN. Zero returns zero; a nonfinite component
## returns that nonfinite value unchanged.
##
## Public because consumers that need a derived magnitude of an admitted
## vector must get the same bounded behaviour as the contract itself.
##
## The returned value is a 64-bit script float, so it can exceed the engine's
## 32-bit float vector range (about 3.4e38) while staying finite: a diagonal
## vector near that range has a norm about sqrt(2) times larger. Never divide a
## `Vector3` by this result, because the divisor is converted to a 32-bit float
## first and an overflowing conversion yields INF and a zero quotient. Divide the
## scalar components and build the vector from the quotients instead, as
## `Builder._resolve_normal()` does.
static func stable_norm(value: Vector3) -> float:
	var largest := maxf(maxf(absf(value.x), absf(value.y)), absf(value.z))
	if not is_finite(largest) or largest <= 0.0:
		return largest
	var scaled_x := value.x / largest
	var scaled_y := value.y / largest
	var scaled_z := value.z / largest
	return largest * sqrt(scaled_x * scaled_x + scaled_y * scaled_y + scaled_z * scaled_z)


## Pure validating factory for committed impact records.
##
## Assign fields, then call `build()`. `build()` mutates no ledger and no
## simulation state; on refusal it returns null and sets `rejection_reason`.
##
## Defaults are deliberately invalid sentinels so a forgotten field refuses
## instead of publishing a plausible-looking event. That matters most where a
## legal explicit value is indistinguishable from the default: a severity of
## exactly zero, a zero contact point, a zero post-contact velocity, a zero
## imparted motion and `region == FRONT` are all valid publications, so the
## builder cannot rely on "the value looks wrong" to catch an omission. Every
## required physical field therefore starts at a sentinel outside its valid
## domain, and `missing_fields()` reports which required fields are still
## unset. `contact_id` is optional and has no sentinel.
class Builder extends RefCounted:
	var event_id := ""
	var tick_index := -1
	var primary_car_id := ""
	var other_car_id := ""
	var contact_id := ""
	var contact_point_world_m := UNSET_VECTOR
	var contact_point_local_m := UNSET_VECTOR
	var contact_normal_world_m := Vector3.ZERO
	var severity_m_s := NAN
	var post_contact_velocity_world_m_s := UNSET_VECTOR
	var imparted_motion_m := UNSET_VECTOR
	var region: ContactRegion = REGION_UNSET
	var normal_mode: NormalMode = NormalMode.PRESERVE
	var source_committed := false
	var rejection_reason := ""


	## Validate every field and return a committed record, or null on refusal.
	func build() -> ImpactEvent:
		rejection_reason = ""
		if not _valid_normal_mode(normal_mode):
			rejection_reason = "invalid normal mode"
			return null
		var event := ImpactEvent.new()
		event.event_id = event_id
		event.tick_index = tick_index
		event.primary_car_id = primary_car_id
		event.other_car_id = other_car_id
		event.contact_id = contact_id
		event.contact_point_world_m = contact_point_world_m
		event.contact_point_local_m = contact_point_local_m
		event.contact_normal_world_m = _resolve_normal()
		event.severity_m_s = severity_m_s
		event.post_contact_velocity_world_m_s = post_contact_velocity_world_m_s
		event.imparted_motion_m = imparted_motion_m
		event.region = region
		event.committed = source_committed
		var error := event.validation_error()
		if not error.is_empty():
			rejection_reason = error
			return null
		return event


	## Names of the required fields still holding their unset sentinel, plus
	## the unset `source_committed` assertion. A field listed here cannot
	## build; a field not listed may still be refused by `build()` for a
	## nonfinite or out-of-domain value. Kept machine-readable so a contract
	## check can assert the exact missing surface for each field.
	func missing_fields() -> Array[String]:
		var missing: Array[String] = []
		if event_id.is_empty():
			missing.append("event_id")
		if tick_index < 0:
			missing.append("tick_index")
		if primary_car_id.is_empty():
			missing.append("primary_car_id")
		if contact_point_world_m == UNSET_VECTOR:
			missing.append("contact_point_world_m")
		if contact_point_local_m == UNSET_VECTOR:
			missing.append("contact_point_local_m")
		if contact_normal_world_m == Vector3.ZERO:
			missing.append("contact_normal_world_m")
		if is_nan(severity_m_s):
			missing.append("severity_m_s")
		if post_contact_velocity_world_m_s == UNSET_VECTOR:
			missing.append("post_contact_velocity_world_m_s")
		if imparted_motion_m == UNSET_VECTOR:
			missing.append("imparted_motion_m")
		if region == REGION_UNSET:
			missing.append("region")
		if not source_committed:
			missing.append("source_committed")
		return missing


	## Whether `mode` is a member of the `NormalMode` domain. An out-of-domain
	## value must refuse instead of falling through to a default branch.
	static func _valid_normal_mode(mode: NormalMode) -> bool:
		return mode == NormalMode.PRESERVE or mode == NormalMode.NORMALIZE


	## Apply the explicit normal mode. PRESERVE leaves the normal untouched so
	## the common validation rule still refuses non-unit input. NORMALIZE
	## accepts a finite normal of at least NORMAL_MIN_LENGTH and publishes a
	## unit normal, using
	## the scaled norm so a very large finite normal normalizes instead of
	## overflowing into a zero vector.
	func _resolve_normal() -> Vector3:
		if normal_mode == NormalMode.NORMALIZE:
			var length := ImpactEvent.stable_norm(contact_normal_world_m)
			if is_finite(length) and length >= NORMAL_MIN_LENGTH:
				return _unit_from_scaled_length(length)
			return Vector3.ZERO
		return contact_normal_world_m

	## Unit vector with the direction of `contact_normal_world_m`, scaled by an
	## already computed `length`.
	##
	## The scalar components are divided and the `Vector3` is built from those
	## quotients. Dividing the vector by `length` instead converts the divisor
	## to the engine's 32-bit float first: `stable_norm` returns a 64-bit
	## script float that stays finite above the float32 maximum, and that
	## conversion turns it into INF, so the quotient collapses to zero and a
	## legitimate normal is then refused as "zero contact normal". The
	## quotients lie in [-1, 1], so constructing the vector cannot overflow.
	func _unit_from_scaled_length(length: float) -> Vector3:
		return Vector3(
			contact_normal_world_m.x / length,
			contact_normal_world_m.y / length,
			contact_normal_world_m.z / length
		)


## Bounded per-tick ledger. Stores copies, returns copies and refuses
## deterministically.
##
## Duplicate handling distinguishes two cases that a single first-wins policy
## silently merges:
##
##   * An identical retry, meaning the same event ID and the same
##     authoritative payload in every field, is coalesced: the retained
##     record wins and `coalesced_count` advances without adding a second
##     record. This is the safe producer-retry path.
##   * A conflicting payload under a retained ID is REFUSED and counted in
##     `conflict_count` as well as `refused_count`. It is never silently
##     discarded and never overwrites the retained record, so a producer ID
##     collision cannot hide a second car's contact behind the first.
##
## Duplicate detection runs before the per-tick capacity check, so an
## identical retry still coalesces when the tick bucket is already full.
##
## Duplicate perspective. Identity is per (physical contact, primary car), so a
## producer that retries a contact under a NEW `event_id` while keeping the same
## nonempty (`contact_id`, `primary_car_id`) pair would publish the same
## perspective twice. Such a record is REFUSED with an explicit reason, the
## retained record is left unchanged, and the complementary record of the other
## primary car still publishes. The refusal is counted in `refused_count` only:
## `conflict_count` stays reserved for a conflicting payload under a retained
## event ID, so the two refusal classes remain distinguishable. The pair key is
## bounded by the retained window exactly like the ID set: a prune or a
## `reset()` forgets it, and after that the same pair may publish again as a
## fresh record.
##
## Producer obligation. One retained perspective per (`contact_id`,
## `primary_car_id`) pair. An identical retry must repeat the same tick,
## event ID and payload to coalesce. A contact reported on a later tick needs
## a distinct contact ID and event ID; reusing the event ID with a new tick is
## a conflicting payload and refuses. This component cannot tell a
## deliberate new contact from a retry of the same one, because it never sees
## the contact geometry.
##
## Memory bounds. Per-tick capacity bounds one tick; the retained-tick bound
## bounds memory across ticks. Pruning forgets the IDs that leave the window,
## so duplicate detection is bounded rather than all-time: after a prune or a
## `reset()` an ID may be published again as a fresh record. `has_event_id()`
## therefore reports retained-window membership, never that an ID was never
## seen before.
##
## A tick far ahead of every retained tick is accepted and occupies one
## retention slot, because pruning always drops the oldest tick. That is
## bounded, one slot and never unbounded growth, but it pins a slot until
## newer ticks push it out. Refusing such a tick needs a coordinator-supplied
## current-tick ceiling, which this component deliberately does not invent;
## that is an integration obligation, and the bounded retention limit is the
## documented fallback.
class Ledger extends RefCounted:
	const DEFAULT_PER_TICK_CAPACITY := 64
	const DEFAULT_MAX_RETAINED_TICKS := 8

	## Result of one `publish()` call.
	class PublishOutcome extends RefCounted:
		enum Status { PUBLISHED, COALESCED, REFUSED }
		var status: Status = Status.REFUSED
		## Retained record copy for PUBLISHED/COALESCED, null for REFUSED.
		var event: ImpactEvent = null
		## Stable reason for COALESCED/REFUSED, empty for PUBLISHED.
		var reason := ""

		func is_published() -> bool:
			return status == Status.PUBLISHED

		func is_coalesced() -> bool:
			return status == Status.COALESCED

		func is_refused() -> bool:
			return status == Status.REFUSED


	var _per_tick_capacity := DEFAULT_PER_TICK_CAPACITY
	var _max_retained_ticks := DEFAULT_MAX_RETAINED_TICKS
	var published_count := 0
	var coalesced_count := 0
	var refused_count := 0
	var conflict_count := 0
	var last_outcome_reason := ""

	var _buckets := {}
	var _bucket_order: Array[int] = []
	var _seen_ids := {}
	var _pair_keys := {}


	func _init(
		per_tick_capacity: int = DEFAULT_PER_TICK_CAPACITY,
		max_retained_ticks: int = DEFAULT_MAX_RETAINED_TICKS
	) -> void:
		_per_tick_capacity = maxi(per_tick_capacity, 0)
		_max_retained_ticks = maxi(max_retained_ticks, 1)


	## Effective per-tick capacity. Private after construction and revalidated
	## on every publish, so a later mutation of the stored field cannot make a
	## publication report success while pruning the record immediately.
	func per_tick_capacity() -> int:
		return maxi(_per_tick_capacity, 0)


	## Effective retained-tick bound. Private after construction and always at
	## least one, so a successful publish is never pruned away at once.
	func max_retained_ticks() -> int:
		return maxi(_max_retained_ticks, 1)


	## Number of refusals caused by a conflicting payload under a retained
	## event ID. Also included in `refused_count`.
	func conflict_total() -> int:
		return conflict_count


	## Publish one already-built event. Validation and duplicate/capacity
	## checks happen before any mutation, so a refusal leaves the ledger
	## byte-for-byte unchanged apart from counters.
	func publish(event: ImpactEvent) -> PublishOutcome:
		var outcome := PublishOutcome.new()
		if event == null:
			return _refuse(outcome, "null event")
		if not event.is_valid():
			return _refuse(outcome, "invalid event: %s" % event.validation_error())
		if not _bucket_order.is_empty() and event.tick_index < _bucket_order[0]:
			return _refuse(
				outcome,
				"tick %d is outside the retained window" % event.tick_index
			)
		if _seen_ids.has(event.event_id):
			var retained := find_by_id(event.event_id)
			if retained == null:
				return _refuse(
					outcome,
					"event id %s is retained but unavailable" % event.event_id
				)
			if retained.same_payload(event):
				coalesced_count += 1
				outcome.status = PublishOutcome.Status.COALESCED
				outcome.reason = "duplicate event id %s" % event.event_id
				outcome.event = retained
				last_outcome_reason = outcome.reason
				return outcome
			conflict_count += 1
			return _refuse(
				outcome,
				"conflicting payload for event id %s" % event.event_id
			)
		if event.has_contact_link() and _pair_keys.has(_pair_key(event)):
			return _refuse(
				outcome,
				"duplicate perspective for contact %s and primary car %s"
					% [event.contact_id, event.primary_car_id]
			)
		var capacity := per_tick_capacity()
		var bucket: Array[ImpactEvent]
		if _buckets.has(event.tick_index):
			bucket = _buckets[event.tick_index]
		else:
			bucket = []
		if bucket.size() >= capacity:
			return _refuse(
				outcome,
				"per-tick capacity %d reached at tick %d"
				% [capacity, event.tick_index]
			)
		bucket.append(event.copy())
		_buckets[event.tick_index] = bucket
		if not _bucket_order.has(event.tick_index):
			_bucket_order.append(event.tick_index)
			_bucket_order.sort()
		_seen_ids[event.event_id] = true
		if event.has_contact_link():
			_pair_keys[_pair_key(event)] = true
		published_count += 1
		_prune_locked()
		outcome.status = PublishOutcome.Status.PUBLISHED
		outcome.event = bucket.back().copy()
		return outcome


	## Copies of the retained events for one tick, oldest publication first.
	func events_for_tick(tick_index: int) -> Array[ImpactEvent]:
		var bucket: Array[ImpactEvent]
		if _buckets.has(tick_index):
			bucket = _buckets[tick_index]
		else:
			bucket = []
		var copies: Array[ImpactEvent] = []
		for event in bucket:
			copies.append(event.copy())
		return copies


	## Copies of every retained event, ordered by tick then publication order.
	func all_events() -> Array[ImpactEvent]:
		var copies: Array[ImpactEvent] = []
		for tick_index in _bucket_order:
			var bucket: Array[ImpactEvent] = _buckets[tick_index]
			for event in bucket:
				copies.append(event.copy())
		return copies


	func event_count() -> int:
		var count := 0
		for tick_index in _bucket_order:
			count += (_buckets[tick_index] as Array[ImpactEvent]).size()
		return count


	func tick_count() -> int:
		return _bucket_order.size()


	func has_event_id(event_id: String) -> bool:
		return _seen_ids.has(event_id)


	## Retained copy of one event by stable ID, or null when pruned/absent.
	func find_by_id(event_id: String) -> ImpactEvent:
		for tick_index in _bucket_order:
			var bucket: Array[ImpactEvent] = _buckets[tick_index]
			for event in bucket:
				if event.event_id == event_id:
					return event.copy()
		return null


	## Deterministic fingerprint of retained contents only. Used by
	## atomic-refusal checks, which must ignore diagnostic counters; not a
	## cryptographic digest.
	##
	## Covers every authoritative field of every retained record through
	## `ImpactEvent.encode_for_digest`, so the fingerprint changes whenever any
	## published field changes, not only the identity, tick, severity and
	## region sampled by earlier revisions.
	func content_digest() -> String:
		var parts: Array[String] = []
		for event in all_events():
			parts.append(_event_digest(event))
		parts.sort()
		var joined := ""
		for index in range(parts.size()):
			if index > 0:
				joined += "|"
			joined += parts[index]
		return joined


	## Content fingerprint plus diagnostic counters.
	func state_digest() -> String:
		return "%s#published=%d,coalesced=%d,refused=%d,conflicts=%d" % [
			content_digest(), published_count, coalesced_count, refused_count,
			conflict_count,
		]


	func reset() -> void:
		_buckets.clear()
		_bucket_order.clear()
		_seen_ids.clear()
		_pair_keys.clear()
		published_count = 0
		coalesced_count = 0
		refused_count = 0
		conflict_count = 0
		last_outcome_reason = ""


	## Loss-free fingerprint of one retained record across every published
	## field. Field order is fixed so the fingerprint is stable across runs.
	static func _event_digest(event: ImpactEvent) -> String:
		var parts := [
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
		var joined := ""
		for index in range(parts.size()):
			if index > 0:
				joined += ","
			joined += parts[index]
		return joined


	func _refuse(outcome: PublishOutcome, reason: String) -> PublishOutcome:
		refused_count += 1
		outcome.status = PublishOutcome.Status.REFUSED
		outcome.reason = reason
		last_outcome_reason = reason
		return outcome


	## Drop oldest tick buckets until the retained-tick bound holds, then
	## forget the IDs that left the window. Only called after a successful
	## publication, so refusals never mutate.
	func _prune_locked() -> void:
		var retained_bound := max_retained_ticks()
		while _bucket_order.size() > retained_bound:
			var oldest: int = _bucket_order.pop_front()
			var old_bucket: Array[ImpactEvent] = _buckets[oldest]
			for old_event in old_bucket:
				_seen_ids.erase(old_event.event_id)
				if old_event.has_contact_link():
					_pair_keys.erase(_pair_key(old_event))
			_buckets.erase(oldest)


	## Retention key of one (contact, primary car) perspective. Records without a
	## contact link never enter this index, so wall and unpaired records cannot
	## collide with each other.
	##
	## The key is length-prefixed, not joined by a separator character.
	## `contact_id` and `primary_car_id` are arbitrary semantic strings and
	## `validation_error()` forbids no character in them, so any single
	## separator is ambiguous: ("a\u001fb", "c") and ("a", "b\u001fc") encode
	## identically, and the second car's record would be refused as a duplicate
	## perspective and lost. Prefixing each component with its character count
	## makes the encoding injective: the first count delimits exactly the first
	## component and the second count the remainder, so two encodings are equal
	## only when both components are equal.
	static func _pair_key(event: ImpactEvent) -> String:
		return "%d:%s%d:%s" % [
			event.contact_id.length(),
			event.contact_id,
			event.primary_car_id.length(),
			event.primary_car_id,
		]
