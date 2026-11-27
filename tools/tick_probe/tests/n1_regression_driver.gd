extends Node
## N1/cold-start regression: every positive coordinator request must receive
## one physics-server integration step per logical tick, including the first
## request after a freshly created body enters a frozen world.
##
## A counting RigidBody3D measures this directly. The unfixed behavior pauses
## inside the final physics callback and loses that tick's server step (11
## steps per 12-tick request). A continuous cold baseline is recorded as a
## registration-latency control: a body created while paused is registered on
## its first unpaused server step and integrates from the second, so the
## baseline alone cannot establish request semantics.

const CoordinatorScript := preload("res://src/tick_coordinator.gd")
const CountingBody := preload("res://tests/counting_body.gd")

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

	await _request_scenario("single_1", [1])
	await _request_scenario("single_12", [12])
	await _request_scenario("repeated_12", [12, 12])
	await _continuous_control(1)
	await _continuous_control(12)

	# Frozen waiting after a completed request must integrate nothing.
	coord.configure(10.0, INF, 1000000, NAN)
	coord.reset()
	var dyn: RigidBody3D = _spawn()
	await _step(12)
	var wait_before: int = dyn.server_steps
	var y_before: float = dyn.global_position.y
	await _wait_physics_frames(30)
	_check(dyn.server_steps == wait_before and dyn.global_position.y == y_before,
		"n1: frozen waiting integrates no server step and moves no body",
		"steps=%d->%d y=%.9f->%.9f" % [wait_before, dyn.server_steps, y_before, dyn.global_position.y])
	dyn.queue_free()

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


func _spawn(y: float = 1000.0) -> RigidBody3D:
	var body: RigidBody3D = CountingBody.new()
	body.can_sleep = false
	body.linear_damp = 0.0
	body.gravity_scale = 1.0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	shape.shape = sphere
	body.add_child(shape)
	body.position = Vector3(5, y, 0)
	coord.add_child(body)
	return body


func _wait_physics_frames(count: int) -> void:
	var target := ext_physics_frames + count
	var guard := 0
	while ext_physics_frames < target:
		await get_tree().process_frame
		guard += 1
		if guard > 200000:
			return


func _step(requested: int) -> Dictionary:
	coord.begin_step(requested)
	var guard := 0
	while not coord.has_pending_result():
		await get_tree().process_frame
		guard += 1
		if guard > 200000:
			return {"elapsed_ticks": -1, "terminal": "timeout"}
	return coord.take_result()


## Fresh body in a frozen world; every request must integrate exactly its own
## logical ticks, including the first one.
func _request_scenario(label: String, requests: Array) -> void:
	coord.configure(10.0, INF, 1000000, NAN)
	coord.reset()
	var body: RigidBody3D = _spawn()
	for i in requests.size():
		var before: int = body.server_steps
		var pf_before: int = Engine.get_physics_frames()
		var result: Dictionary = await _step(int(requests[i]))
		var delta: int = body.server_steps - before
		var pf_delta: int = Engine.get_physics_frames() - pf_before
		print("N1_METRIC %s idx=%d requested=%d elapsed=%d server_steps_delta=%d engine_pf_delta=%d first_integ_pf=%d paused=%s" % [
			label, i, int(requests[i]), int(result.elapsed_ticks), delta, pf_delta,
			body.first_integration_physics_frame, str(get_tree().paused)])
		_check(delta == int(requests[i]),
			"n1: %s request #%d integrates exactly %d server steps" % [label, i + 1, int(requests[i])],
			"delta=%d elapsed=%d paused=%s" % [delta, int(result.elapsed_ticks), str(get_tree().paused)])
		_check(pf_delta == int(requests[i]) + 1,
			"n1: %s request #%d accounts one pause-callback frame beyond its ticks" % [label, i + 1],
			"engine_pf_delta=%d" % pf_delta)
	_check(body.last_state_linear_velocity.y == body.linear_velocity.y,
		"n1: %s observed velocity matches the last counted integration" % label,
		"state=%.9f property=%.9f" % [body.last_state_linear_velocity.y, body.linear_velocity.y])
	body.queue_free()


## Continuous cold baseline: a body created while paused is registered on its
## first unpaused server step and integrates from the second (registration
## latency). This control explains why a naive continuous comparison does not
## establish request semantics; it is not used as the request gate.
func _continuous_control(k: int) -> void:
	coord.configure(10.0, INF, 1000000, NAN)
	coord.reset()
	var body: RigidBody3D = _spawn()
	coord.set_frozen(false)
	var pf_before: int = Engine.get_physics_frames()
	await _wait_physics_frames(k)
	var delta: int = body.server_steps
	var pf_delta: int = Engine.get_physics_frames() - pf_before
	print("N1_METRIC continuous_control k=%d server_steps_delta=%d engine_pf_delta=%d first_integ_pf=%d" % [
		k, delta, pf_delta, body.first_integration_physics_frame])
	_check(delta <= k - 1,
		"n1: continuous cold baseline shows registration latency (%d frames)" % k,
		"server_steps_delta=%d expected<=k-1=%d" % [delta, k - 1])
	coord.set_frozen(true)
	body.queue_free()


func _finish() -> void:
	var report := {
		"schema": "roadstorm.tick_probe.n1.v1",
		"checks_total": checks,
		"checks_failed": failures.size(),
		"failures": failures,
	}
	print("N1_RESULT ", JSON.stringify(report))
	print("N1_TOTAL=", checks, " N1_FAILED=", failures.size())
	await get_tree().process_frame
	get_tree().quit(1 if failures.size() > 0 else 0)
