extends SceneTree
## Bounded local WAV preview renderer for M1.5 vehicle feedback prototyping.
##
## This tool is diagnostic only. It renders a few short segments from the pure
## `VehicleFeedbackSynth` and writes 16-bit mono RIFF/WAVE files to a
## caller-chosen directory (normally an ignored work/ directory). It adds no
## project audio content, imports no external audio, plays nothing, and makes no
## audible-quality claim.
##
## Usage from an isolated project copy:
##   godot --headless --path <project> \
##       --script res://tools/audio_lab/render_preview.gd -- \
##       --out=<absolute-output-dir> [--seconds=<0.1..4.0>]
##
## Hard bounds: one shared duration in [0.1, 4.0] s, four files, and a total
## output byte ceiling of 2,000,000 bytes. The process refuses to exceed them.

const Synth = preload("res://src/audio/vehicle_feedback_synth.gd")

const MIN_SECONDS := 0.1
const MAX_SECONDS := 4.0
const MAX_TOTAL_BYTES := 2000000


func _initialize() -> void:
	var out_dir := ""
	var seconds := 1.0
	var arguments: Array = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for argument in arguments:
		if argument.begins_with("--out="):
			out_dir = argument.substr(6)
		elif argument.begins_with("--seconds="):
			var parsed := float(argument.substr(10))
			if not is_nan(parsed) and not is_inf(parsed):
				seconds = parsed
	if out_dir.is_empty():
		printerr("FAIL: --out=<directory> is required")
		quit(2)
		return
	seconds = clampf(seconds, MIN_SECONDS, MAX_SECONDS)

	var dir_error := DirAccess.make_dir_recursive_absolute(out_dir)
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		printerr("FAIL: cannot create output directory %s (error %d)" % [out_dir, dir_error])
		quit(2)
		return

	var engine_tuning = Synth.EngineTuning.new()
	var tire_tuning = Synth.TireTuning.new()
	var engine_medium = Synth.render_engine(
		Synth.EngineParams.create(25.0, 0.7, seconds, Synth.LoopMode.ONE_SHOT),
		20261127,
		engine_tuning
	)
	var engine_high = Synth.render_engine(
		Synth.EngineParams.create(55.0, 1.0, seconds, Synth.LoopMode.ONE_SHOT),
		20261128,
		engine_tuning
	)
	var tire_scrub = Synth.render_tire(
		Synth.TireParams.create(18.0, 30.0, true, seconds, Synth.LoopMode.ONE_SHOT),
		20261129,
		tire_tuning
	)
	if engine_medium == null or engine_high == null or tire_scrub == null:
		printerr("FAIL: preview synthesis refusal")
		quit(1)
		return

	var mixed := _mix_for_preview(engine_medium, tire_scrub)
	var outputs := [
		{"name": "engine_medium.wav", "samples": _decode(engine_medium)},
		{"name": "engine_high.wav", "samples": _decode(engine_high)},
		{"name": "tire_scrub.wav", "samples": _decode(tire_scrub)},
		{"name": "combined.wav", "samples": mixed},
	]
	var rate: int = engine_medium.sample_rate_hz
	var planned_bytes := 0
	for output in outputs:
		planned_bytes += 44 + output["samples"].size() * 2
	if planned_bytes > MAX_TOTAL_BYTES:
		printerr(
			"FAIL: preview plan is %d bytes, above the %d-byte bound"
			% [planned_bytes, MAX_TOTAL_BYTES]
		)
		quit(2)
		return

	var written := 0
	for output in outputs:
		var path := out_dir.path_join(String(output["name"]))
		if not _write_wav(path, output["samples"], rate):
			printerr("FAIL: could not write %s" % path)
			quit(1)
			return
		var size := _file_size(path)
		written += size
		print("PREVIEW_WRITTEN path=%s bytes=%d" % [path, size])
	print("PREVIEW_SUMMARY ok=true files=%d total_bytes=%d seconds=%.3f" % [
		outputs.size(), written, seconds
	])
	quit(0)


func _decode(segment) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(segment.frame_count)
	for i in range(segment.frame_count):
		samples[i] = segment.float_at(i)
	return samples


## Equal-weight sum of two segments, peak-scaled to the synth headroom target.
func _mix_for_preview(first, second) -> PackedFloat32Array:
	var frame_count: int = mini(first.frame_count, second.frame_count)
	var mixed := PackedFloat32Array()
	mixed.resize(frame_count)
	var peak := 0.0
	for i in range(frame_count):
		var value: float = first.float_at(i) + second.float_at(i)
		mixed[i] = value
		peak = maxf(peak, absf(value))
	var gain := 1.0
	if peak > Synth.PEAK_LIMIT:
		gain = Synth.PEAK_LIMIT / peak
	if gain < 1.0:
		for i in range(frame_count):
			mixed[i] *= gain
	return mixed


func _write_wav(path: String, samples: PackedFloat32Array, sample_rate_hz: int) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	var data_bytes := samples.size() * 2
	file.store_string("RIFF")
	file.store_32(36 + data_bytes)
	file.store_string("WAVE")
	file.store_string("fmt ")
	file.store_32(16)
	file.store_16(1)
	file.store_16(1)
	file.store_32(sample_rate_hz)
	file.store_32(sample_rate_hz * 2)
	file.store_16(2)
	file.store_16(16)
	file.store_string("data")
	file.store_32(data_bytes)
	var peak_code := int(Synth.PEAK_LIMIT * 32767.0)
	for value in samples:
		var quantized := clampi(
			int(round(clampf(value, -1.0, 1.0) * 32767.0)), -peak_code, peak_code
		)
		file.store_16(quantized & 0xFFFF)
	file.close()
	return true


func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size: int = file.get_length()
	file.close()
	return int(size)
