class_name VehicleFeedbackPlayer
extends Node
## One-car synthesized engine/tire feedback playback component (M1.5 prototype).
##
## This node wraps the committed pure generator `VehicleFeedbackSynth` and owns
## exactly two nonpositional `AudioStreamPlayer` children: one engine voice and
## one tire voice. During setup it renders two fixed reference PCM loops through
## the real synth, converts each returned segment into one `AudioStreamWAV`
## (16-bit mono, forward loop over the whole segment) and assigns the streams
## once. Later calls to `apply()` only map committed `CarState` and normalized
## `DriverCommand` values onto `AudioStreamPlayer.pitch_scale` / `volume_db`;
## tire scrub uses the synth's direction-relative tire slip (zero when rolling
## straight forward or straight backward), so reverse no longer saturates it.
## They never re-render, replace or rebuild a stream, and allocate no per-tick
## container.
##
## Scope seams (deliberately absent):
##   * no `AudioDirector`, listener, bus routing, stereo pan, attenuation,
##     voice budget, mixing or pause/policy integration;
##   * no engine/tire force coupling, score, assist, AI, drift-state or surface
##     response: this component is strictly one-way presentation;
##   * no `CarState`/`DriverCommand` writes of any kind, including steering,
##     brake or handbrake interpretation beyond reading `throttle`.
##
## Failure contract: `apply()` requires actual `CarState`/`DriverCommand`
## instances and validates both inputs and every derived target before touching
## playback. Primitives and partially compatible objects are refused with a
## reason rather than raising a script error. A refusal leaves the last accepted
## pitch/gain and both stream assignments untouched and records a reason in
## `last_error`
## (readable through `get_last_error()`). `setup()` refuses an out-of-range
## configuration and any synth refusal; the node stays inert and setup can be
## retried after the caller repairs its configuration.
##
## Memory bound: two mono 16-bit segments of `segment_duration_s` at
## `sample_rate_hz`, each at most 192000 frames (`MAX_SETUP_BYTES` total).
##
## Provisional coefficients: the pitch, level and tire-intensity maps mirror
## the committed synth defaults documented in `tools/audio_lab/README.md`; the
## playback lab asserts that parity. Tire intensity consumes the
## direction-relative tire slip defined by `Synth`. They
## are laboratory starting points, not frozen M1.5/M5 audio specification, and
## require perceptual review. Pitch shifting a fixed reference loop changes
## timbre with speed and is a prototyping convenience, not a production model.
##
## Backend limitation: Godot's headless/dummy audio driver can start and stop
## `AudioStreamPlayer` voices, but it cannot prove audible output, mix balance
## or comfort. Only real-device listening can.

const Synth = preload("res://src/audio/vehicle_feedback_synth.gd")
const CarStateScript = preload("res://src/simulation/car_state.gd")
const DriverCommandScript = preload("res://src/simulation/driver_command.gd")

# --- Setup contract --------------------------------------------------------

## Accepted setup sample-rate bounds, mirroring the committed synth.
const MIN_SAMPLE_RATE_HZ := 8000
const MAX_SAMPLE_RATE_HZ := 48000
## Accepted loop-segment duration bounds, mirroring the committed synth.
const MIN_SEGMENT_DURATION_S := 0.05
const MAX_SEGMENT_DURATION_S := 2.0
## Absolute PCM ceiling: two segments at the synth frame cap (192000 frames,
## 16-bit mono, 2 bytes/frame) each.
const MAX_SETUP_BYTES := 768000

# --- Playback bounds -------------------------------------------------------

## Pitch is clamped well inside Godot's usable `pitch_scale` range so the
## reference loop never reverses or becomes inaudible.
const MIN_PITCH_SCALE := 0.1
const MAX_PITCH_SCALE := 4.0
## Gain is clamped to at most unity and down to effective silence.
const MIN_VOLUME_DB := -80.0
const MAX_VOLUME_DB := 0.0
const SILENCE_LINEAR := 1.0e-4

# --- Provisional mapping coefficients --------------------------------------
# These mirror the committed synth's default `EngineTuning` / `TireTuning`
# values. If those defaults change, this table must change with them.

## Speed mapped to the top of the normalized engine/tire range, m/s.
const SPEED_FULL_M_S := 65.0
const IDLE_HZ := 55.0
const TOP_HZ := 240.0
const THROTTLE_PITCH_LIFT := 0.25
const IDLE_LEVEL := 0.18
const LEVEL_SPEED_WEIGHT := 0.35
const LEVEL_THROTTLE_WEIGHT := 0.65
const TIRE_SLIP_FULL_DEG := 35.0
const TIRE_SLIP_THRESHOLD_DEG := 2.0
const TIRE_MIN_SPEED_M_S := 3.0
const TIRE_REFERENCE_SPEED_M_S := 30.0

## Base seed for the engine reference render. Fixed so equal configuration
## always yields byte-identical streams.
const DEFAULT_SEED := 0x5EED0D15
## Salt separating the tire noise stream from the engine noise stream.
const TIRE_SEED_SALT := 0x5EEDBEEF

## Setup sample rate in Hz. Public because owners configure it before adding
## the node to the tree; `setup()` refuses values outside the synth bounds.
var sample_rate_hz: int = 44100
## Reference loop length in seconds. `setup()` refuses values outside
## `[MIN_SEGMENT_DURATION_S, MAX_SEGMENT_DURATION_S]`.
var segment_duration_s: float = 0.5
## Seed for the deterministic reference renders.
var seed_value: int = DEFAULT_SEED

var _engine_player: AudioStreamPlayer
var _tire_player: AudioStreamPlayer
var _engine_stream: AudioStreamWAV
var _tire_stream: AudioStreamWAV
var _setup_complete := false
var _last_error := ""
var _reference_engine_fundamental_hz := 0.0
var _last_engine_pitch_scale := 1.0
var _last_engine_volume_db := 0.0
var _last_tire_volume_db := 0.0


func _ready() -> void:
	setup()


# --- Public lifecycle ------------------------------------------------------


## Render the two reference loops, build both streams and assign them once.
## Idempotent: a completed setup returns true without rebuilding anything.
## Returns false and records `get_last_error()` on any refusal; the node keeps
## whatever valid partial state it had, which for a first setup is none.
func setup() -> bool:
	if _setup_complete:
		return true
	if not _validate_setup_config():
		return false

	var engine_params := Synth.EngineParams.create(
		SPEED_FULL_M_S, 1.0, segment_duration_s, Synth.LoopMode.LOOP
	)
	var tire_params := Synth.TireParams.create(
		TIRE_SLIP_FULL_DEG, SPEED_FULL_M_S, true, segment_duration_s, Synth.LoopMode.LOOP
	)
	if engine_params == null or tire_params == null:
		return _fail_setup("invalid reference render parameters")

	var engine_tuning := Synth.EngineTuning.new()
	engine_tuning.sample_rate_hz = sample_rate_hz
	var tire_tuning := Synth.TireTuning.new()
	tire_tuning.sample_rate_hz = sample_rate_hz
	if not engine_tuning.validate() or not tire_tuning.validate():
		return _fail_setup("reference tuning validation refusal")

	var engine_segment := Synth.render_engine(engine_params, seed_value, engine_tuning)
	var tire_segment := Synth.render_tire(
		tire_params, _mix_seed(seed_value, TIRE_SEED_SALT), tire_tuning
	)
	if engine_segment == null or tire_segment == null:
		return _fail_setup("reference synthesis refusal")
	if engine_segment.source != &"engine" or tire_segment.source != &"tire":
		return _fail_setup("unexpected reference source label")

	var engine_stream := _make_stream(engine_segment)
	var tire_stream := _make_stream(tire_segment)
	if engine_stream == null or tire_stream == null:
		_clear_playback()
		return _fail_setup("reference PCM to stream conversion failed")
	var setup_bytes := int(engine_stream.data.size()) + int(tire_stream.data.size())
	if setup_bytes > MAX_SETUP_BYTES:
		_clear_playback()
		return _fail_setup("setup PCM exceeds the bounded memory ceiling")

	var engine_player := AudioStreamPlayer.new()
	engine_player.name = "Engine"
	engine_player.stream = engine_stream
	var tire_player := AudioStreamPlayer.new()
	tire_player.name = "Tire"
	tire_player.stream = tire_stream
	add_child(engine_player)
	add_child(tire_player)

	_engine_player = engine_player
	_tire_player = tire_player
	_engine_stream = engine_stream
	_tire_stream = tire_stream
	_reference_engine_fundamental_hz = _engine_fundamental_hz(1.0, 1.0)
	_setup_complete = true
	_last_error = ""

	# Start parked: idle engine tone, silent tires. Uses the same pure mapping
	# as apply() without constructing or validating any simulation records.
	var idle_pitch := clampf(
		_engine_fundamental_hz(0.0, 0.0) / _reference_engine_fundamental_hz,
		MIN_PITCH_SCALE,
		MAX_PITCH_SCALE
	)
	_commit_playback_targets(
		idle_pitch,
		_linear_to_bounded_db(_engine_level(0.0, 0.0)),
		_linear_to_bounded_db(0.0)
	)
	return true


## Remove both players and drop both stream references. Safe to call repeatedly
## and from `setup()` failure paths. Does not change configuration.
func teardown() -> void:
	_clear_playback()
	_setup_complete = false
	_last_error = ""


## Map one committed `CarState` plus one normalized `DriverCommand` onto the
## already-built voices. Reads only. Returns false without changing the last
## accepted pitch/gain or stream assignments when either input is null,
## nonfinite, out of range, not an actual `CarState`/`DriverCommand`, or when a
## derived target is nonfinite. On success clears the last error.
func apply(car_state, command) -> bool:
	if not _setup_complete or _engine_player == null or _tire_player == null:
		return _reject("playback is not set up")
	if car_state == null:
		return _reject("missing CarState")
	if command == null:
		return _reject("missing DriverCommand")
	if not car_state is CarStateScript:
		return _reject("incompatible CarState")
	if not command is DriverCommandScript:
		return _reject("incompatible DriverCommand")
	if not car_state.is_finite():
		return _reject("nonfinite CarState")
	if not command.is_normalized():
		return _reject("non-normalized or nonfinite DriverCommand")

	var speed := float(car_state.speed_m_s())
	var slip := Synth.direction_relative_slip_deg(
		car_state.velocity_m_s, car_state.heading_rad
	)
	var throttle := clampf(float(command.throttle), 0.0, 1.0)
	if not (_finite(speed) and _finite(slip) and _finite(throttle)):
		return _reject("nonfinite derived playback input")

	var speed_norm := clampf(speed / SPEED_FULL_M_S, 0.0, 1.0)
	var pitch := clampf(
		_engine_fundamental_hz(speed_norm, throttle) / _reference_engine_fundamental_hz,
		MIN_PITCH_SCALE,
		MAX_PITCH_SCALE
	)
	var engine_db := _linear_to_bounded_db(_engine_level(speed_norm, throttle))
	var tire_db := _linear_to_bounded_db(
		_tire_intensity(slip, speed, bool(car_state.grounded))
	)
	if not (_finite(pitch) and _finite(engine_db) and _finite(tire_db)):
		return _reject("nonfinite playback target")

	_commit_playback_targets(pitch, engine_db, tire_db)
	_last_error = ""
	return true


# --- Read-only introspection ----------------------------------------------


func is_setup_complete() -> bool:
	return _setup_complete


func get_last_error() -> String:
	return _last_error


func get_engine_player() -> AudioStreamPlayer:
	return _engine_player


func get_tire_player() -> AudioStreamPlayer:
	return _tire_player


func get_engine_stream() -> AudioStreamWAV:
	return _engine_stream


func get_tire_stream() -> AudioStreamWAV:
	return _tire_stream


## Last accepted engine pitch scale, for atomic-refusal checks.
func get_last_engine_pitch_scale() -> float:
	return _last_engine_pitch_scale


## Last accepted engine gain in dB, for atomic-refusal checks.
func get_last_engine_volume_db() -> float:
	return _last_engine_volume_db


## Last accepted tire gain in dB, for atomic-refusal checks.
func get_last_tire_volume_db() -> float:
	return _last_tire_volume_db


## PCM bytes owned by both streams. Zero before setup.
func estimated_memory_bytes() -> int:
	if not _setup_complete or _engine_stream == null or _tire_stream == null:
		return 0
	return int(_engine_stream.data.size()) + int(_tire_stream.data.size())


# --- Internal helpers ------------------------------------------------------


func _validate_setup_config() -> bool:
	if (
		not _is_positive_int(sample_rate_hz)
		or sample_rate_hz < MIN_SAMPLE_RATE_HZ
		or sample_rate_hz > MAX_SAMPLE_RATE_HZ
	):
		return _fail_setup("sample rate outside accepted bounds")
	if (
		not _finite(segment_duration_s)
		or segment_duration_s < MIN_SEGMENT_DURATION_S
		or segment_duration_s > MAX_SEGMENT_DURATION_S
	):
		return _fail_setup("segment duration outside accepted bounds")
	return true


func _make_stream(segment) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = segment.sample_rate_hz
	stream.stereo = false
	stream.data = segment.pcm_i16_le
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = segment.frame_count
	return stream


func _commit_playback_targets(pitch: float, engine_db: float, tire_db: float) -> void:
	_engine_player.pitch_scale = pitch
	_engine_player.volume_db = engine_db
	_tire_player.volume_db = tire_db
	_last_engine_pitch_scale = pitch
	_last_engine_volume_db = engine_db
	_last_tire_volume_db = tire_db


func _clear_playback() -> void:
	for player in [_engine_player, _tire_player]:
		if player != null:
			if player.get_parent() == self:
				remove_child(player)
			player.free()
	_engine_player = null
	_tire_player = null
	_engine_stream = null
	_tire_stream = null


func _fail_setup(reason: String) -> bool:
	_clear_playback()
	_setup_complete = false
	_last_error = reason
	return false


func _reject(reason: String) -> bool:
	_last_error = reason
	return false


## Mirrors the committed synth's exponential engine pitch map, including the
## throttle lift, for a normalized speed.
static func _engine_fundamental_hz(speed_norm: float, throttle: float) -> float:
	return (
		IDLE_HZ
		* pow(TOP_HZ / IDLE_HZ, speed_norm)
		* (1.0 + THROTTLE_PITCH_LIFT * throttle)
	)


## Mirrors the committed synth's idle-to-full output level map.
static func _engine_level(speed_norm: float, throttle: float) -> float:
	var drive := clampf(
		LEVEL_SPEED_WEIGHT * speed_norm + LEVEL_THROTTLE_WEIGHT * throttle,
		0.0,
		1.0
	)
	return IDLE_LEVEL + (1.0 - IDLE_LEVEL) * drive


## Mirrors the committed synth's tire intensity map over direction-relative
## tire slip: smooth onset above the slip threshold, a speed gate, and silence
## while airborne.
static func _tire_intensity(slip_deg: float, speed_m_s: float, grounded: bool) -> float:
	if not grounded:
		return 0.0
	var threshold_norm := clampf(TIRE_SLIP_THRESHOLD_DEG / TIRE_SLIP_FULL_DEG, 0.0, 1.0)
	var slip_norm := clampf(absf(slip_deg) / TIRE_SLIP_FULL_DEG, 0.0, 1.0)
	var speed_factor := clampf(
		(speed_m_s - TIRE_MIN_SPEED_M_S)
		/ (TIRE_REFERENCE_SPEED_M_S - TIRE_MIN_SPEED_M_S),
		0.0,
		1.0
	)
	return smoothstep(threshold_norm, 1.0, slip_norm) * speed_factor


## Convert a normalized linear level to a bounded dB value. Levels at or below
## zero land on `SILENCE_LINEAR` so the result stays finite and clampable.
static func _linear_to_bounded_db(linear: float) -> float:
	if not _finite(linear):
		return MIN_VOLUME_DB
	var clamped := maxf(linear, SILENCE_LINEAR)
	return clampf(linear_to_db(clamped), MIN_VOLUME_DB, MAX_VOLUME_DB)


static func _mix_seed(seed_value: int, salt: int) -> int:
	return (seed_value ^ salt) & 0xFFFFFFFF


static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)


static func _is_positive_int(value: int) -> bool:
	return value > 0
