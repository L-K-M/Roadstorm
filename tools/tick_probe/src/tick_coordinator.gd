extends Node3D
## Minimal Roadstorm M0.8 simulation coordinator.
##
## Owns one logical 60 Hz tick for one probe car in a real Godot physics world.
## It is deliberately smaller than the planned M1 motor: it demonstrates the
## tick/reset/query/wait mechanics the motor and training bridge depend on.
##
## Contract implemented here (TECHNICAL_DESIGN.md "Fixed tick and movement
## ownership", PLAN.md M0.8, OPPONENT_AI.md step semantics):
##   * a nonterminal training request consumes exactly twelve logical ticks;
##   * termination/truncation stops at the first ending tick and reports the
##     actual elapsed tick count;
##   * after a request the authoritative world is frozen until the next request
##     (trainer wait consumes zero logical ticks);
##   * reset restores pose, rotation, counters, RNG stream, events and stats;
##   * every tick uses a nonmutating swept query before the single committed
##     CharacterBody3D.move_and_collide() call, and records the discrepancy.

signal step_finished(result: Dictionary)

const DT := 1.0 / 60.0
const DEFAULT_TICKS_PER_STEP := 12
const SUBSTEP_MAX_LEN := 0.25
const SAFE_MARGIN := 0.08
## cast_motion query margin. Must stay 0: see _execute_tick. The body's own
## safe_margin is unchanged; only the nonmutating predictor casts the real hull.
const CAST_QUERY_MARGIN := 0.0
const MAX_SUBSTEPS := 16
const SEED := 20261126
const MAX_TICK_LOG := 20000

# Scenario configuration, set by the driver before reset().
var speed_mps := 10.0
var finish_z := INF ## finite enables termination when body z <= finish_z
var max_ticks := 1000000 ## scenario truncation limit
var wall_face_z := NAN ## finite enables a static wall whose near face is at z

var body: CharacterBody3D
var hull_shape: BoxShape3D
var initial_transform := Transform3D()
var rng := RandomNumberGenerator.new()

var tick_count := 0
var commanded_distance := 0.0
var rng_draws: Array[float] = []
var events: Array[Dictionary] = []
var episode_terminal := "none"
var last_step_terminal := "none"

var engine_physics_frames := 0
var frozen_physics_frames := 0
var delta_min := -1.0
var delta_max := -1.0

var max_prediction_error := 0.0
var max_test_move_error := 0.0
var max_commit_discrepancy := 0.0
var total_substeps := 0
var max_substep_len := 0.0
var tick_log: Array[Dictionary] = []

var _budget := 0
var _requested_ticks := 0
var _step_elapsed := 0
var _freeze := false
var _pending_result := false
var _result := {}
var _last_grounded := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.seed = SEED
	_build_world()
	initial_transform = body.transform
	get_tree().physics_frame.connect(_on_engine_physics_frame)


static func _is_finite(value: float) -> bool:
	return not is_inf(value) and not is_nan(value)


func _on_engine_physics_frame() -> void:
	engine_physics_frames += 1
	if get_tree().paused:
		frozen_physics_frames += 1


## Rebuild the physics world for a new scenario configuration.
func configure(p_speed_mps: float, p_finish_z: float, p_max_ticks: int, p_wall_face_z: float) -> void:
	set_frozen(false)
	for child in get_children():
		remove_child(child)
		child.free()
	speed_mps = p_speed_mps
	finish_z = p_finish_z
	max_ticks = p_max_ticks
	wall_face_z = p_wall_face_z
	_reset_state()
	_build_world()
	initial_transform = body.transform


func _build_world() -> void:
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(400, 1, 400)
	ground_shape.shape = ground_box
	ground.add_child(ground_shape)
	ground.position = Vector3(0, -0.5, 0)
	add_child(ground)

	if _is_finite(wall_face_z):
		var wall := StaticBody3D.new()
		var wall_shape := CollisionShape3D.new()
		var wall_box := BoxShape3D.new()
		wall_box.size = Vector3(20, 4, 1)
		wall_shape.shape = wall_box
		wall.add_child(wall_shape)
		# Near face at wall_face_z; box is 1 m thick behind it.
		wall.position = Vector3(0, 2, wall_face_z - 0.5)
		add_child(wall)

	body = CharacterBody3D.new()
	var body_shape := CollisionShape3D.new()
	hull_shape = BoxShape3D.new()
	hull_shape.size = Vector3(1.8, 1.0, 3.8)
	body_shape.shape = hull_shape
	body.add_child(body_shape)
	body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	body.safe_margin = SAFE_MARGIN
	body.position = Vector3(0, 0.5, 0)
	add_child(body)


func _reset_state() -> void:
	tick_count = 0
	commanded_distance = 0.0
	rng_draws.clear()
	events.clear()
	episode_terminal = "none"
	last_step_terminal = "none"
	engine_physics_frames = 0
	frozen_physics_frames = 0
	delta_min = -1.0
	delta_max = -1.0
	max_prediction_error = 0.0
	max_test_move_error = 0.0
	max_commit_discrepancy = 0.0
	total_substeps = 0
	max_substep_len = 0.0
	tick_log.clear()
	_budget = 0
	_requested_ticks = 0
	_step_elapsed = 0
	_freeze = false
	_pending_result = false
	rng.seed = SEED


## Complete reset: world pose, clocks, RNG, history, events and counters.
func reset() -> Dictionary:
	set_frozen(false)
	_reset_state()
	_build_world_pose()
	return observe()


func _build_world_pose() -> void:
	body.global_transform = initial_transform
	_last_grounded = _probe_grounded()


func set_frozen(frozen: bool) -> void:
	_freeze = frozen
	get_tree().paused = frozen


func begin_step(requested_ticks: int = DEFAULT_TICKS_PER_STEP) -> void:
	if episode_terminal != "none":
		_emit_result(requested_ticks, 0, episode_terminal)
		return
	_requested_ticks = maxi(0, requested_ticks)
	_budget = _requested_ticks
	_step_elapsed = 0
	_pending_result = false
	if _freeze or get_tree().paused:
		set_frozen(false)
	if _requested_ticks == 0:
		_emit_result(0, 0, "none")


func has_pending_result() -> bool:
	return _pending_result


func take_result() -> Dictionary:
	_pending_result = false
	var result := {}
	for key in ["schema", "requested_ticks", "elapsed_ticks", "terminal", "tick_count", "sim_time", "observation"]:
		result[key] = _result[key]
	return result


func observe() -> Dictionary:
	var p := body.global_position
	return {
		"schema": "roadstorm.tick_probe.obs.v1",
		"tick": tick_count,
		"sim_time": tick_count * DT,
		"position": [p.x, p.y, p.z],
		"rotation_y_deg": rad_to_deg(body.global_rotation.y),
		"grounded": _last_grounded,
		"progress_m": -p.z,
		"terminal": episode_terminal,
	}


func _physics_process(delta: float) -> void:
	# A freeze requested by the previous tick must hold even if the engine
	# delivers one more callback before SceneTree.paused takes effect.
	if _freeze or _budget <= 0 or episode_terminal != "none":
		return
	if delta_min < 0.0 or delta < delta_min:
		delta_min = delta
	if delta > delta_max:
		delta_max = delta
	_execute_tick(delta)
	tick_count += 1
	_step_elapsed += 1
	_budget -= 1
	commanded_distance += speed_mps * DT

	var terminal := "none"
	if _is_finite(finish_z) and body.global_position.z <= finish_z:
		terminal = "terminated"
	elif tick_count >= max_ticks:
		terminal = "truncated"
	if terminal != "none":
		episode_terminal = terminal
	if terminal != "none" or _budget == 0:
		_finish_step(terminal)


func _execute_tick(_delta: float) -> void:
	var start := body.global_transform
	var desired := Vector3(0, 0, -speed_mps * DT)
	var sim := start
	var remaining := desired
	var accepted := Vector3.ZERO
	var substeps := 0
	var worst_pred_error := 0.0
	var grounded := false

	while remaining.length() > 1e-9 and substeps < MAX_SUBSTEPS:
		var seg_len: float = minf(remaining.length(), SUBSTEP_MAX_LEN)
		var motion := remaining.normalized() * seg_len

		# Primary nonmutating swept prediction: shape cast from the explicit
		# simulated transform. The car's own body is excluded from the query.
		# The cast margin is 0: cast_motion grows the shape by this margin, and
		# under the pinned Jolt backend a margin-grown cast both stops the
		# prediction SAFE_MARGIN early and reports the segment clear once the
		# grown hull overlaps a contact (measured; see evidence README). Casting
		# the real hull (margin 0) reproduces the committed move_and_collide
		# travel to <=1e-6 m on approach and 0 m while resting in contact.
		var space := body.get_world_3d().direct_space_state
		var shape_query := PhysicsShapeQueryParameters3D.new()
		shape_query.shape = hull_shape
		shape_query.transform = sim
		shape_query.motion = motion
		shape_query.margin = CAST_QUERY_MARGIN
		shape_query.collide_with_bodies = true
		shape_query.collide_with_areas = false
		shape_query.exclude = [body.get_rid()]
		var fractions: Array = space.cast_motion(shape_query)
		var safe_fraction := 1.0
		if fractions.size() > 0:
			safe_fraction = clampf(float(fractions[0]), 0.0, 1.0)
		var predicted_travel: Vector3 = motion * safe_fraction
		var predicted_end := sim.origin + predicted_travel

		# Secondary diagnostic: the nonmutating test_move query named by the
		# technical design. Its travel can carry a depenetration/recovery offset
		# near contacts; that discrepancy is recorded, not hidden.
		var test_prediction := KinematicCollision3D.new()
		var test_hit := body.test_move(sim, motion, test_prediction, SAFE_MARGIN, false, 8)
		var test_travel: Vector3 = motion
		if test_hit:
			test_travel = test_prediction.get_travel()
			if test_travel.length() > seg_len:
				test_travel = motion

		# Single committed call per accepted segment.
		var collision := body.move_and_collide(motion)
		var actual_travel: Vector3 = motion
		if collision:
			actual_travel = collision.get_travel()
		var committed_end := sim.origin + actual_travel
		var segment_error := predicted_end.distance_to(committed_end)
		worst_pred_error = maxf(worst_pred_error, segment_error)
		max_test_move_error = maxf(max_test_move_error, (sim.origin + test_travel).distance_to(committed_end))
		if OS.get_environment("TICK_PROBE_DEBUG") != "":
			print("DBG tick=%d sub=%d seg=%.6f safe=%.9f pred_travel=%s test_travel=%s actual_travel=%s err=%.9f sim_z=%.9f body_z=%.9f" % [
				tick_count + 1, substeps, seg_len, safe_fraction, predicted_travel,
				test_travel, actual_travel, segment_error, sim.origin.z, body.global_position.z])

		sim.origin = committed_end
		accepted += actual_travel
		remaining = desired - accepted
		substeps += 1
		max_substep_len = maxf(max_substep_len, seg_len)
		if collision and actual_travel.length() < seg_len - 1e-6:
			break

	grounded = _probe_grounded()
	_last_grounded = grounded
	max_prediction_error = maxf(max_prediction_error, worst_pred_error)
	max_commit_discrepancy = maxf(
		max_commit_discrepancy,
		body.global_transform.origin.distance_to(sim.origin)
	)
	total_substeps += substeps

	var draw := rng.randf()
	rng_draws.append(draw)
	events.append({"tick": tick_count + 1, "kind": "tick", "draw": draw})
	tick_log.append({
		"tick": tick_count + 1,
		"start_z": start.origin.z,
		"end_z": body.global_position.z,
		"accepted_len": accepted.length(),
		"substeps": substeps,
		"grounded": grounded,
		"prediction_error": worst_pred_error,
	})
	if tick_log.size() > MAX_TICK_LOG:
		tick_log.pop_front()


func _probe_grounded() -> bool:
	var ray := PhysicsRayQueryParameters3D.new()
	ray.set("from", body.global_position + Vector3(0, 0.25, 0))
	ray.set("to", body.global_position + Vector3(0, -1.0, 0))
	ray.exclude = [body.get_rid()]
	ray.collide_with_bodies = true
	ray.collide_with_areas = false
	var hit: Dictionary = body.get_world_3d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and hit.position.y < 0.05


func _finish_step(terminal: String) -> void:
	last_step_terminal = terminal
	if terminal != "none":
		episode_terminal = terminal
		events.append({"tick": tick_count, "kind": terminal})
	_freeze = true
	get_tree().paused = true
	_emit_result(_requested_ticks, _step_elapsed, terminal)


func _emit_result(requested_ticks: int, elapsed_ticks: int, terminal: String) -> void:
	_result = {
		"schema": "roadstorm.tick_probe.step.v1",
		"requested_ticks": requested_ticks,
		"elapsed_ticks": elapsed_ticks,
		"terminal": terminal,
		"tick_count": tick_count,
		"sim_time": tick_count * DT,
		"observation": observe(),
	}
	_pending_result = true
	step_finished.emit(_result)
