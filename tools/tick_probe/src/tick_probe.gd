extends SceneTree
## M0.8 tick/reset/query probe entry point.
##
## Run from the repository root, for example:
##   godot --headless --path tools/tick_probe \
##       --script res://src/tick_probe.gd -- mode=structural
##
## Exit code 0 means every probe check passed, 1 means at least one failed.


func _initialize() -> void:
	var driver_script: GDScript = load("res://src/probe_driver.gd")
	var driver := Node.new()
	driver.set_script(driver_script)
	# The root is still setting up children during _initialize(); adding the
	# driver synchronously is rejected, so defer it to the first idle frame.
	root.add_child.call_deferred(driver)
