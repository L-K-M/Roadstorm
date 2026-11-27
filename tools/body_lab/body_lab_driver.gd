extends Node
## Headless M1.1 motor/body adapter laboratory driver.
##
## Builds real flat-ground physics worlds, calls `MotorBodyAdapter.step()`
## exactly once per engine physics callback under `--fixed-fps 60`, and prints
## one machine-readable `SLICE_RESULT <json>` line per case plus a final
## `SLICE_SUMMARY <json>` line. The entry point defers adding this node.
##
## Scope: one car, flat ground, static walls, one 60 Hz tick at a time. It
## proves the adapter seam (prediction/commit, refusal atomicity, coordinate
## conventions, envelope, bounded wall response, repeatability), not ground
## adhesion, jumps, drift, reset, surfaces or multi-car contacts.

const AdapterScript = preload("res://src/simulation/motor_body_adapter.gd")
const ArcadeMotorScript = preload("res://src/simulation/arcade_motor.gd")
const ChecksScript = preload("res://tools/body_lab/body_lab_checks.gd")
const WorldScript = preload("res://tools/body_lab/body_lab_world.gd")

const DT := 1.0 / 60.0
## Frames allowed for static colliders to reach the physics server.
const SETTLE_FRAMES := 8
## Extra frames after teleporting the body before its first tick.
const POSE_SETTLE_FRAMES := 3
## Straight-wall laboratory layout.
const STRAIGHT_WALL_Z := -20.0
const OBLIQUE_WALL_POINT := Vector3(0.0, 2.0, -15.0)
const WALL_THICKNESS_M := 2.0
const WALL_WIDTH_M := 20.0
## No-tunneling assertion allowance, metres. The pinned Jolt build reports
# physics/jolt_physics_3d/simulation/penetration_slop = 0.02 m, so the near-face
# bound allows that measured contact slop; the far-face bound remains a real
# no-tunnel gate.
const PENETRATION_TOLERANCE_M := 0.03
## Prediction/commit consistency allowance, metres.
const PREDICTION_TOLERANCE_M := 1e-4
## CharacterBody3D.test_move carries a recovery offset near contacts; this is a
## diagnostic bound, not the authoritative prediction gate.
const TEST_MOVE_DIAGNOSTIC_TOLERANCE_M := 0.02

const CASE_IDS := [
	"config_and_invalid_atomicity",
	"coordinate_sign_conventions",
	"straight_motion_flat_ground",
	"prediction_commit_consistency",
	"wall_approach_no_tunnel",
	"oblique_wall_response",
	"envelope_refusal",
	"work_cap_and_truncation",
	"fixed_60hz_repeatability",
]

var d := ChecksScript.new()
var measurements: Dictionary = {}
var _case_results: Array[Dictionary] = []
var requested_case := "all"
var _recording_deltas := false
var _physics_deltas: Array[float] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_args(OS.get_cmdline_args())
	_run()


func _physics_process(delta: float) -> void:
	if _recording_deltas:
		_physics_deltas.append(delta)


func _parse_args(args: Array) -> void:
	for argument in args:
		if argument.begins_with("--case="):
			requested_case = argument.substr(7)
	var from_environment := OS.get_environment("BODY_LAB_CASE")
	if from_environment != "":
		requested_case = from_environment


func _run() -> void:
	if requested_case == "intentional_failure":
		var result := _run_intentional_failure()
		_finish_with([result])
		return
	if requested_case != "all" and not CASE_IDS.has(requested_case):
		printerr(
			"unknown case '%s'; use all, one of %s, or intentional_failure"
			% [requested_case, str(CASE_IDS)]
		)
		var bad := {
			"cases": 0,
			"checks": 0,
			"failed_cases": 1,
			"pass": false,
		}
		print("SLICE_SUMMARY " + JSON.stringify(bad))
		get_tree().quit(2)
		return
	var cases_to_run: Array = CASE_IDS if requested_case == "all" else [requested_case]
	for case_id in cases_to_run:
		_case_results.append(await _run_case(case_id))
	_finish_with(_case_results)


func _finish_with(results: Array[Dictionary]) -> void:
	var total_checks := 0
	var failed_cases := 0
	for result in results:
		total_checks += int(result["checks"])
		if not result["pass"]:
			failed_cases += 1
	var summary := {
		"cases": results.size(),
		"checks": total_checks,
		"failed_cases": failed_cases,
		"pass": failed_cases == 0,
	}
	print("SLICE_SUMMARY " + JSON.stringify(summary))
	get_tree().quit(0 if failed_cases == 0 else 1)


func _run_case(case_id: String) -> Dictionary:
	d = ChecksScript.new()
	measurements = {}
	match case_id:
		"config_and_invalid_atomicity":
			await _case_config_and_invalid_atomicity()
		"coordinate_sign_conventions":
			await _case_coordinate_sign_conventions()
		"straight_motion_flat_ground":
			await _case_straight_motion()
		"prediction_commit_consistency":
			await _case_prediction_commit_consistency()
		"wall_approach_no_tunnel":
			await _case_wall_approach()
		"oblique_wall_response":
			await _case_oblique_wall()
		"envelope_refusal":
			await _case_envelope_refusal()
		"work_cap_and_truncation":
			await _case_work_cap_and_truncation()
		"fixed_60hz_repeatability":
			await _case_fixed_60hz_repeatability()
	var result := {
		"case": case_id,
		"pass": d.failures.is_empty(),
		"checks": d.checks,
		"failures": d.failures.duplicate(),
		"measurements": measurements.duplicate(),
	}
	print("SLICE_RESULT " + JSON.stringify(result))
	return result


func _run_intentional_failure() -> Dictionary:
	d = ChecksScript.new()
	measurements = {"intentional": true}
	d.check(false, "intentional failure mode: this assertion always fails")
	d.check(true, "intentional-failure control check")
	return {
		"case": "intentional_failure",
		"pass": false,
		"checks": d.checks,
		"failures": d.failures.duplicate(),
		"measurements": measurements.duplicate(),
	}


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------


func _await_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().physics_frame


func _build_world(config, wall_spec: Dictionary = {}) -> BodyLabWorld:
	var world: BodyLabWorld = WorldScript.build(get_tree().root, config, wall_spec)
	await _await_frames(SETTLE_FRAMES)
	return world


func _place_body(world: BodyLabWorld, state, support_y: float) -> void:
	world.set_pose(state, support_y)
	await _await_frames(POSE_SETTLE_FRAMES)


func _destroy_world(world: BodyLabWorld) -> void:
	world.destroy()
	# Let the physics server drop the freed colliders before the next scenario
	# builds its own world; otherwise a stopped car can linger as an obstacle.
	await _await_frames(6)


## Drive one adapter call per engine physics callback. Records the result and
## the body transform immediately after each commit.
func _drive(world: BodyLabWorld, initial_state, commands: Array, tuning, config) -> Array:
	var records := []
	var current = initial_state
	for index in range(commands.size()):
		var result = AdapterScript.step(
			world.body, world.hull_shape, current, commands[index], tuning, config
		)
		records.append({"result": result, "pose": world.body.global_transform})
		current = result.committed_state
		await _await_frames(1)
	return records


func _max_prediction_discrepancy(records: Array) -> float:
	var worst := 0.0
	for record in records:
		worst = maxf(worst, record["result"].prediction_commit_discrepancy_m)
	return worst


func _max_test_move_discrepancy(records: Array) -> float:
	var worst := 0.0
	for record in records:
		worst = maxf(worst, record["result"].test_move_commit_discrepancy_m)
	return worst


func _max_motion_gap(records: Array) -> float:
	var worst := 0.0
	for record in records:
		var result = record["result"]
		worst = maxf(worst, result.accepted_motion_m.distance_to(result.proposed_motion_m))
	return worst


func _first_contact_index(records: Array) -> int:
	for index in range(records.size()):
		if records[index]["result"].contact:
			return index
	return -1


## Assert the hull stays within the wall's near/far faces. The near-face bound
## allows the pinned Jolt solver's measured contact slop (`penetration_slop`
## 0.02 m); the far-face bound is the actual no-tunneling gate. Returns the
## deepest signed distance (negative means slightly inside the near face).
func _assert_hull_within_wall_bounds(
	world: BodyLabWorld,
	records: Array,
	slop_tolerance: float,
	message: String
) -> float:
	var direction := -world.wall_normal
	var worst := 0.0
	for index in range(records.size()):
		var pose: Transform3D = records[index]["pose"]
		var support := d.box_support_point(pose, world.hull_shape.size, direction)
		var signed_distance: float = (support - world.wall_point).dot(world.wall_normal)
		worst = minf(worst, signed_distance)
		d.check(
			signed_distance >= -slop_tolerance,
			"%s: hull passed the near face by %.6f m at tick %d"
			% [message, -signed_distance, index + 1]
		)
		d.check(
			signed_distance >= -(world.wall_thickness_m + slop_tolerance),
			"%s: hull crossed the %.1f m wall at tick %d (signed distance %.6f)"
			% [message, world.wall_thickness_m, index + 1, signed_distance]
		)
	return worst


# ---------------------------------------------------------------------------
# Cases
# ---------------------------------------------------------------------------


func _case_config_and_invalid_atomicity() -> void:
	var config := d.make_config()
	var tuning := d.make_tuning()
	# A nearby wall makes any accidental movement observable.
	var wall_spec := {
		"point": Vector3(0.0, 2.0, -4.0),
		"yaw_deg": 0.0,
		"thickness_m": WALL_THICKNESS_M,
		"width_m": WALL_WIDTH_M,
	}
	var world := await _build_world(config, wall_spec)
	var state := d.make_state(Vector2(0.0, 0.0), Vector2(0.0, 20.0), 0.0)
	await _place_body(world, state, d.BODY_SUPPORT_Y)
	var pose_snapshot := world.body.global_transform
	var state_snapshot := d.snapshot_state(state)
	var idle := d.make_idle_command()

	var nan_state := d.make_state(Vector2(0.0, 0.0), Vector2(0.0, 20.0), 0.0)
	nan_state.position_m = Vector2(NAN, 0.0)
	var unnormalized := d.make_idle_command()
	unnormalized.steer = 2.0
	var negative_throttle := d.make_idle_command()
	negative_throttle.throttle = -0.5
	var empty_curve_tuning := ArcadeMotorScript.MotorTuning.make(
		[], 12.0, 0.0, 0.0, 0.12, 1.6, 4.0, 1.0, 0.3, 4.0, 8.0
	)
	var hull_mismatch := d.make_config()
	hull_mismatch.hull_size_m = Vector3(1.9, 1.0, 3.8)

	var variants := [
		{"name": "nan state", "state": nan_state, "command": idle, "tuning": tuning, "config": config, "dt": DT},
		{"name": "unnormalized steer", "state": state, "command": unnormalized, "tuning": tuning, "config": config, "dt": DT},
		{"name": "negative throttle", "state": state, "command": negative_throttle, "tuning": tuning, "config": config, "dt": DT},
		{"name": "empty tuning curve", "state": state, "command": idle, "tuning": empty_curve_tuning, "config": config, "dt": DT},
		{"name": "null command", "state": state, "command": null, "tuning": tuning, "config": config, "dt": DT},
		{"name": "null tuning", "state": state, "command": idle, "tuning": null, "config": config, "dt": DT},
		{"name": "wrong dt", "state": state, "command": idle, "tuning": tuning, "config": config, "dt": 1.0 / 30.0},
		{"name": "null config", "state": state, "command": idle, "tuning": tuning, "config": null, "dt": DT},
		{"name": "hull mismatch", "state": state, "command": idle, "tuning": tuning, "config": hull_mismatch, "dt": DT},
	]
	for variant in variants:
		var variant_command = variant["command"]
		var command_before := {}
		if variant_command != null:
			command_before = d.snapshot_command(variant_command)
		var result = AdapterScript.step(
			world.body,
			world.hull_shape,
			variant["state"],
			variant_command,
			variant["tuning"],
			variant["config"],
			variant["dt"]
		)
		var label: String = variant["name"]
		d.check(
			result.status == AdapterScript.Status.REJECTED_INVALID_INPUT,
			"%s: expected REJECTED_INVALID_INPUT, got %s (%s)"
			% [label, result.status, result.rejection_reason]
		)
		d.check(result.committed_state == null, "%s: refusal exposes no committed state" % label)
		d.check(
			world.body.global_transform.is_equal_approx(pose_snapshot),
			"%s: body transform unchanged" % label
		)
		d.check(
			world.body.global_position == pose_snapshot.origin,
			"%s: body origin unchanged" % label
		)
		d.check_state_unchanged(state, state_snapshot, label)
		if variant_command != null:
			d.check_command_unchanged(variant_command, command_before, label)

	# Over-envelope travel: 300 m/s * DT = 5 m, above the 4 m work cap.
	var fast_state := d.make_state(Vector2(0.0, 0.0), Vector2(0.0, 300.0), 0.0)
	var fast_snapshot := d.snapshot_state(fast_state)
	var fast_result = AdapterScript.step(
		world.body, world.hull_shape, fast_state, idle, tuning, config, DT
	)
	d.check(
		fast_result.status == AdapterScript.Status.REFUSED_MOTION_BOUND,
		"over-envelope: expected REFUSED_MOTION_BOUND, got %s" % fast_result.status
	)
	d.check(
		fast_result.rejection_reason.contains("exceeds envelope"),
		"over-envelope: refusal names the envelope (%s)" % fast_result.rejection_reason
	)
	d.check(
		world.body.global_transform.is_equal_approx(pose_snapshot),
		"over-envelope: body transform unchanged"
	)
	d.check_state_unchanged(fast_state, fast_snapshot, "over-envelope")
	measurements["envelope_m"] = config.max_tick_travel_m()
	measurements["over_envelope_requested_m"] = 300.0 * DT

	await _destroy_world(world)


func _case_coordinate_sign_conventions() -> void:
	var config := d.make_config()
	var tuning := d.make_tuning()
	var world := await _build_world(config, {})

	# Fixed axis mapping and nose basis at zero heading.
	var state := d.make_state(Vector2(2.0, 3.0), Vector2(0.0, 10.0), 0.0)
	await _place_body(world, state, d.BODY_SUPPORT_Y)
	var idle := d.make_idle_command()
	var result = AdapterScript.step(
		world.body, world.hull_shape, state, idle, tuning, config
	)
	d.check(result.status == AdapterScript.Status.COMMITTED, "mapping: step committed")
	if result.committed_state != null:
		d.check_close(result.proposed_motion_m.x, 0.0, 1e-9, "mapping: no world X motion at zero heading")
		d.check(result.proposed_motion_m.z < 0.0, "mapping: forward CarState y moves toward world -Z")
		d.check_vector_close(
			result.accepted_motion_m, result.proposed_motion_m, PREDICTION_TOLERANCE_M,
			"mapping: accepted follows proposed"
		)
		d.check_state_mapping(world.body, result.committed_state, 1e-5, "mapping")
		var committed_basis := world.body.global_transform.basis
		d.check_close(committed_basis.x.x, 1.0, 1e-6, "mapping: local +X is world +X at heading 0")
		d.check_close(committed_basis.z.z, 1.0, 1e-6, "mapping: local +Z is world +Z at heading 0")
		d.check_close(committed_basis.z.x, 0.0, 1e-6, "mapping: local +Z has no world X at heading 0")

	# Positive heading points the nose toward +X.
	var headed := d.make_state(Vector2(0.0, 0.0), Vector2(0.0, 10.0), 0.4)
	await _place_body(world, headed, d.BODY_SUPPORT_Y)
	var heading_result = AdapterScript.step(
		world.body, world.hull_shape, headed, idle, tuning, config
	)
	if heading_result.committed_state != null:
		var nose := AdapterScript.nose_forward_world(heading_result.committed_state.heading_rad)
		d.check(nose.x > 0.3, "heading: nose forward has positive world X")
		d.check(nose.z < -0.9, "heading: nose forward keeps negative world Z")
		var basis := world.body.global_transform.basis
		d.check_close(basis.z.x, -nose.x, 1e-6, "heading: local +Z is world backward")
		d.check_close(basis.z.z, -nose.z, 1e-6, "heading: local +Z opposes world forward")
		d.check_close(basis.z.y, 0.0, 1e-6, "heading: no roll in the support plane")
		var right := AdapterScript.nose_right_world(heading_result.committed_state.heading_rad)
		d.check_close(basis.x.x, right.x, 1e-6, "heading: local +X follows nose right")
		d.check_close(basis.x.z, right.z, 1e-6, "heading: local +X follows nose right in Z")

	# Road-plane lateral x is world +X regardless of heading. The storage-axis
	# mapping is fixed; heading only rotates the nose frame.
	var mapped := AdapterScript.road_vector_to_world(Vector2(5.0, 0.0))
	d.check(
		mapped.is_equal_approx(Vector3(5.0, 0.0, 0.0)),
		"lateral mapping: CarState (5,0) is world +X"
	)
	var unmapped := AdapterScript.world_vector_to_road(Vector3(5.0, 0.0, -3.0))
	d.check(unmapped == Vector2(5.0, 3.0), "lateral mapping: world (5,0,-3) is CarState (5,3)")
	for heading in [0.0, 0.3, -1.1]:
		var nose := AdapterScript.nose_forward_world(heading)
		var nose_right := AdapterScript.nose_right_world(heading)
		d.check_close(nose.length(), 1.0, 1e-6, "lateral mapping: nose unit length")
		d.check_close(nose.dot(nose_right), 0.0, 1e-6, "lateral mapping: nose axes orthogonal")
		d.check_close(nose.x, sin(heading), 1e-6, "lateral mapping: nose x follows sin(heading)")
		d.check_close(nose.z, -cos(heading), 1e-6, "lateral mapping: nose z follows -cos(heading)")
	var lateral := d.make_state(Vector2(0.0, 0.0), Vector2(5.0, 0.0), 0.0)
	await _place_body(world, lateral, d.BODY_SUPPORT_Y)
	var lateral_result = AdapterScript.step(
		world.body, world.hull_shape, lateral, idle, tuning, config
	)
	if lateral_result.committed_state != null:
		d.check(
			lateral_result.accepted_motion_m.x > 0.0,
			"lateral: CarState +x motion is world +X"
		)
		d.check(
			absf(lateral_result.accepted_motion_m.z) < 1e-9,
			"lateral: pure CarState x motion has no world Z component"
		)

	# Steering rotates the velocity and nose toward +X in world space.
	var steering_initial := d.make_state(Vector2(0.0, 0.0), Vector2(0.0, 20.0), 0.0)
	await _place_body(world, steering_initial, d.BODY_SUPPORT_Y)
	var steer := d.make_steer_command(1.0, 0.0)
	var steer_result = AdapterScript.step(
		world.body, world.hull_shape, steering_initial, steer, tuning, config
	)
	if steer_result.committed_state != null:
		d.check(
			steer_result.committed_state.heading_rad > 0.0,
			"steer: positive steer increases heading"
		)
		d.check(
			steer_result.committed_state.velocity_m_s.x > 0.0,
			"steer: committed velocity gains world +X component"
		)
		d.check(
			steer_result.committed_state.velocity_m_s.y > 0.0,
			"steer: committed velocity keeps forward component"
		)
		d.check(
			steer_result.accepted_motion_m.x > 0.0,
			"steer: committed motion curves toward +X"
		)

	await _destroy_world(world)


func _case_straight_motion() -> void:
	var config := d.make_config()
	var tuning := d.make_tuning()
	var world := await _build_world(config, {})
	var state := d.make_state(Vector2(0.0, 0.0), Vector2(0.0, 0.0), 0.0)
	await _place_body(world, state, d.BODY_SUPPORT_Y)
	var commands: Array = []
	for _index in range(90):
		commands.append(d.make_throttle_command(1.0))
	var records := await _drive(world, state, commands, tuning, config)
	d.check(records.size() == 90, "straight: 90 ticks driven")
	var previous_speed := 0.0
	var max_lateral := 0.0
	for index in range(records.size()):
		var result = records[index]["result"]
		var label := "straight tick %d" % (index + 1)
		d.check(result.status == AdapterScript.Status.COMMITTED, "%s: committed" % label)
		d.check(not result.contact, "%s: no contact on open ground" % label)
		d.check(
			result.prediction_commit_discrepancy_m <= PREDICTION_TOLERANCE_M,
			"%s: prediction matches commit" % label
		)
		d.check(
			result.accepted_motion_m.distance_to(result.proposed_motion_m) <= PREDICTION_TOLERANCE_M,
			"%s: accepted equals proposed without contact" % label
		)
		var committed = result.committed_state
		d.check(committed != null and committed.is_finite(), "%s: finite committed state" % label)
		if committed == null:
			continue
		var speed: float = committed.speed_m_s()
		d.check(speed >= previous_speed - 1e-9, "%s: speed does not decrease under throttle" % label)
		previous_speed = speed
		max_lateral = maxf(max_lateral, absf(committed.lateral_speed_m_s()))
		# Compare against this tick's recorded pose; the live body has advanced
		# further by the time the drive loop ends.
		var pose: Transform3D = records[index]["pose"]
		d.check_close(pose.origin.x, committed.position_m.x, 1e-5, "%s: body x mapping" % label)
		d.check_close(pose.origin.z, -committed.position_m.y, 1e-5, "%s: body z mapping" % label)
	d.check(previous_speed > 10.0 and previous_speed < 14.0, "straight: measured speed in the 10-14 m/s band after 1.5 s")
	d.check(max_lateral < 1e-9, "straight: no lateral drift without steer")
	measurements["final_speed_mps"] = previous_speed
	measurements["max_abs_lateral_mps"] = max_lateral
	measurements["max_prediction_discrepancy_m"] = _max_prediction_discrepancy(records)

	await _destroy_world(world)


func _case_prediction_commit_consistency() -> void:
	var config := d.make_config()
	var tuning := d.make_tuning()
	var world := await _build_world(config, {})
	var state := d.make_state(Vector2.ZERO, Vector2.ZERO, 0.0)
	await _place_body(world, state, d.BODY_SUPPORT_Y)
	var commands: Array = []
	for _index in range(30):
		commands.append(d.make_throttle_command(1.0))
	for _index in range(30):
		commands.append(d.make_steer_command(0.6, 1.0))
	for _index in range(30):
		commands.append(d.make_steer_command(-0.4, 1.0))
	for _index in range(30):
		commands.append(d.make_idle_command())
	var records := await _drive(world, state, commands, tuning, config)
	d.check(records.size() == 120, "consistency: 120 ticks driven")
	for index in range(records.size()):
		var result = records[index]["result"]
		d.check(result.status == AdapterScript.Status.COMMITTED, "consistency tick %d: committed" % (index + 1))
		d.check(result.committed_state != null, "consistency tick %d: state present" % (index + 1))
		d.check(
			result.prediction_commit_discrepancy_m <= PREDICTION_TOLERANCE_M,
			"consistency tick %d: prediction matches commit (%.9f)"
			% [index + 1, result.prediction_commit_discrepancy_m]
		)
		d.check(
			result.accepted_motion_m.distance_to(result.proposed_motion_m) <= PREDICTION_TOLERANCE_M,
			"consistency tick %d: accepted equals proposed (%.9f)"
			% [index + 1, result.accepted_motion_m.distance_to(result.proposed_motion_m)]
		)
	measurements["max_prediction_discrepancy_m"] = _max_prediction_discrepancy(records)
	measurements["max_test_move_discrepancy_m"] = _max_test_move_discrepancy(records)
	measurements["max_motion_gap_m"] = _max_motion_gap(records)
	d.check(
		_max_prediction_discrepancy(records) <= PREDICTION_TOLERANCE_M,
		"consistency: worst prediction discrepancy within tolerance"
	)
	d.check(
		_max_test_move_discrepancy(records) <= TEST_MOVE_DIAGNOSTIC_TOLERANCE_M,
		"consistency: worst test_move diagnostic within tolerance"
	)

	await _destroy_world(world)


## Replay the wall approach on one persistent world. Rebuilding worlds between
## repeats left a freed kinematic body registered long enough to contaminate
## the next run, so the repeat resets the body pose instead.
func _wall_fingerprint(world: BodyLabWorld, tuning, config) -> Dictionary:
	var state := d.make_state(Vector2.ZERO, Vector2(0.0, 65.0), 0.0)
	await _place_body(world, state, d.BODY_SUPPORT_Y)
	var commands: Array = []
	for _index in range(60):
		commands.append(d.make_idle_command())
	var records := await _drive(world, state, commands, tuning, config)
	var last_result = records[-1]["result"]
	return {
		"position_m": last_result.committed_state.position_m,
		"velocity_m_s": last_result.committed_state.velocity_m_s,
		"heading_rad": last_result.committed_state.heading_rad,
		"body_origin": records[-1]["pose"].origin,
		"contact_tick": _first_contact_index(records) + 1,
	}


func _case_wall_approach() -> void:
	var config := d.make_config()
	var tuning := d.make_tuning()
	var wall_spec := {
		"point": Vector3(0.0, 2.0, STRAIGHT_WALL_Z),
		"yaw_deg": 0.0,
		"thickness_m": WALL_THICKNESS_M,
		"width_m": WALL_WIDTH_M,
	}
	var world := await _build_world(config, wall_spec)
	var state := d.make_state(Vector2.ZERO, Vector2(0.0, 65.0), 0.0)
	await _place_body(world, state, d.BODY_SUPPORT_Y)
	var commands: Array = []
	for _index in range(60):
		commands.append(d.make_idle_command())
	var records := await _drive(world, state, commands, tuning, config)
	d.check(records.size() == 60, "wall: 60 ticks driven")

	var first_contact := _first_contact_index(records)
	d.check(first_contact > 0, "wall: contact occurred")
	var pre_contact_result = records[0]["result"]
	var travel_per_tick: float = pre_contact_result.proposed_motion_m.length()
	d.check_close(travel_per_tick, 65.0 * DT, 1e-6, "wall: commanded travel at 65 m/s")
	d.check(
		travel_per_tick <= config.max_tick_travel_m() + config.envelope_epsilon_m,
		"wall: 65 m/s travel is inside the audited envelope"
	)
	measurements["travel_per_tick_m"] = travel_per_tick
	measurements["envelope_m"] = config.max_tick_travel_m()
	measurements["first_contact_tick"] = first_contact + 1

	var min_substeps_at_speed := 999
	for index in range(first_contact):
		var result = records[index]["result"]
		d.check(result.status == AdapterScript.Status.COMMITTED, "wall pre-contact tick %d: committed" % (index + 1))
		d.check(not result.contact, "wall pre-contact tick %d: no contact" % (index + 1))
		d.check(
			result.prediction_commit_discrepancy_m <= PREDICTION_TOLERANCE_M,
			"wall pre-contact tick %d: prediction matches commit" % (index + 1)
		)
		min_substeps_at_speed = mini(min_substeps_at_speed, result.substeps)
	d.check(min_substeps_at_speed >= 4, "wall: 65 m/s motion is subdivided (min %d substeps)" % min_substeps_at_speed)
	measurements["min_substeps_at_65_mps"] = min_substeps_at_speed

	if first_contact >= 0:
		var impact = records[first_contact]["result"]
		d.check(impact.wall_contact, "wall: impact classified as wall contact")
		d.check(impact.contact_normal.z > 0.9, "wall: contact normal points back toward the car (+Z)")
		var committed_velocity_world := AdapterScript.road_vector_to_world(
			impact.committed_state.velocity_m_s
		)
		d.check(
			committed_velocity_world.dot(impact.contact_normal) >= -1e-6,
			"wall: committed velocity retains no inward normal component"
		)
		d.check(
			impact.committed_state.speed_m_s() <= 65.0 + 1e-6,
			"wall: committed speed does not exceed the approach speed"
		)
		var contact_point_plane_distance: float = (impact.contact_point - world.wall_point).dot(world.wall_normal)
		d.check(
			absf(contact_point_plane_distance) <= 0.05,
			"wall: contact point lies on the wall plane"
		)
		measurements["post_contact_speed_mps"] = impact.committed_state.speed_m_s()
		measurements["post_contact_normal_speed_mps"] = committed_velocity_world.dot(
			impact.contact_normal
		)
		measurements["contact_limited_remainder_m"] = impact.remainder_m

	var worst_plane_distance := _assert_hull_within_wall_bounds(
		world, records, PENETRATION_TOLERANCE_M, "wall"
	)
	measurements["worst_hull_plane_distance_m"] = worst_plane_distance
	var last_pose: Transform3D = records[-1]["pose"]
	var front_gap := last_pose.origin.z - world.hull_shape.size.z * 0.5 - STRAIGHT_WALL_Z
	measurements["final_front_gap_m"] = front_gap
	d.check(front_gap >= -PENETRATION_TOLERANCE_M, "wall: final hull front never crosses the wall face")

	# Repeatability: three replays on the same wall must finish bit-identically.
	var fingerprints := []
	for _index in range(3):
		fingerprints.append(await _wall_fingerprint(world, tuning, config))
	for index in range(1, fingerprints.size()):
		d.check(
			fingerprints[index]["position_m"] == fingerprints[0]["position_m"],
			"wall replay %d: position bit-identical" % (index + 1)
		)
		d.check(
			fingerprints[index]["velocity_m_s"] == fingerprints[0]["velocity_m_s"],
			"wall replay %d: velocity bit-identical" % (index + 1)
		)
		d.check(
			fingerprints[index]["heading_rad"] == fingerprints[0]["heading_rad"],
			"wall replay %d: heading bit-identical" % (index + 1)
		)
		d.check(
			fingerprints[index]["body_origin"] == fingerprints[0]["body_origin"],
			"wall replay %d: body origin bit-identical" % (index + 1)
		)
		d.check(
			fingerprints[index]["contact_tick"] == fingerprints[0]["contact_tick"],
			"wall replay %d: contact tick identical" % (index + 1)
		)
	measurements["replay_contact_ticks"] = [
		fingerprints[0]["contact_tick"],
		fingerprints[1]["contact_tick"],
		fingerprints[2]["contact_tick"],
	]

	await _destroy_world(world)


func _case_oblique_wall() -> void:
	var config := d.make_config()
	var tuning := d.make_tuning()
	var wall_spec := {
		"point": OBLIQUE_WALL_POINT,
		"yaw_deg": 30.0,
		"thickness_m": WALL_THICKNESS_M,
		"width_m": WALL_WIDTH_M,
	}
	var world := await _build_world(config, wall_spec)
	var state := d.make_state(Vector2.ZERO, Vector2(0.0, 30.0), 0.0)
	await _place_body(world, state, d.BODY_SUPPORT_Y)
	var commands: Array = []
	for _index in range(60):
		commands.append(d.make_idle_command())
	var records := await _drive(world, state, commands, tuning, config)
	d.check(records.size() == 60, "oblique: 60 ticks driven")
	var first_contact := _first_contact_index(records)
	d.check(first_contact > 0, "oblique: contact occurred")
	if first_contact < 0:
		await _destroy_world(world)
		return
	var impact = records[first_contact]["result"]
	d.check(impact.wall_contact, "oblique: impact classified as wall contact")
	var expected_normal := Vector3(sin(deg_to_rad(30.0)), 0.0, cos(deg_to_rad(30.0)))
	d.check(
		impact.contact_normal.distance_to(expected_normal) <= 1e-3,
		"oblique: measured normal matches the 30 degree wall"
	)
	var committed_world_velocity := AdapterScript.road_vector_to_world(
		impact.committed_state.velocity_m_s
	)
	var inward_speed := committed_world_velocity.dot(impact.contact_normal)
	d.check(inward_speed >= -1e-6, "oblique: committed velocity retains no inward normal component")
	var retained_speed: float = impact.committed_state.speed_m_s()
	d.check_close(retained_speed, 15.0, 1e-3, "oblique: tangential speed retained at unity keep")
	d.check(
		retained_speed <= 30.0 + 1e-6,
		"oblique: committed speed does not increase"
	)
	var contact_plane_distance: float = (impact.contact_point - world.wall_point).dot(world.wall_normal)
	d.check(absf(contact_plane_distance) <= 0.05, "oblique: contact point lies on the wall plane")
	var worst_oblique := _assert_hull_within_wall_bounds(
		world, records, PENETRATION_TOLERANCE_M, "oblique"
	)
	measurements["worst_hull_plane_distance_m"] = worst_oblique
	measurements["post_contact_speed_mps"] = retained_speed
	measurements["post_contact_normal_speed_mps"] = inward_speed
	measurements["first_contact_tick"] = first_contact + 1

	await _destroy_world(world)


func _case_envelope_refusal() -> void:
	# Constrained work cap: 4 * 0.25 m = 1.0 m per tick, below the 1.083 m a
	# 65 m/s tick demands. Travel above the cap must be refused, not truncated.
	var constrained := d.make_constrained_config(4)
	d.check_close(constrained.max_tick_travel_m(), 1.0, 1e-12, "envelope: constrained cap is 1.0 m")
	var world := await _build_world(constrained, {})
	var state := d.make_state(Vector2.ZERO, Vector2(0.0, 65.0), 0.0)
	await _place_body(world, state, d.BODY_SUPPORT_Y)
	var pose_snapshot := world.body.global_transform
	var state_snapshot := d.snapshot_state(state)
	var idle := d.make_idle_command()
	var tuning := d.make_tuning()
	var refused = AdapterScript.step(
		world.body, world.hull_shape, state, idle, tuning, constrained, DT
	)
	d.check(
		refused.status == AdapterScript.Status.REFUSED_MOTION_BOUND,
		"envelope: 65 m/s refused under a 1.0 m cap"
	)
	d.check(
		world.body.global_transform.is_equal_approx(pose_snapshot),
		"envelope: refused body transform unchanged"
	)
	d.check_state_unchanged(state, state_snapshot, "envelope")
	await _destroy_world(world)

	# Boundary control: 50 m/s = 0.833 m/tick is inside the constrained cap.
	var world_two := await _build_world(constrained, {})
	var slower := d.make_state(Vector2.ZERO, Vector2(0.0, 50.0), 0.0)
	await _place_body(world_two, slower, d.BODY_SUPPORT_Y)
	var accepted = AdapterScript.step(
		world_two.body, world_two.hull_shape, slower, idle, tuning, constrained, DT
	)
	d.check(
		accepted.status == AdapterScript.Status.COMMITTED,
		"envelope: 50 m/s control commits under the same cap"
	)
	await _destroy_world(world_two)

	# Default laboratory cap covers 65 m/s with subdivision headroom.
	var default_config := d.make_config()
	var headroom := default_config.max_tick_travel_m() / (65.0 * DT)
	d.check(headroom >= 1.0, "envelope: default cap admits 65 m/s")
	measurements["default_cap_speed_mps"] = default_config.max_tick_travel_m() / DT
	measurements["constrained_cap_m"] = constrained.max_tick_travel_m()
	measurements["headroom_ratio_at_65_mps"] = headroom


func _case_work_cap_and_truncation() -> void:
	# --- Positive and default controls ------------------------------------
	var default_config := d.make_config()
	d.check(default_config.is_valid(), "workcap: default config is valid")
	d.check(
		default_config.max_substeps <= AdapterScript.ABSOLUTE_MAX_SUBSTEPS,
		"workcap: default substep count within absolute cap"
	)
	d.check_close(
		default_config.max_tick_travel_m(), 4.0, 1e-12, "workcap: default envelope is 4 m"
	)
	d.check(
		not is_nan(default_config.max_tick_travel_m())
		and not is_inf(default_config.max_tick_travel_m()),
		"workcap: default envelope product is finite"
	)

	var limit_config := d.make_absolute_limit_config()
	d.check(limit_config.is_valid(), "workcap: absolute-boundary config is valid")
	d.check_close(
		limit_config.max_tick_travel_m(),
		AdapterScript.ABSOLUTE_MAX_SUBSTEP_LENGTH_M * AdapterScript.ABSOLUTE_MAX_SUBSTEPS,
		1e-12,
		"workcap: absolute envelope product is finite and bounded"
	)
	measurements["absolute_envelope_m"] = limit_config.max_tick_travel_m()
	measurements["absolute_max_substeps"] = limit_config.max_substeps

	# The absolute-boundary config still admits the 65 m/s laboratory case.
	var fast_world := await _build_world(limit_config, {})
	var fast_state := d.make_state(Vector2.ZERO, Vector2(0.0, 65.0), 0.0)
	await _place_body(fast_world, fast_state, d.BODY_SUPPORT_Y)
	var fast_result = AdapterScript.step(
		fast_world.body,
		fast_world.hull_shape,
		fast_state,
		d.make_idle_command(),
		d.make_tuning(),
		limit_config
	)
	d.check(
		fast_result.status == AdapterScript.Status.COMMITTED,
		"workcap: 65 m/s commits under absolute caps"
	)
	if fast_result.committed_state != null:
		d.check(
			fast_result.substeps >= 2,
			"workcap: 65 m/s uses at least two 1 m substeps"
		)
		d.check(
			fast_result.prediction_commit_discrepancy_m <= PREDICTION_TOLERANCE_M,
			"workcap: absolute-cap prediction matches commit"
		)
		d.check(
			fast_result.accepted_motion_m.distance_to(fast_result.proposed_motion_m)
			<= PREDICTION_TOLERANCE_M,
			"workcap: absolute-cap accepted equals proposed"
		)
		measurements["absolute_cap_substeps_at_65_mps"] = fast_result.substeps
	await _destroy_world(fast_world)

	# --- Negative configs -------------------------------------------------
	# The coordinator-reported exploit: one substep plus a 10 m epsilon used to
	# accept multi-substep travel and return COMMITTED after one segment.
	var exploit := d.make_constrained_config(1)
	exploit.envelope_epsilon_m = 10.0
	d.check(not exploit.is_valid(), "workcap: reported exploit config is rejected")

	var too_many := d.make_config()
	too_many.max_substeps = AdapterScript.ABSOLUTE_MAX_SUBSTEPS + 1
	d.check(not too_many.is_valid(), "workcap: max_substeps above absolute cap rejected")
	var zero_steps := d.make_config()
	zero_steps.max_substeps = 0
	d.check(not zero_steps.is_valid(), "workcap: zero max_substeps rejected")
	var huge_step := d.make_config()
	huge_step.substep_max_length_m = AdapterScript.ABSOLUTE_MAX_SUBSTEP_LENGTH_M + 0.5
	d.check(not huge_step.is_valid(), "workcap: substep above absolute cap rejected")
	var negative_step := d.make_config()
	negative_step.substep_max_length_m = -0.25
	d.check(not negative_step.is_valid(), "workcap: negative substep rejected")
	var large_eps := d.make_config()
	large_eps.envelope_epsilon_m = 1.0
	d.check(not large_eps.is_valid(), "workcap: 1 m envelope epsilon rejected")
	var negative_eps := d.make_config()
	negative_eps.envelope_epsilon_m = -1e-9
	d.check(not negative_eps.is_valid(), "workcap: negative envelope epsilon rejected")
	var large_stop := d.make_config()
	large_stop.contact_stop_epsilon_m = 0.1
	d.check(
		not large_stop.is_valid(),
		"workcap: contact-stop epsilon above substep fraction rejected"
	)
	var large_margin := d.make_config()
	large_margin.sweep_margin_m = 1.0
	d.check(not large_margin.is_valid(), "workcap: sweep margin above one substep rejected")
	var large_commit_margin := d.make_config()
	large_commit_margin.commit_safe_margin_m = 1.0
	d.check(
		not large_commit_margin.is_valid(),
		"workcap: commit margin above one substep rejected"
	)

	# A config exactly at the epsilon ceiling remains valid; twice it does not.
	var boundary_eps := d.make_constrained_config(1)
	boundary_eps.envelope_epsilon_m = minf(
		boundary_eps.substep_max_length_m * AdapterScript.MAX_ENVELOPE_EPSILON_FRACTION,
		AdapterScript.MAX_ENVELOPE_EPSILON_M
	)
	d.check(boundary_eps.is_valid(), "workcap: epsilon exactly at ceiling is valid")
	var over_eps := d.make_constrained_config(1)
	over_eps.envelope_epsilon_m = boundary_eps.envelope_epsilon_m * 2.0
	d.check(not over_eps.is_valid(), "workcap: epsilon above ceiling rejected")

	# --- No-contact truncation regression ---------------------------------
	# Valid one-substep config; desired travel above its 0.25 m envelope must be
	# refused before any movement, with body and caller state untouched.
	var constrained := d.make_constrained_config(1)
	d.check(constrained.is_valid(), "workcap: one-substep control config is valid")
	var world := await _build_world(constrained, {})
	var tuning := d.make_tuning()
	var idle := d.make_idle_command()
	var state := d.make_state(Vector2.ZERO, Vector2(0.0, 20.0), 0.0)
	await _place_body(world, state, d.BODY_SUPPORT_Y)
	var pose_snapshot := world.body.global_transform
	var state_snapshot := d.snapshot_state(state)
	var desired := 20.0 * DT

	var refused = AdapterScript.step(
		world.body, world.hull_shape, state, idle, tuning, constrained, DT
	)
	d.check(
		refused.status == AdapterScript.Status.REFUSED_MOTION_BOUND,
		"truncation: over-envelope no-contact travel is refused"
	)
	d.check(
		refused.rejection_reason.contains("exceeds envelope"),
		"truncation: refusal names the envelope"
	)
	d.check_close(
		refused.remainder_m, desired, 1e-6, "truncation: refused remainder reports full desired travel"
	)
	d.check(
		world.body.global_transform.is_equal_approx(pose_snapshot),
		"truncation: body transform unchanged"
	)
	d.check(
		world.body.global_position == pose_snapshot.origin,
		"truncation: body origin unchanged"
	)
	d.check_state_unchanged(state, state_snapshot, "truncation")
	measurements["refused_desired_m"] = desired
	measurements["refused_remainder_m"] = refused.remainder_m

	# The previously valid exploit config is now an invalid-input refusal and
	# must also leave the body and state untouched.
	var exploit_result = AdapterScript.step(
		world.body, world.hull_shape, state, idle, tuning, exploit, DT
	)
	d.check(
		exploit_result.status == AdapterScript.Status.REJECTED_INVALID_INPUT,
		"truncation: exploit config rejected as invalid input"
	)
	d.check(
		world.body.global_transform.is_equal_approx(pose_snapshot),
		"truncation: exploit rejection leaves body unchanged"
	)
	d.check_state_unchanged(state, state_snapshot, "truncation exploit")

	# Positive control: a one-substep tick inside the envelope still commits.
	var exact_state := d.make_state(Vector2.ZERO, Vector2(0.0, 15.0), 0.0)
	await _place_body(world, exact_state, d.BODY_SUPPORT_Y)
	var exact_result = AdapterScript.step(
		world.body, world.hull_shape, exact_state, idle, tuning, constrained, DT
	)
	d.check(
		exact_result.status == AdapterScript.Status.COMMITTED,
		"truncation: in-envelope one-substep tick commits"
	)
	if exact_result.committed_state != null:
		d.check_close(
			exact_result.accepted_motion_m.length(),
			0.25,
			1e-6,
			"truncation: one-substep control applies the full segment"
		)
		d.check(
			exact_result.remainder_m <= constrained.envelope_epsilon_m,
			"truncation: clean tick remainder within epsilon"
		)
		d.check(
			not exact_result.contact_limited_remainder,
			"truncation: clean tick is not contact-limited"
		)

	# Boundary epsilon: only micrometre-scale slack may be dropped, and it is
	# reported rather than hidden.
	var boundary_world := await _build_world(boundary_eps, {})
	var boundary_state := d.make_state(Vector2.ZERO, Vector2(0.0, 15.006), 0.0)
	await _place_body(boundary_world, boundary_state, d.BODY_SUPPORT_Y)
	var boundary_result = AdapterScript.step(
		boundary_world.body,
		boundary_world.hull_shape,
		boundary_state,
		idle,
		tuning,
		boundary_eps,
		DT
	)
	d.check(
		boundary_result.status == AdapterScript.Status.COMMITTED,
		"truncation: boundary-epsilon tick commits"
	)
	if boundary_result.committed_state != null:
		d.check(
			boundary_result.remainder_m <= boundary_eps.envelope_epsilon_m,
			"truncation: boundary remainder stays within the tiny epsilon"
		)
		d.check(
			boundary_result.remainder_m < 1e-3,
			"truncation: epsilon cannot authorize millimetre-scale drops"
		)
		measurements["boundary_epsilon_m"] = boundary_eps.envelope_epsilon_m
		measurements["boundary_remainder_m"] = boundary_result.remainder_m

	await _destroy_world(boundary_world)
	await _destroy_world(world)


func _trace_commands() -> Array:
	var commands: Array = []
	for _index in range(40):
		commands.append(d.make_throttle_command(1.0))
	for _index in range(40):
		commands.append(d.make_steer_command(0.5, 1.0))
	for _index in range(40):
		commands.append(d.make_brake_command(0.5))
	for _index in range(40):
		commands.append(d.make_idle_command())
	return commands


func _run_trace(commands: Array) -> Dictionary:
	var config := d.make_config()
	var tuning := d.make_tuning()
	var world := await _build_world(config, {})
	var state := d.make_state(Vector2.ZERO, Vector2.ZERO, 0.0)
	await _place_body(world, state, d.BODY_SUPPORT_Y)
	_recording_deltas = true
	var records := await _drive(world, state, commands, tuning, config)
	_recording_deltas = false
	var trace := {
		"position_m": [],
		"velocity_m_s": [],
		"heading_rad": [],
		"body_origin": [],
	}
	for record in records:
		var committed = record["result"].committed_state
		trace["position_m"].append(committed.position_m)
		trace["velocity_m_s"].append(committed.velocity_m_s)
		trace["heading_rad"].append(committed.heading_rad)
		trace["body_origin"].append(record["pose"].origin)
	await _destroy_world(world)
	return trace


func _case_fixed_60hz_repeatability() -> void:
	var commands := _trace_commands()
	_physics_deltas.clear()
	var first := await _run_trace(commands)
	var second := await _run_trace(commands)
	d.check(
		first["position_m"].size() == commands.size(),
		"repeatability: first trace complete"
	)
	d.check(
		second["position_m"].size() == commands.size(),
		"repeatability: second trace complete"
	)
	var mismatches := 0
	for index in range(mini(first["position_m"].size(), second["position_m"].size())):
		if first["position_m"][index] != second["position_m"][index]:
			mismatches += 1
		if first["velocity_m_s"][index] != second["velocity_m_s"][index]:
			mismatches += 1
		if first["heading_rad"][index] != second["heading_rad"][index]:
			mismatches += 1
		if first["body_origin"][index] != second["body_origin"][index]:
			mismatches += 1
	d.check(mismatches == 0, "repeatability: two fixed-60 Hz traces are bit-identical")
	var bad_delta_count := 0
	for delta in _physics_deltas:
		if absf(delta - DT) > 1e-9:
			bad_delta_count += 1
	d.check(bad_delta_count == 0, "repeatability: every physics callback reported 1/60 s")
	d.check(
		_physics_deltas.size() == commands.size() * 2,
		"repeatability: one adapter tick per physics callback (%d callbacks for %d ticks)"
		% [_physics_deltas.size(), commands.size()]
	)
	measurements["ticks"] = commands.size()
	measurements["physics_callbacks_recorded"] = _physics_deltas.size()
	measurements["mismatches"] = mismatches
	measurements["final_position_m"] = [
		first["position_m"][-1].x,
		first["position_m"][-1].y,
	]
