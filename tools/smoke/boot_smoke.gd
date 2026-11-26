extends SceneTree
## Headless boot smoke test for the M0 shell.
##
## What it verifies (see PLAN.md M0.2 / docs/TECHNICAL_DESIGN.md verification
## matrix T01):
##   * the pinned engine is the exact official Godot 4.7.2 build: version,
##     status, build flavour and commit hash, not just major.minor.patch;
##   * project settings request the (provisional) Compatibility renderer,
##     60 fixed physics ticks and the boot scene as the main scene;
##   * the owned scenes exist, load, instantiate, and their scripts are
##     attached and loadable, so a GDScript parse error or a detached script
##     fails this check instead of printing an engine error and passing;
##   * the menu's quit button has its 'pressed' signal connected, the
##     observable side effect of main_menu.gd::_ready completing;
##   * the boot scene hands off to the menu;
##   * the placeholder race scene loads in the same shell.
##
## It deliberately does not claim any gameplay exists: the menu and race scenes
## are placeholders.
##
## Limit: a runtime script error (an exception thrown from a script that still
## parses, e.g. inside _ready) cannot be observed from inside the engine
## process. The supported entry point is therefore the wrapper
## tools/smoke/run_boot_smoke.sh, which also fails on SCRIPT ERROR / ERROR:
## lines in the engine output. tools/smoke/fault_injection.sh proves all of
## the failing paths on isolated snapshot copies.
##
## Usage:
##   tools/smoke/run_boot_smoke.sh
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

## Exact pinned official build, mirrored from tools/toolchain/pin/engine.txt
## (PLAN.md M0.1). That pin file is owned by tools/toolchain/**; these
## constants are the copy this check reads so the smoke test stays inside
## tools/smoke/**. tools/toolchain/verify.sh independently pins the installed
## binary's digest and the export templates.
const EXPECTED_STATUS := "stable"
const EXPECTED_BUILD := "official"
## Short commit hash recorded in the pin file. Engine.get_version_info()
## reports the full hash, so the comparison is a prefix match.
const EXPECTED_COMMIT := "ed1daf0bf"

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
		_check_scene_loads(scene_path)

	if _has_user_flag("--expect-failure"):
		_fail("--expect-failure requested: proving a failing check exits nonzero")

	# A scene that is missing, fails to load or carries an unloadable script is
	# already fatal. Finish now instead of pretending the shell still boots.
	if not _failures.is_empty():
		_finish()
		return

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
	# A custom or unofficial build of the same version is not the pinned
	# toolchain (Opus review finding 13), so pin the exact official build:
	# release status, build flavour and commit hash.
	if version["status"] != EXPECTED_STATUS:
		_fail("engine status is '%s', expected '%s' for the pinned release build" % [version["status"], EXPECTED_STATUS])
	if version["build"] != EXPECTED_BUILD:
		_fail("engine build is '%s', expected '%s' (a custom build is not the pinned toolchain)" % [version["build"], EXPECTED_BUILD])
	var commit := String(version["hash"])
	if not commit.begins_with(EXPECTED_COMMIT):
		_fail("engine commit hash is '%s', expected it to start with '%s'" % [commit, EXPECTED_COMMIT])
	if _failures.is_empty():
		print("[boot-smoke] pinned engine version matches 4.7.2 (%s, %s, %s)" % [EXPECTED_STATUS, EXPECTED_BUILD, EXPECTED_COMMIT])


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


## Pre-loads a scene and instantiates it once, off-tree, so that script parse
## errors and detached scripts fail here instead of only printing engine
## errors while the handoff still completes (Opus review finding 3).
func _check_scene_loads(scene_path: String) -> void:
	if not ResourceLoader.exists(scene_path):
		_fail("missing scene resource: %s" % scene_path)
		return
	var packed: PackedScene = load(scene_path)
	if packed == null:
		_fail("could not load packed scene: %s" % scene_path)
		return
	var instance: Node = packed.instantiate()
	if instance == null:
		_fail("could not instantiate scene: %s" % scene_path)
		return
	_check_scene_scripts(scene_path, instance)
	instance.free()


## Every node that carries a script must have it attached and loadable. A
## script with a parse error fails to attach, so the node reports a null
## script; a script that loads but cannot instantiate is rejected as well.
func _check_scene_scripts(scene_path: String, root: Node) -> void:
	var root_script: Script = root.get_script()
	if root_script == null:
		_fail("%s: root node '%s' has no script attached (parse error or detached script)" % [scene_path, root.name])
	elif not root_script.can_instantiate():
		_fail("%s: root script '%s' is not loadable" % [scene_path, root_script.resource_path])
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			var child_script: Script = child.get_script()
			if child_script != null and not child_script.can_instantiate():
				_fail("%s: script '%s' on '%s' is not loadable" % [scene_path, child_script.resource_path, child.name])
			pending.append(child)


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
	elif quit_button.pressed.get_connections().is_empty():
		# Ready marker: main_menu.gd::_ready connects this button. No
		# connection means the script threw before finishing _ready, which
		# the scene-structure checks above cannot see.
		_fail("menu quit button has no 'pressed' connection: main_menu.gd::_ready did not complete")


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
