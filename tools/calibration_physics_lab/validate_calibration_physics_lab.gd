extends SceneTree
## Headless entry point for the M1.7 physical straight-line bridge laboratory.
##
## Use tools/calibration_physics_lab/run_validation.sh, which stages a private
## copy, imports it, serializes pinned Godot invocations on the shared lock and
## requires this validator plus the deliberate failure probe.


func _initialize() -> void:
	var driver := Node.new()
	driver.name = "CalibrationPhysicsLabDriver"
	driver.set_script(
		preload("res://tools/calibration_physics_lab/calibration_physics_lab_driver.gd")
	)
	root.add_child.call_deferred(driver)
