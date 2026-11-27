class_name DriveLab
extends Node3D
## One-car driving laboratory on the committed M1.2 handling lab's asphalt
## 500 m straight.
##
## The laboratory owns exactly one `CharacterBody3D` with a `BoxShape3D` hull
## that matches `MotorBodyAdapter.Config.hull_size_m`, one visible graybox
## mesh, and one `CameraRig` chase instance. Every physics tick it samples one
## command (scripted schedule or minimal keyboard), calls
## `MotorBodyAdapter.step()` exactly once, commits the returned `CarState` and
## leaves the visual pose on the committed body transform. There is no second
## integration path: a refusal halts the run and paints the hull red.
##
## Scope: flat-ground one-car integration only. Ground adhesion, jumps, drift,
## car-car contact, full input routing, reset placement, surface modifiers and
## race progress are explicitly out of scope. No M1 acceptance result is
## claimed.
##
## Headless scripted mode never reads GUI input. Keyboard mode is a separate
## convenience path for interactive use.

const HandlingLabSceneScript := preload("res://scenes/laboratory/handling_lab.tscn")
const AdapterScript := preload("res://src/simulation/motor_body_adapter.gd")
const ArcadeMotorScript := preload("res://src/simulation/arcade_motor.gd")
const CarStateScript := preload("res://src/simulation/car_state.gd")
const DriverCommandScript := preload("res://src/simulation/driver_command.gd")
const CameraRigScript := preload("res://src/presentation/camera_rig.gd")

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
var lab_manifest: Dictionary = {}

var state: CarState = null
var last_result: MotorBodyAdapter.Result = null
var start_position_m := Vector2.ZERO

var steps_called := 0
var ticks_committed := 0
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
	_apply_start_pose()
	_sync_camera()
	if not failed and (tuning == null or not tuning.is_valid()):
		_fail("invalid laboratory motor tuning")
	elif not failed and (adapter_config == null or not adapter_config.is_valid()):
		_fail("invalid laboratory motor-body config")


func _exit_tree() -> void:
	if camera_rig != null and is_instance_valid(camera_rig):
		camera_rig.clear_target()
		camera_rig.queue_free()
		camera_rig = null


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
		_sync_camera()
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


func _apply_start_pose() -> void:
	var spawn := Vector3(-360.0, 0.0, 60.0)
	var heading := 0.0
	if _lab != null:
		var marker := _lab.get_node_or_null("Spawn_straight") as Marker3D
		if marker != null:
			spawn = marker.global_position
			heading = deg_to_rad(float(marker.get_meta("heading_deg")))
		elif not lab_manifest.is_empty():
			for bay in lab_manifest.get("bays", []):
				if String(bay.get("bay_id", "")) == "straight":
					spawn = bay.get("origin", spawn)
					heading = deg_to_rad(float(bay.get("yaw_deg", 0.0)))
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
	last_result = null
	if _material != null:
		_material.albedo_color = GRAYBOX_COLOR


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


static func _finite_positive_vec3(value: Vector3) -> bool:
	return (
		is_finite(value.x) and value.x > 0.0
		and is_finite(value.y) and value.y > 0.0
		and is_finite(value.z) and value.z > 0.0
	)
