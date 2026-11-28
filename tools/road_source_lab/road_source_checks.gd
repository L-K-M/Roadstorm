class_name RoadSourceLabChecks
extends RefCounted
## Discriminatory checks for the `roadstorm.road_source.v1` authored road-source
## contract. These checks parse the lab's two original tiny fixtures and mutated
## copies of them through `RoadSourceDocument`. They run no physics, drive no
## car, sample no geometry and produce no course artifact, so they make no M2.1
## or milestone acceptance claim.

const FIXTURE_DIR := "res://tools/road_source_lab/fixtures"
const OPEN_FIXTURE_PATH := FIXTURE_DIR + "/road_source_open_tiny.json"
const CLOSED_FIXTURE_PATH := FIXTURE_DIR + "/road_source_closed_tiny.json"

const OPEN_COURSE_ID := "lab.open_tiny"
const CLOSED_COURSE_ID := "lab.closed_tiny"
const FIXTURE_REVISION := "0.1.0"

## Anchored bank value that exceeds the design's approximately +/-12 degree
## target. The contract must accept it (no hard bank limit here) while carrying
## the authored exception record.
const OUT_OF_TARGET_BANK_DEG := -14.0


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

	func close(actual: float, expected: float, tolerance: float, message: String) -> void:
		checks += 1
		if absf(actual - expected) > tolerance:
			failures.append(
				"%s (got %.9f expected %.9f tol %.6f)" % [message, actual, expected, tolerance]
			)

	func vector_equal(actual: Vector3, expected: Vector3, message: String) -> void:
		checks += 1
		if actual != expected:
			failures.append("%s (got %s expected %s)" % [message, str(actual), str(expected)])

	## Requires a structured refusal: not ok, no document, a diagnostic, the
	## expected stable code and (optionally) a substring of the diagnostic.
	func refuses(
		result: Dictionary,
		expected_code: int,
		message: String,
		expected_substring: String = ""
	) -> void:
		checks += 1
		if bool(result["ok"]):
			failures.append(message + ": expected a refusal, got ok")
			return
		checks += 1
		if result["document"] != null:
			failures.append(message + ": refusal returned a document")
		checks += 1
		if str(result["error"]).strip_edges().is_empty():
			failures.append(message + ": refusal carried no diagnostic")
		checks += 1
		if int(result["code"]) != expected_code:
			failures.append(
				"%s: expected code %s, got %s (%s)" % [
					message,
					RoadSourceDocument.refusal_name(expected_code),
					RoadSourceDocument.refusal_name(int(result["code"])),
					str(result["error"]),
				]
			)
		if not expected_substring.is_empty():
			checks += 1
			if not str(result["error"]).contains(expected_substring):
				failures.append(
					"%s: diagnostic %s does not mention %s" % [
						message, str(result["error"]), expected_substring
					]
				)

	func accepts(result: Dictionary, message: String) -> RoadSourceDocument:
		checks += 1
		if not bool(result["ok"]):
			failures.append(
				"%s: expected acceptance, got refusal %s (%s)" % [
					message,
					RoadSourceDocument.refusal_name(int(result["code"])),
					str(result["error"]),
				]
			)
			return null
		checks += 1
		if result["document"] == null:
			failures.append(message + ": acceptance returned no document")
			return null
		return result["document"]

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
		Callable(self, "_case_open_fixture_contract"),
		Callable(self, "_case_closed_fixture_contract"),
		Callable(self, "_case_round_trip_and_immutability"),
		Callable(self, "_case_identity_and_structure_refusals"),
		Callable(self, "_case_numeric_and_geometry_refusals"),
		Callable(self, "_case_strict_json_text_preflight"),
		Callable(self, "_case_exponent_decoder_bounds"),
		Callable(self, "_case_mantissa_window_bounds"),
		Callable(self, "_case_mutation_controls"),
		Callable(self, "_case_span_semantics"),
	]:
		var result: Dictionary = call.call()
		case_results.append(result)
		cases_run += 1
		total_checks += int(result["checks"])
		total_failures += int(result["checks_failed"])
		print(
			"ROAD_SOURCE_LAB_CASE ",
			JSON.stringify({
				"case": result["case"],
				"checks": result["checks"],
				"checks_failed": result["checks_failed"],
				"pass": result["pass"],
			})
		)
	return {
		"schema": "roadstorm.road_source_lab.summary.v1",
		"pass": total_failures == 0,
		"cases": cases_run,
		"cases_passed": cases_run - _failed_case_count(),
		"checks": total_checks,
		"checks_failed": total_failures,
		"fixtures": [OPEN_FIXTURE_PATH, CLOSED_FIXTURE_PATH],
		"case_results": case_results.duplicate(),
	}


func _failed_case_count() -> int:
	var failed := 0
	for result in case_results:
		if not bool(result["pass"]):
			failed += 1
	return failed


# --- Fixture access ----------------------------------------------------------


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


static func fixture_copy(p_path: String) -> Dictionary:
	var loaded := load_fixture(p_path)
	if not bool(loaded["ok"]):
		return {}
	return (loaded["doc"] as Dictionary).duplicate(true)


## Replaces only the first occurrence of p_needle, so one authored scalar can
## be mutated without changing every identical value in the fixture.
static func replace_once(p_text: String, p_needle: String, p_replacement: String) -> String:
	var index := p_text.find(p_needle)
	if index < 0:
		return p_text
	return p_text.substr(0, index) + p_replacement + p_text.substr(index + p_needle.length())


## Tolerant deep comparison: JSON numbers all arrive as floats, while a
## re-serialized document mixes authored floats with engine values.
static func deep_equal(a: Variant, b: Variant) -> bool:
	var type_a := typeof(a)
	var type_b := typeof(b)
	if type_a != type_b:
		if (type_a == TYPE_INT or type_a == TYPE_FLOAT) and (type_b == TYPE_INT or type_b == TYPE_FLOAT):
			return float(a) == float(b)
		return false
	match type_a:
		TYPE_DICTIONARY:
			var dict_a: Dictionary = a
			var dict_b: Dictionary = b
			if dict_a.size() != dict_b.size():
				return false
			for key in dict_a:
				if not dict_b.has(key):
					return false
				if not deep_equal(dict_a[key], dict_b[key]):
					return false
			return true
		TYPE_ARRAY:
			var array_a: Array = a
			var array_b: Array = b
			if array_a.size() != array_b.size():
				return false
			for index in range(array_a.size()):
				if not deep_equal(array_a[index], array_b[index]):
					return false
			return true
		TYPE_INT, TYPE_FLOAT:
			return float(a) == float(b)
	return a == b


# --- Cases -------------------------------------------------------------------


func _case_open_fixture_contract() -> Dictionary:
	var c := Case.new()
	c.name = "open_fixture_contract"

	var loaded := load_fixture(OPEN_FIXTURE_PATH)
	c.check(bool(loaded["ok"]), "open fixture file loads: " + str(loaded["error"]))
	if not bool(loaded["ok"]):
		return c.result()

	var document := c.accepts(
		RoadSourceDocument.parse_document(loaded["doc"]), "open fixture parses"
	)
	if document == null:
		return c.result()

	c.equal(document.schema, RoadSourceDocument.SCHEMA, "schema constant")
	c.equal(document.course_id, OPEN_COURSE_ID, "course_id preserved")
	c.equal(document.revision, FIXTURE_REVISION, "revision preserved")
	c.check(not document.closed, "open fixture reports closed=false")
	c.equal(document.knot_count, 3, "three authored knots")
	c.equal(document.section_count, 2, "two ordered section records")
	c.equal(document.span_count, 2, "an open source with 3 knots has 2 spans")
	c.equal(
		RoadSourceDocument.expected_span_count(3, false),
		2,
		"span rule N-1 for open sources"
	)
	c.equal(document.section(0).section_id, "lab.open.straight", "first section id and order")
	c.equal(document.section(1).section_id, "lab.open.chicane", "second section id and order")
	c.equal(document.section(0).surface_id, "asphalt", "surface id preserved")
	c.equal(document.section(1).surface_id, "asphalt", "second surface id preserved")
	c.equal(
		document.section(0).feature_tags,
		["straight", "entry"],
		"feature tags preserved in order"
	)
	c.check(not document.section(1).has_exception(), "no exception invented on span 1")
	c.equal(document.section(1).exception, {}, "absent exception reads as empty")
	c.equal(document.knot(1).width_m, 10.0, "authored width change preserved")
	c.equal(document.knot(0).width_m, 12.0, "first authored width preserved")
	c.close(document.knot(1).bank_deg, -4.0, 0.0, "authored bank preserved in degrees")
	c.vector_equal(
		document.knot(2).anchor, Vector3(10.0, 0.0, -80.0), "final anchor in world units"
	)
	c.check(
		deep_equal(loaded["doc"], document.to_dictionary()),
		"to_dictionary round-trips the authored document"
	)

	var repeat := RoadSourceDocument.parse_document(loaded["doc"])
	c.check(bool(repeat["ok"]), "repeated parse succeeds")
	if bool(repeat["ok"]):
		c.equal(
			JSON.stringify(document.summary()),
			JSON.stringify(repeat["document"].summary()),
			"repeated parse summaries are identical"
		)
	c.measurements["open_summary"] = document.summary()
	return c.result()


func _case_closed_fixture_contract() -> Dictionary:
	var c := Case.new()
	c.name = "closed_fixture_contract"

	var loaded := load_fixture(CLOSED_FIXTURE_PATH)
	c.check(bool(loaded["ok"]), "closed fixture file loads: " + str(loaded["error"]))
	if not bool(loaded["ok"]):
		return c.result()

	var document := c.accepts(
		RoadSourceDocument.parse_document(loaded["doc"]), "closed fixture parses"
	)
	if document == null:
		return c.result()

	c.equal(document.course_id, CLOSED_COURSE_ID, "course_id preserved")
	c.check(document.closed, "closed fixture reports closed=true")
	c.equal(document.knot_count, 4, "four authored knots")
	c.equal(document.section_count, 4, "four ordered section records")
	c.equal(document.span_count, 4, "a closed source with 4 knots has 4 spans")
	c.equal(
		RoadSourceDocument.expected_span_count(4, true),
		4,
		"span rule N for closed sources"
	)
	c.equal(
		RoadSourceDocument.expected_span_count(4, false),
		3,
		"the same knots opened would have 3 spans"
	)
	c.equal(
		[document.section(0).section_id, document.section(1).section_id,
		document.section(2).section_id, document.section(3).section_id],
		["lab.loop.north", "lab.loop.east", "lab.loop.south", "lab.loop.west"],
		"section order preserved around the loop"
	)
	c.equal(document.section(2).surface_id, "gravel", "non-asphalt surface id carried verbatim")
	c.check(document.section(1).has_exception(), "authored exception carried on span 1")
	c.equal(
		document.section(1).exception.get("kind"),
		"bank_deg_above_target",
		"exception kind carried verbatim"
	)
	c.check(
		str(document.section(1).exception.get("detail", "")).contains("-14"),
		"exception detail carried verbatim"
	)
	c.check(
		not document.section(0).has_exception(),
		"spans without authored exceptions report none"
	)
	c.close(
		document.knot(2).bank_deg, OUT_OF_TARGET_BANK_DEG, 0.0,
		"bank beyond the +/-12 degree design target is accepted, not limited"
	)
	c.check(
		deep_equal(loaded["doc"], document.to_dictionary()),
		"to_dictionary round-trips the closed document including the exception"
	)
	c.measurements["closed_summary"] = document.summary()
	return c.result()


func _case_round_trip_and_immutability() -> Dictionary:
	var c := Case.new()
	c.name = "round_trip_and_immutability"

	var loaded := load_fixture(OPEN_FIXTURE_PATH)
	var document := c.accepts(
		RoadSourceDocument.parse_document(loaded["doc"]), "open fixture parses"
	)
	if document == null:
		return c.result()

	var before := JSON.stringify(document.summary())

	# Re-serialization is a fresh mutable structure; corrupting it must not
	# reach the validated representation.
	var copy := document.to_dictionary()
	copy["course_id"] = "tampered"
	copy["knots"][0]["anchor"][0] = 999.0
	copy["sections"][0]["section_id"] = "tampered"
	c.equal(JSON.stringify(document.summary()), before, "mutating to_dictionary output is inert")
	c.check(
		deep_equal(loaded["doc"], document.to_dictionary()),
		"a second to_dictionary call still matches the authored source"
	)

	# Container accessors hand out copies.
	var knots_view := document.knots
	c.equal(knots_view.size(), 3, "knots view size")
	knots_view.clear()
	c.equal(document.knot_count, 3, "clearing the returned knots array is inert")
	var sections_view := document.sections
	sections_view.clear()
	c.equal(document.section_count, 2, "clearing the returned sections array is inert")

	# Read-only value objects refuse Object.set through their public members.
	var knot := document.knot(0)
	knot.set("anchor", Vector3.ONE)
	c.vector_equal(knot.anchor, Vector3.ZERO, "knot anchor is read-only")
	knot.set("width_m", 99.0)
	c.equal(knot.width_m, 12.0, "knot width is read-only")
	var section := document.section(1)
	section.set("section_id", "tampered")
	c.equal(section.section_id, "lab.open.chicane", "section id is read-only")
	section.set("surface_id", "gravel")
	c.equal(section.surface_id, "asphalt", "surface id is read-only")
	var tags := section.feature_tags
	tags.append("injected")
	c.equal(
		section.feature_tags, ["chicane", "width_change"], "feature tag list is copied on read"
	)
	var authored_span := document.span(0)
	authored_span.set("index", 42)
	c.equal(authored_span.index, 0, "span index is read-only")

	# The document's own read-only members refuse assignment.
	document.set("course_id", "tampered")
	c.equal(document.course_id, OPEN_COURSE_ID, "document course_id is read-only")
	document.set("closed", true)
	c.check(not document.closed, "document closed flag is read-only")
	document.set("span_count", 99)
	c.equal(document.span_count, 2, "document span_count is read-only")
	document.set("knots", [])
	c.equal(document.knot_count, 3, "document knots view is read-only")
	c.equal(JSON.stringify(document.summary()), before, "document state is unchanged overall")

	# A re-parse of the document's own canonical output is accepted and equal.
	var reparsed := c.accepts(
		RoadSourceDocument.parse_document(document.to_dictionary()),
		"canonical output re-parses"
	)
	if reparsed != null:
		c.equal(
			JSON.stringify(reparsed.summary()), before, "re-parsed canonical summary is identical"
		)

	# The strict JSON-text path also accepts the canonical serialization.
	var canonical_text := JSON.stringify(document.to_dictionary())
	var reparsed_json := c.accepts(
		RoadSourceDocument.parse_json(canonical_text),
		"canonical JSON text re-parses through the strict wrapper"
	)
	if reparsed_json != null:
		c.equal(
			JSON.stringify(reparsed_json.summary()), before,
			"strictly parsed canonical summary is identical"
		)
	return c.result()


func _case_identity_and_structure_refusals() -> Dictionary:
	var c := Case.new()
	c.name = "identity_and_structure_refusals"

	# Non-object inputs.
	for bad in ["a string", [1, 2, 3], 7, 7.5, true, null]:
		c.refuses(
			RoadSourceDocument.parse_document(bad),
			RoadSourceDocument.Refusal.NOT_AN_OBJECT,
			"non-object input %s refused" % str(bad)
		)

	# Schema identity.
	var wrong_schema := fixture_copy(OPEN_FIXTURE_PATH)
	wrong_schema["schema"] = "roadstorm.road_source.v2"
	c.refuses(
		RoadSourceDocument.parse_document(wrong_schema),
		RoadSourceDocument.Refusal.WRONG_SCHEMA,
		"future schema version refused",
		"roadstorm.road_source.v2"
	)
	var non_string_schema := fixture_copy(OPEN_FIXTURE_PATH)
	non_string_schema["schema"] = 1
	c.refuses(
		RoadSourceDocument.parse_document(non_string_schema),
		RoadSourceDocument.Refusal.WRONG_SCHEMA,
		"non-string schema refused"
	)

	# Missing and unknown document keys.
	for required in RoadSourceDocument.DOCUMENT_KEYS:
		var missing := fixture_copy(OPEN_FIXTURE_PATH)
		missing.erase(str(required))
		c.refuses(
			RoadSourceDocument.parse_document(missing),
			RoadSourceDocument.Refusal.MISSING_KEY,
			"missing document key '%s' refused" % str(required),
			str(required)
		)
	var unknown_key := fixture_copy(OPEN_FIXTURE_PATH)
	unknown_key["extra"] = 1
	c.refuses(
		RoadSourceDocument.parse_document(unknown_key),
		RoadSourceDocument.Refusal.UNKNOWN_KEY,
		"unknown document key refused",
		"extra"
	)

	# Identity fields.
	for field in ["course_id", "revision"]:
		var empty := fixture_copy(OPEN_FIXTURE_PATH)
		empty[field] = ""
		var expected := (
			RoadSourceDocument.Refusal.BAD_COURSE_ID
			if field == "course_id" else RoadSourceDocument.Refusal.BAD_REVISION
		)
		c.refuses(
			RoadSourceDocument.parse_document(empty), expected, "empty %s refused" % field
		)
		var wrong_type := fixture_copy(OPEN_FIXTURE_PATH)
		wrong_type[field] = 5
		c.refuses(
			RoadSourceDocument.parse_document(wrong_type), expected,
			"non-string %s refused" % field
		)

	# Explicit closure semantics.
	var string_flag := fixture_copy(OPEN_FIXTURE_PATH)
	string_flag["closed"] = "false"
	c.refuses(
		RoadSourceDocument.parse_document(string_flag),
		RoadSourceDocument.Refusal.BAD_CLOSED_FLAG,
		"string closed flag refused"
	)
	var int_flag := fixture_copy(OPEN_FIXTURE_PATH)
	int_flag["closed"] = 0
	c.refuses(
		RoadSourceDocument.parse_document(int_flag),
		RoadSourceDocument.Refusal.BAD_CLOSED_FLAG,
		"integer closed flag refused"
	)

	# Knot array and knot records.
	var knots_object := fixture_copy(OPEN_FIXTURE_PATH)
	knots_object["knots"] = {}
	c.refuses(
		RoadSourceDocument.parse_document(knots_object),
		RoadSourceDocument.Refusal.BAD_KNOTS_ARRAY,
		"knots object refused"
	)
	var no_knots := fixture_copy(OPEN_FIXTURE_PATH)
	no_knots["knots"] = []
	c.refuses(
		RoadSourceDocument.parse_document(no_knots),
		RoadSourceDocument.Refusal.TOO_FEW_KNOTS,
		"empty knots refused"
	)
	var one_knot := fixture_copy(OPEN_FIXTURE_PATH)
	one_knot["knots"] = [one_knot["knots"][0]]
	one_knot["sections"] = []
	c.refuses(
		RoadSourceDocument.parse_document(one_knot),
		RoadSourceDocument.Refusal.TOO_FEW_KNOTS,
		"single open knot refused"
	)
	var two_knot_closed := fixture_copy(CLOSED_FIXTURE_PATH)
	two_knot_closed["knots"] = [
		two_knot_closed["knots"][0], two_knot_closed["knots"][1]
	]
	two_knot_closed["sections"] = [
		two_knot_closed["sections"][0], two_knot_closed["sections"][1]
	]
	c.refuses(
		RoadSourceDocument.parse_document(two_knot_closed),
		RoadSourceDocument.Refusal.TOO_FEW_KNOTS,
		"two-knot closed loop refused",
		"closed"
	)
	var knot_not_object := fixture_copy(OPEN_FIXTURE_PATH)
	knot_not_object["knots"][1] = [0, 0, 0]
	c.refuses(
		RoadSourceDocument.parse_document(knot_not_object),
		RoadSourceDocument.Refusal.BAD_KNOT,
		"array knot refused"
	)
	var knot_unknown_key := fixture_copy(OPEN_FIXTURE_PATH)
	knot_unknown_key["knots"][1]["grade_deg"] = 3.0
	c.refuses(
		RoadSourceDocument.parse_document(knot_unknown_key),
		RoadSourceDocument.Refusal.BAD_KNOT,
		"unknown knot key refused",
		"grade_deg"
	)
	for required in RoadSourceDocument.KNOT_KEYS:
		var knot_missing := fixture_copy(OPEN_FIXTURE_PATH)
		knot_missing["knots"][0].erase(str(required))
		c.refuses(
			RoadSourceDocument.parse_document(knot_missing),
			RoadSourceDocument.Refusal.BAD_KNOT,
			"knot missing '%s' refused" % str(required),
			str(required)
		)

	# Section array and section records.
	var sections_object := fixture_copy(OPEN_FIXTURE_PATH)
	sections_object["sections"] = {}
	c.refuses(
		RoadSourceDocument.parse_document(sections_object),
		RoadSourceDocument.Refusal.BAD_SECTIONS_ARRAY,
		"sections object refused"
	)
	var short_sections := fixture_copy(OPEN_FIXTURE_PATH)
	short_sections["sections"] = [short_sections["sections"][0]]
	c.refuses(
		RoadSourceDocument.parse_document(short_sections),
		RoadSourceDocument.Refusal.SPAN_COUNT_MISMATCH,
		"open source with one section refused",
		"2 ordered section records"
	)
	var long_sections := fixture_copy(OPEN_FIXTURE_PATH)
	long_sections["sections"].append(long_sections["sections"][0].duplicate(true))
	long_sections["sections"][2]["section_id"] = "lab.open.extra"
	c.refuses(
		RoadSourceDocument.parse_document(long_sections),
		RoadSourceDocument.Refusal.SPAN_COUNT_MISMATCH,
		"open source with three sections refused"
	)
	var section_not_object := fixture_copy(OPEN_FIXTURE_PATH)
	section_not_object["sections"][0] = "asphalt"
	c.refuses(
		RoadSourceDocument.parse_document(section_not_object),
		RoadSourceDocument.Refusal.BAD_SECTION,
		"string section refused"
	)
	var section_unknown_key := fixture_copy(OPEN_FIXTURE_PATH)
	section_unknown_key["sections"][0]["bank_deg"] = 1.0
	c.refuses(
		RoadSourceDocument.parse_document(section_unknown_key),
		RoadSourceDocument.Refusal.BAD_SECTION,
		"unknown section key refused",
		"bank_deg"
	)
	var empty_section_id := fixture_copy(OPEN_FIXTURE_PATH)
	empty_section_id["sections"][0]["section_id"] = "  "
	c.refuses(
		RoadSourceDocument.parse_document(empty_section_id),
		RoadSourceDocument.Refusal.BAD_SECTION_ID,
		"blank section id refused"
	)
	var empty_surface_id := fixture_copy(OPEN_FIXTURE_PATH)
	empty_surface_id["sections"][0]["surface_id"] = ""
	c.refuses(
		RoadSourceDocument.parse_document(empty_surface_id),
		RoadSourceDocument.Refusal.BAD_SURFACE_ID,
		"empty surface id refused"
	)
	var duplicate_ids := fixture_copy(OPEN_FIXTURE_PATH)
	duplicate_ids["sections"][1]["section_id"] = duplicate_ids["sections"][0]["section_id"]
	c.refuses(
		RoadSourceDocument.parse_document(duplicate_ids),
		RoadSourceDocument.Refusal.DUPLICATE_SECTION_ID,
		"duplicate section id refused",
		"lab.open.straight"
	)

	# Optional feature tags and exception metadata shape.
	var tags_not_array := fixture_copy(OPEN_FIXTURE_PATH)
	tags_not_array["sections"][0]["feature_tags"] = "straight"
	c.refuses(
		RoadSourceDocument.parse_document(tags_not_array),
		RoadSourceDocument.Refusal.BAD_FEATURE_TAGS,
		"string feature tags refused"
	)
	var tags_repeat := fixture_copy(OPEN_FIXTURE_PATH)
	tags_repeat["sections"][0]["feature_tags"] = ["straight", "straight"]
	c.refuses(
		RoadSourceDocument.parse_document(tags_repeat),
		RoadSourceDocument.Refusal.BAD_FEATURE_TAGS,
		"repeated feature tag refused"
	)
	var tags_non_string := fixture_copy(OPEN_FIXTURE_PATH)
	tags_non_string["sections"][0]["feature_tags"] = ["straight", 3]
	c.refuses(
		RoadSourceDocument.parse_document(tags_non_string),
		RoadSourceDocument.Refusal.BAD_FEATURE_TAGS,
		"numeric feature tag refused"
	)
	var exception_not_object := fixture_copy(OPEN_FIXTURE_PATH)
	exception_not_object["sections"][0]["exception"] = "authored note"
	c.refuses(
		RoadSourceDocument.parse_document(exception_not_object),
		RoadSourceDocument.Refusal.BAD_EXCEPTION,
		"string exception refused"
	)
	var exception_unknown_key := fixture_copy(CLOSED_FIXTURE_PATH)
	exception_unknown_key["sections"][1]["exception"]["tolerance_deg"] = 2.0
	c.refuses(
		RoadSourceDocument.parse_document(exception_unknown_key),
		RoadSourceDocument.Refusal.BAD_EXCEPTION,
		"unknown exception key refused",
		"tolerance_deg"
	)
	var exception_no_kind := fixture_copy(CLOSED_FIXTURE_PATH)
	exception_no_kind["sections"][1]["exception"] = {"detail": "no kind"}
	c.refuses(
		RoadSourceDocument.parse_document(exception_no_kind),
		RoadSourceDocument.Refusal.BAD_EXCEPTION,
		"exception without kind refused"
	)

	# JSON text wrapper: invalid text and non-finite literals are refused.
	c.refuses(
		RoadSourceDocument.parse_json("{not json"),
		RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
		"invalid JSON text refused"
	)
	c.refuses(
		RoadSourceDocument.parse_json(read_fixture_text(OPEN_FIXTURE_PATH).replace("12.0", "NaN")),
		RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
		"NaN literal in JSON text refused"
	)
	c.refuses(
		RoadSourceDocument.parse_json(read_fixture_text(OPEN_FIXTURE_PATH).replace("12.0", "Infinity")),
		RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
		"Infinity literal in JSON text refused"
	)
	c.refuses(
		RoadSourceDocument.parse_json(5),
		RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
		"non-string JSON input refused"
	)
	var valid_text := RoadSourceDocument.parse_json(read_fixture_text(OPEN_FIXTURE_PATH))
	c.accepts(valid_text, "valid fixture text parses through parse_json")
	return c.result()


func _case_numeric_and_geometry_refusals() -> Dictionary:
	var c := Case.new()
	c.name = "numeric_and_geometry_refusals"

	# Nonfinite and malformed vector components.
	for nonfinite in [NAN, INF, -INF]:
		var nonfinite_anchor := fixture_copy(OPEN_FIXTURE_PATH)
		nonfinite_anchor["knots"][0]["anchor"][1] = nonfinite
		c.refuses(
			RoadSourceDocument.parse_document(nonfinite_anchor),
			RoadSourceDocument.Refusal.NONFINITE_COMPONENT,
			"nonfinite anchor component %s refused" % str(nonfinite),
			"knots[0].anchor"
		)
	var nonfinite_handle := fixture_copy(OPEN_FIXTURE_PATH)
	nonfinite_handle["knots"][2]["handle_out"][2] = NAN
	c.refuses(
		RoadSourceDocument.parse_document(nonfinite_handle),
		RoadSourceDocument.Refusal.NONFINITE_COMPONENT,
		"nonfinite handle component refused",
		"knots[2].handle_out"
	)

	# Finite double-precision scalars can still overflow the engine's stored
	# Vector3 components. The converted vector, not merely the source scalar,
	# must be finite for positions and both handle roles.
	var overflow_anchor := fixture_copy(OPEN_FIXTURE_PATH)
	overflow_anchor["knots"][1]["anchor"][1] = 1e40
	c.refuses(
		RoadSourceDocument.parse_document(overflow_anchor),
		RoadSourceDocument.Refusal.NONFINITE_COMPONENT,
		"finite-but-unrepresentable anchor component refused",
		"knots[1].anchor[1]"
	)
	var overflow_handle_in := fixture_copy(OPEN_FIXTURE_PATH)
	overflow_handle_in["knots"][2]["handle_in"][2] = 1e40
	c.refuses(
		RoadSourceDocument.parse_document(overflow_handle_in),
		RoadSourceDocument.Refusal.NONFINITE_COMPONENT,
		"finite-but-unrepresentable handle_in component refused",
		"knots[2].handle_in[2]"
	)
	var overflow_handle_out := fixture_copy(OPEN_FIXTURE_PATH)
	overflow_handle_out["knots"][0]["handle_out"][0] = 1e40
	c.refuses(
		RoadSourceDocument.parse_document(overflow_handle_out),
		RoadSourceDocument.Refusal.NONFINITE_COMPONENT,
		"finite-but-unrepresentable handle_out component refused",
		"knots[0].handle_out[0]"
	)
	var large_representable := fixture_copy(OPEN_FIXTURE_PATH)
	large_representable["knots"][1]["anchor"][0] = 1e30
	var large_document := c.accepts(
		RoadSourceDocument.parse_document(large_representable),
		"large but representable coordinate accepted"
	)
	if large_document != null:
		c.check(
			large_document.knot(1).anchor.is_finite(),
			"large representable coordinate remains finite after conversion"
		)

	var short_vector := fixture_copy(OPEN_FIXTURE_PATH)
	short_vector["knots"][0]["anchor"] = [0.0, 0.0]
	c.refuses(
		RoadSourceDocument.parse_document(short_vector),
		RoadSourceDocument.Refusal.BAD_VECTOR,
		"two-component vector refused"
	)
	var long_vector := fixture_copy(OPEN_FIXTURE_PATH)
	long_vector["knots"][0]["anchor"] = [0.0, 0.0, 0.0, 1.0]
	c.refuses(
		RoadSourceDocument.parse_document(long_vector),
		RoadSourceDocument.Refusal.BAD_VECTOR,
		"four-component vector refused"
	)
	var string_component := fixture_copy(OPEN_FIXTURE_PATH)
	string_component["knots"][0]["anchor"] = [0.0, "0", 0.0]
	c.refuses(
		RoadSourceDocument.parse_document(string_component),
		RoadSourceDocument.Refusal.NONFINITE_COMPONENT,
		"string vector component refused"
	)
	var vector3_value := fixture_copy(OPEN_FIXTURE_PATH)
	vector3_value["knots"][0]["anchor"] = Vector3.ZERO
	c.refuses(
		RoadSourceDocument.parse_document(vector3_value),
		RoadSourceDocument.Refusal.BAD_VECTOR,
		"Vector3 value refused in favour of the JSON array form"
	)

	# Width plausibility band.
	for width in [0.0, -3.0, 0.5, 1000.0, NAN, INF]:
		var bad_width := fixture_copy(OPEN_FIXTURE_PATH)
		bad_width["knots"][1]["width_m"] = width
		c.refuses(
			RoadSourceDocument.parse_document(bad_width),
			RoadSourceDocument.Refusal.BAD_WIDTH,
			"implausible width %s refused" % str(width),
			"knots[1].width_m"
		)
	var band_edge_low := fixture_copy(OPEN_FIXTURE_PATH)
	band_edge_low["knots"][1]["width_m"] = RoadSourceDocument.MIN_WIDTH_M
	c.accepts(RoadSourceDocument.parse_document(band_edge_low), "band edge minimum width accepted")
	var band_edge_high := fixture_copy(OPEN_FIXTURE_PATH)
	band_edge_high["knots"][1]["width_m"] = RoadSourceDocument.MAX_WIDTH_M
	c.accepts(RoadSourceDocument.parse_document(band_edge_high), "band edge maximum width accepted")

	# Bank: finiteness only, no universal limit.
	for bank in [NAN, INF, -INF]:
		var bad_bank := fixture_copy(OPEN_FIXTURE_PATH)
		bad_bank["knots"][1]["bank_deg"] = bank
		c.refuses(
			RoadSourceDocument.parse_document(bad_bank),
			RoadSourceDocument.Refusal.BAD_BANK,
			"nonfinite bank %s refused" % str(bank)
		)
	var steep_bank := fixture_copy(OPEN_FIXTURE_PATH)
	steep_bank["knots"][1]["bank_deg"] = 45.0
	var steep_document := c.accepts(
		RoadSourceDocument.parse_document(steep_bank), "45 degree bank accepted by the schema"
	)
	if steep_document != null:
		c.close(
			steep_document.knot(1).bank_deg, 45.0, 0.0,
			"out-of-target bank preserved verbatim for the later geometry gate"
		)

	# Nondegenerate anchors and handles.
	var coincident_anchors := fixture_copy(OPEN_FIXTURE_PATH)
	coincident_anchors["knots"][2]["anchor"] = (coincident_anchors["knots"][1]["anchor"] as Array).duplicate()
	c.refuses(
		RoadSourceDocument.parse_document(coincident_anchors),
		RoadSourceDocument.Refusal.DEGENERATE_ANCHOR,
		"coincident adjacent anchors refused",
		"span 1"
	)
	var coincident_out := fixture_copy(OPEN_FIXTURE_PATH)
	coincident_out["knots"][0]["handle_out"] = (coincident_out["knots"][0]["anchor"] as Array).duplicate()
	c.refuses(
		RoadSourceDocument.parse_document(coincident_out),
		RoadSourceDocument.Refusal.DEGENERATE_HANDLE,
		"handle_out on its own anchor refused",
		"knot 0"
	)
	var coincident_in := fixture_copy(OPEN_FIXTURE_PATH)
	coincident_in["knots"][2]["handle_in"] = (coincident_in["knots"][2]["anchor"] as Array).duplicate()
	c.refuses(
		RoadSourceDocument.parse_document(coincident_in),
		RoadSourceDocument.Refusal.DEGENERATE_HANDLE,
		"handle_in on its own anchor refused",
		"knot 2"
	)

	# The first incoming and last outgoing handle of an open source participate
	# in no span. They are carried as authored data but are not tangent-checked.
	var unused_first_handle := fixture_copy(OPEN_FIXTURE_PATH)
	unused_first_handle["knots"][0]["handle_in"] = (
		unused_first_handle["knots"][0]["anchor"] as Array
	).duplicate()
	c.accepts(
		RoadSourceDocument.parse_document(unused_first_handle),
		"unused first open endpoint handle_in is not tangent-checked"
	)
	var unused_last_handle := fixture_copy(OPEN_FIXTURE_PATH)
	unused_last_handle["knots"][2]["handle_out"] = (
		unused_last_handle["knots"][2]["anchor"] as Array
	).duplicate()
	c.accepts(
		RoadSourceDocument.parse_document(unused_last_handle),
		"unused last open endpoint handle_out is not tangent-checked"
	)

	var closure_coincident := fixture_copy(CLOSED_FIXTURE_PATH)
	closure_coincident["knots"][3]["anchor"] = (closure_coincident["knots"][0]["anchor"] as Array).duplicate()
	c.refuses(
		RoadSourceDocument.parse_document(closure_coincident),
		RoadSourceDocument.Refusal.DEGENERATE_ANCHOR,
		"closed closure span with coincident anchors refused",
		"span 3"
	)
	var closure_handle := fixture_copy(CLOSED_FIXTURE_PATH)
	closure_handle["knots"][0]["handle_in"] = (closure_handle["knots"][0]["anchor"] as Array).duplicate()
	c.refuses(
		RoadSourceDocument.parse_document(closure_handle),
		RoadSourceDocument.Refusal.DEGENERATE_HANDLE,
		"closed closure span with degenerate end tangent refused",
		"knot 0"
	)

	# Closure semantics against the same records.
	var opened_closed := fixture_copy(CLOSED_FIXTURE_PATH)
	opened_closed["closed"] = false
	c.refuses(
		RoadSourceDocument.parse_document(opened_closed),
		RoadSourceDocument.Refusal.SPAN_COUNT_MISMATCH,
		"closed records opened refuse on span count",
		"open"
	)
	var closed_open := fixture_copy(OPEN_FIXTURE_PATH)
	closed_open["closed"] = true
	c.refuses(
		RoadSourceDocument.parse_document(closed_open),
		RoadSourceDocument.Refusal.SPAN_COUNT_MISMATCH,
		"open records closed refuse on span count",
		"closed"
	)
	return c.result()


func _case_strict_json_text_preflight() -> Dictionary:
	var c := Case.new()
	c.name = "strict_json_text_preflight"

	var open_text := read_fixture_text(OPEN_FIXTURE_PATH)
	var closed_text := read_fixture_text(CLOSED_FIXTURE_PATH)
	var trimmed := open_text.strip_edges()

	# Sol counterexamples: Godot's permissive reader accepted both of these
	# before the preflight. The duplicate first value is invalid but hidden by
	# the later valid boolean unless members are checked before Dictionary
	# construction.
	c.refuses(
		RoadSourceDocument.parse_json(trimmed.left(-1) + ",}"),
		RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
		"trailing comma before the final document brace refused",
		"trailing comma"
	)
	c.refuses(
		RoadSourceDocument.parse_json("{\"closed\":123," + trimmed.substr(1)),
		RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
		"duplicate closed member refused before later valid value can hide the first",
		"duplicate object member name 'closed'"
	)
	c.refuses(
		RoadSourceDocument.parse_json("{\"cl\\u006fsed\":false," + trimmed.substr(1)),
		RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
		"escaped duplicate closed member refused",
		"duplicate object member name 'closed'"
	)

	# Unicode escapes canonicalize to the same member names as their raw UTF-8
	# spellings, including surrogate pairs, so they cannot bypass duplicate
	# detection.
	var emoji := PackedByteArray([0xf0, 0x9f, 0x98, 0x80]).get_string_from_utf8()
	c.refuses(
		RoadSourceDocument.parse_json(
			"{\"\\uD83D\\uDE00\":0,\"" + emoji + "\":1}"
		),
		RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
		"surrogate-pair escaped duplicate member refused",
		"duplicate object member name"
	)
	var accented := PackedByteArray([0xc3, 0xa9]).get_string_from_utf8()
	c.refuses(
		RoadSourceDocument.parse_json(
			"{\"\\u00e9\":0,\"" + accented + "\":1}"
		),
		RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
		"BMP Unicode escaped duplicate member refused",
		"duplicate object member name"
	)

	# Duplicate and trailing-comma detection applies inside nested objects and
	# arrays, not only at the document root.
	var nested_duplicate_text := closed_text.replace(
		"\"kind\": \"bank_deg_above_target\"",
		"\"kind\": \"bank_deg_above_target\", \"kind\": \"other\""
	)
	c.refuses(
		RoadSourceDocument.parse_json(nested_duplicate_text),
		RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
		"duplicate member inside a nested exception object refused",
		"duplicate object member name"
	)
	var nested_trailing_text := closed_text.replace(
		"\"feature_tags\": [\"straight\"]",
		"\"feature_tags\": [\"straight\",]"
	)
	c.refuses(
		RoadSourceDocument.parse_json(nested_trailing_text),
		RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
		"trailing comma inside a nested array refused",
		"trailing comma"
	)

	# Commas, braces, escaped quotes, escaped backslashes and Unicode escapes
	# inside strings are string content, not structure. This positive control
	# remains a valid road source and checks the decoded free-text detail.
	var backslash := "\\"
	var quote := "\""
	var detail_json := (
		"quoted " + backslash + quote
		+ " comma, braces { } "
		+ backslash + backslash
		+ " unicode "
		+ backslash + "u263A end"
	)
	var original_detail := (
		"Knot 2 authors -14 degrees of bank, outside the approximately +/-12 degree "
		+ "design target; the later geometry gate reviews this exception."
	)
	var escaped_text := closed_text.replace(original_detail, detail_json)
	var escaped_document := c.accepts(
		RoadSourceDocument.parse_json(escaped_text),
		"valid string escapes and structural characters inside strings accepted"
	)
	if escaped_document != null:
		var smiley := PackedByteArray([0xe2, 0x98, 0xba]).get_string_from_utf8()
		var expected_detail := (
			"quoted " + quote + " comma, braces { } " + backslash
			+ " unicode " + smiley + " end"
		)
		c.equal(
			escaped_document.section(1).exception.get("detail"),
			expected_detail,
			"escaped free-text detail decoded exactly"
		)

	# Syntactically valid JSON that is not a road-source object must reach the
	# document validator rather than being misreported as malformed JSON text.
	c.refuses(
		RoadSourceDocument.parse_json("{}"),
		RoadSourceDocument.Refusal.MISSING_KEY,
		"valid empty object reaches document validation",
		"schema"
	)
	c.refuses(
		RoadSourceDocument.parse_json("[null,true,false,0,-1.25e+2,\"x\"]"),
		RoadSourceDocument.Refusal.NOT_AN_OBJECT,
		"valid scalar and array grammar reaches document validation"
	)
	c.refuses(
		RoadSourceDocument.parse_json("{\"x\":[{\"y\":[true,null,{\"z\":\"nested\"}]}]}"),
		RoadSourceDocument.Refusal.UNKNOWN_KEY,
		"valid nested objects and arrays reach document validation",
		"x"
	)
	c.refuses(
		RoadSourceDocument.parse_json(
			"{\"x\":[{\"same\":1},{\"same\":2}],\"y\":{\"same\":3}}"
		),
		RoadSourceDocument.Refusal.UNKNOWN_KEY,
		"same member name in separate objects remains valid JSON and reaches validation",
		"x"
	)

	# Representative strict-grammar controls. Several are also rejected by
	# Godot; they pin the boundary at INVALID_JSON_TEXT rather than any later
	# schema refusal.
	for control in [
		["missing object comma", "{\"schema\":1 \"closed\":false}"],
		["missing object colon", "{\"schema\" 1}"],
		["trailing array comma", "[1,]"],
		["leading zero", "{\"schema\":01}"],
		["invalid string escape", "{\"schema\":\"\\q\"}"],
		["unescaped string control", "{\"schema\":\"a\nb\"}"],
		["unpaired Unicode surrogate", "{\"schema\":\"\\uD800\"}"],
		["engine-unrepresentable NUL escape", "{\"schema\":\"\\u0000\"}"],
		["trailing root data", "{\"schema\":1} null"],
		["single-quoted member name", "{'schema':1}"],
	]:
		c.refuses(
			RoadSourceDocument.parse_json(control[1]),
			RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
			"strict grammar control refused: %s" % str(control[0])
		)
	return c.result()


func _case_exponent_decoder_bounds() -> Dictionary:
	var c := Case.new()
	c.name = "exponent_decoder_bounds"

	var open_text := read_fixture_text(OPEN_FIXTURE_PATH)
	var closed_text := read_fixture_text(CLOSED_FIXTURE_PATH)

	# Exact Sol payloads. Godot's permissive reader wrapped these exponents
	# into plausible finite values (12.0, 0.0 and 1.0), so they previously passed
	# finiteness and the authored width band. The lexical preflight must refuse
	# them before decode, for width, bank and vector spellings alike.
	for token in ["12e4294967296", "12e18446744073709551616", "12e-4294967296"]:
		c.refuses(
			RoadSourceDocument.parse_json(
				replace_once(open_text, "\"width_m\": 12.0", "\"width_m\": " + token)
			),
			RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
			"giant width exponent %s refused before engine decode" % token,
			"supported range"
		)
	for token in ["1e2147483648", "1e4294967296"]:
		c.refuses(
			RoadSourceDocument.parse_json(
				replace_once(closed_text, "\"bank_deg\": -14.0", "\"bank_deg\": " + token)
			),
			RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
			"giant bank exponent %s refused before engine decode" % token,
			"supported range"
		)
	for vector_case in [
		["\"anchor\": [0.0, 0.0, -40.0]", "\"anchor\": [12e4294967296, 0.0, -40.0]"],
		["\"handle_in\": [0.0, 0.0, -28.0]", "\"handle_in\": [-12e18446744073709551616, 0.0, -28.0]"],
	]:
		c.refuses(
			RoadSourceDocument.parse_json(replace_once(open_text, vector_case[0], vector_case[1])),
			RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
			"giant vector exponent refused before engine decode",
			"supported range"
		)
	c.refuses(
		RoadSourceDocument.parse_json("{\"unused\": [12e4294967296]}"),
		RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
		"giant exponent refused in a nested array outside the document schema",
		"supported range"
	)

	# Ordinary signed exponents survive the lexical bound and decode to the
	# authored value; e+2 and e-2 spellings are exercised directly.
	var ordinary_width := c.accepts(
		RoadSourceDocument.parse_json(
			replace_once(open_text, "\"width_m\": 12.0", "\"width_m\": 1.2e+1")
		),
		"ordinary e+1 width accepted"
	)
	if ordinary_width != null:
		c.equal(ordinary_width.knot(0).width_m, 12.0, "e+1 width decodes to 12.0")
	var fractional_width := c.accepts(
		RoadSourceDocument.parse_json(
			replace_once(open_text, "\"width_m\": 12.0", "\"width_m\": 120e-2")
		),
		"ordinary e-2 width accepted"
	)
	if fractional_width != null:
		c.close(fractional_width.knot(0).width_m, 1.2, 1e-12, "e-2 width decodes to 1.2")
	var ordinary_handle := c.accepts(
		RoadSourceDocument.parse_json(
			replace_once(
				open_text,
				"\"handle_in\": [0.0, 0.0, 12.0]",
				"\"handle_in\": [0e+2, 0e-2, 1.2e+1]"
			)
		),
		"ordinary e+2/e-2 handle accepted"
	)
	if ordinary_handle != null:
		c.vector_equal(
			ordinary_handle.knot(0).handle_in,
			Vector3(0.0, 0.0, 12.0),
			"signed exponents decode to the authored unused open handle"
		)

	# Boundary exponents are lexically supported; one past either boundary is
	# refused. The bank field carries the decoded double directly, so it
	# exercises the bound without float32 conversion masking the value.
	var max_bank := c.accepts(
		RoadSourceDocument.parse_json(
			replace_once(closed_text, "\"bank_deg\": -14.0", "\"bank_deg\": 1e+308")
		),
		"+308 exponent accepted"
	)
	if max_bank != null:
		c.check(is_finite(max_bank.knot(2).bank_deg), "+308 bank remains finite")
		c.close(max_bank.knot(2).bank_deg, 1e308, 1e294, "+308 bank decodes near 1e308")
	var min_bank := c.accepts(
		RoadSourceDocument.parse_json(
			replace_once(closed_text, "\"bank_deg\": -14.0", "\"bank_deg\": 1e-308")
		),
		"-308 exponent accepted"
	)
	if min_bank != null:
		c.check(is_finite(min_bank.knot(2).bank_deg), "-308 bank remains finite")
		c.check(
			min_bank.knot(2).bank_deg > 0.0 and min_bank.knot(2).bank_deg < 1e-300,
			"-308 bank decodes as a tiny positive value"
		)
	var padded_bank := c.accepts(
		RoadSourceDocument.parse_json(
			replace_once(closed_text, "\"bank_deg\": -14.0", "\"bank_deg\": 1e+0308")
		),
		"four-digit in-range exponent spelling accepted"
	)
	if padded_bank != null:
		c.close(padded_bank.knot(2).bank_deg, 1e308, 1e294, "padded +308 bank decodes near 1e308")
	c.refuses(
		RoadSourceDocument.parse_json(
			replace_once(closed_text, "\"bank_deg\": -14.0", "\"bank_deg\": 1e+309")
		),
		RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
		"+309 exponent refused",
		"supported range"
	)
	c.refuses(
		RoadSourceDocument.parse_json(
			replace_once(closed_text, "\"bank_deg\": -14.0", "\"bank_deg\": 1e-309")
		),
		RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
		"-309 exponent refused",
		"supported range"
	)

	# Long leading-zero spellings are refused by digit count even when their
	# numeric value is small or in range; the engine decoder's digit handling is
	# not trusted with them.
	for token in [
		"1e+00308",
		"1e-00308",
		"1e+000000000000000000000308",
		"1e+0000000000000000000000000000000000000000002",
	]:
		c.refuses(
			RoadSourceDocument.parse_json(
				replace_once(closed_text, "\"bank_deg\": -14.0", "\"bank_deg\": " + token)
			),
			RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
			"excessive exponent digit spelling %s refused" % token,
			"number exponent"
		)
	return c.result()


func _case_mantissa_window_bounds() -> Dictionary:
	var c := Case.new()
	c.name = "mantissa_window_bounds"

	var open_text := read_fixture_text(OPEN_FIXTURE_PATH)
	var closed_text := read_fixture_text(CLOSED_FIXTURE_PATH)

	# Opus Finding 1: the pinned decoder retains only the first 18 mantissa
	# digit characters, counting the integer part's leading zero and fractional
	# leading zeros, then applies the exponent. These exact valid-JSON tokens
	# place significant digits beyond that window and previously decoded to
	# plausible wrong values inside the authored bands. The lexical preflight
	# must refuse them in width, bank, vector and schema-unknown positions.
	for token in [
		"0.000000000000000025e17",
		"-0.0000000000000000014e19",
		"0.00000000000000000050e20",
		"0.0000000000000000012e19",
		"0.000000000000001234e15",
	]:
		c.refuses(
			RoadSourceDocument.parse_json(
				replace_once(open_text, "\"width_m\": 12.0", "\"width_m\": " + token)
			),
			RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
			"long width significand %s refused before engine decode" % token,
			"significand"
		)
	for token in ["-0.0000000000000000014e19", "0.000000000000001234e15"]:
		c.refuses(
			RoadSourceDocument.parse_json(
				replace_once(closed_text, "\"bank_deg\": -14.0", "\"bank_deg\": " + token)
			),
			RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
			"long bank significand %s refused before engine decode" % token,
			"significand"
		)
	for vector_case in [
		["\"anchor\": [0.0, 0.0, -40.0]", "\"anchor\": [0.00000000000000000050e20, 0.0, -40.0]"],
		["\"handle_out\": [0.0, 0.0, -12.0]", "\"handle_out\": [0.0, 0.0000000000000000012e19, -12.0]"],
		["\"handle_in\": [0.0, 0.0, -28.0]", "\"handle_in\": [0.0, 0.0, 0.000000000000001234e15]"],
	]:
		c.refuses(
			RoadSourceDocument.parse_json(replace_once(open_text, vector_case[0], vector_case[1])),
			RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
			"long vector significand refused before engine decode",
			"significand"
		)
	for token in ["0.000000000000000025e17", "0.000000000000001234e15"]:
		c.refuses(
			RoadSourceDocument.parse_json(
				"{\"unused\": {\"nested\": [1, {\"value\": " + token + "}]}}"
			),
			RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
			"long nested schema-unknown significand %s refused" % token,
			"significand"
		)
	c.refuses(
		RoadSourceDocument.parse_json("[0.000000000000000025e17]"),
		RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
		"long significand refused as a root array element",
		"significand"
	)
	c.refuses(
		RoadSourceDocument.parse_json("0.000000000000000025e17"),
		RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
		"long significand refused as a bare root number",
		"significand"
	)

	# A nonzero-led 22-digit significand is refused under the documented
	# 18-digit contract. Its truncated value would stay close to the authored
	# value, but the simple rule keeps every refusal fail-closed and bounded.
	c.refuses(
		RoadSourceDocument.parse_json(
			replace_once(open_text, "\"width_m\": 12.0", "\"width_m\": 1234567890123456789012e-20")
		),
		RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
		"22-digit nonzero-led significand refused by the 18-digit contract",
		"significand"
	)

	# Every numeric-contract refusal carries a byte offset for the offending
	# significand, not just an error code.
	var offset_result := RoadSourceDocument.parse_json(
		replace_once(open_text, "\"width_m\": 12.0", "\"width_m\": 0.000000000000000025e17")
	)
	c.check(
		not bool(offset_result["ok"]) and str(offset_result["error"]).contains("at byte"),
		"significand refusal reports a byte offset"
	)

	# Prior giant-exponent refusals remain in force alongside the mantissa rule.
	for token in ["12e4294967296", "1e4294967296"]:
		c.refuses(
			RoadSourceDocument.parse_json(
				replace_once(open_text, "\"width_m\": 12.0", "\"width_m\": " + token)
			),
			RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
			"giant width exponent %s still refused" % token,
			"supported range"
		)
		c.refuses(
			RoadSourceDocument.parse_json(
				replace_once(closed_text, "\"bank_deg\": -14.0", "\"bank_deg\": " + token)
			),
			RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
			"giant bank exponent %s still refused" % token,
			"supported range"
		)
	c.refuses(
		RoadSourceDocument.parse_json("{\"unused\": [12e4294967296]}"),
		RoadSourceDocument.Refusal.INVALID_JSON_TEXT,
		"giant exponent in a nested schema-unknown position still refused",
		"supported range"
	)

	# Positive controls: short-significand spellings decode exactly. The
	# 18-digit boundary is exercised on both sides by the acceptance below and
	# the 19-digit refusal above.
	var positive_width_cases := [
		["0.25e1", 2.5],
		["0.00000000025e10", 2.5],
		["0.00000000000000025e16", 2.5],
		["120e-2", 1.2],
	]
	for case_pair in positive_width_cases:
		var document := c.accepts(
			RoadSourceDocument.parse_json(
				replace_once(open_text, "\"width_m\": 12.0", "\"width_m\": " + str(case_pair[0]))
			),
			"short width significand %s accepted" % str(case_pair[0])
		)
		if document != null:
			c.close(
				document.knot(0).width_m,
				float(case_pair[1]),
				1e-12,
				"short width significand %s decodes exactly" % str(case_pair[0])
			)
	var canonical_bank := c.accepts(
		RoadSourceDocument.parse_json(
			replace_once(closed_text, "\"bank_deg\": -14.0", "\"bank_deg\": 0.30000000000000004")
		),
		"canonical double-precision bank spelling accepted"
	)
	if canonical_bank != null:
		c.equal(
			canonical_bank.knot(2).bank_deg,
			0.30000000000000004,
			"canonical double-precision bank spelling decodes exactly"
		)
	var upper_width := c.accepts(
		RoadSourceDocument.parse_json(
			replace_once(open_text, "\"width_m\": 12.0", "\"width_m\": 0.25E1")
		),
		"uppercase width exponent accepted"
	)
	if upper_width != null:
		c.close(upper_width.knot(0).width_m, 2.5, 1e-12, "uppercase exponent decodes to 2.5")

	var signed_bank := c.accepts(
		RoadSourceDocument.parse_json(
			replace_once(closed_text, "\"bank_deg\": -14.0", "\"bank_deg\": -1.2E+1")
		),
		"signed uppercase bank exponent accepted"
	)
	if signed_bank != null:
		c.close(signed_bank.knot(2).bank_deg, -12.0, 1e-12, "signed uppercase exponent decodes to -12")
	var vector_spellings := c.accepts(
		RoadSourceDocument.parse_json(
			replace_once(
				open_text,
				"\"handle_in\": [0.0, 0.0, 12.0]",
				"\"handle_in\": [0E+2, -0.12E+2, 1.2e+1]"
			)
		),
		"mixed-case signed vector exponents accepted"
	)
	if vector_spellings != null:
		c.vector_equal(
			vector_spellings.knot(0).handle_in,
			Vector3(0.0, -12.0, 12.0),
			"signed and uppercase vector exponents decode exactly"
		)

	# parse_document receives already-decoded Variants and cannot recover the
	# source spelling; the lexical guard protects the parse_json text path only.
	var decoded_width := fixture_copy(OPEN_FIXTURE_PATH)
	decoded_width["knots"][0]["width_m"] = 2.0
	c.accepts(
		RoadSourceDocument.parse_document(decoded_width),
		"direct parse_document accepts an already-decoded width and cannot see its spelling"
	)
	return c.result()


func _case_mutation_controls() -> Dictionary:
	var c := Case.new()
	c.name = "mutation_controls"

	# Control: an untouched copy of each fixture still parses.
	c.accepts(
		RoadSourceDocument.parse_document(fixture_copy(OPEN_FIXTURE_PATH)),
		"untouched open copy parses"
	)
	c.accepts(
		RoadSourceDocument.parse_document(fixture_copy(CLOSED_FIXTURE_PATH)),
		"untouched closed copy parses"
	)

	# Authored order is preserved, not re-sorted or re-derived: swapping the two
	# section records swaps which span carries which surface and metadata.
	var swapped := fixture_copy(OPEN_FIXTURE_PATH)
	var held: Dictionary = swapped["sections"][0]
	swapped["sections"][0] = swapped["sections"][1]
	swapped["sections"][1] = held
	var swapped_document := c.accepts(
		RoadSourceDocument.parse_document(swapped), "reordered section records still parse"
	)
	if swapped_document != null:
		c.equal(
			swapped_document.section(0).section_id,
			"lab.open.chicane",
			"section order follows the authored order"
		)
		c.equal(
			swapped_document.section(1).section_id,
			"lab.open.straight",
			"second section follows the authored order"
		)

	# Adding a knot without a matching section record is refused rather than
	# silently truncating or padding.
	var extra_knot := fixture_copy(OPEN_FIXTURE_PATH)
	extra_knot["knots"].append((extra_knot["knots"][2] as Dictionary).duplicate(true))
	(extra_knot["knots"][3] as Dictionary)["anchor"] = [10.0, 0.0, -120.0]
	(extra_knot["knots"][3] as Dictionary)["handle_in"] = [4.0, 0.0, -108.0]
	(extra_knot["knots"][3] as Dictionary)["handle_out"] = [10.0, 0.0, -132.0]
	c.refuses(
		RoadSourceDocument.parse_document(extra_knot),
		RoadSourceDocument.Refusal.SPAN_COUNT_MISMATCH,
		"extra knot without a section record refused"
	)

	# Dropping a closed knot while retaining its section record breaks the
	# closure-aware one-section-per-span count.
	var dropped_knot := fixture_copy(CLOSED_FIXTURE_PATH)
	dropped_knot["knots"].remove_at(3)
	c.refuses(
		RoadSourceDocument.parse_document(dropped_knot),
		RoadSourceDocument.Refusal.SPAN_COUNT_MISMATCH,
		"dropped closed knot with stale section record refuses on span count",
		"closed"
	)

	# A surface rename travels with the span; it is never defaulted back.
	var renamed_surface := fixture_copy(CLOSED_FIXTURE_PATH)
	renamed_surface["sections"][2]["surface_id"] = "wet_gravel"
	var renamed_document := c.accepts(
		RoadSourceDocument.parse_document(renamed_surface), "renamed surface id parses"
	)
	if renamed_document != null:
		c.equal(
			renamed_document.section(2).surface_id,
			"wet_gravel",
			"renamed surface id carried verbatim on its span"
		)
		c.equal(
			renamed_document.span(2).section.surface_id,
			"wet_gravel",
			"span accessor exposes the same surface id"
		)

	# Feature tags and exceptions can be added, dropped or changed and are
	# carried through verbatim.
	var tagged := fixture_copy(OPEN_FIXTURE_PATH)
	tagged["sections"][0]["exception"] = {"kind": "grade_percent_above_target", "detail": "authored"}
	var tagged_document := c.accepts(
		RoadSourceDocument.parse_document(tagged), "added exception metadata parses"
	)
	if tagged_document != null:
		c.equal(
			tagged_document.section(0).exception.get("kind"),
			"grade_percent_above_target",
			"added exception kind carried verbatim"
		)
		c.equal(
			tagged_document.section(0).exception.get("detail"),
			"authored",
			"added exception detail carried verbatim"
		)
	var untagged := fixture_copy(OPEN_FIXTURE_PATH)
	untagged["sections"][1].erase("feature_tags")
	var untagged_document := c.accepts(
		RoadSourceDocument.parse_document(untagged), "absent feature tags parse"
	)
	if untagged_document != null:
		c.equal(untagged_document.section(1).feature_tags, [], "absent feature tags read as empty")
	return c.result()


func _case_span_semantics() -> Dictionary:
	var c := Case.new()
	c.name = "span_semantics"

	var open_loaded := load_fixture(OPEN_FIXTURE_PATH)
	var open_document := c.accepts(
		RoadSourceDocument.parse_document(open_loaded["doc"]), "open fixture parses"
	)
	if open_document == null:
		return c.result()

	# Each open span runs knot i anchor -> knot i handle_out -> knot (i+1)
	# handle_in -> knot (i+1) anchor.
	for index in range(open_document.span_count):
		var authored_span := open_document.span(index)
		var start_knot := open_document.knot(index)
		var end_knot := open_document.knot(index + 1)
		c.equal(authored_span.start_knot_index, index, "span %d start knot index" % index)
		c.equal(authored_span.end_knot_index, index + 1, "span %d end knot index" % index)
		c.equal(authored_span.control_points(), [
			start_knot.anchor,
			start_knot.handle_out,
			end_knot.handle_in,
			end_knot.anchor,
		], "span %d control point chain" % index)
		c.equal(
			authored_span.section.section_id,
			open_document.section(index).section_id,
			"span %d carries its ordered section record" % index
		)
	c.check(open_document.span(2) == null, "out-of-range open span is null")
	c.check(open_document.knot(3) == null, "out-of-range knot is null")
	c.check(open_document.section(2) == null, "out-of-range section is null")
	c.check(open_document.span(-1) == null, "negative span index is null")

	# The closed fixture's final span wraps from the last knot to the first.
	var closed_loaded := load_fixture(CLOSED_FIXTURE_PATH)
	var closed_document := c.accepts(
		RoadSourceDocument.parse_document(closed_loaded["doc"]), "closed fixture parses"
	)
	if closed_document == null:
		return c.result()
	var closure_span := closed_document.span(closed_document.span_count - 1)
	var last_knot := closed_document.knot(closed_document.knot_count - 1)
	var first_knot := closed_document.knot(0)
	c.equal(closure_span.start_knot_index, 3, "closure span starts at the last knot")
	c.equal(closure_span.end_knot_index, 0, "closure span ends at the first knot")
	c.vector_equal(closure_span.start_knot.anchor, last_knot.anchor, "closure span start anchor")
	c.vector_equal(closure_span.end_knot.anchor, first_knot.anchor, "closure span end anchor")
	c.equal(closure_span.control_points(), [
		last_knot.anchor,
		last_knot.handle_out,
		first_knot.handle_in,
		first_knot.anchor,
	], "closure span control point chain wraps")
	c.equal(
		closure_span.section.section_id,
		"lab.loop.west",
		"closure span carries the final authored section record"
	)
	c.check(closed_document.span(4) == null, "out-of-range closed span is null")
	c.measurements["open_span_count"] = open_document.span_count
	c.measurements["closed_span_count"] = closed_document.span_count
	return c.result()
