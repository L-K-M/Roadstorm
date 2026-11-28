class_name RoadFrameLabChecks
extends RefCounted
## Focused checks for the bounded open-course RoadTransportFrame slice. The
## fixtures are original lab data. These checks exercise transported frames
## only; they do not bake geometry, validate course quality, or claim M2.1
## acceptance.

const RoadSourceDocument := preload("res://src/course/road_source.gd")
const RoadArcSampler := preload("res://src/course/road_arc_sampler.gd")
const RoadTransportFrame := preload("res://src/course/road_transport_frame.gd")

const FIXTURE_DIR := "res://tools/road_frame_lab/fixtures"
const OPEN_STRAIGHT_PATH := FIXTURE_DIR + "/road_frame_open_straight.json"
const OPEN_BANKED_BEND_PATH := FIXTURE_DIR + "/road_frame_open_banked_bend.json"
const OPEN_RAPID_GRADE_PATH := FIXTURE_DIR + "/road_frame_open_rapid_grade.json"
const CLOSED_LOOP_PATH := FIXTURE_DIR + "/road_frame_closed_loop.json"

const FRAME_UNIT_TOLERANCE := 0.00002
const FRAME_DOT_TOLERANCE := 0.00002
const EXACT_STRAIGHT_TOLERANCE := 0.000001
const BANK_EFFECT_TOLERANCE := 0.0002


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

	func accepts_arc_table(result: Dictionary, message: String) -> RoadArcSampler.Table:
		checks += 1
		if not bool(result.get("ok", false)):
			failures.append(
				"%s: expected arc-table acceptance, got %s (%s)" % [
					message,
					str(result.get("code_name", "missing_code")),
					str(result.get("error", "missing error")),
				]
			)
			return null
		checks += 1
		if result.get("table", null) == null:
			failures.append(message + ": arc-table acceptance returned no table")
			return null
		return result["table"]

	func accepts_frame_table(result: Dictionary, message: String) -> RoadTransportFrame.FrameTable:
		checks += 1
		if not bool(result.get("ok", false)):
			failures.append(
				"%s: expected frame acceptance, got %s (%s)" % [
					message,
					str(result.get("code_name", "missing_code")),
					str(result.get("error", "missing error")),
				]
			)
			return null
		checks += 1
		if result.get("frame_table", null) == null:
			failures.append(message + ": frame acceptance returned no frame table")
			return null
		return result["frame_table"]

	func refuses_frame(
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
		if result.get("frame_table", null) != null:
			failures.append(message + ": refusal returned a partial frame table")
		checks += 1
		if str(result.get("error", "")).strip_edges().is_empty():
			failures.append(message + ": refusal carried no readable diagnostic")
		checks += 1
		if typeof(result.get("diagnostic", null)) != TYPE_DICTIONARY:
			failures.append(message + ": refusal carried no structured diagnostic dictionary")
		checks += 1
		if int(result.get("code", -1)) != expected_code:
			failures.append(
				"%s: expected code %s, got %s (%s)" % [
					message,
					RoadTransportFrame.refusal_name(expected_code),
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
		Callable(self, "_case_open_straight_zero_bank_basis"),
		Callable(self, "_case_graded_banked_bend_transport_and_bank"),
		Callable(self, "_case_bank_returns_to_authored_zero"),
		Callable(self, "_case_near_vertical_rapid_grade_transport"),
		Callable(self, "_case_deterministic_repeat_and_copy_safety"),
		Callable(self, "_case_malformed_input_refusals"),
		Callable(self, "_case_closed_loop_explicit_refusal"),
	]:
		var result: Dictionary = call.call()
		case_results.append(result)
		cases_run += 1
		total_checks += int(result["checks"])
		total_failures += int(result["checks_failed"])
		print(
			"ROAD_FRAME_LAB_CASE ",
			JSON.stringify({
				"case": result["case"],
				"checks": result["checks"],
				"checks_failed": result["checks_failed"],
				"pass": result["pass"],
			})
		)
	return {
		"schema": "roadstorm.road_frame_lab.summary.v1",
		"pass": total_failures == 0,
		"cases": cases_run,
		"cases_passed": cases_run - _failed_case_count(),
		"checks": total_checks,
		"checks_failed": total_failures,
		"fixtures": [
			OPEN_STRAIGHT_PATH,
			OPEN_BANKED_BEND_PATH,
			OPEN_RAPID_GRADE_PATH,
			CLOSED_LOOP_PATH,
		],
		"case_results": case_results.duplicate(),
	}


func _failed_case_count() -> int:
	var failed := 0
	for result in case_results:
		if not bool(result["pass"]):
			failed += 1
	return failed


# --- Fixture, construction and serialization helpers -------------------------


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
	return parse_control_source(c, loaded["doc"], label)


static func parse_control_source(c: Case, source: Dictionary, label: String) -> RoadSourceDocument:
	var parsed := RoadSourceDocument.parse_document(source)
	c.check(bool(parsed["ok"]), label + " source parses: " + str(parsed["error"]))
	if not bool(parsed["ok"]):
		return null
	return parsed["document"]


static func build_arc_table(
	c: Case,
	document: RoadSourceDocument,
	spacing: float,
	label: String
) -> RoadArcSampler.Table:
	return c.accepts_arc_table(
		RoadArcSampler.build_uniform_table(document, spacing),
		label
	)


static func build_frame_table(
	c: Case,
	arc_table: RoadArcSampler.Table,
	label: String
) -> RoadTransportFrame.FrameTable:
	return c.accepts_frame_table(
		RoadTransportFrame.build_open_frame_table(arc_table),
		label
	)


static func build_fixture_frames(
	c: Case,
	path: String,
	spacing: float,
	label: String
) -> Dictionary:
	var document := parse_fixture_document(c, path, label)
	if document == null:
		return {"arc_table": null, "frame_table": null}
	var arc_table := build_arc_table(c, document, spacing, label + " arc table builds")
	if arc_table == null:
		return {"arc_table": null, "frame_table": null}
	var frame_table := build_frame_table(c, arc_table, label + " frame table builds")
	return {"arc_table": arc_table, "frame_table": frame_table}


static func zero_bank_source_copy(source: Dictionary) -> Dictionary:
	var out := source.duplicate(true)
	for knot in out["knots"]:
		(knot as Dictionary)["bank_deg"] = 0.0
	return out


static func make_bank_pulse_source() -> Dictionary:
	return {
		"schema": RoadSourceDocument.SCHEMA,
		"course_id": "lab.frame.control.bank_pulse",
		"revision": "0.1.0",
		"closed": false,
		"knots": [
			{
				"anchor": [0.0, 0.0, 0.0],
				"handle_in": [0.0, 0.0, 10.0],
				"handle_out": [0.0, 0.0, -10.0],
				"width_m": 10.0,
				"bank_deg": 0.0,
			},
			{
				"anchor": [0.0, 0.0, -30.0],
				"handle_in": [0.0, 0.0, -20.0],
				"handle_out": [0.0, 0.0, -40.0],
				"width_m": 10.0,
				"bank_deg": 12.0,
			},
			{
				"anchor": [0.0, 0.0, -60.0],
				"handle_in": [0.0, 0.0, -50.0],
				"handle_out": [0.0, 0.0, -70.0],
				"width_m": 10.0,
				"bank_deg": 0.0,
			},
		],
		"sections": [
			{"section_id": "lab.frame.bank_pulse.in", "surface_id": "asphalt"},
			{"section_id": "lab.frame.bank_pulse.out", "surface_id": "asphalt"},
		],
	}


static func normalized_variant(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR3:
			var vector: Vector3 = value
			return ["Vector3", vector.x, vector.y, vector.z]
		TYPE_BASIS:
			var basis: Basis = value
			return [
				"Basis",
				normalized_variant(basis.x),
				normalized_variant(basis.y),
				normalized_variant(basis.z),
			]
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


static func canonical_frame_text(table: RoadTransportFrame.FrameTable) -> String:
	return JSON.stringify(normalized_variant(table.to_dictionary()), "", false, true)


static func replace_samples(table: RoadArcSampler.Table, samples: Array) -> RoadArcSampler.Table:
	table.set("_samples", samples)
	return table


static func fresh_straight_arc_table(c: Case, label: String) -> RoadArcSampler.Table:
	var document := parse_fixture_document(c, OPEN_STRAIGHT_PATH, label)
	if document == null:
		return null
	return build_arc_table(c, document, 5.0, label + " arc table builds")


# --- Shared frame assertions ---------------------------------------------------


static func check_unit_orthogonal_frames(
	c: Case,
	frames: Array,
	label: String
) -> void:
	for index in range(frames.size()):
		var frame: Dictionary = frames[index]
		var forward: Vector3 = frame["forward"]
		var right: Vector3 = frame["right"]
		var up: Vector3 = frame["up"]
		c.close(forward.length(), 1.0, FRAME_UNIT_TOLERANCE, label + " forward unit at frame %d" % index)
		c.close(right.length(), 1.0, FRAME_UNIT_TOLERANCE, label + " right unit at frame %d" % index)
		c.close(up.length(), 1.0, FRAME_UNIT_TOLERANCE, label + " up unit at frame %d" % index)
		c.close(forward.dot(right), 0.0, FRAME_DOT_TOLERANCE, label + " forward/right orthogonal at frame %d" % index)
		c.close(forward.dot(up), 0.0, FRAME_DOT_TOLERANCE, label + " forward/up orthogonal at frame %d" % index)
		c.close(right.dot(up), 0.0, FRAME_DOT_TOLERANCE, label + " right/up orthogonal at frame %d" % index)
		c.vector_close(
			right.cross(forward),
			up,
			FRAME_DOT_TOLERANCE,
			label + " right-handed up relation at frame %d" % index
		)
		c.vector_close(
			forward.cross(up),
			right,
			FRAME_DOT_TOLERANCE,
			label + " right-handed right relation at frame %d" % index
		)
		var basis: Basis = frame["basis"]
		c.close(
			basis.determinant(),
			1.0,
			FRAME_DOT_TOLERANCE,
			label + " basis determinant +1 at frame %d" % index
		)


static func check_frame_input_preservation(
	c: Case,
	arc_table: RoadArcSampler.Table,
	frame_table: RoadTransportFrame.FrameTable,
	label: String
) -> void:
	var samples := arc_table.samples
	var frames := frame_table.frames
	c.equal(frames.size(), samples.size(), label + " frame count matches sample count")
	var count: int = mini(samples.size(), frames.size())
	for index in range(count):
		var sample: Dictionary = samples[index]
		var frame: Dictionary = frames[index]
		c.close(float(frame["s"]), float(sample["s"]), 0.0, label + " station preserved at frame %d" % index)
		c.equal(frame["section_id"], sample["section_id"], label + " section id preserved at frame %d" % index)
		c.equal(frame["surface_id"], sample["surface_id"], label + " surface id preserved at frame %d" % index)
		c.close(float(frame["width_m"]), float(sample["width_m"]), 0.0, label + " width preserved at frame %d" % index)
		c.close(float(frame["bank_deg"]), float(sample["bank_deg"]), 0.0, label + " bank preserved at frame %d" % index)
		c.close(float(frame["grade_dy_ds"]), float(sample["grade_dy_ds"]), 0.0, label + " grade preserved at frame %d" % index)
		c.equal(int(frame["span_index"]), int(sample["span_index"]), label + " span index preserved at frame %d" % index)
		c.close(float(frame["span_t"]), float(sample["span_t"]), 0.0, label + " span parameter preserved at frame %d" % index)
		c.equal(frame["sample_role"], sample["sample_role"], label + " sample role preserved at frame %d" % index)
		c.vector_close(frame["position"], sample["position"], 0.0, label + " position preserved at frame %d" % index)


static func check_no_consecutive_sign_flip(
	c: Case,
	frames: Array,
	label: String
) -> void:
	for index in range(1, frames.size()):
		var previous: Dictionary = frames[index - 1]
		var current: Dictionary = frames[index]
		c.check(
			(previous["right"] as Vector3).dot(current["right"]) > 0.0,
			label + " right vector has no sign flip at frame %d" % index
		)
		c.check(
			(previous["up"] as Vector3).dot(current["up"]) > 0.0,
			label + " up vector has no sign flip at frame %d" % index
		)


# --- Positive cases -------------------------------------------------------------


func _case_open_straight_zero_bank_basis() -> Dictionary:
	var c := Case.new()
	c.name = "open_straight_zero_bank_basis"
	var built := build_fixture_frames(c, OPEN_STRAIGHT_PATH, 5.0, "straight")
	var arc_table: RoadArcSampler.Table = built["arc_table"]
	var frame_table: RoadTransportFrame.FrameTable = built["frame_table"]
	if arc_table == null or frame_table == null:
		return c.result()

	c.close(arc_table.total_length_m, 40.0, 0.000001, "straight analytic length")
	c.equal(frame_table.frame_count, 9, "straight exact spacing frame count")
	c.equal(frame_table.schema, RoadTransportFrame.RESULT_SCHEMA, "frame table schema")
	c.check(
		frame_table.positive_bank_policy.contains("tilts up toward road right"),
		"positive-bank sign is explicitly documented"
	)
	c.check(
		frame_table.orientation_policy.contains("right.cross(forward)=up"),
		"right-handed orientation is explicitly documented"
	)
	var frames := frame_table.frames
	for index in range(frames.size()):
		var frame: Dictionary = frames[index]
		c.vector_close(frame["forward"], Vector3(0.0, 0.0, -1.0), EXACT_STRAIGHT_TOLERANCE, "straight forward at frame %d" % index)
		c.vector_close(frame["right"], Vector3.RIGHT, EXACT_STRAIGHT_TOLERANCE, "straight zero-bank right at frame %d" % index)
		c.vector_close(frame["up"], Vector3.UP, EXACT_STRAIGHT_TOLERANCE, "straight zero-bank up at frame %d" % index)
	check_unit_orthogonal_frames(c, frames, "straight")
	check_frame_input_preservation(c, arc_table, frame_table, "straight")
	c.measurements["straight_total_length_m"] = arc_table.total_length_m
	c.measurements["straight_frame_count"] = frame_table.frame_count
	return c.result()


func _case_graded_banked_bend_transport_and_bank() -> Dictionary:
	var c := Case.new()
	c.name = "graded_banked_bend_transport_and_bank"
	var loaded := load_fixture(OPEN_BANKED_BEND_PATH)
	c.check(bool(loaded["ok"]), "banked bend fixture loads: " + str(loaded["error"]))
	if not bool(loaded["ok"]):
		return c.result()
	var document := parse_control_source(c, loaded["doc"], "banked bend")
	if document == null:
		return c.result()
	var arc_table := build_arc_table(c, document, 2.5, "banked bend arc table builds")
	if arc_table == null:
		return c.result()
	var frame_table := build_frame_table(c, arc_table, "banked bend frame table builds")
	if frame_table == null:
		return c.result()

	var zero_document := parse_control_source(c, zero_bank_source_copy(loaded["doc"]), "zero-bank bend control")
	if zero_document == null:
		return c.result()
	var zero_arc := build_arc_table(c, zero_document, 2.5, "zero-bank bend arc table builds")
	if zero_arc == null:
		return c.result()
	var zero_frames_table := build_frame_table(c, zero_arc, "zero-bank bend frame table builds")
	if zero_frames_table == null:
		return c.result()

	var frames := frame_table.frames
	var zero_frames := zero_frames_table.frames
	c.equal(frames.size(), zero_frames.size(), "banked and zero-bank control frame counts match")
	check_unit_orthogonal_frames(c, frames, "banked bend")
	check_no_consecutive_sign_flip(c, frames, "banked bend")
	check_frame_input_preservation(c, arc_table, frame_table, "banked bend")

	var count: int = mini(frames.size(), zero_frames.size())
	var measured_bank_effect := 0
	for index in range(count):
		var frame: Dictionary = frames[index]
		var zero_frame: Dictionary = zero_frames[index]
		var bank_rad := deg_to_rad(float(frame["bank_deg"]))
		var sine := sin(bank_rad)
		var cosine := cos(bank_rad)
		var right: Vector3 = frame["right"]
		var up: Vector3 = frame["up"]
		var zero_right: Vector3 = zero_frame["right"]
		var zero_up: Vector3 = zero_frame["up"]
		c.close(up.dot(zero_right), sine, BANK_EFFECT_TOLERANCE, "positive bank tilts up toward right at frame %d" % index)
		c.close(up.dot(zero_up), cosine, BANK_EFFECT_TOLERANCE, "banked up keeps cosine component at frame %d" % index)
		c.close(right.dot(zero_up), -sine, BANK_EFFECT_TOLERANCE, "positive bank lowers right edge at frame %d" % index)
		c.close(right.dot(zero_right), cosine, BANK_EFFECT_TOLERANCE, "banked right keeps cosine component at frame %d" % index)
		if absf(float(frame["bank_deg"])) > 5.0:
			measured_bank_effect += 1
	c.check(measured_bank_effect > 0, "at least one strongly banked bend sample measured")
	var first: Dictionary = frames[0]
	var last: Dictionary = frames[frames.size() - 1]
	c.check(float(first["bank_deg"]) < 0.0, "bend starts with negative authored bank")
	c.check(float(last["bank_deg"]) > 5.0, "bend ends with positive authored bank")
	c.check(
		(last["up"] as Vector3).dot((zero_frames[zero_frames.size() - 1] as Dictionary)["right"]) > 0.0,
		"positive end bank tilts up toward local right"
	)
	c.measurements["bend_frame_count"] = frame_table.frame_count
	c.measurements["bend_max_bank_deg"] = float(last["bank_deg"])
	c.measurements["bend_max_grade"] = arc_table.samples[arc_table.samples.size() - 1]["grade_dy_ds"]
	return c.result()


func _case_bank_returns_to_authored_zero() -> Dictionary:
	var c := Case.new()
	c.name = "bank_returns_to_authored_zero"
	var document := parse_control_source(c, make_bank_pulse_source(), "bank pulse")
	if document == null:
		return c.result()
	var arc_table := build_arc_table(c, document, 5.0, "bank pulse arc table builds")
	if arc_table == null:
		return c.result()
	var frame_table := build_frame_table(c, arc_table, "bank pulse frame table builds")
	if frame_table == null:
		return c.result()
	var frames := frame_table.frames
	var middle: Dictionary = frames[6]
	var end: Dictionary = frames[frames.size() - 1]
	c.close(float(middle["s"]), 30.0, 0.000001, "bank pulse middle station is the authored knot")
	c.close(float(middle["bank_deg"]), 12.0, 0.000001, "bank pulse middle bank is +12 degrees")
	c.check(absf((middle["up"] as Vector3).dot(Vector3.RIGHT)) > 0.1, "bank pulse middle up tilts toward +X")
	c.close(float(end["bank_deg"]), 0.0, 0.0, "bank pulse end authored bank returns to zero")
	c.vector_close(end["forward"], Vector3(0.0, 0.0, -1.0), EXACT_STRAIGHT_TOLERANCE, "bank pulse end forward")
	c.vector_close(end["right"], Vector3.RIGHT, EXACT_STRAIGHT_TOLERANCE, "bank pulse end right is not cumulatively rolled")
	c.vector_close(end["up"], Vector3.UP, EXACT_STRAIGHT_TOLERANCE, "bank pulse end up is not cumulatively rolled")
	check_unit_orthogonal_frames(c, frames, "bank pulse")
	c.measurements["bank_pulse_middle_up_dot_right"] = (middle["up"] as Vector3).dot(Vector3.RIGHT)
	return c.result()


func _case_near_vertical_rapid_grade_transport() -> Dictionary:
	var c := Case.new()
	c.name = "near_vertical_rapid_grade_transport"
	var built := build_fixture_frames(c, OPEN_RAPID_GRADE_PATH, 0.2, "rapid grade")
	var arc_table: RoadArcSampler.Table = built["arc_table"]
	var frame_table: RoadTransportFrame.FrameTable = built["frame_table"]
	if arc_table == null or frame_table == null:
		return c.result()
	var frames := frame_table.frames
	check_unit_orthogonal_frames(c, frames, "rapid grade")
	check_no_consecutive_sign_flip(c, frames, "rapid grade")
	var max_grade := -INF
	var max_grade_index := -1
	for index in range(frames.size()):
		var frame: Dictionary = frames[index]
		max_grade = maxf(max_grade, float(frame["grade_dy_ds"]))
		if float(frame["grade_dy_ds"]) == max_grade:
			max_grade_index = index
		c.check((frame["right"] as Vector3).x > 0.99, "rapid grade right stays +X at frame %d" % index)
		c.vector_close(frame["right"], Vector3.RIGHT, 0.0001, "rapid grade transported right has no vertical-reference flip at frame %d" % index)
	c.check(max_grade > 0.98, "control reaches a near-vertical rapid grade")
	c.check(max_grade_index > 0, "maximum rapid grade occurs after the seed station")
	check_frame_input_preservation(c, arc_table, frame_table, "rapid grade")
	c.measurements["rapid_grade_max_dy_ds"] = max_grade
	c.measurements["rapid_grade_max_index"] = max_grade_index
	c.measurements["rapid_grade_frame_count"] = frame_table.frame_count
	return c.result()


# --- Determinism, copy safety and refusal cases ---------------------------------


func _case_deterministic_repeat_and_copy_safety() -> Dictionary:
	var c := Case.new()
	c.name = "deterministic_repeat_and_copy_safety"
	var document := parse_fixture_document(c, OPEN_BANKED_BEND_PATH, "determinism bend")
	if document == null:
		return c.result()
	var first_arc := build_arc_table(c, document, 3.1, "first determinism arc table")
	var second_arc := build_arc_table(c, document, 3.1, "second determinism arc table")
	if first_arc == null or second_arc == null:
		return c.result()
	var first := build_frame_table(c, first_arc, "first deterministic frame build")
	var second := build_frame_table(c, second_arc, "second deterministic frame build")
	if first == null or second == null:
		return c.result()
	var first_text := canonical_frame_text(first)
	var second_text := canonical_frame_text(second)
	c.equal(first_text == second_text, true, "repeated frame builds serialize identically")
	c.equal(first.frame_count, second.frame_count, "repeat frame count identical")
	c.close(first.total_length_m, second.total_length_m, 0.0, "repeat total length exactly identical")

	var copied_frames := first.frames
	c.check(not copied_frames.is_empty(), "frame copy is available")
	if not copied_frames.is_empty():
		# Capture the stored value before touching the copy. This bend starts with
		# authored bank and grade, so its right vector is legitimately not
		# Vector3.RIGHT; comparing against a world-axis constant would assert the
		# wrong thing. The copy-safety point is that the stored vector is
		# unchanged by the mutation.
		var stored_right: Vector3 = first.frame(0)["right"]
		(copied_frames[0] as Dictionary)["s"] = -999.0
		(copied_frames[0] as Dictionary)["right"] = Vector3.ZERO
		c.close(float(first.frame(0)["s"]), 0.0, 0.0, "mutating copied frames cannot rewrite the stored table")
		c.vector_close(first.frame(0)["right"], stored_right, 0.0001, "mutating a copied frame vector cannot rewrite the stored frame")
	var copied_summary := first.source_summary
	copied_summary["course_id"] = "mutated"
	c.equal(first.source_summary["course_id"], "lab.frame.open_banked_bend", "mutating copied source summary cannot rewrite the stored table")

	var mutated_samples := first_arc.samples
	(mutated_samples[0] as Dictionary)["width_m"] = 777.0
	replace_samples(first_arc, mutated_samples)
	c.close(float(first.frame(0)["width_m"]), 11.0, 0.0, "later input-table mutation cannot rewrite the completed frame result")
	c.measurements["canonical_repeat_byte_count"] = first_text.length()
	c.measurements["canonical_repeat_text_hash"] = hash(first_text)
	return c.result()


func _case_malformed_input_refusals() -> Dictionary:
	var c := Case.new()
	c.name = "malformed_input_refusals"
	c.refuses_frame(
		RoadTransportFrame.build_open_frame_table(null),
		RoadTransportFrame.Refusal.BAD_TABLE,
		"null input"
	)
	c.refuses_frame(
		RoadTransportFrame.build_open_frame_table(RefCounted.new()),
		RoadTransportFrame.Refusal.BAD_TABLE,
		"wrong object input"
	)

	var nonmonotonic := fresh_straight_arc_table(c, "nonmonotonic control")
	if nonmonotonic != null:
		var samples := nonmonotonic.samples
		(samples[1] as Dictionary)["s"] = float((samples[0] as Dictionary)["s"])
		c.refuses_frame(
			RoadTransportFrame.build_open_frame_table(replace_samples(nonmonotonic, samples)),
			RoadTransportFrame.Refusal.NONMONOTONIC_STATIONS,
			"nonmonotonic station table",
			"strictly increasing"
		)

	var missing_key := fresh_straight_arc_table(c, "missing key control")
	if missing_key != null:
		var samples := missing_key.samples
		(samples[0] as Dictionary).erase("surface_id")
		c.refuses_frame(
			RoadTransportFrame.build_open_frame_table(replace_samples(missing_key, samples)),
			RoadTransportFrame.Refusal.BAD_SAMPLE,
			"missing required sample key"
		)

	var zero_tangent := fresh_straight_arc_table(c, "zero tangent control")
	if zero_tangent != null:
		var samples := zero_tangent.samples
		(samples[1] as Dictionary)["forward_tangent"] = Vector3.ZERO
		(samples[1] as Dictionary)["grade_dy_ds"] = 0.0
		c.refuses_frame(
			RoadTransportFrame.build_open_frame_table(replace_samples(zero_tangent, samples)),
			RoadTransportFrame.Refusal.DEGENERATE_TANGENT,
			"zero-length tangent"
		)

	var reversing := fresh_straight_arc_table(c, "reversing tangent control")
	if reversing != null:
		var samples := reversing.samples
		var prior_forward: Vector3 = (samples[0] as Dictionary)["forward_tangent"]
		(samples[1] as Dictionary)["forward_tangent"] = -prior_forward
		(samples[1] as Dictionary)["grade_dy_ds"] = (-prior_forward).y
		c.refuses_frame(
			RoadTransportFrame.build_open_frame_table(replace_samples(reversing, samples)),
			RoadTransportFrame.Refusal.REVERSING_TANGENT,
			"exact reversing tangent",
			"reverse"
		)

	var nonfinite_tangent := fresh_straight_arc_table(c, "nonfinite tangent control")
	if nonfinite_tangent != null:
		var samples := nonfinite_tangent.samples
		(samples[1] as Dictionary)["forward_tangent"] = Vector3(NAN, 0.0, -1.0)
		c.refuses_frame(
			RoadTransportFrame.build_open_frame_table(replace_samples(nonfinite_tangent, samples)),
			RoadTransportFrame.Refusal.NONFINITE_DERIVED_STATE,
			"nonfinite tangent input"
		)

	var bad_width := fresh_straight_arc_table(c, "bad width control")
	if bad_width != null:
		var samples := bad_width.samples
		(samples[1] as Dictionary)["width_m"] = NAN
		c.refuses_frame(
			RoadTransportFrame.build_open_frame_table(replace_samples(bad_width, samples)),
			RoadTransportFrame.Refusal.NONFINITE_DERIVED_STATE,
			"nonfinite width input"
		)

	var inconsistent_grade := fresh_straight_arc_table(c, "inconsistent grade control")
	if inconsistent_grade != null:
		var samples := inconsistent_grade.samples
		(samples[1] as Dictionary)["grade_dy_ds"] = 0.5
		c.refuses_frame(
			RoadTransportFrame.build_open_frame_table(replace_samples(inconsistent_grade, samples)),
			RoadTransportFrame.Refusal.TABLE_INCONSISTENT,
			"grade inconsistent with tangent"
		)
	return c.result()


func _case_closed_loop_explicit_refusal() -> Dictionary:
	var c := Case.new()
	c.name = "closed_loop_explicit_refusal"
	var document := parse_fixture_document(c, CLOSED_LOOP_PATH, "closed loop")
	if document == null:
		return c.result()
	var arc_table := build_arc_table(c, document, 8.0, "closed loop arc table builds")
	if arc_table == null:
		return c.result()
	c.check(arc_table.closed, "closed loop control really is closed")
	var result := RoadTransportFrame.build_open_frame_table(arc_table)
	c.refuses_frame(
		result,
		RoadTransportFrame.Refusal.CLOSED_LOOP_UNSUPPORTED,
		"closed loop explicit refusal",
		"residual-roll closure"
	)
	c.equal(str(result.get("code_name", "")), "closed_loop_unsupported", "closed refusal stable code name")
	c.equal(bool((result.get("diagnostic", {}) as Dictionary).get("closed", false)), true, "closed refusal diagnostic marks closed input")
	c.check(
		str((result.get("diagnostic", {}) as Dictionary).get("closed_loop_policy", "")).contains("later separate slice"),
		"closed refusal diagnostic names the later closure slice"
	)
	return c.result()
