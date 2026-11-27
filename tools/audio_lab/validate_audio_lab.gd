extends SceneTree
## Headless black-box numeric validator for the M1.5 procedural engine/tire
## feedback source.
##
## Run from an isolated project copy (tools/audio_lab/run_validation.sh stages
## one and imports first):
##   godot --headless --fixed-fps 60 --path <project> \
##       --script res://tools/audio_lab/validate_audio_lab.gd
##
## Optional `--case=<id>` selects one case; the default runs every case.
## `--case=intentional_failure` always exits nonzero to prove the harness
## detects a failing check. Each case prints its own machine-readable result;
## the runner prints one AUDIO_LAB_RESULT line, one CHECKS_TOTAL line and calls
## `quit` on every path.
##
## These are pure-kernel numeric checks only: no AudioStreamPlayer, audio
## device, listener, bus, scene, body, physics query, clock, input routing or
## rendering is exercised. They make no audible-quality, mixing, M1.5 or M1
## acceptance claim.

const Synth = preload("res://src/audio/vehicle_feedback_synth.gd")
const DriverScript = preload("res://tools/audio_lab/audio_lab_driver.gd")

## Expected upper component-gain ceiling shared by the tuning classes. Kept
## here rather than read from the synth so this validator can be pointed at a
## pre-fix revision and still fail on the overflow cases.
const EXPECTED_MAX_COMPONENT_GAIN := 1.0e6

const CASE_IDS := [
	"deterministic_replay",
	"nonfinite_and_invalid_input",
	"length_bounds",
	"engine_speed_throttle_response",
	"tire_intensity_vs_slip",
	"clipping_peak_dc_limits",
	"loop_endpoints",
	"car_independence",
	"extreme_finite_tuning",
	"direction_relative_reverse_slip",
]


## Partially compatible stand-ins for the bundle-boundary probes. Each passes
## the old duck-typed first guard but lacks a member the old code called
## unchecked; only an actual type check refuses them with a reason.
class AudioLabPartialState extends RefCounted:
	func is_finite() -> bool:
		return true


class AudioLabPartialCommand extends RefCounted:
	func is_normalized() -> bool:
		return true

var _checks := 0
var _failures: Array[String] = []
var _measured: Dictionary = {}
var _finished := false


func _initialize() -> void:
	var requested := _requested_case()
	if requested == "intentional_failure":
		_finish(_run_intentional_failure(), 1)
		return
	var case_ids: Array = []
	if requested == "all":
		case_ids = CASE_IDS.duplicate()
	elif CASE_IDS.has(requested):
		case_ids = [requested]
	else:
		printerr(
			"unknown case '%s'; use all, one of %s, or intentional_failure"
			% [requested, str(CASE_IDS)]
		)
		quit(2)
		return
	var results := []
	for case_id in case_ids:
		results.append(_run_case(String(case_id)))
	var failed_cases := 0
	for result in results:
		if not bool(result["pass"]):
			failed_cases += 1
	var report := {
		"schema": "roadstorm.audio_lab.validation.v1",
		"engine_version": Engine.get_version_info(),
		"cases": results.size(),
		"checks_total": _checks,
		"checks_failed": _failures.size(),
		"failed_cases": failed_cases,
		"case_results": results,
		"measured": _measured,
		"limitations": LIMITATIONS,
	}
	_finish(report)


func _requested_case() -> String:
	for argument in OS.get_cmdline_args():
		if argument.begins_with("--case="):
			return argument.substr(7)
	var from_environment := OS.get_environment("AUDIO_LAB_CASE")
	if from_environment != "":
		return from_environment
	return "all"


func _run_case(case_id: String) -> Dictionary:
	var driver := DriverScript.new()
	match case_id:
		"deterministic_replay":
			_case_deterministic_replay(driver)
		"nonfinite_and_invalid_input":
			_case_nonfinite_and_invalid_input(driver)
		"length_bounds":
			_case_length_bounds(driver)
		"engine_speed_throttle_response":
			_case_engine_speed_throttle_response(driver)
		"tire_intensity_vs_slip":
			_case_tire_intensity_vs_slip(driver)
		"clipping_peak_dc_limits":
			_case_clipping_peak_dc_limits(driver)
		"loop_endpoints":
			_case_loop_endpoints(driver)
		"car_independence":
			_case_car_independence(driver)
		"extreme_finite_tuning":
			_case_extreme_finite_tuning(driver)
		"direction_relative_reverse_slip":
			_case_direction_relative_reverse_slip(driver)
	_checks += driver.checks
	for failure in driver.failures:
		_failures.append("%s: %s" % [case_id, failure])
	_measured[case_id] = driver.measured
	return {
		"id": case_id,
		"checks": driver.checks,
		"pass": driver.failures.is_empty(),
		"failures": driver.failures.duplicate(),
	}


# --- Cases ------------------------------------------------------------------


func _case_deterministic_replay(driver) -> void:
	var params = driver.engine_params(30.0, 0.6, 0.5)
	var first = driver.render_engine(params, 12345)
	var second = driver.render_engine(params, 12345)
	driver.check(first != null and second != null, "identical engine inputs rendered twice")
	if first == null or second == null:
		return
	driver.check_eq(
		first.pcm_i16_le,
		second.pcm_i16_le,
		"identical engine inputs and seed produce byte-identical PCM"
	)
	driver.check_eq(first.frame_count, second.frame_count, "identical engine length")
	driver.check_close(
		float(first.metadata["nominal_fundamental_hz"]),
		float(second.metadata["nominal_fundamental_hz"]),
		0.0,
		"identical engine inputs keep the same nominal fundamental"
	)
	var different_seed = driver.render_engine(params, 12346)
	driver.check(
		different_seed != null and first.pcm_i16_le != different_seed.pcm_i16_le,
		"different seeds change the deterministic noise texture"
	)

	var tire_params = driver.tire_params(18.0, 30.0, true, 0.5)
	var tire_first = driver.render_tire(tire_params, 777)
	var tire_second = driver.render_tire(tire_params, 777)
	driver.check(tire_first != null and tire_second != null, "identical tire inputs rendered twice")
	if tire_first != null and tire_second != null:
		driver.check_eq(
			tire_first.pcm_i16_le,
			tire_second.pcm_i16_le,
			"identical tire inputs and seed produce byte-identical PCM"
		)
		driver.measure("tire_intensity_18deg", float(tire_first.metadata["intensity"]))

	var car = driver.make_car(22.0, 2.0)
	var command = driver.command(0.7)
	var bundle_first = driver.render_bundle(car, command, 909)
	var bundle_second = driver.render_bundle(car, command, 909)
	driver.check(
		bundle_first.get("valid") == true and bundle_second.get("valid") == true,
		"repeated one-car bundles are valid"
	)
	if bundle_first.get("valid") == true and bundle_second.get("valid") == true:
		var engine_first = bundle_first["engine"]
		var engine_second = bundle_second["engine"]
		var tire_first_seg = bundle_first["tire"]
		var tire_second_seg = bundle_second["tire"]
		driver.check_eq(
			engine_first.pcm_i16_le,
			engine_second.pcm_i16_le,
			"bundle engine PCM is repeatable"
		)
		driver.check_eq(
			tire_first_seg.pcm_i16_le,
			tire_second_seg.pcm_i16_le,
			"bundle tire PCM is repeatable"
		)
		driver.check_close(
			float(bundle_first["telemetry"]["slip_deg"]),
			float(bundle_second["telemetry"]["slip_deg"]),
			0.0,
			"bundle telemetry slip is repeatable"
		)


func _case_nonfinite_and_invalid_input(driver) -> void:
	driver.check(Synth.EngineParams.create(NAN, 0.5) == null, "NaN engine speed refused")
	driver.check(Synth.EngineParams.create(INF, 0.5) == null, "infinite engine speed refused")
	driver.check(Synth.EngineParams.create(30.0, NAN) == null, "NaN throttle refused")
	driver.check(Synth.EngineParams.create(30.0, INF) == null, "infinite throttle refused")
	driver.check(
		Synth.EngineParams.create(30.0, 0.5, 0.0) == null,
		"zero engine duration refused"
	)
	driver.check(
		Synth.EngineParams.create(30.0, 0.5, -1.0) == null,
		"negative engine duration refused"
	)
	driver.check(
		Synth.EngineParams.create(30.0, 0.5, NAN) == null,
		"NaN engine duration refused"
	)

	var direct = Synth.EngineParams.new()
	direct.speed_m_s = NAN
	driver.check(not direct.is_normalized(), "direct NaN speed fails normalization")
	driver.check(driver.render_engine(direct) == null, "direct NaN speed render refused")
	direct = Synth.EngineParams.new()
	direct.throttle = 7.0
	driver.check(not direct.is_normalized(), "direct out-of-range throttle fails normalization")
	driver.check(driver.render_engine(direct) == null, "out-of-range throttle render refused")
	direct = Synth.EngineParams.new()
	direct.duration_s = -2.0
	driver.check(driver.render_engine(direct) == null, "negative direct duration render refused")
	direct = Synth.EngineParams.new()
	direct.loop_mode = 99
	driver.check(driver.render_engine(direct) == null, "invalid loop mode render refused")

	var atomic = Synth.EngineParams.create(20.0, 0.3, 0.5)
	driver.check(atomic != null, "valid engine params construct")
	if atomic != null:
		var accepted := atomic.set_from_raw(
			NAN, 0.9, 0.5, Synth.LoopMode.ONE_SHOT
		)
		driver.check(not accepted, "failed set_from_raw refuses the whole update")
		driver.check_eq(atomic.speed_m_s, 20.0, "failed update keeps prior speed")
		driver.check_eq(atomic.throttle, 0.3, "failed update keeps prior throttle")
		driver.check_eq(atomic.duration_s, 0.5, "failed update keeps prior duration")

	driver.check(Synth.TireParams.create(NAN, 30.0) == null, "NaN tire slip refused")
	driver.check(Synth.TireParams.create(20.0, INF) == null, "infinite tire speed refused")
	driver.check(
		Synth.TireParams.create(20.0, 30.0, true, 0.0) == null,
		"zero tire duration refused"
	)
	var tire_direct = Synth.TireParams.new()
	tire_direct.slip_deg = INF
	driver.check(driver.render_tire(tire_direct) == null, "direct infinite slip render refused")

	var engine_tuning = driver.default_engine_tuning()
	engine_tuning.sample_rate_hz = 0
	driver.check(
		driver.render_engine(driver.engine_params(30.0, 0.5), 1, engine_tuning) == null,
		"invalid sample rate refused"
	)
	engine_tuning = driver.default_engine_tuning()
	engine_tuning.max_speed_m_s = -1.0
	driver.check(
		driver.render_engine(driver.engine_params(30.0, 0.5), 1, engine_tuning) == null,
		"invalid engine max speed refused"
	)
	var tire_tuning = driver.default_tire_tuning()
	tire_tuning.band_center_hz = NAN
	driver.check(
		driver.render_tire(driver.tire_params(20.0, 30.0), 1, tire_tuning) == null,
		"invalid tire band centre refused"
	)

	var bad_car = driver.make_car(20.0)
	bad_car.velocity_m_s = Vector2(NAN, 20.0)
	var bad_bundle = driver.render_bundle(bad_car, driver.command(0.5), 1)
	driver.check(bad_bundle.get("valid") == false, "nonfinite CarState bundle refused")
	driver.check(
		String(bad_bundle.get("error", "")) != "",
		"refused bundle reports a reason"
	)
	driver.check(bad_bundle.get("engine") == null, "refused bundle has no engine segment")
	var null_command_bundle = driver.render_bundle(driver.make_car(20.0), null, 1)
	driver.check(null_command_bundle.get("valid") == false, "missing command bundle refused")

	# The bundle boundary must refuse primitives and partially compatible
	# objects with a reason rather than raising on member access.
	var primitive_state_bundle = driver.render_bundle(17, driver.command(0.5), 1)
	driver.check(
		primitive_state_bundle.get("valid") == false,
		"primitive CarState bundle refused",
	)
	driver.check(
		String(primitive_state_bundle.get("error", "")) != "",
		"primitive CarState refusal reports a reason",
	)
	driver.check(
		primitive_state_bundle.get("engine") == null,
		"primitive CarState refusal has no engine segment",
	)
	var partial_state_bundle = driver.render_bundle(
		AudioLabPartialState.new(), driver.command(0.5), 1
	)
	driver.check(
		partial_state_bundle.get("valid") == false,
		"partially compatible state bundle refused",
	)
	var partial_command_bundle = driver.render_bundle(
		driver.make_car(20.0), AudioLabPartialCommand.new(), 1
	)
	driver.check(
		partial_command_bundle.get("valid") == false,
		"partially compatible command bundle refused",
	)


func _case_length_bounds(driver) -> void:
	var rate := Synth.DEFAULT_SAMPLE_RATE_HZ
	var min_frames := int(round(Synth.MIN_SEGMENT_DURATION_S * float(rate)))
	var max_frames := int(round(Synth.MAX_SEGMENT_DURATION_S * float(rate)))

	var tiny = driver.render_engine(driver.engine_params(30.0, 0.5, 0.001), 1)
	driver.check(tiny != null, "short engine request renders")
	if tiny != null:
		driver.check_eq(
			tiny.frame_count, min_frames, "sub-minimum duration clamps to the minimum"
		)
		driver.check_eq(
			tiny.requested_duration_s, 0.001, "requested short duration is reported"
		)
		driver.check(tiny.duration_clamped, "short duration is marked clamped")
		driver.check_eq(
			tiny.byte_size(), tiny.frame_count * 2, "PCM byte count matches frame count"
		)

	var huge = driver.render_engine(driver.engine_params(30.0, 0.5, 99.0), 1)
	driver.check(huge != null, "long engine request renders")
	if huge != null:
		driver.check_eq(huge.frame_count, max_frames, "over-max duration clamps to the maximum")
		driver.check(huge.duration_clamped, "over-max duration is marked clamped")

	var exact_min = driver.render_engine(
		driver.engine_params(30.0, 0.5, Synth.MIN_SEGMENT_DURATION_S), 1
	)
	if exact_min != null:
		driver.check(not exact_min.duration_clamped, "exact minimum duration is not clamped")
		driver.check_eq(exact_min.frame_count, min_frames, "exact minimum frame count")

	var exact_max = driver.render_engine(
		driver.engine_params(30.0, 0.5, Synth.MAX_SEGMENT_DURATION_S), 1
	)
	if exact_max != null:
		driver.check(not exact_max.duration_clamped, "exact maximum duration is not clamped")
		driver.check_eq(exact_max.frame_count, max_frames, "exact maximum frame count")

	var tuning = driver.default_engine_tuning()
	tuning.sample_rate_hz = 22050
	var custom = driver.render_engine(driver.engine_params(30.0, 0.5, 0.1), 1, tuning)
	if custom != null:
		driver.check_eq(custom.sample_rate_hz, 22050, "custom sample rate is used")
		driver.check_eq(custom.frame_count, 2205, "custom sample rate frame count")

	var low_rate = driver.default_engine_tuning()
	low_rate.sample_rate_hz = Synth.MIN_SAMPLE_RATE_HZ
	driver.check(
		driver.render_engine(driver.engine_params(30.0, 0.5, 0.1), 1, low_rate) != null,
		"minimum accepted sample rate renders"
	)
	var high_rate = driver.default_engine_tuning()
	high_rate.sample_rate_hz = Synth.MAX_SAMPLE_RATE_HZ
	driver.check(
		driver.render_engine(driver.engine_params(30.0, 0.5, 0.1), 1, high_rate) != null,
		"maximum accepted sample rate renders"
	)
	var too_low = driver.default_engine_tuning()
	too_low.sample_rate_hz = Synth.MIN_SAMPLE_RATE_HZ - 1
	driver.check(
		driver.render_engine(driver.engine_params(30.0, 0.5, 0.1), 1, too_low) == null,
		"below-minimum sample rate refused"
	)
	var too_high = driver.default_engine_tuning()
	too_high.sample_rate_hz = Synth.MAX_SAMPLE_RATE_HZ + 1
	driver.check(
		driver.render_engine(driver.engine_params(30.0, 0.5, 0.1), 1, too_high) == null,
		"above-maximum sample rate refused"
	)


func _case_engine_speed_throttle_response(driver) -> void:
	var tuning = driver.default_engine_tuning()
	var speeds := [5.0, 25.0, 55.0]
	var previous_rms := -1.0
	var previous_fundamental := -1.0
	for speed in speeds:
		var segment = driver.render_engine(
			driver.engine_params(speed, 0.6, 0.5), 1, tuning
		)
		driver.check(segment != null, "engine speed response segment renders")
		if segment == null:
			continue
		var fundamental := float(segment.metadata["nominal_fundamental_hz"])
		var expected: float = driver.expected_engine_fundamental_hz(tuning, speed, 0.6)
		driver.check_close(
			fundamental, expected, 1e-6, "engine fundamental follows the documented map"
		)
		driver.check(
			fundamental > previous_fundamental,
			"engine fundamental increases with speed (%.1f m/s)" % speed
		)
		previous_fundamental = fundamental
		var samples = driver.decode_segment(segment)
		var value_rms: float = driver.rms(samples)
		driver.check(
			value_rms > previous_rms,
			"engine RMS increases with speed (%.1f m/s)" % speed
		)
		previous_rms = value_rms
		var speed_norm := float(segment.metadata["speed_normalized"])
		driver.check_close(
			speed_norm, clampf(speed / tuning.max_speed_m_s, 0.0, 1.0), 1e-9,
			"normalized speed matches the documented scale"
		)
		driver.measure("engine_rms_at_%d_m_s" % int(speed), value_rms)
		driver.measure("engine_hz_at_%d_m_s" % int(speed), fundamental)

	var throttles := [0.0, 0.5, 1.0]
	previous_rms = -1.0
	for throttle in throttles:
		var segment = driver.render_engine(
			driver.engine_params(30.0, throttle, 0.5), 1, tuning
		)
		if segment == null:
			continue
		var value_rms: float = driver.rms(driver.decode_segment(segment))
		driver.check(
			value_rms > previous_rms,
			"engine RMS increases with throttle (%.1f)" % throttle
		)
		previous_rms = value_rms
		driver.measure("engine_rms_at_throttle_%.1f" % throttle, value_rms)

	var idle = driver.render_engine(driver.engine_params(0.0, 0.0, 0.5), 1, tuning)
	if idle != null:
		var idle_level := float(idle.metadata["level"])
		driver.check_between(idle_level, 0.0, 1.0, "idle level stays normalized")
		driver.check(
			driver.rms(driver.decode_segment(idle)) < previous_rms,
			"loaded engine is louder than idle/coast"
		)


func _case_tire_intensity_vs_slip(driver) -> void:
	var tuning = driver.default_tire_tuning()
	var slips := [0.0, 3.0, 10.0, 20.0, 35.0]
	var previous_rms := -1.0
	for slip in slips:
		var segment = driver.render_tire(
			driver.tire_params(slip, 30.0, true, 0.5), 2, tuning
		)
		driver.check(segment != null, "tire slip segment renders (%.1f deg)" % slip)
		if segment == null:
			continue
		var intensity := float(segment.metadata["intensity"])
		driver.check_between(intensity, 0.0, 1.0, "tire intensity stays normalized")
		var value_rms: float = driver.rms(driver.decode_segment(segment))
		if slip >= 10.0:
			driver.check(
				value_rms > previous_rms,
				"tire RMS rises strictly across loaded slips (%.1f deg)" % slip
			)
		else:
			driver.check(
				value_rms >= previous_rms - 1e-9,
				"tire RMS does not fall below threshold onset (%.1f deg)" % slip
			)
		previous_rms = maxf(previous_rms, value_rms)
		driver.measure("tire_intensity_at_%d_deg" % int(slip), intensity)
		driver.measure("tire_rms_at_%d_deg" % int(slip), value_rms)

	var silent = driver.render_tire(driver.tire_params(0.0, 30.0, true, 0.5), 2, tuning)
	if silent != null:
		driver.check(
			driver.max_abs(driver.decode_segment(silent)) <= 1e-6,
			"zero-slip tire segment is silent"
		)

	var airborne = driver.render_tire(driver.tire_params(30.0, 30.0, false, 0.5), 2, tuning)
	if airborne != null:
		driver.check_close(
			float(airborne.metadata["intensity"]), 0.0, 1e-9, "airborne tire intensity is zero"
		)
		driver.check(
			driver.rms(driver.decode_segment(airborne)) <= 1e-6,
			"airborne tire segment is silent"
		)

	var stationary = driver.render_tire(driver.tire_params(30.0, 1.0, true, 0.5), 2, tuning)
	if stationary != null:
		driver.check_close(
			float(stationary.metadata["intensity"]),
			0.0,
			1e-9,
			"below-gate speed suppresses tire scrub"
		)

	var saturated = driver.render_tire(driver.tire_params(90.0, 30.0, true, 0.5), 2, tuning)
	if saturated != null:
		driver.check_close(
			float(saturated.metadata["intensity"]), 1.0, 1e-9,
			"slip beyond full scale saturates at one"
		)


func _case_clipping_peak_dc_limits(driver) -> void:
	var limit := Synth.PEAK_LIMIT
	var extreme = driver.render_engine(driver.engine_params(65.0, 1.0, 1.0), 3)
	driver.check(extreme != null, "full-speed/full-throttle engine segment renders")
	if extreme != null:
		driver.check(
			driver.max_abs(driver.decode_segment(extreme)) <= limit + 1e-6,
			"default full-throttle samples stay within the peak limit"
		)
		driver.check(
			extreme.peak_amplitude <= limit + 1e-6,
			"default full-throttle peak stays within the peak limit"
		)
		driver.check_eq(extreme.gain_applied, 1.0, "default full-throttle needs no limiting")

	# A deliberately boosted master gain exercises the downward-only limiter.
	var overdrive_tuning = driver.default_engine_tuning()
	overdrive_tuning.output_gain = 3.0
	var engine = driver.render_engine(
		driver.engine_params(65.0, 1.0, 1.0), 3, overdrive_tuning
	)
	driver.check(engine != null, "overdriven engine segment renders")
	if engine != null:
		var samples = driver.decode_segment(engine)
		driver.check(
			driver.max_abs(samples) <= limit + 1e-6,
			"decoded engine samples stay within the peak limit"
		)
		driver.check(
			engine.peak_amplitude <= limit + 1e-6,
			"reported engine peak stays within the peak limit"
		)
		driver.check(
			absf(engine.dc_offset) <= 1e-5,
			"engine DC offset is removed"
		)
		driver.check(
			engine.gain_applied <= 1.0 + 1e-12,
			"limiter gain never amplifies"
		)
		driver.check(
			engine.peak_amplitude_before_limit >= engine.peak_amplitude - 1e-12,
			"limiter does not raise the peak"
		)
		driver.check(
			engine.peak_amplitude_before_limit > limit,
			"overdriven engine exercises the limiter"
		)
		driver.check(engine.gain_applied < 1.0, "overdriven engine is limited downward")
		driver.check(
			driver.encoded_values_in_range(engine),
			"engine 16-bit codes stay in signed range"
		)
		driver.check_eq(
			engine.byte_size(), engine.frame_count * 2, "engine PCM byte count"
		)
		driver.measure("engine_overdrive_peak", engine.peak_amplitude)
		driver.measure("engine_overdrive_gain", engine.gain_applied)

	var tire = driver.render_tire(driver.tire_params(80.0, 65.0, true, 1.0), 4)
	driver.check(tire != null, "extreme tire segment renders")
	if tire != null:
		driver.check(
			driver.max_abs(driver.decode_segment(tire)) <= limit + 1e-6,
			"decoded tire samples stay within the peak limit"
		)
		driver.check(
			absf(tire.dc_offset) <= 1e-5, "tire DC offset is removed"
		)
		driver.check(driver.encoded_values_in_range(tire), "tire 16-bit codes stay in range")
		driver.measure("tire_extreme_peak", tire.peak_amplitude)

	var idle = driver.render_engine(driver.engine_params(0.0, 0.0, 0.25), 5)
	if idle != null:
		driver.check(idle.peak_amplitude <= limit + 1e-6, "idle engine peak bounded")
		driver.check(idle.rms_amplitude > 0.0, "idle engine has nonzero energy")
		driver.check_eq(idle.gain_applied, 1.0, "idle engine needs no limiting")


func _case_loop_endpoints(driver) -> void:
	var modes := [Synth.LoopMode.ONE_SHOT, Synth.LoopMode.LOOP]
	for mode in modes:
		var engine = driver.render_engine(
			driver.engine_params(30.0, 0.6, 0.5, mode), 6
		)
		driver.check(engine != null, "engine loop-mode segment renders")
		if engine == null:
			continue
		driver.check_eq(engine.loop_mode, mode, "requested loop mode is preserved")
		driver.check_close(engine.float_at(0), 0.0, 1e-6, "engine starts at zero")
		driver.check_close(
			engine.float_at(engine.frame_count - 1), 0.0, 1e-6, "engine ends at zero"
		)
		driver.check_close(
			absf(engine.float_at(0) - engine.float_at(engine.frame_count - 1)),
			0.0,
			1e-6,
			"engine endpoints agree for clean looping"
		)
		driver.check(
			engine.fade_s <= 0.25 * engine.duration_s + 1e-9,
			"engine fade fits inside a quarter of the segment"
		)
		driver.check(engine.fade_s >= 0.0, "engine fade is nonnegative")
		driver.measure("engine_fade_s_%d" % int(mode), engine.fade_s)

		var tire = driver.render_tire(driver.tire_params(20.0, 30.0, true, 0.5, mode), 6)
		driver.check(tire != null, "tire loop-mode segment renders")
		if tire == null:
			continue
		driver.check_eq(tire.loop_mode, mode, "requested tire loop mode is preserved")
		driver.check_close(tire.float_at(0), 0.0, 1e-6, "tire starts at zero")
		driver.check_close(
			tire.float_at(tire.frame_count - 1), 0.0, 1e-6, "tire ends at zero"
		)


func _case_car_independence(driver) -> void:
	var car_a = driver.make_car(20.0, 1.5)
	var command_a = driver.command(0.4)
	var car_b = driver.make_car(45.0, -3.0)
	var command_b = driver.command(1.0)

	var bundle_a = driver.render_bundle(car_a, command_a, 11)
	var bundle_b = driver.render_bundle(car_b, command_b, 11)
	driver.check(bundle_a.get("valid") == true, "car A bundle valid")
	driver.check(bundle_b.get("valid") == true, "car B bundle valid")
	if bundle_a.get("valid") != true or bundle_b.get("valid") != true:
		return
	var engine_a = bundle_a["engine"]
	var tire_a = bundle_a["tire"]
	var engine_b = bundle_b["engine"]
	var tire_b = bundle_b["tire"]
	driver.check(
		engine_a.pcm_i16_le != engine_b.pcm_i16_le,
		"distinct car inputs give distinct engine PCM"
	)
	driver.check(
		tire_a.pcm_i16_le != tire_b.pcm_i16_le,
		"distinct car inputs give distinct tire PCM"
	)
	driver.check_eq(engine_a.source, &"engine", "engine segment is labelled engine")
	driver.check_eq(tire_a.source, &"tire", "tire segment is labelled tire")
	driver.check_eq(
		String(bundle_a["telemetry"]["engine_source"]),
		&"engine",
		"telemetry names the engine source"
	)
	driver.check_eq(
		String(bundle_a["telemetry"]["tire_source"]),
		&"tire",
		"telemetry names the tire source"
	)
	driver.check_close(
		float(bundle_a["telemetry"]["speed_m_s"]),
		car_a.speed_m_s(),
		1e-6,
		"telemetry speed matches car A"
	)
	driver.check_close(
		float(bundle_a["telemetry"]["slip_deg"]),
		car_a.slip_deg(),
		1e-6,
		"telemetry slip matches car A"
	)
	driver.check_close(
		float(bundle_a["telemetry"]["throttle"]),
		command_a.throttle,
		1e-9,
		"telemetry throttle matches command A"
	)

	var bundle_a_again = driver.render_bundle(car_a, command_a, 11)
	driver.check(
		driver.snapshots_equal(bundle_a_again["engine"], engine_a),
		"rendering car B did not perturb car A"
	)
	driver.check(
		driver.snapshots_equal(bundle_a_again["tire"], tire_a),
		"rendering car B did not perturb car A tires"
	)
	var bundle_b_other_seed = driver.render_bundle(car_b, command_b, 12)
	driver.check(
		bundle_b_other_seed.get("valid") == true
		and engine_b.pcm_i16_le != bundle_b_other_seed["engine"].pcm_i16_le,
		"a different seed changes car B without cross-car coupling"
	)


func _case_extreme_finite_tuning(driver) -> void:
	var slip_deg := 35.0
	var speed_m_s := 30.0
	# Reported overflow: finite nonnegative gains far beyond the float32 range
	# used for the sample buffer made DC/peak/RMS NaN and returned a segment.
	var absurd_tone = driver.default_tire_tuning()
	absurd_tone.tone_gain = 1.0e100
	driver.check(not absurd_tone.validate(), "tire tone_gain=1e100 fails validation")
	driver.check(
		driver.render_tire(driver.tire_params(slip_deg, speed_m_s), 7, absurd_tone) == null,
		"tire tone_gain=1e100 render is refused"
	)

	var absurd_noise = driver.default_tire_tuning()
	absurd_noise.noise_gain = 1.0e100
	driver.check(not absurd_noise.validate(), "tire noise_gain=1e100 fails validation")
	driver.check(
		driver.render_tire(driver.tire_params(slip_deg, speed_m_s), 7, absurd_noise) == null,
		"tire noise_gain=1e100 render is refused"
	)

	# The same induction-noise overflow path was reproduced for engine tuning.
	for gain_name in ["noise_floor", "throttle_noise_gain", "speed_noise_gain"]:
		var tuning = driver.default_engine_tuning()
		tuning.set(gain_name, 1.0e100)
		driver.check(not tuning.validate(), "engine %s=1e100 fails validation" % gain_name)
		driver.check(
			driver.render_engine(driver.engine_params(speed_m_s, 0.6, 0.5), 7, tuning) == null,
			"engine %s=1e100 render is refused" % gain_name
		)

	# The accepted ceiling still renders finite PCM and clips safely; the
	# limiter scales the whole waveform down, so huge-but-safe gains are not
	# distorted relative to any smaller overdrive.
	var ceiling = driver.default_tire_tuning()
	ceiling.tone_gain = EXPECTED_MAX_COMPONENT_GAIN
	ceiling.noise_gain = EXPECTED_MAX_COMPONENT_GAIN
	driver.check(ceiling.validate(), "tire gains at the documented ceiling validate")
	var above_ceiling = driver.default_tire_tuning()
	above_ceiling.tone_gain = EXPECTED_MAX_COMPONENT_GAIN * 2.0
	driver.check(
		not above_ceiling.validate(),
		"tire tone_gain above the ceiling fails validation"
	)
	above_ceiling = driver.default_tire_tuning()
	above_ceiling.noise_gain = EXPECTED_MAX_COMPONENT_GAIN * 2.0
	driver.check(
		not above_ceiling.validate(),
		"tire noise_gain above the ceiling fails validation"
	)
	var ceiling_segment = driver.render_tire(
		driver.tire_params(slip_deg, speed_m_s), 7, ceiling
	)
	driver.check(ceiling_segment != null, "tire ceiling-gain render succeeds")
	if ceiling_segment != null:
		var ceiling_samples = driver.decode_segment(ceiling_segment)
		driver.check(driver.all_finite(ceiling_samples), "tire ceiling-gain decoded samples are finite")
		driver.check(
			driver.max_abs(ceiling_samples) <= Synth.PEAK_LIMIT + 1e-6,
			"tire ceiling-gain samples stay within the peak limit"
		)
		driver.check(
			ceiling_segment.peak_amplitude <= Synth.PEAK_LIMIT + 1e-6,
			"tire ceiling-gain reported peak stays within the peak limit"
		)
		driver.check(driver.measurements_finite(ceiling_segment), "tire ceiling-gain measurements are finite")
		driver.check(absf(ceiling_segment.dc_offset) <= 1e-5, "tire ceiling-gain DC offset is removed")
		driver.check(
			driver.encoded_values_in_range(ceiling_segment),
			"tire ceiling-gain 16-bit codes stay in range"
		)
		driver.check(
			ceiling_segment.gain_applied < 1.0,
			"tire ceiling-gain exercises the downward limiter"
		)

	# A legitimate loud-but-finite configuration still renders and clips.
	var loud = driver.default_tire_tuning()
	loud.tone_gain = 4.0
	loud.noise_gain = 8.0
	driver.check(loud.validate(), "loud finite tire tuning validates")
	var loud_segment = driver.render_tire(
		driver.tire_params(slip_deg, speed_m_s), 7, loud
	)
	driver.check(loud_segment != null, "loud finite tire render succeeds")
	if loud_segment != null:
		var loud_samples = driver.decode_segment(loud_segment)
		driver.check(driver.all_finite(loud_samples), "loud finite tire samples are finite")
		driver.check(
			driver.max_abs(loud_samples) <= Synth.PEAK_LIMIT + 1e-6,
			"loud finite tire samples stay within the peak limit"
		)
		driver.check(
			loud_segment.peak_amplitude_before_limit > Synth.PEAK_LIMIT,
			"loud finite tire pre-limit peak exceeds the limit"
		)
		driver.check(loud_segment.gain_applied < 1.0, "loud finite tire is limited downward")
		driver.check(driver.measurements_finite(loud_segment), "loud finite tire measurements are finite")
		driver.check(absf(loud_segment.dc_offset) <= 1e-5, "loud finite tire DC offset is removed")
		driver.check(driver.encoded_values_in_range(loud_segment), "loud finite tire 16-bit codes stay in range")
		driver.measure("tire_loud_peak", loud_segment.peak_amplitude)
		driver.measure("tire_loud_gain", loud_segment.gain_applied)

	# Finalization itself refuses nonfinite intermediates even when validation
	# accepts the source parameters, covering frequency extremes as well.
	var frequency_extreme = driver.default_tire_tuning()
	frequency_extreme.resonance_hz = 1.0e308
	driver.check(frequency_extreme.validate(), "resonance_hz=1e308 still passes validation")
	driver.check(
		driver.render_tire(driver.tire_params(slip_deg, speed_m_s), 7, frequency_extreme) == null,
		"nonfinite resonance intermediate refuses rendering"
	)


func _case_direction_relative_reverse_slip(driver) -> void:
	# The synth bundle must feed tire scrub with the direction-relative slip:
	# straight forward and straight reverse are both zero, while lateral motion
	# stays audible. Expected values come from an independent geometric oracle
	# and the documented provisional intensity map.
	var tuning = driver.default_tire_tuning()
	var command = driver.command(0.5)
	var drift := deg_to_rad(35.0)

	var cases := [
		{
			"label": "straight_forward",
			"state": driver.make_car(30.0, 0.0),
			"expected_slip_deg": 0.0,
			"expect_silent": true,
		},
		{
			"label": "straight_reverse",
			"state": driver.make_car(-30.0, 0.0),
			"expected_slip_deg": 0.0,
			"expect_silent": true,
		},
		{
			"label": "forward_drift_35deg",
			"state": driver.make_car(cos(drift) * 30.0, sin(drift) * 30.0),
			"expected_slip_deg": 35.0,
			"expect_silent": false,
		},
		{
			"label": "reverse_lateral_drift_35deg",
			"state": driver.make_car(-cos(drift) * 30.0, -sin(drift) * 30.0),
			"expected_slip_deg": 35.0,
			"expect_silent": false,
		},
		{
			"label": "pure_lateral_90deg",
			"state": driver.make_car(0.0, 30.0),
			"expected_slip_deg": 90.0,
			"expect_silent": false,
		},
	]
	for entry in cases:
		var state = entry["state"]
		var label := String(entry["label"])
		var expected_slip: float = driver.expected_direction_relative_slip_deg(
			state.velocity_m_s, state.heading_rad
		)
		driver.check_close(
			expected_slip,
			float(entry["expected_slip_deg"]),
			1e-4,
			"%s: independent slip oracle" % label,
		)
		var bundle = driver.render_bundle(state, command, 41)
		driver.check(bundle.get("valid") == true, "%s: bundle valid" % label)
		if bundle.get("valid") != true:
			continue
		var telemetry = bundle["telemetry"]
		var tire_segment = bundle["tire"]
		driver.check_close(
			float(telemetry["tire_slip_deg"]),
			expected_slip,
			1e-6,
			"%s: telemetry direction-relative tire slip" % label,
		)
		driver.check_close(
			float(telemetry["slip_deg"]),
			state.slip_deg(),
			1e-6,
			"%s: telemetry keeps raw nose-relative slip" % label,
		)
		var expected_intensity: float = driver.expected_tire_intensity(
			tuning, expected_slip, state.speed_m_s(), state.grounded
		)
		driver.check_close(
			float(tire_segment.metadata["intensity"]),
			expected_intensity,
			1e-9,
			"%s: rendered tire intensity matches the independent map" % label,
		)
		var samples = driver.decode_segment(tire_segment)
		if bool(entry["expect_silent"]):
			driver.check(
				driver.max_abs(samples) <= 1e-6,
				"%s: rendered tire segment is silent" % label,
			)
		else:
			driver.check(
				driver.rms(samples) > 0.0,
				"%s: genuine lateral slip renders energy" % label,
			)
		driver.measure("tire_slip_" + label, expected_slip)

	# Broken-behavior negative control: the raw signed nose slip is saturated in
	# straight reverse, so feeding it directly to the tire renderer would be
	# loud. The bundle must instead report zero and render silence.
	var reverse_state = driver.make_car(-30.0, 0.0)
	reverse_state.reverse_engaged = true
	driver.check(
		absf(reverse_state.slip_deg()) >= tuning.slip_full_deg,
		"straight-reverse raw nose slip remains saturated (broken-behavior marker)",
	)
	var reverse_bundle = driver.render_bundle(reverse_state, command, 42)
	driver.check(reverse_bundle.get("valid") == true, "straight-reverse bundle valid")
	if reverse_bundle.get("valid") == true:
		driver.check_close(
			float(reverse_bundle["telemetry"]["tire_slip_deg"]),
			0.0,
			1e-6,
			"straight reverse maps to zero direction-relative tire slip",
		)
		driver.check_close(
			float(reverse_bundle["tire"].metadata["intensity"]),
			0.0,
			1e-9,
			"straight reverse renders zero tire intensity",
		)
		driver.check(
			driver.max_abs(driver.decode_segment(reverse_bundle["tire"])) <= 1e-6,
			"straight reverse renders a silent tire segment",
		)


# --- Deliberate failure proof ----------------------------------------------


func _run_intentional_failure() -> Dictionary:
	var driver := DriverScript.new()
	# Deliberately false expectation: the default sample rate is never zero.
	# This assertion must fail and the process must exit nonzero, proving the
	# harness detects failures rather than inferring a pass from exit status.
	driver.check_eq(
		Synth.DEFAULT_SAMPLE_RATE_HZ,
		0,
		"intentional failure probe: default sample rate unexpectedly zero"
	)
	var proof := {
		"schema": "roadstorm.audio_lab.validation.v1",
		"proof": "intentional_failure",
		"expected_nonzero_exit": true,
		"observed_checks_failed": driver.failures.size(),
		"pass": driver.failures.is_empty(),
		"failures": driver.failures.duplicate(),
	}
	print("INTENTIONAL_FAILURE_PROOF " + JSON.stringify(proof))
	return proof


# --- Report -----------------------------------------------------------------


const LIMITATIONS := [
	"Pure-kernel numeric checks only: no AudioStreamPlayer, audio server, listener, bus, mixing, attenuation, stereo pan, voice budget or playback scheduling is exercised.",
	"Headless Godot dummy display and audio drivers; numeric PCM bounds are not evidence of audible quality, mix balance or comfort.",
	"No simulation, scene, body, physics query, clock, input routing or race state is integrated; car states and commands are scripted records.",
	"The generator makes no engine/tire force coupling, score, assist, AI, drift-state or surface-response decision; it only reads committed CarState/DriverCommand fields.",
	"All synthesis coefficients are provisional M1.5 laboratory choices. Pitch mapping, harmonic balance, noise bands and fades require later perceptual review and production tuning.",
	"A local WAV preview, if produced, is diagnostic PCM evidence under an ignored work directory; it is not committed project content and proves nothing about perceived sound.",
	"LongCat-authored creative source remains un-cleared for release; provenance OI-02 is open.",
	"No M1.5 or M1 acceptance claim and no audio-listening claim is made by this validator.",
]


func _finish(report: Dictionary, forced_exit: int = -1) -> void:
	if _finished:
		return
	_finished = true
	var passed := _failures.is_empty() and int(report.get("failed_cases", 0)) == 0
	var code := forced_exit
	if code < 0:
		code = 0 if passed else 1
	print("AUDIO_LAB_RESULT " + JSON.stringify(report))
	print("CHECKS_TOTAL=%d CHECKS_FAILED=%d" % [_checks, _failures.size()])
	quit(code)
