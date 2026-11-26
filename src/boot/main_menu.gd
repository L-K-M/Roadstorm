class_name MainMenuPlaceholder
extends Control
## M0 placeholder main menu.
##
## It exists so the boot handoff has a real destination and so the shell can
## be smoke-tested end to end. It deliberately contains no navigation, join,
## car selection, settings or mode entry: those belong to M5.3/M6.5 work.

@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	print("[menu] placeholder menu shown (no navigation implemented yet)")
	_quit_button.pressed.connect(_on_quit_pressed)


func _on_quit_pressed() -> void:
	get_tree().quit()
