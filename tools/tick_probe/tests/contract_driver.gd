extends Node
## Independent focused contract tests for the M0.8 tick probe.
##
## Deliberately separate from probe_driver.gd: this suite counts
## SceneTree.physics_frame itself, so the coordinator's logical tick accounting
## is checked against an independent engine-frame count rather than trusted.
## Negative controls show that raw call counts and direct physics calls are not
## evidence of accounted logical ticks.

const CoordinatorScript := preload("res://src/tick_coordinator.gd")

var coord
var ext_physics_frames := 0
var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().physics_frame.connect(_on_engine_physics_frame)
	coord = CoordinatorScript.new()
	get_tree().root.add_child(coord)
	await get_tree().process_frame
	await _test_frame_accounting()
	await _test_frozen_zero_advance()
	await _test_stale_result_after_reset()
	await _test_zero_tick_budget()
	await _test_motion_bound()
	await _test_wait_guard()
	await _test_begin_step_refusals()
	await _test_bypass_negative_control()
	await _test_pause_ownership()
	_finish()


func _on_engine_physics_frame() -> void:
	ext_physics_frames += 1


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
		var ext_delta := ext_physics_frames - ef0
		var coord_delta: int = coord.engine_physics_frames - cf0
		_check(elapsed == requested,
			"frame-account: request %d consumed exactly %d logical ticks" % [requested, requested],
			"elapsed=%d terminal=%s" % [elapsed, str(result.terminal)])
		_check(ext_delta == elapsed and coord_delta == elapsed and coord.tick_count == t0 + elapsed,
			"frame-account: independent physics-frame count matches logical ticks",
			"requested=%d elapsed=%d ext_frames=%d coord_frames=%d tick_count=%d->%d" % [
				requested, elapsed, ext_delta, coord_delta, t0, coord.tick_count])


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
