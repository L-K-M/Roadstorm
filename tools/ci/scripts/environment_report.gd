extends SceneTree
## Original headless/display environment report for the M0 command tooling.
##
## Run by `tools/ci/ci.sh doctor`. It records the machine, engine, renderer and
## input-device facts that PLAN.md M0.6 asks to be inventoried, so a later
## performance or platform claim can be traced to a recorded configuration.
##
## Headless runs report dummy display/audio drivers and cannot enumerate
## controllers; `ci.sh doctor --display` runs the same script with a real
## display driver to record the actual GPU and audio devices.
##
## Output lines:
##   [ci-env] key=<name> value=<...>
## Exit code: 0.

func _initialize() -> void:
	var version: Dictionary = Engine.get_version_info()
	_report("engine_version", "%d.%d.%d" % [version["major"], version["minor"], version["patch"]])
	_report("engine_version_string", str(version["string"]))
	_report("engine_status", str(version.get("status", "")))
	_report("engine_build", str(version.get("build", "")))
	_report("architecture", Engine.get_architecture_name())
	_report("threading", "threaded" if ProjectSettings.get_setting("rendering/driver/threads/thread_model", 1) != 0 else "unsafe")
	_report("os_name", OS.get_name())
	_report("os_version", OS.get_version())
	_report("processor_count", str(OS.get_processor_count()))
	_report("static_memory_bytes", str(OS.get_static_memory_usage()))
	_report("display_driver", DisplayServer.get_name())
	_report("video_adapter", RenderingServer.get_video_adapter_name())
	_report("video_api", RenderingServer.get_video_adapter_api_version())
	_report("screen_size", str(DisplayServer.screen_get_size()))
	_report("rendering_method", str(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method")))
	_report("audio_output_device", str(AudioServer.output_device))
	_report("audio_mix_rate_hz", str(AudioServer.get_mix_rate()))
	_report("audio_devices", str(AudioServer.get_output_device_list()))
	_report("audio_speaker_mode", str(AudioServer.get_speaker_mode()))
	_report("user_data_dir", OS.get_user_data_dir())
	_report("cache_dir", OS.get_cache_dir())
	_report("executable", OS.get_executable_path())

	var joypads: Array = Input.get_connected_joypads()
	_report("connected_joypads", str(joypads.size()))
	for id in joypads:
		_report("joypad", "id=%s guid=%s" % [str(id), Input.get_joy_guid(id)])
	if joypads.is_empty():
		_report("joypad_note", "none connected; PLAN.md M0.6/M3 require real controller verification separately")

	_report("physics_ticks_per_second", str(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 0)))
	# "DEFAULT" resolves to the built-in Jolt backend in the pinned engine
	# (docs/TECHNICAL_DESIGN.md: "the built-in Jolt 3D backend").
	_report("physics_3d_engine", str(ProjectSettings.get_setting("physics/3d/physics_engine", "DEFAULT")))
	print("[ci-env] RESULT: PASS")
	quit(0)
	return


func _report(key: String, value: String) -> void:
	print("[ci-env] key=%s value=%s" % [key, value])
