extends SceneTree
## Deliberate failing-check proof for the impact-event lab runner.
##
## The isolated runner executes this probe and requires a nonzero exit code
## plus `"pass":false`, proving that a failing assertion cannot be reported as
## a success. Exit code 3 is deliberately distinctive.

const ChecksScript := preload("res://tools/impact_lab/impact_lab_checks.gd")


func _initialize() -> void:
	var checks := ChecksScript.new()
	checks.check(true, "control check passes")
	checks.check(false, "deliberate failure: a failing assertion must fail the run")
	var report := {
		"schema": "roadstorm.impact_lab.failure_probe.v1",
		"checks": checks.checks,
		"failures": checks.failures.duplicate(),
		"pass": checks.failures.is_empty(),
	}
	print("IMPACT_PROBE_RESULT ", JSON.stringify(report))
	print("CHECKS_TOTAL=", checks.checks, " CHECKS_FAILED=", checks.failures.size())
	quit(3)
