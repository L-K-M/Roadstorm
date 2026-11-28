extends SceneTree
## Deliberate failing-check proof for the calibration-driver lab runner.
##
## The isolated runner executes this probe and requires a nonzero exit code
## plus `"pass":false`, proving that a failing assertion cannot be reported as
## a success. Exit code 3 is deliberately distinctive.

const ChecksScript = preload(
	"res://tools/calibration_driver_lab/calibration_driver_lab_checks.gd"
)


func _initialize() -> void:
	# Exercise the lab's real Case collector so the probe proves the same
	# assertion path fails closed; `check` lives on Case, not the suite.
	var probe_case := ChecksScript.Case.new()
	probe_case.name = "deliberate_failure"
	probe_case.check(true, "control check passes")
	probe_case.check(
		false,
		"deliberate failure: a failing assertion must fail the run"
	)
	var report := {
		"schema": "roadstorm.calibration_driver_lab.failure_probe.v1",
		"checks": probe_case.checks,
		"failures": probe_case.failures.size(),
		"case_results": [probe_case.result()],
		"pass": probe_case.failures.is_empty(),
	}
	print("CALIBRATION_DRIVER_FAILURE_PROBE ", JSON.stringify(report))
	print(
		"CHECKS_TOTAL=",
		probe_case.checks,
		" CHECKS_FAILED=",
		probe_case.failures.size()
	)
	quit(3)
