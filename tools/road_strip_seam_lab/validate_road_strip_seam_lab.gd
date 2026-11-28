extends SceneTree
## Headless diagnostic for the M2.1 road-strip seam support gap.
##
## Builds the committed banked-bend source at 2 m spacing through
## RoadSourceDocument -> RoadArcSampler -> RoadTransportFrame -> RoadStripBaker,
## instantiates each chunk's real ConcavePolygonShape3D under separate
## Node3D containers, and calls the real GroundSupportProbe.probe() for
## exact interior frame-row poses. This is a diagnostic baseline only: a
## measured center-miss gap is reported, not treated as "seam safe".

const RoadSourceDocument := preload("res://src/course/road_source.gd")
const RoadArcSampler := preload("res://src/course/road_arc_sampler.gd")
const RoadTransportFrame := preload("res://src/course/road_transport_frame.gd")
const RoadStripBaker := preload("res://src/course/road_strip_baker.gd")
const GroundSupportProbe := preload("res://src/simulation/ground_support_probe.gd")

const FIXTURE_PATH := "res://tools/road_frame_lab/fixtures/road_frame_open_banked_bend.json"
const SPACING_M := 2.0
const K_VALUES := [1, 1024]
const LATERAL_FRACTIONS := [-0.4, -0.2, 0.0, 0.2, 0.4]
const FORWARD_OFFSETS := [0.0, 0.001]
const HEIGHT_ABOVE_M := 0.5
const SETTLE_FRAMES := 10
const DESTROY_FRAMES := 8

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
	var frame_table := _build_frame_table(probe)
	if frame_table == null:
		_finish(probe, [], 0, 0)
		return

	var frames: Array = frame_table.frames
	var segment_count := frames.size() - 1
	var interior_indices: Array[int] = []
	for i in range(1, frames.size() - 1):
		interior_indices.append(i)

	var config := GroundSupportProbe.Config.new()
	var box := BoxShape3D.new()
	box.size = config.hull_size_m

	var body := CharacterBody3D.new()
	body.name = "SeamProbeBody"
	body.collision_layer = 1
	body.collision_mask = 1
	var body_shape_node := CollisionShape3D.new()
	body_shape_node.shape = box
	body.add_child(body_shape_node)
	body.position = Vector3.ZERO
	root.add_child(body)

	probe.check(config.is_valid(), "default GroundSupportProbe.Config is valid")
	probe.check(
		box.size.distance_to(config.hull_size_m) <= 1e-6,
		"BoxShape3D matches the default config hull"
	)
	probe.check(
		ProjectSettings.get_setting("physics/3d/physics_engine") == "Jolt Physics",
		"physics backend is Jolt"
	)

	var metrics_list: Array = []
	for k in K_VALUES:
		probe.cases += 1
		var bake_result := RoadStripBaker.bake_open_strip(
			frame_table, {RoadStripBaker.OPTION_MAX_SEGMENTS_PER_CHUNK: k}
		)
		probe.check(bool(bake_result.get("ok", false)), "bake ok for k=%d" % k)
		if not bool(bake_result.get("ok", false)):
			metrics_list.append({"k": k, "error": str(bake_result.get("error", ""))})
			continue
		var chunks: Array = bake_result["chunks"]
		var expected_chunks := segment_count if k == 1 else 1
		probe.equal(chunks.size(), expected_chunks, "chunk count for k=%d" % k)

		var stage := _build_stage(k, chunks)
		await _await_frames(SETTLE_FRAMES)

		var metrics := _run_probes(
			probe, body, box, config, frames, interior_indices, chunks, k
		)
		metrics["k"] = k
		metrics["chunk_count"] = chunks.size()
		metrics_list.append(metrics)

		_destroy_stage(stage)
		await _await_frames(DESTROY_FRAMES)

	var total_poses := 0
	var total_rays := 0
	for m in metrics_list:
		if m.has("pose_count"):
			total_poses += int(m["pose_count"])
			total_rays += int(m["ray_count"])
	probe.check(total_poses <= 1000, "total poses <= 1000 (got %d)" % total_poses)
	probe.check(total_rays <= 5000, "total rays <= 5000 (got %d)" % total_rays)

	root.remove_child(body)
	body.free()

	_finish(probe, metrics_list, total_poses, total_rays)


func _build_frame_table(probe: Probe) -> RoadTransportFrame.FrameTable:
	var text := FileAccess.get_file_as_string(FIXTURE_PATH)
	if text.is_empty():
		probe.check(false, "banked-bend fixture is readable")
		return null
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		probe.check(false, "banked-bend fixture parses as JSON object")
		return null
	var doc_result := RoadSourceDocument.parse_document(parsed)
	if not bool(doc_result.get("ok", false)):
		probe.check(false, "RoadSourceDocument parses: " + str(doc_result.get("error", "")))
		return null
	var document = doc_result["document"]
	var arc_result := RoadArcSampler.build_uniform_table(document, SPACING_M)
	if not bool(arc_result.get("ok", false)):
		probe.check(false, "RoadArcSampler builds: " + str(arc_result.get("error", "")))
		return null
	var frame_result := RoadTransportFrame.build_open_frame_table(arc_result["table"])
	if not bool(frame_result.get("ok", false)):
		probe.check(false, "RoadTransportFrame builds: " + str(frame_result.get("error", "")))
		return null
	probe.check(true, "banked-bend pipeline builds at 2 m spacing")
	return frame_result["frame_table"]


func _build_stage(k: int, chunks: Array) -> Node3D:
	var stage := Node3D.new()
	stage.name = "SeamLabStageK%d" % k
	root.add_child(stage)
	for chunk_index in range(chunks.size()):
		var chunk: RoadStripBaker.Chunk = chunks[chunk_index]
		var body := StaticBody3D.new()
		body.name = "RoadStripChunk%d" % chunk_index
		body.collision_layer = 1
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		collision.shape = chunk.shape
		body.add_child(collision)
		stage.add_child(body)
	return stage


func _destroy_stage(stage: Node3D) -> void:
	if stage == null or not is_instance_valid(stage):
		return
	var parent := stage.get_parent()
	if parent != null:
		parent.remove_child(stage)
	stage.free()


func _await_frames(count: int) -> void:
	for _i in range(count):
		await physics_frame


func _run_probes(
	probe: Probe,
	body: CharacterBody3D,
	box: BoxShape3D,
	config: GroundSupportProbe.Config,
	frames: Array,
	interior_indices: Array[int],
	chunks: Array,
	k: int
) -> Dictionary:
	var center_miss_count := 0
	var ungrounded_count := 0
	var hist: Array[int] = [0, 0, 0, 0, 0, 0]
	var dist_min := 1e9
	var dist_max := -1e9
	var dist_sum := 0.0
	var height_min := 1e9
	var height_max := -1e9
	var normal_outlier_count := 0
	var distance_outlier_count := 0
	var outlier_poses: Array[int] = []
	var pose_count := 0
	var all_status_ok := true
	var all_five_queries := true

	for fi in interior_indices:
		var frame: Dictionary = frames[fi]
		var pos: Vector3 = frame["position"]
		var right: Vector3 = frame["right"]
		var forward: Vector3 = frame["forward"]
		var width: float = float(frame["width_m"])
		for f in LATERAL_FRACTIONS:
			for off in FORWARD_OFFSETS:
				var lateral_point := pos + right * (float(f) * width)
				var origin := lateral_point + Vector3(0.0, HEIGHT_ABOVE_M, 0.0) + forward * float(off)
				var transform := Transform3D(Basis.IDENTITY, origin)
				var result := GroundSupportProbe.probe(body, box, config, transform)
				pose_count += 1
				if result.status != GroundSupportProbe.Status.OK:
					all_status_ok = false
					probe.check(false, "probe rejected at k=%d pose %d" % [k, pose_count])
					continue
				if result.queries_used != 5:
					all_five_queries = false
				if not result.center_supported:
					center_miss_count += 1
				if not result.grounded:
					ungrounded_count += 1
				var sc := clampi(result.support_count, 0, 5)
				hist[sc] += 1
				if result.has_support:
					var d := float(result.support_distance_m)
					dist_min = minf(dist_min, d)
					dist_max = maxf(dist_max, d)
					dist_sum += d
					var h := float(result.support_height_m)
					height_min = minf(height_min, h)
					height_max = maxf(height_max, h)
					var is_outlier := false
					if d > 0.7:
						distance_outlier_count += 1
						is_outlier = true
					if result.support_normal.length() > 0.0:
						var up_dot := float(result.support_normal.dot(Vector3.UP))
						if up_dot < 0.9:
							normal_outlier_count += 1
							is_outlier = true
					if is_outlier and outlier_poses.size() < 32:
						outlier_poses.append(pose_count - 1)

	probe.check(all_status_ok, "all probe statuses OK for k=%d" % k)
	probe.check(all_five_queries, "all probes used 5 queries for k=%d" % k)

	var supported_poses := pose_count - hist[0]
	var dist_mean := 0.0
	if supported_poses > 0:
		dist_mean = dist_sum / float(supported_poses)
	if dist_min > 1e8:
		dist_min = 0.0
	if dist_max < -1e8:
		dist_max = 0.0
	if height_min > 1e8:
		height_min = 0.0
	if height_max < -1e8:
		height_max = 0.0

	var ray_count := pose_count * 5
	return {
		"pose_count": pose_count,
		"ray_count": ray_count,
		"center_miss_count": center_miss_count,
		"ungrounded_count": ungrounded_count,
		"support_count_histogram": {
			"0": hist[0],
			"1": hist[1],
			"2": hist[2],
			"3": hist[3],
			"4": hist[4],
			"5": hist[5],
		},
		"support_distance_m": {
			"min": dist_min,
			"max": dist_max,
			"mean": dist_mean,
		},
		"support_height_m": {
			"min": height_min,
			"max": height_max,
		},
		"outliers": {
			"distance_gt_0_7_count": distance_outlier_count,
			"normal_up_dot_lt_0_9_count": normal_outlier_count,
			"pose_indices": outlier_poses,
		},
	}


func _finish(
	probe: Probe,
	metrics_list: Array,
	total_poses: int,
	total_rays: int
) -> void:
	var summary := probe.summary()
	var pass_flag := bool(summary["pass"])
	var full := {
		"schema": "roadstorm.road_strip_seam_lab.summary.v1",
		"fixture": FIXTURE_PATH,
		"spacing_m": SPACING_M,
		"pass": pass_flag,
		"cases": summary["cases"],
		"checks": summary["checks"],
		"checks_total": summary["checks"],
		"checks_failed": summary["failed"],
		"failed": summary["failed"],
		"total_poses": total_poses,
		"total_rays": total_rays,
		"metrics": metrics_list,
	}
	print("ROAD_STRIP_SEAM_LAB_SUMMARY ", JSON.stringify(full))
	print(
		"CHECKS_TOTAL=", summary["checks"],
		" CHECKS_FAILED=", summary["failed"],
		" FAILED=", summary["failed"]
	)
	quit(0 if pass_flag else 1)
