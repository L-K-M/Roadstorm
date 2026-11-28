extends SceneTree
## Headless entry for one bounded M1 frame-trace launch.
##
## Usage (one process per nominal --fixed-fps mode):
##   godot --headless --fixed-fps <30|60|120> --path <stage> \
##       --script res://tools/frame_trace_lab/frame_trace_entry.gd
##
## Environment:
##   FTP_FPS      "30", "60" or "120"; recorded as a label, never used to
##                change the physics rate
##   FTP_VARIANT  "full" | "drop" | "short"
##   FTP_RESULT   absolute path of the result JSON
##
## The entry pins `Engine.physics_ticks_per_second` to 60 before the driver
## starts, so every launch integrates the same logical 60 Hz trace regardless
## of the nominal process frame rate. It writes an error result and exits 2 on
## invalid environment input; the driver owns run-level success and failure.

const DriverScript := preload("res://tools/frame_trace_lab/frame_trace_driver.gd")

const ALLOWED_FPS := [30, 60, 120]
const ALLOWED_VARIANTS := ["full", "drop", "short"]
const PINNED_PHYSICS_TICKS := 60


func _initialize() -> void:
	var fps_text = OS.get_environment("FTP_FPS")
	var variant = OS.get_environment("FTP_VARIANT")
	var result_path = OS.get_environment("FTP_RESULT")

	var problem = _validate_env(fps_text, variant, result_path)
	if not problem.is_empty():
		_emit_error(result_path, fps_text, variant, problem)
		quit(2)
		return

	var pre_set_physics_ticks = Engine.get_physics_ticks_per_second()
	var pre_set_max_fps = int(Engine.max_fps)
	Engine.physics_ticks_per_second = PINNED_PHYSICS_TICKS
	if Engine.get_physics_ticks_per_second() != PINNED_PHYSICS_TICKS:
		_emit_error(result_path, fps_text, variant,
			"could not pin Engine.physics_ticks_per_second to %d (observed %d)"
			% [PINNED_PHYSICS_TICKS, Engine.get_physics_ticks_per_second()])
		quit(2)
		return

	var driver = Node.new()
	driver.name = "FrameTraceDriver"
	driver.set_script(DriverScript)
	driver.pre_set_physics_ticks = pre_set_physics_ticks
	driver.pre_set_max_fps = pre_set_max_fps
	driver.pinned_physics_ticks = Engine.get_physics_ticks_per_second()
	# The root is still setting up children during _initialize(); defer the add.
	root.add_child.call_deferred(driver)


func _validate_env(fps_text: String, variant: String, result_path: String) -> String:
	var fps = int(fps_text) if fps_text.is_valid_int() else -1
	if not (fps in ALLOWED_FPS):
		return "FTP_FPS must be one of 30, 60, 120 (got " + fps_text + ")"
	if not (variant in ALLOWED_VARIANTS):
		return "FTP_VARIANT must be one of full, drop, short (got " + variant + ")"
	if result_path.is_empty():
		return "FTP_RESULT must name an absolute result JSON path"
	if not result_path.is_absolute_path():
		return "FTP_RESULT must be an absolute path (got " + result_path + ")"
	return ""


func _emit_error(path: String, fps_text: String, variant: String, reason: String) -> void:
	var nominal = null
	if fps_text.is_valid_int() and int(fps_text) in ALLOWED_FPS:
		nominal = int(fps_text)
	var result = {
		"schema": "roadstorm.frame_trace.result.v1",
		"mode": {"nominal_fixed_fps": nominal, "variant": variant},
		"error": reason,
		"harness": {"coherent": false},
	}
	if not path.is_empty():
		var file = FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(result, "  "))
			file.close()
	printerr("FRAME_TRACE_ERROR " + JSON.stringify(result))
