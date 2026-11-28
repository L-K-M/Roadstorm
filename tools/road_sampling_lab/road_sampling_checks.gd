class_name RoadSamplingLabChecks
extends RefCounted
## Focused checks for the deterministic RoadArcSampler slice. The fixtures are
## original lab data. These checks exercise arc tables and uniform samples only;
## they do not bake geometry, validate course quality, or claim M2.1 acceptance.

const RoadSourceDocument := preload("res://src/course/road_source.gd")
const RoadArcSampler := preload("res://src/course/road_arc_sampler.gd")

const FIXTURE_DIR := "res://tools/road_sampling_lab/fixtures"
const OPEN_STRAIGHT_PATH := FIXTURE_DIR + "/road_sampling_open_straight.json"
const OPEN_CURVE_PATH := FIXTURE_DIR + "/road_sampling_open_curve.json"
const CLOSED_LOOP_PATH := FIXTURE_DIR + "/road_sampling_closed_loop.json"

const INDEPENDENT_LENGTH_PANELS := 65536
const INDEPENDENT_GAUSS_COARSE_PANELS := 64
const INDEPENDENT_GAUSS_FINE_PANELS := 256
## Coarse/fine uncertainty limit for the independent fixed quadrature. It is
## one picometre, six orders of magnitude below the sampler tolerance.
const INDEPENDENT_REFERENCE_UNCERTAINTY_LIMIT_M := 1.0e-12
const SEEDED_ROAD_SPAN_COUNT := 40
const CURVED_LENGTH_AGREEMENT_TOLERANCE_M := 0.005
const GAUSS5_X := [-0.9061798459386640, -0.5384693101056831, 0.0, 0.5384693101056831, 0.9061798459386640]
const GAUSS5_W := [0.2369268850561891, 0.4786286704993665, 0.5688888888888889, 0.4786286704993665, 0.2369268850561891]
## Exact length of the Sol analytic quadratic B(t)=(t, 5t^2-3.17t, 0).
const SOL_QUADRATIC_EXACT_LENGTH_M := 3.1086978942948535
## Independent midpoint panels used only to invert the analytic quadratic.
const ANALYTIC_INVERSE_PANELS := 4096
## Pass gate for the pinned-engine review counterexamples: the authored
## per-span tolerance, compared against an independent fine reference rather
## than the sampler's own Richardson estimate.
const REVIEW_COUNTEREXAMPLE_TOLERANCE_M := 0.001


class Case extends RefCounted:
	var name := ""
	var checks := 0
	var failures: Array[String] = []
	var measurements: Dictionary = {}

	func check(condition: bool, message: String) -> void:
		checks += 1
		if not condition:
			failures.append(message)

	func equal(actual: Variant, expected: Variant, message: String) -> void:
		checks += 1
		if actual != expected:
			failures.append("%s (got %s expected %s)" % [message, str(actual), str(expected)])

	func close(actual: float, expected: float, tolerance: float, message: String) -> void:
		checks += 1
		if absf(actual - expected) > tolerance:
			failures.append(
				"%s (got %.9f expected %.9f tol %.9f)" % [message, actual, expected, tolerance]
			)

	func vector_close(actual: Vector3, expected: Vector3, tolerance: float, message: String) -> void:
		checks += 1
		if actual.distance_to(expected) > tolerance:
			failures.append(
				"%s (got %s expected %s tol %.9f)" % [message, str(actual), str(expected), tolerance]
			)

	func accepts_table(result: Dictionary, message: String) -> RoadArcSampler.Table:
		checks += 1
		if not bool(result.get("ok", false)):
			failures.append(
				"%s: expected acceptance, got %s (%s)" % [
					message,
					str(result.get("code_name", "missing_code")),
					str(result.get("error", "missing error")),
				]
			)
			return null
		checks += 1
		if result.get("table", null) == null:
			failures.append(message + ": acceptance returned no table")
			return null
		return result["table"]

	func refuses(
		result: Dictionary,
		expected_code: int,
		message: String,
		expected_substring: String = ""
	) -> void:
		checks += 1
		if bool(result.get("ok", true)):
			failures.append(message + ": expected a refusal, got ok")
			return
		checks += 1
		if result.get("table", null) != null:
			failures.append(message + ": refusal returned a partial table")
		checks += 1
		if str(result.get("error", "")).strip_edges().is_empty():
			failures.append(message + ": refusal carried no diagnostic")
		checks += 1
		if typeof(result.get("diagnostic", null)) != TYPE_DICTIONARY:
			failures.append(message + ": refusal carried no structured diagnostic dictionary")
		checks += 1
		if int(result.get("code", -1)) != expected_code:
			failures.append(
				"%s: expected code %s, got %s (%s)" % [
					message,
					RoadArcSampler.refusal_name(expected_code),
					str(result.get("code_name", "missing")),
					str(result.get("error", "")),
				]
			)
		if not expected_substring.is_empty():
			checks += 1
			if not str(result.get("error", "")).contains(expected_substring):
				failures.append(
					"%s: diagnostic %s does not mention %s" % [
						message, str(result.get("error", "")), expected_substring
					]
				)

	func result() -> Dictionary:
		return {
			"case": name,
			"pass": failures.is_empty(),
			"checks": checks,
			"checks_failed": failures.size(),
			"failures": failures.duplicate(),
			"measurements": measurements.duplicate(),
		}


var cases_run := 0
var total_checks := 0
var total_failures := 0
var case_results: Array[Dictionary] = []


func run_all() -> Dictionary:
	for call in [
		Callable(self, "_case_open_straight_uniform_table"),
		Callable(self, "_case_open_curve_length_and_fields"),
		Callable(self, "_case_closed_loop_seam_and_boundaries"),
		Callable(self, "_case_deterministic_repeats"),
		Callable(self, "_case_source_preservation_and_table_copies"),
		Callable(self, "_case_malformed_and_derived_refusals"),
		Callable(self, "_case_budget_controls"),
		Callable(self, "_case_conservative_bracket_regressions"),
		Callable(self, "_case_translated_float64_regressions"),
		Callable(self, "_case_tightened_tolerance_precision_contract"),
	]:
		var result: Dictionary = call.call()
		case_results.append(result)
		cases_run += 1
		total_checks += int(result["checks"])
		total_failures += int(result["checks_failed"])
		print(
			"ROAD_SAMPLING_LAB_CASE ",
			JSON.stringify({
				"case": result["case"],
				"checks": result["checks"],
				"checks_failed": result["checks_failed"],
				"pass": result["pass"],
			})
		)
	return {
		"schema": "roadstorm.road_sampling_lab.summary.v1",
		"pass": total_failures == 0,
		"cases": cases_run,
		"cases_passed": cases_run - _failed_case_count(),
		"checks": total_checks,
		"checks_failed": total_failures,
		"fixtures": [OPEN_STRAIGHT_PATH, OPEN_CURVE_PATH, CLOSED_LOOP_PATH],
		"case_results": case_results.duplicate(),
	}


func _failed_case_count() -> int:
	var failed := 0
	for result in case_results:
		if not bool(result["pass"]):
			failed += 1
	return failed


# --- Fixture and numeric helpers --------------------------------------------


static func read_fixture_text(p_path: String) -> String:
	if not FileAccess.file_exists(p_path):
		return ""
	return FileAccess.get_file_as_string(p_path)


static func load_fixture(p_path: String) -> Dictionary:
	var text := read_fixture_text(p_path)
	if text.is_empty():
		return {"ok": false, "error": "fixture missing or empty: " + p_path, "doc": {}}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "fixture is not a JSON object: " + p_path, "doc": {}}
	return {"ok": true, "error": "", "doc": parsed}


static func parse_fixture_document(c: Case, p_path: String, label: String) -> RoadSourceDocument:
	var loaded := load_fixture(p_path)
	c.check(bool(loaded["ok"]), label + " fixture loads: " + str(loaded["error"]))
	if not bool(loaded["ok"]):
		return null
	var parsed := RoadSourceDocument.parse_document(loaded["doc"])
	c.check(bool(parsed["ok"]), label + " fixture parses: " + str(parsed["error"]))
	if not bool(parsed["ok"]):
		return null
	return parsed["document"]


static func build_table(c: Case, document: RoadSourceDocument, spacing: float, label: String) -> RoadArcSampler.Table:
	return c.accepts_table(
		RoadArcSampler.build_uniform_table(document, spacing),
		label
	)


static func vector3_from_array(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


## Scalar float64 endpoint chord of stored control points; mirrors the sampler's
## precision-floor computation without going through float32 Vector3 distance.
static func scalar_chord_length(points: Array[Vector3]) -> float:
	var first: Vector3 = points[0]
	var last: Vector3 = points[3]
	var dx := float(last.x) - float(first.x)
	var dy := float(last.y) - float(first.y)
	var dz := float(last.z) - float(first.z)
	return sqrt(dx * dx + dy * dy + dz * dz)


static func fixture_control_points(source: Dictionary, span_index: int) -> Array[Vector3]:
	var knots: Array = source["knots"]
	var end_index := span_index + 1
	if bool(source["closed"]) and span_index == knots.size() - 1:
		end_index = 0
	var start: Dictionary = knots[span_index]
	var end: Dictionary = knots[end_index]
	return [
		vector3_from_array(start["anchor"]),
		vector3_from_array(start["handle_out"]),
		vector3_from_array(end["handle_in"]),
		vector3_from_array(end["anchor"]),
	]


## Map a plan-view (x, y) point from the review counterexamples into the
## sampler's world axes: Vector3(x, 0, -y).
static func plan_point_to_array(p_point: Array) -> Array:
	return [float(p_point[0]), 0.0, -float(p_point[1])]


static func sol_quadratic_position(p_t: float) -> Vector3:
	return Vector3(p_t, 5.0 * p_t * p_t - 3.17 * p_t, 0.0)


static func sol_quadratic_speed(p_t: float) -> float:
	var slope := 10.0 * p_t - 3.17
	return sqrt(1.0 + slope * slope)


## Composite midpoint length of the analytic quadratic from t=0 to t.
static func sol_quadratic_length(p_t: float, p_panels: int) -> float:
	var width := p_t / float(p_panels)
	var sum := 0.0
	for panel in range(p_panels):
		sum += sol_quadratic_speed(width * (float(panel) + 0.5))
	return sum * width


static func sol_quadratic_inverse_length(p_target_s: float, p_panels: int) -> float:
	var low := 0.0
	var high := 1.0
	for iteration in range(64):
		var middle := 0.5 * (low + high)
		if sol_quadratic_length(middle, p_panels) < p_target_s:
			low = middle
		else:
			high = middle
	return 0.5 * (low + high)


static func independent_bezier_speed(points: Array[Vector3], t: float) -> float:
	var u := 1.0 - t
	var weight0 := 3.0 * u * u
	var weight1 := 6.0 * u * t
	var weight2 := 3.0 * t * t
	var p0: Vector3 = points[0]
	var p1: Vector3 = points[1]
	var p2: Vector3 = points[2]
	var p3: Vector3 = points[3]
	var dx := weight0 * (p1.x - p0.x) + weight1 * (p2.x - p1.x) + weight2 * (p3.x - p2.x)
	var dy := weight0 * (p1.y - p0.y) + weight1 * (p2.y - p1.y) + weight2 * (p3.y - p2.y)
	var dz := weight0 * (p1.z - p0.z) + weight1 * (p2.z - p1.z) + weight2 * (p3.z - p2.z)
	return sqrt(dx * dx + dy * dy + dz * dz)


## Independent length reference: plain fixed midpoint quadrature, not the
## sampler's adaptive Simpson or inversion implementation.
static func independent_midpoint_length(points: Array[Vector3], panels: int) -> float:
	var sum := 0.0
	for panel in range(panels):
		var t := (float(panel) + 0.5) / float(panels)
		sum += independent_bezier_speed(points, t)
	return sum / float(panels)


## Independent fixed Gauss-Legendre reference in scalar float arithmetic. It
## uses the float32-rounded control points exposed by the parsed document.
static func independent_gauss_length(points: Array[Vector3], panels: int) -> float:
	var width := 1.0 / float(panels)
	var half_width := 0.5 * width
	var sum := 0.0
	for panel in range(panels):
		var center := width * (float(panel) + 0.5)
		for point in range(GAUSS5_X.size()):
			sum += float(GAUSS5_W[point]) * independent_bezier_speed(
				points,
				center + half_width * float(GAUSS5_X[point])
			)
	return sum * half_width


static func translated_plan_control_points(p_plan: Array, p_offset: Array) -> Array:
	var out := []
	for point in p_plan:
		out.append([
			float(point[0]) + float(p_offset[0]),
			float(p_offset[1]),
			-float(point[1]) + float(p_offset[2]),
		])
	return out


static func normalized_variant(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR3:
			var vector: Vector3 = value
			return ["Vector3", vector.x, vector.y, vector.z]
		TYPE_DICTIONARY:
			var input: Dictionary = value
			var keys := input.keys()
			keys.sort()
			var out := {}
			for key in keys:
				out[str(key)] = normalized_variant(input[key])
			return out
		TYPE_ARRAY:
			var input_array: Array = value
			var out_array := []
			for item in input_array:
				out_array.append(normalized_variant(item))
			return out_array
	return value


static func canonical_table_text(table: RoadArcSampler.Table) -> String:
	return JSON.stringify(normalized_variant(table.to_dictionary()), "", false, true)


static func make_single_span_source(
	course_id: String,
	p0: Array,
	p1: Array,
	p2: Array,
	p3: Array
) -> Dictionary:
	return {
		"schema": RoadSourceDocument.SCHEMA,
		"course_id": course_id,
		"revision": "0.1.0",
		"closed": false,
		"knots": [
			{
				"anchor": p0,
				"handle_in": [p0[0] - 1.0, p0[1], p0[2] + 1.0],
				"handle_out": p1,
				"width_m": 10.0,
				"bank_deg": 0.0,
			},
			{
				"anchor": p3,
				"handle_in": p2,
				"handle_out": [p3[0] + 1.0, p3[1], p3[2] - 1.0],
				"width_m": 10.0,
				"bank_deg": 0.0,
			},
		],
		"sections": [
			{"section_id": course_id + ".only", "surface_id": "asphalt"}
		],
	}


static func parse_control_source(c: Case, source: Dictionary, label: String) -> RoadSourceDocument:
	var parsed := RoadSourceDocument.parse_document(source)
	c.check(bool(parsed["ok"]), label + " control source parses: " + str(parsed["error"]))
	if not bool(parsed["ok"]):
		return null
	return parsed["document"]


func _build_single_span_table(
	c: Case,
	course_id: String,
	label: String,
	points: Array,
	spacing: float
) -> RoadArcSampler.Table:
	var source := make_single_span_source(course_id, points[0], points[1], points[2], points[3])
	var document := parse_control_source(c, source, label)
	if document == null:
		return null
	return build_table(c, document, spacing, label + " builds at default options")


func _check_length_error_covered(
	c: Case,
	table: RoadArcSampler.Table,
	control_points: Array[Vector3],
	label: String
) -> Dictionary:
	var coarse_reference := independent_gauss_length(control_points, INDEPENDENT_GAUSS_COARSE_PANELS)
	var reference := independent_gauss_length(control_points, INDEPENDENT_GAUSS_FINE_PANELS)
	var reference_uncertainty := absf(reference - coarse_reference)
	var actual_error := absf(table.total_length_m - reference)
	var reported := table.length_error_estimate_m
	var allowed := reported
	c.check(
		reference_uncertainty <= INDEPENDENT_REFERENCE_UNCERTAINTY_LIMIT_M,
		"%s independent reference coarse/fine uncertainty is negligible (%.9f)" % [label, reference_uncertainty]
	)
	c.check(
		actual_error <= allowed,
		"%s reported error covers independent reference error (actual %.9f reported %.9f uncertainty %.9f)"
			% [label, actual_error, reported, reference_uncertainty]
	)
	c.check(
		reported <= RoadArcSampler.DEFAULT_ARC_LENGTH_TOLERANCE_M,
		label + " reported error estimate stays inside the default tolerance"
	)
	return {
		"actual_error": actual_error,
		"allowed": allowed,
		"reference": reference,
		"reference_uncertainty": reference_uncertainty,
		"reported": reported,
	}


# --- Positive cases ----------------------------------------------------------


func _case_open_straight_uniform_table() -> Dictionary:
	var c := Case.new()
	c.name = "open_straight_uniform_table"
	var document := parse_fixture_document(c, OPEN_STRAIGHT_PATH, "open straight")
	if document == null:
		return c.result()
	var table := build_table(c, document, 15.0, "open straight builds")
	if table == null:
		return c.result()

	c.close(table.total_length_m, 60.0, 0.000001, "analytic straight total length")
	c.close(table.length_error_estimate_m, 0.0, 0.000000001, "straight Simpson error estimate is zero")
	c.equal(table.sample_count, 5, "exact spacing produces five samples")
	c.equal(table.span_count, 2, "two ordered span tables")
	var expected_stations := [0.0, 15.0, 30.0, 45.0, 60.0]
	var samples := table.samples
	for index in range(expected_stations.size()):
		var sample: Dictionary = samples[index]
		c.close(float(sample["s"]), float(expected_stations[index]), 0.000000001, "station %d exact" % index)
		if index > 0:
			c.check(
				float(sample["s"]) > float((samples[index - 1] as Dictionary)["s"]),
				"station %d strictly increases" % index
			)

	var start: Dictionary = samples[0]
	var end: Dictionary = samples[samples.size() - 1]
	c.vector_close(start["position"], Vector3(0.0, 0.0, 0.0), 0.000000001, "exact open start position")
	c.vector_close(end["position"], Vector3(0.0, 0.0, -60.0), 0.000000001, "exact open end position")
	c.equal(start["sample_role"], "open_start", "open start role")
	c.equal(end["sample_role"], "open_end", "open end role")
	c.close(float(end["span_t"]), 1.0, 0.0, "open end is final span t=1")

	var boundary: Dictionary = samples[2]
	c.equal(boundary["span_index"], 1, "knot boundary uses the following span")
	c.equal(boundary["section_id"], "lab.sampling.straight.b", "boundary section is following section")
	c.equal(boundary["surface_id"], "concrete", "boundary surface is following surface")
	c.close(float(boundary["span_t"]), 0.0, 0.000000001, "boundary is following span t=0")
	c.close(float(boundary["width_m"]), 10.0, 0.000000001, "boundary width is authored knot width")
	c.close(float(boundary["bank_deg"]), 6.0, 0.000000001, "boundary bank is authored knot bank")

	var midpoint: Dictionary = samples[1]
	c.close(float(midpoint["width_m"]), 11.0, 0.00001, "half-span width interpolation")
	c.close(float(midpoint["bank_deg"]), 3.0, 0.00001, "half-span bank interpolation")
	c.vector_close(midpoint["forward_tangent"], Vector3(0.0, 0.0, -1.0), 0.000000001, "straight forward tangent")
	c.close(float(midpoint["grade_dy_ds"]), 0.0, 0.000000001, "flat straight grade")
	c.close((midpoint["forward_tangent"] as Vector3).length(), 1.0, 0.000000001, "tangent normalized")

	var first_span := table.span_table(0)
	var second_span := table.span_table(1)
	c.close(float(first_span["length_m"]), 30.0, 0.000001, "first analytic span length")
	c.close(float(second_span["length_m"]), 30.0, 0.000001, "second analytic span length")
	c.equal(int(first_span["integration_leaf_count"]), 1, "straight first span integrates in one leaf")
	c.equal(int(second_span["integration_leaf_count"]), 1, "straight second span integrates in one leaf")
	c.close(float((first_span["nodes"] as Array)[0]["t"]), 0.0, 0.0, "first node t=0")
	c.close(float((first_span["nodes"] as Array)[(first_span["nodes"] as Array).size() - 1]["t"]), 1.0, 0.0, "last node t=1")

	for sample in samples:
		var span_record := table.span_table(int(sample["span_index"]))
		var start_knot := document.knot(int(span_record["start_knot_index"]))
		var end_knot := document.knot(int(span_record["end_knot_index"]))
		var min_width := minf(start_knot.width_m, end_knot.width_m)
		var max_width := maxf(start_knot.width_m, end_knot.width_m)
		var min_bank := minf(start_knot.bank_deg, end_knot.bank_deg)
		var max_bank := maxf(start_knot.bank_deg, end_knot.bank_deg)
		c.check(
			float(sample["width_m"]) >= min_width - 0.000000001
				and float(sample["width_m"]) <= max_width + 0.000000001,
			"width has no overshoot at sample %d" % int(sample["index"])
		)
		c.check(
			float(sample["bank_deg"]) >= min_bank - 0.000000001
				and float(sample["bank_deg"]) <= max_bank + 0.000000001,
			"bank has no overshoot at sample %d" % int(sample["index"])
		)

	c.measurements["straight_total_length_m"] = table.total_length_m
	c.measurements["straight_length_error_estimate_m"] = table.length_error_estimate_m
	c.measurements["straight_max_inversion_residual_m"] = table.max_inversion_residual_m
	return c.result()


func _case_open_curve_length_and_fields() -> Dictionary:
	var c := Case.new()
	c.name = "open_curve_length_and_fields"
	var loaded := load_fixture(OPEN_CURVE_PATH)
	c.check(bool(loaded["ok"]), "open curve fixture loads: " + str(loaded["error"]))
	if not bool(loaded["ok"]):
		return c.result()
	var document := parse_fixture_document(c, OPEN_CURVE_PATH, "open curve")
	if document == null:
		return c.result()
	var table := build_table(c, document, 5.0, "open curve builds")
	if table == null:
		return c.result()

	var control_points := fixture_control_points(loaded["doc"], 0)
	var independent_length := independent_midpoint_length(control_points, INDEPENDENT_LENGTH_PANELS)
	var length_difference := absf(table.total_length_m - independent_length)
	c.close(
		table.total_length_m,
		independent_length,
		CURVED_LENGTH_AGREEMENT_TOLERANCE_M,
		"curved length agrees with independent high-resolution midpoint integration"
	)
	c.check(
		table.length_error_estimate_m <= RoadArcSampler.DEFAULT_ARC_LENGTH_TOLERANCE_M,
		"reported curved length error estimate stays inside the explicit tolerance"
	)
	c.check(
		table.max_inversion_residual_m <= RoadArcSampler.DEFAULT_ARC_LENGTH_TOLERANCE_M * 0.1,
		"reported inversion residual stays inside the inversion tolerance"
	)

	var samples := table.samples
	c.equal(float(samples[0]["s"]), 0.0, "curve first station is exact start")
	c.close(
		float(samples[samples.size() - 1]["s"]),
		table.total_length_m,
		0.0,
		"curve last station is exact end"
	)
	for index in range(samples.size()):
		var sample: Dictionary = samples[index]
		if index > 0:
			c.check(
				float(sample["s"]) > float((samples[index - 1] as Dictionary)["s"]),
				"curve station %d strictly increases" % index
			)
		var tangent: Vector3 = sample["forward_tangent"]
		c.close(tangent.length(), 1.0, 0.000001, "curve tangent normalized at sample %d" % index)
		c.close(float(sample["grade_dy_ds"]), tangent.y, 0.0, "grade is tangent dy/ds at sample %d" % index)
		c.equal(sample["section_id"], "lab.sampling.curve.climb", "curve section id at sample %d" % index)
		c.equal(sample["surface_id"], "asphalt", "curve surface id at sample %d" % index)
		c.check(
			float(sample["width_m"]) >= 9.0 - 0.000000001
				and float(sample["width_m"]) <= 11.0 + 0.000000001,
			"curve width remains between authored endpoints at sample %d" % index
		)
		c.check(
			float(sample["bank_deg"]) >= -3.0 - 0.000000001
				and float(sample["bank_deg"]) <= 8.0 + 0.000000001,
			"curve bank remains between authored endpoints at sample %d" % index
		)

	c.measurements["curved_sampler_length_m"] = table.total_length_m
	c.measurements["curved_independent_length_m"] = independent_length
	c.measurements["curved_length_absolute_difference_m"] = length_difference
	c.measurements["curved_length_error_estimate_m"] = table.length_error_estimate_m
	c.measurements["curved_max_inversion_error_estimate_m"] = table.max_inversion_error_estimate_m
	c.measurements["curved_max_inversion_residual_m"] = table.max_inversion_residual_m
	c.measurements["curved_sample_count"] = table.sample_count
	return c.result()


func _case_closed_loop_seam_and_boundaries() -> Dictionary:
	var c := Case.new()
	c.name = "closed_loop_seam_and_boundaries"
	var document := parse_fixture_document(c, CLOSED_LOOP_PATH, "closed loop")
	if document == null:
		return c.result()
	var table := build_table(c, document, 15.0, "closed loop builds")
	if table == null:
		return c.result()

	c.close(table.total_length_m, 120.0, 0.000001, "closed rectangular loop total length")
	c.equal(table.sample_count, 9, "closed loop exact spacing sample count")
	var samples := table.samples
	var start: Dictionary = samples[0]
	var end: Dictionary = samples[samples.size() - 1]
	c.equal(start["sample_role"], "closed_seam_start", "closed start seam role")
	c.equal(end["sample_role"], "closed_seam_end", "closed end seam role")
	c.close(float(start["s"]), 0.0, 0.0, "closed seam starts at s=0")
	c.close(float(end["s"]), table.total_length_m, 0.0, "closed seam ends at total length")
	c.vector_close(start["position"], Vector3.ZERO, 0.000000001, "closed seam start position")
	c.vector_close(end["position"], Vector3.ZERO, 0.000000001, "closed seam end position")
	c.close((start["position"] as Vector3).distance_to(end["position"]), 0.0, 0.000000001, "closed seam positions coincide")
	var seam := table.closed_seam()
	c.equal(int(seam["start_sample_index"]), 0, "seam metadata start sample")
	c.equal(int(seam["end_sample_index"]), samples.size() - 1, "seam metadata end sample")
	c.check(str(seam["policy"]).contains("closed_seam_end"), "seam metadata states the ordered pair policy")

	var expected_boundary_spans := [1, 2, 3]
	var expected_sections := [
		"lab.sampling.loop.east",
		"lab.sampling.loop.south",
		"lab.sampling.loop.west",
	]
	for boundary_index in range(3):
		var sample: Dictionary = samples[(boundary_index + 1) * 2]
		c.equal(
			sample["span_index"],
			expected_boundary_spans[boundary_index],
			"closed interior boundary %d uses following span" % boundary_index
		)
		c.equal(
			sample["section_id"],
			expected_sections[boundary_index],
			"closed interior boundary %d uses following section" % boundary_index
		)
		c.close(float(sample["span_t"]), 0.0, 0.000000001, "closed interior boundary %d t=0" % boundary_index)
	c.equal(end["span_index"], 3, "closed final end uses final span")
	c.close(float(end["span_t"]), 1.0, 0.0, "closed final end is t=1")
	c.equal(end["section_id"], "lab.sampling.loop.west", "closed final end keeps incoming final section")

	var expected_order := [
		"lab.sampling.loop.north",
		"lab.sampling.loop.east",
		"lab.sampling.loop.south",
		"lab.sampling.loop.west",
	]
	var expected_surfaces := ["asphalt", "asphalt", "concrete", "asphalt"]
	for span_index in range(4):
		var span_record := table.span_table(span_index)
		c.equal(span_record["section_id"], expected_order[span_index], "span %d source order and stable id" % span_index)
		c.equal(span_record["surface_id"], expected_surfaces[span_index], "span %d surface id" % span_index)
		c.equal(int(span_record["span_index"]), span_index, "span %d index preserved" % span_index)
	c.equal(int(table.span_table(3)["start_knot_index"]), 3, "closing span starts at knot 3")
	c.equal(int(table.span_table(3)["end_knot_index"]), 0, "closing span wraps to knot 0")
	c.close(float(samples[4]["bank_deg"]), -8.0, 0.000000001, "bank at authored knot 2")
	c.close(float(samples[4]["width_m"]), 9.0, 0.000000001, "width at authored knot 2")

	c.measurements["closed_total_length_m"] = table.total_length_m
	c.measurements["closed_length_error_estimate_m"] = table.length_error_estimate_m
	c.measurements["closed_seam_position_delta_m"] = (start["position"] as Vector3).distance_to(end["position"])
	return c.result()


# --- Determinism, preservation and refusal cases ----------------------------


func _case_deterministic_repeats() -> Dictionary:
	var c := Case.new()
	c.name = "deterministic_repeats"
	var document := parse_fixture_document(c, OPEN_CURVE_PATH, "determinism curve")
	if document == null:
		return c.result()
	var first := build_table(c, document, 3.7, "first deterministic build")
	var second := build_table(c, document, 3.7, "second deterministic build")
	if first == null or second == null:
		return c.result()
	var first_text := canonical_table_text(first)
	var second_text := canonical_table_text(second)
	c.equal(first_text == second_text, true, "repeated builds serialize identically")
	c.equal(first.sample_count, second.sample_count, "repeat sample count identical")
	c.close(first.total_length_m, second.total_length_m, 0.0, "repeat total length exactly identical")
	c.measurements["canonical_repeat_byte_count"] = first_text.length()
	c.measurements["canonical_repeat_text_hash"] = hash(first_text)
	return c.result()


func _case_source_preservation_and_table_copies() -> Dictionary:
	var c := Case.new()
	c.name = "source_preservation_and_table_copies"
	var document := parse_fixture_document(c, OPEN_STRAIGHT_PATH, "preservation straight")
	if document == null:
		return c.result()
	var before := JSON.stringify(normalized_variant(document.summary()), "", false, true)
	var table := build_table(c, document, 15.0, "preservation build")
	if table == null:
		return c.result()
	var after := JSON.stringify(normalized_variant(document.summary()), "", false, true)
	c.equal(after, before, "building the table does not mutate the source summary")

	var copied_samples := table.samples
	c.check(not copied_samples.is_empty(), "sample copy is available")
	if not copied_samples.is_empty():
		(copied_samples[0] as Dictionary)["s"] = -999.0
		c.close(float(table.sample(0)["s"]), 0.0, 0.0, "mutating a copied sample cannot rewrite the table")
	var copied_spans := table.span_tables
	c.check(not copied_spans.is_empty(), "span copy is available")
	if not copied_spans.is_empty():
		(copied_spans[0] as Dictionary)["section_id"] = "mutated"
		c.equal(table.span_table(0)["section_id"], "lab.sampling.straight.a", "mutating a copied span cannot rewrite the table")
	return c.result()


func _case_malformed_and_derived_refusals() -> Dictionary:
	var c := Case.new()
	c.name = "malformed_and_derived_refusals"
	var document := parse_fixture_document(c, OPEN_STRAIGHT_PATH, "refusal straight")
	if document == null:
		return c.result()

	c.refuses(
		RoadArcSampler.build_uniform_table(null, 15.0),
		RoadArcSampler.Refusal.BAD_DOCUMENT,
		"null document"
	)
	for bad_spacing in [0.0, -1.0, NAN, INF, "15"]:
		c.refuses(
			RoadArcSampler.build_uniform_table(document, bad_spacing),
			RoadArcSampler.Refusal.BAD_SPACING,
			"bad spacing %s" % str(bad_spacing)
		)
	c.refuses(
		RoadArcSampler.build_uniform_table(document, 15.0, {"unknown": 1}),
		RoadArcSampler.Refusal.BAD_OPTIONS,
		"unknown option"
	)
	c.refuses(
		RoadArcSampler.build_uniform_table(
			document,
			15.0,
			{RoadArcSampler.OPTION_ARC_LENGTH_TOLERANCE_M: 0.01}
		),
		RoadArcSampler.Refusal.BAD_OPTIONS,
		"looser tolerance option is refused"
	)

	var cusp_source := make_single_span_source(
		"lab.sampling.control.cusp",
		[0.0, 0.0, 0.0],
		[10.0, 0.0, 0.0],
		[0.0, 0.0, 0.0],
		[10.0, 0.0, 0.0]
	)
	var cusp_document := parse_control_source(c, cusp_source, "cusp")
	if cusp_document != null:
		c.refuses(
			RoadArcSampler.build_uniform_table(cusp_document, 5.0),
			RoadArcSampler.Refusal.DEGENERATE_DERIVATIVE,
			"interior cusp derivative",
			"derivative"
		)

	var interior_zero_source := make_single_span_source(
		"lab.sampling.control.interior_zero",
		[0.0, 0.0, 0.0],
		[1.1111111111111112, 0.0, 0.0],
		[-1.1111111111111112, 0.0, 0.0],
		[3.3333333333333335, 0.0, 0.0]
	)
	var interior_zero_document := parse_control_source(c, interior_zero_source, "interior zero")
	if interior_zero_document != null:
		c.refuses(
			RoadArcSampler.build_uniform_table(interior_zero_document, 0.5),
			RoadArcSampler.Refusal.DEGENERATE_DERIVATIVE,
			"non-dyadic interior zero derivative",
			"derivative"
		)

	var overflow_source := make_single_span_source(
		"lab.sampling.control.overflow",
		[0.0, 0.0, 0.0],
		# Each control point fits Vector3; the derived subtraction overflows.
		[2.0e38, 0.0, -1.0],
		[-2.0e38, 0.0, -1.0],
		[0.0, 0.0, -2.0]
	)
	var overflow_document := parse_control_source(c, overflow_source, "overflow")
	if overflow_document != null:
		c.refuses(
			RoadArcSampler.build_uniform_table(overflow_document, 5.0),
			RoadArcSampler.Refusal.NONFINITE_DERIVED_STATE,
			"overflowing derived Bezier state"
		)
	return c.result()


func _case_budget_controls() -> Dictionary:
	var c := Case.new()
	c.name = "budget_controls"
	var straight := parse_fixture_document(c, OPEN_STRAIGHT_PATH, "budget straight")
	var curve := parse_fixture_document(c, OPEN_CURVE_PATH, "budget curve")
	if straight == null or curve == null:
		return c.result()

	c.refuses(
		RoadArcSampler.build_uniform_table(
			straight,
			15.0,
			{RoadArcSampler.OPTION_MAX_OUTPUT_SAMPLES: 4}
		),
		RoadArcSampler.Refusal.SAMPLE_CAP_EXCEEDED,
		"output sample cap"
	)
	c.refuses(
		RoadArcSampler.build_uniform_table(
			curve,
			5.0,
			{RoadArcSampler.OPTION_MAX_TABLE_NODES_PER_SPAN: 2}
		),
		RoadArcSampler.Refusal.TABLE_NODE_CAP_EXCEEDED,
		"table node cap"
	)
	c.refuses(
		RoadArcSampler.build_uniform_table(
			curve,
			5.0,
			{RoadArcSampler.OPTION_MAX_SUBDIVISION_DEPTH: 0}
		),
		RoadArcSampler.Refusal.SUBDIVISION_CAP_EXCEEDED,
		"subdivision depth cap"
	)
	c.refuses(
		RoadArcSampler.build_uniform_table(
			straight,
			15.0,
			{RoadArcSampler.OPTION_MAX_OUTPUT_SAMPLES: 4.5}
		),
		RoadArcSampler.Refusal.BAD_OPTIONS,
		"noninteger output cap"
	)
	c.refuses(
		RoadArcSampler.build_uniform_table(
			straight,
			15.0,
			{RoadArcSampler.OPTION_MAX_OUTPUT_SAMPLES: RoadArcSampler.DEFAULT_MAX_OUTPUT_SAMPLES + 1}
		),
		RoadArcSampler.Refusal.BAD_OPTIONS,
		"loosened output cap"
	)
	return c.result()


# --- Conservative bracket review regressions ---------------------------------


func _case_conservative_bracket_regressions() -> Dictionary:
	var c := Case.new()
	c.name = "conservative_bracket_regressions"
	_check_sol_quadratic_regression(c)
	_check_opus_counterexample_regression(
		c,
		"lab.sampling.control.opus_hook",
		"Opus hook",
		[
			[0.0, 0.0],
			[-41.51432074598111, -26.793159374705738],
			[-5.398951534001867, -15.298719443537351],
			[-12.430606748396634, -10.973956893541455],
		],
		5.0
	)
	_check_opus_counterexample_regression(
		c,
		"lab.sampling.control.opus_road1",
		"Opus road1",
		[
			[0.0, 0.0],
			[46.68122811764261, -30.631338526912597],
			[88.92034614456695, -19.57132160513956],
			[141.37228732321915, 0.0],
		],
		5.0
	)
	_check_global_station_collapse_regression(c)
	return c.result()


func _check_sol_quadratic_regression(c: Case) -> void:
	var source := make_single_span_source(
		"lab.sampling.control.sol_quadratic",
		[0.0, 0.0, 0.0],
		[1.0 / 3.0, -3.17 / 3.0, 0.0],
		[2.0 / 3.0, 5.0 / 3.0 - 6.34 / 3.0, 0.0],
		[1.0, 1.83, 0.0]
	)
	var document := parse_control_source(c, source, "Sol analytic quadratic")
	if document == null:
		return

	var table := build_table(c, document, 1.0, "Sol analytic quadratic at 1 m spacing")
	if table == null:
		return
	var float32_coverage := _check_length_error_covered(
		c,
		table,
		document.spans[0].control_points(),
		"Sol analytic quadratic float32 control points"
	)
	c.close(
		table.total_length_m,
		SOL_QUADRATIC_EXACT_LENGTH_M,
		RoadArcSampler.DEFAULT_ARC_LENGTH_TOLERANCE_M,
		"Sol analytic quadratic total length matches the exact arc length"
	)
	c.check(
		table.length_error_estimate_m <= RoadArcSampler.DEFAULT_ARC_LENGTH_TOLERANCE_M,
		"Sol analytic quadratic conservative error estimate stays inside the tolerance"
	)
	c.equal(table.sample_count, 5, "Sol analytic quadratic 1 m spacing sample count")
	var samples := table.samples
	c.close(
		float(samples[samples.size() - 1]["s"]),
		table.total_length_m,
		0.0,
		"Sol analytic quadratic last station is the exact end"
	)
	for sample in samples:
		var t := float(sample["span_t"])
		c.vector_close(
			sample["position"],
			sol_quadratic_position(t),
			0.00001,
			"Sol analytic quadratic sample position matches B(span_t)"
		)
		c.vector_close(
			sample["forward_tangent"],
			Vector3(1.0, 10.0 * t - 3.17, 0.0) / sol_quadratic_speed(t),
			0.000001,
			"Sol analytic quadratic forward tangent is analytic"
		)
		c.close(
			absf(sol_quadratic_length(t, ANALYTIC_INVERSE_PANELS) - float(sample["s"])),
			0.0,
			0.002,
			"Sol analytic quadratic station matches independent arc length at span_t"
		)
	for index in range(1, samples.size()):
		var station := float((samples[index] as Dictionary)["s"])
		var inverse_t := sol_quadratic_inverse_length(station, ANALYTIC_INVERSE_PANELS)
		c.vector_close(
			samples[index]["position"],
			sol_quadratic_position(inverse_t),
			0.005,
			"Sol analytic quadratic sample position matches independent inverse at station %d" % index
		)
	c.measurements["sol_quadratic_total_length_m"] = table.total_length_m
	c.measurements["sol_quadratic_absolute_difference_m"] = absf(
		table.total_length_m - SOL_QUADRATIC_EXACT_LENGTH_M
	)
	c.measurements["sol_quadratic_reported_error_m"] = table.length_error_estimate_m
	c.measurements["sol_quadratic_float32_reference_length_m"] = float(float32_coverage["reference"])
	c.measurements["sol_quadratic_float32_absolute_difference_m"] = float(float32_coverage["actual_error"])

	var near_table := build_table(c, document, 3.05, "Sol analytic quadratic near-end spacing")
	if near_table == null:
		return
	c.close(
		near_table.total_length_m,
		SOL_QUADRATIC_EXACT_LENGTH_M,
		RoadArcSampler.DEFAULT_ARC_LENGTH_TOLERANCE_M,
		"Sol analytic quadratic near-end spacing total length matches the exact arc length"
	)
	c.equal(near_table.sample_count, 3, "Sol analytic quadratic near-end spacing sample count")
	var near_samples := near_table.samples
	var near_last: Dictionary = near_samples[near_samples.size() - 1]
	c.close(float(near_last["s"]), near_table.total_length_m, 0.0, "near-end last station is exact")
	c.close(float(near_last["span_t"]), 1.0, 0.0, "near-end final sample is t=1")
	c.vector_close(
		near_last["position"],
		sol_quadratic_position(1.0),
		0.000000001,
		"near-end final position is exact"
	)
	c.measurements["sol_quadratic_near_end_total_length_m"] = near_table.total_length_m
	c.measurements["sol_quadratic_near_end_absolute_difference_m"] = absf(
		near_table.total_length_m - SOL_QUADRATIC_EXACT_LENGTH_M
	)


func _check_opus_counterexample_regression(
	c: Case,
	p_course_id: String,
	p_label: String,
	p_plan: Array,
	p_spacing: float
) -> void:
	var source := make_single_span_source(
		p_course_id,
		plan_point_to_array(p_plan[0]),
		plan_point_to_array(p_plan[1]),
		plan_point_to_array(p_plan[2]),
		plan_point_to_array(p_plan[3])
	)
	var document := parse_control_source(c, source, p_label)
	if document == null:
		return
	var control_points: Array[Vector3] = document.spans[0].control_points()
	var table := build_table(c, document, p_spacing, p_label + " builds")
	if table == null:
		return
	var coverage := _check_length_error_covered(c, table, control_points, p_label)
	var reference := float(coverage["reference"])
	c.close(
		table.total_length_m,
		reference,
		REVIEW_COUNTEREXAMPLE_TOLERANCE_M,
		p_label + " length agrees with the independent fine reference"
	)
	c.check(
		table.length_error_estimate_m <= RoadArcSampler.DEFAULT_ARC_LENGTH_TOLERANCE_M,
		p_label + " conservative error estimate stays inside the tolerance"
	)
	c.measurements[p_course_id + "_sampler_length_m"] = table.total_length_m
	c.measurements[p_course_id + "_reference_length_m"] = reference
	c.measurements[p_course_id + "_absolute_difference_m"] = absf(table.total_length_m - reference)
	c.measurements[p_course_id + "_reported_error_m"] = table.length_error_estimate_m


func _check_global_station_collapse_regression(c: Case) -> void:
	# The 2^53 m prefix puts the first span's endpoint chord near 9e15 m, so
	# its mandatory reported-error floor is about 9e3 m. At the default 1 mm
	# tolerance that span is refused as precision_unreachable before any local
	# integration, so this fixture no longer reaches the global-station advance
	# guard retained in build_uniform_table. A request above the floor could
	# still expose that guard, but the guard is deliberately not claimed here.
	var loaded := load_fixture(OPEN_STRAIGHT_PATH)
	c.check(bool(loaded["ok"]), "global-station prefix fixture loads: " + str(loaded["error"]))
	if not bool(loaded["ok"]):
		return
	var doc: Dictionary = loaded["doc"]
	var knots: Array = doc["knots"]
	var prefix := 9007199254740992.0
	knots[0]["handle_out"] = [prefix / 4.0, 0.0, 0.0]
	knots[1]["handle_in"] = [2.0 * prefix / 4.0, 0.0, 0.0]
	knots[1]["anchor"] = [prefix, 0.0, 0.0]
	knots[1]["handle_out"] = [prefix, 0.0, 0.0625]
	knots[2]["handle_in"] = [prefix, 0.0, 0.1875]
	knots[2]["anchor"] = [prefix, 0.0, 0.25]
	knots[2]["handle_out"] = [prefix, 0.0, 0.3125]
	var parsed := RoadSourceDocument.parse_document(doc)
	c.check(
		bool(parsed["ok"]),
		"global-station collapse source parses: " + str(parsed["error"])
	)
	if not bool(parsed["ok"]):
		return
	c.refuses(
		RoadArcSampler.build_uniform_table(parsed["document"], 1.0e16),
		RoadArcSampler.Refusal.PRECISION_UNREACHABLE,
		"positive span after a 2^53 m prefix is refused below its reported-error precision floor",
		"roundoff-implied precision floor"
	)


# --- Float64 translated-geometry regressions --------------------------------


func _case_translated_float64_regressions() -> Dictionary:
	var c := Case.new()
	c.name = "translated_float64_regressions"

	# Sol's exact diagonal counterexample: the old float32 vector norm path
	# accepted a 1.571 mm error while reporting only 0.977 mm, despite the
	# requested 1 mm tolerance. Its dyadic control components make the true
	# geometric length exactly 24576*sqrt(2) in real arithmetic.
	var diagonal_points := [
		[0.0, 0.0, 0.0],
		[8192.0, 0.0, 8192.0],
		[16384.0, 0.0, 16384.0],
		[24576.0, 0.0, 24576.0],
	]
	var diagonal_table := _build_single_span_table(
		c,
		"lab.sampling.control.sol_diagonal",
		"Sol exact diagonal straight",
		diagonal_points,
		65536.0
	)
	if diagonal_table != null:
		var exact_diagonal_length := 24576.0 * sqrt(2.0)
		var diagonal_error := absf(diagonal_table.total_length_m - exact_diagonal_length)
		c.equal(diagonal_table.sample_count, 2, "diagonal uses only endpoint samples")
		c.check(
			diagonal_error <= RoadArcSampler.DEFAULT_ARC_LENGTH_TOLERANCE_M,
			"diagonal actual error stays within the requested 1 mm tolerance"
		)
		c.check(
			diagonal_error <= diagonal_table.length_error_estimate_m,
			"diagonal reported error covers actual analytic error"
		)
		c.measurements["sol_diagonal_exact_length_m"] = exact_diagonal_length
		c.measurements["sol_diagonal_actual_error_m"] = diagonal_error
		c.measurements["sol_diagonal_reported_error_m"] = diagonal_table.length_error_estimate_m

	_check_non_dyadic_straight_regression(
		c,
		"lab.sampling.control.nondyadic_straight_a",
		"non-dyadic straight to (100.1,0,-0.3)",
		[100.1, 0.0, -0.3]
	)
	_check_non_dyadic_straight_regression(
		c,
		"lab.sampling.control.nondyadic_straight_b",
		"non-dyadic straight to (37.3,4.1,-61.7)",
		[37.3, 4.1, -61.7]
	)

	var road1 := [
		[0.0, 0.0],
		[46.68122811764261, -30.631338526912597],
		[88.92034614456695, -19.57132160513956],
		[141.37228732321915, 0.0],
	]
	var road2 := [
		[0.0, 0.0],
		[51.0, 18.45],
		[95.86, 28.36],
		[144.71, 0.0],
	]
	var hook := [
		[0.0, 0.0],
		[-41.51432074598111, -26.793159374705738],
		[-5.398951534001867, -15.298719443537351],
		[-12.430606748396634, -10.973956893541455],
	]
	_check_translated_plan_span_regression(
		c,
		"lab.sampling.control.translated_road1",
		"road1 translated 1.4 km",
		road1,
		[1000.0, 3.7, -1000.0]
	)
	_check_translated_plan_span_regression(
		c,
		"lab.sampling.control.translated_road2",
		"road2 translated 2.8 km",
		road2,
		[2000.0, 11.1, -2000.0]
	)
	_check_translated_plan_span_regression(
		c,
		"lab.sampling.control.translated_hook",
		"hook translated 5 km",
		hook,
		[4000.0, 18.5, -3000.0]
	)
	_check_seeded_normal_span_regressions(c)
	return c.result()


func _control_points_from_arrays(points: Array) -> Array[Vector3]:
	var control_points: Array[Vector3] = []
	for point in points:
		control_points.append(vector3_from_array(point))
	return control_points


func _record_single_span_measurements(
	c: Case,
	key: String,
	table: RoadArcSampler.Table,
	coverage: Dictionary
) -> void:
	c.measurements[key + "_sampler_length_m"] = table.total_length_m
	c.measurements[key + "_reference_length_m"] = float(coverage["reference"])
	c.measurements[key + "_absolute_difference_m"] = float(coverage["actual_error"])
	c.measurements[key + "_reported_error_m"] = float(coverage["reported"])
	c.measurements[key + "_reference_uncertainty_m"] = float(coverage["reference_uncertainty"])


func _check_non_dyadic_straight_regression(
	c: Case,
	course_id: String,
	label: String,
	displacement: Array
) -> void:
	var start := [0.0, 0.0, 0.0]
	var points := [
		start,
		[float(displacement[0]) / 3.0, float(displacement[1]) / 3.0, float(displacement[2]) / 3.0],
		[2.0 * float(displacement[0]) / 3.0, 2.0 * float(displacement[1]) / 3.0, 2.0 * float(displacement[2]) / 3.0],
		displacement,
	]
	var table := _build_single_span_table(c, course_id, label, points, 5.0)
	if table == null:
		return
	var coverage := _check_length_error_covered(
		c,
		table,
		_control_points_from_arrays(points),
		label
	)
	_record_single_span_measurements(c, course_id, table, coverage)


func _check_translated_plan_span_regression(
	c: Case,
	course_id: String,
	label: String,
	plan: Array,
	offset: Array
) -> void:
	var points := translated_plan_control_points(plan, offset)
	var table := _build_single_span_table(c, course_id, label, points, 5.0)
	if table == null:
		return
	var coverage := _check_length_error_covered(
		c,
		table,
		_control_points_from_arrays(points),
		label
	)
	_record_single_span_measurements(c, course_id, table, coverage)


func _check_seeded_normal_span_regressions(c: Case) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261128
	var accepted := 0
	var worst_actual_error := 0.0
	var worst_reported := 0.0
	var worst_uncertainty := 0.0
	var worst_error_minus_reported := -INF
	var worst_index := -1
	for index in range(SEEDED_ROAD_SPAN_COUNT):
		var chord := rng.randf_range(30.0, 200.0)
		var heading := rng.randf_range(-PI, PI)
		var out_angle := heading + rng.randf_range(-0.6, 0.6)
		var in_angle := heading - rng.randf_range(-0.6, 0.6)
		var out_length := chord * rng.randf_range(0.25, 0.4)
		var in_length := chord * rng.randf_range(0.25, 0.4)
		var grade := rng.randf_range(-0.08, 0.08)
		var start := [
			2000.0 + rng.randf_range(-30.0, 30.0),
			rng.randf_range(0.0, 20.0),
			-2000.0 + rng.randf_range(-30.0, 30.0),
		]
		var end := [
			float(start[0]) + chord * cos(heading),
			float(start[1]) + chord * grade,
			float(start[2]) - chord * sin(heading),
		]
		var p1 := [
			float(start[0]) + out_length * cos(out_angle),
			float(start[1]) + out_length * grade,
			float(start[2]) - out_length * sin(out_angle),
		]
		var p2 := [
			float(end[0]) - in_length * cos(in_angle),
			float(end[1]) - in_length * grade,
			float(end[2]) + in_length * sin(in_angle),
		]
		var points := [start, p1, p2, end]
		var label := "seeded normal road-like span %02d" % index
		var table := _build_single_span_table(
			c,
			"lab.sampling.control.seeded_%02d" % index,
			label,
			points,
			15.0
		)
		if table == null:
			continue
		accepted += 1
		var coverage := _check_length_error_covered(
			c,
			table,
			_control_points_from_arrays(points),
			label
		)
		var actual_error := float(coverage["actual_error"])
		if actual_error > worst_actual_error:
			worst_actual_error = actual_error
			worst_index = index
		worst_reported = maxf(worst_reported, float(coverage["reported"]))
		worst_uncertainty = maxf(worst_uncertainty, float(coverage["reference_uncertainty"]))
		worst_error_minus_reported = maxf(
			worst_error_minus_reported,
			actual_error - float(coverage["reported"])
		)
	c.equal(
		accepted,
		SEEDED_ROAD_SPAN_COUNT,
		"all seeded normal road-like spans are accepted at default options"
	)
	c.measurements["seeded_normal_span_count"] = SEEDED_ROAD_SPAN_COUNT
	c.measurements["seeded_normal_accepted_count"] = accepted
	c.measurements["seeded_normal_worst_actual_error_m"] = worst_actual_error
	c.measurements["seeded_normal_worst_reported_error_m"] = worst_reported
	c.measurements["seeded_normal_worst_reference_uncertainty_m"] = worst_uncertainty
	c.measurements["seeded_normal_worst_error_minus_reported_m"] = worst_error_minus_reported
	c.measurements["seeded_normal_worst_error_index"] = worst_index


# --- Tightened-tolerance reported-error contract ----------------------------

func _case_tightened_tolerance_precision_contract() -> Dictionary:
	var c := Case.new()
	c.name = "tightened_tolerance_precision_contract"

	# Analytic straight with dyadic control components: constant speed makes
	# the coarse and refined Simpson values agree at the nodes, so the geometric
	# bracket distance is tiny while the leaf roundoff allowance dominates the
	# reported error. This is exactly the gap Sol identified.
	var diagonal_points := [
		[0.0, 0.0, 0.0],
		[8192.0, 0.0, 8192.0],
		[16384.0, 0.0, 16384.0],
		[24576.0, 0.0, 24576.0],
	]
	var source := make_single_span_source(
		"lab.sampling.control.tight_diagonal",
		diagonal_points[0],
		diagonal_points[1],
		diagonal_points[2],
		diagonal_points[3]
	)
	var document := parse_control_source(c, source, "tight-tolerance diagonal")
	if document == null:
		return c.result()
	var control_points: Array[Vector3] = document.spans[0].control_points()
	var chord := scalar_chord_length(control_points)
	var allowance := float(RoadArcSampler.ARC_LENGTH_BOUND_RELATIVE_ROUNDOFF)
	var floor := allowance * chord
	var exact_length := 24576.0 * sqrt(2.0)

	# The request is above the tiny geometric bracket distance but below the
	# summed roundoff-implied reported-error floor. The old padded-distance-free
	# acceptance would accept it and report above the request.
	var below_floor := 1.0e-8
	c.check(
		below_floor < floor,
		"below-floor request is below the diagonal reported-error floor (floor %.9f)" % floor
	)
	var below := RoadArcSampler.build_uniform_table(
		document,
		65536.0,
		{RoadArcSampler.OPTION_ARC_LENGTH_TOLERANCE_M: below_floor}
	)
	c.refuses(
		below,
		RoadArcSampler.Refusal.PRECISION_UNREACHABLE,
		"tolerance below the reported-error floor is refused",
		"floor"
	)
	if typeof(below.get("diagnostic", null)) == TYPE_DICTIONARY:
		var below_diagnostic: Dictionary = below["diagnostic"]
		c.close(
			float(below_diagnostic.get("requested_tolerance_m", NAN)),
			below_floor,
			0.0,
			"precision refusal reports the requested tolerance"
		)
		c.close(
			float(below_diagnostic.get("precision_floor_m", NAN)),
			floor,
			floor * 1.0e-9,
			"precision refusal reports the derived floor"
		)
		c.close(
			float(below_diagnostic.get("endpoint_chord_m", NAN)),
			chord,
			0.0,
			"precision refusal reports the endpoint chord"
		)

	# Ordinary tight control just above the floor: accepted, and the reported
	# padded bound must satisfy the caller's request rather than merely the
	# geometric bracket distance.
	var just_above := 5.0e-8
	c.check(just_above > floor, "just-above-floor control is genuinely above the floor")
	var just_above_result := RoadArcSampler.build_uniform_table(
		document,
		65536.0,
		{RoadArcSampler.OPTION_ARC_LENGTH_TOLERANCE_M: just_above}
	)
	var just_above_table := c.accepts_table(
		just_above_result, "tolerance just above the floor builds"
	)
	if just_above_table != null:
		c.check(
			just_above_table.length_error_estimate_m <= just_above,
			"just-above-floor reported padded error satisfies the requested budget "
				+ "(%.9f <= %.9f)" % [just_above_table.length_error_estimate_m, just_above]
		)
		c.close(
			just_above_table.total_length_m,
			exact_length,
			just_above,
			"just-above-floor tight length stays within the requested analytic error"
		)
		c.measurements["tight_diagonal_just_above_requested_tolerance_m"] = just_above
		c.measurements["tight_diagonal_just_above_reported_error_m"] = (
			just_above_table.length_error_estimate_m
		)

	# A second ordinary tight control well above the floor exercises the same
	# padded acceptance on an unambiguously achievable budget.
	var tight := 1.0e-6
	var tight_result := RoadArcSampler.build_uniform_table(
		document,
		65536.0,
		{RoadArcSampler.OPTION_ARC_LENGTH_TOLERANCE_M: tight}
	)
	var tight_table := c.accepts_table(tight_result, "tight tolerance well above the floor builds")
	if tight_table != null:
		c.check(
			tight_table.length_error_estimate_m <= tight,
			"tight tolerance reported padded error satisfies the requested budget "
				+ "(%.9f <= %.9f)" % [tight_table.length_error_estimate_m, tight]
		)
		c.close(
			tight_table.total_length_m,
			exact_length,
			tight,
			"tight tolerance length stays within the requested analytic error"
		)
		c.measurements["tight_diagonal_requested_tolerance_m"] = tight
		c.measurements["tight_diagonal_reported_error_m"] = tight_table.length_error_estimate_m

	c.measurements["tight_diagonal_endpoint_chord_m"] = chord
	c.measurements["tight_diagonal_precision_floor_m"] = floor
	c.measurements["tight_diagonal_below_floor_refused"] = not bool(below.get("ok", false))
	return c.result()
