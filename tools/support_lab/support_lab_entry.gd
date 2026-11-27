extends SceneTree
## Headless entry point for the M1.4 ground-support sensing laboratory.
##
## Run from an isolated scratch project copy after a headless import:
##   godot --headless --fixed-fps 60 --path <scratch> \
##       --script res://tools/support_lab/support_lab_entry.gd
## or use tools/support_lab/run_support_lab.sh, which stages a private copy,
## imports, enforces wall-clock timeouts, gates engine errors, runs the
## deliberate-failure proof and the broken-behaviour mutants, and requires a
## SLICE_SUMMARY line containing "pass":true.
##
## Optional `--case=<id>` selects one case; the default runs every case.

const DriverScript = preload("res://tools/support_lab/support_lab_driver.gd")


func _initialize() -> void:
	var driver := Node.new()
	driver.name = "SupportLabDriver"
	driver.set_script(DriverScript)
	# The root is still setting up children during _initialize(); defer the add.
	root.add_child.call_deferred(driver)
