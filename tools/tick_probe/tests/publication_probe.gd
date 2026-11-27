extends Node
## Test-only observer ordered BEFORE the coordinator (lower
## process_physics_priority) so it can exercise the inter-callback
## _pending_publish window: refused begin_step, empty take_result, then reset
## cancels publication.

var coordinator
var fired := false
var begin_accepted := false
var take_was_empty := true
var reset_done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -2000


func _physics_process(_delta: float) -> void:
	if fired or coordinator == null or not coordinator.is_publication_pending():
		return
	fired = true
	begin_accepted = coordinator.begin_step(12)
	take_was_empty = coordinator.take_result().is_empty()
	coordinator.reset()
	reset_done = true
