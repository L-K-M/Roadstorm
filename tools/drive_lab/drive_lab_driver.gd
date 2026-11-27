extends Node
## Headless M1 one-car drive-lab validator.
##
## Instantiates the real `scenes/laboratory/drive_lab.tscn` against the
## committed handling lab's asphalt straight, drives bounded scripted runs at
## a fixed 60 Hz, and prints one machine-readable `DRIVE_LAB_RESULT <json>` per
## case plus a final `DRIVE_LAB_SUMMARY <json>`.
##
## Scope: one car, one flat straight, adapter integration only. It proves the
## laboratory seam, not adhesion, jumps, drift, car-car contact, reset,
## surfaces or M1 acceptance.

const DriveLabScript := preload("res://src/laboratory/drive_lab.gd")
const ChecksScript := preload("res://tools/drive_lab/drive_lab_checks.gd")
const AdapterScript := preload("res://src/simulation/motor_body_adapter.gd")
const CameraRigScript := preload("res://src/presentation/camera_rig.gd")

const DRIVE_LAB_SCENE_PATH := "res://scenes/laboratory/drive_lab.tscn"
const SETTLE_FRAMES := 10
const CLEANUP_FRAMES := 8
const PREDICTION_TOLERANCE_M := 1e-4
const COMMITTED_MATCH_TOLERANCE_M := 5e-5
const PENETRATION_TOLERANCE_M := 0.03
const RAY_TOLERANCE_M := 0.35
const ROAD_HALF_WIDTH_M := 6.0
const LOG_BOUND := 1800

const CASE_IDS: Array[String] = [
	"scene_and_manifest",
	"movement_from_rest",
	"braking",
	"displacement_accounting",
	"repeatability",
	"finite_state",
	"hull_road_overlap",
	"one_call_per_tick",
	"refusal_halts",
]

var d := DriveLabChecks.new()
var measurements: Dictionary = {}
var _results: Array[Dictionary] = []
var _holder: Node3D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_holder = Node3D.new()
	_holder.name = "DriveLabHolder"
	add_child(_holder)
	_run()


func _run() -> void:
	for case_id in CASE_IDS:
		_results.append(await _run_case(case_id))
	var total_checks := 0
	var total_failures := 0
	var failed_cases := 0
	for result in _results:
		total_checks += int(result["checks"])
		total_failures += int(result["checks_failed"])
		if not bool(result["pass"]):
			failed_cases += 1
	var summary := {
		"schema": "roadstorm.drive_lab.summary.v1",
		"backend": str(ProjectSettings.get_setting("physics/3d/physics_engine")),
		"engine_version": Engine.get_version_info(),
		"cases": _results.size(),
		"checks": total_checks,
		"checks_failed": total_failures,
		"failed_cases": failed_cases,
		"pass": failed_cases == 0,
	}
	print("DRIVE_LAB_SUMMARY ", JSON.stringify(summary))
	print("CHECKS_TOTAL=", total_checks, " CHECKS_FAILED=", total_failures)
	get_tree().quit(0 if failed_cases == 0 else 1)


func _run_case(case_id: String) -> Dictionary:
	d = DriveLabChecks.new()
	measurements = {}
	match case_id:
		"scene_and_manifest":
			await _case_scene_and_manifest()
		"movement_from_rest":
			await _case_movement_from_rest()
		"braking":
			await _case_braking()
		"displacement_accounting":
			await _case_displacement_accounting()
		"repeatability":
			await _case_repeatability()
		"finite_state":
			await _case_finite_state()
		"hull_road_overlap":
			await _case_hull_road_overlap()
		"one_call_per_tick":
			await _case_one_call_per_tick()
		"refusal_halts":
			await _case_refusal_halts()
		_:
			d.check(false, "unknown case %s" % case_id)
	var result := {
		"case": case_id,
		"pass": d.failures.is_empty(),
		"checks": d.checks,
		"checks_failed": d.failures.size(),
		"failures": d.failures.duplicate(),
		"measurements": measurements.duplicate(),
	}
	print("DRIVE_LAB_RESULT ", JSON.stringify(result))
	return result


# --- Shared helpers --------------------------------------------------------


func _make_lab(commands: Array, config = null, tuning = null):
	var packed: PackedScene = load(DRIVE_LAB_SCENE_PATH)
	if packed == null:
		d.check(false, "scene.load: could not load %s" % DRIVE_LAB_SCENE_PATH)
		return null
	var lab = packed.instantiate()
	if lab == null:
		d.check(false, "scene.instantiate: could not instantiate %s" % DRIVE_LAB_SCENE_PATH)
		return null
	var cfg = config if config != null else d.make_config()
	var tun = tuning if tuning != null else d.make_tuning()
	var configured: bool = lab.configure(tun, cfg, commands)
	d.check(configured, "lab.configure accepted the explicit fixtures")
	_holder.add_child(lab)
	return lab


func _settle() -> void:
	for _index in range(SETTLE_FRAMES):
		await get_tree().physics_frame


func _cleanup() -> void:
	for _index in range(CLEANUP_FRAMES):
		await get_tree().physics_frame


func _teardown_lab(lab) -> void:
	if lab != null and is_instance_valid(lab):
		lab.queue_free()
	await _cleanup()


## Run one auto tick per physics callback until `count` ticks commit. Bounded
## by a guard so a refusal or early halt fails instead of hanging.
func _run_auto(lab, count: int) -> Dictionary:
	var start_steps := int(lab.steps_called)
	var start_committed := int(lab.ticks_committed)
	var start_frames := Engine.get_physics_frames()
	lab.start()
	var guard := 0
	var limit := count * 4 + 120
	while int(lab.ticks_committed) - start_committed < count and guard < limit:
		await get_tree().physics_frame
		guard += 1
	var frames := Engine.get_physics_frames() - start_frames
	return {
		"guard": guard,
		"frames": frames,
		"steps": int(lab.steps_called) - start_steps,
		"committed": int(lab.ticks_committed) - start_committed,
	}


func _ray_hit(from: Vector3, to: Vector3, exclude: Array = []) -> Dictionary:
	var space := get_tree().root.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.hit_back_faces = false
	query.exclude = exclude
	return space.intersect_ray(query)


func _hit_surface(hit: Dictionary) -> String:
	var collider = hit.get("collider")
	if collider != null and collider.has_meta("surface_id"):
		return String(collider.get_meta("surface_id"))
	return ""


func _find_bay(manifest: Dictionary, bay_id: String) -> Dictionary:
	for bay in manifest.get("bays", []):
		if String(bay.get("bay_id", "")) == bay_id:
			return bay
	return {}


func _find_section(bay: Dictionary, section_id: String) -> Dictionary:
	for section in bay.get("sections", []):
		if String(section.get("section_id", "")) == section_id:
			return section
	return {}


func _max_prediction_discrepancy(lab) -> float:
	var worst := 0.0
	for record in lab.tick_log:
		worst = maxf(worst, float(record["prediction_commit_discrepancy_m"]))
	return worst


func _max_motion_gap(lab) -> float:
	var worst := 0.0
	for record in lab.tick_log:
		worst = maxf(
			worst,
			(record["accepted_motion_m"] as Vector3).distance_to(
				record["proposed_motion_m"] as Vector3
			)
		)
	return worst


func _all_logged_numbers_finite(lab) -> bool:
	for record in lab.tick_log:
		var position: Vector2 = record["position_m"]
		var velocity: Vector2 = record["velocity_m_s"]
		var scalars := [
			position.x, position.y, velocity.x, velocity.y,
			record["heading_rad"], record["prediction_commit_discrepancy_m"],
			record["remainder_m"],
		]
		for value in scalars:
			if is_nan(value) or is_inf(value):
				return false
		var transform: Transform3D = record["body_transform"]
		if not (
			is_finite(transform.origin.x) and is_finite(transform.origin.y)
			and is_finite(transform.origin.z)
		):
			return false
	return true


func _telemetry_numbers_finite(lab) -> bool:
	for key in lab.get_telemetry():
		var value = lab.get_telemetry()[key]
		if typeof(value) == TYPE_FLOAT and (is_nan(value) or is_inf(value)):
			return false
	return true


# --- Cases -----------------------------------------------------------------


func _case_scene_and_manifest() -> void:
	var lab = _make_lab([])
	if lab == null:
		return
	await _settle()
	d.check(not lab.failed, "scene.not_failed: " + str(lab.failure_reason))
	var manifest: Dictionary = lab.lab_manifest
	d.check(not manifest.is_empty(), "manifest.present")
	d.check(
		String(manifest.get("schema_version", "")) == "roadstorm.handling_lab.v1",
		"manifest.schema_version"
	)
	d.check(
		String(manifest.get("lab_id", "")) == "roadstorm.laboratory.handling_lab",
		"manifest.lab_id"
	)
	var straight := _find_bay(manifest, "straight")
	d.check(not straight.is_empty(), "manifest.straight_bay")
	var section := _find_section(straight, "straight.main")
	d.check(not section.is_empty(), "manifest.straight_section")
	if not section.is_empty():
		d.check_close(float(section["length_m"]), 500.0, 1e-6, "manifest.straight_length")
		d.check(String(section["surface_id"]) == "asphalt", "manifest.straight_surface")
		d.check(
			float(section["width_m"]) >= ROAD_HALF_WIDTH_M * 2.0 - 1e-6,
			"manifest.straight_width"
		)

	d.check(lab.body is CharacterBody3D, "car.body_is_character_body")
	d.check(lab.hull_shape is BoxShape3D, "car.hull_is_box_shape")
	if lab.hull_shape is BoxShape3D:
		d.check(
			lab.hull_shape.size.distance_to(lab.adapter_config.hull_size_m) <= 0.0,
			"car.hull_matches_config_exactly"
		)
	d.check(lab.graybox_mesh is MeshInstance3D, "car.graybox_is_mesh_instance")
	if lab.graybox_mesh is MeshInstance3D:
		d.check(lab.graybox_mesh.mesh != null, "car.graybox_mesh_present")
		d.check(lab.graybox_mesh.material_override != null, "car.graybox_material_present")
	d.check(lab.camera_rig != null, "camera.rig_present")
	if lab.camera_rig != null:
		d.check(lab.camera_rig.get_camera() != null, "camera.present")
		d.check(
			int(lab.camera_rig.get_mode()) == int(CameraRigScript.Mode.CHASE),
			"camera.chase_mode"
		)
		d.check(lab.camera_rig.get_target_node() == lab.body, "camera.target_is_car")

	d.check(lab.state != null and lab.state.is_finite(), "start.state_finite")
	if lab.state != null and lab.body != null:
		d.check_close(
			lab.body.global_position.x, lab.state.position_m.x, 1e-5, "start.map_x"
		)
		d.check_close(
			lab.body.global_position.z, -lab.state.position_m.y, 1e-5, "start.map_z"
		)
		var bottom := d.aabb_min_y(lab.body.global_transform, lab.hull_shape.size)
		d.check(bottom >= -PENETRATION_TOLERANCE_M, "start.hull_not_buried")
		d.check(
			bottom <= DriveLabScript.HULL_REST_CLEARANCE_M + 0.05,
			"start.hull_near_road"
		)
		var hit := _ray_hit(
			lab.body.global_position + Vector3.UP * 2.0,
			lab.body.global_position - Vector3.UP * 4.0,
			[lab.body.get_rid()]
		)
		d.check(not hit.is_empty(), "road.ray_hit")
		if not hit.is_empty():
			d.check(_hit_surface(hit) == "asphalt", "road.surface_asphalt")
			d.check_close(float(hit["position"].y), 0.0, RAY_TOLERANCE_M, "road.top_at_origin")
	await _teardown_lab(lab)


func _case_movement_from_rest() -> void:
	var commands: Array = []
	for _index in range(90):
		commands.append(d.throttle_command(1.0))
	var lab = _make_lab(commands)
	if lab == null:
		return
	await _settle()
	var run := await _run_auto(lab, 90)
	d.check(not lab.failed, "move.not_failed: " + str(lab.failure_reason))
	d.check(int(run["steps"]) == 90, "move.exactly_90_adapter_calls")
	d.check(int(run["committed"]) == 90, "move.all_90_ticks_committed")
	d.check(int(run["frames"]) >= 90, "move.physics_advanced_at_60hz")
	d.check(int(lab.steps_called) == int(lab.ticks_committed), "move.no_extra_calls")
	if lab.state == null:
		d.check(false, "move.final_state_present")
		await _teardown_lab(lab)
		return
	d.check(lab.state.is_finite(), "move.final_state_finite")
	var station: float = lab.state.position_m.y - lab.start_position_m.y
	d.check(station > 4.0, "move.forward_distance")
	d.check(absf(lab.state.position_m.x - lab.start_position_m.x) < 1e-6, "move.no_lateral_drift")
	d.check(lab.state.speed_m_s() > 5.0, "move.final_speed")
	d.check(
		station + lab.hull_shape.size.z * 0.5 < 500.0 - DriveLabScript.COURSE_END_MARGIN_M,
		"move.stops_before_road_end"
	)

	var max_prediction := 0.0
	var previous: Vector2 = lab.start_position_m
	for index in range(lab.tick_log.size()):
		var record: Dictionary = lab.tick_log[index]
		var label := "move.tick_%d" % (index + 1)
		var position: Vector2 = record["position_m"]
		var velocity: Vector2 = record["velocity_m_s"]
		d.check(
			not is_nan(position.x) and not is_nan(position.y)
			and not is_nan(velocity.x) and not is_nan(velocity.y),
			label + ".finite"
		)
		d.check(not bool(record["contact"]), label + ".open_road_contact_free")
		d.check(
			float(record["remainder_m"]) <= lab.adapter_config.envelope_epsilon_m + 1e-12,
			label + ".clean_remainder"
		)
		var committed_delta := Vector3(
			position.x - previous.x, 0.0, -(position.y - previous.y)
		)
		d.check_vector_close(
			committed_delta, record["accepted_motion_m"], COMMITTED_MATCH_TOLERANCE_M,
			label + ".committed_matches_accepted"
		)
		max_prediction = maxf(
			max_prediction, float(record["prediction_commit_discrepancy_m"])
		)
		previous = position
	d.check(max_prediction <= PREDICTION_TOLERANCE_M, "move.prediction_commit_within_tolerance")
	measurements["final_speed_m_s"] = lab.state.speed_m_s()
	measurements["forward_distance_m"] = station
	measurements["max_prediction_discrepancy_m"] = max_prediction
	await _teardown_lab(lab)


func _case_braking() -> void:
	var commands: Array = []
	for _index in range(90):
		commands.append(d.throttle_command(1.0))
	for _index in range(30):
		commands.append(d.brake_command(1.0))
	for _index in range(20):
		commands.append(d.idle_command())
	var lab = _make_lab(commands)
	if lab == null:
		return
	await _settle()
	var run := await _run_auto(lab, commands.size())
	d.check(not lab.failed, "brake.not_failed: " + str(lab.failure_reason))
	d.check(int(run["committed"]) == commands.size(), "brake.all_ticks_committed")
	if lab.state == null or lab.tick_log.size() < commands.size():
		d.check(false, "brake.complete_trace")
		await _teardown_lab(lab)
		return
	var speeds: Array[float] = []
	for record in lab.tick_log:
		speeds.append((record["velocity_m_s"] as Vector2).length())
	var speed_before: float = speeds[89]
	var speed_after: float = speeds[119]
	d.check(speed_before > 5.0, "brake.entry_speed_positive")
	d.check(speed_after < speed_before - 4.0, "brake.decelerates_by_four_mps")
	var monotonic := true
	for index in range(90, 120):
		if speeds[index] > speeds[index - 1] + 1e-9:
			monotonic = false
	d.check(monotonic, "brake.monotonic_deceleration_window")
	d.check(not lab.state.reverse_engaged, "brake.reverse_not_engaged_in_window")
	d.check(lab.state.speed_m_s() > 0.0, "brake.still_forward_after_window")
	d.check(_all_logged_numbers_finite(lab), "brake.finite_trace")
	measurements["speed_before_brake_m_s"] = speed_before
	measurements["speed_after_brake_m_s"] = speed_after
	measurements["final_speed_m_s"] = lab.state.speed_m_s()
	await _teardown_lab(lab)


func _case_displacement_accounting() -> void:
	var commands: Array = []
	for _index in range(30):
		commands.append(d.throttle_command(1.0))
	for _index in range(30):
		commands.append(d.steer_command(0.4, 1.0))
	for _index in range(30):
		commands.append(d.steer_command(-0.3, 1.0))
	for _index in range(20):
		commands.append(d.idle_command())
	var lab = _make_lab(commands)
	if lab == null:
		return
	await _settle()
	var run := await _run_auto(lab, commands.size())
	d.check(not lab.failed, "account.not_failed: " + str(lab.failure_reason))
	d.check(int(run["committed"]) == commands.size(), "account.all_ticks_committed")
	if lab.state == null or lab.tick_log.size() < commands.size():
		d.check(false, "account.complete_trace")
		await _teardown_lab(lab)
		return
	var previous: Vector2 = lab.start_position_m
	var max_gap := 0.0
	var worst_remainder := 0.0
	for index in range(lab.tick_log.size()):
		var record: Dictionary = lab.tick_log[index]
		var label := "account.tick_%d" % (index + 1)
		var position: Vector2 = record["position_m"]
		var committed_delta := Vector3(
			position.x - previous.x, 0.0, -(position.y - previous.y)
		)
		var accepted: Vector3 = record["accepted_motion_m"]
		var proposed: Vector3 = record["proposed_motion_m"]
		d.check_vector_close(
			committed_delta, accepted, COMMITTED_MATCH_TOLERANCE_M,
			label + ".committed_equals_accepted"
		)
		var gap := proposed.distance_to(accepted)
		max_gap = maxf(max_gap, gap)
		d.check(gap <= PREDICTION_TOLERANCE_M, label + ".predicted_matches_accepted")
		var remainder := float(record["remainder_m"])
		worst_remainder = maxf(worst_remainder, remainder)
		d.check(
			remainder <= lab.adapter_config.envelope_epsilon_m + 1e-12,
			label + ".remainder_within_epsilon"
		)
		d.check(
			accepted.length() + remainder + 1e-9 >= proposed.length(),
			label + ".no_dropped_motion"
		)
		previous = position
	d.check(max_gap <= PREDICTION_TOLERANCE_M, "account.worst_gap_within_tolerance")
	measurements["max_motion_gap_m"] = max_gap
	measurements["worst_remainder_m"] = worst_remainder
	measurements["max_prediction_discrepancy_m"] = _max_prediction_discrepancy(lab)
	await _teardown_lab(lab)


func _case_repeatability() -> void:
	var commands: Array = []
	for _index in range(70):
		commands.append(d.throttle_command(1.0))
	for _index in range(20):
		commands.append(d.steer_command(0.5, 1.0))
	for _index in range(20):
		commands.append(d.brake_command(1.0))
	var first := await _record_trace(commands)
	var second := await _record_trace(commands)
	d.check(bool(first.has("logs")) and bool(second.has("logs")), "repeat.traces_present")
	if not (first.has("logs") and second.has("logs")):
		return
	var logs_a: Array = first["logs"]
	var logs_b: Array = second["logs"]
	d.check(logs_a.size() == commands.size(), "repeat.first_trace_complete")
	d.check(logs_b.size() == commands.size(), "repeat.second_trace_complete")
	var mismatches := 0
	for index in range(mini(logs_a.size(), logs_b.size())):
		var a: Dictionary = logs_a[index]
		var b: Dictionary = logs_b[index]
		if a["position_m"] != b["position_m"]:
			mismatches += 1
		if a["velocity_m_s"] != b["velocity_m_s"]:
			mismatches += 1
		if a["heading_rad"] != b["heading_rad"]:
			mismatches += 1
		if a["body_transform"] != b["body_transform"]:
			mismatches += 1
	d.check(mismatches == 0, "repeat.bit_identical_traces")
	var state_a: Dictionary = first["state"]
	var state_b: Dictionary = second["state"]
	d.check(state_a == state_b, "repeat.final_state_identical")
	measurements["ticks"] = commands.size()
	measurements["mismatches"] = mismatches


func _record_trace(commands: Array) -> Dictionary:
	var lab = _make_lab(commands)
	if lab == null:
		return {}
	await _settle()
	await _run_auto(lab, commands.size())
	var out := {
		"logs": lab.tick_log.duplicate(),
		"state": d.snapshot_state(lab.state),
	}
	await _teardown_lab(lab)
	return out


func _case_finite_state() -> void:
	var commands: Array = []
	for _index in range(60):
		commands.append(d.throttle_command(1.0))
	for _index in range(20):
		commands.append(d.steer_command(0.5, 1.0))
	for _index in range(20):
		commands.append(d.brake_command(1.0))
	for _index in range(20):
		commands.append(d.idle_command())
	var lab = _make_lab(commands)
	if lab == null:
		return
	await _settle()
	var run := await _run_auto(lab, commands.size())
	d.check(not lab.failed, "finite.not_failed: " + str(lab.failure_reason))
	d.check(int(run["committed"]) == commands.size(), "finite.all_ticks_committed")
	d.check(_all_logged_numbers_finite(lab), "finite.every_logged_number")
	d.check(lab.state != null and lab.state.is_finite(), "finite.final_state")
	d.check(_telemetry_numbers_finite(lab), "finite.telemetry")
	d.check(lab.tick_log.size() <= LOG_BOUND, "finite.telemetry_bound")
	d.check(lab.tick_log_dropped == 0, "finite.no_dropped_telemetry_entries")
	var telemetry: Dictionary = lab.get_telemetry()
	for key in ["total_accepted_motion_m", "max_speed_m_s", "max_prediction_discrepancy_m"]:
		d.check_number_finite(float(telemetry[key]), "finite." + String(key))
	await _teardown_lab(lab)


func _case_hull_road_overlap() -> void:
	var commands: Array = []
	for _index in range(60):
		commands.append(d.throttle_command(1.0))
	var lab = _make_lab(commands)
	if lab == null:
		return
	await _settle()
	await _run_auto(lab, commands.size())
	d.check(not lab.failed, "overlap.not_failed: " + str(lab.failure_reason))
	d.check(
		lab.hull_shape.size.distance_to(lab.adapter_config.hull_size_m) <= 0.0,
		"overlap.hull_matches_config"
	)
	var road_center_x: float = lab.start_position_m.x
	for index in range(lab.tick_log.size()):
		var record: Dictionary = lab.tick_log[index]
		var transform: Transform3D = record["body_transform"]
		var bottom := d.aabb_min_y(transform, lab.hull_shape.size)
		d.check(bottom >= -PENETRATION_TOLERANCE_M, "overlap.tick_%d_not_buried" % (index + 1))
		d.check(
			bottom <= DriveLabScript.HULL_REST_CLEARANCE_M + 0.02,
			"overlap.tick_%d_not_floating" % (index + 1)
		)
		var lateral := absf(transform.origin.x - road_center_x)
		d.check(
			lateral <= ROAD_HALF_WIDTH_M - lab.hull_shape.size.x * 0.5 + 0.05,
			"overlap.tick_%d_within_road" % (index + 1)
		)
	for index in [0, int(lab.tick_log.size() / 2), lab.tick_log.size() - 1]:
		var transform: Transform3D = lab.tick_log[index]["body_transform"]
		var hit := _ray_hit(
			transform.origin + Vector3.UP * 2.0,
			transform.origin - Vector3.UP * 4.0,
			[lab.body.get_rid()]
		)
		d.check(not hit.is_empty(), "overlap.ray_%d_hits_road" % index)
		if not hit.is_empty():
			d.check(_hit_surface(hit) == "asphalt", "overlap.ray_%d_asphalt" % index)
			d.check_close(
				float(hit["position"].y), 0.0, RAY_TOLERANCE_M,
				"overlap.ray_%d_top_y" % index
			)
	await _teardown_lab(lab)


func _case_one_call_per_tick() -> void:
	var auto_commands: Array = []
	for _index in range(60):
		auto_commands.append(d.throttle_command(1.0))
	var lab = _make_lab(auto_commands)
	if lab == null:
		return
	await _settle()
	var run := await _run_auto(lab, auto_commands.size())
	d.check(int(run["steps"]) == auto_commands.size(), "onecall.auto_one_step_per_tick")
	d.check(int(run["committed"]) == auto_commands.size(), "onecall.auto_all_committed")
	var indices: Array[int] = []
	for record in lab.tick_log:
		indices.append(int(record["callback_index"]))
	var contiguous := true
	for index in range(1, indices.size()):
		if indices[index] != indices[index - 1] + 1:
			contiguous = false
	d.check(contiguous, "onecall.auto_callback_indices_contiguous")
	var settled_steps := int(lab.steps_called)
	await _settle()
	d.check(int(lab.steps_called) == settled_steps, "onecall.auto_stops_after_script")
	await _teardown_lab(lab)

	var manual = _make_lab([])
	if manual == null:
		return
	await _settle()
	manual.set_auto_tick(false)
	var callbacks_before := int(manual.physics_callbacks)
	for index in range(10):
		var result = manual.step_once(d.throttle_command(1.0))
		d.check(result != null, "onecall.manual_result_present")
		if result != null:
			d.check(
				int(result.status) == int(AdapterScript.Status.COMMITTED),
				"onecall.manual_commits"
			)
		d.check(int(manual.steps_called) == index + 1, "onecall.manual_single_step")
		await get_tree().physics_frame
	d.check(
		int(manual.physics_callbacks) > callbacks_before,
		"onecall.manual_physics_advanced"
	)
	d.check(int(manual.steps_called) == 10, "onecall.manual_no_auto_extra_steps")
	await _teardown_lab(manual)


func _case_refusal_halts() -> void:
	var commands: Array = []
	for _index in range(10):
		commands.append(d.throttle_command(1.0))
	commands.append(null)
	for _index in range(10):
		commands.append(d.throttle_command(1.0))
	var lab = _make_lab(commands)
	if lab == null:
		return
	await _settle()
	lab.start()
	var guard := 0
	while not lab.failed and int(lab.steps_called) < 11 and guard < 200:
		await get_tree().physics_frame
		guard += 1
	d.check(lab.failed, "refusal.failed_flag_set")
	d.check(str(lab.failure_reason) != "", "refusal.reason_reported")
	d.check(int(lab.ticks_committed) == 10, "refusal.committed_before_refusal")
	d.check(int(lab.steps_called) == 11, "refusal.one_refused_call")
	if lab.tick_log.is_empty():
		d.check(false, "refusal.trace_present")
		await _teardown_lab(lab)
		return
	var last: Dictionary = lab.tick_log[-1]
	d.check(
		lab.body.global_transform == last["body_transform"],
		"refusal.body_unchanged"
	)
	d.check(lab.state.position_m == last["position_m"], "refusal.state_unchanged")
	d.check(lab.is_visually_failed(), "refusal.visible_failure_marker")
	var settled_steps := int(lab.steps_called)
	await _settle()
	d.check(int(lab.steps_called) == settled_steps, "refusal.halted_no_more_calls")
	await _teardown_lab(lab)
