extends Node
## Internal helper owned by the M0.8 coordinator.
##
## The coordinator needs one extra unpaused engine iteration after a request so
## the final tick's physics-server step is not suppressed by an immediate
## SceneTree pause. A plain pausable simulation node would still receive that
## iteration's `_physics_process`. This helper is PROCESS_MODE_ALWAYS and is
## ordered after the coordinator but before ordinary world nodes; it performs
## the deferred pause at the start of that iteration, so pausable nodes later
## in the tree are skipped. Simulation nodes ordered before the coordinator
## (or otherwise earlier than this helper) still see the extra callback and
## must gate on the coordinator's tick state.

var coordinator: Node


func _physics_process(_delta: float) -> void:
	if coordinator != null:
		coordinator.request_deferred_pause()
