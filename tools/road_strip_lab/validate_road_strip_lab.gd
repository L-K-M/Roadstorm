extends SceneTree
## Bounded headless validator for the provisional RoadStripBaker OPEN slice.
##
## Three canonical synthetic frames at stations 0/10/20 with forward -Z,
## right +X and up +Y produce two one-segment chunks. The validator checks the
## real ArrayMesh and ConcavePolygonShape3D resources, ordered metadata, UVs,
## bit-exact shared boundary row, the two structured refusals, and one-sided
## Jolt support for a downward ray from above. It is not M2.1 acceptance.

const RoadTransportFrame := preload("res://src/course/road_transport_frame.gd")
const RoadStripBaker := preload("res://src/course/road_strip_baker.gd")

const COURSE_ID := "road_strip_lab"
const REVISION := "r1"
const WIDTH_M := 4.0
const STATIONS := [0.0, 10.0, 20.0]
const ZS := [0.0, -10.0, -20.0]
const RAY_HEIGHT_M := 5.0
const HIT_TOLERANCE_M := 0.0001
const MESH_NORMAL_TOLERANCE := 0.001
const SUPPORT_NORMAL_MIN_Y := 0.999


class Probe extends RefCounted:
	var cases := 0
	var checks := 0
	var failures: Array[String] = []

	func check(condition: bool, message: String) -> bool:
		checks += 1
		if condition:
			return true
		failures.append(message)
		return false

	func equal(actual: Variant, expected: Variant, message: String) -> bool:
		return check(
			actual == expected,
			"%s (got %s expected %s)" % [message, str(actual), str(expected)]
		)

	func summary() -> Dictionary:
		return {
			"cases": cases,
			"checks": checks,
			"failed": failures.size(),
			"pass": failures.is_empty(),
		}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var probe := Probe.new()
	var table := _frame_table()
	var chunks := _check_bake(probe, table)
	_check_refusals(probe, table)
	if chunks.size() == 2:
		await _check_physics(probe, chunks)
	else:
		probe.check(false, "physics checks need exactly two baked chunks")

	for failure in probe.failures:
		print("ROAD_STRIP_LAB_FAIL ", failure)
	var summary := probe.summary()
	print("ROAD_STRIP_LAB_SUMMARY ", JSON.stringify(summary))
	print("CHECKS_TOTAL=", summary["checks"], " CHECKS_FAILED=", summary["failed"])
	quit(0 if bool(summary["pass"]) else 1)


func _frame_table() -> RoadTransportFrame.FrameTable:
	var frames: Array = []
	for index in range(STATIONS.size()):
		var section_id := "straight"
		var surface_id := "asphalt"
		if index == 1:
			section_id = "marker"
			surface_id = "gravel"
		frames.append({
			"index": index,
			"s": STATIONS[index],
			"position": Vector3(0.0, 0.0, ZS[index]),
			"forward": Vector3(0.0, 0.0, -1.0),
			"right": Vector3(1.0, 0.0, 0.0),
			"up": Vector3(0.0, 1.0, 0.0),
			"basis": Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK),
			"width_m": WIDTH_M,
			"bank_deg": 0.0,
			"grade_dy_ds": 0.0,
			"span_index": index,
			"span_t": 0.0,
			"section_id": section_id,
			"surface_id": surface_id,
			"sample_role": "interior",
		})
	return RoadTransportFrame.FrameTable.make(
		COURSE_ID, REVISION, 10.0, 20.0, {}, frames
	)


func _check_bake(probe: Probe, table: RoadTransportFrame.FrameTable) -> Array:
	probe.cases += 1
	var result := RoadStripBaker.bake_open_strip(
		table, {RoadStripBaker.OPTION_MAX_SEGMENTS_PER_CHUNK: 1}
	)
	if not probe.check(bool(result.get("ok", false)), "bake accepted the open table"):
		return []
	var chunks: Array = result["chunks"]
	var bake: RoadStripBaker.Bake = result["bake"]
	probe.equal(chunks.size(), 2, "chunk count")
	probe.equal(bake.shared_boundary_count, 1, "shared boundary count")
	probe.equal(bake.segment_count, 2, "bake segment count")

	for chunk_index in range(chunks.size()):
		var chunk: RoadStripBaker.Chunk = chunks[chunk_index]
		_check_chunk(probe, chunk, chunk_index)

	if chunks.size() == 2:
		var first: PackedVector3Array = (
			(chunks[0] as RoadStripBaker.Chunk).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		)
		var second: PackedVector3Array = (
			(chunks[1] as RoadStripBaker.Chunk).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		)
		probe.check(
			first[2] == second[0] and first[3] == second[1],
			"shared boundary row is bit-exact in both chunks"
		)
		var first_uv: PackedVector2Array = (
			(chunks[0] as RoadStripBaker.Chunk).mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		)
		var second_uv: PackedVector2Array = (
			(chunks[1] as RoadStripBaker.Chunk).mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		)
		probe.check(
			first_uv[2] == second_uv[0] and first_uv[3] == second_uv[1],
			"shared boundary UV row is bit-exact in both chunks"
		)
	return chunks


func _check_chunk(
	probe: Probe, chunk: RoadStripBaker.Chunk, chunk_index: int
) -> void:
	var label := "chunk %d" % chunk_index
	probe.check(chunk.mesh is ArrayMesh, label + " mesh is an ArrayMesh")
	probe.equal(chunk.vertex_count(), 4, label + " vertex_count")
	probe.equal(chunk.triangle_count(), 2, label + " triangle_count")
	probe.equal(chunk.segment_count, 1, label + " segment_count")
	probe.equal(chunk.first_frame_index, chunk_index, label + " first frame")
	probe.equal(chunk.last_frame_index, chunk_index + 1, label + " last frame")

	var arrays: Array = chunk.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	probe.equal(vertices.size(), chunk.vertex_count(), label + " ARRAY_VERTEX size")
	probe.equal(indices.size(), 6, label + " index count")
	probe.equal(indices.size() / 3, 2, label + " index triangle count")

	var stations := [STATIONS[chunk_index], STATIONS[chunk_index + 1]]
	for row in range(vertices.size() / 2):
		var station: float = stations[row]
		probe.check(
			vertices[row * 2].is_equal_approx(Vector3(-WIDTH_M * 0.5, 0.0, -station)),
			label + " row %d left vertex" % row
		)
		probe.check(
			vertices[row * 2 + 1].is_equal_approx(Vector3(WIDTH_M * 0.5, 0.0, -station)),
			label + " row %d right vertex" % row
		)
		probe.check(
			normals[row * 2].distance_to(Vector3.UP) <= MESH_NORMAL_TOLERANCE
			and normals[row * 2 + 1].distance_to(Vector3.UP) <= MESH_NORMAL_TOLERANCE,
			label + " row %d up normal" % row
		)
		probe.check(uvs[row * 2] == Vector2(0.0, station), label + " row %d left UV" % row)
		probe.check(uvs[row * 2 + 1] == Vector2(1.0, station), label + " row %d right UV" % row)

	var shape: ConcavePolygonShape3D = chunk.shape
	if indices.size() == 6:
		for offset in [0, 3]:
			var cross: Vector3 = (
				vertices[indices[offset + 1]] - vertices[indices[offset]]
			).cross(vertices[indices[offset + 2]] - vertices[indices[offset]])
			probe.check(
				cross.dot(Vector3.UP) < 0.0,
				label + " triangle %d has clockwise road-top front" % (offset / 3)
			)
	probe.check(shape is ConcavePolygonShape3D, label + " shape is concave")
	probe.check(not shape.backface_collision, label + " backface_collision is false")
	var faces: PackedVector3Array = shape.get_faces()
	probe.equal(faces.size(), 6, label + " concave face vertex count")
	for offset in range(mini(faces.size(), indices.size())):
		probe.check(
			faces[offset] == vertices[indices[offset]],
			label + " concave face %d matches mesh index" % offset
		)

	var segments: Array = chunk.segments()
	probe.equal(segments.size(), 1, label + " segment metadata count")
	if segments.size() == 1:
		var segment: Dictionary = segments[0]
		var expected_section := "straight" if chunk_index == 0 else "marker"
		var expected_surface := "asphalt" if chunk_index == 0 else "gravel"
		probe.equal(segment["segment_index"], chunk_index, label + " segment_index")
		probe.equal(segment["start_frame_index"], chunk_index, label + " start_frame_index")
		probe.equal(segment["chunk_segment_index"], 0, label + " chunk_segment_index")
		probe.equal(segment["s_start"], stations[0], label + " s_start")
		probe.equal(segment["s_end"], stations[1], label + " s_end")
		probe.equal(segment["section_id"], expected_section, label + " section_id")
		probe.equal(segment["surface_id"], expected_surface, label + " surface_id")
		probe.equal(segment["triangle_count"], 2, label + " metadata triangle_count")
		probe.equal(segment["index_base"], 0, label + " index_base")
		probe.equal(segment["row_vertex_base"], 0, label + " row_vertex_base")
		probe.check(
			String(segment["section_id"]) != "marker" or chunk_index == 1,
			label + " distinct frame1 section reaches the second chunk"
		)


func _check_refusals(probe: Probe, table: RoadTransportFrame.FrameTable) -> void:
	probe.cases += 1
	var null_result := RoadStripBaker.bake_open_strip(null)
	probe.check(
		not bool(null_result.get("ok", true)), "null table is refused"
	)
	probe.equal(null_result.get("code_name", ""), "bad_table", "null table code")
	probe.check(null_result.get("bake", false) == null, "null table returns no bake")
	probe.equal((null_result.get("chunks", [1]) as Array).size(), 0, "null table returns no chunks")

	var zero_option := RoadStripBaker.bake_open_strip(
		table, {RoadStripBaker.OPTION_MAX_SEGMENTS_PER_CHUNK: 0}
	)
	probe.check(
		not bool(zero_option.get("ok", true)), "zero chunk option is refused"
	)
	probe.equal(zero_option.get("code_name", ""), "bad_options", "zero option code")
	probe.check(zero_option.get("bake", false) == null, "zero option returns no bake")

	var typed_option := RoadStripBaker.bake_open_strip(
		table, {RoadStripBaker.OPTION_MAX_SEGMENTS_PER_CHUNK: 1.5}
	)
	probe.check(
		not bool(typed_option.get("ok", true)), "non-integer chunk option is refused"
	)
	probe.equal(typed_option.get("code_name", ""), "bad_options", "typed option code")


func _check_physics(probe: Probe, chunks: Array) -> void:
	probe.cases += 1
	probe.equal(
		ProjectSettings.get_setting("physics/3d/physics_engine"),
		"Jolt Physics",
		"physics backend is Jolt"
	)
	var stage := Node3D.new()
	stage.name = "RoadStripLabStage"
	root.add_child(stage)
	for chunk_index in range(chunks.size()):
		var chunk: RoadStripBaker.Chunk = chunks[chunk_index]
		var body := StaticBody3D.new()
		body.name = "RoadStripChunk%d" % chunk_index
		var collision := CollisionShape3D.new()
		collision.shape = chunk.shape
		body.add_child(collision)
		stage.add_child(body)

	await physics_frame
	await physics_frame

	for z in [-5.0, -15.0]:
		var space := stage.get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(0.0, RAY_HEIGHT_M, z),
			Vector3(0.0, -RAY_HEIGHT_M, z)
		)
		query.hit_back_faces = false
		var hit := space.intersect_ray(query)
		if not probe.check(not hit.is_empty(), "downward ray at z=%s hits" % str(z)):
			continue
		probe.check(
			absf(float(hit["position"].y)) <= HIT_TOLERANCE_M,
			"ray at z=%s lands on the strip top" % str(z)
		)
		probe.check(
			float(hit["normal"].y) >= SUPPORT_NORMAL_MIN_Y,
			"ray at z=%s is supported from above" % str(z)
		)
	for chunk in chunks:
		probe.check(
			not (chunk as RoadStripBaker.Chunk).shape.backface_collision,
			"instantiated shape keeps backface_collision false"
		)

	root.remove_child(stage)
	stage.free()
