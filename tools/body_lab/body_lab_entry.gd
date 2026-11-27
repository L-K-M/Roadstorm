extends SceneTree
## Headless entry point for the M1.1 motor/body adapter laboratory.
##
## Run from an isolated scratch project copy after a headless import:
##   godot --headless --fixed-fps 60 --path <scratch> \
##       --script res://tools/body_lab/body_lab_entry.gd
## or use tools/body_lab/run_body_lab.sh, which stages a private copy, imports,
## enforces a wall-clock timeout, gates engine ERROR/SCRIPT ERROR lines, and
## requires a SLICE_SUMMARY line containing "pass":true.
##
## Optional `--case=<id>` selects one case; the default runs every case. On
## this engine the argument follows the script path directly.

const DriverScript = preload("res://tools/body_lab/body_lab_driver.gd")


func _initialize() -> void:
	var driver := Node.new()
	driver.name = "BodyLabDriver"
	driver.set_script(DriverScript)
	# The root is still setting up children during _initialize(); defer the add.
	root.add_child.call_deferred(driver)
