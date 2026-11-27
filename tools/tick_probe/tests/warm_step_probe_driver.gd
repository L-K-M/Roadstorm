extends Node
## Warmed independent-body server-step probe (F2/F3 evidence).
##
## Scenarios print WARM_METRIC lines and assert the exact request gates:
## an idle warmed 12-tick request integrates exactly 12 physics-server steps;
## a physics-callback-origin request stays frozen at the call and integrates
## exactly 12 with no unaccounted unpaused iteration; a warmed over-envelope
## refusal integrates nothing. A repeated immediate request is recorded as an
## informational engine-boundary metric (not gated).

const CoordinatorScript := preload("res://src/tick_coordinator.gd")
const CountingBody := preload("res://tests/counting_body.gd")
const CallbackObserver := preload("res://tests/callback_observer.gd")

class Caller extends Node:
	var coord
	var fired := false
	var accepted := false
	var paused_after_call := false
	func _physics_process(_delta: float) -> void:
		if not fired and coord != null:
			fired = true
			accepted = coord.begin_step(12)
			paused_after_call = get_tree().paused

var coord
var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	coord = CoordinatorScript.new()
	get_tree().root.add_child(coord)
	await get_tree().process_frame
	await _warmed_idle()
	await _physics_caller()
	await _motion_bound()
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

func _spawn() -> RigidBody3D:
	var body: RigidBody3D = CountingBody.new()
	body.can_sleep = false
	body.linear_damp = 0.0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	shape.shape = sphere
	body.add_child(shape)
	body.position = Vector3(5, 1000, 0)
	coord.add_child(body)
	return body

func _wait_frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _take_after(n: int) -> Dictionary:
	coord.begin_step(n)
	var guard := 0
	while not coord.has_pending_result() and guard < 200000:
		await get_tree().process_frame
		guard += 1
	return coord.take_result()

func _settle_warm_body() -> RigidBody3D:
	var body := _spawn()
	coord.set_frozen(false)
	await _wait_frames(5)
	coord.set_frozen(true)
	await _wait_frames(2)
	return body

func _warmed_idle() -> void:
	coord.configure(10.0, INF, 1000000, NAN)
	coord.reset()
	var body: RigidBody3D = await _settle_warm_body()
	var before: int = body.server_steps
	var pf_before: int = Engine.get_physics_frames()
	var result: Dictionary = await _take_after(12)
	var delta: int = body.server_steps - before
	var pf_delta: int = Engine.get_physics_frames() - pf_before
	print("WARM_METRIC warmed_idle requested=12 elapsed=%d server_steps_delta=%d pf_delta=%d" % [
		int(result.elapsed_ticks), delta, pf_delta])
	_check(delta == 12 and int(result.elapsed_ticks) == 12,
		"warm-probe: warmed idle request integrates exactly 12 server steps",
		"delta=%d elapsed=%d" % [delta, int(result.elapsed_ticks)])

	# Immediate repeated request: informational engine-boundary variance.
	var before2: int = body.server_steps
	var r2: Dictionary = await _take_after(12)
	var delta2: int = body.server_steps - before2
	print("WARM_METRIC immediate_repeat requested=12 elapsed=%d server_steps_delta=%d" % [
		int(r2.elapsed_ticks), delta2])
	body.queue_free()

func _physics_caller() -> void:
	coord.configure(10.0, INF, 1000000, NAN)
	coord.reset()
	var body: RigidBody3D = await _settle_warm_body()
	var caller := Caller.new()
	caller.coord = coord
	caller.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(caller)
	var observer := CallbackObserver.new()
	get_tree().root.add_child(observer)
	var before: int = body.server_steps
	var obs_before: int = observer.unpaused_physics_callbacks
	var guard := 0
	while not coord.has_pending_result() and guard < 200000:
		await get_tree().process_frame
		guard += 1
	var result: Dictionary = coord.take_result()
	var delta: int = body.server_steps - before
	var obs_delta: int = observer.unpaused_physics_callbacks - obs_before
	print("WARM_METRIC physics_caller requested=12 elapsed=%d server_steps_delta=%d paused_after_call=%s unpaused_observer_delta=%d" % [
		int(result.elapsed_ticks), delta, str(caller.paused_after_call), obs_delta])
	_check(caller.accepted and caller.paused_after_call,
		"warm-probe: physics-callback request stays frozen at the call",
		"accepted=%s paused=%s" % [str(caller.accepted), str(caller.paused_after_call)])
	_check(delta == 12 and int(result.elapsed_ticks) == 12,
		"warm-probe: physics-callback request integrates exactly 12 server steps",
		"delta=%d elapsed=%d" % [delta, int(result.elapsed_ticks)])
	_check(obs_delta == 11,
		"warm-probe: no unaccounted unpaused iteration precedes the first tick",
		"unpaused_observer_delta=%d expected=11" % obs_delta)
	caller.queue_free()
	observer.queue_free()
	body.queue_free()

func _motion_bound() -> void:
	coord.configure(250.0, INF, 1000000, NAN)
	coord.reset()
	var body: RigidBody3D = await _settle_warm_body()
	var before: int = body.server_steps
	var result: Dictionary = await _take_after(12)
	var delta: int = body.server_steps - before
	print("WARM_METRIC motion_bound requested=12 elapsed=%d terminal=%s server_steps_delta=%d" % [
		int(result.elapsed_ticks), str(result.terminal), delta])
	_check(delta == 0 and int(result.elapsed_ticks) == 0 and str(result.terminal) == "motion_bound",
		"warm-probe: warmed over-envelope refusal integrates no server step",
		"delta=%d elapsed=%d terminal=%s" % [delta, int(result.elapsed_ticks), str(result.terminal)])
	body.queue_free()

func _finish() -> void:
	var report := {
		"schema": "roadstorm.tick_probe.warm_step.v1",
		"checks_total": checks,
		"checks_failed": failures.size(),
		"failures": failures,
	}
	print("WARM_RESULT ", JSON.stringify(report))
	await get_tree().process_frame
	get_tree().quit(1 if failures.size() > 0 else 0)
