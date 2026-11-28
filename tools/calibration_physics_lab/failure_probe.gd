extends SceneTree
## Deliberate failing-check proof for the calibration physics lab runner.
## Exit code 3 is deliberately distinctive.

const ChecksScript := preload(
	"res://tools/calibration_physics_lab/calibration_physics_lab_checks.gd"
)


func _initialize() -> void:
	var probe_case := ChecksScript.Case.new()
	probe_case.name = "deliberate_failure"
	probe_case.check(true, "control check passes")
	probe_case.check(false, "deliberate failure: a failing assertion must fail the run")
	var report := {
		"schema": "roadstorm.calibration_physics_lab.failure_probe.v1",
		"checks": probe_case.checks,
		"failures": probe_case.failures.duplicate(),
		"pass": probe_case.failures.is_empty(),
	}
	print("CALIBRATION_PHYSICS_FAILURE_PROBE ", JSON.stringify(report))
	print(
		"CHECKS_TOTAL=",
		probe_case.checks,
		" CHECKS_FAILED=",
		probe_case.failures.size()
	)
	quit(3)
