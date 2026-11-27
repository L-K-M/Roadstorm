extends Node
## M0.8 tick/reset/query probe driver.
##
## Runs the structural fidelity scenarios and, on request, the accelerated /
## real-time throughput measurement. Prints one machine-readable
## PROBE_RESULT <json> line and exits nonzero on any failed check.

const DT := 1.0 / 60.0
const DEFAULT_REQUESTS := 50
const CoordinatorScript := preload("res://src/tick_coordinator.gd")

var coord
var failures: Array[String] = []
var checks := 0
var frames := 0
var mode := "structural"
var label := "local"
var throughput_requests := DEFAULT_REQUESTS
var inject_failure := false
var env := {}
var scenario_report := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_args(OS.get_cmdline_user_args())
	coord = CoordinatorScript.new()
	get_tree().root.add_child(coord)
	await get_tree().process_frame
	_collect_environment()
	match mode:
		"throughput":
			scenario_report = {"throughput": await _run_throughput(throughput_requests)}
		"structural":
			await _run_structural()
		_:
			await _run_structural()
			scenario_report["throughput"] = await _run_throughput(throughput_requests)
	_finish()


func _process(_delta: float) -> void:
	frames += 1


func _parse_args(args: Array) -> void:
	for arg in args:
		if arg.begins_with("mode="):
			mode = arg.substr(5)
		elif arg.begins_with("label="):
			label = arg.substr(6)
		elif arg.begins_with("requests="):
			throughput_requests = maxi(1, int(arg.substr(9)))
		elif arg == "inject_failure=1":
			inject_failure = true


func _collect_environment() -> void:
	var version := Engine.get_version_info()
	env = {
		"engine_string": str(version.get("string", "")),
		"engine_major": int(version.get("major", 0)),
		"engine_minor": int(version.get("minor", 0)),
		"engine_patch": int(version.get("patch", 0)),
		"os": OS.get_name(),
		"processor_count": OS.get_processor_count(),
		"processor_name": OS.get_processor_name() if OS.has_method("get_processor_name") else "",
		"physics_ticks_per_second": ProjectSettings.get_setting("physics/common/physics_ticks_per_second"),
		"swept_cast_margin_m": CoordinatorScript.CAST_QUERY_MARGIN,
		"character_body_safe_margin_m": CoordinatorScript.SAFE_MARGIN,
		"max_tick_travel_m": CoordinatorScript.MAX_TICK_TRAVEL_M,
		"max_supported_speed_mps": CoordinatorScript.MAX_SUPPORTED_SPEED_MPS,
		"physics_engine_setting": str(ProjectSettings.get_setting("physics/3d/physics_engine")),
		"physics_engine_allowed": _physics_engine_allowed(),
		"rendering_method_setting": str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
	}
	var ok: bool = env.engine_major == 4 and env.engine_minor == 7 and env.engine_patch == 2
	_check(ok, "pinned engine is Godot 4.7.2", str(env.engine_string))
	_check(env.physics_engine_setting == "Jolt Physics",
		"pinned 3D physics backend is Jolt Physics",
		"setting=%s allowed=%s" % [str(env.physics_engine_setting), str(env.physics_engine_allowed)])


## Allowed values of physics/3d/physics_engine from the engine property list.
## GDScript cannot query which backend is actually instantiated at runtime
## (PhysicsServer3D is opaque), so the setting value plus the recorded
## backend-contrast run in the evidence directory are the verification.
func _physics_engine_allowed() -> Array:
	for p in ProjectSettings.get_property_list():
		if str(p.get("name", "")) == "physics/3d/physics_engine":
			return str(p.get("hint_string", "")).split(",")
	return []


func _check(condition: bool, label: String, detail: String = "") -> void:
	checks += 1
	if condition:
		print("PASS ", label)
	else:
		var line := "FAIL " + label
		if detail != "":
			line += " | " + detail
		failures.append(line)
		print(line)


func _wait_frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _step(requested_ticks: int = 12) -> Dictionary:
	coord.begin_step(requested_ticks)
	var guard := 0
	while not coord.has_pending_result():
		await get_tree().process_frame
		guard += 1
		if guard > 200000:
			_check(false, "step result arrived", "guard exhausted")
			return {"elapsed_ticks": -1, "terminal": "error"}
	return coord.take_result()


func _configure(speed: float, finish_z: float = INF, max_ticks: int = 1000000, wall_face_z: float = NAN) -> void:
	coord.configure(speed, finish_z, max_ticks, wall_face_z)
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# Structural scenarios
# ---------------------------------------------------------------------------

func _run_structural() -> void:
	await _scenario_open_fidelity()
	await _scenario_bypass_calls()
	await _scenario_early_termination()
	await _scenario_truncation()
	await _scenario_zero_tick_budget()
	await _scenario_bounded_work_envelope()
	await _scenario_reset_replay()
	await _scenario_wall_swept_motion()
	await _scenario_max_speed_no_tunnel()
	await _scenario_wait_freeze()


func _scenario_open_fidelity() -> void:
	await _configure(10.0)
	var obs0: Dictionary = coord.reset()

	# Negative control: a plain call counter that never asks the coordinator to
	# step the world. Twelve unacked calls must not advance the world or the
	# tick budget. The arithmetic below is only a claimed distance; it is not
	# measured motion and is not evidence that any motor ran.
	var unacked_calls := 12
	var unacked_claimed_m := unacked_calls * 10.0 * DT
	await _wait_frames(30)
	var obs_fake = coord.observe()
	_check(coord.tick_count == 0,
		"negative-control: 12 unacked calls consumed zero logical ticks",
		"tick_count=%d" % coord.tick_count)
	_check(obs_fake.position[2] == obs0.position[2],
		"negative-control: unacked calls did not move the body",
		"z0=%.9f z1=%.9f" % [obs0.position[2], obs_fake.position[2]])
	_check(unacked_claimed_m > 0.0,
		"negative-control: call arithmetic alone is not evidence of motion",
		"claimed=%.6f m" % unacked_claimed_m)

	# Five training-style requests of twelve ticks each.
	var elapsed_list: Array[int] = []
	var all_full := true
	var all_nonterminal := true
	var inter_wait_ok := true
	for i in 5:
		var result: Dictionary = await _step(12)
		elapsed_list.append(int(result.elapsed_ticks))
		if int(result.elapsed_ticks) != 12:
			all_full = false
		if str(result.terminal) != "none":
			all_nonterminal = false
		if i < 4:
			var idle_ticks: int = coord.tick_count
			await _wait_frames(5)
			if coord.tick_count != idle_ticks:
				inter_wait_ok = false
	_check(inter_wait_ok, "open: waiting between requests consumed zero logical ticks")
	_check(all_full, "open: every nonterminal request consumed exactly 12 ticks",
		str(elapsed_list))
	_check(all_nonterminal, "open: five requests stayed nonterminal")
	_check(coord.tick_count == 60, "open: total logical ticks is 60", "ticks=%d" % coord.tick_count)

	var expected_z: float = float(obs0.position[2]) - 10.0
	var actual_z: float = coord.body.global_position.z
	_check(absf(actual_z - expected_z) < 1e-4, "open: 60 ticks moved the body the commanded 10 m",
		"expected=%.9f actual=%.9f" % [expected_z, actual_z])
	_check(coord.max_prediction_error < 0.01,
		"open: shape-cast prediction matches committed motion below 0.01 m",
		"max_error=%.9f" % coord.max_prediction_error)
	_check(coord.max_commit_discrepancy < 1e-4,
		"open: explicit simulated transform matches committed body position",
		"max_discrepancy=%.9f" % coord.max_commit_discrepancy)
	var grounded_all := true
	for entry in coord.tick_log:
		if not bool(entry.grounded):
			grounded_all = false
	_check(grounded_all, "open: ground query reported support on every tick")
	_check(coord.delta_min > 0.0 and absf(coord.delta_min - DT) < 1e-6
		and absf(coord.delta_max - DT) < 1e-6,
		"open: physics delta stayed fixed at 1/60 s",
		"min=%.9f max=%.9f" % [coord.delta_min, coord.delta_max])

	scenario_report["open_fidelity"] = {
		"unacked_call_count": unacked_calls,
		"unacked_claimed_distance_m": unacked_claimed_m,
		"request_elapsed_ticks": elapsed_list,
		"tick_count": coord.tick_count,
		"expected_z_m": expected_z,
		"actual_z_m": actual_z,
		"max_prediction_error_m": coord.max_prediction_error,
		"max_test_move_error_m": coord.max_test_move_error,
		"max_commit_discrepancy_m": coord.max_commit_discrepancy,
		"delta_min": coord.delta_min,
		"delta_max": coord.delta_max,
	}


func _scenario_bypass_calls() -> void:
	await _configure(10.0)
	coord.reset()
	var z0: float = coord.body.global_position.z
	# Twelve direct physics calls made outside any coordinator tick: the body
	# moves, but no logical tick is accounted.
	for i in 12:
		coord.body.move_and_collide(Vector3(0, 0, -10.0 * DT))
	var z1: float = coord.body.global_position.z
	_check(coord.tick_count == 0,
		"bypass: 12 direct physics calls consumed zero logical ticks",
		"ticks=%d" % coord.tick_count)
	_check(absf((z0 - z1) - 2.0) < 1e-4,
		"bypass: direct calls still moved the body 2 m outside tick accounting",
		"moved=%.9f m" % (z0 - z1))
	scenario_report["bypass_calls"] = {
		"direct_calls": 12,
		"logical_ticks": coord.tick_count,
		"body_displacement_m": z0 - z1,
	}


func _scenario_early_termination() -> void:
	await _configure(10.0, -0.9)
	coord.reset()
	var result: Dictionary = await _step(12)
	_check(str(result.terminal) == "terminated", "termination: terminal kind is terminated",
		str(result.terminal))
	_check(int(result.elapsed_ticks) == 6, "termination: stopped early at tick 6",
		"elapsed=%d" % int(result.elapsed_ticks))
	_check(coord.tick_count == 6, "termination: only 6 ticks accumulated", "ticks=%d" % coord.tick_count)
	var z: float = coord.body.global_position.z
	_check(z <= -0.9 and z > -1.000001, "termination: car stopped on the crossing tick",
		"z=%.9f" % z)
	var again: Dictionary = await _step(12)
	_check(int(again.elapsed_ticks) == 0, "termination: later request consumes zero ticks",
		"elapsed=%d" % int(again.elapsed_ticks))
	_check(str(again.terminal) == "terminated", "termination: episode stays terminated")
	_check(coord.body.global_position.z == z, "termination: no motion after terminal")

	scenario_report["early_termination"] = {
		"requested_ticks": 12,
		"elapsed_ticks": int(result.elapsed_ticks),
		"terminal": str(result.terminal),
		"final_z_m": z,
		"later_request_elapsed_ticks": int(again.elapsed_ticks),
	}


func _scenario_truncation() -> void:
	await _configure(10.0, INF, 30)
	coord.reset()
	var r1: Dictionary = await _step(12)
	var r2: Dictionary = await _step(12)
	var r3: Dictionary = await _step(12)
	var r4: Dictionary = await _step(12)
	_check(str(r1.terminal) == "none" and int(r1.elapsed_ticks) == 12,
		"truncation: first request full and nonterminal")
	_check(str(r2.terminal) == "none" and int(r2.elapsed_ticks) == 12,
		"truncation: second request full and nonterminal")
	_check(str(r3.terminal) == "truncated" and int(r3.elapsed_ticks) == 6,
		"truncation: partial final request returns the 6 remaining ticks",
		"elapsed=%d terminal=%s" % [int(r3.elapsed_ticks), str(r3.terminal)])
	_check(str(r4.terminal) == "truncated" and int(r4.elapsed_ticks) == 0,
		"truncation: post-truncation request consumes zero ticks")
	_check(coord.tick_count == 30, "truncation: total ticks capped at 30",
		"ticks=%d" % coord.tick_count)
	var z: float = coord.body.global_position.z
	_check(absf(z - (-5.0)) < 1e-4, "truncation: 30 ticks moved the commanded 5 m",
		"z=%.9f" % z)

	scenario_report["truncation"] = {
		"max_ticks": 30,
		"sequence": [
			{"elapsed_ticks": int(r1.elapsed_ticks), "terminal": str(r1.terminal)},
			{"elapsed_ticks": int(r2.elapsed_ticks), "terminal": str(r2.terminal)},
			{"elapsed_ticks": int(r3.elapsed_ticks), "terminal": str(r3.terminal)},
			{"elapsed_ticks": int(r4.elapsed_ticks), "terminal": str(r4.terminal)},
		],
		"final_z_m": z,
	}


func _scenario_zero_tick_budget() -> void:
	# Explicit exhausted-budget semantics: max_ticks <= 0 means zero ticks are
	# ever executed, so no physics callback may advance the world.
	await _configure(10.0, INF, 0)
	coord.reset()
	var z0: float = coord.body.global_position.z
	var r: Dictionary = await _step(12)
	_check(int(r.elapsed_ticks) == 0 and str(r.terminal) == "truncated",
		"zero-budget: max_ticks=0 consumes zero ticks and starts truncated",
		"elapsed=%d terminal=%s" % [int(r.elapsed_ticks), str(r.terminal)])
	_check(coord.tick_count == 0 and coord.body.global_position.z == z0,
		"zero-budget: no unintended tick or motion at cap 0",
		"ticks=%d z_delta=%.9f" % [coord.tick_count, coord.body.global_position.z - z0])
	var later: Dictionary = await _step(12)
	_check(int(later.elapsed_ticks) == 0 and str(later.terminal) == "truncated",
		"zero-budget: later requests stay zero-tick truncated")

	await _configure(10.0, INF, -5)
	coord.reset()
	var rn: Dictionary = await _step(12)
	_check(int(rn.elapsed_ticks) == 0 and str(rn.terminal) == "truncated",
		"zero-budget: negative cap is treated as zero, not one tick",
		"elapsed=%d terminal=%s" % [int(rn.elapsed_ticks), str(rn.terminal)])

	# Boundary control: a one-tick budget executes exactly one tick.
	await _configure(10.0, INF, 1)
	coord.reset()
	var rb: Dictionary = await _step(12)
	_check(int(rb.elapsed_ticks) == 1 and str(rb.terminal) == "truncated",
		"zero-budget: max_ticks=1 executes exactly one tick",
		"elapsed=%d terminal=%s" % [int(rb.elapsed_ticks), str(rb.terminal)])
	_check(coord.tick_count == 1,
		"zero-budget: one-tick boundary accounted exactly once",
		"ticks=%d" % coord.tick_count)

	scenario_report["zero_tick_budget"] = {
		"cap_0_elapsed_ticks": int(r.elapsed_ticks),
		"cap_0_terminal": str(r.terminal),
		"negative_cap_elapsed_ticks": int(rn.elapsed_ticks),
		"one_tick_cap_elapsed_ticks": int(rb.elapsed_ticks),
	}


func _scenario_bounded_work_envelope() -> void:
	# The work cap implies MAX_SUBSTEPS * SUBSTEP_MAX_LEN per tick. A command at
	# that bound must succeed; above it the coordinator fails closed instead of
	# silently dropping the unapplied remainder.
	await _configure(CoordinatorScript.MAX_SUPPORTED_SPEED_MPS, INF, 1000000)
	coord.reset()
	var boundary: Dictionary = await _step(12)
	var boundary_violations: int = coord.motion_bound_violations
	_check(str(boundary.terminal) == "none" and int(boundary.elapsed_ticks) == 12,
		"work-envelope: speed at the 4 m/tick bound completed 12 ticks",
		"elapsed=%d terminal=%s" % [int(boundary.elapsed_ticks), str(boundary.terminal)])
	_check(boundary_violations == 0,
		"work-envelope: no bounded-work failure at the supported speed",
		"violations=%d" % boundary_violations)
	_check(max_substep_ok(), "work-envelope: substep cap respected at the bound",
		"max_substep=%.6f" % coord.max_substep_len)

	await _configure(250.0, INF, 1000000)
	coord.reset()
	var z0: float = coord.body.global_position.z
	var over: Dictionary = await _step(12)
	_check(str(over.terminal) == "motion_bound" and int(over.elapsed_ticks) == 0,
		"work-envelope: 250 m/s refused with motion_bound and zero elapsed ticks",
		"elapsed=%d terminal=%s" % [int(over.elapsed_ticks), str(over.terminal)])
	_check(coord.tick_count == 0 and coord.body.global_position.z == z0,
		"work-envelope: refused command moved nothing",
		"ticks=%d z_delta=%.9f" % [coord.tick_count, coord.body.global_position.z - z0])
	_check(coord.motion_bound_violations >= 1 and coord.last_motion_bound_deficit_m > 0.0,
		"work-envelope: residual deficit recorded explicitly",
		"violations=%d deficit=%.9f m" % [coord.motion_bound_violations, coord.last_motion_bound_deficit_m])
	var over_deficit: float = coord.last_motion_bound_deficit_m

	await _configure(-250.0, INF, 1000000)
	coord.reset()
	var reverse: Dictionary = await _step(12)
	_check(str(reverse.terminal) == "motion_bound" and int(reverse.elapsed_ticks) == 0,
		"work-envelope: reverse over-speed is also refused",
		"elapsed=%d terminal=%s" % [int(reverse.elapsed_ticks), str(reverse.terminal)])

	scenario_report["bounded_work_envelope"] = {
		"max_tick_travel_m": CoordinatorScript.MAX_TICK_TRAVEL_M,
		"max_supported_speed_mps": CoordinatorScript.MAX_SUPPORTED_SPEED_MPS,
		"boundary_elapsed_ticks": int(boundary.elapsed_ticks),
		"boundary_motion_bound_violations": boundary_violations,
		"over_speed_terminal": str(over.terminal),
		"over_speed_deficit_m": over_deficit,
		"reverse_terminal": str(reverse.terminal),
	}


func _scenario_reset_replay() -> void:
	await _configure(10.0)
	var initial: Dictionary = coord.reset()
	await _step(12)
	await _step(12)
	var pos_a: Vector3 = coord.body.global_position
	var rot_a: Vector3 = coord.body.global_rotation
	var rng_a: Array = coord.rng_draws.duplicate()
	var events_a: int = coord.events.size()
	var distance_a: float = coord.commanded_distance
	var substeps_a: int = coord.total_substeps

	coord.reset()
	var after_reset = coord.observe()
	_check(coord.tick_count == 0, "reset: tick counter cleared")
	var stale_result: Dictionary = coord.take_result()
	_check(stale_result.is_empty(),
		"reset: take_result exposes no pre-reset result",
		"keys=%s" % str(stale_result.keys()))
	_check(not coord.has_pending_result(), "reset: no pending result survives reset")
	_check(after_reset.position == initial.position, "reset: pose restored exactly")
	_check(is_equal_approx(rad_to_deg(coord.body.global_rotation.y), rad_to_deg(coord.initial_transform.basis.get_euler().y)),
		"reset: rotation restored")
	_check(coord.rng_draws.is_empty(), "reset: RNG history cleared")
	_check(coord.events.is_empty(), "reset: event queue cleared")
	_check(coord.commanded_distance == 0.0 and coord.total_substeps == 0,
		"reset: distance/substep counters cleared")
	_check(coord.episode_terminal == "none" and not get_tree().paused,
		"reset: episode open and world unfrozen")

	# Reset while frozen must also work.
	await _step(12)
	coord.set_frozen(true)
	await _wait_frames(3)
	coord.reset()
	_check(coord.tick_count == 0 and not get_tree().paused,
		"reset: works while waiting/frozen")

	await _step(12)
	await _step(12)
	var pos_b: Vector3 = coord.body.global_position
	var rng_b: Array = coord.rng_draws.duplicate()
	_check(pos_a == pos_b, "replay: identical command trace reproduces the exact transform",
		"a=(%.9f, %.9f, %.9f) b=(%.9f, %.9f, %.9f)" % [pos_a.x, pos_a.y, pos_a.z, pos_b.x, pos_b.y, pos_b.z])
	_check(rot_a == coord.body.global_rotation, "replay: rotation reproduced exactly")
	_check(rng_a == rng_b, "replay: seeded RNG stream reproduced exactly",
		"draws=%d" % rng_a.size())
	_check(coord.events.size() == events_a, "replay: event count reproduced",
		"a=%d b=%d" % [events_a, coord.events.size()])
	_check(coord.commanded_distance == distance_a and coord.total_substeps == substeps_a,
		"replay: distance and substep totals reproduced")

	scenario_report["reset_replay"] = {
		"ticks_per_replay": 24,
		"exact_transform_match": pos_a == pos_b,
		"exact_rng_stream_match": rng_a == rng_b,
		"event_count_first_run": events_a,
		"event_count_replay": coord.events.size(),
		"commanded_distance_m": distance_a,
	}


func _scenario_wall_swept_motion() -> void:
	await _configure(10.0, INF, 1000000, -3.0)
	coord.reset()
	var naive_chord_z := -12 * 10.0 * DT
	var result: Dictionary = await _step(12)
	var z: float = coord.body.global_position.z
	_check(str(result.terminal) == "none" and int(result.elapsed_ticks) == 12,
		"wall: request completed 12 ticks without terminal")
	_check(z > -1.15 and z < -1.0, "wall: car stopped at the wall face instead of the naive chord",
		"z=%.9f naive_chord=%.9f contact_plane=%.3f" % [z, naive_chord_z, -1.1])
	var min_z := INF
	for entry in coord.tick_log:
		min_z = minf(min_z, float(entry.end_z))
	_check(min_z > -1.1 - 0.02, "wall: no tick endpoint tunneled through the wall",
		"min_z=%.9f" % min_z)
	_check(coord.max_prediction_error < 0.01,
		"wall: shape-cast prediction tracked committed contact motion below 0.01 m",
		"max_error=%.9f" % coord.max_prediction_error)
	_check(max_substep_ok(), "wall: movement subdivision respected the 0.25 m cap")

	scenario_report["wall_swept_motion"] = {
		"wall_face_z_m": -3.0,
		"contact_plane_z_m": -1.1,
		"naive_chord_z_m": naive_chord_z,
		"actual_stop_z_m": z,
		"minimum_tick_end_z_m": min_z,
		"max_prediction_error_m": coord.max_prediction_error,
		"test_move_recovery_artifact_m": coord.max_test_move_error,
		"max_substep_len_m": coord.max_substep_len,
		"total_substeps": coord.total_substeps,
	}


func _scenario_max_speed_no_tunnel() -> void:
	await _configure(65.0, INF, 1000000, -2.5)
	coord.reset()
	var naive_chord_one_tick := -65.0 * DT
	var naive_chord_request := -12 * 65.0 * DT
	var result: Dictionary = await _step(12)
	var z: float = coord.body.global_position.z
	var contact_plane := -2.5 + 1.9
	_check(str(result.terminal) == "none" and int(result.elapsed_ticks) == 12,
		"max-speed: request completed 12 ticks")
	_check(z > contact_plane - 0.05 and z < contact_plane + 0.02,
		"max-speed: 65 m/s car stopped at the wall, not through it",
		"z=%.9f contact_plane=%.3f naive_one_tick=%.6f naive_request=%.3f" % [z, contact_plane, naive_chord_one_tick, naive_chord_request])
	_check(max_substep_ok(), "max-speed: per-substep displacement stayed within 0.25 m",
		"max_substep=%.6f" % coord.max_substep_len)
	_check(coord.total_substeps > 12, "max-speed: subdivision was actually exercised",
		"substeps=%d" % coord.total_substeps)

	scenario_report["max_speed_no_tunnel"] = {
		"speed_mps": 65.0,
		"wall_face_z_m": -2.5,
		"contact_plane_z_m": contact_plane,
		"naive_one_tick_z_m": naive_chord_one_tick,
		"naive_request_z_m": naive_chord_request,
		"actual_stop_z_m": z,
		"max_substep_len_m": coord.max_substep_len,
		"total_substeps": coord.total_substeps,
	}


func max_substep_ok() -> bool:
	return coord.max_substep_len <= 0.25 + 1e-6


func _scenario_wait_freeze() -> void:
	await _configure(10.0)
	coord.reset()
	await _step(12)
	var ticks_before: int = coord.tick_count
	var z_before: float = coord.body.global_position.z

	# Trainer-wait gate: freeze the authoritative world, let the engine keep
	# iterating frames, and require zero logical advancement.
	var driver_frames_before: int = frames
	coord.set_frozen(true)
	await _wait_frames(60)
	var driver_frames_during: int = frames - driver_frames_before
	_check(coord.tick_count == ticks_before, "wait: zero logical ticks while frozen",
		"before=%d after=%d" % [ticks_before, coord.tick_count])
	_check(coord.body.global_position.z == z_before, "wait: probe car did not move while frozen")
	_check(driver_frames_during >= 60 and coord.frozen_physics_frames >= 1,
		"wait: engine frames continued while the world was frozen",
		"driver_frames=%d frozen_physics_frames=%d" % [driver_frames_during, coord.frozen_physics_frames])
	coord.set_frozen(false)
	var resumed: Dictionary = await _step(12)
	_check(int(resumed.elapsed_ticks) == 12 and coord.tick_count == ticks_before + 12,
		"wait: stepping resumed with exactly 12 ticks", "elapsed=%d" % int(resumed.elapsed_ticks))

	# An autonomous RigidBody must also stop under both freeze mechanisms.
	# The step above leaves the tree frozen between requests; unfreeze first.
	coord.set_frozen(false)
	var ambient := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	shape.shape = sphere
	ambient.add_child(shape)
	ambient.position = Vector3(5, 10, 0)
	coord.add_child(ambient)
	await _wait_frames(30)
	var y_after_fall: float = ambient.global_position.y
	_check(y_after_fall < 10.0, "freeze: ambient rigid body falls under normal stepping",
		"y=%.6f" % y_after_fall)

	coord.set_frozen(true)
	await _wait_frames(60)
	_check(ambient.global_position.y == y_after_fall,
		"freeze: SceneTree.paused stops an autonomous rigid body",
		"y=%.9f" % ambient.global_position.y)

	coord.set_frozen(false)
	Engine.time_scale = 0.0
	# Engine.time_scale takes effect on a later iteration; let it settle
	# before measuring the steady-state hold.
	await _wait_frames(3)
	var ts_start: float = ambient.global_position.y
	await _wait_frames(60)
	var ts_end: float = ambient.global_position.y
	_check(absf(ts_end - ts_start) < 1e-5,
		"freeze: Engine.time_scale=0 holds an autonomous rigid body within 1e-5 m",
		"start=%.9f end=%.9f" % [ts_start, ts_end])
	Engine.time_scale = 1.0
	ambient.queue_free()

	scenario_report["wait_freeze"] = {
		"ticks_before_wait": ticks_before,
		"ticks_after_wait": ticks_before,
		"frozen_engine_physics_frames": coord.frozen_physics_frames,
		"driver_frames_during_wait": driver_frames_during,
		"resumed_elapsed_ticks": int(resumed.elapsed_ticks),
		"ambient_y_after_fall": y_after_fall,
		"ambient_time_scale_drift_m": absf(ts_end - ts_start),
	}


# ---------------------------------------------------------------------------
# Throughput: accelerated versus real-time pacing
# ---------------------------------------------------------------------------

func _run_throughput(requests: int) -> Dictionary:
	await _configure(10.0)
	coord.reset()
	var start_usec := Time.get_ticks_usec()
	var frames0 := frames
	var engine0: int = coord.engine_physics_frames
	var elapsed := 0
	for i in requests:
		var result: Dictionary = await _step(12)
		elapsed += int(result.elapsed_ticks)
	var elapsed_usec := Time.get_ticks_usec() - start_usec
	var wall_s := elapsed_usec / 1000000.0
	var sim_s := elapsed * DT
	var final_z: float = coord.body.global_position.z
	_check(elapsed == requests * 12, "throughput: all requests consumed 12 ticks",
		"elapsed=%d" % elapsed)
	var position_error := absf(final_z - (-sim_s * 10.0))
	_check(position_error < 1e-4 + 1e-6 * elapsed,
		"throughput: final position matches command trace within float32 accumulation",
		"error=%.9f m over %d ticks" % [position_error, elapsed])
	return {
		"label": label,
		"requests": requests,
		"elapsed_ticks": elapsed,
		"sim_seconds": sim_s,
		"wall_seconds": wall_s,
		"logical_ticks_per_wall_second": elapsed / wall_s,
		"speedup_vs_wall_clock": sim_s / wall_s,
		"rendered_frames": frames - frames0,
		"engine_physics_frames": coord.engine_physics_frames - engine0,
		"delta_min": coord.delta_min,
		"delta_max": coord.delta_max,
		"final_z_m": final_z,
		"position_error_m": position_error,
		"max_prediction_error_m": coord.max_prediction_error,
		"max_commit_discrepancy_m": coord.max_commit_discrepancy,
	}


func _finish() -> void:
	if inject_failure:
		_check(false, "injected failure (exit-code self-test)")
	var report := {
		"schema": "roadstorm.tick_probe.report.v1",
		"environment": env,
		"mode": mode,
		"label": label,
		"checks_total": checks,
		"checks_failed": failures.size(),
		"failures": failures,
		"scenarios": scenario_report,
		"limitations": [
			"Headless dummy display/audio drivers; no rendering, input or audio claims.",
			"Accelerated pacing uses --fixed-fps (engine disables real-time synchronization); real-time pacing uses --max-fps 60 and depends on host load.",
			"Godot/Jolt same-host determinism is measured; cross-platform byte determinism is not claimed.",
			"The probe car uses CharacterBody3D explicit displacement like the planned motor; it is not the full M1 motor, AI, contacts, multi-car reset or renderer. A one-car open-road/wall trace is not a full simulation claim.",
			"The coordinator advances exactly 1/60 s per logical tick and does not use the engine delta parameter; structural scenarios assert that the delivered physics delta stays 1/60 s rather than clamping or adapting to a different delta.",
			"The coordinator owns SceneTree.paused for the probe world: begin_step() and reset() clear an externally set pause so the authoritative world cannot be left frozen by another subsystem. Other nodes must not write SceneTree.paused while the probe runs.",
			"A commanded per-tick displacement above MAX_SUBSTEPS * SUBSTEP_MAX_LEN (4.0 m, 240 m/s) is refused with terminal motion_bound; speeds within the envelope are subdivided into <=0.25 m substeps.",
			"take_result() consumes the pending result and returns an empty Dictionary when none is pending; reset clears any stored result so a prior episode result cannot be read back.",
			"GDScript cannot query the active 3D physics backend at runtime (PhysicsServer3D is opaque and this build prints no backend line even with --verbose); the backend pin is verified by the physics/3d/physics_engine setting value above plus the explicit backend-contrast run recorded in the evidence directory.",
		],
	}
	print("PROBE_RESULT ", JSON.stringify(report))
	print("CHECKS_TOTAL=", checks, " CHECKS_FAILED=", failures.size())
	# Defer quit by one frame so the final prints flush.
	await get_tree().process_frame
	get_tree().quit(1 if failures.size() > 0 else 0)
