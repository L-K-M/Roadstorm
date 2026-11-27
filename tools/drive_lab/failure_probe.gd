extends SceneTree
## Deliberate failing-check proof for the drive-lab runner.
##
## The isolated runner executes this probe and requires a nonzero exit code
## plus `"pass":false`, proving that a failing check cannot be reported as a
## success. Exit code 3 is deliberately distinctive.


func _initialize() -> void:
	var checks := preload("res://tools/drive_lab/drive_lab_checks.gd").new()
	checks.check(true, "control check passes")
	checks.check(false, "deliberate failure: a failing assertion must fail the run")
	var report := {
		"schema": "roadstorm.drive_lab.failure_probe.v1",
		"checks": checks.checks,
		"failures": checks.failures.duplicate(),
		"pass": checks.failures.is_empty(),
	}
	print("PROBE_RESULT ", JSON.stringify(report))
	print("CHECKS_TOTAL=", checks.checks, " CHECKS_FAILED=", checks.failures.size())
	quit(3)
