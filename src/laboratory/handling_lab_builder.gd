class_name HandlingLabBuilder
extends RefCounted
## Deterministic builder for the M1.2 static graybox handling laboratory.
##
## The builder owns no randomness, clocks or engine queries. Given the authored
## bay table in HandlingLabData it always produces the same nodes, transforms,
## meshes and colliders. Visible ribbon geometry and its ConcavePolygonShape3D
## collider come from the same vertex/index arrays, so collision cannot drift
## from the visible surface within this revision.
##
## Scope limit: this is static geometry only. No car body, motor, surface
## modifier or acceptance measurement lives here.

const DataScript := preload("res://src/laboratory/handling_lab_data.gd")

const BAY_NODE_PREFIX := "Bay_"
const SPAWN_PREFIX := "Spawn_"
const RECOVERY_PREFIX := "Recovery_"
const RECOVERY_ANCHOR_NAME := "RecoveryZoneAnchor"
## Distance from a section join at which boundary-coverage probes are cast.
const JOIN_PROBE_OFFSET_M := 0.25
## Half-width of the sub-centimetre band straddling a section join. The exact
## seam is a zero-width crack between two independent trimesh bodies, so a
## ray precisely on it can fall through; these offsets sit safely on each side.
const JOIN_SEAM_PROBE_OFFSET_M := 0.005


static func build(root: Node3D) -> Dictionary:
	var materials := _make_materials()
	var bay_records: Array[Dictionary] = []
	var probes: Dictionary = {}

	for bay in DataScript.bays():
		var bay_id := String(bay["bay_id"])
		var bay_node := Node3D.new()
		bay_node.name = BAY_NODE_PREFIX + bay_id
		bay_node.set_meta("bay_id", bay_id)
		bay_node.set_meta("origin", bay["origin"])
		bay_node.set_meta("yaw_deg", bay["yaw_deg"])
		root.add_child(bay_node)

		var sections: Array[Dictionary] = []
		var features: Array[Dictionary] = []
		var samples: Array[Dictionary] = []
		var slab_spec: Dictionary = {}

		for seg in bay["segments"]:
			if String(seg["type"]) == "slab":
				slab_spec = seg

		var pose := _pose_for_bay(bay)

		if not slab_spec.is_empty():
			_add_slab(bay_node, bay, slab_spec, materials)
			sections.append({
				"section_id": slab_spec["section_id"],
				"bay_id": bay_id,
				"type": "slab",
				"surface_id": slab_spec["surface_id"],
				"role": "road",
				"start_s_m": 0.0,
				"end_s_m": float(slab_spec["length_m"]),
				"length_m": float(slab_spec["length_m"]),
				"width_m": float(slab_spec["width_m"]),
				"lateral_offset_m": 0.0,
				"grade_start_percent": 0.0,
				"grade_end_percent": 0.0,
				"banking_start_deg": 0.0,
				"banking_end_deg": 0.0,
				"feature": slab_spec.get("feature", ""),
				"provenance": slab_spec.get("provenance", "authored_preliminary"),
				"status": "preliminary_graybox",
			})
			features.append({
				"feature": "recovery_pad",
				"section_id": slab_spec["section_id"],
				"position": bay["origin"],
				"width_m": float(slab_spec["width_m"]),
				"length_m": float(slab_spec["length_m"]),
				"provenance": slab_spec.get("provenance", "authored_preliminary"),
				"preliminary": true,
			})
		else:
			var sampled := _sample_bay(bay)
			samples = sampled["samples"]
			sections = sampled["sections"]
			features = sampled["features"]
			var runs := _split_runs(samples)
			for run_index in range(runs.size()):
				var run: Array = runs[run_index]
				# End caps are real road ends (bay edges, jump lips, restarted
				# strips). At an ordinary join the next run repeats this run's
				# last cross-section, so a cap there would be a coincident
				# vertical obstacle across the seam; omit it on both sides.
				var cap_start := not bool(run[0].get("joined_prev", false))
				var cap_end := true
				if run_index + 1 < runs.size():
					cap_end = not bool(runs[run_index + 1][0].get("joined_prev", false))
				_add_surface_run(bay_node, bay, run, run_index, materials, cap_start, cap_end)

		for wall in bay.get("walls", []):
			_add_wall(bay_node, bay, wall, samples, materials)

		_add_pose_markers(bay_node, bay, pose)
		_collect_probes(bay, samples, slab_spec, sections, features, probes)

		bay_records.append({
			"bay_id": bay_id,
			"title": bay["title"],
			"origin": bay["origin"],
			"yaw_deg": bay["yaw_deg"],
			"fixture_refs": bay.get("fixture_refs", []),
			"sections": sections,
			"features": features,
			"walls": bay.get("walls", []),
			"spawn": pose["spawn"],
			"recovery": pose["recovery"],
		})

	_add_recovery_anchor(root, bay_records)

	var manifest := {
		"schema_version": DataScript.SCHEMA_VERSION,
		"lab_id": DataScript.LAB_ID,
		"coordinate_frame": DataScript.COORDINATE_FRAME,
		"units": DataScript.UNITS,
		"generated_by": "HandlingLabBuilder",
		"deterministic": true,
		"preliminary": true,
		"preliminary_notice": DataScript.PRELIMINARY_NOTICE,
		"fixture_unknown_notice": DataScript.FIXTURE_UNKNOWN_NOTICE,
		"sources": [
			"PLAN.md#m1-2",
			"docs/TECHNICAL_DESIGN.md",
			"docs/BENCHMARKS.md#handling-fixtures",
			"docs/GAME_DESIGN.md",
			"fixtures/handling/straight.json",
			"fixtures/handling/sweeper.json",
			"fixtures/handling/hairpin.json",
			"fixtures/handling/grounding.json",
			"fixtures/handling/gravel.json",
			"fixtures/handling/contact.json",
		],
		"sampling_step_m": DataScript.SAMPLE_STEP_M,
		"road_thickness_m": DataScript.ROAD_THICKNESS_M,
		"car_envelope_m": DataScript.CAR_ENVELOPE_M,
		"clearance_margin_m": DataScript.CLEARANCE_MARGIN_M,
		"required_road_width_m": DataScript.REQUIRED_ROAD_WIDTH_M,
		"surfaces": DataScript.surfaces(),
		"unknowns": DataScript.unknowns(),
		"bays": bay_records,
		"probe_points": probes,
	}
	return manifest


# --- Sampling -------------------------------------------------------------


static func _forward(heading_rad: float) -> Vector3:
	## Horizontal forward for a heading angle that grows toward local left.
	return Vector3(-sin(heading_rad), 0.0, -cos(heading_rad))


static func _make_sample(
	pos: Vector3,
	heading_rad: float,
	grade_percent: float,
	bank_deg: float,
	width_m: float,
	lateral_offset_m: float,
	surface_id: String,
	section_id: String,
	feature: String,
	s_m: float
) -> Dictionary:
	var tangent := _frame_tangent(heading_rad, grade_percent)
	var frame := _frame_from_tangent(tangent, bank_deg)
	return {
		"pos": pos,
		"heading_rad": heading_rad,
		"tangent": tangent,
		"right": frame["right"],
		"up": frame["up"],
		"width": width_m,
		"lateral_offset": lateral_offset_m,
		"surface_id": surface_id,
		"section_id": section_id,
		"feature": feature,
		"s": s_m,
		"bank_deg": bank_deg,
	}


static func _frame_tangent(heading_rad: float, grade_percent: float) -> Vector3:
	var horizontal := _forward(heading_rad)
	var slope := atan(grade_percent / 100.0)
	return (horizontal * cos(slope) + Vector3.UP * sin(slope)).normalized()


static func _frame_from_tangent(tangent: Vector3, bank_deg: float) -> Dictionary:
	var right := tangent.cross(Vector3.UP)
	if right.length_squared() < 1e-9:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(tangent).normalized()
	var angle := deg_to_rad(bank_deg)
	return {"right": right.rotated(tangent, angle), "up": up.rotated(tangent, angle)}
static func _pose_for_bay(bay: Dictionary) -> Dictionary:
	var yaw := float(bay["yaw_deg"])
	var origin: Vector3 = bay["origin"]
	var back := origin - _forward(deg_to_rad(yaw)) * 5.0
	return {
		"spawn": {"position": origin, "heading_deg": yaw, "role": "spawn"},
		"recovery": {"position": back, "heading_deg": yaw, "role": "recovery"},
	}


static func _sample_bay(bay: Dictionary) -> Dictionary:
	var origin: Vector3 = bay["origin"]
	var yaw_rad := deg_to_rad(float(bay["yaw_deg"]))
	var heading := yaw_rad
	var pos := origin
	var s := 0.0
	var samples: Array[Dictionary] = []
	var sections: Array[Dictionary] = []
	var features: Array[Dictionary] = []
	var segments: Array = bay["segments"]
	if segments.is_empty():
		return {"samples": samples, "sections": sections, "features": features}

	var pending_break := false

	for seg in segments:
		var restart := bool(seg.get("restart_at_origin", false))
		if restart:
			pos = origin
			heading = yaw_rad
			s = 0.0
			pending_break = true
		var type := String(seg["type"])
		var start_s := s
		if type != "gap":
			# Every non-gap section begins with its exact start cross-section.
			# At an ordinary join this repeats the previous section's end pose
			# under the new surface and section tags, so adjacent ribbons abut
			# with no uncovered interval. `joined_prev` marks that shared
			# boundary; `break_before` marks a run that starts away from the
			# previous run (after a jump gap or at a restarted strip).
			var start_sample := _make_sample(
				pos, heading,
				float(seg.get("grade_start_percent", 0.0)),
				float(seg.get("bank_start_deg", 0.0)),
				float(seg["width_m"]),
				float(seg.get("lateral_offset_m", 0.0)),
				String(seg["surface_id"]), String(seg["section_id"]),
				String(seg.get("feature", "")), s
			)
			start_sample["break_before"] = pending_break
			start_sample["joined_prev"] = not pending_break and not samples.is_empty()
			pending_break = false
			samples.append(start_sample)
		if type == "straight":
			var length := float(seg["length_m"])
			var n := maxi(1, int(ceil(length / DataScript.SAMPLE_STEP_M - 1e-9)))
			var ds := length / float(n)
			var g0 := float(seg.get("grade_start_percent", 0.0))
			var g1 := float(seg.get("grade_end_percent", 0.0))
			var b0 := float(seg.get("bank_start_deg", 0.0))
			var b1 := float(seg.get("bank_end_deg", 0.0))
			for i in range(1, n + 1):
				var u := float(i) / float(n)
				var grade: float = lerp(g0, g1, u)
				var bank: float = lerp(b0, b1, u)
				pos += _frame_tangent(heading, grade) * ds
				s += ds
				var smp := _make_sample(
					pos, heading, grade, bank,
					float(seg["width_m"]),
					float(seg.get("lateral_offset_m", 0.0)),
					String(seg["surface_id"]), String(seg["section_id"]),
					String(seg.get("feature", "")), s
				)
				samples.append(smp)
			sections.append(_section_record(seg, bay, start_s, s))
		elif type == "arc":
			var radius := float(seg["radius_m"])
			var angle := deg_to_rad(float(seg["angle_deg"]))
			var arc_len := radius * angle
			var n := maxi(2, int(ceil(arc_len / DataScript.SAMPLE_STEP_M - 1e-9)))
			var dtheta := angle / float(n)
			var sign := 1.0 if String(seg["direction"]) == "left" else -1.0
			var ds := arc_len / float(n)
			var b0 := float(seg.get("bank_start_deg", 0.0))
			var b1 := float(seg.get("bank_end_deg", 0.0))
			for i in range(1, n + 1):
				var u := float(i) / float(n)
				var bank: float = lerp(b0, b1, u)
				var mid := heading + sign * dtheta * 0.5
				pos += _forward(mid) * ds
				heading += sign * dtheta
				s += ds
				var smp := _make_sample(
					pos, heading, 0.0, bank,
					float(seg["width_m"]),
					float(seg.get("lateral_offset_m", 0.0)),
					String(seg["surface_id"]), String(seg["section_id"]),
					String(seg.get("feature", "")), s
				)
				samples.append(smp)
			sections.append(_section_record(seg, bay, start_s, s))
		elif type == "gap":
			var gap_start := pos
			pos += _forward(heading) * float(seg["gap_m"])
			pos.y -= float(seg["drop_m"])
			s += float(seg["gap_m"])
			features.append({
				"feature": "jump_gap",
				"section_id": String(seg["section_id"]),
				"start": gap_start,
				"end": pos,
				"gap_m": float(seg["gap_m"]),
				"drop_m": float(seg["drop_m"]),
				"landing_run_m": float(seg["landing_run_m"]),
				"provenance": String(seg.get("provenance", "authored_preliminary")),
				"preliminary": true,
			})
			sections.append(_section_record(seg, bay, start_s, s))
			pending_break = true

	return {"samples": samples, "sections": sections, "features": features}
static func _section_record(seg: Dictionary, bay: Dictionary, start_s: float, end_s: float) -> Dictionary:
	var type := String(seg["type"])
	var length := 0.0
	if type == "arc":
		length = float(seg["radius_m"]) * deg_to_rad(float(seg["angle_deg"]))
	elif type == "gap":
		length = float(seg["gap_m"])
	else:
		length = float(seg.get("length_m", 0.0))
	var rec := {
		"section_id": String(seg["section_id"]),
		"bay_id": String(bay["bay_id"]),
		"type": type,
		"surface_id": String(seg.get("surface_id", "")),
		"role": String(seg.get("role", "road")),
		"start_s_m": start_s,
		"end_s_m": end_s,
		"length_m": length,
		"width_m": float(seg.get("width_m", 0.0)),
		"lateral_offset_m": float(seg.get("lateral_offset_m", 0.0)),
		"grade_start_percent": float(seg.get("grade_start_percent", 0.0)),
		"grade_end_percent": float(seg.get("grade_end_percent", 0.0)),
		"banking_start_deg": float(seg.get("bank_start_deg", 0.0)),
		"banking_end_deg": float(seg.get("bank_end_deg", 0.0)),
		"feature": String(seg.get("feature", "")),
		"provenance": String(seg.get("provenance", "authored_preliminary")),
		"status": "preliminary_graybox",
	}
	if type == "arc":
		rec["radius_m"] = float(seg["radius_m"])
		rec["angle_deg"] = float(seg["angle_deg"])
		rec["direction"] = String(seg["direction"])
	if type == "gap":
		rec["gap_m"] = float(seg["gap_m"])
		rec["drop_m"] = float(seg["drop_m"])
		rec["landing_run_m"] = float(seg["landing_run_m"])
	return rec


static func _split_runs(samples: Array[Dictionary]) -> Array:
	var runs: Array = []
	var current: Array[Dictionary] = []
	var last_key := ""
	for smp in samples:
		var key := "%s|%s" % [String(smp["surface_id"]), String(smp["section_id"])]
		var brk := bool(smp.get("break_before", false))
		if brk or (not current.is_empty() and key != last_key):
			runs.append(current)
			current = []
		current.append(smp)
		last_key = key
	if not current.is_empty():
		runs.append(current)
	return runs


# --- Geometry -------------------------------------------------------------


static func _add_surface_run(
	parent: Node3D,
	bay: Dictionary,
	run: Array,
	run_index: int,
	materials: Dictionary,
	cap_start: bool,
	cap_end: bool
) -> void:
	if run.size() < 2:
		return
	var smp0: Dictionary = run[0]
	var surface_id := String(smp0["surface_id"])
	var section_id := String(smp0["section_id"])
	var bay_id := String(bay["bay_id"])
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var down := Vector3(0.0, DataScript.ROAD_THICKNESS_M, 0.0)

	for smp in run:
		var right: Vector3 = smp["right"]
		var up: Vector3 = smp["up"]
		var center: Vector3 = smp["pos"] + right * float(smp["lateral_offset"])
		var half := float(smp["width"]) * 0.5
		var tl := center - right * half
		var tr := center + right * half
		verts.append(tl)
		verts.append(tr)
		verts.append(tl - down)
		verts.append(tr - down)
		normals.append(up)
		normals.append(up)
		normals.append(-up)
		normals.append(-up)
		var u := float(smp["s"]) * 0.1
		uvs.append(Vector2(u, 0.0))
		uvs.append(Vector2(u, 1.0))
		uvs.append(Vector2(u, 0.0))
		uvs.append(Vector2(u, 1.0))

	for i in range(run.size() - 1):
		var b := i * 4
		var nxt := b + 4
		_append_tris(indices, [b, nxt, b + 1, b + 1, nxt, nxt + 1])
		_append_tris(indices, [b + 2, b + 3, nxt + 3, b + 2, nxt + 3, nxt + 2])
		_append_tris(indices, [b, b + 2, nxt + 2, b, nxt + 2, nxt])
		_append_tris(indices, [b + 1, nxt + 1, nxt + 3, b + 1, nxt + 3, b + 3])
	var first := 0
	var last := (run.size() - 1) * 4
	if cap_start:
		_append_tris(indices, [first, first + 1, first + 3, first, first + 3, first + 2])
	if cap_end:
		_append_tris(indices, [last, last + 2, last + 3, last, last + 3, last + 1])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mi := MeshInstance3D.new()
	mi.name = "Surface_%s_%d" % [bay_id, run_index]
	mi.mesh = mesh
	mi.material_override = materials[surface_id]
	_set_common_meta(mi, surface_id, section_id, bay_id)
	parent.add_child(mi)

	var body := StaticBody3D.new()
	body.name = "Collision_%s_%d" % [bay_id, run_index]
	var shape_node := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(_triangle_soup(verts, indices))
	shape.backface_collision = false
	shape_node.shape = shape
	body.add_child(shape_node)
	_set_common_meta(body, surface_id, section_id, bay_id)
	body.set_meta("collision_role", "terrain")
	body.set_meta("shape_kind", "concave_polygon")
	body.set_meta("faces", indices.size() / 3)
	parent.add_child(body)
static func _add_wall(
	parent: Node3D,
	bay: Dictionary,
	wall: Dictionary,
	samples: Array[Dictionary],
	materials: Dictionary
) -> void:
	var base := _nearest_sample(samples, float(wall["s_m"]))
	var right: Vector3 = base["right"]
	var up: Vector3 = base["up"]
	var ground_pos: Vector3 = base["pos"] + right * float(wall["lateral_offset_m"])
	var size := Vector3(
		float(wall["length_m"]),
		float(wall["height_m"]),
		float(wall["thickness_m"])
	)
	var basis := Basis(Quaternion(up, deg_to_rad(float(wall["angle_deg"]))))
	var center := ground_pos + up * (float(wall["height_m"]) * 0.5)

	var body := StaticBody3D.new()
	body.name = String(wall["wall_id"])
	body.transform = Transform3D(basis, center)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = materials[String(wall["surface_id"])]
	body.add_child(mi)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	_set_common_meta(body, String(wall["surface_id"]), String(wall["wall_id"]), String(bay["bay_id"]))
	_set_common_meta(mi, String(wall["surface_id"]), String(wall["wall_id"]), String(bay["bay_id"]))
	body.set_meta("collision_role", "wall")
	body.set_meta("shape_kind", "box")
	body.set_meta("wall_id", String(wall["wall_id"]))
	body.set_meta("length_m", float(wall["length_m"]))
	body.set_meta("thickness_m", float(wall["thickness_m"]))
	body.set_meta("height_m", float(wall["height_m"]))
	body.set_meta("angle_deg", float(wall["angle_deg"]))
	body.set_meta("s_m", float(wall["s_m"]))
	body.set_meta("lateral_offset_m", float(wall["lateral_offset_m"]))
	parent.add_child(body)


static func _add_slab(
	parent: Node3D,
	bay: Dictionary,
	spec: Dictionary,
	materials: Dictionary
) -> void:
	var surface_id := String(spec["surface_id"])
	var section_id := String(spec["section_id"])
	var bay_id := String(bay["bay_id"])
	var size := Vector3(
		float(spec["width_m"]),
		DataScript.ROAD_THICKNESS_M,
		float(spec["length_m"])
	)
	var origin: Vector3 = bay["origin"]
	var center := origin - Vector3.UP * (DataScript.ROAD_THICKNESS_M * 0.5)
	var body := StaticBody3D.new()
	body.name = "Collision_" + section_id
	body.transform = Transform3D(Basis(), center)
	var mi := MeshInstance3D.new()
	mi.name = "Surface_" + section_id
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = materials[surface_id]
	body.add_child(mi)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	_set_common_meta(body, surface_id, section_id, bay_id)
	_set_common_meta(mi, surface_id, section_id, bay_id)
	body.set_meta("collision_role", "terrain")
	body.set_meta("shape_kind", "box")
	body.set_meta("width_m", float(spec["width_m"]))
	body.set_meta("length_m", float(spec["length_m"]))
	parent.add_child(body)


static func _add_pose_markers(parent: Node3D, bay: Dictionary, pose: Dictionary) -> void:
	var bay_id := String(bay["bay_id"])
	var yaw := deg_to_rad(float(bay["yaw_deg"]))
	var spawn: Dictionary = pose["spawn"]
	var recovery: Dictionary = pose["recovery"]
	var spawn_node := Marker3D.new()
	spawn_node.name = SPAWN_PREFIX + bay_id
	spawn_node.transform = Transform3D(Basis(Quaternion(Vector3.UP, yaw)), spawn["position"])
	spawn_node.set_meta("pose_role", "spawn")
	spawn_node.set_meta("bay_id", bay_id)
	spawn_node.set_meta("heading_deg", float(spawn["heading_deg"]))
	spawn_node.set_meta("preliminary", true)
	parent.add_child(spawn_node)
	var recovery_node := Marker3D.new()
	recovery_node.name = RECOVERY_PREFIX + bay_id
	recovery_node.transform = Transform3D(Basis(Quaternion(Vector3.UP, yaw)), recovery["position"])
	recovery_node.set_meta("pose_role", "recovery")
	recovery_node.set_meta("bay_id", bay_id)
	recovery_node.set_meta("heading_deg", float(recovery["heading_deg"]))
	recovery_node.set_meta("preliminary", true)
	parent.add_child(recovery_node)


static func _add_recovery_anchor(root: Node3D, bay_records: Array[Dictionary]) -> void:
	for rec in bay_records:
		if String(rec["bay_id"]) != "recovery":
			continue
		var node := Marker3D.new()
		node.name = RECOVERY_ANCHOR_NAME
		node.transform = Transform3D(Basis(), rec["origin"])
		node.set_meta("pose_role", "recovery_zone_anchor")
		node.set_meta("bay_id", "recovery")
		node.set_meta("surface_id", "recovery")
		node.set_meta("recovery_zone", true)
		node.set_meta("car_envelope_m", DataScript.CAR_ENVELOPE_M)
		node.set_meta("clearance_margin_m", DataScript.CLEARANCE_MARGIN_M)
		root.add_child(node)
static func _collect_probes(
	bay: Dictionary,
	samples: Array[Dictionary],
	slab_spec: Dictionary,
	sections: Array[Dictionary],
	features: Array[Dictionary],
	probes: Dictionary
) -> void:
	var bay_id := String(bay["bay_id"])
	var bay_origin: Vector3 = bay["origin"]
	match bay_id:
		"straight":
			var asphalt := _nearest_sample(samples, 10.0)
			if not asphalt.is_empty():
				probes["floor_asphalt"] = _floor_probe(asphalt, "asphalt")
		"gravel":
			var sector := _middle_section_sample(samples, "gravel.sector")
			if not sector.is_empty():
				probes["floor_gravel"] = _floor_probe(sector, "gravel")
		"shoulder":
			var shoulder := _middle_section_sample(samples, "shoulder.right")
			if not shoulder.is_empty():
				probes["floor_shoulder"] = _floor_probe(shoulder, "shoulder")
		"jump":
			var landing := _middle_section_sample(samples, "jump.landing")
			if not landing.is_empty():
				probes["floor_jump_landing"] = _floor_probe(landing, "asphalt")
		"contact":
			var before := _nearest_sample(samples, 470.0)
			var after := _nearest_sample(samples, 490.0)
			var wall_mid := _nearest_sample(samples, 480.0)
			if not before.is_empty() and not after.is_empty() and not wall_mid.is_empty():
				probes["wall_frontal"] = {
					"from": before["pos"] + Vector3.UP,
					"to": after["pos"] + Vector3.UP,
					"expected_collision_role": "wall",
					"expected_position": wall_mid["pos"] + Vector3.UP,
				}
		"recovery":
			var pad_center := bay_origin
			probes["recovery_pad"] = {
				"from": pad_center + Vector3.UP * 3.0,
				"to": pad_center - Vector3.UP * 10.0,
				"expected_surface": "recovery",
				"expected_position": pad_center,
			}

	_collect_join_probes(bay_id, samples, sections, probes)
	_collect_restart_probes(bay, probes)
	_collect_jump_gap_probe(bay_id, sections, features, probes)


static func _collect_join_probes(
	bay_id: String,
	samples: Array[Dictionary],
	sections: Array[Dictionary],
	probes: Dictionary
) -> void:
	if not probes.has("join_probes"):
		probes["join_probes"] = []
	var joins: Array = probes["join_probes"]
	var prev: Dictionary = {}
	for section in sections:
		if String(section.get("type", "")) == "gap":
			prev = {}
			continue
		if not prev.is_empty():
			var station := float(prev["end_s_m"])
			if absf(station - float(section["start_s_m"])) <= 1e-6:
				var before_surface := String(prev.get("surface_id", ""))
				var after_surface := String(section.get("surface_id", ""))
				joins.append({
					"bay_id": bay_id,
					"station_s_m": station,
					"before_surface_id": before_surface,
					"after_surface_id": after_surface,
					"before": _station_probe(samples, station - JOIN_PROBE_OFFSET_M, before_surface),
					"seam_before": _station_probe(
						samples, station - JOIN_SEAM_PROBE_OFFSET_M, before_surface
					),
					"seam_after": _station_probe(
						samples, station + JOIN_SEAM_PROBE_OFFSET_M, after_surface
					),
					"after": _station_probe(samples, station + JOIN_PROBE_OFFSET_M, after_surface),
				})
		prev = section


static func _collect_restart_probes(bay: Dictionary, probes: Dictionary) -> void:
	if not probes.has("restart_probes"):
		probes["restart_probes"] = []
	var out: Array = probes["restart_probes"]
	var yaw_rad := deg_to_rad(float(bay["yaw_deg"]))
	var forward := _forward(yaw_rad)
	var right := forward.cross(Vector3.UP)
	if right.length_squared() < 1e-9:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	var origin: Vector3 = bay["origin"]
	for seg in bay["segments"]:
		if not bool(seg.get("restart_at_origin", false)):
			continue
		var surface_id := String(seg["surface_id"])
		var center := origin + right * float(seg.get("lateral_offset_m", 0.0))
		var length := float(seg.get("length_m", 0.0))
		out.append({
			"bay_id": String(bay["bay_id"]),
			"section_id": String(seg["section_id"]),
			"surface_id": surface_id,
			"start": _point_probe(center + forward * JOIN_PROBE_OFFSET_M, surface_id),
			"end": _point_probe(center + forward * (length - JOIN_PROBE_OFFSET_M), surface_id),
		})


static func _collect_jump_gap_probe(
	bay_id: String,
	sections: Array[Dictionary],
	features: Array[Dictionary],
	probes: Dictionary
) -> void:
	var gap_feature: Dictionary = {}
	for feature in features:
		if String(feature.get("feature", "")) == "jump_gap":
			gap_feature = feature
			break
	if gap_feature.is_empty():
		return
	var neighbors := _gap_neighbors(sections)
	var gap_start: Vector3 = gap_feature["start"]
	var gap_end: Vector3 = gap_feature["end"]
	var flat := Vector3(gap_end.x - gap_start.x, 0.0, gap_end.z - gap_start.z)
	if flat.length_squared() <= 1e-9:
		return
	var dir := flat.normalized()
	var mid := gap_start.lerp(gap_end, 0.5)
	var takeoff_surface := String(neighbors["before"])
	var landing_surface := String(neighbors["after"])
	probes["jump_gap"] = {
		"bay_id": bay_id,
		"start": gap_start,
		"end": gap_end,
		"gap_m": float(gap_feature["gap_m"]),
		"drop_m": float(gap_feature["drop_m"]),
		"takeoff_surface_id": takeoff_surface,
		"landing_surface_id": landing_surface,
		"takeoff_before": _point_probe(gap_start - dir * JOIN_PROBE_OFFSET_M, takeoff_surface),
		"takeoff_edge": _point_probe(gap_start, takeoff_surface),
		"mid_gap": _point_probe(mid, "", false),
		"landing_edge": _point_probe(gap_end, landing_surface),
		"landing_after": _point_probe(gap_end + dir * JOIN_PROBE_OFFSET_M, landing_surface),
	}


static func _gap_neighbors(sections: Array[Dictionary]) -> Dictionary:
	for i in range(sections.size()):
		if String(sections[i].get("type", "")) != "gap":
			continue
		var before := ""
		var after := ""
		if i > 0:
			before = String(sections[i - 1].get("surface_id", ""))
		if i + 1 < sections.size():
			after = String(sections[i + 1].get("surface_id", ""))
		return {"before": before, "after": after}
	return {"before": "", "after": ""}


static func _station_probe(
	samples: Array[Dictionary],
	station_s: float,
	expected_surface: String
) -> Dictionary:
	var point := _position_at_station(samples, station_s)
	return {
		"from": point + Vector3.UP * 3.0,
		"to": point - Vector3.UP * 10.0,
		"expected_position": point,
		"expected_surface": expected_surface,
	}


static func _point_probe(point: Vector3, expected_surface: String, expect_hit: bool = true) -> Dictionary:
	var probe := {
		"from": point + Vector3.UP * 3.0,
		"to": point - Vector3.UP * 10.0,
		"expected_position": point,
		"expected_hit": expect_hit,
	}
	if expect_hit:
		probe["expected_surface"] = expected_surface
	return probe


static func _position_at_station(samples: Array[Dictionary], station_s: float) -> Vector3:
	for i in range(samples.size() - 1):
		var a: Dictionary = samples[i]
		var b: Dictionary = samples[i + 1]
		var sa := float(a["s"])
		var sb := float(b["s"])
		if station_s < sa or station_s > sb:
			continue
		var span := sb - sa
		var u := 0.0 if span <= 1e-9 else (station_s - sa) / span
		return (a["pos"] as Vector3).lerp(b["pos"], u)
	var nearest := _nearest_sample(samples, station_s)
	if nearest.is_empty():
		return Vector3.ZERO
	return nearest["pos"] as Vector3

static func _floor_probe(smp: Dictionary, expected_surface: String) -> Dictionary:
	var p: Vector3 = smp["pos"] + smp["right"] * float(smp["lateral_offset"])
	return {
		"from": p + Vector3.UP * 3.0,
		"to": p - Vector3.UP * 10.0,
		"expected_surface": expected_surface,
		"expected_position": p,
	}


static func _nearest_sample(samples: Array[Dictionary], target_s: float) -> Dictionary:
	var best: Dictionary = {}
	var best_error := INF
	for smp in samples:
		var err := absf(float(smp["s"]) - target_s)
		if err < best_error:
			best_error = err
			best = smp
	return best


static func _middle_section_sample(samples: Array[Dictionary], section_id: String) -> Dictionary:
	var matches: Array[Dictionary] = []
	for smp in samples:
		if String(smp["section_id"]) == section_id:
			matches.append(smp)
	if matches.is_empty():
		return {}
	return matches[matches.size() / 2]


static func _make_materials() -> Dictionary:
	var out: Dictionary = {}
	for surface in DataScript.surfaces():
		var mat := StandardMaterial3D.new()
		mat.albedo_color = surface["color"]
		mat.roughness = float(surface["roughness"])
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		out[String(surface["surface_id"])] = mat
	return out


static func _set_common_meta(node: Node, surface_id: String, section_id: String, bay_id: String) -> void:
	node.set_meta("surface_id", surface_id)
	node.set_meta("section_id", section_id)
	node.set_meta("bay_id", bay_id)
	node.set_meta("status", "preliminary_graybox")


static func _append_tris(indices: PackedInt32Array, values: Array) -> void:
	for value in values:
		indices.append(int(value))


static func _triangle_soup(verts: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for i in range(0, indices.size(), 3):
		faces.append(verts[indices[i]])
		faces.append(verts[indices[i + 1]])
		faces.append(verts[indices[i + 2]])
	return faces
