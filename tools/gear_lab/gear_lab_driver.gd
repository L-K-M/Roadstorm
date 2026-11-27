class_name GearLabDriver
extends RefCounted
## Black-box helpers shared by the M1.1 automatic-gearbox checks.
##
## This driver never re-implements gearbox math: it constructs explicit
## configurations and `CarState` records, calls the real `AutomaticGearbox`,
## and compares measured invariants, paired runs and replays. Failures are
## collected rather than pushed through the engine error path so the runner can
## emit machine-readable results and control its exit code.

const AutomaticGearboxScript = preload("res://src/simulation/automatic_gearbox.gd")
const CarStateScript = preload("res://src/simulation/car_state.gd")


var checks := 0
var failures: Array[String] = []
var measured: Dictionary = {}


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func check_eq(actual, expected, message: String) -> void:
	checks += 1
	if actual != expected:
		failures.append(
			"%s (actual=%s expected=%s)" % [message, str(actual), str(expected)]
		)


func check_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	checks += 1
	if is_nan(actual) or is_inf(actual) or absf(actual - expected) > tolerance:
		failures.append(
			"%s (actual=%s expected=%s tol=%s)"
			% [message, str(actual), str(expected), str(tolerance)]
		)


func check_between(value: float, low: float, high: float, message: String) -> void:
	checks += 1
	if is_nan(value) or is_inf(value) or value < low or value > high:
		failures.append(
			"%s (value=%s range=[%s,%s])"
			% [message, str(value), str(low), str(high)]
		)


func measure(key: String, value) -> void:
	measured[key] = value


## Provisional defaults spanning the committed 0-45 m/s motor envelope.
func default_config():
	var config := AutomaticGearboxScript.GearboxConfig.new()
	return config


## Explicit configuration builder for boundary cases. All values are test
## inputs, not frozen product coefficients.
func config(
	forward_gear_count: int,
	upshift_speeds_m_s: Array,
	downshift_speeds_m_s: Array,
	min_shift_dwell_s: float,
	min_hysteresis_gap_m_s: float,
	reverse_exit_forward_speed_m_s: float,
	top_reference_speed_m_s: float
):
	var built := AutomaticGearboxScript.GearboxConfig.new()
	built.forward_gear_count = forward_gear_count
	set_upshift_speeds(built, upshift_speeds_m_s)
	set_downshift_speeds(built, downshift_speeds_m_s)
	built.min_shift_dwell_s = min_shift_dwell_s
	built.min_hysteresis_gap_m_s = min_hysteresis_gap_m_s
	built.reverse_exit_forward_speed_m_s = reverse_exit_forward_speed_m_s
	built.top_reference_speed_m_s = top_reference_speed_m_s
	return built


## Typed-array assignment helpers: an untyped Array literal cannot be assigned
## directly to an `Array[float]` member.
func set_upshift_speeds(config, values: Array) -> void:
	var typed: Array[float] = []
	for value in values:
		typed.append(float(value))
	config.upshift_speeds_m_s = typed


func set_downshift_speeds(config, values: Array) -> void:
	var typed: Array[float] = []
	for value in values:
		typed.append(float(value))
	config.downshift_speeds_m_s = typed


## Road-plane car record with a pure longitudinal velocity along +y at zero
## heading. Only the fields the gearbox reads are meaningful here.
func make_car(forward_speed_m_s: float, reverse_engaged: bool = false):
	var car := CarStateScript.new()
	car.velocity_m_s = Vector2(0.0, forward_speed_m_s)
	car.heading_rad = 0.0
	car.reverse_engaged = reverse_engaged
	return car


func fresh_gearbox(config = null):
	if config == null:
		return AutomaticGearboxScript.create(default_config())
	return AutomaticGearboxScript.create(config)


func step(gearbox, car, dt: float = AutomaticGearboxScript.DT):
	return gearbox.propose(car, dt)


func snapshot_car(car) -> Dictionary:
	if car == null:
		return {"null": true}
	return {
		"velocity_x": car.velocity_m_s.x,
		"velocity_y": car.velocity_m_s.y,
		"heading_rad": car.heading_rad,
		"reverse_engaged": car.reverse_engaged,
	}


func snapshot_proposal(proposal) -> Dictionary:
	if proposal == null:
		return {"null": true}
	var event_snapshot = null
	if proposal.event != null:
		event_snapshot = {
			"from_gear": proposal.event.from_gear,
			"to_gear": proposal.event.to_gear,
			"direction": int(proposal.event.direction),
			"normalized_rpm": proposal.event.normalized_rpm,
		}
	return {
		"gear_index": proposal.gear_index,
		"normalized_rpm": proposal.normalized_rpm,
		"shift_cooldown_s": proposal.state.shift_cooldown_s,
		"event": event_snapshot,
	}


## Run a `{s: speed, r: reverse}` schedule and return one proposal snapshot
## per tick. The real gearbox owns its state; no external state is threaded.
## Pass `gearbox` to replay onto an existing instance, otherwise a fresh one is
## created from `config`. A refused tick records null.
func replay_trace(config, specs: Array, gearbox = null) -> Array:
	var trace := []
	var owned = gearbox
	if owned == null:
		owned = fresh_gearbox(config)
	for spec in specs:
		var proposal = step(owned, make_car(float(spec["s"]), bool(spec["r"])))
		trace.append(snapshot_proposal(proposal))
	return trace


func event_count(trace: Array) -> int:
	var count := 0
	for entry in trace:
		if entry != null and entry.has("event") and entry["event"] != null:
			count += 1
	return count
