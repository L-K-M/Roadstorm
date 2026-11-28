class_name CalibrationPathLabChecks
extends RefCounted
## Discriminatory checks for the HandlingLab sweeper -> CalibrationPath
## conversion. These checks read the live authored laboratory data; they do not
## run physics, drive a car or produce a lap record. Negative controls mutate
## copies of the authored inputs and require the source to refuse them.

const SourceScript = preload("res://tools/calibration_path_lab/calibration_path_source.gd")
const DriverScript = preload("res://src/calibration/calibration_driver.gd")
const AdapterScript = preload("res://src/simulation/motor_body_adapter.gd")

const VECTOR_TOLERANCE := 1e-7
const STATION_TOLERANCE := 1e-4
const ARC_RADIUS_TOLERANCE := 0.01
## The builder integrates the arc as a 1 m sampled polyline. Its endpoint is
## within about 0.00035 m of the ideal circle, so a millimetre is a tight but
## stable tolerance for boundary positions while exact station/order checks
## remain much stricter.
const ARC_POLYLINE_TOLERANCE_M := 1e-3


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
				"%s (got %.9f expected %.9f tol %.3g)"
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
		Callable(self, "_case_station_range_and_mapping"),
		Callable(self, "_case_arc_geometry_and_direction"),
		Callable(self, "_case_repeat_identity_and_path_contract"),
		Callable(self, "_case_changed_or_missing_source_refusal"),
		Callable(self, "_case_provisional_labels"),
	]:
		var result: Dictionary = call.call()
		case_results.append(result)
		cases_run += 1
		total_checks += int(result["checks"])
		total_failures += int(result["checks_failed"])
		print(
			"CALIBRATION_PATH_LAB_CASE ",
			JSON.stringify({
				"case": result["case"],
				"checks": result["checks"],
				"checks_failed": result["checks_failed"],
				"pass": result["pass"],
			})
		)
	return {
		"schema": "roadstorm.calibration_path_lab.summary.v1",
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
		if String(bay["bay_id"]) == SourceScript.SWEEPER_BAY_ID:
			return bay.duplicate(true)
	return {}


static func _fixture_copy() -> Dictionary:
	var doc := SourceScript._load_fixture_document()
	if doc.is_empty():
		return {}
	return doc.duplicate(true)


# --- Cases ----------------------------------------------------------------


func _case_authority_and_shape() -> Dictionary:
	var c := Case.new()
	c.name = "authority_and_sweep_shape"

	var built := SourceScript.build()
	c.check(bool(built["ok"]), "live authored conversion must succeed")
	if not bool(built["ok"]):
		return c.result()
	c.equal(String(built["error"]), "", "successful build reports no error")

	var path: DriverScript.CalibrationPath = built["path"]
	c.check(path is DriverScript.CalibrationPath, "result is a CalibrationPath")
	c.check(path.is_valid(), "path validates: " + path.validation_error())
	c.equal(path.version, SourceScript.PATH_VERSION, "path version is pinned")
	c.equal(path.samples.size(), 290, "unique sample count follows builder sampling")

	var summary: Dictionary = built["summary"]
	c.equal(int(summary["sample_count"]), 290, "summary sample count matches path")
	c.equal(int(summary["builder_sample_count"]), 292, "builder emits 292 raw section samples")
	c.equal(int(summary["join_duplicates_skipped"]), 2, "exactly two genuine join duplicates are skipped")
	c.close(
		float(summary["length_m"]),
		SourceScript.EXPECTED_TOTAL_LENGTH_M,
		STATION_TOLERANCE,
		"summary length matches authored section lengths"
	)
	c.equal(
		String(summary["status"]), "provisional_not_production", "summary status provisional"
	)

	# Approach straight: first 50 m runs along road +y from the mapped origin.
	var approach_end := -1
	for index in range(path.samples.size()):
		var sample: DriverScript.PathSample = path.samples[index]
		if sample.s_m <= SourceScript.EXPECTED_APPROACH_LENGTH_M + STATION_TOLERANCE:
			approach_end = index
			c.close(sample.position_m.x, 0.0, VECTOR_TOLERANCE, "approach stays on centerline")
			c.close(
				sample.position_m.y,
				-60.0 + sample.s_m,
				VECTOR_TOLERANCE,
				"approach advances along +y"
			)
	c.check(approach_end >= 50, "approach station coverage reaches 50 m")

	# Exit straight: last 50 m runs along road -x at about y = 110.
	var exit_start_s := (
		SourceScript.EXPECTED_APPROACH_LENGTH_M + SourceScript.EXPECTED_ARC_LENGTH_M
	)
	var saw_exit := false
	for sample: DriverScript.PathSample in path.samples:
		if sample.s_m + STATION_TOLERANCE < exit_start_s:
			continue
		saw_exit = true
		c.close(
			sample.position_m.y,
			110.0,
			ARC_POLYLINE_TOLERANCE_M,
			"exit holds y = 110 after the left quarter-circle"
		)
		c.close(
			sample.position_m.x,
			-120.0 - (sample.s_m - exit_start_s),
			ARC_POLYLINE_TOLERANCE_M,
			"exit advances along -x"
		)
	c.check(saw_exit, "exit station coverage present")
	c.vector_close(
		path.samples[path.samples.size() - 1].position_m,
		Vector2(-170.0, 110.0),
		ARC_POLYLINE_TOLERANCE_M,
		"finish point"
	)
	c.measurements["first_position"] = str(path.samples[0].position_m)
	c.measurements["last_position"] = str(path.samples[path.samples.size() - 1].position_m)
	return c.result()


func _case_station_range_and_mapping() -> Dictionary:
	var c := Case.new()
	c.name = "station_order_range_and_mapping"

	var built := SourceScript.build()
	if not bool(built["ok"]):
		c.check(false, "live conversion failed: " + String(built["error"]))
		return c.result()
	var path: DriverScript.CalibrationPath = built["path"]

	var previous := -INF
	var strictly_increasing := true
	var finite := true
	for sample: DriverScript.PathSample in path.samples:
		if sample.s_m <= previous:
			strictly_increasing = false
		previous = sample.s_m
		if not is_finite(sample.position_m.x) or not is_finite(sample.position_m.y):
			finite = false
		if not is_finite(sample.target_speed_m_s):
			finite = false
	c.check(strictly_increasing, "stations are strictly increasing")
	c.check(finite, "all positions and speeds are finite")

	c.close(path.first_s_m(), 0.0, VECTOR_TOLERANCE, "first station")
	c.close(
		path.last_s_m(),
		SourceScript.EXPECTED_TOTAL_LENGTH_M,
		STATION_TOLERANCE,
		"last station is the authored 50 + 188.4956 + 50 total"
	)
	c.close(
		path.last_s_m(),
		288.49556,
		STATION_TOLERANCE,
		"last station is the documented 288.49556 m total"
	)
	c.close(
		path.length_m(),
		SourceScript.EXPECTED_TOTAL_LENGTH_M,
		STATION_TOLERANCE,
		"declared open-profile length"
	)
	c.check(
		path.last_s_m() > 220.0,
		"station range is the authored ~288.5 m, not the request's approximate 220 m"
	)

	# Mapping must be the committed adapter mapping for the bay origin.
	var origin_road: Vector2 = AdapterScript.world_vector_to_road(
		SourceScript.EXPECTED_ORIGIN
	)
	c.vector_close(path.samples[0].position_m, origin_road, VECTOR_TOLERANCE, "start maps bay origin")
	c.vector_close(origin_road, Vector2(0.0, -60.0), VECTOR_TOLERANCE, "bay origin road coordinates")

	var summary: Dictionary = built["summary"]
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


func _case_arc_geometry_and_direction() -> Dictionary:
	var c := Case.new()
	c.name = "arc_geometry_and_direction"

	var built := SourceScript.build()
	if not bool(built["ok"]):
		c.check(false, "live conversion failed: " + String(built["error"]))
		return c.result()
	var path: DriverScript.CalibrationPath = built["path"]

	var arc_start_s := SourceScript.EXPECTED_APPROACH_LENGTH_M
	var arc_end_s := arc_start_s + SourceScript.EXPECTED_ARC_LENGTH_M
	# Road-plane center: corner entry is (0, -10), tangent +y; a left turn's
	# center is 120 m toward -x. The world-to-road mapping is x = world.x,
	# y = -world.z.
	var center_road := Vector2(-SourceScript.EXPECTED_ARC_RADIUS_M, -10.0)

	var on_arc := false
	var previous: DriverScript.PathSample = null
	var monotonic_left := true
	for sample: DriverScript.PathSample in path.samples:
		if sample.s_m + STATION_TOLERANCE < arc_start_s:
			continue
		if sample.s_m - STATION_TOLERANCE > arc_end_s:
			continue
		on_arc = true
		var radial := sample.position_m.distance_to(center_road)
		c.close(
			radial,
			SourceScript.EXPECTED_ARC_RADIUS_M,
			ARC_RADIUS_TOLERANCE,
			"arc sample radius"
		)
		if previous != null:
			if sample.position_m.x > previous.position_m.x + 1e-9:
				monotonic_left = false
			if sample.position_m.y < previous.position_m.y - 1e-9:
				monotonic_left = false
		previous = sample
	c.check(on_arc, "arc station coverage present")
	c.check(monotonic_left, "left turn moves toward -x and +y throughout the arc")

	# Corner entry/exit are the expected circle tangency points.
	c.vector_close(
		path.samples[path.samples.size() - 1].position_m,
		Vector2(-170.0, 110.0),
		ARC_POLYLINE_TOLERANCE_M,
		"arc exit tangent point and finish"
	)
	return c.result()


func _case_repeat_identity_and_path_contract() -> Dictionary:
	var c := Case.new()
	c.name = "repeat_identity_and_path_contract"

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
	var mid := path_a.interpolate_at(25.0)
	c.close(mid.position_m.x, 0.0, VECTOR_TOLERANCE, "mid-approach interpolation x")
	c.close(mid.position_m.y, -35.0, VECTOR_TOLERANCE, "mid-approach interpolation y")
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
	c.check(
		not String(missing_bay["error"]).is_empty(),
		"missing bay refusal carries a diagnostic"
	)
	c.check(missing_bay["path"] == null, "missing bay returns no path")

	# Missing fixture.
	var missing_fixture := SourceScript.build({}, {}, false, true)
	c.check(not bool(missing_fixture["ok"]), "missing fixture is refused")
	c.check(
		not String(missing_fixture["error"]).is_empty(),
		"missing fixture refusal carries a diagnostic"
	)

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

	# Builder sample semantics: the raw centerline has 292 samples, with exact
	# boundary duplicates at the approach/arc and arc/exit joins. The conversion
	# accepts those two only because they are identical points at recorded
	# adjacent-section boundaries.
	var live_bay := _live_bay_copy()
	c.check(not live_bay.is_empty(), "test can sample the live sweeper bay")
	if not live_bay.is_empty():
		var sampled: Dictionary = SourceScript.BuilderScript._sample_bay(live_bay)
		var raw_samples: Array = sampled["samples"]
		var raw_sections: Array = sampled["sections"]
		c.equal(raw_samples.size(), 292, "builder raw sample count")
		var duplicate_indices: Array = []
		for index in range(1, raw_samples.size()):
			if float(raw_samples[index]["s"]) == float(raw_samples[index - 1]["s"]):
				duplicate_indices.append(index)
		c.equal(duplicate_indices, [51, 241], "exact boundary duplicate sample indices")
		c.equal(
			SourceScript._validate_samples(raw_samples, raw_sections),
			"",
			"unmodified raw builder samples pass conversion validation"
		)

		# Discriminatory discontinuity: moving only the duplicate arc-entry
		# sample makes it no longer the identical boundary point, so it must be
		# refused rather than silently dropped.
		var discontinuous: Array = []
		for smp in raw_samples:
			discontinuous.append(smp.duplicate(true))
		discontinuous[51]["pos"] = discontinuous[51]["pos"] + Vector3(0.001, 0.0, 0.0)
		var discontinuity_error := SourceScript._validate_samples(discontinuous, raw_sections)
		c.check(not discontinuity_error.is_empty(), "discontinuous join duplicate is refused")
		c.check(
			discontinuity_error.contains("discontinuous"),
			"discontinuity refusal names the positional mismatch"
		)

		# A repeated station away from a genuine section join is not dropped.
		var repeated_interior: Array = []
		for smp in raw_samples:
			repeated_interior.append(smp.duplicate(true))
		repeated_interior[10]["s"] = float(repeated_interior[9]["s"])
		var repeat_error := SourceScript._validate_samples(repeated_interior, raw_sections)
		c.check(not repeat_error.is_empty(), "non-join repeated station is refused")
		c.check(
			repeat_error.contains("not marked as an ordinary section join"),
			"non-join repeat refusal explains why it is not accepted"
		)

		# Swapping adjacent interior samples reorders stations and must refuse.
		var reordered: Array = []
		for smp in raw_samples:
			reordered.append(smp.duplicate(true))
		var held: Dictionary = reordered[10]
		reordered[10] = reordered[11]
		reordered[11] = held
		var reorder_error := SourceScript._validate_samples(reordered, raw_sections)
		c.check(not reorder_error.is_empty(), "reordered samples are refused")
		c.check(
			reorder_error.contains("non-monotonic or reordered"),
			"reordered refusal names station ordering"
		)

	# Malformed fixture document.
	var malformed := SourceScript.build({}, {"fixture_id": "fixture.handling.other"})
	c.check(not bool(malformed["ok"]), "malformed fixture identity is refused")

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


func _case_provisional_labels() -> Dictionary:
	var c := Case.new()
	c.name = "provisional_labels"

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
	var all_constant := true
	for sample: DriverScript.PathSample in path.samples:
		if absf(sample.target_speed_m_s - SourceScript.PROVISIONAL_TARGET_SPEED_M_S) > 0.0:
			all_constant = false
	c.check(all_constant, "target speed is the single provisional lab value")
	c.equal(
		SourceScript.PROVISIONAL_TARGET_SPEED_M_S,
		12.0,
		"provisional target speed is the documented lab value"
	)
	return c.result()
