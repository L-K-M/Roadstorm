extends Node
## Test-only observer used to measure engine callback delivery around the
## coordinator's request boundaries. Default process mode/priority; instances
## can be given an explicit process_priority to probe ordering.

var physics_callbacks := 0
var unpaused_physics_callbacks := 0
var coord_ref
var tick_sequence: Array[int] = []
## Engine physics-frame counter observed at each unpaused callback, parallel to
## tick_sequence. Lets tests prove the observer ran in the same engine
## iteration as the coordinator's logical tick rather than merely reading a
## consecutive tick count one iteration later.
var tick_frame_sequence: Array[int] = []


func _physics_process(_delta: float) -> void:
	physics_callbacks += 1
	if not get_tree().paused:
		unpaused_physics_callbacks += 1
		if coord_ref != null:
			tick_sequence.append(coord_ref.tick_count)
			tick_frame_sequence.append(Engine.get_physics_frames())


func clear_ticks() -> void:
	tick_sequence.clear()
	tick_frame_sequence.clear()
