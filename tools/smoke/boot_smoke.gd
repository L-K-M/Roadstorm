extends SceneTree
## Original headless boot smoke test for the M0 shell.
##
## What it verifies (see PLAN.md M0.2 / docs/TECHNICAL_DESIGN.md verification
## matrix T01):
##   * the pinned engine is Godot 4.7.2;
##   * project settings request the (provisional) Compatibility renderer,
##     60 fixed physics ticks and the boot scene as the main scene;
##   * the owned scenes exist, instantiate without script errors, and the boot
##     scene hands off to the menu;
##   * the placeholder race scene loads in the same shell.
##
## It deliberately does not claim any gameplay exists: the menu and race scenes
## are placeholders.
##
## Usage:
##   godot --headless --path . --script res://tools/smoke/boot_smoke.gd
##   godot --headless --path . --script res://tools/smoke/boot_smoke.gd -- --expect-failure
##
## Exit code: 0 = pass, 1 = fail. The `--expect-failure` flag exists to prove
## that a failing check really returns a nonzero exit code (PLAN.md M0.4).

const BOOT_SCENE_PATH := "res://scenes/boot.tscn"
const MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const GAME_SCENE_PATH := "res://scenes/game.tscn"

const EXPECTED_MAJOR := 4
const EXPECTED_MINOR := 7
const EXPECTED_PATCH := 2

## Generous ceiling: the shell should hand off within a few frames.
const MAX_FRAMES := 600

## 0 = waiting for boot -> menu handoff, 1 = waiting for the game scene.
var _stage: int = 0
var _frames: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	var version: Dictionary = Engine.get_version_info()
	print("[boot-smoke] engine ", version["string"], " (", OS.get_name(), " ", OS.get_version(), ")")
	print("[boot-smoke] display driver ", DisplayServer.get_name())

	_check_version(version)
	_check_settings()

	for scene_path in [BOOT_SCENE_PATH, MENU_SCENE_PATH, GAME_SCENE_PATH]:
		if not ResourceLoader.exists(scene_path):
			_fail("missing scene resource: %s" % scene_path)

	if _has_user_flag("--expect-failure"):
		_fail("--expect-failure requested: proving a failing check exits nonzero")

	change_scene_to_file(BOOT_SCENE_PATH)
	process_frame.connect(_on_process_frame)


func _on_process_frame() -> void:
	_frames += 1
	if _frames > MAX_FRAMES:
		_fail("timed out after %d frames at stage %d" % [_frames, _stage])
		_finish()
		return

	var current := current_scene
	if current == null:
		return

	if _stage == 0 and current.scene_file_path == MENU_SCENE_PATH:
		print("[boot-smoke] boot handed off to menu after %d frame(s)" % _frames)
		_check_menu(current)
		_stage = 1
		change_scene_to_file(GAME_SCENE_PATH)
	elif _stage == 1 and current.scene_file_path == GAME_SCENE_PATH:
		print("[boot-smoke] placeholder race scene loaded after %d frame(s)" % _frames)
		_check_game(current)
		_finish()


func _check_version(version: Dictionary) -> void:
	if version["major"] != EXPECTED_MAJOR or version["minor"] != EXPECTED_MINOR or version["patch"] != EXPECTED_PATCH:
		_fail("expected Godot %d.%d.%d, found %d.%d.%d" % [
			EXPECTED_MAJOR, EXPECTED_MINOR, EXPECTED_PATCH,
			version["major"], version["minor"], version["patch"],
		])
		return
	print("[boot-smoke] pinned engine version matches 4.7.2")


func _check_settings() -> void:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if main_scene != BOOT_SCENE_PATH:
		_fail("application/run/main_scene is '%s', expected '%s'" % [main_scene, BOOT_SCENE_PATH])

	var renderer: String = ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method")
	if renderer != "gl_compatibility":
		_fail("rendering/renderer/rendering_method is '%s', expected 'gl_compatibility'" % renderer)

	var ticks: int = ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 0)
	if ticks != 60:
		_fail("physics/common/physics_ticks_per_second is %d, expected 60" % ticks)

	print("[boot-smoke] project settings: main scene, renderer and 60 ticks/second confirmed")


func _check_menu(menu: Node) -> void:
	if not (menu is Control):
		_fail("menu root is %s, expected Control" % menu.get_class())
		return
	var title := menu.get_node_or_null(^"Center/Panel/Title") as Label
	if title == null:
		_fail("menu is missing the title label at Center/Panel/Title")
	elif title.text != "Roadstorm Racer!":
		_fail("menu title is '%s', expected 'Roadstorm Racer!'" % title.text)
	var quit_button := menu.get_node_or_null(^"Center/Panel/QuitButton") as Button
	if quit_button == null:
		_fail("menu is missing the quit button at Center/Panel/QuitButton")


func _check_game(game: Node) -> void:
	if not (game is Node3D):
		_fail("game root is %s, expected Node3D" % game.get_class())
		return
	if game.get_node_or_null(^"Camera3D") == null:
		_fail("placeholder race scene has no Camera3D")


func _has_user_flag(flag: String) -> bool:
	return flag in OS.get_cmdline_user_args()


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("[boot-smoke] FAIL: ", message)


func _finish() -> void:
	if _failures.is_empty():
		print("[boot-smoke] PASS: M0 shell boots, hands off and loads the placeholder race scene")
		quit(0)
	else:
		printerr("[boot-smoke] RESULT: FAIL (%d problem(s))" % _failures.size())
		quit(1)
