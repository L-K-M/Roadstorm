extends Node
## Independent focused contract tests for the M0.8 tick probe.
##
## Deliberately separate from probe_driver.gd: this suite counts
## SceneTree.physics_frame itself, so the coordinator's logical tick accounting
## is checked against an independent engine-frame count rather than trusted.
## Negative controls show that raw call counts and direct physics calls are not
## evidence of accounted logical ticks.

const CoordinatorScript := preload("res://src/tick_coordinator.gd")
const CountingBody := preload("res://tests/counting_body.gd")
const CallbackObserver := preload("res://tests/callback_observer.gd")

var coord
var ext_physics_frames := 0
var last_signal := {}
var last_accounting := {}
var completion_probe := ""
var completion_probe_reentry: bool = false
var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().physics_frame.connect(_on_engine_physics_frame)
	coord = CoordinatorScript.new()
	get_tree().root.add_child(coord)
	coord.step_finished.connect(_on_step_finished)
	coord.step_accounted.connect(_on_step_accounted)
	coord.step_accounted.connect(_on_step_accounted_probe)
	coord.step_finished.connect(_on_step_finished_probe)
	await get_tree().process_frame
	await _test_frame_accounting()
	await _test_frozen_zero_advance()
	await _test_stale_result_after_reset()
	await _test_zero_tick_budget()
	await _test_motion_bound()
	await _test_wait_guard()
	await _test_dynamic_server_steps()
	await _test_begin_step_refusals()
	await _test_completion_callback_reentrancy()
	await _test_callback_ordering()
	await _test_motion_bound_server_steps()
	await _test_api_edges()
	await _test_bypass_negative_control()
	await _test_pause_ownership()
	_finish()


func _on_engine_physics_frame() -> void:
	ext_physics_frames += 1


## Snapshot the independent tallies at the exact step_finished boundary. A
## trailing engine callback can land after completion/freeze; measuring there
## would mix harness polling timing into the accounting evidence.
func _on_step_finished(result: Dictionary) -> void:
	last_signal = {
		"ext_physics_frames": ext_physics_frames,
		"coord_engine_physics_frames": coord.engine_physics_frames,
		"tick_count": coord.tick_count,
		"paused": get_tree().paused,
		"requested_ticks": int(result.requested_ticks),
		"elapsed_ticks": int(result.elapsed_ticks),
		"terminal": str(result.terminal),
	}


## F1: the pause-enforcer pauses before ordinary later-in-tree nodes, so the
## one post-request pause iteration does not reach them. A node ordered before
## the coordinator subtree still sees the extra callback and is documented as
## requiring tick gating.
func _test_callback_ordering() -> void:
	await _configure(10.0)
	coord.reset()
	var root := get_tree().root
	var before := CallbackObserver.new()
	root.add_child(before)
	root.move_child(before, 0)
	var after := CallbackObserver.new()
	root.add_child(after)
	await _step(12)
	_check(after.physics_callbacks == 12,
		"ordering: node after the coordinator sees exactly the logical tick callbacks",
		"after=%d" % after.physics_callbacks)
	_check(before.physics_callbacks == 13,
		"ordering: node before the coordinator sees the one pause callback (documented exposure)",
		"before=%d" % before.physics_callbacks)
	before.queue_free()
	after.queue_free()


## A refused over-envelope command must integrate no physics-server step.
func _test_motion_bound_server_steps() -> void:
	await _configure(250.0)
	coord.reset()
	var dyn: RigidBody3D = _spawn_counting_body()
	var result: Dictionary = await _step(12)
	_check(str(result.terminal) == "motion_bound" and int(result.elapsed_ticks) == 0,
		"motion-bound: refusal returns zero elapsed ticks",
		"terminal=%s elapsed=%d" % [str(result.terminal), int(result.elapsed_ticks)])
	_check(dyn.server_steps == 0 and coord.tick_count == 0,
		"motion-bound: refusal integrates no physics-server step",
		"server_steps=%d ticks=%d" % [dyn.server_steps, coord.tick_count])
	dyn.queue_free()


## Completion-callback reentrancy probes: while armed, a synchronous listener
## attempts begin_step()/reset() from inside step_accounted/step_finished.
func _on_step_accounted_probe(_result: Dictionary) -> void:
	match completion_probe:
		"accounting_begin":
			completion_probe_reentry = coord.begin_step(2)
		"accounting_reset":
			coord.reset()


func _on_step_finished_probe(_result: Dictionary) -> void:
	match completion_probe:
		"finished_begin":
			completion_probe_reentry = coord.begin_step(2)
		"finished_reset":
			coord.reset()


## Accounting boundary at the final logical tick (before the pause callback).
func _on_step_accounted(result: Dictionary) -> void:
	last_accounting = {
		"ext_physics_frames": ext_physics_frames,
		"coord_engine_physics_frames": coord.engine_physics_frames,
		"tick_count": coord.tick_count,
		"paused": get_tree().paused,
		"requested_ticks": int(result.requested_ticks),
		"elapsed_ticks": int(result.elapsed_ticks),
		"terminal": str(result.terminal),
	}


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


func _configure(speed: float, finish_z: float = INF, max_ticks: int = 1000000, wall_face_z: float = NAN) -> void:
	coord.configure(speed, finish_z, max_ticks, wall_face_z)
	await get_tree().process_frame


func _wait_process_frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## Wait on engine physics callbacks, not process frames: pacing modes differ
## in how many process frames correspond to one physics iteration.
func _wait_physics_frames(count: int) -> void:
	var target := ext_physics_frames + count
	var guard := 0
	while ext_physics_frames < target:
		await get_tree().process_frame
		guard += 1
		if guard > 200000:
			return


func _spawn_ambient(y: float = 10.0) -> RigidBody3D:
	var ambient := RigidBody3D.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	shape.shape = sphere
	ambient.add_child(shape)
	ambient.position = Vector3(5, y, 0)
	coord.add_child(ambient)
	return ambient


func _wait_ambient_below(ambient: RigidBody3D, threshold: float) -> void:
	var guard := 0
	while is_instance_valid(ambient) and ambient.global_position.y > threshold and guard < 600:
		await get_tree().process_frame
		guard += 1


func _wait_pending() -> void:
	var guard := 0
	while not coord.has_pending_result():
		await get_tree().process_frame
		guard += 1
		if guard > 200000:
			return


func _step(requested: int) -> Dictionary:
	coord.begin_step(requested)
	await _wait_pending()
	return coord.take_result()


func _wait_pending_and_take() -> Dictionary:
	await _wait_pending()
	return coord.take_result()


func _wait_pending_and_take_bounded(max_frames: int = 400) -> void:
	var guard := 0
	while not coord.has_pending_result() and guard < max_frames:
		await get_tree().process_frame
		guard += 1


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

## Twelve logical ticks per request must equal independently counted engine
## physics callbacks for several request sizes, including a partial request.
func _test_frame_accounting() -> void:
	await _configure(10.0)
	coord.reset()
	for requested in [1, 7, 12, 13]:
		var ef0 := ext_physics_frames
		var cf0: int = coord.engine_physics_frames
		var t0: int = coord.tick_count
		var result: Dictionary = await _step(requested)
		var elapsed := int(result.elapsed_ticks)
		var snap: Dictionary = last_accounting
		var ext_delta := int(snap.get("ext_physics_frames", -1)) - ef0
		var coord_delta := int(snap.get("coord_engine_physics_frames", -1)) - cf0
		_check(elapsed == requested,
			"frame-account: request %d consumed exactly %d logical ticks" % [requested, requested],
			"elapsed=%d terminal=%s" % [elapsed, str(result.terminal)])
		_check(int(snap.get("elapsed_ticks", -1)) == elapsed
			and int(snap.get("tick_count", -1)) == t0 + elapsed,
			"frame-account: step_accounted boundary reports exactly %d accounted ticks" % requested,
			"snap_elapsed=%s snap_ticks=%s" % [
				snap.get("elapsed_ticks"), snap.get("tick_count")])
		_check(ext_delta == elapsed and coord_delta == elapsed,
			"frame-account: independent physics-frame tally at step_accounted matches logical ticks",
			"requested=%d elapsed=%d ext_frames=%d coord_frames=%d tick_count=%d->%d" % [
				requested, elapsed, ext_delta, coord_delta, t0, coord.tick_count])
		# Any trailing engine callback after completion must not advance the sim.
		await _wait_physics_frames(1)
		_check(coord.tick_count == t0 + elapsed,
			"frame-account: trailing frozen callback advanced no logical tick",
			"ticks=%d expected=%d" % [coord.tick_count, t0 + elapsed])


## While the trainer wait is frozen, engine frames continue but no logical tick
## or body motion may occur.
func _test_frozen_zero_advance() -> void:
	await _configure(10.0)
	coord.reset()
	await _step(12)
	var t0: int = coord.tick_count
	var z0: float = coord.body.global_position.z
	var ef0 := ext_physics_frames
	coord.set_frozen(true)
	await _wait_physics_frames(30)
	_check(ext_physics_frames - ef0 >= 30,
		"frozen: engine physics frames continued while waiting",
		"frames=%d" % (ext_physics_frames - ef0))
	_check(coord.tick_count == t0 and coord.body.global_position.z == z0,
		"frozen: zero logical advancement and no motion while waiting",
		"ticks=%d->%d z=%.9f->%.9f" % [t0, coord.tick_count, z0, coord.body.global_position.z])
	coord.set_frozen(false)


## A pre-reset step result must never be retrievable through take_result().
func _test_stale_result_after_reset() -> void:
	await _configure(10.0)
	coord.reset()
	var first: Dictionary = await _step(12)
	_check(int(first.elapsed_ticks) == 12,
		"stale-result: first step returned 12 ticks",
		"elapsed=%d" % int(first.elapsed_ticks))
	coord.reset()
	var after_take: Dictionary = coord.take_result()
	_check(after_take.is_empty(),
		"stale-result: take_result after reset returns empty",
		"keys=%s" % str(after_take.keys()))
	_check(not coord.has_pending_result(),
		"stale-result: reset cleared the pending-result flag")
	# The untaken-pending path must also be discarded by reset.
	coord.begin_step(12)
	await _wait_pending()
	coord.reset()
	var after_untaken: Dictionary = coord.take_result()
	_check(after_untaken.is_empty(),
		"stale-result: reset discards an untaken pending result",
		"keys=%s" % str(after_untaken.keys()))


## max_ticks <= 0 is an explicit exhausted budget: zero ticks, zero motion, no
## unintended first tick. The one-tick boundary must execute exactly one tick.
func _test_zero_tick_budget() -> void:
	await _configure(10.0, INF, 0)
	coord.reset()
	var z0: float = coord.body.global_position.z
	var ef0 := ext_physics_frames
	coord.begin_step(12)
	var immediate: bool = coord.has_pending_result()
	var result: Dictionary = coord.take_result()
	_check(immediate and int(result.elapsed_ticks) == 0 and str(result.terminal) == "truncated",
		"zero-budget: cap 0 emits a zero-tick truncated result without awaiting a frame",
		"immediate=%s elapsed=%d terminal=%s" % [str(immediate), int(result.elapsed_ticks), str(result.terminal)])
	_check(coord.tick_count == 0 and coord.body.global_position.z == z0,
		"zero-budget: cap 0 executed no tick and moved nothing",
		"ticks=%d z_delta=%.9f" % [coord.tick_count, coord.body.global_position.z - z0])
	_check(ext_physics_frames == ef0,
		"zero-budget: cap 0 consumed no engine physics frame")
	await _wait_process_frames(5)
	_check(coord.tick_count == 0 and coord.body.global_position.z == z0,
		"zero-budget: still zero ticks after further engine frames")
	await _configure(10.0, INF, -3)
	coord.reset()
	var negative: Dictionary = await _step(12)
	_check(int(negative.elapsed_ticks) == 0 and str(negative.terminal) == "truncated",
		"zero-budget: negative cap behaves as zero, not one tick",
		"elapsed=%d terminal=%s" % [int(negative.elapsed_ticks), str(negative.terminal)])
	await _configure(10.0, INF, 1)
	coord.reset()
	var one_tick: Dictionary = await _step(12)
	_check(int(one_tick.elapsed_ticks) == 1 and str(one_tick.terminal) == "truncated"
		and coord.tick_count == 1,
		"zero-budget: one-tick boundary executes exactly one tick",
		"elapsed=%d terminal=%s ticks=%d" % [int(one_tick.elapsed_ticks), str(one_tick.terminal), coord.tick_count])


## The bounded substep envelope is MAX_SUBSTEPS * SUBSTEP_MAX_LEN (4 m/tick,
## 240 m/s). At the bound the step succeeds; above it the coordinator refuses
## loudly with terminal motion_bound instead of dropping the remainder.
func _test_motion_bound() -> void:
	await _configure(CoordinatorScript.MAX_SUPPORTED_SPEED_MPS)
	coord.reset()
	var boundary: Dictionary = await _step(12)
	_check(str(boundary.terminal) == "none" and int(boundary.elapsed_ticks) == 12
		and coord.motion_bound_violations == 0,
		"work-boundary: supported speed completes 12 ticks without refusal",
		"elapsed=%d terminal=%s violations=%d" % [int(boundary.elapsed_ticks), str(boundary.terminal), coord.motion_bound_violations])
	_check(coord.max_substep_len <= 0.25 + 1e-6,
		"work-boundary: substep length stayed within the cap",
		"max_substep=%.6f" % coord.max_substep_len)

	await _configure(250.0)
	coord.reset()
	var z0: float = coord.body.global_position.z
	var t0: int = coord.tick_count
	var over: Dictionary = await _step(12)
	_check(str(over.terminal) == "motion_bound" and int(over.elapsed_ticks) == 0,
		"work-envelope: over-bound speed is refused explicitly",
		"elapsed=%d terminal=%s" % [int(over.elapsed_ticks), str(over.terminal)])
	_check(coord.tick_count == t0 and coord.body.global_position.z == z0,
		"work-envelope: refused command advanced no tick and moved nothing",
		"ticks=%d z_delta=%.9f" % [coord.tick_count, coord.body.global_position.z - z0])
	_check(coord.motion_bound_violations >= 1 and coord.last_motion_bound_deficit_m > 0.0,
		"work-envelope: residual deficit is recorded, not silently dropped",
		"violations=%d deficit=%.9f m" % [coord.motion_bound_violations, coord.last_motion_bound_deficit_m])

	await _configure(-250.0)
	coord.reset()
	var reverse: Dictionary = await _step(12)
	_check(str(reverse.terminal) == "motion_bound" and int(reverse.elapsed_ticks) == 0,
		"work-envelope: reverse over-bound speed is refused too",
		"elapsed=%d terminal=%s" % [int(reverse.elapsed_ticks), str(reverse.terminal)])


## The waiting contract: reset, zero-tick requests and exhausted budgets must
## leave the authoritative world physically frozen. An independent
## RigidBody3D proves physical stasis, not just a zero logical tick count.
func _test_wait_guard() -> void:
	await _configure(10.0)
	coord.reset()
	_check(get_tree().paused, "wait-guard: reset leaves the authoritative world frozen")

	# Control: the same independent body does fall when the world is run. Spawn
	# it while unpaused so the engine activates the body normally.
	coord.set_frozen(false)
	var ambient := _spawn_ambient(10.0)
	await _wait_ambient_below(ambient, 9.5)
	_check(ambient.global_position.y <= 9.5,
		"wait-guard: control body falls while the world is deliberately running",
		"y=%.9f" % ambient.global_position.y)

	coord.reset()
	var y_reset: float = ambient.global_position.y
	var f0 := ext_physics_frames
	await _wait_physics_frames(30)
	_check(ext_physics_frames - f0 >= 30,
		"wait-guard: engine physics frames continued while frozen after reset",
		"frames=%d" % (ext_physics_frames - f0))
	_check(ambient.global_position.y == y_reset,
		"wait-guard: independent body did not drift after reset",
		"y=%.9f->%.9f" % [y_reset, ambient.global_position.y])
	_check(coord.tick_count == 0, "wait-guard: zero logical ticks after reset")

	# A zero-tick request ends frozen too.
	coord.set_frozen(false)
	await _wait_ambient_below(ambient, y_reset - 0.2)
	var zero: Dictionary = await _step(0)
	_check(int(zero.elapsed_ticks) == 0 and str(zero.terminal) == "none",
		"wait-guard: zero-tick request is a nonterminal zero step",
		"elapsed=%d terminal=%s" % [int(zero.elapsed_ticks), str(zero.terminal)])
	_check(get_tree().paused, "wait-guard: zero-tick request leaves the world frozen")
	var y_zero: float = ambient.global_position.y
	f0 = ext_physics_frames
	await _wait_physics_frames(30)
	_check(ambient.global_position.y == y_zero,
		"wait-guard: independent body did not drift after a zero-tick request",
		"y=%.9f->%.9f" % [y_zero, ambient.global_position.y])
	_check(coord.tick_count == 0, "wait-guard: zero logical ticks after a zero-tick request")
	ambient.queue_free()

	# Exhausted budget after reset is the same frozen waiting state.
	await _configure(10.0, INF, 0)
	coord.reset()
	coord.set_frozen(false)
	var ambient_cap := _spawn_ambient(10.0)
	await _wait_ambient_below(ambient_cap, 9.5)
	var capped: Dictionary = await _step(12)
	_check(int(capped.elapsed_ticks) == 0 and str(capped.terminal) == "truncated",
		"wait-guard: exhausted-budget request is zero-tick truncated",
		"elapsed=%d terminal=%s" % [int(capped.elapsed_ticks), str(capped.terminal)])
	_check(get_tree().paused, "wait-guard: exhausted-budget request freezes the world")
	var y_cap: float = ambient_cap.global_position.y
	f0 = ext_physics_frames
	await _wait_physics_frames(30)
	_check(ambient_cap.global_position.y == y_cap,
		"wait-guard: independent body did not drift after an exhausted-budget request",
		"y=%.9f->%.9f" % [y_cap, ambient_cap.global_position.y])
	ambient_cap.queue_free()


## Overlapping, untaken-result and negative begin_step calls are refused
## without disturbing current accounting.
func _test_begin_step_refusals() -> void:
	await _configure(10.0)
	coord.reset()
	var ok_first: bool = coord.begin_step(12)
	_check(ok_first, "begin-step: first request accepted")
	await _wait_physics_frames(3)
	var mid: int = coord.tick_count
	var ok_overlap: bool = coord.begin_step(5)
	_check(not ok_overlap and coord.begin_step_refusals == 1,
		"begin-step: overlapping request refused",
		"ok=%s refusals=%d reason=%s" % [str(ok_overlap), coord.begin_step_refusals, coord.last_begin_step_refusal])
	var first: Dictionary = await _wait_pending_and_take()
	_check(int(first.elapsed_ticks) == 12 and coord.tick_count == 12,
		"begin-step: first request accounting survived the overlap attempt",
		"elapsed=%d ticks=%d->%d" % [int(first.elapsed_ticks), mid, coord.tick_count])

	var ticks_before_negative: int = coord.tick_count
	var ok_negative: bool = coord.begin_step(-1)
	_check(not ok_negative and coord.begin_step_refusals == 2,
		"begin-step: negative budget refused",
		"ok=%s refusals=%d reason=%s" % [str(ok_negative), coord.begin_step_refusals, coord.last_begin_step_refusal])
	_check(coord.tick_count == ticks_before_negative and not coord.has_pending_result(),
		"begin-step: negative refusal changed no accounting")

	var ok_third: bool = coord.begin_step(12)
	_check(ok_third, "begin-step: request after refusals accepted")
	await _wait_pending()
	var ticks_inflight: int = coord.tick_count
	var ok_untaken: bool = coord.begin_step(4)
	_check(not ok_untaken and coord.begin_step_refusals == 3,
		"begin-step: untaken-result overlap refused",
		"ok=%s refusals=%d reason=%s" % [str(ok_untaken), coord.begin_step_refusals, coord.last_begin_step_refusal])
	_check(coord.tick_count == ticks_inflight,
		"begin-step: untaken refusal changed no accounting")
	var third: Dictionary = coord.take_result()
	_check(int(third.elapsed_ticks) == 12,
		"begin-step: pending result still readable after a refusal")


## A positive request must receive one physics-server integration per logical
## tick once the world is warm. Freezing inside the physics callback would
## suppress the final tick's engine step; the counting body measures it.
func _spawn_counting_body() -> RigidBody3D:
	var dyn: RigidBody3D = CountingBody.new()
	dyn.can_sleep = false
	dyn.linear_damp = 0.0
	dyn.gravity_scale = 1.0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	shape.shape = sphere
	dyn.add_child(shape)
	dyn.position = Vector3(5, 1000, 0)
	coord.add_child(dyn)
	return dyn


func _test_dynamic_server_steps() -> void:
	# First request from a frozen world with a freshly created active body:
	# exactly one server integration, not a registration-delayed zero.
	await _configure(10.0)
	coord.reset()
	var first: RigidBody3D = _spawn_counting_body()
	var first_result: Dictionary = await _step(1)
	_check(first.server_steps == 1,
		"dynamic-steps: first one-tick request integrates exactly one server step",
		"server_steps=%d elapsed=%d" % [first.server_steps, int(first_result.elapsed_ticks)])
	_check(bool(last_signal.get("paused", false)),
		"dynamic-steps: first request publishes while frozen")
	first.queue_free()

	# Fresh body, no warm-up: repeated 12-tick requests integrate exactly 12.
	await _configure(10.0)
	coord.reset()
	var dyn: RigidBody3D = _spawn_counting_body()
	var emission_steps: Array[int] = []
	var emission_observer = func(_result: Dictionary) -> void:
		emission_steps.append(dyn.server_steps)
	coord.step_finished.connect(emission_observer)
	for i in 2:
		var before: int = dyn.server_steps
		var result: Dictionary = await _step(12)
		var delta: int = dyn.server_steps - before
		_check(delta == 12,
			"dynamic-steps: 12-tick request integrates exactly 12 server steps (#%d)" % (i + 1),
			"server_steps_delta=%d elapsed=%d" % [delta, int(result.elapsed_ticks)])
		_check(bool(last_signal.get("paused", false)),
			"dynamic-steps: request completion publishes while frozen (#%d)" % (i + 1))
		_check(emission_steps.size() > i and emission_steps[i] == 12 * (i + 1),
			"dynamic-steps: step_finished observes the post-server-step count (#%d)" % (i + 1),
			"observed=%s expected=%d" % [str(emission_steps), 12 * (i + 1)])
	coord.step_finished.disconnect(emission_observer)

	var s_wait: int = dyn.server_steps
	var y_wait: float = dyn.global_position.y
	var v_wait: float = dyn.last_state_linear_velocity.y
	await _wait_physics_frames(30)
	_check(dyn.server_steps == s_wait,
		"dynamic-steps: frozen wait adds no server steps",
		"steps=%d->%d" % [s_wait, dyn.server_steps])
	_check(dyn.global_position.y == y_wait and dyn.last_state_linear_velocity.y == v_wait,
		"dynamic-steps: frozen wait has zero body drift",
		"y=%.9f->%.9f" % [y_wait, dyn.global_position.y])
	dyn.queue_free()


## Synchronous completion listeners must not reenter begin_step() or leave a
## stale result after reset(). The coordinator arms publication state before
## dispatching observers and cancels it if reset() runs during dispatch.
func _test_completion_callback_reentrancy() -> void:
	# begin_step() from step_accounted is refused; original result still valid.
	await _configure(10.0)
	coord.reset()
	completion_probe = "accounting_begin"
	completion_probe_reentry = true
	coord.begin_step(1)
	await _wait_pending_and_take_bounded()
	var r1: Dictionary = coord.take_result()
	_check(not completion_probe_reentry,
		"completion-callback: begin_step refused inside step_accounted",
		"accepted=%s" % str(completion_probe_reentry))
	_check(int(r1.get("elapsed_ticks", -1)) == 1 and int(r1.get("tick_count", -1)) == 1,
		"completion-callback: accounting reentry did not hijack the result",
		"elapsed=%s ticks=%s live=%d" % [r1.get("elapsed_ticks"), r1.get("tick_count"), coord.tick_count])
	completion_probe = ""

	# begin_step() from step_finished is refused; pending result survives.
	await _configure(10.0)
	coord.reset()
	completion_probe = "finished_begin"
	completion_probe_reentry = true
	coord.begin_step(1)
	await _wait_pending_and_take_bounded()
	var r2: Dictionary = coord.take_result()
	_check(not completion_probe_reentry,
		"completion-callback: begin_step refused inside step_finished",
		"accepted=%s" % str(completion_probe_reentry))
	_check(int(r2.get("elapsed_ticks", -1)) == 1 and int(r2.get("tick_count", -1)) == 1,
		"completion-callback: finished reentry did not disturb the result")
	completion_probe = ""

	# reset() inside step_accounted cancels the old result completely.
	await _configure(10.0)
	coord.reset()
	completion_probe = "accounting_reset"
	coord.begin_step(1)
	await _wait_physics_frames(5)
	var pending_after_acc: bool = coord.has_pending_result()
	var stale_acc: Dictionary = coord.take_result()
	_check(not pending_after_acc and stale_acc.is_empty(),
		"completion-callback: reset in step_accounted leaves no stale result",
		"pending=%s keys=%s" % [str(pending_after_acc), str(stale_acc.keys())])
	_check(coord.tick_count == 0 and get_tree().paused,
		"completion-callback: reset in step_accounted restores tick 0/frozen")
	completion_probe = ""

	# reset() inside step_finished also cancels publication.
	await _configure(10.0)
	coord.reset()
	completion_probe = "finished_reset"
	coord.begin_step(1)
	await _wait_physics_frames(5)
	var pending_after_fin: bool = coord.has_pending_result()
	var stale_fin: Dictionary = coord.take_result()
	_check(not pending_after_fin and stale_fin.is_empty(),
		"completion-callback: reset in step_finished leaves no stale result",
		"pending=%s keys=%s" % [str(pending_after_fin), str(stale_fin.keys())])
	_check(coord.tick_count == 0 and get_tree().paused,
		"completion-callback: reset in step_finished restores tick 0/frozen")
	completion_probe = ""


## API edge regressions: negative requests are refused even on a consumed
## terminal episode; zero-tick completion publishes while frozen; an exhausted
## budget starts the observation in the truncated state.
func _test_api_edges() -> void:
	await _configure(10.0, INF, 1)
	coord.reset()
	var terminal_result: Dictionary = await _step(12)
	_check(str(terminal_result.terminal) == "truncated",
		"api-edge: one-tick cap reaches a consumed terminal result",
		"elapsed=%d terminal=%s" % [int(terminal_result.elapsed_ticks), str(terminal_result.terminal)])
	var ticks_before: int = coord.tick_count
	var refusals_before: int = coord.begin_step_refusals
	var accepted_negative: bool = coord.begin_step(-2)
	_check(not accepted_negative and coord.begin_step_refusals == refusals_before + 1,
		"api-edge: negative request refused after consumed terminal",
		"accepted=%s refusals=%d reason=%s" % [str(accepted_negative), coord.begin_step_refusals, coord.last_begin_step_refusal])
	_check(not coord.has_pending_result(),
		"api-edge: negative terminal request published no result")
	_check(coord.tick_count == ticks_before,
		"api-edge: negative terminal request changed no tick",
		"ticks=%d expected=%d" % [coord.tick_count, ticks_before])
	_check(int(last_signal.get("requested_ticks", -1)) == int(terminal_result.requested_ticks),
		"api-edge: last signal still belongs to the consumed step")

	# Zero-tick completion must be published with the waiting freeze in effect.
	await _configure(10.0)
	coord.reset()
	var accepted_zero: bool = coord.begin_step(0)
	var snap_zero: Dictionary = last_signal
	_check(accepted_zero and bool(snap_zero.get("paused", false)),
		"api-edge: zero-tick signal observed with the world frozen",
		"accepted=%s paused_at_signal=%s" % [str(accepted_zero), snap_zero.get("paused")])
	_check(int(snap_zero.get("elapsed_ticks", -1)) == 0
		and str(snap_zero.get("terminal", "")) == "none",
		"api-edge: zero-tick signal carries an empty nonterminal result",
		"elapsed=%s terminal=%s" % [snap_zero.get("elapsed_ticks"), snap_zero.get("terminal")])
	var zero_result: Dictionary = coord.take_result()
	_check(int(zero_result.elapsed_ticks) == 0 and get_tree().paused,
		"api-edge: zero-tick request leaves the frozen waiting state")

	# An exhausted budget starts truncated in the observation too.
	await _configure(10.0, INF, 0)
	var obs: Dictionary = coord.reset()
	_check(str(obs.terminal) == "truncated",
		"api-edge: cap-0 reset observation starts truncated",
		"terminal=%s paused=%s" % [str(obs.terminal), str(get_tree().paused)])
	var capped: Dictionary = await _step(12)
	_check(int(capped.elapsed_ticks) == 0 and str(capped.terminal) == "truncated",
		"api-edge: cap-0 request stays zero-tick truncated",
		"elapsed=%d terminal=%s" % [int(capped.elapsed_ticks), str(capped.terminal)])


## Negative control: twelve direct physics calls outside any coordinator request
## move the body but consume no accounted logical tick. Call count alone is not
## evidence of accounted world steps.
func _test_bypass_negative_control() -> void:
	await _configure(10.0)
	coord.reset()
	var z0: float = coord.body.global_position.z
	var t0: int = coord.tick_count
	for i in 12:
		coord.body.move_and_collide(Vector3(0, 0, -10.0 / 60.0))
	_check(coord.tick_count == t0,
		"bypass-negative: direct physics calls consumed zero logical ticks",
		"ticks=%d" % coord.tick_count)
	_check(absf((z0 - coord.body.global_position.z) - 2.0) < 1e-4,
		"bypass-negative: direct calls still moved the body outside tick accounting",
		"moved=%.9f m" % (z0 - coord.body.global_position.z))


## Pause ownership: the coordinator owns SceneTree.paused for the probe world;
## begin_step clears an externally-set pause and then steps normally.
func _test_pause_ownership() -> void:
	await _configure(10.0)
	coord.reset()
	get_tree().paused = true
	await _wait_physics_frames(2)
	coord.begin_step(12)
	_check(not get_tree().paused,
		"pause-ownership: begin_step clears an externally set pause")
	await _wait_pending()
	var result: Dictionary = coord.take_result()
	_check(int(result.elapsed_ticks) == 12,
		"pause-ownership: stepping proceeds after clearing the external pause",
		"elapsed=%d" % int(result.elapsed_ticks))
	coord.set_frozen(false)


func _finish() -> void:
	var report := {
		"schema": "roadstorm.tick_probe.contract.v1",
		"checks_total": checks,
		"checks_failed": failures.size(),
		"failures": failures,
	}
	print("TEST_RESULT ", JSON.stringify(report))
	print("TESTS_TOTAL=", checks, " TESTS_FAILED=", failures.size())
	await get_tree().process_frame
	get_tree().quit(1 if failures.size() > 0 else 0)
