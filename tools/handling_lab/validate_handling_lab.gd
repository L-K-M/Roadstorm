extends SceneTree
## Headless validation entry point for the M1.2 static handling laboratory.
##
## Run from an isolated project copy:
##   godot --headless --fixed-fps 60 --path <project> \
##       --script res://tools/handling_lab/validate_handling_lab.gd
##
## The script extends SceneTree, instantiates the laboratory scene, waits for a
## few physics frames so Jolt has the static colliders, then checks section
## identities, dimensions, clearance, transform finiteness, collider presence,
## surface metadata and representative ray queries. It prints one
## LAB_RESULT <json> line and exits 0 only when every check passed.
##
## Scope: structural geometry validation only. This is not a handling
## measurement and makes no M1.2 acceptance claim.

const LAB_SCENE_PATH := "res://scenes/laboratory/handling_lab.tscn"
const SETTLE_PHYSICS_FRAMES := 8
const MAX_WAIT_FRAMES := 1800
const RAY_TOLERANCE_M := 0.35
const DIMENSION_TOLERANCE_M := 0.05
## Tolerance for the measured Jolt collision gap versus the authored jump gap.
const GAP_MEASUREMENT_TOLERANCE_M := 0.2

const EXPECTED_BAY_IDS: Array[String] = [
	"bank",
	"contact",
	"gravel",
	"grounding",
	"hairpin",
	"jump",
	"recovery",
	"shoulder",
	"straight",
	"sweeper",
]
const REQUIRED_SURFACE_IDS: Array[String] = [
	"asphalt",
	"gravel",
	"shoulder",
	"sand",
	"recovery",
	"barrier",
]
const DRIVABLE_SURFACES: Array[String] = ["asphalt", "gravel", "recovery"]
const FORBIDDEN_TAG_KEYS: Array[String] = [
	"face_index",
	"triangle_index",
	"jolt_face_index",
]
const HandlingLabBuilderScript := preload("res://src/laboratory/handling_lab_builder.gd")
const HandlingLabDataScript := preload("res://src/laboratory/handling_lab_data.gd")
## Synthetic regression: a bay whose first cross-section carries break_before
## (a restart strip at the very start) must still produce only nonempty runs.
const SYNTHETIC_RESTART_RUN_COUNT := 4
const MIN_BAY_SEPARATION_M := 1.0

var _checks := 0
var _failures: Array[String] = []
var _measured: Dictionary = {}
var _lab: Node = null
var _physics_gate := -1
var _wait_frames := 0
var _finished := false


func _initialize() -> void:
	var backend := str(ProjectSettings.get_setting("physics/3d/physics_engine"))
	if backend != "Jolt Physics":
		_record_failure(
			"environment.backend",
			"expected Jolt Physics, got %s" % backend
		)
	var packed: PackedScene = load(LAB_SCENE_PATH)
	if packed == null:
		_record_failure("scene.load", "could not load %s" % LAB_SCENE_PATH)
		_finish()
		return
	_lab = packed.instantiate()
	if _lab == null:
		_record_failure("scene.instantiate", "could not instantiate %s" % LAB_SCENE_PATH)
		_finish()
		return
	_lab.name = "HandlingLabValidation"
	root.add_child.call_deferred(_lab)


func _process(_delta: float) -> bool:
	if _finished:
		return true
	if _lab == null or not is_instance_valid(_lab):
		_finish()
		return true
	if _physics_gate < 0:
		if not _lab.is_inside_tree():
			return false
		_physics_gate = Engine.get_physics_frames() + SETTLE_PHYSICS_FRAMES
		return false
	if Engine.get_physics_frames() < _physics_gate:
		_wait_frames += 1
		if _wait_frames > MAX_WAIT_FRAMES:
			_record_failure(
				"environment.settle",
				"physics did not settle within %d frames" % MAX_WAIT_FRAMES
			)
			_finish()
			return true
		return false
	_run_checks()
	_finish()
	return true


# --- Checks ----------------------------------------------------------------


func _run_checks() -> void:
	if not _lab.has_meta("lab_manifest"):
		_record_failure("manifest.present", "root has no lab_manifest metadata")
		return
	var manifest: Dictionary = _lab.get_meta("lab_manifest")

	_check_manifest_identity(manifest)
	_check_manifest_surfaces(manifest)
	_check_bays_and_sections(manifest)
	_check_colliders()
	_check_surface_tags(manifest)
	_check_pose_markers(manifest)
	_check_dimensions(manifest)
	_check_layout_separation()
	_check_features_and_walls(manifest)
	_check_ray_probes(manifest)
	_check_boundary_probes(manifest)
	_check_determinism()
	_check_first_restart_synthetic()


func _check_manifest_identity(manifest: Dictionary) -> void:
	_check(
		String(manifest.get("schema_version", "")) == "roadstorm.handling_lab.v1",
		"manifest.schema_version",
		str(manifest.get("schema_version", ""))
	)
	_check(
		String(manifest.get("lab_id", "")) == "roadstorm.laboratory.handling_lab",
		"manifest.lab_id",
		str(manifest.get("lab_id", ""))
	)
	var frame: Dictionary = manifest.get("coordinate_frame", {})
	_check(String(frame.get("forward", "")) == "-Z", "manifest.frame.forward", str(frame))
	_check(String(frame.get("up", "")) == "+Y", "manifest.frame.up", str(frame))
	_check(String(frame.get("right", "")) == "+X", "manifest.frame.right", str(frame))
	_check(bool(manifest.get("preliminary", false)), "manifest.preliminary_flag", "must be true")
	_check(
		not String(manifest.get("preliminary_notice", "")).is_empty(),
		"manifest.preliminary_notice",
		"empty"
	)
	_check(bool(manifest.get("deterministic", false)), "manifest.deterministic_flag", "must be true")


func _check_manifest_surfaces(manifest: Dictionary) -> void:
	var registry: Array[String] = []
	for surface in manifest.get("surfaces", []):
		registry.append(String(surface.get("surface_id", "")))
	for required in REQUIRED_SURFACE_IDS:
		_check(registry.has(required), "surfaces.registry.%s" % required, str(registry))
	var envelope: Dictionary = manifest.get("car_envelope_m", {})
	_check(
		absf(float(envelope.get("length", 0.0)) - 4.8) <= 1e-6
		and absf(float(envelope.get("width", 0.0)) - 2.2) <= 1e-6
		and absf(float(envelope.get("height", 0.0)) - 1.8) <= 1e-6,
		"clearance.car_envelope",
		str(envelope)
	)
	_check(
		absf(float(manifest.get("required_road_width_m", 0.0)) - 4.2) <= 1e-6,
		"clearance.required_road_width_m",
		str(manifest.get("required_road_width_m", 0.0))
	)


func _section_records(manifest: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for bay in manifest.get("bays", []):
		for section in bay.get("sections", []):
			out.append(section)
	return out


func _bay_records(manifest: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for bay in manifest.get("bays", []):
		out.append(bay)
	return out


func _features(manifest: Dictionary, feature_name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for bay in manifest.get("bays", []):
		for feature in bay.get("features", []):
			if String(feature.get("feature", "")) == feature_name:
				out.append(feature)
	return out


func _check_bays_and_sections(manifest: Dictionary) -> void:
	var bays := _bay_records(manifest)
	var ids: Array[String] = []
	for bay in bays:
		ids.append(String(bay.get("bay_id", "")))
	var expected := EXPECTED_BAY_IDS.duplicate()
	expected.sort()
	ids.sort()
	_check(ids == expected, "bays.identity_set", str(ids))

	var sections := _section_records(manifest)
	var mesh_nodes := _meshes_with_meta(_lab, "section_id")
	var body_nodes := _bodies_with_meta(_lab, "section_id")
	var road_roles := 0
	for section in sections:
		var sid := String(section.get("section_id", ""))
		_check(not sid.is_empty(), "sections.nonempty_id", sid)
		var has_mesh := _node_for_section(mesh_nodes, sid) != null
		var has_body := _node_for_section(body_nodes, sid) != null
		if String(section.get("type", "")) == "gap":
			_check(not has_mesh and not has_body, "sections.gap_has_no_geometry", sid)
			continue
		if String(section.get("role", "")) == "strip":
			# Restarted strips author their own station origin, so their
			# station range must begin at zero regardless of the road bay.
			_check(
				absf(float(section.get("start_s_m", 0.0))) <= 1e-6,
				"sections.restart_strip_station.%s" % sid,
				str(section.get("start_s_m", 0.0))
			)
		_check(has_mesh, "sections.mesh_present.%s" % sid, "missing MeshInstance3D")
		_check(has_body, "sections.collider_present.%s" % sid, "missing StaticBody3D")
		if String(section.get("role", "")) == "road":
			road_roles += 1
			_check(
				String(section.get("surface_id", "")) in DRIVABLE_SURFACES,
				"sections.drivable_surface.%s" % sid,
				String(section.get("surface_id", ""))
			)
			_check(
				float(section.get("width_m", 0.0)) + DIMENSION_TOLERANCE_M
				>= float(manifest.get("required_road_width_m", 4.2)),
				"clearance.road_width.%s" % sid,
				str(section.get("width_m", 0.0))
			)
	_measured["bay_count"] = bays.size()
	_measured["section_count"] = sections.size()
	_measured["drivable_section_count"] = road_roles


func _check_colliders() -> void:
	var bodies := _bodies_with_meta(_lab, "collision_role")
	var checked_shapes := 0
	for body in bodies:
		var role := String(body.get_meta("collision_role"))
		_check(role == "terrain" or role == "wall", "collider.role.%s" % body.name, role)
		var shapes: Array[Node] = []
		for child in body.get_children():
			if child is CollisionShape3D:
				shapes.append(child)
		_check(shapes.size() >= 1, "collider.shape_present.%s" % body.name, str(shapes.size()))
		for shape_node in shapes:
			checked_shapes += 1
			_check(shape_node.shape != null, "collider.shape_valid.%s" % body.name, "null shape")
	_measured["static_body_count"] = bodies.size()
	_measured["collision_shape_count"] = checked_shapes


func _check_surface_tags(manifest: Dictionary) -> void:
	var registry: Array[String] = []
	for surface in manifest.get("surfaces", []):
		registry.append(String(surface.get("surface_id", "")))
	var tagged := _nodes_with_meta(_lab, "surface_id")
	var seen: Array[String] = []
	for node in tagged:
		var sid := String(node.get_meta("surface_id"))
		seen.append(sid)
		_check(not sid.is_empty() and registry.has(sid), "tags.surface_id.%s" % node.name, sid)
		for forbidden in FORBIDDEN_TAG_KEYS:
			_check(
				not node.has_meta(forbidden),
				"tags.no_face_indices.%s.%s" % [node.name, forbidden],
				"face-index tagging is forbidden"
			)
	var seen_set := {}
	for sid in seen:
		seen_set[sid] = true
	for required in ["asphalt", "gravel", "shoulder", "recovery"]:
		_check(seen_set.has(required), "tags.required_surface.%s" % required, str(seen))


func _check_pose_markers(manifest: Dictionary) -> void:
	var pose_nodes := _nodes_with_meta(_lab, "pose_role")
	var spawn_count := 0
	var recovery_count := 0
	var anchor_count := 0
	var names := {}
	for node in pose_nodes:
		var role := String(node.get_meta("pose_role"))
		match role:
			"spawn":
				spawn_count += 1
			"recovery":
				recovery_count += 1
			"recovery_zone_anchor":
				anchor_count += 1
		names[node.name] = int(names.get(node.name, 0)) + 1
		_check(_finite_transform(node.transform), "transform.finite.%s" % node.name, str(node.transform))
	for name_key in names:
		_check(int(names[name_key]) == 1, "transform.unique_name.%s" % name_key, str(names[name_key]))
	var bay_count := _bay_records(manifest).size()
	_check(spawn_count == bay_count, "transform.spawn_count", "%d vs %d" % [spawn_count, bay_count])
	_check(recovery_count == bay_count, "transform.recovery_count", "%d vs %d" % [recovery_count, bay_count])
	_check(anchor_count >= 1, "transform.recovery_anchor_present", str(anchor_count))
	_measured["spawn_count"] = spawn_count
	_measured["recovery_count"] = recovery_count
	_measured["recovery_anchor_count"] = anchor_count


func _check_dimensions(manifest: Dictionary) -> void:
	var straight_mesh := _mesh_for_section("straight.main")
	if straight_mesh != null:
		var length := straight_mesh.get_aabb().size.z
		_check(absf(length - 500.0) <= DIMENSION_TOLERANCE_M, "dimensions.straight_500m", "%.3f" % length)
		_measured["straight_length_m"] = length
	var contact_mesh := _mesh_for_section("contact.approach")
	if contact_mesh != null:
		var length := contact_mesh.get_aabb().size.z
		_check(absf(length - 500.0) <= DIMENSION_TOLERANCE_M, "dimensions.contact_500m", "%.3f" % length)

	var sweeper := _section_by_id(manifest, "sweeper.arc")
	if not sweeper.is_empty():
		_check(absf(float(sweeper["radius_m"]) - 120.0) <= 1e-6, "dimensions.sweeper_radius", str(sweeper["radius_m"]))
		_check(absf(float(sweeper["angle_deg"]) - 90.0) <= 1e-6, "dimensions.sweeper_angle", str(sweeper["angle_deg"]))
		_check(
			absf(float(sweeper["length_m"]) - 120.0 * PI * 0.5) <= 1e-3,
			"dimensions.sweeper_arc_length",
			str(sweeper["length_m"])
		)
	var hairpin := _section_by_id(manifest, "hairpin.arc")
	if not hairpin.is_empty():
		_check(absf(float(hairpin["radius_m"]) - 30.0) <= 1e-6, "dimensions.hairpin_radius", str(hairpin["radius_m"]))
		_check(absf(float(hairpin["angle_deg"]) - 180.0) <= 1e-6, "dimensions.hairpin_angle", str(hairpin["angle_deg"]))
		_check(
			absf(float(hairpin["length_m"]) - 30.0 * PI) <= 1e-3,
			"dimensions.hairpin_arc_length",
			str(hairpin["length_m"])
		)
	var gravel_sector := _section_by_id(manifest, "gravel.sector")
	if not gravel_sector.is_empty():
		_check(
			absf(float(gravel_sector["length_m"]) - 80.0) <= 1e-3,
			"dimensions.gravel_sector_length",
			str(gravel_sector["length_m"])
		)

	var max_bank := 0.0
	var max_grade := 0.0
	for section in _section_records(manifest):
		if String(section.get("bay_id", "")) == "bank":
			max_bank = maxf(max_bank, absf(float(section.get("banking_start_deg", 0.0))))
			max_bank = maxf(max_bank, absf(float(section.get("banking_end_deg", 0.0))))
		if String(section.get("bay_id", "")) == "grounding":
			max_grade = maxf(max_grade, absf(float(section.get("grade_start_percent", 0.0))))
			max_grade = maxf(max_grade, absf(float(section.get("grade_end_percent", 0.0))))
	_check(max_bank >= 12.0 - 1e-6 and max_bank <= 12.0 + 1e-6, "dimensions.bank_limit_12deg", "%.6f" % max_bank)
	_check(max_grade >= 12.0 - 1e-6 and max_grade <= 12.0 + 1e-6, "dimensions.grade_limit_12pct", "%.6f" % max_grade)
	_measured["max_abs_bank_deg"] = max_bank
	_measured["max_abs_grade_percent"] = max_grade

	var pad_mesh := _mesh_for_section("recovery.pad")
	if pad_mesh != null:
		var pad_size := pad_mesh.get_aabb().size
		var envelope: Dictionary = manifest.get("car_envelope_m", {})
		var clearance := float(manifest.get("clearance_margin_m", 1.0))
		var needed_x := float(envelope.get("length", 4.8)) + 2.0 * clearance
		var needed_z := float(envelope.get("length", 4.8)) + 2.0 * clearance
		_check(pad_size.x >= needed_x - DIMENSION_TOLERANCE_M, "dimensions.recovery_pad_x", "%.3f" % pad_size.x)
		_check(pad_size.z >= needed_z - DIMENSION_TOLERANCE_M, "dimensions.recovery_pad_z", "%.3f" % pad_size.z)
		_measured["recovery_pad_x_m"] = pad_size.x
		_measured["recovery_pad_z_m"] = pad_size.z


func _check_layout_separation() -> void:
	var boxes: Array = []
	for bay_node in _typed_children(_lab, "Bay_", "bay_id"):
		boxes.append([String(bay_node.get_meta("bay_id")), _world_aabb(bay_node)])
	var minimum_separation := INF
	var worst_pair := ""
	for i in range(boxes.size()):
		for j in range(i + 1, boxes.size()):
			var sep := _aabb_separation(boxes[i][1], boxes[j][1])
			if sep < minimum_separation:
				minimum_separation = sep
				worst_pair = "%s/%s" % [boxes[i][0], boxes[j][0]]
	_check(
		minimum_separation >= MIN_BAY_SEPARATION_M,
		"layout.bay_separation",
		"min %.3f m (%s)" % [minimum_separation, worst_pair]
	)
	_measured["minimum_bay_separation_m"] = minimum_separation


func _typed_children(node: Node, prefix: String, meta_key: String) -> Array[Node]:
	var out: Array[Node] = []
	for child in node.get_children():
		if String(child.name).begins_with(prefix) and child.has_meta(meta_key):
			out.append(child)
	return out


func _world_aabb(node: Node3D) -> AABB:
	var min_c := Vector3(INF, INF, INF)
	var max_c := Vector3(-INF, -INF, -INF)
	for mi in _meshes_with_meta(node, "surface_id"):
		var local := mi.get_aabb()
		var basis := mi.get_global_transform().basis
		var origin := mi.get_global_transform().origin
		for xi in range(2):
			var x := local.position.x if xi == 0 else local.end.x
			for yi in range(2):
				var y := local.position.y if yi == 0 else local.end.y
				for zi in range(2):
					var z := local.position.z if zi == 0 else local.end.z
					var w := origin + basis * Vector3(x, y, z)
					min_c = Vector3(minf(min_c.x, w.x), minf(min_c.y, w.y), minf(min_c.z, w.z))
					max_c = Vector3(maxf(max_c.x, w.x), maxf(max_c.y, w.y), maxf(max_c.z, w.z))
	return AABB(min_c, max_c - min_c)


func _aabb_separation(a: AABB, b: AABB) -> float:
	var dx := maxf(a.position.x - b.end.x, b.position.x - a.end.x)
	var dy := maxf(a.position.y - b.end.y, b.position.y - a.end.y)
	var dz := maxf(a.position.z - b.end.z, b.position.z - a.end.z)
	if dx < 0.0:
		dx = 0.0
	if dy < 0.0:
		dy = 0.0
	if dz < 0.0:
		dz = 0.0
	return sqrt(dx * dx + dy * dy + dz * dz)


func _check_features_and_walls(manifest: Dictionary) -> void:
	var gaps := _features(manifest, "jump_gap")
	_check(gaps.size() == 1, "features.jump_gap_count", str(gaps.size()))
	if gaps.size() == 1:
		var gap := gaps[0]
		var envelope: Dictionary = manifest.get("car_envelope_m", {})
		var clearance := float(manifest.get("clearance_margin_m", 1.0))
		_check(float(gap.get("gap_m", 0.0)) > 0.0, "features.jump_gap_positive", str(gap.get("gap_m", 0.0)))
		_check(_finite(float(gap.get("drop_m", 0.0))), "features.jump_drop_finite", str(gap.get("drop_m", 0.0)))
		_check(
			float(gap.get("landing_run_m", 0.0)) >= float(envelope.get("length", 4.8)) + clearance,
			"features.jump_landing_run_clearance",
			str(gap.get("landing_run_m", 0.0))
		)
		_check(bool(gap.get("preliminary", false)), "features.jump_preliminary_label", "must be preliminary")
		_measured["jump_gap_m"] = float(gap.get("gap_m", 0.0))
		_measured["jump_drop_m"] = float(gap.get("drop_m", 0.0))
		_measured["jump_landing_run_m"] = float(gap.get("landing_run_m", 0.0))

	var contact_bay := _bay_by_id(manifest, "contact")
	var walls: Array = contact_bay.get("walls", [])
	_check(walls.size() >= 2, "features.wall_count", str(walls.size()))
	var envelope_height := float(manifest.get("car_envelope_m", {}).get("height", 1.8))
	var wall_count := 0
	for wall in walls:
		wall_count += 1
		_check(
			float(wall.get("height_m", 0.0)) >= envelope_height - DIMENSION_TOLERANCE_M,
			"features.wall_height.%s" % String(wall.get("wall_id", "")),
			str(wall.get("height_m", 0.0))
		)
		_check(
			float(wall.get("length_m", 0.0)) >= float(manifest.get("required_road_width_m", 4.2)),
			"features.wall_span.%s" % String(wall.get("wall_id", "")),
			str(wall.get("length_m", 0.0))
		)
		_check(bool(wall.get("status", "") == "preliminary_graybox"), "features.wall_preliminary_label", str(wall.get("status", "")))
	_measured["wall_count"] = wall_count


func _check_ray_probes(manifest: Dictionary) -> void:
	var probes: Dictionary = manifest.get("probe_points", {})
	for key in ["floor_asphalt", "floor_gravel", "floor_shoulder", "floor_jump_landing", "recovery_pad"]:
		if not probes.has(key):
			_record_failure("probe.missing.%s" % key, "authored probe absent")
			continue
		var probe: Dictionary = probes[key]
		var from: Vector3 = probe["from"]
		var to: Vector3 = probe["to"]
		var hit := _ray_hit(from, to)
		if hit.is_empty():
			_record_failure("probe.%s.hit" % key, "no ray hit")
			continue
		var collider: Object = hit.get("collider")
		var surface_id := ""
		if collider != null and collider.has_meta("surface_id"):
			surface_id = String(collider.get_meta("surface_id"))
		_check(surface_id == String(probe.get("expected_surface", "")), "probe.%s.surface" % key, surface_id)
		var expected: Vector3 = probe["expected_position"]
		var distance: float = (hit["position"] as Vector3).distance_to(expected)
		_check(distance <= RAY_TOLERANCE_M, "probe.%s.position" % key, "%.3f m" % distance)
		_measured["probe_%s_distance_m" % key] = distance

	if probes.has("wall_frontal"):
		var wall_probe: Dictionary = probes["wall_frontal"]
		var from: Vector3 = wall_probe["from"]
		var to: Vector3 = wall_probe["to"]
		var hit := _ray_hit(from, to)
		if hit.is_empty():
			_record_failure("probe.wall_frontal.hit", "no ray hit")
		else:
			var collider: Object = hit.get("collider")
			var role := ""
			if collider != null and collider.has_meta("collision_role"):
				role = String(collider.get_meta("collision_role"))
			_check(role == "wall", "probe.wall_frontal.role", role)
			var expected: Vector3 = wall_probe["expected_position"]
			var distance: float = (hit["position"] as Vector3).distance_to(expected)
			_check(distance <= 1.0, "probe.wall_frontal.position", "%.3f m" % distance)
			_measured["probe_wall_frontal_distance_m"] = distance
	else:
		_record_failure("probe.missing.wall_frontal", "authored probe absent")


func _check_boundary_probes(manifest: Dictionary) -> void:
	_check_join_probes(manifest)
	_check_restart_probes(manifest)
	_check_jump_gap_probe(manifest)


func _metadata_join_keys(manifest: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for bay in manifest.get("bays", []):
		var prev: Dictionary = {}
		for section in bay.get("sections", []):
			if String(section.get("type", "")) == "gap":
				prev = {}
				continue
			if not prev.is_empty():
				var station := float(prev.get("end_s_m", 0.0))
				if absf(station - float(section.get("start_s_m", 0.0))) <= 1e-6:
					out.append("%s@%.3f" % [String(bay.get("bay_id", "")), station])
			prev = section
	return out


func _check_join_probes(manifest: Dictionary) -> void:
	var probes: Dictionary = manifest.get("probe_points", {})
	if not probes.has("join_probes"):
		_record_failure("probe.missing.join_probes", "authored join probes absent")
		return
	var joins: Array = probes["join_probes"]
	var metadata := _metadata_join_keys(manifest)
	_check(
		joins.size() == metadata.size(),
		"probe.join_count",
		"%d probes vs %d metadata joins" % [joins.size(), metadata.size()]
	)
	var covered := {}
	for join in joins:
		var bay_id := String(join.get("bay_id", ""))
		var station := float(join.get("station_s_m", 0.0))
		var before_surface := String(join.get("before_surface_id", ""))
		var after_surface := String(join.get("after_surface_id", ""))
		covered["%s@%.3f" % [bay_id, station]] = true
		var label := "probe.join.%s.%.2f" % [bay_id, station]
		_run_expected_probe(join.get("before", {}), "%s.before" % label, before_surface)
		_run_expected_probe(join.get("seam_before", {}), "%s.seam_before" % label, before_surface)
		_run_expected_probe(join.get("seam_after", {}), "%s.seam_after" % label, after_surface)
		_run_expected_probe(join.get("after", {}), "%s.after" % label, after_surface)
	for key in metadata:
		_check(covered.has(key), "probe.join_coverage.%s" % key, "no authored join probe")


func _check_restart_probes(manifest: Dictionary) -> void:
	var probes: Dictionary = manifest.get("probe_points", {})
	if not probes.has("restart_probes"):
		_record_failure("probe.missing.restart_probes", "authored restart probes absent")
		return
	var restarts: Array = probes["restart_probes"]
	_check(restarts.size() >= 1, "probe.restart_count", str(restarts.size()))
	for entry in restarts:
		var surface := String(entry.get("surface_id", ""))
		var label := "probe.restart.%s" % String(entry.get("section_id", ""))
		_run_expected_probe(entry.get("start", {}), "%s.start" % label, surface)
		_run_expected_probe(entry.get("end", {}), "%s.end" % label, surface)


func _check_jump_gap_probe(manifest: Dictionary) -> void:
	var probes: Dictionary = manifest.get("probe_points", {})
	if not probes.has("jump_gap"):
		_record_failure("probe.missing.jump_gap", "authored jump gap probes absent")
		return
	var gp: Dictionary = probes["jump_gap"]
	var gaps := _features(manifest, "jump_gap")
	_check(gaps.size() == 1, "probe.jump_gap_feature_count", str(gaps.size()))
	if gaps.is_empty():
		return
	var feature: Dictionary = gaps[0]
	var section_id := String(feature.get("section_id", ""))
	var gap_section := _section_by_id(manifest, section_id)
	_check(not gap_section.is_empty(), "probe.jump_gap_section", "gap section missing")
	if gap_section.is_empty():
		return

	var start: Vector3 = gp["start"]
	var end: Vector3 = gp["end"]
	var gap_m := float(gp["gap_m"])
	var drop_m := float(gp["drop_m"])
	_check(start.is_equal_approx(feature["start"]), "jump_gap.feature_start_matches_probe", str(start))
	_check(end.is_equal_approx(feature["end"]), "jump_gap.feature_end_matches_probe", str(end))
	_check(
		absf(float(feature.get("gap_m", 0.0)) - gap_m) <= 1e-6,
		"jump_gap.feature_gap_matches_probe",
		str(gap_m)
	)
	var flat_span := Vector3(end.x - start.x, 0.0, end.z - start.z).length()
	_check(
		absf(flat_span - gap_m) <= DIMENSION_TOLERANCE_M,
		"jump_gap.authored_horizontal_span",
		"%.3f m" % flat_span
	)
	var vertical_drop := start.y - end.y
	_check(
		absf(vertical_drop - drop_m) <= DIMENSION_TOLERANCE_M,
		"jump_gap.authored_vertical_drop",
		"%.3f m" % vertical_drop
	)
	var station_span := float(gap_section.get("end_s_m", 0.0)) - float(gap_section.get("start_s_m", 0.0))
	_check(absf(station_span - gap_m) <= 1e-6, "jump_gap.section_station_span", "%.3f m" % station_span)

	var sections: Array = _bay_by_id(manifest, String(gap_section.get("bay_id", ""))).get("sections", [])
	var gap_index := -1
	for i in range(sections.size()):
		if String(sections[i].get("section_id", "")) == section_id:
			gap_index = i
			break
	_check(gap_index > 0, "jump_gap.takeoff_section_present", str(gap_index))
	_check(gap_index + 1 < sections.size(), "jump_gap.landing_section_present", str(gap_index))
	if gap_index > 0:
		var prev_section: Dictionary = sections[gap_index - 1]
		_check(
			absf(float(prev_section.get("end_s_m", 0.0)) - float(gap_section.get("start_s_m", 0.0))) <= 1e-6,
			"jump_gap.takeoff_section_station",
			"%.3f vs %.3f" % [
				float(prev_section.get("end_s_m", 0.0)),
				float(gap_section.get("start_s_m", 0.0))
			]
		)
		_check(
			String(prev_section.get("surface_id", "")) == String(gp.get("takeoff_surface_id", "")),
			"jump_gap.takeoff_surface_metadata",
			String(prev_section.get("surface_id", ""))
		)
	if gap_index + 1 < sections.size():
		var next_section: Dictionary = sections[gap_index + 1]
		_check(
			absf(float(next_section.get("start_s_m", 0.0)) - float(gap_section.get("end_s_m", 0.0))) <= 1e-6,
			"jump_gap.landing_section_station",
			"%.3f vs %.3f" % [
				float(next_section.get("start_s_m", 0.0)),
				float(gap_section.get("end_s_m", 0.0))
			]
		)
		_check(
			String(next_section.get("surface_id", "")) == String(gp.get("landing_surface_id", "")),
			"jump_gap.landing_surface_metadata",
			String(next_section.get("surface_id", ""))
		)

	var takeoff_surface := String(gp.get("takeoff_surface_id", ""))
	var landing_surface := String(gp.get("landing_surface_id", ""))
	_run_expected_probe(gp.get("takeoff_before", {}), "probe.jump_gap.takeoff_before", takeoff_surface)
	_run_expected_probe(gp.get("takeoff_edge", {}), "probe.jump_gap.takeoff_edge", takeoff_surface)
	_run_no_hit_probe(gp.get("mid_gap", {}), "probe.jump_gap.mid_gap")
	_run_expected_probe(gp.get("landing_edge", {}), "probe.jump_gap.landing_edge", landing_surface)
	_run_expected_probe(gp.get("landing_after", {}), "probe.jump_gap.landing_after", landing_surface)

	var measured := _measure_collision_gap(start, end)
	_measured["jump_gap_measured_m"] = measured
	_check(
		absf(measured - gap_m) <= GAP_MEASUREMENT_TOLERANCE_M,
		"jump_gap.measured_collision_gap",
		"%.3f m measured vs %.3f m authored" % [measured, gap_m]
	)


func _run_expected_probe(probe: Dictionary, label: String, expected_surface: String) -> void:
	if probe.is_empty():
		_record_failure("%s.present" % label, "probe absent")
		return
	var hit := _ray_hit(probe["from"], probe["to"])
	if hit.is_empty():
		_record_failure("%s.hit" % label, "no ray hit")
		return
	var collider: Object = hit.get("collider")
	var surface_id := ""
	if collider != null and collider.has_meta("surface_id"):
		surface_id = String(collider.get_meta("surface_id"))
	_check(surface_id == expected_surface, "%s.surface" % label, surface_id)
	var expected: Vector3 = probe["expected_position"]
	var distance := (hit["position"] as Vector3).distance_to(expected)
	_check(distance <= RAY_TOLERANCE_M, "%s.position" % label, "%.3f m" % distance)
	_measured["%s_distance_m" % label] = distance


func _run_no_hit_probe(probe: Dictionary, label: String) -> void:
	if probe.is_empty():
		_record_failure("%s.present" % label, "probe absent")
		return
	var hit := _ray_hit(probe["from"], probe["to"])
	_check(hit.is_empty(), "%s.unexpected_hit" % label, str(hit.get("position", Vector3.ZERO)))


func _gap_ground_at(flat_a: Vector3, flat_b: Vector3, y_ref: float, t: float) -> bool:
	var p := flat_a.lerp(flat_b, t)
	var hit := _ray_hit(
		Vector3(p.x, y_ref + 3.0, p.z),
		Vector3(p.x, y_ref - 10.0, p.z)
	)
	return not hit.is_empty()


func _measure_collision_gap(start: Vector3, end: Vector3) -> float:
	var flat_a := Vector3(start.x, 0.0, start.z)
	var flat_b := Vector3(end.x, 0.0, end.z)
	var span := flat_a.distance_to(flat_b)
	if span <= 1e-6:
		return 0.0
	var y_ref := maxf(start.y, end.y)
	var lo := 0.0
	var hi := 0.5
	for _i in range(32):
		var mid := 0.5 * (lo + hi)
		if _gap_ground_at(flat_a, flat_b, y_ref, mid):
			lo = mid
		else:
			hi = mid
	var takeoff_t := lo
	lo = 0.5
	hi = 1.0
	for _i in range(32):
		var mid := 0.5 * (lo + hi)
		if _gap_ground_at(flat_a, flat_b, y_ref, mid):
			hi = mid
		else:
			lo = mid
	var landing_t := hi
	return (landing_t - takeoff_t) * span


func _check_determinism() -> void:
	var packed: PackedScene = load(LAB_SCENE_PATH)
	if packed == null:
		_record_failure("determinism.second_load", "could not reload scene")
		return
	var second := packed.instantiate()
	if second == null:
		_record_failure("determinism.second_instantiate", "could not instantiate second scene")
		return
	second.name = "HandlingLabSecondValidation"
	var holder := Node3D.new()
	holder.name = "HandlingLabDeterminismHolder"
	root.add_child(holder)
	holder.add_child(second)
	var first_signature := _fingerprint(_lab)
	var second_signature := _fingerprint(second)
	_check(first_signature == second_signature, "determinism.rebuild_fingerprint", "second build differs")
	holder.queue_free()


# --- Helpers ---------------------------------------------------------------


func _record_failure(label: String, detail: String) -> void:
	_check(false, label, detail)


func _check(ok: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if not ok:
		if detail.is_empty():
			_failures.append(label)
		else:
			_failures.append("%s (%s)" % [label, detail])


func _nodes_with_meta(node: Node, key: String) -> Array[Node]:
	var out: Array[Node] = []
	if node.has_meta(key):
		out.append(node)
	for child in node.get_children():
		out.append_array(_nodes_with_meta(child, key))
	return out


func _meshes_with_meta(node: Node, key: String) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for candidate in _nodes_with_meta(node, key):
		if candidate is MeshInstance3D:
			out.append(candidate)
	return out


func _bodies_with_meta(node: Node, key: String) -> Array[StaticBody3D]:
	var out: Array[StaticBody3D] = []
	for candidate in _nodes_with_meta(node, key):
		if candidate is StaticBody3D:
			out.append(candidate)
	return out


func _node_for_section(nodes: Array, section_id: String) -> Node:
	for node in nodes:
		if String(node.get_meta("section_id")) == section_id:
			return node
	return null


func _mesh_for_section(section_id: String) -> MeshInstance3D:
	var meshes := _meshes_with_meta(_lab, "section_id")
	var node := _node_for_section(meshes, section_id)
	if node == null:
		return null
	return node as MeshInstance3D


func _section_by_id(manifest: Dictionary, section_id: String) -> Dictionary:
	for section in _section_records(manifest):
		if String(section.get("section_id", "")) == section_id:
			return section
	return {}


func _bay_by_id(manifest: Dictionary, bay_id: String) -> Dictionary:
	for bay in _bay_records(manifest):
		if String(bay.get("bay_id", "")) == bay_id:
			return bay
	return {}


func _ray_hit(from: Vector3, to: Vector3) -> Dictionary:
	var space := root.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.hit_back_faces = false
	return space.intersect_ray(query)


func _finite(value: float) -> bool:
	return is_finite(value)


func _finite_vec(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _finite_transform(transform: Transform3D) -> bool:
	return (
		_finite_vec(transform.origin)
		and _finite_vec(transform.basis.x)
		and _finite_vec(transform.basis.y)
		and _finite_vec(transform.basis.z)
	)


func _synthetic_first_restart_bay() -> Dictionary:
	var origin := Vector3.ZERO
	return {
		"bay_id": "synthetic_first_restart",
		"title": "Synthetic bay beginning with a restart strip",
		"origin": origin,
		"yaw_deg": 0.0,
		"fixture_refs": [],
		"segments": [
			HandlingLabDataScript.straight(
				"synthetic.restart_a", 20.0, 12.0, "asphalt",
				0.0, 0.0, 0.0, 0.0, "synthetic_restart_a", 0.0, "road",
				"synthetic_regression", true
			),
			HandlingLabDataScript.straight(
				"synthetic.joined_b", 20.0, 12.0, "asphalt",
				0.0, 0.0, 0.0, 0.0, "synthetic_joined_b", 0.0, "road",
				"synthetic_regression"
			),
			HandlingLabDataScript.straight(
				"synthetic.restart_c", 20.0, 12.0, "asphalt",
				0.0, 0.0, 0.0, 0.0, "synthetic_restart_c", 0.0, "road",
				"synthetic_regression", true
			),
			HandlingLabDataScript.straight(
				"synthetic.joined_d", 20.0, 12.0, "asphalt",
				0.0, 0.0, 0.0, 0.0, "synthetic_joined_d", 0.0, "road",
				"synthetic_regression"
			),
		],
		"walls": [],
	}


func _check_first_restart_synthetic() -> void:
	var bay := _synthetic_first_restart_bay()
	var origin: Vector3 = bay["origin"]
	var sampled: Dictionary = HandlingLabBuilderScript._sample_bay(bay)
	var samples: Array = sampled["samples"]
	_check(samples.size() > 0, "synthetic.first_restart.samples_present", str(samples.size()))
	if samples.is_empty():
		return
	_check(
		bool(samples[0].get("break_before", false)),
		"synthetic.first_restart.first_sample_break_before",
		str(samples[0].get("break_before", false))
	)
	_check(
		(samples[0]["pos"] as Vector3).is_equal_approx(origin),
		"synthetic.first_restart.first_sample_at_origin",
		str(samples[0]["pos"])
	)
	_check(
		absf(float(samples[0]["s"])) <= 1e-6,
		"synthetic.first_restart.first_sample_station_zero",
		str(samples[0]["s"])
	)

	var runs: Array = HandlingLabBuilderScript._split_runs(samples)
	_check(
		runs.size() == SYNTHETIC_RESTART_RUN_COUNT,
		"synthetic.first_restart.run_count",
		"%d vs %d" % [runs.size(), SYNTHETIC_RESTART_RUN_COUNT]
	)

	# A restart resets the station to zero; an ordinary join keeps it running.
	var expected_starts := [0.0, 20.0, 0.0, 20.0]
	var expected_ends := [20.0, 40.0, 20.0, 40.0]
	for i in range(runs.size()):
		var run: Array = runs[i]
		var label := "synthetic.first_restart.run_%d" % i
		_check(run.size() > 0, "%s.nonempty" % label, str(run.size()))
		if run.is_empty():
			continue
		# Surface generation needs at least two cross-sections per run.
		_check(run.size() >= 2, "%s.min_samples" % label, str(run.size()))
		if i >= expected_starts.size():
			continue
		var first: Dictionary = run[0]
		var last: Dictionary = run[run.size() - 1]
		_check(
			absf(float(first["s"]) - expected_starts[i]) <= 1e-6,
			"%s.start_station" % label,
			"%.3f vs %.3f" % [float(first["s"]), expected_starts[i]]
		)
		_check(
			absf(float(last["s"]) - expected_ends[i]) <= 1e-6,
			"%s.end_station" % label,
			"%.3f vs %.3f" % [float(last["s"]), expected_ends[i]]
		)
		_check(
			_finite_vec(first["pos"]) and _finite_vec(last["pos"]),
			"%s.finite_positions" % label,
			"%s..%s" % [str(first["pos"]), str(last["pos"])]
		)
		var monotonic := true
		for j in range(1, run.size()):
			if float(run[j]["s"]) <= float(run[j - 1]["s"]):
				monotonic = false
			break
		_check(monotonic, "%s.station_monotonic" % label, "stations must increase along a run")

		if i == 0:
			continue
		var previous: Array = runs[i - 1]
		if previous.is_empty():
			continue
		var boundary: Dictionary = previous[previous.size() - 1]
		if bool(first.get("joined_prev", false)):
			_check(
				(first["pos"] as Vector3).is_equal_approx(boundary["pos"]),
				"%s.joined_boundary_position" % label,
				"%s vs %s" % [str(first["pos"]), str(boundary["pos"])]
			)
			_check(
				absf(float(first["s"]) - float(boundary["s"])) <= 1e-6,
				"%s.joined_boundary_station" % label,
				"%.3f vs %.3f" % [float(first["s"]), float(boundary["s"])]
			)
		else:
			_check(
				(first["pos"] as Vector3).is_equal_approx(origin)
				and absf(float(first["s"])) <= 1e-6,
				"%s.break_start_geometry" % label,
				"%s at s=%.3f" % [str(first["pos"]), float(first["s"])]
			)


func _fingerprint(node: Node) -> Array:
	var out: Array = []
	for mesh_node in _meshes_with_meta(node, "surface_id"):
		var mi := mesh_node as MeshInstance3D
		var vertex_count := 0
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			vertex_count = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
		var box := mi.get_aabb()
		out.append([
			String(mi.name),
			vertex_count,
			box.size.x,
			box.size.y,
			box.size.z,
		])
	for pose_node in _nodes_with_meta(node, "pose_role"):
		out.append([
			String(pose_node.name),
			pose_node.transform.origin.x,
			pose_node.transform.origin.y,
			pose_node.transform.origin.z,
		])
	return out


func _finish() -> void:
	if _finished:
		return
	_finished = true
	var report := {
		"schema": "roadstorm.handling_lab.validation.v1",
		"lab_scene": LAB_SCENE_PATH,
		"backend": str(ProjectSettings.get_setting("physics/3d/physics_engine")),
		"engine_version": Engine.get_version_info(),
		"checks_total": _checks,
		"checks_failed": _failures.size(),
		"failures": _failures,
		"measured": _measured,
		"limitations": [
			"Headless dummy display/audio drivers; no rendering, input or audio claims.",
			"All geometry is preliminary M1.2 graybox authoring; no handling coefficients or measurements are validated here.",
			"The jump landing run is an authored preliminary value, not a validated landing envelope.",
			"Wall height is preliminary pending M2 barrier content.",
			"No car body, motor, surface modifiers, AI or gameplay are integrated; no M1.2 acceptance result is claimed.",
			"Esses and draft fixtures are outside this slice.",
			"Static concave trimesh road colliders match the visible ribbons in this revision; future car integration must add the thickened swept collision the technical design requires.",
			"Adjacent road sections are independent static trimesh bodies; their shared boundary edges coincide and a sub-millimetre crack exactly on a seam can return no ray hit, so boundary probes straddle each join by 5 mm.",
		],
	}
	print("LAB_RESULT ", JSON.stringify(report))
	print("CHECKS_TOTAL=", _checks, " CHECKS_FAILED=", _failures.size())
	quit(1 if _failures.size() > 0 else 0)
