class_name RoadArcSampler
extends RefCounted

const RoadSourceDocument := preload("res://src/course/road_source.gd")

## Deterministic arc-length sampling table for a validated RoadSourceDocument.
##
## This is a bounded M2 road-geometry slice only. It consumes the public span,
## knot, section and metadata accessors of `roadstorm.road_source.v1`; it does
## not mutate or revalidate the authored source, build transported frames,
## meshes, collision, gates, course art or gameplay, and it does not certify the
## design's course-quality, grade or bank targets.
##
## Output policy:
##   * stations are nominal metres along the chained spans and are strictly
##     increasing, including exact course start and end samples;
##   * spans own the half-open station interval [start_s, end_s), so a station
##     exactly on an interior knot boundary uses the following span and its
##     section/surface metadata;
##   * the final course end is the one exception and uses the final span at
##     t=1;
##   * a closed course emits an ordered seam pair: s=0 is
##     `closed_seam_start` from span 0 at t=0 and s=total_length is
##     `closed_seam_end` from the final span at t=1;
##   * width and bank are linear in Bezier parameter t inside each span. The
##     clamped parameter keeps them continuous and free of overshoot between
##     the two authored knot values; it does not make them linear in distance.
##
## Numerical method. Each cubic span's speed |dB/dt| is evaluated with scalar
## float arithmetic from the stored Vector3 control-point components and is
## integrated by adaptive recursive Simpson quadrature in a fixed left-to-right
## order. Scalar floats avoid the float32 Vector3 roundoff that a large world
## translation would otherwise introduce into length calculations. Every
## candidate leaf must additionally lie inside an independent geometric
## bracket for the same Bezier subsegment: the summed chord lengths lower-bound
## the true arc length and the summed subsegment control-polygon lengths
## upper-bound it. A leaf is accepted only when its extrapolated Simpson value
## lies inside that bracket (within an explicit IEEE-754 roundoff allowance)
## and its reported error, the maximum distance from the value to either
## bracket bound plus the leaf's relative roundoff allowance, is within the
## local tolerance; that local tolerance halves at each subdivision, so an
## accepted span's summed reported error stays within the requested per-span
## tolerance. The per-span reported error is the sum of those padded leaf
## estimates, not the Richardson extrapolation; a leaf whose bracket is
## nonfinite or inverted beyond roundoff is refused, as is a leaf that cannot
## satisfy the padded condition before the depth or node cap. Every leaf
## allowance is relative to a bracket that encloses its subarc, so the reported
## span error cannot fall below ARC_LENGTH_BOUND_RELATIVE_ROUNDOFF times the
## true span length, and therefore not below that fraction of the endpoint
## chord. A request below that fraction is refused as precision_unreachable
## instead of being reported as success. This floor bounds the conservative
## reported estimate, not a proven forward error.
## Arc-length inversion uses the adaptive table for a bracket, then bounded
## Newton steps with bisection fallback and fixed Richardson-refined composite
## Simpson quadrature. Tolerances and caps are explicit. Options may tighten
## the defaults but cannot loosen them; hitting a cap is a structured refusal,
## not a silent approximation-quality reduction or partial table.

const RESULT_SCHEMA := "roadstorm.road_arc_table.v1"

const DEFAULT_ARC_LENGTH_TOLERANCE_M := 0.001
const DEFAULT_MAX_SUBDIVISION_DEPTH := 20
const DEFAULT_MAX_TABLE_NODES_PER_SPAN := 4097
const DEFAULT_MAX_OUTPUT_SAMPLES := 20000

const OPTION_ARC_LENGTH_TOLERANCE_M := "arc_length_tolerance_m"
const OPTION_MAX_SUBDIVISION_DEPTH := "max_subdivision_depth"
const OPTION_MAX_TABLE_NODES_PER_SPAN := "max_table_nodes_per_span"
const OPTION_MAX_OUTPUT_SAMPLES := "max_output_samples"
const OPTION_KEYS: Array = [
	OPTION_ARC_LENGTH_TOLERANCE_M,
	OPTION_MAX_SUBDIVISION_DEPTH,
	OPTION_MAX_TABLE_NODES_PER_SPAN,
	OPTION_MAX_OUTPUT_SAMPLES,
]

const ARC_LENGTH_BOUND_PIECES := 8
## Relative IEEE-754 roundoff allowance used to compare the geometric bracket
## with the extrapolated Simpson value. The true subarc length always lies
## between the summed chord and control-polygon bounds, so a lower bound above
## the upper bound by more than this allowance is an inconsistent derived state
## rather than roundoff. The allowance is far below the authored tolerance and
## is included in each accepted leaf's stored error bound.
const ARC_LENGTH_BOUND_RELATIVE_ROUNDOFF := 1.0e-12
const INVERSION_COARSE_PANELS := 8
const INVERSION_FINE_PANELS := 16
const INVERSION_MAX_ITERATIONS := 16
const INVERSION_RESIDUAL_FRACTION := 0.1
const INVERSION_CONVERGENCE_FRACTION := 0.05
const DERIVATIVE_ROOT_PARAMETER_TOLERANCE := 1.0e-12
const DERIVATIVE_DISCRIMINANT_EPSILON := 1.0e-7
const DEGENERATE_SPEED_RELATIVE_EPSILON := 1.0e-7
const VECTOR3_FINITE_COMPONENT_LIMIT := 3.4028234663852886e38

const SECTION_BOUNDARY_POLICY := (
	"each span owns [start_s,end_s); an exact interior knot station uses the "
	+ "following span, while the final course end uses the final span at t=1"
)
const CLOSED_SEAM_POLICY := (
	"closed sources emit both ordered seam endpoints: s=0 closed_seam_start "
	+ "from span 0 at t=0, and s=total_length closed_seam_end from the final "
	+ "span at t=1"
)

## Stable refusal codes. Every refusal also carries `code_name`, a readable
## `error`, a machine-readable `diagnostic` dictionary, and `table:null`.
enum Refusal {
	NONE = 0,
	BAD_DOCUMENT,
	BAD_SPACING,
	BAD_OPTIONS,
	NONFINITE_DERIVED_STATE,
	DEGENERATE_DERIVATIVE,
	SUBDIVISION_CAP_EXCEEDED,
	TABLE_NODE_CAP_EXCEEDED,
	SAMPLE_CAP_EXCEEDED,
	INVERSION_FAILED,
	TABLE_INCONSISTENT,
	PRECISION_UNREACHABLE,
}

const REFUSAL_NAMES := {
	Refusal.NONE: "none",
	Refusal.BAD_DOCUMENT: "bad_document",
	Refusal.BAD_SPACING: "bad_spacing",
	Refusal.BAD_OPTIONS: "bad_options",
	Refusal.NONFINITE_DERIVED_STATE: "nonfinite_derived_state",
	Refusal.DEGENERATE_DERIVATIVE: "degenerate_derivative",
	Refusal.SUBDIVISION_CAP_EXCEEDED: "subdivision_cap_exceeded",
	Refusal.TABLE_NODE_CAP_EXCEEDED: "table_node_cap_exceeded",
	Refusal.SAMPLE_CAP_EXCEEDED: "sample_cap_exceeded",
	Refusal.INVERSION_FAILED: "inversion_failed",
	Refusal.TABLE_INCONSISTENT: "table_inconsistent",
	Refusal.PRECISION_UNREACHABLE: "precision_unreachable",
}


# --- Immutable table view ----------------------------------------------------


## A successful immutable-ish table. Container accessors return deep mutable
## copies, so altering them cannot rewrite the stored table. As with the source
## contract, GDScript's Object.set private-member escape is a documented
## residual rather than part of the API.
class Table extends RefCounted:
	var _course_id := ""
	var _revision := ""
	var _closed := false
	var _sample_spacing_m := 0.0
	var _total_length_m := 0.0
	var _length_error_estimate_m := 0.0
	var _max_inversion_error_estimate_m := 0.0
	var _max_inversion_residual_m := 0.0
	var _options: Dictionary = {}
	var _span_tables: Array = []
	var _samples: Array = []

	var schema: String: get = _get_schema
	var course_id: String: get = _get_course_id
	var revision: String: get = _get_revision
	var closed: bool: get = _get_closed
	var sample_spacing_m: float: get = _get_sample_spacing_m
	var total_length_m: float: get = _get_total_length_m
	var length_error_estimate_m: float: get = _get_length_error_estimate_m
	var max_inversion_error_estimate_m: float: get = _get_max_inversion_error_estimate_m
	var max_inversion_residual_m: float: get = _get_max_inversion_residual_m
	var span_count: int: get = _get_span_count
	var sample_count: int: get = _get_sample_count
	var options: Dictionary: get = _get_options
	var span_tables: Array: get = _get_span_tables
	var samples: Array: get = _get_samples
	var section_boundary_policy: String: get = _get_section_boundary_policy
	var closed_seam_policy: String: get = _get_closed_seam_policy


	static func make(
		p_course_id: String,
		p_revision: String,
		p_closed: bool,
		p_sample_spacing_m: float,
		p_total_length_m: float,
		p_length_error_estimate_m: float,
		p_max_inversion_error_estimate_m: float,
		p_max_inversion_residual_m: float,
		p_options: Dictionary,
		p_span_tables: Array,
		p_samples: Array
	) -> Table:
		var table := Table.new()
		table._course_id = p_course_id
		table._revision = p_revision
		table._closed = p_closed
		table._sample_spacing_m = p_sample_spacing_m
		table._total_length_m = p_total_length_m
		table._length_error_estimate_m = p_length_error_estimate_m
		table._max_inversion_error_estimate_m = p_max_inversion_error_estimate_m
		table._max_inversion_residual_m = p_max_inversion_residual_m
		table._options = p_options.duplicate(true)
		table._span_tables = p_span_tables.duplicate(true)
		table._samples = p_samples.duplicate(true)
		return table


	func _get_schema() -> String:
		return RESULT_SCHEMA


	func _get_course_id() -> String:
		return _course_id


	func _get_revision() -> String:
		return _revision


	func _get_closed() -> bool:
		return _closed


	func _get_sample_spacing_m() -> float:
		return _sample_spacing_m


	func _get_total_length_m() -> float:
		return _total_length_m


	func _get_length_error_estimate_m() -> float:
		return _length_error_estimate_m


	func _get_max_inversion_error_estimate_m() -> float:
		return _max_inversion_error_estimate_m


	func _get_max_inversion_residual_m() -> float:
		return _max_inversion_residual_m


	func _get_span_count() -> int:
		return _span_tables.size()


	func _get_sample_count() -> int:
		return _samples.size()


	func _get_options() -> Dictionary:
		return _options.duplicate(true)


	func _get_span_tables() -> Array:
		return _span_tables.duplicate(true)


	func _get_samples() -> Array:
		return _samples.duplicate(true)


	func _get_section_boundary_policy() -> String:
		return SECTION_BOUNDARY_POLICY


	func _get_closed_seam_policy() -> String:
		if not _closed:
			return ""
		return CLOSED_SEAM_POLICY


	func span_table(p_index: int) -> Dictionary:
		if p_index < 0 or p_index >= _span_tables.size():
			return {}
		return (_span_tables[p_index] as Dictionary).duplicate(true)


	func sample(p_index: int) -> Dictionary:
		if p_index < 0 or p_index >= _samples.size():
			return {}
		return (_samples[p_index] as Dictionary).duplicate(true)


	func closed_seam() -> Dictionary:
		if not _closed or _samples.is_empty():
			return {}
		return {
			"policy": CLOSED_SEAM_POLICY,
			"start_sample_index": 0,
			"end_sample_index": _samples.size() - 1,
			"start_s": 0.0,
			"end_s": _total_length_m,
		}


	func summary() -> Dictionary:
		var max_span_error := 0.0
		var total_nodes := 0
		var total_leaves := 0
		for span_record in _span_tables:
			max_span_error = maxf(
				max_span_error, float((span_record as Dictionary)["length_error_estimate_m"])
			)
			total_nodes += int((span_record as Dictionary)["table_node_count"])
			total_leaves += int((span_record as Dictionary)["integration_leaf_count"])
		return {
			"schema": RESULT_SCHEMA,
			"course_id": _course_id,
			"revision": _revision,
			"closed": _closed,
			"span_count": _span_tables.size(),
			"sample_count": _samples.size(),
			"sample_spacing_m": _sample_spacing_m,
			"total_length_m": _total_length_m,
			"length_error_estimate_m": _length_error_estimate_m,
			"max_span_length_error_estimate_m": max_span_error,
			"max_inversion_error_estimate_m": _max_inversion_error_estimate_m,
			"max_inversion_residual_m": _max_inversion_residual_m,
			"integration_leaf_count": total_leaves,
			"table_node_count": total_nodes,
			"options": _options.duplicate(true),
			"section_boundary_policy": SECTION_BOUNDARY_POLICY,
			"closed_seam_policy": CLOSED_SEAM_POLICY if _closed else "",
		}


	func to_dictionary() -> Dictionary:
		return {
			"schema": RESULT_SCHEMA,
			"course_id": _course_id,
			"revision": _revision,
			"closed": _closed,
			"sample_spacing_m": _sample_spacing_m,
			"total_length_m": _total_length_m,
			"length_error_estimate_m": _length_error_estimate_m,
			"max_inversion_error_estimate_m": _max_inversion_error_estimate_m,
			"max_inversion_residual_m": _max_inversion_residual_m,
			"options": _options.duplicate(true),
			"section_boundary_policy": SECTION_BOUNDARY_POLICY,
			"closed_seam_policy": CLOSED_SEAM_POLICY if _closed else "",
			"span_tables": _span_tables.duplicate(true),
			"samples": _samples.duplicate(true),
		}


# --- Public construction -----------------------------------------------------


## Builds a uniform-by-distance sample table. `p_spacing_m` is the nominal
## spacing in metres; the final interval is shorter unless the length is an
## exact multiple. On success returns
## {"ok":true,"code":0,"code_name":"none","error":"","diagnostic":{},"table":Table}.
## On failure no partial table is returned.
static func build_uniform_table(
	p_document: Variant,
	p_spacing_m: Variant,
	p_options: Variant = {}
) -> Dictionary:
	if typeof(p_document) != TYPE_OBJECT or not (p_document is RoadSourceDocument):
		return _refuse(
			Refusal.BAD_DOCUMENT,
			"document must be a validated RoadSourceDocument",
			{"received_type": type_string(typeof(p_document))}
		)
	var document: RoadSourceDocument = p_document

	var spacing_result := _read_positive_finite_number(p_spacing_m, "spacing_m")
	if not bool(spacing_result["ok"]):
		return _refuse(
			Refusal.BAD_SPACING,
			"spacing_m must be a positive finite number of metres",
			{"received": str(p_spacing_m)}
		)
	var spacing := float(spacing_result["value"])

	var options_result := _resolve_options(p_options)
	if not bool(options_result["ok"]):
		return options_result["refusal"]
	var options: Dictionary = options_result["options"]

	var authored_spans := document.spans
	if authored_spans.size() != document.span_count or authored_spans.is_empty():
		return _refuse(
			Refusal.BAD_DOCUMENT,
			"document exposes an inconsistent or empty ordered span array",
			{
				"span_count_property": document.span_count,
				"span_array_size": authored_spans.size(),
			}
		)

	var evaluation_spans: Array = []
	var span_records: Array = []
	var total_length := 0.0
	var total_length_error := 0.0

	for span_index in range(authored_spans.size()):
		var authored_span: RoadSourceDocument.Span = authored_spans[span_index]
		var section: RoadSourceDocument.Section = authored_span.section
		var control_points := authored_span.control_points()
		var control_error := _validate_control_points(control_points, span_index, section.section_id)
		if not control_error.is_empty():
			return control_error

		var integration := _integrate_span(
			control_points,
			float(options[OPTION_ARC_LENGTH_TOLERANCE_M]),
			int(options[OPTION_MAX_SUBDIVISION_DEPTH]),
			int(options[OPTION_MAX_TABLE_NODES_PER_SPAN])
		)
		if not bool(integration["ok"]):
			var integration_diagnostic: Dictionary = (integration["diagnostic"] as Dictionary).duplicate(true)
			integration_diagnostic["span_index"] = span_index
			integration_diagnostic["section_id"] = section.section_id
			return _refuse(
				int(integration["code"]),
				"span %d (%s): %s" % [span_index, section.section_id, str(integration["error"])],
				integration_diagnostic
			)

		var nodes: Array = integration["nodes"]
		var node_error := _validate_arc_nodes(nodes, span_index, section.section_id)
		if not node_error.is_empty():
			return node_error

		var length := float((nodes[nodes.size() - 1] as Dictionary)["s"])
		if not is_finite(length):
			return _refuse(
				Refusal.NONFINITE_DERIVED_STATE,
				"span %d (%s) produced a nonfinite length" % [span_index, section.section_id],
				{"span_index": span_index, "section_id": section.section_id}
			)
		if length <= 0.0:
			return _refuse(
				Refusal.DEGENERATE_DERIVATIVE,
				"span %d (%s) produced no positive arc length" % [span_index, section.section_id],
				{"span_index": span_index, "section_id": section.section_id, "length_m": length}
			)

		var span_start := total_length
		total_length += length
		total_length_error += float(integration["error_estimate_m"])
		if not is_finite(total_length) or not is_finite(total_length_error):
			return _refuse(
				Refusal.NONFINITE_DERIVED_STATE,
				"chained span length or error estimate became nonfinite",
				{"span_index": span_index, "section_id": section.section_id}
			)
		if total_length <= span_start:
			return _refuse(
				Refusal.TABLE_INCONSISTENT,
				"span %d (%s) produced a positive local length that does not advance the global station"
				% [span_index, section.section_id],
				{
					"span_index": span_index,
				"section_id": section.section_id,
					"span_start_s": span_start,
					"span_end_s": total_length,
					"length_m": length,
				}
			)

		var record := {
			"span_index": span_index,
			"start_knot_index": authored_span.start_knot_index,
			"end_knot_index": authored_span.end_knot_index,
			"section_id": section.section_id,
			"surface_id": section.surface_id,
			"start_s": span_start,
			"end_s": total_length,
			"length_m": length,
			"length_error_estimate_m": float(integration["error_estimate_m"]),
			"integration_leaf_count": int(integration["leaf_count"]),
			"max_depth_used": int(integration["max_depth_used"]),
			"table_node_count": nodes.size(),
			"nodes": nodes.duplicate(true),
		}
		span_records.append(record)
		evaluation_spans.append({
			"span": authored_span,
			"control_points": control_points,
			"nodes": nodes,
			"record": record,
		})

	if not is_finite(total_length) or total_length <= 0.0:
		return _refuse(
			Refusal.TABLE_INCONSISTENT,
			"chained table length is not positive and finite",
			{"total_length_m": total_length}
		)

	var interval_ratio := total_length / spacing
	if not is_finite(interval_ratio):
		return _refuse(
			Refusal.BAD_SPACING,
			"spacing_m is too small to produce a finite station ratio",
			{"spacing_m": spacing, "total_length_m": total_length}
		)
	var max_output := int(options[OPTION_MAX_OUTPUT_SAMPLES])
	if interval_ratio + 1.0 > float(max_output):
		var required_estimate: float = ceilf(interval_ratio) + 1.0
		return _refuse(
			Refusal.SAMPLE_CAP_EXCEEDED,
			"uniform sampling would exceed the output sample cap",
			{
				"total_length_m": total_length,
				"spacing_m": spacing,
				"estimated_sample_count": required_estimate,
				"max_output_samples": max_output,
			}
		)

	var stations := _make_uniform_stations(total_length, spacing)
	if stations.size() > max_output:
		return _refuse(
			Refusal.SAMPLE_CAP_EXCEEDED,
			"uniform station generation exceeded the output sample cap",
			{
				"sample_count": stations.size(),
				"max_output_samples": max_output,
			}
		)
	var station_error := _validate_stations(stations, total_length)
	if not station_error.is_empty():
		return station_error

	var inversion_tolerance := float(options[OPTION_ARC_LENGTH_TOLERANCE_M]) * INVERSION_RESIDUAL_FRACTION
	var samples: Array = []
	var max_inversion_error := 0.0
	var max_inversion_residual := 0.0

	for sample_index in range(stations.size()):
		var station := float(stations[sample_index])
		var span_index := _span_index_for_station(span_records, station, total_length)
		if span_index < 0:
			return _refuse(
				Refusal.TABLE_INCONSISTENT,
				"no owning span found for a generated station",
				{"station_s": station, "total_length_m": total_length}
			)
		var evaluation: Dictionary = evaluation_spans[span_index]
		var record: Dictionary = evaluation["record"]
		var local_distance := station - float(record["start_s"])
		if sample_index == stations.size() - 1:
			local_distance = float(record["length_m"])

		var inversion := _invert_arc_length(
			evaluation["control_points"],
			evaluation["nodes"],
			local_distance,
			inversion_tolerance
		)
		if not bool(inversion["ok"]):
			var inversion_diagnostic: Dictionary = (inversion["diagnostic"] as Dictionary).duplicate(true)
			inversion_diagnostic["span_index"] = span_index
			inversion_diagnostic["section_id"] = str(record["section_id"])
			inversion_diagnostic["station_s"] = station
			return _refuse(
				int(inversion["code"]),
				"station %.12f in span %d (%s): %s" % [
					station, span_index, str(record["section_id"]), str(inversion["error"])
				],
				inversion_diagnostic
			)
		max_inversion_error = maxf(max_inversion_error, float(inversion["error_estimate_m"]))
		max_inversion_residual = maxf(max_inversion_residual, absf(float(inversion["residual_m"])))

		var role := "interior"
		if sample_index == 0:
			role = "closed_seam_start" if document.closed else "open_start"
		elif sample_index == stations.size() - 1:
			role = "closed_seam_end" if document.closed else "open_end"

		var sampled := _evaluate_sample(
			evaluation["span"],
			evaluation["control_points"],
			span_index,
			float(inversion["t"]),
			sample_index,
			station,
			role
		)
		if not bool(sampled["ok"]):
			var sample_diagnostic: Dictionary = (sampled["diagnostic"] as Dictionary).duplicate(true)
			sample_diagnostic["span_index"] = span_index
			sample_diagnostic["section_id"] = str(record["section_id"])
			sample_diagnostic["station_s"] = station
			return _refuse(
				int(sampled["code"]),
				"station %.12f in span %d (%s): %s" % [
					station, span_index, str(record["section_id"]), str(sampled["error"])
				],
				sample_diagnostic
			)
		samples.append(sampled["sample"])

	var sample_error := _validate_samples(samples, total_length)
	if not sample_error.is_empty():
		return sample_error

	var table := Table.make(
		document.course_id,
		document.revision,
		document.closed,
		spacing,
		total_length,
		total_length_error,
		max_inversion_error,
		max_inversion_residual,
		options,
		span_records,
		samples
	)
	return {
		"ok": true,
		"code": Refusal.NONE,
		"code_name": refusal_name(Refusal.NONE),
		"error": "",
		"diagnostic": {},
		"table": table,
	}


static func refusal_name(p_code: int) -> String:
	if REFUSAL_NAMES.has(p_code):
		return str(REFUSAL_NAMES[p_code])
	return "unknown_code_%d" % p_code


# --- Adaptive arc integration ------------------------------------------------


static func _derivative_degeneracy_error(p_control_points: Array[Vector3]) -> Dictionary:
	var p0: Vector3 = p_control_points[0]
	var p1: Vector3 = p_control_points[1]
	var p2: Vector3 = p_control_points[2]
	var p3: Vector3 = p_control_points[3]
	var quadratic := [
		3.0 * (p3.x - 3.0 * p2.x + 3.0 * p1.x - p0.x),
		3.0 * (p3.y - 3.0 * p2.y + 3.0 * p1.y - p0.y),
		3.0 * (p3.z - 3.0 * p2.z + 3.0 * p1.z - p0.z),
	]
	var linear := [
		6.0 * (p2.x - 2.0 * p1.x + p0.x),
		6.0 * (p2.y - 2.0 * p1.y + p0.y),
		6.0 * (p2.z - 2.0 * p1.z + p0.z),
	]
	var constant := [
		3.0 * (p1.x - p0.x),
		3.0 * (p1.y - p0.y),
		3.0 * (p1.z - p0.z),
	]

	var coefficient_scale := 0.0
	for axis in range(3):
		for coefficients in [quadratic, linear, constant]:
			var coefficient := float(coefficients[axis])
			if not is_finite(coefficient):
				return {
					"code": Refusal.NONFINITE_DERIVED_STATE,
					"error": "Bezier derivative polynomial became nonfinite",
					"diagnostic": {"axis": axis},
				}
			coefficient_scale = maxf(coefficient_scale, absf(coefficient))
	if coefficient_scale <= 0.0:
		return {
			"code": Refusal.DEGENERATE_DERIVATIVE,
			"error": "Bezier derivative is identically zero",
			"diagnostic": {},
		}

	var candidates: Array = []
	for axis in range(3):
		_append_quadratic_root_candidates(
			float(quadratic[axis]),
			float(linear[axis]),
			float(constant[axis]),
			candidates
		)

	var degenerate_speed := coefficient_scale * DEGENERATE_SPEED_RELATIVE_EPSILON
	for candidate in candidates:
		var t := float(candidate)
		var speed := _speed(p_control_points, t)
		if not is_finite(speed):
			return {
				"code": Refusal.NONFINITE_DERIVED_STATE,
				"error": "Bezier derivative length became nonfinite at an interior polynomial candidate",
				"diagnostic": {"t": t},
			}
		if speed <= degenerate_speed:
			return {
				"code": Refusal.DEGENERATE_DERIVATIVE,
				"error": "Bezier derivative length is zero or numerically degenerate inside the span",
				"diagnostic": {
					"t": t,
					"speed": speed,
					"coefficient_scale": coefficient_scale,
					"relative_epsilon": DEGENERATE_SPEED_RELATIVE_EPSILON,
				},
			}
	return {}


static func _append_quadratic_root_candidates(
	p_a: float,
	p_b: float,
	p_c: float,
	p_candidates: Array
) -> void:
	var coefficient_scale := maxf(absf(p_a), maxf(absf(p_b), absf(p_c)))
	if coefficient_scale <= 0.0 or not is_finite(coefficient_scale):
		return
	var a := p_a / coefficient_scale
	var b := p_b / coefficient_scale
	var c := p_c / coefficient_scale
	if a == 0.0:
		if b != 0.0:
			_append_root_candidate(-c / b, p_candidates)
		return

	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		if absf(discriminant) <= DERIVATIVE_DISCRIMINANT_EPSILON:
			_append_root_candidate(-b / (2.0 * a), p_candidates)
		return

	var root_discriminant := sqrt(discriminant)
	var signed_root := root_discriminant if b >= 0.0 else -root_discriminant
	var q := -0.5 * (b + signed_root)
	if q == 0.0:
		_append_root_candidate(-b / (2.0 * a), p_candidates)
		return
	_append_root_candidate(q / a, p_candidates)
	_append_root_candidate(c / q, p_candidates)


static func _append_root_candidate(p_t: float, p_candidates: Array) -> void:
	if not is_finite(p_t):
		return
	if p_t < -DERIVATIVE_ROOT_PARAMETER_TOLERANCE or p_t > 1.0 + DERIVATIVE_ROOT_PARAMETER_TOLERANCE:
		return
	var clamped := clampf(p_t, 0.0, 1.0)
	if not p_candidates.has(clamped):
		p_candidates.append(clamped)


static func _integrate_span(
	p_control_points: Array[Vector3],
	p_tolerance_m: float,
	p_max_depth: int,
	p_max_nodes: int
) -> Dictionary:
	# Each accepted leaf adds a relative roundoff allowance on a bracket that
	# encloses its subarc, so the summed reported error is at least this fraction
	# of the true span length, and therefore of the endpoint chord. A tighter
	# request can never be satisfied by any leaf partition and is refused rather
	# than silently reported as success.
	var chord_length := _scalar_control_chord_length(p_control_points)
	var precision_floor := ARC_LENGTH_BOUND_RELATIVE_ROUNDOFF * chord_length
	if p_tolerance_m < precision_floor:
		return _integration_failure({
			"code": Refusal.PRECISION_UNREACHABLE,
			"error": "requested arc length tolerance is below the sampler's roundoff-implied precision floor for the reported error",
			"diagnostic": {
				"requested_tolerance_m": p_tolerance_m,
				"precision_floor_m": precision_floor,
				"endpoint_chord_m": chord_length,
				"relative_roundoff_allowance": ARC_LENGTH_BOUND_RELATIVE_ROUNDOFF,
			},
		})
	var state := {
		"failed": false,
		"code": Refusal.NONE,
		"error": "",
		"diagnostic": {},
		"nodes": [{"t": 0.0, "s": 0.0}],
		"s_end": 0.0,
		"error_estimate_m": 0.0,
		"leaf_count": 0,
		"max_depth_used": 0,
	}
	var degeneracy_error := _derivative_degeneracy_error(p_control_points)
	if not degeneracy_error.is_empty():
		return _integration_failure(degeneracy_error)
	var speed0 := _speed(p_control_points, 0.0)
	var speed_half := _speed(p_control_points, 0.5)
	var speed1 := _speed(p_control_points, 1.0)
	for item in [
		{"speed": speed0, "label": "t=0"},
		{"speed": speed_half, "label": "t=0.5"},
		{"speed": speed1, "label": "t=1"},
	]:
		var speed_error := _speed_error(float(item["speed"]), str(item["label"]))
		if not speed_error.is_empty():
			return _integration_failure(speed_error)

	var whole := _simpson_integral(0.0, 1.0, speed0, speed_half, speed1)
	_integrate_span_recursive(
		p_control_points,
		0.0,
		1.0,
		speed0,
		speed_half,
		speed1,
		whole,
		p_tolerance_m,
		0,
		p_max_depth,
		p_max_nodes,
		state
	)
	if bool(state["failed"]):
		return _integration_failure({
			"code": int(state["code"]),
			"error": str(state["error"]),
			"diagnostic": state["diagnostic"],
		})
	return {
		"ok": true,
		"nodes": (state["nodes"] as Array).duplicate(true),
		"error_estimate_m": float(state["error_estimate_m"]),
		"leaf_count": int(state["leaf_count"]),
		"max_depth_used": int(state["max_depth_used"]),
	}


static func _integrate_span_recursive(
	p_control_points: Array[Vector3],
	p_a: float,
	p_b: float,
	p_fa: float,
	p_fm: float,
	p_fb: float,
	p_whole: float,
	p_tolerance: float,
	p_depth: int,
	p_max_depth: int,
	p_max_nodes: int,
	p_state: Dictionary
) -> void:
	if bool(p_state["failed"]):
		return
	p_state["max_depth_used"] = maxi(int(p_state["max_depth_used"]), p_depth)

	var middle := 0.5 * (p_a + p_b)
	var left_middle := 0.5 * (p_a + middle)
	var right_middle := 0.5 * (middle + p_b)
	var left_speed := _speed(p_control_points, left_middle)
	var right_speed := _speed(p_control_points, right_middle)
	for item in [
		{"speed": left_speed, "label": "t=%.12f" % left_middle},
		{"speed": right_speed, "label": "t=%.12f" % right_middle},
	]:
		var speed_error := _speed_error(float(item["speed"]), str(item["label"]))
		if not speed_error.is_empty():
			_set_integration_state_failure(p_state, speed_error)
			return

	var left_integral := _simpson_integral(p_a, middle, p_fa, left_speed, p_fm)
	var right_integral := _simpson_integral(middle, p_b, p_fm, right_speed, p_fb)
	var refined := left_integral + right_integral
	var delta := refined - p_whole
	var richardson_estimate := absf(delta) / 15.0
	var extrapolated := refined + delta / 15.0
	if not is_finite(refined) or not is_finite(richardson_estimate) or not is_finite(extrapolated):
		_set_integration_state_failure(p_state, {
			"code": Refusal.NONFINITE_DERIVED_STATE,
			"error": "adaptive Simpson integration became nonfinite",
			"diagnostic": {"t0": p_a, "t1": p_b, "depth": p_depth},
		})
		return

	var candidate_bounds := {}
	if richardson_estimate <= p_tolerance:
		candidate_bounds = _bezier_interval_length_bounds(p_control_points, p_a, p_b)
		if not bool(candidate_bounds["ok"]):
			_set_integration_state_failure(p_state, candidate_bounds)
			return
		var lower := float(candidate_bounds["lower"])
		var upper := float(candidate_bounds["upper"])
		var roundoff_slack := _arc_length_bound_roundoff_slack(lower, upper)
		if lower > upper + roundoff_slack:
			_set_integration_state_failure(p_state, {
				"code": Refusal.TABLE_INCONSISTENT,
				"error": "geometric arc-length bracket is inverted beyond roundoff",
				"diagnostic": {
					"t0": p_a,
					"t1": p_b,
					"depth": p_depth,
					"bracket_lower_m": lower,
					"bracket_upper_m": upper,
					"roundoff_slack_m": roundoff_slack,
				},
			})
			return
		if extrapolated >= lower - roundoff_slack and extrapolated <= upper + roundoff_slack:
			var distance := maxf(extrapolated - lower, upper - extrapolated)
			var error_estimate := distance + roundoff_slack
			if error_estimate <= p_tolerance:
				_accept_integration_leaf(
					p_state, p_b, extrapolated, error_estimate, p_max_nodes, p_a, p_depth
				)
				return

	if p_depth >= p_max_depth:
		var cap_diagnostic := {
			"t0": p_a,
			"t1": p_b,
			"depth": p_depth,
			"max_subdivision_depth": p_max_depth,
			"richardson_estimate_m": richardson_estimate,
			"richardson_tolerance_m": p_tolerance,
		}
		if not candidate_bounds.is_empty():
			var cap_lower := float(candidate_bounds["lower"])
			var cap_upper := float(candidate_bounds["upper"])
			cap_diagnostic["bracket_lower_m"] = cap_lower
			cap_diagnostic["bracket_upper_m"] = cap_upper
			cap_diagnostic["extrapolated_length_m"] = extrapolated
			cap_diagnostic["bracket_distance_m"] = maxf(
				extrapolated - cap_lower, cap_upper - extrapolated
			)
			cap_diagnostic["bracket_reported_error_m"] = (
				maxf(extrapolated - cap_lower, cap_upper - extrapolated)
				+ _arc_length_bound_roundoff_slack(cap_lower, cap_upper)
			)
		_set_integration_state_failure(p_state, {
			"code": Refusal.SUBDIVISION_CAP_EXCEEDED,
			"error": "adaptive Simpson subdivision depth cap reached before the geometric arc-length bracket and tolerance were satisfied",
			"diagnostic": cap_diagnostic,
		})
		return

	_integrate_span_recursive(
		p_control_points, p_a, middle, p_fa, left_speed, p_fm, left_integral,
		p_tolerance * 0.5, p_depth + 1, p_max_depth, p_max_nodes, p_state
	)
	_integrate_span_recursive(
		p_control_points, middle, p_b, p_fm, right_speed, p_fb, right_integral,
		p_tolerance * 0.5, p_depth + 1, p_max_depth, p_max_nodes, p_state
	)


static func _accept_integration_leaf(
	p_state: Dictionary,
	p_end_t: float,
	p_length: float,
	p_length_error_estimate_m: float,
	p_max_nodes: int,
	p_start_t: float,
	p_depth: int
) -> void:
	if not is_finite(p_length) or not is_finite(p_length_error_estimate_m):
		_set_integration_state_failure(p_state, {
			"code": Refusal.NONFINITE_DERIVED_STATE,
			"error": "accepted integration leaf has a nonfinite length or error estimate",
			"diagnostic": {"t0": p_start_t, "t1": p_end_t, "depth": p_depth},
		})
		return
	if p_length <= 0.0:
		_set_integration_state_failure(p_state, {
			"code": Refusal.DEGENERATE_DERIVATIVE,
			"error": "accepted integration leaf has no positive arc length",
			"diagnostic": {"t0": p_start_t, "t1": p_end_t, "depth": p_depth, "length_m": p_length},
		})
		return
	var nodes: Array = p_state["nodes"]
	if nodes.size() >= p_max_nodes:
		_set_integration_state_failure(p_state, {
			"code": Refusal.TABLE_NODE_CAP_EXCEEDED,
			"error": "adaptive arc table node cap exceeded",
			"diagnostic": {
				"table_node_count_before_append": nodes.size(),
				"max_table_nodes_per_span": p_max_nodes,
				"t0": p_start_t,
				"t1": p_end_t,
			},
		})
		return
	var new_end := float(p_state["s_end"]) + p_length
	if not is_finite(new_end) or new_end <= float(p_state["s_end"]):
		_set_integration_state_failure(p_state, {
			"code": Refusal.NONFINITE_DERIVED_STATE if not is_finite(new_end) else Refusal.TABLE_INCONSISTENT,
			"error": "adaptive arc table cumulative length is not strictly increasing and finite",
			"diagnostic": {
				"t0": p_start_t,
				"t1": p_end_t,
				"previous_s": float(p_state["s_end"]),
				"new_s": new_end,
			},
		})
		return
	nodes.append({"t": p_end_t, "s": new_end})
	p_state["s_end"] = new_end
	p_state["error_estimate_m"] = float(p_state["error_estimate_m"]) + p_length_error_estimate_m
	p_state["leaf_count"] = int(p_state["leaf_count"]) + 1


static func _integration_failure(p_failure: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"code": int(p_failure["code"]),
		"error": str(p_failure["error"]),
		"diagnostic": (p_failure.get("diagnostic", {}) as Dictionary).duplicate(true),
	}


static func _set_integration_state_failure(p_state: Dictionary, p_failure: Dictionary) -> void:
	if bool(p_state["failed"]):
		return
	p_state["failed"] = true
	p_state["code"] = int(p_failure["code"])
	p_state["error"] = str(p_failure["error"])
	p_state["diagnostic"] = (p_failure.get("diagnostic", {}) as Dictionary).duplicate(true)


static func _simpson_integral(
	p_a: float,
	p_b: float,
	p_fa: float,
	p_fm: float,
	p_fb: float
) -> float:
	return (p_b - p_a) * (p_fa + 4.0 * p_fm + p_fb) / 6.0


## Conservative geometric length bracket for one Bezier parameter interval.
## The interval is split into ARC_LENGTH_BOUND_PIECES equal subintervals. Each
## subinterval is reparameterised as a cubic with Q0=B(u), Q1=B(u)+h*B'(u)/3,
## Q2=B(v)-h*B'(v)/3, Q3=B(v), where h=v-u. The chord |Q3-Q0| lower-bounds
## that subarc and the control-polygon perimeter upper-bounds it; summing both
## over a contiguous partition of [a,b] bounds the whole subarc. Returns a
## failure dictionary with structured diagnostics when a bound is nonfinite.
static func _bezier_interval_length_bounds(
	p_control_points: Array[Vector3],
	p_a: float,
	p_b: float
) -> Dictionary:
	var lower := 0.0
	var upper := 0.0
	var step := (p_b - p_a) / float(ARC_LENGTH_BOUND_PIECES)
	var start_t := p_a
	for piece in range(ARC_LENGTH_BOUND_PIECES):
		var end_t := clampf(p_a + step * float(piece + 1), start_t, p_b)
		if piece == ARC_LENGTH_BOUND_PIECES - 1:
			end_t = p_b
		var width := end_t - start_t
		var derivative0 := _bezier_derivative_components(p_control_points, start_t)
		var derivative1 := _bezier_derivative_components(p_control_points, end_t)
		var displacement := _bezier_displacement_components(p_control_points, start_t, end_t)
		var derivative_scale := width / 3.0
		var first_segment := [
			float(derivative0[0]) * derivative_scale,
			float(derivative0[1]) * derivative_scale,
			float(derivative0[2]) * derivative_scale,
		]
		var last_segment := [
			float(derivative1[0]) * derivative_scale,
			float(derivative1[1]) * derivative_scale,
			float(derivative1[2]) * derivative_scale,
		]
		var middle_segment := [
			float(displacement[0]) - float(first_segment[0]) - float(last_segment[0]),
			float(displacement[1]) - float(first_segment[1]) - float(last_segment[1]),
			float(displacement[2]) - float(first_segment[2]) - float(last_segment[2]),
		]
		var chord := _components_length(displacement)
		var polygon := (
			_components_length(first_segment)
			+ _components_length(middle_segment)
			+ _components_length(last_segment)
		)
		if not is_finite(chord) or not is_finite(polygon):
			return {
				"ok": false,
				"code": Refusal.NONFINITE_DERIVED_STATE,
				"error": "geometric arc-length bracket became nonfinite",
				"diagnostic": {
					"t0": p_a,
					"t1": p_b,
					"piece": piece,
					"u": start_t,
					"v": end_t,
					"chord_m": chord,
					"polygon_m": polygon,
				},
			}
		lower += chord
		upper += polygon
		start_t = end_t
	if not is_finite(lower) or not is_finite(upper):
		return {
			"ok": false,
			"code": Refusal.NONFINITE_DERIVED_STATE,
			"error": "summed geometric arc-length bracket became nonfinite",
			"diagnostic": {"t0": p_a, "t1": p_b, "lower_m": lower, "upper_m": upper},
		}
	return {"ok": true, "lower": lower, "upper": upper}


static func _arc_length_bound_roundoff_slack(p_lower: float, p_upper: float) -> float:
	var scale := maxf(absf(p_lower), absf(p_upper))
	return ARC_LENGTH_BOUND_RELATIVE_ROUNDOFF * scale


## Scalar float64 endpoint chord of the stored control points. Used only to
## derive the reported-error precision floor before integration.
static func _scalar_control_chord_length(p_control_points: Array[Vector3]) -> float:
	var first: Vector3 = p_control_points[0]
	var last: Vector3 = p_control_points[3]
	return _components_length([
		last.x - first.x,
		last.y - first.y,
		last.z - first.z,
	])


# --- Arc inversion and evaluation -------------------------------------------


static func _invert_arc_length(
	p_control_points: Array[Vector3],
	p_nodes: Array,
	p_target_s: float,
	p_tolerance_m: float
) -> Dictionary:
	var first: Dictionary = p_nodes[0]
	var last: Dictionary = p_nodes[p_nodes.size() - 1]
	var span_length := float(last["s"])
	if p_target_s <= 0.0:
		return _inversion_success(float(first["t"]), 0.0, 0.0)
	if p_target_s >= span_length:
		return _inversion_success(float(last["t"]), 0.0, 0.0)

	var upper_index := _first_node_at_or_after(p_nodes, p_target_s)
	if upper_index < 0:
		return _inversion_failure(
			Refusal.TABLE_INCONSISTENT,
			"arc nodes do not bracket the target distance",
			{"target_s": p_target_s, "span_length_m": span_length}
		)
	var upper_node: Dictionary = p_nodes[upper_index]
	if float(upper_node["s"]) == p_target_s:
		return _inversion_success(float(upper_node["t"]), 0.0, 0.0)
	if upper_index == 0:
		return _inversion_failure(
			Refusal.TABLE_INCONSISTENT,
			"target distance precedes the first arc node",
			{"target_s": p_target_s}
		)

	var lower_node: Dictionary = p_nodes[upper_index - 1]
	var node_t0 := float(lower_node["t"])
	var node_t1 := float(upper_node["t"])
	var node_s0 := float(lower_node["s"])
	var node_s1 := float(upper_node["s"])
	var fraction := (p_target_s - node_s0) / (node_s1 - node_s0)
	var t := node_t0 + (node_t1 - node_t0) * fraction
	var lower_t := node_t0
	var upper_t := node_t1
	var local_target := p_target_s - node_s0
	var residual := 0.0
	var error_estimate := 0.0

	for iteration in range(INVERSION_MAX_ITERATIONS):
		var partial := _integrate_speed_richardson(p_control_points, node_t0, t)
		var partial_length := float(partial["length"])
		if not is_finite(partial_length):
			return _inversion_failure(
				Refusal.NONFINITE_DERIVED_STATE,
				"arc inversion quadrature became nonfinite",
				{"iteration": iteration, "t": t, "node_t0": node_t0, "node_t1": node_t1}
			)
		error_estimate = maxf(error_estimate, float(partial["error_estimate_m"]))
		residual = partial_length - local_target
		if absf(residual) <= p_tolerance_m * INVERSION_CONVERGENCE_FRACTION:
			break

		var tangent_speed := _speed(p_control_points, t)
		if not is_finite(tangent_speed):
			return _inversion_failure(
				Refusal.NONFINITE_DERIVED_STATE,
				"arc inversion derivative became nonfinite",
				{"iteration": iteration, "t": t}
			)
		if tangent_speed <= 0.0:
			return _inversion_failure(
				Refusal.DEGENERATE_DERIVATIVE,
				"arc inversion encountered a zero-length derivative",
				{"iteration": iteration, "t": t}
			)

		if residual > 0.0:
			upper_t = t
		else:
			lower_t = t
		var next_t := t - residual / tangent_speed
		if not is_finite(next_t) or next_t <= lower_t or next_t >= upper_t:
			next_t = 0.5 * (lower_t + upper_t)
		if next_t == t:
			break
		t = next_t

	var final_partial := _integrate_speed_richardson(p_control_points, node_t0, t)
	var final_length := float(final_partial["length"])
	if not is_finite(final_length):
		return _inversion_failure(
			Refusal.NONFINITE_DERIVED_STATE,
			"final arc inversion quadrature became nonfinite",
			{"t": t}
		)
	error_estimate = maxf(error_estimate, float(final_partial["error_estimate_m"]))
	residual = final_length - local_target
	if absf(residual) > p_tolerance_m:
		return _inversion_failure(
			Refusal.INVERSION_FAILED,
			"bounded arc inversion did not converge to the inversion tolerance",
			{
				"target_s": p_target_s,
				"residual_m": residual,
				"inversion_tolerance_m": p_tolerance_m,
				"node_t0": node_t0,
				"node_t1": node_t1,
				"iterations": INVERSION_MAX_ITERATIONS,
			}
		)
	return _inversion_success(t, residual, error_estimate)


static func _inversion_success(p_t: float, p_residual: float, p_error_estimate: float) -> Dictionary:
	return {
		"ok": true,
		"t": clampf(p_t, 0.0, 1.0),
		"residual_m": p_residual,
		"error_estimate_m": p_error_estimate,
	}


static func _inversion_failure(p_code: int, p_error: String, p_diagnostic: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"code": p_code,
		"error": p_error,
		"diagnostic": p_diagnostic.duplicate(true),
	}


static func _first_node_at_or_after(p_nodes: Array, p_target_s: float) -> int:
	var low := 0
	var high := p_nodes.size() - 1
	while low < high:
		var middle := (low + high) / 2
		if float((p_nodes[middle] as Dictionary)["s"]) < p_target_s:
			low = middle + 1
		else:
			high = middle
	return low


static func _integrate_speed_richardson(
	p_control_points: Array[Vector3],
	p_a: float,
	p_b: float
) -> Dictionary:
	if p_b <= p_a:
		return {"length": 0.0, "error_estimate_m": 0.0}
	var coarse := _integrate_speed_composite(p_control_points, p_a, p_b, INVERSION_COARSE_PANELS)
	var fine := _integrate_speed_composite(p_control_points, p_a, p_b, INVERSION_FINE_PANELS)
	if not is_finite(coarse) or not is_finite(fine):
		return {"length": NAN, "error_estimate_m": INF}
	var correction := (fine - coarse) / 15.0
	return {
		"length": fine + correction,
		"error_estimate_m": absf(correction),
	}


static func _integrate_speed_composite(
	p_control_points: Array[Vector3],
	p_a: float,
	p_b: float,
	p_panels: int
) -> float:
	var width := (p_b - p_a) / float(p_panels)
	var sum := _speed(p_control_points, p_a) + _speed(p_control_points, p_b)
	for panel in range(1, p_panels):
		var factor := 4.0 if panel % 2 == 1 else 2.0
		sum += factor * _speed(p_control_points, p_a + width * float(panel))
	if not is_finite(sum):
		return NAN
	return width * sum / 3.0


static func _evaluate_sample(
	p_span: RoadSourceDocument.Span,
	p_control_points: Array[Vector3],
	p_span_index: int,
	p_t: float,
	p_sample_index: int,
	p_station: float,
	p_role: String
) -> Dictionary:
	var t := clampf(p_t, 0.0, 1.0)
	var position_components := _bezier_position_components(p_control_points, t)
	var position := Vector3(
		float(position_components[0]),
		float(position_components[1]),
		float(position_components[2])
	)
	if not _finite_vector3(position):
		return _sample_failure(
			Refusal.NONFINITE_DERIVED_STATE,
			"sample position became nonfinite",
			{"t": t, "sample_index": p_sample_index}
		)
	var derivative_components := _bezier_derivative_components(p_control_points, t)
	var derivative_length := _components_length(derivative_components)
	if not is_finite(derivative_length):
		return _sample_failure(
			Refusal.NONFINITE_DERIVED_STATE,
			"sample derivative length became nonfinite",
			{"t": t, "sample_index": p_sample_index}
		)
	if derivative_length <= 0.0:
		return _sample_failure(
			Refusal.DEGENERATE_DERIVATIVE,
			"sample derivative has zero length and no normalized forward tangent",
			{"t": t, "sample_index": p_sample_index}
		)
	var tangent := Vector3(
		float(derivative_components[0]) / derivative_length,
		float(derivative_components[1]) / derivative_length,
		float(derivative_components[2]) / derivative_length
	)
	if not _finite_vector3(tangent):
		return _sample_failure(
			Refusal.NONFINITE_DERIVED_STATE,
			"normalized forward tangent became nonfinite",
			{"t": t, "sample_index": p_sample_index}
		)

	var start_knot: RoadSourceDocument.Knot = p_span.start_knot
	var end_knot: RoadSourceDocument.Knot = p_span.end_knot
	var width := start_knot.width_m * (1.0 - t) + end_knot.width_m * t
	var bank := start_knot.bank_deg * (1.0 - t) + end_knot.bank_deg * t
	if not is_finite(width) or not is_finite(bank):
		return _sample_failure(
			Refusal.NONFINITE_DERIVED_STATE,
			"width or bank interpolation became nonfinite",
			{"t": t, "sample_index": p_sample_index, "width_m": width, "bank_deg": bank}
		)
	var grade := tangent.y
	if not is_finite(grade):
		return _sample_failure(
			Refusal.NONFINITE_DERIVED_STATE,
			"grade dy/ds became nonfinite",
			{"t": t, "sample_index": p_sample_index}
		)

	var section: RoadSourceDocument.Section = p_span.section
	return {
		"ok": true,
		"sample": {
			"index": p_sample_index,
			"s": p_station,
			"position": position,
			"forward_tangent": tangent,
			"width_m": width,
			"bank_deg": bank,
			"grade_dy_ds": grade,
			"span_index": p_span_index,
			"span_t": t,
			"section_id": section.section_id,
			"surface_id": section.surface_id,
			"sample_role": p_role,
		},
	}


static func _sample_failure(p_code: int, p_error: String, p_diagnostic: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"code": p_code,
		"error": p_error,
		"diagnostic": p_diagnostic.duplicate(true),
	}


# --- Validation and small utilities -----------------------------------------


static func _resolve_options(p_options: Variant) -> Dictionary:
	if typeof(p_options) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"refusal": _refuse(
				Refusal.BAD_OPTIONS,
				"options must be a dictionary with only documented numeric cap keys",
				{"received_type": type_string(typeof(p_options))}
			),
		}
	var raw: Dictionary = p_options
	for key in raw:
		if not OPTION_KEYS.has(key):
			return {
				"ok": false,
				"refusal": _refuse(
					Refusal.BAD_OPTIONS,
					"unknown sampling option '%s'" % str(key),
					{"unknown_key": str(key), "allowed_keys": OPTION_KEYS.duplicate()}
				),
			}

	var resolved := {
		OPTION_ARC_LENGTH_TOLERANCE_M: DEFAULT_ARC_LENGTH_TOLERANCE_M,
		OPTION_MAX_SUBDIVISION_DEPTH: DEFAULT_MAX_SUBDIVISION_DEPTH,
		OPTION_MAX_TABLE_NODES_PER_SPAN: DEFAULT_MAX_TABLE_NODES_PER_SPAN,
		OPTION_MAX_OUTPUT_SAMPLES: DEFAULT_MAX_OUTPUT_SAMPLES,
	}

	if raw.has(OPTION_ARC_LENGTH_TOLERANCE_M):
		var tolerance := _read_positive_finite_number(
			raw[OPTION_ARC_LENGTH_TOLERANCE_M], OPTION_ARC_LENGTH_TOLERANCE_M
		)
		if not bool(tolerance["ok"]) or float(tolerance["value"]) > DEFAULT_ARC_LENGTH_TOLERANCE_M:
			return {
				"ok": false,
				"refusal": _refuse(
					Refusal.BAD_OPTIONS,
					"arc_length_tolerance_m must be positive, finite, and no looser than the default",
					{
						"received": str(raw[OPTION_ARC_LENGTH_TOLERANCE_M]),
						"default_maximum_m": DEFAULT_ARC_LENGTH_TOLERANCE_M,
					}
				),
			}
		resolved[OPTION_ARC_LENGTH_TOLERANCE_M] = float(tolerance["value"])

	var integer_specs := [
		{
			"key": OPTION_MAX_SUBDIVISION_DEPTH,
			"minimum": 0,
			"maximum": DEFAULT_MAX_SUBDIVISION_DEPTH,
		},
		{
			"key": OPTION_MAX_TABLE_NODES_PER_SPAN,
			"minimum": 2,
			"maximum": DEFAULT_MAX_TABLE_NODES_PER_SPAN,
		},
		{
			"key": OPTION_MAX_OUTPUT_SAMPLES,
			"minimum": 2,
			"maximum": DEFAULT_MAX_OUTPUT_SAMPLES,
		},
	]
	for spec in integer_specs:
		var key := str(spec["key"])
		if not raw.has(key):
			continue
		if typeof(raw[key]) != TYPE_INT:
			return {
				"ok": false,
				"refusal": _refuse(
					Refusal.BAD_OPTIONS,
					"%s must be an integer cap" % key,
					{"received": str(raw[key])}
				),
			}
		var value := int(raw[key])
		if value < int(spec["minimum"]) or value > int(spec["maximum"]):
			return {
				"ok": false,
				"refusal": _refuse(
					Refusal.BAD_OPTIONS,
					"%s is outside the permitted tightening range" % key,
					{
						"received": value,
						"minimum": int(spec["minimum"]),
						"maximum": int(spec["maximum"]),
					}
				),
			}
		resolved[key] = value
	return {"ok": true, "options": resolved}


static func _read_positive_finite_number(p_value: Variant, p_label: String) -> Dictionary:
	if typeof(p_value) != TYPE_FLOAT and typeof(p_value) != TYPE_INT:
		return {"ok": false, "error": "%s is not numeric" % p_label, "value": NAN}
	var value := float(p_value)
	if not is_finite(value) or value <= 0.0:
		return {"ok": false, "error": "%s is not positive and finite" % p_label, "value": value}
	return {"ok": true, "error": "", "value": value}


static func _validate_control_points(
	p_control_points: Array[Vector3],
	p_span_index: int,
	p_section_id: String
) -> Dictionary:
	if p_control_points.size() != 4:
		return _refuse(
			Refusal.BAD_DOCUMENT,
			"span %d (%s) does not expose exactly four cubic control points" % [p_span_index, p_section_id],
			{"span_index": p_span_index, "section_id": p_section_id, "count": p_control_points.size()}
		)
	for index in range(4):
		if not _finite_vector3(p_control_points[index]):
			return _refuse(
				Refusal.NONFINITE_DERIVED_STATE,
				"span %d (%s) exposes a nonfinite control point" % [p_span_index, p_section_id],
				{"span_index": p_span_index, "section_id": p_section_id, "control_point": index}
			)
	return {}


static func _validate_arc_nodes(p_nodes: Array, p_span_index: int, p_section_id: String) -> Dictionary:
	if p_nodes.size() < 2:
		return _refuse(
			Refusal.TABLE_INCONSISTENT,
			"span %d (%s) produced fewer than two arc nodes" % [p_span_index, p_section_id],
			{"span_index": p_span_index, "section_id": p_section_id}
		)
	var previous_t := -INF
	var previous_s := -INF
	for index in range(p_nodes.size()):
		var node: Dictionary = p_nodes[index]
		var t := float(node["t"])
		var s := float(node["s"])
		if not is_finite(t) or not is_finite(s):
			return _refuse(
				Refusal.NONFINITE_DERIVED_STATE,
				"span %d (%s) produced a nonfinite arc node" % [p_span_index, p_section_id],
				{"span_index": p_span_index, "section_id": p_section_id, "node_index": index}
			)
		if index == 0:
			if t != 0.0 or s != 0.0:
				return _refuse(
					Refusal.TABLE_INCONSISTENT,
					"span %d (%s) arc table does not start at t=0,s=0" % [p_span_index, p_section_id],
					{"span_index": p_span_index, "section_id": p_section_id, "t": t, "s": s}
				)
		elif t <= previous_t or s <= previous_s:
			return _refuse(
				Refusal.TABLE_INCONSISTENT,
				"span %d (%s) arc nodes are not strictly increasing" % [p_span_index, p_section_id],
				{"span_index": p_span_index, "section_id": p_section_id, "node_index": index}
			)
		previous_t = t
		previous_s = s
	var final_node: Dictionary = p_nodes[p_nodes.size() - 1]
	if float(final_node["t"]) != 1.0:
		return _refuse(
			Refusal.TABLE_INCONSISTENT,
			"span %d (%s) arc table does not end at t=1" % [p_span_index, p_section_id],
			{"span_index": p_span_index, "section_id": p_section_id, "final_t": float(final_node["t"])}
		)
	return {}


static func _make_uniform_stations(p_total_length: float, p_spacing: float) -> Array:
	var interval_count := maxi(1, int(ceil(p_total_length / p_spacing)))
	var stations: Array = []
	for index in range(interval_count):
		var station := float(index) * p_spacing
		if station < p_total_length:
			stations.append(station)
	if stations.is_empty() or float(stations[stations.size() - 1]) != p_total_length:
		stations.append(p_total_length)
	return stations


static func _validate_stations(p_stations: Array, p_total_length: float) -> Dictionary:
	if p_stations.size() < 2:
		return _refuse(
			Refusal.TABLE_INCONSISTENT,
			"station generation produced fewer than start and end samples",
			{"station_count": p_stations.size()}
		)
	if float(p_stations[0]) != 0.0 or float(p_stations[p_stations.size() - 1]) != p_total_length:
		return _refuse(
			Refusal.TABLE_INCONSISTENT,
			"station generation does not include exact start and end",
			{"first": float(p_stations[0]), "last": float(p_stations[p_stations.size() - 1]), "total_length_m": p_total_length}
		)
	var previous := -INF
	for index in range(p_stations.size()):
		var station := float(p_stations[index])
		if not is_finite(station):
			return _refuse(
				Refusal.NONFINITE_DERIVED_STATE,
				"station generation produced a nonfinite station",
				{"station_index": index}
			)
		if station <= previous:
			return _refuse(
				Refusal.BAD_SPACING,
				"station generation did not produce strictly increasing s",
				{"station_index": index, "previous_s": previous, "station_s": station}
			)
		previous = station
	return {}


static func _validate_samples(p_samples: Array, p_total_length: float) -> Dictionary:
	if p_samples.size() < 2:
		return _refuse(
			Refusal.TABLE_INCONSISTENT,
			"sample table has fewer than start and end samples",
			{"sample_count": p_samples.size()}
		)
	var previous := -INF
	for index in range(p_samples.size()):
		var sample: Dictionary = p_samples[index]
		var station := float(sample["s"])
		if not is_finite(station):
			return _refuse(
				Refusal.NONFINITE_DERIVED_STATE,
				"sample table contains a nonfinite station",
				{"sample_index": index}
			)
		if station <= previous:
			return _refuse(
				Refusal.BAD_SPACING,
				"sample stations are not strictly increasing",
				{"sample_index": index, "previous_s": previous, "station_s": station}
			)
		if not _finite_vector3(sample["position"]) or not _finite_vector3(sample["forward_tangent"]):
			return _refuse(
				Refusal.NONFINITE_DERIVED_STATE,
				"sample table contains a nonfinite position or tangent",
				{"sample_index": index}
			)
		previous = station
	if float((p_samples[0] as Dictionary)["s"]) != 0.0:
		return _refuse(
			Refusal.TABLE_INCONSISTENT,
			"sample table does not start at s=0",
			{"first_s": float((p_samples[0] as Dictionary)["s"])}
		)
	if float((p_samples[p_samples.size() - 1] as Dictionary)["s"]) != p_total_length:
		return _refuse(
			Refusal.TABLE_INCONSISTENT,
			"sample table does not end at total length",
			{"last_s": float((p_samples[p_samples.size() - 1] as Dictionary)["s"]), "total_length_m": p_total_length}
		)
	return {}


static func _span_index_for_station(p_span_records: Array, p_station: float, p_total_length: float) -> int:
	if p_station >= p_total_length:
		return p_span_records.size() - 1
	var low := 0
	var high := p_span_records.size() - 1
	while low < high:
		var middle := (low + high) / 2
		if p_station < float((p_span_records[middle] as Dictionary)["end_s"]):
			high = middle
		else:
			low = middle + 1
	return low


static func _bezier_position_components(p_control_points: Array[Vector3], p_t: float) -> Array:
	var u := 1.0 - p_t
	var weight0 := u * u * u
	var weight1 := 3.0 * u * u * p_t
	var weight2 := 3.0 * u * p_t * p_t
	var weight3 := p_t * p_t * p_t
	var p0: Vector3 = p_control_points[0]
	var p1: Vector3 = p_control_points[1]
	var p2: Vector3 = p_control_points[2]
	var p3: Vector3 = p_control_points[3]
	return [
		weight0 * p0.x + weight1 * p1.x + weight2 * p2.x + weight3 * p3.x,
		weight0 * p0.y + weight1 * p1.y + weight2 * p2.y + weight3 * p3.y,
		weight0 * p0.z + weight1 * p1.z + weight2 * p2.z + weight3 * p3.z,
	]


static func _bezier_derivative_components(p_control_points: Array[Vector3], p_t: float) -> Array:
	var u := 1.0 - p_t
	var weight0 := 3.0 * u * u
	var weight1 := 6.0 * u * p_t
	var weight2 := 3.0 * p_t * p_t
	var p0: Vector3 = p_control_points[0]
	var p1: Vector3 = p_control_points[1]
	var p2: Vector3 = p_control_points[2]
	var p3: Vector3 = p_control_points[3]
	return [
		weight0 * (p1.x - p0.x) + weight1 * (p2.x - p1.x) + weight2 * (p3.x - p2.x),
		weight0 * (p1.y - p0.y) + weight1 * (p2.y - p1.y) + weight2 * (p3.y - p2.y),
		weight0 * (p1.z - p0.z) + weight1 * (p2.z - p1.z) + weight2 * (p3.z - p2.z),
	]


static func _bezier_displacement_components(
	p_control_points: Array[Vector3],
	p_a: float,
	p_b: float
) -> Array:
	var width := p_b - p_a
	var linear_t := p_b + p_a
	var quadratic_t := p_b * p_b + p_b * p_a + p_a * p_a
	var p0: Vector3 = p_control_points[0]
	var p1: Vector3 = p_control_points[1]
	var p2: Vector3 = p_control_points[2]
	var p3: Vector3 = p_control_points[3]
	var linear := [
		3.0 * (p1.x - p0.x),
		3.0 * (p1.y - p0.y),
		3.0 * (p1.z - p0.z),
	]
	var quadratic := [
		3.0 * (p0.x - 2.0 * p1.x + p2.x),
		3.0 * (p0.y - 2.0 * p1.y + p2.y),
		3.0 * (p0.z - 2.0 * p1.z + p2.z),
	]
	var cubic := [
		p3.x - 3.0 * p2.x + 3.0 * p1.x - p0.x,
		p3.y - 3.0 * p2.y + 3.0 * p1.y - p0.y,
		p3.z - 3.0 * p2.z + 3.0 * p1.z - p0.z,
	]
	return [
		width * (float(linear[0]) + float(quadratic[0]) * linear_t + float(cubic[0]) * quadratic_t),
		width * (float(linear[1]) + float(quadratic[1]) * linear_t + float(cubic[1]) * quadratic_t),
		width * (float(linear[2]) + float(quadratic[2]) * linear_t + float(cubic[2]) * quadratic_t),
	]


static func _components_length(p_components: Array) -> float:
	var x := float(p_components[0])
	var y := float(p_components[1])
	var z := float(p_components[2])
	var squared := x * x + y * y + z * z
	if not is_finite(squared):
		return NAN
	return sqrt(squared)


static func _speed(p_control_points: Array[Vector3], p_t: float) -> float:
	var p0: Vector3 = p_control_points[0]
	var p1: Vector3 = p_control_points[1]
	var p2: Vector3 = p_control_points[2]
	var p3: Vector3 = p_control_points[3]
	for difference in [
		p1.x - p0.x, p1.y - p0.y, p1.z - p0.z,
		p2.x - p1.x, p2.y - p1.y, p2.z - p1.z,
		p3.x - p2.x, p3.y - p2.y, p3.z - p2.z,
	]:
		if absf(float(difference)) > VECTOR3_FINITE_COMPONENT_LIMIT:
			return NAN
	var components := _bezier_derivative_components(p_control_points, p_t)
	for component in components:
		if absf(float(component)) > VECTOR3_FINITE_COMPONENT_LIMIT:
			return NAN
	return _components_length(components)


static func _speed_error(p_speed: float, p_label: String) -> Dictionary:
	if not is_finite(p_speed):
		return {
			"code": Refusal.NONFINITE_DERIVED_STATE,
			"error": "Bezier derivative length became nonfinite at " + p_label,
			"diagnostic": {"where": p_label},
		}
	if p_speed <= 0.0:
		return {
			"code": Refusal.DEGENERATE_DERIVATIVE,
			"error": "Bezier derivative length is zero at " + p_label,
			"diagnostic": {"where": p_label},
		}
	return {}


static func _finite_vector3(p_value: Vector3) -> bool:
	return is_finite(p_value.x) and is_finite(p_value.y) and is_finite(p_value.z)


static func _refuse(p_code: int, p_error: String, p_diagnostic: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"code": p_code,
		"code_name": refusal_name(p_code),
		"error": p_error,
		"diagnostic": p_diagnostic.duplicate(true),
		"table": null,
	}
