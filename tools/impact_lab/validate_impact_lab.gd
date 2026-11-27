extends SceneTree
## Headless entry point for the M1.8 impact-event contract laboratory.
##
## Run from an isolated scratch project copy after a headless import:
##   godot --headless --fixed-fps 60 --path <scratch> \
##       --script res://tools/impact_lab/validate_impact_lab.gd
##
## or use tools/impact_lab/run_validation.sh, which stages a private copy,
## imports, serializes engine calls on the coordinator lock, enforces an outer
## timeout, gates engine error lines and requires an IMPACT_LAB_SUMMARY line
## containing "pass":true plus a nonzero deliberate-failure probe.

const DriverScript := preload("res://tools/impact_lab/impact_lab_driver.gd")


func _initialize() -> void:
	var driver := Node.new()
	driver.name = "ImpactLabDriver"
	driver.set_script(DriverScript)
	# The root is still setting up children during _initialize(); defer the add.
	root.add_child.call_deferred(driver)
