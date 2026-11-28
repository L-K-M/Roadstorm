extends SceneTree
## Headless entry point for the M1.7 physical sweeper bridge laboratory.
##
## Use tools/calibration_sweeper_lab/run_validation.sh, which stages a private
## frozen project copy, imports it, serializes pinned Godot invocations on the
## shared coordinator lock and requires this validator plus the deliberate
## failure probe.
##
## Prints CALIBRATION_SWEEPER_LAB_CASE per case, CALIBRATION_SWEEPER_SUMMARY
## and CHECKS_TOTAL/CHECKS_FAILED, then exits 0/1. With
## `-- --summary-out=<path>` it writes the full summary JSON.


func _initialize() -> void:
	var driver := Node.new()
	driver.name = "CalibrationSweeperLabDriver"
	driver.set_script(
		preload("res://tools/calibration_sweeper_lab/calibration_sweeper_lab_driver.gd")
	)
	root.add_child.call_deferred(driver)


func _summary_out_path() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--summary-out="):
			return arg.substr("--summary-out=".length())
	return ""
