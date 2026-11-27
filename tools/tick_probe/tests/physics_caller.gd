extends Node
## Test-only later-ordered physics caller for the F1 regression.
##
## Added to the scene tree after the coordinator; PROCESS_MODE_ALWAYS lets it
## run while the authoritative world is paused. On its first physics callback
## it requests a positive step, exactly like a motor/bridge node would.

var coordinator
var requested_once := false
var accepted := false
var paused_after_call := false


func _physics_process(_delta: float) -> void:
	if not requested_once and coordinator != null:
		requested_once = true
		accepted = coordinator.begin_step(12)
		paused_after_call = get_tree().paused
