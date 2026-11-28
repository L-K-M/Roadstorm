class_name MainMenuPlaceholder
extends Control
## M0 placeholder main menu with one playable graybox practice entry.
##
## The committed `scenes/game.tscn` hosts the real `DriveLab`; this menu only
## offers that entry and Quit. Navigation, join, car selection, settings and
## other modes remain out of scope (M5.3/M6.5 work).

const GAME_SCENE_PATH := "res://scenes/game.tscn"

@onready var _practice_button: Button = %PracticeButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	print("[menu] placeholder menu shown (Driving Lab entry available)")
	_practice_button.pressed.connect(_on_practice_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)


func _on_practice_pressed() -> void:
	print("[menu] entering practice: ", GAME_SCENE_PATH)
	get_tree().change_scene_to_file(GAME_SCENE_PATH)


func _on_quit_pressed() -> void:
	get_tree().quit()
