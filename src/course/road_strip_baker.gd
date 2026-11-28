class_name RoadStripBaker
extends RefCounted

const RoadTransportFrame := preload("res://src/course/road_transport_frame.gd")

## Deterministic driving-strip mesh and collision baker for an OPEN
## `RoadTransportFrame.FrameTable` (`roadstorm.road_frame_table.v1`).
##
## This is a bounded provisional M2.1 slice only. It consumes the public
## accessors of a frame table the transport slice already accepted, lays out
## the driving strip between every adjacent frame pair, and emits one
## `ArrayMesh` surface plus one matching `ConcavePolygonShape3D` per chunk. It
## does not bake shoulders, barriers, terrain skirts, thickness, end caps,
## LODs, materials or scene nodes; does not detect or close a geometrically
## closed course (closed-loop closure is a later slice); does not build gates,
## AI samples or minimaps; and does not certify drivability or M2.1
## acceptance.
##
## Row geometry. Each frame contributes one row of two vertices at
## `position -/+ right * width_m / 2`, both with the frame's `up` as their
## normal. UVs are `(lateral, s)`: `uv.x` is 0 at the left edge and 1 at the
## right edge, `uv.y` is the station `s` in metres, unscaled.
##
## Triangulation. Adjacent rows i and i+1 form a quad split along the
## right_i to left_{i+1} diagonal into `(left_i, left_{i+1}, right_i)` and
## `(right_i, left_{i+1}, right_{i+1})`. Godot renders CLOCKWISE winding as
## the front face, so each triangle's right-hand-rule cross product points
## opposite the preceding frame's `up`: the road top is the render front and
## the one-sided concave collision face. This is verified before any resource
## exists; an inverted or collapsed quad is refused.
##
## Chunking. Segments are cut into chunks of at most `max_segments_per_chunk`
## segments (default 32, hard cap 1024). Chunk c owns segments
## `[c*K, min((c+1)*K, segment_count))`, i.e. frames `[c*K, last+1]`. Every
## row is laid out exactly once and copied into the chunks that need it, so
## the boundary row shared by adjacent chunks is duplicated bit-exactly.
##
## Segment metadata. Segment i owns the half-open station interval
## `[s_i, s_{i+1})` and carries the `section_id`/`surface_id` of its preceding
## frame i, matching the sampler's half-open span ownership: a station exactly
## on an interior knot boundary belongs to the following span. Surface is
## never inferred from collision face indices. One chunk has one
## `ConcavePolygonShape3D` and cannot distinguish surfaces, so consumers map
## a contact position to the ordered segment table instead.
##
## Output policy. The table is validated again defensively and every row and
## triangle is laid out before any engine resource is created. Every refusal
## returns a stable `code`, `code_name`, a readable `error`, a machine-readable
## `diagnostic`, `bake:null` and `chunks:[]`, with no partial mesh or shape.
## Success returns a `Bake` whose `chunks` hold the resources. The bake is
## pure with respect to its inputs and global state (no randomness, time or
## scene tree); the same table and options produce the same resources. As with
## the sibling slices, GDScript's `Object.set` private-member escape is a
## documented residual rather than part of the API.

const RESULT_SCHEMA := "roadstorm.road_strip_bake.v1"

const DEFAULT_MAX_SEGMENTS_PER_CHUNK := 32
const MAX_SEGMENTS_PER_CHUNK_LIMIT := 1024
const OPTION_MAX_SEGMENTS_PER_CHUNK := "max_segments_per_chunk"

## Frame fields this baker consumes. The remaining frame fields (`basis`,
## `bank_deg`, `grade_dy_ds`, `span_index`, `span_t`, `sample_role`) are not
## read and are not revalidated here.
const FRAME_REQUIRED_KEYS: Array = [
	"index",
	"s",
	"position",
	"forward",
	"right",
	"up",
	"width_m",
	"section_id",
	"surface_id",
]
const FRAME_AXIS_KEYS: Array = ["forward", "right", "up"]
const FRAME_ID_KEYS: Array = ["section_id", "surface_id"]

## Provisional floors. A station interval below MIN_STATION_INTERVAL_M or a
## triangle below MIN_TRIANGLE_AREA_M2 is not meaningful road geometry and
## would collapse in float32 engine vectors.
const MIN_STATION_INTERVAL_M := 1.0e-6
const MIN_TRIANGLE_AREA_M2 := 1.0e-6
## Same coherence tolerance as the transport frame's own frame check.
const FRAME_AXIS_TOLERANCE := 0.0001

const UV_LEFT := 0.0
const UV_RIGHT := 1.0

const WINDING_POLICY := (
	"per segment (left_i, left_i+1, right_i) and (right_i, left_i+1, "
	+ "right_i+1): (v1-v0).cross(v2-v0) points opposite the preceding "
	+ "frame's up; Godot's clockwise front face is the road top for "
	+ "CULL_BACK materials and one-sided concave shapes"
)
const UV_POLICY := (
	"uv.x = lateral (0 left edge, 1 right edge); uv.y = station s in metres, "
	+ "unscaled"
)
const SEGMENT_METADATA_POLICY := (
	"segment i owns [s_i, s_i+1) and the section_id/surface_id of its "
	+ "preceding frame i; surface is never inferred from collision face indices"
)
const CHUNK_POLICY := (
	"at most max_segments_per_chunk segments per chunk; chunk c owns segments "
	+ "[c*K, min((c+1)*K, segment_count)) and frames [c*K, last+1]; the shared "
	+ "boundary row is duplicated bit-exactly"
)

## Stable refusal codes. Every refusal also carries `code_name`, a readable
## `error`, a machine-readable `diagnostic`, `bake:null` and `chunks:[]`.
enum Refusal {
	NONE = 0,
	BAD_TABLE,
	CLOSED_LOOP_UNSUPPORTED,
	TABLE_INCONSISTENT,
	TOO_FEW_FRAMES,
	BAD_FRAME,
	NONMONOTONIC_STATIONS,
	TINY_INTERVAL,
	BAD_WIDTH,
	BAD_FRAME_AXES,
	BAD_OPTIONS,
	NONFINITE_VERTEX,
	NONFINITE_DERIVED_STATE,
	DEGENERATE_TRIANGLE,
	FLIPPED_TRIANGLE,
}

const REFUSAL_NAMES := {
	Refusal.NONE: "none",
	Refusal.BAD_TABLE: "bad_table",
	Refusal.CLOSED_LOOP_UNSUPPORTED: "closed_loop_unsupported",
	Refusal.TABLE_INCONSISTENT: "table_inconsistent",
	Refusal.TOO_FEW_FRAMES: "too_few_frames",
	Refusal.BAD_FRAME: "bad_frame",
	Refusal.NONMONOTONIC_STATIONS: "nonmonotonic_stations",
	Refusal.TINY_INTERVAL: "tiny_interval",
	Refusal.BAD_WIDTH: "bad_width",
	Refusal.BAD_FRAME_AXES: "bad_frame_axes",
	Refusal.BAD_OPTIONS: "bad_options",
	Refusal.NONFINITE_VERTEX: "nonfinite_vertex",
	Refusal.NONFINITE_DERIVED_STATE: "nonfinite_derived_state",
	Refusal.DEGENERATE_TRIANGLE: "degenerate_triangle",
	Refusal.FLIPPED_TRIANGLE: "flipped_triangle",
}


# --- Result containers -------------------------------------------------------


## One laid-out frame row. Built once per frame and copied into every chunk
## that needs it, which is what makes shared boundary rows bit-exact.
class StripRow extends RefCounted:
	var _frame_index := 0
	var _station := 0.0
	var _left := Vector3.ZERO
	var _right := Vector3.ZERO
	var _up := Vector3.UP
	var _section_id := ""
	var _surface_id := ""


## One baked segment: the quad between frames i and i+1 with the metadata of
## its preceding frame.
class StripSegment extends RefCounted:
	var _segment_index := 0
	var _s_start := 0.0
	var _s_end := 0.0
	var _section_id := ""
	var _surface_id := ""

	## Machine-readable copy. `row_vertex_base` is the vertex index of the
	## segment's start-row left vertex inside its chunk (each row has two
	## vertices, the segment uses four); `index_base` is the offset of the
	## segment's first index inside the chunk's index array (two triangles,
	## six indices, in the order documented by WINDING_POLICY).
	func to_dictionary(p_chunk_segment_index: int) -> Dictionary:
		return {
			"segment_index": _segment_index,
			"start_frame_index": _segment_index,
			"end_frame_index": _segment_index + 1,
			"chunk_segment_index": p_chunk_segment_index,
			"s_start": _s_start,
			"s_end": _s_end,
			"section_id": _section_id,
			"surface_id": _surface_id,
			"row_vertex_base": p_chunk_segment_index * 2,
			"index_base": p_chunk_segment_index * 6,
			"triangle_count": 2,
		}


## One baked chunk: a single triangle `ArrayMesh` surface, the matching
## concave shape with the same triangles in the same order, and the metadata
## of the segments it holds.
class Chunk extends RefCounted:
	var _chunk_index := 0
	var _first_frame_index := 0
	var _last_frame_index := 0
	var _s_start := 0.0
	var _s_end := 0.0
	var _mesh: ArrayMesh = null
	var _shape: ConcavePolygonShape3D = null
	var _segments: Array = []

	var chunk_index: int: get = _get_chunk_index
	var first_frame_index: int: get = _get_first_frame_index
	var last_frame_index: int: get = _get_last_frame_index
	var s_start: float: get = _get_s_start
	var s_end: float: get = _get_s_end
	var segment_count: int: get = _get_segment_count
	var mesh: ArrayMesh: get = _get_mesh
	var shape: ConcavePolygonShape3D: get = _get_shape

	static func make(
		p_chunk_index: int,
		p_first_frame_index: int,
		p_last_frame_index: int,
		p_s_start: float,
		p_s_end: float,
		p_mesh: ArrayMesh,
		p_shape: ConcavePolygonShape3D,
		p_segments: Array
	) -> Chunk:
		var chunk := Chunk.new()
		chunk._chunk_index = p_chunk_index
		chunk._first_frame_index = p_first_frame_index
		chunk._last_frame_index = p_last_frame_index
		chunk._s_start = p_s_start
		chunk._s_end = p_s_end
		chunk._mesh = p_mesh
		chunk._shape = p_shape
		chunk._segments = p_segments.duplicate(true)
		return chunk

	func _get_chunk_index() -> int:
		return _chunk_index

	func _get_first_frame_index() -> int:
		return _first_frame_index

	func _get_last_frame_index() -> int:
		return _last_frame_index

	func _get_s_start() -> float:
		return _s_start

	func _get_s_end() -> float:
		return _s_end

	func _get_segment_count() -> int:
		return _segments.size()

	func _get_mesh() -> ArrayMesh:
		return _mesh

	func _get_shape() -> ConcavePolygonShape3D:
		return _shape

	## Ordered segment records for this chunk, as deep copies.
	func segments() -> Array:
		return _segments.duplicate(true)

	func vertex_count() -> int:
		return (_last_frame_index - _first_frame_index + 1) * 2

	func triangle_count() -> int:
		return _segments.size() * 2

	func summary() -> Dictionary:
		return {
			"chunk_index": _chunk_index,
			"first_frame_index": _first_frame_index,
			"last_frame_index": _last_frame_index,
			"s_start": _s_start,
			"s_end": _s_end,
			"segment_count": _segments.size(),
			"vertex_count": vertex_count(),
			"triangle_count": triangle_count(),
			"face_count": triangle_count(),
			"segments": segments(),
		}


## A successful bake. The mesh and shape resources are shared references to
## the baked resources; treat them as immutable.
class Bake extends RefCounted:
	var _course_id := ""
	var _revision := ""
	var _frame_count := 0
	var _max_segments_per_chunk := 0
	var _chunks: Array = []

	var schema: String: get = _get_schema
	var course_id: String: get = _get_course_id
	var revision: String: get = _get_revision
	var frame_count: int: get = _get_frame_count
	var segment_count: int: get = _get_segment_count
	var chunk_count: int: get = _get_chunk_count
	var max_segments_per_chunk: int: get = _get_max_segments_per_chunk
	var shared_boundary_count: int: get = _get_shared_boundary_count
	var chunks: Array: get = _get_chunks

	static func make(
		p_course_id: String,
		p_revision: String,
		p_frame_count: int,
		p_max_segments_per_chunk: int,
		p_chunks: Array
	) -> Bake:
		var bake := Bake.new()
		bake._course_id = p_course_id
		bake._revision = p_revision
		bake._frame_count = p_frame_count
		bake._max_segments_per_chunk = p_max_segments_per_chunk
		bake._chunks = p_chunks.duplicate()
		return bake

	func _get_schema() -> String:
		return RESULT_SCHEMA

	func _get_course_id() -> String:
		return _course_id

	func _get_revision() -> String:
		return _revision

	func _get_frame_count() -> int:
		return _frame_count

	func _get_segment_count() -> int:
		return _frame_count - 1

	func _get_chunk_count() -> int:
		return _chunks.size()

	func _get_max_segments_per_chunk() -> int:
		return _max_segments_per_chunk

	func _get_shared_boundary_count() -> int:
		return maxi(_chunks.size() - 1, 0)

	func _get_chunks() -> Array:
		return _chunks.duplicate()

	func vertex_count() -> int:
		var total := 0
		for chunk in _chunks:
			total += (chunk as Chunk).vertex_count()
		return total

	func triangle_count() -> int:
		var total := 0
		for chunk in _chunks:
			total += (chunk as Chunk).triangle_count()
		return total

	## Every segment record in station order, across chunks.
	func segments() -> Array:
		var out: Array = []
		for chunk in _chunks:
			out.append_array((chunk as Chunk).segments())
		return out

	func summary() -> Dictionary:
		var chunk_summaries: Array = []
		for chunk in _chunks:
			chunk_summaries.append((chunk as Chunk).summary())
		return {
			"schema": RESULT_SCHEMA,
			"frame_table_schema": RoadTransportFrame.RESULT_SCHEMA,
			"course_id": _course_id,
			"revision": _revision,
			"frame_count": _frame_count,
			"segment_count": segment_count,
			"chunk_count": _chunks.size(),
			"max_segments_per_chunk": _max_segments_per_chunk,
			"shared_boundary_count": shared_boundary_count,
			"vertex_count": vertex_count(),
			"triangle_count": triangle_count(),
			"winding_policy": WINDING_POLICY,
			"uv_policy": UV_POLICY,
			"segment_metadata_policy": SEGMENT_METADATA_POLICY,
			"chunk_policy": CHUNK_POLICY,
			"chunks": chunk_summaries,
		}


# --- Public baking -----------------------------------------------------------


static func default_options() -> Dictionary:
	return {OPTION_MAX_SEGMENTS_PER_CHUNK: DEFAULT_MAX_SEGMENTS_PER_CHUNK}


## Bakes the driving strip of an open frame table. Options: only
## `max_segments_per_chunk` (int, 1..MAX_SEGMENTS_PER_CHUNK_LIMIT, default
## 32). On success returns {"ok":true,"code":0,"code_name":"none",
## "error":"","diagnostic":<bake summary>,"bake":Bake,"chunks":Array[Chunk]}.
## On failure `bake` is null and `chunks` is empty, and no mesh or shape
## resource has been created. This is the canonical entry point.
static func bake_open_strip(p_table: Variant, p_options: Dictionary = {}) -> Dictionary:
	if typeof(p_table) != TYPE_OBJECT or not (p_table is RoadTransportFrame.FrameTable):
		return _refuse(
			Refusal.BAD_TABLE,
			"input must be a RoadTransportFrame.FrameTable",
			{"received_type": type_string(typeof(p_table))}
		)
	var table: RoadTransportFrame.FrameTable = p_table

	if table.closed:
		return _refuse(
			Refusal.CLOSED_LOOP_UNSUPPORTED,
			"closed-loop strip baking is not supported in this slice: residual-roll closure and seam matching are a later slice",
			{
				"course_id": table.course_id,
				"closed": true,
				"closed_loop_policy": table.closed_loop_policy,
			}
		)
	if table.schema != RoadTransportFrame.RESULT_SCHEMA:
		return _refuse(
			Refusal.TABLE_INCONSISTENT,
			"table schema is not the road frame table schema",
			{
				"schema": table.schema,
				"expected_schema": RoadTransportFrame.RESULT_SCHEMA,
			}
		)
	if table.frame_count != table.frames.size():
		return _refuse(
			Refusal.TABLE_INCONSISTENT,
			"table frame count does not match its frame array",
			{
				"frame_count_property": table.frame_count,
				"frame_array_size": table.frames.size(),
			}
		)
	if table.frame_count < 2:
		return _refuse(
			Refusal.TOO_FEW_FRAMES,
			"a driving strip needs at least a start and an end frame",
			{"frame_count": table.frame_count}
		)

	var options := _resolve_options(p_options)
	if not bool(options["ok"]):
		return options

	# Rows and triangles are laid out and checked as pure data first, so a
	# refusal can never leave a partially built mesh or shape behind.
	var rows_result := _layout_rows(table)
	if not bool(rows_result["ok"]):
		return rows_result

	var segments_result := _layout_segments(rows_result["rows"])
	if not bool(segments_result["ok"]):
		return segments_result

	var chunks := _build_chunks(
		rows_result["rows"],
		segments_result["segments"],
		int(options["max_segments_per_chunk"])
	)
	var strip_bake := Bake.make(
		table.course_id,
		table.revision,
		table.frame_count,
		int(options["max_segments_per_chunk"]),
		chunks
	)
	return {
		"ok": true,
		"code": Refusal.NONE,
		"code_name": refusal_name(Refusal.NONE),
		"error": "",
		"diagnostic": strip_bake.summary(),
		"bake": strip_bake,
		"chunks": chunks.duplicate(),
	}


static func refusal_name(p_code: int) -> String:
	if REFUSAL_NAMES.has(p_code):
		return str(REFUSAL_NAMES[p_code])
	return "unknown_code_%d" % p_code


# --- Options -----------------------------------------------------------------


static func _resolve_options(p_options: Dictionary) -> Dictionary:
	for key in p_options:
		if str(key) != OPTION_MAX_SEGMENTS_PER_CHUNK:
			return _refuse(
				Refusal.BAD_OPTIONS,
				"unknown bake option",
				{"key": str(key), "known_keys": [OPTION_MAX_SEGMENTS_PER_CHUNK]}
			)
	var max_segments := DEFAULT_MAX_SEGMENTS_PER_CHUNK
	if p_options.has(OPTION_MAX_SEGMENTS_PER_CHUNK):
		var value: Variant = p_options[OPTION_MAX_SEGMENTS_PER_CHUNK]
		if typeof(value) != TYPE_INT:
			return _refuse(
				Refusal.BAD_OPTIONS,
				"max_segments_per_chunk must be an integer",
				{
					"key": OPTION_MAX_SEGMENTS_PER_CHUNK,
					"received_type": type_string(typeof(value)),
				}
			)
		max_segments = int(value)
	if max_segments < 1 or max_segments > MAX_SEGMENTS_PER_CHUNK_LIMIT:
		return _refuse(
			Refusal.BAD_OPTIONS,
			"max_segments_per_chunk is outside the supported range",
			{
				"key": OPTION_MAX_SEGMENTS_PER_CHUNK,
				"value": max_segments,
				"min": 1,
				"max": MAX_SEGMENTS_PER_CHUNK_LIMIT,
			}
		)
	return {"ok": true, "max_segments_per_chunk": max_segments}


# --- Row layout --------------------------------------------------------------


## Validates every consumed frame field and lays out the row vertices. Pure
## data: no engine resource is created here.
static func _layout_rows(p_table: RoadTransportFrame.FrameTable) -> Dictionary:
	var frames: Array = p_table.frames
	var rows: Array = []
	var previous_station := 0.0

	for index in range(frames.size()):
		if typeof(frames[index]) != TYPE_DICTIONARY:
			return _refuse(
				Refusal.BAD_FRAME,
				"frame is not a dictionary",
				{"frame_index": index, "received_type": type_string(typeof(frames[index]))}
			)
		var frame: Dictionary = frames[index]
		for key in FRAME_REQUIRED_KEYS:
			if not frame.has(key):
				return _refuse(
					Refusal.BAD_FRAME,
					"frame is missing required key '%s'" % str(key),
					{"frame_index": index, "missing_key": str(key)}
				)
		if typeof(frame["index"]) != TYPE_INT or int(frame["index"]) != index:
			return _refuse(
				Refusal.TABLE_INCONSISTENT,
				"frame index does not match its ordered position",
				{"frame_index": index, "recorded_index": frame["index"]}
			)

		if not _is_number(frame["s"]):
			return _refuse(
				Refusal.BAD_FRAME,
				"frame station is not numeric",
				{"frame_index": index, "key": "s", "received": str(frame["s"])}
			)
		var station := float(frame["s"])
		if not is_finite(station):
			return _refuse(
				Refusal.BAD_FRAME,
				"frame station is nonfinite",
				{"frame_index": index, "key": "s"}
			)
		if index > 0:
			if station <= previous_station:
				return _refuse(
					Refusal.NONMONOTONIC_STATIONS,
					"frame stations are not strictly increasing",
					{
						"frame_index": index,
						"previous_s": previous_station,
						"station_s": station,
					}
				)
			var interval := station - previous_station
			if interval < MIN_STATION_INTERVAL_M:
				return _refuse(
					Refusal.TINY_INTERVAL,
					"frame station interval is below the minimum driving-strip interval",
					{
						"frame_index": index,
						"interval_m": interval,
						"min_interval_m": MIN_STATION_INTERVAL_M,
					}
				)
		previous_station = station

		if typeof(frame["position"]) != TYPE_VECTOR3:
			return _refuse(
				Refusal.BAD_FRAME,
				"frame position is not a Vector3",
				{
					"frame_index": index,
					"key": "position",
					"received_type": type_string(typeof(frame["position"])),
				}
			)
		var position: Vector3 = frame["position"]
		if not _finite_vector3(position):
			return _refuse(
				Refusal.BAD_FRAME,
				"frame position is nonfinite",
				{"frame_index": index, "key": "position"}
			)

		for key in FRAME_AXIS_KEYS:
			if typeof(frame[key]) != TYPE_VECTOR3:
				return _refuse(
					Refusal.BAD_FRAME,
					"frame %s is not a Vector3" % str(key),
					{
						"frame_index": index,
						"key": str(key),
						"received_type": type_string(typeof(frame[key])),
					}
				)
			if not _finite_vector3(frame[key]):
				return _refuse(
					Refusal.BAD_FRAME_AXES,
					"frame %s is nonfinite" % str(key),
					{"frame_index": index, "key": str(key)}
				)
		var forward: Vector3 = frame["forward"]
		var right: Vector3 = frame["right"]
		var up: Vector3 = frame["up"]
		var unit_errors := [
			absf(forward.length() - 1.0),
			absf(right.length() - 1.0),
			absf(up.length() - 1.0),
		]
		var dot_errors := [
			absf(forward.dot(right)),
			absf(forward.dot(up)),
			absf(right.dot(up)),
		]
		var max_unit_error: float = unit_errors.max()
		var max_dot_error: float = dot_errors.max()
		if max_unit_error > FRAME_AXIS_TOLERANCE or max_dot_error > FRAME_AXIS_TOLERANCE:
			return _refuse(
				Refusal.BAD_FRAME_AXES,
				"frame axes are not unit/orthogonal within the coherence tolerance",
				{
					"frame_index": index,
					"max_unit_error": max_unit_error,
					"max_dot_error": max_dot_error,
					"tolerance": FRAME_AXIS_TOLERANCE,
				}
			)
		var handedness := Basis(right, up, -forward).determinant()
		if not is_finite(handedness) or absf(handedness - 1.0) > FRAME_AXIS_TOLERANCE:
			return _refuse(
				Refusal.BAD_FRAME_AXES,
				"frame axes are not right-handed within the coherence tolerance",
				{
					"frame_index": index,
					"basis_determinant": handedness,
					"tolerance": FRAME_AXIS_TOLERANCE,
				}
			)

		if not _is_number(frame["width_m"]):
			return _refuse(
				Refusal.BAD_FRAME,
				"frame width_m is not numeric",
				{"frame_index": index, "key": "width_m", "received": str(frame["width_m"])}
			)
		var width := float(frame["width_m"])
		if not is_finite(width):
			return _refuse(
				Refusal.BAD_WIDTH,
				"frame width_m is nonfinite",
				{"frame_index": index}
			)
		if width <= 0.0:
			return _refuse(
				Refusal.BAD_WIDTH,
				"frame width_m is not positive",
				{"frame_index": index, "width_m": width}
			)

		for key in FRAME_ID_KEYS:
			if typeof(frame[key]) != TYPE_STRING or str(frame[key]).strip_edges().is_empty():
				return _refuse(
					Refusal.BAD_FRAME,
					"frame %s is not a non-empty string" % str(key),
					{"frame_index": index, "key": str(key), "received": str(frame[key])}
				)

		var half_width := width * 0.5
		var left := position - right * half_width
		var right_edge := position + right * half_width
		if not _finite_vector3(left) or not _finite_vector3(right_edge):
			return _refuse(
				Refusal.NONFINITE_VERTEX,
				"a driving-strip edge vertex is nonfinite",
				{"frame_index": index}
			)

		var row := StripRow.new()
		row._frame_index = index
		row._station = station
		row._left = left
		row._right = right_edge
		row._up = up
		row._section_id = str(frame["section_id"])
		row._surface_id = str(frame["surface_id"])
		rows.append(row)

	var first_frame: Dictionary = frames[0]
	var last_frame: Dictionary = frames[frames.size() - 1]
	var first_station := float(first_frame["s"])
	var last_station := float(last_frame["s"])
	if first_station != 0.0:
		return _refuse(
			Refusal.TABLE_INCONSISTENT,
			"frame table does not start at s=0",
			{"first_s": first_station}
		)
	if last_station != p_table.total_length_m:
		return _refuse(
			Refusal.TABLE_INCONSISTENT,
			"frame table does not end at its total length",
			{
				"last_s": last_station,
				"total_length_m": p_table.total_length_m,
			}
		)

	return {"ok": true, "rows": rows}


# --- Triangle layout ---------------------------------------------------------


## Lays out and verifies the two triangles of every segment. The vertex
## triples here are exactly the index triples `_build_chunks` emits. Pure
## data: no engine resource is created here.
static func _layout_segments(p_rows: Array) -> Dictionary:
	var segments: Array = []
	for index in range(p_rows.size() - 1):
		var start_row: StripRow = p_rows[index]
		var end_row: StripRow = p_rows[index + 1]
		var first := _check_triangle(
			start_row._left, end_row._left, start_row._right, start_row._up, index, "left"
		)
		if not bool(first["ok"]):
			return first
		var second := _check_triangle(
			start_row._right, end_row._left, end_row._right, start_row._up, index, "right"
		)
		if not bool(second["ok"]):
			return second
		var segment := StripSegment.new()
		segment._segment_index = index
		segment._s_start = start_row._station
		segment._s_end = end_row._station
		segment._section_id = start_row._section_id
		segment._surface_id = start_row._surface_id
		segments.append(segment)
	return {"ok": true, "segments": segments}


static func _check_triangle(
	p_v0: Vector3,
	p_v1: Vector3,
	p_v2: Vector3,
	p_up: Vector3,
	p_segment_index: int,
	p_triangle: String
) -> Dictionary:
	var where := {"segment_index": p_segment_index, "triangle": p_triangle}
	var normal := (p_v1 - p_v0).cross(p_v2 - p_v0)
	if not _finite_vector3(normal):
		return _refuse(
			Refusal.NONFINITE_DERIVED_STATE,
			"triangle cross product is nonfinite",
			where
		)
	var double_area := normal.length()
	if not is_finite(double_area):
		return _refuse(
			Refusal.NONFINITE_DERIVED_STATE,
			"triangle cross product length is nonfinite",
			where
		)
	var area := double_area * 0.5
	if area < MIN_TRIANGLE_AREA_M2:
		return _refuse(
			Refusal.DEGENERATE_TRIANGLE,
			"triangle area is below the minimum driving-strip area",
			{
				"segment_index": p_segment_index,
				"triangle": p_triangle,
				"area_m2": area,
				"min_area_m2": MIN_TRIANGLE_AREA_M2,
			}
		)
	var alignment := normal.dot(p_up)
	if not is_finite(alignment):
		return _refuse(
			Refusal.NONFINITE_DERIVED_STATE,
			"triangle alignment with road up is nonfinite",
			where
		)
	if alignment >= 0.0:
		return _refuse(
			Refusal.FLIPPED_TRIANGLE,
			"triangle winding does not face the road top under Godot's clockwise convention",
			{
				"segment_index": p_segment_index,
				"triangle": p_triangle,
				"up_alignment": alignment,
				"winding_policy": WINDING_POLICY,
			}
		)
	return {"ok": true, "area_m2": area, "up_alignment": alignment}


# --- Chunk assembly ----------------------------------------------------------


## Creates the engine resources. Only reached after every row and triangle has
## been laid out and verified, so nothing here can refuse.
static func _build_chunks(p_rows: Array, p_segments: Array, p_max_segments: int) -> Array:
	var segment_count := p_segments.size()
	var chunk_count := ceili(float(segment_count) / float(p_max_segments))
	var chunks: Array = []

	for chunk_index in range(chunk_count):
		# Segment k spans frames k and k+1, so segments [first, end) span
		# frames [first, end]; frame `end` is the row the next chunk starts
		# with, copied from the same StripRow so it is bit-exact.
		var first_segment := chunk_index * p_max_segments
		var end_segment := mini(first_segment + p_max_segments, segment_count)
		var segment_count_here := end_segment - first_segment

		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var indices := PackedInt32Array()
		for frame_index in range(first_segment, end_segment + 1):
			var row: StripRow = p_rows[frame_index]
			vertices.append(row._left)
			vertices.append(row._right)
			normals.append(row._up)
			normals.append(row._up)
			uvs.append(Vector2(UV_LEFT, row._station))
			uvs.append(Vector2(UV_RIGHT, row._station))
		for chunk_segment_index in range(segment_count_here):
			var base := chunk_segment_index * 2
			var next := base + 2
			indices.append(base)
			indices.append(next)
			indices.append(base + 1)
			indices.append(base + 1)
			indices.append(next)
			indices.append(next + 1)

		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

		# The collision faces are the same triangles in the same order as the
		# surface's index array, expanded to a triangle soup.
		var faces := PackedVector3Array()
		for offset in range(0, indices.size(), 3):
			faces.append(vertices[indices[offset]])
			faces.append(vertices[indices[offset + 1]])
			faces.append(vertices[indices[offset + 2]])
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		# One-sided faces, matching the handling-lab precedent. The emitted
		# clockwise winding faces the road top; a ray from above can support a
		# vehicle without enabling collision from underneath.
		shape.backface_collision = false

		var segment_records: Array = []
		for chunk_segment_index in range(segment_count_here):
			var segment: StripSegment = p_segments[first_segment + chunk_segment_index]
			segment_records.append(segment.to_dictionary(chunk_segment_index))

		chunks.append(
			Chunk.make(
				chunk_index,
				first_segment,
				end_segment,
				(p_rows[first_segment] as StripRow)._station,
				(p_rows[end_segment] as StripRow)._station,
				mesh,
				shape,
				segment_records
			)
		)
	return chunks


# --- Small utilities ---------------------------------------------------------


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
		"bake": null,
		"chunks": [],
	}
