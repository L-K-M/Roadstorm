class_name BootScene
extends Node
## M0 placeholder boot scene.
##
## The shell's only job right now is to start cleanly and hand off to the
## placeholder menu. No game systems exist yet (see PLAN.md milestone M0):
## no profiles, settings service, asset pipeline or race content.
##
## The handoff is frame-based rather than timer-based so the headless smoke
## test in tools/smoke/ is deterministic.

## Scene to hand off to once the shell is up.
@export var menu_scene_path: String = "res://scenes/main_menu.tscn"

## Number of rendered frames to hold before handing off. Placeholder pacing;
## a real splash/branding pass belongs to M5 presentation work.
@export var hold_frames: int = 2

var _frames_held: int = 0
var _handed_off: bool = false


func _ready() -> void:
	print("[boot] Roadstorm Racer! M0 shell (placeholder - no gameplay yet)")


func _process(_delta: float) -> void:
	if _handed_off:
		return
	_frames_held += 1
	if _frames_held < hold_frames:
		return
	_handed_off = true
	_handoff_to_menu()


func _handoff_to_menu() -> void:
	if not ResourceLoader.exists(menu_scene_path):
		push_error("[boot] menu scene missing: %s" % menu_scene_path)
		return
	print("[boot] handing off to menu: ", menu_scene_path)
	get_tree().change_scene_to_file(menu_scene_path)
