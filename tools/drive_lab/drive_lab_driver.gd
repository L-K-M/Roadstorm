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
const SynthScript := preload("res://src/audio/vehicle_feedback_synth.gd")
const GearboxScript := preload("res://src/simulation/automatic_gearbox.gd")
const ImpactEventScript := preload("res://src/simulation/impact_event.gd")

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
## Bounded tick counts for the M1.5 gear-readout regression: enough throttle
## to reach at least second gear, then enough brake to engage the reverse latch.
const PRESENTATION_GEAR_THROTTLE_TICKS := 120
const PRESENTATION_GEAR_BRAKE_TICKS := 150
## Bounded wait for both the forward shift and the reverse latch.
const PRESENTATION_GEAR_WAIT_FRAMES := 400
## Bounded tick counts for the M1.5 audio feedback integration case.
const AUDIO_TICKS := 60
const AUDIO_REFUSAL_HEAD_TICKS := 10
## Brake-only ticks for the straight-reverse tire-slip regression. The first
## ticks satisfy the design reverse hold; the remainder reverses in a straight
## line, where direction-relative tire slip must stay silent.
const AUDIO_REVERSE_TICKS := 80
## Brake ticks that engage reverse and build enough backward speed for the
## latch-clear coast regression; the released-brake ticks then clear the latch
## while the car is still rolling backwards.
const AUDIO_LATCH_CLEAR_BRAKE_TICKS := 90
const AUDIO_LATCH_CLEAR_COAST_TICKS := 15
## Synthetic oblique backward pose pinned against the committed synth and
## playback mapping. It is a documented geometry input, not a claim that the
## laboratory can reach it by driving.
const AUDIO_OBLIQUE_BACKWARD_SLIP_DEG := 20.0
const AUDIO_OBLIQUE_BACKWARD_SPEED_M_S := 30.0
## Must match the movement_from_rest schedule used as the committed-trace
## baseline; the audio case replays it with audio wired.
const AUDIO_BASELINE_TICKS := 90
## Bounded tick counts for the M1.1 gearbox integration case.
const GEARBOX_FORWARD_TICKS := 300
const GEARBOX_BRAKE_TICKS := 120
const GEARBOX_EVENT_GAP_TICKS := 10
const GEARBOX_REVERSE_THROTTLE_TICKS := 60
const GEARBOX_REVERSE_BRAKE_TICKS := 90
const GEARBOX_COAST_TICKS := 20
const GEARBOX_FORWARD_RESUME_TICKS := 60
const GEARBOX_SNAPSHOT_TICKS := 120
const GEARBOX_TRACE_TICKS := 90
const GEARBOX_RECONFIG_IDLE_TICKS := 5
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
## A right-angle bay makes the raw road-y station differ maximally from the
## projected authored-axis station.
const ROTATED_SPAWN_YAW_90_DEG := 90.0
const ROTATED_SPAWN_ORIGIN := Vector3(-360.0, 0.0, 60.0)
## Bounded throttle ticks proving the rotated car tracks its authored forward.
const ROTATED_SPAWN_TICKS := 30
## Synthetic stations used to pin the authored-axis projection and both course
## limits without driving an adapter tick from each probe pose.
const ROTATED_SPAWN_FORWARD_STATION_M := 12.5
const ROTATED_SPAWN_REVERSE_STATION_M := -4.0
const ROTATED_SPAWN_LIMIT_EPSILON_M := 1e-3
## M1.8 wall-impact regression fixture. The authored handling-lab contact bay
## is a 500 m straight whose frontal barrier stands at s=480 m (near face at
## 479.75 m). The fixture relocates the laboratory spawn onto that bay's
## approach and stages a longer course specification so the 40 m course-end
## margin cannot halt the car before the authored wall.
const WALL_BAY_ORIGIN := Vector3(-200.0, 0.0, 60.0)
const WALL_FACE_ROAD_Y_M := 419.75
const WALL_SPAWN_ROAD_POSITION := Vector2(-200.0, 390.0)
const WALL_COURSE_LENGTH_M := 600.0
const WALL_MAX_TICKS := 600
const WALL_VECTOR_TOLERANCE_M := 1e-5
const WALL_LOCAL_TOLERANCE_M := 1e-5
const WALL_NORMAL_TOLERANCE := 1e-5
const WALL_SEVERITY_TOLERANCE_M_S := 1e-5

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
	"gearbox_integration",
	"wall_impact_integration",
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


## Test-only gearbox that forces the two post-COMMITTED refusal paths.
## Validation swaps it into a laboratory so recovery behavior is exercised
## without adding a production fault hook; it copies the real configuration and
## current canonical state, then overrides only the failing step.
class GearboxFaultInjector extends AutomaticGearbox:
	var fault := ""

	func _init(config: AutomaticGearbox.GearboxConfig, fault_name: String) -> void:
		_forward_gear_count = config.forward_gear_count
		_upshifts = config.upshift_speeds_m_s.duplicate()
		_downshifts = config.downshift_speeds_m_s.duplicate()
		_min_shift_dwell_s = config.min_shift_dwell_s
		_reverse_exit_forward_speed_m_s = config.reverse_exit_forward_speed_m_s
		_top_reference_speed_m_s = config.top_reference_speed_m_s
		reset()
		fault = fault_name

	func propose(car_state, dt: float = 1.0 / 60.0):
		if fault == "proposal_refused":
			return null
		return super.propose(car_state, dt)

	func mirror_gear(car_state):
		if fault == "mirror_refused":
			return null
		return super.mirror_gear(car_state)


## Test-only gearbox that refuses a proposal once the committed road-y pose
## reaches a threshold. The wall-impact case arms it on the tick that must
## reach the authored barrier, proving no event is published when the
## canonical gearbox/CarState pair cannot be published.
class GearboxPositionFaultInjector extends AutomaticGearbox:
	var _position_y_threshold_m := INF

	func _init(
		config: AutomaticGearbox.GearboxConfig, position_y_threshold_m: float
	) -> void:
		_forward_gear_count = config.forward_gear_count
		_upshifts = config.upshift_speeds_m_s.duplicate()
		_downshifts = config.downshift_speeds_m_s.duplicate()
		_min_shift_dwell_s = config.min_shift_dwell_s
		_reverse_exit_forward_speed_m_s = config.reverse_exit_forward_speed_m_s
		_top_reference_speed_m_s = config.top_reference_speed_m_s
		reset()
		_position_y_threshold_m = position_y_threshold_m

	func propose(car_state, dt: float = 1.0 / 60.0):
		if car_state != null and car_state.position_m.y >= _position_y_threshold_m:
			return null
		return super.propose(car_state, dt)


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
		"gearbox_integration":
			await _case_gearbox_integration()
		"wall_impact_integration":
			await _case_wall_impact_integration()
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
	await _rotated_spawn_variant("marker", true, ROTATED_SPAWN_YAW_DEG)
	await _rotated_spawn_variant("manifest_fallback", false, ROTATED_SPAWN_YAW_DEG)
	await _rotated_spawn_variant("marker_right_angle", true, ROTATED_SPAWN_YAW_90_DEG)
	await _rotated_spawn_zero_control()


func _rotated_spawn_variant(label: String, use_marker: bool, yaw_deg: float) -> void:
	var commands: Array = []
	for _index in range(ROTATED_SPAWN_TICKS):
		commands.append(d.throttle_command(1.0))
	var lab = _make_real_geometry_lab(yaw_deg, use_marker, commands)
	if lab == null:
		return
	await _settle()
	var authored_heading := deg_to_rad(yaw_deg)
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
	_rotated_station_and_limit_checks(lab, label, builder_forward)
	measurements[label + "_state_heading_rad"] = lab.state.heading_rad
	measurements[label + "_builder_forward"] = str(builder_forward)
	await _teardown_lab(lab)


## Pins the authored-axis station projection and both course limits for a
## rotated spawn. The station probes place the committed state directly on the
## authored axis; the limit probes query the same predicate `step_once()` gates
## on, then confirm one projected-limit halt consumes no adapter call.
func _rotated_station_and_limit_checks(lab, label: String, builder_forward: Vector3) -> void:
	var axis := Vector2(builder_forward.x, -builder_forward.z)
	var half_length: float = lab.hull_shape.size.z * 0.5
	lab.state.position_m = lab.start_position_m + axis * ROTATED_SPAWN_FORWARD_STATION_M
	d.check_close(
		lab.get_road_station_m(), ROTATED_SPAWN_FORWARD_STATION_M, 1e-4,
		label + ".station_projects_positive_authored_axis"
	)
	lab.state.position_m = lab.start_position_m + axis * ROTATED_SPAWN_REVERSE_STATION_M
	d.check_close(
		lab.get_road_station_m(), ROTATED_SPAWN_REVERSE_STATION_M, 1e-4,
		label + ".station_projects_negative_authored_axis"
	)
	# The old axis-locked arithmetic reads raw road y. At this yaw that differs
	# from the projected station, so these checks fail against the old code.
	var raw_road_y_station: float = lab.state.position_m.y - lab.start_position_m.y
	d.check(
		absf(raw_road_y_station - ROTATED_SPAWN_REVERSE_STATION_M) > 1e-3,
		label + ".raw_road_y_differs_from_projected_station"
	)

	var end_station := 500.0 - DriveLabScript.COURSE_END_MARGIN_M - half_length
	lab.state.position_m = lab.start_position_m + axis * (end_station + ROTATED_SPAWN_LIMIT_EPSILON_M)
	d.check(lab.is_course_limit_reached(), label + ".end_limit_true_on_projected_station")
	lab.state.position_m = lab.start_position_m + axis * (end_station - ROTATED_SPAWN_LIMIT_EPSILON_M)
	d.check(not lab.is_course_limit_reached(), label + ".end_limit_false_just_before")

	var reverse_station := -DriveLabScript.COURSE_START_MARGIN_M + half_length
	lab.state.position_m = lab.start_position_m + axis * (reverse_station - ROTATED_SPAWN_LIMIT_EPSILON_M)
	d.check(lab.is_course_limit_reached(), label + ".reverse_limit_true_on_projected_station")
	lab.state.position_m = lab.start_position_m + axis * (reverse_station + ROTATED_SPAWN_LIMIT_EPSILON_M)
	d.check(not lab.is_course_limit_reached(), label + ".reverse_limit_false_just_after")

	lab.state.position_m = lab.start_position_m + axis * (end_station + ROTATED_SPAWN_LIMIT_EPSILON_M)
	var steps_before := int(lab.steps_called)
	var result = lab.step_once(d.idle_command())
	d.check(result == null, label + ".end_limit_step_returns_null")
	d.check(
		lab.halted and lab.halt_reason == "course limit reached",
		label + ".end_limit_halts_on_projected_station"
	)
	d.check(int(lab.steps_called) == steps_before, label + ".end_limit_consumes_no_adapter_call")


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


## Builds a DriveLab on the authored contact bay's 500 m straight so its
## frontal wall can be reached under the laboratory's own tick path. The
## handling-lab builder output is real and unchanged except for two explicit
## test-fixture fields: the staged straight-bay origin points at the contact
## approach (the car otherwise spawns on the disjoint plain straight), and the
## staged straight length is extended so the 40 m course-end margin does not
## halt the car before the authored barrier. No wall, road or collider is
## invented; the collision is the committed Jolt response against the built
## `wall_frontal` body.
func _make_wall_hit_lab(commands: Array):
	var lab = DriveLabScript.new()
	lab.name = "DriveLab"
	var handling := Node3D.new()
	handling.name = "HandlingLab"
	var manifest: Dictionary = HandlingLabBuilderScript.build(handling)
	for bay in manifest.get("bays", []):
		if String(bay.get("bay_id", "")) == "straight":
			bay["origin"] = WALL_BAY_ORIGIN
			bay["yaw_deg"] = 0.0
			for section in bay.get("sections", []):
				if String(section.get("section_id", "")) == "straight.main":
					section["length_m"] = WALL_COURSE_LENGTH_M
	# Remove the builder's authored straight marker so the manifest fallback
	# above is the only spawn input; leaving it would pin the car to the plain
	# straight 160 m away from this wall.
	var marker := handling.get_node_or_null("Spawn_straight")
	if marker != null:
		handling.remove_child(marker)
		marker.free()
	handling.set_meta("lab_manifest", manifest)
	var configured: bool = lab.configure(d.make_tuning(), d.make_config(), commands)
	d.check(configured, "wall.fixture.configure_accepted")
	lab.add_child(handling)
	_holder.add_child(lab)
	return lab


## Places the staged car at the fixture spawn station, preserving the support
## height already resolved by the laboratory pose. Road y maps to world -z at
## zero heading.
func _place_wall_lab_at_spawn(lab) -> void:
	var support_y: float = lab.body.global_transform.origin.y
	var spawn := WALL_SPAWN_ROAD_POSITION
	lab.start_position_m = spawn
	lab.state.position_m = spawn
	lab.body.global_transform = Transform3D(
		AdapterScript.basis_from_heading(0.0),
		Vector3(spawn.x, support_y, -spawn.y)
	)


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
	# A zero-yaw spawn keeps the original road-y arithmetic exactly.
	var half_length: float = lab.hull_shape.size.z * 0.5
	lab.state.position_m = lab.start_position_m + Vector2(1.5, -7.25)
	d.check_exact_float(
		lab.get_road_station_m(),
		lab.state.position_m.y - lab.start_position_m.y,
		"rotated.zero_yaw_station_is_raw_road_y_difference"
	)
	var end_station := 500.0 - DriveLabScript.COURSE_END_MARGIN_M - half_length
	lab.state.position_m = lab.start_position_m + Vector2(0.0, end_station + ROTATED_SPAWN_LIMIT_EPSILON_M)
	d.check(lab.is_course_limit_reached(), "rotated.zero_yaw_end_limit_still_on_road_y")
	lab.state.position_m = lab.start_position_m + Vector2(0.0, end_station - ROTATED_SPAWN_LIMIT_EPSILON_M)
	d.check(not lab.is_course_limit_reached(), "rotated.zero_yaw_end_limit_open_just_before")
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
	var station: float = lab.get_road_station_m()
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
		if lab.tick_log.is_empty():
			break
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
	await _presentation_gear_readout_checks()


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
	d.check(
		d.hud_label_text(hud, "GearLabel") == str(int(lab.state.gear_index)),
		"hud.gear_label_mirrors_committed_gear"
	)
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


## M1.5 gear-readout integration: the actual `Contents/GearLabel` text must
## mirror the published `CarState.gear_index` after a real forward shift and
## after the reverse latch. This reads the committed label node headlessly; it
## proves behavior only, not rendered readability or layout.
func _presentation_gear_readout_checks() -> void:
	var commands: Array = []
	for _index in range(PRESENTATION_GEAR_THROTTLE_TICKS):
		commands.append(d.throttle_command(1.0))
	for _index in range(PRESENTATION_GEAR_BRAKE_TICKS):
		commands.append(d.brake_command(1.0))
	var lab = _make_lab(commands)
	if lab == null:
		return
	if not _presentation_api_available(lab):
		await _teardown_lab(lab)
		return
	var hud: SpeedHud = lab.get_speed_hud()
	if hud == null:
		d.check(false, "hud.gear.instance_present")
		await _teardown_lab(lab)
		return
	d.check(
		d.hud_label_text(hud, "GearLabel") == "1",
		"hud.gear.initial_first_gear"
	)
	lab.set_auto_tick(true)
	lab.start()
	var guard := 0
	var forward_gear := 0
	var saw_reverse_latch := false
	while guard < PRESENTATION_GEAR_WAIT_FRAMES \
			and not lab.failed and not lab.halted:
		await get_tree().physics_frame
		guard += 1
		var gear := int(lab.state.gear_index)
		if forward_gear == 0 and gear >= 2:
			forward_gear = gear
			d.check(
				d.hud_label_text(hud, "GearLabel") == str(gear),
				"hud.gear.forward_label_mirrors_committed_gear (gear=%d)" % gear
			)
			d.check(
				d.hud_label_text(hud, "SpeedLabel")
					== str(int(round(lab.state.speed_m_s() * KMH_PER_M_S))),
				"hud.gear.forward_speed_still_mirrors_committed_state"
			)
		if lab.state.reverse_engaged:
			saw_reverse_latch = true
			d.check(gear == -1, "hud.gear.reverse_latch_publishes_reverse_gear")
			d.check(
				d.hud_label_text(hud, "GearLabel") == "R",
				"hud.gear.reverse_label_mirrors_committed_gear"
			)
			break
	d.check(forward_gear >= 2, "hud.gear.forward_shift_observed (gear=%d)" % forward_gear)
	d.check(saw_reverse_latch, "hud.gear.reverse_latch_observed")
	d.check(not lab.failed, "hud.gear.run_not_failed: " + str(lab.failure_reason))
	measurements["hud_forward_gear"] = forward_gear
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
	await _audio_straight_reverse_checks()
	await _audio_adapter_refusal_checks()
	await _audio_apply_refusal_checks()
	await _audio_reconfigure_and_trace_checks()
	await _audio_backward_geometry_checks()


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
			lab.state.velocity_m_s, lab.state.heading_rad, lab.state.grounded
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
		feedback_oracle_tire_db(
			lab.state.velocity_m_s, lab.state.heading_rad, lab.state.grounded
		),
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


## Straight-line reverse regression for the direction-relative tire-slip fix.
## A car reversing straight has a raw nose-to-travel angle near +/-180 deg;
## the committed component must fold that into the travel frame so tire scrub
## stays silent instead of saturating. The old `abs(slip)` formula predicted an
## audible level here, which this case records as a broken-behavior control.
func _audio_straight_reverse_checks() -> void:
	var commands: Array = []
	for _index in range(AUDIO_REVERSE_TICKS):
		commands.append(d.brake_command(1.0))
	var lab = _make_lab(commands)
	if lab == null:
		return
	if not _audio_api_available(lab):
		await _teardown_lab(lab)
		return
	await _settle()
	var player = lab.get_feedback_player()
	if player == null:
		d.check(false, "audio.reverse.fixture_ready")
		await _teardown_lab(lab)
		return
	lab.start()
	var last_tire_db := 0.0
	for _index in range(AUDIO_REVERSE_TICKS):
		await get_tree().physics_frame
		if lab.failed:
			break
		var telemetry: Dictionary = lab.get_audio_telemetry()
		last_tire_db = float(telemetry["last_tire_volume_db"])
	d.check(not lab.failed, "audio.reverse.run_not_failed: " + str(lab.failure_reason))
	d.check(lab.state != null, "audio.reverse.final_state_present")
	if lab.state == null:
		await _teardown_lab(lab)
		return
	d.check(lab.state.reverse_engaged, "audio.reverse.reverse_latch_engaged")
	var forward_speed: float = lab.state.forward_speed_m_s()
	d.check(forward_speed < 0.0, "audio.reverse.travelling_backwards")
	var raw_slip: float = lab.state.slip_deg()
	var relative_slip := feedback_oracle_travel_relative_slip_deg(
		lab.state.velocity_m_s, lab.state.heading_rad
	)
	var expected_tire_db := feedback_oracle_tire_db(
		lab.state.velocity_m_s, lab.state.heading_rad, lab.state.grounded
	)
	# Broken-behavior control: the pre-fix abs(slip) map would have produced an
	# audible tire level in this straight reversal.
	var old_formula_db := feedback_oracle_tire_db_from_abs_nose_slip(
		raw_slip, lab.state.speed_m_s(), lab.state.grounded
	)
	d.check(
		old_formula_db > FEEDBACK_SILENCE_DB + 1.0,
		"audio.reverse.old_formula_predicts_audible_tires (db=%f)" % old_formula_db
	)
	d.check(
		last_tire_db <= FEEDBACK_SILENCE_DB + 1e-3,
		"audio.reverse.straight_reverse_tires_silent (db=%f)" % last_tire_db
	)
	d.check_close(
		last_tire_db, expected_tire_db, 1e-6,
		"audio.reverse.matches_direction_relative_oracle"
	)
	d.check(
		int(lab.get_audio_telemetry()["audio_updates"]) == int(lab.ticks_committed),
		"audio.reverse.one_update_per_committed_tick"
	)
	measurements["audio_reverse_forward_speed_m_s"] = forward_speed
	measurements["audio_reverse_raw_slip_deg"] = raw_slip
	measurements["audio_reverse_travel_relative_slip_deg"] = relative_slip
	measurements["audio_reverse_measured_tire_db"] = last_tire_db
	measurements["audio_reverse_old_formula_tire_db"] = old_formula_db
	await _teardown_lab(lab)


## Focused regression for the direction-relative tire oracle in the regime the
## reverse latch cannot identify: a car still rolling backwards after the latch
## clears, and an oblique backward travel direction. The first part drives the
## real motor through a reverse engagement and releases the brake; the second
## pins a synthetic oblique backward pose against the committed synth and
## playback mapping. The pose is a documented geometry input, not a claim that
## this laboratory can reach it by driving.
func _audio_backward_geometry_checks() -> void:
	var commands: Array = []
	for _index in range(AUDIO_LATCH_CLEAR_BRAKE_TICKS):
		commands.append(d.brake_command(1.0))
	for _index in range(AUDIO_LATCH_CLEAR_COAST_TICKS):
		commands.append(d.idle_command())
	var lab = _make_lab(commands)
	if lab == null:
		return
	if not _audio_api_available(lab):
		await _teardown_lab(lab)
		return
	await _settle()
	var player = lab.get_feedback_player()
	if player == null:
		d.check(false, "audio.backward_geometry.fixture_ready")
		await _teardown_lab(lab)
		return
	lab.start()
	var last_tire_db := 0.0
	for index in range(commands.size()):
		await get_tree().physics_frame
		if lab.failed:
			break
		if index >= AUDIO_LATCH_CLEAR_BRAKE_TICKS:
			last_tire_db = float(lab.get_audio_telemetry()["last_tire_volume_db"])
	d.check(not lab.failed, "audio.backward_geometry.run_not_failed: " + str(lab.failure_reason))
	d.check(
		int(lab.ticks_committed) == commands.size(),
		"audio.backward_geometry.all_ticks_committed"
	)
	d.check(lab.state != null, "audio.backward_geometry.final_state_present")
	if lab.state == null:
		await _teardown_lab(lab)
		return
	var state = lab.state
	d.check(not state.reverse_engaged, "audio.backward_geometry.reverse_latch_cleared")
	var forward_speed: float = state.forward_speed_m_s()
	d.check(forward_speed < 0.0, "audio.backward_geometry.still_travelling_backwards")
	var raw_slip: float = state.slip_deg()
	d.check(
		absf(raw_slip) > 145.0,
		"audio.backward_geometry.raw_nose_slip_in_divergent_regime (slip=%f)" % raw_slip
	)
	var oracle_slip := feedback_oracle_travel_relative_slip_deg(
		state.velocity_m_s, state.heading_rad
	)
	var synth_slip := SynthScript.direction_relative_slip_deg(
		state.velocity_m_s, state.heading_rad
	)
	d.check_close(
		oracle_slip, synth_slip, 1e-9,
		"audio.backward_geometry.coast_oracle_matches_synth_geometry"
	)
	d.check(
		oracle_slip < 1.0,
		"audio.backward_geometry.coast_reads_straight_travel (slip=%f)" % oracle_slip
	)
	var command := d.idle_command()
	var coast_bundle := SynthScript.render_bundle(state, command, 41)
	d.check(coast_bundle.get("valid") == true, "audio.backward_geometry.coast_bundle_valid")
	if coast_bundle.get("valid") == true:
		d.check_close(
			float(coast_bundle["telemetry"]["tire_slip_deg"]), oracle_slip, 1e-6,
			"audio.backward_geometry.coast_synth_telemetry_matches_oracle"
		)
		var coast_segment = coast_bundle["tire"]
		d.check(
			float(coast_segment.metadata["intensity"]) <= 1e-12,
			"audio.backward_geometry.coast_synth_intensity_zero"
		)
		d.check(
			coast_segment.rms_amplitude <= 1e-12,
			"audio.backward_geometry.coast_synth_pcm_silent"
		)
	var coast_oracle_db := feedback_oracle_tire_db(
		state.velocity_m_s, state.heading_rad, state.grounded
	)
	var old_formula_db := feedback_oracle_tire_db_from_abs_nose_slip(
		raw_slip, state.speed_m_s(), state.grounded
	)
	d.check(
		last_tire_db <= FEEDBACK_SILENCE_DB + 1e-3,
		"audio.backward_geometry.coast_player_tires_silent (db=%f)" % last_tire_db
	)
	d.check_close(
		last_tire_db, coast_oracle_db, 1e-6,
		"audio.backward_geometry.coast_player_matches_oracle"
	)
	d.check(
		old_formula_db > FEEDBACK_SILENCE_DB + 1.0,
		"audio.backward_geometry.coast_old_formula_predicts_audible_tires (db=%f)" % old_formula_db
	)

	# Synthetic oblique backward pose: travel 20 deg off the nose line while
	# moving backwards. The pre-fix latch-gated fold would leave the raw signed
	# angle near 160 deg and saturate the map.
	var drift_rad := deg_to_rad(AUDIO_OBLIQUE_BACKWARD_SLIP_DEG)
	var oblique_velocity := Vector2(
		sin(drift_rad) * AUDIO_OBLIQUE_BACKWARD_SPEED_M_S,
		-cos(drift_rad) * AUDIO_OBLIQUE_BACKWARD_SPEED_M_S
	)
	var oblique_state = d.make_state(Vector2.ZERO, oblique_velocity, 0.0)
	oblique_state.reverse_engaged = false
	var oblique_oracle_slip := feedback_oracle_travel_relative_slip_deg(
		oblique_state.velocity_m_s, oblique_state.heading_rad
	)
	var oblique_synth_slip := SynthScript.direction_relative_slip_deg(
		oblique_state.velocity_m_s, oblique_state.heading_rad
	)
	d.check_close(
		oblique_oracle_slip, AUDIO_OBLIQUE_BACKWARD_SLIP_DEG, 1e-6,
		"audio.backward_geometry.oblique_oracle_angle"
	)
	d.check_close(
		oblique_oracle_slip, oblique_synth_slip, 1e-9,
		"audio.backward_geometry.oblique_oracle_matches_synth_geometry"
	)
	var oblique_bundle := SynthScript.render_bundle(oblique_state, command, 41)
	d.check(oblique_bundle.get("valid") == true, "audio.backward_geometry.oblique_bundle_valid")
	if oblique_bundle.get("valid") == true:
		d.check_close(
			float(oblique_bundle["telemetry"]["tire_slip_deg"]), oblique_oracle_slip, 1e-6,
			"audio.backward_geometry.oblique_synth_telemetry_matches_oracle"
		)
		var oblique_segment = oblique_bundle["tire"]
		var expected_intensity := feedback_oracle_tire_intensity(
			oblique_oracle_slip, oblique_state.speed_m_s(), oblique_state.grounded
		)
		d.check_close(
			float(oblique_segment.metadata["intensity"]), expected_intensity, 1e-9,
			"audio.backward_geometry.oblique_synth_intensity_matches_oracle"
		)
		d.check(
			oblique_segment.rms_amplitude > 0.0,
			"audio.backward_geometry.oblique_synth_pcm_has_energy"
	)
	var applied = player.apply(oblique_state, command)
	d.check(applied, "audio.backward_geometry.oblique_player_apply_accepted")
	if applied:
		var oblique_oracle_db := feedback_oracle_tire_db(
			oblique_state.velocity_m_s, oblique_state.heading_rad, oblique_state.grounded
		)
		d.check_close(
			player.get_last_tire_volume_db(), oblique_oracle_db, 1e-6,
			"audio.backward_geometry.oblique_player_matches_oracle"
		)
		var oblique_old_db := feedback_oracle_tire_db_from_abs_nose_slip(
			oblique_state.slip_deg(), oblique_state.speed_m_s(), oblique_state.grounded
		)
		d.check(
			oblique_old_db > oblique_oracle_db,
			"audio.backward_geometry.oblique_old_formula_overpredicts"
		)
		measurements["audio_oblique_backward_oracle_slip_deg"] = oblique_oracle_slip
		measurements["audio_oblique_backward_oracle_db"] = oblique_oracle_db
		measurements["audio_oblique_backward_old_formula_db"] = oblique_old_db

	measurements["audio_backward_coast_forward_speed_m_s"] = forward_speed
	measurements["audio_backward_coast_raw_slip_deg"] = raw_slip
	measurements["audio_backward_coast_oracle_slip_deg"] = oracle_slip
	measurements["audio_backward_coast_player_tire_db"] = last_tire_db
	measurements["audio_backward_coast_old_formula_db"] = old_formula_db
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


## Unsigned angle between the direction of travel and the nose axis line,
## mirroring `VehicleFeedbackSynth.direction_relative_slip_deg`. Computed from
## the committed road-plane velocity and heading rather than the reverse latch,
## so straight forward and straight reverse both give zero and a backward coast
## after the latch clears is not misread as saturated lateral slip.
func feedback_oracle_travel_relative_slip_deg(velocity_m_s: Vector2, heading_rad: float) -> float:
	var forward := Vector2(sin(heading_rad), cos(heading_rad))
	var right := Vector2(forward.y, -forward.x)
	var forward_component := velocity_m_s.dot(forward)
	var lateral_component := velocity_m_s.dot(right)
	if is_zero_approx(forward_component) and is_zero_approx(lateral_component):
		return 0.0
	return rad_to_deg(atan2(absf(lateral_component), absf(forward_component)))


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


func feedback_oracle_tire_db(
	velocity_m_s: Vector2, heading_rad: float, grounded: bool
) -> float:
	var travel_slip := feedback_oracle_travel_relative_slip_deg(velocity_m_s, heading_rad)
	return feedback_oracle_tire_db_from_intensity(
		feedback_oracle_tire_intensity(travel_slip, velocity_m_s.length(), grounded)
	)


## Pre-fix broken control: key the tire map directly on `abs(slip_deg())`, the
## signed nose-relative angle. Straight reverse saturates it even though the
## component folds by travel geometry. This exists only to prove that the
## regressions' negative controls separate the old and current behaviour.
func feedback_oracle_tire_db_from_abs_nose_slip(
	slip_deg: float, speed_m_s: float, grounded: bool
) -> float:
	return feedback_oracle_tire_db_from_intensity(
		feedback_oracle_tire_intensity(slip_deg, speed_m_s, grounded)
	)


func feedback_oracle_tire_intensity(
	travel_slip_deg: float, speed_m_s: float, grounded: bool
) -> float:
	if not grounded:
		return 0.0
	var threshold_norm := clampf(
		FEEDBACK_TIRE_SLIP_THRESHOLD_DEG / FEEDBACK_TIRE_SLIP_FULL_DEG, 0.0, 1.0
	)
	var slip_norm := clampf(absf(travel_slip_deg) / FEEDBACK_TIRE_SLIP_FULL_DEG, 0.0, 1.0)
	var speed_factor := clampf(
		(speed_m_s - FEEDBACK_TIRE_MIN_SPEED_M_S)
		/ (FEEDBACK_TIRE_REFERENCE_SPEED_M_S - FEEDBACK_TIRE_MIN_SPEED_M_S),
		0.0, 1.0
	)
	return smoothstep(threshold_norm, 1.0, slip_norm) * speed_factor


func feedback_oracle_tire_db_from_intensity(intensity: float) -> float:
	return clampf(
		linear_to_db(maxf(intensity, 1.0e-4)),
		FeedbackScript.MIN_VOLUME_DB,
		FeedbackScript.MAX_VOLUME_DB
	)


# --- M1.1 gearbox integration ---------------------------------------------

func _throttle_commands(count: int) -> Array:
	var commands: Array = []
	for _index in range(count):
		commands.append(d.throttle_command(1.0))
	return commands


## Full-throttle manual run until the committed forward speed exceeds
## `threshold_m_s`, bounded by `max_ticks`. Returns the committed tick count.
func _gearbox_warmup_until_speed(lab, threshold_m_s: float, max_ticks: int) -> int:
	lab.set_auto_tick(false)
	var ticks := 0
	while ticks < max_ticks and lab.state.forward_speed_m_s() <= threshold_m_s:
		var result = lab.step_once(d.throttle_command(1.0))
		if result == null or int(result.status) != int(AdapterScript.Status.COMMITTED):
			break
		if lab.failed:
			break
		ticks += 1
		await get_tree().physics_frame
	return ticks


## Shared assertion block: after a post-commit gearbox failure, `configure()`
## clears the failure/halt flags but must keep the body-pose block, and an
## attempted tick must make no adapter call.
func _gearbox_assert_pose_block_survives_configure(lab, label: String) -> void:
	var commands := _throttle_commands(5)
	var configured: bool = lab.configure(lab.tuning, lab.adapter_config, commands)
	d.check(configured, label + ".configure_accepted")
	d.check(lab.is_drive_replay_blocked(), label + ".configure_keeps_pose_block")
	var steps_before := int(lab.steps_called)
	var blocked = lab.step_once(d.throttle_command(1.0))
	d.check(blocked == null, label + ".blocked_tick_refused")
	d.check(
		int(lab.steps_called) == steps_before,
		label + ".blocked_tick_makes_no_adapter_call"
	)


## Auto-tick regression shared by the post-commit failure and state-only
## restore paths: after `configure()` clears the terminal flags but keeps the
## pose block, `start()` and the automatic physics callback must halt with the
## explicit replay block reason before consuming a scripted command, calling
## the adapter or reporting completion. A repeated start attempt stays inert.
func _gearbox_assert_auto_tick_refused(lab, label: String) -> void:
	lab.set_auto_tick(true)
	var steps_before := int(lab.steps_called)
	var ticks_before := int(lab.ticks_committed)
	var index_before := int(lab._script_index)
	var events_before := int(lab.get_gear_shift_events().size())
	var callbacks_before := int(lab.physics_callbacks)
	var reason_before := str(lab.get_drive_replay_block_reason())
	d.check(not reason_before.is_empty(), label + ".pose_block_reason_present")
	lab.start()
	d.check(lab.failed or lab.halted, label + ".auto_start_terminal_state")
	d.check(
		str(lab.halt_reason) == reason_before,
		label + ".auto_start_explicit_halt_reason"
	)
	d.check(not lab.completed, label + ".auto_start_not_completed")
	for _index in range(SETTLE_FRAMES):
		await get_tree().physics_frame
	d.check(
		int(lab.physics_callbacks) > callbacks_before,
		label + ".auto_physics_path_actually_ran"
	)
	d.check(
		int(lab._script_index) == index_before,
		label + ".auto_no_scripted_command_consumed"
	)
	d.check(int(lab.steps_called) == steps_before, label + ".auto_no_adapter_call")
	d.check(int(lab.ticks_committed) == ticks_before, label + ".auto_no_committed_tick")
	d.check(
		int(lab.get_gear_shift_events().size()) == events_before,
		label + ".auto_no_shift_event_side_effect"
	)
	d.check(not lab.completed, label + ".auto_still_not_completed")
	# Repeated attempts stay inert: the halt is recorded once and no side effect
	# repeats across further automatic callbacks.
	lab.start()
	for _index in range(3):
		await get_tree().physics_frame
	d.check(int(lab.steps_called) == steps_before, label + ".repeat_start_no_adapter_call")
	d.check(
		int(lab._script_index) == index_before,
		label + ".repeat_start_no_script_progress"
	)
	d.check(not lab.completed, label + ".repeat_start_not_completed")
	d.check(str(lab.halt_reason) == reason_before, label + ".halt_reason_stable")

## One canonical AutomaticGearbox per laboratory: initial pair agreement,
## natural shifts with bounded event telemetry and no dithering, reverse-latch
## entry and backward coast after latch clear, state-only snapshot/restore with
## an explicit body-pose block, atomic refusal of invalid pairs, and
## reconfiguration/reset agreement. Every wait is bounded.
func _case_gearbox_integration() -> void:
	await _gearbox_initial_checks()
	await _gearbox_forward_shift_checks()
	await _gearbox_reverse_and_coast_checks()
	await _gearbox_snapshot_restore_checks()
	await _gearbox_invalid_pair_atomicity_checks()
	await _gearbox_reconfigure_reset_checks()
	await _gearbox_physical_trace_checks()
	await _gearbox_failure_path_checks()


func _gearbox_api_available(lab) -> bool:
	var required := [
		"get_gearbox_state", "get_gearbox_snapshot", "get_gearbox_config_snapshot",
		"get_gear_shift_events", "get_gearbox_telemetry", "get_gearbox_error",
		"get_last_committed_physical_state", "snapshot_drive_state",
		"restore_drive_snapshot", "is_drive_replay_blocked",
		"get_drive_replay_block_reason", "get_drive_restore_error",
	]
	var missing: Array = []
	for name in required:
		if not lab.has_method(name):
			missing.append(name)
	d.check(missing.is_empty(), "gearbox.api_present: missing " + str(missing))
	return missing.is_empty()


func _gearbox_check_float_array(actual, expected: Array, label: String) -> void:
	d.check(
		actual.size() == expected.size(),
		label + ".size (actual=%d expected=%d)" % [actual.size(), expected.size()]
	)
	for index in range(mini(actual.size(), expected.size())):
		d.check_close(
			float(actual[index]), float(expected[index]), 1e-12,
			label + ".entry_%d" % index
		)


func _gearbox_variant_snapshot(car, box) -> DriveLabScript.DriveSnapshot:
	var snapshot := DriveLabScript.DriveSnapshot.new()
	snapshot.car_state = car
	snapshot.gearbox_state = box
	return snapshot


func _gearbox_compact_trace(log: Array) -> Array:
	var out: Array = []
	for record in log:
		out.append({
			"position_m": record["position_m"],
			"velocity_m_s": record["velocity_m_s"],
			"heading_rad": record["heading_rad"],
			"body_transform": record["body_transform"],
			"gear_index": int(record["gear_index"]),
			"normalized_rpm": float(record["normalized_rpm"]),
		})
	return out


func _gearbox_capture(lab) -> Dictionary:
	return {
		"trace": _gearbox_compact_trace(lab.tick_log),
		"events": lab.get_gear_shift_events().duplicate(),
		"gearbox": lab.get_gearbox_snapshot(),
	}


func _gearbox_manual_run(lab, commands: Array) -> bool:
	lab.set_auto_tick(false)
	for index in range(commands.size()):
		var result = lab.step_once(commands[index])
		if result == null or int(result.status) != int(AdapterScript.Status.COMMITTED):
			return false
		if lab.failed:
			return false
		await get_tree().physics_frame
	return true


func _gearbox_initial_checks() -> void:
	var lab = _make_lab([])
	if lab == null:
		return
	if not _gearbox_api_available(lab):
		await _teardown_lab(lab)
		return
	await _settle()
	d.check(not lab.failed, "gearbox.initial_not_failed: " + str(lab.failure_reason))
	d.check(lab.gearbox != null and lab.gearbox is GearboxScript, "gearbox.instance_present")
	d.check(int(lab.state.gear_index) == 1, "gearbox.initial_car_mirror_is_first_gear")
	var box = lab.get_gearbox_state()
	d.check(box != null, "gearbox.initial_state_copy_present")
	if box != null:
		d.check(int(box.gear_index) == 1, "gearbox.initial_canonical_gear_is_one")
		d.check_exact_float(box.shift_cooldown_s, 0.0, "gearbox.initial_cooldown_zero")
		d.check_exact_float(box.normalized_rpm, 0.0, "gearbox.initial_rpm_zero")
	d.check(lab.get_gear_shift_events().is_empty(), "gearbox.initial_no_events")
	var telemetry: Dictionary = lab.get_gearbox_telemetry()
	d.check(int(telemetry["shift_event_count"]) == 0, "gearbox.initial_event_counter_zero")
	d.check(int(telemetry["shift_events_dropped"]) == 0, "gearbox.initial_drop_counter_zero")
	d.check(int(telemetry["gearbox_refusals"]) == 0, "gearbox.initial_refusal_counter_zero")
	d.check(str(lab.get_gearbox_error()).is_empty(), "gearbox.initial_no_failure")
	d.check(not lab.is_drive_replay_blocked(), "gearbox.initial_ticks_allowed")
	d.check(str(lab.get_drive_replay_block_reason()).is_empty(), "gearbox.initial_no_block_reason")

	var config: Dictionary = lab.get_gearbox_config_snapshot()
	d.check(int(config["forward_gear_count"]) == 6, "gearbox.config_forward_gears")
	_gearbox_check_float_array(
		config["upshift_speeds_m_s"], [8.0, 14.0, 21.0, 29.0, 38.0],
		"gearbox.config_upshifts"
	)
	_gearbox_check_float_array(
		config["downshift_speeds_m_s"], [5.0, 10.0, 16.0, 23.0, 31.0],
		"gearbox.config_downshifts"
	)
	d.check_close(float(config["min_shift_dwell_s"]), 0.25, 1e-12, "gearbox.config_dwell")
	d.check_close(
		float(config["reverse_exit_forward_speed_m_s"]), 0.5, 1e-12,
		"gearbox.config_reverse_exit"
	)

	var snapshot = lab.snapshot_drive_state()
	d.check(snapshot is DriveLabScript.DriveSnapshot, "gearbox.snapshot_type")
	d.check(String(snapshot.schema) == "roadstorm.drive_snapshot.v1", "gearbox.snapshot_schema")
	d.check(
		snapshot.car_state != null and snapshot.car_state.is_finite(),
		"gearbox.snapshot_car_finite"
	)
	d.check(snapshot.gearbox_state != null, "gearbox.snapshot_gearbox_present")
	if snapshot.car_state != null and snapshot.gearbox_state != null:
		d.check(
			int(snapshot.car_state.gear_index) == int(snapshot.gearbox_state.gear_index),
			"gearbox.snapshot_pair_mirror_agrees"
		)
		d.check_exact_float(
			snapshot.car_state.position_m.x, lab.state.position_m.x,
			"gearbox.snapshot_copies_position_x"
		)
	# Copy semantics: neither live record nor a returned copy aliases another.
	var exposed = lab.get_gearbox_state()
	if exposed != null:
		exposed.gear_index = 99
		d.check(
			lab.get_gearbox_state() != null and int(lab.get_gearbox_state().gear_index) == 1,
			"gearbox.get_state_returns_independent_copy"
	)
	var live_x: float = lab.state.position_m.x
	if snapshot.car_state != null:
		snapshot.car_state.position_m.x = 123.0
		d.check_exact_float(
			lab.state.position_m.x, live_x,
			"gearbox.snapshot_car_is_a_copy"
	)
	if snapshot.gearbox_state != null:
		snapshot.gearbox_state.gear_index = 99
		var live_snapshot: Dictionary = lab.get_gearbox_snapshot()
		d.check(int(live_snapshot["gear_index"]) == 1, "gearbox.snapshot_gearbox_is_a_copy")
	await _teardown_lab(lab)


func _gearbox_forward_shift_checks() -> void:
	var commands: Array = []
	for _index in range(GEARBOX_FORWARD_TICKS):
		commands.append(d.throttle_command(1.0))
	for _index in range(GEARBOX_BRAKE_TICKS):
		commands.append(d.brake_command(1.0))
	var lab = _make_lab([])
	if lab == null:
		return
	if not _gearbox_api_available(lab):
		await _teardown_lab(lab)
		return
	lab.set_auto_tick(false)
	await _settle()
	var ticks_run := 0
	var dwell_limit: float = lab.get_gearbox_config_snapshot()["min_shift_dwell_s"]
	for index in range(commands.size()):
		var result = lab.step_once(commands[index])
		if result == null or int(result.status) != int(AdapterScript.Status.COMMITTED):
			d.check(false, "gearbox.shift.tick_%d_committed" % (index + 1))
			break
		# A gearbox refusal halts before publishing; there is no paired record
		# or tick-log entry for this irreversible physical tick.
		if lab.failed:
			break
		ticks_run += 1
		var canonical = lab.get_gearbox_state()
		d.check(
			int(lab.state.gear_index) == int(canonical.gear_index),
			"gearbox.shift.tick_%d_mirror_matches_canonical" % (index + 1)
		)
		var record: Dictionary = lab.tick_log[-1]
		d.check(
			int(record["gear_index"]) == int(lab.state.gear_index),
			"gearbox.shift.tick_%d_logged_gear" % (index + 1)
		)
		var rpm := float(record["normalized_rpm"])
		d.check(rpm >= 0.0 and rpm <= 1.0, "gearbox.shift.tick_%d_rpm_bounded" % (index + 1))
		d.check_exact_float(
			rpm, float(canonical.normalized_rpm),
			"gearbox.shift.tick_%d_rpm_matches_canonical" % (index + 1)
		)
		d.check(
			float(canonical.shift_cooldown_s) >= 0.0
			and float(canonical.shift_cooldown_s) <= dwell_limit + 1e-12,
			"gearbox.shift.tick_%d_cooldown_bounded" % (index + 1)
		)
		await get_tree().physics_frame
	d.check(not lab.failed, "gearbox.shift.run_not_failed: " + str(lab.failure_reason))
	d.check(ticks_run == commands.size(), "gearbox.shift.all_ticks_committed")

	var log: Array = lab.tick_log
	var events: Array = lab.get_gear_shift_events()
	if log.is_empty():
		d.check(false, "gearbox.shift.trace_present")
		await _teardown_lab(lab)
		return
	var transitions: Array = []
	for index in range(1, log.size()):
		if int(log[index]["gear_index"]) != int(log[index - 1]["gear_index"]):
			transitions.append(index + 1)
	d.check(
		events.size() == transitions.size(),
		"gearbox.shift.event_count_equals_transitions (events=%d transitions=%d)"
			% [events.size(), transitions.size()]
	)
	var forward_events := 0
	var brake_events := 0
	for index in range(mini(events.size(), transitions.size())):
		var event: Dictionary = events[index]
		var tick := int(transitions[index])
		d.check(
			int(event["tick"]) == tick,
			"gearbox.shift.event_%d_tick_matches_transition" % index
		)
		var previous_gear := 1
		if tick >= 2:
			previous_gear = int(log[tick - 2]["gear_index"])
		var current_gear := int(log[tick - 1]["gear_index"])
		d.check(
			int(event["from_gear"]) == previous_gear,
			"gearbox.shift.event_%d_from_gear_matches_log" % index
		)
		d.check(
			int(event["to_gear"]) == current_gear,
			"gearbox.shift.event_%d_to_gear_matches_log" % index
		)
		d.check(
			int(event["from_gear"]) != int(event["to_gear"]),
			"gearbox.shift.event_%d_is_a_real_change" % index
		)
		d.check_exact_float(
			float(event["normalized_rpm"]), float(log[tick - 1]["normalized_rpm"]),
			"gearbox.shift.event_%d_rpm_matches_log" % index
		)
		if tick <= GEARBOX_FORWARD_TICKS:
			forward_events += 1
			d.check(
				int(event["direction"]) == int(GearboxScript.ShiftDirection.UPSHIFT),
				"gearbox.shift.event_%d_is_an_upshift" % index
			)
		else:
			brake_events += 1
			d.check(
				int(event["direction"]) == int(GearboxScript.ShiftDirection.DOWNSHIFT),
				"gearbox.shift.event_%d_is_a_downshift" % index
			)
	d.check(forward_events >= 2, "gearbox.shift.natural_forward_shifts_observed (%d)" % forward_events)
	d.check(brake_events >= 1, "gearbox.shift.downshifts_observed (%d)" % brake_events)
	for index in range(1, transitions.size()):
		d.check(
			int(transitions[index]) - int(transitions[index - 1]) >= GEARBOX_EVENT_GAP_TICKS,
			"gearbox.shift.events_are_not_repeated_within_dwell (ticks %d and %d)"
			% [int(transitions[index - 1]), int(transitions[index])]
		)
	var forward_gears: Array = []
	for tick in transitions:
		if int(tick) <= GEARBOX_FORWARD_TICKS:
			forward_gears.append(int(log[int(tick) - 1]["gear_index"]))
	var monotonic_forward := true
	for index in range(1, forward_gears.size()):
		if forward_gears[index] <= forward_gears[index - 1]:
			monotonic_forward = false
	d.check(monotonic_forward, "gearbox.shift.forward_gears_strictly_increase")
	var max_forward_gear := 1
	for tick in transitions:
		if int(tick) <= GEARBOX_FORWARD_TICKS:
			max_forward_gear = maxi(
				max_forward_gear, int(log[int(tick) - 1]["gear_index"])
			)
	d.check(
		max_forward_gear >= 3,
		"gearbox.shift.reaches_at_least_third_gear (%d)" % max_forward_gear
	)
	var final_gear := int(log[-1]["gear_index"])
	d.check(
		int(lab.get_gearbox_telemetry()["shift_events_dropped"]) == 0,
		"gearbox.shift.no_dropped_events"
	)
	# Returned telemetry entries are copies: mutating them cannot alter the
	# laboratory's bounded internal log.
	var exposed_events = lab.get_gear_shift_events()
	if exposed_events.size() > 0:
		exposed_events[0]["to_gear"] = 99
		exposed_events[0]["normalized_rpm"] = -1.0
		var internal_again: Array = lab.get_gear_shift_events()
		d.check(
			int(internal_again[0]["to_gear"]) == int(events[0]["to_gear"]),
			"gearbox.shift.returned_event_entries_are_copies"
		)
		d.check_exact_float(
			float(internal_again[0]["normalized_rpm"]), float(events[0]["normalized_rpm"]),
			"gearbox.shift.returned_event_values_are_copies"
		)
	d.check(
		int(lab.steps_called) == int(lab.ticks_committed),
		"gearbox.shift.one_adapter_call_per_committed_tick"
	)
	measurements["gearbox_forward_events"] = forward_events
	measurements["gearbox_brake_events"] = brake_events
	measurements["gearbox_max_forward_gear"] = max_forward_gear
	measurements["gearbox_final_gear"] = final_gear
	await _teardown_lab(lab)


func _gearbox_reverse_and_coast_checks() -> void:
	var lab = _make_lab([])
	if lab == null:
		return
	if not _gearbox_api_available(lab):
		await _teardown_lab(lab)
		return
	lab.set_auto_tick(false)
	await _settle()
	var total := (
		GEARBOX_REVERSE_THROTTLE_TICKS
		+ GEARBOX_REVERSE_BRAKE_TICKS
		+ GEARBOX_COAST_TICKS
		+ GEARBOX_FORWARD_RESUME_TICKS
	)
	var brake_end := GEARBOX_REVERSE_THROTTLE_TICKS + GEARBOX_REVERSE_BRAKE_TICKS
	var coast_end := brake_end + GEARBOX_COAST_TICKS
	for index in range(total):
		var command
		if index < GEARBOX_REVERSE_THROTTLE_TICKS:
			command = d.throttle_command(1.0)
		elif index < brake_end:
			command = d.brake_command(1.0)
		elif index < coast_end:
			command = d.idle_command()
		else:
			command = d.throttle_command(1.0)
		var result = lab.step_once(command)
		if result == null or int(result.status) != int(AdapterScript.Status.COMMITTED):
			d.check(false, "gearbox.reverse.tick_%d_committed" % (index + 1))
			break
		if lab.failed:
			break
		var canonical = lab.get_gearbox_state()
		d.check(
			int(lab.state.gear_index) == int(canonical.gear_index),
			"gearbox.reverse.tick_%d_mirror_matches_canonical" % (index + 1)
		)
		if index + 1 == GEARBOX_REVERSE_THROTTLE_TICKS:
			d.check(not lab.state.reverse_engaged, "gearbox.reverse.latch_clear_while_forward")
			d.check(int(canonical.gear_index) >= 1, "gearbox.reverse.forward_gear_before_brake")
		if index + 1 == brake_end:
			d.check(lab.state.reverse_engaged, "gearbox.reverse.latch_engaged_after_brake_hold")
			d.check(
				lab.state.forward_speed_m_s() < 0.0,
				"gearbox.reverse.travelling_backwards_after_latch"
			)
			d.check(int(canonical.gear_index) == -1, "gearbox.reverse.canonical_reverse_gear")
		if index + 1 == coast_end:
			d.check(not lab.state.reverse_engaged, "gearbox.coast.latch_cleared_after_idle")
			d.check(
				lab.state.forward_speed_m_s() < 0.0,
				"gearbox.coast.still_travelling_backwards"
			)
			d.check(int(canonical.gear_index) == -1, "gearbox.coast.gear_stays_reverse")
			for event in lab.get_gear_shift_events():
				d.check(
					int(event["direction"]) != int(GearboxScript.ShiftDirection.EXIT_REVERSE),
					"gearbox.coast.no_exit_reverse_during_backward_coast"
				)
		await get_tree().physics_frame
	d.check(not lab.failed, "gearbox.reverse.run_not_failed: " + str(lab.failure_reason))
	var enter_events := 0
	var exit_events := 0
	var exit_event: Dictionary = {}
	for event in lab.get_gear_shift_events():
		if int(event["direction"]) == int(GearboxScript.ShiftDirection.ENTER_REVERSE):
			enter_events += 1
		elif int(event["direction"]) == int(GearboxScript.ShiftDirection.EXIT_REVERSE):
			exit_events += 1
			if exit_event.is_empty():
				exit_event = event
	d.check(enter_events == 1, "gearbox.reverse.exactly_one_enter_reverse_event (%d)" % enter_events)
	d.check(exit_events == 1, "gearbox.reverse.exactly_one_exit_reverse_event (%d)" % exit_events)
	d.check(not exit_event.is_empty(), "gearbox.reverse.exit_event_present_after_forward_resume")
	if not exit_event.is_empty():
		d.check(int(exit_event["from_gear"]) == -1, "gearbox.reverse.exit_from_reverse")
		d.check(int(exit_event["to_gear"]) >= 1, "gearbox.reverse.exit_to_forward_gear")
		d.check(
			int(exit_event["tick"]) > coast_end,
			"gearbox.reverse.exit_happens_after_latch_clear"
		)
	d.check(int(lab.state.gear_index) >= 1, "gearbox.reverse.forward_gear_after_exit")
	measurements["gearbox_reverse_enter_events"] = enter_events
	measurements["gearbox_reverse_exit_events"] = exit_events
	await _teardown_lab(lab)


func _gearbox_snapshot_restore_checks() -> void:
	var lab = _make_lab([])
	if lab == null:
		return
	if not _gearbox_api_available(lab):
		await _teardown_lab(lab)
		return
	lab.set_auto_tick(false)
	await _settle()
	var snapshot: DriveLabScript.DriveSnapshot = null
	var captured_tick := 0
	for index in range(GEARBOX_SNAPSHOT_TICKS):
		var result = lab.step_once(d.throttle_command(1.0))
		if result == null or int(result.status) != int(AdapterScript.Status.COMMITTED):
			d.check(false, "gearbox.snapshot.tick_%d_committed" % (index + 1))
			break
		if lab.failed:
			break
		captured_tick = index + 1
		if lab.get_gear_shift_events().size() > 0:
			snapshot = lab.snapshot_drive_state()
			break
		await get_tree().physics_frame
	d.check(snapshot != null, "gearbox.snapshot.captured_immediately_after_first_shift")
	if snapshot == null:
		await _teardown_lab(lab)
		return
	d.check(snapshot.car_state != null and snapshot.gearbox_state != null, "gearbox.snapshot.complete_pair")
	var checkpoint = snapshot.gearbox_state.copy()
	var checkpoint_car = snapshot.car_state.copy()
	d.check(int(checkpoint.gear_index) >= 2, "gearbox.snapshot.nonzero_gear_checkpoint")
	d.check(float(checkpoint.shift_cooldown_s) > 0.0, "gearbox.snapshot.nonzero_cooldown")
	d.check(
		float(checkpoint.shift_cooldown_s) <= 0.25 + 1e-12,
		"gearbox.snapshot.cooldown_within_dwell"
	)
	d.check(
		float(checkpoint.normalized_rpm) > 0.0 and float(checkpoint.normalized_rpm) <= 1.0,
		"gearbox.snapshot.normalized_rpm"
	)
	d.check(
		int(checkpoint_car.gear_index) == int(checkpoint.gear_index),
		"gearbox.snapshot.mirror_agrees_with_canonical"
	)
	d.check(captured_tick > 0, "gearbox.snapshot.capture_tick_recorded")
	# Snapshot copies are independent of the live pair.
	var alias_probe = lab.snapshot_drive_state()
	alias_probe.car_state.position_m.x += 5.0
	alias_probe.gearbox_state.gear_index = 99
	var live_now: Dictionary = lab.get_gearbox_snapshot()
	d.check(
		int(live_now["gear_index"]) == int(checkpoint.gear_index),
		"gearbox.snapshot.does_not_alias_live_pair"
	)
	d.check_exact_float(
		lab.state.position_m.x, checkpoint_car.position_m.x,
		"gearbox.snapshot.car_is_a_copy"
	)

	var dest = _make_lab([])
	if dest == null:
		await _teardown_lab(lab)
		return
	if not _gearbox_api_available(dest):
		await _teardown_lab(dest)
		await _teardown_lab(lab)
		return
	var restored_ok: bool = dest.restore_drive_snapshot(snapshot)
	d.check(restored_ok, "gearbox.restore.valid_pair_accepted")
	d.check(dest.state != null and dest.state.is_finite(), "gearbox.restore.published_car_finite")
	if dest.state != null:
		d.check(
			dest.state.position_m == checkpoint_car.position_m,
			"gearbox.restore.car_position_published"
		)
		d.check(
			dest.state.velocity_m_s == checkpoint_car.velocity_m_s,
			"gearbox.restore.car_velocity_published"
		)
		d.check_exact_float(
			dest.state.heading_rad, checkpoint_car.heading_rad,
			"gearbox.restore.car_heading_published"
		)
		d.check(
			dest.state.grounded == checkpoint_car.grounded
			and dest.state.surface_id == checkpoint_car.surface_id
			and dest.state.reverse_engaged == checkpoint_car.reverse_engaged
			and dest.state.drafting_active == checkpoint_car.drafting_active,
			"gearbox.restore.car_flags_verbatim"
		)
		d.check_exact_float(
			dest.state.reverse_hold_s, checkpoint_car.reverse_hold_s,
			"gearbox.restore.car_reverse_hold_verbatim"
		)
		d.check_exact_float(
			dest.state.drift_timer_s, checkpoint_car.drift_timer_s,
			"gearbox.restore.car_drift_timer_verbatim"
		)
		d.check_exact_float(
			dest.state.drift_slip_deg, checkpoint_car.drift_slip_deg,
			"gearbox.restore.car_drift_slip_verbatim"
		)
		d.check_exact_float(
			dest.state.surge_cooldown_s, checkpoint_car.surge_cooldown_s,
			"gearbox.restore.car_surge_cooldown_verbatim"
		)
		d.check_exact_float(
			dest.state.contact_immunity_s, checkpoint_car.contact_immunity_s,
			"gearbox.restore.car_contact_immunity_verbatim"
		)
		d.check_exact_float(
			dest.state.valid_progress_m, checkpoint_car.valid_progress_m,
			"gearbox.restore.car_progress_verbatim"
		)
		d.check(
			int(dest.state.gear_index) == int(checkpoint.gear_index),
			"gearbox.restore.mirror_repaired_from_canonical"
		)
	var restored_box = dest.get_gearbox_state()
	d.check(restored_box != null, "gearbox.restore.box_present")
	if restored_box != null:
		d.check(int(restored_box.gear_index) == int(checkpoint.gear_index), "gearbox.restore.gear_exact")
		d.check_exact_float(
			restored_box.shift_cooldown_s, float(checkpoint.shift_cooldown_s),
			"gearbox.restore.cooldown_exact"
		)
		d.check_exact_float(
			restored_box.normalized_rpm, float(checkpoint.normalized_rpm),
			"gearbox.restore.rpm_exact"
		)
	# State-only restore blocks every tick until body pose reconciliation exists.
	d.check(dest.is_drive_replay_blocked(), "gearbox.restore.ticks_blocked")
	d.check(
		str(dest.get_drive_replay_block_reason()) != "",
		"gearbox.restore.explicit_block_reason"
	)
	var steps_before := int(dest.steps_called)
	var blocked_result = dest.step_once(d.throttle_command(1.0))
	d.check(blocked_result == null, "gearbox.restore.step_refused_without_adapter_call")
	d.check(int(dest.steps_called) == steps_before, "gearbox.restore.no_adapter_call_consumed")
	d.check(not dest.failed, "gearbox.restore.block_is_not_a_failure")
	d.check(dest.halted, "gearbox.restore.halt_flag_set")
	d.check(
		str(dest.halt_reason) == String(DriveLabScript.DRIVE_STATE_ONLY_HALT),
		"gearbox.restore.explicit_halt_reason"
	)

	# Restoring the same pair into a second destination is deterministic.
	var dest2 = _make_lab([])
	if dest2 != null and _gearbox_api_available(dest2):
		var fresh_snapshot = lab.snapshot_drive_state()
		var ok2: bool = dest2.restore_drive_snapshot(fresh_snapshot)
		d.check(ok2, "gearbox.restore.second_destination_accepts_valid_pair")
		d.check(
			dest2.get_gearbox_snapshot() == dest.get_gearbox_snapshot(),
			"gearbox.restore.deterministic_across_destinations"
		)
		await _teardown_lab(dest2)

	# A stale CarState mirror is repaired from the canonical gearbox gear.
	var dest3 = _make_lab([])
	if dest3 != null and _gearbox_api_available(dest3):
		var repair_snapshot = lab.snapshot_drive_state()
		repair_snapshot.car_state.gear_index = 99
		var ok3: bool = dest3.restore_drive_snapshot(repair_snapshot)
		d.check(ok3, "gearbox.restore.stale_mirror_repair_accepted")
		d.check(
			int(dest3.state.gear_index) == int(repair_snapshot.gearbox_state.gear_index),
			"gearbox.restore.publishes_canonical_not_stale_mirror"
		)
		await _teardown_lab(dest3)
		await _teardown_lab(dest)
	else:
		await _teardown_lab(dest)

	# State-only restore path: reconfiguration keeps the pose block, and a
	# started automatic run must halt explicitly without scripted-index or
	# adapter progress, completion, or repeated side effects. A separate
	# destination keeps the determinism comparison above untouched.
	var dest_auto = _make_lab([])
	if dest_auto != null and _gearbox_api_available(dest_auto):
		var auto_restored: bool = dest_auto.restore_drive_snapshot(snapshot)
		d.check(auto_restored, "gearbox.restore.auto.valid_pair_accepted")
		var restore_commands := _throttle_commands(5)
		var dest_reconfigured: bool = dest_auto.configure(
			dest_auto.tuning, dest_auto.adapter_config, restore_commands
		)
		d.check(dest_reconfigured, "gearbox.restore.auto.configure_accepted")
		await _gearbox_assert_auto_tick_refused(dest_auto, "gearbox.restore.auto")
		await _teardown_lab(dest_auto)
	await _teardown_lab(lab)


func _gearbox_invalid_pair_atomicity_checks() -> void:
	var lab = _make_lab([])
	if lab == null:
		return
	if not _gearbox_api_available(lab):
		await _teardown_lab(lab)
		return
	lab.set_auto_tick(false)
	await _settle()
	var warmup := []
	for _index in range(80):
		warmup.append(d.throttle_command(1.0))
	var warmed := await _gearbox_manual_run(lab, warmup)
	d.check(warmed, "gearbox.atomic.warmup_completed")
	var base = lab.snapshot_drive_state()
	d.check(base.car_state != null and base.gearbox_state != null, "gearbox.atomic.base_complete")
	var box_before: Dictionary = lab.get_gearbox_snapshot()
	var state_before: Dictionary = d.snapshot_state(lab.state)
	var gear_before := int(lab.state.gear_index)
	var events_before: int = lab.get_gear_shift_events().size()

	var nonfinite_car = base.car_state.copy()
	nonfinite_car.position_m.x = NAN
	var null_car_box = base.gearbox_state.copy()
	var bad_gear_zero = base.gearbox_state.copy()
	bad_gear_zero.gear_index = 0
	var bad_gear_high = base.gearbox_state.copy()
	bad_gear_high.gear_index = int(lab.get_gearbox_config_snapshot()["forward_gear_count"]) + 1
	var bad_gear_negative = base.gearbox_state.copy()
	bad_gear_negative.gear_index = -2
	var bad_cooldown_negative = base.gearbox_state.copy()
	bad_cooldown_negative.shift_cooldown_s = -0.1
	var bad_cooldown_high = base.gearbox_state.copy()
	bad_cooldown_high.shift_cooldown_s = 0.3
	var bad_cooldown_nan = base.gearbox_state.copy()
	bad_cooldown_nan.shift_cooldown_s = NAN
	var bad_rpm_low = base.gearbox_state.copy()
	bad_rpm_low.normalized_rpm = -0.1
	var bad_rpm_high = base.gearbox_state.copy()
	bad_rpm_high.normalized_rpm = 1.5
	var bad_rpm_nan = base.gearbox_state.copy()
	bad_rpm_nan.normalized_rpm = NAN

	var variants: Array = [
		{"name": "nonfinite_car", "snapshot": _gearbox_variant_snapshot(nonfinite_car, base.gearbox_state.copy())},
		{"name": "null_car", "snapshot": _gearbox_variant_snapshot(null, null_car_box)},
		{"name": "null_gearbox", "snapshot": _gearbox_variant_snapshot(base.car_state.copy(), null)},
		{"name": "gear_zero", "snapshot": _gearbox_variant_snapshot(base.car_state.copy(), bad_gear_zero)},
		{"name": "gear_above_configured", "snapshot": _gearbox_variant_snapshot(base.car_state.copy(), bad_gear_high)},
		{"name": "gear_negative_two", "snapshot": _gearbox_variant_snapshot(base.car_state.copy(), bad_gear_negative)},
		{"name": "cooldown_negative", "snapshot": _gearbox_variant_snapshot(base.car_state.copy(), bad_cooldown_negative)},
		{"name": "cooldown_above_dwell", "snapshot": _gearbox_variant_snapshot(base.car_state.copy(), bad_cooldown_high)},
		{"name": "cooldown_nonfinite", "snapshot": _gearbox_variant_snapshot(base.car_state.copy(), bad_cooldown_nan)},
		{"name": "rpm_negative", "snapshot": _gearbox_variant_snapshot(base.car_state.copy(), bad_rpm_low)},
		{"name": "rpm_above_one", "snapshot": _gearbox_variant_snapshot(base.car_state.copy(), bad_rpm_high)},
		{"name": "rpm_nonfinite", "snapshot": _gearbox_variant_snapshot(base.car_state.copy(), bad_rpm_nan)},
		{"name": "plain_dictionary", "snapshot": {}},
	]
	for variant in variants:
		var label: String = variant["name"]
		var refused: bool = not lab.restore_drive_snapshot(variant["snapshot"])
		d.check(refused, "gearbox.atomic." + label + "_refused")
		d.check(
			lab.get_gearbox_snapshot() == box_before,
			"gearbox.atomic." + label + "_gearbox_unchanged"
		)
		d.check(
			d.snapshot_state(lab.state) == state_before,
			"gearbox.atomic." + label + "_state_unchanged"
		)
		d.check(
			int(lab.state.gear_index) == gear_before,
			"gearbox.atomic." + label + "_mirror_unchanged"
		)
		d.check(
			lab.get_gear_shift_events().size() == events_before,
			"gearbox.atomic." + label + "_no_new_events"
		)
		d.check(
			not lab.is_drive_replay_blocked(),
			"gearbox.atomic." + label + "_no_restore_side_effect"
		)
		d.check(not lab.failed, "gearbox.atomic." + label + "_not_failed")
	d.check(
		str(lab.get_drive_restore_error()) != "",
		"gearbox.atomic.refusal_reason_recorded"
	)
	d.check(not lab.restore_drive_snapshot(null), "gearbox.atomic.null_snapshot_refused")
	d.check(
		lab.get_gearbox_snapshot() == box_before,
		"gearbox.atomic.final_gearbox_unchanged"
	)
	var valid_restore: bool = lab.restore_drive_snapshot(base)
	d.check(valid_restore, "gearbox.atomic.valid_restore_still_works_after_refusals")
	d.check(lab.is_drive_replay_blocked(), "gearbox.atomic.valid_restore_blocks_ticks")
	await _teardown_lab(lab)


func _gearbox_reconfigure_reset_checks() -> void:
	var lab = _make_lab([])
	if lab == null:
		return
	if not _gearbox_api_available(lab):
		await _teardown_lab(lab)
		return
	lab.set_auto_tick(false)
	await _settle()
	var warmup: Array = []
	for _index in range(80):
		warmup.append(d.throttle_command(1.0))
	var warmed := await _gearbox_manual_run(lab, warmup)
	d.check(warmed, "gearbox.reset.warmup_completed")
	d.check(lab.get_gear_shift_events().size() > 0, "gearbox.reset.shifts_before_reconfigure")
	var commands: Array = []
	for _index in range(GEARBOX_TRACE_TICKS):
		commands.append(d.throttle_command(1.0))
	var reconfigured: bool = lab.configure(lab.tuning, lab.adapter_config, commands)
	d.check(reconfigured, "gearbox.reset.configure_accepted")
	var box = lab.get_gearbox_state()
	d.check(int(box.gear_index) == 1, "gearbox.reset.gear_one")
	d.check_exact_float(box.shift_cooldown_s, 0.0, "gearbox.reset.zero_cooldown")
	d.check_exact_float(box.normalized_rpm, 0.0, "gearbox.reset.zero_rpm")
	d.check(int(lab.state.gear_index) == 1, "gearbox.reset.mirror_agrees")
	d.check(lab.get_gear_shift_events().is_empty(), "gearbox.reset.events_cleared")
	d.check(
		int(lab.get_gearbox_telemetry()["gearbox_refusals"]) == 0,
		"gearbox.reset.refusal_counter_cleared"
	)
	d.check(not lab.is_drive_replay_blocked(), "gearbox.reset.ticks_allowed")
	var ran := await _gearbox_manual_run(lab, commands)
	d.check(ran, "gearbox.reset.second_schedule_ran")
	d.check(not lab.failed, "gearbox.reset.second_run_not_failed: " + str(lab.failure_reason))
	d.check(
		int(lab.state.gear_index) == int(lab.get_gearbox_state().gear_index),
		"gearbox.reset.second_run_mirror_agrees"
	)
	d.check(
		lab.get_gear_shift_events().size() >= 1,
		"gearbox.reset.new_schedule_shifts_again"
	)
	await _teardown_lab(lab)


func _gearbox_physical_trace_checks() -> void:
	# Part 1: on every committed tick the published physical fields are copied
	# verbatim from the adapter commit; only the gear mirror can differ.
	var lab = _make_lab([])
	if lab == null:
		return
	if not _gearbox_api_available(lab):
		await _teardown_lab(lab)
		return
	lab.set_auto_tick(false)
	await _settle()
	var compared := 0
	for _index in range(GEARBOX_TRACE_TICKS):
		var result = lab.step_once(d.throttle_command(1.0))
		if result == null or int(result.status) != int(AdapterScript.Status.COMMITTED):
			d.check(false, "gearbox.trace.tick_%d_committed" % (_index + 1))
			break
		if lab.failed:
			break
		var physical = lab.get_last_committed_physical_state()
		d.check(physical != null, "gearbox.trace.physical_copy_present")
		if physical != null:
			d.check(
				lab.state.position_m == physical.position_m,
			"gearbox.trace.tick_%d_position_verbatim" % (_index + 1)
			)
			d.check(
				lab.state.velocity_m_s == physical.velocity_m_s,
			"gearbox.trace.tick_%d_velocity_verbatim" % (_index + 1)
			)
			d.check_exact_float(
				lab.state.heading_rad, physical.heading_rad,
				"gearbox.trace.tick_%d_heading_verbatim" % (_index + 1)
			)
			d.check(
				lab.state.grounded == physical.grounded
				and lab.state.surface_id == physical.surface_id
				and lab.state.reverse_engaged == physical.reverse_engaged
				and lab.state.drafting_active == physical.drafting_active,
			"gearbox.trace.tick_%d_flags_verbatim" % (_index + 1)
			)
			d.check_exact_float(
				lab.state.reverse_hold_s, physical.reverse_hold_s,
			"gearbox.trace.tick_%d_reverse_hold_verbatim" % (_index + 1)
			)
			d.check_exact_float(
				lab.state.drift_timer_s, physical.drift_timer_s,
			"gearbox.trace.tick_%d_drift_timer_verbatim" % (_index + 1)
			)
			d.check_exact_float(
				lab.state.surge_cooldown_s, physical.surge_cooldown_s,
			"gearbox.trace.tick_%d_surge_cooldown_verbatim" % (_index + 1)
			)
			d.check_exact_float(
				lab.state.contact_immunity_s, physical.contact_immunity_s,
			"gearbox.trace.tick_%d_contact_immunity_verbatim" % (_index + 1)
			)
			d.check_exact_float(
				lab.state.valid_progress_m, physical.valid_progress_m,
			"gearbox.trace.tick_%d_progress_verbatim" % (_index + 1)
		)
			compared += 1
		await get_tree().physics_frame
	d.check(not lab.failed, "gearbox.trace.run_not_failed: " + str(lab.failure_reason))
	d.check(compared == GEARBOX_TRACE_TICKS, "gearbox.trace.all_ticks_compared")
	await _teardown_lab(lab)

	# Part 2: an independent fresh run reproduces position, velocity, heading,
	# body transform, gear and rpm bit-for-bit after a configure/idle baseline.
	var reference_lab = _make_lab([])
	if reference_lab == null:
		return
	var idle_commands: Array = []
	for _index in range(GEARBOX_RECONFIG_IDLE_TICKS):
		idle_commands.append(d.idle_command())
	var trace_commands: Array = []
	for _index in range(GEARBOX_TRACE_TICKS):
		trace_commands.append(d.throttle_command(1.0))
	var reference_ready := await _gearbox_manual_run(reference_lab, idle_commands)
	d.check(reference_ready, "gearbox.trace.reference_idle_ran")
	var reconfigured: bool = reference_lab.configure(
		reference_lab.tuning, reference_lab.adapter_config, trace_commands
	)
	d.check(reconfigured, "gearbox.trace.reference_reconfigure_accepted")
	var reference_ran := await _gearbox_manual_run(reference_lab, trace_commands)
	d.check(reference_ran, "gearbox.trace.reference_run_ran")
	var reference = _gearbox_capture(reference_lab)
	# Tear the reference laboratory down before the independent run: both cars
	# share one physics world and spawn lane, so a parked reference body would
	# otherwise block the fresh car once it caught up.
	await _teardown_lab(reference_lab)
	var fresh_lab = _make_lab(trace_commands)
	if fresh_lab == null:
		return
	var fresh_ran := await _gearbox_manual_run(fresh_lab, trace_commands)
	d.check(fresh_ran, "gearbox.trace.fresh_run_ran")
	var fresh = _gearbox_capture(fresh_lab)
	d.check(
		reference["trace"].size() == fresh["trace"].size(),
		"gearbox.trace.entry_count_matches"
	)
	var mismatches := 0
	for index in range(mini(reference["trace"].size(), fresh["trace"].size())):
		if reference["trace"][index] != fresh["trace"][index]:
			mismatches += 1
	d.check(
		mismatches == 0,
		"gearbox.trace.bit_identical_position_velocity_heading_body_gear_rpm (mismatches=%d)"
		% mismatches
	)
	d.check(reference["events"] == fresh["events"], "gearbox.trace.shift_events_identical")
	d.check(reference["gearbox"] == fresh["gearbox"], "gearbox.trace.final_gearbox_state_identical")
	measurements["gearbox_trace_entries"] = reference["trace"].size()
	measurements["gearbox_trace_mismatches"] = mismatches
	await _teardown_lab(fresh_lab)


# --- M1.1 post-commit gearbox failure paths -------------------------------

## Forces a real COMMITTED adapter tick whose gearbox proposal or mirror then
## refuses. The body has physically advanced before the refusal, so the
## laboratory must restore the canonical gearbox, keep the last published pair,
## mark the pose unreconciled and survive `configure()` without allowing another
## adapter call.
func _gearbox_failure_path_checks() -> void:
	await _gearbox_proposal_refusal_checks()
	await _gearbox_mirror_refusal_checks()


func _gearbox_proposal_refusal_checks() -> void:
	var lab = _make_lab([])
	if lab == null:
		return
	if not _gearbox_api_available(lab):
		await _teardown_lab(lab)
		return
	lab.set_auto_tick(false)
	await _settle()
	var warmed: bool = await _gearbox_manual_run(lab, _throttle_commands(40))
	d.check(warmed, "gearbox.failure.proposal.warmup_committed")
	if not warmed:
		await _teardown_lab(lab)
		return
	var state_before := d.snapshot_state(lab.state)
	var box_before: Dictionary = lab.get_gearbox_snapshot()
	var gear_before := int(lab.state.gear_index)
	var body_before: Transform3D = lab.body.global_transform
	var steps_before := int(lab.steps_called)
	var refusals_before := int(lab.get_gearbox_telemetry()["gearbox_refusals"])
	var injector := GearboxFaultInjector.new(
		lab.make_laboratory_gearbox_config(), "proposal_refused"
	)
	injector.restore_state(lab.gearbox.get_state())
	lab.gearbox = injector
	var result = lab.step_once(d.throttle_command(1.0))
	d.check(result != null, "gearbox.failure.proposal.result_present")
	if result != null:
		d.check(
			int(result.status) == int(AdapterScript.Status.COMMITTED),
			"gearbox.failure.proposal.physical_commit_happened"
		)
	d.check(lab.failed, "gearbox.failure.proposal.lab_failed: " + str(lab.failure_reason))
	d.check(lab.halted, "gearbox.failure.proposal.lab_halted")
	d.check(lab.is_drive_replay_blocked(), "gearbox.failure.proposal.body_pose_marked_stale")
	d.check(
		str(lab.get_drive_replay_block_reason()) != "",
		"gearbox.failure.proposal.block_reason_present"
	)
	d.check(
		int(lab.get_gearbox_telemetry()["gearbox_refusals"]) == refusals_before + 1,
		"gearbox.failure.proposal.refusal_counted"
	)
	d.check(
		int(lab.steps_called) == steps_before + 1,
		"gearbox.failure.proposal.exactly_one_adapter_call"
	)
	d.check(
		d.snapshot_state(lab.state) == state_before,
		"gearbox.failure.proposal.published_pair_untouched"
	)
	d.check(
		int(lab.state.gear_index) == gear_before,
		"gearbox.failure.proposal.published_gear_unchanged"
	)
	d.check(
		lab.get_gearbox_snapshot() == box_before,
		"gearbox.failure.proposal.canonical_restored"
	)
	var travel: float = lab.body.global_transform.origin.distance_to(body_before.origin)
	d.check(
		travel > 1e-4,
		"gearbox.failure.proposal.nonzero_physical_travel (travel=%.6f)" % travel
	)
	# A failed laboratory refuses a drive restore explicitly, with no live pair
	# mutation.
	var restore_pair = lab.snapshot_drive_state()
	var restored: bool = lab.restore_drive_snapshot(restore_pair)
	d.check(not restored, "gearbox.failure.restore_on_failed_lab_refused")
	d.check(
		d.snapshot_state(lab.state) == state_before,
		"gearbox.failure.failed_restore_no_published_change"
	)
	d.check(
		lab.get_gearbox_snapshot() == box_before,
		"gearbox.failure.failed_restore_no_canonical_change"
	)
	d.check(
		str(lab.get_drive_restore_error()) != "",
		"gearbox.failure.failed_restore_reason_recorded"
	)
	d.check(
		lab.is_drive_replay_blocked(),
		"gearbox.failure.failed_restore_keeps_pose_block"
	)
	_gearbox_assert_pose_block_survives_configure(lab, "gearbox.failure.proposal")
	await _gearbox_assert_auto_tick_refused(lab, "gearbox.failure.proposal")
	await _teardown_lab(lab)


func _gearbox_mirror_refusal_checks() -> void:
	var lab = _make_lab([])
	if lab == null:
		return
	if not _gearbox_api_available(lab):
		await _teardown_lab(lab)
		return
	lab.set_auto_tick(false)
	await _settle()
	var warmup_ticks: int = await _gearbox_warmup_until_speed(lab, 8.5, 300)
	var speed: float = lab.state.forward_speed_m_s()
	d.check(
		warmup_ticks > 0 and speed > 8.5,
		"gearbox.failure.mirror.warmup_above_first_upshift (ticks=%d speed=%.3f)"
			% [warmup_ticks, speed]
	)
	if speed <= 8.5:
		await _teardown_lab(lab)
		return
	# Install a known, internally consistent pre-tick pair so the abandoned
	# proposal would visibly advance the canonical gear (speed is above the first
	# upshift threshold). The rollback must put exactly this state back.
	var inner: AutomaticGearbox = lab.gearbox
	var pre_box := GearboxScript.GearboxState.new()
	pre_box.gear_index = 1
	pre_box.shift_cooldown_s = 0.0
	pre_box.normalized_rpm = 0.0
	d.check(inner.restore_state(pre_box), "gearbox.failure.mirror.pre_tick_pair_installed")
	lab.state.gear_index = 1
	var state_before := d.snapshot_state(lab.state)
	var box_before: Dictionary = lab.get_gearbox_snapshot()
	var events_before: Array = lab.get_gear_shift_events().duplicate()
	var body_before: Transform3D = lab.body.global_transform
	var steps_before := int(lab.steps_called)
	var injector := GearboxFaultInjector.new(
		lab.make_laboratory_gearbox_config(), "mirror_refused"
	)
	injector.restore_state(inner.get_state())
	lab.gearbox = injector
	var result = lab.step_once(d.throttle_command(1.0))
	d.check(result != null, "gearbox.failure.mirror.result_present")
	if result != null:
		d.check(
			int(result.status) == int(AdapterScript.Status.COMMITTED),
			"gearbox.failure.mirror.physical_commit_happened"
		)
	d.check(lab.failed, "gearbox.failure.mirror.lab_failed: " + str(lab.failure_reason))
	d.check(lab.halted, "gearbox.failure.mirror.lab_halted")
	d.check(lab.is_drive_replay_blocked(), "gearbox.failure.mirror.body_pose_marked_stale")
	d.check(
		str(lab.get_drive_replay_block_reason()) != "",
		"gearbox.failure.mirror.block_reason_present"
	)
	d.check(
		int(lab.steps_called) == steps_before + 1,
		"gearbox.failure.mirror.exactly_one_adapter_call"
	)
	# The canonical gear must be put back, not left advanced by the abandoned
	# proposal.
	var canonical_after: Dictionary = lab.get_gearbox_snapshot()
	d.check(
		canonical_after == box_before,
		"gearbox.failure.mirror.canonical_gear_and_dwell_restored"
	)
	d.check(
		int(canonical_after["gear_index"]) == 1,
		"gearbox.failure.mirror.canonical_gear_is_pre_tick"
	)
	d.check_exact_float(
		float(canonical_after["shift_cooldown_s"]), 0.0,
		"gearbox.failure.mirror.canonical_dwell_is_pre_tick"
	)
	d.check_exact_float(
		float(canonical_after["normalized_rpm"]), 0.0,
	"gearbox.failure.mirror.canonical_rpm_is_pre_tick"
	)
	d.check(
		d.snapshot_state(lab.state) == state_before,
		"gearbox.failure.mirror.published_pair_untouched"
	)
	d.check(
		int(lab.state.gear_index) == int(box_before["gear_index"]),
		"gearbox.failure.mirror.published_gear_matches_canonical"
	)
	d.check(
		lab.get_gear_shift_events() == events_before,
		"gearbox.failure.mirror.no_shift_event_published"
	)
	var travel: float = lab.body.global_transform.origin.distance_to(body_before.origin)
	d.check(
		travel > 1e-4,
		"gearbox.failure.mirror.nonzero_physical_travel (travel=%.6f)" % travel
	)
	_gearbox_assert_pose_block_survives_configure(lab, "gearbox.failure.mirror")
	await _gearbox_assert_auto_tick_refused(lab, "gearbox.failure.mirror")
	await _teardown_lab(lab)


# --- M1.8 wall-impact integration ----------------------------------------


func _case_wall_impact_integration() -> void:
	await _wall_hit_publication_and_retry_checks()
	await _wall_refusal_paths_emit_no_event_checks()
	await _wall_postcommit_gearbox_failure_withholds_witness_checks()
	await _wall_scope_retirement_keeps_car_state_checks()


## Drives one real pinned-Jolt head-on hit against the authored contact-bay
## frontal wall through the laboratory's own tick path, then proves the event
## was published on that committed tick and coalesces identical retries.
func _wall_hit_publication_and_retry_checks() -> void:
	var lab = _make_wall_hit_lab([])
	if lab == null:
		return
	lab.set_auto_tick(false)
	await _settle()
	_place_wall_lab_at_spawn(lab)
	await _settle()
	d.check_exact_float(lab.state.heading_rad, 0.0, "wall.spawn.heading_is_zero")
	d.check(not lab.is_course_limit_reached(), "wall.spawn.inside_course_limits")
	var committed_before := int(lab.ticks_committed)
	var witness = null
	var hit_index := -1
	for index in range(WALL_MAX_TICKS):
		var result = lab.step_once(d.throttle_command(1.0))
		if result == null:
			d.check(false, "wall.run.tick_%d_returned_null: %s" % [index, lab.failure_reason])
			break
		if result.has_wall_response_witness and result.has_wall_contact_point:
			witness = result
			hit_index = index
			break
	if witness == null:
		d.check(false, "wall.run.committed_wall_witness_occurred")
		await _teardown_lab(lab)
		return
	d.check(
		int(witness.status) == int(AdapterScript.Status.COMMITTED),
		"wall.run.witness_status_committed"
	)
	d.check(
		int(lab.ticks_committed) == committed_before + hit_index + 1,
		"wall.run.one_commit_per_tick_up_to_witness"
	)
	d.check(not lab.failed and not lab.halted, "wall.run.laboratory_not_failed_or_halted")
	var telemetry: Dictionary = lab.get_wall_event_telemetry()
	d.check(int(telemetry["published"]) == 1, "wall.pub.exactly_one_event_published")
	d.check(int(telemetry["coalesced"]) == 0, "wall.pub.no_coalesce_on_first_publication")
	d.check(int(telemetry["refused"]) == 0, "wall.pub.no_refusal_on_first_publication")
	d.check(int(telemetry["identity_tick_slots"]) <= 1, "wall.pub.retry_id_map_is_bounded")
	d.check(str(telemetry["diagnostic"]) == "", "wall.pub.no_diagnostic_on_success")
	d.check(lab.get_wall_event_count() == 1, "wall.pub.ledger_retains_one_event")
	var event := lab.get_last_wall_event()
	d.check(event != null, "wall.pub.last_event_present")
	if event == null:
		await _teardown_lab(lab)
		return
	d.check(
		event.event_id.begins_with(DriveLabScript.WALL_EVENT_ID_PREFIX + "."),
		"wall.pub.caller_owned_event_id_prefix"
	)
	d.check(
		event.primary_car_id == DriveLabScript.WALL_EVENT_PRIMARY_CAR_ID,
		"wall.pub.stable_primary_car_id"
	)
	d.check(
		int(event.tick_index) == int(lab.ticks_committed),
		"wall.pub.event_matches_published_tick"
	)
	d.check(event.committed, "wall.pub.event_marked_committed")
	d.check(str(event.contact_id) == "", "wall.pub.wall_event_has_no_contact_link")
	var expected_severity := ImpactEventScript.stable_norm(
		witness.wall_pre_response_velocity_world_m_s
		- witness.wall_post_response_velocity_world_m_s
	)
	d.check_close(
		event.severity_m_s, expected_severity, WALL_SEVERITY_TOLERANCE_M_S,
		"wall.pub.severity_is_witness_change"
	)
	d.check_vector_close(
		event.post_contact_velocity_world_m_s,
		witness.wall_post_response_velocity_world_m_s,
		WALL_VECTOR_TOLERANCE_M,
		"wall.pub.post_velocity_is_witness_value"
	)
	d.check_vector_close(
		event.contact_point_world_m, witness.wall_contact_point,
		WALL_VECTOR_TOLERANCE_M, "wall.pub.world_point_is_witness_value"
	)
	var expected_local: Vector3 = (
		witness.wall_contact_transform.affine_inverse() * witness.wall_contact_point
	)
	d.check_vector_close(
		event.contact_point_local_m, expected_local, WALL_LOCAL_TOLERANCE_M,
		"wall.pub.local_point_is_collision_time_inverse"
	)
	d.check(event.imparted_motion_m == Vector3.ZERO, "wall.pub.imparted_motion_zero")
	d.check(
		event.region == ImpactEventScript.ContactRegion.FRONT,
		"wall.pub.head_on_front_region"
	)
	d.check_vector_close(
		event.contact_normal_world_m, Vector3(0.0, 0.0, 1.0),
		WALL_NORMAL_TOLERANCE, "wall.pub.frontal_normal_projects_to_plus_z"
	)
	d.check_exact_float(
		event.contact_normal_world_m.y, 0.0,
		"wall.pub.normal_road_plane_projected"
	)
	d.check(event.is_valid(), "wall.pub.event_is_valid")
	d.check(event.severity_m_s > 15.0, "wall.pub.real_hit_exceeds_15_m_s")
	d.check(
		event.post_contact_velocity_world_m_s.length()
			< witness.wall_pre_response_velocity_world_m_s.length() * 0.2,
		"wall.pub.real_hit_loses_most_inward_speed"
	)
	measurements["wall_hit_tick"] = hit_index
	measurements["wall_event_id"] = event.event_id
	measurements["wall_severity_m_s"] = event.severity_m_s
	measurements["wall_region"] = event.region_name()
	var state_snapshot := d.snapshot_state(lab.state)
	var body_snapshot: Transform3D = lab.body.global_transform
	var first_retry: bool = lab.publish_wall_event(witness)
	d.check(first_retry, "wall.retry.first_returns_represented")
	var telemetry_after_first: Dictionary = lab.get_wall_event_telemetry()
	d.check(int(telemetry_after_first["coalesced"]) == 1, "wall.retry.first_coalesced")
	d.check(
		int(telemetry_after_first["published"]) == 1,
		"wall.retry.first_does_not_publish_twice"
	)
	d.check(lab.get_wall_event_count() == 1, "wall.retry.ledger_still_one_event")
	var retried := lab.get_last_wall_event()
	d.check(
		retried != null and retried.event_id == event.event_id,
		"wall.retry.same_caller_owned_id"
	)
	d.check(
		lab.find_wall_event(event.event_id) != null,
		"wall.retry.retained_by_original_id"
	)
	var second_retry: bool = lab.publish_wall_event(witness)
	d.check(second_retry, "wall.retry.second_returns_represented")
	d.check(
		int(lab.get_wall_event_telemetry()["coalesced"]) == 2,
		"wall.retry.second_coalesced"
	)
	d.check(
		lab.get_wall_event_count() == 1,
		"wall.retry.ledger_still_one_event_after_second"
	)
	d.check(
		d.snapshot_state(lab.state) == state_snapshot,
		"wall.retry.publication_leaves_car_state_unchanged"
	)
	d.check(
		lab.body.global_transform == body_snapshot,
		"wall.retry.publication_leaves_body_pose_unchanged"
	)
	# The accepted Result is caller-owned and mutable. Mutating any
	# authoritative witness field after the first publication must be refused
	# before an ID, event or ledger entry appears; an exact restore must still
	# coalesce as the same event.
	var saved_witness := _saved_wall_witness_state(witness)
	var base_telemetry: Dictionary = lab.get_wall_event_telemetry()
	var base_digest := lab.get_wall_event_content_digest()
	var base_last_id := lab.get_last_wall_event().event_id
	for entry in [
		{"key": "contact_point", "field": "point", "token": "contact point"},
		{"key": "contact_normal", "field": "normal", "token": "contact normal"},
		{"key": "pre_response_velocity", "field": "pre_velocity", "token": "pre-response velocity"},
		{"key": "post_response_velocity", "field": "post_velocity", "token": "post-response velocity"},
		{"key": "collision_frame_origin", "field": "frame_origin", "token": "collision frame"},
		{"key": "collision_frame_basis", "field": "frame_basis", "token": "collision frame"},
		{"key": "response_witness_flag", "field": "response_flag", "token": "wall response witness flag"},
		{"key": "contact_point_witness_flag", "field": "contact_flag", "token": "wall contact point witness flag"},
		{"key": "adapter_status", "field": "status", "token": "adapter result status"},
	]:
		_apply_wall_witness_mutation(witness, str(entry["field"]))
		var iteration_base: Dictionary = lab.get_wall_event_telemetry()
		var mutated_retry: bool = lab.publish_wall_event(witness)
		var key := str(entry["key"])
		d.check(not mutated_retry, "wall.mutant.%s_refused" % key)
		var mutant_telemetry: Dictionary = lab.get_wall_event_telemetry()
		d.check(
			int(mutant_telemetry["published"]) == int(base_telemetry["published"]),
			"wall.mutant.%s_no_new_publication" % key
		)
		d.check(
			int(mutant_telemetry["coalesced"]) == int(base_telemetry["coalesced"]),
			"wall.mutant.%s_no_coalesce" % key
		)
		d.check(
			int(mutant_telemetry["refused"]) == int(iteration_base["refused"]) + 1,
			"wall.mutant.%s_counts_one_refusal" % key
		)
		d.check(
			lab.get_wall_event_count() == 1,
			"wall.mutant.%s_retains_one_event" % key
		)
		d.check(
			int(mutant_telemetry["identity_tick_slots"]) <= 1,
			"wall.mutant.%s_no_second_id_slot" % key
		)
		d.check(
			lab.get_wall_event_content_digest() == base_digest,
			"wall.mutant.%s_digest_unchanged" % key
		)
		var mutant_last := lab.get_last_wall_event()
		d.check(
			mutant_last != null and mutant_last.event_id == base_last_id,
			"wall.mutant.%s_last_event_unchanged" % key
		)
		var mutant_diagnostic := str(lab.get_wall_event_diagnostic())
		d.check(
			mutant_diagnostic.contains("fingerprint mismatch")
				and mutant_diagnostic.contains(str(entry["token"])),
			"wall.mutant.%s_specific_diagnostic" % key
		)
		_restore_wall_witness_state(witness, saved_witness)
	var restored_retry: bool = lab.publish_wall_event(witness)
	d.check(restored_retry, "wall.mutant.restored_witness_still_coalesces")
	d.check(
		int(lab.get_wall_event_telemetry()["coalesced"])
			== int(base_telemetry["coalesced"]) + 1,
		"wall.mutant.restore_does_not_forge_a_second_event"
	)
	# A fresh Result carrying identical authoritative values is still foreign:
	# identity belongs to the accepted object, not merely to its contents.
	var foreign := MotorBodyAdapter.Result.new()
	foreign.status = witness.status
	foreign.committed_state = witness.committed_state
	foreign.has_wall_response_witness = witness.has_wall_response_witness
	foreign.has_wall_contact_point = witness.has_wall_contact_point
	foreign.wall_contact = witness.wall_contact
	foreign.wall_contact_point = witness.wall_contact_point
	foreign.wall_contact_normal = witness.wall_contact_normal
	foreign.wall_pre_response_velocity_world_m_s = (
		witness.wall_pre_response_velocity_world_m_s
	)
	foreign.wall_post_response_velocity_world_m_s = (
		witness.wall_post_response_velocity_world_m_s
	)
	foreign.wall_contact_transform = witness.wall_contact_transform
	var before_foreign: Dictionary = lab.get_wall_event_telemetry()
	var foreign_digest := lab.get_wall_event_content_digest()
	var foreign_result: bool = lab.publish_wall_event(foreign)
	d.check(not foreign_result, "wall.foreign_identical_result_refused")
	var foreign_telemetry: Dictionary = lab.get_wall_event_telemetry()
	d.check(
		int(foreign_telemetry["refused"]) == int(before_foreign["refused"]) + 1,
		"wall.foreign_identical_result_counts_refusal"
	)
	d.check(
		int(foreign_telemetry["published"]) == int(before_foreign["published"]),
		"wall.foreign_identical_result_no_publication"
	)
	d.check(
		lab.get_wall_event_content_digest() == foreign_digest,
		"wall.foreign_identical_result_digest_unchanged"
	)
	d.check(
		str(lab.get_wall_event_diagnostic()).contains(
			"not the current accepted canonical pair"
		),
		"wall.foreign_identical_result_identity_diagnostic"
	)
	# A stale later tick must not republish the earlier tick's witness either.
	var later_tick = lab.step_once(d.throttle_command(1.0))
	d.check(
		later_tick != null and not lab.failed and not lab.halted,
		"wall.stale.later_tick_committed"
	)
	var before_stale: Dictionary = lab.get_wall_event_telemetry()
	var stale_digest := lab.get_wall_event_content_digest()
	var stale_last_id := lab.get_last_wall_event().event_id
	var stale_retry: bool = lab.publish_wall_event(witness)
	d.check(not stale_retry, "wall.stale.old_witness_refused")
	var stale_telemetry: Dictionary = lab.get_wall_event_telemetry()
	d.check(
		int(stale_telemetry["refused"]) == int(before_stale["refused"]) + 1,
		"wall.stale.counts_one_refusal"
	)
	d.check(
		int(stale_telemetry["published"]) == int(before_stale["published"]),
		"wall.stale.no_new_publication"
	)
	d.check(
		lab.get_wall_event_content_digest() == stale_digest,
		"wall.stale.digest_unchanged"
	)
	d.check(
		lab.get_last_wall_event().event_id == stale_last_id,
		"wall.stale.last_event_unchanged"
	)
	d.check(
		str(lab.get_wall_event_diagnostic()).contains(
			"not the current accepted canonical pair"
		),
		"wall.stale.tick_diagnostic"
	)
	lab.retire_wall_event_scope()
	d.check(
		not lab.publish_wall_event(witness),
		"wall.retry.retired_witness_cannot_republish_in_new_scope"
	)
	d.check(lab.get_wall_event_count() == 0, "wall.retry.retired_scope_stays_empty")
	await _teardown_lab(lab)


## Saves every authoritative witness field the accepted-state fingerprint
## covers, by value, so the mutation regression can restore the real witness.
func _saved_wall_witness_state(witness) -> Dictionary:
	return {
		"status": witness.status,
		"has_response_witness": witness.has_wall_response_witness,
		"has_contact_point": witness.has_wall_contact_point,
		"point": witness.wall_contact_point,
		"normal": witness.wall_contact_normal,
		"pre_velocity": witness.wall_pre_response_velocity_world_m_s,
		"post_velocity": witness.wall_post_response_velocity_world_m_s,
		"frame": witness.wall_contact_transform,
	}


## Restores a saved witness snapshot exactly. Value-type fields copy, so the
## accepted Result becomes byte-identical to its state at acceptance.
func _restore_wall_witness_state(witness, saved: Dictionary) -> void:
	witness.status = saved["status"]
	witness.has_wall_response_witness = saved["has_response_witness"]
	witness.has_wall_contact_point = saved["has_contact_point"]
	witness.wall_contact_point = saved["point"]
	witness.wall_contact_normal = saved["normal"]
	witness.wall_pre_response_velocity_world_m_s = saved["pre_velocity"]
	witness.wall_post_response_velocity_world_m_s = saved["post_velocity"]
	witness.wall_contact_transform = saved["frame"]


## Applies one bounded mutation to the accepted witness for the retry-gate
## regression. Only Result fields are touched; motor and body state stay put.
func _apply_wall_witness_mutation(witness, field: String) -> void:
	match field:
		"point":
			witness.wall_contact_point += Vector3(0.05, 0.0, 0.0)
		"normal":
			witness.wall_contact_normal += Vector3(0.01, 0.0, 0.0)
		"pre_velocity":
			witness.wall_pre_response_velocity_world_m_s += Vector3(0.1, 0.0, 0.0)
		"post_velocity":
			witness.wall_post_response_velocity_world_m_s += Vector3(0.1, 0.0, 0.0)
		"frame_origin":
			var moved: Transform3D = witness.wall_contact_transform
			moved.origin += Vector3(0.01, 0.0, 0.0)
			witness.wall_contact_transform = moved
		"frame_basis":
			var rotated: Transform3D = witness.wall_contact_transform
			rotated.basis = rotated.basis.rotated(Vector3.RIGHT, 0.01)
			witness.wall_contact_transform = rotated
		"response_flag":
			witness.has_wall_response_witness = false
		"contact_flag":
			witness.has_wall_contact_point = false
		"status":
			witness.status = MotorBodyAdapter.Status.REFUSED_MOTION_BOUND
		"committed_velocity":
			witness.committed_state.velocity_m_s.x += 0.1


## Adapter refusal, post-commit gearbox failure and the resulting stale-pose
## block must all emit no wall event.
func _wall_refusal_paths_emit_no_event_checks() -> void:
	var lab = _make_lab([])
	if lab != null:
		lab.set_auto_tick(false)
		await _settle()
		var result = lab.step_once(null)
		d.check(
			result != null
			and int(result.status) != int(AdapterScript.Status.COMMITTED),
			"wall.refusal.adapter_refusal_returned"
		)
		d.check(lab.failed, "wall.refusal.lab_failed")
		d.check(
			lab.get_wall_event_count() == 0,
			"wall.refusal.no_event_on_adapter_refusal"
		)
		var refusal_telemetry: Dictionary = lab.get_wall_event_telemetry()
		d.check(
			int(refusal_telemetry["published"]) == 0
			and int(refusal_telemetry["refused"]) == 0,
			"wall.refusal.no_publication_counters"
		)
		await _teardown_lab(lab)
	var lab2 = _make_lab([])
	if lab2 == null:
		return
	lab2.set_auto_tick(false)
	await _settle()
	await _gearbox_manual_run(lab2, _throttle_commands(20))
	var injector := GearboxFaultInjector.new(
		lab2.make_laboratory_gearbox_config(), "proposal_refused"
	)
	injector.restore_state(lab2.gearbox.get_state())
	lab2.gearbox = injector
	var failed = lab2.step_once(d.throttle_command(1.0))
	d.check(failed != null, "wall.refusal.gearbox_failure_result_present")
	d.check(
		lab2.failed and lab2.is_drive_replay_blocked(),
		"wall.refusal.pose_blocked"
	)
	d.check(
		lab2.get_wall_event_count() == 0,
		"wall.refusal.no_event_on_gearbox_failure"
	)
	var blocked = lab2.step_once(d.throttle_command(1.0))
	d.check(blocked == null, "wall.refusal.stale_pose_tick_returns_null")
	d.check(
		lab2.get_wall_event_count() == 0,
		"wall.refusal.no_event_on_stale_pose_block"
	)
	await _teardown_lab(lab2)


## Arms a position-gated gearbox refusal on the exact tick that reaches the
## authored wall. The physical tick carries a real wall witness, but the
## canonical pair is not published, so the laboratory must withhold the event
## and record why.
func _wall_postcommit_gearbox_failure_withholds_witness_checks() -> void:
	var lab = _make_wall_hit_lab([])
	if lab == null:
		return
	lab.set_auto_tick(false)
	await _settle()
	_place_wall_lab_at_spawn(lab)
	await _settle()
	var half_length: float = lab.hull_shape.size.z * 0.5
	var expected_stop_y: float = WALL_FACE_ROAD_Y_M - half_length
	var gap := INF
	var armed := false
	var guard := 0
	while guard < WALL_MAX_TICKS:
		var front_y: float = lab.state.position_m.y + half_length
		gap = WALL_FACE_ROAD_Y_M - front_y
		var step_m: float = maxf(lab.state.speed_m_s() * DriveLabScript.DT, 0.02)
		if gap <= step_m * 1.2:
			armed = true
			break
		var result = lab.step_once(d.throttle_command(1.0))
		if result == null:
			break
		guard += 1
	d.check(armed, "wall.withheld.car_reached_one_tick_of_wall (guard=%d)" % guard)
	if not armed:
		await _teardown_lab(lab)
		return
	var committed_before := int(lab.ticks_committed)
	var threshold: float = expected_stop_y - gap * 0.25
	var injector := GearboxPositionFaultInjector.new(
		lab.make_laboratory_gearbox_config(), threshold
	)
	injector.restore_state(lab.gearbox.get_state())
	lab.gearbox = injector
	var failing = lab.step_once(d.throttle_command(1.0))
	d.check(failing != null, "wall.withheld.failing_tick_returned_result")
	if failing != null:
		d.check(
			int(failing.status) == int(AdapterScript.Status.COMMITTED),
			"wall.withheld.physical_tick_committed"
		)
		d.check(
			failing.has_wall_response_witness and failing.has_wall_contact_point,
			"wall.withheld.real_wall_witness_present"
		)
	d.check(lab.failed and lab.halted, "wall.withheld.lab_failed_and_halted")
	d.check(lab.is_drive_replay_blocked(), "wall.withheld.pose_blocked")
	d.check(
		int(lab.ticks_committed) == committed_before,
		"wall.withheld.no_pair_published_for_witness_tick"
	)
	d.check(lab.get_wall_event_count() == 0, "wall.withheld.no_event_emitted")
	var withheld_telemetry: Dictionary = lab.get_wall_event_telemetry()
	d.check(int(withheld_telemetry["published"]) == 0, "wall.withheld.no_publish_counter")
	d.check(
		not str(withheld_telemetry["diagnostic"]).is_empty(),
		"wall.withheld.diagnostic_recorded"
	)
	d.check(
		str(withheld_telemetry["diagnostic"]).contains("withheld"),
		"wall.withheld.diagnostic_explains_withheld_witness"
	)
	var blocked = lab.step_once(d.throttle_command(1.0))
	d.check(blocked == null, "wall.withheld.stale_tick_returns_null")
	d.check(lab.get_wall_event_count() == 0, "wall.withheld.still_no_event")
	if failing != null:
		d.check(
			not lab.publish_wall_event(failing),
			"wall.withheld.direct_adapter_result_is_not_an_accepted_pair"
		)
		d.check(
			lab.get_wall_event_count() == 0,
			"wall.withheld.direct_retry_leaves_ledger_empty"
		)
	await _teardown_lab(lab)


## Reconfiguration and explicit retirement clear the event scope and advance
## its generation without moving the committed car or the physical body.
func _wall_scope_retirement_keeps_car_state_checks() -> void:
	var lab = _make_lab(_throttle_commands(5))
	if lab == null:
		return
	lab.set_auto_tick(false)
	await _settle()
	await _gearbox_manual_run(lab, _throttle_commands(3))
	var telemetry_before: Dictionary = lab.get_wall_event_telemetry()
	var generation_before := int(telemetry_before["scope_generation"])
	var state_before := d.snapshot_state(lab.state)
	var body_before: Transform3D = lab.body.global_transform
	var reconfigured: bool = lab.configure(d.make_tuning(), d.make_config(), [])
	d.check(reconfigured, "wall.reset.configure_accepted")
	var telemetry_after: Dictionary = lab.get_wall_event_telemetry()
	d.check(
		int(telemetry_after["scope_generation"]) == generation_before + 1,
		"wall.reset.scope_generation_advanced"
	)
	d.check(lab.get_wall_event_count() == 0, "wall.reset.ledger_empty")
	d.check(
		int(telemetry_after["published"]) == 0
			and int(telemetry_after["coalesced"]) == 0
			and int(telemetry_after["refused"]) == 0,
		"wall.reset.counters_zero"
	)
	d.check(str(telemetry_after["diagnostic"]) == "", "wall.reset.diagnostic_clear")
	d.check(int(telemetry_after["identity_tick_slots"]) == 0, "wall.reset.retry_id_map_clear")
	d.check(
		d.snapshot_state(lab.state) == state_before,
		"wall.reset.car_state_unchanged"
	)
	d.check(
		lab.body.global_transform == body_before,
		"wall.reset.body_pose_unchanged"
	)
	lab.retire_wall_event_scope()
	var telemetry_retired: Dictionary = lab.get_wall_event_telemetry()
	d.check(
		int(telemetry_retired["scope_generation"]) == generation_before + 2,
		"wall.reset.explicit_retire_advances_generation"
	)
	d.check(
		d.snapshot_state(lab.state) == state_before,
		"wall.reset.explicit_retire_car_state_unchanged"
	)
	d.check(
		lab.body.global_transform == body_before,
		"wall.reset.explicit_retire_body_unchanged"
	)
	await _teardown_lab(lab)


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
