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
##     delta, throttle input or a presentation speed.
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
##   * `event_id` and `tick_index`: coordinator/event-bus assigned identity
##     and logical tick or sequence index.
##
## Missing authoritative seam: `MotorBodyAdapter.Result` exposes an
## authoritative `wall_contact_normal` but no authoritative wall contact
## point. Its generic `contact_point` is the first reported contact of the
## last colliding substep and can be floor-first even when a later wall
## contact drove the response. Wall events therefore cannot yet carry a
## truthful `contact_point_world_m`; the adapter or integrator must add a
## dedicated wall-contact point query before integration.
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
	## Normalize a nonzero finite normal before validation and publication.
	NORMALIZE,
}

## Names parallel to `ContactRegion`, for logs and machine-readable reports.
const REGION_NAMES: Array[String] = ["front", "rear", "left", "right"]

## Published normals must be unit length within this absolute tolerance.
const NORMAL_UNIT_TOLERANCE := 1e-4
## A normal shorter than this is treated as zero/invalid and refused.
const NORMAL_MIN_LENGTH := 1e-6

## Field names the integrator must fill from authoritative simulation state.
## Kept machine-readable so contract checks can assert the published surface.
const INTEGRATOR_SUPPLIED_FIELDS: Array[String] = [
	"severity_m_s",
	"post_contact_velocity_world_m_s",
	"contact_point_world_m",
	"contact_normal_world_m",
	"contact_point_local_m",
	"imparted_motion_m",
	"region",
]

## Stable unique identity of this physical contact. Empty is invalid.
var event_id := ""
## Logical tick or sequence index at which the contact was committed.
var tick_index := -1
## Semantic ID of the primary (striken/own) car. Never empty.
var primary_car_id := ""
## Semantic ID of the other car in a car-car contact. Empty means wall,
## scenery, self-contact or a contact with no second car.
var other_car_id := ""
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
var region: ContactRegion = ContactRegion.FRONT
## True only for records built from an authoritative committed source.
var committed := false


## Whether a second car participates in this contact.
func has_other_car() -> bool:
	return not other_car_id.is_empty()


## Whether this record came from a committed authoritative source.
func is_committed() -> bool:
	return committed


## Magnitude of the imparted contact displacement, metres.
func imparted_motion_magnitude_m() -> float:
	return imparted_motion_m.length()


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
	var normal_length := contact_normal_world_m.length()
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


static func _finite_vector(value: Vector3) -> bool:
	return (
		is_finite(value.x)
		and is_finite(value.y)
		and is_finite(value.z)
	)


## Pure validating factory for committed impact records.
##
## Assign fields, then call `build()`. `build()` mutates no ledger and no
## simulation state; on refusal it returns null and sets `rejection_reason`.
## Defaults are deliberately invalid so a forgotten field refuses instead of
## publishing a plausible-looking event.
class Builder extends RefCounted:
	var event_id := ""
	var tick_index := -1
	var primary_car_id := ""
	var other_car_id := ""
	var contact_point_world_m := Vector3.ZERO
	var contact_point_local_m := Vector3.ZERO
	var contact_normal_world_m := Vector3.ZERO
	var severity_m_s := NAN
	var post_contact_velocity_world_m_s := Vector3.ZERO
	var imparted_motion_m := Vector3.ZERO
	var region: ContactRegion = ContactRegion.FRONT
	var normal_mode: NormalMode = NormalMode.PRESERVE
	var source_committed := false
	var rejection_reason := ""


	## Validate every field and return a committed record, or null on refusal.
	func build() -> ImpactEvent:
		rejection_reason = ""
		var event := ImpactEvent.new()
		event.event_id = event_id
		event.tick_index = tick_index
		event.primary_car_id = primary_car_id
		event.other_car_id = other_car_id
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


	## Apply the explicit normal mode. PRESERVE leaves the normal untouched so
	## the common validation rule still refuses non-unit input. NORMALIZE
	## accepts any nonzero finite normal and publishes a unit normal.
	func _resolve_normal() -> Vector3:
		if normal_mode == NormalMode.NORMALIZE:
			var length := contact_normal_world_m.length()
			if is_finite(length) and length >= NORMAL_MIN_LENGTH:
				return contact_normal_world_m / length
			return Vector3.ZERO
		return contact_normal_world_m


## Bounded per-tick ledger. Stores copies, returns copies and refuses
## deterministically. Duplicate event IDs are coalesced: the first retained
## event wins and later repeats increment `coalesced_count` without adding a
## second record. Per-tick capacity bounds one tick; retained-tick bound bounds
## memory across ticks. Pruned IDs leave duplicate detection, so event IDs must
## be globally unique by construction.
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


	var per_tick_capacity := DEFAULT_PER_TICK_CAPACITY
	var max_retained_ticks := DEFAULT_MAX_RETAINED_TICKS
	var published_count := 0
	var coalesced_count := 0
	var refused_count := 0
	var last_outcome_reason := ""

	var _buckets := {}
	var _bucket_order: Array[int] = []
	var _seen_ids := {}


	func _init(
		per_tick_capacity: int = DEFAULT_PER_TICK_CAPACITY,
		max_retained_ticks: int = DEFAULT_MAX_RETAINED_TICKS
	) -> void:
		self.per_tick_capacity = maxi(per_tick_capacity, 0)
		self.max_retained_ticks = maxi(max_retained_ticks, 1)


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
			coalesced_count += 1
			outcome.status = PublishOutcome.Status.COALESCED
			outcome.reason = "duplicate event id %s" % event.event_id
			outcome.event = find_by_id(event.event_id)
			last_outcome_reason = outcome.reason
			return outcome
		var bucket: Array[ImpactEvent]
		if _buckets.has(event.tick_index):
			bucket = _buckets[event.tick_index]
		else:
			bucket = []
		if bucket.size() >= per_tick_capacity:
			return _refuse(
				outcome,
				"per-tick capacity %d reached at tick %d"
				% [per_tick_capacity, event.tick_index]
			)
		bucket.append(event.copy())
		_buckets[event.tick_index] = bucket
		if not _bucket_order.has(event.tick_index):
			_bucket_order.append(event.tick_index)
			_bucket_order.sort()
		_seen_ids[event.event_id] = true
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
	func content_digest() -> String:
		var parts: Array[String] = []
		for event in all_events():
			parts.append(
				"%s@%d:%s:%s" % [
					event.event_id,
					event.tick_index,
					event.severity_m_s,
					event.region_name(),
				]
			)
		parts.sort()
		var joined := ""
		for index in range(parts.size()):
			if index > 0:
				joined += "|"
			joined += parts[index]
		return joined


	## Content fingerprint plus diagnostic counters.
	func state_digest() -> String:
		return "%s#published=%d,coalesced=%d,refused=%d" % [
			content_digest(), published_count, coalesced_count, refused_count,
		]


	func reset() -> void:
		_buckets.clear()
		_bucket_order.clear()
		_seen_ids.clear()
		published_count = 0
		coalesced_count = 0
		refused_count = 0
		last_outcome_reason = ""


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
		while _bucket_order.size() > max_retained_ticks:
			var oldest: int = _bucket_order.pop_front()
			var old_bucket: Array[ImpactEvent] = _buckets[oldest]
			for old_event in old_bucket:
				_seen_ids.erase(old_event.event_id)
			_buckets.erase(oldest)
