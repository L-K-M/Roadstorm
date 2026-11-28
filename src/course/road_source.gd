class_name RoadSourceDocument
extends RefCounted
## Authored road-source data contract, schema `roadstorm.road_source.v1`.
##
## This is the M2.1 first slice: the versioned, authored source that later
## arc-length resampling and every derived course artifact (road strip,
## shoulders, barriers, collision, AI samples, gates, anchors, minimap) will
## consume. It contains no mesh, no sampling, no physics and no fun claim.
##
## Document shape (JSON object, exact keys, unknown keys are refused):
##   {
##     "schema": "roadstorm.road_source.v1",
##     "course_id": "lab.open_tiny",        # stable course identity
##     "revision": "0.1.0",                 # authored revision string
##     "closed": false,                     # explicit closure semantics
##     "knots": [                           # ordered, at least 2 (open) / 3 (closed)
##       {
##         "anchor": [x, y, z],             # metres, +Y up, -Z forward
##         "handle_in": [x, y, z],          # incoming cubic handle
##         "handle_out": [x, y, z],         # outgoing cubic handle
##         "width_m": 12.0,                 # authored road width in metres
##         "bank_deg": 0.0                  # authored bank in degrees
##       }
##     ],
##     "sections": [                        # one record per Bezier span, in order
##       {
##         "section_id": "lab.open.straight",   # stable, unique
##         "surface_id": "asphalt",             # route-local surface identity
##         "feature_tags": ["straight"],        # optional
##         "exception": {                       # optional authored metadata
##           "kind": "bank_deg_above_target",
##           "detail": "free text"
##         }
##       }
##     ]
##   }
##
## Span semantics. Cubic span i runs from knot i's `anchor` (P0), out through
## knot i's `handle_out` (P1), into knot (i+1)'s `handle_in` (P2), to knot
## (i+1)'s `anchor` (P3). An open source with N knots has N-1 spans; a closed
## source with N knots has N spans, the last wrapping from knot N-1 to knot 0.
## Surface and metadata stay attached to the span record so later sampling
## cannot silently invent them.
##
## Geometry units are Godot world units in metres with +Y up and -Z forward,
## the same frame as the handling fixtures and CarState.
##
## What this slice validates, and what it deliberately does not:
##   * schema, course/revision identity, stable unique section IDs, finite
##     components, minimum knot counts, the exact ordered span count,
##     nondegenerate adjacent anchors and of each handle against its own knot
##     anchor, and a plausible authored width band;
##   * no universal bank or grade limit is encoded. The design's 12% grade and
##     approximately +/-12 degree bank targets, and the exceptions that exceed
##     them, belong to the later geometry-validation gate (M2.3/T09), so bank
##     is checked for finiteness only and authored exceptions are carried
##     through untouched.
##
## Purity and immutability. Parsing is pure: it reads one Variant (normally a
## JSON object), performs no file or engine access, and returns either a
## validated document or a structured refusal; it never silently defaults a
## malformed source. A parsed document exposes read-only properties, hands out
## copies of every container, and stores its own containers read-only, so a
## caller cannot alter a validated representation through the public API.
## GDScript cannot hide a member variable from `Object.set`; replacing a
## private member wholesale is the one documented residual path.

const SCHEMA := "roadstorm.road_source.v1"

const KEY_SCHEMA := "schema"
const KEY_COURSE_ID := "course_id"
const KEY_REVISION := "revision"
const KEY_CLOSED := "closed"
const KEY_KNOTS := "knots"
const KEY_SECTIONS := "sections"
const DOCUMENT_KEYS: Array = [
	KEY_SCHEMA, KEY_COURSE_ID, KEY_REVISION, KEY_CLOSED, KEY_KNOTS, KEY_SECTIONS
]

const KEY_ANCHOR := "anchor"
const KEY_HANDLE_IN := "handle_in"
const KEY_HANDLE_OUT := "handle_out"
const KEY_WIDTH_M := "width_m"
const KEY_BANK_DEG := "bank_deg"
const KNOT_KEYS: Array = [KEY_ANCHOR, KEY_HANDLE_IN, KEY_HANDLE_OUT, KEY_WIDTH_M, KEY_BANK_DEG]

const KEY_SECTION_ID := "section_id"
const KEY_SURFACE_ID := "surface_id"
const KEY_FEATURE_TAGS := "feature_tags"
const KEY_EXCEPTION := "exception"
const SECTION_KEYS: Array = [KEY_SECTION_ID, KEY_SURFACE_ID, KEY_FEATURE_TAGS, KEY_EXCEPTION]

const KEY_EXCEPTION_KIND := "kind"
const KEY_EXCEPTION_DETAIL := "detail"
const EXCEPTION_KEYS: Array = [KEY_EXCEPTION_KIND, KEY_EXCEPTION_DETAIL]

## An open source needs two knots to describe one span; a closed source needs
## three so a loop has three distinct corner anchors. A two-knot "loop" is
## refused as suspected truncation rather than silently accepted.
const MIN_KNOTS_OPEN := 2
const MIN_KNOTS_CLOSED := 3

## Plausible authored road width band. These are data-entry guards, not the
## design's 9-20 m authoring target: the content gate that checks the authored
## band and two-wide passage belongs to course acceptance, not to this schema.
const MIN_WIDTH_M := 1.0
const MAX_WIDTH_M := 100.0

const COORDINATE_FRAME := "Godot world units (metres), +Y up, -Z forward"

## No bank or grade limit is declared here. See the class comment.
const NO_BANK_OR_GRADE_LIMIT_NOTE := (
	"This schema enforces finiteness of bank_deg only. The design's 12% grade "
	+ "and approximately +/-12 degree bank targets and their exceptions are a "
	+ "later geometry-validation gate, not a schema limit."
)


## Stable refusal codes. Every refusal also carries a human-readable `error`
## naming the offending field and index.
enum Refusal {
	NONE = 0,
	INVALID_JSON_TEXT,
	NOT_AN_OBJECT,
	UNKNOWN_KEY,
	MISSING_KEY,
	WRONG_SCHEMA,
	BAD_COURSE_ID,
	BAD_REVISION,
	BAD_CLOSED_FLAG,
	BAD_KNOTS_ARRAY,
	TOO_FEW_KNOTS,
	BAD_KNOT,
	BAD_VECTOR,
	NONFINITE_COMPONENT,
	BAD_WIDTH,
	BAD_BANK,
	BAD_SECTIONS_ARRAY,
	BAD_SECTION,
	BAD_SECTION_ID,
	DUPLICATE_SECTION_ID,
	BAD_SURFACE_ID,
	BAD_FEATURE_TAGS,
	BAD_EXCEPTION,
	SPAN_COUNT_MISMATCH,
	DEGENERATE_ANCHOR,
	DEGENERATE_HANDLE,
}

const REFUSAL_NAMES := {
	Refusal.NONE: "none",
	Refusal.INVALID_JSON_TEXT: "invalid_json_text",
	Refusal.NOT_AN_OBJECT: "not_an_object",
	Refusal.UNKNOWN_KEY: "unknown_key",
	Refusal.MISSING_KEY: "missing_key",
	Refusal.WRONG_SCHEMA: "wrong_schema",
	Refusal.BAD_COURSE_ID: "bad_course_id",
	Refusal.BAD_REVISION: "bad_revision",
	Refusal.BAD_CLOSED_FLAG: "bad_closed_flag",
	Refusal.BAD_KNOTS_ARRAY: "bad_knots_array",
	Refusal.TOO_FEW_KNOTS: "too_few_knots",
	Refusal.BAD_KNOT: "bad_knot",
	Refusal.BAD_VECTOR: "bad_vector",
	Refusal.NONFINITE_COMPONENT: "nonfinite_component",
	Refusal.BAD_WIDTH: "bad_width",
	Refusal.BAD_BANK: "bad_bank",
	Refusal.BAD_SECTIONS_ARRAY: "bad_sections_array",
	Refusal.BAD_SECTION: "bad_section",
	Refusal.BAD_SECTION_ID: "bad_section_id",
	Refusal.DUPLICATE_SECTION_ID: "duplicate_section_id",
	Refusal.BAD_SURFACE_ID: "bad_surface_id",
	Refusal.BAD_FEATURE_TAGS: "bad_feature_tags",
	Refusal.BAD_EXCEPTION: "bad_exception",
	Refusal.SPAN_COUNT_MISMATCH: "span_count_mismatch",
	Refusal.DEGENERATE_ANCHOR: "degenerate_anchor",
	Refusal.DEGENERATE_HANDLE: "degenerate_handle",
}


# --- Immutable value objects ------------------------------------------------


## One authored Bezier knot. All members are read-only; Vector3 is a value
## type, so reading one hands the caller a copy.
class Knot extends RefCounted:
	var _anchor: Vector3
	var _handle_in: Vector3
	var _handle_out: Vector3
	var _width_m: float
	var _bank_deg: float

	var anchor: Vector3: get = _get_anchor
	var handle_in: Vector3: get = _get_handle_in
	var handle_out: Vector3: get = _get_handle_out
	var width_m: float: get = _get_width_m
	var bank_deg: float: get = _get_bank_deg


	static func make(
		p_anchor: Vector3,
		p_handle_in: Vector3,
		p_handle_out: Vector3,
		p_width_m: float,
		p_bank_deg: float
	) -> Knot:
		var knot := Knot.new()
		knot._anchor = p_anchor
		knot._handle_in = p_handle_in
		knot._handle_out = p_handle_out
		knot._width_m = p_width_m
		knot._bank_deg = p_bank_deg
		return knot


	func _get_anchor() -> Vector3:
		return _anchor


	func _get_handle_in() -> Vector3:
		return _handle_in


	func _get_handle_out() -> Vector3:
		return _handle_out


	func _get_width_m() -> float:
		return _width_m


	func _get_bank_deg() -> float:
		return _bank_deg


	static func _vector_to_array(p_vector: Vector3) -> Array:
		return [p_vector.x, p_vector.y, p_vector.z]


	func to_dictionary() -> Dictionary:
		return {
			RoadSourceDocument.KEY_ANCHOR: _vector_to_array(_anchor),
			RoadSourceDocument.KEY_HANDLE_IN: _vector_to_array(_handle_in),
			RoadSourceDocument.KEY_HANDLE_OUT: _vector_to_array(_handle_out),
			RoadSourceDocument.KEY_WIDTH_M: _width_m,
			RoadSourceDocument.KEY_BANK_DEG: _bank_deg,
		}


## One ordered span record: the surface and authored metadata that later
## sampling must use instead of inventing values.
class Section extends RefCounted:
	var _section_id: String
	var _surface_id: String
	var _feature_tags: Array[String] = []
	var _exception: Dictionary = {}
	var _has_exception := false

	var section_id: String: get = _get_section_id
	var surface_id: String: get = _get_surface_id
	var feature_tags: Array[String]: get = _get_feature_tags
	var exception: Dictionary: get = _get_exception


	static func make(
		p_section_id: String,
		p_surface_id: String,
		p_feature_tags: Array[String],
		p_exception: Dictionary,
		p_has_exception: bool
	) -> Section:
		var section := Section.new()
		section._section_id = p_section_id
		section._surface_id = p_surface_id
		section._feature_tags = p_feature_tags.duplicate()
		section._feature_tags.make_read_only()
		section._exception = p_exception.duplicate(true)
		section._exception.make_read_only()
		section._has_exception = p_has_exception
		return section


	func _get_section_id() -> String:
		return _section_id


	func _get_surface_id() -> String:
		return _surface_id


	## A fresh mutable array: the stored tag list is read-only and never leaked.
	func _get_feature_tags() -> Array[String]:
		var tags: Array[String] = []
		for tag in _feature_tags:
			tags.append(tag)
		return tags


	## A fresh mutable deep copy; empty when the record carries no exception.
	func _get_exception() -> Dictionary:
		if not _has_exception:
			return {}
		return _exception.duplicate(true)


	func has_exception() -> bool:
		return _has_exception


	func to_dictionary() -> Dictionary:
		var out := {
			RoadSourceDocument.KEY_SECTION_ID: _section_id,
			RoadSourceDocument.KEY_SURFACE_ID: _surface_id,
		}
		if not _feature_tags.is_empty():
			var tags := []
			for tag in _feature_tags:
				tags.append(tag)
			out[RoadSourceDocument.KEY_FEATURE_TAGS] = tags
		if _has_exception:
			var exception := {RoadSourceDocument.KEY_EXCEPTION_KIND: str(_exception.get(
				RoadSourceDocument.KEY_EXCEPTION_KIND, ""
			))}
			if _exception.has(RoadSourceDocument.KEY_EXCEPTION_DETAIL):
				exception[RoadSourceDocument.KEY_EXCEPTION_DETAIL] = str(
					_exception.get(RoadSourceDocument.KEY_EXCEPTION_DETAIL, "")
				)
			out[RoadSourceDocument.KEY_EXCEPTION] = exception
		return out


## One validated Bezier span: the two knots it joins plus its ordered section
## record. Control points are P0 = start anchor, P1 = start handle_out,
## P2 = end handle_in, P3 = end anchor.
class Span extends RefCounted:
	var _index: int
	var _start_knot: Knot
	var _end_knot: Knot
	var _start_knot_index: int
	var _end_knot_index: int
	var _section: Section

	var index: int: get = _get_index
	var start_knot: Knot: get = _get_start_knot
	var end_knot: Knot: get = _get_end_knot
	var start_knot_index: int: get = _get_start_knot_index
	var end_knot_index: int: get = _get_end_knot_index
	var section: Section: get = _get_section


	static func make(
		p_index: int,
		p_start_knot: Knot,
		p_end_knot: Knot,
		p_start_knot_index: int,
		p_end_knot_index: int,
		p_section: Section
	) -> Span:
		var span := Span.new()
		span._index = p_index
		span._start_knot = p_start_knot
		span._end_knot = p_end_knot
		span._start_knot_index = p_start_knot_index
		span._end_knot_index = p_end_knot_index
		span._section = p_section
		return span


	func _get_index() -> int:
		return _index


	func _get_start_knot() -> Knot:
		return _start_knot


	func _get_end_knot() -> Knot:
		return _end_knot


	func _get_start_knot_index() -> int:
		return _start_knot_index


	func _get_end_knot_index() -> int:
		return _end_knot_index


	func _get_section() -> Section:
		return _section


	func control_points() -> Array[Vector3]:
		return [
			_start_knot.anchor,
			_start_knot.handle_out,
			_end_knot.handle_in,
			_end_knot.anchor,
		]


	static func _vector_to_array(p_vector: Vector3) -> Array:
		return [p_vector.x, p_vector.y, p_vector.z]


# --- Document ----------------------------------------------------------------


var _course_id := ""
var _revision := ""
var _closed := false
var _knots: Array = []
var _sections: Array = []
var _spans: Array = []

var schema: String: get = _get_schema
var course_id: String: get = _get_course_id
var revision: String: get = _get_revision
var closed: bool: get = _get_closed
var knot_count: int: get = _get_knot_count
var section_count: int: get = _get_section_count
var span_count: int: get = _get_span_count
var knots: Array: get = _get_knots
var sections: Array: get = _get_sections
var spans: Array: get = _get_spans


func _get_schema() -> String:
	return SCHEMA


func _get_course_id() -> String:
	return _course_id


func _get_revision() -> String:
	return _revision


func _get_closed() -> bool:
	return _closed


func _get_knot_count() -> int:
	return _knots.size()


func _get_section_count() -> int:
	return _sections.size()


func _get_span_count() -> int:
	return _spans.size()


## Fresh array of the immutable knot objects; mutating the array cannot reach
## the stored one.
func _get_knots() -> Array:
	var out := []
	out.assign(_knots)
	return out


func _get_sections() -> Array:
	var out := []
	out.assign(_sections)
	return out


func _get_spans() -> Array:
	var out := []
	out.assign(_spans)
	return out


func knot(p_index: int) -> Knot:
	if p_index < 0 or p_index >= _knots.size():
		return null
	return _knots[p_index]


func section(p_index: int) -> Section:
	if p_index < 0 or p_index >= _sections.size():
		return null
	return _sections[p_index]


func span(p_index: int) -> Span:
	if p_index < 0 or p_index >= _spans.size():
		return null
	return _spans[p_index]


## Number of Bezier spans an authored knot count implies for the given closure
## semantics: N-1 for an open source, N for a closed one.
static func expected_span_count(p_knot_count: int, p_closed: bool) -> int:
	if p_closed:
		return p_knot_count
	return p_knot_count - 1


## Canonical re-serialization. Parsing this output again yields an identical
## document; it is a fresh mutable structure.
func to_dictionary() -> Dictionary:
	var knots_out := []
	for knot_object in _knots:
		knots_out.append(knot_object.to_dictionary())
	var sections_out := []
	for section_object in _sections:
		sections_out.append(section_object.to_dictionary())
	return {
		KEY_SCHEMA: SCHEMA,
		KEY_COURSE_ID: _course_id,
		KEY_REVISION: _revision,
		KEY_CLOSED: _closed,
		KEY_KNOTS: knots_out,
		KEY_SECTIONS: sections_out,
	}


## Flat, report-friendly view of the validated document. Records the authored
## values verbatim and states that no bank or grade limit is enforced here.
func summary() -> Dictionary:
	var knots_out := []
	var min_width := INF
	var max_width := -INF
	var min_bank := INF
	var max_bank := -INF
	for index in range(_knots.size()):
		var knot_object: Knot = _knots[index]
		min_width = minf(min_width, knot_object.width_m)
		max_width = maxf(max_width, knot_object.width_m)
		min_bank = minf(min_bank, knot_object.bank_deg)
		max_bank = maxf(max_bank, knot_object.bank_deg)
		knots_out.append({
			"index": index,
			"anchor": Span._vector_to_array(knot_object.anchor),
			"handle_in": Span._vector_to_array(knot_object.handle_in),
			"handle_out": Span._vector_to_array(knot_object.handle_out),
			"width_m": knot_object.width_m,
			"bank_deg": knot_object.bank_deg,
		})
	var spans_out := []
	for index in range(_spans.size()):
		var authored_span: Span = _spans[index]
		var authored_section: Section = authored_span.section
		spans_out.append({
			"index": index,
			"start_knot_index": authored_span.start_knot_index,
			"end_knot_index": authored_span.end_knot_index,
			"section_id": authored_section.section_id,
			"surface_id": authored_section.surface_id,
			"feature_tags": authored_section.feature_tags,
			"exception": authored_section.exception,
		})
	return {
		"schema": SCHEMA,
		"course_id": _course_id,
		"revision": _revision,
		"closed": _closed,
		"knot_count": _knots.size(),
		"section_count": _sections.size(),
		"span_count": _spans.size(),
		"span_rule": "open: N-1 spans" if not _closed else "closed: N spans",
		"coordinate_frame": COORDINATE_FRAME,
		"knots": knots_out,
		"spans": spans_out,
		"width_range_m": [min_width, max_width],
		"bank_range_deg": [min_bank, max_bank],
		"bank_grade_limit_note": NO_BANK_OR_GRADE_LIMIT_NOTE,
	}


# --- Parsing -----------------------------------------------------------------


## Strict pure entry point. `p_source` is normally a JSON object (see
## `parse_json`); any other shape is refused. On success returns
## {"ok": true, "code": 0, "error": "", "document": RoadSourceDocument}.
## On failure returns {"ok": false, "code": <Refusal>, "error": "...",
## "document": null} and never defaults a malformed field.
static func parse_document(p_source: Variant) -> Dictionary:
	if typeof(p_source) != TYPE_DICTIONARY:
		return _refuse(
			Refusal.NOT_AN_OBJECT,
			"road source must be a JSON object, got %s" % type_string(typeof(p_source))
		)
	var source: Dictionary = p_source

	for key in source:
		if not DOCUMENT_KEYS.has(key):
			return _refuse(
				Refusal.UNKNOWN_KEY,
				"unknown document key '%s'; expected exactly %s" % [str(key), str(DOCUMENT_KEYS)]
			)
	for required in DOCUMENT_KEYS:
		if not source.has(required):
			return _refuse(Refusal.MISSING_KEY, "missing document key '%s'" % str(required))

	if typeof(source[KEY_SCHEMA]) != TYPE_STRING:
		return _refuse(Refusal.WRONG_SCHEMA, "schema must be a string")
	if str(source[KEY_SCHEMA]) != SCHEMA:
		return _refuse(
			Refusal.WRONG_SCHEMA,
			"schema '%s' is not '%s'" % [str(source[KEY_SCHEMA]), SCHEMA]
		)

	var course_id := str(source[KEY_COURSE_ID])
	if typeof(source[KEY_COURSE_ID]) != TYPE_STRING or course_id.strip_edges().is_empty():
		return _refuse(Refusal.BAD_COURSE_ID, "course_id must be a non-empty string")

	var revision := str(source[KEY_REVISION])
	if typeof(source[KEY_REVISION]) != TYPE_STRING or revision.strip_edges().is_empty():
		return _refuse(Refusal.BAD_REVISION, "revision must be a non-empty string")

	if typeof(source[KEY_CLOSED]) != TYPE_BOOL:
		return _refuse(Refusal.BAD_CLOSED_FLAG, "closed must be a JSON boolean")
	var closed := bool(source[KEY_CLOSED])

	if typeof(source[KEY_KNOTS]) != TYPE_ARRAY:
		return _refuse(Refusal.BAD_KNOTS_ARRAY, "knots must be an array")
	var knot_entries: Array = source[KEY_KNOTS]
	var minimum_knots := MIN_KNOTS_CLOSED if closed else MIN_KNOTS_OPEN
	if knot_entries.size() < minimum_knots:
		return _refuse(
			Refusal.TOO_FEW_KNOTS,
			"a %s source needs at least %d knots, got %d"
				% ["closed" if closed else "open", minimum_knots, knot_entries.size()]
		)

	var knots: Array = []
	for index in range(knot_entries.size()):
		var parsed_knot := _parse_knot(knot_entries[index], index)
		if not bool(parsed_knot["ok"]):
			return parsed_knot
		knots.append(parsed_knot["knot"])

	if typeof(source[KEY_SECTIONS]) != TYPE_ARRAY:
		return _refuse(Refusal.BAD_SECTIONS_ARRAY, "sections must be an array")
	var section_entries: Array = source[KEY_SECTIONS]
	var expected_spans := expected_span_count(knots.size(), closed)
	if section_entries.size() != expected_spans:
		return _refuse(
			Refusal.SPAN_COUNT_MISMATCH,
			"a %s source with %d knots needs exactly %d ordered section records, got %d"
				% ["closed" if closed else "open", knots.size(), expected_spans, section_entries.size()]
		)

	var sections: Array = []
	var seen_ids := {}
	for index in range(section_entries.size()):
		var parsed_section := _parse_section(section_entries[index], index)
		if not bool(parsed_section["ok"]):
			return parsed_section
		var section_id := str(parsed_section["section"].section_id)
		if seen_ids.has(section_id):
			return _refuse(
				Refusal.DUPLICATE_SECTION_ID,
				"section_id '%s' repeats at records %d and %d; section IDs must be stable and unique"
					% [section_id, int(seen_ids[section_id]), index]
			)
		seen_ids[section_id] = index
		sections.append(parsed_section["section"])

	var geometry_error := _validate_span_geometry(knots, closed)
	if not geometry_error.is_empty():
		return geometry_error

	var document := RoadSourceDocument.new()
	document._course_id = course_id
	document._revision = revision
	document._closed = closed
	document._knots = knots
	document._knots.make_read_only()
	document._sections = sections
	document._sections.make_read_only()
	document._spans = _build_spans(knots, sections, closed)
	document._spans.make_read_only()
	return {"ok": true, "code": Refusal.NONE, "error": "", "document": document}


## JSON text convenience wrapper around `parse_document`. Invalid JSON, and
## the non-finite literals some writers emit, are refused instead of parsed.
static func parse_json(p_text: Variant) -> Dictionary:
	if typeof(p_text) != TYPE_STRING:
		return _refuse(Refusal.INVALID_JSON_TEXT, "JSON text must be a string")
	var json := JSON.new()
	if json.parse(str(p_text)) != OK:
		return _refuse(
			Refusal.INVALID_JSON_TEXT,
			"text is not valid JSON at line %d: %s (NaN/Infinity literals are not accepted)"
				% [json.get_error_line(), json.get_error_message()]
		)
	return parse_document(json.data)


static func refusal_name(p_code: int) -> String:
	if REFUSAL_NAMES.has(p_code):
		return str(REFUSAL_NAMES[p_code])
	return "unknown_code_%d" % p_code


static func _build_spans(p_knots: Array, p_sections: Array, p_closed: bool) -> Array:
	var spans := []
	for index in range(p_sections.size()):
		var end_index := index + 1
		if p_closed and index == p_knots.size() - 1:
			end_index = 0
		spans.append(Span.make(
			index,
			p_knots[index],
			p_knots[end_index],
			index,
			end_index,
			p_sections[index]
		))
	return spans


## Closure-aware degeneracy check. "Coincident" means exactly equal: a span
## whose two anchors are the same point, or whose control point sits exactly on
## its own knot anchor, has no usable tangent and is refused. Near-coincident
## anchors and all curvature, grade, bank and self-intersection limits are the
## later geometry gate, not this schema.
static func _validate_span_geometry(p_knots: Array, p_closed: bool) -> Dictionary:
	var count := p_knots.size()
	for index in range(count):
		var end_index := index + 1
		if p_closed and index == count - 1:
			end_index = 0
		elif not p_closed and index == count - 1:
			continue
		var start: Knot = p_knots[index]
		var end: Knot = p_knots[end_index]
		if start.anchor == end.anchor:
			return _refuse(
				Refusal.DEGENERATE_ANCHOR,
				"span %d joins knots %d and %d at the same anchor %s"
					% [index, index, end_index, str(start.anchor)]
			)
		if start.handle_out == start.anchor:
			return _refuse(
				Refusal.DEGENERATE_HANDLE,
				"knot %d handle_out coincides with its own anchor; the span has no start tangent"
					% index
			)
		if end.handle_in == end.anchor:
			return _refuse(
				Refusal.DEGENERATE_HANDLE,
				"knot %d handle_in coincides with its own anchor; the span has no end tangent"
					% end_index
			)
	return {}


static func _parse_knot(p_entry: Variant, p_index: int) -> Dictionary:
	var label := "knots[%d]" % p_index
	if typeof(p_entry) != TYPE_DICTIONARY:
		return _refuse(
			Refusal.BAD_KNOT, "%s must be an object, got %s" % [label, type_string(typeof(p_entry))]
		)
	var entry: Dictionary = p_entry
	for key in entry:
		if not KNOT_KEYS.has(key):
			return _refuse(
				Refusal.BAD_KNOT,
				"%s has unknown key '%s'; expected exactly %s" % [label, str(key), str(KNOT_KEYS)]
			)
	for required in KNOT_KEYS:
		if not entry.has(required):
			return _refuse(Refusal.BAD_KNOT, "%s is missing '%s'" % [label, str(required)])

	var anchor := _read_vector(entry[KEY_ANCHOR], "%s.anchor" % label)
	if not bool(anchor["ok"]):
		return anchor
	var handle_in := _read_vector(entry[KEY_HANDLE_IN], "%s.handle_in" % label)
	if not bool(handle_in["ok"]):
		return handle_in
	var handle_out := _read_vector(entry[KEY_HANDLE_OUT], "%s.handle_out" % label)
	if not bool(handle_out["ok"]):
		return handle_out

	var width := _read_number(entry[KEY_WIDTH_M])
	if not is_finite(width):
		return _refuse(Refusal.BAD_WIDTH, "%s.width_m must be a finite number" % label)
	if width < MIN_WIDTH_M or width > MAX_WIDTH_M:
		return _refuse(
			Refusal.BAD_WIDTH,
			"%s.width_m %.6f is outside the plausible authored band [%.6f, %.6f]"
				% [label, width, MIN_WIDTH_M, MAX_WIDTH_M]
		)

	## Finiteness only: no universal bank limit is encoded in this slice.
	var bank := _read_number(entry[KEY_BANK_DEG])
	if not is_finite(bank):
		return _refuse(Refusal.BAD_BANK, "%s.bank_deg must be a finite number" % label)

	return {
		"ok": true,
		"code": Refusal.NONE,
		"error": "",
		"document": null,
		"knot": Knot.make(
			anchor["value"], handle_in["value"], handle_out["value"], width, bank
		),
	}


static func _parse_section(p_entry: Variant, p_index: int) -> Dictionary:
	var label := "sections[%d]" % p_index
	if typeof(p_entry) != TYPE_DICTIONARY:
		return _refuse(
			Refusal.BAD_SECTION, "%s must be an object, got %s" % [label, type_string(typeof(p_entry))]
		)
	var entry: Dictionary = p_entry
	for key in entry:
		if not SECTION_KEYS.has(key):
			return _refuse(
				Refusal.BAD_SECTION,
				"%s has unknown key '%s'; expected a subset of %s"
					% [label, str(key), str(SECTION_KEYS)]
			)
	for required in [KEY_SECTION_ID, KEY_SURFACE_ID]:
		if not entry.has(required):
			return _refuse(Refusal.BAD_SECTION, "%s is missing '%s'" % [label, str(required)])

	if typeof(entry[KEY_SECTION_ID]) != TYPE_STRING:
		return _refuse(Refusal.BAD_SECTION_ID, "%s.section_id must be a string" % label)
	var section_id := str(entry[KEY_SECTION_ID])
	if section_id.strip_edges().is_empty():
		return _refuse(Refusal.BAD_SECTION_ID, "%s.section_id must be non-empty" % label)

	if typeof(entry[KEY_SURFACE_ID]) != TYPE_STRING:
		return _refuse(Refusal.BAD_SURFACE_ID, "%s.surface_id must be a string" % label)
	var surface_id := str(entry[KEY_SURFACE_ID])
	if surface_id.strip_edges().is_empty():
		return _refuse(Refusal.BAD_SURFACE_ID, "%s.surface_id must be non-empty" % label)

	var tags: Array[String] = []
	if entry.has(KEY_FEATURE_TAGS):
		if typeof(entry[KEY_FEATURE_TAGS]) != TYPE_ARRAY:
			return _refuse(Refusal.BAD_FEATURE_TAGS, "%s.feature_tags must be an array" % label)
		for tag in entry[KEY_FEATURE_TAGS]:
			if typeof(tag) != TYPE_STRING:
				return _refuse(Refusal.BAD_FEATURE_TAGS, "%s.feature_tags entries must be strings" % label)
			if str(tag).strip_edges().is_empty():
				return _refuse(Refusal.BAD_FEATURE_TAGS, "%s.feature_tags entries must be non-empty" % label)
			if tags.has(str(tag)):
				return _refuse(
					Refusal.BAD_FEATURE_TAGS, "%s.feature_tags repeats '%s'" % [label, str(tag)]
				)
			tags.append(str(tag))

	var exception := {}
	var has_exception := false
	if entry.has(KEY_EXCEPTION):
		if typeof(entry[KEY_EXCEPTION]) != TYPE_DICTIONARY:
			return _refuse(Refusal.BAD_EXCEPTION, "%s.exception must be an object" % label)
		var raw_exception: Dictionary = entry[KEY_EXCEPTION]
		for key in raw_exception:
			if not EXCEPTION_KEYS.has(key):
				return _refuse(
					Refusal.BAD_EXCEPTION,
					"%s.exception has unknown key '%s'; expected a subset of %s"
						% [label, str(key), str(EXCEPTION_KEYS)]
				)
		if not raw_exception.has(KEY_EXCEPTION_KIND):
			return _refuse(Refusal.BAD_EXCEPTION, "%s.exception is missing 'kind'" % label)
		if typeof(raw_exception[KEY_EXCEPTION_KIND]) != TYPE_STRING:
			return _refuse(Refusal.BAD_EXCEPTION, "%s.exception.kind must be a string" % label)
		if str(raw_exception[KEY_EXCEPTION_KIND]).strip_edges().is_empty():
			return _refuse(Refusal.BAD_EXCEPTION, "%s.exception.kind must be non-empty" % label)
		if raw_exception.has(KEY_EXCEPTION_DETAIL):
			if typeof(raw_exception[KEY_EXCEPTION_DETAIL]) != TYPE_STRING:
				return _refuse(Refusal.BAD_EXCEPTION, "%s.exception.detail must be a string" % label)
		exception = raw_exception.duplicate(true)
		has_exception = true

	return {
		"ok": true,
		"code": Refusal.NONE,
		"error": "",
		"document": null,
		"section": Section.make(section_id, surface_id, tags, exception, has_exception),
	}


## Reads a 3-component finite vector. Arrays only: a Vector3 value cannot
## round-trip through the JSON contract, so it is refused with that reason.
static func _read_vector(p_value: Variant, p_label: String) -> Dictionary:
	if typeof(p_value) != TYPE_ARRAY:
		return _refuse(
			Refusal.BAD_VECTOR,
			"%s must be an array of three finite numbers, got %s" % [p_label, type_string(typeof(p_value))]
		)
	var components: Array = p_value
	if components.size() != 3:
		return _refuse(
			Refusal.BAD_VECTOR, "%s must have exactly 3 components, got %d" % [p_label, components.size()]
		)
	var values: Array = []
	for axis in range(3):
		var component := _read_number(components[axis])
		if not is_finite(component):
			return _refuse(
				Refusal.NONFINITE_COMPONENT,
				"%s[%d] is not a finite number (%s)" % [p_label, axis, str(components[axis])]
			)
		values.append(component)
	return {
		"ok": true,
		"code": Refusal.NONE,
		"error": "",
		"document": null,
		"value": Vector3(values[0], values[1], values[2]),
	}


## Numeric read that accepts JSON floats and GDScript ints but never booleans.
## Returns NAN for anything else; callers classify the refusal.
static func _read_number(p_value: Variant) -> float:
	if typeof(p_value) == TYPE_FLOAT:
		return float(p_value)
	if typeof(p_value) == TYPE_INT:
		return float(p_value)
	return NAN


static func _refuse(p_code: int, p_error: String) -> Dictionary:
	return {"ok": false, "code": p_code, "error": p_error, "document": null}
