extends Node
## Bounded physical M1.7 sweeper bridge from CalibrationDriver to the ordinary
## DriveLab motor/gearbox/MotorBodyAdapter integration.
##
## The laboratory instantiates the committed scenes/laboratory/drive_lab.tscn
## unchanged. DriveLab owns one CharacterBody3D, one ArcadeMotor, one
## AutomaticGearbox and the MotorBodyAdapter commit path; this bridge only
## supplies one externally validated progress number and one CalibrationDriver
## command per logical 60 Hz tick, then calls DriveLab.step_once() exactly once.
## It never integrates motion itself and never moves the body between ticks.
##
## Spawn seam: DriveLab starts every car at the authored straight-bay marker and
## exposes no public spawn API for another bay. This lab therefore reads the
## authored HandlingLab `Spawn_sweeper` marker and writes the already-built
## public CarState/body/start-position fields once, before the first tick, with
## the gearbox left at its deterministic reset pair. It then verifies that the
## installed body basis and origin map back to the published CarState through
## the committed MotorBodyAdapter mapping. Progress is measured independently
## of DriveLab's straight-only `get_road_station_m()` accessor, because that
## accessor projects onto one fixed straight axis and cannot describe an arc.
##
## The 12 m/s target-speed profile comes from the committed
## tools/calibration_path_lab/calibration_path_source.gd conversion and is
## explicitly provisional. No grip/drift parity, lap completion, M1.7 acceptance
## or fun claim is made.

const ChecksScript := preload(
	"res://tools/calibration_sweeper_lab/calibration_sweeper_lab_checks.gd"
)
const SourceScript := preload(
	"res://tools/calibration_path_lab/calibration_path_source.gd"
)
const DriverScript := preload("res://src/calibration/calibration_driver.gd")
const AdapterScript := preload("res://src/simulation/motor_body_adapter.gd")
const DriveLabScript := preload("res://src/laboratory/drive_lab.gd")

const DRIVE_LAB_SCENE_PATH := "res://scenes/laboratory/drive_lab.tscn"
const HANDLING_LAB_SCENE_PATH := "res://scenes/laboratory/handling_lab.tscn"

## Bounded first pass. The authored approach is 50 m and the provisional target
## speed is 12 m/s; roughly 300 ticks are needed to reach the arc, so 420 leaves
## margin while staying far below the 1200-tick bound.
const BRIDGE_TICKS := 420
## Separate full-arc-exit witness. The authored arc ends at
## `ARC_ENTRY_STATION_M + EXPECTED_ARC_LENGTH_M` (~238.4956 m); reaching
## `FULL_ARC_EXIT_STATION_M` means at least 6.5 m into the authored 50 m exit.
## This mode is opt-in so the default validator keeps its existing 420-tick
## arc-entry case separate.
const FULL_ARC_EXIT_TICKS := 1800
const FULL_ARC_EXIT_STATION_M := 245.0
const FULL_ARC_EXIT_TRACE_SCHEMA := "roadstorm.calibration_sweeper_lab.exit_trace.v1"
## Every JSON-facing numeric field recorded in a physical trace. Repeat runs
## must agree on all of them within REPEAT_TOLERANCE.
const TRACE_NUMERIC_REPEAT_FIELDS := [
	"station_before_m", "station_after_m", "station_delta_m",
	"lateral_error_before_m", "lateral_error_after_m", "nearest_distance_m",
	"position_x_m", "position_y_m", "world_x_m", "world_y_m", "world_z_m",
	"speed_m_s", "forward_speed_m_s", "heading_rad", "steer", "throttle",
	"brake", "lookahead_m", "target_s_m", "target_speed_m_s", "remainder_m",
	"drive_lab_straight_projection_m",
]
## Every nonnumeric trace field. Repeat runs must agree on these exactly.
const TRACE_EXACT_REPEAT_FIELDS := [
	"tick", "gear_index", "result_status", "grounded", "reverse_engaged",
	"contact", "wall_contact", "substeps",
]
const SETTLE_FRAMES := 10
const CLEANUP_FRAMES := 8
const ARC_ENTRY_STATION_M := 50.0
## Authored sweeper half-width (12 m road). This is a road-containment report
## bound, not a tuned controller limit.
const ROAD_HALF_WIDTH_M := 6.0
const LATERAL_ERROR_BOUND_M := ROAD_HALF_WIDTH_M
const STATION_MONOTONIC_TOLERANCE_M := 0.01
## Declared same-host repeat tolerance for independently recorded JSON-facing
## numbers. The committed DriveLab/Jolt trace is expected to be deterministic;
## this covers floating-point roundoff only.
const REPEAT_TOLERANCE := 1e-6
const PATH_PROBE_TOLERANCE_M := 1e-3

var _holder: Node3D = null
var _case_results: Array = []
var _total_checks := 0
var _total_failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_holder = Node3D.new()
	_holder.name = "CalibrationSweeperLabHolder"
	add_child(_holder)
	if _full_arc_exit_requested():
		_run_full_arc_exit()
	else:
		_run()


## The separate full-arc-exit witness is opt-in: the default invocation keeps
## the original three cases and the bounded 420-tick arc-entry budget.
func _full_arc_exit_requested() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == "--full-arc-exit":
			return true
	return false


func _run() -> void:
	var geometry_case := ChecksScript.Case.new()
	geometry_case.name = "sweeper_geometry_and_source_identity"
	await _case_geometry_identity(geometry_case)
	_record_case(geometry_case)

	var bridge_case := ChecksScript.Case.new()
	bridge_case.name = "physical_sweeper_bridge_repeat"
	await _case_physical_bridge_repeat(bridge_case)
	_record_case(bridge_case)

	var refusal_case := ChecksScript.Case.new()
	refusal_case.name = "invalid_or_mismatched_source_refusal_no_motor_step"
	await _case_invalid_source_refusal(refusal_case)
	_record_case(refusal_case)

	var failed_cases := 0
	for result in _case_results:
		if not bool(result["pass"]):
			failed_cases += 1
	var summary := {
		"schema": "roadstorm.calibration_sweeper_lab.summary.v1",
		"status": "provisional_physical_evidence_not_acceptance",
		"bridge_scope": (
			"physical HandlingLab sweeper CalibrationDriver to ordinary DriveLab "
			+ "motor/gearbox/MotorBodyAdapter integration only"
		),
		"profile_status": "provisional_not_tuned_not_benchmark_not_reference",
		"backend": str(ProjectSettings.get_setting("physics/3d/physics_engine")),
		"engine_version": Engine.get_version_info(),
		"ticks_per_run": BRIDGE_TICKS,
		"repeat_tolerance": REPEAT_TOLERANCE,
		"cases": _case_results.size(),
		"cases_passed": _case_results.size() - failed_cases,
		"checks": _total_checks,
		"checks_failed": _total_failures,
		"pass": failed_cases == 0,
		"case_results": _case_results.duplicate(true),
	}
	print("CALIBRATION_SWEEPER_SUMMARY ", JSON.stringify(summary))
	print("CHECKS_TOTAL=", _total_checks, " CHECKS_FAILED=", _total_failures)
	_write_summary_if_requested(summary)
	get_tree().quit(0 if failed_cases == 0 else 1)


func _write_summary_if_requested(summary: Dictionary) -> void:
	var out_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--summary-out="):
			out_path = arg.substr("--summary-out=".length())
			break
	if out_path.is_empty():
		return
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write calibration sweeper summary to %s" % out_path)
		return
	file.store_string(JSON.stringify(summary, "  ", false, true))
	file.close()
	print("CALIBRATION_SWEEPER_SUMMARY_WRITTEN ", out_path)


func _record_case(c) -> void:
	var result: Dictionary = c.result()
	_case_results.append(result)
	_total_checks += int(result["checks"])
	_total_failures += int(result["checks_failed"])
	print(
		"CALIBRATION_SWEEPER_LAB_CASE ",
		JSON.stringify({
			"case": result["case"],
			"checks": result["checks"],
			"checks_failed": result["checks_failed"],
			"pass": result["pass"],
		})
	)


# --- Case 1: geometry and source identity ----------------------------------


func _case_geometry_identity(c) -> void:
	var packed: PackedScene = load(HANDLING_LAB_SCENE_PATH)
	if packed == null:
		c.check(false, "geometry.handling_lab_scene_load")
		return
	var lab = packed.instantiate()
	if lab == null:
		c.check(false, "geometry.handling_lab_scene_instantiate")
		return
	_holder.add_child(lab)
	await _settle()

	var bay_node := lab.get_node_or_null("Bay_sweeper") as Node3D
	c.check(bay_node != null, "geometry.sweeper_bay_node_present")
	if bay_node == null:
		await _teardown_node(lab)
		return

	# Authored spawn marker: the pose the bridge must install.
	var marker := bay_node.get_node_or_null("Spawn_sweeper") as Marker3D
	c.check(marker != null, "geometry.sweeper_spawn_marker_present")
	if marker != null:
		c.close(
			float(marker.global_position.x),
			SourceScript.EXPECTED_ORIGIN.x,
			1e-6,
			"geometry.spawn_x_matches_authored_origin"
		)
		c.close(
			float(marker.global_position.y),
			SourceScript.EXPECTED_ORIGIN.y,
			1e-6,
			"geometry.spawn_y_matches_authored_origin"
		)
		c.close(
			float(marker.global_position.z),
			SourceScript.EXPECTED_ORIGIN.z,
			1e-6,
			"geometry.spawn_z_matches_authored_origin"
		)
		c.close(
			float(marker.get_meta("heading_deg")),
			SourceScript.EXPECTED_YAW_DEG,
			1e-6,
			"geometry.spawn_heading_matches_authored_yaw"
		)

	# Collider inventory: every authored section owns a real terrain collider.
	var collision_bodies: Array = []
	var mesh_instances: Array = []
	for child in bay_node.get_children():
		if child is StaticBody3D and String(child.get_meta("bay_id", "")) == "sweeper":
			collision_bodies.append(child)
		if child is MeshInstance3D and String(child.get_meta("bay_id", "")) == "sweeper":
			mesh_instances.append(child)
	c.equal(collision_bodies.size(), 3, "geometry.three_sweeper_collision_runs")
	c.equal(mesh_instances.size(), 3, "geometry.three_sweeper_surface_runs")

	var section_ids := ["sweeper.approach", "sweeper.arc", "sweeper.exit"]
	for index in range(mini(section_ids.size(), collision_bodies.size())):
		var body: StaticBody3D = collision_bodies[index]
		c.equal(String(body.get_meta("section_id", "")), section_ids[index], "geometry.collider_section_id_%d" % index)
		c.equal(String(body.get_meta("surface_id", "")), "asphalt", "geometry.collider_surface_%d" % index)
		c.equal(String(body.get_meta("collision_role", "")), "terrain", "geometry.collider_role_%d" % index)
		c.equal(String(body.get_meta("shape_kind", "")), "concave_polygon", "geometry.collider_shape_%d" % index)
		var shape_node: CollisionShape3D = null
		for child in body.get_children():
			if child is CollisionShape3D:
				shape_node = child
				break
		c.check(shape_node != null, "geometry.collider_shape_node_%d" % index)
		if shape_node != null and shape_node.shape is ConcavePolygonShape3D:
			c.check(
				(shape_node.shape as ConcavePolygonShape3D).get_faces().size() > 0,
				"geometry.collider_has_faces_%d" % index
			)

	# Manifest section records tie the collider identity to the authored table.
	var manifest: Dictionary = lab.get_meta("lab_manifest") as Dictionary
	if manifest == null:
		manifest = {}
	var sweeper_record: Dictionary = {}
	for record in manifest.get("bays", []):
		if String(record.get("bay_id", "")) == "sweeper":
			sweeper_record = record
			break
	c.check(not sweeper_record.is_empty(), "geometry.manifest_sweeper_bay_present")
	if not sweeper_record.is_empty():
		var sections: Array = sweeper_record.get("sections", [])
		c.equal(sections.size(), 3, "geometry.manifest_section_count")
		var expected_stations := [0.0, 50.0, 50.0 + SourceScript.EXPECTED_ARC_LENGTH_M]
		var expected_ends := [50.0, 50.0 + SourceScript.EXPECTED_ARC_LENGTH_M, SourceScript.EXPECTED_TOTAL_LENGTH_M]
		for index in range(mini(3, sections.size())):
			c.close(
				float(sections[index].get("start_s_m", NAN)),
				expected_stations[index],
				1e-4,
				"geometry.manifest_start_station_%d" % index
			)
			c.close(
				float(sections[index].get("end_s_m", NAN)),
				expected_ends[index],
				1e-4,
				"geometry.manifest_end_station_%d" % index
			)

	# The committed path's own centerline must land on those colliders. Probe
	# exact interpolated path positions, including both section boundaries.
	var built := SourceScript.build()
	c.check(bool(built["ok"]), "geometry.committed_source_build_succeeds")
	if not bool(built["ok"]):
		await _teardown_node(lab)
		return
	var path: DriverScript.CalibrationPath = built["path"]
	var summary: Dictionary = built["summary"]
	c.equal(String(summary["bay_id"]), "sweeper", "geometry.source_bay_id")
	c.equal(String(summary["fixture_id"]), SourceScript.EXPECTED_FIXTURE_ID, "geometry.source_fixture_id")
	c.equal(int(summary["sample_count"]), 290, "geometry.source_unique_samples")
	c.equal(int(summary["builder_sample_count"]), 292, "geometry.source_raw_samples")
	c.equal(int(summary["join_duplicates_skipped"]), 2, "geometry.source_join_duplicates")
	c.close(
		float(summary["length_m"]),
		SourceScript.EXPECTED_TOTAL_LENGTH_M,
		1e-4,
		"geometry.source_length"
	)
	c.close(float(summary["target_speed_m_s"]), SourceScript.PROVISIONAL_TARGET_SPEED_M_S, 0.0, "geometry.source_target_speed")
	c.check(
		String(summary["target_speed_provenance"]).contains("not_measured_or_tuned"),
		"geometry.source_target_speed_provisional"
	)

	var probe_stations: Array = [
		0.0, 10.0, 20.0, 30.0, 40.0, 49.0, 50.0, 51.0, 60.0, 80.0, 100.0,
		140.0, 180.0, 220.0, 50.0 + SourceScript.EXPECTED_ARC_LENGTH_M,
		250.0, SourceScript.EXPECTED_TOTAL_LENGTH_M,
	]
	var probes_hit := 0
	var worst_probe_y := 0.0
	for station in probe_stations:
		var point: Vector2 = path.interpolate_at(float(station)).position_m
		var hit := _ray_down(lab, point)
		if not bool(hit["ok"]):
			continue
		probes_hit += 1
		c.equal(
			String(hit["bay_id"]), "sweeper",
			"geometry.probe_station_%s_hits_sweeper_collider" % str(station)
		)
		c.equal(String(hit["surface_id"]), "asphalt", "geometry.probe_station_%s_asphalt" % str(station))
		worst_probe_y = maxf(worst_probe_y, absf(float(hit["position_y"])))
	c.equal(probes_hit, probe_stations.size(), "geometry.all_path_probes_hit_sweeper")
	c.close(worst_probe_y, 0.0, PATH_PROBE_TOLERANCE_M, "geometry.probe_hit_height_flat")
	c.measurements["probe_stations"] = probe_stations.duplicate()
	c.measurements["probe_hit_count"] = probes_hit
	c.measurements["worst_probe_height_m"] = worst_probe_y

	await _teardown_node(lab)


func _ray_down(world_owner: Node3D, road_point: Vector2) -> Dictionary:
	var space := world_owner.get_world_3d().direct_space_state
	if space == null:
		return {"ok": false}
	var query := PhysicsRayQueryParameters3D.new()
	query.from = Vector3(road_point.x, 3.0, -road_point.y)
	query.to = Vector3(road_point.x, -10.0, -road_point.y)
	query.collision_mask = 1
	query.hit_from_inside = false
	var hit := space.intersect_ray(query)
	if hit.is_empty() or not hit.has("collider") or hit["collider"] == null:
		return {"ok": false}
	var collider: Object = hit["collider"]
	return {
		"ok": true,
		"bay_id": String(collider.get_meta("bay_id", "")),
		"surface_id": String(collider.get_meta("surface_id", "")),
		"position_y": float(hit["position"].y),
	}


# --- Case 2: physical bridge repeat ----------------------------------------


func _case_physical_bridge_repeat(c) -> void:
	var built := SourceScript.build()
	if not bool(built["ok"]):
		c.check(false, "bridge.committed_source_build_succeeds: " + String(built["error"]))
		return
	var path: DriverScript.CalibrationPath = built["path"]
	c.check(path.is_valid(), "bridge.path_valid: " + path.validation_error())
	var tuning := DriverScript.Tuning.make()
	c.check(tuning != null and tuning.is_valid(), "bridge.driver_tuning_valid")

	var first: Dictionary = await _run_physical_bridge(c, "first", path, tuning)
	var second: Dictionary = await _run_physical_bridge(c, "second", path, tuning)
	c.check(bool(first.get("completed", false)), "bridge.first_run_completed")
	c.check(bool(second.get("completed", false)), "bridge.second_run_completed")
	if not (bool(first.get("completed", false)) and bool(second.get("completed", false))):
		return

	var first_trace: Array = first.get("trace", [])
	var second_trace: Array = second.get("trace", [])
	c.equal(first_trace.size(), BRIDGE_TICKS, "bridge.first_trace_length")
	c.equal(second_trace.size(), BRIDGE_TICKS, "bridge.second_trace_length")
	c.equal(first_trace.size(), second_trace.size(), "bridge.repeat_trace_lengths_match")
	if first_trace.size() != second_trace.size():
		return

	var compared_fields: Array = TRACE_NUMERIC_REPEAT_FIELDS
	var max_diffs := {}
	for field in compared_fields:
		max_diffs[field] = 0.0
	var gear_mismatches := 0
	var status_mismatches := 0
	var contact_mismatches := 0
	var tick_mismatches := 0
	var grounded_mismatches := 0
	var reverse_mismatches := 0
	var wall_contact_mismatches := 0
	var substep_mismatches := 0
	for index in range(first_trace.size()):
		var a: Dictionary = first_trace[index]
		var b: Dictionary = second_trace[index]
		for field in compared_fields:
			var diff := absf(float(a[field]) - float(b[field]))
			max_diffs[field] = maxf(float(max_diffs[field]), diff)
		if int(a["gear_index"]) != int(b["gear_index"]):
			gear_mismatches += 1
		if int(a["result_status"]) != int(b["result_status"]):
			status_mismatches += 1
		if bool(a["contact"]) != bool(b["contact"]):
			contact_mismatches += 1
		if int(a["tick"]) != int(b["tick"]):
			tick_mismatches += 1
		if bool(a["grounded"]) != bool(b["grounded"]):
			grounded_mismatches += 1
		if bool(a["reverse_engaged"]) != bool(b["reverse_engaged"]):
			reverse_mismatches += 1
		if bool(a["wall_contact"]) != bool(b["wall_contact"]):
			wall_contact_mismatches += 1
		if int(a["substeps"]) != int(b["substeps"]):
			substep_mismatches += 1

	var worst := 0.0
	var worst_field := ""
	for field in compared_fields:
		var value := float(max_diffs[field])
		if value > worst:
			worst = value
			worst_field = String(field)
	c.check(
		worst <= REPEAT_TOLERANCE,
		"bridge.same_host_repeat_within_tolerance (worst %s=%s tol=%s)"
			% [worst_field, str(worst), str(REPEAT_TOLERANCE)]
	)
	c.equal(gear_mismatches, 0, "bridge.repeat_gear_indications_identical")
	c.equal(status_mismatches, 0, "bridge.repeat_physical_statuses_identical")
	c.equal(contact_mismatches, 0, "bridge.repeat_contact_flags_identical")
	c.equal(tick_mismatches, 0, "bridge.repeat_ticks_identical")
	c.equal(grounded_mismatches, 0, "bridge.repeat_grounded_flags_identical")
	c.equal(reverse_mismatches, 0, "bridge.repeat_reverse_flags_identical")
	c.equal(wall_contact_mismatches, 0, "bridge.repeat_wall_contact_flags_identical")
	c.equal(substep_mismatches, 0, "bridge.repeat_substep_counts_identical")

	c.measurements["repeat_compared_fields"] = compared_fields.duplicate()
	c.measurements["repeat_exact_fields"] = TRACE_EXACT_REPEAT_FIELDS.duplicate()
	c.measurements["repeat_max_diffs"] = max_diffs.duplicate()
	c.measurements["repeat_worst_field"] = worst_field
	c.measurements["repeat_worst_diff"] = worst
	c.measurements["repeat_tolerance"] = REPEAT_TOLERANCE
	c.measurements["repeat_exact_mismatches"] = {
		"tick": tick_mismatches,
		"gear_index": gear_mismatches,
		"result_status": status_mismatches,
		"grounded": grounded_mismatches,
		"reverse_engaged": reverse_mismatches,
		"contact": contact_mismatches,
		"wall_contact": wall_contact_mismatches,
		"substeps": substep_mismatches,
	}
	c.measurements["first_final"] = first.get("final", {})
	c.measurements["second_final"] = second.get("final", {})
	c.measurements["first_selected_samples"] = _selected_samples(first_trace)
	c.measurements["second_selected_samples"] = _selected_samples(second_trace)


func _run_physical_bridge(
	c, label: String, path, tuning, expect_input_refusal := false
) -> Dictionary:
	var out := {
		"label": label,
		"completed": false,
		"trace": [],
		"final": {},
		"input_refusal": {},
		"steps_called": 0,
		"ticks_committed": 0,
	}
	var lab = _make_lab(c, label)
	if lab == null:
		return out
	await _settle()
	lab.set_auto_tick(false)
	c.check(not lab.is_auto_tick(), label + ".auto_tick_disabled")
	c.check(not lab.failed, label + ".laboratory_not_failed_after_settle")
	c.check(not lab.halted, label + ".laboratory_not_halted_after_settle")
	c.equal(int(lab.steps_called), 0, label + ".settle_made_no_adapter_calls")
	if lab.failed or lab.halted or lab.state == null or not lab.state.is_finite():
		c.check(false, label + ".initial_committed_state_finite")
		await _teardown_lab(lab)
		return out

	# Validate the bridge inputs at the run entry point, before placement or any
	# motor step. The refusal case uses the same path as a genuine control rather
	# than inferring no-step behavior only from component-level API calls.
	var control_position: Vector2 = lab.state.position_m
	var control_velocity: Vector2 = lab.state.velocity_m_s
	var control_heading: float = lab.state.heading_rad
	var input_refusal := _bridge_input_refusal(path, tuning)
	out["input_refusal"] = input_refusal.duplicate()
	if expect_input_refusal:
		c.check(
			bool(input_refusal["refused"]),
			label + ".invalid_input_refused_before_motor_step"
		)
		c.equal(
			String(input_refusal["code"]),
			"invalid_path",
			label + ".invalid_input_refusal_code"
		)
	else:
		c.check(not bool(input_refusal["refused"]), label + ".bridge_input_accepted")
	if bool(input_refusal["refused"]) or expect_input_refusal:
		c.equal(int(lab.steps_called), 0, label + ".input_control_no_adapter_step")
		c.equal(int(lab.ticks_committed), 0, label + ".input_control_no_commit")
		c.check(lab.state.position_m == control_position, label + ".input_control_position_unchanged")
		c.check(lab.state.velocity_m_s == control_velocity, label + ".input_control_velocity_unchanged")
		c.check(lab.state.heading_rad == control_heading, label + ".input_control_heading_unchanged")
		out["steps_called"] = int(lab.steps_called)
		out["ticks_committed"] = int(lab.ticks_committed)
		await _teardown_lab(lab)
		return out

	if not _place_at_sweeper_start(lab, c, label):
		await _teardown_lab(lab)
		return out

	var trace: Array = []
	var accepted_decisions := 0
	var physical_commits := 0
	var finite_states := 0
	var validated_stations := 0
	var exclusivity_violations := 0
	var normalization_violations := 0
	var step_count_mismatches := 0
	var grounded_ticks := 0
	var contact_ticks := 0
	var wall_contact_ticks := 0
	var max_abs_lateral_error := 0.0
	var max_nearest_distance := 0.0
	var max_speed := 0.0
	var min_station_delta := INF
	var final_station := 0.0
	var first_arc_entry_tick := -1
	var first_arc_entry_station := 0.0
	var final_state = lab.state
	var start_ms := Time.get_ticks_msec()
	var end_ms := start_ms

	for tick in range(BRIDGE_TICKS):
		end_ms = Time.get_ticks_msec()
		if lab.failed or lab.halted:
			c.check(false, label + ".laboratory_alive_at_tick_%d" % tick)
			break
		var committed_state = lab.state
		if committed_state == null or not committed_state.is_finite():
			c.check(false, label + ".finite_committed_input_state_tick_%d" % tick)
			break

		# External validation of progress: nearest projection onto the committed
		# authored path, independent of DriveLab's straight-only accessor.
		var before_fix := _nearest_station(path, committed_state.position_m)
		var station: float = float(before_fix["station_m"])
		var lateral_before: float = float(before_fix["lateral_error_m"])
		var distance_before: float = float(before_fix["distance_m"])
		var station_valid := (
			is_finite(station)
			and is_finite(lateral_before)
			and is_finite(distance_before)
			and distance_before <= ROAD_HALF_WIDTH_M + PATH_PROBE_TOLERANCE_M
		)
		if not station_valid:
			c.check(false, label + ".validated_sweeper_station_tick_%d" % tick)
			break
		validated_stations += 1

		var decision: DriverScript.Decision = DriverScript.decide(
			committed_state, path, station, tuning
		)
		if not decision.accepted or decision.command == null:
			c.check(false, label + ".decision_accepted_tick_%d" % tick)
			break
		accepted_decisions += 1
		var command = decision.command
		if not command.is_normalized():
			normalization_violations += 1
		if command.throttle > 0.0 and command.brake > 0.0:
			exclusivity_violations += 1

		var steps_before := int(lab.steps_called)
		var commits_before := int(lab.ticks_committed)
		var result: AdapterScript.Result = lab.step_once(command)
		if result == null:
			c.check(false, label + ".physical_result_present_tick_%d" % tick)
			break
		if int(result.status) != int(AdapterScript.Status.COMMITTED):
			c.check(false, label + ".physical_commit_tick_%d" % tick)
			break
		physical_commits += 1
		if int(lab.steps_called) != steps_before + 1:
			step_count_mismatches += 1
		if int(lab.ticks_committed) != commits_before + 1:
			step_count_mismatches += 1

		var post_state = lab.state
		if post_state == null or not post_state.is_finite():
			c.check(false, label + ".finite_committed_output_state_tick_%d" % tick)
			break
		finite_states += 1
		final_state = post_state
		var after_fix := _nearest_station(path, post_state.position_m)
		var post_station := float(after_fix["station_m"])
		var lateral_after := float(after_fix["lateral_error_m"])
		var distance_after := float(after_fix["distance_m"])
		final_station = post_station
		min_station_delta = minf(min_station_delta, post_station - station)
		max_abs_lateral_error = maxf(max_abs_lateral_error, absf(lateral_after))
		max_nearest_distance = maxf(max_nearest_distance, distance_after)
		max_speed = maxf(max_speed, post_state.speed_m_s())
		if first_arc_entry_tick < 0 and post_station >= ARC_ENTRY_STATION_M:
			first_arc_entry_tick = tick
			first_arc_entry_station = post_station
		if post_state.grounded:
			grounded_ticks += 1
		if result.contact:
			contact_ticks += 1
		if result.wall_contact:
			wall_contact_ticks += 1

		var world: Vector3 = lab.body.global_transform.origin
		trace.append({
			"tick": tick,
			"station_before_m": station,
			"station_after_m": post_station,
			"station_delta_m": post_station - station,
			"lateral_error_before_m": lateral_before,
			"lateral_error_after_m": lateral_after,
			"nearest_distance_m": distance_after,
			"position_x_m": post_state.position_m.x,
			"position_y_m": post_state.position_m.y,
			"world_x_m": world.x,
			"world_z_m": world.z,
			"world_y_m": world.y,
			"speed_m_s": post_state.speed_m_s(),
			"forward_speed_m_s": post_state.forward_speed_m_s(),
			"heading_rad": post_state.heading_rad,
			"steer": command.steer,
			"throttle": command.throttle,
			"brake": command.brake,
			"lookahead_m": decision.telemetry.lookahead_m,
			"target_s_m": decision.telemetry.target_s_m,
			"target_speed_m_s": decision.telemetry.target_speed_m_s,
			"gear_index": int(post_state.gear_index),
			"result_status": int(result.status),
			"grounded": post_state.grounded,
			"reverse_engaged": post_state.reverse_engaged,
			"contact": result.contact,
			"wall_contact": result.wall_contact,
			"substeps": result.substeps,
			"remainder_m": result.remainder_m,
			"drive_lab_straight_projection_m": lab.get_road_station_m(),
		})
		await get_tree().physics_frame

	c.equal(accepted_decisions, BRIDGE_TICKS, label + ".all_decisions_accepted")
	c.equal(physical_commits, BRIDGE_TICKS, label + ".all_ticks_physically_committed")
	c.equal(finite_states, BRIDGE_TICKS, label + ".all_committed_states_finite")
	c.equal(validated_stations, BRIDGE_TICKS, label + ".all_stations_externally_validated")
	c.equal(exclusivity_violations, 0, label + ".throttle_brake_mutually_exclusive")
	c.equal(normalization_violations, 0, label + ".commands_normalized")
	c.equal(step_count_mismatches, 0, label + ".exactly_one_adapter_step_and_commit_per_tick")
	c.equal(int(lab.steps_called), BRIDGE_TICKS, label + ".adapter_steps_exact")
	c.equal(int(lab.ticks_committed), BRIDGE_TICKS, label + ".committed_ticks_exact")
	c.equal(grounded_ticks, BRIDGE_TICKS, label + ".grounded_on_every_tick")
	c.equal(contact_ticks, 0, label + ".no_contacts")
	c.equal(wall_contact_ticks, 0, label + ".no_wall_contacts")
	c.check(
		max_abs_lateral_error <= LATERAL_ERROR_BOUND_M,
		label + ".lateral_error_within_road_half_width"
	)
	c.check(
		max_nearest_distance <= ROAD_HALF_WIDTH_M + PATH_PROBE_TOLERANCE_M,
		label + ".nearest_distance_within_road"
	)
	c.check(
		first_arc_entry_tick >= 0,
		label + ".arc_entry_observed"
	)
	c.check(
		final_station >= ARC_ENTRY_STATION_M,
		label + ".crossed_approach_to_arc_boundary"
	)
	c.check(
		min_station_delta >= -STATION_MONOTONIC_TOLERANCE_M,
		label + ".external_station_monotonic"
	)
	c.check(not lab.failed, label + ".laboratory_not_failed_after_run")
	c.check(not lab.halted, label + ".laboratory_not_halted_after_run")

	var completed: bool = (
		accepted_decisions == BRIDGE_TICKS
		and physical_commits == BRIDGE_TICKS
		and finite_states == BRIDGE_TICKS
		and validated_stations == BRIDGE_TICKS
		and exclusivity_violations == 0
		and normalization_violations == 0
		and step_count_mismatches == 0
		and grounded_ticks == BRIDGE_TICKS
		and contact_ticks == 0
		and wall_contact_ticks == 0
		and max_abs_lateral_error <= LATERAL_ERROR_BOUND_M
		and first_arc_entry_tick >= 0
		and final_station >= ARC_ENTRY_STATION_M
		and min_station_delta >= -STATION_MONOTONIC_TOLERANCE_M
		and not lab.failed
		and not lab.halted
	)
	var final := {
		"station_m": final_station,
		"forward_progress_m": final_station,
		"arc_entry_tick": first_arc_entry_tick,
		"arc_entry_station_m": first_arc_entry_station,
		"speed_m_s": final_state.speed_m_s(),
		"forward_speed_m_s": final_state.forward_speed_m_s(),
		"position_x_m": final_state.position_m.x,
		"position_y_m": final_state.position_m.y,
		"world_x_m": lab.body.global_transform.origin.x,
		"world_z_m": lab.body.global_transform.origin.z,
		"heading_rad": final_state.heading_rad,
		"gear_index": int(final_state.gear_index),
		"max_speed_m_s": max_speed,
		"max_abs_lateral_error_m": max_abs_lateral_error,
		"max_nearest_distance_m": max_nearest_distance,
		"min_station_delta_m": 0.0 if min_station_delta == INF else min_station_delta,
		"logical_drive_time_s": float(BRIDGE_TICKS) / 60.0,
		"wall_drive_time_s": float(end_ms - start_ms) / 1000.0,
		"gear_shift_events": int(lab.gear_shift_events.size()),
		"grounded_ticks": grounded_ticks,
		"contact_ticks": contact_ticks,
		"wall_contact_ticks": wall_contact_ticks,
		"steps_called": int(lab.steps_called),
		"ticks_committed": int(lab.ticks_committed),
	}
	out["completed"] = completed
	out["trace"] = trace
	out["final"] = final
	out["steps_called"] = int(lab.steps_called)
	out["ticks_committed"] = int(lab.ticks_committed)
	print(
		"CALIBRATION_SWEEPER_TRACE ",
		JSON.stringify({
			"schema": "roadstorm.calibration_sweeper_lab.trace.v1",
			"run": label,
			"profile_status": "provisional_not_tuned_not_benchmark_not_reference",
			"ticks": trace.size(),
			"records": trace,
		})
	)
	c.measurements[label + "_final"] = final.duplicate()
	c.measurements[label + "_trace_ticks"] = trace.size()
	c.measurements[label + "_first_arc_entry_tick"] = first_arc_entry_tick
	c.measurements[label + "_max_abs_lateral_error_m"] = max_abs_lateral_error
	c.measurements[label + "_max_nearest_distance_m"] = max_nearest_distance
	c.measurements[label + "_steps_called"] = int(lab.steps_called)
	c.measurements[label + "_ticks_committed"] = int(lab.ticks_committed)
	await _teardown_lab(lab)
	return out


func _bridge_input_refusal(path, tuning) -> Dictionary:
	if path == null:
		return {
			"refused": true,
			"code": "missing_path",
			"detail": "bridge input path is null",
		}
	if not path.is_valid():
		return {
			"refused": true,
			"code": "invalid_path",
			"detail": path.validation_error(),
		}
	if tuning == null or not tuning.is_valid():
		return {
			"refused": true,
			"code": "invalid_tuning",
			"detail": "bridge input tuning is missing or invalid",
		}
	return {"refused": false, "code": "", "detail": ""}


# --- Separate case: full arc exit ------------------------------------------

## Opt-in full-arc-exit witness. Same authored start, same ordinary DriveLab
## motor/gearbox/MotorBodyAdapter path and same committed CalibrationDriver
## decisions as the 420-tick bridge, but a hard 1800-tick budget and an exit
## threshold 6.5 m past the authored arc end. A run that cannot reach the
## threshold records every tick it did commit and fails honestly; a failing
## trace is never truncated or hidden.
func _run_full_arc_exit() -> void:
	var exit_case := ChecksScript.Case.new()
	exit_case.name = "full_arc_exit_physical_repeat"
	await _case_full_arc_exit(exit_case)
	var result: Dictionary = exit_case.result()
	_total_checks += int(result["checks"])
	_total_failures += int(result["checks_failed"])
	print(
		"CALIBRATION_SWEEPER_EXIT_CASE ",
		JSON.stringify({
			"case": result["case"],
			"checks": result["checks"],
			"checks_failed": result["checks_failed"],
			"pass": result["pass"],
		})
	)
	var summary := {
		"schema": "roadstorm.calibration_sweeper_lab.exit_summary.v1",
		"status": "provisional_physical_evidence_not_acceptance",
		"scope": (
			"separate full-arc-exit physical witness at the provisional 12 m/s "
			+ "profile; not grip/drift parity, a lap or M1.7 acceptance"
		),
		"profile_status": "provisional_not_tuned_not_benchmark_not_reference",
		"backend": str(ProjectSettings.get_setting("physics/3d/physics_engine")),
		"engine_version": Engine.get_version_info(),
		"tick_budget": FULL_ARC_EXIT_TICKS,
		"exit_station_m": FULL_ARC_EXIT_STATION_M,
		"arc_end_station_m": ARC_ENTRY_STATION_M + float(SourceScript.EXPECTED_ARC_LENGTH_M),
		"repeat_tolerance": REPEAT_TOLERANCE,
		"cases": 1,
		"cases_passed": 1 if result["pass"] else 0,
		"checks": _total_checks,
		"checks_failed": _total_failures,
		"pass": bool(result["pass"]),
		"case_results": [result],
	}
	print("CALIBRATION_SWEEPER_EXIT_SUMMARY ", JSON.stringify(summary))
	print("CHECKS_TOTAL=", _total_checks, " CHECKS_FAILED=", _total_failures)
	_write_exit_summary_if_requested(summary)
	get_tree().quit(0 if result["pass"] else 1)


func _write_exit_summary_if_requested(summary: Dictionary) -> void:
	var out_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--summary-out="):
			out_path = arg.substr("--summary-out=".length())
			break
	if out_path.is_empty():
		return
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write calibration sweeper exit summary to %s" % out_path)
		return
	file.store_string(JSON.stringify(summary, "  ", false, true))
	file.close()
	print("CALIBRATION_SWEEPER_EXIT_SUMMARY_WRITTEN ", out_path)


func _case_full_arc_exit(c) -> void:
	var built := SourceScript.build()
	if not bool(built["ok"]):
		c.check(false, "exit.committed_source_build_succeeds: " + String(built["error"]))
		return
	var path: DriverScript.CalibrationPath = built["path"]
	c.check(path.is_valid(), "exit.path_valid: " + path.validation_error())
	var source_summary: Dictionary = built["summary"]
	c.equal(String(source_summary["bay_id"]), "sweeper", "exit.source_bay_id")
	c.equal(
		String(source_summary["fixture_id"]),
		SourceScript.EXPECTED_FIXTURE_ID,
		"exit.source_fixture_id"
	)
	c.close(
		float(source_summary["target_speed_m_s"]),
		SourceScript.PROVISIONAL_TARGET_SPEED_M_S,
		0.0,
		"exit.provisional_target_speed_unchanged"
	)
	c.check(
		String(source_summary["target_speed_provenance"]).contains("not_measured_or_tuned"),
		"exit.target_speed_provisional"
	)
	var tuning := DriverScript.Tuning.make()
	c.check(tuning != null and tuning.is_valid(), "exit.driver_tuning_valid")

	var arc_end_limit := ARC_ENTRY_STATION_M + float(SourceScript.EXPECTED_ARC_LENGTH_M)
	c.close(arc_end_limit, 238.495559215388, 1e-6, "exit.authored_arc_end_station")
	c.check(
		FULL_ARC_EXIT_STATION_M > arc_end_limit
		and FULL_ARC_EXIT_STATION_M < float(SourceScript.EXPECTED_TOTAL_LENGTH_M),
		"exit.threshold_lies_inside_authored_exit_segment"
	)

	var first: Dictionary = await _run_full_arc_exit_bridge(c, "first", path, tuning)
	var second: Dictionary = await _run_full_arc_exit_bridge(c, "second", path, tuning)

	var repeat := _compare_exit_runs(c, first, second)
	c.check(bool(first.get("completed", false)), "exit.first_run_completed")
	c.check(bool(second.get("completed", false)), "exit.second_run_completed")
	c.check(
		bool(first.get("reached_exit_threshold", false)),
		"exit.first_reached_245m_within_budget"
	)
	c.check(
		bool(second.get("reached_exit_threshold", false)),
		"exit.second_reached_245m_within_budget"
	)

	var first_final: Dictionary = first.get("final", {})
	var second_final: Dictionary = second.get("final", {})
	c.measurements["exit_tick_budget"] = FULL_ARC_EXIT_TICKS
	c.measurements["exit_station_threshold_m"] = FULL_ARC_EXIT_STATION_M
	c.measurements["arc_end_station_m"] = arc_end_limit
	c.measurements["first_final"] = first_final.duplicate(true)
	c.measurements["second_final"] = second_final.duplicate(true)
	c.measurements["repeat"] = repeat
	c.measurements["first_trace_ticks"] = first.get("trace", []).size()
	c.measurements["second_trace_ticks"] = second.get("trace", []).size()


func _run_full_arc_exit_bridge(c, label: String, path, tuning) -> Dictionary:
	var out := {
		"label": label,
		"completed": false,
		"reached_exit_threshold": false,
		"trace": [],
		"final": {},
	}
	var lab = _make_lab(c, label)
	if lab == null:
		return out
	await _settle()
	lab.set_auto_tick(false)
	c.check(not lab.is_auto_tick(), label + ".auto_tick_disabled")
	c.check(not lab.failed, label + ".laboratory_not_failed_after_settle")
	c.check(not lab.halted, label + ".laboratory_not_halted_after_settle")
	c.equal(int(lab.steps_called), 0, label + ".settle_made_no_adapter_calls")
	if lab.failed or lab.halted or lab.state == null or not lab.state.is_finite():
		c.check(false, label + ".initial_committed_state_finite")
		await _teardown_lab(lab)
		return out
	var input_refusal := _bridge_input_refusal(path, tuning)
	c.check(not bool(input_refusal["refused"]), label + ".bridge_input_accepted")
	if bool(input_refusal["refused"]):
		await _teardown_lab(lab)
		return out
	if not _place_at_sweeper_start(lab, c, label):
		await _teardown_lab(lab)
		return out

	var trace: Array = []
	var accepted_decisions := 0
	var refused_decisions := 0
	var physical_commits := 0
	var finite_states := 0
	var validated_stations := 0
	var exclusivity_violations := 0
	var normalization_violations := 0
	var step_count_mismatches := 0
	var max_abs_lateral_error := 0.0
	var max_nearest_distance := 0.0
	var min_speed := INF
	var max_speed := 0.0
	var min_station_delta := INF
	var final_station := 0.0
	var final_state = lab.state
	var first_arc_entry_tick := -1
	var first_arc_entry_station := 0.0
	var arc_end_tick := -1
	var arc_end_station := 0.0
	var threshold_tick := -1
	var threshold_station := 0.0
	var grounded_ticks := 0
	var contact_ticks := 0
	var wall_contact_ticks := 0
	var gear_indices: Array = []
	var stop_reason := "budget_exhausted"
	var reached := false
	var start_ms := Time.get_ticks_msec()
	var end_ms := start_ms
	var arc_end_limit := ARC_ENTRY_STATION_M + float(SourceScript.EXPECTED_ARC_LENGTH_M)

	for tick in range(FULL_ARC_EXIT_TICKS):
		end_ms = Time.get_ticks_msec()
		if lab.failed or lab.halted:
			c.check(false, label + ".laboratory_alive_at_tick_%d" % tick)
			stop_reason = "laboratory_stopped"
			break
		var committed_state = lab.state
		if committed_state == null or not committed_state.is_finite():
			c.check(false, label + ".finite_committed_input_state_tick_%d" % tick)
			stop_reason = "nonfinite_input_state"
			break

		var before_fix := _nearest_station(path, committed_state.position_m)
		var station := float(before_fix["station_m"])
		var lateral_before := float(before_fix["lateral_error_m"])
		var distance_before := float(before_fix["distance_m"])
		var station_valid := (
			is_finite(station)
			and is_finite(lateral_before)
			and is_finite(distance_before)
			and distance_before <= ROAD_HALF_WIDTH_M + PATH_PROBE_TOLERANCE_M
		)
		if not station_valid:
			c.check(false, label + ".validated_sweeper_station_tick_%d" % tick)
			stop_reason = "nearest_projection_left_road_envelope"
			break
		validated_stations += 1

		var decision: DriverScript.Decision = DriverScript.decide(
			committed_state, path, station, tuning
		)
		if not decision.accepted or decision.command == null:
			c.check(false, label + ".decision_accepted_tick_%d" % tick)
			refused_decisions += 1
			stop_reason = "driver_decision_refused"
			break
		accepted_decisions += 1
		var command = decision.command
		if not command.is_normalized():
			normalization_violations += 1
		if command.throttle > 0.0 and command.brake > 0.0:
			exclusivity_violations += 1

		var steps_before := int(lab.steps_called)
		var commits_before := int(lab.ticks_committed)
		var result: AdapterScript.Result = lab.step_once(command)
		if result == null:
			c.check(false, label + ".physical_result_present_tick_%d" % tick)
			stop_reason = "missing_physical_result"
			break
		if int(result.status) != int(AdapterScript.Status.COMMITTED):
			c.check(false, label + ".physical_commit_tick_%d" % tick)
			stop_reason = "physical_refusal"
			break
		physical_commits += 1
		if int(lab.steps_called) != steps_before + 1:
			step_count_mismatches += 1
		if int(lab.ticks_committed) != commits_before + 1:
			step_count_mismatches += 1

		var post_state = lab.state
		if post_state == null or not post_state.is_finite():
			c.check(false, label + ".finite_committed_output_state_tick_%d" % tick)
			stop_reason = "nonfinite_output_state"
			break
		finite_states += 1
		final_state = post_state
		var after_fix := _nearest_station(path, post_state.position_m)
		var post_station := float(after_fix["station_m"])
		var lateral_after := float(after_fix["lateral_error_m"])
		var distance_after := float(after_fix["distance_m"])
		final_station = post_station
		min_station_delta = minf(min_station_delta, post_station - station)
		max_abs_lateral_error = maxf(max_abs_lateral_error, absf(lateral_after))
		max_nearest_distance = maxf(max_nearest_distance, distance_after)
		min_speed = minf(min_speed, post_state.speed_m_s())
		max_speed = maxf(max_speed, post_state.speed_m_s())
		if first_arc_entry_tick < 0 and post_station >= ARC_ENTRY_STATION_M:
			first_arc_entry_tick = tick
			first_arc_entry_station = post_station
		if arc_end_tick < 0 and post_station >= arc_end_limit:
			arc_end_tick = tick
			arc_end_station = post_station
		if threshold_tick < 0 and post_station >= FULL_ARC_EXIT_STATION_M:
			threshold_tick = tick
			threshold_station = post_station
		if post_state.grounded:
			grounded_ticks += 1
		if result.contact:
			contact_ticks += 1
		if result.wall_contact:
			wall_contact_ticks += 1
		var gear := int(post_state.gear_index)
		if not gear_indices.has(gear):
			gear_indices.append(gear)

		var world: Vector3 = lab.body.global_transform.origin
		trace.append({
			"tick": tick,
			"station_before_m": station,
			"station_after_m": post_station,
			"station_delta_m": post_station - station,
			"lateral_error_before_m": lateral_before,
			"lateral_error_after_m": lateral_after,
			"nearest_distance_m": distance_after,
			"position_x_m": post_state.position_m.x,
			"position_y_m": post_state.position_m.y,
			"world_x_m": world.x,
			"world_z_m": world.z,
			"world_y_m": world.y,
			"speed_m_s": post_state.speed_m_s(),
			"forward_speed_m_s": post_state.forward_speed_m_s(),
			"heading_rad": post_state.heading_rad,
			"steer": command.steer,
			"throttle": command.throttle,
			"brake": command.brake,
			"lookahead_m": decision.telemetry.lookahead_m,
			"target_s_m": decision.telemetry.target_s_m,
			"target_speed_m_s": decision.telemetry.target_speed_m_s,
			"gear_index": int(post_state.gear_index),
			"result_status": int(result.status),
			"grounded": post_state.grounded,
			"reverse_engaged": post_state.reverse_engaged,
			"contact": result.contact,
			"wall_contact": result.wall_contact,
			"substeps": result.substeps,
			"remainder_m": result.remainder_m,
			"drive_lab_straight_projection_m": lab.get_road_station_m(),
		})
		await get_tree().physics_frame
		if post_station >= FULL_ARC_EXIT_STATION_M:
			reached = true
			stop_reason = "exit_threshold_reached"
			break

	gear_indices.sort()
	c.equal(
		accepted_decisions,
		trace.size(),
		label + ".every_recorded_tick_had_one_accepted_decision"
	)
	c.equal(
		physical_commits,
		trace.size(),
		label + ".every_recorded_tick_physically_committed"
	)
	c.equal(finite_states, trace.size(), label + ".all_committed_states_finite")
	c.equal(
		validated_stations,
		trace.size(),
		label + ".all_stations_externally_validated"
	)
	c.equal(refused_decisions, 0, label + ".no_refused_driver_decisions")
	c.equal(exclusivity_violations, 0, label + ".throttle_brake_mutually_exclusive")
	c.equal(normalization_violations, 0, label + ".commands_normalized")
	c.equal(
		step_count_mismatches,
		0,
		label + ".exactly_one_adapter_step_and_commit_per_tick"
	)
	c.equal(
		int(lab.steps_called),
		trace.size(),
		label + ".adapter_steps_equal_recorded_ticks"
	)
	c.equal(
		int(lab.ticks_committed),
		trace.size(),
		label + ".committed_ticks_equal_recorded_ticks"
	)
	c.check(trace.size() <= FULL_ARC_EXIT_TICKS, label + ".within_hard_tick_budget")
	c.check(
		max_abs_lateral_error <= LATERAL_ERROR_BOUND_M,
		label + ".lateral_error_within_road_half_width"
	)
	c.check(
		max_nearest_distance <= ROAD_HALF_WIDTH_M + PATH_PROBE_TOLERANCE_M,
		label + ".nearest_distance_within_road"
	)
	c.check(
		min_station_delta >= -STATION_MONOTONIC_TOLERANCE_M,
		label + ".external_station_monotonic"
	)
	c.equal(grounded_ticks, trace.size(), label + ".grounded_on_every_recorded_tick")
	c.equal(contact_ticks, 0, label + ".no_contacts")
	c.equal(wall_contact_ticks, 0, label + ".no_wall_contacts")
	c.check(arc_end_tick >= 0, label + ".authored_arc_end_observed")
	c.check(reached, label + ".reached_station_245m_within_budget")
	c.check(not lab.failed, label + ".laboratory_not_failed_after_run")
	c.check(not lab.halted, label + ".laboratory_not_halted_after_run")

	var completed: bool = (
		accepted_decisions == trace.size()
		and physical_commits == trace.size()
		and finite_states == trace.size()
		and validated_stations == trace.size()
		and refused_decisions == 0
		and exclusivity_violations == 0
		and normalization_violations == 0
		and step_count_mismatches == 0
		and max_abs_lateral_error <= LATERAL_ERROR_BOUND_M
		and max_nearest_distance <= ROAD_HALF_WIDTH_M + PATH_PROBE_TOLERANCE_M
		and min_station_delta >= -STATION_MONOTONIC_TOLERANCE_M
		and grounded_ticks == trace.size()
		and contact_ticks == 0
		and wall_contact_ticks == 0
		and arc_end_tick >= 0
		and reached
		and not lab.failed
		and not lab.halted
	)
	var final := {
		"label": label,
		"committed_ticks": trace.size(),
		"reached_exit_threshold": reached,
		"stop_reason": stop_reason,
		"station_m": final_station,
		"arc_entry_tick": first_arc_entry_tick,
		"arc_entry_station_m": first_arc_entry_station,
		"arc_end_tick": arc_end_tick,
		"arc_end_station_m": arc_end_station,
		"threshold_tick": threshold_tick,
		"threshold_station_m": threshold_station,
		"max_abs_lateral_error_m": max_abs_lateral_error,
		"max_nearest_distance_m": max_nearest_distance,
		"min_station_delta_m": 0.0 if min_station_delta == INF else min_station_delta,
		"min_speed_m_s": 0.0 if min_speed == INF else min_speed,
		"max_speed_m_s": max_speed,
		"final_speed_m_s": final_state.speed_m_s(),
		"final_forward_speed_m_s": final_state.forward_speed_m_s(),
		"final_position_x_m": final_state.position_m.x,
		"final_position_y_m": final_state.position_m.y,
		"final_world_x_m": lab.body.global_transform.origin.x,
		"final_world_z_m": lab.body.global_transform.origin.z,
		"final_heading_rad": final_state.heading_rad,
		"gear_indices_seen": gear_indices.duplicate(),
		"gear_shift_events": int(lab.gear_shift_events.size()),
		"grounded_ticks": grounded_ticks,
		"contact_ticks": contact_ticks,
		"wall_contact_ticks": wall_contact_ticks,
		"steps_called": int(lab.steps_called),
		"ticks_committed": int(lab.ticks_committed),
		"road_half_width_breach": (
			max_abs_lateral_error > LATERAL_ERROR_BOUND_M
			or max_nearest_distance > ROAD_HALF_WIDTH_M + PATH_PROBE_TOLERANCE_M
		),
		"logical_drive_time_s": float(trace.size()) / 60.0,
		"wall_drive_time_s": float(end_ms - start_ms) / 1000.0,
	}
	out["completed"] = completed
	out["reached_exit_threshold"] = reached
	out["trace"] = trace
	out["final"] = final
	print(
		"CALIBRATION_SWEEPER_EXIT_TRACE ",
		JSON.stringify({
			"schema": FULL_ARC_EXIT_TRACE_SCHEMA,
			"run": label,
			"profile_status": "provisional_not_tuned_not_benchmark_not_reference",
			"ticks": trace.size(),
			"reached_exit_threshold": reached,
			"stop_reason": stop_reason,
			"arc_entry_tick": first_arc_entry_tick,
			"arc_end_tick": arc_end_tick,
			"threshold_tick": threshold_tick,
			"selected_samples": _select_exit_samples(trace),
		})
	)
	c.measurements[label + "_final"] = final.duplicate(true)
	c.measurements[label + "_trace_ticks"] = trace.size()
	c.measurements[label + "_selected_samples"] = _select_exit_samples(trace)
	c.measurements[label + "_steps_called"] = int(lab.steps_called)
	c.measurements[label + "_ticks_committed"] = int(lab.ticks_committed)
	await _teardown_lab(lab)
	return out


func _compare_exit_runs(c, first: Dictionary, second: Dictionary) -> Dictionary:
	var a: Array = first.get("trace", [])
	var b: Array = second.get("trace", [])
	c.equal(a.size(), b.size(), "exit.repeat_trace_lengths_match")
	var common := mini(a.size(), b.size())
	var max_diffs := {}
	for field in TRACE_NUMERIC_REPEAT_FIELDS:
		max_diffs[field] = 0.0
	var gear_mismatches := 0
	var status_mismatches := 0
	var contact_mismatches := 0
	var grounded_mismatches := 0
	var reverse_mismatches := 0
	var wall_mismatches := 0
	var substep_mismatches := 0
	var tick_mismatches := 0
	for index in range(common):
		var ra: Dictionary = a[index]
		var rb: Dictionary = b[index]
		for field in TRACE_NUMERIC_REPEAT_FIELDS:
			var diff := absf(float(ra[field]) - float(rb[field]))
			max_diffs[field] = maxf(float(max_diffs[field]), diff)
		if int(ra["tick"]) != int(rb["tick"]):
			tick_mismatches += 1
		if int(ra["gear_index"]) != int(rb["gear_index"]):
			gear_mismatches += 1
		if int(ra["result_status"]) != int(rb["result_status"]):
			status_mismatches += 1
		if bool(ra["contact"]) != bool(rb["contact"]):
			contact_mismatches += 1
		if bool(ra["grounded"]) != bool(rb["grounded"]):
			grounded_mismatches += 1
		if bool(ra["reverse_engaged"]) != bool(rb["reverse_engaged"]):
			reverse_mismatches += 1
		if bool(ra["wall_contact"]) != bool(rb["wall_contact"]):
			wall_mismatches += 1
		if int(ra["substeps"]) != int(rb["substeps"]):
			substep_mismatches += 1
	var worst := 0.0
	var worst_field := ""
	for field in TRACE_NUMERIC_REPEAT_FIELDS:
		var value := float(max_diffs[field])
		if value > worst:
			worst = value
			worst_field = String(field)
	var first_final: Dictionary = first.get("final", {})
	var second_final: Dictionary = second.get("final", {})
	for metric in [
		"station_m", "arc_entry_station_m", "arc_end_station_m",
		"threshold_station_m", "max_abs_lateral_error_m", "max_nearest_distance_m",
		"min_station_delta_m", "min_speed_m_s", "max_speed_m_s",
	]:
		var value_a := float(first_final.get(metric, NAN))
		var value_b := float(second_final.get(metric, NAN))
		c.check(
			is_finite(value_a) and is_finite(value_b) and absf(value_a - value_b) <= REPEAT_TOLERANCE,
			"exit.repeat_metric_%s_within_tolerance" % metric
		)
	c.equal(
		int(first_final.get("committed_ticks", -1)),
		int(second_final.get("committed_ticks", -2)),
		"exit.repeat_committed_tick_count_identical"
	)
	c.equal(
		int(first_final.get("arc_end_tick", -1)),
		int(second_final.get("arc_end_tick", -2)),
		"exit.repeat_arc_end_tick_identical"
	)
	c.equal(
		int(first_final.get("threshold_tick", -1)),
		int(second_final.get("threshold_tick", -2)),
		"exit.repeat_threshold_tick_identical"
	)
	c.equal(
		int(first_final.get("grounded_ticks", -1)),
		int(second_final.get("grounded_ticks", -2)),
		"exit.repeat_grounded_tick_count_identical"
	)
	c.check(
		worst <= REPEAT_TOLERANCE,
		"exit.same_host_repeat_within_tolerance (worst %s=%s tol=%s)"
			% [worst_field, str(worst), str(REPEAT_TOLERANCE)]
	)
	c.equal(gear_mismatches, 0, "exit.repeat_gear_indications_identical")
	c.equal(status_mismatches, 0, "exit.repeat_physical_statuses_identical")
	c.equal(contact_mismatches, 0, "exit.repeat_contact_flags_identical")
	c.equal(grounded_mismatches, 0, "exit.repeat_grounded_flags_identical")
	c.equal(reverse_mismatches, 0, "exit.repeat_reverse_flags_identical")
	c.equal(wall_mismatches, 0, "exit.repeat_wall_contact_flags_identical")
	c.equal(substep_mismatches, 0, "exit.repeat_substep_counts_identical")
	c.equal(tick_mismatches, 0, "exit.repeat_ticks_identical")
	return {
		"compared_fields": TRACE_NUMERIC_REPEAT_FIELDS.duplicate(),
		"exact_fields": TRACE_EXACT_REPEAT_FIELDS.duplicate(),
		"max_diffs": max_diffs.duplicate(),
		"worst_field": worst_field,
		"worst_diff": worst,
		"repeat_tolerance": REPEAT_TOLERANCE,
		"common_ticks_compared": common,
		"gear_mismatches": gear_mismatches,
		"status_mismatches": status_mismatches,
		"contact_mismatches": contact_mismatches,
		"grounded_mismatches": grounded_mismatches,
		"reverse_mismatches": reverse_mismatches,
		"wall_contact_mismatches": wall_mismatches,
		"substep_mismatches": substep_mismatches,
		"tick_mismatches": tick_mismatches,
	}


func _select_exit_samples(trace: Array) -> Array:
	var wanted := [0, 150, 300, 450, 600, 750, 900, 1050, 1200, 1350, 1500, 1650, 1799]
	var out: Array = []
	var seen := {}
	for index in wanted:
		if index >= 0 and index < trace.size() and not seen.has(index):
			seen[index] = true
			out.append(trace[index])
	if trace.size() > 0:
		var last_index := trace.size() - 1
		if not seen.has(last_index):
			out.append(trace[last_index])
	return out


# --- Case 3: refusal without a motor step ----------------------------------


func _case_invalid_source_refusal(c) -> void:
	var lab = _make_lab(c, "refusal")
	if lab == null:
		return
	await _settle()
	lab.set_auto_tick(false)

	var steps_before := int(lab.steps_called)
	var commits_before := int(lab.ticks_committed)
	var position_before: Vector2 = lab.state.position_m
	var velocity_before: Vector2 = lab.state.velocity_m_s
	var heading_before: float = lab.state.heading_rad

	# Missing authored source: refused by the committed conversion.
	var missing := SourceScript.build({}, {}, true, false)
	c.check(not bool(missing["ok"]), "refusal.missing_source_refused")
	c.check(not String(missing["error"]).is_empty(), "refusal.missing_source_diagnostic")
	c.check(missing["path"] == null, "refusal.missing_source_returns_no_path")

	# Mismatched authored geometry: a changed arc radius must not fall back.
	var changed_bay := _live_sweeper_bay_copy()
	c.check(not changed_bay.is_empty(), "refusal.live_bay_copy_available")
	if not changed_bay.is_empty():
		var segments: Array = changed_bay["segments"]
		segments[1]["radius_m"] = 90.0
		var mismatched := SourceScript.build(changed_bay, {})
		c.check(not bool(mismatched["ok"]), "refusal.mismatched_geometry_refused")
		c.check(mismatched["path"] == null, "refusal.mismatched_geometry_returns_no_path")

	# Invalid produced path reaches the driver, which must refuse without a
	# command. The bridge contract then never submits anything to step_once.
	var invalid_path := DriverScript.CalibrationPath.from_arrays(
		[0.0, 10.0, 10.0],
		[Vector2.ZERO, Vector2(0.0, 10.0), Vector2(0.0, 10.0)],
		[
			SourceScript.PROVISIONAL_TARGET_SPEED_M_S,
			SourceScript.PROVISIONAL_TARGET_SPEED_M_S,
			SourceScript.PROVISIONAL_TARGET_SPEED_M_S,
		],
		SourceScript.PATH_VERSION + ".invalid_duplicate_station"
	)
	c.check(invalid_path != null, "refusal.invalid_path_object_built")
	c.check(not invalid_path.is_valid(), "refusal.duplicate_station_path_rejected_by_validation")
	var tuning := DriverScript.Tuning.make()
	c.check(tuning != null and tuning.is_valid(), "refusal.tuning_valid")
	var decision := DriverScript.decide(lab.state, invalid_path, 0.0, tuning)
	c.check(not decision.accepted, "refusal.decision_refused")
	c.check(decision.command == null, "refusal.refusal_has_no_command")
	c.equal(
		int(decision.refusal_code),
		int(DriverScript.Refusal.INVALID_PATH),
		"refusal.refusal_code"
	)
	c.equal(decision.refusal_label, "invalid_path", "refusal.refusal_label")
	c.check(not decision.refusal_detail.is_empty(), "refusal.refusal_detail_present")

	# Bridge-path control: pass the invalid produced path through the same
	# physical bridge entry point used by the genuine runs. It must be refused
	# before placement or the first adapter step. Missing/changed authored-source
	# cases above remain component-refusal tests of the conversion API.
	var bridge_control: Dictionary = await _run_physical_bridge(
		c, "refusal_bridge_control", invalid_path, tuning, true
	)
	var control_refusal: Dictionary = bridge_control.get("input_refusal", {}) as Dictionary
	var control_trace: Array = bridge_control.get("trace", []) as Array
	c.check(
		bool(control_refusal.get("refused", false)),
		"refusal.bridge_entry_refused_invalid_path"
	)
	c.equal(
		String(control_refusal.get("code", "")),
		"invalid_path",
		"refusal.bridge_entry_refusal_code"
	)
	c.equal(control_trace.size(), 0, "refusal.bridge_entry_recorded_no_ticks")
	c.equal(
		int(bridge_control.get("steps_called", -1)),
		0,
		"refusal.bridge_entry_no_adapter_step"
	)
	c.equal(
		int(bridge_control.get("ticks_committed", -1)),
		0,
		"refusal.bridge_entry_no_commit"
	)
	c.check(
		not bool(bridge_control.get("completed", true)),
		"refusal.bridge_entry_did_not_complete"
	)
	c.measurements["bridge_control_refusal"] = control_refusal.duplicate()

	# No motor step may accompany a refused or unusable source.
	c.equal(int(lab.steps_called), steps_before, "refusal.no_additional_adapter_step")
	c.equal(int(lab.ticks_committed), commits_before, "refusal.no_additional_commit")
	c.check(lab.state.position_m == position_before, "refusal.position_unchanged")
	c.check(lab.state.velocity_m_s == velocity_before, "refusal.velocity_unchanged")
	c.check(lab.state.heading_rad == heading_before, "refusal.heading_unchanged")
	c.measurements["steps_before"] = steps_before
	c.measurements["steps_after"] = int(lab.steps_called)
	c.measurements["missing_source_error"] = String(missing["error"])
	c.measurements["refusal_detail"] = decision.refusal_detail
	await _teardown_lab(lab)


# --- Placement seam --------------------------------------------------------


func _place_at_sweeper_start(lab, c, label: String) -> bool:
	var handling := lab.get_node_or_null("HandlingLab") as Node3D
	c.check(handling != null, label + ".handling_lab_child_present")
	if handling == null:
		return false
	var bay_node := handling.get_node_or_null("Bay_sweeper") as Node3D
	c.check(bay_node != null, label + ".sweeper_bay_present")
	if bay_node == null:
		return false
	var marker := bay_node.get_node_or_null("Spawn_sweeper") as Marker3D
	c.check(marker != null, label + ".authored_sweeper_spawn_marker_present")
	if marker == null:
		return false

	var spawn_world: Vector3 = marker.global_position
	c.close(
		spawn_world.distance_to(SourceScript.EXPECTED_ORIGIN),
		0.0,
		1e-6,
		label + ".spawn_matches_authored_sweeper_origin"
	)
	var builder_yaw := deg_to_rad(float(marker.get_meta("heading_deg")))
	var heading := DriveLabScript.builder_heading_to_state(builder_yaw)
	c.close(heading, 0.0, 1e-9, label + ".state_heading_matches_authored_yaw")

	# Install the authored start pose on the ordinary public state/body fields.
	# The gearbox stays at its deterministic reset pair from DriveLab._ready();
	# no tick has run and no body-pose block is set.
	# Mirrors DriveLab.HULL_REST_CLEARANCE_M (0.02 m) so the installed hull
	# bottom rests 2 cm above the authored flat road top.
	var support_y: float = lab.hull_shape.size.y * 0.5 + 0.02
	var installed_origin := Vector3(spawn_world.x, support_y, spawn_world.z)
	lab.state.position_m = AdapterScript.world_vector_to_road(spawn_world)
	lab.state.velocity_m_s = Vector2.ZERO
	lab.state.heading_rad = heading
	lab.start_position_m = lab.state.position_m
	lab.body.global_transform = Transform3D(
		AdapterScript.basis_from_heading(heading),
		installed_origin
	)

	# The installed pose must map back to the published state exactly.
	var mapped: Vector2 = AdapterScript.world_vector_to_road(lab.body.global_transform.origin)
	c.close(
		mapped.distance_to(lab.state.position_m),
		0.0,
		1e-9,
		label + ".installed_pose_maps_to_published_state"
	)
	c.check(
		lab.body.global_transform.basis.is_equal_approx(
			AdapterScript.basis_from_heading(lab.state.heading_rad)
		),
		label + ".installed_basis_matches_state_heading"
	)
	c.close(lab.body.global_transform.origin.y, installed_origin.y, 1e-9, label + ".support_height")
	c.check(lab.gearbox != null, label + ".gearbox_present_at_sweeper_start")
	if lab.gearbox != null:
		c.equal(int(lab.gearbox.get_state().gear_index), 1, label + ".gearbox_reset_pair_gear_one")
	c.equal(int(lab.steps_called), 0, label + ".no_motor_step_before_placement")
	c.close(lab.get_road_station_m(), 0.0, 1e-7, label + ".straight_accessor_zero_at_sweeper_start")
	c.measurements[label + "_start_position_road_m"] = [lab.state.position_m.x, lab.state.position_m.y]
	c.measurements[label + "_start_position_world_m"] = [spawn_world.x, spawn_world.y, spawn_world.z]
	c.measurements[label + "_support_height_m"] = support_y
	return true


# --- External station validation --------------------------------------------


## Nearest projection of a road-plane position onto the committed path.
## Returns station, unsigned nearest distance and signed lateral error
## (positive is right of the local path tangent). This is deliberately
## external to DriveLab, whose station accessor projects onto one fixed
## straight axis.
func _nearest_station(path: DriverScript.CalibrationPath, position_m: Vector2) -> Dictionary:
	var samples: Array[DriverScript.PathSample] = path.samples
	var best_distance := INF
	var best_station := 0.0
	var best_lateral := 0.0
	for index in range(samples.size() - 1):
		var low: DriverScript.PathSample = samples[index]
		var high: DriverScript.PathSample = samples[index + 1]
		var segment: Vector2 = high.position_m - low.position_m
		var length_sq := segment.length_squared()
		var blend := 0.0
		if length_sq > 1e-12:
			blend = clampf((position_m - low.position_m).dot(segment) / length_sq, 0.0, 1.0)
		var projected := low.position_m + segment * blend
		var offset := position_m - projected
		var distance := offset.length()
		if distance < best_distance:
			best_distance = distance
			best_station = lerpf(low.s_m, high.s_m, blend)
			var tangent := segment.normalized() if length_sq > 1e-12 else Vector2(0.0, 1.0)
			var right := Vector2(tangent.y, -tangent.x)
			best_lateral = offset.dot(right)
	# Exact endpoint fallback for positions beyond the declared profile.
	if samples.size() >= 2:
		var last = samples[samples.size() - 1]
		var tail := position_m.distance_to(last.position_m)
		if tail < best_distance:
			best_distance = tail
			best_station = last.s_m
			var previous = samples[samples.size() - 2]
			var tangent: Vector2 = last.position_m - previous.position_m
			tangent = tangent.normalized() if tangent.length_squared() > 1e-12 else Vector2(0.0, 1.0)
			var right := Vector2(tangent.y, -tangent.x)
			best_lateral = (position_m - last.position_m).dot(right)
	return {
		"station_m": best_station,
		"distance_m": best_distance,
		"lateral_error_m": best_lateral,
	}


static func _live_sweeper_bay_copy() -> Dictionary:
	for bay in SourceScript.DataScript.bays():
		if String(bay["bay_id"]) == SourceScript.SWEEPER_BAY_ID:
			return bay.duplicate(true)
	return {}


# --- Construction helpers --------------------------------------------------


func _make_lab(c, label: String):
	var packed: PackedScene = load(DRIVE_LAB_SCENE_PATH)
	if packed == null:
		c.check(false, label + ".drive_lab_scene_load")
		return null
	var lab = packed.instantiate()
	if lab == null:
		c.check(false, label + ".drive_lab_scene_instantiate")
		return null
	# The laboratory's own ordinary tuning/config factories: the same
	# ArcadeMotor, AutomaticGearbox and MotorBodyAdapter integration path used
	# by the committed drive-lab validator.
	var configured: bool = lab.configure(
		lab.make_laboratory_tuning(), lab.make_laboratory_config(), []
	)
	c.check(configured, label + ".ordinary_drive_lab_configuration_accepted")
	if not configured:
		lab.free()
		return null
	_holder.add_child(lab)
	return lab


func _selected_samples(trace: Array) -> Array:
	var wanted := [0, 60, 120, 180, 240, 300, 340, 380, BRIDGE_TICKS - 1]
	var out: Array = []
	for index in wanted:
		if index >= 0 and index < trace.size():
			out.append(trace[index])
	return out


func _settle() -> void:
	for _index in range(SETTLE_FRAMES):
		await get_tree().physics_frame


func _teardown_lab(lab) -> void:
	if lab != null and is_instance_valid(lab):
		lab.queue_free()
	for _index in range(CLEANUP_FRAMES):
		await get_tree().physics_frame


func _teardown_node(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
	for _index in range(CLEANUP_FRAMES):
		await get_tree().physics_frame
