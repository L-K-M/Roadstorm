extends SceneTree
## Entry point for the warmed server-step probe used by the F2/F3 evidence.
##
##   godot --headless --fixed-fps 60 --path tools/tick_probe \
##       --script res://tests/warm_step_probe_entry.gd

func _initialize() -> void:
	var driver_script: GDScript = load("res://tests/warm_step_probe_driver.gd")
	var driver := Node.new()
	driver.set_script(driver_script)
	root.add_child.call_deferred(driver)
