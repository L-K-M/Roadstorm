extends SceneTree
## Headless entry point for the M1 one-car drive-lab validator.
##
## Run from an isolated project copy:
##   godot --headless --fixed-fps 60 --path <project> \
##       --script res://tools/drive_lab/validate_drive_lab.gd
##
## Prints `DRIVE_LAB_RESULT` per case and a final `DRIVE_LAB_SUMMARY` line.
## Exit code 0 means every case passed; 1 means at least one check failed.


func _initialize() -> void:
	var driver := Node.new()
	driver.name = "DriveLabDriver"
	driver.set_script(preload("res://tools/drive_lab/drive_lab_driver.gd"))
	root.add_child.call_deferred(driver)
