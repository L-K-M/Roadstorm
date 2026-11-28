class_name CalibrationSweeperLabChecks
extends RefCounted
## Small assertion collector for the physical M1.7 sweeper bridge lab.
##
## The checks describe integration and identity facts only. They do not claim
## grip/drift parity, a completed lap, M1.7 acceptance or fun.

class Case extends RefCounted:
	var name := ""
	var checks := 0
	var failures: Array[String] = []
	var measurements: Dictionary = {}

	func check(condition: bool, message: String) -> void:
		checks += 1
		if not condition:
			failures.append(message)

	func equal(actual, expected, message: String) -> void:
		checks += 1
		if actual != expected:
			failures.append(
				"%s (got %s expected %s)" % [message, str(actual), str(expected)]
			)

	func close(
		actual: float, expected: float, tolerance: float, message: String
	) -> void:
		checks += 1
		if is_nan(actual) or is_inf(actual) or absf(actual - expected) > tolerance:
			failures.append(
				"%s (got %s expected %s tol %s)"
					% [message, str(actual), str(expected), str(tolerance)]
			)

	func result() -> Dictionary:
		return {
			"case": name,
			"pass": failures.is_empty(),
			"checks": checks,
			"checks_failed": failures.size(),
			"failures": failures.duplicate(),
			"measurements": measurements.duplicate(true),
		}
