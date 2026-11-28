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
## Gentle-yaw regression layout: a parallel wall whose near face is 5 cm from
## the hull's right side at zero heading. Its outward near-face normal is -X.
const GENTLE_YAW_WALL_POINT := Vector3(0.95, 2.0, 0.0)
const GENTLE_YAW_TICKS := 30
## Low-speed/high-gain tuning gives a yaw rate of 5.0 * 0.1 = 0.5 rad/s,
## below the old per-tick skip threshold `tolerance / (0.5 * hull diagonal)`
## ~ 0.00925 rad (about 0.555 rad/s). The low speed keeps translation small.
const GENTLE_YAW_FORWARD_SPEED_M_S := 0.1
const GENTLE_YAW_GAIN_GRIP := 5.0
## Yaw-constrained committed-velocity regression layout: a parallel wall whose
## near face is 5 cm from the hull's right side. The car carries a lateral
## component pointing away from the wall while steering hard toward it, so the
## translation chord moves away (no wall hit) but the proposed yaw swings the
## long hull's right corner into the wall. The old adapter publishes the full
## proposal velocity into the wall; the policy reprojects the same scalars into
## the applied heading.
const YAW_VELOCITY_WALL_POINT := Vector3(0.95, 2.0, 0.0)
const YAW_VELOCITY_FORWARD_SPEED_M_S := 2.0
const YAW_VELOCITY_LATERAL_SPEED_M_S := -0.5
const YAW_VELOCITY_STEER_GAIN_GRIP := 9.0
const YAW_VELOCITY_MAX_YAW_RATE_RAD_S := 20.0
const YAW_VELOCITY_TICKS := 8
## Yaw-constrained wall-response witness layout: the same parallel wall and
## steering as `yaw_constrained_velocity_policy`, but with a lateral component
## that carries the car into the wall, so one tick has both a constrained yaw
## and a real wall contact. The 5 cm gap closes in about two ticks.
const YAW_WITNESS_LATERAL_SPEED_M_S := 0.5
const YAW_WITNESS_TICKS := 6
## Same slab used with its layer excluded from and included in the body mask.
const MASK_CONSISTENCY_WALL_POINT := Vector3(0.0, 2.0, -10.0)
const MASK_CONSISTENCY_APPROACH_SPEED_M_S := 20.0
const MASK_CONSISTENCY_TICKS := 55
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
## Tolerance for the wall-response witness comparisons, m/s and metres. The
## laboratory's own contact slop is centimetres; this gate only has to catch a
## wrong sample, a wrong frame or an inferred displacement.
const WITNESS_TOLERANCE_MPS := 1e-5
## The rotated-hull regression asserts against the laboratory's existing
## no-tunnel gate (3 cm); the reduced-box probe boundary sits about 5 mm past
## its nominal shrink, well inside that gate.

const CASE_IDS := [
	"config_and_invalid_atomicity",
	"coordinate_sign_conventions",
	"straight_motion_flat_ground",
	"prediction_commit_consistency",
	"collision_mask_consistency",
	"wall_approach_no_tunnel",
	"oblique_wall_response",
	"tilted_wall_response",
	"multi_contact_collection",
	"wall_contact_normal_authority",
	"wall_contact_point_selection",
	"wall_contact_point_telemetry",
	"rotated_hull_wall_orientation",
	"gentle_yaw_wall_probe",
	"yaw_constrained_velocity_policy",
	"envelope_refusal",
	"work_cap_and_truncation",
	"wall_response_witness_selection",
	"wall_response_witness_telemetry",
	"fixed_60hz_repeatability",
]

var d := ChecksScript.new()
var measurements: Dictionary = {}
var _case_results: Array[Dictionary] = []
var requested_case := "all"
var _recording_deltas := false
var _physics_deltas: Array[float] = []


## Deterministic collision-like fixture for the collection seam. It exposes the
## same `get_collision_count()`, `get_normal(index)` and
## `get_position(index)` surface as a real `KinematicCollision3D`, with an
## explicit contact order the physics server cannot be made to emit.
class SeamCollision extends RefCounted:
	var normals: Array = []
	var positions: Array = []

	func _init(normals_: Array, positions_: Array) -> void:
		normals = normals_
		positions = positions_

	func get_collision_count() -> int:
		return normals.size()

	func get_normal(index: int = 0) -> Vector3:
		return normals[index]

	func get_position(index: int = 0) -> Vector3:
		return positions[index]


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
		"collision_mask_consistency":
			await _case_collision_mask_consistency()
		"wall_approach_no_tunnel":
			await _case_wall_approach()
		"oblique_wall_response":
			await _case_oblique_wall()
		"tilted_wall_response":
			await _case_tilted_wall_response()
		"multi_contact_collection":
			await _case_multi_contact_collection()
		"wall_contact_normal_authority":
			await _case_wall_contact_normal_authority()
		"wall_contact_point_selection":
			await _case_wall_contact_point_selection()
		"wall_contact_point_telemetry":
			await _case_wall_contact_point_telemetry()
		"wall_response_witness_selection":
			await _case_wall_response_witness_selection()
		"wall_response_witness_telemetry":
			await _case_wall_response_witness_telemetry()
		"rotated_hull_wall_orientation":
			await _case_rotated_hull_wall_orientation()
		"gentle_yaw_wall_probe":
			await _case_gentle_yaw_wall_probe()
		"yaw_constrained_velocity_policy":
			await _case_yaw_constrained_velocity_policy()
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
		# `state_in` is the committed state this tick started from, so a witness
		# assertion can rebuild the tick-start basis independently of the result.
		records.append({
			"result": result,
			"pose": world.body.global_transform,
			"state_in": current,
		})
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


## Assert `value` is parallel (or antiparallel) to `direction` within a tight
## cosine tolerance. Used to prove a velocity change lies along one axis.
func _check_parallel(value: Vector3, direction: Vector3, message: String) -> void:
	var length := value.length()
	if length <= 1e-9:
		d.check(false, message + " (zero vector)")
		return
	var cosine: float = value.normalized().dot(direction.normalized())
	d.check(
		absf(absf(cosine) - 1.0) <= 1e-6,
		"%s (cosine %.12f)" % [message, cosine]
	)


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


func _case_collision_mask_consistency() -> void:
	# Regression for the MEDIUM interim finding: `_cast_safe_fraction()` must
	# query with the body's actual collision mask. A wall on an excluded layer is
	# invisible to `move_and_collide()`, so the primary prediction must ignore it
	# too and stay bit-consistent with the committed travel. The identical slab on
	# an included layer must still stop the body and the prediction.
	var config := d.make_config()
	var tuning := d.make_tuning()
	var wall_spec := {
		"point": MASK_CONSISTENCY_WALL_POINT,
		"yaw_deg": 0.0,
		"thickness_m": WALL_THICKNESS_M,
		"width_m": WALL_WIDTH_M,
	}
	var commands: Array = []
	for _index in range(MASK_CONSISTENCY_TICKS):
		commands.append(d.make_idle_command())

	# --- Excluded layer: the wall is on layer 2, the car mask is layer 1. ---
	var world := await _build_world(config, wall_spec)
	world.wall.collision_layer = 2
	world.body.collision_layer = 1
	world.body.collision_mask = 1
	await _await_frames(2)
	d.check(world.wall.collision_layer == 2, "mask-excluded: wall is on layer 2")
	d.check(world.body.collision_mask == 1, "mask-excluded: car mask is layer 1 only")
	var state := d.make_state(
		Vector2.ZERO, Vector2(0.0, MASK_CONSISTENCY_APPROACH_SPEED_M_S), 0.0
	)
	await _place_body(world, state, d.BODY_SUPPORT_Y)
	var records := await _drive(world, state, commands, tuning, config)
	d.check(records.size() == MASK_CONSISTENCY_TICKS, "mask-excluded: all ticks driven")
	for index in range(records.size()):
		var result = records[index]["result"]
		var label := "mask-excluded tick %d" % (index + 1)
		d.check(result.status == AdapterScript.Status.COMMITTED, "%s: committed" % label)
		d.check(not result.contact, "%s: excluded-layer wall produces no contact" % label)
		d.check(
			result.prediction_commit_discrepancy_m <= PREDICTION_TOLERANCE_M,
			"%s: primary prediction matches commit (%.9f)"
			% [label, result.prediction_commit_discrepancy_m]
		)
		d.check(
			result.predicted_motion_m.distance_to(result.accepted_motion_m)
			<= PREDICTION_TOLERANCE_M,
			"%s: predicted travel equals committed travel" % label
		)
		d.check(
			result.accepted_motion_m.distance_to(result.proposed_motion_m)
			<= PREDICTION_TOLERANCE_M,
			"%s: full physical motion committed" % label
		)
	var final_origin: Vector3 = records[-1]["pose"].origin
	var far_face_z := MASK_CONSISTENCY_WALL_POINT.z - WALL_THICKNESS_M * 0.5
	var rear_offset := world.hull_shape.size.z * 0.5
	d.check(
		final_origin.z + rear_offset <= far_face_z + PREDICTION_TOLERANCE_M,
		"mask-excluded: hull fully crosses the excluded-layer wall (origin z %.6f)"
		% final_origin.z
	)
	measurements["excluded_final_origin_z"] = final_origin.z
	measurements["excluded_wall_far_face_z"] = far_face_z
	measurements["excluded_max_prediction_discrepancy_m"] = _max_prediction_discrepancy(records)
	await _destroy_world(world)

	# --- Included layer: the identical slab stops body and prediction. -----
	var included_world := await _build_world(config, wall_spec)
	included_world.wall.collision_layer = 1
	included_world.body.collision_layer = 1
	included_world.body.collision_mask = 1
	await _await_frames(2)
	d.check(included_world.wall.collision_layer == 1, "mask-included: wall is on layer 1")
	d.check(
		included_world.body.collision_mask == 1,
		"mask-included: car mask includes layer 1"
	)
	var included_state := d.make_state(
		Vector2.ZERO, Vector2(0.0, MASK_CONSISTENCY_APPROACH_SPEED_M_S), 0.0
	)
	await _place_body(included_world, included_state, d.BODY_SUPPORT_Y)
	var included_records := await _drive(
		included_world, included_state, commands, tuning, config
	)
	d.check(
		included_records.size() == MASK_CONSISTENCY_TICKS,
		"mask-included: all ticks driven"
	)
	var first_contact := _first_contact_index(included_records)
	d.check(first_contact > 0, "mask-included: included-layer wall produced contact")
	if first_contact >= 0:
		var impact = included_records[first_contact]["result"]
		d.check(impact.wall_contact, "mask-included: impact classified as wall contact")
		d.check(
			impact.contact_normal.z > 0.9,
			"mask-included: contact normal points back toward the car (+Z)"
		)
		d.check(
			impact.prediction_commit_discrepancy_m <= PREDICTION_TOLERANCE_M,
			"mask-included: primary prediction matches the stopped commit (%.9f)"
			% impact.prediction_commit_discrepancy_m
		)
		d.check(
			impact.accepted_motion_m.length() < impact.proposed_motion_m.length(),
			"mask-included: contact stops the physical motion short"
		)
		d.check(
			impact.contact_limited_remainder,
			"mask-included: contact-limited remainder reported"
		)
		measurements["included_first_contact_tick"] = first_contact + 1
	var worst_included := _assert_hull_within_wall_bounds(
		included_world, included_records, PENETRATION_TOLERANCE_M, "mask-included"
	)
	measurements["included_worst_hull_plane_distance_m"] = worst_included
	measurements["included_max_prediction_discrepancy_m"] = _max_prediction_discrepancy(
		included_records
	)
	await _destroy_world(included_world)


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


func _case_tilted_wall_response() -> void:
	# Regression for the GPT-6.2 Sol tilted-wall finding on 4ff7bec: the old
	# response removed the inward component along the full 3D normal and then
	# flattened the velocity, leaving about -1.6 m/s of inward road speed for
	# this exact scenario. The adapter now resolves against the normalized
	# road-plane projection, and this case drives the real adapter into a real
	# pinned-Jolt rolled wall whose measured normal is (sqrt(0.84), 0.4, 0).
	var config := d.make_config()
	var tuning := d.make_tuning()
	# Keep the approach velocity exactly (-10, 0, 0) for the reported
	# geometry; the shared tuning's lateral damping would decay it first.
	tuning.lateral_damping_grip_per_s = 0.0
	var expected_normal := Vector3(sqrt(0.84), 0.4, 0.0)
	var wall_spec := {
		"point": Vector3(1.0, 0.55, 0.0),
		"normal": expected_normal,
		"thickness_m": WALL_THICKNESS_M,
		"width_m": WALL_WIDTH_M,
	}
	var world := await _build_world(config, wall_spec)
	var state := d.make_state(Vector2(2.5, 0.0), Vector2(-10.0, 0.0), 0.0)
	await _place_body(world, state, d.BODY_SUPPORT_Y)
	var commands: Array = []
	for _index in range(8):
		commands.append(d.make_idle_command())
	var records := await _drive(world, state, commands, tuning, config)
	d.check(records.size() == 8, "tilted: 8 ticks driven")
	var first_contact := _first_contact_index(records)
	d.check(first_contact > 0, "tilted: contact occurred")
	if first_contact < 0:
		await _destroy_world(world)
		return
	var impact = records[first_contact]["result"]
	d.check(
		impact.status == AdapterScript.Status.COMMITTED,
		"tilted: impact tick committed"
	)
	d.check(impact.contact, "tilted: contact telemetry set")
	d.check(impact.wall_contact, "tilted: tilted normal classified as wall contact")
	d.check(
		impact.wall_contact_normal.distance_to(expected_normal) <= 1e-4,
		"tilted: authoritative normal matches the rolled wall (%s)"
		% impact.wall_contact_normal
	)
	var projected_normal := Vector3(
		expected_normal.x, 0.0, expected_normal.z
	).normalized()
	var committed_world := AdapterScript.road_vector_to_world(
		impact.committed_state.velocity_m_s
	)
	var inward_projected := committed_world.dot(projected_normal)
	var inward_full := committed_world.dot(expected_normal.normalized())
	d.check(
		inward_projected >= -1e-6,
		"tilted: no inward road-plane projected component (%.9f m/s)" % inward_projected
	)
	d.check(
		inward_full >= -1e-6,
		"tilted: no inward full-normal component (%.9f m/s)" % inward_full
	)
	d.check(
		impact.committed_state.speed_m_s() <= 10.0 + 1e-6,
		"tilted: committed speed does not increase"
	)
	measurements["wall_contact_normal"] = impact.wall_contact_normal
	measurements["inward_projected_speed_mps"] = inward_projected
	measurements["inward_full_normal_speed_mps"] = inward_full
	measurements["worst_hull_plane_distance_m"] = (
		_assert_hull_within_wall_bounds(
			world, records, PENETRATION_TOLERANCE_M, "tilted"
		)
	)
	await _destroy_world(world)


func _case_multi_contact_collection() -> void:
	# Regression for the second GPT-6.2 Sol finding: one collision result can
	# report several contacts, so reading only the default index can drop a
	# wall listed after a floor-like contact. Pinned Jolt did not reproduce a
	# literal floor-first/wall-second batch here (see README); the ordered batch
	# is injected at the collection seam the sweep uses, and a real engine
	# collision flows through the same helper below.
	var config := d.make_config()
	var adapter := AdapterScript.new()
	var has_collector: bool = adapter.has_method("_collect_collision_contacts")
	d.check(
		has_collector,
		"seam: adapter exposes the collision collection helper"
	)
	if not has_collector:
		# Old source lacks the collection seam; the tilted-wall case carries the
		# behavioral negative control instead.
		return
	var floor_normal := Vector3(0.0, 1.0, 0.0)
	var wall_normal := Vector3(0.0, 0.0, 1.0)
	var opposite_wall_normal := Vector3(0.0, 0.0, -1.0)
	var floor_first := SeamCollision.new(
		[floor_normal, wall_normal],
		[Vector3(0.0, 0.0, -1.0), Vector3(0.0, 0.5, -1.0)]
	)
	var collected: Dictionary = adapter.call(
		"_collect_collision_contacts", floor_first, config
	)
	d.check(
		collected["generic_normal"] == floor_normal,
		"seam: generic telemetry stays the first reported contact"
	)
	d.check(
		collected["generic_point"] == Vector3(0.0, 0.0, -1.0),
		"seam: generic point stays the first reported contact"
	)
	d.check(
		collected["wall_normals"].size() == 1,
		"seam: floor-first batch still yields the wall candidate"
	)
	d.check(
		collected["wall_normals"][0] == wall_normal,
		"seam: retained wall normal is exact"
	)
	# The retained candidate must drive the real response: the old
	# default-index-only rule would have left this inward wall speed.
	var approach_velocity := Vector3(0.0, 0.0, -20.0)
	var injected_chosen := AdapterScript._select_wall_response_normal(
		collected["wall_normals"], approach_velocity
	)
	d.check(
		injected_chosen == wall_normal,
		"seam: collected wall candidate is selectable"
	)
	var injected_corrected := AdapterScript._apply_wall_response(
		approach_velocity, injected_chosen, config
	)
	d.check(
		injected_corrected.dot(wall_normal) >= -1e-6,
		"seam: injected batch responds without inward wall remainder"
	)

	var two_walls := SeamCollision.new(
		[wall_normal, floor_normal, opposite_wall_normal],
		[Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	)
	var collected_two: Dictionary = adapter.call(
		"_collect_collision_contacts", two_walls, config
	)
	d.check(
		collected_two["generic_normal"] == wall_normal,
		"seam: first of three contacts is generic"
	)
	d.check(
		collected_two["wall_normals"].size() == 2,
		"seam: both wall candidates survive a floor between them"
	)
	d.check(
		collected_two["wall_normals"][0] == wall_normal
		and collected_two["wall_normals"][1] == opposite_wall_normal,
		"seam: wall candidates keep reported order"
	)

	# Degenerate road-plane projection guard.
	var vertical_normal := Vector3(0.0, 1.0, 0.0)
	var zero_projection: Vector3 = adapter.call(
		"_road_plane_unit_normal", vertical_normal
	)
	d.check(
		zero_projection == Vector3.ZERO,
		"guard: vertical normal has no road-plane projection"
	)
	d.check(
		AdapterScript._apply_wall_response(
			Vector3(1.0, 2.0, 3.0), vertical_normal, config
		) == Vector3(1.0, 2.0, 3.0),
		"guard: degenerate projection leaves the velocity unchanged"
	)

	# A real pinned-Jolt collision object flows through the same helper.
	var wall_spec := {
		"point": Vector3(0.0, 2.0, STRAIGHT_WALL_Z),
		"yaw_deg": 0.0,
	"thickness_m": WALL_THICKNESS_M,
	"width_m": WALL_WIDTH_M,
	}
	var world := await _build_world(config, wall_spec)
	var state := d.make_state(Vector2.ZERO, Vector2(0.0, 20.0), 0.0)
	await _place_body(world, state, d.BODY_SUPPORT_Y)
	var real_collision: KinematicCollision3D = null
	for _index in range(60):
		var motion := Vector3(0.0, 0.0, -20.0 * DT)
		real_collision = world.body.move_and_collide(motion, false, 0.0, false, 8)
		if real_collision != null:
			break
		await _await_frames(1)
	d.check(real_collision != null, "seam: real pinned-Jolt wall collision captured")
	if real_collision != null:
		var real_collected: Dictionary = adapter.call(
			"_collect_collision_contacts", real_collision, config
		)
		d.check(
			real_collected["generic_normal"].distance_to(Vector3(0.0, 0.0, 1.0)) <= 1e-4,
			"seam: real generic telemetry is the wall normal"
		)
		d.check(
			real_collected["wall_normals"].size() >= 1,
			"seam: real multi-contact result yields wall candidates"
		)
		var approach := Vector3(0.0, 0.0, -20.0)
		var chosen := AdapterScript._select_wall_response_normal(
			real_collected["wall_normals"], approach
		)
		var corrected := AdapterScript._apply_wall_response(approach, chosen, config)
		d.check(
			corrected.dot(chosen.normalized()) >= -1e-6,
			"seam: collected real wall normal responds without inward remainder"
		)
		measurements["real_wall_contact_count"] = real_collected["wall_normals"].size()
	await _destroy_world(world)


func _case_wall_contact_normal_authority() -> void:
	# Regression for interim review N2: `wall_hit` latched true while the
	# generic `hit_normal` was overwritten on every collision, so a later
	# floor-like contact could make the final wall response use the floor normal
	# and leave the inward wall velocity. The adapter now retains an
	# authoritative wall-like normal independently of last-contact telemetry.
	#
	# A pinned-Jolt staging search did not reliably emit a wall-like contact
	# followed by a floor-like contact inside one tick (see README), so the
	# sequence is driven through the public selection seam. The same case run
	# against pre-fix source reports failures, which is the old-source proof.
	var config := d.make_config()
	var tuning := d.make_tuning()

	# --- Wall-like contact followed by a floor-like generic contact. ---------
	var wall_normal := Vector3(0.0, 0.0, 1.0)
	var floor_normal := Vector3(0.0, 1.0, 0.0)
	var approach_velocity := Vector3(0.0, 0.0, -20.0)
	var adapter := AdapterScript.new()
	var has_selector := adapter.has_method("_select_wall_response_normal")
	d.check(has_selector, "seam: adapter exposes the wall-normal selection helper")
	var authoritative := floor_normal
	if has_selector:
		var chosen: Vector3 = adapter.call(
			"_select_wall_response_normal",
			[wall_normal, floor_normal],
			approach_velocity
		)
		authoritative = chosen
	d.check(
		authoritative == wall_normal,
		"seam: a later floor-like contact does not replace the wall normal"
	)

	var corrected := AdapterScript._apply_wall_response(
		approach_velocity, authoritative, config
	)
	d.check(
		corrected.dot(wall_normal) >= -1e-6,
		"seam: no inward velocity on the authoritative wall normal"
	)
	d.check(
		corrected.dot(floor_normal) >= -1e-6,
		"seam: response adds no floor-normal velocity"
	)

	# Negative control: the old last-contact rule applies the floor normal and
	# leaves the inward wall component untouched. This shows the scenario
	# discriminates pre-fix from fixed source.
	var old_rule_result := AdapterScript._apply_wall_response(
		approach_velocity, floor_normal, config
	)
	d.check(
		old_rule_result.dot(wall_normal) < -1.0,
		"control: old last-contact rule keeps inward wall velocity"
	)
	d.check(
		old_rule_result.dot(wall_normal) < corrected.dot(wall_normal),
		"control: old rule is strictly less corrected"
	)
	measurements["wall_seam_authoritative"] = authoritative
	measurements["wall_seam_old_rule_inward_speed"] = old_rule_result.dot(wall_normal)
	measurements["wall_seam_corrected_inward_speed"] = corrected.dot(wall_normal)

	# --- Multiple wall contacts: documented deterministic choice. ----------
	if has_selector:
		var head_on := Vector3(0.0, 0.0, 1.0)
		var oblique := Vector3(0.5, 0.0, 0.8660254)
		var head_on_choice: Vector3 = adapter.call(
			"_select_wall_response_normal",
			[oblique, head_on],
			Vector3(0.0, 0.0, -20.0)
		)
		d.check(
			head_on_choice.is_equal_approx(head_on),
			"multi-wall: most-opposed normal chosen"
		)
		var oblique_choice: Vector3 = adapter.call(
			"_select_wall_response_normal",
			[head_on, oblique],
			Vector3(-20.0, 0.0, 0.0)
		)
		d.check(
			oblique_choice.is_equal_approx(oblique),
			"multi-wall: choice follows the proposed velocity"
		)
		var tie_choice: Vector3 = adapter.call(
			"_select_wall_response_normal",
			[Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0)],
			Vector3(-10.0, 0.0, -10.0)
		)
		d.check(
			tie_choice.is_equal_approx(Vector3(1.0, 0.0, 0.0)),
			"multi-wall: exact tie keeps the earliest contact"
		)
	else:
		d.check(false, "old source lacks the wall-normal selection helper")

	# --- Real pinned Jolt wall contact wires the authoritative normal. -----
	var wall_spec := {
		"point": Vector3(0.0, 2.0, STRAIGHT_WALL_Z),
		"yaw_deg": 0.0,
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
	var first_contact := _first_contact_index(records)
	d.check(first_contact > 0, "jolt: wall contact occurred")
	if first_contact >= 0:
		var impact = records[first_contact]["result"]
		d.check(impact.wall_contact, "jolt: impact classified as wall contact")
		if has_selector:
			d.check(
				impact.wall_contact_normal.z > 0.9,
				"jolt: authoritative wall normal points back toward the car (+Z)"
			)
		var committed_world := AdapterScript.road_vector_to_world(
			impact.committed_state.velocity_m_s
		)
		var response_normal: Vector3 = (
			impact.wall_contact_normal if has_selector else impact.contact_normal
		)
		d.check(
			committed_world.dot(response_normal) >= -1e-6,
			"jolt: committed velocity retains no inward component on the response normal"
		)
		if has_selector:
			measurements["jolt_wall_contact_normal"] = impact.wall_contact_normal
		measurements["jolt_post_contact_normal_speed"] = committed_world.dot(response_normal)
	await _destroy_world(world)


## Replay the exact accepted substep motions of one committed tick from its
## recorded start transform, returning the real pinned-Jolt collision of the
## first colliding substep. Used to bind the published wall point back to the
## collision object's own `get_position(index)` values.
func _replay_collision(
	world: BodyLabWorld,
	pre_pose: Transform3D,
	proposed_motion: Vector3,
	config
) -> KinematicCollision3D:
	world.body.global_transform = pre_pose
	var remaining := proposed_motion
	for _index in range(config.max_substeps):
		if remaining.length() <= AdapterScript.MIN_SEGMENT_LENGTH_M:
			break
		var segment_length := minf(remaining.length(), config.substep_max_length_m)
		var motion := remaining.normalized() * segment_length
		var collision := world.body.move_and_collide(
			motion, false, config.commit_safe_margin_m, false, 8
		)
		if collision != null:
			return collision
		remaining -= motion
	return null


func _case_wall_contact_point_selection() -> void:
	# Focused regressions for the authoritative wall-contact point witness.
	# Contact ordering is driven through the deterministic collision-like
	# fixture already supported by `_collect_collision_contacts`; pinned Jolt
	# staging does not reliably emit a floor-first/wall-second batch (README).
	var config := d.make_config()
	var adapter := AdapterScript.new()
	var has_witness: bool = adapter.has_method("_select_wall_contact")
	d.check(has_witness, "witness: adapter exposes the wall contact selection helper")
	if not has_witness:
		return

	# Source contract guard for the exact named regression: the Result field
	# must be populated from the selected witness candidate, never from the
	# generic first-contact telemetry. Pinned-Jolt staging cannot reliably emit
	# a winning candidate whose point differs from the generic point, so this
	# guard complements the fixture behavior checks below.
	var adapter_source := ""
	if FileAccess.file_exists("res://src/simulation/motor_body_adapter.gd"):
		var source_file := FileAccess.open(
			"res://src/simulation/motor_body_adapter.gd", FileAccess.READ
		)
		adapter_source = source_file.get_as_text()
		source_file.close()
	d.check(not adapter_source.is_empty(), "witness source: adapter source readable")
	d.check(
		adapter_source.contains("selected_wall_contact[\"point\"]"),
		"witness source: Result publishes the selected witness point"
	)
	d.check(
		adapter_source.contains("wall_points.append_array(collected[\"wall_points\"])"),
		"witness source: collected wall points are retained per candidate"
	)
	d.check(
		not adapter_source.contains("result.wall_contact_point = hit_point"),
		"witness source: Result does not publish the generic hit point"
	)

	var floor_normal := Vector3(0.0, 1.0, 0.0)
	var wall_normal := Vector3(0.0, 0.0, 1.0)
	var head_on_normal := Vector3(0.0, 0.0, 1.0)
	var oblique_normal := Vector3(0.5, 0.0, 0.8660254)
	var approach_velocity := Vector3(0.0, 0.0, -20.0)

	# --- Floor-first/wall-second with different points. -----------------
	var floor_point := Vector3(0.0, 0.0, -1.0)
	var wall_point := Vector3(0.9, 0.5, -2.0)
	var floor_first := SeamCollision.new(
		[floor_normal, wall_normal], [floor_point, wall_point]
	)
	var collected_floor: Dictionary = adapter.call(
		"_collect_collision_contacts", floor_first, config
	)
	d.check(
		collected_floor["generic_point"] == floor_point,
		"witness floor-first: generic point stays the first contact"
	)
	d.check(
		collected_floor["wall_normals"].size() == 1,
		"witness floor-first: wall candidate retained"
	)
	d.check(
		collected_floor["wall_points"].size() == 1,
		"witness floor-first: wall point retained"
	)
	d.check(
		collected_floor["wall_points"][0] == wall_point,
		"witness floor-first: wall point is the second contact position"
	)
	var chosen_floor: Dictionary = adapter.call(
		"_select_wall_contact",
		collected_floor["wall_normals"],
		collected_floor["wall_points"],
		approach_velocity
	)
	d.check(chosen_floor["valid"], "witness floor-first: valid witness")
	d.check(chosen_floor["normal"] == wall_normal, "witness floor-first: winning normal")
	d.check(
		chosen_floor["point"] == wall_point,
		"witness floor-first: point bound to the wall contact"
	)
	d.check(
		chosen_floor["point"] != collected_floor["generic_point"],
		"witness floor-first: point is not the generic first contact"
	)

	# --- Two wall normals; the most-opposed winner is not first. --------
	var oblique_point := Vector3(-3.0, 0.5, 2.0)
	var head_on_point := Vector3(0.0, 0.5, -2.0)
	var two_walls := SeamCollision.new(
		[oblique_normal, head_on_normal], [oblique_point, head_on_point]
	)
	var collected_two: Dictionary = adapter.call(
		"_collect_collision_contacts", two_walls, config
	)
	d.check(collected_two["wall_points"][0] == oblique_point, "witness two-wall: first point recorded")
	d.check(collected_two["wall_points"][1] == head_on_point, "witness two-wall: second point recorded")
	var chosen_two: Dictionary = adapter.call(
		"_select_wall_contact",
		collected_two["wall_normals"],
		collected_two["wall_points"],
		approach_velocity
	)
	d.check(
		chosen_two["normal"].is_equal_approx(head_on_normal),
		"witness two-wall: most-opposed winner is not first"
	)
	d.check(
		chosen_two["point"] == head_on_point,
		"witness two-wall: point follows the winning candidate"
	)
	d.check(
		chosen_two["point"] != collected_two["generic_point"],
		"witness two-wall: point is not the generic first contact"
	)

	# --- Exact tie keeps the earliest candidate and its point. ----------
	var tie_point_a := Vector3(1.0, 0.5, 0.0)
	var tie_point_b := Vector3(0.0, 0.5, 1.0)
	var tie := SeamCollision.new(
		[Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0)],
		[tie_point_a, tie_point_b]
	)
	var collected_tie: Dictionary = adapter.call(
		"_collect_collision_contacts", tie, config
	)
	var tie_velocity := Vector3(-10.0, 0.0, -10.0)
	var chosen_tie: Dictionary = adapter.call(
		"_select_wall_contact",
		collected_tie["wall_normals"],
		collected_tie["wall_points"],
		tie_velocity
	)
	d.check(
		chosen_tie["normal"].is_equal_approx(Vector3(1.0, 0.0, 0.0)),
		"witness tie: earliest normal kept"
	)
	d.check(chosen_tie["point"] == tie_point_a, "witness tie: earliest candidate point kept")
	d.check(
		AdapterScript._select_wall_response_index(
			collected_tie["wall_normals"], tie_velocity
		) == 0,
		"witness tie: shared index helper keeps the earliest candidate"
	)

	# --- Candidates aggregated across collision indices and substeps. ---
	var first_substep := SeamCollision.new(
		[floor_normal, oblique_normal], [floor_point, oblique_point]
	)
	var second_substep := SeamCollision.new([head_on_normal], [head_on_point])
	var substep_normals: Array = []
	var substep_points: Array = []
	for collision in [first_substep, second_substep]:
		var collected: Dictionary = adapter.call(
			"_collect_collision_contacts", collision, config
		)
		substep_normals.append_array(collected["wall_normals"])
		substep_points.append_array(collected["wall_points"])
	var chosen_steps: Dictionary = adapter.call(
		"_select_wall_contact", substep_normals, substep_points, approach_velocity
	)
	d.check(
		chosen_steps["normal"].is_equal_approx(head_on_normal),
		"witness substeps: winner comes from a later substep"
	)
	d.check(
		chosen_steps["point"] == head_on_point,
		"witness substeps: point bound across substeps"
	)

	# --- Degenerate normal, nonfinite point and empty candidates. -------
	var vertical_point := Vector3(1.0, 2.0, 3.0)
	var degenerate: Dictionary = adapter.call(
		"_select_wall_contact",
		[Vector3(0.0, 1.0, 0.0)], [vertical_point], approach_velocity
	)
	d.check(not degenerate["valid"], "witness degenerate: no valid witness")
	d.check(degenerate["point"] == Vector3.ZERO, "witness degenerate: zero point")
	d.check(
		AdapterScript._select_wall_response_normal(
			[Vector3(0.0, 1.0, 0.0)], approach_velocity
		).is_equal_approx(Vector3(0.0, 1.0, 0.0)),
		"witness degenerate: normal-only selection unchanged"
	)
	var nonfinite: Dictionary = adapter.call(
		"_select_wall_contact",
		[wall_normal], [Vector3(NAN, 0.0, 0.0)], approach_velocity
	)
	d.check(not nonfinite["valid"], "witness nonfinite: no valid witness")
	d.check(nonfinite["point"] == Vector3.ZERO, "witness nonfinite: zero point")
	var empty: Dictionary = adapter.call(
		"_select_wall_contact", [], [], approach_velocity
	)
	d.check(not empty["valid"], "witness empty: no valid witness")
	measurements["witness_fixture_valid"] = (
		1 if chosen_floor["valid"] and chosen_two["valid"] and chosen_tie["valid"] else 0
	)


func _case_wall_contact_point_telemetry() -> void:
	# Real pinned-Jolt Result telemetry and default/refusal atomicity.
	var config := d.make_config()
	var tuning := d.make_tuning()

	# --- Committed no-wall tick: no witness. -----------------------------
	var open_world := await _build_world(config, {})
	var open_state := d.make_state(Vector2.ZERO, Vector2(0.0, 20.0), 0.0)
	await _place_body(open_world, open_state, d.BODY_SUPPORT_Y)
	var open_result = AdapterScript.step(
		open_world.body, open_world.hull_shape, open_state,
		d.make_idle_command(), tuning, config
	)
	d.check(open_result.status == AdapterScript.Status.COMMITTED, "witness open: committed")
	d.check(not open_result.contact, "witness open: no contact")
	d.check(not open_result.wall_contact, "witness open: no wall contact")
	d.check(
		not open_result.has_wall_contact_point,
		"witness open: no witness flag"
	)
	d.check(
		open_result.wall_contact_point == Vector3.ZERO,
		"witness open: zero wall point"
	)
	await _destroy_world(open_world)

	# --- Refused tick: must not publish a wall point. -------------------
	var refuse_world := await _build_world(config, {
		"point": Vector3(0.0, 2.0, -4.0),
		"yaw_deg": 0.0,
		"thickness_m": WALL_THICKNESS_M,
		"width_m": WALL_WIDTH_M,
	})
	var fast_state := d.make_state(Vector2.ZERO, Vector2(0.0, 300.0), 0.0)
	await _place_body(refuse_world, fast_state, d.BODY_SUPPORT_Y)
	var refuse_pose := refuse_world.body.global_transform
	var refused = AdapterScript.step(
		refuse_world.body, refuse_world.hull_shape, fast_state,
		d.make_idle_command(), tuning, config
	)
	d.check(
		refused.status == AdapterScript.Status.REFUSED_MOTION_BOUND,
		"witness refusal: over-envelope tick refused"
	)
	d.check(
		not refused.has_wall_contact_point,
		"witness refusal: no witness flag"
	)
	d.check(
		refused.wall_contact_point == Vector3.ZERO,
		"witness refusal: zero wall point"
	)
	d.check(
		refuse_world.body.global_transform.is_equal_approx(refuse_pose),
		"witness refusal: body transform unchanged"
	)
	await _destroy_world(refuse_world)

	# --- Real pinned-Jolt single wall: valid witness on the wall plane. -
	var wall_spec := {
		"point": Vector3(0.0, 2.0, STRAIGHT_WALL_Z),
		"yaw_deg": 0.0,
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
	var first_contact := _first_contact_index(records)
	d.check(first_contact > 0, "witness jolt: wall contact occurred")
	if first_contact < 0:
		await _destroy_world(world)
		return
	var impact = records[first_contact]["result"]
	d.check(impact.status == AdapterScript.Status.COMMITTED, "witness jolt: committed")
	d.check(impact.wall_contact, "witness jolt: wall contact classified")
	d.check(impact.has_wall_contact_point, "witness jolt: witness flag set")
	d.check_vector_finite(impact.wall_contact_point, "witness jolt: finite wall point")
	var plane_distance: float = (
		(impact.wall_contact_point - world.wall_point).dot(world.wall_normal)
	)
	d.check(
		absf(plane_distance) <= 0.05,
		"witness jolt: wall point lies on the wall plane (%.6f m)" % plane_distance
	)
	d.check(not impact.heading_constrained, "witness jolt: yaw unconstrained for replay")
	measurements["witness_jolt_plane_distance_m"] = plane_distance

	# Replay the exact tick to recover the real collision object, then
	# require the published point to equal the winning candidate's own
	# reported position.
	var replay_collision := _replay_collision(
		world, impact.start_transform, impact.proposed_motion_m, config
	)
	d.check(replay_collision != null, "witness jolt: replay captured the real collision")
	if replay_collision != null:
		var adapter := AdapterScript.new()
		var collected: Dictionary = adapter.call(
			"_collect_collision_contacts", replay_collision, config
		)
		d.check(
			collected["wall_points"].size() == collected["wall_normals"].size(),
			"witness jolt: every wall candidate carries a point"
		)
		d.check(
			collected["wall_points"].size() == replay_collision.get_collision_count(),
			"witness jolt: all real contacts are wall-like"
		)
		for index in range(collected["wall_points"].size()):
			d.check(
				collected["wall_points"][index] == replay_collision.get_position(index),
				"witness jolt: candidate point is get_position(%d)" % index
			)
		var velocity_world := AdapterScript.road_vector_to_world(
			impact.proposed_state.velocity_m_s
		)
		var expected: Dictionary = AdapterScript._select_wall_contact(
			collected["wall_normals"], collected["wall_points"], velocity_world
		)
		d.check(expected["valid"], "witness jolt: replay yields a valid winner")
		d.check(
			impact.wall_contact_normal.is_equal_approx(expected["normal"]),
			"witness jolt: replay winner normal matches the response"
		)
		d.check(
			impact.wall_contact_point.is_equal_approx(expected["point"]),
			"witness jolt: published point equals the exact winning contact position"
		)
		measurements["witness_jolt_candidate_count"] = collected["wall_points"].size()
	await _destroy_world(world)


func _case_rotated_hull_wall_orientation() -> void:
	# Regression for the HIGH interim finding: the translation sweep uses the
	# tick-start basis, so an unchecked yaw can install a long hull across a
	# wall. Hull 1.8 x 3.8 m, right side 5 cm from a parallel wall.
	var config := d.make_config()
	# Nominal 1.5 cm shrink: tight enough to prove the constraint, loose enough
	# that the measured probe boundary stays well inside the 3 cm lab gate.
	config.orientation_contact_tolerance_m = 0.015
	# Explicit reviewer-scenario yaw: about 3 degrees per 60 Hz tick, the angle
	# whose 3.8 m hull corner extends roughly 9.8 cm sideways. The shared lab
	# tuning caps yaw at 1.6 rad/s, which cannot reach it in one tick.
	var tuning := d.make_tuning()
	tuning.yaw_gain_grip = 2.0
	tuning.max_yaw_rate_rad_s = PI
	var wall_spec := {
		"point": Vector3(0.95, 2.0, 0.0),
		"yaw_deg": -90.0,
		"thickness_m": WALL_THICKNESS_M,
		"width_m": WALL_WIDTH_M,
	}
	var world := await _build_world(config, wall_spec)
	var state := d.make_state(Vector2.ZERO, Vector2(0.0, 2.0), 0.0)
	await _place_body(world, state, d.BODY_SUPPORT_Y)
	var commands: Array = []
	for _index in range(6):
		commands.append(d.make_steer_command(1.0, 0.0))
	var records := await _drive(world, state, commands, tuning, config)
	d.check(records.size() == 6, "rotated: 6 ticks driven")

	var allowance := PENETRATION_TOLERANCE_M
	var saw_constraint := false
	var worst_signed := 0.0
	for index in range(records.size()):
		var result = records[index]["result"]
		var label := "rotated tick %d" % (index + 1)
		if result.committed_state == null:
			d.check(
				result.status != AdapterScript.Status.COMMITTED,
				"%s: refusal exposes no committed state" % label
			)
		var pose: Transform3D = records[index]["pose"]
		var support := d.box_support_point(pose, world.hull_shape.size, -world.wall_normal)
		var signed: float = (support - world.wall_point).dot(world.wall_normal)
		worst_signed = minf(worst_signed, signed)
		d.check(
			signed >= -allowance,
			"%s: final hull overlaps the wall by %.6f m" % [label, -signed]
		)
		if result.committed_state == null:
			continue
		var committed = result.committed_state
		d.check(committed.is_finite(), "%s: finite committed state" % label)
		d.check_close(pose.origin.x, committed.position_m.x, 1e-5, "%s: body x mapping" % label)
		d.check_close(pose.origin.z, -committed.position_m.y, 1e-5, "%s: body z mapping" % label)
		d.check(
			pose.basis.is_equal_approx(AdapterScript.basis_from_heading(committed.heading_rad)),
			"%s: body basis matches the committed heading" % label
		)
		if not is_equal_approx(committed.heading_rad, result.proposed_state.heading_rad):
			saw_constraint = true
		if index == 0:
			var unchecked_pose := Transform3D(
				AdapterScript.basis_from_heading(result.proposed_state.heading_rad), pose.origin
			)
			var unchecked_support := d.box_support_point(
				unchecked_pose, world.hull_shape.size, -world.wall_normal
			)
			var unchecked_signed: float = (
				(unchecked_support - world.wall_point).dot(world.wall_normal)
			)
			d.check(
				unchecked_signed < -allowance,
				"rotated tick 1: the unchecked yaw would penetrate by %.6f m"
				% [-unchecked_signed]
			)
	d.check(saw_constraint, "rotated: steering toward the wall constrained the yaw")
	measurements["worst_hull_plane_distance_m"] = worst_signed
	measurements["orientation_allowance_m"] = allowance

	await _destroy_world(world)

	# Clean open-ground control: identical steering must rotate without a wall.
	var open_world := await _build_world(config, {})
	var open_state := d.make_state(Vector2.ZERO, Vector2(0.0, 2.0), 0.0)
	await _place_body(open_world, open_state, d.BODY_SUPPORT_Y)
	var open_records := await _drive(open_world, open_state, commands, tuning, config)
	var previous_heading := open_state.heading_rad
	for index in range(open_records.size()):
		var result = open_records[index]["result"]
		var label := "open-ground tick %d" % (index + 1)
		d.check(result.status == AdapterScript.Status.COMMITTED, "%s: committed" % label)
		if result.committed_state == null:
			continue
		d.check(
			is_equal_approx(result.committed_state.heading_rad, result.proposed_state.heading_rad),
			"%s: clear ground preserves the proposed yaw" % label
		)
		d.check(
			result.committed_state.heading_rad > previous_heading,
			"%s: steering still rotates the nose" % label
		)
		var pose: Transform3D = open_records[index]["pose"]
		d.check(
			pose.basis.is_equal_approx(
				AdapterScript.basis_from_heading(result.committed_state.heading_rad)
			),
			"%s: body basis matches the committed heading" % label
		)
		previous_heading = result.committed_state.heading_rad
	await _destroy_world(open_world)


func _case_gentle_yaw_wall_probe() -> void:
	# Regression for interim review F1: the installed-pose probe used to run
	# only when `0.5 * hull diagonal * |yaw delta|` exceeded the orientation
	# contact tolerance, so a gentle yaw below that threshold (~0.555 rad/s for
	# the default 0.02 m tolerance and this hull) skipped the world check
	# entirely. The adapter now probes every nonzero yaw. This real pinned-Jolt
	# case runs at 0.5 rad/s (0.1 m/s with grip gain 5.0, full opposite lock)
	# for 30 ticks next to a parallel wall 5 cm from the hull's right side.
	# The nose turns away from the wall so the trailing right corner sweeps
	# toward it while the centreline velocity carries the car away. That keeps
	# `move_and_collide()` depenetration recovery from masking the yaw-only
	# bound: with the nose steered into the wall, Jolt pushes the body back out
	# every tick and the probe never sees the installed overlap.
	var config := d.make_config()
	var tuning := d.make_tuning()
	tuning.yaw_gain_grip = GENTLE_YAW_GAIN_GRIP
	var wall_spec := {
		"point": GENTLE_YAW_WALL_POINT,
		"yaw_deg": -90.0,
		"thickness_m": WALL_THICKNESS_M,
		"width_m": WALL_WIDTH_M,
	}
	var world := await _build_world(config, wall_spec)
	var state := d.make_state(
		Vector2.ZERO, Vector2(0.0, GENTLE_YAW_FORWARD_SPEED_M_S), 0.0
	)
	await _place_body(world, state, d.BODY_SUPPORT_Y)
	var start_pose := world.body.global_transform
	var commands: Array = []
	for _index in range(GENTLE_YAW_TICKS):
		commands.append(d.make_steer_command(-1.0, 0.0))
	var records := await _drive(world, state, commands, tuning, config)
	d.check(records.size() == GENTLE_YAW_TICKS, "gentle: %d ticks driven" % GENTLE_YAW_TICKS)

	var hull_half_width := world.hull_shape.size.x * 0.5
	var hull_half_length := world.hull_shape.size.z * 0.5
	var skip_threshold_rad := (
		config.orientation_contact_tolerance_m
		/ (0.5 * world.hull_shape.size.length())
	)
	var saw_constraint := false
	var first_constraint_tick := -1
	var refusals := 0
	var worst_signed := 0.0
	var max_committed_heading := 0.0
	var max_abs_proposed_yaw_delta := 0.0
	for index in range(records.size()):
		var result = records[index]["result"]
		var label := "gentle tick %d" % (index + 1)
		max_abs_proposed_yaw_delta = maxf(
			max_abs_proposed_yaw_delta, absf(result.motor_yaw_delta_rad)
		)
		if result.status != AdapterScript.Status.COMMITTED:
			refusals += 1
			d.check(
				result.status == AdapterScript.Status.REFUSED_ORIENTATION,
				"%s: unexpected refusal %s (%s)"
				% [label, result.status, result.rejection_reason]
			)
			d.check(
				result.committed_state == null,
				"%s: refusal exposes no committed state" % label
			)
			var expected_pose: Transform3D = (
				start_pose if index == 0 else records[index - 1]["pose"]
			)
			d.check(
				records[index]["pose"].is_equal_approx(expected_pose),
				"%s: refused tick leaves the body at its pre-tick pose" % label
			)
			continue
		var pose: Transform3D = records[index]["pose"]
		var support := d.box_support_point(
			pose, world.hull_shape.size, -world.wall_normal
		)
		var signed: float = (support - world.wall_point).dot(world.wall_normal)
		worst_signed = minf(worst_signed, signed)
		d.check(
			signed >= -PENETRATION_TOLERANCE_M,
			"%s: hull passed the wall near face by %.6f m" % [label, -signed]
		)
		d.check(
			signed >= -(world.wall_thickness_m + PENETRATION_TOLERANCE_M),
			"%s: hull crossed the %.1f m wall (signed distance %.6f)"
			% [label, world.wall_thickness_m, signed]
		)
		var committed = result.committed_state
		d.check(
			committed != null and committed.is_finite(),
			"%s: finite committed state" % label
		)
		if committed == null:
			continue
		max_committed_heading = maxf(
			max_committed_heading, absf(committed.heading_rad)
		)
		d.check(
			pose.basis.is_equal_approx(
				AdapterScript.basis_from_heading(committed.heading_rad)
			),
			"%s: body basis matches the committed heading" % label
		)
		if result.heading_constrained:
			if not saw_constraint:
				first_constraint_tick = index + 1
			saw_constraint = true

	d.check(
		max_abs_proposed_yaw_delta < skip_threshold_rad,
		"gentle: every proposed yaw delta (max %.9f rad) is below the old skip threshold %.9f rad"
		% [max_abs_proposed_yaw_delta, skip_threshold_rad]
	)
	d.check(
		refusals == 0,
		"gentle: no refusal; the installed-pose bound constrains instead"
	)
	d.check(saw_constraint, "gentle: steering toward the wall constrained the yaw")
	d.check(first_constraint_tick > 0, "gentle: constraint tick recorded")

	# Geometric control for the old skip: the first six proposed yaw deltas, if
	# applied unchecked, rotate the hull's front-right corner past the 3 cm lab
	# gate. Origin drift only adds penetration, so this is a conservative
	# mirror of what the pre-fix code installed.
	var unchecked_heading := 0.0
	for index in range(mini(6, records.size())):
		unchecked_heading += records[index]["result"].motor_yaw_delta_rad
	unchecked_heading = absf(unchecked_heading)
	var unchecked_support_x := (
		hull_half_width * cos(unchecked_heading)
		+ hull_half_length * sin(unchecked_heading)
	)
	var unchecked_penetration := unchecked_support_x - GENTLE_YAW_WALL_POINT.x
	d.check(
		unchecked_penetration > PENETRATION_TOLERANCE_M,
		"gentle control: unchecked yaw would penetrate %.6f m by tick 6, past the %.3f m gate"
		% [unchecked_penetration, PENETRATION_TOLERANCE_M]
	)
	d.check(
		worst_signed >= -PENETRATION_TOLERANCE_M,
		"gentle: worst committed hull plane distance %.6f m stays inside the gate"
		% worst_signed
	)
	measurements["worst_hull_plane_distance_m"] = worst_signed
	measurements["max_committed_heading_rad"] = max_committed_heading
	measurements["max_abs_proposed_yaw_delta_rad"] = max_abs_proposed_yaw_delta
	measurements["old_skip_threshold_rad_per_tick"] = skip_threshold_rad
	measurements["first_constraint_tick"] = first_constraint_tick
	measurements["refusals"] = refusals
	measurements["unchecked_control_penetration_m"] = unchecked_penetration

	# Refusal path: an installed pose already across the wall at the tick-start
	# heading must fail closed without moving the body or exposing a state.
	var overlap_state := d.make_state(
		Vector2(1.0, 0.0), Vector2(0.0, GENTLE_YAW_FORWARD_SPEED_M_S), 0.0
	)
	await _place_body(world, overlap_state, d.BODY_SUPPORT_Y)
	var overlap_pose := world.body.global_transform
	var overlap_result = AdapterScript.step(
		world.body, world.hull_shape, overlap_state,
		d.make_steer_command(-1.0, 0.0), tuning, config
	)
	d.check(
		overlap_result.status == AdapterScript.Status.REFUSED_ORIENTATION,
		"gentle refusal: already-overlapping pose refused (%s)"
		% overlap_result.rejection_reason
	)
	d.check(
		overlap_result.committed_state == null,
		"gentle refusal: no committed state exposed"
	)
	d.check(
		overlap_result.rejection_reason.contains("installed hull overlaps"),
		"gentle refusal: reason names the overlapping installed hull"
	)
	d.check(
		world.body.global_transform.is_equal_approx(overlap_pose),
		"gentle refusal: body pose unchanged"
	)
	await _destroy_world(world)


func _case_yaw_constrained_velocity_policy() -> void:
	# Regression for GPT-6.2 Sol interim finding 3: when the installed-pose
	# probe shortens the proposed yaw, the motor velocity was still published in
	# the fully proposed nose frame. Here a real pinned-Jolt parallel wall leaves
	# the translation chord outside the wall (the car's lateral component points
	# away), but the proposed yaw swings the long hull's right corner into it.
	# The old adapter commits the full proposal velocity and points into the
	# wall; the committed-velocity policy reprojects the same longitudinal and
	# lateral scalars into the applied heading before any wall response.
	var config := d.make_config()
	var tuning := d.make_tuning()
	tuning.yaw_gain_grip = YAW_VELOCITY_STEER_GAIN_GRIP
	tuning.max_yaw_rate_rad_s = YAW_VELOCITY_MAX_YAW_RATE_RAD_S
	tuning.lateral_damping_grip_per_s = 0.0
	var wall_spec := {
		"point": YAW_VELOCITY_WALL_POINT,
		"yaw_deg": -90.0,
		"thickness_m": WALL_THICKNESS_M,
		"width_m": WALL_WIDTH_M,
	}
	var world := await _build_world(config, wall_spec)
	var state := d.make_state(
		Vector2.ZERO,
		Vector2(YAW_VELOCITY_LATERAL_SPEED_M_S, YAW_VELOCITY_FORWARD_SPEED_M_S),
		0.0
	)
	await _place_body(world, state, d.BODY_SUPPORT_Y)
	var commands: Array = []
	for _index in range(YAW_VELOCITY_TICKS):
		commands.append(d.make_steer_command(1.0, 0.0))
	var records := await _drive(world, state, commands, tuning, config)
	d.check(records.size() == YAW_VELOCITY_TICKS, "yawvel: %d ticks driven" % YAW_VELOCITY_TICKS)

	var saw_constraint := false
	var worst_hull_plane_distance := 0.0
	var max_speed_error := 0.0
	var max_reprojection_error := 0.0
	var rejected_inward_speed_sum := 0.0
	for index in range(records.size()):
		var result = records[index]["result"]
		var label := "yawvel tick %d" % (index + 1)
		d.check(result.status == AdapterScript.Status.COMMITTED, "%s: committed" % label)
		if result.committed_state == null:
			continue
		d.check(not result.contact, "%s: translation did not hit the wall" % label)
		d.check(not result.wall_contact, "%s: no wall contact response" % label)
		d.check(result.heading_constrained, "%s: proposed yaw was constrained" % label)
		saw_constraint = true
		var proposed = result.proposed_state
		var committed = result.committed_state
		d.check(committed.is_finite(), "%s: finite committed state" % label)
		d.check(
			not is_equal_approx(committed.heading_rad, proposed.heading_rad),
			"%s: applied heading differs from the full proposal" % label
		)
		var pose: Transform3D = records[index]["pose"]
		d.check(
			pose.basis.is_equal_approx(
				AdapterScript.basis_from_heading(committed.heading_rad)
			),
			"%s: body basis matches the committed heading" % label
		)
		d.check_close(pose.origin.x, committed.position_m.x, 1e-5, "%s: body x mapping" % label)
		d.check_close(pose.origin.z, -committed.position_m.y, 1e-5, "%s: body z mapping" % label)

		# The committed velocity must carry the proposal's longitudinal and
		# lateral scalars in the applied heading, not the full-proposal yaw.
		var proposed_heading: float = proposed.heading_rad
		var committed_heading: float = committed.heading_rad
		var proposed_forward := Vector2(sin(proposed_heading), cos(proposed_heading))
		var proposed_right := Vector2(proposed_forward.y, -proposed_forward.x)
		var longitudinal_speed: float = proposed.velocity_m_s.dot(proposed_forward)
		var lateral_speed: float = proposed.velocity_m_s.dot(proposed_right)
		var applied_forward := Vector2(sin(committed_heading), cos(committed_heading))
		var applied_right := Vector2(applied_forward.y, -applied_forward.x)
		var expected_velocity: Vector2 = (
			applied_forward * longitudinal_speed + applied_right * lateral_speed
		)
		var reprojection_error: float = expected_velocity.distance_to(
			committed.velocity_m_s
		)
		max_reprojection_error = maxf(max_reprojection_error, reprojection_error)
		d.check(
			reprojection_error <= 1e-6,
			"%s: committed velocity equals the reprojection (error %.9f)"
			% [label, reprojection_error]
		)
		var speed_error: float = absf(committed.speed_m_s() - proposed.speed_m_s())
		max_speed_error = maxf(max_speed_error, speed_error)
		d.check(
			speed_error <= 1e-6,
			"%s: speed magnitude preserved (error %.9f)" % [label, speed_error]
		)
		d.check(
			committed.speed_m_s() <= proposed.speed_m_s() + 1e-6,
			"%s: committed speed is bounded by the proposal" % label
		)
		d.check_close(
			float(committed.velocity_m_s.dot(applied_forward)),
			longitudinal_speed,
			1e-6,
			"%s: longitudinal scalar preserved" % label
		)
		d.check_close(
			float(committed.velocity_m_s.dot(applied_right)),
			lateral_speed,
			1e-6,
			"%s: lateral scalar preserved (%.6f m/s)" % [label, lateral_speed]
		)

		# No inward velocity created solely by the rejected yaw fraction. The
		# rejected rotation is exactly the difference between the full proposal
		# and the committed velocity; its wall-normal component must point into
		# the wall, so removing it leaves the committed velocity less inward.
		var proposed_world: Vector3 = AdapterScript.road_vector_to_world(
			proposed.velocity_m_s
		)
		var committed_world: Vector3 = AdapterScript.road_vector_to_world(
			committed.velocity_m_s
		)
		var proposed_normal_speed: float = proposed_world.dot(world.wall_normal)
		var committed_normal_speed: float = committed_world.dot(world.wall_normal)
		var rejected_normal_speed: float = (
			(proposed_world - committed_world).dot(world.wall_normal)
		)
		rejected_inward_speed_sum += rejected_normal_speed
		d.check(
			proposed_normal_speed <= -1e-3,
			"%s: full proposal points into the wall (%.6f m/s)"
			% [label, proposed_normal_speed]
		)
		d.check(
			rejected_normal_speed <= -1e-6,
			"%s: rejected yaw fraction contributed inward speed (%.6f m/s)"
			% [label, rejected_normal_speed]
		)
		d.check(
			committed_normal_speed >= proposed_normal_speed + 1e-6,
			"%s: committed velocity is less inward than the proposal (%.6f vs %.6f)"
			% [label, committed_normal_speed, proposed_normal_speed]
		)
		d.check(
			committed_normal_speed > 0.0,
			"%s: committed velocity has no inward wall component (%.6f m/s)"
			% [label, committed_normal_speed]
		)

		var support: Vector3 = d.box_support_point(
			pose, world.hull_shape.size, -world.wall_normal
		)
		var signed: float = (support - world.wall_point).dot(world.wall_normal)
		worst_hull_plane_distance = minf(worst_hull_plane_distance, signed)
		d.check(
			signed >= -PENETRATION_TOLERANCE_M,
			"%s: hull passed the wall near face by %.6f m" % [label, -signed]
		)
	d.check(saw_constraint, "yawvel: at least one constrained tick")
	measurements["worst_hull_plane_distance_m"] = worst_hull_plane_distance
	measurements["max_reprojection_error_mps"] = max_reprojection_error
	measurements["max_speed_error_mps"] = max_speed_error
	measurements["rejected_inward_speed_sum_mps"] = rejected_inward_speed_sum
	await _destroy_world(world)

	# Clean-ground control: identical steering has no wall, so the yaw is not
	# constrained and the motor velocity must pass through untouched.
	var open_world := await _build_world(config, {})
	var open_state := d.make_state(
		Vector2.ZERO,
		Vector2(YAW_VELOCITY_LATERAL_SPEED_M_S, YAW_VELOCITY_FORWARD_SPEED_M_S),
		0.0
	)
	await _place_body(open_world, open_state, d.BODY_SUPPORT_Y)
	var open_records := await _drive(open_world, open_state, commands, tuning, config)
	var max_open_velocity_error := 0.0
	for index in range(open_records.size()):
		var result = open_records[index]["result"]
		var label := "yawvel open tick %d" % (index + 1)
		d.check(result.status == AdapterScript.Status.COMMITTED, "%s: committed" % label)
		if result.committed_state == null:
			continue
		d.check(not result.heading_constrained, "%s: clear ground does not constrain yaw" % label)
		d.check(
			is_equal_approx(result.committed_state.heading_rad, result.proposed_state.heading_rad),
			"%s: clear ground preserves the proposed yaw" % label
		)
		var error: float = result.committed_state.velocity_m_s.distance_to(
			result.proposed_state.velocity_m_s
		)
		max_open_velocity_error = maxf(max_open_velocity_error, error)
		d.check(
			error <= 1e-12,
			"%s: unconstrained velocity is untouched (error %.9f)" % [label, error]
		)
		d.check_close(
			result.committed_state.speed_m_s(),
			result.proposed_state.speed_m_s(),
			1e-9,
			"%s: speed preserved" % label
		)
	measurements["open_ticks"] = open_records.size()
	measurements["max_open_velocity_error_mps"] = max_open_velocity_error
	await _destroy_world(open_world)


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
	var large_orientation_tolerance := d.make_config()
	large_orientation_tolerance.orientation_contact_tolerance_m = (
		AdapterScript.MAX_ORIENTATION_CONTACT_TOLERANCE_M + 0.01
	)
	d.check(
		not large_orientation_tolerance.is_valid(),
		"workcap: orientation tolerance above absolute cap rejected"
	)
	var collapsed_orientation_probe := d.make_config()
	collapsed_orientation_probe.orientation_contact_tolerance_m = 0.5
	d.check(
		not collapsed_orientation_probe.is_valid(),
		"workcap: orientation tolerance collapsing the hull probe rejected"
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


func _case_wall_response_witness_selection() -> void:
	# Focused deterministic regressions for the authoritative wall-response
	# witness (`has_wall_response_witness`, both world velocities and the
	# collision-time body transform). Contact ordering, frame availability and
	# the degenerate guards are driven through the collision-like fixture the
	# collection seam already supports; the real pinned-Jolt values live in
	# `wall_response_witness_telemetry`.
	var config := d.make_config()
	var adapter := AdapterScript.new()
	var has_selector: bool = adapter.has_method("_select_wall_contact")
	d.check(has_selector, "witness: adapter exposes the wall contact selection helper")
	if not has_selector:
		return

	# --- Source contract guards for the witness sampling point. ----------
	var adapter_source := ""
	if FileAccess.file_exists("res://src/simulation/motor_body_adapter.gd"):
		var source_file := FileAccess.open(
			"res://src/simulation/motor_body_adapter.gd", FileAccess.READ
		)
		adapter_source = source_file.get_as_text()
		source_file.close()
	d.check(not adapter_source.is_empty(), "witness source: adapter source readable")
	d.check(
		adapter_source.contains("wall_transforms.append_array(collected[\"wall_transforms\"])"),
		"witness source: collision-time frames are collected per candidate"
	)
	d.check(
		adapter_source.contains("Transform3D(simulated.basis, simulated.origin + actual)"),
		"witness source: the collected frame is the committed pose at that collision"
	)
	d.check(
		adapter_source.contains("result.has_wall_response_witness = has_wall_response_witness"),
		"witness source: the witness flag is published from the selection result"
	)
	d.check(
		adapter_source.contains(
			"result.wall_pre_response_velocity_world_m_s = witness_pre_velocity"
		),
		"witness source: the pre-response velocity is published from its sample"
	)
	d.check(
		adapter_source.contains(
			"result.wall_post_response_velocity_world_m_s = witness_post_velocity"
		),
		"witness source: the post-response velocity is published from its sample"
	)
	d.check(
		adapter_source.contains("result.wall_contact_transform = witness_transform"),
		"witness source: the contact-time frame is published from the selection"
	)
	var pre_sample_at: int = adapter_source.find("witness_pre_velocity = velocity_world")
	var response_at: int = adapter_source.find("velocity_world = _apply_wall_response(")
	var post_sample_at: int = adapter_source.find("witness_post_velocity = velocity_world")
	var reprojection_at: int = adapter_source.find("committed_velocity_road = _reproject_velocity_road(")
	d.check(
		pre_sample_at >= 0 and response_at >= 0 and post_sample_at >= 0
		and pre_sample_at < response_at and response_at < post_sample_at,
		"witness source: pre is sampled before the response and post after it"
	)
	d.check(
		reprojection_at >= 0 and reprojection_at < pre_sample_at,
		"witness source: pre is sampled after the yaw-constraint reprojection"
	)
	d.check(
		not adapter_source.contains("result.wall_contact_transform = result.committed_transform"),
		"witness source: the frame is never the final tick transform"
	)
	d.check(
		not adapter_source.contains("result.wall_contact_transform = start_transform"),
		"witness source: the frame is never the raw tick-start transform"
	)
	d.check(
		not adapter_source.contains("wall_pre_response_velocity_world_m_s = proposed_motion_m"),
		"witness source: pre is never the total tick displacement"
	)

	var head_on_normal := Vector3(0.0, 0.0, 1.0)
	var oblique_normal := Vector3(0.5, 0.0, 0.8660254)
	var floor_normal := Vector3(0.0, 1.0, 0.0)
	var approach_velocity := Vector3(0.0, 0.0, -20.0)

	# --- Head-on: the whole approach speed is the contact change. --------
	var head_on_point := Vector3(0.9, 0.05, -2.0)
	var head_on_frame := Transform3D(
		AdapterScript.basis_from_heading(0.25), Vector3(1.0, 0.55, -18.1)
	)
	var head_on := SeamCollision.new([head_on_normal], [head_on_point])
	var collected_head_on: Dictionary = adapter.call(
		"_collect_collision_contacts", head_on, config, head_on_frame
	)
	d.check(
		collected_head_on["wall_transforms"].size() == 1,
		"witness head-on: one frame collected for one candidate"
	)
	var chosen_head_on: Dictionary = adapter.call(
		"_select_wall_contact",
		collected_head_on["wall_normals"],
		collected_head_on["wall_points"],
		approach_velocity,
		collected_head_on["wall_transforms"]
	)
	d.check(chosen_head_on["valid"], "witness head-on: valid witness")
	d.check(chosen_head_on["frame_valid"], "witness head-on: usable frame")
	d.check(
		chosen_head_on["transform"] == head_on_frame,
		"witness head-on: frame is the collision-time pose"
	)
	var pre_head_on := approach_velocity
	var post_head_on: Vector3 = AdapterScript._apply_wall_response(
		pre_head_on, chosen_head_on["normal"], config
	)
	d.check(
		post_head_on == Vector3.ZERO,
		"witness head-on: restitution 0 removes the whole inward approach speed"
	)
	var head_on_change: Vector3 = pre_head_on - post_head_on
	d.check_close(head_on_change.length(), 20.0, 1e-9, "witness head-on: change is the approach speed")
	d.check(
		head_on_change.normalized().distance_to(-head_on_normal) <= 1e-6,
		"witness head-on: the change is along the wall normal only"
	)
	d.check(
		AdapterScript.road_vector_to_world(
			AdapterScript.world_vector_to_road(post_head_on)
		) == post_head_on,
		"witness head-on: the post sample round-trips through the committed road state"
	)

	# --- Oblique: only the inward component changes, tangent survives. --
	var oblique_point := Vector3(-3.0, 0.5, 2.0)
	var oblique_frame := Transform3D(
		AdapterScript.basis_from_heading(-0.4), Vector3(-0.5, 0.55, -12.0)
	)
	var oblique := SeamCollision.new([oblique_normal], [oblique_point])
	var collected_oblique: Dictionary = adapter.call(
		"_collect_collision_contacts", oblique, config, oblique_frame
	)
	var chosen_oblique: Dictionary = adapter.call(
		"_select_wall_contact",
		collected_oblique["wall_normals"],
		collected_oblique["wall_points"],
		approach_velocity,
		collected_oblique["wall_transforms"]
	)
	d.check(chosen_oblique["valid"] and chosen_oblique["frame_valid"], "witness oblique: valid witness")
	var pre_oblique := approach_velocity
	var post_oblique: Vector3 = AdapterScript._apply_wall_response(
		pre_oblique, chosen_oblique["normal"], config
	)
	var oblique_change: Vector3 = pre_oblique - post_oblique
	d.check_close(
		oblique_change.length(),
		absf(pre_oblique.dot(oblique_normal)),
		1e-9,
		"witness oblique: change is the inward normal speed"
	)
	d.check(
		oblique_change.normalized().distance_to(-oblique_normal) <= 1e-6,
		"witness oblique: the change is along the wall normal only"
	)
	d.check_close(
		post_oblique.dot(oblique_normal), 0.0, WITNESS_TOLERANCE_MPS,
		"witness oblique: no inward component remains"
	)
	var pre_tangent: Vector3 = (
		pre_oblique - oblique_normal * pre_oblique.dot(oblique_normal)
	)
	var post_tangent: Vector3 = (
		post_oblique - oblique_normal * post_oblique.dot(oblique_normal)
	)
	d.check_close(
		post_tangent.distance_to(pre_tangent), 0.0, WITNESS_TOLERANCE_MPS,
		"witness oblique: tangential speed is untouched by the contact"
	)
	d.check(
		chosen_oblique["point"] == oblique_point
		and chosen_oblique["transform"] == oblique_frame,
		"witness oblique: point and frame come from the same candidate"
	)

	# --- Floor-first/wall-second: point and frame from one candidate. ----
	# Two collision results (two substeps), each with its own contact-time
	# frame. The winner must take both the point and the frame from the
	# collision that reported it.
	var frame_a := Transform3D(
		AdapterScript.basis_from_heading(0.0), Vector3(0.0, 0.55, -3.0)
	)
	var frame_b := Transform3D(
		AdapterScript.basis_from_heading(0.1), Vector3(0.25, 0.55, -2.75)
	)
	var floor_point_a := Vector3(0.0, 0.05, -3.0)
	var wall_point_a := Vector3(0.4, 0.5, -3.0)
	var wall_point_b := Vector3(-0.2, 0.5, -2.75)
	var collision_a := SeamCollision.new(
		[floor_normal, oblique_normal], [floor_point_a, wall_point_a]
	)
	var collision_b := SeamCollision.new([head_on_normal], [wall_point_b])
	var batched_normals: Array = []
	var batched_points: Array = []
	var batched_frames: Array = []
	for pair in [[collision_a, frame_a], [collision_b, frame_b]]:
		var collected: Dictionary = adapter.call(
			"_collect_collision_contacts", pair[0], config, pair[1]
		)
		batched_normals.append_array(collected["wall_normals"])
		batched_points.append_array(collected["wall_points"])
		batched_frames.append_array(collected["wall_transforms"])
	d.check(batched_normals.size() == 2, "witness batch: two wall candidates across substeps")
	d.check(batched_frames.size() == 2, "witness batch: one frame per candidate")
	# Head-on approach: the second substep's head-on wall is most opposed.
	var chosen_batch: Dictionary = adapter.call(
		"_select_wall_contact",
		batched_normals, batched_points, approach_velocity, batched_frames
	)
	d.check(
		chosen_batch["normal"].is_equal_approx(head_on_normal),
		"witness batch: the most-opposed candidate wins"
	)
	d.check(
		chosen_batch["point"] == wall_point_b,
		"witness batch: point comes from the winning substep"
	)
	d.check(
		chosen_batch["transform"] == frame_b,
		"witness batch: frame comes from the winning substep, not the first"
	)
	# Lateral approach: the first substep's oblique wall wins, and its own
	# second contact supplies the point while its own frame supplies the pose.
	var lateral_velocity := Vector3(-20.0, 0.0, 0.0)
	var chosen_lateral: Dictionary = adapter.call(
		"_select_wall_contact",
		batched_normals, batched_points, lateral_velocity, batched_frames
	)
	d.check(
		chosen_lateral["normal"].is_equal_approx(oblique_normal),
		"witness batch: the choice follows the approach velocity"
	)
	d.check(
		chosen_lateral["point"] == wall_point_a,
		"witness batch: point is the winning collision's wall contact, not its floor contact"
	)
	d.check(
		chosen_lateral["point"] != floor_point_a,
		"witness batch: the floor-first contact does not supply the point"
	)
	d.check(
		chosen_lateral["transform"] == frame_a,
		"witness batch: frame is the winning collision's pose"
	)

	# --- Later motion must not move the published frame. ----------------
	# A wall candidate from an early substep keeps its own frame even when a
	# later substep reports a different pose; the frame is never the latest
	# pose in the tick.
	var early_frame := Transform3D(
		AdapterScript.basis_from_heading(0.0), Vector3(0.0, 0.55, -5.0)
	)
	var late_frame := Transform3D(
		AdapterScript.basis_from_heading(0.6), Vector3(0.9, 0.55, -4.0)
	)
	var early_collision := SeamCollision.new([head_on_normal], [wall_point_a])
	var late_collision := SeamCollision.new([floor_normal], [floor_point_a])
	var ordered_normals: Array = []
	var ordered_points: Array = []
	var ordered_frames: Array = []
	for pair in [[early_collision, early_frame], [late_collision, late_frame]]:
		var collected: Dictionary = adapter.call(
			"_collect_collision_contacts", pair[0], config, pair[1]
		)
		ordered_normals.append_array(collected["wall_normals"])
		ordered_points.append_array(collected["wall_points"])
		ordered_frames.append_array(collected["wall_transforms"])
	var chosen_ordered: Dictionary = adapter.call(
		"_select_wall_contact",
		ordered_normals, ordered_points, approach_velocity, ordered_frames
	)
	d.check(chosen_ordered["valid"] and chosen_ordered["frame_valid"], "witness ordering: valid witness")
	d.check(
		chosen_ordered["transform"] == early_frame,
		"witness ordering: the frame is the early collision pose, not the later pose"
	)
	d.check(
		chosen_ordered["transform"] != late_frame,
		"witness ordering: a later substep pose never replaces the contact frame"
	)

	# --- Exact tie keeps the earliest candidate and its frame. ----------
	var tie_frame_a := Transform3D(
		AdapterScript.basis_from_heading(0.2), Vector3(1.0, 0.55, 0.0)
	)
	var tie_frame_b := Transform3D(
		AdapterScript.basis_from_heading(0.9), Vector3(0.0, 0.55, 1.0)
	)
	var tie := SeamCollision.new(
		[Vector3(1.0, 0.0, 0.0), head_on_normal], [wall_point_a, wall_point_b]
	)
	var collected_tie: Dictionary = adapter.call(
		"_collect_collision_contacts", tie, config, tie_frame_a
	)
	var chosen_tie: Dictionary = adapter.call(
		"_select_wall_contact",
		collected_tie["wall_normals"],
		collected_tie["wall_points"],
		Vector3(-10.0, 0.0, -10.0),
		[tie_frame_a, tie_frame_b]
	)
	d.check(
		chosen_tie["normal"].is_equal_approx(Vector3(1.0, 0.0, 0.0)),
		"witness tie: earliest normal kept"
	)
	d.check(
		chosen_tie["transform"] == tie_frame_a,
		"witness tie: frame follows the earliest candidate"
	)

	# --- Degenerate, nonfinite and unavailable candidates. --------------
	var vertical_frame := Transform3D(
		AdapterScript.basis_from_heading(0.0), Vector3(1.0, 2.0, 3.0)
	)
	var degenerate: Dictionary = adapter.call(
		"_select_wall_contact",
		[Vector3(0.0, 1.0, 0.0)], [Vector3(1.0, 2.0, 3.0)], approach_velocity,
		[vertical_frame]
	)
	d.check(not degenerate["valid"], "witness degenerate: no valid witness")
	d.check(not degenerate["frame_valid"], "witness degenerate: no usable frame")
	d.check(
		degenerate["transform"] == Transform3D(),
		"witness degenerate: default transform"
	)
	var nonfinite_point: Dictionary = adapter.call(
		"_select_wall_contact",
		[head_on_normal], [Vector3(NAN, 0.0, 0.0)], approach_velocity, [vertical_frame]
	)
	d.check(not nonfinite_point["valid"], "witness nonfinite point: no valid witness")
	d.check(
		nonfinite_point["transform"] == Transform3D(),
		"witness nonfinite point: default transform"
	)
	var nonfinite_frame := Transform3D(
		AdapterScript.basis_from_heading(0.0), Vector3(NAN, 0.55, 0.0)
	)
	var nonfinite_frame_result: Dictionary = adapter.call(
		"_select_wall_contact",
		[head_on_normal], [head_on_point], approach_velocity, [nonfinite_frame]
	)
	d.check(
		nonfinite_frame_result["valid"],
		"witness nonfinite frame: the point witness itself is still valid"
	)
	d.check(
		not nonfinite_frame_result["frame_valid"],
		"witness nonfinite frame: the frame is rejected"
	)
	d.check(
		nonfinite_frame_result["transform"] == Transform3D(),
		"witness nonfinite frame: default transform"
	)
	var unavailable: Dictionary = adapter.call(
		"_select_wall_contact",
		[head_on_normal], [head_on_point], approach_velocity
	)
	d.check(unavailable["valid"], "witness unavailable frame: point witness unchanged")
	d.check(
		not unavailable["frame_valid"],
		"witness unavailable frame: no frame was collected"
	)
	d.check(
		unavailable["transform"] == Transform3D(),
		"witness unavailable frame: default transform, never an identity pose claim"
	)
	var empty: Dictionary = adapter.call(
		"_select_wall_contact", [], [], approach_velocity, []
	)
	d.check(not empty["valid"], "witness empty: no valid witness")
	d.check(not empty["frame_valid"], "witness empty: no usable frame")

	# --- A finite transform guard rejects a collapsed basis. ------------
	var collapsed_basis := Basis()
	collapsed_basis.x = Vector3.ZERO
	var collapsed_frame := Transform3D(collapsed_basis, Vector3(0.0, 0.55, 0.0))
	d.check(
		not adapter.call("_finite_transform", collapsed_frame),
		"witness frame guard: a degenerate basis is not a usable pose"
	)
	d.check(
		adapter.call("_finite_transform", head_on_frame),
		"witness frame guard: a laboratory pose is usable"
	)

	# --- Yaw-only reprojection never enters the pre sample. -------------
	# The pre sample is taken after the proposal's scalars are reprojected
	# into the applied heading. With a shortened yaw the reprojection changes
	# the world velocity, and that change has a component along the wall
	# normal, so sampling before the reprojection would publish a velocity
	# that is not the one the response saw.
	var proposed_heading := 0.331128
	var applied_heading := 0.041016
	var proposal_velocity_road := Vector2(1.123058, 1.728798)
	var reprojected_road: Vector2 = adapter.call(
		"_reproject_velocity_road",
		proposal_velocity_road, proposed_heading, applied_heading
	)
	var pre_reprojected: Vector3 = AdapterScript.road_vector_to_world(reprojected_road)
	var pre_unreprojected: Vector3 = AdapterScript.road_vector_to_world(
		proposal_velocity_road
	)
	var yaw_only_difference: Vector3 = pre_unreprojected - pre_reprojected
	d.check(
		yaw_only_difference.length() > 1e-3,
		"witness yaw: the rejected yaw fraction moves the world velocity (%.6f m/s)"
		% yaw_only_difference.length()
	)
	d.check(
		absf(yaw_only_difference.dot(head_on_normal)) > 1e-3,
		"witness yaw: the rejected yaw fraction has a wall-normal component"
	)
	var wall_normal_for_yaw := Vector3(-1.0, 0.0, 0.0)
	var post_reprojected: Vector3 = AdapterScript._apply_wall_response(
		pre_reprojected, wall_normal_for_yaw, config
	)
	var contact_change: Vector3 = pre_reprojected - post_reprojected
	_check_parallel(contact_change, wall_normal_for_yaw, "witness yaw: the contact change is along the wall normal")
	var yaw_only_tangent: Vector3 = yaw_only_difference - wall_normal_for_yaw * (
		yaw_only_difference.dot(wall_normal_for_yaw)
	)
	d.check(
		yaw_only_tangent.length() > 1e-3,
		"witness yaw control: an unreprojected pre sample would add a non-normal change"
	)
	measurements["witness_yaw_only_speed_mps"] = yaw_only_difference.length()
	measurements["witness_yaw_only_normal_speed_mps"] = yaw_only_difference.dot(
		wall_normal_for_yaw
	)
	measurements["witness_fixture_valid"] = (
		1
		if (
			chosen_head_on["frame_valid"]
			and chosen_oblique["frame_valid"]
			and chosen_batch["frame_valid"]
			and chosen_lateral["frame_valid"]
			and chosen_ordered["frame_valid"]
		)
		else 0
	)


func _case_wall_response_witness_telemetry() -> void:
	# Real pinned-Jolt Result telemetry for the wall-response witness. Open
	# ground and refusals publish no witness; a head-on, an oblique and a
	# yaw-constrained wall hit publish pre/post velocities whose only
	# difference is the contact response, plus the collision-time body pose.
	var config := d.make_config()
	var tuning := d.make_tuning()

	# --- Committed no-wall tick: no witness. -----------------------------
	var open_world := await _build_world(config, {})
	var open_state := d.make_state(Vector2.ZERO, Vector2(0.0, 20.0), 0.0)
	await _place_body(open_world, open_state, d.BODY_SUPPORT_Y)
	var open_result = AdapterScript.step(
		open_world.body, open_world.hull_shape, open_state,
		d.make_idle_command(), tuning, config
	)
	d.check(open_result.status == AdapterScript.Status.COMMITTED, "witness open: committed")
	d.check(not open_result.contact, "witness open: no contact")
	d.check(
		not open_result.has_wall_response_witness,
		"witness open: no response witness flag"
	)
	d.check(
		open_result.wall_pre_response_velocity_world_m_s == Vector3.ZERO,
		"witness open: zero pre-response velocity"
	)
	d.check(
		open_result.wall_post_response_velocity_world_m_s == Vector3.ZERO,
		"witness open: zero post-response velocity"
	)
	d.check(
		open_result.wall_contact_transform == Transform3D(),
		"witness open: default contact transform"
	)
	await _destroy_world(open_world)

	# --- Refused ticks must not publish a witness. -----------------------
	var refuse_world := await _build_world(config, {
		"point": Vector3(0.0, 2.0, -4.0),
		"yaw_deg": 0.0,
		"thickness_m": WALL_THICKNESS_M,
		"width_m": WALL_WIDTH_M,
	})
	var fast_state := d.make_state(Vector2.ZERO, Vector2(0.0, 300.0), 0.0)
	await _place_body(refuse_world, fast_state, d.BODY_SUPPORT_Y)
	var refuse_pose := refuse_world.body.global_transform
	var refused = AdapterScript.step(
		refuse_world.body, refuse_world.hull_shape, fast_state,
		d.make_idle_command(), tuning, config
	)
	d.check(
		refused.status == AdapterScript.Status.REFUSED_MOTION_BOUND,
		"witness refusal: over-envelope tick refused"
	)
	d.check(
		not refused.has_wall_response_witness,
		"witness refusal: no response witness flag"
	)
	d.check(
		refused.wall_pre_response_velocity_world_m_s == Vector3.ZERO
		and refused.wall_post_response_velocity_world_m_s == Vector3.ZERO,
		"witness refusal: zero velocities"
	)
	d.check(
		refused.wall_contact_transform == Transform3D(),
		"witness refusal: default contact transform"
	)
	d.check(
		refuse_world.body.global_transform.is_equal_approx(refuse_pose),
		"witness refusal: body transform unchanged"
	)
	# Invalid input is rejected before the body is read at all.
	var invalid_pose := refuse_world.body.global_transform
	var nonfinite_state := d.make_state(Vector2.ZERO, Vector2(0.0, 10.0), 0.0)
	nonfinite_state.position_m = Vector2(NAN, 0.0)
	var rejected = AdapterScript.step(
		refuse_world.body, refuse_world.hull_shape, nonfinite_state,
		d.make_idle_command(), tuning, config
	)
	d.check(
		rejected.status == AdapterScript.Status.REJECTED_INVALID_INPUT,
		"witness rejection: nonfinite state rejected"
	)
	d.check(
		not rejected.has_wall_response_witness
		and rejected.wall_pre_response_velocity_world_m_s == Vector3.ZERO
		and rejected.wall_post_response_velocity_world_m_s == Vector3.ZERO
		and rejected.wall_contact_transform == Transform3D(),
		"witness rejection: no witness published"
	)
	d.check(
		refuse_world.body.global_transform.is_equal_approx(invalid_pose),
		"witness rejection: body transform unchanged"
	)
	await _destroy_world(refuse_world)

	# --- Head-on wall: the whole approach speed is the contact change. ---
	var head_on_world := await _build_world(config, {
		"point": Vector3(0.0, 2.0, STRAIGHT_WALL_Z),
		"yaw_deg": 0.0,
		"thickness_m": WALL_THICKNESS_M,
		"width_m": WALL_WIDTH_M,
	})
	var head_on_state := d.make_state(Vector2.ZERO, Vector2(0.0, 30.0), 0.0)
	await _place_body(head_on_world, head_on_state, d.BODY_SUPPORT_Y)
	var head_on_commands: Array = []
	for _index in range(60):
		head_on_commands.append(d.make_idle_command())
	var head_on_records := await _drive(
		head_on_world, head_on_state, head_on_commands, tuning, config
	)
	var head_on_contact := _first_contact_index(head_on_records)
	d.check(head_on_contact > 0, "witness head-on: wall contact occurred")
	if head_on_contact >= 0:
		var impact = head_on_records[head_on_contact]["result"]
		var state_in = head_on_records[head_on_contact]["state_in"]
		_assert_wall_response_witness(
			head_on_world, impact, state_in, config, "witness head-on", head_on_contact
		)
		var pre: Vector3 = impact.wall_pre_response_velocity_world_m_s
		var post: Vector3 = impact.wall_post_response_velocity_world_m_s
		_check_witness_change_along_normal(
			pre, post, impact.wall_contact_normal, "witness head-on"
		)
		# A head-on hit at restitution 0 leaves no forward speed at all.
		d.check_close(post.length(), 0.0, WITNESS_TOLERANCE_MPS, "witness head-on: no speed survives a head-on hit")
		d.check_close((pre - post).length(), pre.length(), WITNESS_TOLERANCE_MPS,
			"witness head-on: the contact change is the approach speed"
		)
		# The frame is the body pose at the collision, not the contact point:
		# the origin sits half a hull length behind the wall plane at the
		# support height, while the published point lies on the wall plane.
		var frame: Transform3D = impact.wall_contact_transform
		var plane_distance: float = (frame.origin - head_on_world.wall_point).dot(
			head_on_world.wall_normal
		)
		d.check_close(plane_distance, head_on_world.hull_shape.size.z * 0.5, 1e-3,
			"witness head-on: frame origin is the body pose half a hull behind the wall"
		)
		d.check_close(frame.origin.y, d.BODY_SUPPORT_Y, WITNESS_TOLERANCE_MPS,
			"witness head-on: frame origin keeps the support height"
		)
		d.check(
			absf(frame.origin.y - impact.wall_contact_point.y) > 0.1,
			"witness head-on: the frame is not the contact point"
		)
		d.check(
			frame.basis.is_equal_approx(
				AdapterScript.basis_from_heading(state_in.heading_rad)
			),
			"witness head-on: frame basis is the tick-start sweep basis"
		)
		d.check(
			impact.substeps >= 1,
			"witness head-on: contact tick used the bounded sweep"
		)
		measurements["witness_head_on_plane_distance_m"] = plane_distance
		measurements["witness_head_on_frame_origin"] = frame.origin
		measurements["witness_head_on_pre_speed_mps"] = pre.length()
	await _destroy_world(head_on_world)

	# --- Oblique wall: tangent survives, only the inward part changes. ---
	var oblique_world := await _build_world(config, {
		"point": OBLIQUE_WALL_POINT,
		"yaw_deg": 30.0,
		"thickness_m": WALL_THICKNESS_M,
		"width_m": WALL_WIDTH_M,
	})
	var oblique_state := d.make_state(Vector2.ZERO, Vector2(0.0, 30.0), 0.0)
	await _place_body(oblique_world, oblique_state, d.BODY_SUPPORT_Y)
	var oblique_commands: Array = []
	for _index in range(60):
		oblique_commands.append(d.make_idle_command())
	var oblique_records := await _drive(
		oblique_world, oblique_state, oblique_commands, tuning, config
	)
	var oblique_contact := _first_contact_index(oblique_records)
	d.check(oblique_contact > 0, "witness oblique: wall contact occurred")
	if oblique_contact >= 0:
		var impact = oblique_records[oblique_contact]["result"]
		var state_in = oblique_records[oblique_contact]["state_in"]
		_assert_wall_response_witness(
			oblique_world, impact, state_in, config, "witness oblique", oblique_contact
		)
		var pre: Vector3 = impact.wall_pre_response_velocity_world_m_s
		var post: Vector3 = impact.wall_post_response_velocity_world_m_s
		_check_witness_change_along_normal(
			pre, post, impact.wall_contact_normal, "witness oblique"
		)
		var normal: Vector3 = impact.wall_contact_normal.normalized()
		var pre_tangent: Vector3 = pre - normal * pre.dot(normal)
		var post_tangent: Vector3 = post - normal * post.dot(normal)
		d.check_close(post_tangent.distance_to(pre_tangent), 0.0, WITNESS_TOLERANCE_MPS,
			"witness oblique: tangential speed survives the contact"
		)
		d.check_close(post.dot(normal), 0.0, WITNESS_TOLERANCE_MPS,
			"witness oblique: no inward component remains"
		)
		measurements["witness_oblique_pre_speed_mps"] = pre.length()
		measurements["witness_oblique_post_speed_mps"] = post.length()
	await _destroy_world(oblique_world)

	# --- Yaw-constrained wall: pre excludes the yaw-only reprojection. ---
	# A parallel wall 5 cm from the hull's right side. The lateral component
	# drives the car into the wall while full opposite lock swings the long
	# hull's corner into it, so the installed-pose probe constrains the yaw on
	# the same tick the translation reaches the wall.
	var yaw_world := await _build_world(config, {
		"point": YAW_VELOCITY_WALL_POINT,
		"yaw_deg": -90.0,
		"thickness_m": WALL_THICKNESS_M,
		"width_m": WALL_WIDTH_M,
	})
	var yaw_tuning := d.make_tuning()
	yaw_tuning.yaw_gain_grip = YAW_VELOCITY_STEER_GAIN_GRIP
	yaw_tuning.max_yaw_rate_rad_s = YAW_VELOCITY_MAX_YAW_RATE_RAD_S
	yaw_tuning.lateral_damping_grip_per_s = 0.0
	var yaw_state := d.make_state(
		Vector2.ZERO,
		Vector2(YAW_WITNESS_LATERAL_SPEED_M_S, YAW_VELOCITY_FORWARD_SPEED_M_S),
		0.0
	)
	await _place_body(yaw_world, yaw_state, d.BODY_SUPPORT_Y)
	var yaw_commands: Array = []
	for _index in range(YAW_WITNESS_TICKS):
		yaw_commands.append(d.make_steer_command(1.0, 0.0))
	var yaw_records := await _drive(yaw_world, yaw_state, yaw_commands, yaw_tuning, config)
	d.check(yaw_records.size() == YAW_WITNESS_TICKS, "witness yaw: %d ticks driven" % YAW_WITNESS_TICKS)

	var constrained_wall_tick := -1
	for index in range(yaw_records.size()):
		var result = yaw_records[index]["result"]
		if (
			result.status == AdapterScript.Status.COMMITTED
			and result.heading_constrained
			and result.wall_contact
			and result.has_wall_response_witness
		):
			constrained_wall_tick = index
			break
	d.check(
		constrained_wall_tick >= 0,
		"witness yaw: a constrained tick also reported a wall-response witness"
	)
	var max_yaw_only_speed := 0.0
	var max_reprojection_error := 0.0
	var first_contact_frame := Transform3D()
	for index in range(yaw_records.size()):
		var result = yaw_records[index]["result"]
		if not result.wall_contact or not result.has_wall_response_witness:
			continue
		var state_in = yaw_records[index]["state_in"]
		var label := "witness yaw tick %d" % (index + 1)
		d.check(
			result.status == AdapterScript.Status.COMMITTED,
			"%s: committed" % label
		)
		_assert_wall_response_witness(
			yaw_world, result, state_in, config, label, index
		)
		var pre: Vector3 = result.wall_pre_response_velocity_world_m_s
		var post: Vector3 = result.wall_post_response_velocity_world_m_s
		_check_witness_change_along_normal(
			pre, post, result.wall_contact_normal, label
		)

		# The pre sample must be the reprojected velocity, not the raw motor
		# proposal: the probe refused part of the yaw, and publishing that part
		# would put a velocity into the witness that the response never saw.
		var proposed = result.proposed_state
		var committed = result.committed_state
		var proposed_heading: float = proposed.heading_rad
		var applied_heading: float = committed.heading_rad
		var expected_road: Vector2 = AdapterScript._reproject_velocity_road(
			proposed.velocity_m_s, proposed_heading, applied_heading
		)
		var expected_pre: Vector3 = AdapterScript.road_vector_to_world(expected_road)
		var reprojection_error: float = expected_pre.distance_to(pre)
		max_reprojection_error = maxf(max_reprojection_error, reprojection_error)
		d.check(
			reprojection_error <= 1e-9,
			"%s: pre equals the reprojected proposal velocity (error %.12f)"
			% [label, reprojection_error]
		)
		if result.heading_constrained:
			var raw_pre: Vector3 = AdapterScript.road_vector_to_world(
				proposed.velocity_m_s
			)
			var yaw_only: Vector3 = raw_pre - pre
			max_yaw_only_speed = maxf(max_yaw_only_speed, yaw_only.length())
			d.check(
				yaw_only.length() > 1e-3,
				"%s: the rejected yaw fraction moved the velocity (%.6f m/s)"
				% [label, yaw_only.length()]
			)
			d.check(
				absf(yaw_only.dot(result.wall_contact_normal.normalized())) > 1e-3,
				"%s: the rejected yaw fraction has a wall-normal component" % label
			)

		# The contact-time frame carries the tick-start basis, so a tick that
		# rotated the hull still publishes the pose at the collision.
		var frame: Transform3D = result.wall_contact_transform
		d.check(
			frame.basis.is_equal_approx(
				AdapterScript.basis_from_heading(state_in.heading_rad)
			),
			"%s: frame basis is the tick-start sweep basis" % label
		)
		if not is_equal_approx(applied_heading, state_in.heading_rad):
			d.check(
				not frame.basis.is_equal_approx(result.committed_transform.basis),
				"%s: the frame is not the finalized tick pose" % label
			)
		d.check(
			frame.basis.is_equal_approx(result.start_transform.basis),
			"%s: the frame basis is the sweep basis of this tick" % label
		)
		d.check_close(frame.origin.y, d.BODY_SUPPORT_Y, WITNESS_TOLERANCE_MPS,
			"%s: frame origin keeps the support height" % label
		)
		if index == constrained_wall_tick:
			first_contact_frame = frame
	d.check(
		constrained_wall_tick < 0 or first_contact_frame != Transform3D(),
		"witness yaw: the constrained tick published a contact frame"
	)
	measurements["witness_yaw_constrained_tick"] = constrained_wall_tick + 1
	measurements["witness_yaw_max_reprojection_error_mps"] = max_reprojection_error
	measurements["witness_yaw_max_yaw_only_speed_mps"] = max_yaw_only_speed

	# The witness frame is a contact-time snapshot: later motion and rotation
	# must not move it.
	if constrained_wall_tick >= 0:
		var later_pose: Transform3D = yaw_records[-1]["pose"]
		d.check(
			not first_contact_frame.is_equal_approx(later_pose),
			"witness yaw: the contact frame differs from the pose after later motion"
		)
		d.check(
			not first_contact_frame.origin.is_equal_approx(later_pose.origin),
			"witness yaw: later translation moves the body away from the contact frame"
		)
		measurements["witness_yaw_later_travel_m"] = first_contact_frame.origin.distance_to(
			later_pose.origin
		)
	await _destroy_world(yaw_world)


## Shared assertions for one committed wall-contact witness. Verifies the
## flag, finiteness, the documented pre/post relation against the committed
## road state, and that the witness is a body pose rather than a wall point.
func _assert_wall_response_witness(
	world: BodyLabWorld,
	impact,
	state_in,
	config,
	label: String,
	tick_index: int
) -> void:
	d.check(
		impact.status == AdapterScript.Status.COMMITTED,
		"%s: committed" % label
	)
	d.check(impact.wall_contact, "%s: wall contact classified" % label)
	d.check(impact.has_wall_response_witness, "%s: response witness flag set" % label)
	var pre: Vector3 = impact.wall_pre_response_velocity_world_m_s
	var post: Vector3 = impact.wall_post_response_velocity_world_m_s
	d.check_vector_finite(pre, "%s: finite pre-response velocity" % label)
	d.check_vector_finite(post, "%s: finite post-response velocity" % label)
	d.check_vector_finite(
		impact.wall_contact_transform.origin, "%s: finite contact frame origin" % label
	)

	# The post sample is the velocity the committed state stores, mapped back
	# to world axes. The road-plane state keeps no vertical component, so the
	# comparison is exact for the planar laboratory velocities.
	var committed_world: Vector3 = AdapterScript.road_vector_to_world(
		impact.committed_state.velocity_m_s
	)
	if absf(post.y) <= 1e-12:
		d.check(
			committed_world == post,
			"%s: post equals the committed state velocity in world axes" % label
		)
	else:
		d.check_close(
			committed_world.distance_to(post), absf(post.y), 1e-9,
			"%s: post matches the committed state up to the dropped vertical part" % label
		)

	# Post is exactly the documented response applied to pre.
	var expected_post: Vector3 = AdapterScript._apply_wall_response(
		pre, impact.wall_contact_normal, config
	)
	d.check(
		expected_post.distance_to(post) <= 1e-9,
		"%s: post is the wall response applied to pre (error %.12f)"
		% [label, expected_post.distance_to(post)]
	)

	# Pre is never the motor proposal on a tick whose yaw was constrained, and
	# it is never derived from the tick's travel.
	d.check(
		pre.distance_to(impact.proposed_motion_m) > 1e-6 or pre == Vector3.ZERO,
		"%s: pre is a velocity, not the tick displacement" % label
	)
	if impact.heading_constrained:
		var raw_pre: Vector3 = AdapterScript.road_vector_to_world(
			impact.proposed_state.velocity_m_s
		)
		d.check(
			raw_pre.distance_to(pre) > 1e-6,
			"%s: pre excludes the rejected yaw fraction" % label
		)

	# The frame is a body pose: its origin sits inside the hull envelope of the
	# contact point, never on the wall plane itself.
	var plane_distance: float = (impact.wall_contact_transform.origin - world.wall_point).dot(
		world.wall_normal
	)
	d.check(
		plane_distance > 0.0,
		"%s: the contact frame origin is behind the wall plane (%.6f m)" % [label, plane_distance]
	)
	d.check(
		plane_distance < world.hull_shape.size.length(),
		"%s: the contact frame origin is within one hull diagonal of the wall" % label
	)
	d.check(
		impact.wall_contact_transform.basis.is_equal_approx(
			impact.start_transform.basis
		),
		"%s: the contact frame uses the tick-start sweep basis" % label
	)
	measurements["%s_plane_distance_m" % label.replace(" ", "_")] = plane_distance


## Assert the pre/post difference is exactly the inward normal component.
func _check_witness_change_along_normal(
	pre: Vector3,
	post: Vector3,
	normal: Vector3,
	label: String
) -> void:
	var change: Vector3 = pre - post
	var projected: Vector3 = AdapterScript._road_plane_unit_normal(normal)
	d.check(
		projected != Vector3.ZERO,
		"%s: the response normal has a road-plane projection" % label
	)
	_check_parallel(change, projected, "%s: the contact change is along the wall normal" % label)
	d.check_close(change.length(), absf(pre.dot(projected)), WITNESS_TOLERANCE_MPS,
		"%s: the contact change is the inward normal speed" % label
	)
	d.check_close(post.dot(projected), 0.0, WITNESS_TOLERANCE_MPS,
		"%s: no inward component remains" % label
	)


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
