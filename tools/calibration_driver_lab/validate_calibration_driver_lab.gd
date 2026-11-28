extends SceneTree
## Headless entry point for the M1.7 calibration-driver CONTROL laboratory.
##
## Run from an isolated scratch project copy after a headless import:
##   godot --headless --fixed-fps 60 --path <scratch> \
##       --script res://tools/calibration_driver_lab/validate_calibration_driver_lab.gd
##
## or use tools/calibration_driver_lab/run_calibration_driver_lab.sh, which
## stages a private copy, imports it, serializes engine calls on the coordinator
## godot-test lock, enforces an outer timeout, gates engine error lines and
## requires this summary plus a nonzero deliberate-failure probe.

const ChecksScript = preload(
	"res://tools/calibration_driver_lab/calibration_driver_lab_checks.gd"
)


func _initialize() -> void:
	var checks := ChecksScript.new()
	var summary := checks.run_all()
	print("CALIBRATION_DRIVER_LAB_SUMMARY ", JSON.stringify(summary))
	print("CHECKS_TOTAL=", summary.checks, " CHECKS_FAILED=", summary.checks_failed)
	quit(0 if summary.pass else 1)
