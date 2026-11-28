class_name RoadTransportFrame
extends RefCounted

const RoadArcSampler := preload("res://src/course/road_arc_sampler.gd")

## Bounded open-course transported road frames for `roadstorm.road_arc_table.v1`.
##
## This is the first M2 frame-transport slice only. It consumes an already
## validated `RoadArcSampler.Table`, transports a right-handed road frame by
## the minimal rotation from each ordered tangent to the next, and applies the
## sample's authored bank after that transport. It does not mutate or
## revalidate the authored road source, bake meshes or collision, correct
## closed-loop residual roll, inspect course quality, or certify drivability.
##
## Coordinate and orientation contract. Positions and tangents use Godot world
## units with +Y up and world forward -Z. Each emitted frame is right-handed in
## the same object sense as a Godot `Basis`: local +X is road right, local +Y
## is road up, and local -Z is road forward. Equivalently,
## `right.cross(forward) == up` and `forward.cross(up) == right`; a transform
## basis can be formed as `Basis(right, up, -forward)`.
##
## Positive-bank sign. `bank_deg` is applied as a positive right-hand rotation
## about the forward tangent. Because `forward.cross(up) == right`, positive
## bank tilts the up vector toward local road right. For the canonical flat
## forward -Z frame this moves up toward +X and lowers the right edge, matching
## the established handling-lab banking convention. Negative bank is opposite.
##
## Transport policy. The first frame is seeded once from a deterministic
## world-reference axis: world +Y when it is usefully perpendicular to the
## first tangent, otherwise road +X orthogonalized against the near-vertical
## tangent. Later frames are not rebuilt from world up at each station. The
## previous right/up pair is rotated by the minimal rotation taking the
## previous tangent to the current tangent, then re-orthonormalized in float32
## engine vectors. Exact or near-exact tangent reversal has no unique minimal
## rotation axis and is refused.
##
## Closed courses are deliberately out of scope here. A closed table receives
## an explicit `closed_loop_unsupported` refusal because residual-roll closure
## distribution and a matching seam are a later separate slice.
##
## Output policy. Success returns an immutable-ish `FrameTable`; container
## accessors return deep mutable copies so callers cannot rewrite stored frame
## metadata through the public API. As with the source and sampler contracts,
## GDScript's Object.set private-member escape is a documented residual rather
## than part of the API. Every failure returns a stable code, `code_name`, a
## readable error and a machine-readable diagnostic, with no partial result.

const RESULT_SCHEMA := "roadstorm.road_frame_table.v1"
const SOURCE_TABLE_SCHEMA := "roadstorm.road_arc_table.v1"

const COORDINATE_FRAME_POLICY := (
	"Godot world units (metres), +Y up, world forward -Z; "
	+ "road frame +X right, +Y up, -Z forward"
)
const ORIENTATION_POLICY := (
	"right-handed frame: right.cross(forward)=up and "
	+ "forward.cross(up)=right; Basis columns are right, up, -forward"
)
const POSITIVE_BANK_POLICY := (
	"positive bank_deg is a positive right-hand rotation about forward; "
	+ "it tilts up toward road right and, for canonical forward -Z, lowers "
	+ "the +X/right edge"
)
const TRANSPORT_POLICY := (
	"seed once deterministically, then transport right/up by the minimal "
	+ "rotation from each previous tangent to the current tangent; never "
	+ "rebuild the frame from a world-up cross product at every station"
)
const CLOSED_LOOP_POLICY := (
	"closed tables are explicitly refused in this slice; residual-roll "
	+ "closure correction and seam matching are a later separate slice"
)

const WORLD_UP_SEED_ALIGNMENT_LIMIT := 0.999999
const TANGENT_UNIT_TOLERANCE := 0.0001
const MIN_TANGENT_LENGTH := 1.0e-12
const MIN_RIGHT_LENGTH_SQ := 1.0e-12
const SAME_TANGENT_AXIS_EPSILON := 1.0e-7
const REVERSING_TANGENT_DOT_LIMIT := -0.999999
const FRAME_COHERENCE_TOLERANCE := 0.0001
const SPAN_PARAMETER_TOLERANCE := 0.000001
const GRADE_CONSISTENCY_TOLERANCE := 0.0001

const SAMPLE_REQUIRED_KEYS: Array = [
	"index",
	"s",
	"position",
	"forward_tangent",
	"width_m",
	"bank_deg",
	"grade_dy_ds",
	"span_index",
	"span_t",
	"section_id",
	"surface_id",
	"sample_role",
]

## Stable refusal codes. Every refusal also carries `code_name`, a readable
## `error`, a machine-readable `diagnostic` dictionary, and `frame_table:null`.
enum Refusal {
	NONE = 0,
	BAD_TABLE,
	CLOSED_LOOP_UNSUPPORTED,
	TABLE_INCONSISTENT,
	BAD_SAMPLE,
	NONMONOTONIC_STATIONS,
	DEGENERATE_TANGENT,
	REVERSING_TANGENT,
	NONFINITE_DERIVED_STATE,
	FRAME_NUMERICS_INCONSISTENT,
}

const REFUSAL_NAMES := {
	Refusal.NONE: "none",
	Refusal.BAD_TABLE: "bad_table",
	Refusal.CLOSED_LOOP_UNSUPPORTED: "closed_loop_unsupported",
	Refusal.TABLE_INCONSISTENT: "table_inconsistent",
	Refusal.BAD_SAMPLE: "bad_sample",
	Refusal.NONMONOTONIC_STATIONS: "nonmonotonic_stations",
	Refusal.DEGENERATE_TANGENT: "degenerate_tangent",
	Refusal.REVERSING_TANGENT: "reversing_tangent",
	Refusal.NONFINITE_DERIVED_STATE: "nonfinite_derived_state",
	Refusal.FRAME_NUMERICS_INCONSISTENT: "frame_numerics_inconsistent",
}


# --- Immutable table view ----------------------------------------------------


## A successful immutable-ish frame table. Container accessors return deep
## mutable copies, so altering them cannot rewrite the stored result.
class FrameTable extends RefCounted:
	var _course_id := ""
	var _revision := ""
	var _sample_spacing_m := 0.0
	var _total_length_m := 0.0
	var _source_summary: Dictionary = {}
	var _frames: Array = []

	var schema: String: get = _get_schema
	var source_table_schema: String: get = _get_source_table_schema
	var course_id: String: get = _get_course_id
	var revision: String: get = _get_revision
	var closed: bool: get = _get_closed
	var sample_spacing_m: float: get = _get_sample_spacing_m
	var total_length_m: float: get = _get_total_length_m
	var frame_count: int: get = _get_frame_count
	var sample_count: int: get = _get_frame_count
	var frames: Array: get = _get_frames
	var source_summary: Dictionary: get = _get_source_summary
	var coordinate_frame_policy: String: get = _get_coordinate_frame_policy
	var orientation_policy: String: get = _get_orientation_policy
	var positive_bank_policy: String: get = _get_positive_bank_policy
	var transport_policy: String: get = _get_transport_policy
	var closed_loop_policy: String: get = _get_closed_loop_policy


	static func make(
		p_course_id: String,
		p_revision: String,
		p_sample_spacing_m: float,
		p_total_length_m: float,
		p_source_summary: Dictionary,
		p_frames: Array
	) -> FrameTable:
		var table := FrameTable.new()
		table._course_id = p_course_id
		table._revision = p_revision
		table._sample_spacing_m = p_sample_spacing_m
		table._total_length_m = p_total_length_m
		table._source_summary = p_source_summary.duplicate(true)
		table._frames = p_frames.duplicate(true)
		return table


	func _get_schema() -> String:
		return RESULT_SCHEMA


	func _get_source_table_schema() -> String:
		return SOURCE_TABLE_SCHEMA


	func _get_course_id() -> String:
		return _course_id


	func _get_revision() -> String:
		return _revision


	func _get_closed() -> bool:
		return false


	func _get_sample_spacing_m() -> float:
		return _sample_spacing_m


	func _get_total_length_m() -> float:
		return _total_length_m


	func _get_frame_count() -> int:
		return _frames.size()


	func _get_frames() -> Array:
		return _frames.duplicate(true)


	func _get_source_summary() -> Dictionary:
		return _source_summary.duplicate(true)


	func _get_coordinate_frame_policy() -> String:
		return COORDINATE_FRAME_POLICY


	func _get_orientation_policy() -> String:
		return ORIENTATION_POLICY


	func _get_positive_bank_policy() -> String:
		return POSITIVE_BANK_POLICY


	func _get_transport_policy() -> String:
		return TRANSPORT_POLICY


	func _get_closed_loop_policy() -> String:
		return CLOSED_LOOP_POLICY


	func frame(p_index: int) -> Dictionary:
		if p_index < 0 or p_index >= _frames.size():
			return {}
		return (_frames[p_index] as Dictionary).duplicate(true)


	func summary() -> Dictionary:
		return {
			"schema": RESULT_SCHEMA,
			"source_table_schema": SOURCE_TABLE_SCHEMA,
			"course_id": _course_id,
			"revision": _revision,
			"closed": false,
			"frame_count": _frames.size(),
			"sample_count": _frames.size(),
			"sample_spacing_m": _sample_spacing_m,
			"total_length_m": _total_length_m,
			"coordinate_frame_policy": COORDINATE_FRAME_POLICY,
			"orientation_policy": ORIENTATION_POLICY,
			"positive_bank_policy": POSITIVE_BANK_POLICY,
			"transport_policy": TRANSPORT_POLICY,
			"closed_loop_policy": CLOSED_LOOP_POLICY,
		}


	func to_dictionary() -> Dictionary:
		return {
			"schema": RESULT_SCHEMA,
			"source_table_schema": SOURCE_TABLE_SCHEMA,
			"course_id": _course_id,
			"revision": _revision,
			"closed": false,
			"sample_spacing_m": _sample_spacing_m,
			"total_length_m": _total_length_m,
			"coordinate_frame_policy": COORDINATE_FRAME_POLICY,
			"orientation_policy": ORIENTATION_POLICY,
			"positive_bank_policy": POSITIVE_BANK_POLICY,
			"transport_policy": TRANSPORT_POLICY,
			"closed_loop_policy": CLOSED_LOOP_POLICY,
			"source_summary": _source_summary.duplicate(true),
			"frames": _frames.duplicate(true),
		}


# --- Public construction -----------------------------------------------------


## Builds transported frames for an open validated arc table. On success
## returns {"ok":true,"code":0,"code_name":"none","error":"",
## "diagnostic":{},"frame_table":FrameTable}. On failure no partial frame
## table is returned. This is the canonical entry point.
static func build_open_frame_table(p_table: Variant) -> Dictionary:
	if typeof(p_table) != TYPE_OBJECT or not (p_table is RoadArcSampler.Table):
		return _refuse(
			Refusal.BAD_TABLE,
			"input must be a RoadArcSampler.Table",
			{"received_type": type_string(typeof(p_table))}
		)
	var table: RoadArcSampler.Table = p_table

	if table.closed:
		return _refuse(
			Refusal.CLOSED_LOOP_UNSUPPORTED,
			"closed loop frame transport is not supported in this slice: residual-roll closure correction and seam matching are a later slice",
			{
				"course_id": table.course_id,
				"closed": true,
				"closed_loop_policy": CLOSED_LOOP_POLICY,
			}
		)

	var header_error := _validate_table_header(table)
	if not header_error.is_empty():
		return header_error

	var samples := table.samples
	var sample_error := _validate_samples(table, samples)
	if not sample_error.is_empty():
		return sample_error

	var frames: Array = []
	var previous_forward := Vector3.ZERO
	var previous_right := Vector3.ZERO
	var previous_up := Vector3.ZERO

	for index in range(samples.size()):
		var sample: Dictionary = samples[index]
		var forward: Vector3 = sample["forward_tangent"]
		forward = forward.normalized()
		if not _finite_vector3(forward):
			return _refuse(
				Refusal.NONFINITE_DERIVED_STATE,
				"normalized forward tangent became nonfinite",
				{"sample_index": index}
			)

		var base_frame: Dictionary
		if index == 0:
			base_frame = _initial_frame(forward, index)
		else:
			base_frame = _transport_frame(
				previous_forward,
				previous_right,
				previous_up,
				forward,
				index
			)
		if not bool(base_frame["ok"]):
			return base_frame

		var banked_frame := _apply_bank(
			forward,
			base_frame["right"],
			base_frame["up"],
			float(sample["bank_deg"]),
			index
		)
		if not bool(banked_frame["ok"]):
			return banked_frame

		var coherent_error := _validate_frame_coherence(
			banked_frame["forward"],
			banked_frame["right"],
			banked_frame["up"],
			index
		)
		if not coherent_error.is_empty():
			return coherent_error

		# Transport continuity uses the unbanked base frame. Authored bank is an
		# absolute per-sample roll applied after transport, not an incremental
		# rotation accumulated into later stations.
		previous_forward = base_frame["forward"]
		previous_right = base_frame["right"]
		previous_up = base_frame["up"]

		var frame_basis := Basis(
			banked_frame["right"],
			banked_frame["up"],
			-banked_frame["forward"]
		)
		frames.append({
			"index": index,
			"s": float(sample["s"]),
			"position": sample["position"],
			"forward": banked_frame["forward"],
			"right": banked_frame["right"],
			"up": banked_frame["up"],
			"basis": frame_basis,
			"width_m": float(sample["width_m"]),
			"bank_deg": float(sample["bank_deg"]),
			"grade_dy_ds": float(sample["grade_dy_ds"]),
			"span_index": int(sample["span_index"]),
			"span_t": float(sample["span_t"]),
			"section_id": str(sample["section_id"]),
			"surface_id": str(sample["surface_id"]),
			"sample_role": str(sample["sample_role"]),
		})

	var frame_table := FrameTable.make(
		table.course_id,
		table.revision,
		table.sample_spacing_m,
		table.total_length_m,
		table.summary(),
		frames
	)
	return {
		"ok": true,
		"code": Refusal.NONE,
		"code_name": refusal_name(Refusal.NONE),
		"error": "",
		"diagnostic": {},
		"frame_table": frame_table,
	}


## Compatibility spelling for callers that naturally name the result a frame
## table. It has exactly the canonical open-course behavior above.
static func build_frame_table(p_table: Variant) -> Dictionary:
	return build_open_frame_table(p_table)


static func refusal_name(p_code: int) -> String:
	if REFUSAL_NAMES.has(p_code):
		return str(REFUSAL_NAMES[p_code])
	return "unknown_code_%d" % p_code


# --- Validation --------------------------------------------------------------


static func _validate_table_header(p_table: RoadArcSampler.Table) -> Dictionary:
	if p_table.schema != SOURCE_TABLE_SCHEMA:
		return _refuse(
			Refusal.TABLE_INCONSISTENT,
			"table schema is not the road arc table schema",
			{"schema": p_table.schema, "expected_schema": SOURCE_TABLE_SCHEMA}
		)
	if not is_finite(p_table.sample_spacing_m) or p_table.sample_spacing_m <= 0.0:
		return _refuse(
			Refusal.TABLE_INCONSISTENT,
			"table sample spacing is not positive and finite",
			{"sample_spacing_m": p_table.sample_spacing_m}
		)
	if not is_finite(p_table.total_length_m) or p_table.total_length_m <= 0.0:
		return _refuse(
			Refusal.TABLE_INCONSISTENT,
			"table total length is not positive and finite",
			{"total_length_m": p_table.total_length_m}
		)
	if p_table.sample_count != p_table.samples.size():
		return _refuse(
			Refusal.TABLE_INCONSISTENT,
			"table sample count does not match its sample array",
			{
				"sample_count_property": p_table.sample_count,
				"sample_array_size": p_table.samples.size(),
			}
		)
	if p_table.sample_count < 2:
		return _refuse(
			Refusal.TABLE_INCONSISTENT,
			"open frame transport requires at least start and end samples",
			{"sample_count": p_table.sample_count}
		)
	return {}


static func _validate_samples(p_table: RoadArcSampler.Table, p_samples: Array) -> Dictionary:
	var previous_station := -INF
	for index in range(p_samples.size()):
		if typeof(p_samples[index]) != TYPE_DICTIONARY:
			return _refuse(
				Refusal.BAD_SAMPLE,
				"sample is not a dictionary",
				{"sample_index": index, "received_type": type_string(typeof(p_samples[index]))}
			)
		var sample: Dictionary = p_samples[index]
		for key in SAMPLE_REQUIRED_KEYS:
			if not sample.has(key):
				return _refuse(
					Refusal.BAD_SAMPLE,
					"sample is missing required key '%s'" % str(key),
					{"sample_index": index, "missing_key": str(key)}
				)

		if typeof(sample["index"]) != TYPE_INT or int(sample["index"]) != index:
			return _refuse(
				Refusal.BAD_SAMPLE,
				"sample index does not match its ordered position",
				{"sample_index": index, "recorded_index": sample["index"]}
			)
		if not _is_number(sample["s"]):
			return _refuse(
				Refusal.BAD_SAMPLE,
				"sample station is not numeric",
				{"sample_index": index, "received": str(sample["s"])}
			)
		var station := float(sample["s"])
		if not is_finite(station):
			return _refuse(
				Refusal.NONFINITE_DERIVED_STATE,
				"sample station is nonfinite",
				{"sample_index": index}
			)
		if station <= previous_station:
			return _refuse(
				Refusal.NONMONOTONIC_STATIONS,
				"sample stations are not strictly increasing",
				{
					"sample_index": index,
					"previous_s": previous_station,
					"station_s": station,
				}
			)
		previous_station = station

		if typeof(sample["position"]) != TYPE_VECTOR3:
			return _refuse(
				Refusal.BAD_SAMPLE,
				"sample position is not a Vector3",
				{"sample_index": index, "received_type": type_string(typeof(sample["position"]))}
			)
		if not _finite_vector3(sample["position"]):
			return _refuse(
				Refusal.NONFINITE_DERIVED_STATE,
				"sample position is nonfinite or cannot remain finite as float32 vector state",
				{"sample_index": index}
			)
		if typeof(sample["forward_tangent"]) != TYPE_VECTOR3:
			return _refuse(
				Refusal.BAD_SAMPLE,
				"sample forward tangent is not a Vector3",
				{"sample_index": index, "received_type": type_string(typeof(sample["forward_tangent"]))}
			)
		var tangent: Vector3 = sample["forward_tangent"]
		if not _finite_vector3(tangent):
			return _refuse(
				Refusal.NONFINITE_DERIVED_STATE,
				"sample forward tangent is nonfinite or cannot remain finite as float32 vector state",
				{"sample_index": index}
			)
		var tangent_length := tangent.length()
		if not is_finite(tangent_length):
			return _refuse(
				Refusal.NONFINITE_DERIVED_STATE,
				"sample forward tangent length is nonfinite",
				{"sample_index": index}
			)
		if tangent_length <= MIN_TANGENT_LENGTH:
			return _refuse(
				Refusal.DEGENERATE_TANGENT,
				"sample forward tangent has zero or near-zero length",
				{"sample_index": index, "tangent_length": tangent_length}
			)
		if absf(tangent_length - 1.0) > TANGENT_UNIT_TOLERANCE:
			return _refuse(
				Refusal.DEGENERATE_TANGENT,
				"sample forward tangent is not unit length within the arc-table contract tolerance",
				{
					"sample_index": index,
					"tangent_length": tangent_length,
					"tolerance": TANGENT_UNIT_TOLERANCE,
				}
			)

		if not _is_number(sample["width_m"]):
			return _refuse(
				Refusal.BAD_SAMPLE,
				"sample width_m is not numeric",
				{"sample_index": index, "received": str(sample["width_m"])}
			)
		var width := float(sample["width_m"])
		if not is_finite(width):
			return _refuse(
				Refusal.NONFINITE_DERIVED_STATE,
				"sample width_m is nonfinite",
				{"sample_index": index}
			)
		if width <= 0.0:
			return _refuse(
				Refusal.BAD_SAMPLE,
				"sample width_m is not positive",
				{"sample_index": index, "width_m": width}
			)
		if not _is_number(sample["bank_deg"]):
			return _refuse(
				Refusal.BAD_SAMPLE,
				"sample bank_deg is not numeric",
				{"sample_index": index, "received": str(sample["bank_deg"])}
			)
		var bank := float(sample["bank_deg"])
		if not is_finite(bank):
			return _refuse(
				Refusal.NONFINITE_DERIVED_STATE,
				"sample bank_deg is nonfinite",
				{"sample_index": index}
			)
		if not _is_number(sample["grade_dy_ds"]):
			return _refuse(
				Refusal.BAD_SAMPLE,
				"sample grade_dy_ds is not numeric",
				{"sample_index": index, "received": str(sample["grade_dy_ds"])}
			)
		var grade := float(sample["grade_dy_ds"])
		if not is_finite(grade):
			return _refuse(
				Refusal.NONFINITE_DERIVED_STATE,
				"sample grade_dy_ds is nonfinite",
				{"sample_index": index}
			)
		if absf(grade - tangent.y) > GRADE_CONSISTENCY_TOLERANCE:
			return _refuse(
				Refusal.TABLE_INCONSISTENT,
				"sample grade_dy_ds does not match its forward tangent y component",
				{
					"sample_index": index,
					"grade_dy_ds": grade,
					"forward_tangent_y": tangent.y,
					"tolerance": GRADE_CONSISTENCY_TOLERANCE,
				}
			)

		if typeof(sample["span_index"]) != TYPE_INT:
			return _refuse(
				Refusal.BAD_SAMPLE,
				"sample span_index is not an integer",
				{"sample_index": index, "received_type": type_string(typeof(sample["span_index"]))}
			)
		var span_index := int(sample["span_index"])
		if span_index < 0 or span_index >= p_table.span_count:
			return _refuse(
				Refusal.TABLE_INCONSISTENT,
				"sample span_index is outside the table span range",
				{"sample_index": index, "span_index": span_index, "span_count": p_table.span_count}
			)
		if not _is_number(sample["span_t"]):
			return _refuse(
				Refusal.BAD_SAMPLE,
				"sample span_t is not numeric",
				{"sample_index": index, "received": str(sample["span_t"])}
			)
		var span_t := float(sample["span_t"])
		if not is_finite(span_t):
			return _refuse(
				Refusal.NONFINITE_DERIVED_STATE,
				"sample span_t is nonfinite",
				{"sample_index": index}
			)
		if span_t < -SPAN_PARAMETER_TOLERANCE or span_t > 1.0 + SPAN_PARAMETER_TOLERANCE:
			return _refuse(
				Refusal.TABLE_INCONSISTENT,
				"sample span_t is outside the unit Bezier parameter interval",
				{"sample_index": index, "span_t": span_t}
			)
		if typeof(sample["section_id"]) != TYPE_STRING or str(sample["section_id"]).strip_edges().is_empty():
			return _refuse(
				Refusal.BAD_SAMPLE,
				"sample section_id is not a non-empty string",
				{"sample_index": index, "received": str(sample["section_id"])}
			)
		if typeof(sample["surface_id"]) != TYPE_STRING or str(sample["surface_id"]).strip_edges().is_empty():
			return _refuse(
				Refusal.BAD_SAMPLE,
				"sample surface_id is not a non-empty string",
				{"sample_index": index, "received": str(sample["surface_id"])}
			)
		if typeof(sample["sample_role"]) != TYPE_STRING:
			return _refuse(
				Refusal.BAD_SAMPLE,
				"sample sample_role is not a string",
				{"sample_index": index, "received_type": type_string(typeof(sample["sample_role"]))}
			)
		var expected_role := "interior"
		if index == 0:
			expected_role = "open_start"
		elif index == p_samples.size() - 1:
			expected_role = "open_end"
		if str(sample["sample_role"]) != expected_role:
			return _refuse(
				Refusal.TABLE_INCONSISTENT,
				"sample role does not match open ordered table position",
				{
					"sample_index": index,
					"sample_role": str(sample["sample_role"]),
					"expected_role": expected_role,
				}
			)

	if float((p_samples[0] as Dictionary)["s"]) != 0.0:
		return _refuse(
			Refusal.TABLE_INCONSISTENT,
			"sample table does not start at s=0",
			{"first_s": float((p_samples[0] as Dictionary)["s"])}
		)
	if float((p_samples[p_samples.size() - 1] as Dictionary)["s"]) != p_table.total_length_m:
		return _refuse(
			Refusal.TABLE_INCONSISTENT,
			"sample table does not end at total length",
			{
				"last_s": float((p_samples[p_samples.size() - 1] as Dictionary)["s"]),
				"total_length_m": p_table.total_length_m,
			}
		)
	return {}


# --- Frame construction ------------------------------------------------------


static func _initial_frame(p_forward: Vector3, p_sample_index: int) -> Dictionary:
	var seed_right := Vector3.ZERO
	if absf(p_forward.y) <= WORLD_UP_SEED_ALIGNMENT_LIMIT:
		seed_right = p_forward.cross(Vector3.UP)
	else:
		seed_right = Vector3.RIGHT
	return _orthonormalize_frame(p_forward, seed_right, p_sample_index, "initial_seed")


static func _transport_frame(
	p_previous_forward: Vector3,
	p_previous_right: Vector3,
	p_previous_up: Vector3,
	p_forward: Vector3,
	p_sample_index: int
) -> Dictionary:
	var tangent_dot := clampf(p_previous_forward.dot(p_forward), -1.0, 1.0)
	if not is_finite(tangent_dot):
		return _refuse(
			Refusal.NONFINITE_DERIVED_STATE,
			"tangent dot product became nonfinite during transport",
			{"sample_index": p_sample_index}
		)
	if tangent_dot <= REVERSING_TANGENT_DOT_LIMIT:
		return _refuse(
			Refusal.REVERSING_TANGENT,
			"consecutive tangents reverse direction; the minimal transport rotation axis is not uniquely defined",
			{
				"sample_index": p_sample_index,
				"tangent_dot": tangent_dot,
				"reversing_dot_limit": REVERSING_TANGENT_DOT_LIMIT,
			}
		)

	var axis := p_previous_forward.cross(p_forward)
	var axis_length := axis.length()
	if not is_finite(axis_length):
		return _refuse(
			Refusal.NONFINITE_DERIVED_STATE,
			"minimal transport axis became nonfinite",
			{"sample_index": p_sample_index}
		)

	var transported_right := p_previous_right
	var transported_up := p_previous_up
	if axis_length > SAME_TANGENT_AXIS_EPSILON:
		var unit_axis := axis / axis_length
		var angle := atan2(axis_length, tangent_dot)
		if not is_finite(angle):
			return _refuse(
				Refusal.NONFINITE_DERIVED_STATE,
				"minimal transport angle became nonfinite",
				{"sample_index": p_sample_index, "axis_length": axis_length, "tangent_dot": tangent_dot}
			)
		transported_right = _rotate_around_unit_axis(p_previous_right, unit_axis, angle)
		transported_up = _rotate_around_unit_axis(p_previous_up, unit_axis, angle)

	return _orthonormalize_frame(p_forward, transported_right, p_sample_index, "minimal_transport")


static func _apply_bank(
	p_forward: Vector3,
	p_right: Vector3,
	p_up: Vector3,
	p_bank_deg: float,
	p_sample_index: int
) -> Dictionary:
	var bank_rad := deg_to_rad(p_bank_deg)
	if not is_finite(bank_rad):
		return _refuse(
			Refusal.NONFINITE_DERIVED_STATE,
			"bank angle conversion became nonfinite",
			{"sample_index": p_sample_index, "bank_deg": p_bank_deg}
		)
	# Bank is periodic. Reducing finite angles before trigonometry avoids
	# meaningless ultra-large-argument results while preserving exact sign.
	bank_rad = fmod(bank_rad, TAU)
	if not is_finite(bank_rad):
		return _refuse(
			Refusal.NONFINITE_DERIVED_STATE,
			"bank angle reduction became nonfinite",
			{"sample_index": p_sample_index, "bank_deg": p_bank_deg}
		)
	var right := _rotate_around_unit_axis(p_right, p_forward, bank_rad)
	var up := _rotate_around_unit_axis(p_up, p_forward, bank_rad)
	return _orthonormalize_frame(p_forward, right, p_sample_index, "bank_application")


static func _orthonormalize_frame(
	p_forward: Vector3,
	p_right_guess: Vector3,
	p_sample_index: int,
	p_phase: String
) -> Dictionary:
	var forward := p_forward.normalized()
	if not _finite_vector3(forward) or forward.length_squared() <= 0.0:
		return _refuse(
			Refusal.NONFINITE_DERIVED_STATE,
			"forward vector became nonfinite during frame orthonormalization",
			{"sample_index": p_sample_index, "phase": p_phase}
		)

	var right := p_right_guess - forward * p_right_guess.dot(forward)
	if not _finite_vector3(right):
		return _refuse(
			Refusal.NONFINITE_DERIVED_STATE,
			"right vector became nonfinite during frame orthonormalization",
			{"sample_index": p_sample_index, "phase": p_phase}
		)
	var right_length_sq := right.length_squared()
	if not is_finite(right_length_sq):
		return _refuse(
			Refusal.NONFINITE_DERIVED_STATE,
			"right vector length became nonfinite during frame orthonormalization",
			{"sample_index": p_sample_index, "phase": p_phase}
		)
	if right_length_sq <= MIN_RIGHT_LENGTH_SQ:
		return _refuse(
			Refusal.DEGENERATE_TANGENT,
			"transported right vector is degenerate after tangent orthogonalization",
			{
				"sample_index": p_sample_index,
				"phase": p_phase,
				"right_length_squared": right_length_sq,
			}
		)
	right = right / sqrt(right_length_sq)

	var up := right.cross(forward)
	if not _finite_vector3(up):
		return _refuse(
			Refusal.NONFINITE_DERIVED_STATE,
			"up vector became nonfinite during frame orthonormalization",
			{"sample_index": p_sample_index, "phase": p_phase}
		)
	var up_length := up.length()
	if not is_finite(up_length) or up_length <= MIN_TANGENT_LENGTH:
		return _refuse(
			Refusal.DEGENERATE_TANGENT,
			"derived up vector is degenerate during frame orthonormalization",
			{"sample_index": p_sample_index, "phase": p_phase, "up_length": up_length}
		)
	up = up / up_length

	# Recompose right from the orthogonal pair so all three float32 axes satisfy
	# the documented handedness as tightly as engine vector rounding permits.
	right = forward.cross(up)
	if not _finite_vector3(right):
		return _refuse(
			Refusal.NONFINITE_DERIVED_STATE,
			"recomposed right vector became nonfinite",
			{"sample_index": p_sample_index, "phase": p_phase}
		)
	var recomposed_length := right.length()
	if not is_finite(recomposed_length) or recomposed_length <= MIN_TANGENT_LENGTH:
		return _refuse(
			Refusal.DEGENERATE_TANGENT,
			"recomposed right vector is degenerate",
			{"sample_index": p_sample_index, "phase": p_phase, "right_length": recomposed_length}
		)
	right = right / recomposed_length

	if not _finite_vector3(forward) or not _finite_vector3(right) or not _finite_vector3(up):
		return _refuse(
			Refusal.NONFINITE_DERIVED_STATE,
			"orthonormal frame contains nonfinite float32 vector state",
			{"sample_index": p_sample_index, "phase": p_phase}
		)
	return {"ok": true, "forward": forward, "right": right, "up": up}


static func _rotate_around_unit_axis(p_vector: Vector3, p_axis: Vector3, p_angle: float) -> Vector3:
	var sine := sin(p_angle)
	var cosine := cos(p_angle)
	return (
		p_vector * cosine
		+ p_axis.cross(p_vector) * sine
		+ p_axis * (p_axis.dot(p_vector) * (1.0 - cosine))
	)


static func _validate_frame_coherence(
	p_forward: Vector3,
	p_right: Vector3,
	p_up: Vector3,
	p_sample_index: int
) -> Dictionary:
	if not _finite_vector3(p_forward) or not _finite_vector3(p_right) or not _finite_vector3(p_up):
		return _refuse(
			Refusal.NONFINITE_DERIVED_STATE,
			"derived frame contains nonfinite float32 vector state",
			{"sample_index": p_sample_index}
		)
	var unit_errors := [
		absf(p_forward.length() - 1.0),
		absf(p_right.length() - 1.0),
		absf(p_up.length() - 1.0),
	]
	var dot_errors := [
		absf(p_forward.dot(p_right)),
		absf(p_forward.dot(p_up)),
		absf(p_right.dot(p_up)),
	]
	var max_unit_error: float = unit_errors.max()
	var max_dot_error: float = dot_errors.max()
	if max_unit_error > FRAME_COHERENCE_TOLERANCE or max_dot_error > FRAME_COHERENCE_TOLERANCE:
		return _refuse(
			Refusal.FRAME_NUMERICS_INCONSISTENT,
			"derived frame is not unit/orthogonal within the float32 coherence tolerance",
			{
				"sample_index": p_sample_index,
				"max_unit_error": max_unit_error,
				"max_dot_error": max_dot_error,
				"tolerance": FRAME_COHERENCE_TOLERANCE,
			}
		)
	var basis_determinant := Basis(p_right, p_up, -p_forward).determinant()
	if not is_finite(basis_determinant):
		return _refuse(
			Refusal.NONFINITE_DERIVED_STATE,
			"derived frame basis determinant became nonfinite",
			{"sample_index": p_sample_index}
		)
	if absf(basis_determinant - 1.0) > FRAME_COHERENCE_TOLERANCE:
		return _refuse(
			Refusal.FRAME_NUMERICS_INCONSISTENT,
			"derived frame basis is not right-handed within tolerance",
			{
				"sample_index": p_sample_index,
				"basis_determinant": basis_determinant,
				"tolerance": FRAME_COHERENCE_TOLERANCE,
			}
		)
	return {}


# --- Small utilities ----------------------------------------------------------


static func _finite_vector3(p_vector: Vector3) -> bool:
	return is_finite(p_vector.x) and is_finite(p_vector.y) and is_finite(p_vector.z)


static func _is_number(p_value: Variant) -> bool:
	return typeof(p_value) == TYPE_FLOAT or typeof(p_value) == TYPE_INT


static func _refuse(p_code: int, p_error: String, p_diagnostic: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"code": p_code,
		"code_name": refusal_name(p_code),
		"error": p_error,
		"diagnostic": p_diagnostic.duplicate(true),
		"frame_table": null,
	}
