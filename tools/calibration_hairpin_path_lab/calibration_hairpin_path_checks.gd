class_name CalibrationHairpinPathLabChecks
extends RefCounted
## Discriminatory checks for the HandlingLab hairpin -> CalibrationPath
## conversion. These checks read the live authored laboratory data; they do not
## run physics, drive a car or produce a lap record. Negative controls mutate
## copies of the authored inputs and require the source to refuse them.

const SourceScript = preload(
	"res://tools/calibration_hairpin_path_lab/calibration_hairpin_path_source.gd"
)
const DriverScript = preload("res://src/calibration/calibration_driver.gd")
const AdapterScript = preload("res://src/simulation/motor_body_adapter.gd")

const VECTOR_TOLERANCE := 1e-7
const STATION_TOLERANCE := 1e-4
const ARC_RADIUS_TOLERANCE := 0.01
## The builder integrates the arc as a 1 m sampled polyline, stepping along
## the mid-heading, so each chord endpoint sits slightly outside the ideal
## circle (a replica measured up to +2.73 mm at the arc exit on the 30 m
## radius). The 1 cm positional tolerance is a tight but stable bound for that
## outside offset, while station/order checks remain much stricter.
const POLYLINE_TOLERANCE_M := 0.01
const TURN_TOLERANCE_RAD := 1e-4


class Case extends RefCounted:
	var name := ""
	var checks := 0
	var failures: Array[String] = []
	var measurements: Dictionary = {}

	func check(condition: bool, message: String) -> void:
		checks += 1
		if not condition:
			failures.append(message)

	func close(
		actual: float, expected: float, tolerance: float, message: String
	) -> void:
		checks += 1
		if absf(actual - expected) > tolerance:
			failures.append(
				"%s (got %f expected %f tol %f)"
				% [message, actual, expected, tolerance]
			)

	func equal(actual, expected, message: String) -> void:
		checks += 1
		if actual != expected:
			failures.append(
				"%s (got %s expected %s)" % [message, str(actual), str(expected)]
			)

	func vector_close(
		actual: Vector2, expected: Vector2, tolerance: float, message: String
	) -> void:
		close(actual.x, expected.x, tolerance, message + " x")
		close(actual.y, expected.y, tolerance, message + " y")

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
		Callable(self, "_case_authority_and_shape"),
		Callable(self, "_case_section_identity_and_boundaries"),
		Callable(self, "_case_geometry_turn_and_heading_reversal"),
		Callable(self, "_case_world_to_road_mapping"),
		Callable(self, "_case_repeatability_and_interpolation"),
		Callable(self, "_case_changed_or_missing_source_refusal"),
		Callable(self, "_case_provisional_labels_and_progress_policy"),
		Callable(self, "_case_fail_closed_scalar_guards"),
		Callable(self, "_case_tag_ownership_refusal"),
	]:
		var result: Dictionary = call.call()
		case_results.append(result)
		cases_run += 1
		total_checks += int(result["checks"])
		total_failures += int(result["checks_failed"])
		print(
			"CALIBRATION_HAIRPIN_PATH_LAB_CASE ",
			JSON.stringify({
				"case": result["case"],
				"checks": result["checks"],
				"checks_failed": result["checks_failed"],
				"pass": result["pass"],
			})
		)
	return {
		"schema": "roadstorm.calibration_hairpin_path_lab.summary.v1",
		"pass": total_failures == 0,
		"cases": cases_run,
		"cases_passed": cases_run - _failed_case_count(),
		"checks": total_checks,
		"checks_failed": total_failures,
		"case_results": case_results.duplicate(),
	}


func _failed_case_count() -> int:
	var failed := 0
	for result in case_results:
		if not bool(result["pass"]):
			failed += 1
	return failed


static func _live_bay_copy() -> Dictionary:
	for bay in SourceScript.DataScript.bays():
		if String(bay["bay_id"]) == SourceScript.HAIRPIN_BAY_ID:
			return bay.duplicate(true)
	return {}


static func _fixture_copy() -> Dictionary:
	var doc := SourceScript._load_fixture_document()
	if doc.is_empty():
		return {}
	return doc.duplicate(true)


static func _live_raw_sample() -> Dictionary:
	var bay := _live_bay_copy()
	if bay.is_empty():
		return {}
	return SourceScript.BuilderScript._sample_bay(bay)


# --- Cases ----------------------------------------------------------------


func _case_authority_and_shape() -> Dictionary:
	var c := Case.new()
	c.name = "authority_and_hairpin_shape"

	var built := SourceScript.build()
	c.check(bool(built["ok"]), "live authored conversion must succeed")
	if not bool(built["ok"]):
		return c.result()
	c.equal(String(built["error"]), "", "successful build reports no error")

	var path: DriverScript.CalibrationPath = built["path"]
	c.check(path is DriverScript.CalibrationPath, "result is a CalibrationPath")
	c.check(path.is_valid(), "path validates: " + path.validation_error())
	c.equal(path.version, SourceScript.PATH_VERSION, "path version is pinned")
	c.equal(
		path.samples.size(),
		SourceScript.EXPECTED_UNIQUE_SAMPLE_COUNT,
		"unique sample count follows 1 m builder sampling"
	)

	var summary: Dictionary = built["summary"]
	c.equal(int(summary["sample_count"]), 156, "summary unique sample count matches path")
	c.equal(int(summary["builder_sample_count"]), 158, "builder emits 158 raw samples")
	c.equal(int(summary["join_duplicates_skipped"]), 2, "exactly two genuine join duplicates are skipped")
	c.equal(
		summary["raw_join_duplicate_indices"],
		SourceScript.EXPECTED_JOIN_DUPLICATE_INDICES,
		"raw join duplicates occur at the two authored section joins"
	)
	c.close(
		float(summary["length_m"]),
		SourceScript.EXPECTED_TOTAL_LENGTH_M,
		STATION_TOLERANCE,
		"summary length matches 30 + 30*pi + 30"
	)
	c.close(
		float(summary["length_m"]),
		154.2477796,
		STATION_TOLERANCE,
		"summary length matches the documented 154.2477796 m"
	)
	c.equal(
		String(summary["status"]), "provisional_not_production", "summary status provisional"
	)
	c.equal(
		String(summary["fixture_id"]), SourceScript.EXPECTED_FIXTURE_ID, "fixture identity recorded"
	)
	c.equal(
		String(summary["fixture_revision"]), "1.0.1", "authored fixture revision recorded"
	)

	# Ordered boundary stations are distinct and increasing.
	var boundaries: Array = summary["boundary_stations_m"]
	c.equal(boundaries.size(), 4, "four ordered section boundaries")
	for index in range(4):
		c.close(
			float(boundaries[index]),
			float(SourceScript.EXPECTED_BOUNDARY_STATIONS_M[index]),
			STATION_TOLERANCE,
			"boundary %d station" % index
		)
	for index in range(3):
		c.check(
			float(boundaries[index + 1]) - float(boundaries[index]) > 1.0,
			"boundary %d and %d are distinct" % [index, index + 1]
		)

	# Approach start, corner entry, corner exit and finish map to the authored
	# world geometry through the committed adapter.
	c.vector_close(
		path.samples[0].position_m, Vector2(240.0, -60.0),
		POLYLINE_TOLERANCE_M, "approach start maps bay origin"
	)
	c.vector_close(
		path.samples[path.samples.size() - 1].position_m, Vector2(180.0, -60.0),
		POLYLINE_TOLERANCE_M, "exit finish maps authored endpoint"
	)
	c.measurements["first_position"] = str(path.samples[0].position_m)
	c.measurements["last_position"] = str(path.samples[path.samples.size() - 1].position_m)
	return c.result()


func _case_section_identity_and_boundaries() -> Dictionary:
	var c := Case.new()
	c.name = "section_identity_and_boundary_duplicates"

	var built := SourceScript.build()
	if not bool(built["ok"]):
		c.check(false, "live conversion failed: " + String(built["error"]))
		return c.result()
	var path: DriverScript.CalibrationPath = built["path"]
	var summary: Dictionary = built["summary"]

	# Section records preserve ordered station and surface identity.
	var sections: Array = summary["sections"]
	c.equal(sections.size(), 3, "three section records")
	var wanted_ids: Array = SourceScript.EXPECTED_SECTION_IDS
	var wanted_types: Array = ["straight", "arc", "straight"]
	for index in range(3):
		var rec: Dictionary = sections[index]
		c.equal(String(rec["section_id"]), String(wanted_ids[index]), "section %d id" % index)
		c.equal(String(rec["type"]), String(wanted_types[index]), "section %d type" % index)
		c.equal(String(rec["surface_id"]), SourceScript.EXPECTED_SURFACE_ID, "section %d surface" % index)
		c.close(
			float(rec["start_s_m"]),
			float(SourceScript.EXPECTED_BOUNDARY_STATIONS_M[index]),
			STATION_TOLERANCE,
			"section %d start station" % index
		)
		c.close(
			float(rec["end_s_m"]),
			float(SourceScript.EXPECTED_BOUNDARY_STATIONS_M[index + 1]),
			STATION_TOLERANCE,
			"section %d end station" % index
		)

	# Per-sample identity arrays stay aligned with the path and preserve the
	# builder's section/surface tags in ordered-station order.
	var sample_sections: Array = summary["sample_section_ids"]
	var sample_surfaces: Array = summary["sample_surface_ids"]
	c.equal(sample_sections.size(), path.samples.size(), "per-sample section identity count")
	c.equal(sample_surfaces.size(), path.samples.size(), "per-sample surface identity count")
	var counts: Dictionary = summary["section_sample_counts"]
	c.equal(int(counts["hairpin.approach"]), 31, "approach retains 31 unique samples")
	c.equal(int(counts["hairpin.arc"]), 95, "arc retains 95 unique samples")
	c.equal(int(counts["hairpin.exit"]), 30, "exit retains 30 unique samples")

	var expected_sequence := []
	for index in range(31):
		expected_sequence.append("hairpin.approach")
	for index in range(95):
		expected_sequence.append("hairpin.arc")
	for index in range(30):
		expected_sequence.append("hairpin.exit")
	c.equal(sample_sections, expected_sequence, "ordered per-sample section sequence")
	for surface_id in sample_surfaces:
		c.equal(String(surface_id), "asphalt", "every sample keeps the asphalt surface tag")

	# Exact boundary duplicate semantics: the raw stream repeats each internal
	# boundary cross-section once. The surviving sample is the preceding
	# section's copy; the dropped duplicate carries the following section tag.
	var raw := _live_raw_sample()
	c.check(not raw.is_empty(), "test can sample the live hairpin bay")
	if raw.is_empty():
		return c.result()
	var raw_samples: Array = raw["samples"]
	var raw_sections: Array = raw["sections"]
	c.equal(raw_samples.size(), 158, "builder raw sample count")

	var duplicate_indices: Array = []
	for index in range(1, raw_samples.size()):
		if float(raw_samples[index]["s"]) == float(raw_samples[index - 1]["s"]):
			duplicate_indices.append(index)
	c.equal(duplicate_indices, [31, 127], "exact duplicate indices are the two joins")

	for join_index in [31, 127]:
		var previous: Dictionary = raw_samples[join_index - 1]
		var duplicate: Dictionary = raw_samples[join_index]
		c.equal(float(duplicate["s"]), float(previous["s"]), "duplicate shares exact station")
		c.equal(duplicate["pos"], previous["pos"], "duplicate is the identical world position")
		c.check(bool(duplicate["joined_prev"]), "duplicate is marked joined_prev")
		c.check(not bool(duplicate["break_before"]), "duplicate is not a broken run")
		c.check(
			previous["section_id"] != duplicate["section_id"],
			"duplicate changes section identity at the join"
		)
	c.equal(
		String(raw_samples[31]["section_id"]), "hairpin.arc",
		"dropped arc-start duplicate carries the following section id"
	)
	c.equal(
		String(raw_samples[30]["section_id"]), "hairpin.approach",
		"surviving boundary sample carries the preceding section id"
	)
	c.equal(
		String(raw_samples[127]["section_id"]), "hairpin.exit",
		"dropped exit-start duplicate carries the following section id"
	)
	c.equal(
		String(raw_samples[126]["section_id"]), "hairpin.arc",
		"surviving arc-exit boundary carries the preceding section id"
	)

	# Adjacent section records share the exact join station recorded by samples.
	for index in range(2):
		c.close(
			float(raw_sections[index]["end_s_m"]),
			float(raw_sections[index + 1]["start_s_m"]),
			1e-4,
			"adjacent section records share join %d station" % index
		)
	c.equal(
		SourceScript._validate_samples(raw_samples, raw_sections),
		"",
		"unmodified raw builder samples pass conversion validation"
	)
	return c.result()


func _case_geometry_turn_and_heading_reversal() -> Dictionary:
	var c := Case.new()
	c.name = "geometry_turn_and_heading_reversal"

	var built := SourceScript.build()
	if not bool(built["ok"]):
		c.check(false, "live conversion failed: " + String(built["error"]))
		return c.result()
	var path: DriverScript.CalibrationPath = built["path"]
	var summary: Dictionary = built["summary"]

	var arc_start_s := SourceScript.EXPECTED_APPROACH_LENGTH_M
	var arc_end_s := arc_start_s + SourceScript.EXPECTED_ARC_LENGTH_M
	var center := Vector2(
		float(summary["expected_arc_center_road_m"][0]),
		float(summary["expected_arc_center_road_m"][1])
	)
	c.vector_close(center, Vector2(210.0, -30.0), VECTOR_TOLERANCE, "derived arc center")

	# Every sample on the arc, including both exact boundary points, lies on the
	# authored 30 m circle.
	var saw_arc := false
	for sample: DriverScript.PathSample in path.samples:
		if sample.s_m + STATION_TOLERANCE < arc_start_s:
			continue
		if sample.s_m - STATION_TOLERANCE > arc_end_s:
			continue
		saw_arc = true
		c.close(
			sample.position_m.distance_to(center),
			SourceScript.EXPECTED_ARC_RADIUS_M,
			ARC_RADIUS_TOLERANCE,
			"arc sample radius"
		)
	c.check(saw_arc, "arc station coverage present")

	# Approach runs along road +y; exit runs back along road -y.
	var first_dir := (path.samples[1].position_m - path.samples[0].position_m).normalized()
	var last_dir := (
		path.samples[path.samples.size() - 1].position_m
		- path.samples[path.samples.size() - 2].position_m
	).normalized()
	c.vector_close(first_dir, Vector2(0.0, 1.0), 1e-3, "approach travel direction")
	c.vector_close(last_dir, Vector2(0.0, -1.0), 1e-3, "exit travel direction")

	# Heading reversal: first and last travel directions are opposite.
	var reversal := acos(clampf(first_dir.dot(last_dir), -1.0, 1.0))
	c.close(reversal, PI, TURN_TOLERANCE_RAD, "heading reverses by 180 degrees")

	# Signed left turn along the whole polyline sums to +pi.
	var total_turn := 0.0
	var previous_dir := Vector2.ZERO
	for index in range(path.samples.size() - 1):
		var direction := (
			path.samples[index + 1].position_m - path.samples[index].position_m
		).normalized()
		if index > 0:
			total_turn += atan2(
				previous_dir.x * direction.y - previous_dir.y * direction.x,
				previous_dir.dot(direction)
			)
		previous_dir = direction
	c.close(total_turn, PI, TURN_TOLERANCE_RAD, "total signed geometric turn is +180 degrees")

	# Arc endpoints are diametrically opposite around the center and the arc
	# bulges toward road +y (left of the approach).
	# Unique index 30 is the surviving approach-end/arc-entry boundary; unique
	# index 125 is the surviving arc-end/exit-entry boundary (raw duplicates at
	# indices 31 and 127 are dropped from the path).
	var arc_entry_rel := path.samples[30].position_m - center
	var arc_exit_rel := path.samples[125].position_m - center
	c.close(arc_entry_rel.length(), 30.0, POLYLINE_TOLERANCE_M, "arc entry radius vector")
	c.close(arc_exit_rel.length(), 30.0, POLYLINE_TOLERANCE_M, "arc exit radius vector")
	c.close(
		absf(arc_entry_rel.angle_to(arc_exit_rel)), PI, TURN_TOLERANCE_RAD,
		"arc sweeps a half-circle about its center"
	)
	var arc_mid := _sample_at_station(path, arc_start_s + SourceScript.EXPECTED_ARC_LENGTH_M * 0.5)
	c.check(arc_mid.position_m.y > center.y, "left arc bulges toward road +y")

	# The two legs are parallel and separated by exactly one diameter, which is
	# why nearest-point route progress would be ambiguous.
	c.close(
		absf(path.samples[0].position_m.x - path.samples[path.samples.size() - 1].position_m.x),
		2.0 * SourceScript.EXPECTED_ARC_RADIUS_M,
		POLYLINE_TOLERANCE_M,
		"approach and exit legs are one diameter apart"
	)

	# Nearest-point route lookup is deliberately unavailable.
	var nearest := SourceScript.resolve_progress_by_nearest_point(Vector2(210.0, -45.0))
	c.check(not bool(nearest["ok"]), "nearest-point progress lookup is refused")
	c.check(
		not String(nearest["error"]).is_empty(),
		"nearest-point refusal carries a diagnostic"
	)
	c.equal(
		SourceScript.progress_policy(),
		"ordered_station_from_caller_only_nearest_point_route_lookup_prohibited",
		"progress policy is explicit"
	)
	return c.result()


func _case_world_to_road_mapping() -> Dictionary:
	var c := Case.new()
	c.name = "world_to_road_mapping"

	var built := SourceScript.build()
	if not bool(built["ok"]):
		c.check(false, "live conversion failed: " + String(built["error"]))
		return c.result()
	var path: DriverScript.CalibrationPath = built["path"]
	var summary: Dictionary = built["summary"]

	c.vector_close(
		path.samples[0].position_m,
		AdapterScript.world_vector_to_road(SourceScript.EXPECTED_ORIGIN),
		VECTOR_TOLERANCE,
		"start maps through the committed adapter"
	)
	c.vector_close(
		AdapterScript.world_vector_to_road(SourceScript.EXPECTED_ORIGIN),
		Vector2(240.0, -60.0),
		VECTOR_TOLERANCE,
		"bay origin road coordinates"
	)
	c.vector_close(
		AdapterScript.world_vector_to_road(Vector3(1.5, 2.5, -3.5)),
		Vector2(1.5, 3.5),
		VECTOR_TOLERANCE,
		"adapter mapping formula is Vector2(world.x, -world.z)"
	)

	# Cross-check every produced sample against an independent application of
	# the builder world sample and the committed adapter.
	var raw := _live_raw_sample()
	if raw.is_empty():
		c.check(false, "test can sample the live hairpin bay")
		return c.result()
	var filtered := SourceScript._filter_join_duplicates(raw["samples"], raw["sections"])
	c.check(bool(filtered["ok"]), "raw filtering succeeds for mapping cross-check")
	if not bool(filtered["ok"]):
		return c.result()
	var unique: Array = filtered["samples"]
	c.equal(unique.size(), path.samples.size(), "cross-check alignment count")
	var all_mapped := true
	for index in range(mini(unique.size(), path.samples.size())):
		var smp: Dictionary = unique[index]
		var world: Vector3 = smp["pos"] + (smp["right"] as Vector3) * float(smp["lateral_offset"])
		var road: Vector2 = AdapterScript.world_vector_to_road(world)
		if road.distance_to((path.samples[index] as DriverScript.PathSample).position_m) > VECTOR_TOLERANCE:
			all_mapped = false
	c.check(all_mapped, "every sample equals the adapter image of its builder world position")

	c.equal(
		summary["coordinate_mapping"]["authority"],
		"MotorBodyAdapter.world_vector_to_road",
		"mapping authority recorded"
	)
	c.equal(
		summary["coordinate_mapping"]["car_state_axes"],
		"+x right, +y forward",
		"CarState axis convention recorded"
	)
	return c.result()


func _case_repeatability_and_interpolation() -> Dictionary:
	var c := Case.new()
	c.name = "repeatability_and_interpolation"

	var first := SourceScript.build()
	var second := SourceScript.build()
	c.check(bool(first["ok"]) and bool(second["ok"]), "repeated builds succeed")
	if not bool(first["ok"]) or not bool(second["ok"]):
		return c.result()

	var path_a: DriverScript.CalibrationPath = first["path"]
	var path_b: DriverScript.CalibrationPath = second["path"]
	c.equal(path_a.samples.size(), path_b.samples.size(), "repeat sample count identical")

	var identical := true
	for index in range(path_a.samples.size()):
		var a: DriverScript.PathSample = path_a.samples[index]
		var b: DriverScript.PathSample = path_b.samples[index]
		if a.s_m != b.s_m:
			identical = false
		if a.position_m != b.position_m:
			identical = false
		if a.target_speed_m_s != b.target_speed_m_s:
			identical = false
	c.check(identical, "repeat samples are bit-identical")
	c.equal(
		JSON.stringify(first["summary"]),
		JSON.stringify(second["summary"]),
		"repeat summaries are identical JSON"
	)

	# Interpolation contract: mid-approach, exact end clamp and out-of-range
	# clamping stay finite and inside the declared profile.
	var mid := path_a.interpolate_at(15.0)
	c.close(mid.position_m.x, 240.0, VECTOR_TOLERANCE, "mid-approach interpolation x")
	c.close(mid.position_m.y, -45.0, VECTOR_TOLERANCE, "mid-approach interpolation y")
	c.close(mid.target_speed_m_s, SourceScript.PROVISIONAL_TARGET_SPEED_M_S, 0.0, "interpolated speed")
	var clamped_high := path_a.interpolate_at(1.0e6)
	c.close(clamped_high.s_m, path_a.last_s_m(), VECTOR_TOLERANCE, "high progress clamps to last station")
	var clamped_low := path_a.interpolate_at(-5.0)
	c.close(clamped_low.s_m, path_a.first_s_m(), VECTOR_TOLERANCE, "low progress clamps to first station")
	return c.result()


func _case_changed_or_missing_source_refusal() -> Dictionary:
	var c := Case.new()
	c.name = "changed_or_missing_source_refusal"

	# Sanity: the unmodified live sources still succeed.
	var baseline := SourceScript.build()
	c.check(bool(baseline["ok"]), "baseline succeeds before negative controls")
	if not bool(baseline["ok"]):
		return c.result()

	# Missing bay.
	var missing_bay := SourceScript.build({}, {}, true, false)
	c.check(not bool(missing_bay["ok"]), "missing authored bay is refused")
	c.check(not String(missing_bay["error"]).is_empty(), "missing bay refusal carries a diagnostic")
	c.check(missing_bay["path"] == null, "missing bay returns no path")

	# Missing fixture.
	var missing_fixture := SourceScript.build({}, {}, false, true)
	c.check(not bool(missing_fixture["ok"]), "missing fixture is refused")
	c.check(not String(missing_fixture["error"]).is_empty(), "missing fixture refusal carries a diagnostic")

	# Changed bay geometry: a different arc radius must not fall back.
	var changed_bay := _live_bay_copy()
	c.check(not changed_bay.is_empty(), "test can read a live bay copy")
	if not changed_bay.is_empty():
		var segments: Array = changed_bay["segments"]
		segments[1]["radius_m"] = 90.0
		var refused := SourceScript.build(changed_bay, {})
		c.check(not bool(refused["ok"]), "changed arc radius is refused")
		c.check(refused["path"] == null, "changed bay returns no path")

	# Changed bay direction.
	var turned_bay := _live_bay_copy()
	if not turned_bay.is_empty():
		var segments: Array = turned_bay["segments"]
		segments[1]["direction"] = "right"
		var refused := SourceScript.build(turned_bay, {})
		c.check(not bool(refused["ok"]), "changed arc direction is refused")

	# Changed fixture geometry: a different radius must not fall back even
	# when the bay table is untouched.
	var changed_fixture := _fixture_copy()
	c.check(not changed_fixture.is_empty(), "test can read a live fixture copy")
	if not changed_fixture.is_empty():
		var geometry: Dictionary = changed_fixture["geometry"]
		var fsegments: Array = geometry["segments"]
		fsegments[1]["radius_m"] = 90.0
		var refused := SourceScript.build({}, changed_fixture)
		c.check(not bool(refused["ok"]), "changed fixture arc radius is refused")

	# Corrupted fixture entry speed and timing gate.
	var speed_fixture := _fixture_copy()
	if not speed_fixture.is_empty():
		var runs: Array = speed_fixture["runs"]
		runs[0]["initial_state"]["velocity_m_s"] = 25.0
		c.check(not bool(SourceScript.build({}, speed_fixture)["ok"]), "changed fixture entry speed is refused")
	var gate_fixture := _fixture_copy()
	if not gate_fixture.is_empty():
		var gates: Array = gate_fixture["timing_gates"]
		for gate in gates:
			if String(gate.get("gate_id", "")) == "corner_exit":
				gate["arc_length_m"] = 10.0
		c.check(not bool(SourceScript.build({}, gate_fixture)["ok"]), "corrupted corner-exit gate is refused")
	var frame_fixture := _fixture_copy()
	if not frame_fixture.is_empty():
		frame_fixture["coordinate_frame"]["forward"] = "+Z"
		c.check(not bool(SourceScript.build({}, frame_fixture)["ok"]), "corrupted coordinate frame is refused")

	# Malformed fixture document.
	var malformed := SourceScript.build({}, {"fixture_id": "fixture.handling.other"})
	c.check(not bool(malformed["ok"]), "malformed fixture identity is refused")

	# Impossible join and raw-stream corruption controls.
	var raw := _live_raw_sample()
	if raw.is_empty():
		c.check(false, "test can sample the live hairpin bay")
		return c.result()
	var raw_samples: Array = raw["samples"]
	var raw_sections: Array = raw["sections"]

	var discontinuous: Array = []
	for smp in raw_samples:
		discontinuous.append(smp.duplicate(true))
	discontinuous[31]["pos"] = (discontinuous[31]["pos"] as Vector3) + Vector3(0.001, 0.0, 0.0)
	var discontinuity_error := SourceScript._validate_samples(discontinuous, raw_sections)
	c.check(not discontinuity_error.is_empty(), "discontinuous join duplicate is refused")
	c.check(discontinuity_error.contains("discontinuous"), "discontinuity refusal names the mismatch")

	var broken: Array = []
	for smp in raw_samples:
		broken.append(smp.duplicate(true))
	broken[31]["break_before"] = true
	var broken_error := SourceScript._validate_samples(broken, raw_sections)
	c.check(not broken_error.is_empty(), "broken-run duplicate is refused")
	c.check(broken_error.contains("broken run"), "broken-run refusal explains the rejection")

	var unmarked: Array = []
	for smp in raw_samples:
		unmarked.append(smp.duplicate(true))
	unmarked[31]["joined_prev"] = false
	var unmarked_error := SourceScript._validate_samples(unmarked, raw_sections)
	c.check(not unmarked_error.is_empty(), "unmarked repeated station is refused")
	c.check(
		unmarked_error.contains("not marked as an ordinary section join"),
		"unmarked-repeat refusal explains the rejection"
	)

	# Repeated station away from a genuine section join is not dropped.
	var repeated_interior: Array = []
	for smp in raw_samples:
		repeated_interior.append(smp.duplicate(true))
	repeated_interior[10]["s"] = float(repeated_interior[9]["s"])
	var repeat_error := SourceScript._validate_samples(repeated_interior, raw_sections)
	c.check(not repeat_error.is_empty(), "non-join repeated station is refused")

	# Swapping adjacent interior samples reorders stations and must refuse.
	var reordered: Array = []
	for smp in raw_samples:
		reordered.append(smp.duplicate(true))
	var held: Dictionary = reordered[10]
	reordered[10] = reordered[11]
	reordered[11] = held
	var reorder_error := SourceScript._validate_samples(reordered, raw_sections)
	c.check(not reorder_error.is_empty(), "reordered samples are refused")
	c.check(reorder_error.contains("non-monotonic or reordered"), "reordered refusal names station ordering")

	# Tampered section identity is refused by the section record guard. A
	# repeated boundary sample whose following-section tag no longer pairs
	# with the preceding tag under unchanged records is refused separately.
	var mislabeled_sections: Array = []
	for rec in raw_sections:
		mislabeled_sections.append(rec.duplicate(true))
	mislabeled_sections[0]["section_id"] = "hairpin.arc"
	var section_identity_error := SourceScript._validate_samples(
		raw_samples, mislabeled_sections
	)
	c.check(not section_identity_error.is_empty(), "mislabeled section record is refused")
	c.check(
		section_identity_error.contains("section 0 section_id changed"),
		"section-identity refusal names the tampered record"
	)

	var mispaired_tags: Array = []
	for smp in raw_samples:
		mispaired_tags.append(smp.duplicate(true))
	mispaired_tags[31]["section_id"] = "hairpin.approach"
	var pairing_error := SourceScript._validate_samples(mispaired_tags, raw_sections)
	c.check(not pairing_error.is_empty(), "mispaired join tags are refused")
	c.check(
		pairing_error.contains("does not join adjacent recorded sections"),
		"impossible join refusal names the pairing failure"
	)

	# Missing section record.
	var short_sections: Array = [raw_sections[0].duplicate(true), raw_sections[1].duplicate(true)]
	var short_error := SourceScript._validate_samples(raw_samples, short_sections)
	c.check(not short_error.is_empty(), "missing section record is refused")

	# Corrupted produced path is caught by the driver's own validation.
	var corrupted := DriverScript.CalibrationPath.from_arrays(
		[0.0, 1.0], [Vector2.ZERO, Vector2.RIGHT], [-1.0, 5.0]
	)
	c.check(not corrupted.is_valid(), "negative target speed fails path validation")
	c.check(
		not corrupted.validation_error().is_empty(),
		"path validation emits a specific error"
	)
	return c.result()


func _case_provisional_labels_and_progress_policy() -> Dictionary:
	var c := Case.new()
	c.name = "provisional_labels_and_progress_policy"

	var built := SourceScript.build()
	if not bool(built["ok"]):
		c.check(false, "live conversion failed: " + String(built["error"]))
		return c.result()
	var summary: Dictionary = built["summary"]
	var path: DriverScript.CalibrationPath = built["path"]

	c.check(
		String(summary["path_version"]).contains("provisional"),
		"path version marks itself provisional"
	)
	c.equal(
		summary["target_speed_provenance"],
		SourceScript.TARGET_SPEED_PROVENANCE,
		"target speed provenance recorded"
	)
	c.check(
		String(summary["target_speed_provenance"]).contains("not_measured_or_tuned"),
		"target speed is explicitly not measured or tuned"
	)
	c.check(
		String(summary["sampling_seam"]).contains("provisional"),
		"private sampling seam is labelled provisional"
	)
	c.check(
		String(summary["sampling_seam"]).contains("_sample_bay"),
		"private sampling seam names the called function"
	)
	c.equal(
		summary["progress_policy"],
		"ordered_station_from_caller_only_nearest_point_route_lookup_prohibited",
		"progress policy recorded"
	)
	var all_constant := true
	for sample: DriverScript.PathSample in path.samples:
		if absf(sample.target_speed_m_s - SourceScript.PROVISIONAL_TARGET_SPEED_M_S) > 0.0:
			all_constant = false
	c.check(all_constant, "target speed is the single provisional lab value")
	c.equal(
		SourceScript.PROVISIONAL_TARGET_SPEED_M_S,
		18.0,
		"provisional target speed is the authored benchmark entry value"
	)
	c.equal(
		float(summary["expected_entry_speed_m_s"]),
		18.0,
		"summary ties the provisional profile to the fixture entry speed"
	)
	return c.result()


func _case_fail_closed_scalar_guards() -> Dictionary:
	var c := Case.new()
	c.name = "fail_closed_scalar_guards"

	# Authored bay scalars: missing, wrong-type, NaN and infinity must all
	# refuse before any float conversion or tolerance comparison.
	for kind in [
		"missing_yaw_deg", "nan_yaw_deg", "inf_yaw_deg", "string_yaw_deg",
		"missing_origin", "wrong_type_origin", "nonfinite_origin",
		"missing_segments", "wrong_type_segments",
		"missing_width_m", "nan_width_m", "inf_width_m", "string_width_m",
		"missing_lateral_offset_m", "missing_grade_start_percent",
		"missing_bank_end_deg", "missing_length_m", "missing_radius_m",
		"missing_angle_deg",
	]:
		var mutated := _mutated_bay(kind)
		var refused := SourceScript.build(mutated, {})
		c.check(
			not bool(refused["ok"]),
			"bay %s is refused (error: %s)" % [kind, String(refused["error"])]
		)
		c.check(
			not String(refused["error"]).is_empty(),
			"bay %s refusal carries a diagnostic" % kind
		)

	var missing_yaw := SourceScript.build(_mutated_bay("missing_yaw_deg"), {})
	c.check(
		String(missing_yaw["error"]).contains("yaw_deg is missing"),
		"missing bay yaw names the missing key"
	)
	var nan_width := SourceScript.build(_mutated_bay("nan_width_m"), {})
	c.check(
		String(nan_width["error"]).contains("width_m is not finite"),
		"NaN bay width names the nonfinite value"
	)

	# Fixture scalars, including all four timing gates and both initial states.
	for kind in [
		"missing_coordinate_frame", "wrong_type_geometry",
		"missing_geometry_segments", "missing_fixture_width_m",
		"nan_fixture_width_m", "missing_fixture_length_m",
		"missing_fixture_radius_m", "missing_fixture_angle_deg",
		"missing_timing_gates",
		"missing_gate_arc_start", "missing_gate_arc_entry",
		"missing_gate_arc_exit", "missing_gate_arc_finish",
		"missing_all_gate_arc_lengths", "nan_gate_arc_exit",
		"missing_gate_segment_index", "nan_gate_segment_index",
		"missing_primary_velocity", "nan_primary_velocity",
		"inf_primary_velocity", "string_primary_heading",
		"missing_grip_velocity", "grip_speed_40", "nan_grip_velocity",
		"missing_grip_run", "missing_grip_initial_state",
	]:
		var mutated := _mutated_fixture(kind)
		var refused := SourceScript.build({}, mutated)
		c.check(
			not bool(refused["ok"]),
			"fixture %s is refused (error: %s)" % [kind, String(refused["error"])]
		)
		c.check(
			not String(refused["error"]).is_empty(),
			"fixture %s refusal carries a diagnostic" % kind
		)

	var all_missing := SourceScript.build(
		{}, _mutated_fixture("missing_all_gate_arc_lengths")
	)
	c.check(
		String(all_missing["error"]).contains("arc_length_m"),
		"all-missing gate arc lengths name arc_length_m"
	)
	var grip_speed := SourceScript.build({}, _mutated_fixture("grip_speed_40"))
	c.check(
		String(grip_speed["error"]).contains("grip_entry entry speed changed"),
		"grip_entry speed 40 refusal names the grip run"
	)

	# Builder section records and raw samples.
	for kind in [
		"missing_section_start", "missing_section_end", "missing_section_length",
		"nan_section_start", "string_section_end", "nan_section_width",
		"missing_section_surface", "missing_sample_s", "nan_sample_s",
		"wrong_type_sample_pos",
	]:
		var mutated := _mutated_samples(kind)
		var error := SourceScript._validate_samples(
			mutated["samples"], mutated["sections"]
		)
		c.check(not error.is_empty(), "section/sample %s is refused" % kind)

	var missing_start := SourceScript._validate_samples(
		_mutated_samples("missing_section_start")["samples"],
		_mutated_samples("missing_section_start")["sections"]
	)
	c.check(
		missing_start.contains("start_s_m is missing"),
		"missing section start names start_s_m"
	)
	var missing_length := SourceScript._validate_samples(
		_mutated_samples("missing_section_length")["samples"],
		_mutated_samples("missing_section_length")["sections"]
	)
	c.check(
		missing_length.contains("length_m is missing"),
		"missing section length names length_m"
	)
	return c.result()


func _case_tag_ownership_refusal() -> Dictionary:
	var c := Case.new()
	c.name = "tag_ownership_refusal"

	var raw := _live_raw_sample()
	if raw.is_empty():
		c.check(false, "test can sample the live hairpin bay")
		return c.result()
	var raw_samples: Array = raw["samples"]
	var raw_sections: Array = raw["sections"]

	# The unmodified raw stream passes, including the two legitimate side
	# copies at each join (approach copy at index 30, arc copy at index 31).
	c.equal(
		SourceScript._validate_samples(raw_samples, raw_sections), "",
		"unmodified raw stream passes"
	)
	c.equal(
		String(raw_samples[30]["section_id"]), "hairpin.approach",
		"join keeps the preceding approach copy"
	)
	c.equal(
		String(raw_samples[31]["section_id"]), "hairpin.arc",
		"join keeps the following arc copy"
	)

	var starts: Array = []
	var ends: Array = []
	for rec: Dictionary in raw_sections:
		starts.append(float(rec["start_s_m"]))
		ends.append(float(rec["end_s_m"]))
	c.equal(
		SourceScript._samples_ownership_error(raw_samples, raw_sections, starts, ends),
		"",
		"both legitimate join side copies satisfy ownership"
	)

	# An interior sample relabelled with another section tag must refuse.
	var relabelled_section := _mutated_samples("relabel_interior_section")
	var section_error := SourceScript._validate_samples(
		relabelled_section["samples"], relabelled_section["sections"]
	)
	c.check(not section_error.is_empty(), "interior sample with exit tag is refused")
	c.check(
		section_error.contains("does not own that station"),
		"section-tag refusal names ownership"
	)

	# An interior sample relabelled with another surface must refuse.
	var relabelled_surface := _mutated_samples("relabel_interior_surface")
	var surface_error := SourceScript._validate_samples(
		relabelled_surface["samples"], relabelled_surface["sections"]
	)
	c.check(
		not surface_error.is_empty(),
		"interior sample with gravel surface is refused"
	)
	c.check(
		surface_error.contains("surface"),
		"surface-tag refusal names the mismatch"
	)

	# Both tags changed together must refuse.
	var relabelled_both := _mutated_samples("relabel_interior_both")
	var both_error := SourceScript._validate_samples(
		relabelled_both["samples"], relabelled_both["sections"]
	)
	c.check(
		not both_error.is_empty(),
		"interior sample with exit/gravel tags is refused"
	)

	# A mid-arc sample relabelled with the approach tag must refuse.
	var relabelled_arc := _mutated_samples("relabel_arc_interior")
	var arc_error := SourceScript._validate_samples(
		relabelled_arc["samples"], relabelled_arc["sections"]
	)
	c.check(not arc_error.is_empty(), "mid-arc sample with approach tag is refused")
	return c.result()


# --- Helpers --------------------------------------------------------------


# --- Negative-control mutation helpers ------------------------------------


static func _run_by_id(fixture: Dictionary, run_id: String) -> Dictionary:
	var runs: Array = fixture.get("runs", [])
	for run: Dictionary in runs:
		if String(run.get("run_id", "")) == run_id:
			return run
	return {}


static func _gate_by_id(fixture: Dictionary, gate_id: String) -> Dictionary:
	var gates: Array = fixture.get("timing_gates", [])
	for gate: Dictionary in gates:
		if String(gate.get("gate_id", "")) == gate_id:
			return gate
	return {}


static func _mutated_bay(kind: String) -> Dictionary:
	var bay := _live_bay_copy()
	match kind:
		"missing_yaw_deg":
			bay.erase("yaw_deg")
		"nan_yaw_deg":
			bay["yaw_deg"] = NAN
		"inf_yaw_deg":
			bay["yaw_deg"] = INF
		"string_yaw_deg":
			bay["yaw_deg"] = "0"
		"missing_origin":
			bay.erase("origin")
		"wrong_type_origin":
			bay["origin"] = "240,0,60"
		"nonfinite_origin":
			bay["origin"] = Vector3(240.0, INF, 60.0)
		"missing_segments":
			bay.erase("segments")
		"wrong_type_segments":
			bay["segments"] = "segments"
		"missing_width_m":
			(bay["segments"][0] as Dictionary).erase("width_m")
		"nan_width_m":
			bay["segments"][0]["width_m"] = NAN
		"inf_width_m":
			bay["segments"][0]["width_m"] = INF
		"string_width_m":
			bay["segments"][0]["width_m"] = "12"
		"missing_lateral_offset_m":
			(bay["segments"][0] as Dictionary).erase("lateral_offset_m")
		"missing_grade_start_percent":
			(bay["segments"][0] as Dictionary).erase("grade_start_percent")
		"missing_bank_end_deg":
			(bay["segments"][2] as Dictionary).erase("bank_end_deg")
		"missing_length_m":
			(bay["segments"][0] as Dictionary).erase("length_m")
		"missing_radius_m":
			(bay["segments"][1] as Dictionary).erase("radius_m")
		"missing_angle_deg":
			(bay["segments"][1] as Dictionary).erase("angle_deg")
	return bay


static func _mutated_fixture(kind: String) -> Dictionary:
	var fixture := _fixture_copy()
	match kind:
		"missing_coordinate_frame":
			fixture.erase("coordinate_frame")
		"wrong_type_geometry":
			fixture["geometry"] = "geometry"
		"missing_geometry_segments":
			(fixture["geometry"] as Dictionary).erase("segments")
		"missing_fixture_width_m":
			((fixture["geometry"]["segments"] as Array)[0] as Dictionary).erase(
				"width_m"
			)
		"nan_fixture_width_m":
			(fixture["geometry"]["segments"][0] as Dictionary)["width_m"] = NAN
		"missing_fixture_length_m":
			((fixture["geometry"]["segments"] as Array)[0] as Dictionary).erase(
				"length_m"
			)
		"missing_fixture_radius_m":
			((fixture["geometry"]["segments"] as Array)[1] as Dictionary).erase(
				"radius_m"
			)
		"missing_fixture_angle_deg":
			((fixture["geometry"]["segments"] as Array)[1] as Dictionary).erase(
				"angle_deg"
			)
		"missing_timing_gates":
			fixture.erase("timing_gates")
		"missing_gate_arc_start":
			(_gate_by_id(fixture, "start") as Dictionary).erase("arc_length_m")
		"missing_gate_arc_entry":
			(_gate_by_id(fixture, "corner_entry") as Dictionary).erase("arc_length_m")
		"missing_gate_arc_exit":
			(_gate_by_id(fixture, "corner_exit") as Dictionary).erase("arc_length_m")
		"missing_gate_arc_finish":
			(_gate_by_id(fixture, "finish") as Dictionary).erase("arc_length_m")
		"missing_all_gate_arc_lengths":
			for gate: Dictionary in fixture["timing_gates"]:
				gate.erase("arc_length_m")
		"nan_gate_arc_exit":
			_gate_by_id(fixture, "corner_exit")["arc_length_m"] = NAN
		"missing_gate_segment_index":
			(_gate_by_id(fixture, "finish") as Dictionary).erase("segment_index")
		"nan_gate_segment_index":
			_gate_by_id(fixture, "start")["segment_index"] = NAN
		"missing_primary_velocity":
			(_run_by_id(fixture, "drift_entry")["initial_state"] as Dictionary).erase(
				"velocity_m_s"
			)
		"nan_primary_velocity":
			_run_by_id(fixture, "drift_entry")["initial_state"]["velocity_m_s"] = NAN
		"inf_primary_velocity":
			_run_by_id(fixture, "drift_entry")["initial_state"]["velocity_m_s"] = INF
		"string_primary_heading":
			_run_by_id(fixture, "drift_entry")["initial_state"]["heading_deg"] = "0"
		"missing_grip_velocity":
			(_run_by_id(fixture, "grip_entry")["initial_state"] as Dictionary).erase(
				"velocity_m_s"
			)
		"grip_speed_40":
			_run_by_id(fixture, "grip_entry")["initial_state"]["velocity_m_s"] = 40.0
		"nan_grip_velocity":
			_run_by_id(fixture, "grip_entry")["initial_state"]["velocity_m_s"] = NAN
		"missing_grip_initial_state":
			(_run_by_id(fixture, "grip_entry") as Dictionary).erase("initial_state")
		"missing_grip_run":
			var kept: Array = []
			for run: Dictionary in fixture["runs"]:
				if String(run.get("run_id", "")) != "grip_entry":
					kept.append(run)
			fixture["runs"] = kept
	return fixture


static func _mutated_samples(kind: String) -> Dictionary:
	var raw := _live_raw_sample()
	var samples: Array = raw["samples"]
	var sections: Array = raw["sections"]
	match kind:
		"missing_section_start":
			for rec: Dictionary in sections:
				rec.erase("start_s_m")
		"missing_section_end":
			for rec: Dictionary in sections:
				rec.erase("end_s_m")
		"missing_section_length":
			for rec: Dictionary in sections:
				rec.erase("length_m")
		"nan_section_start":
			sections[0]["start_s_m"] = NAN
		"string_section_end":
			sections[1]["end_s_m"] = "124.2478"
		"nan_section_width":
			sections[2]["width_m"] = NAN
		"missing_section_surface":
			(sections[0] as Dictionary).erase("surface_id")
		"missing_sample_s":
			(samples[1] as Dictionary).erase("s")
		"nan_sample_s":
			samples[1]["s"] = NAN
		"wrong_type_sample_pos":
			samples[1]["pos"] = "pos"
		"relabel_interior_section":
			samples[1]["section_id"] = "hairpin.exit"
		"relabel_interior_surface":
			samples[1]["surface_id"] = "gravel"
		"relabel_interior_both":
			samples[1]["section_id"] = "hairpin.exit"
			samples[1]["surface_id"] = "gravel"
		"relabel_arc_interior":
			samples[50]["section_id"] = "hairpin.approach"
	return {"samples": samples, "sections": sections}


static func _sample_at_station(
	path: DriverScript.CalibrationPath, station_m: float
) -> DriverScript.PathSample:
	var best: DriverScript.PathSample = path.samples[0]
	var best_error := INF
	for sample: DriverScript.PathSample in path.samples:
		var error := absf(sample.s_m - station_m)
		if error < best_error:
			best_error = error
			best = sample
	return best
