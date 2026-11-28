extends SceneTree
## Deliberate failing-check proof for the road-source laboratory runner.
## Exit code 3 is deliberately distinctive: a passing run of this probe would
## mean the lab cannot detect a failing check.

const ChecksScript := preload(
	"res://tools/road_source_lab/road_source_checks.gd"
)


func _initialize() -> void:
	var probe_case := ChecksScript.Case.new()
	probe_case.name = "deliberate_failure"
	probe_case.check(true, "control check passes")
	probe_case.check(false, "deliberate failure: a failing assertion must fail the run")
	var report := {
		"schema": "roadstorm.road_source_lab.failure_probe.v1",
		"checks": probe_case.checks,
		"failures": probe_case.failures.duplicate(),
		"pass": probe_case.failures.is_empty(),
	}
	print("ROAD_SOURCE_FAILURE_PROBE ", JSON.stringify(report))
	print(
		"CHECKS_TOTAL=",
		probe_case.checks,
		" CHECKS_FAILED=",
		probe_case.failures.size()
	)
	quit(3)
