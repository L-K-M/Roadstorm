extends SceneTree
## Deliberate failing-check proof.

const ChecksScript := preload("res://tools/cosmetic_damage_lab/cosmetic_damage_lab_checks.gd")

func _initialize() -> void:
	var probe_case := ChecksScript.Case.new()
	probe_case.name = "deliberate_failure"
	probe_case.check(true, "control check passes")
	probe_case.check(false, "deliberate failure: a failing assertion must fail the run")
	var report := {
		"schema": "roadstorm.cosmetic_damage_lab.failure_probe.v1",
		"checks": probe_case.checks,
		"failures": probe_case.failures.duplicate(),
		"pass": probe_case.failures.is_empty(),
	}
	print("COSMETIC_DAMAGE_LAB_FAILURE_PROBE ", JSON.stringify(report))
	print("CHECKS_TOTAL=", probe_case.checks, " CHECKS_FAILED=", probe_case.failures.size())
	quit(3)
