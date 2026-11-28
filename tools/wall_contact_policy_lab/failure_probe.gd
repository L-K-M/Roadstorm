extends SceneTree
## Deliberate failing-check proof for the wall-contact policy laboratory.
##
## Exit code 3 is deliberately distinctive: a passing run of this probe would
## mean the lab cannot detect a failing check.

const ChecksScript := preload(
	"res://tools/wall_contact_policy_lab/wall_contact_policy_checks.gd"
)


func _initialize() -> void:
	var probe_case := ChecksScript.Case.new()
	probe_case.name = "deliberate_failure"
	probe_case.check(true, "control check passes")
	probe_case.check(false, "deliberate failure: a failing assertion must fail the run")
	var report := probe_case.result()

	print("WALL_CONTACT_POLICY_LAB_FAILURE_PROBE ", JSON.stringify(report))
	print("CHECKS_TOTAL=", report["checks"], " CHECKS_FAILED=", report["checks_failed"])

	quit(3)
