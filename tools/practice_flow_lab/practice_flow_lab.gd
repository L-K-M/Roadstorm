extends SceneTree
## Headless practice-flow lab for the M0.2/M1 graybox driving entry.
##
## It exercises the real boot -> menu -> practice path in one process:
##   * the boot scene hands off to the committed menu;
##   * the menu offers the labelled "Driving Lab (graybox)" entry;
##   * pressing it loads scenes/game.tscn, which hosts exactly one committed
##     scenes/laboratory/drive_lab.tscn instance with one body, one chase
##     camera and one speed HUD;
##   * bounded synthetic keyboard input through the real input pipeline drives
##     at least one COMMITTED physics tick and finite motion;
##   * Escape (cycle 1) and public navigation (cycle 2) both return to the
##     menu, twice in a row;
##   * after each teardown no DriveLab, Camera3D or CanvasLayer survives and
##     the retired laboratory node is invalid;
##   * a forced state-only drive restore halts the laboratory and the overlay
##     must report that halt truthfully.
##
## This is structural/behaviour evidence only. It does not review rendered GUI,
## physical keyboards, gamepad routing, audio quality, handling feel, or any
## M0.2/M1/M5 acceptance criterion.
##
## Usage (isolated project copy):
##   godot --headless --fixed-fps 60 --path <project> \
##       --script res://tools/practice_flow_lab/practice_flow_lab.gd
##   godot ... -- --expect-failure
##
## `--expect-failure` deliberately records a failure so the wrapper can prove a
## failing check exits nonzero.

const BOOT_SCENE_PATH := "res://scenes/boot.tscn"
const MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const GAME_SCENE_PATH := "res://scenes/game.tscn"

const DRIVE_LAB_SCRIPT_PATH := "res://src/laboratory/drive_lab.gd"
const DriveLabScript := preload("res://src/laboratory/drive_lab.gd")

const EXPECTED_MAJOR := 4
const EXPECTED_MINOR := 7
const EXPECTED_PATCH := 2
const EXPECTED_STATUS := "stable"
const EXPECTED_BUILD := "official"
const EXPECTED_COMMIT_PREFIX := "ed1daf0bf"

const PRACTICE_BUTTON_TEXT := "Driving Lab (graybox)"
const CYCLES := 2
const MAX_BOOT_FRAMES := 300
const MAX_TRANSITION_FRAMES := 120
const TEARDOWN_WAIT_FRAMES := 8
const DRIVE_TARGET_COMMITS := 12
const DRIVE_MAX_FRAMES := 180
const MIN_MOVEMENT_M := 0.001

var _checks := 0
var _failures: Array[String] = []
var _measured: Dictionary = {}
var _finished := false
var _probe: InputEventProbe = null


## Records synthetic key events that reach the unhandled-input pipeline. A
## driving check uses it to prove the key really was delivered, so an
## unchanged car cannot pass merely because the event never arrived.
class InputEventProbe extends Node:
	var events: Array = []

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey:
			var key := event as InputEventKey
			events.append({"keycode": key.keycode, "pressed": key.pressed})


func _initialize() -> void:
	print("[practice-flow] engine ", Engine.get_version_info()["string"])
	_check_engine()
	_check_resources()

	if _has_user_flag("--expect-failure"):
		_record_failure("control.expect_failure", "--expect-failure requested")
		_finish()
		return

	if not _failures.is_empty():
		_finish()
		return

	_probe = InputEventProbe.new()
	_probe.name = "PracticeInputProbe"
	root.add_child.call_deferred(_probe)

	_negative_control()
	_run.call_deferred()


# --- Flow -------------------------------------------------------------------


func _run() -> void:
	var cycle_records: Array = []
	change_scene_to_file(BOOT_SCENE_PATH)
	if not await _wait_for_scene(MENU_SCENE_PATH, MAX_BOOT_FRAMES):
		_record_failure("boot.handoff", "boot scene did not hand off to %s" % MENU_SCENE_PATH)
		_finish()
		return

	for index in range(CYCLES):
		cycle_records.append(await _run_cycle(index))

	_measured["cycles"] = cycle_records
	_final_teardown_checks(cycle_records)
	_finish()


func _run_cycle(index: int) -> Dictionary:
	var prefix := "cycle%d" % index
	var record := {"index": index}

	var menu := current_scene
	var practice_button := _check_menu(menu, prefix)
	if practice_button == null:
		return record
	practice_button.pressed.emit()
	if not await _wait_for_scene(GAME_SCENE_PATH, MAX_TRANSITION_FRAMES):
		_record_failure(prefix + ".transition", "menu entry did not load %s" % GAME_SCENE_PATH)
		return record

	var game := current_scene
	var structure_failures: Array[String] = []
	var lab := _check_game_structure(game, structure_failures)
	_sink_failures(structure_failures, prefix + ".structure")
	if lab == null:
		_leave_to_menu(game, index)
		await _wait_for_scene(MENU_SCENE_PATH, MAX_TRANSITION_FRAMES)
		return record

	record["drive_lab_present"] = true
	var drive_record := await _drive_and_measure(lab, prefix)
	record.merge(drive_record)

	# The second cycle forces the laboratory's documented state-only restore
	# halt and requires the overlay to report it truthfully.
	if index == CYCLES - 1:
		var diagnostic_ok := await _check_forced_halt_diagnostic(game, lab, prefix)
		record["diagnostic_truthful"] = diagnostic_ok

	_leave_to_menu(game, index)
	var returned := await _wait_for_scene(MENU_SCENE_PATH, MAX_TRANSITION_FRAMES)
	record["returned_to_menu"] = returned
	if not returned:
		_record_failure(prefix + ".return", "Escape/public navigation did not return to %s" % MENU_SCENE_PATH)
		return record

	await _settle(TEARDOWN_WAIT_FRAMES)
	var physics_before := Engine.get_physics_frames()
	await _settle(TEARDOWN_WAIT_FRAMES)
	record["teardown_physics_advanced"] = Engine.get_physics_frames() > physics_before
	_check(
		not is_instance_valid(lab),
		prefix + ".teardown.retired_laboratory_node_is_invalid"
	)
	var remaining_labs := _collect_script_instances(current_scene, DriveLabScript)
	_check(
		remaining_labs.is_empty(),
		prefix + ".teardown.no_drive_lab_remains (%d found)" % remaining_labs.size()
	)
	var remaining_cameras := _collect_by_class(root, "Camera3D")
	_check(
		remaining_cameras.is_empty(),
		prefix + ".teardown.no_camera_remains (%d found)" % remaining_cameras.size()
	)
	var remaining_layers := _collect_by_class(current_scene, "CanvasLayer")
	_check(
		remaining_layers.is_empty(),
		prefix + ".teardown.no_hud_canvas_layer_remains (%d found)" % remaining_layers.size()
	)
	return record


func _drive_and_measure(lab: DriveLab, prefix: String) -> Dictionary:
	var record := {}
	var ticks_before := int(lab.ticks_committed)
	var position_before: Vector2 = lab.state.position_m
	var probe_events_before := 0 if _probe == null else _probe.events.size()

	_deliver_key(Key.KEY_W, true)
	var waited := 0
	while int(lab.ticks_committed) - ticks_before < DRIVE_TARGET_COMMITS \
			and waited < DRIVE_MAX_FRAMES:
		await physics_frame
		waited += 1
	_deliver_key(Key.KEY_W, false)
	await physics_frame
	await physics_frame

	var moved_ticks := int(lab.ticks_committed) - ticks_before
	var displacement := lab.state.position_m.distance_to(position_before)
	var speed := lab.state.speed_m_s()
	var finite_state := lab.state.is_finite() and _finite_vector2(lab.state.position_m)

	_check(moved_ticks >= 1, prefix + ".drive.at_least_one_committed_tick (%d)" % moved_ticks)
	_check(
		finite_state and displacement > MIN_MOVEMENT_M,
		prefix + ".drive.finite_movement (displacement=%.6f m)" % displacement
	)
	_check(
		is_finite(speed) and speed > 0.0,
		prefix + ".drive.finite_forward_speed (speed=%.6f m/s)" % speed
	)
	_check(
		lab.total_accepted_motion_m > 0.0 and is_finite(lab.total_accepted_motion_m),
		prefix + ".drive.finite_accepted_motion (total=%.6f m)" % lab.total_accepted_motion_m
	)
	_check(not lab.failed, prefix + ".drive.not_failed (%s)" % lab.failure_reason)
	_check(not lab.halted, prefix + ".drive.not_halted (%s)" % lab.halt_reason)
	if _probe != null:
		_check(
			_probe.events.size() > probe_events_before,
			prefix + ".drive.synthetic_key_reached_the_input_pipeline"
		)

	record["committed_ticks_during_input"] = moved_ticks
	record["displacement_m"] = displacement
	record["speed_m_s"] = speed
	record["input_probe_events"] = 0 if _probe == null else _probe.events.size() - probe_events_before
	record["physics_wait_frames"] = waited
	return record


## Forces the laboratory's documented state-only restore, then requires the
## overlay to show the halt reason. Returns true when the diagnostic is visible
## and names the recorded reason.
func _check_forced_halt_diagnostic(game: Node, lab: DriveLab, prefix: String) -> bool:
	var snapshot := lab.snapshot_drive_state()
	var restored: bool = lab.restore_drive_snapshot(snapshot)
	_check(restored, prefix + ".diagnostic.forced_restore_succeeded")
	await process_frame
	await process_frame
	var diagnostic := game.get_node_or_null("GameOverlay/Diagnostic") as Label
	if diagnostic == null:
		_record_failure(prefix + ".diagnostic.overlay_label_missing", "GameOverlay/Diagnostic not found")
		return false
	var expected_reason := lab.halt_reason
	_check(lab.halted, prefix + ".diagnostic.laboratory_reports_halt")
	_check(
		diagnostic.visible,
		prefix + ".diagnostic.label_visible_after_halt"
	)
	var text := diagnostic.text
	var names_reason := not expected_reason.is_empty() and text.contains(expected_reason)
	_check(
		names_reason,
		prefix + ".diagnostic.label_names_halt_reason (text='%s' reason='%s')" % [
			text, expected_reason,
		]
	)
	_check(
		not text.contains("failed") or not lab.failed,
		prefix + ".diagnostic.no_false_success_wording"
	)
	return names_reason and diagnostic.visible


# --- Structural checks ------------------------------------------------------


func _check_menu(menu: Node, prefix: String) -> Button:
	if menu == null or menu.scene_file_path != MENU_SCENE_PATH:
		_record_failure(prefix + ".menu.wrong_scene", "expected %s" % MENU_SCENE_PATH)
		return null
	var title := menu.get_node_or_null("Center/Panel/Title") as Label
	if title == null:
		_record_failure(prefix + ".menu.title_missing", "Center/Panel/Title not found")
	elif title.text != "Roadstorm Racer!":
		_record_failure(prefix + ".menu.title_changed", "'%s'" % title.text)
	var quit_button := menu.get_node_or_null("Center/Panel/QuitButton") as Button
	if quit_button == null:
		_record_failure(prefix + ".menu.quit_missing", "Center/Panel/QuitButton not found")
	var practice_button := menu.get_node_or_null("Center/Panel/PracticeButton") as Button
	if practice_button == null:
		_record_failure(prefix + ".menu.practice_entry_missing", "Center/Panel/PracticeButton not found")
		return null
	if practice_button.text != PRACTICE_BUTTON_TEXT:
		_record_failure(
			prefix + ".menu.practice_entry_label",
			"'%s', expected '%s'" % [practice_button.text, PRACTICE_BUTTON_TEXT]
		)
	if practice_button.pressed.get_connections().is_empty():
		_record_failure(prefix + ".menu.practice_entry_not_connected", "no pressed connection")
	return practice_button


func _check_game_structure(game: Node, failures: Array[String]) -> DriveLab:
	if not (game is Node3D):
		failures.append("game root is %s, expected Node3D" % game.get_class())
		return null
	var labs := _collect_script_instances(game, DriveLabScript)
	if labs.size() != 1:
		failures.append("game hosts %d DriveLab instances, expected exactly one" % labs.size())
		return null
	var lab := labs[0] as DriveLab
	if lab.body == null:
		failures.append("DriveLab has no CharacterBody3D body")
	if lab.camera_rig == null or lab.camera_rig.get_camera() == null:
		failures.append("DriveLab camera rig has no Camera3D")
	if lab.speed_hud == null or lab.hud_layer == null:
		failures.append("DriveLab presentation HUD or its CanvasLayer is missing")
	if not lab.is_presentation_ready():
		failures.append("DriveLab is_presentation_ready() is false")
	# CameraRig.attach_to_viewport() moves the rig under the root Viewport.
	var cameras := _collect_by_class(root, "Camera3D")
	if cameras.size() != 1:
		failures.append("game exposes %d Camera3D nodes, expected exactly one" % cameras.size())
	elif lab.camera_rig != null and lab.camera_rig.get_camera() != cameras[0]:
		failures.append("the single game Camera3D is not the DriveLab camera")
	if game.get_node_or_null("GameOverlay") == null:
		failures.append("back-hint/diagnostic overlay (GameOverlay) is missing")
	elif game.get_node_or_null("GameOverlay/BackHint") == null:
		failures.append("overlay back hint (GameOverlay/BackHint) is missing")
	return lab


## Negative control: the same structural check must reject a scene with no
## DriveLab, proving the normal-pass checks are not vacuous.
func _negative_control() -> void:
	var dummy := Node3D.new()
	var sink: Array[String] = []
	_check_game_structure(dummy, sink)
	dummy.free()
	_check(
		not sink.is_empty(),
		"negative_control.empty_scene_is_rejected_by_the_structure_check (%d failures)" % sink.size()
	)


# --- Teardown helpers -------------------------------------------------------


func _leave_to_menu(game: Node, cycle_index: int) -> void:
	if cycle_index == 0:
		_deliver_key(Key.KEY_ESCAPE, true)
		_deliver_key(Key.KEY_ESCAPE, false)
		return
	if game is GamePlaceholder:
		(game as GamePlaceholder).return_to_menu()
	else:
		_record_failure("cycle%d.return" % cycle_index, "game root is not GamePlaceholder")


func _final_teardown_checks(cycle_records: Array) -> void:
	var returned_all := true
	for record in cycle_records:
		if not bool(record.get("returned_to_menu", false)):
			returned_all = false
	_check(returned_all, "flow.every_cycle_returned_to_menu")
	if current_scene != null and current_scene.scene_file_path == MENU_SCENE_PATH:
		var labs := _collect_script_instances(current_scene, DriveLabScript)
		_check(labs.is_empty(), "flow.final_no_drive_lab_in_menu (%d found)" % labs.size())
		var cameras := _collect_by_class(root, "Camera3D")
		_check(cameras.is_empty(), "flow.final_no_camera_in_menu (%d found)" % cameras.size())


# --- Small utilities --------------------------------------------------------


func _wait_for_scene(scene_path: String, max_frames: int) -> bool:
	var frames := 0
	while frames < max_frames:
		if current_scene != null and current_scene.scene_file_path == scene_path:
			return true
		await process_frame
		frames += 1
	return false


func _settle(frames: int) -> void:
	for _i in range(frames):
		await process_frame


func _deliver_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _collect_script_instances(node: Node, script: Script) -> Array[Node]:
	var found: Array[Node] = []
	if node.get_script() == script:
		found.append(node)
	for child in node.get_children():
		found.append_array(_collect_script_instances(child, script))
	return found


func _collect_by_class(node: Node, type_name: String) -> Array[Node]:
	var found: Array[Node] = []
	if node.is_class(type_name):
		found.append(node)
	for child in node.get_children():
		found.append_array(_collect_by_class(child, type_name))
	return found


func _finite_vector2(value: Vector2) -> bool:
	return not (
		is_nan(value.x) or is_inf(value.x) or is_nan(value.y) or is_inf(value.y)
	)


func _has_user_flag(flag: String) -> bool:
	return flag in OS.get_cmdline_user_args()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		printerr("[practice-flow] FAIL: ", label)


func _record_failure(label: String, detail: String) -> void:
	_checks += 1
	var message := "%s: %s" % [label, detail]
	_failures.append(message)
	printerr("[practice-flow] FAIL: ", message)


func _sink_failures(failures: Array[String], prefix: String) -> void:
	for failure in failures:
		_record_failure(prefix, failure)


func _check_engine() -> void:
	var version: Dictionary = Engine.get_version_info()
	if version["major"] != EXPECTED_MAJOR or version["minor"] != EXPECTED_MINOR \
			or version["patch"] != EXPECTED_PATCH:
		_record_failure(
			"engine.version",
			"expected %d.%d.%d, found %s" % [
				EXPECTED_MAJOR, EXPECTED_MINOR, EXPECTED_PATCH, version["string"],
			]
		)
		return
	if version["status"] != EXPECTED_STATUS or version["build"] != EXPECTED_BUILD:
		_record_failure(
			"engine.build",
			"expected %s/%s, found %s/%s" % [
				EXPECTED_STATUS, EXPECTED_BUILD, version["status"], version["build"],
			]
		)
	if not String(version["hash"]).begins_with(EXPECTED_COMMIT_PREFIX):
		_record_failure(
			"engine.commit",
			"expected prefix %s, found %s" % [EXPECTED_COMMIT_PREFIX, version["hash"]]
		)


func _check_resources() -> void:
	for path in [BOOT_SCENE_PATH, MENU_SCENE_PATH, GAME_SCENE_PATH]:
		if not ResourceLoader.exists(path):
			_record_failure("resource.missing", path)
	if not ResourceLoader.exists(DRIVE_LAB_SCRIPT_PATH):
		_record_failure("resource.missing", DRIVE_LAB_SCRIPT_PATH)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	var report := {
		"schema": "roadstorm.practice_flow_lab.v1",
		"boot_scene": BOOT_SCENE_PATH,
		"menu_scene": MENU_SCENE_PATH,
		"game_scene": GAME_SCENE_PATH,
		"cycles": CYCLES,
		"checks_total": _checks,
		"checks_failed": _failures.size(),
		"failures": _failures,
		"measured": _measured,
		"limitations": [
			"Headless dummy display/audio drivers; no rendered-GUI, visual-readability, audio-quality or physical-keyboard review.",
			"No gamepad/controller routing, split-screen, race rules, rewards, cosmetics, saves or release claim.",
			"Synthetic key events prove the input pipeline and one COMMITTED tick, not real device behaviour.",
			"Teardown absence of DriveLab/Camera3D/CanvasLayer is structural evidence; no global listener registry is inspected.",
			"No M0.2, M1 or M5 acceptance claim; the coordinator integrates and judges the slice.",
		],
	}
	print("PRACTICE_RESULT ", JSON.stringify(report))
	print("CHECKS_TOTAL=", _checks, " CHECKS_FAILED=", _failures.size())
	quit(1 if not _failures.is_empty() else 0)
