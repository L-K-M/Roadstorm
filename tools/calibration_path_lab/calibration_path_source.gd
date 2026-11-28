class_name CalibrationPathSource
extends RefCounted
## Deterministic conversion of the authored HandlingLab sweeper centerline
## into a `CalibrationDriver.CalibrationPath`.
##
## Authority:
##   * `src/laboratory/handling_lab_data.gd` owns the authored bay table;
##   * `src/laboratory/handling_lab_builder.gd` owns the centerline sampling
##     (`_sample_bay`, a private function called here as a labelled provisional
##     seam);
##   * `src/simulation/motor_body_adapter.gd` owns the world-XZ to road-plane
##     mapping used by the committed `CarState` integrator.
##
## No geometry is re-derived here. If the authored sweeper changes, build()
## refuses instead of substituting a hard-coded fallback. Target speeds are
## provisional authored lab values, not measured or tuned calibration data.

const DataScript = preload("res://src/laboratory/handling_lab_data.gd")
const BuilderScript = preload("res://src/laboratory/handling_lab_builder.gd")
const DriverScript = preload("res://src/calibration/calibration_driver.gd")
const AdapterScript = preload("res://src/simulation/motor_body_adapter.gd")

const SOURCE_SCHEMA := "roadstorm.calibration_path.source_summary.v1"
const SWEEPER_BAY_ID := "sweeper"
const FIXTURE_PATH := "res://fixtures/handling/sweeper.json"
const EXPECTED_FIXTURE_ID := "fixture.handling.sweeper"

## Version of the produced path. The `_provisional` marker is deliberate.
const PATH_VERSION := "roadstorm.calibration_path.sweeper_handling_lab_provisional.v1"

## Provisional target speed for every sample. Same authored preliminary lab
## value family as tools/calibration_physics_lab; it is not a measured corner
## speed, not a tuned reference and not evidence that the car can hold it.
const PROVISIONAL_TARGET_SPEED_M_S := 12.0
const TARGET_SPEED_PROVENANCE := (
	"authored_preliminary_lab_value_not_measured_or_tuned"
)
const SAMPLING_SEAM_NOTICE := (
	"HandlingLabBuilder._sample_bay is private; this conversion calls it "
	+ "directly as a provisional seam. It is not a production-stable API and "
	+ "may change with the M1.2 graybox laboratory."
)

## Pinned authored sweeper signature. This is a guard, not a generator: it is
## compared against both the live bay table and the live fixture, and any
## disagreement fails the build. The station total below follows from the
## fixture's 120 m centerline radius and 90-degree arc (r*theta = 188.4956 m),
## not from treating "120 m" as an arc length.
const EXPECTED_ORIGIN := Vector3(0.0, 0.0, 60.0)
const EXPECTED_YAW_DEG := 0.0
const EXPECTED_APPROACH_LENGTH_M := 50.0
const EXPECTED_ARC_RADIUS_M := 120.0
const EXPECTED_ARC_ANGLE_DEG := 90.0
const EXPECTED_EXIT_LENGTH_M := 50.0
const EXPECTED_ROAD_WIDTH_M := 12.0
const EXPECTED_SURFACE_ID := "asphalt"
const EXPECTED_ARC_LENGTH_M := EXPECTED_ARC_RADIUS_M * PI * 0.5
const EXPECTED_TOTAL_LENGTH_M := (
	EXPECTED_APPROACH_LENGTH_M + EXPECTED_ARC_LENGTH_M + EXPECTED_EXIT_LENGTH_M
)

const FLOAT_TOLERANCE := 1e-6


static func build(
	p_bay_override: Dictionary = {},
	p_fixture_override: Dictionary = {},
	p_missing_bay: bool = false,
	p_missing_fixture: bool = false
) -> Dictionary:
	## Build the path from the live authored data. Overrides and the two
	## missing-source flags exist only for negative controls; with defaults,
	## every value comes from the live authored sources.
	var bay: Dictionary = p_bay_override
	if p_missing_bay:
		bay = {}
	elif bay.is_empty():
		bay = _live_sweeper_bay()
	if bay.is_empty():
		return _fail("authored sweeper bay is missing from HandlingLabData.bays()")

	var shape_error := _validate_bay_shape(bay)
	if not shape_error.is_empty():
		return _fail("authored sweeper shape refused: " + shape_error)

	var fixture_doc := p_fixture_override
	if p_missing_fixture:
		fixture_doc = {}
	elif fixture_doc.is_empty():
		var loaded := _load_fixture_document()
		if loaded.is_empty():
			return _fail("missing or unreadable fixture " + FIXTURE_PATH)
		fixture_doc = loaded
	var fixture_error := _validate_fixture(fixture_doc, bay)
	if not fixture_error.is_empty():
		return _fail("fixture data refused: " + fixture_error)

	var sampled: Dictionary = BuilderScript._sample_bay(bay)
	if not sampled.has_all(["samples", "sections"]):
		return _fail("builder sampling seam returned no samples/sections")

	var samples: Array = sampled["samples"]
	var sections: Array = sampled["sections"]
	var filtered := _filter_join_duplicates(samples, sections)
	if not bool(filtered["ok"]):
		return _fail("builder samples refused: " + String(filtered["error"]))
	var unique_samples: Array = filtered["samples"]

	var path := _build_path(unique_samples)
	if path == null or not path.is_valid():
		var detail := "unknown path construction failure"
		if path != null:
			detail = path.validation_error()
		return _fail("CalibrationPath validation failed: " + detail)

	return {
		"ok": true,
		"error": "",
		"path": path,
		"summary": _summarize(
			path,
			unique_samples,
			sections,
			bay,
			fixture_doc,
			samples.size(),
			int(filtered["join_duplicates_skipped"])
		),
	}


static func _live_sweeper_bay() -> Dictionary:
	for candidate in DataScript.bays():
		if String(candidate["bay_id"]) == SWEEPER_BAY_ID:
			return candidate
	return {}


static func _load_fixture_document() -> Dictionary:
	if not FileAccess.file_exists(FIXTURE_PATH):
		return {}
	var text := FileAccess.get_file_as_string(FIXTURE_PATH)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


# --- Authored-shape guard -------------------------------------------------


static func _validate_bay_shape(bay: Dictionary) -> String:
	if String(bay.get("bay_id", "")) != SWEEPER_BAY_ID:
		return "bay_id is not %s" % SWEEPER_BAY_ID
	var origin: Vector3 = bay.get("origin", Vector3.INF)
	if not _vec3_close(origin, EXPECTED_ORIGIN, FLOAT_TOLERANCE):
		return "origin %s does not match authored %s" % [str(origin), str(EXPECTED_ORIGIN)]
	if absf(float(bay.get("yaw_deg", NAN)) - EXPECTED_YAW_DEG) > FLOAT_TOLERANCE:
		return "yaw_deg is not 0"

	var segments: Array = bay.get("segments", [])
	if segments.size() != 3:
		return "expected exactly 3 segments, got %d" % segments.size()

	var expected := [
		{
			"type": "straight", "section_id": "sweeper.approach",
			"length_m": EXPECTED_APPROACH_LENGTH_M,
		},
		{
			"type": "arc", "section_id": "sweeper.arc",
			"radius_m": EXPECTED_ARC_RADIUS_M, "angle_deg": EXPECTED_ARC_ANGLE_DEG,
			"direction": "left",
		},
		{
			"type": "straight", "section_id": "sweeper.exit",
			"length_m": EXPECTED_EXIT_LENGTH_M,
		},
	]
	for index in range(3):
		var seg: Dictionary = segments[index]
		var want: Dictionary = expected[index]
		if String(seg.get("type", "")) != String(want["type"]):
			return "segment %d type changed" % index
		if String(seg.get("section_id", "")) != String(want["section_id"]):
			return "segment %d section_id changed" % index
		if absf(float(seg.get("width_m", NAN)) - EXPECTED_ROAD_WIDTH_M) > FLOAT_TOLERANCE:
			return "segment %d width changed" % index
		if String(seg.get("surface_id", "")) != EXPECTED_SURFACE_ID:
			return "segment %d surface changed" % index
		if absf(float(seg.get("lateral_offset_m", NAN))) > FLOAT_TOLERANCE:
			return "segment %d lateral offset changed" % index
		if index != 1:
			if absf(float(seg.get("grade_start_percent", NAN))) > FLOAT_TOLERANCE:
				return "segment %d grade start changed" % index
			if absf(float(seg.get("grade_end_percent", NAN))) > FLOAT_TOLERANCE:
				return "segment %d grade end changed" % index
		if absf(float(seg.get("bank_start_deg", NAN))) > FLOAT_TOLERANCE:
			return "segment %d bank start changed" % index
		if absf(float(seg.get("bank_end_deg", NAN))) > FLOAT_TOLERANCE:
			return "segment %d bank end changed" % index
		if bool(seg.get("restart_at_origin", false)):
			return "segment %d restart flag changed" % index
		match index:
			0, 2:
				if absf(float(seg.get("length_m", NAN)) - float(want["length_m"])) > FLOAT_TOLERANCE:
					return "segment %d length changed" % index
			1:
				if absf(float(seg.get("radius_m", NAN)) - EXPECTED_ARC_RADIUS_M) > FLOAT_TOLERANCE:
					return "arc radius changed"
				if absf(float(seg.get("angle_deg", NAN)) - EXPECTED_ARC_ANGLE_DEG) > FLOAT_TOLERANCE:
					return "arc angle changed"
				if String(seg.get("direction", "")) != "left":
					return "arc direction changed"
	return ""


static func _validate_fixture(doc: Dictionary, bay: Dictionary) -> String:
	if doc.is_empty():
		return "fixture document is empty"
	if String(doc.get("fixture_id", "")) != EXPECTED_FIXTURE_ID:
		return "fixture_id changed"
	if not doc.has("revision") or typeof(doc["revision"]) != TYPE_STRING:
		return "fixture revision missing or not a string"
	var frame: Dictionary = doc.get("coordinate_frame", {})
	var wanted_frame: Dictionary = DataScript.COORDINATE_FRAME
	for key in wanted_frame:
		if String(frame.get(key, "")) != String(wanted_frame[key]):
			return "fixture coordinate_frame changed"

	var geometry: Dictionary = doc.get("geometry", {})
	var fixture_segments: Array = geometry.get("segments", [])
	var bay_segments: Array = bay.get("segments", [])
	if fixture_segments.size() != bay_segments.size():
		return "fixture segment count disagrees with authored bay"
	for index in range(fixture_segments.size()):
		var fseg: Dictionary = fixture_segments[index]
		var bseg: Dictionary = bay_segments[index]
		if String(fseg.get("type", "")) != String(bseg.get("type", "")):
			return "fixture segment %d type disagrees with authored bay" % index
		if absf(float(fseg.get("width_m", NAN)) - float(bseg.get("width_m", NAN))) > FLOAT_TOLERANCE:
			return "fixture segment %d width disagrees with authored bay" % index
		if String(fseg.get("surface_id", "")) != String(bseg.get("surface_id", "")):
			return "fixture segment %d surface disagrees with authored bay" % index
		match index:
			0, 2:
				if absf(float(fseg.get("length_m", NAN)) - float(bseg.get("length_m", NAN))) > FLOAT_TOLERANCE:
					return "fixture segment %d length disagrees with authored bay" % index
			1:
				if absf(float(fseg.get("radius_m", NAN)) - EXPECTED_ARC_RADIUS_M) > FLOAT_TOLERANCE:
					return "fixture arc radius changed"
				if absf(float(fseg.get("angle_deg", NAN)) - EXPECTED_ARC_ANGLE_DEG) > FLOAT_TOLERANCE:
					return "fixture arc angle changed"
				if String(fseg.get("direction", "")) != "left":
					return "fixture arc direction changed"

	var gates: Array = doc.get("timing_gates", [])
	var found_exit_gate := false
	for gate in gates:
		if String(gate.get("gate_id", "")) == "corner_exit":
			found_exit_gate = true
			if absf(float(gate.get("arc_length_m", NAN)) - EXPECTED_ARC_LENGTH_M) > 1e-3:
				return "fixture corner-exit arc length changed"
	if not found_exit_gate:
		return "fixture corner-exit timing gate missing"
	return ""


# --- Sampled-data guard ---------------------------------------------------


static func _validate_samples(samples: Array, sections: Array) -> String:
	var filtered := _filter_join_duplicates(samples, sections)
	if not bool(filtered["ok"]):
		return String(filtered["error"])
	return ""


static func _filter_join_duplicates(samples: Array, sections: Array) -> Dictionary:
	## Validate the builder's raw centerline samples and return the unique
	## centerline points used by CalibrationPath. HandlingLabBuilder deliberately
	## emits the same cross-section twice at an ordinary section join so the two
	## road ribbons abut. That duplicate is metadata for mesh construction, not a
	## second centerline point: accept it only when it is exactly the same position
	## at the exact recorded end/start station of adjacent sections, then skip it.
	## Every other repeated station, decrease, reordering or positional mismatch is
	## a refusal.
	if samples.size() < 2:
		return _filter_fail("fewer than two samples")
	if sections.size() != 3:
		return _filter_fail("expected three section records, got %d" % sections.size())

	var expected_stations := [
		0.0,
		EXPECTED_APPROACH_LENGTH_M,
		EXPECTED_APPROACH_LENGTH_M + EXPECTED_ARC_LENGTH_M,
		EXPECTED_TOTAL_LENGTH_M,
	]
	var section_starts := [0.0, 0.0, 0.0]
	var section_ends := [0.0, 0.0, 0.0]
	for index in range(3):
		var rec: Dictionary = sections[index]
		section_starts[index] = float(rec.get("start_s_m", NAN))
		section_ends[index] = float(rec.get("end_s_m", NAN))
		if absf(section_starts[index] - expected_stations[index]) > 1e-4:
			return _filter_fail("section %d start station changed" % index)
		if absf(section_ends[index] - expected_stations[index + 1]) > 1e-4:
			return _filter_fail("section %d end station changed" % index)
		var length := float(rec.get("length_m", NAN))
		if absf(length - (expected_stations[index + 1] - expected_stations[index])) > 1e-4:
			return _filter_fail("section %d length changed" % index)

	var unique: Array = []
	var skipped := 0
	var previous: Dictionary = {}
	var have_previous := false
	var first := true
	for index in range(samples.size()):
		var smp: Dictionary = samples[index]
		if not smp.has_all(["pos", "s", "right", "lateral_offset", "section_id"]):
			return _filter_fail("sample %d is missing required fields" % index)
		var s := float(smp["s"])
		if not is_finite(s):
			return _filter_fail("sample %d has nonfinite station" % index)
		var pos: Vector3 = smp["pos"]
		if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
			return _filter_fail("sample %d has nonfinite world position" % index)
		var right: Vector3 = smp["right"]
		if not (is_finite(right.x) and is_finite(right.y) and is_finite(right.z)):
			return _filter_fail("sample %d has nonfinite right vector" % index)
		if absf(float(smp["lateral_offset"])) > FLOAT_TOLERANCE:
			return _filter_fail("sample %d has a nonzero lateral offset" % index)
		if not _is_sweeper_section(String(smp["section_id"])):
			return _filter_fail("sample %d carries an unexpected section id" % index)

		if first:
			if absf(s) > FLOAT_TOLERANCE:
				return _filter_fail("first sample station is not zero")
			first = false
		elif have_previous:
			var previous_s := float(previous["s"])
			if s < previous_s:
				return _filter_fail(
					"sample %d decreases station (non-monotonic or reordered)" % index
				)
			if s == previous_s:
				var join_error := _join_duplicate_error(previous, smp, sections)
				if not join_error.is_empty():
					return _filter_fail("sample %d refused: %s" % [index, join_error])
				skipped += 1
				# Ordering is a property of the raw stream. Even when the genuine
				# join duplicate is omitted from the path, it becomes the immediate
				# predecessor for the next validation step; otherwise a third copy of
				# the same boundary sample could be mistaken for another valid join.
				previous = smp
				have_previous = true
				continue

		unique.append(smp)
		previous = smp
		have_previous = true

	if unique.size() < 2:
		return _filter_fail("fewer than two unique samples")
	var last_s := float(unique[unique.size() - 1]["s"])
	if absf(last_s - EXPECTED_TOTAL_LENGTH_M) > 1e-4:
		return _filter_fail(
			"final station %.6f does not match authored total %.6f" % [
				last_s, EXPECTED_TOTAL_LENGTH_M
			]
		)
	return {
		"ok": true,
		"error": "",
		"samples": unique,
		"join_duplicates_skipped": skipped,
	}


static func _join_duplicate_error(
	previous: Dictionary, current: Dictionary, sections: Array
) -> String:
	if bool(current.get("break_before", false)):
		return "repeated station starts a broken run, not a continuous section join"
	if not bool(current.get("joined_prev", false)):
		return "repeated station is not marked as an ordinary section join"
	var previous_pos: Vector3 = previous["pos"]
	var current_pos: Vector3 = current["pos"]
	if previous_pos != current_pos:
		return "section join repeated station is discontinuous (positions differ)"
	var station := float(current["s"])
	for index in range(sections.size() - 1):
		var left: Dictionary = sections[index]
		var right_section: Dictionary = sections[index + 1]
		if String(left.get("section_id", "")) != String(previous["section_id"]):
			continue
		if String(right_section.get("section_id", "")) != String(current["section_id"]):
			continue
		var left_end := float(left.get("end_s_m", NAN))
		var right_start := float(right_section.get("start_s_m", NAN))
		if absf(left_end - right_start) > 1e-4:
			return "adjacent section records do not share the join station"
		if absf(left_end - station) > 1e-4:
			return "repeated station does not match the previous section end"
		if absf(right_start - station) > 1e-4:
			return "repeated station does not match the next section start"
		return ""
	return "repeated station does not join adjacent recorded sections"


static func _filter_fail(message: String) -> Dictionary:
	return {"ok": false, "error": message, "samples": [], "join_duplicates_skipped": 0}


static func _is_sweeper_section(section_id: String) -> bool:
	return (
		section_id == "sweeper.approach"
		or section_id == "sweeper.arc"
		or section_id == "sweeper.exit"
	)


# --- Conversion -----------------------------------------------------------


static func _build_path(samples: Array) -> CalibrationDriver.CalibrationPath:
	var stations: Array = []
	var positions: Array = []
	var speeds: Array = []
	for smp in samples:
		# Apply the builder's lateral offset in world space, then map the
		# resulting world position through the committed adapter mapping.
		var right: Vector3 = smp["right"]
		var world: Vector3 = smp["pos"] + right * float(smp["lateral_offset"])
		var road: Vector2 = AdapterScript.world_vector_to_road(world)
		stations.append(float(smp["s"]))
		positions.append(road)
		speeds.append(PROVISIONAL_TARGET_SPEED_M_S)
	return DriverScript.CalibrationPath.from_arrays(
		stations, positions, speeds, PATH_VERSION
	)


static func _summarize(
	path: CalibrationDriver.CalibrationPath,
	samples: Array,
	sections: Array,
	bay: Dictionary,
	fixture_doc: Dictionary,
	builder_sample_count: int,
	join_duplicates_skipped: int
) -> Dictionary:
	var stations: Array = []
	var positions: Array = []
	var speeds: Array = []
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for sample: DriverScript.PathSample in path.samples:
		stations.append(sample.s_m)
		positions.append([sample.position_m.x, sample.position_m.y])
		speeds.append(sample.target_speed_m_s)
		min_x = minf(min_x, sample.position_m.x)
		max_x = maxf(max_x, sample.position_m.x)
		min_y = minf(min_y, sample.position_m.y)
		max_y = maxf(max_y, sample.position_m.y)

	var section_records: Array = []
	for rec in sections:
		section_records.append({
			"section_id": rec["section_id"],
			"type": rec["type"],
			"start_s_m": rec["start_s_m"],
			"end_s_m": rec["end_s_m"],
			"length_m": rec["length_m"],
			"surface_id": rec.get("surface_id", ""),
		})

	return {
		"schema": SOURCE_SCHEMA,
		"status": "provisional_not_production",
		"path_version": path.version,
		"bay_id": bay["bay_id"],
		"fixture_id": fixture_doc.get("fixture_id", ""),
		"fixture_revision": fixture_doc.get("revision", ""),
		"sample_count": path.samples.size(),
		"builder_sample_count": builder_sample_count,
		"join_duplicates_skipped": join_duplicates_skipped,
		"station_first_m": path.first_s_m(),
		"station_last_m": path.last_s_m(),
		"length_m": path.length_m(),
		"expected_length_m": EXPECTED_TOTAL_LENGTH_M,
		"target_speed_m_s": PROVISIONAL_TARGET_SPEED_M_S,
		"target_speed_provenance": TARGET_SPEED_PROVENANCE,
		"sampling_seam": SAMPLING_SEAM_NOTICE,
		"coordinate_mapping": {
			"authority": "MotorBodyAdapter.world_vector_to_road",
			"world_to_road": "Vector2(world.x, -world.z)",
			"car_state_axes": "+x right, +y forward",
			"builder_world_axes": "+X right, -Z forward, +Y up",
		},
		"bounding_box_m": {
			"min_x": min_x, "max_x": max_x, "min_y": min_y, "max_y": max_y,
		},
		"sections": section_records,
		"stations_m": stations,
		"positions_xy_m": positions,
		"target_speeds_m_s": speeds,
	}


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message, "path": null, "summary": {}}


static func _vec3_close(a: Vector3, b: Vector3, tolerance: float) -> bool:
	return (
		is_finite(a.x) and is_finite(a.y) and is_finite(a.z)
		and absf(a.x - b.x) <= tolerance
		and absf(a.y - b.y) <= tolerance
		and absf(a.z - b.z) <= tolerance
	)
