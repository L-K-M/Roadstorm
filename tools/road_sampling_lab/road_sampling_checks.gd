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
const CURVED_LENGTH_AGREEMENT_TOLERANCE_M := 0.005


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


static func independent_bezier_derivative(points: Array[Vector3], t: float) -> Vector3:
	var u := 1.0 - t
	return (
		(points[1] - points[0]) * (3.0 * u * u)
		+ (points[2] - points[1]) * (6.0 * u * t)
		+ (points[3] - points[2]) * (3.0 * t * t)
	)


## Independent length reference: plain fixed midpoint quadrature, not the
## sampler's adaptive Simpson or inversion implementation.
static func independent_midpoint_length(points: Array[Vector3], panels: int) -> float:
	var sum := 0.0
	for panel in range(panels):
		var t := (float(panel) + 0.5) / float(panels)
		sum += independent_bezier_derivative(points, t).length()
	return sum / float(panels)


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
