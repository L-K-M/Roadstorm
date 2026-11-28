class_name GamePlaceholder
extends Node3D
## Practice scene: one committed `DriveLab` instance plus a small overlay.
##
## The laboratory owns the graybox straight, car, motor, chase camera, HUD and
## audio. This scene only selects keyboard command mode before the first
## physics tick, offers Escape/public navigation back to the menu, and reports
## a laboratory failure or halt truthfully on screen. It creates no second
## camera, viewport, motor step or world geometry.

const MENU_SCENE_PATH := "res://scenes/main_menu.tscn"
const BACK_HINT_TEXT := "Esc - back to menu"

@onready var _drive_lab: DriveLab = $DriveLab as DriveLab

var _diagnostic_label: Label = null
var _diagnostic_shown := ""


func _ready() -> void:
	if _drive_lab == null:
		push_error("[game] DriveLab instance is missing from scenes/game.tscn")
	else:
		# Must happen before the first physics tick: in KEYBOARD mode the
		# laboratory samples live key state once per tick.
		_drive_lab.command_mode = DriveLab.CommandMode.KEYBOARD
	_build_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		return_to_menu()


## Public navigation back to the committed menu. Used by the headless
## practice-flow lab and available to any future pause/settings flow.
func return_to_menu() -> void:
	if not ResourceLoader.exists(MENU_SCENE_PATH):
		push_error("[game] menu scene missing: %s" % MENU_SCENE_PATH)
		_show_diagnostic("Practice cannot return: menu scene is missing")
		return
	print("[game] returning to menu: ", MENU_SCENE_PATH)
	get_tree().change_scene_to_file(MENU_SCENE_PATH)


func _process(_delta: float) -> void:
	if _drive_lab == null:
		_show_diagnostic("Driving Lab unavailable: DriveLab instance is missing")
		return
	if _drive_lab.failed:
		_show_diagnostic(
			"Driving Lab failed: %s" % _failure_text(_drive_lab.failure_reason, "no reason recorded")
		)
	elif _drive_lab.halted:
		_show_diagnostic(
			"Driving Lab halted: %s" % _failure_text(_drive_lab.halt_reason, "no reason recorded")
		)
	else:
		_show_diagnostic("")


func _failure_text(reason: String, fallback: String) -> String:
	var trimmed := reason.strip_edges()
	return trimmed if not trimmed.is_empty() else fallback


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "GameOverlay"
	add_child(layer)

	var hint := Label.new()
	hint.name = "BackHint"
	hint.text = BACK_HINT_TEXT
	hint.position = Vector2(16.0, 12.0)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hint)

	var diagnostic := Label.new()
	diagnostic.name = "Diagnostic"
	diagnostic.visible = false
	diagnostic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	diagnostic.set_anchors_preset(Control.PRESET_FULL_RECT)
	diagnostic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	diagnostic.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	diagnostic.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	diagnostic.add_theme_font_size_override("font_size", 28)
	diagnostic.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	diagnostic.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	diagnostic.add_theme_constant_override("outline_size", 6)
	layer.add_child(diagnostic)
	_diagnostic_label = diagnostic


func _show_diagnostic(message: String) -> void:
	if _diagnostic_label == null:
		return
	var trimmed := message.strip_edges()
	if trimmed == _diagnostic_shown:
		return
	_diagnostic_shown = trimmed
	_diagnostic_label.text = trimmed
	_diagnostic_label.visible = not trimmed.is_empty()
