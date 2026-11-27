extends SceneTree
## Entry point for the N1 dynamic-step regression.
##
##   godot --headless --fixed-fps 60 --path tools/tick_probe \
##       --script res://tests/n1_regression_entry.gd
##
## Exit code 0 means every N1 check passed, 1 means at least one failed.


func _initialize() -> void:
	var driver_script: GDScript = load("res://tests/n1_regression_driver.gd")
	var driver := Node.new()
	driver.set_script(driver_script)
	root.add_child.call_deferred(driver)
