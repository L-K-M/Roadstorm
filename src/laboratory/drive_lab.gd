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
## Course station: the straight has a fixed authored axis, established once at
## spawn from whichever input supplied the heading. `get_road_station_m()` and
## both course limits project road-plane displacement onto that axis, so a
## rotated bay measures travel along its own forward rather than along world
## road +y. A zero-yaw spawn produces the exact axis `(0, 1)`, which keeps the
## original y-difference arithmetic bit-for-bit unchanged.
##
## Automatic-gearbox integration (M1.1 bounded slice): exactly one
## `AutomaticGearbox` instance owns gear indication. Every accepted
## `MotorBodyAdapter` COMMITTED tick retains the canonical gearbox state, then
## proposes exactly once from that committed physical `CarState` at fixed `DT`,
## mirrors the canonical gear into the published `CarState`, and only then
## advances the published pair, telemetry, presentation and audio. A proposal,
## mirror, mirrored-agreement or committed-state refusal is an atomic failure
## path: the adapter commit is irreversible, so the laboratory restores the
## canonical gearbox to its retained pre-tick state, keeps the last published
## pair untouched, marks the body pose unreconciled, and halts without another
## adapter call. The physical body is never rolled back or teleported;
## `configure()` clears failure/halt flags but not the pose block, so no later
## tick can reuse the old published pair with the advanced body. That last pair
## remains internally consistent but is deliberately not reconciled with the
## irreversibly advanced body; validation proves no further adapter call
## happens.
##
## Replay/restore is explicitly state-only in this slice.
## `snapshot_drive_state()` captures the complete `CarState` + `GearboxState`
## pair. `restore_drive_snapshot()` validates the whole pair in a temporary
## gearbox, repairs the gear mirror, and publishes both together. It does not
## restore the body transform, so a restored laboratory blocks every tick
## (`is_drive_replay_blocked()`) until a future body-pose reconciliation
## operation exists. `start()` and the automatic physics path halt with
## `get_drive_replay_block_reason()` before consuming a scripted command or
## reporting completion, so a zero-tick run can never read as complete.
## Restoring a `CarState` alone is not offered: it cannot reproduce shift
## dwell or canonical rpm. Gear selection drives no audio here; the only gear
## display is the committed `CarState.gear_index` mirror the speed HUD shows.
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
const GearboxScript := preload("res://src/simulation/automatic_gearbox.gd")
const WallImpactProducerScript := preload("res://src/simulation/wall_impact_producer.gd")
const ImpactEventScript := preload("res://src/simulation/impact_event.gd")

## Hard cap on recorded gearbox shift events. Further events are counted as
## dropped instead of growing without bound.
const MAX_GEAR_SHIFT_EVENTS := 128
## Stable primary car identity for every laboratory wall impact event. One
## car, one identity; reconfiguration and new runs never change it.
const WALL_EVENT_PRIMARY_CAR_ID := "drive_lab.primary_car"
## Prefix of caller-owned wall event IDs. A full ID also carries the lab event
## scope generation, the committed tick index and a per-tick collision
## sequence, so a later tick cannot reuse an earlier ID even if the bounded
## ledger has already pruned that tick.
const WALL_EVENT_ID_PREFIX := "drive_lab.wall"
## Halt reason used after a state-only drive restore, which cannot advance the
## simulation until a body-pose reconciliation operation exists.
const DRIVE_STATE_ONLY_HALT := "state-only drive restore awaits body pose reconciliation"
## Block reason used after a COMMITTED physical tick whose gearbox pair could
## not be published. The body has already advanced and is never rolled back;
## ticks stay blocked until a future body-pose reconciliation operation exists.
const DRIVE_BODY_POSE_STALE_HALT := "committed physical tick left the body pose unreconciled"

## Complete state-only drive replay record: one committed `CarState` and the
## canonical `GearboxState` captured as a pair. The pair carries the shift
## cooldown and normalized rpm that a `CarState` alone cannot reproduce. It is
## deliberately not a runnable replay: restoring it does not reconcile the
## physical body transform, so the destination laboratory blocks ticks.
class DriveSnapshot extends RefCounted:
	var schema := "roadstorm.drive_snapshot.v1"
	var car_state: CarState = null
	var gearbox_state: AutomaticGearbox.GearboxState = null


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
## The laboratory's one canonical `AutomaticGearbox`. It owns gear indication,
## shift dwell and rpm; `state.gear_index` is only the published mirror.
var gearbox: AutomaticGearbox = null
## Physical `CarState` produced by the adapter on the most recent COMMITTED
## tick, before the gear mirror was applied. Diagnostic only; never published
## as the laboratory's committed pair.
var last_committed_physical: CarState = null
## Bounded shift-event telemetry, oldest first. Each entry is a Dictionary with
## `tick`, `from_gear`, `to_gear`, `direction`, `normalized_rpm` and
## `forward_speed_m_s`.
var gear_shift_events: Array = []
var gear_shift_events_dropped := 0
var gearbox_refusals := 0
var gearbox_failure_reason := ""
var drive_restores := 0
var drive_restore_refusals := 0
var drive_restore_refusal_reason := ""
## M1.8 wall-impact publication scope. The ledger is laboratory-owned and is
## never exposed mutably; tests read it through the surface below. A witness
## is published only after the adapter COMMITTED tick and the canonical
## gearbox/CarState pair were both accepted and published. A publication
## refusal records a diagnostic and never alters simulation or presentation.
var wall_event_ledger: ImpactEvent.Ledger = null
## Last published or coalesced retained record; read-only copies are returned.
var last_wall_event: ImpactEvent = null
var wall_events_published := 0
var wall_events_coalesced := 0
var wall_events_refused := 0
var wall_event_missed_witnesses := 0
var wall_event_diagnostic := ""
var _wall_event_scope_generation := 0
var _wall_event_ids_by_fingerprint := {}
## Full authoritative snapshot and fingerprint of the one wall witness state
## accepted with the current committed tick. The accepted Result itself stays
## caller-owned and mutable, so retries are checked against this immutable
## snapshot rather than against the live object. Empty when no tick is
## accepted; a new tick or an explicit retirement replaces or clears it.
var _wall_event_accepted_fingerprint := ""
var _wall_event_accepted_snapshot := {}
## Set only after the physical result and canonical gearbox/CarState pair are
## published. A direct caller cannot publish an adapter-only or stale result.
var _wall_event_accepted_result: MotorBodyAdapter.Result = null
var _wall_event_accepted_tick := -1
## True after a state-only drive restore or a post-commit gearbox failure.
## Cleared only by a future body-pose reconciliation operation, which this
## slice deliberately does not implement.
var _drive_body_pose_stale := false
## Explicit reason `_drive_body_pose_stale` is set, readable through
## `get_drive_replay_block_reason()`.
var _drive_body_pose_block_reason := ""

var state: CarState = null
var last_result: MotorBodyAdapter.Result = null
var start_position_m := Vector2.ZERO
## Unit road-plane direction of the authored straight, fixed at spawn. At a
## zero-yaw spawn this is exactly `(0, 1)`.
var _straight_axis_m := Vector2(0.0, 1.0)

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
	gearbox = AutomaticGearbox.create(make_laboratory_gearbox_config())
	wall_event_ledger = ImpactEventScript.Ledger.new()


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
	if not failed and gearbox == null:
		_fail("laboratory gearbox could not be built")


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
	if _halt_for_pose_block():
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


## Explicit provisional gearbox thresholds spanning the committed 0-45 m/s
## laboratory motor envelope. These are M1.1 starting values, not frozen
## handling coefficients; M1.6/M1.7 measurements own their ratification.
func make_laboratory_gearbox_config() -> AutomaticGearbox.GearboxConfig:
	var config := AutomaticGearbox.GearboxConfig.new()
	config.forward_gear_count = 6
	config.upshift_speeds_m_s = [8.0, 14.0, 21.0, 29.0, 38.0]
	config.downshift_speeds_m_s = [5.0, 10.0, 16.0, 23.0, 31.0]
	config.min_shift_dwell_s = 0.25
	config.min_hysteresis_gap_m_s = 0.5
	config.reverse_exit_forward_speed_m_s = 0.5
	config.top_reference_speed_m_s = 45.0
	return config


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
	if _halt_for_pose_block():
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


# --- Gearbox and drive-replay API ------------------------------------------


## Read-only copy of the canonical gearbox state (gear, shift cooldown,
## normalized rpm). The returned object is a copy: mutating it cannot change
## the laboratory.
func get_gearbox_state() -> AutomaticGearbox.GearboxState:
	if gearbox == null:
		return null
	return gearbox.get_state()


## Machine-readable canonical gearbox snapshot, matching
## `AutomaticGearbox.snapshot()`.
func get_gearbox_snapshot() -> Dictionary:
	if gearbox == null:
		return {}
	return gearbox.snapshot()


## Snapshot of the copied gearbox configuration actually in force.
func get_gearbox_config_snapshot() -> Dictionary:
	if gearbox == null:
		return {}
	return gearbox.config_snapshot()


## Bounded shift-event telemetry, oldest first. The array is capped at
## `MAX_GEAR_SHIFT_EVENTS`; later events are counted, not stored. Every
## returned entry is an independent copy, so mutating the result cannot alter
## the laboratory's telemetry.
func get_gear_shift_events() -> Array:
	var copy: Array = []
	for event in gear_shift_events:
		copy.append((event as Dictionary).duplicate())
	return copy


## Gearbox-facing counters for validation reporting. These describe the gear
## indication only; they never gate or alter the physical simulation run.
func get_gearbox_telemetry() -> Dictionary:
	var gear_index := 0
	var cooldown := 0.0
	var rpm := 0.0
	if gearbox != null:
		var current := gearbox.get_state()
		gear_index = current.gear_index
		cooldown = current.shift_cooldown_s
		rpm = current.normalized_rpm
	return {
		"gear_index": gear_index,
		"shift_cooldown_s": cooldown,
		"normalized_rpm": rpm,
		"shift_event_count": gear_shift_events.size(),
		"shift_events_dropped": gear_shift_events_dropped,
		"gearbox_refusals": gearbox_refusals,
		"gearbox_failure_reason": gearbox_failure_reason,
	}


## Last gearbox proposal/mirror refusal reason, empty when no gearbox refusal
## has occurred.
func get_gearbox_error() -> String:
	return gearbox_failure_reason


## Copy of the physical `CarState` produced by the most recent COMMITTED
## adapter tick, before the gear mirror was applied. Null before the first
## committed tick.
func get_last_committed_physical_state() -> CarState:
	if last_committed_physical == null:
		return null
	return last_committed_physical.copy()


## Captures the complete state-only drive pair. Both records are independent
## copies. This is not a runnable replay: restoring it does not reconcile the
## body transform.
func snapshot_drive_state() -> DriveSnapshot:
	var snapshot := DriveSnapshot.new()
	if state != null:
		snapshot.car_state = state.copy()
	if gearbox != null:
		snapshot.gearbox_state = gearbox.get_state()
	return snapshot


## Restores a complete `DriveSnapshot` pair atomically. The whole pair is
## validated against a temporary gearbox before either live record changes;
## an invalid or incomplete pair returns false and leaves both records
## untouched. A laboratory that has already failed refuses explicitly: a
## restore cannot undo the recorded failure and must not mutate the live pair.
## A valid restore repairs `CarState.gear_index` from the canonical gearbox
## gear, publishes both records together, then blocks all ticks because the
## body pose is deliberately not restored. There is intentionally no
## CarState-only restore: dwell and rpm would be lost.
func restore_drive_snapshot(snapshot) -> bool:
	if failed:
		return _reject_drive_restore(
			"cannot restore a drive snapshot into a laboratory that has already failed"
		)
	if snapshot == null or not (snapshot is DriveSnapshot):
		return _reject_drive_restore("snapshot is absent or is not a DriveSnapshot")
	if snapshot.car_state == null or snapshot.gearbox_state == null:
		return _reject_drive_restore("snapshot pair is incomplete")
	# Validate into a temporary gearbox; the live records are not touched yet.
	var candidate_box := AutomaticGearbox.create(make_laboratory_gearbox_config())
	if candidate_box == null:
		return _reject_drive_restore("laboratory gearbox configuration is invalid")
	if not candidate_box.restore_state(snapshot.gearbox_state):
		return _reject_drive_restore("gearbox record is invalid for this configuration")
	if not snapshot.car_state.is_finite():
		return _reject_drive_restore("car record is nonfinite")
	var candidate_car: CarState = snapshot.car_state.copy()
	var published := candidate_box.mirror_gear(candidate_car)
	if published == null or not published.is_finite():
		return _reject_drive_restore("complete pair cannot be mirrored")
	if int(published.gear_index) != int(candidate_box.get_state().gear_index):
		return _reject_drive_restore("repaired mirror disagrees with the canonical gear")
	# Every check passed on copies/temporary objects: publish the pair together.
	gearbox = candidate_box
	state = published
	last_committed_physical = null
	drive_restores += 1
	_mark_body_pose_stale(DRIVE_STATE_ONLY_HALT)
	_running = false
	if not failed and not halted:
		halted = true
		halt_reason = DRIVE_STATE_ONLY_HALT
	return true


## True while the body pose is unreconciled after a state-only restore or a
## post-commit gearbox failure. `step_once()` refuses every tick in this state
## until a future body-pose reconciliation operation exists.
func is_drive_replay_blocked() -> bool:
	return _drive_body_pose_stale


## Explicit reason ticks are blocked, empty when ticks are allowed.
func get_drive_replay_block_reason() -> String:
	return _drive_body_pose_block_reason


## Last drive-restore refusal reason, empty when no restore was refused.
func get_drive_restore_error() -> String:
	return drive_restore_refusal_reason


# --- M1.8 wall-impact publication surface ----------------------------------


## Retires the laboratory wall-event scope: clears the lab-owned ledger,
## counters, diagnostics and per-tick ID maps, and advances the scope
## generation so no retired ID can be regenerated. It never touches the
## committed CarState, the canonical gearbox or the physical body pose.
## `configure()` calls this on every new configuration/run.
func retire_wall_event_scope() -> void:
	_wall_event_scope_generation += 1
	if wall_event_ledger != null:
		wall_event_ledger.reset()
	last_wall_event = null
	wall_events_published = 0
	wall_events_coalesced = 0
	wall_events_refused = 0
	wall_event_missed_witnesses = 0
	wall_event_diagnostic = ""
	_wall_event_ids_by_fingerprint = {}
	_wall_event_accepted_result = null
	_wall_event_accepted_tick = -1
	_wall_event_accepted_fingerprint = ""
	_wall_event_accepted_snapshot = {}


## Read-only copy of the last published or coalesced retained wall event, or
## null when the current scope has none. Mutating the copy cannot change the
## laboratory.
func get_last_wall_event() -> ImpactEvent:
	if last_wall_event == null:
		return null
	return last_wall_event.copy()


## Number of events currently retained by the lab-owned ledger. This is a
## bounded retention count, not the all-time published total; the telemetry
## dictionary carries both.
func get_wall_event_count() -> int:
	if wall_event_ledger == null:
		return 0
	return wall_event_ledger.event_count()


## Last wall-event diagnostic, empty after a successful publication or an
## explicit scope retirement. A diagnostic never gates or halts the run.
func get_wall_event_diagnostic() -> String:
	return wall_event_diagnostic


## Read-only wall-event telemetry for validation and reports.
func get_wall_event_telemetry() -> Dictionary:
	var last_id := ""
	if last_wall_event != null:
		last_id = last_wall_event.event_id
	return {
		"primary_car_id": WALL_EVENT_PRIMARY_CAR_ID,
		"scope_generation": _wall_event_scope_generation,
		"published": wall_events_published,
		"coalesced": wall_events_coalesced,
		"refused": wall_events_refused,
		"missed_witnesses": wall_event_missed_witnesses,
		"retained": get_wall_event_count(),
		"identity_tick_slots": _wall_event_ids_by_fingerprint.size(),
		"last_event_id": last_id,
		"diagnostic": wall_event_diagnostic,
	}


## Retained copy of one event by caller-owned ID, or null when absent/pruned.
func find_wall_event(event_id: String) -> ImpactEvent:
	if wall_event_ledger == null:
		return null
	return wall_event_ledger.find_by_id(event_id)


## Copies of the retained events for one committed tick, oldest first.
func get_wall_events_for_tick(tick_index: int) -> Array[ImpactEvent]:
	if wall_event_ledger == null:
		return []
	return wall_event_ledger.events_for_tick(tick_index)


func has_wall_event_id(event_id: String) -> bool:
	if wall_event_ledger == null:
		return false
	return wall_event_ledger.has_event_id(event_id)


## Deterministic fingerprint of the retained wall records only.
func get_wall_event_content_digest() -> String:
	if wall_event_ledger == null:
		return ""
	return wall_event_ledger.content_digest()


## Publishes one committed wall witness through `WallImpactProducer` into the
## laboratory-owned ledger. Identity belongs to this laboratory and is pinned
## to one accepted witness state per committed tick: the adapter exposes a
## single selected wall witness, so the first publication assigns the
## deterministic ID `<prefix>.<generation>.<tick>.0`, and an identical retry of
## that exact state reuses it while the real ledger coalesces it. Any changed
## witness field, a foreign Result object, a stale tick or a retired scope is
## refused before an ID, event, ledger entry or motor state can change.
## Returns true only when the record is represented in the ledger (published
## or coalesced). Every failure is recorded as a diagnostic and leaves motor
## state, body pose, RNG, progress and presentation untouched.
func publish_wall_event(result: MotorBodyAdapter.Result) -> bool:
	if result == null:
		return false
	if result != _wall_event_accepted_result \
			or ticks_committed != _wall_event_accepted_tick \
			or failed or halted or _drive_body_pose_stale:
		wall_events_refused += 1
		wall_event_diagnostic = (
			"tick %d wall event refused: result is not the current accepted canonical pair"
			% ticks_committed
		)
		return false
	var snapshot := _wall_witness_snapshot(result)
	var fingerprint := _wall_witness_fingerprint(snapshot)
	if fingerprint != _wall_event_accepted_fingerprint:
		wall_events_refused += 1
		wall_event_diagnostic = (
			"tick %d wall event refused: accepted witness fingerprint mismatch (%s)"
			% [
				ticks_committed,
				_wall_witness_mismatch_field(snapshot, _wall_event_accepted_snapshot),
			]
		)
		return false
	if not result.has_wall_response_witness \
			or not result.has_wall_contact_point:
		if result.wall_contact:
			wall_event_missed_witnesses += 1
			wall_event_diagnostic = (
				"tick %d wall contact had no publishable response/contact-point witness"
				% ticks_committed
			)
		return false
	var tick := ticks_committed
	var ids_for_tick: Dictionary = {}
	if _wall_event_ids_by_fingerprint.has(tick):
		ids_for_tick = _wall_event_ids_by_fingerprint[tick]
	var event_id: String = String(ids_for_tick.get(fingerprint, ""))
	if event_id.is_empty():
		event_id = "%s.%d.%d.0" % [
			WALL_EVENT_ID_PREFIX, _wall_event_scope_generation, tick
		]
		ids_for_tick[fingerprint] = event_id
		_wall_event_ids_by_fingerprint[tick] = ids_for_tick
	var outcome := WallImpactProducerScript.produce(
		result, adapter_config, WALL_EVENT_PRIMARY_CAR_ID, event_id, "", tick
	)
	if outcome.is_refused():
		wall_events_refused += 1
		wall_event_diagnostic = "tick %d producer refused wall event %s: %s" % [
			tick, event_id, outcome.reason
		]
		return false
	var published := WallImpactProducerScript.publish(
		outcome.event, wall_event_ledger
	)
	if published.is_published():
		wall_events_published += 1
		last_wall_event = published.event.copy()
		wall_event_diagnostic = ""
		return true
	if published.is_coalesced():
		wall_events_coalesced += 1
		last_wall_event = published.event.copy()
		wall_event_diagnostic = ""
		return true
	wall_events_refused += 1
	wall_event_diagnostic = "tick %d ledger refused wall event %s: %s" % [
		tick, event_id, published.reason
	]
	return false


## Full authoritative witness snapshot at acceptance time. Stored by value
## because the accepted Result remains caller-owned and mutable. Every field
## the producer rebuilds, plus the status and witness flags that gate it, is
## captured so no mutation can pass as the accepted state.
static func _wall_witness_snapshot(
	result: MotorBodyAdapter.Result
) -> Dictionary:
	var committed_velocity := Vector3.ZERO
	if result.committed_state != null:
		committed_velocity = MotorBodyAdapter.road_vector_to_world(
			result.committed_state.velocity_m_s
		)
	return {
		"status": int(result.status),
		"has_response_witness": result.has_wall_response_witness,
		"has_contact_point": result.has_wall_contact_point,
		"point": result.wall_contact_point,
		"normal": result.wall_contact_normal,
		"pre_velocity": result.wall_pre_response_velocity_world_m_s,
		"post_velocity": result.wall_post_response_velocity_world_m_s,
		"frame_origin": result.wall_contact_transform.origin,
		"frame_basis": result.wall_contact_transform.basis,
		"committed_velocity": committed_velocity,
	}


## Deterministic fingerprint of one full witness snapshot. Equal fingerprints
## are exact retries of the same accepted state; any difference refuses the
## retry instead of issuing another per-tick ID.
static func _wall_witness_fingerprint(snapshot: Dictionary) -> String:
	var parts := [
		ImpactEventScript.encode_for_digest(int(snapshot["status"])),
		ImpactEventScript.encode_for_digest(
			bool(snapshot["has_response_witness"])
		),
		ImpactEventScript.encode_for_digest(bool(snapshot["has_contact_point"])),
		ImpactEventScript.encode_for_digest(snapshot["point"]),
		ImpactEventScript.encode_for_digest(snapshot["normal"]),
		ImpactEventScript.encode_for_digest(snapshot["pre_velocity"]),
		ImpactEventScript.encode_for_digest(snapshot["post_velocity"]),
		ImpactEventScript.encode_for_digest(snapshot["frame_origin"]),
		ImpactEventScript.encode_for_digest(snapshot["frame_basis"]),
		ImpactEventScript.encode_for_digest(snapshot["committed_velocity"]),
	]
	var joined := ""
	for index in range(parts.size()):
		if index > 0:
			joined += "|"
		joined += parts[index]
	return joined


## Names the first authoritative witness field that differs from the accepted
## snapshot, for a specific refusal diagnostic.
func _wall_witness_mismatch_field(
	snapshot: Dictionary, accepted: Dictionary
) -> String:
	if int(snapshot["status"]) != int(accepted["status"]):
		return "adapter result status"
	if bool(snapshot["has_response_witness"]) != bool(accepted["has_response_witness"]):
		return "wall response witness flag"
	if bool(snapshot["has_contact_point"]) != bool(accepted["has_contact_point"]):
		return "wall contact point witness flag"
	if snapshot["point"] != accepted["point"]:
		return "contact point"
	if snapshot["normal"] != accepted["normal"]:
		return "contact normal"
	if snapshot["pre_velocity"] != accepted["pre_velocity"]:
		return "pre-response velocity"
	if snapshot["post_velocity"] != accepted["post_velocity"]:
		return "post-response velocity"
	if snapshot["frame_origin"] != accepted["frame_origin"] \
			or snapshot["frame_basis"] != accepted["frame_basis"]:
		return "collision frame"
	if snapshot["committed_velocity"] != accepted["committed_velocity"]:
		return "committed planar velocity"
	return "witness state"


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
	# A state-only drive restore leaves the body transform unreconciled. No
	# tick is allowed until a body-pose reconciliation operation exists.
	if _drive_body_pose_stale:
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
			# The adapter already advanced the body for this COMMITTED tick, so
			# even a missing or nonfinite record leaves the pose unreconciled. No
			# gearbox proposal happened; there is no canonical state to restore.
			_mark_body_pose_stale(DRIVE_BODY_POSE_STALE_HALT)
			_fail("nonfinite committed state")
			return result
		# The adapter commit is irreversible from here: the body transform has
		# already advanced. Remember the physical record for diagnostics and
		# retain the canonical gearbox state. If any later gearbox step cannot
		# publish a valid mirrored pair, the canonical gearbox returns to this
		# pre-tick state and `state` stays at the last successfully published
		# pair; the body pose is marked unreconciled and the run halts without
		# publishing an unmirrored or mismatched record as the committed pair.
		var committed := result.committed_state
		last_committed_physical = committed.copy()
		var pre_tick_gearbox := gearbox.get_state()
		var proposal := gearbox.propose(committed, DT)
		if proposal == null:
			_reject_gearbox_step(
				"gearbox proposal refused after the irreversible COMMITTED physical tick; "
				+ _rollback_pre_tick_gearbox(pre_tick_gearbox)
				+ " and no CarState was published"
			)
			return result
		var published := gearbox.mirror_gear(committed)
		if published == null:
			_reject_gearbox_step(
				"gearbox mirror refused after the irreversible COMMITTED physical tick; "
				+ _rollback_pre_tick_gearbox(pre_tick_gearbox)
				+ " and no CarState was published"
			)
			return result
		if int(published.gear_index) != int(proposal.gear_index) or not published.is_finite():
			_reject_gearbox_step(
				(
					"gearbox mirror disagreed with the canonical gear after the irreversible "
					+ "COMMITTED physical tick (canonical=%d mirrored=%d); "
					+ _rollback_pre_tick_gearbox(pre_tick_gearbox)
					+ " and no mismatched CarState was published"
				) % [int(proposal.gear_index), int(published.gear_index)]
			)
			return result
		state = published
		ticks_committed += 1
		_record_shift_event(proposal)
		# Only one selected wall witness exists per committed tick. Snapshot its
		# full authoritative state now, before the first publication; retries of
		# this exact tick must match this snapshot, and old maps are cleared so
		# they cannot grow with a long laboratory run.
		_wall_event_ids_by_fingerprint.clear()
		_wall_event_accepted_result = result
		_wall_event_accepted_tick = ticks_committed
		_wall_event_accepted_snapshot = _wall_witness_snapshot(result)
		_wall_event_accepted_fingerprint = _wall_witness_fingerprint(
			_wall_event_accepted_snapshot
		)
		# The physical tick and the mirrored canonical pair are both published
		# now. Only this committed path may publish a wall event; every earlier
		# refusal, stale-pose block and post-commit gearbox failure returns first.
		publish_wall_event(result)
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
	return (state.position_m - start_position_m).dot(_straight_axis_m)


## Read-only course-envelope query over the projected station, mirroring the
## private limit check that gates `step_once()`. Validation uses it to pin both
## limits without driving an adapter tick from a synthetic pose.
func is_course_limit_reached() -> bool:
	return _course_limit_reached()


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
		"gear_index": 0 if state == null else int(state.gear_index),
		"gear_shift_events": gear_shift_events.size(),
		"gear_shift_events_dropped": gear_shift_events_dropped,
		"gearbox_refusals": gearbox_refusals,
		"drive_restores": drive_restores,
		"drive_restore_refusals": drive_restore_refusals,
		"drive_replay_blocked": _drive_body_pose_stale,
		"body_pose_reconciled": not _drive_body_pose_stale,
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
	# A fresh spawn starts a fresh complete pair: canonical gear 1, zero dwell,
	# zero rpm, and the published mirror agreeing with both.
	if gearbox != null:
		gearbox.reset()
	state.position_m = AdapterScript.world_vector_to_road(spawn)
	state.heading_rad = heading
	start_position_m = state.position_m
	# The authored straight axis comes from the same converted heading that
	# sets the nose and the installed body basis. Deriving it from `state`
	# keeps the three consumers consistent; a zero heading gives (0, 1) exactly.
	_straight_axis_m = Vector2(sin(state.heading_rad), cos(state.heading_rad))
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
	var station := (state.position_m - start_position_m).dot(_straight_axis_m)
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
		"gear_index": int(state.gear_index),
		"normalized_rpm": float(gearbox.get_state().normalized_rpm) if gearbox != null else 0.0,
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
	retire_wall_event_scope()
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
	# Reconfiguration starts a fresh complete pair: canonical gear 1, zero
	# dwell and the published mirror agreeing with it. A body-pose block from
	# a state-only restore or a post-commit gearbox failure is deliberately NOT
	# cleared here: configure() clears failure/halt flags but no body-pose
	# reconciliation operation exists yet, so reusing the old published pair
	# with an advanced body must stay impossible.
	gear_shift_events = []
	gear_shift_events_dropped = 0
	gearbox_refusals = 0
	gearbox_failure_reason = ""
	drive_restores = 0
	drive_restore_refusals = 0
	drive_restore_refusal_reason = ""
	last_committed_physical = null
	if gearbox != null:
		gearbox.reset()
		# The gear mirror below changes only the published gear field; wall
		# event retirement above deliberately leaves position, velocity,
		# heading and the physical body untouched.
		if state != null:
			state.gear_index = gearbox.get_state().gear_index
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


## Records one gearbox shift event in bounded telemetry. Called only after the
## proposal and mirror both succeeded, so an event always belongs to a
## published paired tick.
func _record_shift_event(proposal: AutomaticGearbox.GearboxProposal) -> void:
	if proposal == null or not proposal.has_event():
		return
	if gear_shift_events.size() >= MAX_GEAR_SHIFT_EVENTS:
		gear_shift_events_dropped += 1
		return
	var event: AutomaticGearbox.ShiftEvent = proposal.event
	gear_shift_events.append({
		"tick": ticks_committed,
		"from_gear": int(event.from_gear),
		"to_gear": int(event.to_gear),
		"direction": int(event.direction),
		"normalized_rpm": float(event.normalized_rpm),
		"forward_speed_m_s": state.forward_speed_m_s() if state != null else 0.0,
	})


## Puts the canonical gearbox back to the retained pre-tick state after a
## COMMITTED physical tick whose gearbox pair could not be published. Returns
## a clause for the bounded failure reason. The physical body is never touched.
func _rollback_pre_tick_gearbox(pre_tick) -> String:
	if gearbox == null or pre_tick == null:
		return "canonical gearbox RESTORE FAILED"
	if not gearbox.restore_state(pre_tick):
		return "canonical gearbox RESTORE FAILED"
	return "canonical gearbox was restored to its pre-tick state"


## Records an unreconcilable body pose: the physical body has advanced past the
## last published pair and no reconciliation operation exists. Ticks stay
## blocked even after `configure()`, which clears only failure/halt flags.
func _mark_body_pose_stale(reason: String) -> void:
	_drive_body_pose_stale = true
	_drive_body_pose_block_reason = reason


## Stops an automatic run attempt while the body pose is unreconciled. Returns
## true when the caller must not advance. `start()` and `_physics_process()`
## use this before they could consume a scripted command or report completion,
## so a stale-pose laboratory halts with its explicit replay block reason
## instead of completing a zero-tick script.
func _halt_for_pose_block() -> bool:
	if not _drive_body_pose_stale:
		return false
	_halt(_drive_body_pose_block_reason)
	return true


## Bounded explicit gearbox failure. The physical tick is already committed
## and cannot be rolled back; this records the reason, marks the body pose
## unreconciled and halts the run without publishing the unmirrored record as
## the committed pair.
func _reject_gearbox_step(reason: String) -> void:
	gearbox_refusals += 1
	gearbox_failure_reason = reason
	# A wall witness on this irreversible physical tick must not be published
	# because the canonical pair it would have accompanied was not published.
	if last_result != null and last_result.has_wall_response_witness \
			and last_result.has_wall_contact_point:
		wall_event_diagnostic = (
			"wall witness withheld: canonical gearbox pair was not published"
		)
	_mark_body_pose_stale(DRIVE_BODY_POSE_STALE_HALT)
	_fail(reason)


## Atomic drive-restore refusal: no live record was modified, so recording the
## reason and returning false is the whole operation.
func _reject_drive_restore(reason: String) -> bool:
	drive_restore_refusals += 1
	drive_restore_refusal_reason = reason
	print("[drive_lab] DRIVE RESTORE REFUSED: ", reason)
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
