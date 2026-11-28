class_name WallImpactProducer
extends RefCounted
## Pure, bounded producer that turns one committed `MotorBodyAdapter.Result`
## carrying the authoritative wall-response witness into an `ImpactEvent`
## record (M1.8 wall-impact publication slice).
##
## The producer owns no clock, physics query, scene node, ledger or identity
## allocation. A coordinator supplies the committed adapter result, the same
## validated `MotorBodyAdapter.Config` the adapter accepted, the primary car
## ID, the event ID, an optional shared contact ID and the logical tick index;
## the producer rebuilds the physical fields from the adapter's witness and
## never invents or renumbers an identity. `produce()` mutates no simulation
## state, no ledger and no input object. `publish()` only forwards an
## already-built event to `ImpactEvent.Ledger`; it never re-reads the result.
##
## Authority rules enforced here (fail closed, with a stable reason):
##
##   * `result.status` must be `COMMITTED`, and both explicit witness flags
##     (`has_wall_response_witness`, `has_wall_contact_point`) must be true;
##   * the committed state, the selected wall point, the selected raw normal
##     and the collision-time frame must be finite, and the frame must be
##     non-degenerate, so an affine-inverse local point can be computed;
##   * the witness post velocity must equal the committed state's planar
##     velocity mapped back to world axes exactly, because the committed state
##     is the authority for the post-response velocity; the adapter samples the
##     witness and the committed planar velocity from the same world vector, so
##     their round trip is bit-exact and no tolerance is admitted here;
##   * the published normal is the normalized road-plane projection of the
##     adapter's selected `wall_contact_normal`, never the raw possibly tilted
##     normal and never the generic first-contact `contact_normal`;
##   * `severity_m_s` is only `ImpactEvent.stable_norm(wall_pre - wall_post)`,
##     the magnitude across the contact response itself. It is never derived
##     from motor acceleration, throttle, sweep travel or `accepted_motion_m`.
##
## `contact_point_local_m` is `wall_contact_transform.affine_inverse() *
## wall_contact_point`. The frame is the body pose at the selected collision:
## the tick-start sweep basis at the colliding substep's committed origin,
## before the tick's yaw is finalized. It is deliberately not the final
## post-yaw pose; the record describes the contact, and a consumer that needs
## the final pose must transform again. Region is classified from that local
## point against half the validated `Config.hull_size_m` extents (local -Z
## forward, +X right). A box-wall contact lands on a hull vertex whose pinned
## solver point can sit inside both face planes by centimetres; when both axes
## are within `REGION_CORNER_BAND_M` of their half-extents the collision-time
## response normal, transformed by the same frame's inverse basis, identifies
## the struck face if its dominant-axis sign borders the contacted quadrant.
## A normal whose X and Z components are too close to call, or whose sign is
## inconsistent with that quadrant, identifies nothing and classification
## falls back to the exact-point comparison, whose deterministic corner tie
## resolves to FRONT/REAR. Contacts outside the corner band stay
## point-classified.
##
## On this adapter path the wall response alters velocity after the sweep and
## performs no further body movement, so `imparted_motion_m` is exactly
## `Vector3.ZERO`. The total accepted sweep travel (`accepted_motion_m`) is not
## a contact-induced displacement and is never substituted for it.
##
## The builder is called with `source_committed = true` only after every
## authoritative check above passes. A synthetic Result proves these
## publication contracts; it is not proof that the witness came from a real
## committed physics response. Car-car production, presentation wiring and
## cosmetic damage remain later integration work; this module makes no M1
## acceptance claim.

## Metre band around both hull half-extents within which a local contact point
## counts as part of a corner. This is a classification capture width, not a
## solver tolerance. Pinned Godot 4.7.2/Jolt flat straight box-wall vertex
## witnesses were measured inset by at most 0.0160 m in X and 0.0139 m in Z
## across 38,034 witnesses, independent of `orientation_contact_tolerance_m`
## in its validated 0-0.1 m range. A 0.6 m wall end sliding along the side of
## the same laboratory hull remained a side-face contact as close as 0.0288 m
## to the nose plane, so 0.035 m covers that measured wall-end transition
## while true face-centre contacts remain far outside the band. This constant
## is not a general hull contract: other hull dimensions, wall shapes or
## orientation tolerances need their own pinned measurements before widening
## or reusing it.
const REGION_CORNER_BAND_M := 0.035
## Minimum difference between the absolute X and Z components of the local
## response normal for it to identify a face. A normal closer to diagonal than
## this cannot break a near-tie and the exact-point comparison is used.
const REGION_NORMAL_AXIS_MARGIN := 1e-3
## Smallest usable road-plane projection length of the selected wall normal.
## Mirrors the adapter's degenerate-normal guard (`1e-12` squared) so a
## producer cannot promote a contact the adapter itself would treat as
## unusable.
const MIN_ROAD_PLANE_NORMAL_LENGTH := 1e-6
## Minimum absolute basis determinant for the collision-time frame. The
## laboratory body basis is orthonormal (determinant magnitude 1); this only
## rejects a degenerate or collapsed transform before `affine_inverse()`.
const MIN_CONTACT_FRAME_DETERMINANT := 1e-6

## Outcome of `produce()`. `event` is a fresh, valid committed `ImpactEvent`
## on success; on refusal it is null, `reason` is a stable non-empty string,
## and no ledger or simulation state was touched.
class BuildOutcome extends RefCounted:
	var event: ImpactEvent = null
	var reason := ""

	func is_ok() -> bool:
		return event != null

	func is_refused() -> bool:
		return event == null


## Build the wall impact event for one committed adapter result, or refuse.
##
## `contact_id` is optional; an empty value means no shared contact link, which
## is the normal wall path. `tick_index` defaults to 0 and must not be
## negative. Refusal reasons are deterministic for a given input.
static func produce(
	result: MotorBodyAdapter.Result,
	config: MotorBodyAdapter.Config,
	primary_car_id: String,
	event_id: String,
	contact_id := "",
	tick_index := 0
) -> BuildOutcome:
	var outcome := BuildOutcome.new()
	if result == null:
		return _refuse(outcome, "null adapter result")
	if config == null:
		return _refuse(outcome, "null motor-body config")
	if not config.is_valid():
		return _refuse(outcome, "invalid motor-body config")
	if primary_car_id.is_empty():
		return _refuse(outcome, "empty primary car id")
	if event_id.is_empty():
		return _refuse(outcome, "empty event id")
	if tick_index < 0:
		return _refuse(outcome, "negative tick index")
	if result.status != MotorBodyAdapter.Status.COMMITTED:
		return _refuse(outcome, "adapter result status is not COMMITTED")
	if not result.has_wall_response_witness:
		return _refuse(outcome, "missing wall response witness")
	if not result.has_wall_contact_point:
		return _refuse(outcome, "missing wall contact point witness")

	var committed: CarState = result.committed_state
	if committed == null:
		return _refuse(outcome, "missing committed state")
	if not committed.is_finite():
		return _refuse(outcome, "nonfinite committed state")

	var pre_velocity := result.wall_pre_response_velocity_world_m_s
	var post_velocity := result.wall_post_response_velocity_world_m_s
	if not _finite_vector(pre_velocity):
		return _refuse(outcome, "nonfinite pre-response velocity")
	if not _finite_vector(post_velocity):
		return _refuse(outcome, "nonfinite post-response velocity")
	var committed_world := MotorBodyAdapter.road_vector_to_world(
		committed.velocity_m_s
	)
	if not _finite_vector(committed_world):
		return _refuse(outcome, "nonfinite committed planar velocity")
	if post_velocity != committed_world:
		return _refuse(
			outcome, "post-response velocity disagrees with committed state"
		)

	var raw_normal := result.wall_contact_normal
	if not _finite_vector(raw_normal):
		return _refuse(outcome, "nonfinite wall contact normal")
	var contact_normal := _normalized_road_plane_normal(raw_normal)
	if contact_normal == Vector3.ZERO:
		return _refuse(
			outcome, "degenerate wall contact normal road-plane projection"
		)

	var world_point := result.wall_contact_point
	if not _finite_vector(world_point):
		return _refuse(outcome, "nonfinite wall contact point")
	var contact_frame := result.wall_contact_transform
	if not _finite_transform(contact_frame):
		return _refuse(
			outcome, "nonfinite or degenerate wall contact transform"
		)
	var local_point := contact_frame.affine_inverse() * world_point
	if not _finite_vector(local_point):
		return _refuse(outcome, "nonfinite local contact point")
	# The same collision-time inverse rotation expresses the selected response
	# normal in the frame the point is classified in. The origin is irrelevant
	# to a direction, so only the basis inverse is applied.
	var local_normal := contact_frame.basis.inverse() * contact_normal
	if not _finite_vector(local_normal):
		return _refuse(
			outcome, "nonfinite collision-time local response normal"
		)

	var severity := ImpactEvent.stable_norm(pre_velocity - committed_world)
	if not is_finite(severity):
		return _refuse(outcome, "nonfinite severity")

	var builder := ImpactEvent.Builder.new()
	builder.event_id = event_id
	builder.tick_index = tick_index
	builder.primary_car_id = primary_car_id
	builder.other_car_id = ""
	builder.contact_id = contact_id
	builder.contact_point_world_m = world_point
	builder.contact_point_local_m = local_point
	builder.contact_normal_world_m = contact_normal
	builder.severity_m_s = severity
	builder.post_contact_velocity_world_m_s = committed_world
	# The wall response changes velocity after the sweep; the sweep's accepted
	# travel is not contact-induced motion. Explicitly zero, never derived.
	builder.imparted_motion_m = Vector3.ZERO
	builder.region = _classify_region(
		local_point, config.hull_size_m, local_normal
	)
	builder.normal_mode = ImpactEvent.NormalMode.PRESERVE
	builder.source_committed = true
	var event := builder.build()
	if event == null:
		return _refuse(outcome, builder.rejection_reason)
	outcome.event = event
	return outcome


## Forward one already-built event to the ledger. The producer does not build,
## validate or mutate the event here, and the adapter result is not read at
## all. A null ledger refuses locally instead of crashing; a real ledger
## applies its own validation, duplicate, capacity and window rules.
static func publish(
	event: ImpactEvent, ledger: ImpactEvent.Ledger
) -> ImpactEvent.Ledger.PublishOutcome:
	if ledger == null:
		var outcome := ImpactEvent.Ledger.PublishOutcome.new()
		outcome.reason = "null ledger"
		return outcome
	return ledger.publish(event)


## Unit normal of the road-plane projection of `normal`, or zero when the
## projection is nonfinite or shorter than `MIN_ROAD_PLANE_NORMAL_LENGTH`.
## Uses `ImpactEvent.stable_norm` and scalar quotients so a large finite normal
## cannot overflow into a zero direction.
static func _normalized_road_plane_normal(normal: Vector3) -> Vector3:
	var projected := Vector3(normal.x, 0.0, normal.z)
	if not _finite_vector(projected):
		return Vector3.ZERO
	if projected.length_squared() < (
		MIN_ROAD_PLANE_NORMAL_LENGTH * MIN_ROAD_PLANE_NORMAL_LENGTH
	):
		return Vector3.ZERO
	var length := ImpactEvent.stable_norm(projected)
	if not is_finite(length) or length <= 0.0:
		return Vector3.ZERO
	return Vector3(
		projected.x / length,
		0.0,
		projected.z / length
	)


## FRONT/REAR/LEFT/RIGHT from a local contact point against half the hull
## extents. Local -Z is forward and +X is right. Coordinates are normalized by
## their own half extent for the deterministic point rule. When the point is
## within `REGION_CORNER_BAND_M` of both face planes, the collision-time
## response normal in the same local frame may name the struck face. The
## normal is used only when one axis is clearly dominant and its sign borders
## the contacted quadrant: front (local Z negative) expects +Z, rear expects
## -Z, left (local X negative) expects +X and right expects -X. A diagonal or
## sign-inconsistent normal falls back to the deterministic point comparison,
## which resolves an exact corner tie to FRONT/REAR; fallback is deliberate
## because a malformed opposite-sign normal must never publish the opposite
## face.
static func _classify_region(
	local_point: Vector3,
	hull_size_m: Vector3,
	local_normal: Vector3
) -> ImpactEvent.ContactRegion:
	var half_extents := hull_size_m * 0.5
	var lateral := absf(local_point.x) / half_extents.x
	var longitudinal := absf(local_point.z) / half_extents.z
	var near_side_face := absf(absf(local_point.x) - half_extents.x) \
		<= REGION_CORNER_BAND_M
	var near_end_face := absf(absf(local_point.z) - half_extents.z) \
		<= REGION_CORNER_BAND_M
	if near_side_face and near_end_face:
		var lateral_normal := absf(local_normal.x)
		var longitudinal_normal := absf(local_normal.z)
		if absf(lateral_normal - longitudinal_normal) \
				> REGION_NORMAL_AXIS_MARGIN:
			if longitudinal_normal > lateral_normal:
				if local_point.z < 0.0 and local_normal.z > 0.0:
					return ImpactEvent.ContactRegion.FRONT
				if local_point.z > 0.0 and local_normal.z < 0.0:
					return ImpactEvent.ContactRegion.REAR
			else:
				if local_point.x < 0.0 and local_normal.x > 0.0:
					return ImpactEvent.ContactRegion.LEFT
				if local_point.x > 0.0 and local_normal.x < 0.0:
					return ImpactEvent.ContactRegion.RIGHT
	if longitudinal >= lateral:
		return (
			ImpactEvent.ContactRegion.FRONT
			if local_point.z < 0.0
			else ImpactEvent.ContactRegion.REAR
		)
	return (
		ImpactEvent.ContactRegion.RIGHT
		if local_point.x > 0.0
		else ImpactEvent.ContactRegion.LEFT
	)

## True when the transform has a finite origin and a finite basis whose
## determinant is safely away from zero, so `affine_inverse()` cannot produce a
## nonfinite or collapsed local point.
static func _finite_transform(transform: Transform3D) -> bool:
	if not _finite_vector(transform.origin):
		return false
	var basis := transform.basis
	if not _finite_vector(basis.x) or not _finite_vector(basis.y) \
			or not _finite_vector(basis.z):
		return false
	var determinant := basis.determinant()
	return is_finite(determinant) and absf(determinant) > MIN_CONTACT_FRAME_DETERMINANT


static func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


static func _refuse(outcome: BuildOutcome, reason: String) -> BuildOutcome:
	outcome.event = null
	outcome.reason = reason
	return outcome
