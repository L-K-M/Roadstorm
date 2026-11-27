extends SceneTree
## Headless node-level validator for the M1.5 one-car feedback playback
## component.
##
## Run from an isolated project copy (tools/audio_playback_lab/run_validation.sh
## stages one and imports first):
##   godot --headless --fixed-fps 60 --path <project> \
##       --script res://tools/audio_playback_lab/validate_audio_playback.gd
##
## Optional `--case=<id>` selects one case; the default runs every case.
## `--case=intentional_failure` always exits nonzero to prove the harness
## detects a failing check. Each case prints its own machine-readable result;
## the runner prints one AUDIO_PLAYBACK_RESULT line and one CHECKS_TOTAL line.
##
## These are real-node structural checks against `AudioStreamPlayer` and
## `AudioStreamWAV` objects in a running headless scene tree. They prove node
## ownership, stream format/data/loop points, stable assignments, bounded
## pitch/gain mapping, atomic invalid-input refusal and teardown. They do NOT
## prove audible quality, mix balance or comfort: Godot's headless audio driver
## is a dummy device that can start a voice flag but carries no sound.

const PlayerScript = preload("res://src/audio/vehicle_feedback_player.gd")
const Synth = preload("res://src/audio/vehicle_feedback_synth.gd")
const CarStateScript = preload("res://src/simulation/car_state.gd")
const DriverCommandScript = preload("res://src/simulation/driver_command.gd")

const CASE_IDS := [
	"nodes_and_streams",
	"stream_stability_no_resynthesis",
	"response_bounds",
	"invalid_atomic_refusal",
	"deterministic_setup",
	"teardown",
	"headless_play_flag",
]

var _checks := 0
var _failures: Array[String] = []
var _measured: Dictionary = {}
var _frame := 0
var _requested_case := "all"


func _initialize() -> void:
	for argument in OS.get_cmdline_args():
		if argument.begins_with("--case="):
			_requested_case = argument.substr(7)
	var from_environment := OS.get_environment("AUDIO_PLAYBACK_CASE")
	if from_environment != "":
		_requested_case = from_environment


func _process(_delta: float) -> bool:
	# Let the tree finish its first initialization so node addition and
	# AudioStreamPlayer.play() behave like a running scene.
	_frame += 1
	if _frame < 2:
		return false
	_run_all()
	return true


func _run_all() -> void:
	if _requested_case == "intentional_failure":
		var proof := _run_intentional_failure()
		_finish(proof, 1)
		return
	var case_ids: Array = []
	if _requested_case == "all":
		case_ids = CASE_IDS.duplicate()
	elif CASE_IDS.has(_requested_case):
		case_ids = [_requested_case]
	else:
		printerr(
			"unknown case '%s'; use all, one of %s, or intentional_failure"
			% [_requested_case, str(CASE_IDS)]
		)
		_finish({}, 2)
		return
	var results := []
	for case_id in case_ids:
		results.append(_run_case(String(case_id)))
	var failed_cases := 0
	for result in results:
		if not bool(result["pass"]):
			failed_cases += 1
	var report := {
		"schema": "roadstorm.audio_playback.validation.v1",
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


var _case_checks := 0


func _begin_case() -> void:
	_case_checks = 0


func _end_case() -> int:
	var count := _case_checks
	_checks += count
	return count


func _run_case(case_id: String) -> Dictionary:
	var before_failures := _failures.size()
	_begin_case()
	match case_id:
		"nodes_and_streams":
			_case_nodes_and_streams()
		"stream_stability_no_resynthesis":
			_case_stream_stability_no_resynthesis()
		"response_bounds":
			_case_response_bounds()
		"invalid_atomic_refusal":
			_case_invalid_atomic_refusal()
		"deterministic_setup":
			_case_deterministic_setup()
		"teardown":
			_case_teardown()
		"headless_play_flag":
			_case_headless_play_flag()
	var checks := _end_case()
	var case_failures: Array[String] = []
	for i in range(before_failures, _failures.size()):
		case_failures.append(_failures[i])
	return {
		"id": case_id,
		"checks": checks,
		"pass": case_failures.is_empty(),
		"failures": case_failures,
	}


# --- Cases ------------------------------------------------------------------


func _case_nodes_and_streams() -> void:
	var player := PlayerScript.new()
	player.sample_rate_hz = 22050
	player.segment_duration_s = 0.25
	player.seed_value = 987
	root.add_child(player)
	check(player.is_setup_complete(), "_ready uses the configured rate and duration")
	check(player.setup(), "manual setup is idempotent after auto setup")
	check(player.is_setup_complete(), "setup reports complete")
	check_eq(player.get_child_count(), 2, "component owns exactly two child nodes")

	var engine_player = player.get_node_or_null("Engine")
	var tire_player = player.get_node_or_null("Tire")
	check(engine_player != null and tire_player != null, "both named players exist")
	if engine_player == null or tire_player == null:
		player.free()
		return
	check_eq(engine_player.get_class(), "AudioStreamPlayer", "engine node is an AudioStreamPlayer")
	check_eq(tire_player.get_class(), "AudioStreamPlayer", "tire node is an AudioStreamPlayer")
	check(
		engine_player.get_parent() == player and tire_player.get_parent() == player,
		"players are owned by the component"
	)

	var expected_frames := int(round(0.25 * 22050.0))
	var engine_stream = engine_player.stream
	var tire_stream = tire_player.stream
	check(engine_stream is AudioStreamWAV, "engine stream is AudioStreamWAV")
	check(tire_stream is AudioStreamWAV, "tire stream is AudioStreamWAV")
	if engine_stream == null or tire_stream == null:
		player.free()
		return
	check_eq(engine_stream.format, AudioStreamWAV.FORMAT_16_BITS, "engine format is 16-bit")
	check_eq(tire_stream.format, AudioStreamWAV.FORMAT_16_BITS, "tire format is 16-bit")
	check_eq(engine_stream.mix_rate, 22050, "engine mix rate follows configuration")
	check_eq(tire_stream.mix_rate, 22050, "tire mix rate follows configuration")
	check_false(engine_stream.stereo, "engine stream is mono")
	check_false(tire_stream.stereo, "tire stream is mono")
	check_eq(engine_stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "engine loops forward")
	check_eq(tire_stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "tire loops forward")
	check_eq(engine_stream.loop_begin, 0, "engine loop starts at frame zero")
	check_eq(tire_stream.loop_begin, 0, "tire loop starts at frame zero")
	check_eq(engine_stream.loop_end, expected_frames, "engine loop ends at the frame count")
	check_eq(tire_stream.loop_end, expected_frames, "tire loop ends at the frame count")
	check_eq(engine_stream.data.size(), expected_frames * 2, "engine PCM byte size matches frames")
	check_eq(tire_stream.data.size(), expected_frames * 2, "tire PCM byte size matches frames")
	check_eq(engine_stream.data[0], 0, "engine seam starts at zero")
	check_eq(engine_stream.data[1], 0, "engine second seam byte is zero")
	var engine_last: int = engine_stream.data.size() - 1
	check_eq(engine_stream.data[engine_last], 0, "engine seam ends at zero")
	check(
		engine_stream.data != tire_stream.data,
		"engine and tire streams carry different PCM"
	)

	# Conversion preserves the committed synth bytes exactly.
	var engine_tuning := Synth.EngineTuning.new()
	engine_tuning.sample_rate_hz = 22050
	var tire_tuning := Synth.TireTuning.new()
	tire_tuning.sample_rate_hz = 22050
	var engine_segment := Synth.render_engine(
		Synth.EngineParams.create(
			PlayerScript.SPEED_FULL_M_S, 1.0, 0.25, Synth.LoopMode.LOOP
		),
		987,
		engine_tuning
	)
	var tire_segment := Synth.render_tire(
		Synth.TireParams.create(
			PlayerScript.TIRE_SLIP_FULL_DEG,
			PlayerScript.SPEED_FULL_M_S,
			true,
			0.25,
			Synth.LoopMode.LOOP
		),
		(987 ^ PlayerScript.TIRE_SEED_SALT) & 0xFFFFFFFF,
		tire_tuning
	)
	check(engine_segment != null and tire_segment != null, "independent synth reference renders")
	if engine_segment != null and tire_segment != null:
		check_eq(
			engine_stream.data,
			engine_segment.pcm_i16_le,
			"engine stream bytes equal the committed synth segment"
		)
		check_eq(
			tire_stream.data,
			tire_segment.pcm_i16_le,
			"tire stream bytes equal the committed synth segment"
		)

	check_eq(
		player.estimated_memory_bytes(),
		expected_frames * 2 * 2,
		"reported setup memory equals both PCM buffers"
	)
	check(
		player.estimated_memory_bytes() <= PlayerScript.MAX_SETUP_BYTES,
		"setup memory stays under the bounded ceiling"
	)
	_measured["setup_pcm_bytes"] = player.estimated_memory_bytes()
	_measured["setup_frames_per_voice"] = expected_frames

	# _ready also performs automatic setup for an unconfigured instance.
	var auto_player := PlayerScript.new()
	root.add_child(auto_player)
	check(auto_player.is_setup_complete(), "_ready performs automatic setup")
	check_eq(auto_player.get_child_count(), 2, "auto setup owns exactly two players")
	auto_player.free()
	player.free()


func _case_stream_stability_no_resynthesis() -> void:
	var player = _make_player(22050, 0.25, 555)
	check(player.is_setup_complete(), "stability fixture setup completes")
	var engine_stream: AudioStreamWAV = player.get_engine_stream()
	var tire_stream: AudioStreamWAV = player.get_tire_stream()
	if engine_stream == null or tire_stream == null:
		check(false, "stability fixture has both streams")
		player.free()
		return
	var engine_data = engine_stream.data
	var tire_data = tire_stream.data
	var engine_ref: AudioStreamWAV = engine_stream
	var tire_ref: AudioStreamWAV = tire_stream
	var updates := 0
	var refusals := 0
	for i in range(240):
		var speed := 30.0 + 28.0 * sin(float(i) * 0.11)
		var lateral := 6.0 * sin(float(i) * 0.37)
		var state = _make_car(speed, lateral)
		state.grounded = i % 7 != 0
		var command = _make_command(0.2 + 0.7 * absf(sin(float(i) * 0.23)))
		if not player.apply(state, command):
			refusals += 1
			continue
		updates += 1
		if player.get_engine_player().stream != engine_ref:
			check(false, "engine stream replaced during update %d" % i)
			break
		if player.get_tire_player().stream != tire_ref:
			check(false, "tire stream replaced during update %d" % i)
			break
		if engine_stream.data != engine_data:
			check(false, "engine PCM changed during update %d" % i)
			break
		if tire_stream.data != tire_data:
			check(false, "tire PCM changed during update %d" % i)
			break
		check_eq(player.get_child_count(), 2, "update keeps exactly two child nodes")
		var pitch = player.get_engine_player().pitch_scale
		var engine_db = player.get_engine_player().volume_db
		var tire_db = player.get_tire_player().volume_db
		check_between(pitch, PlayerScript.MIN_PITCH_SCALE, PlayerScript.MAX_PITCH_SCALE, "pitch bounded")
		check_between(engine_db, PlayerScript.MIN_VOLUME_DB, PlayerScript.MAX_VOLUME_DB, "engine gain bounded")
		check_between(tire_db, PlayerScript.MIN_VOLUME_DB, PlayerScript.MAX_VOLUME_DB, "tire gain bounded")
		check(not is_nan(pitch) and not is_inf(pitch), "pitch finite")
	check_eq(refusals, 0, "every scripted update is accepted")
	check_eq(updates, 240, "all 240 updates ran")
	_measured["stability_updates"] = updates
	player.free()


func _case_response_bounds() -> void:
	var player = _make_player(44100, 0.25, 77)
	check(player.is_setup_complete(), "response fixture setup completes")

	var idle_state = _make_car(0.0, 0.0)
	var idle_command = _make_command(0.0)
	check(player.apply(idle_state, idle_command), "idle/coast input accepted")
	var idle_pitch: float = player.get_engine_player().pitch_scale
	var idle_engine_db: float = player.get_engine_player().volume_db
	var idle_tire_db: float = player.get_tire_player().volume_db

	var fast_state = _make_car(PlayerScript.SPEED_FULL_M_S, 0.0)
	var fast_command = _make_command(1.0)
	check(player.apply(fast_state, fast_command), "full-speed/full-throttle input accepted")
	var fast_pitch: float = player.get_engine_player().pitch_scale
	var fast_engine_db: float = player.get_engine_player().volume_db
	check(fast_pitch > idle_pitch, "engine pitch rises from idle to full speed")
	check(fast_engine_db > idle_engine_db, "engine gain rises from idle to full speed")
	check_eq(fast_engine_db, PlayerScript.MAX_VOLUME_DB, "reference-level input reaches unity gain")
	check_close(
		fast_pitch,
		1.0,
		1e-6,
		"full-speed/full-throttle reference plays at pitch scale one"
	)
	check_close(
		idle_tire_db,
		PlayerScript.MIN_VOLUME_DB,
		1e-6,
		"stationary tire voice is silent"
	)

	var speeds := [0.0, 10.0, 25.0, 40.0, 65.0]
	var previous_pitch := -1.0
	var previous_engine_db := -INF
	for speed in speeds:
		var state = _make_car(float(speed), 0.0)
		var command = _make_command(0.5)
		if not player.apply(state, command):
			check(false, "speed sweep input accepted (%.1f)" % speed)
			continue
		var pitch: float = player.get_engine_player().pitch_scale
		var engine_db: float = player.get_engine_player().volume_db
		check(pitch >= previous_pitch - 1e-9, "engine pitch does not fall across speed (%.1f)" % speed)
		previous_pitch = pitch
		check(
			engine_db >= previous_engine_db - 1e-9,
			"engine gain does not fall across speed (%.1f)" % speed
		)
		previous_engine_db = engine_db
		check_between(pitch, PlayerScript.MIN_PITCH_SCALE, PlayerScript.MAX_PITCH_SCALE, "pitch bounded")
		check_between(engine_db, PlayerScript.MIN_VOLUME_DB, PlayerScript.MAX_VOLUME_DB, "gain bounded")
	_measured["engine_pitch_idle"] = idle_pitch
	_measured["engine_pitch_full"] = fast_pitch
	_measured["engine_db_idle"] = idle_engine_db
	_measured["engine_db_full"] = fast_engine_db

	var throttles := [0.0, 0.5, 1.0]
	previous_pitch = -1.0
	for throttle in throttles:
		var state = _make_car(30.0, 0.0)
		var command = _make_command(float(throttle))
		if not player.apply(state, command):
			check(false, "throttle sweep input accepted (%.1f)" % throttle)
			continue
		var pitch: float = player.get_engine_player().pitch_scale
		check(pitch >= previous_pitch - 1e-9, "engine pitch does not fall across throttle (%.1f)" % throttle)
		previous_pitch = pitch
	_measured["engine_pitch_throttle_1"] = previous_pitch

	var slips := [0.0, 2.0, 3.0, 10.0, 35.0, 90.0]
	var previous_tire_db := -INF
	for slip in slips:
		var state = _make_car(30.0, 0.0)
		state.velocity_m_s = Vector2(sin(deg_to_rad(float(slip))) * 30.0, cos(deg_to_rad(float(slip))) * 30.0)
		var command = _make_command(0.5)
		if not player.apply(state, command):
			check(false, "slip sweep input accepted (%.1f)" % slip)
			continue
		var tire_db: float = player.get_tire_player().volume_db
		check(tire_db >= previous_tire_db - 1e-9, "tire gain does not fall across slip (%.1f)" % slip)
		previous_tire_db = tire_db
		check_between(tire_db, PlayerScript.MIN_VOLUME_DB, PlayerScript.MAX_VOLUME_DB, "tire gain bounded")
		_measured["tire_db_at_%d_deg" % int(slip)] = tire_db
	check_close(
		float(_measured["tire_db_at_2_deg"]),
		PlayerScript.MIN_VOLUME_DB,
		1e-6,
		"tire voice silent at/below the slip threshold"
	)
	check_close(
		float(_measured["tire_db_at_90_deg"]),
		PlayerScript.MAX_VOLUME_DB,
		1e-6,
		"saturated slide reaches full tire gain"
	)
	check(
		float(_measured["tire_db_at_90_deg"]) > float(_measured["tire_db_at_3_deg"]),
		"grip-to-slide tire gain rises"
	)

	var airborne_state = _make_car(30.0, 12.0)
	airborne_state.grounded = false
	var airborne_command = _make_command(0.5)
	check(player.apply(airborne_state, airborne_command), "airborne input accepted")
	check_close(
		player.get_tire_player().volume_db,
		PlayerScript.MIN_VOLUME_DB,
		1e-6,
		"airborne tire voice is silenced"
	)

	# Deterministic mapping: identical input twice gives identical settings.
	var repeat_state = _make_car(27.0, 4.0)
	var repeat_command = _make_command(0.6)
	check(player.apply(repeat_state, repeat_command), "repeat input accepted")
	var first_pitch: float = player.get_engine_player().pitch_scale
	var first_engine_db: float = player.get_engine_player().volume_db
	var first_tire_db: float = player.get_tire_player().volume_db
	check(player.apply(repeat_state, repeat_command), "repeat input accepted twice")
	check_eq(player.get_engine_player().pitch_scale, first_pitch, "repeat pitch is identical")
	check_eq(player.get_engine_player().volume_db, first_engine_db, "repeat engine gain is identical")
	check_eq(player.get_tire_player().volume_db, first_tire_db, "repeat tire gain is identical")
	_measured["tire_db_full_slide"] = first_tire_db
	player.free()


func _case_invalid_atomic_refusal() -> void:
	var player = _make_player(44100, 0.25, 123)
	check(player.is_setup_complete(), "atomicity fixture setup completes")
	var good_state = _make_car(20.0, 1.0)
	var good_command = _make_command(0.5)
	check(player.apply(good_state, good_command), "baseline valid input accepted")

	var snapshot_pitch: float = player.get_engine_player().pitch_scale
	var snapshot_engine_db: float = player.get_engine_player().volume_db
	var snapshot_tire_db: float = player.get_tire_player().volume_db
	var snapshot_engine_stream: AudioStreamWAV = player.get_engine_stream()
	var snapshot_tire_stream: AudioStreamWAV = player.get_tire_stream()
	var snapshot_last_pitch: float = player.get_last_engine_pitch_scale()
	var snapshot_last_engine_db: float = player.get_last_engine_volume_db()
	var snapshot_last_tire_db: float = player.get_last_tire_volume_db()

	var nan_state = _make_car(20.0, 0.0)
	nan_state.velocity_m_s = Vector2(NAN, 20.0)
	var inf_state = _make_car(20.0, 0.0)
	inf_state.heading_rad = INF
	var overflow_state = _make_car(0.0, 0.0)
	overflow_state.velocity_m_s = Vector2(1.0e308, 1.0e308)
	var direct_nan_command = _make_command(0.4)
	direct_nan_command.throttle = NAN
	var direct_range_command = _make_command(0.4)
	direct_range_command.brake = 7.0
	var incompatible_state := RefCounted.new()
	var incompatible_command := RefCounted.new()

	var invalid_inputs := [
		{"label": "null state", "state": null, "command": good_command},
		{"label": "null command", "state": good_state, "command": null},
		{"label": "NaN state component", "state": nan_state, "command": good_command},
		{"label": "infinite state component", "state": inf_state, "command": good_command},
		{"label": "finite-but-overflowing speed", "state": overflow_state, "command": good_command},
		{"label": "direct NaN command field", "state": good_state, "command": direct_nan_command},
		{"label": "direct out-of-range command field", "state": good_state, "command": direct_range_command},
		{"label": "incompatible state object", "state": incompatible_state, "command": good_command},
		{"label": "incompatible command object", "state": good_state, "command": incompatible_command},
	]
	var refusals := 0
	for entry in invalid_inputs:
		var accepted: bool = player.apply(entry["state"], entry["command"])
		if accepted:
			check(false, "refuses %s" % String(entry["label"]))
			continue
		refusals += 1
		check(
			player.get_last_error() != "",
			"refusal for %s records a reason" % String(entry["label"])
		)
		check_eq(player.get_engine_player().pitch_scale, snapshot_pitch, "refusal keeps engine pitch")
		check_eq(player.get_engine_player().volume_db, snapshot_engine_db, "refusal keeps engine gain")
		check_eq(player.get_tire_player().volume_db, snapshot_tire_db, "refusal keeps tire gain")
		check_eq(player.get_engine_stream(), snapshot_engine_stream, "refusal keeps engine stream")
		check_eq(player.get_tire_stream(), snapshot_tire_stream, "refusal keeps tire stream")
		check_eq(player.get_last_engine_pitch_scale(), snapshot_last_pitch, "refusal keeps last pitch")
		check_eq(player.get_last_engine_volume_db(), snapshot_last_engine_db, "refusal keeps last engine gain")
		check_eq(player.get_last_tire_volume_db(), snapshot_last_tire_db, "refusal keeps last tire gain")
	check_eq(refusals, invalid_inputs.size(), "every invalid input refused")

	# A refusal must not repair or mutate the rejected records either.
	check(is_nan(nan_state.velocity_m_s.x), "rejected NaN state component untouched")
	check_eq(inf_state.heading_rad, INF, "rejected infinite heading untouched")
	check(is_nan(direct_nan_command.throttle), "rejected NaN command field untouched")
	check_eq(direct_range_command.brake, 7.0, "rejected out-of-range command field untouched")

	# The last accepted settings still work after refusals.
	check(player.apply(good_state, good_command), "valid input still accepted after refusals")
	check_eq(player.get_engine_player().pitch_scale, snapshot_pitch, "settings restored to last accepted")
	_measured["atomic_refusals"] = refusals

	# apply() must not mutate a valid state or command.
	var input_state = _make_car(17.0, 3.0)
	input_state.heading_rad = 0.4
	input_state.grounded = false
	var state_copy = input_state.copy()
	var input_command = _make_command(0.65)
	input_command.steer = -0.3
	var command_copy = input_command.copy()
	check(player.apply(input_state, input_command), "mutation-probe input accepted")
	check_eq(input_state.position_m, state_copy.position_m, "apply leaves position untouched")
	check_eq(input_state.velocity_m_s, state_copy.velocity_m_s, "apply leaves velocity untouched")
	check_eq(input_state.heading_rad, state_copy.heading_rad, "apply leaves heading untouched")
	check_eq(input_state.grounded, state_copy.grounded, "apply leaves grounded untouched")
	check_eq(input_command.steer, command_copy.steer, "apply leaves steer untouched")
	check_eq(input_command.throttle, command_copy.throttle, "apply leaves throttle untouched")
	check_eq(input_command.brake, command_copy.brake, "apply leaves brake untouched")
	check_eq(input_command.handbrake, command_copy.handbrake, "apply leaves handbrake untouched")
	player.free()


func _case_deterministic_setup() -> void:
	var first := PlayerScript.new()
	first.sample_rate_hz = 16000
	first.segment_duration_s = 0.2
	first.seed_value = 4242
	check(first.setup(), "first deterministic setup succeeds")
	var second := PlayerScript.new()
	second.sample_rate_hz = 16000
	second.segment_duration_s = 0.2
	second.seed_value = 4242
	check(second.setup(), "second deterministic setup succeeds")
	if not first.is_setup_complete() or not second.is_setup_complete():
		first.free()
		second.free()
		return
	var first_engine: AudioStreamWAV = first.get_engine_stream()
	var first_tire: AudioStreamWAV = first.get_tire_stream()
	var second_engine: AudioStreamWAV = second.get_engine_stream()
	var second_tire: AudioStreamWAV = second.get_tire_stream()
	check_eq(first_engine.data, second_engine.data, "equal setup gives byte-identical engine PCM")
	check_eq(first_tire.data, second_tire.data, "equal setup gives byte-identical tire PCM")
	check_eq(first_engine.mix_rate, second_engine.mix_rate, "equal setup keeps engine rate")
	check_eq(first_tire.mix_rate, second_tire.mix_rate, "equal setup keeps tire rate")
	check_eq(first_engine.loop_end, second_engine.loop_end, "equal setup keeps engine loop end")
	check_eq(first_tire.loop_end, second_tire.loop_end, "equal setup keeps tire loop end")
	check(
		first.estimated_memory_bytes() <= PlayerScript.MAX_SETUP_BYTES,
		"deterministic setup stays inside the memory ceiling"
	)
	_measured["deterministic_pcm_bytes"] = first.estimated_memory_bytes()

	first.teardown()
	check(not first.is_setup_complete(), "teardown clears completion")
	check_eq(first.get_child_count(), 0, "teardown removes both players")
	check(first.setup(), "re-setup after teardown succeeds")
	check_eq(first.get_engine_stream().data, first_engine.data, "re-setup reproduces engine bytes")
	check_eq(first.get_tire_stream().data, first_tire.data, "re-setup reproduces tire bytes")
	first.free()
	second.free()


func _case_teardown() -> void:
	var player = _make_player(22050, 0.25, 909)
	check(player.is_setup_complete(), "teardown fixture setup completes")
	var engine_player: AudioStreamPlayer = player.get_engine_player()
	var tire_player: AudioStreamPlayer = player.get_tire_player()
	check(engine_player != null and tire_player != null, "teardown fixture owns both players")
	var engine_stream: AudioStreamWAV = player.get_engine_stream()
	var tire_stream: AudioStreamWAV = player.get_tire_stream()
	player.teardown()
	check(not player.is_setup_complete(), "teardown marks setup incomplete")
	check_eq(player.get_child_count(), 0, "teardown leaves no child nodes")
	check(player.get_engine_player() == null, "teardown drops the engine player")
	check(player.get_tire_player() == null, "teardown drops the tire player")
	check(player.get_engine_stream() == null, "teardown drops the engine stream")
	check(player.get_tire_stream() == null, "teardown drops the tire stream")
	check_eq(player.estimated_memory_bytes(), 0, "teardown reports zero PCM memory")
	check(not player.apply(_make_car(20.0, 0.0), _make_command(0.5)), "apply refused after teardown")
	check(player.get_last_error() != "", "post-teardown refusal records a reason")
	check(player.setup(), "setup works again after teardown")
	check(player.get_engine_player() != null, "re-setup rebuilds the engine player")
	check(player.get_tire_player() != null, "re-setup rebuilds the tire player")
	check(player.get_engine_stream() != engine_stream, "re-setup builds a fresh engine stream")
	check(player.get_tire_stream() != tire_stream, "re-setup builds a fresh tire stream")
	check_eq(player.estimated_memory_bytes(), 2 * 5513 * 2, "re-setup PCM size matches 0.25 s at 22050 Hz")
	_measured["teardown_child_count"] = player.get_child_count()
	player.free()


func _case_headless_play_flag() -> void:
	# Dummy-driver observation only: it proves the nodes accept play/stop in a
	# running tree, never that anyone can hear them.
	var player = _make_player(22050, 0.25, 31)
	check(player.is_setup_complete(), "play-flag fixture setup completes")
	var engine_player: AudioStreamPlayer = player.get_engine_player()
	var tire_player: AudioStreamPlayer = player.get_tire_player()
	engine_player.play()
	tire_player.play()
	check(engine_player.playing, "dummy driver reports the engine voice playing")
	check(tire_player.playing, "dummy driver reports the tire voice playing")
	engine_player.stop()
	tire_player.stop()
	check(not engine_player.playing, "stop clears the engine playing flag")
	check(not tire_player.playing, "stop clears the tire playing flag")
	_measured["headless_play_flag_supported"] = 1
	player.free()


# --- Deliberate failure proof ----------------------------------------------


func _run_intentional_failure() -> Dictionary:
	# Deliberately false expectation about a real setup: a configured
	# AudioStreamWAV mix rate is never zero. This assertion must fail and the
	# process must exit nonzero, proving the harness detects failures rather
	# than inferring a pass from the exit status.
	var player := PlayerScript.new()
	player.sample_rate_hz = 22050
	root.add_child(player)
	check(player.setup(), "intentional-failure fixture setup")
	var mix_rate := 0
	if player.is_setup_complete():
		mix_rate = player.get_engine_stream().mix_rate
	check_eq(mix_rate, 0, "intentional failure probe: mix rate unexpectedly zero")
	var proof := {
		"schema": "roadstorm.audio_playback.validation.v1",
		"proof": "intentional_failure",
		"expected_nonzero_exit": true,
		"observed_checks_failed": _failures.size(),
		"pass": _failures.is_empty(),
		"failures": _failures.duplicate(),
	}
	print("INTENTIONAL_FAILURE_PROOF " + JSON.stringify(proof))
	player.free()
	return proof


# --- Fixtures and check helpers --------------------------------------------


func _make_player(rate: int, duration: float, seed_value: int):
	var player := PlayerScript.new()
	player.sample_rate_hz = rate
	player.segment_duration_s = duration
	player.seed_value = seed_value
	root.add_child(player)
	check(player.is_setup_complete(), "fixture player setup completes")
	return player


func _make_car(forward_speed_m_s: float, lateral_speed_m_s: float):
	var state := CarStateScript.new()
	state.velocity_m_s = Vector2(lateral_speed_m_s, forward_speed_m_s)
	return state


func _make_command(throttle: float):
	return DriverCommandScript.create(0.0, throttle, 0.0, 0.0, false)


func check(condition: bool, message: String) -> void:
	_case_checks += 1
	if not condition:
		_failures.append(message)


func check_eq(actual, expected, message: String) -> void:
	_case_checks += 1
	if actual != expected:
		_failures.append("%s (actual=%s expected=%s)" % [message, str(actual), str(expected)])


func check_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	_case_checks += 1
	if is_nan(actual) or is_inf(actual) or absf(actual - expected) > tolerance:
		_failures.append(
			"%s (actual=%s expected=%s tol=%s)" % [message, actual, expected, tolerance]
		)


func check_between(value: float, low: float, high: float, message: String) -> void:
	_case_checks += 1
	if is_nan(value) or is_inf(value) or value < low - 1e-9 or value > high + 1e-9:
		_failures.append(
			"%s (value=%s range=[%s,%s])" % [message, value, low, high]
		)


func check_false(condition: bool, message: String) -> void:
	check(not condition, message)


# --- Report -----------------------------------------------------------------


const LIMITATIONS := [
	"Real node structure only: AudioStreamPlayer/AudioStreamWAV ownership, format, mono layout, PCM bytes and loop points are inspected in a running headless tree.",
	"Headless Godot uses dummy display and audio drivers. The play/stop case proves only that the dummy server accepts voice start/stop; it cannot prove audible output, mix balance, timbre or comfort.",
	"The pitch/gain mapping proves bounded, monotonic numeric response over scripted idle-to-fast and grip-to-slide inputs; it says nothing about perceived loudness or audio quality.",
	"Pitch shifting one fixed reference loop changes timbre with speed. Production audio needs re-synthesis, layered variants or a director-owned design; this is a one-car prototype.",
	"No AudioDirector, listener, bus routing, stereo pan, attenuation, voice budget, pause policy or four-player mixing is exercised.",
	"No simulation authority is read or written: car states and commands are scripted records, and no sound feeds physics, score, AI or car state.",
	"All mapping coefficients mirror the provisional committed synth defaults and require perceptual review and production tuning.",
	"A mono dummy driver cannot validate stereo placement, which this slice does not implement anyway.",
	"LongCat-authored creative source remains un-cleared for release; provenance OI-02 is open. No M1.5 or M1 acceptance claim is made.",
]


func _finish(report: Dictionary, forced_exit: int = -1) -> void:
	var passed := _failures.is_empty() and int(report.get("failed_cases", 0)) == 0
	var code := forced_exit
	if code < 0:
		code = 0 if passed else 1
	print("AUDIO_PLAYBACK_RESULT " + JSON.stringify(report))
	print("CHECKS_TOTAL=%d CHECKS_FAILED=%d" % [_checks, _failures.size()])
	quit(code)
