extends Node
## Hard repeated-request gate: every logical tick must be paired with its own
## physics-server integration, and publication must happen only after the final
## server-owned state is observable.
##
## Runs 12 + 12 + 1 on ONE warmed body/world for idle, callback and mixed
## origins, with no reset/warm-up between requests. A mid-request motion-bound
## case proves exactly k server steps for k elapsed ticks. A one-tick terminal
## proves final-state freshness at publication.

const CoordinatorScript := preload("res://src/tick_coordinator.gd")
const CountingBody := preload("res://tests/counting_body.gd")
const PhysicsCaller := preload("res://tests/physics_caller.gd")
const MotionInjector := preload("res://tests/motion_injector.gd")
const PublicationProbe := preload("res://tests/publication_probe.gd")

var coord
var dyn: RigidBody3D
var failures: Array[String] = []
var checks := 0
var signal_events: Array[Dictionary] = []
var step_finished_count := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	coord = CoordinatorScript.new()
	get_tree().root.add_child(coord)
	coord.step_finished.connect(_on_finished)
	coord.step_finished.connect(_on_finished_count)
	await get_tree().process_frame
	await _sequence("idle", ["idle", "idle", "idle"])
	await _sequence("callback", ["callback", "callback", "callback"])
	await _sequence("mixed", ["idle", "callback", "idle"])
	await _mid_request_motion_bound()
	await _one_tick_terminal()
	await _publication_window_reset()
	_finish()

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

func _on_finished_count(_result: Dictionary) -> void:
	step_finished_count += 1


func _on_finished(result: Dictionary) -> void:
	signal_events.append({
		"elapsed": int(result.elapsed_ticks),
		"ticks": coord.tick_count,
		"terminal": str(result.terminal),
		"steps": dyn.server_steps,
		"integ_ticks": dyn.integ_ticks.duplicate(),
		"body_y": dyn.global_position.y,
		"body_v": dyn.linear_velocity.y,
		"state_y": dyn.last_state_transform.origin.y,
		"state_v": dyn.last_state_linear_velocity.y,
		"paused": get_tree().paused,
	})

func _wait_frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _spawn() -> void:
	dyn = CountingBody.new()
	dyn.can_sleep = false
	dyn.linear_damp = 0.0
	dyn.coord_ref = coord
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	shape.shape = sphere
	dyn.add_child(shape)
	dyn.position = Vector3(5, 1000, 0)
	coord.add_child(dyn)

func _warm(speed: float = 10.0, finish_z: float = INF) -> void:
	coord.configure(speed, finish_z, 1000000, NAN)
	coord.reset()
	signal_events.clear()
	_spawn()
	coord.set_frozen(false)
	await _wait_frames(5)
	coord.set_frozen(true)
	await _wait_frames(2)

func _request(origin: String, n: int) -> Dictionary:
	if origin == "callback":
		var caller := PhysicsCaller.new()
		caller.coordinator = coord
		caller.requested_ticks = n
		caller.process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().root.add_child(caller)
		var guard := 0
		while not coord.has_pending_result() and guard < 200000:
			await get_tree().process_frame
			guard += 1
		caller.queue_free()
	else:
		coord.begin_step(n)
		var guard := 0
		while not coord.has_pending_result() and guard < 200000:
			await get_tree().process_frame
			guard += 1
	return coord.take_result()

func _sequence(label: String, origins: Array) -> void:
	await _warm()
	var baseline_steps: int = dyn.server_steps
	var baseline_ticks: int = coord.tick_count
	var integ_baseline: int = dyn.integ_ticks.size()
	var expected_next_tick: int = baseline_ticks + 1
	for i in origins.size():
		var n := 12 if i < 2 else 1
		var y_before: float = dyn.global_position.y
		var v_before: float = dyn.linear_velocity.y
		var r: Dictionary = await _request(origins[i], n)
		var snap: Dictionary = signal_events.back()
		var end_tick: int = coord.tick_count
		var range_start: int = expected_next_tick
		var expected_integ: Array[int] = []
		for t in range(range_start, end_tick + 1):
			expected_integ.append(t)
		var actual_integ: Array[int] = snap.integ_ticks.slice(integ_baseline)
		var step_delta: int = snap.steps - baseline_steps
		_check(int(r.elapsed_ticks) == n and int(r.requested_ticks) == n and end_tick == range_start + n - 1,
			"repeat %s req%d: requested/elapsed/tick deltas exact" % [label, i + 1],
			"requested=%d elapsed=%d ticks=%d->%d" % [int(r.requested_ticks), int(r.elapsed_ticks), range_start - 1, end_tick])
		_check(dyn.global_position.y < y_before - 1e-6 and dyn.linear_velocity.y < v_before - 1e-6,
			"repeat %s req%d: dynamic body actually fell faster" % [label, i + 1],
			"dy=%.9f dv=%.9f" % [dyn.global_position.y - y_before, dyn.linear_velocity.y - v_before])
		expected_next_tick = end_tick + 1
		_check(step_delta == n and actual_integ == expected_integ,
			"repeat %s req%d: n server steps paired with ticks %d..%d" % [label, i + 1, range_start, end_tick],
			"step_delta=%d integ=%s expected=%s" % [step_delta, str(actual_integ), str(expected_integ)])
		_check(snap.state_y == snap.body_y and snap.state_v == snap.body_v,
			"repeat %s req%d: published server-owned dynamic state matches" % [label, i + 1],
			"y %.9f/%.9f v %.9f/%.9f" % [snap.state_y, snap.body_y, snap.state_v, snap.body_v])
		_check(snap.paused and str(snap.terminal) == "none",
			"repeat %s req%d: frozen nonterminal publication" % [label, i + 1])
		var expected_z: float = -10.0 * (1.0 / 60.0) * coord.tick_count
		_check(absf(coord.body.global_position.z - expected_z) < 1e-4,
			"repeat %s req%d: committed kinematic progress exact" % [label, i + 1],
			"z=%.9f expected=%.9f" % [coord.body.global_position.z, expected_z])
		baseline_steps = snap.steps
		baseline_ticks = coord.tick_count
		integ_baseline = snap.integ_ticks.size()
	# Frozen wait after the sequence: zero additional server steps/motion.
	var wait_steps: int = dyn.server_steps
	var wait_y: float = dyn.global_position.y
	var wait_v: float = dyn.linear_velocity.y
	await _wait_frames(30)
	_check(dyn.server_steps == wait_steps and dyn.global_position.y == wait_y and dyn.linear_velocity.y == wait_v,
		"repeat %s: frozen wait adds no server step or dynamic motion" % label,
		"steps=%d->%d" % [wait_steps, dyn.server_steps])

func _mid_request_motion_bound() -> void:
	await _warm()
	var baseline_steps: int = dyn.server_steps
	var baseline_ticks: int = coord.tick_count
	var integ_baseline: int = dyn.integ_ticks.size()
	var injector := MotionInjector.new()
	injector.coordinator = coord
	injector.trigger_tick = 3
	get_tree().root.add_child(injector)
	injector.armed = true
	coord.begin_step(12)
	var r: Dictionary = await _wait_result()
	injector.queue_free()
	var snap: Dictionary = signal_events.back()
	var expected_integ: Array[int] = [1, 2, 3]
	var actual_integ: Array[int] = snap.integ_ticks.slice(integ_baseline)
	_check(str(r.terminal) == "motion_bound" and int(r.elapsed_ticks) == 3
		and int(r.requested_ticks) == 12 and coord.tick_count == baseline_ticks + 3,
		"motion-bound-mid: refusal keeps exactly k=3 elapsed ticks",
		"requested=%d elapsed=%d terminal=%s" % [int(r.requested_ticks), int(r.elapsed_ticks), str(r.terminal)])
	_check(snap.steps - baseline_steps == 3 and actual_integ == expected_integ,
		"motion-bound-mid: exactly k=3 server steps paired with ticks 1..3",
		"step_delta=%d integ=%s" % [snap.steps - baseline_steps, str(actual_integ)])
	_check(snap.paused and snap.state_y == snap.body_y and snap.state_v == snap.body_v,
		"motion-bound-mid: refusal publishes frozen fresh state")

func _one_tick_terminal() -> void:
	await _warm(10.0, -0.1)
	var baseline_steps: int = dyn.server_steps
	var baseline_ticks: int = coord.tick_count
	var integ_baseline: int = dyn.integ_ticks.size()
	var y_before: float = dyn.global_position.y
	var v_before: float = dyn.linear_velocity.y
	var r: Dictionary = await _request("idle", 12)
	var snap: Dictionary = signal_events.back()
	var actual_integ: Array[int] = snap.integ_ticks.slice(integ_baseline)
	_check(str(r.terminal) == "terminated" and int(r.elapsed_ticks) == 1
		and int(r.requested_ticks) == 12 and coord.tick_count == baseline_ticks + 1,
		"terminal-one-tick: terminal elapsed is exactly one tick",
		"requested=%d elapsed=%d terminal=%s" % [int(r.requested_ticks), int(r.elapsed_ticks), str(r.terminal)])
	_check(dyn.global_position.y < y_before - 1e-6 and dyn.linear_velocity.y < v_before - 1e-6,
		"terminal-one-tick: dynamic body actually changed across the request",
		"dy=%.9f dv=%.9f" % [dyn.global_position.y - y_before, dyn.linear_velocity.y - v_before])
	_check(snap.steps - baseline_steps == 1 and actual_integ == [baseline_ticks + 1],
		"terminal-one-tick: final tick integrated exactly once before publication",
		"step_delta=%d integ=%s" % [snap.steps - baseline_steps, str(actual_integ)])
	_check(snap.state_y == snap.body_y and snap.state_v == snap.body_v and snap.paused,
		"terminal-one-tick: publication observes post-step dynamic state while frozen")

func _publication_window_reset() -> void:
	await _warm()
	var probe := PublicationProbe.new()
	probe.coordinator = coord
	get_tree().root.add_child(probe)
	var finished_before: int = step_finished_count
	coord.begin_step(12)
	var guard := 0
	while not probe.fired and guard < 200000:
		await get_tree().process_frame
		guard += 1
	_check(probe.fired,
		"publication-window: observer entered the inter-callback pending window",
		"fired=%s" % str(probe.fired))
	var steps_at_fire: int = dyn.server_steps
	await _wait_frames(5)
	_check(not probe.begin_accepted,
		"publication-window: overlapping begin_step refused",
		"accepted=%s" % str(probe.begin_accepted))
	_check(probe.take_was_empty,
		"publication-window: take_result is empty",
		"empty=%s" % str(probe.take_was_empty))
	_check(probe.reset_done and coord.tick_count == 0 and get_tree().paused,
		"publication-window: reset cancelled publication and froze the world",
		"reset=%s ticks=%d paused=%s" % [str(probe.reset_done), coord.tick_count, str(get_tree().paused)])
	_check(step_finished_count == finished_before,
	"publication-window: cancelled publication emitted no step_finished",
		"count=%d->%d" % [finished_before, step_finished_count])
	_check(dyn.server_steps == steps_at_fire,
	"publication-window: no extra server step after cancellation",
		"steps=%d->%d" % [steps_at_fire, dyn.server_steps])
	probe.queue_free()


func _wait_result() -> Dictionary:
	var guard := 0
	while not coord.has_pending_result() and guard < 200000:
		await get_tree().process_frame
		guard += 1
	return coord.take_result()

func _finish() -> void:
	var report := {
		"schema": "roadstorm.tick_probe.repeat_sequence.v1",
		"checks_total": checks,
		"checks_failed": failures.size(),
		"failures": failures,
	}
	print("REPEAT_RESULT ", JSON.stringify(report))
	print("REPEAT_TOTAL=", checks, " REPEAT_FAILED=", failures.size())
	await get_tree().process_frame
	get_tree().quit(1 if failures.size() > 0 else 0)
