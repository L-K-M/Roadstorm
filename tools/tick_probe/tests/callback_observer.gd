extends Node
## Test-only observer used to measure engine callback delivery around the
## coordinator's request boundaries. Default process mode/priority; instances
## can be given an explicit process_priority to probe ordering.

var physics_callbacks := 0
var unpaused_physics_callbacks := 0
var coord_ref
var tick_sequence: Array[int] = []


func _physics_process(_delta: float) -> void:
	physics_callbacks += 1
	if not get_tree().paused:
		unpaused_physics_callbacks += 1
		if coord_ref != null:
			tick_sequence.append(coord_ref.tick_count)


func clear_ticks() -> void:
	tick_sequence.clear()
