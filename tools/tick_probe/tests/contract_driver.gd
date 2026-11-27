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
	await _wait_process_frames(30)
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
	await _wait_process_frames(2)
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
