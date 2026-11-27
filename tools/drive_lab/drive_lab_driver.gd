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
const SpeedHudScript := preload("res://src/presentation/speed_hud.gd")
const HandlingLabBuilderScript := preload("res://src/laboratory/handling_lab_builder.gd")
const FeedbackScript := preload("res://src/audio/vehicle_feedback_player.gd")

const DRIVE_LAB_SCENE_PATH := "res://scenes/laboratory/drive_lab.tscn"
const SETTLE_FRAMES := 10
const CLEANUP_FRAMES := 8
const PREDICTION_TOLERANCE_M := 1e-4
const COMMITTED_MATCH_TOLERANCE_M := 5e-5
const PENETRATION_TOLERANCE_M := 0.03
const RAY_TOLERANCE_M := 0.35
const ROAD_HALF_WIDTH_M := 6.0
const LOG_BOUND := 1800
## Bounded scripted tick count for the M1.5 presentation case.
const PRESENTATION_TICKS := 30
## Bounded tick counts for the M1.5 audio feedback integration case.
const AUDIO_TICKS := 60
const AUDIO_REFUSAL_HEAD_TICKS := 10
## Must match the movement_from_rest schedule used as the committed-trace
## baseline; the audio case replays it with audio wired.
const AUDIO_BASELINE_TICKS := 90
## Independent oracle constants mirroring the committed component's documented
## provisional map. They exist so validation compares measured playback targets
## against an independent calculation rather than trusting the component.
const FEEDBACK_SPEED_FULL_M_S := 65.0
const FEEDBACK_IDLE_HZ := 55.0
const FEEDBACK_TOP_HZ := 240.0
const FEEDBACK_THROTTLE_PITCH_LIFT := 0.25
const FEEDBACK_IDLE_LEVEL := 0.18
const FEEDBACK_LEVEL_SPEED_WEIGHT := 0.35
const FEEDBACK_LEVEL_THROTTLE_WEIGHT := 0.65
const FEEDBACK_TIRE_SLIP_FULL_DEG := 35.0
const FEEDBACK_TIRE_SLIP_THRESHOLD_DEG := 2.0
const FEEDBACK_TIRE_MIN_SPEED_M_S := 3.0
const FEEDBACK_TIRE_REFERENCE_SPEED_M_S := 30.0
const FEEDBACK_SILENCE_DB := -80.0
## Independent conversion oracle, mirroring the HUD's documented km/h factor.
const KMH_PER_M_S := 3.6
## Bounded wait for a synthetic key event to reach the input pipeline.
const INPUT_WAIT_FRAMES := 20
## Bounded tick counts for the keyboard focus-loss lifecycle case.
const FOCUS_HOLD_TICKS := 20
const FOCUS_COAST_TICKS := 20
const FOCUS_FRESH_TICKS := 20
## Authored bay yaw for the rotated-spawn heading-convention case.
const ROTATED_SPAWN_YAW_DEG := 30.0
const ROTATED_SPAWN_ORIGIN := Vector3(-360.0, 0.0, 60.0)
## Bounded throttle ticks proving the rotated car tracks its authored forward.
const ROTATED_SPAWN_TICKS := 30

const CASE_IDS: Array[String] = [
	"scene_and_manifest",
	"rotated_spawn_heading",
	"movement_from_rest",
	"braking",
	"displacement_accounting",
	"repeatability",
	"finite_state",
	"hull_road_overlap",
	"one_call_per_tick",
	"refusal_halts",
	"presentation_integration",
	"keyboard_focus_lifecycle",
	"reconfigure_presentation_counters",
	"audio_feedback_integration",
]

var d := DriveLabChecks.new()
var measurements: Dictionary = {}
var _results: Array[Dictionary] = []
var _holder: Node3D = null
var _input_probe: InputEventProbe = null
## Committed trace captured by `movement_from_rest`; the audio case replays the
## same schedule and requires a bit-identical simulation trace.
var _baseline_trace: Array = []


## Records synthetic key events that reach the input pipeline. A check that
## expects no reaction uses it to prove the event really was delivered, so an
## unchanged laboratory cannot pass merely because the event never arrived.
class InputEventProbe extends Node:
	var events: Array = []

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey:
			var key := event as InputEventKey
			events.append({"keycode": key.keycode, "pressed": key.pressed, "echo": key.echo})


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_holder = Node3D.new()
	_holder.name = "DriveLabHolder"
	add_child(_holder)
	_input_probe = InputEventProbe.new()
	_input_probe.name = "InputEventProbe"
	add_child(_input_probe)
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
		"rotated_spawn_heading":
			await _case_rotated_spawn_heading()
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
		"presentation_integration":
			await _case_presentation_integration()
		"keyboard_focus_lifecycle":
			await _case_keyboard_focus_lifecycle()
		"reconfigure_presentation_counters":
			await _case_reconfigure_presentation_counters()
		"audio_feedback_integration":
			await _case_audio_feedback_integration()
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


# --- Rotated spawn heading convention --------------------------------------


## The handling-lab builder's heading grows toward local left while
## `CarState`/`MotorBodyAdapter` headings grow toward local right. A rotated
## authored spawn must be converted exactly once, so the committed state and
## the installed body basis both point along the builder's forward vector.
## Both real spawn inputs are exercised: the marker-metadata path and the
## manifest fallback. The zero-yaw control pins the unchanged baseline.
func _case_rotated_spawn_heading() -> void:
	await _rotated_spawn_variant("marker", true)
	await _rotated_spawn_variant("manifest_fallback", false)
	await _rotated_spawn_zero_control()


func _rotated_spawn_variant(label: String, use_marker: bool) -> void:
	var commands: Array = []
	for _index in range(ROTATED_SPAWN_TICKS):
		commands.append(d.throttle_command(1.0))
	var lab = _make_real_geometry_lab(ROTATED_SPAWN_YAW_DEG, use_marker, commands)
	if lab == null:
		return
	await _settle()
	var authored_heading := deg_to_rad(ROTATED_SPAWN_YAW_DEG)
	var builder_forward := HandlingLabBuilderScript._forward(authored_heading)
	var expected_state_heading := 0.0 - authored_heading

	d.check_close(
		lab.state.heading_rad, expected_state_heading, 1e-12,
		label + ".state_heading_converted_to_car_state_convention"
	)
	d.check_vector_close(
		AdapterScript.nose_forward_world(lab.state.heading_rad), builder_forward, 1e-6,
		label + ".state_nose_matches_builder_forward"
	)
	d.check_vector_close(
		d.node_forward(lab.body), builder_forward, 1e-6,
		label + ".installed_body_forward_matches_builder_forward"
	)
	d.check_vector_close(
		-AdapterScript.basis_from_heading(lab.state.heading_rad).z,
		builder_forward, 1e-6,
		label + ".installed_basis_comes_from_converted_heading"
	)
	d.check(
		lab.start_position_m == AdapterScript.world_vector_to_road(ROTATED_SPAWN_ORIGIN),
		label + ".spawn_position_mapping_unchanged"
	)

	var run := await _run_auto(lab, ROTATED_SPAWN_TICKS)
	d.check(not lab.failed, label + ".run_not_failed: " + str(lab.failure_reason))
	d.check(int(run["committed"]) == ROTATED_SPAWN_TICKS, label + ".all_ticks_committed")
	if lab.state == null:
		d.check(false, label + ".final_state_present")
		await _teardown_lab(lab)
		return
	var velocity: Vector2 = lab.state.velocity_m_s
	var start: Vector2 = lab.start_position_m
	var end: Vector2 = lab.state.position_m
	var displacement_world := Vector3(end.x - start.x, 0.0, -(end.y - start.y))
	if displacement_world.length_squared() <= 1e-9:
		d.check(false, label + ".car_displaced_along_authored_forward")
	else:
		d.check(
			displacement_world.normalized().dot(builder_forward) > 0.995,
			label + ".drives_along_authored_bay_forward"
		)
	if velocity.length_squared() > 1e-9:
		var velocity_world := Vector3(velocity.x, 0.0, -velocity.y).normalized()
		d.check(
			velocity_world.dot(builder_forward) > 0.995,
			label + ".velocity_tracks_authored_bay_forward"
		)
	else:
		d.check(false, label + ".velocity_nonzero_after_throttle")
	measurements[label + "_state_heading_rad"] = lab.state.heading_rad
	measurements[label + "_builder_forward"] = str(builder_forward)
	await _teardown_lab(lab)


## Builds a DriveLab whose HandlingLab child is the real builder output, with
## the authored straight spawn at `yaw_deg`. With `use_marker` a direct-child
## `Spawn_straight` marker carries the yaw (the marker-metadata input); without
## it, the manifest straight-bay yaw is rewritten so the manifest fallback is
## the only spawn source. The real asphalt straight geometry is present in both.
func _make_real_geometry_lab(yaw_deg: float, use_marker: bool, commands: Array):
	var lab = DriveLabScript.new()
	lab.name = "DriveLab"
	var handling := Node3D.new()
	handling.name = "HandlingLab"
	var manifest: Dictionary = HandlingLabBuilderScript.build(handling)
	if use_marker:
		handling.set_meta("lab_manifest", manifest)
		var marker := Marker3D.new()
		marker.name = "Spawn_straight"
		marker.transform = Transform3D(
			Basis(Quaternion(Vector3.UP, deg_to_rad(yaw_deg))), ROTATED_SPAWN_ORIGIN
		)
		marker.set_meta("heading_deg", yaw_deg)
		handling.add_child(marker)
	else:
		for bay in manifest.get("bays", []):
			if String(bay.get("bay_id", "")) == "straight":
				bay["yaw_deg"] = yaw_deg
		handling.set_meta("lab_manifest", manifest)
	var configured: bool = lab.configure(d.make_tuning(), d.make_config(), commands)
	d.check(configured, "rotated.configure_accepted")
	lab.add_child(handling)
	_holder.add_child(lab)
	return lab


func _rotated_spawn_zero_control() -> void:
	var lab = _make_real_geometry_lab(0.0, true, [])
	if lab == null:
		return
	await _settle()
	d.check_exact_float(lab.state.heading_rad, 0.0, "rotated.zero_yaw_heading_is_positive_zero")
	d.check_vector_close(
		d.node_forward(lab.body), Vector3(0.0, 0.0, -1.0), 1e-9,
		"rotated.zero_yaw_body_forward_is_minus_z"
	)
	d.check_vector_close(
		AdapterScript.nose_forward_world(lab.state.heading_rad),
		HandlingLabBuilderScript._forward(0.0), 1e-9,
		"rotated.zero_yaw_conventions_agree"
	)
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
	_baseline_trace = _compact_tick_trace(lab.tick_log)
	measurements["baseline_trace_entries"] = _baseline_trace.size()
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


## Compact committed-trace projection used for bit-identical comparisons.
## Simulation-only fields exclude presentation counters that legitimately differ
## between cases.
func _compact_tick_trace(log: Array) -> Array:
	var out: Array = []
	for record in log:
		out.append({
			"position_m": record["position_m"],
			"velocity_m_s": record["velocity_m_s"],
			"heading_rad": record["heading_rad"],
			"body_transform": record["body_transform"],
		})
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


# --- M1.5 presentation integration -----------------------------------------


## Wires the committed `CameraRig` and `SpeedHud` into the laboratory's real
## node tree and proves the integration is honest: exactly one camera and one
## HUD, a display that only ever reads committed state, camera mode cycling and
## momentary rear view that never touch the simulation, and scripted/headless
## mode that ignores synthetic keyboard input. Every wait is bounded, so a
## broken integration fails instead of hanging.
func _case_presentation_integration() -> void:
	var commands: Array = []
	for _index in range(PRESENTATION_TICKS):
		commands.append(d.throttle_command(1.0))
	var lab = _make_lab(commands)
	if lab == null:
		return
	if not _presentation_api_available(lab):
		await _teardown_lab(lab)
		return
	await _settle()
	await _presentation_structure_checks(lab)
	await _presentation_initial_display_checks(lab)
	_presentation_negative_control(lab)
	await _presentation_committed_display_checks(lab)
	await _presentation_camera_action_checks(lab)
	await _presentation_scripted_input_immunity_checks(lab)
	await _presentation_teardown_checks(lab)
	await _presentation_keyboard_checks()


## The laboratory must expose the presentation API this case exercises. A
## laboratory without it fails the case cleanly instead of erroring out.
func _presentation_api_available(lab) -> bool:
	var required := [
		"get_speed_hud", "get_hud_layer", "get_hud_error", "is_presentation_ready",
		"cycle_camera_mode", "get_camera_mode", "get_camera_mode_name",
		"set_rear_view_held", "is_rear_view_held", "get_presentation_telemetry",
	]
	var missing: Array = []
	for name in required:
		if not lab.has_method(name):
			missing.append(name)
	d.check(missing.is_empty(), "presentation.api_present: missing " + str(missing))
	return missing.is_empty()


func _presentation_structure_checks(lab) -> void:
	d.check(str(lab.get_hud_error()).is_empty(), "hud.build_error: " + str(lab.get_hud_error()))
	d.check(lab.is_presentation_ready(), "presentation.rig_hud_and_camera_ready")
	var layer: CanvasLayer = lab.get_hud_layer()
	d.check(layer != null, "hud.canvas_layer_present")
	if layer != null:
		d.check(layer is CanvasLayer, "hud.canvas_layer_type")
		d.check(layer.is_inside_tree(), "hud.canvas_layer_inside_tree")
		d.check(layer.get_child_count() == 1, "hud.canvas_layer_holds_exactly_one_child")
	var hud: SpeedHud = lab.get_speed_hud()
	d.check(hud != null, "hud.instance_present")
	if hud != null and layer != null:
		d.check(hud.get_parent() == layer, "hud.parent_is_the_lab_canvas_layer")
		d.check(hud.get_script() == SpeedHudScript, "hud.uses_the_committed_component")
	d.check(
		d.count_script_instances(get_tree().root, SpeedHudScript) == 1,
		"hud.exactly_one_instance_in_tree"
	)
	d.check(
		d.count_class_instances(get_tree().root, "Camera3D") == 1,
		"camera.exactly_one_camera3d"
	)
	var cameras := d.find_class_instances(get_tree().root, "Camera3D")
	if cameras.size() == 1 and lab.camera_rig != null:
		d.check(
			cameras[0] == lab.camera_rig.get_camera(),
			"camera.rig_owns_the_only_camera"
		)
	d.check(
		d.count_class_instances(get_tree().root, "Viewport") == 1,
		"camera.exactly_one_viewport"
	)
	d.check(
		int(lab.get_camera_mode()) == int(CameraRigScript.Mode.CHASE),
		"camera.initial_mode_is_chase"
	)
	d.check(lab.get_camera_mode_name() == "chase", "camera.initial_mode_name")
	d.check(lab.camera_rig.get_target_node() == lab.body, "camera.target_is_the_car")
	d.check(not lab.is_rear_view_held(), "camera.rear_view_initially_released")


func _presentation_initial_display_checks(lab) -> void:
	var hud: SpeedHud = lab.get_speed_hud()
	if hud == null:
		d.check(false, "hud.initial_display_requires_an_instance")
		return
	d.check(int(lab.ticks_committed) == 0, "hud.initial_display_before_any_commit")
	d.check(hud.has_display(), "hud.initial_display_committed")
	d.check(d.hud_label_text(hud, "SpeedLabel") == "0", "hud.initial_speed_zero")
	d.check(d.hud_label_text(hud, "UnitLabel") == "km/h", "hud.initial_unit_km_h")
	d.check(d.hud_label_text(hud, "DriftLabel") == "GRIP", "hud.initial_drift_text_grip")
	d.check(d.hud_label_text(hud, "ReverseLabel") == "", "hud.initial_no_reverse_text")
	d.check(d.hud_label_text(hud, "QualifyingLabel") == "", "hud.initial_no_qualifying_text")
	d.check(
		int(hud.get_last_phase()) == int(SpeedHudScript.DriftPhase.GRIP),
		"hud.initial_phase_is_grip"
	)
	d.check(
		int(hud.get_last_units()) == int(SpeedHudScript.SpeedUnit.KM_H),
		"hud.initial_units_km_h"
	)
	var marker = hud.get_marker()
	d.check(marker != null and marker.get_shape_name() == "ring", "hud.initial_grip_marker_ring")
	var reverse_label: Control = hud.get_node_or_null("Contents/ReverseLabel") as Control
	d.check(reverse_label != null and not reverse_label.visible, "hud.initial_reverse_hidden")


## Deliberate negative control for this case: a scratch collector fed a
## deliberately wrong expectation about a real measurement must record exactly
## one failure, and the live collector must be untouched. Without it, a set of
## assertions that can never fail would look like passing evidence.
func _presentation_negative_control(lab) -> void:
	var measured := d.hud_label_text(lab.get_speed_hud(), "SpeedLabel")
	var live_failures_before := d.failures.size()
	var scratch := ChecksScript.new()
	scratch.check(
		measured == "999",
		"negative control: deliberately wrong speed expectation"
	)
	scratch.check(true, "negative control: passing control assertion")
	d.check(scratch.checks == 2, "negative_control.collector_counted_both_assertions")
	d.check(scratch.failures.size() == 1, "negative_control.deliberate_failure_detected")
	d.check(
		d.failures.size() == live_failures_before,
		"negative_control.live_collector_untouched"
	)
	measurements["negative_control_measured_speed_text"] = measured


func _presentation_committed_display_checks(lab) -> void:
	var hud: SpeedHud = lab.get_speed_hud()
	if hud == null:
		d.check(false, "hud.committed_display_requires_an_instance")
		return
	var run := await _run_auto(lab, PRESENTATION_TICKS)
	d.check(not lab.failed, "hud.committed_run_not_failed: " + str(lab.failure_reason))
	d.check(int(run["committed"]) == PRESENTATION_TICKS, "hud.committed_ticks_ran")
	var expected := str(int(round(lab.state.speed_m_s() * KMH_PER_M_S)))
	d.check(
		d.hud_label_text(hud, "SpeedLabel") == expected,
		"hud.speed_matches_committed_state (shown=%s expected=%s)"
			% [d.hud_label_text(hud, "SpeedLabel"), expected]
	)
	d.check(expected != "0", "hud.speed_nonzero_after_throttle")
	d.check(d.hud_label_text(hud, "DriftLabel") == "GRIP", "hud.committed_drift_text_still_grip")
	d.check(
		int(hud.get_last_phase()) == int(SpeedHudScript.DriftPhase.GRIP),
		"hud.committed_phase_still_grip"
	)
	var telemetry: Dictionary = lab.get_presentation_telemetry()
	d.check(
		int(telemetry["hud_updates"]) == 1 + PRESENTATION_TICKS,
		"hud.one_update_per_commit_plus_the_initial_one (updates=%s)"
			% str(telemetry["hud_updates"])
	)
	d.check(int(telemetry["hud_rejected_updates"]) == 0, "hud.no_rejected_updates")
	d.check(str(telemetry["hud_error"]).is_empty(), "hud.no_refresh_defect")
	measurements["hud_speed_text"] = d.hud_label_text(hud, "SpeedLabel")
	measurements["committed_speed_m_s"] = lab.state.speed_m_s()
	measurements["hud_updates"] = int(telemetry["hud_updates"])


func _presentation_camera_action_checks(lab) -> void:
	var steps_before := int(lab.steps_called)
	var committed_before := int(lab.ticks_committed)
	var callbacks_before := int(lab.physics_callbacks)
	var log_before := int(lab.tick_log.size())
	var state_before := d.snapshot_state(lab.state)
	var transform_before: Transform3D = lab.body.global_transform
	var car_forward: Vector3 = d.node_forward(lab.body)
	var camera: Camera3D = lab.camera_rig.get_camera()
	var chase_dot := 0.0
	var rear_dot := 0.0
	d.check(camera != null, "camera.single_camera_node")
	d.check(lab.get_camera_mode_name() == "chase", "camera.actions_start_in_chase")
	var first = lab.cycle_camera_mode()
	d.check(
		int(first) == int(CameraRigScript.Mode.NEAR_CHASE),
		"camera.cycle_chase_to_near_chase (got=%s)" % str(first)
	)
	d.check(lab.get_camera_mode_name() == "near_chase", "camera.mode_name_near_chase")
	var second = lab.cycle_camera_mode()
	d.check(
		int(second) == int(CameraRigScript.Mode.HOOD),
		"camera.cycle_near_chase_to_hood (got=%s)" % str(second)
	)
	d.check(lab.get_camera_mode_name() == "hood", "camera.mode_name_hood")
	var third = lab.cycle_camera_mode()
	d.check(
		int(third) == int(CameraRigScript.Mode.CHASE),
		"camera.cycle_wraps_back_to_chase (got=%s)" % str(third)
	)
	if camera != null:
		chase_dot = d.camera_forward(camera).dot(car_forward)
		d.check(
			chase_dot > 0.9,
			"camera.chase_looks_along_the_car_forward_axis (dot=%s)" % str(chase_dot)
		)
		lab.set_rear_view_held(true)
		d.check(lab.is_rear_view_held(), "camera.rear_view_held_flag_set")
		rear_dot = d.camera_forward(camera).dot(car_forward)
		d.check(
			rear_dot < -0.9,
			"camera.rear_view_looks_backwards (dot=%s)" % str(rear_dot)
		)
		lab.set_rear_view_held(false)
		d.check(not lab.is_rear_view_held(), "camera.rear_view_released_flag_cleared")
		var restored_dot := d.camera_forward(camera).dot(car_forward)
		d.check(
			restored_dot > 0.9,
			"camera.forward_view_restored_after_release (dot=%s)" % str(restored_dot)
		)
	d.check(
		d.count_class_instances(get_tree().root, "Camera3D") == 1,
		"camera.actions_created_no_second_camera"
	)
	d.check(
		d.count_class_instances(get_tree().root, "Viewport") == 1,
		"camera.actions_created_no_second_viewport"
	)
	d.check(int(lab.steps_called) == steps_before, "camera.actions_called_no_adapter_step")
	d.check(int(lab.ticks_committed) == committed_before, "camera.actions_committed_no_tick")
	d.check(
		int(lab.physics_callbacks) == callbacks_before,
		"camera.actions_caused_no_physics_frame"
	)
	d.check(lab.tick_log.size() == log_before, "camera.actions_logged_no_tick")
	d.check(
		lab.body.global_transform == transform_before,
		"camera.actions_left_body_transform_unchanged"
	)
	d.check_state_unchanged(lab.state, state_before, "camera.actions_left_committed_state_unchanged")
	measurements["camera_chase_dot"] = chase_dot
	measurements["camera_rear_dot"] = rear_dot


func _presentation_scripted_input_immunity_checks(lab) -> void:
	var mode_before: String = lab.get_camera_mode_name()
	var steps_before := int(lab.steps_called)
	var committed_before := int(lab.ticks_committed)
	var state_before := d.snapshot_state(lab.state)
	var transform_before: Transform3D = lab.body.global_transform
	var frames_before := int(lab.physics_callbacks)
	for _index in range(4):
		await get_tree().physics_frame
	var idle_delta := int(lab.physics_callbacks) - frames_before
	_input_probe.events.clear()
	_deliver_key(Key.KEY_C, true)
	_deliver_key(Key.KEY_SHIFT, true)
	var delivered := await _await_input_events(2, INPUT_WAIT_FRAMES)
	d.check(delivered, "scripted_input.synthetic_events_reached_the_input_pipeline")
	var frames_after := int(lab.physics_callbacks)
	for _index in range(4):
		await get_tree().physics_frame
	var action_delta := int(lab.physics_callbacks) - frames_after
	d.check(
		action_delta == idle_delta,
		"scripted_input.caused_no_extra_physics_frames (idle=%d action=%d)"
			% [idle_delta, action_delta]
	)
	d.check(lab.get_camera_mode_name() == mode_before, "scripted_input.camera_mode_unchanged")
	d.check(not lab.is_rear_view_held(), "scripted_input.rear_view_not_held")
	d.check(int(lab.steps_called) == steps_before, "scripted_input.called_no_adapter_step")
	d.check(int(lab.ticks_committed) == committed_before, "scripted_input.committed_no_tick")
	d.check(
		lab.body.global_transform == transform_before,
		"scripted_input.body_transform_unchanged"
	)
	d.check_state_unchanged(lab.state, state_before, "scripted_input.committed_state_unchanged")
	measurements["scripted_input_events_delivered"] = _input_probe.events.size()


func _presentation_teardown_checks(lab) -> void:
	var hud = lab.get_speed_hud()
	var layer: CanvasLayer = lab.get_hud_layer()
	var rig = lab.camera_rig
	var camera: Camera3D = null
	if rig != null:
		camera = rig.get_camera()
	await _teardown_lab(lab)
	d.check(not is_instance_valid(hud), "teardown.hud_instance_freed")
	d.check(not is_instance_valid(layer), "teardown.hud_canvas_layer_freed")
	d.check(not is_instance_valid(rig), "teardown.camera_rig_freed")
	d.check(not is_instance_valid(camera), "teardown.camera_freed")
	d.check(
		d.count_script_instances(get_tree().root, SpeedHudScript) == 0,
		"teardown.no_hud_left_in_tree"
	)
	d.check(
		d.count_class_instances(get_tree().root, "Camera3D") == 0,
		"teardown.no_camera_left_in_tree"
	)
	d.check(
		d.count_class_instances(get_tree().root, "CanvasLayer") == 0,
		"teardown.no_canvas_layer_left_in_tree"
	)


## Keyboard mode only: synthetic `C` and `Shift` must reach the laboratory
## through the real input pipeline and drive the presentation, and the normal
## keyboard drive path must still work. Every wait is bounded.
func _presentation_keyboard_checks() -> void:
	var lab = _make_lab([])
	if lab == null:
		return
	if not _presentation_api_available(lab):
		await _teardown_lab(lab)
		return
	lab.command_mode = DriveLabScript.CommandMode.KEYBOARD
	lab.set_auto_tick(false)
	await _settle()
	var steps_before := int(lab.steps_called)
	_input_probe.events.clear()
	_deliver_key(Key.KEY_C, true)
	var cycled := await _await_camera_mode_name(lab, "near_chase", INPUT_WAIT_FRAMES)
	d.check(cycled, "keyboard_input.c_cycles_the_camera_mode")
	d.check(
		_input_probe.events.size() >= 1,
		"keyboard_input.synthetic_key_reached_the_input_pipeline"
	)
	_deliver_key(Key.KEY_SHIFT, true)
	var held := await _await_rear_view(lab, true, INPUT_WAIT_FRAMES)
	d.check(held, "keyboard_input.shift_holds_the_rear_view")
	_deliver_key(Key.KEY_SHIFT, false)
	var released := await _await_rear_view(lab, false, INPUT_WAIT_FRAMES)
	d.check(released, "keyboard_input.shift_release_restores_the_forward_view")
	# Auto-repeat must not advance the mode a second time for one press.
	_deliver_key(Key.KEY_C, true, true)
	await _settle()
	d.check(
		lab.get_camera_mode_name() == "near_chase",
		"keyboard_input.key_repeat_does_not_cycle_the_mode"
	)
	d.check(
		int(lab.steps_called) == steps_before,
		"keyboard_input.presentation_keys_called_no_adapter_step"
	)
	_deliver_key(Key.KEY_W, true)
	lab.set_auto_tick(true)
	var guard := 0
	while int(lab.steps_called) - steps_before < 6 and guard < 120:
		await get_tree().physics_frame
		guard += 1
	lab.set_auto_tick(false)
	var driven := int(lab.steps_called) - steps_before
	d.check(
		driven >= 6,
		"keyboard_input.throttle_key_drove_bounded_ticks (ticks=%d)" % driven
	)
	d.check(not lab.failed, "keyboard_input.run_not_failed: " + str(lab.failure_reason))
	d.check(lab.state.speed_m_s() > 0.0, "keyboard_input.car_accelerated_from_the_throttle_key")
	d.check(
		d.hud_label_text(lab.get_speed_hud(), "SpeedLabel") != "0",
		"keyboard_input.hud_follows_the_keyboard_commits"
	)
	measurements["keyboard_driven_ticks"] = driven
	measurements["keyboard_speed_m_s"] = lab.state.speed_m_s()
	await _teardown_lab(lab)


# --- Keyboard focus-loss lifecycle ------------------------------------------


## Hold `W` and `Shift` through the real input pipeline, lose focus without any
## key-up event, and prove the laboratory drops the held throttle and rear view
## immediately. A real release while the window is unfocused never reaches
## `_unhandled_input()`, so this reproduces the exact failure mode. Headless
## runs cannot create a genuine OS window focus transition; the case drives
## Godot's `NOTIFICATION_WM_WINDOW_FOCUS_OUT` through the scene-tree root, the
## same notification the engine propagates on window focus loss. It does not
## exercise DisplayServer or a window-manager transition.
func _case_keyboard_focus_lifecycle() -> void:
	var lab = _make_lab([])
	if lab == null:
		return
	if not _presentation_api_available(lab):
		await _teardown_lab(lab)
		return
	lab.command_mode = DriveLabScript.CommandMode.KEYBOARD
	lab.set_auto_tick(false)
	await _settle()

	_input_probe.events.clear()
	_deliver_key(Key.KEY_W, true)
	_deliver_key(Key.KEY_SHIFT, true)
	var registered := await _await_input_events(2, INPUT_WAIT_FRAMES)
	d.check(registered, "focus.synthetic_key_downs_reached_the_input_pipeline")
	d.check(lab._keys.get(Key.KEY_W, false), "focus.w_registered_as_held")
	d.check(lab._keys.get(Key.KEY_SHIFT, false), "focus.shift_registered_as_held")
	d.check(lab.is_rear_view_held(), "focus.rear_view_held_before_focus_loss")

	lab.set_auto_tick(true)
	var hold_run := await _run_auto(lab, FOCUS_HOLD_TICKS)
	lab.set_auto_tick(false)
	d.check(int(hold_run["steps"]) == FOCUS_HOLD_TICKS, "focus.held_w_drove_ticks")
	d.check(not lab.failed, "focus.held_run_not_failed: " + str(lab.failure_reason))
	var held_speed := 0.0
	if lab.state != null:
		held_speed = lab.state.speed_m_s()
	d.check(held_speed > 0.0, "focus.car_accelerated_under_held_throttle")

	get_tree().root.propagate_notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	d.check(not lab.is_rear_view_held(), "focus.rear_view_released_on_focus_loss")
	d.check(lab._keys.is_empty(), "focus.keyboard_cache_cleared_on_focus_loss")
	var coast_start_speed := 0.0
	if lab.state != null:
		coast_start_speed = lab.state.speed_m_s()
	lab.set_auto_tick(true)
	var coast_run := await _run_auto(lab, FOCUS_COAST_TICKS)
	lab.set_auto_tick(false)
	d.check(int(coast_run["steps"]) == FOCUS_COAST_TICKS, "focus.coast_ticks_ran_without_release_events")
	d.check(not lab.failed, "focus.coast_run_not_failed: " + str(lab.failure_reason))
	var coast_end_speed := 0.0
	if lab.state != null:
		coast_end_speed = lab.state.speed_m_s()
	d.check(
		coast_end_speed <= coast_start_speed + 1e-6,
		"focus.no_residual_throttle_after_focus_loss (before=%s after=%s)"
			% [coast_start_speed, coast_end_speed]
	)

	_input_probe.events.clear()
	_deliver_key(Key.KEY_W, true)
	var fresh_registered := await _await_input_events(1, INPUT_WAIT_FRAMES)
	d.check(fresh_registered, "focus.fresh_key_down_reached_the_input_pipeline")
	d.check(lab._keys.get(Key.KEY_W, false), "focus.fresh_press_registered_after_focus_loss")
	lab.set_auto_tick(true)
	var fresh_run := await _run_auto(lab, FOCUS_FRESH_TICKS)
	lab.set_auto_tick(false)
	d.check(int(fresh_run["steps"]) == FOCUS_FRESH_TICKS, "focus.fresh_press_drove_ticks")
	d.check(not lab.failed, "focus.fresh_run_not_failed: " + str(lab.failure_reason))
	var fresh_end_speed := 0.0
	if lab.state != null:
		fresh_end_speed = lab.state.speed_m_s()
	d.check(
		fresh_end_speed > coast_start_speed + 0.5,
		"focus.fresh_press_resumes_throttle (coast=%s fresh=%s)"
			% [coast_start_speed, fresh_end_speed]
	)

	measurements["focus_held_speed_m_s"] = held_speed
	measurements["focus_coast_start_speed_m_s"] = coast_start_speed
	measurements["focus_coast_end_speed_m_s"] = coast_end_speed
	measurements["focus_fresh_end_speed_m_s"] = fresh_end_speed

	# The application-level deactivation notification takes the same path.
	# Release and re-press Shift first: the pre-focus-loss press never got a
	# release event, so this is a genuine fresh press rather than a duplicate.
	_input_probe.events.clear()
	_deliver_key(Key.KEY_SHIFT, false)
	_deliver_key(Key.KEY_SHIFT, true)
	var shift_registered := await _await_input_events(2, INPUT_WAIT_FRAMES)
	d.check(shift_registered, "focus.shift_key_down_reached_the_input_pipeline")
	d.check(lab.is_rear_view_held(), "focus.rear_view_held_before_application_focus_loss")
	get_tree().root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	d.check(
		not lab.is_rear_view_held(),
		"focus.rear_view_released_on_application_focus_loss"
	)
	d.check(
		lab._keys.is_empty(),
		"focus.keyboard_cache_cleared_on_application_focus_loss"
	)

	await _teardown_lab(lab)


## Reconfiguring one laboratory must describe only the new configuration.
## Presentation counters cover the current run; carrying camera cycles, rear-view
## holds and HUD updates across `configure()` would report activity that no
## longer belongs to the configured schedule.
func _case_reconfigure_presentation_counters() -> void:
	var first_commands: Array = []
	for _index in range(20):
		first_commands.append(d.throttle_command(1.0))
	var lab = _make_lab(first_commands)
	if lab == null:
		return
	await _settle()
	var first_run := await _run_auto(lab, first_commands.size())
	d.check(int(first_run["committed"]) == first_commands.size(), "reconfig.first_schedule_ran")
	lab.cycle_camera_mode()
	lab.set_rear_view_held(true)
	lab.set_rear_view_held(false)
	var telemetry_before: Dictionary = lab.get_presentation_telemetry()
	d.check(
		int(telemetry_before["camera_mode_cycles"]) > 0,
		"reconfig.camera_counter_nonzero_before_reset"
	)
	d.check(
		int(telemetry_before["rear_view_holds"]) > 0,
		"reconfig.rear_view_counter_nonzero_before_reset"
	)
	d.check(
		int(telemetry_before["hud_updates"]) > 0,
		"reconfig.hud_update_counter_nonzero_before_reset"
	)

	var second_commands: Array = []
	for _index in range(10):
		second_commands.append(d.idle_command())
	var reconfigured: bool = lab.configure(lab.tuning, lab.adapter_config, second_commands)
	d.check(reconfigured, "reconfig.configure_accepted_second_schedule")
	var telemetry_after: Dictionary = lab.get_presentation_telemetry()
	d.check(
		int(telemetry_after["hud_updates"]) == 1,
		"reconfig.hud_update_counter_reset_to_initial_update (got=%d)"
			% int(telemetry_after["hud_updates"])
	)
	d.check(
		int(telemetry_after["hud_rejected_updates"]) == 0,
		"reconfig.hud_rejected_counter_reset"
	)
	d.check(
		int(telemetry_after["camera_mode_cycles"]) == 0,
		"reconfig.camera_counter_reset"
	)
	d.check(
		int(telemetry_after["rear_view_holds"]) == 0,
		"reconfig.rear_view_counter_reset"
	)
	var simulation: Dictionary = lab.get_telemetry()
	d.check(int(simulation["steps_called"]) == 0, "reconfig.steps_counter_reset")
	d.check(int(simulation["ticks_committed"]) == 0, "reconfig.committed_counter_reset")

	var second_run := await _run_auto(lab, second_commands.size())
	d.check(int(second_run["committed"]) == second_commands.size(), "reconfig.second_schedule_ran")
	d.check(not lab.failed, "reconfig.second_run_not_failed: " + str(lab.failure_reason))
	measurements["reconfig_first_committed"] = int(first_run["committed"])
	measurements["reconfig_second_committed"] = int(second_run["committed"])
	await _teardown_lab(lab)


# --- M1.5 audio feedback integration --------------------------------------


## Wires the committed `VehicleFeedbackPlayer` into the laboratory's real node
## tree and proves the integration is honest: exactly one component under the
## laboratory owning exactly two named voices, startup parked at the independent
## idle targets, mapped pitch/gain changing on real committed acceleration
## ticks, stable stream references and PCM across those commits, no audio apply
## on an adapter refusal, counted diagnostic refusals when the component is
## torn down, one component and two voices across reconfiguration, and a
## bit-identical committed simulation trace against the movement baseline.
## Headless dummy audio cannot certify audible quality; see README.
func _case_audio_feedback_integration() -> void:
	await _audio_structure_and_startup_checks()
	await _audio_acceleration_mapping_checks()
	await _audio_adapter_refusal_checks()
	await _audio_apply_refusal_checks()
	await _audio_reconfigure_and_trace_checks()


func _audio_api_available(lab) -> bool:
	var required := [
		"get_feedback_player", "is_audio_ready", "get_audio_error",
		"get_audio_telemetry",
	]
	var missing: Array = []
	for name in required:
		if not lab.has_method(name):
			missing.append(name)
	d.check(missing.is_empty(), "audio.api_present: missing " + str(missing))
	return missing.is_empty()


func _audio_structure_and_startup_checks() -> void:
	var lab = _make_lab([])
	if lab == null:
		return
	if not _audio_api_available(lab):
		await _teardown_lab(lab)
		return
	await _settle()
	d.check(not lab.failed, "audio.startup_not_failed: " + str(lab.failure_reason))
	d.check(str(lab.get_audio_error()).is_empty(), "audio.no_startup_error: " + str(lab.get_audio_error()))
	d.check(lab.is_audio_ready(), "audio.component_ready")
	var player = lab.get_feedback_player()
	d.check(player != null, "audio.player_present")
	if player == null:
		await _teardown_lab(lab)
		return
	d.check(player.get_parent() == lab, "audio.player_owned_by_laboratory")
	d.check(player.get_script() == FeedbackScript, "audio.uses_committed_component")
	d.check(
		d.count_script_instances(get_tree().root, FeedbackScript) == 1,
		"audio.exactly_one_component_in_tree"
	)
	d.check(player.is_setup_complete(), "audio.setup_complete")
	d.check(player.get_child_count() == 2, "audio.owns_exactly_two_voices")
	var engine_player = player.get_node_or_null("Engine")
	var tire_player = player.get_node_or_null("Tire")
	d.check(
		engine_player is AudioStreamPlayer and tire_player is AudioStreamPlayer,
		"audio.named_voices_are_audio_stream_players"
	)
	if engine_player != null:
		d.check(engine_player.get_parent() == player, "audio.engine_voice_owned_by_component")
	if tire_player != null:
		d.check(tire_player.get_parent() == player, "audio.tire_voice_owned_by_component")
	d.check(
		d.count_class_instances(get_tree().root, "AudioStreamPlayer") == 2,
		"audio.exactly_two_voices_in_tree"
	)
	var engine_stream: AudioStreamWAV = player.get_engine_stream()
	var tire_stream: AudioStreamWAV = player.get_tire_stream()
	d.check(engine_stream is AudioStreamWAV and tire_stream is AudioStreamWAV, "audio.both_streams_are_wav")
	if engine_stream != null:
		d.check(engine_stream.data.size() > 0, "audio.engine_pcm_present")
	if tire_stream != null:
		d.check(tire_stream.data.size() > 0, "audio.tire_pcm_present")
	if engine_player != null and engine_stream != null:
		d.check(engine_player.stream == engine_stream, "audio.engine_voice_assigned_the_engine_stream")
	if tire_player != null and tire_stream != null:
		d.check(tire_player.stream == tire_stream, "audio.tire_voice_assigned_the_tire_stream")

	# Startup must be parked/idle: no commit, no apply attempt, idle targets and
	# both voices playing under the dummy driver. Values only; no audible claim.
	d.check(int(lab.ticks_committed) == 0, "audio.startup_before_any_commit")
	var telemetry: Dictionary = lab.get_audio_telemetry()
	d.check(int(telemetry["audio_setup_complete"]), "audio.startup_setup_complete_flag")
	d.check(int(telemetry["audio_updates"]) == 0, "audio.startup_no_apply_yet")
	d.check(int(telemetry["audio_rejected_updates"]) == 0, "audio.startup_no_refused_apply")
	d.check(int(telemetry["audio_apply_attempts"]) == 0, "audio.startup_no_apply_attempt")
	d.check(bool(telemetry["engine_voice_playing"]), "audio.startup_engine_voice_playing")
	d.check(bool(telemetry["tire_voice_playing"]), "audio.startup_tire_voice_playing")
	d.check_close(
		float(telemetry["last_engine_pitch_scale"]),
		feedback_oracle_pitch(0.0, 0.0), 1e-6, "audio.startup_idle_pitch"
	)
	d.check_close(
		float(telemetry["last_engine_volume_db"]),
		feedback_oracle_engine_db(0.0, 0.0), 1e-6, "audio.startup_idle_engine_level"
	)
	d.check_close(
		float(telemetry["last_tire_volume_db"]),
		FEEDBACK_SILENCE_DB, 1e-6, "audio.startup_tires_silent"
	)
	measurements["audio_idle_pitch"] = float(telemetry["last_engine_pitch_scale"])
	measurements["audio_idle_engine_db"] = float(telemetry["last_engine_volume_db"])
	measurements["audio_engine_pcm_bytes"] = int(telemetry["engine_stream_bytes"])
	measurements["audio_tire_pcm_bytes"] = int(telemetry["tire_stream_bytes"])
	await _teardown_lab(lab)


func _audio_acceleration_mapping_checks() -> void:
	var commands: Array = []
	for _index in range(AUDIO_TICKS):
		commands.append(d.throttle_command(1.0))
	var lab = _make_lab(commands)
	if lab == null:
		return
	if not _audio_api_available(lab):
		await _teardown_lab(lab)
		return
	await _settle()
	var player = lab.get_feedback_player()
	var engine_stream: AudioStreamWAV = player.get_engine_stream() if player != null else null
	var tire_stream: AudioStreamWAV = player.get_tire_stream() if player != null else null
	if player == null or engine_stream == null or tire_stream == null:
		d.check(false, "audio.acceleration_fixture_ready")
		await _teardown_lab(lab)
		return
	var engine_data: PackedByteArray = engine_stream.data.duplicate()
	var tire_data: PackedByteArray = tire_stream.data.duplicate()

	var pitch_first := 0.0
	var pitch_previous := 0.0
	var engine_db_first := 0.0
	var engine_db_previous := 0.0
	var monotonic_pitch := true
	var monotonic_engine_db := true
	var oracle_mismatches := 0
	var last_pitch := 0.0
	var last_engine_db := 0.0
	var last_tire_db := 0.0
	lab.start()
	for index in range(AUDIO_TICKS):
		await get_tree().physics_frame
		if lab.failed:
			break
		var telemetry: Dictionary = lab.get_audio_telemetry()
		var pitch := float(telemetry["last_engine_pitch_scale"])
		var engine_db := float(telemetry["last_engine_volume_db"])
		var tire_db := float(telemetry["last_tire_volume_db"])
		if index == 0:
			pitch_first = pitch
			engine_db_first = engine_db
		else:
			if pitch < pitch_previous - 1e-9:
				monotonic_pitch = false
			if engine_db < engine_db_previous - 1e-9:
				monotonic_engine_db = false
		pitch_previous = pitch
		engine_db_previous = engine_db
		last_pitch = pitch
		last_engine_db = engine_db
		last_tire_db = tire_db
		var expected_pitch := feedback_oracle_pitch(lab.state.speed_m_s(), 1.0)
		var expected_engine_db := feedback_oracle_engine_db(lab.state.speed_m_s(), 1.0)
		var expected_tire_db := feedback_oracle_tire_db(
			lab.state.slip_deg(), lab.state.speed_m_s(), lab.state.grounded
		)
		if absf(pitch - expected_pitch) > 1e-6:
			oracle_mismatches += 1
		if absf(engine_db - expected_engine_db) > 1e-6:
			oracle_mismatches += 1
		if absf(tire_db - expected_tire_db) > 1e-6:
			oracle_mismatches += 1

	d.check(not lab.failed, "audio.acceleration_run_not_failed: " + str(lab.failure_reason))
	d.check(int(lab.ticks_committed) == AUDIO_TICKS, "audio.all_acceleration_ticks_committed")
	var final_telemetry: Dictionary = lab.get_audio_telemetry()
	d.check(int(final_telemetry["audio_updates"]) == AUDIO_TICKS, "audio.one_update_per_committed_tick")
	d.check(int(final_telemetry["audio_apply_attempts"]) == AUDIO_TICKS, "audio.one_apply_attempt_per_committed_tick")
	d.check(int(final_telemetry["audio_rejected_updates"]) == 0, "audio.no_refused_apply_on_normal_run")
	d.check(monotonic_pitch, "audio.engine_pitch_monotonic_over_acceleration")
	d.check(monotonic_engine_db, "audio.engine_level_monotonic_over_acceleration")
	d.check(last_pitch > pitch_first, "audio.engine_pitch_rises_with_speed")
	d.check(last_engine_db > engine_db_first, "audio.engine_level_rises_with_speed")
	d.check(
		oracle_mismatches == 0,
		"audio.mapping_matches_independent_oracle (mismatches=%d)" % oracle_mismatches
	)
	d.check_close(
		last_pitch, feedback_oracle_pitch(lab.state.speed_m_s(), 1.0), 1e-6,
		"audio.final_pitch_oracle"
	)
	d.check_close(
		last_engine_db, feedback_oracle_engine_db(lab.state.speed_m_s(), 1.0), 1e-6,
		"audio.final_engine_level_oracle"
	)
	d.check_close(
		last_tire_db,
		feedback_oracle_tire_db(lab.state.slip_deg(), lab.state.speed_m_s(), lab.state.grounded),
		1e-6, "audio.final_tire_level_oracle"
	)
	d.check(player.get_engine_stream() == engine_stream, "audio.engine_stream_reference_stable")
	d.check(player.get_tire_stream() == tire_stream, "audio.tire_stream_reference_stable")
	d.check(engine_stream.data == engine_data, "audio.engine_pcm_unchanged_across_commits")
	d.check(tire_stream.data == tire_data, "audio.tire_pcm_unchanged_across_commits")
	d.check(player.get_child_count() == 2, "audio.still_exactly_two_voices_after_commits")
	d.check(
		d.count_class_instances(get_tree().root, "AudioStreamPlayer") == 2,
		"audio.no_duplicate_voices_after_commits"
	)
	measurements["audio_final_speed_m_s"] = lab.state.speed_m_s()
	measurements["audio_final_pitch"] = last_pitch
	measurements["audio_final_engine_db"] = last_engine_db
	measurements["audio_oracle_mismatches"] = oracle_mismatches
	await _teardown_lab(lab)


func _audio_adapter_refusal_checks() -> void:
	var commands: Array = []
	for _index in range(AUDIO_REFUSAL_HEAD_TICKS):
		commands.append(d.throttle_command(1.0))
	commands.append(null)
	for _index in range(10):
		commands.append(d.throttle_command(1.0))
	var lab = _make_lab(commands)
	if lab == null:
		return
	await _settle()
	var player = lab.get_feedback_player()
	if player == null:
		d.check(false, "audio.refusal.fixture_ready")
		await _teardown_lab(lab)
		return
	lab.start()
	var guard := 0
	while (
		int(lab.ticks_committed) < AUDIO_REFUSAL_HEAD_TICKS
		and guard < 400
		and not lab.failed
	):
		await get_tree().physics_frame
		guard += 1
	var head_telemetry: Dictionary = lab.get_audio_telemetry()
	var updates_at_head := int(head_telemetry["audio_updates"])
	var attempts_at_head := int(head_telemetry["audio_apply_attempts"])
	var rejected_at_head := int(head_telemetry["audio_rejected_updates"])
	var pitch_at_head: float = player.get_last_engine_pitch_scale()
	var engine_db_at_head: float = player.get_last_engine_volume_db()
	var tire_db_at_head: float = player.get_last_tire_volume_db()
	while not lab.failed and guard < 800:
		await get_tree().physics_frame
		guard += 1
	d.check(lab.failed, "audio.refusal.adapter_refusal_detected")
	d.check(str(lab.failure_reason) != "", "audio.refusal.reason_reported")
	d.check(int(lab.ticks_committed) == AUDIO_REFUSAL_HEAD_TICKS, "audio.refusal.committed_before_refusal")
	d.check(int(lab.steps_called) == AUDIO_REFUSAL_HEAD_TICKS + 1, "audio.refusal.one_refused_step")
	var after_telemetry: Dictionary = lab.get_audio_telemetry()
	d.check(int(after_telemetry["audio_updates"]) == updates_at_head, "audio.refusal.no_apply_after_refusal")
	d.check(
		int(after_telemetry["audio_apply_attempts"]) == attempts_at_head,
		"audio.refusal.no_apply_attempt_after_refusal"
	)
	d.check(
		int(after_telemetry["audio_rejected_updates"]) == rejected_at_head,
		"audio.refusal.rejection_counter_unchanged"
	)
	d.check(
		int(after_telemetry["audio_updates"]) == AUDIO_REFUSAL_HEAD_TICKS,
		"audio.refusal.updates_equal_committed_ticks"
	)
	d.check(
		int(after_telemetry["audio_apply_attempts"]) == AUDIO_REFUSAL_HEAD_TICKS,
		"audio.refusal.attempts_equal_committed_ticks"
	)
	d.check(player.get_last_engine_pitch_scale() == pitch_at_head, "audio.refusal.engine_pitch_unchanged")
	d.check(player.get_last_engine_volume_db() == engine_db_at_head, "audio.refusal.engine_gain_unchanged")
	d.check(player.get_last_tire_volume_db() == tire_db_at_head, "audio.refusal.tire_gain_unchanged")
	d.check(str(after_telemetry["audio_error"]).is_empty(), "audio.refusal.no_apply_error")
	if not lab.tick_log.is_empty():
		var last: Dictionary = lab.tick_log[-1]
		d.check(lab.state.position_m == last["position_m"], "audio.refusal.state_unchanged")
		d.check(lab.body.global_transform == last["body_transform"], "audio.refusal.body_unchanged")
	await _teardown_lab(lab)


func _audio_apply_refusal_checks() -> void:
	var commands: Array = []
	for _index in range(5):
		commands.append(d.throttle_command(1.0))
	var lab = _make_lab(commands)
	if lab == null:
		return
	if not _audio_api_available(lab):
		await _teardown_lab(lab)
		return
	await _settle()
	var player = lab.get_feedback_player()
	if player == null or not player.is_setup_complete():
		d.check(false, "audio.apply_refusal.fixture_ready")
		await _teardown_lab(lab)
		return
	player.teardown()
	d.check(not player.is_setup_complete(), "audio.apply_refusal.setup_torn_down")
	lab.set_auto_tick(false)
	var steps_before := int(lab.steps_called)
	var result = lab.step_once(d.throttle_command(1.0))
	d.check(
		result != null and int(result.status) == int(AdapterScript.Status.COMMITTED),
		"audio.apply_refusal.simulation_still_commits"
	)
	d.check(int(lab.steps_called) == steps_before + 1, "audio.apply_refusal.one_step")
	d.check(not lab.failed, "audio.apply_refusal.audio_refusal_does_not_fail_simulation")
	var telemetry: Dictionary = lab.get_audio_telemetry()
	d.check(int(telemetry["audio_apply_attempts"]) == 1, "audio.apply_refusal.attempt_counted")
	d.check(int(telemetry["audio_updates"]) == 0, "audio.apply_refusal.no_successful_update")
	d.check(int(telemetry["audio_rejected_updates"]) == 1, "audio.apply_refusal.refusal_counted")
	d.check(not str(telemetry["audio_error"]).is_empty(), "audio.apply_refusal.reason_recorded")
	d.check(not player.get_last_error().is_empty(), "audio.apply_refusal.component_reason_present")
	d.check(not lab.is_audio_ready(), "audio.apply_refusal.ready_flag_clears")
	var second = lab.step_once(d.throttle_command(1.0))
	d.check(
		second != null and int(second.status) == int(AdapterScript.Status.COMMITTED),
		"audio.apply_refusal.second_tick_still_commits"
	)
	var second_telemetry: Dictionary = lab.get_audio_telemetry()
	d.check(int(second_telemetry["audio_rejected_updates"]) == 2, "audio.apply_refusal.refusals_accumulate")
	d.check(int(lab.ticks_committed) == 2, "audio.apply_refusal.simulation_commits_unaffected")
	# Restoring the component's own lifecycle creates its two voices again; the
	# laboratory must not have built a duplicate alongside them.
	var restored: bool = player.setup()
	d.check(restored and player.is_setup_complete(), "audio.apply_refusal.setup_can_be_restored")
	d.check(player.get_child_count() == 2, "audio.apply_refusal.restored_voice_count")
	d.check(
		d.count_class_instances(get_tree().root, "AudioStreamPlayer") == 2,
		"audio.apply_refusal.no_duplicate_voices_after_restore"
	)
	await _teardown_lab(lab)


func _audio_reconfigure_and_trace_checks() -> void:
	var first_commands: Array = []
	for _index in range(5):
		first_commands.append(d.idle_command())
	var lab = _make_lab(first_commands)
	if lab == null:
		return
	await _settle()
	var first_run := await _run_auto(lab, first_commands.size())
	d.check(int(first_run["committed"]) == first_commands.size(), "audio.reconfigure.first_schedule_ran")
	var player = lab.get_feedback_player()
	var first_telemetry: Dictionary = lab.get_audio_telemetry()
	d.check(int(first_telemetry["audio_updates"]) == first_commands.size(), "audio.reconfigure.first_updates")

	var trace_commands: Array = []
	for _index in range(AUDIO_BASELINE_TICKS):
		trace_commands.append(d.throttle_command(1.0))
	var reconfigured: bool = lab.configure(lab.tuning, lab.adapter_config, trace_commands)
	d.check(reconfigured, "audio.reconfigure.second_configure_accepted")
	d.check(lab.get_feedback_player() == player, "audio.reconfigure.same_component_kept")
	d.check(
		d.count_script_instances(get_tree().root, FeedbackScript) == 1,
		"audio.reconfigure.exactly_one_component"
	)
	d.check(
		d.count_class_instances(get_tree().root, "AudioStreamPlayer") == 2,
		"audio.reconfigure.exactly_two_voices"
	)
	d.check(player.get_child_count() == 2, "audio.reconfigure.component_keeps_two_children")
	var reset_telemetry: Dictionary = lab.get_audio_telemetry()
	d.check(int(reset_telemetry["audio_updates"]) == 0, "audio.reconfigure.update_counter_reset")
	d.check(int(reset_telemetry["audio_apply_attempts"]) == 0, "audio.reconfigure.attempt_counter_reset")
	d.check(int(reset_telemetry["audio_rejected_updates"]) == 0, "audio.reconfigure.rejection_counter_reset")
	d.check(str(reset_telemetry["audio_error"]).is_empty(), "audio.reconfigure.error_cleared")

	var second_run := await _run_auto(lab, AUDIO_BASELINE_TICKS)
	d.check(not lab.failed, "audio.reconfigure.second_run_not_failed: " + str(lab.failure_reason))
	d.check(int(second_run["committed"]) == AUDIO_BASELINE_TICKS, "audio.reconfigure.second_schedule_committed")
	var second_telemetry: Dictionary = lab.get_audio_telemetry()
	d.check(
		int(second_telemetry["audio_updates"]) == AUDIO_BASELINE_TICKS,
		"audio.reconfigure.second_updates_equal_commits"
	)
	d.check(int(second_telemetry["audio_rejected_updates"]) == 0, "audio.reconfigure.second_no_refusals")

	d.check(not _baseline_trace.is_empty(), "audio.trace.baseline_present")
	if not _baseline_trace.is_empty():
		d.check(lab.tick_log.size() == _baseline_trace.size(), "audio.trace.entry_count_matches_baseline")
		var mismatches := 0
		for index in range(mini(lab.tick_log.size(), _baseline_trace.size())):
			var record: Dictionary = lab.tick_log[index]
			var baseline: Dictionary = _baseline_trace[index]
			if record["position_m"] != baseline["position_m"]:
				mismatches += 1
			if record["velocity_m_s"] != baseline["velocity_m_s"]:
				mismatches += 1
			if record["heading_rad"] != baseline["heading_rad"]:
				mismatches += 1
			if record["body_transform"] != baseline["body_transform"]:
				mismatches += 1
		d.check(
			mismatches == 0,
			"audio.trace.bit_identical_to_audio_enabled_baseline (mismatches=%d)" % mismatches
		)
		measurements["audio_trace_mismatches"] = mismatches
	measurements["audio_trace_entries"] = lab.tick_log.size()

	await _teardown_lab(lab)
	d.check(not is_instance_valid(player), "audio.teardown.component_freed")
	d.check(
		d.count_script_instances(get_tree().root, FeedbackScript) == 0,
		"audio.teardown.no_component_left_in_tree"
	)
	d.check(
		d.count_class_instances(get_tree().root, "AudioStreamPlayer") == 0,
		"audio.teardown.no_voices_left_in_tree"
	)


## Independent playback-target oracle mirroring the committed component's
## documented provisional coefficients. Validation compares measured values
## against these formulas rather than trusting the component under test.
func feedback_oracle_pitch(speed_m_s: float, throttle: float) -> float:
	var speed_norm := clampf(speed_m_s / FEEDBACK_SPEED_FULL_M_S, 0.0, 1.0)
	var fundamental := (
		FEEDBACK_IDLE_HZ
		* pow(FEEDBACK_TOP_HZ / FEEDBACK_IDLE_HZ, speed_norm)
		* (1.0 + FEEDBACK_THROTTLE_PITCH_LIFT * throttle)
	)
	var reference := FEEDBACK_TOP_HZ * (1.0 + FEEDBACK_THROTTLE_PITCH_LIFT)
	return clampf(
		fundamental / reference,
		FeedbackScript.MIN_PITCH_SCALE,
		FeedbackScript.MAX_PITCH_SCALE
	)


func feedback_oracle_engine_db(speed_m_s: float, throttle: float) -> float:
	var speed_norm := clampf(speed_m_s / FEEDBACK_SPEED_FULL_M_S, 0.0, 1.0)
	var drive := clampf(
		FEEDBACK_LEVEL_SPEED_WEIGHT * speed_norm
		+ FEEDBACK_LEVEL_THROTTLE_WEIGHT * throttle,
		0.0, 1.0
	)
	var level := FEEDBACK_IDLE_LEVEL + (1.0 - FEEDBACK_IDLE_LEVEL) * drive
	return clampf(
		linear_to_db(maxf(level, 1.0e-4)),
		FeedbackScript.MIN_VOLUME_DB,
		FeedbackScript.MAX_VOLUME_DB
	)


func feedback_oracle_tire_db(slip_deg: float, speed_m_s: float, grounded: bool) -> float:
	if not grounded:
		return FEEDBACK_SILENCE_DB
	var threshold_norm := clampf(
		FEEDBACK_TIRE_SLIP_THRESHOLD_DEG / FEEDBACK_TIRE_SLIP_FULL_DEG, 0.0, 1.0
	)
	var slip_norm := clampf(absf(slip_deg) / FEEDBACK_TIRE_SLIP_FULL_DEG, 0.0, 1.0)
	var speed_factor := clampf(
		(speed_m_s - FEEDBACK_TIRE_MIN_SPEED_M_S)
		/ (FEEDBACK_TIRE_REFERENCE_SPEED_M_S - FEEDBACK_TIRE_MIN_SPEED_M_S),
		0.0, 1.0
	)
	var intensity := smoothstep(threshold_norm, 1.0, slip_norm) * speed_factor
	return clampf(
		linear_to_db(maxf(intensity, 1.0e-4)),
		FeedbackScript.MIN_VOLUME_DB,
		FeedbackScript.MAX_VOLUME_DB
	)


# --- Bounded waits and synthetic input -------------------------------------


func _deliver_key(keycode: Key, pressed: bool, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)


func _await_input_events(count: int, limit: int) -> bool:
	var waited := 0
	while waited < limit and _input_probe.events.size() < count:
		await get_tree().physics_frame
		waited += 1
	return _input_probe.events.size() >= count


func _await_camera_mode_name(lab, name: String, limit: int) -> bool:
	var waited := 0
	while waited < limit and lab.get_camera_mode_name() != name:
		await get_tree().physics_frame
		waited += 1
	return lab.get_camera_mode_name() == name


func _await_rear_view(lab, held: bool, limit: int) -> bool:
	var waited := 0
	while waited < limit and lab.is_rear_view_held() != held:
		await get_tree().physics_frame
		waited += 1
	return lab.is_rear_view_held() == held
