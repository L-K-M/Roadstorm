extends SceneTree
## Deliberate failing-assertion proof for the road-strip laboratory.
##
## Exit code 3 is deliberately distinctive: a passing run of this probe would
## mean the lab cannot detect a failing check.

class Probe extends RefCounted:
	var checks := 0
	var failures: Array[String] = []

	func assert_check(condition: bool, message: String) -> void:
		checks += 1
		if not condition:
			failures.append(message)


func _initialize() -> void:
	var probe := Probe.new()
	probe.assert_check(true, "control assertion passes")
	probe.assert_check(false, "deliberate failure: a failing assertion must fail the run")
	var report := {
		"checks": probe.checks,
		"failed": probe.failures.size(),
		"pass": probe.failures.is_empty(),
	}
	print("ROAD_STRIP_FAILURE_PROBE ", JSON.stringify(report))
	print("CHECKS_TOTAL=", probe.checks, " CHECKS_FAILED=", probe.failures.size())
	quit(3 if not bool(report["pass"]) else 0)
