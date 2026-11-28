extends SceneTree
## Headless entry point for the bounded wall-contact policy laboratory.
##
## Runs the WallContactPolicyLabChecks suite, which prints one
## WALL_CONTACT_POLICY_LAB_CASE line per case, then prints
## WALL_CONTACT_POLICY_LAB_SUMMARY and CHECKS_TOTAL/CHECKS_FAILED and exits 0
## only when every check passed. This validates the provisional pure policy
## only; it is not M1.8 acceptance and has no cosmetic consumer.

const ChecksScript := preload(
	"res://tools/wall_contact_policy_lab/wall_contact_policy_checks.gd"
)


func _initialize() -> void:
	var checks := ChecksScript.new()
	var summary: Dictionary = checks.run_all()

	print("WALL_CONTACT_POLICY_LAB_SUMMARY ", JSON.stringify(summary))
	print("CHECKS_TOTAL=", summary["checks"], " CHECKS_FAILED=", summary["checks_failed"])

	quit(0 if bool(summary["pass"]) else 1)
