extends Node
## Test-only observer used to measure engine callback delivery around the
## coordinator's request boundaries. Default process mode/priority; instances
## can be given an explicit process_priority to probe ordering.

var physics_callbacks := 0
var unpaused_physics_callbacks := 0


func _physics_process(_delta: float) -> void:
	physics_callbacks += 1
	if not get_tree().paused:
		unpaused_physics_callbacks += 1
