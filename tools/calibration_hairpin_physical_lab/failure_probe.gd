extends SceneTree
## Deliberate failing-check control for the hairpin first-tick physical lab.
##
## This is a harness control, not a physics case: it proves that a failing
## assertion in this lab's reporting path makes the engine exit nonzero, so a
## green runner cannot hide a red check. It touches one real committed identity
## (the authored hairpin path conversion) and then records one deliberate
## failure. Exit code 3 is deliberately distinctive.
##
## Run by tools/calibration_hairpin_physical_lab/run_validation.sh after the
## real first-tick case has passed.

const SourceScript = preload(
	"res://tools/calibration_hairpin_path_lab/calibration_hairpin_path_source.gd"
)

const SCHEMA := "roadstorm.calibration_hairpin_physical_lab.failure_probe.v1"


func _initialize() -> void:
	var checks := 0
	var failures: Array[String] = []

	var built: Dictionary = SourceScript.build()
	checks += 1
	if not bool(built.get("ok", false)):
		failures.append(
			"control check failed unexpectedly: committed hairpin path did not build"
		)
	else:
		var summary: Dictionary = built["summary"]
		# Real identity observation, not the deliberate failure below.
		checks += 1
		if String(summary.get("bay_id", "")) != "hairpin":
			failures.append(
				"control check failed unexpectedly: built bay_id is not hairpin"
			)

	checks += 1
	# Deliberate mismatch: the provisional target speed is authored at 18 m/s,
	# so requiring zero must fail.
	var target_speed := float(built.get("summary", {}).get("target_speed_m_s", 0.0))
	if is_equal_approx(target_speed, 18.0):
		failures.append(
			"deliberate failure: provisional target speed is 18 m/s, not the required 0 m/s"
		)

	var report := {
		"schema": SCHEMA,
		"pass": failures.is_empty(),
		"checks": checks,
		"failures": failures.duplicate(),
	}
	print("CALIBRATION_HAIRPIN_PHYSICAL_FAILURE_PROBE ", JSON.stringify(report))
	print("CHECKS_TOTAL=", checks, " CHECKS_FAILED=", failures.size())
	quit(3 if not failures.is_empty() else 0)
