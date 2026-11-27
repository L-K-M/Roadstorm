class_name VehicleFeedbackSynth
extends RefCounted
## Deterministic procedural engine and tire PCM feedback source (M1.5 slice).
##
## This is a pure generator for one car's basic engine tone and tire scrub.
## It owns no AudioStreamPlayer, listener, scene tree, clock, body, physics
## query, global RNG or audio bus. Every render is stateless with respect to
## previous renders: identical validated inputs and seed produce byte-identical
## 16-bit little-endian mono PCM segments. The presentation layer's later
## `AudioDirector` decides how to play, attenuate, pan, mix and virtualize the
## returned segments.
##
## Scope seams (deliberately absent):
##   * no engine/tire force coupling, score, assist, AI or race-state effect;
##   * no listener attenuation, stereo pan, bus routing or voice stealing;
##   * no reading of sampled songs, recorded audio, streams or external files;
##   * no integration with `CarState`/`DriverCommand` beyond the explicit
##     read-only `render_bundle()` mapping documented below.
##
## The engine tone and tire scrub are separate sources with separate telemetry:
## engine pitch follows normalized speed and throttle, while tire intensity
## follows absolute slip angle and forward speed. Neither source influences the
## other's synthesis path.
##
## All coefficients are provisional laboratory choices for M1.5 feedback
## prototyping, not frozen M1.5/M5 audio specification. Release clearance for
## LongCat-authored creative source remains open (provenance OI-02).

## Default and accepted sample-rate bounds. Segments are mono; the director
## owns any stereo placement.
const DEFAULT_SAMPLE_RATE_HZ := 44100
const MIN_SAMPLE_RATE_HZ := 8000
const MAX_SAMPLE_RATE_HZ := 48000

## Requested durations outside this inclusive range are clamped. Nonpositive or
## nonfinite durations are refused, not silently repaired.
const MIN_SEGMENT_DURATION_S := 0.05
const MAX_SEGMENT_DURATION_S := 2.0

## Absolute frame ceiling, independent of rate and duration, so one request
## cannot allocate an unbounded buffer.
const MAX_SEGMENT_FRAMES := 192000

## Post-synthesis peak target. Every returned float sample and encoded 16-bit
## sample is bounded by this value in magnitude; the limiter only scales down.
## 0.89 leaves roughly 1 dB of headroom before full scale.
const PEAK_LIMIT := 0.89

## One-shot envelope or a caller-intended loop. Both modes use symmetric short
## raised-cosine fades so endpoints rest at zero; `LOOP` is advisory intent for
## the director, not a claim of phase-perfect periodicity.
enum LoopMode { ONE_SHOT, LOOP }

## Internal noise-shaping constants, documented rather than exposed as tuning:
## engine induction noise is lightly smoothed; tire scrub uses a crude highpass
## then resonant-ish lowpass so its band sits near `resonance_hz`.
const ENGINE_NOISE_LOWPASS := 0.25
const TIRE_HIGHPASS_ALPHA := 0.75
const TIRE_LOWPASS_ALPHA := 0.18


# --- Tuning -----------------------------------------------------------------


## Provisional engine synthesis coefficients. Defaults are starting points for
## M1.5 numeric/preview work; M5 production tuning replaces them.
class EngineTuning extends RefCounted:
	## Samples per second for rendered segments.
	var sample_rate_hz := DEFAULT_SAMPLE_RATE_HZ
	## Speed mapped to the top of the normalized engine range, m/s. Provisional
	## 65 m/s ~= 234 km/h, inside docs/GAME_DESIGN.md:39's 205-235 km/h band.
	var max_speed_m_s := 65.0
	## Fundamental at zero normalized speed, Hz.
	var idle_hz := 55.0
	## Fundamental at full normalized speed before throttle lift, Hz.
	var top_hz := 240.0
	## Multiplicative pitch lift at full throttle, 1 + this value.
	var throttle_pitch_lift := 0.25
	## Number of harmonic partials above the fundamental.
	var harmonic_count := 8
	## Fundamental-relative harmonic amplitude scale.
	var harmonic_base := 0.55
	## Amplitude falloff exponent across harmonics.
	var harmonic_rolloff := 1.15
	## Sub-octave sine gain relative to `harmonic_base` level.
	var sub_octave_gain := 0.22
	## Slightly detuned second oscillator gain.
	var detune_gain := 0.28
	## Detune of the second oscillator in cents.
	var detune_cents := 9.0
	## Peak amplitude-modulation depth from engine rotation, 0..1.
	var amplitude_modulation_depth := 0.10
	## Always-present induction-noise floor, normalized.
	var noise_floor := 0.03
	## Additional noise gain at full throttle.
	var throttle_noise_gain := 0.10
	## Additional noise gain at full normalized speed.
	var speed_noise_gain := 0.05
	## Output level at idle/coast before limiting, 0..1.
	var idle_level := 0.18
	## Master oscillator gain applied before the peak limiter. Defaults to 1;
	## values above one intentionally exercise the limiter and are clamped.
	var output_gain := 1.0
	## Symmetric fade length in seconds when it fits the segment.
	var fade_s := 0.012

	func validate() -> bool:
		return (
			_is_positive_int(sample_rate_hz)
			and sample_rate_hz >= MIN_SAMPLE_RATE_HZ
			and sample_rate_hz <= MAX_SAMPLE_RATE_HZ
			and _is_finite(max_speed_m_s)
			and max_speed_m_s > 0.0
			and _is_finite(idle_hz)
			and idle_hz > 0.0
			and _is_finite(top_hz)
			and top_hz > 0.0
			and _is_finite(throttle_pitch_lift)
			and throttle_pitch_lift >= 0.0
			and _is_positive_int(harmonic_count)
			and harmonic_count <= 16
			and _is_finite(harmonic_base)
			and harmonic_base >= 0.0
			and _is_finite(harmonic_rolloff)
			and harmonic_rolloff >= 0.0
			and _is_finite(sub_octave_gain)
			and sub_octave_gain >= 0.0
			and _is_finite(detune_gain)
			and detune_gain >= 0.0
			and _is_finite(detune_cents)
			and _is_finite(amplitude_modulation_depth)
			and amplitude_modulation_depth >= 0.0
			and amplitude_modulation_depth <= 1.0
			and _is_finite(noise_floor)
			and noise_floor >= 0.0
			and _is_finite(throttle_noise_gain)
			and throttle_noise_gain >= 0.0
			and _is_finite(speed_noise_gain)
			and speed_noise_gain >= 0.0
			and _is_finite(idle_level)
			and idle_level >= 0.0
			and idle_level <= 1.0
			and _is_finite(output_gain)
			and output_gain >= 0.0
			and output_gain <= 4.0
			and _is_finite(fade_s)
			and fade_s >= 0.0
		)

	## Machine-readable effective coefficients, for evidence records.
	func snapshot() -> Dictionary:
		return {
			"sample_rate_hz": sample_rate_hz,
			"max_speed_m_s": max_speed_m_s,
			"idle_hz": idle_hz,
			"top_hz": top_hz,
			"throttle_pitch_lift": throttle_pitch_lift,
			"harmonic_count": harmonic_count,
			"harmonic_base": harmonic_base,
			"harmonic_rolloff": harmonic_rolloff,
			"sub_octave_gain": sub_octave_gain,
			"detune_gain": detune_gain,
			"detune_cents": detune_cents,
			"amplitude_modulation_depth": amplitude_modulation_depth,
			"noise_floor": noise_floor,
			"throttle_noise_gain": throttle_noise_gain,
			"speed_noise_gain": speed_noise_gain,
			"idle_level": idle_level,
			"output_gain": output_gain,
			"fade_s": fade_s,
		}

	func _is_finite(value: float) -> bool:
		return not is_nan(value) and not is_inf(value)

	func _is_positive_int(value: int) -> bool:
		return value > 0


## Provisional tire scrub coefficients. Slip is signed in degrees; only its
## magnitude drives intensity.
class TireTuning extends RefCounted:
	var sample_rate_hz := DEFAULT_SAMPLE_RATE_HZ
	## Speed mapped to the top of the normalized range, m/s.
	var max_speed_m_s := 65.0
	## Absolute slip angle at which scrub intensity saturates, degrees.
	var slip_full_deg := 35.0
	## Absolute slip angle below which scrub is silent, degrees.
	var slip_threshold_deg := 2.0
	## Centre of the filtered noise band, Hz.
	var band_center_hz := 1500.0
	## Nominal width of the filtered noise band, Hz (documentation aid; the
	## actual shaping uses fixed one-pole constants).
	var band_width_hz := 900.0
	## Tonal squeal frequency, Hz.
	var resonance_hz := 2200.0
	## Tonal component gain.
	var tone_gain := 0.35
	## Filtered-noise component gain.
	var noise_gain := 0.55
	## Speed below which no scrub is emitted, m/s.
	var min_speed_m_s := 3.0
	## Speed at which scrub reaches full loudness, m/s.
	var reference_speed_m_s := 30.0
	## Symmetric fade length in seconds when it fits the segment.
	var fade_s := 0.02

	func validate() -> bool:
		return (
			_is_positive_int(sample_rate_hz)
			and sample_rate_hz >= MIN_SAMPLE_RATE_HZ
			and sample_rate_hz <= MAX_SAMPLE_RATE_HZ
			and _finite(max_speed_m_s)
			and max_speed_m_s > 0.0
			and _finite(slip_full_deg)
			and slip_full_deg > 0.0
			and _finite(slip_threshold_deg)
			and slip_threshold_deg >= 0.0
			and slip_threshold_deg <= slip_full_deg
			and _finite(band_center_hz)
			and band_center_hz > 0.0
			and _finite(band_width_hz)
			and band_width_hz > 0.0
			and _finite(resonance_hz)
			and resonance_hz > 0.0
			and _finite(tone_gain)
			and tone_gain >= 0.0
			and _finite(noise_gain)
			and noise_gain >= 0.0
			and _finite(min_speed_m_s)
			and min_speed_m_s >= 0.0
			and _finite(reference_speed_m_s)
			and reference_speed_m_s > min_speed_m_s
			and _finite(fade_s)
			and fade_s >= 0.0
		)

	func snapshot() -> Dictionary:
		return {
			"sample_rate_hz": sample_rate_hz,
			"max_speed_m_s": max_speed_m_s,
			"slip_full_deg": slip_full_deg,
			"slip_threshold_deg": slip_threshold_deg,
			"band_center_hz": band_center_hz,
			"band_width_hz": band_width_hz,
			"resonance_hz": resonance_hz,
			"tone_gain": tone_gain,
			"noise_gain": noise_gain,
			"min_speed_m_s": min_speed_m_s,
			"reference_speed_m_s": reference_speed_m_s,
			"fade_s": fade_s,
		}

	func _finite(value: float) -> bool:
		return not is_nan(value) and not is_inf(value)

	func _is_positive_int(value: int) -> bool:
		return value > 0


# --- Request records --------------------------------------------------------


## Validated engine render request. Build with `create()`/`set_from_raw()`;
## direct field assignment is checked again by `is_normalized()` at render
## time, mirroring `DriverCommand`.
class EngineParams extends RefCounted:
	## Forward ground speed, m/s. Negative finite values are clamped to zero by
	## `set_from_raw()`; nonfinite values invalidate the whole record.
	var speed_m_s := 0.0
	## Normalized throttle in [0, 1].
	var throttle := 0.0
	## Requested segment duration in seconds, > 0. Clamped to the declared
	## duration bounds during rendering.
	var duration_s := 0.5
	var loop_mode := LoopMode.ONE_SHOT

	static func create(
		p_speed_m_s := 0.0,
		p_throttle := 0.0,
		p_duration_s := 0.5,
		p_loop_mode: int = LoopMode.ONE_SHOT
	) -> EngineParams:
		var params := EngineParams.new()
		if not params.set_from_raw(p_speed_m_s, p_throttle, p_duration_s, p_loop_mode):
			return null
		return params

	func set_from_raw(
		p_speed_m_s: float,
		p_throttle: float,
		p_duration_s: float,
		p_loop_mode: int
	) -> bool:
		if not _three_finite(p_speed_m_s, p_throttle, p_duration_s):
			return false
		if p_duration_s <= 0.0:
			return false
		if p_loop_mode != LoopMode.ONE_SHOT and p_loop_mode != LoopMode.LOOP:
			return false
		speed_m_s = maxf(0.0, p_speed_m_s)
		throttle = clampf(p_throttle, 0.0, 1.0)
		duration_s = p_duration_s
		loop_mode = p_loop_mode
		return true

	func is_normalized() -> bool:
		return (
			_three_finite(speed_m_s, throttle, duration_s)
			and speed_m_s >= 0.0
			and throttle >= 0.0
			and throttle <= 1.0
			and duration_s > 0.0
			and (loop_mode == LoopMode.ONE_SHOT or loop_mode == LoopMode.LOOP)
		)

	func copy() -> EngineParams:
		var params := EngineParams.new()
		params.speed_m_s = speed_m_s
		params.throttle = throttle
		params.duration_s = duration_s
		params.loop_mode = loop_mode
		return params

	static func _three_finite(a: float, b: float, c: float) -> bool:
		return _is_finite(a) and _is_finite(b) and _is_finite(c)

	static func _is_finite(value: float) -> bool:
		return not is_nan(value) and not is_inf(value)


## Validated tire scrub render request.
class TireParams extends RefCounted:
	## Signed slip angle in degrees; only magnitude drives intensity.
	var slip_deg := 0.0
	## Forward ground speed, m/s.
	var speed_m_s := 0.0
	## Airborne cars emit no tire scrub.
	var grounded := true
	var duration_s := 0.5
	var loop_mode := LoopMode.ONE_SHOT

	static func create(
		p_slip_deg := 0.0,
		p_speed_m_s := 0.0,
		p_grounded := true,
		p_duration_s := 0.5,
		p_loop_mode: int = LoopMode.ONE_SHOT
	) -> TireParams:
		var params := TireParams.new()
		if not params.set_from_raw(p_slip_deg, p_speed_m_s, p_grounded, p_duration_s, p_loop_mode):
			return null
		return params

	func set_from_raw(
		p_slip_deg: float,
		p_speed_m_s: float,
		p_grounded: bool,
		p_duration_s: float,
		p_loop_mode: int
	) -> bool:
		if not _three_finite(p_slip_deg, p_speed_m_s, p_duration_s):
			return false
		if p_duration_s <= 0.0:
			return false
		if p_loop_mode != LoopMode.ONE_SHOT and p_loop_mode != LoopMode.LOOP:
			return false
		slip_deg = p_slip_deg
		speed_m_s = maxf(0.0, p_speed_m_s)
		grounded = p_grounded
		duration_s = p_duration_s
		loop_mode = p_loop_mode
		return true

	func is_normalized() -> bool:
		return (
			_three_finite(slip_deg, speed_m_s, duration_s)
			and speed_m_s >= 0.0
			and duration_s > 0.0
			and (loop_mode == LoopMode.ONE_SHOT or loop_mode == LoopMode.LOOP)
		)

	func copy() -> TireParams:
		var params := TireParams.new()
		params.slip_deg = slip_deg
		params.speed_m_s = speed_m_s
		params.grounded = grounded
		params.duration_s = duration_s
		params.loop_mode = loop_mode
		return params

	static func _three_finite(a: float, b: float, c: float) -> bool:
		return _is_finite(a) and _is_finite(b) and _is_finite(c)

	static func _is_finite(value: float) -> bool:
		return not is_nan(value) and not is_inf(value)


# --- Output record ----------------------------------------------------------


## One rendered mono PCM segment plus numeric telemetry. `pcm_i16_le` is
## signed 16-bit little-endian data, `frame_count * 2` bytes. Float-domain
## peaks never exceed `PEAK_LIMIT`. The director owns playback, looping,
## crossfades and mixing.
class SynthSegment extends RefCounted:
	var source := &""
	var sample_rate_hz := 0
	var frame_count := 0
	var requested_duration_s := 0.0
	var duration_s := 0.0
	var duration_clamped := false
	var loop_mode := LoopMode.ONE_SHOT
	var seed := 0
	var pcm_i16_le := PackedByteArray()
	var peak_amplitude_before_limit := 0.0
	var gain_applied := 1.0
	var peak_amplitude := 0.0
	var rms_amplitude := 0.0
	var dc_offset_before_removal := 0.0
	var dc_offset := 0.0
	var fade_s := 0.0
	## Effective source-specific values and tuning snapshot. JSON-serializable.
	var metadata := {}

	func byte_size() -> int:
		return pcm_i16_le.size()

	## Decode one frame back to the normalized float domain.
	func float_at(frame_index: int) -> float:
		var offset := frame_index * 2
		var low := pcm_i16_le[offset]
		var high := pcm_i16_le[offset + 1]
		var unsigned := low | (high << 8)
		if unsigned >= 32768:
			unsigned -= 65536
		return float(unsigned) / 32767.0


# --- Public render API ------------------------------------------------------


## Render one engine-tone segment. Returns `null` when the request or tuning
## is invalid; a refusal never mutates caller state.
static func render_engine(
	params: EngineParams,
	seed_value: int = 0,
	tuning: EngineTuning = null
) -> SynthSegment:
	if params == null or not params.is_normalized():
		return null
	var et := _engine_tuning(tuning)
	if et == null:
		return null
	var planned := _plan_segment(params.duration_s, et.sample_rate_hz)
	if not bool(planned["valid"]):
		return null
	var frames := int(planned["frame_count"])
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var speed_norm := clampf(params.speed_m_s / et.max_speed_m_s, 0.0, 1.0)
	var throttle := params.throttle
	var fundamental := _engine_fundamental_hz(et, speed_norm, throttle)
	var level := _engine_level(et, speed_norm, throttle)
	# Partial gains are normalized by their summed magnitude so ordinary
	# full-level operation stays near the peak budget; the final limiter still
	# catches residual peaks and deliberate overdrive.
	var partial_sum := 0.0
	for n in range(1, int(et.harmonic_count) + 1):
		partial_sum += et.harmonic_base / pow(float(n), et.harmonic_rolloff)
	partial_sum += et.sub_octave_gain + et.detune_gain
	var amplitude_scale := level * et.output_gain / maxf(partial_sum, 1e-9)
	var rng := RandomNumberGenerator.new()
	rng.seed = _normalize_seed(seed_value)
	var phase := 0.0
	var sub_phase := 0.0
	var detune_phase := 0.0
	var am_phase := 0.0
	var noise_state := 0.0
	var omega := TAU * fundamental / float(et.sample_rate_hz)
	var sub_omega := 0.5 * omega
	var detune_omega := omega * pow(2.0, et.detune_cents / 1200.0)
	var am_omega := TAU * clampf(fundamental / 16.0, 4.0, 30.0) / float(et.sample_rate_hz)
	for i in range(frames):
		var oscillator := 0.0
		for n in range(1, int(et.harmonic_count) + 1):
			oscillator += (
				(et.harmonic_base / pow(float(n), et.harmonic_rolloff))
				* sin(phase * float(n))
			)
		oscillator += et.sub_octave_gain * sin(sub_phase)
		oscillator += et.detune_gain * sin(detune_phase)
		oscillator *= amplitude_scale
		oscillator *= 1.0 + et.amplitude_modulation_depth * sin(am_phase)
		var white := rng.randf_range(-1.0, 1.0)
		noise_state += ENGINE_NOISE_LOWPASS * (white - noise_state)
		var noise_amount := (
			et.noise_floor
			+ et.throttle_noise_gain * throttle
			+ et.speed_noise_gain * speed_norm
		)
		samples[i] = oscillator + noise_state * noise_amount
		phase += omega
		if phase >= TAU:
			phase -= TAU
		sub_phase += sub_omega
		if sub_phase >= TAU:
			sub_phase -= TAU
		detune_phase += detune_omega
		if detune_phase >= TAU:
			detune_phase -= TAU
		am_phase += am_omega
		if am_phase >= TAU:
			am_phase -= TAU
	return _finalize_segment(
		samples,
		&"engine",
		params.loop_mode,
		seed_value,
		float(planned["duration_s"]),
		float(planned["requested_duration_s"]),
		bool(planned["clamped"]),
		et.sample_rate_hz,
		et.fade_s,
		{
			"speed_m_s": params.speed_m_s,
			"speed_normalized": speed_norm,
			"throttle": throttle,
			"nominal_fundamental_hz": fundamental,
			"level": level,
			"tuning": et.snapshot(),
		}
	)


## Render one tire-scrub segment. Returns `null` when the request or tuning is
## invalid.
static func render_tire(
	params: TireParams,
	seed_value: int = 0,
	tuning: TireTuning = null
) -> SynthSegment:
	if params == null or not params.is_normalized():
		return null
	var tt := _tire_tuning(tuning)
	if tt == null:
		return null
	var planned := _plan_segment(params.duration_s, tt.sample_rate_hz)
	if not bool(planned["valid"]):
		return null
	var frames := int(planned["frame_count"])
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var slip_norm := clampf(absf(params.slip_deg) / tt.slip_full_deg, 0.0, 1.0)
	var intensity := _tire_intensity(tt, params.slip_deg, params.speed_m_s, params.grounded)
	var speed_norm := clampf(params.speed_m_s / tt.max_speed_m_s, 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = _normalize_seed(seed_value)
	var highpass_state := 0.0
	var band_state := 0.0
	var resonance_phase := 0.0
	var resonance_omega := TAU * tt.resonance_hz / float(tt.sample_rate_hz)
	for i in range(frames):
		var white := rng.randf_range(-1.0, 1.0)
		var highpassed := white - highpass_state
		highpass_state += TIRE_HIGHPASS_ALPHA * (white - highpass_state)
		band_state += TIRE_LOWPASS_ALPHA * (highpassed - band_state)
		var wobble := 1.0 + 0.04 * band_state
		var tonal := sin(resonance_phase) * tt.tone_gain
		var value := (band_state * tt.noise_gain + tonal) * intensity
		samples[i] = value
		resonance_phase += resonance_omega * wobble
		if resonance_phase >= TAU:
			resonance_phase -= TAU
	return _finalize_segment(
		samples,
		&"tire",
		params.loop_mode,
		seed_value,
		float(planned["duration_s"]),
		float(planned["requested_duration_s"]),
		bool(planned["clamped"]),
		tt.sample_rate_hz,
		tt.fade_s,
		{
			"slip_deg": params.slip_deg,
			"slip_abs_normalized": slip_norm,
			"speed_m_s": params.speed_m_s,
			"speed_normalized": speed_norm,
			"grounded": params.grounded,
			"intensity": intensity,
			"tuning": tt.snapshot(),
		}
	)


## Render both sources for one car from committed `CarState` and normalized
## `DriverCommand` records. Reads only; it never writes the simulation,
## awards score, changes handling or contacts, or decides playback. The two
## noise streams use derived seeds so they stay independent and reproducible.
##
## Returns a Dictionary: `{"valid": bool, "error": String, "engine":
## SynthSegment, "tire": SynthSegment, "telemetry": Dictionary}`. On refusal,
## both segments are null, `valid` is false and `error` names the reason.
static func render_bundle(
	car_state,
	command,
	seed_value: int = 0,
	engine_tuning: EngineTuning = null,
	tire_tuning: TireTuning = null
) -> Dictionary:
	if car_state == null or command == null:
		return _invalid_bundle("missing CarState or DriverCommand")
	if not car_state.is_finite():
		return _invalid_bundle("nonfinite CarState")
	if not command.is_normalized():
		return _invalid_bundle("non-normalized or nonfinite DriverCommand")
	var engine_params := EngineParams.create(
		car_state.speed_m_s(), command.throttle, 0.5, LoopMode.ONE_SHOT
	)
	var tire_params := TireParams.create(
		car_state.slip_deg(), car_state.speed_m_s(), car_state.grounded, 0.5, LoopMode.ONE_SHOT
	)
	if engine_params == null or tire_params == null:
		return _invalid_bundle("unrenderable car/command values")
	var engine := render_engine(engine_params, seed_value, engine_tuning)
	var tire := render_tire(tire_params, _mix_seed(seed_value, 0x5EEDBEEF), tire_tuning)
	if engine == null or tire == null:
		return _invalid_bundle("synthesis refusal")
	return {
		"valid": true,
		"error": "",
		"engine": engine,
		"tire": tire,
		"telemetry": {
			"speed_m_s": car_state.speed_m_s(),
			"forward_speed_m_s": car_state.forward_speed_m_s(),
			"throttle": command.throttle,
			"slip_deg": car_state.slip_deg(),
			"grounded": car_state.grounded,
			"engine_source": engine.source,
			"tire_source": tire.source,
			"seed": seed_value,
		},
	}


# --- Internal synthesis -----------------------------------------------------


static func _engine_tuning(tuning) -> EngineTuning:
	if tuning == null:
		var defaults := EngineTuning.new()
		return defaults if defaults.validate() else null
	if tuning is EngineTuning and tuning.validate():
		return tuning
	return null


static func _tire_tuning(tuning) -> TireTuning:
	if tuning == null:
		var defaults := TireTuning.new()
		return defaults if defaults.validate() else null
	if tuning is TireTuning and tuning.validate():
		return tuning
	return null


## Exponential-ish pitch map across normalized speed, plus throttle lift.
static func _engine_fundamental_hz(et: EngineTuning, speed_norm: float, throttle: float) -> float:
	var ratio := et.top_hz / et.idle_hz
	return et.idle_hz * pow(ratio, speed_norm) * (1.0 + et.throttle_pitch_lift * throttle)


## Idle-to-full output level before limiting.
static func _engine_level(et: EngineTuning, speed_norm: float, throttle: float) -> float:
	var drive := clampf(0.35 * speed_norm + 0.65 * throttle, 0.0, 1.0)
	return et.idle_level + (1.0 - et.idle_level) * drive


## Tire scrub intensity: smooth onset above the slip threshold, scaled by a
## speed gate, and silenced while airborne.
static func _tire_intensity(tt: TireTuning, slip_deg: float, speed_m_s: float, grounded: bool) -> float:
	if not grounded:
		return 0.0
	var threshold_norm := clampf(tt.slip_threshold_deg / tt.slip_full_deg, 0.0, 1.0)
	var slip_norm := clampf(absf(slip_deg) / tt.slip_full_deg, 0.0, 1.0)
	var speed_factor := clampf(
		(speed_m_s - tt.min_speed_m_s) / (tt.reference_speed_m_s - tt.min_speed_m_s),
		0.0,
		1.0
	)
	return smoothstep(threshold_norm, 1.0, slip_norm) * speed_factor


## Clamp a requested duration, compute the exact frame count and report
## whether clamping occurred.
static func _plan_segment(requested_s: float, sample_rate_hz: int) -> Dictionary:
	if not _is_finite(requested_s) or requested_s <= 0.0:
		return {"valid": false}
	var clamped := clampf(requested_s, MIN_SEGMENT_DURATION_S, MAX_SEGMENT_DURATION_S)
	var clamped_flag := absf(clamped - requested_s) > 1e-12
	var frames := int(round(clamped * float(sample_rate_hz)))
	frames = clampi(frames, 1, MAX_SEGMENT_FRAMES)
	if frames > MAX_SEGMENT_FRAMES:
		return {"valid": false}
	return {
		"valid": true,
		"duration_s": clamped,
		"requested_duration_s": requested_s,
		"clamped": clamped_flag,
		"frame_count": frames,
	}


## Apply symmetric raised-cosine fades, remove DC, apply the downward-only
## peak limiter, measure the result and encode 16-bit little-endian PCM.
static func _finalize_segment(
	samples: PackedFloat32Array,
	source: StringName,
	loop_mode: int,
	seed_value: int,
	duration_s: float,
	requested_duration_s: float,
	clamped: bool,
	sample_rate_hz: int,
	configured_fade_s: float,
	metadata: Dictionary
) -> SynthSegment:
	var frames := samples.size()
	# Fades run first so both endpoints are exactly zero before DC removal;
	# removing DC afterwards would otherwise shift the loop seam off zero.
	var fade_s := minf(configured_fade_s, 0.25 * duration_s)
	var fade_frames := int(round(fade_s * float(sample_rate_hz)))
	fade_frames = clampi(fade_frames, 1, maxi(1, frames / 2))
	if frames > 1:
		for i in range(fade_frames):
			var rise := 0.5 - 0.5 * cos(PI * float(i) / float(fade_frames))
			samples[i] *= rise
			samples[frames - 1 - i] *= rise
	var dc_before := 0.0
	for i in range(frames):
		dc_before += samples[i]
	dc_before /= float(frames)
	for i in range(frames):
		samples[i] -= dc_before
	var peak_before := 0.0
	for i in range(frames):
		peak_before = maxf(peak_before, absf(samples[i]))
	var gain := 1.0
	if peak_before > PEAK_LIMIT:
		gain = PEAK_LIMIT / peak_before
	if gain < 1.0:
		for i in range(frames):
			samples[i] *= gain
	# Pin the two seam samples to zero after limiting: DC subtraction moved
	# them by a negligible amount and exact zero keeps the loop click-free.
	if frames > 1:
		samples[0] = 0.0
		samples[frames - 1] = 0.0
	var pcm := PackedByteArray()
	pcm.resize(frames * 2)
	var peak_code := int(PEAK_LIMIT * 32767.0)
	var peak := 0.0
	var encoded_peak := 0.0
	var square_sum := 0.0
	var dc_after := 0.0
	for i in range(frames):
		var value := samples[i]
		value = clampf(value, -1.0, 1.0)
		var signed := clampi(int(round(value * 32767.0)), -peak_code, peak_code)
		var quantized := signed
		if quantized < 0:
			quantized += 65536
		pcm[i * 2] = quantized & 0xFF
		pcm[i * 2 + 1] = (quantized >> 8) & 0xFF
		encoded_peak = maxf(encoded_peak, absf(float(signed) / 32767.0))
		peak = maxf(peak, absf(value))
		square_sum += value * value
		dc_after += value
	dc_after /= float(frames)
	var segment := SynthSegment.new()
	segment.source = source
	segment.sample_rate_hz = sample_rate_hz
	segment.frame_count = frames
	segment.requested_duration_s = requested_duration_s
	segment.duration_s = duration_s
	segment.duration_clamped = clamped
	segment.loop_mode = loop_mode
	segment.seed = seed_value
	segment.pcm_i16_le = pcm
	segment.peak_amplitude_before_limit = peak_before
	segment.gain_applied = gain
	segment.peak_amplitude = maxf(peak, encoded_peak)
	segment.rms_amplitude = sqrt(square_sum / float(frames))
	segment.dc_offset_before_removal = dc_before
	segment.dc_offset = dc_after
	segment.fade_s = fade_s
	segment.metadata = metadata
	return segment


static func _invalid_bundle(reason: String) -> Dictionary:
	return {
		"valid": false,
		"error": reason,
		"engine": null,
		"tire": null,
		"telemetry": {},
	}


static func _normalize_seed(seed_value: int) -> int:
	return int(seed_value & 0xFFFFFFFF)


static func _mix_seed(seed_value: int, salt: int) -> int:
	return _normalize_seed(seed_value ^ salt)


static func _is_finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)
