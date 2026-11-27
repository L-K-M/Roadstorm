class_name DriveLab
extends Node3D
## One-car driving laboratory on the committed M1.2 handling lab's asphalt
## 500 m straight.
##
## The laboratory owns exactly one `CharacterBody3D` with a `BoxShape3D` hull
## that matches `MotorBodyAdapter.Config.hull_size_m`, one visible graybox
## mesh, one `CameraRig` chase instance and one `SpeedHud` instance under its
## own `CanvasLayer`. Every physics tick it samples one command (scripted
## schedule or minimal keyboard), calls `MotorBodyAdapter.step()` exactly once,
## commits the returned `CarState` and leaves the visual pose on the committed
## body transform. There is no second integration path: a refusal halts the run
## and paints the hull red.
##
## Presentation wiring (M1.5 slice): the committed components are instantiated
## into the real node tree instead of being merely preloaded. The HUD is the
## committed `scenes/ui/speed_hud.tscn` under one `CanvasLayer` owned by this
## laboratory, and it is refreshed only from a committed `CarState`. The camera
## rig is the committed `CameraRig`, whose single `Camera3D` follows the body.
## Keyboard mode adds two presentation controls: `C` cycles the camera mode and
## `Shift` is a momentary rear view. Scripted and headless mode never reads GUI
## input at all. Presentation actions never call the adapter, never write
## simulation or body state and never create a second viewport or camera.
##
## Keyboard focus-loss lifecycle: a key released while the window is unfocused
## never reaches `_unhandled_input()`, so every held keyboard level is dropped and
## rear view is released on Godot focus loss. A fresh press after refocus
## registers normally; scripted and headless command isolation is unchanged.
##
## Audio feedback (M1.5 slice): exactly one committed `VehicleFeedbackPlayer`
## child is built once, set up on entrance and started parked at idle. After a
## successful `MotorBodyAdapter.step()` commit it applies the committed
## `CarState` and the accepted normalized command only; the component never
## writes simulation state and this laboratory never calls the adapter for
## audio. An apply refusal is counted and reported, never fatal. Reconfiguring
## keeps the same single component and its two voices; teardown frees them with
## the laboratory. Headless dummy audio proves node ownership, stream stability
## and mapped values only, never audible quality.
##
## The laboratory has no drift telemetry source, so the HUD cue is the honest
## `GRIP` phase with a zero slip reading and no qualifying flag: it never claims
## a drift the flat straight cannot produce. Audio is wired structurally and
## numerically only: nothing here claims audible sound quality, visual
## readability or M1.5/M1 acceptance.
##
## Scope: flat-ground one-car integration only. Ground adhesion, jumps, drift,
## car-car contact, full input routing, reset placement, surface modifiers and
## race progress are explicitly out of scope. No M1 acceptance result is
## claimed.
##
## Spawn heading: `HandlingLabBuilder` headings grow toward local left
## (`_forward()` is `(-sin h, 0, -cos h)`), while `CarState` and
## `MotorBodyAdapter` headings grow toward local right (`nose_forward_world()`
## is `(sin h, 0, -cos h)`). The authored bay yaw is therefore converted once at
## each spawn input (marker metadata, then manifest fallback) so the committed
## state and the installed body basis both point along the authored bay forward.
## An authored zero yaw stays exactly positive zero.
##
## Headless scripted mode never reads GUI input. Keyboard mode is a separate
## convenience path for interactive use.

const HandlingLabSceneScript := preload("res://scenes/laboratory/handling_lab.tscn")
const AdapterScript := preload("res://src/simulation/motor_body_adapter.gd")
const ArcadeMotorScript := preload("res://src/simulation/arcade_motor.gd")
const CarStateScript := preload("res://src/simulation/car_state.gd")
const DriverCommandScript := preload("res://src/simulation/driver_command.gd")
const CameraRigScript := preload("res://src/presentation/camera_rig.gd")
const SpeedHudScript := preload("res://src/presentation/speed_hud.gd")
const SpeedHudScene := preload("res://scenes/ui/speed_hud.tscn")
const VehicleFeedbackScript := preload("res://src/audio/vehicle_feedback_player.gd")

enum CommandMode { SCRIPTED, KEYBOARD }

const DT := 1.0 / 60.0
## Gap between the hull bottom and the road top at spawn. Small enough to read
## as resting on the road, large enough to avoid an initial penetration.
const HULL_REST_CLEARANCE_M := 0.02
## Hard cap on recorded per-tick telemetry entries.
const MAX_TICK_LOG := 1800
## Hard cap on one scripted run, 100 s at 60 Hz.
const MAX_SCRIPT_TICKS := 6000
## Stop this far before the authored end of the straight.
const COURSE_END_MARGIN_M := 40.0
## Stop this far behind the spawn before the car leaves the authored road.
const COURSE_START_MARGIN_M := 10.0
const GRAYBOX_COLOR := Color(0.55, 0.56, 0.60)
const FAILURE_COLOR := Color(0.85, 0.12, 0.10)

## Speed unit preference handed to the HUD. The laboratory reports the road-plane
## speed in km/h, matching the HUD's default unit.
const HUD_SPEED_UNIT: int = SpeedHudScript.SpeedUnit.KM_H
## The only drift phase this laboratory can honestly report: the flat straight
## has no slip or airborne telemetry to source a drift phase from.
const HUD_DRIFT_PHASE: int = SpeedHudScript.DriftPhase.GRIP
## Keyboard mode presentation controls.
const KEY_CAMERA_CYCLE := Key.KEY_C
const KEY_REAR_VIEW := Key.KEY_SHIFT

## Scripted schedules consume one array entry per tick; keyboard mode ignores
## the array and samples live key state instead.
var command_mode: CommandMode = CommandMode.SCRIPTED
var tuning: ArcadeMotor.MotorTuning = null
var adapter_config: MotorBodyAdapter.Config = null
var scripted_commands: Array = []

var body: CharacterBody3D = null
var hull_shape: BoxShape3D = null
var graybox_mesh: MeshInstance3D = null
var camera_rig: CameraRig = null
var hud_layer: CanvasLayer = null
var speed_hud: SpeedHud = null
var lab_manifest: Dictionary = {}
## Presentation defects are recorded instead of being papered over: a HUD that
## cannot be built or refuses a committed state leaves this string nonempty and
## is reported by validation rather than presented as working evidence.
var hud_error := ""
## The one synthesized feedback component owned by this laboratory. Exactly one
## exists; its two voices are children of it. Null only when construction failed.
var feedback_player: VehicleFeedbackPlayer = null
## Last audio setup/apply refusal reason, readable through `get_audio_error()`.
## Cleared by a successful apply; a build/setup defect persists until repaired.
var audio_error := ""

var state: CarState = null
var last_result: MotorBodyAdapter.Result = null
var start_position_m := Vector2.ZERO

var steps_called := 0
var ticks_committed := 0
var hud_updates := 0
var hud_rejected_updates := 0
var audio_updates := 0
var audio_rejected_updates := 0
var audio_apply_attempts := 0
var camera_mode_cycles := 0
var rear_view_holds := 0
var physics_callbacks := 0
var total_accepted_motion_m := 0.0
var max_speed_m_s := 0.0
var max_substeps := 0
var contact_ticks := 0
var wall_contact_ticks := 0
var max_prediction_discrepancy_m := 0.0
var max_commit_gap_m := 0.0
var max_remainder_m := 0.0
var tick_log: Array = []
var tick_log_dropped := 0

var failed := false
var failure_reason := ""
var halted := false
var halt_reason := ""
var completed := false

var _lab: Node3D = null
var _running := false
var _auto_tick := true
var _script_index := 0
var _straight_length_m := 500.0
var _end_reported := false
var _material: StandardMaterial3D = null
var _keys := {}


func _init() -> void:
	tuning = make_laboratory_tuning()
	adapter_config = make_laboratory_config()
	state = CarStateScript.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_lab = get_node_or_null("HandlingLab") as Node3D
	if _lab == null:
		_lab = HandlingLabSceneScript.instantiate()
		_lab.name = "HandlingLab"
		add_child(_lab)
	if _lab != null and _lab.has_meta("lab_manifest"):
		lab_manifest = _lab.get_meta("lab_manifest")
	var manifest_error := _read_straight_spec()
	if not manifest_error.is_empty() and not failed:
		_fail(manifest_error)
	_build_car()
	_build_camera_rig()
	_build_presentation()
	_build_audio_feedback()
	_apply_start_pose()
	_update_presentation()
	if not failed and (tuning == null or not tuning.is_valid()):
		_fail("invalid laboratory motor tuning")
	elif not failed and (adapter_config == null or not adapter_config.is_valid()):
		_fail("invalid laboratory motor-body config")


func _exit_tree() -> void:
	if feedback_player != null and is_instance_valid(feedback_player):
		var engine_player := feedback_player.get_engine_player()
		var tire_player := feedback_player.get_tire_player()
		if engine_player != null:
			engine_player.stop()
		if tire_player != null:
			tire_player.stop()
		feedback_player.teardown()
		feedback_player.queue_free()
		feedback_player = null
	if camera_rig != null and is_instance_valid(camera_rig):
		camera_rig.clear_target()
		camera_rig.queue_free()
		camera_rig = null
	if speed_hud != null and is_instance_valid(speed_hud):
		speed_hud.queue_free()
		speed_hud = null
	if hud_layer != null and is_instance_valid(hud_layer):
		hud_layer.queue_free()
		hud_layer = null


func _physics_process(_delta: float) -> void:
	physics_callbacks += 1
	if failed or halted:
		return
	if not _auto_tick:
		return
	var command = null
	if command_mode == CommandMode.KEYBOARD:
		command = _sample_keyboard_command()
	elif _running:
		if _script_index >= scripted_commands.size():
			_complete("script complete")
			return
		if _script_index >= MAX_SCRIPT_TICKS:
			_halt("script tick cap %d reached" % MAX_SCRIPT_TICKS)
			return
		command = scripted_commands[_script_index]
		_script_index += 1
	else:
		return
	step_once(command)


func _unhandled_input(event: InputEvent) -> void:
	if command_mode != CommandMode.KEYBOARD:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.keycode != 0:
			_keys[key.keycode] = key.pressed
		_apply_presentation_key(key)


func _notification(what: int) -> void:
	if what == Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT \
			or what == Node.NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear_keyboard_lifecycle_state()


# --- Public laboratory API -------------------------------------------------


## Laboratory adapter envelope. The hull size is duplicated in the car's
## `BoxShape3D`; `configure()` refuses a later mismatch.
func make_laboratory_config() -> MotorBodyAdapter.Config:
	var config := MotorBodyAdapter.Config.new()
	config.hull_size_m = Vector3(1.8, 1.0, 3.8)
	config.substep_max_length_m = 0.25
	config.max_substeps = 16
	config.sweep_margin_m = 0.0
	config.commit_safe_margin_m = 0.0
	config.envelope_epsilon_m = 1e-6
	config.contact_stop_epsilon_m = 1e-6
	config.wall_normal_max_up_alignment = 0.5
	config.wall_restitution = 0.0
	config.wall_tangential_keep = 1.0
	return config


## Explicit laboratory motor tuning. These are laboratory authoring values,
## not frozen product handling coefficients.
func make_laboratory_tuning() -> ArcadeMotor.MotorTuning:
	var curve: Array = [
		ArcadeMotorScript.SpeedAccelerationPoint.make(0.0, 8.0),
		ArcadeMotorScript.SpeedAccelerationPoint.make(10.0, 6.5),
		ArcadeMotorScript.SpeedAccelerationPoint.make(20.0, 4.0),
		ArcadeMotorScript.SpeedAccelerationPoint.make(32.0, 1.2),
		ArcadeMotorScript.SpeedAccelerationPoint.make(45.0, 0.0),
	]
	return ArcadeMotorScript.MotorTuning.make(
		curve, 12.0, 0.0, 0.05, 0.05, 1.5, 5.0, 1.0, 0.3, 4.0, 8.0
	)


## Supplies the tuning, adapter config and scripted command schedule. Valid
## callers must invoke this before the node enters the tree, or before its
## first tick. An invalid config is refused atomically: the laboratory is
## marked failed and no adapter call is made.
func configure(p_tuning, p_config, p_commands: Array = []) -> bool:
	if p_tuning == null or not p_tuning.is_valid():
		return _reject_configuration("invalid motor tuning")
	if p_config == null or not p_config.is_valid():
		return _reject_configuration("invalid motor-body config")
	if not _finite_positive_vec3(p_config.hull_size_m):
		return _reject_configuration("nonfinite or nonpositive hull size")
	if body != null and hull_shape != null:
		if hull_shape.size.distance_to(p_config.hull_size_m) > 1e-9:
			return _reject_configuration("hull size cannot change after the car is built")
	_reset_run_state()
	tuning = p_tuning
	adapter_config = p_config
	scripted_commands = p_commands.duplicate()
	_script_index = 0
	return true


func start() -> void:
	if failed or halted:
		return
	_running = true


func stop() -> void:
	_running = false


## Enables or disables the per-physics-tick automatic path. Tests use the
## disabled mode to drive `step_once()` deterministically.
func set_auto_tick(enabled: bool) -> void:
	_auto_tick = enabled


func is_auto_tick() -> bool:
	return _auto_tick


# --- Presentation API ------------------------------------------------------


## Cycles the single camera rig's mode CHASE -> NEAR_CHASE -> HOOD -> CHASE and
## returns the new mode. Presentation only: no adapter call, no state write.
## Without a usable rig there is nothing to cycle: the returned mode stays
## CHASE, exactly as `get_camera_mode()` reports it, and no cycle is counted.
func cycle_camera_mode() -> CameraRig.Mode:
	if camera_rig == null or not is_instance_valid(camera_rig):
		return CameraRig.Mode.CHASE
	var mode: CameraRig.Mode = camera_rig.cycle_mode()
	camera_mode_cycles += 1
	return mode


func get_camera_mode() -> CameraRig.Mode:
	if camera_rig == null or not is_instance_valid(camera_rig):
		return CameraRig.Mode.CHASE
	return camera_rig.get_mode()


func get_camera_mode_name() -> String:
	if camera_rig == null or not is_instance_valid(camera_rig):
		return ""
	return camera_rig.get_mode_name(camera_rig.get_mode())


## Momentary rear view on the same camera node. While held, the rig redirects
## its single `Camera3D` backwards; releasing restores the selected forward
## mode. No second camera or viewport is created.
func set_rear_view_held(active: bool) -> void:
	if camera_rig == null or not is_instance_valid(camera_rig):
		return
	if camera_rig.is_rear_held() == active:
		return
	camera_rig.hold_rear(active)
	rear_view_holds += 1


func is_rear_view_held() -> bool:
	if camera_rig == null or not is_instance_valid(camera_rig):
		return false
	return camera_rig.is_rear_held()


## The one speed HUD instance owned by this laboratory, or null when the HUD
## could not be built (see `get_hud_error()`).
func get_speed_hud() -> SpeedHud:
	return speed_hud


## The one `CanvasLayer` that carries the HUD. Owning it here keeps HUD
## teardown bound to the laboratory's own lifetime.
func get_hud_layer() -> CanvasLayer:
	return hud_layer


func get_hud_error() -> String:
	return hud_error


## True when the camera rig, its camera, the HUD layer and the HUD instance are
## all present and valid.
func is_presentation_ready() -> bool:
	return (
		camera_rig != null and is_instance_valid(camera_rig)
		and camera_rig.get_camera() != null
		and hud_layer != null and is_instance_valid(hud_layer)
		and speed_hud != null and is_instance_valid(speed_hud)
	)


## The laboratory's one `VehicleFeedbackPlayer`, or null when it could not be
## built (see `get_audio_error()`).
func get_feedback_player() -> VehicleFeedbackPlayer:
	return feedback_player


## True when the feedback component is present, set up and owns both voices.
func is_audio_ready() -> bool:
	return (
		feedback_player != null and is_instance_valid(feedback_player)
		and feedback_player.is_setup_complete()
		and feedback_player.get_engine_player() != null
		and feedback_player.get_tire_player() != null
	)


func get_audio_error() -> String:
	return audio_error


## Read-only audio diagnostics for validation. These describe presentation
## activity only; they never gate or alter the simulation run.
func get_audio_telemetry() -> Dictionary:
	var engine_stream_bytes := 0
	var tire_stream_bytes := 0
	var estimated_bytes := 0
	var last_pitch := 0.0
	var last_engine_db := 0.0
	var last_tire_db := 0.0
	var engine_playing := false
	var tire_playing := false
	var setup_complete := false
	if feedback_player != null and is_instance_valid(feedback_player):
		setup_complete = feedback_player.is_setup_complete()
		var engine_stream: AudioStreamWAV = feedback_player.get_engine_stream()
		var tire_stream: AudioStreamWAV = feedback_player.get_tire_stream()
		if engine_stream != null:
			engine_stream_bytes = int(engine_stream.data.size())
		if tire_stream != null:
			tire_stream_bytes = int(tire_stream.data.size())
		estimated_bytes = feedback_player.estimated_memory_bytes()
		last_pitch = feedback_player.get_last_engine_pitch_scale()
		last_engine_db = feedback_player.get_last_engine_volume_db()
		last_tire_db = feedback_player.get_last_tire_volume_db()
		var engine_player := feedback_player.get_engine_player()
		var tire_player := feedback_player.get_tire_player()
		engine_playing = engine_player != null and engine_player.playing
		tire_playing = tire_player != null and tire_player.playing
	return {
		"audio_ready": is_audio_ready(),
		"audio_setup_complete": setup_complete,
		"audio_updates": audio_updates,
		"audio_apply_attempts": audio_apply_attempts,
		"audio_rejected_updates": audio_rejected_updates,
		"audio_error": audio_error,
		"engine_stream_bytes": engine_stream_bytes,
		"tire_stream_bytes": tire_stream_bytes,
		"estimated_memory_bytes": estimated_bytes,
		"last_engine_pitch_scale": last_pitch,
		"last_engine_volume_db": last_engine_db,
		"last_tire_volume_db": last_tire_db,
		"engine_voice_playing": engine_playing,
		"tire_voice_playing": tire_playing,
	}


## Presentation-side counters for validation reporting. These describe
## presentation activity only; they never gate or alter the simulation run.
func get_presentation_telemetry() -> Dictionary:
	return {
		"hud_layer_present": hud_layer != null and is_instance_valid(hud_layer),
		"hud_instance_present": speed_hud != null and is_instance_valid(speed_hud),
		"hud_updates": hud_updates,
		"hud_rejected_updates": hud_rejected_updates,
		"hud_error": hud_error,
		"camera_mode": int(get_camera_mode()),
		"camera_mode_name": get_camera_mode_name(),
		"camera_mode_cycles": camera_mode_cycles,
		"rear_view_held": is_rear_view_held(),
		"rear_view_holds": rear_view_holds,
	}


## Exactly one integration call. Shared by `_physics_process()` and by tests;
## there is no other place that calls the adapter.
func step_once(command) -> MotorBodyAdapter.Result:
	if failed or halted:
		return null
	if body == null or hull_shape == null or state == null \
			or tuning == null or adapter_config == null:
		_fail("incomplete laboratory")
		return null
	if _course_limit_reached():
		_halt("course limit reached")
		return null
	var result := AdapterScript.step(
		body, hull_shape, state, command, tuning, adapter_config, DT
	)
	steps_called += 1
	last_result = result
	if result.status == MotorBodyAdapter.Status.COMMITTED:
		if result.committed_state == null or not result.committed_state.is_finite():
			_fail("nonfinite committed state")
			return result
		state = result.committed_state
		ticks_committed += 1
		_update_telemetry(result)
		_append_tick_log(result)
		_update_presentation()
		_update_audio_feedback(command)
		return result
	var reason := result.rejection_reason
	if reason.is_empty():
		reason = "adapter refused the tick"
	_fail(reason)
	return result


func is_visually_failed() -> bool:
	return _material != null and _material.albedo_color.is_equal_approx(FAILURE_COLOR)


func get_road_station_m() -> float:
	if state == null:
		return 0.0
	return state.position_m.y - start_position_m.y


func get_telemetry() -> Dictionary:
	return {
		"steps_called": steps_called,
		"ticks_committed": ticks_committed,
		"physics_callbacks": physics_callbacks,
		"total_accepted_motion_m": total_accepted_motion_m,
		"max_speed_m_s": max_speed_m_s,
		"max_substeps": max_substeps,
		"contact_ticks": contact_ticks,
		"wall_contact_ticks": wall_contact_ticks,
		"max_prediction_discrepancy_m": max_prediction_discrepancy_m,
		"max_commit_gap_m": max_commit_gap_m,
		"max_remainder_m": max_remainder_m,
		"tick_log_entries": tick_log.size(),
		"tick_log_dropped": tick_log_dropped,
		"road_station_m": get_road_station_m(),
		"failed": failed,
		"failure_reason": failure_reason,
		"halted": halted,
		"halt_reason": halt_reason,
		"completed": completed,
	}


# --- Construction ----------------------------------------------------------


func _read_straight_spec() -> String:
	if lab_manifest.is_empty():
		return "handling lab manifest is absent"
	var bays: Array = lab_manifest.get("bays", [])
	var straight: Dictionary = {}
	for bay in bays:
		if String(bay.get("bay_id", "")) == "straight":
			straight = bay
			break
	if straight.is_empty():
		return "straight bay is absent from the handling lab manifest"
	for section in straight.get("sections", []):
		if String(section.get("section_id", "")) == "straight.main":
			var length := float(section.get("length_m", 0.0))
			if not is_finite(length) or length <= 0.0:
				return "straight.main has a nonpositive length"
			_straight_length_m = length
			return ""
	return "straight.main section is absent from the straight bay"


func _build_car() -> void:
	var size := Vector3(1.8, 1.0, 3.8)
	if adapter_config != null and _finite_positive_vec3(adapter_config.hull_size_m):
		size = adapter_config.hull_size_m
	body = CharacterBody3D.new()
	body.name = "LabCar"
	hull_shape = BoxShape3D.new()
	hull_shape.size = size
	var shape_node := CollisionShape3D.new()
	shape_node.name = "HullShape"
	shape_node.shape = hull_shape
	body.add_child(shape_node)
	var box := BoxMesh.new()
	box.size = size
	graybox_mesh = MeshInstance3D.new()
	graybox_mesh.name = "GrayboxMesh"
	graybox_mesh.mesh = box
	_material = StandardMaterial3D.new()
	_material.albedo_color = GRAYBOX_COLOR
	_material.roughness = 0.9
	graybox_mesh.material_override = _material
	body.add_child(graybox_mesh)
	add_child(body)


func _build_camera_rig() -> void:
	camera_rig = CameraRigScript.new()
	camera_rig.name = "ChaseCameraRig"
	add_child(camera_rig)
	var viewport := get_viewport()
	if viewport != null and not camera_rig.attach_to_viewport(viewport):
		camera_rig.get_camera().current = true
	if body != null:
		camera_rig.set_target(body)


## Builds the laboratory's one `VehicleFeedbackPlayer`. The component owns its
## two voices and performs its own bounded reference setup on entrance. This
## owner starts both voices parked at the idle targets `setup()` installs;
## headless dummy audio accepts the play flags but proves no audible output.
## Repeated calls are refused so `configure()` can never leave duplicate
## players or voices behind.
func _build_audio_feedback() -> void:
	if feedback_player != null and is_instance_valid(feedback_player):
		return
	var player := VehicleFeedbackScript.new()
	player.name = "VehicleFeedback"
	add_child(player)
	feedback_player = player
	if not player.is_setup_complete():
		audio_error = player.get_last_error()
		print("[drive_lab] PRESENTATION DEFECT: ", audio_error)
		return
	var engine_player := player.get_engine_player()
	var tire_player := player.get_tire_player()
	if engine_player != null and tire_player != null:
		engine_player.play()
		tire_player.play()


## Builds the laboratory's own presentation nodes: one `CanvasLayer` carrying
## exactly one `SpeedHud` instance. Both are children of the laboratory, so
## freeing the laboratory frees them. A HUD that cannot be instantiated is
## recorded as a presentation defect and reported, never faked.
func _build_presentation() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "DriveLabHudLayer"
	add_child(hud_layer)
	var instance = SpeedHudScene.instantiate()
	if instance == null or not (instance is SpeedHud):
		if instance != null:
			instance.free()
		hud_error = "speed HUD scene did not instantiate a SpeedHud"
		print("[drive_lab] PRESENTATION DEFECT: ", hud_error)
		return
	instance.name = "SpeedHud"
	hud_layer.add_child(instance)
	speed_hud = instance as SpeedHud


func _apply_start_pose() -> void:
	var spawn := Vector3(-360.0, 0.0, 60.0)
	var heading := 0.0
	if _lab != null:
		var marker := _lab.get_node_or_null("Spawn_straight") as Marker3D
		if marker != null:
			spawn = marker.global_position
			heading = builder_heading_to_state(
				deg_to_rad(float(marker.get_meta("heading_deg")))
			)
		elif not lab_manifest.is_empty():
			for bay in lab_manifest.get("bays", []):
				if String(bay.get("bay_id", "")) == "straight":
					spawn = bay.get("origin", spawn)
					heading = builder_heading_to_state(
						deg_to_rad(float(bay.get("yaw_deg", 0.0)))
				)
					break
	state = CarStateScript.new()
	state.position_m = AdapterScript.world_vector_to_road(spawn)
	state.heading_rad = heading
	start_position_m = state.position_m
	if body == null or hull_shape == null:
		return
	var support_y := hull_shape.size.y * 0.5 + HULL_REST_CLEARANCE_M
	body.global_transform = Transform3D(
		AdapterScript.basis_from_heading(heading),
		Vector3(spawn.x, support_y, spawn.z)
	)


# --- Per-tick internals ----------------------------------------------------


func _sample_keyboard_command():
	var steer := 0.0
	if _keys.get(Key.KEY_A, false) or _keys.get(Key.KEY_LEFT, false):
		steer -= 1.0
	if _keys.get(Key.KEY_D, false) or _keys.get(Key.KEY_RIGHT, false):
		steer += 1.0
	var throttle := 1.0 if (_keys.get(Key.KEY_W, false) or _keys.get(Key.KEY_UP, false)) else 0.0
	var brake := 0.0
	if _keys.get(Key.KEY_S, false) or _keys.get(Key.KEY_DOWN, false) or _keys.get(Key.KEY_SPACE, false):
		brake = 1.0
	return DriverCommandScript.create(steer, throttle, brake, 0.0)


func _course_limit_reached() -> bool:
	if state == null or hull_shape == null:
		return false
	var station := state.position_m.y - start_position_m.y
	var half_length := hull_shape.size.z * 0.5
	if station + half_length >= _straight_length_m - COURSE_END_MARGIN_M:
		return true
	if station - half_length <= -COURSE_START_MARGIN_M:
		return true
	return false


func _update_telemetry(result: MotorBodyAdapter.Result) -> void:
	total_accepted_motion_m += result.accepted_motion_m.length()
	max_speed_m_s = maxf(max_speed_m_s, state.speed_m_s())
	max_substeps = maxi(max_substeps, result.substeps)
	if result.contact:
		contact_ticks += 1
	if result.wall_contact:
		wall_contact_ticks += 1
	max_prediction_discrepancy_m = maxf(
		max_prediction_discrepancy_m, result.prediction_commit_discrepancy_m
	)
	max_commit_gap_m = maxf(
		max_commit_gap_m, result.accepted_motion_m.distance_to(result.proposed_motion_m)
	)
	max_remainder_m = maxf(max_remainder_m, result.remainder_m)


func _append_tick_log(result: MotorBodyAdapter.Result) -> void:
	if tick_log.size() >= MAX_TICK_LOG:
		tick_log_dropped += 1
		return
	tick_log.append({
		"tick": ticks_committed,
		"callback_index": physics_callbacks,
		"status": int(result.status),
		"position_m": state.position_m,
		"velocity_m_s": state.velocity_m_s,
		"heading_rad": state.heading_rad,
		"grounded": state.grounded,
		"reverse_engaged": state.reverse_engaged,
		"body_transform": body.global_transform,
		"substeps": result.substeps,
		"contact": result.contact,
		"wall_contact": result.wall_contact,
		"proposed_motion_m": result.proposed_motion_m,
		"accepted_motion_m": result.accepted_motion_m,
		"prediction_commit_discrepancy_m": result.prediction_commit_discrepancy_m,
		"remainder_m": result.remainder_m,
	})


func _sync_camera() -> void:
	if camera_rig != null and is_instance_valid(camera_rig):
		camera_rig.update_target_pose(0.0)


## Refreshes every presentation consumer from the committed state: the camera
## pose and the speed HUD. Called after the initial pose and after every
## committed tick, so no presentation read ever observes an uncommitted state.
func _update_presentation() -> void:
	_sync_camera()
	_update_speed_hud()


## Pushes one committed `CarState` into the HUD. The cue is the honest grip
## phase for a flat straight: no slip reading, no qualifying claim. A rejected
## update is counted and recorded, because silently presenting a stale or wrong
## readout would be worse than reporting the defect.
func _update_speed_hud() -> void:
	if speed_hud == null or not is_instance_valid(speed_hud):
		return
	if state == null or not state.is_finite():
		hud_rejected_updates += 1
		hud_error = "committed state is absent or nonfinite at a HUD refresh"
		return
	var cue := SpeedHudScript.DriftCue.new(HUD_DRIFT_PHASE, false, 0.0)
	if speed_hud.update(state, cue, HUD_SPEED_UNIT):
		hud_updates += 1
		return
	hud_rejected_updates += 1
	if hud_error.is_empty():
		hud_error = "speed HUD refused a committed-state update"


## Applies one committed state and the already-accepted command to the single
## feedback component. Called only from the `COMMITTED` branch of
## `step_once()`, so an adapter refusal never reaches audio and audio never
## triggers a second motor call. A component refusal is recorded and counted;
## it never halts the simulation.
func _update_audio_feedback(command) -> void:
	if feedback_player == null or not is_instance_valid(feedback_player):
		return
	audio_apply_attempts += 1
	if state == null or not state.is_finite():
		_reject_audio_update("committed state is absent or nonfinite at an audio refresh")
		return
	if feedback_player.apply(state, command):
		audio_updates += 1
		audio_error = ""
		return
	_reject_audio_update(feedback_player.get_last_error())


func _reject_audio_update(reason: String) -> void:
	audio_rejected_updates += 1
	if audio_error.is_empty():
		audio_error = reason


## Keyboard-mode presentation controls. Called only from `_unhandled_input()`,
## which returns immediately in scripted and headless mode, so no GUI input is
## ever read there.
func _apply_presentation_key(key: InputEventKey) -> void:
	match key.keycode:
		KEY_CAMERA_CYCLE:
			# Auto-repeat must not advance the mode more than once per press.
			if key.pressed and not key.echo:
				cycle_camera_mode()
		KEY_REAR_VIEW:
			set_rear_view_held(key.pressed)


## Drops every held keyboard level and releases momentary rear view. Called on
## focus loss because a release delivered while the window is unfocused never
## reaches `_unhandled_input()`, which would otherwise latch throttle, brake,
## steering or rear view. Scripted and headless mode read no GUI input, so the
## clear cannot inject a command there; a fresh press after refocus registers
## normally.
func _clear_keyboard_lifecycle_state() -> void:
	_keys.clear()
	set_rear_view_held(false)


func _reset_run_state() -> void:
	failed = false
	failure_reason = ""
	halted = false
	halt_reason = ""
	completed = false
	_running = false
	_script_index = 0
	_end_reported = false
	steps_called = 0
	ticks_committed = 0
	physics_callbacks = 0
	total_accepted_motion_m = 0.0
	max_speed_m_s = 0.0
	max_substeps = 0
	contact_ticks = 0
	wall_contact_ticks = 0
	max_prediction_discrepancy_m = 0.0
	max_commit_gap_m = 0.0
	max_remainder_m = 0.0
	tick_log = []
	tick_log_dropped = 0
	# Presentation counters describe the current configuration, not the whole
	# lifetime of a node that is reconfigured with a new schedule.
	hud_updates = 0
	hud_rejected_updates = 0
	audio_updates = 0
	audio_rejected_updates = 0
	audio_apply_attempts = 0
	audio_error = ""
	camera_mode_cycles = 0
	rear_view_holds = 0
	last_result = null
	if _material != null:
		_material.albedo_color = GRAYBOX_COLOR
	_update_presentation()


func _reject_configuration(reason: String) -> bool:
	failed = true
	failure_reason = reason
	halted = true
	_running = false
	print("[drive_lab] CONFIG REFUSED: ", reason)
	_show_failure_visual()
	return false


func _fail(reason: String) -> void:
	if failed:
		return
	failed = true
	failure_reason = reason
	halted = true
	_running = false
	print("[drive_lab] REFUSED after %d committed ticks: %s" % [ticks_committed, reason])
	_show_failure_visual()


func _halt(reason: String) -> void:
	if failed or halted:
		return
	halted = true
	halt_reason = reason
	_running = false
	if not _end_reported:
		print("[drive_lab] HALT: ", reason)
		_end_reported = true


func _complete(reason: String) -> void:
	completed = true
	_halt(reason)


func _show_failure_visual() -> void:
	if _material != null:
		_material.albedo_color = FAILURE_COLOR


## Converts an authored handling-lab bay heading into the road-plane
## `CarState` heading convention. The builder's heading grows toward local
## left; `CarState`/`MotorBodyAdapter` grow toward local right. Negating once
## keeps the state nose and the installed body basis on the authored bay
## forward. A zero input returns positive zero, so zero-yaw behaviour is
## bit-for-bit unchanged.
static func builder_heading_to_state(builder_heading_rad: float) -> float:
	if builder_heading_rad == 0.0:
		return 0.0
	return -builder_heading_rad


static func _finite_positive_vec3(value: Vector3) -> bool:
	return (
		is_finite(value.x) and value.x > 0.0
		and is_finite(value.y) and value.y > 0.0
		and is_finite(value.z) and value.z > 0.0
	)
