extends SceneTree
## Entry point for the independent M0.8 contract tests.
##
##   godot --headless --fixed-fps 60 --path tools/tick_probe \
##       --script res://tests/contract_entry.gd
##
## Exit code 0 means every contract test passed, 1 means at least one failed.


func _initialize() -> void:
	var driver_script: GDScript = load("res://tests/contract_driver.gd")
	var driver := Node.new()
	driver.set_script(driver_script)
	root.add_child.call_deferred(driver)
