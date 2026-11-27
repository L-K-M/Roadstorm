extends Node
## Test-only physics-ordered injector: on the first physics callback that sees
## `coordinator.tick_count >= trigger_tick`, raises the configured speed above
## the movement envelope. Default priority means it runs after the
## coordinator's low-priority callback in the same engine iteration.

var coordinator
var trigger_tick := 3
var armed := false
var fired := false


func _physics_process(_delta: float) -> void:
	if armed and not fired and coordinator != null and coordinator.tick_count >= trigger_tick:
		fired = true
		coordinator.speed_mps = 250.0
