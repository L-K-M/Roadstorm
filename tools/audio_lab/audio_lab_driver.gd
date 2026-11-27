class_name AudioLabDriver
extends RefCounted
## Black-box numeric helpers shared by the M1.5 audio-lab checks.
##
## This driver never re-implements synthesis. It builds explicit
## `VehicleFeedbackSynth` requests, calls the real render API, decodes the
## returned PCM for measurement, and records failures so the validator can emit
## machine-readable results and control its exit code.

const Synth = preload("res://src/audio/vehicle_feedback_synth.gd")
const CarStateScript = preload("res://src/simulation/car_state.gd")
const DriverCommandScript = preload("res://src/simulation/driver_command.gd")

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
		failures.append("%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func check_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	checks += 1
	if is_nan(actual) or is_inf(actual) or absf(actual - expected) > tolerance:
		failures.append(
			"%s (actual=%s expected=%s tol=%s)" % [message, actual, expected, tolerance]
		)


func check_between(value: float, low: float, high: float, message: String) -> void:
	checks += 1
	if is_nan(value) or is_inf(value) or value < low - 1e-9 or value > high + 1e-9:
		failures.append(
			"%s (value=%s range=[%s,%s])" % [message, value, low, high]
		)


func measure(key: String, value) -> void:
	measured[key] = value


# --- Builders ---------------------------------------------------------------


func default_engine_tuning():
	var tuning = Synth.EngineTuning.new()
	return tuning


func default_tire_tuning():
	var tuning = Synth.TireTuning.new()
	return tuning


func engine_params(
	speed_m_s: float,
	throttle: float,
	duration_s: float = 0.5,
	loop_mode: int = Synth.LoopMode.ONE_SHOT
):
	return Synth.EngineParams.create(speed_m_s, throttle, duration_s, loop_mode)


func tire_params(
	slip_deg: float,
	speed_m_s: float,
	grounded: bool = true,
	duration_s: float = 0.5,
	loop_mode: int = Synth.LoopMode.ONE_SHOT
):
	return Synth.TireParams.create(slip_deg, speed_m_s, grounded, duration_s, loop_mode)


func make_car(
	forward_speed_m_s: float = 20.0,
	lateral_speed_m_s: float = 0.0,
	heading_rad: float = 0.0,
	grounded: bool = true
):
	var state = CarStateScript.new()
	state.velocity_m_s = Vector2(lateral_speed_m_s, forward_speed_m_s)
	state.heading_rad = heading_rad
	state.grounded = grounded
	return state


func command(throttle: float = 0.5, steer: float = 0.0):
	return DriverCommandScript.create(steer, throttle, 0.0, 0.0, false)


func render_engine(params, seed_value: int = 0, tuning = null):
	return Synth.render_engine(params, seed_value, tuning)


func render_tire(params, seed_value: int = 0, tuning = null):
	return Synth.render_tire(params, seed_value, tuning)


func render_bundle(car_state, cmd, seed_value: int = 0):
	return Synth.render_bundle(car_state, cmd, seed_value, null, null)


# --- Measurement ------------------------------------------------------------


func decode_segment(segment) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if segment == null:
		return out
	out.resize(segment.frame_count)
	for i in range(segment.frame_count):
		out[i] = segment.float_at(i)
	return out


func max_abs(samples: PackedFloat32Array) -> float:
	var peak := 0.0
	for value in samples:
		peak = maxf(peak, absf(value))
	return peak


## True when every decoded sample is finite (neither NaN nor infinite).
func all_finite(samples: PackedFloat32Array) -> bool:
	for value in samples:
		if is_nan(value) or is_inf(value):
			return false
	return true


## True when every numeric field a returned segment reports is finite.
func measurements_finite(segment) -> bool:
	if segment == null:
		return false
	var values := [
		segment.peak_amplitude_before_limit,
		segment.gain_applied,
		segment.peak_amplitude,
		segment.rms_amplitude,
		segment.dc_offset_before_removal,
		segment.dc_offset,
	]
	for value in values:
		if is_nan(float(value)) or is_inf(float(value)):
			return false
	return true


func mean(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var total := 0.0
	for value in samples:
		total += value
	return total / float(samples.size())


func rms(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var square_sum := 0.0
	for value in samples:
		square_sum += value * value
	return sqrt(square_sum / float(samples.size()))


## Signed 16-bit integer range check over the encoded bytes.
func encoded_values_in_range(segment) -> bool:
	for i in range(segment.frame_count):
		var quantized: int = segment.pcm_i16_le[i * 2] | (segment.pcm_i16_le[i * 2 + 1] << 8)
		if quantized >= 32768:
			quantized -= 65536
		if quantized < -32768 or quantized > 32767:
			return false
	return true


## Expected engine fundamental from the documented provisional map.
func expected_engine_fundamental_hz(tuning, speed_m_s: float, throttle: float) -> float:
	var speed_norm: float = clampf(speed_m_s / tuning.max_speed_m_s, 0.0, 1.0)
	var ratio: float = tuning.top_hz / tuning.idle_hz
	return tuning.idle_hz * pow(ratio, speed_norm) * (1.0 + tuning.throttle_pitch_lift * throttle)


func snapshots_equal(a, b) -> bool:
	if a == null or b == null:
		return a == b
	return a.pcm_i16_le == b.pcm_i16_le
