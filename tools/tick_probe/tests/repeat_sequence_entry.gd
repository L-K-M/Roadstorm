extends SceneTree
## Entry point for the hard same-world repeated-sequence gate.
##
##   godot --headless --fixed-fps 60 --path tools/tick_probe \
##       --script res://tests/repeat_sequence_entry.gd

func _initialize() -> void:
	var driver_script: GDScript = load("res://tests/repeat_sequence_driver.gd")
	var driver := Node.new()
	driver.set_script(driver_script)
	root.add_child.call_deferred(driver)
