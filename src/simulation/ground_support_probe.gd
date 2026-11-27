class_name GroundSupportProbe
extends RefCounted
## Bounded, nonmutating ground-support sensing for one `CharacterBody3D`
## rectangular hull (M1.4 laboratory slice).
##
## The probe casts exactly five downward physics ray queries from one
## caller-supplied world transform: one central probe at the hull local origin
## and four footprint probes inset from the hull edges. It never moves the
## body, never writes any input, and never issues a query before every input
## has been validated. Invalid configuration, hull, transform or nonfinite
## values fail atomically with zero queries issued.
##
## The supplied frame must also be world-upright: a sideways frame casts
## horizontally and an inverted frame casts upward, so neither is a legal
## ground-sensing pose even when a support-shaped surface lies along the ray.
## `dot(local +Y, world +Y)` below `min_frame_up_dot` refuses the call
## atomically with zero queries.
##
## Coordinate convention:
##   * world units are metres and world +Y is up;
##   * the hull local frame follows the project car convention: local +X is
##     right, local +Y is up and local +Z is rearward (the nose points -Z);
##   * the supplied transform describes the hull box frame: the hull is
##     centred on the transform origin and spans `hull_size_m / 2` about it;
##   * each probe starts at local `(offset_x, 0, offset_z)` (the hull
##     mid-plane, not the bottom face) and casts along `-basis.y`;
##   * `support_distance_m` is measured along that local down axis from the
##     transform origin; `support_height_m` is the world-vertical drop from
##     the origin to the chosen support point.
##
## The footprint offsets are inset by `footprint_inset_fraction` of each
## half-extent, so they stay inside the hull footprint for any rectangular
## envelope. A hit counts as legal support only when its surface normal has
## `dot(normal, world +Y) >= min_up_dot`, lies at or below the probe start,
## and is within `max_support_distance_m`. Ceilings and wall-like surfaces
## are therefore never promoted to support.
##
## `grounded` requires either a legal central hit or at least
## `required_footprint_hits` legal footprint hits whose support distances
## agree within `footprint_support_spread_max_m`. That lets a body whose
## centre hangs over a legal road seam stay grounded on nearby floor while a
## single distant or steep hit cannot claim support by itself.
##
## Limitations, stated rather than hidden:
##   * point rays have no skin or radius; a seam can fall between the five
##     sample points and thin geometry can be missed;
##   * this is sensing only. It does not sweep, depenetrate, attract, snap or
##     recover, and it makes no claim that the motor should adhere;
##   * physics areas are ignored, so area-tagged surfaces are invisible here;
##     bodies that pass the collision mask (including other cars) read as
##     support;
##   * only rectangular box hulls with the centred convention above are
##     supported; the body scale must be one;
##   * rays use front-face, outside-origin Jolt queries; geometry seen edge-on
##     or from inside may not register;
##   * any legal-normal surface below the probe origin counts as support; the
##     caller must supply route/height context to tell a low ceiling from a
##     road;
##   * the upright gate bounds frame attitude only. It rejects sideways and
##     inverted poses; it does not by itself prove the ray reaches ground
##     rather than another surface that happens to face the cast.
##
## Thresholds here are provisional laboratory defaults, not frozen handling
## coefficients. M1.4 owns final adhesion, landing and attraction values.

enum Status {
	OK,
	REJECTED_INVALID_INPUT,
}

## Exactly one central probe plus four footprint probes.
const PROBE_COUNT := 5
## Hard ceiling for a configured probe length, metres. Keeps sensing work
## bounded and independent of caller enthusiasm.
const ABSOLUTE_MAX_RAY_LENGTH_M := 2.0
## Tolerance for requiring the actual collision shape to match `Config`.
const HULL_MATCH_TOLERANCE_M := 1e-6
## Tolerance for rejecting a scaled, skewed or non-finite supplied basis.
const TRANSFORM_BASIS_TOLERANCE := 1e-4
## A hit this far above its probe start is an upward/overhead reading.
const ABOVE_START_TOLERANCE_M := 1e-6
## Slack for ray-length and support-distance comparisons.
const DISTANCE_TOLERANCE_M := 1e-6
## Below this length a returned normal is treated as degenerate.
const NORMAL_MIN_LENGTH := 1e-6


## Explicit, caller-supplied sensing envelope.
##
## Every physical number used by `probe()` is a field here. The initializers
## are documented laboratory defaults; a coordinator or car resource supplies
## its own values and changing them changes the sensed envelope only.
class Config extends RefCounted:
	## Collision hull envelope (width X, height Y, length Z) in metres. Must
	## match the body's actual BoxShape3D so the probe offsets describe the
	## real footprint. Laboratory envelope, not a car specification.
	var hull_size_m := Vector3(1.8, 1.0, 3.8)
	## Hard ray length from each probe start, metres. Capped by
	## `ABSOLUTE_MAX_RAY_LENGTH_M`.
	var ray_length_m := 1.0
	## Closest legal support the sensor will report, metres along the probe
	## axis. Hits farther than this are recorded but never count as support,
	## so a distant floor seen through a seam cannot be promoted. Must not
	## exceed `ray_length_m`.
	var max_support_distance_m := 0.75
	## Footprint inset as a fraction of each hull half-extent, in
	## [0, 0.5). Zero places probes on the hull edges; 0.15 keeps them just
	## inside.
	var footprint_inset_fraction := 0.15
	## Minimum `dot(unit_normal, world +Y)` for a hit to be legal floor,
	## measured against the world up axis rather than the hull attitude so a
	## rolled or pitched body cannot excuse a wall or ceiling. 0.5 admits slopes
	## up to 30 degrees from horizontal, above the 12% grade and +/-12 degree
	## banking targets, and rejects wall-like normals.
	var min_up_dot := 0.5
	## Minimum `dot(local hull +Y, world +Y)` for the supplied frame to be a
	## legal ground-sensing pose. 0.5 admits a frame tilted up to 60 degrees
	## from vertical, well beyond the +/-12 degree banking target, while a
	## sideways frame (dot 0) and an inverted frame (dot -1) are refused before
	## any query. Separate from `min_up_dot` because it gates frame attitude,
	## not surface slope.
	var min_frame_up_dot := 0.5
	## Legal footprint hits required to ground a body whose centre probe
	## found no support, in [1, 4].
	var required_footprint_hits := 2
	## Maximum spread among the legal footprint support distances for the
	## centre-miss ground decision, metres.
	var footprint_support_spread_max_m := 0.25


	func footprint_offsets() -> Array[Vector3]:
		var half_x := 0.5 * hull_size_m.x
		var half_z := 0.5 * hull_size_m.z
		var x := half_x * (1.0 - footprint_inset_fraction)
		var z := half_z * (1.0 - footprint_inset_fraction)
		return [
			Vector3(0.0, 0.0, 0.0),
			Vector3(x, 0.0, z),
			Vector3(-x, 0.0, z),
			Vector3(x, 0.0, -z),
			Vector3(-x, 0.0, -z),
		]


	func is_valid() -> bool:
		if not GroundSupportProbe._finite_positive_vector3(hull_size_m):
			return false
		if not GroundSupportProbe._finite(ray_length_m) or ray_length_m <= 0.0:
			return false
		if ray_length_m > ABSOLUTE_MAX_RAY_LENGTH_M:
			return false
		if not GroundSupportProbe._finite(max_support_distance_m) or max_support_distance_m <= 0.0:
			return false
		# A support bound beyond the ray length would report a distance the
		# sensor can never observe.
		if max_support_distance_m > ray_length_m:
			return false
		if (
			not GroundSupportProbe._finite(footprint_inset_fraction)
			or footprint_inset_fraction < 0.0
			or footprint_inset_fraction >= 0.5
		):
			return false
		if not GroundSupportProbe._finite(min_up_dot) or min_up_dot < 0.0 or min_up_dot > 1.0:
			return false
		# Zero would admit a perfectly sideways frame, so the gate needs a
		# strictly positive threshold.
		if (
			not GroundSupportProbe._finite(min_frame_up_dot)
			or min_frame_up_dot <= 0.0
			or min_frame_up_dot > 1.0
		):
			return false
		if required_footprint_hits < 1 or required_footprint_hits > 4:
			return false
		if (
			not GroundSupportProbe._finite(footprint_support_spread_max_m)
			or footprint_support_spread_max_m < 0.0
		):
			return false
		if footprint_support_spread_max_m > ABSOLUTE_MAX_RAY_LENGTH_M:
			return false
		return true


## Outcome of one probe call. All per-probe fields are world-space.
class Result extends RefCounted:
	var status: Status = Status.OK
	var rejection_reason := ""
	## Alignment of the supplied frame's local +Y with world +Y at entry.
	var frame_up_dot := 0.0
	## True when the ground rule below is satisfied.
	var grounded := false
	## True when the central probe alone found legal support.
	var center_supported := false
	## Number of legal support hits across all five probes.
	var support_count := 0
	## Number of legal support hits among the four footprint probes.
	var footprint_support_count := 0
	## Closest legal support point below the transform origin, if any.
	var has_support := false
	var support_probe_index := -1
	var support_point := Vector3.ZERO
	## Averaged unit normal of the legal hits, zero when none survive the
	## up-dot check.
	var support_normal := Vector3.ZERO
	## Distance from the transform origin to the support point along local
	## down, metres.
	var support_distance_m := 0.0
	## World-vertical drop from the transform origin to the support point,
	## metres (positive below the origin).
	var support_height_m := 0.0
	## Validated detail for each of the five probes, in fixed order.
	var probes: Array[Dictionary] = []
	## Actual `intersect_ray` calls issued. Five on success, zero on refusal.
	var queries_used := 0
	var world_transform := Transform3D()


## Probe one explicit hull pose without moving the body or mutating any input.
##
## `world_transform` is the hull frame to sense from; it need not equal the
## body's current `global_transform`. The body supplies only its collision
## mask and RID (excluded), so a caller can evaluate a simulated pose before
## committing it.
static func probe(
	body: CharacterBody3D,
	hull_shape: BoxShape3D,
	config: Config,
	world_transform: Transform3D
) -> Result:
	var result := Result.new()
	result.world_transform = world_transform
	if body == null or hull_shape == null or config == null:
		return _reject(result, "null body, hull shape or config")
	if not config.is_valid():
		return _reject(result, "invalid support probe config")
	if not _finite_positive_vector3(hull_shape.size):
		return _reject(result, "nonfinite or non-positive hull shape")
	if hull_shape.size.distance_to(config.hull_size_m) > HULL_MATCH_TOLERANCE_M:
		return _reject(result, "collision hull does not match the documented envelope")
	if not body.scale.is_equal_approx(Vector3.ONE):
		return _reject(result, "scaled body is outside the documented box-hull convention")
	if not _transform_is_usable(world_transform):
		return _reject(result, "nonfinite, scaled or non-orthonormal transform")
	# Attitude gate before any query: a sideways or inverted frame is not a
	# legal ground-sensing pose regardless of what lies along its cast.
	var frame_up_dot := world_transform.basis.y.dot(Vector3.UP)
	result.frame_up_dot = frame_up_dot
	if frame_up_dot < config.min_frame_up_dot:
		return _reject(
			result,
			"hull frame is outside the world-upright gate (up dot %.6f)" % frame_up_dot
		)
	var world := body.get_world_3d()
	if world == null or world.direct_space_state == null:
		return _reject(result, "body is not inside a physics world")

	var space := world.direct_space_state
	# The cast follows the hull's local down so a banked or pitched pose still
	# probes its own footprint. Legal-normal acceptance is measured against
	# world +Y so a rolled body cannot excuse a wall or ceiling.
	var down := -world_transform.basis.y
	var up := Vector3.UP
	var offsets := config.footprint_offsets()
	var labels := [
		"center",
		"rear_right",
		"rear_left",
		"front_right",
		"front_left",
	]
	var probes: Array[Dictionary] = []
	var valid_distances: Array[float] = []
	var valid_normals: Array[Vector3] = []
	var valid_indices: Array[int] = []
	var queries := 0

	for index in range(PROBE_COUNT):
		var local_offset: Vector3 = offsets[index]
		var start := world_transform * local_offset
		var end := start + down * config.ray_length_m
		var detail := {
			"index": index,
			"label": labels[index],
			"offset_local": local_offset,
			"start": start,
			"end": end,
			"direction": down,
			"hit": false,
			"valid": false,
			"position": Vector3.ZERO,
			"normal": Vector3.ZERO,
			"distance_m": 0.0,
			"up_dot": 0.0,
			"reason": "no_hit",
		}

		var query := PhysicsRayQueryParameters3D.new()
		query.from = start
		query.to = end
		query.collision_mask = body.collision_mask
		query.exclude = [body.get_rid()]
		query.collide_with_bodies = true
		query.collide_with_areas = false
		query.hit_from_inside = false

		var hit: Dictionary = space.intersect_ray(query)
		queries += 1
		if hit.is_empty():
			probes.append(detail)
			continue

		detail["hit"] = true
		var position: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		if not _vector3_is_finite(position) or not _vector3_is_finite(normal):
			detail["reason"] = "nonfinite_hit"
			probes.append(detail)
			continue

		var along := (position - start).dot(down)
		detail["position"] = position
		detail["normal"] = normal
		detail["distance_m"] = maxf(0.0, along)
		detail["up_dot"] = normal.normalized().dot(up)
		if along < -ABOVE_START_TOLERANCE_M:
			detail["reason"] = "above_start"
		elif along > config.ray_length_m + DISTANCE_TOLERANCE_M:
			detail["reason"] = "beyond_ray"
		elif normal.length_squared() < NORMAL_MIN_LENGTH * NORMAL_MIN_LENGTH:
			detail["reason"] = "degenerate_normal"
		elif detail["up_dot"] < config.min_up_dot:
			detail["reason"] = "steep_normal"
		elif along > config.max_support_distance_m + DISTANCE_TOLERANCE_M:
			detail["reason"] = "beyond_max_support"
		else:
			detail["valid"] = true
			detail["reason"] = "ok"
			valid_distances.append(clampf(along, 0.0, config.max_support_distance_m))
			valid_normals.append(normal.normalized())
			valid_indices.append(index)
		probes.append(detail)

	# Internal work-cap invariant: the loop above is the entire query budget.
	assert(queries == PROBE_COUNT)

	result.status = Status.OK
	result.probes = probes
	result.queries_used = queries
	result.support_count = valid_indices.size()
	result.center_supported = not probes.is_empty() and bool(probes[0]["valid"])

	var footprint_count := 0
	var footprint_min := INF
	var footprint_max := -INF
	for index in range(1, PROBE_COUNT):
		if bool(probes[index]["valid"]):
			footprint_count += 1
			var distance: float = probes[index]["distance_m"]
			footprint_min = minf(footprint_min, distance)
			footprint_max = maxf(footprint_max, distance)
	result.footprint_support_count = footprint_count

	result.grounded = result.center_supported
	if not result.grounded and footprint_count >= config.required_footprint_hits:
		result.grounded = (footprint_max - footprint_min) <= config.footprint_support_spread_max_m

	if valid_indices.is_empty():
		return result

	# Closest legal support below the supplied pose.
	var best := 0
	for index in range(1, valid_indices.size()):
		if valid_distances[index] < valid_distances[best]:
			best = index
	var chosen_index: int = valid_indices[best]
	result.has_support = true
	result.support_probe_index = chosen_index
	result.support_point = probes[chosen_index]["position"]
	result.support_distance_m = valid_distances[best]
	result.support_height_m = world_transform.origin.y - result.support_point.y

	# Bounded average of the unit normals: at most `PROBE_COUNT` contributions
	# and renormalized, so the result is always a unit vector or zero. An
	# average that cancels below the same up-dot floor is reported as zero.
	var normal_sum := Vector3.ZERO
	for unit_normal in valid_normals:
		normal_sum += unit_normal
	if normal_sum.length() > NORMAL_MIN_LENGTH:
		var averaged := normal_sum.normalized()
		if averaged.dot(up) >= config.min_up_dot:
			result.support_normal = averaged
	return result


static func _reject(result: Result, reason: String) -> Result:
	result.status = Status.REJECTED_INVALID_INPUT
	result.rejection_reason = reason
	result.probes = []
	result.queries_used = 0
	return result


static func _transform_is_usable(value: Transform3D) -> bool:
	if not _vector3_is_finite(value.origin):
		return false
	var basis := value.basis
	for column in [basis.x, basis.y, basis.z]:
		if not _vector3_is_finite(column):
			return false
		if absf(column.length() - 1.0) > TRANSFORM_BASIS_TOLERANCE:
			return false
	if absf(basis.x.dot(basis.y)) > TRANSFORM_BASIS_TOLERANCE:
		return false
	if absf(basis.y.dot(basis.z)) > TRANSFORM_BASIS_TOLERANCE:
		return false
	if absf(basis.x.dot(basis.z)) > TRANSFORM_BASIS_TOLERANCE:
		return false
	if absf(basis.determinant() - 1.0) > TRANSFORM_BASIS_TOLERANCE:
		return false
	return true


static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)


static func _finite_positive_vector3(value: Vector3) -> bool:
	return (
		_vector3_is_finite(value)
		and value.x > 0.0
		and value.y > 0.0
		and value.z > 0.0
	)


static func _vector3_is_finite(value: Vector3) -> bool:
	return _finite(value.x) and _finite(value.y) and _finite(value.z)
