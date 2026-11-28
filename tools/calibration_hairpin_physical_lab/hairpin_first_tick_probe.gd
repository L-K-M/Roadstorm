extends Node
## M1.7 hairpin first-tick physical laboratory case: ONE real committed 60 Hz
## physical tick at the authored hairpin start with initial forward speed
## 18 m/s.
##
## Ownership: tools/calibration_hairpin_physical_lab/** (tracked lab). The case
## instantiates the committed scenes/laboratory/drive_lab.tscn unchanged and the
## committed MotorBodyAdapter/Jolt commit path, and it uses the committed
## hairpin bay colliders that HandlingLabBuilder already builds. No synthetic
## geometry is created and no source file is modified.
##
## Provenance of this file. The original draft was written by the StepFun 5
## Preview read-only feasibility worker at
## work/agents/coordinator/m17-hairpin-first-tick-stepfun-20261128/probe/
## m17_hairpin_first_tick.gd. That worker timed out before running an engine.
## The coordinator copied it into its private validation build and applied five
## small corrections: typed Tuning and Decision, corrected the concave-polygon
## triangle-face divisor (/3, not /9), typed the ray hit collider as Object,
## cast the ray position to Vector3, and delayed the initial scene-tree run by
## one process frame so DriveLab is not added during the parent's setup. This
## tracked copy keeps that corrected body verbatim apart from this header and
## the runner-facing scene path; the case was re-run on candidate SHA
## 9f9ef376f8e17ec5025ad6c899c4c93f4b348504 under pinned Godot/Jolt.
##
## Placement seam (the missing seam this probe documents): DriveLab starts every
## car at the authored straight-bay marker and exposes no public spawn API for
## another bay. tools/calibration_sweeper_lab already bridges this exact seam for
## the sweeper bay by writing the already-built public CarState /
## start_position_m / body.global_transform fields once before the first tick,
## leaving the gearbox at its deterministic reset pair. This probe reuses that
## same technique for the hairpin bay, then adds the authored 18 m/s entry speed
## on the public CarState velocity field.
##
## Route progress: the committed hairpin source refuses nearest-point progress
## because the exit leg runs back parallel to the approach. This probe therefore
## supplies the caller-ordered station 0.0 (the authored hairpin start) to the
## committed CalibrationDriver.

const SourceScript := preload(
	"res://tools/calibration_hairpin_path_lab/calibration_hairpin_path_source.gd"
)
const DriverScript := preload("res://src/calibration/calibration_driver.gd")
const AdapterScript := preload("res://src/simulation/motor_body_adapter.gd")
const DriveLabScript := preload("res://src/laboratory/drive_lab.gd")

const DRIVE_LAB_SCENE_PATH := "res://scenes/laboratory/drive_lab.tscn"
const HAIRPIN_BAY_ID := "hairpin"
const ENTRY_SPEED_M_S := 18.0
## Mirrors DriveLab.HULL_REST_CLEARANCE_M (0.02 m): the installed hull bottom
## rests 2 cm above the authored flat road top.
const HULL_REST_CLEARANCE_M := 0.02
const SETTLE_FRAMES := 10
const CLEANUP_FRAMES := 8
const PROBE_TOLERANCE := 1e-6

var _holder: Node3D = null
var _checks := 0
var _failures: Array[String] = []
var _measurements: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_holder = Node3D.new()
	_holder.name = "HairpinFirstTickHolder"
	add_child(_holder)
	await get_tree().process_frame
	await _run()
	_emit()
	get_tree().quit(0 if _failures.is_empty() else 1)


# --- Assertion helpers -----------------------------------------------------


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _close(actual: float, expected: float, tolerance: float, message: String) -> void:
	_checks += 1
	if is_nan(actual) or is_inf(actual) or absf(actual - expected) > tolerance:
		_failures.append(
			"%s (got %s expected %s tol %s)" % [message, str(actual), str(expected), str(tolerance)]
		)


# --- Probe -----------------------------------------------------------------


func _run() -> void:
	# 1. The committed hairpin path, converted from the live authored bay.
	var built: Dictionary = SourceScript.build()
	_check(bool(built.get("ok", false)), "hairpin.source_path_built")
	if not bool(built.get("ok", false)):
		_measurements["hairpin_source_error"] = String(built.get("error", ""))
		return
	var path = built["path"]
	var summary: Dictionary = built["summary"]
	_check(String(summary.get("bay_id", "")) == HAIRPIN_BAY_ID, "hairpin.source_bay_id")
	_measurements["path_version"] = String(path.version)
	_measurements["path_sample_count"] = int(path.samples.size())
	_measurements["path_station_first_m"] = float(path.first_s_m())
	_measurements["path_station_last_m"] = float(path.last_s_m())
	_measurements["path_target_speed_m_s"] = float(summary.get("target_speed_m_s", 0.0))
	_measurements["progress_policy_refusal"] = String(
		SourceScript.resolve_progress_by_nearest_point(Vector2.ZERO)["error"]
	)

	# 2. The ordinary committed DriveLab scene, unchanged.
	var packed: PackedScene = load(DRIVE_LAB_SCENE_PATH)
	_check(packed != null, "hairpin.drive_lab_scene_loaded")
	if packed == null:
		return
	var lab = packed.instantiate()
	_check(lab != null, "hairpin.drive_lab_scene_instantiated")
	if lab == null:
		return
	var configured: bool = lab.configure(
		lab.make_laboratory_tuning(), lab.make_laboratory_config(), []
	)
	_check(configured, "hairpin.ordinary_drive_lab_configuration_accepted")
	if not configured:
		lab.free()
		return
	_holder.add_child(lab)
	await _settle()

	_check(not lab.failed, "hairpin.laboratory_not_failed_after_settle")
	_check(not lab.halted, "hairpin.laboratory_not_halted_after_settle")
	_check(int(lab.steps_called) == 0, "hairpin.settle_made_no_adapter_calls")
	if lab.failed or lab.halted:
		await _teardown(lab)
		return
	lab.set_auto_tick(false)
	_check(not lab.is_auto_tick(), "hairpin.auto_tick_disabled")

	# 3. The committed hairpin colliders really exist under Bay_hairpin.
	var handling := lab.get_node_or_null("HandlingLab") as Node3D
	_check(handling != null, "hairpin.handling_lab_child_present")
	if handling == null:
		await _teardown(lab)
		return
	var bay_node := handling.get_node_or_null("Bay_" + HAIRPIN_BAY_ID) as Node3D
	_check(bay_node != null, "hairpin.authored_bay_node_present")
	if bay_node == null:
		await _teardown(lab)
		return
	var colliders: Array = []
	var meshes: Array = []
	for child in bay_node.get_children():
		if child is StaticBody3D and String(child.get_meta("bay_id", "")) == HAIRPIN_BAY_ID:
			colliders.append(child)
		if child is MeshInstance3D and String(child.get_meta("bay_id", "")) == HAIRPIN_BAY_ID:
			meshes.append(child)
	_check(colliders.size() == 3, "hairpin.three_committed_hairpin_collision_runs")
	_check(meshes.size() == 3, "hairpin.three_committed_hairpin_surface_runs")
	var total_faces := 0
	for collider in colliders:
		var shape_node := (collider as StaticBody3D).get_child(0) as CollisionShape3D
		_check(shape_node != null, "hairpin.collider_has_shape")
		if shape_node != null:
			_check(
				shape_node.shape is ConcavePolygonShape3D,
				"hairpin.collider_is_concave_polygon"
			)
			if shape_node.shape is ConcavePolygonShape3D:
				total_faces += int((shape_node.shape as ConcavePolygonShape3D).get_faces().size() / 3)
	_measurements["hairpin_collider_count"] = colliders.size()
	_measurements["hairpin_collider_triangle_faces"] = total_faces
	_check(total_faces > 0, "hairpin.colliders_have_real_triangles")

	# 4. Authored hairpin start pose, installed once through the same public
	#    fields the committed sweeper bridge uses.
	var marker := bay_node.get_node_or_null("Spawn_" + HAIRPIN_BAY_ID) as Marker3D
	_check(marker != null, "hairpin.authored_spawn_marker_present")
	if marker == null:
		await _teardown(lab)
		return
	var spawn_world: Vector3 = marker.global_position
	_close(
		spawn_world.distance_to(SourceScript.EXPECTED_ORIGIN), 0.0, PROBE_TOLERANCE,
		"hairpin.spawn_matches_authored_origin"
	)
	var builder_yaw := deg_to_rad(float(marker.get_meta("heading_deg")))
	var heading := DriveLabScript.builder_heading_to_state(builder_yaw)
	_close(heading, 0.0, PROBE_TOLERANCE, "hairpin.state_heading_matches_authored_yaw")
	var support_y: float = lab.hull_shape.size.y * 0.5 + HULL_REST_CLEARANCE_M
	var installed_origin := Vector3(spawn_world.x, support_y, spawn_world.z)
	lab.state.position_m = AdapterScript.world_vector_to_road(spawn_world)
	lab.state.heading_rad = heading
	lab.start_position_m = lab.state.position_m
	lab.body.global_transform = Transform3D(
		AdapterScript.basis_from_heading(heading), installed_origin
	)
	_check(bool(lab.state.grounded), "hairpin.start_state_grounded")

	# 5. The physical ground under the installed hull is the committed hairpin
	#    collider, not a synthetic floor.
	var ground := _ray_ground(lab.body, installed_origin + Vector3.UP * 2.0)
	_check(ground.has("collider"), "hairpin.start_ground_ray_hit")
	_check(
		String(ground.get("bay_id", "")) == HAIRPIN_BAY_ID,
		"hairpin.start_ground_is_committed_hairpin_collider"
	)
	_check(
		String(ground.get("collision_role", "")) == "terrain",
		"hairpin.start_ground_collision_role_terrain"
	)
	_close(
		float(ground.get("point_y", -INF)), 0.0, 1e-3,
		"hairpin.start_ground_is_authored_road_plane"
	)
	_measurements["start_ground_bay_id"] = String(ground.get("bay_id", ""))
	_measurements["start_ground_section_id"] = String(ground.get("section_id", ""))

	# 6. The authored 18 m/s initial forward speed along the authored heading,
	#    written on the already-built public CarState.
	lab.state.velocity_m_s = lab.state.forward_vector() * ENTRY_SPEED_M_S
	_check(lab.state.is_finite(), "hairpin.start_state_finite")
	_close(lab.state.speed_m_s(), ENTRY_SPEED_M_S, PROBE_TOLERANCE, "hairpin.start_speed")
	_close(
		lab.state.forward_speed_m_s(), ENTRY_SPEED_M_S, PROBE_TOLERANCE,
		"hairpin.start_forward_speed"
	)
	var forward_world := AdapterScript.road_vector_to_world(lab.state.forward_vector())
	_close(forward_world.z, -1.0, PROBE_TOLERANCE, "hairpin.start_forward_is_world_minus_z")
	_measurements["initial_speed_m_s"] = float(lab.state.speed_m_s())
	_measurements["initial_forward_speed_m_s"] = float(lab.state.forward_speed_m_s())
	_measurements["initial_position_road_m"] = [lab.state.position_m.x, lab.state.position_m.y]
	_measurements["initial_position_world_m"] = [spawn_world.x, spawn_world.y, spawn_world.z]
	_measurements["initial_heading_rad"] = float(lab.state.heading_rad)
	_measurements["initial_velocity_road_m_s"] = [lab.state.velocity_m_s.x, lab.state.velocity_m_s.y]
	_measurements["initial_support_height_m"] = support_y
	_close(lab.get_road_station_m(), 0.0, PROBE_TOLERANCE, "hairpin.station_zero_at_start")

	# 7. One committed CalibrationDriver command from the committed hairpin path
	#    at the caller-ordered authored start station. Never a nearest-point query.
	var tuning: DriverScript.Tuning = DriverScript.Tuning.make()
	_check(bool(tuning.is_valid()), "hairpin.driver_tuning_valid")
	var decision: DriverScript.Decision = DriverScript.decide(lab.state, path, 0.0, tuning)
	_check(bool(decision.accepted), "hairpin.driver_decision_accepted")
	if not bool(decision.accepted):
		_measurements["driver_refusal"] = String(decision.telemetry.refusal_label)
		await _teardown(lab)
		return
	var command = decision.command
	_measurements["tick_command"] = {
		"steer": float(command.steer),
		"throttle": float(command.throttle),
		"brake": float(command.brake),
	}
	_measurements["driver_target_speed_m_s"] = float(decision.telemetry.target_speed_m_s)

	# 8. Exactly one real committed 60 Hz physical tick.
	var steps_before := int(lab.steps_called)
	var commits_before := int(lab.ticks_committed)
	var result = lab.step_once(command)
	_check(result != null, "hairpin.physical_result_present")
	if result == null:
		_measurements["failure_reason"] = String(lab.failure_reason)
		_measurements["halt_reason"] = String(lab.halt_reason)
		await _teardown(lab)
		return
	_check(
		int(result.status) == int(AdapterScript.Status.COMMITTED),
		"hairpin.physical_commit_status"
	)
	_check(int(lab.steps_called) == steps_before + 1, "hairpin.exactly_one_adapter_step")
	_check(int(lab.ticks_committed) == commits_before + 1, "hairpin.exactly_one_committed_tick")
	_measurements["committed_tick_count"] = int(lab.ticks_committed)
	_measurements["adapter_step_count"] = int(lab.steps_called)
	_measurements["result_status"] = int(result.status)
	_measurements["result_substeps"] = int(result.substeps)
	_measurements["result_contact"] = bool(result.contact)
	_measurements["result_wall_contact"] = bool(result.wall_contact)

	# 9. Final committed state, pose reconciliation and post-tick ground.
	var final_state = lab.state
	_check(final_state != null and final_state.is_finite(), "hairpin.final_state_finite")
	if final_state != null:
		_measurements["final_speed_m_s"] = float(final_state.speed_m_s())
		_measurements["final_forward_speed_m_s"] = float(final_state.forward_speed_m_s())
		_measurements["final_position_road_m"] = [final_state.position_m.x, final_state.position_m.y]
		_measurements["final_velocity_road_m_s"] = [
			final_state.velocity_m_s.x, final_state.velocity_m_s.y
		]
		_measurements["final_heading_rad"] = float(final_state.heading_rad)
		_measurements["final_gear_index"] = int(final_state.gear_index)
		_measurements["final_station_m"] = float(lab.get_road_station_m())
	var body_transform: Transform3D = lab.body.global_transform
	_measurements["final_body_world_m"] = [
		body_transform.origin.x, body_transform.origin.y, body_transform.origin.z
	]
	var mapped: Vector2 = AdapterScript.world_vector_to_road(body_transform.origin)
	_close(
		mapped.distance_to(final_state.position_m), 0.0, 1e-9,
		"hairpin.final_pose_maps_to_published_state"
	)
	_check(
		body_transform.basis.is_equal_approx(
			AdapterScript.basis_from_heading(final_state.heading_rad)
		),
		"hairpin.final_basis_matches_published_heading"
	)
	var telemetry: Dictionary = lab.get_telemetry()
	_check(bool(telemetry["body_pose_reconciled"]), "hairpin.body_pose_reconciled")
	_check(not bool(telemetry["failed"]), "hairpin.telemetry_not_failed")
	_check(not bool(telemetry["halted"]), "hairpin.telemetry_not_halted")
	_check(int(telemetry["contact_ticks"]) >= 0, "hairpin.contact_ticks_reported")
	var post_ground := _ray_ground(lab.body, body_transform.origin + Vector3.UP * 2.0)
	_check(
		String(post_ground.get("bay_id", "")) == HAIRPIN_BAY_ID,
		"hairpin.post_tick_ground_is_committed_hairpin_collider"
	)
	_measurements["post_tick_ground_bay_id"] = String(post_ground.get("bay_id", ""))
	_measurements["post_tick_ground_section_id"] = String(post_ground.get("section_id", ""))
	_measurements["max_speed_m_s"] = float(telemetry["max_speed_m_s"])
	_measurements["total_accepted_motion_m"] = float(telemetry["total_accepted_motion_m"])
	_measurements["max_commit_gap_m"] = float(telemetry["max_commit_gap_m"])

	await _teardown(lab)


# --- Helpers ---------------------------------------------------------------


## Downward world ray from just above the installed hull, excluding the car RID,
## so the reported ground is the committed hairpin terrain collider.
func _ray_ground(body: CharacterBody3D, from: Vector3) -> Dictionary:
	var world := body.get_world_3d()
	if world == null:
		return {}
	var query := PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = from + Vector3.DOWN * 8.0
	query.exclude = [body.get_rid()]
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider: Object = hit.get("collider", null)
	if collider == null:
		return hit
	return {
		"collider": collider,
		"position": hit.get("position", Vector3.ZERO),
		"point_y": float((hit.get("position", Vector3.ZERO) as Vector3).y),
		"bay_id": String(collider.get_meta("bay_id", "")),
		"section_id": String(collider.get_meta("section_id", "")),
		"collision_role": String(collider.get_meta("collision_role", "")),
		"shape_kind": String(collider.get_meta("shape_kind", "")),
	}


func _settle() -> void:
	for _index in range(SETTLE_FRAMES):
		await get_tree().physics_frame


func _teardown(lab) -> void:
	if lab != null and is_instance_valid(lab):
		lab.queue_free()
	for _index in range(CLEANUP_FRAMES):
		await get_tree().physics_frame


func _emit() -> void:
	var report := {
		"schema": "roadstorm.m17_hairpin_first_tick.v1",
		"pass": _failures.is_empty(),
		"checks": _checks,
		"checks_failed": _failures.size(),
		"failures": _failures.duplicate(),
		"measurements": _measurements.duplicate(true),
	}
	print("M17_HAIRPIN_FIRST_TICK ", JSON.stringify(report))
	print("CHECKS_TOTAL=", _checks, " CHECKS_FAILED=", _failures.size())
