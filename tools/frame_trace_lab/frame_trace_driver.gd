extends Node
## Bounded M1 numerical frame-rate comparison driver (tools/frame_trace_lab).
##
## Runs the real committed one-car `DriveLab` scene
## (`scenes/laboratory/drive_lab.tscn`) with its own ordinary motor tuning,
## motor-body adapter config and canonical `AutomaticGearbox`, driven by one
## fixed 1200-logical-tick traffic-free command schedule (20 s at 60 Hz) with
## exactly one command per committed physics tick. The only integration path
## is `DriveLab._physics_process()` -> `DriveLab.step_once()`; this driver never
## re-implements motor, gearbox or adapter math. One Godot process handles one
## nominal rendered-FPS launch (`--fixed-fps`), while
## `frame_trace_entry.gd` pins `Engine.physics_ticks_per_second` to 60.
##
## Environment contract (validated by the entry and re-checked here):
##   FTP_FPS      nominal --fixed-fps label: "30", "60" or "120"
##   FTP_VARIANT  "full"  = the fixed 1200-tick schedule
##                "drop"  = deliberate negative control: every third command
##                          is idle, so the trajectory must deviate
##                "short" = deliberate negative control: the final command is
##                          withheld, so the run completes one tick early
##   FTP_RESULT   absolute path of the result JSON to write
##
## Output: one `FRAME_TRACE_RESULT <json>` line on stdout and the same JSON at
## FTP_RESULT. Exit code 0 means the harness ran coherently and wrote a
## result; interpretation of the numbers belongs to the comparator. A halt,
## early completion, missing ticks, dropped tick-log records, a refused
## configuration or an unwritable result are reported as `coherent: false`
## with a nonzero exit.

const DriveLabScenePath := "res://scenes/laboratory/drive_lab.tscn"
const DriverCommandScript := preload("res://src/simulation/driver_command.gd")

## docs/BENCHMARKS.md 'Numerical comparisons': a fixed 20-second trace.
const SCHEDULE_TICKS := 1200
## Authored schedule phases, in logical ticks at 60 Hz.
const THROTTLE_TICKS := 420
const COAST_TICKS := 120
## Gate-time criterion station from docs/BENCHMARKS.md.
const GATE_STATION_M := 100.0
## Physics frames awaited before `start()`, mirroring the committed driver's
## settle pattern. Presentation and spawn construction settle without consuming
## scripted commands.
const SETTLE_FRAMES := 10
## Extra physics frames awaited after the run so terminal callbacks land.
const DRAIN_FRAMES := 4
## Bounded guard: a refusal, stall or early halt must fail instead of hanging.
const GUARD_FRAMES := SCHEDULE_TICKS * 4 + 240
## The laboratory's own course margins, mirrored here only for reporting the
## measured envelope against the authored straight.
const COURSE_END_MARGIN_M := 40.0
const COURSE_START_MARGIN_M := 10.0

const ALLOWED_VARIANTS := ["full", "drop", "short"]

## Recorded by frame_trace_entry.gd before it pins the physics tick rate.
var pre_set_physics_ticks = -1
var pre_set_max_fps = -1
var pinned_physics_ticks = -1

var _lab = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _run() -> void:
	var fps_text = OS.get_environment("FTP_FPS")
	var variant = OS.get_environment("FTP_VARIANT")
	var result_path = OS.get_environment("FTP_RESULT")
	if not _env_valid(fps_text, variant, result_path):
		_write_error(result_path, fps_text, variant,
			"invalid FTP_FPS/FTP_VARIANT/FTP_RESULT")
		get_tree().quit(2)
		return

	var schedule = _build_schedule(variant)
	if schedule.is_empty():
		_write_error(result_path, fps_text, variant,
			"the command schedule is empty")
		get_tree().quit(1)
		return
	var expected_ticks = SCHEDULE_TICKS if variant != "short" else SCHEDULE_TICKS - 1

	var packed: PackedScene = load(DriveLabScenePath)
	if packed == null:
		_write_error(result_path, fps_text, variant,
			"could not load " + DriveLabScenePath)
		get_tree().quit(1)
		return
	var lab = packed.instantiate()
	if lab == null:
		_write_error(result_path, fps_text, variant,
			"could not instantiate the DriveLab scene")
		get_tree().quit(1)
		return
	_lab = lab

	# The real laboratory's own factories supply the ordinary tuning and
	# adapter config; its _init owns the canonical gearbox.
	var tuning = lab.make_laboratory_tuning()
	var config = lab.make_laboratory_config()
	if tuning == null or not tuning.is_valid():
		_write_error(result_path, fps_text, variant,
			"laboratory motor tuning is invalid")
		get_tree().quit(1)
		return
	if config == null or not config.is_valid():
		_write_error(result_path, fps_text, variant,
			"laboratory motor-body config is invalid")
		get_tree().quit(1)
		return
	if not lab.configure(tuning, config, schedule):
		_write_error(result_path, fps_text, variant,
			"laboratory refused the configuration: " + str(lab.failure_reason))
		get_tree().quit(1)
		return
	add_child(lab)

	for _index in range(SETTLE_FRAMES):
		await get_tree().physics_frame
	if lab.failed or lab.halted:
		_write_error(result_path, fps_text, variant,
			"laboratory failed before start: " + str(lab.failure_reason)
			+ " / " + str(lab.halt_reason))
		get_tree().quit(1)
		return

	var start_physics_frames = Engine.get_physics_frames()
	var start_process_frames = Engine.get_process_frames()
	var start_callbacks = int(lab.physics_callbacks)
	var start_ms = Time.get_ticks_msec()
	lab.start()

	var guard = 0
	while int(lab.ticks_committed) < expected_ticks and guard < GUARD_FRAMES:
		if lab.failed or lab.halted or lab.completed:
			break
		await get_tree().physics_frame
		guard += 1
	for _index in range(DRAIN_FRAMES):
		await get_tree().physics_frame

	var wall_ms = Time.get_ticks_msec() - start_ms
	var result = _build_result(lab, fps_text, variant, schedule, expected_ticks,
		start_physics_frames, start_process_frames, start_callbacks,
		wall_ms, guard)
	if not _write_result(result_path, result):
		printerr("[frame_trace] cannot write result file " + result_path)
		get_tree().quit(1)
		return
	print("FRAME_TRACE_RESULT " + JSON.stringify(result))
	get_tree().quit(0 if bool(result["harness"]["coherent"]) else 1)


# --- Schedule ---------------------------------------------------------------


## The fixed traffic-free command schedule. Zero steer, no handbrake, no reset
## requests: this is a longitudinal-only trace on the committed 500 m straight,
## so no lateral slip or wall contact is authored. Every tick still receives
## exactly one command; the controls change its value or its count.
func _build_schedule(variant: String) -> Array:
	var commands: Array = []
	var count = SCHEDULE_TICKS if variant != "short" else SCHEDULE_TICKS - 1
	for index in range(count):
		var command = null
		if variant == "drop" and index % 3 == 2:
			command = _command(0.0, 0.0, 0.0, 0.0)
		elif index < THROTTLE_TICKS:
			command = _command(0.0, 1.0, 0.0, 0.0)
		elif index < THROTTLE_TICKS + COAST_TICKS:
			command = _command(0.0, 0.0, 0.0, 0.0)
		else:
			command = _command(0.0, 0.0, 1.0, 0.0)
		if command == null:
			push_error("[frame_trace] schedule command %d is invalid" % index)
			return []
		commands.append(command)
	return commands


func _command(steer: float, throttle: float, brake: float, handbrake: float):
	return DriverCommandScript.create(steer, throttle, brake, handbrake)


func _phase_for_command(index: int, variant: String) -> String:
	if variant == "drop" and index % 3 == 2:
		return "idle_control"
	if index < THROTTLE_TICKS:
		return "full_throttle"
	if index < THROTTLE_TICKS + COAST_TICKS:
		return "coast"
	return "brake_then_reverse"


func _schedule_phases() -> Array:
	return [
		{"phase": "full_throttle", "first_tick": 1, "last_tick": THROTTLE_TICKS},
		{"phase": "coast", "first_tick": THROTTLE_TICKS + 1,
			"last_tick": THROTTLE_TICKS + COAST_TICKS},
		{"phase": "brake_then_reverse", "first_tick": THROTTLE_TICKS + COAST_TICKS + 1,
			"last_tick": SCHEDULE_TICKS},
	]


# --- Result -----------------------------------------------------------------


func _build_result(lab, fps_text: String, variant: String, schedule: Array,
		expected_ticks: int, start_physics_frames: int, start_process_frames: int,
		start_callbacks: int, wall_ms: int, guard: int) -> Dictionary:
	var telemetry: Dictionary = lab.get_telemetry()
	var gearbox_telemetry: Dictionary = lab.get_gearbox_telemetry()
	var wall_telemetry: Dictionary = lab.get_wall_event_telemetry()
	var state = lab.state
	var tick_log: Array = lab.tick_log
	var ticks = int(lab.ticks_committed)
	var steps = int(lab.steps_called)
	var callbacks = int(lab.physics_callbacks) - start_callbacks
	var physics_frames = Engine.get_physics_frames() - start_physics_frames
	var process_frames = Engine.get_process_frames() - start_process_frames
	var wall_s = float(wall_ms) / 1000.0

	var straight_length = _straight_length(lab)
	var half_length = 1.9
	if lab.hull_shape != null:
		half_length = float(lab.hull_shape.size.z) * 0.5
	var end_limit = straight_length - COURSE_END_MARGIN_M - half_length
	var start_limit = -COURSE_START_MARGIN_M + half_length

	var axis = Vector2(0.0, 1.0)
	var right = Vector2(1.0, 0.0)
	var first_heading = 0.0
	if tick_log.size() > 0:
		first_heading = float((tick_log[0] as Dictionary)["heading_rad"])
		axis = Vector2(sin(first_heading), cos(first_heading))
		right = Vector2(cos(first_heading), -sin(first_heading))

	var consecutive_tick = true
	var consecutive_callback = true
	var last_callback = -1
	var heading_constant = true
	var gate_tick = -1
	var lateral_slip_ticks = 0
	var max_station = -INF
	var min_station = INF
	var last_station = 0.0
	var trace: Array = []
	for index in range(tick_log.size()):
		var entry: Dictionary = tick_log[index]
		var tick = int(entry["tick"])
		var callback_index = int(entry["callback_index"])
		if tick != index + 1:
			consecutive_tick = false
		if last_callback >= 0 and callback_index <= last_callback:
			consecutive_callback = false
		last_callback = callback_index

		var position: Vector2 = entry["position_m"]
		var velocity: Vector2 = entry["velocity_m_s"]
		var heading = float(entry["heading_rad"])
		if index > 0 and heading != first_heading:
			heading_constant = false
		var station = (position - lab.start_position_m).dot(axis)
		max_station = maxf(max_station, station)
		min_station = minf(min_station, station)
		last_station = station
		if gate_tick < 0 and station >= GATE_STATION_M:
			gate_tick = tick
		var lateral_speed = velocity.dot(right)
		if absf(lateral_speed) > 1e-9:
			lateral_slip_ticks += 1

		var command = schedule[index]
		trace.append({
			"tick": tick,
			"command_index": tick - 1,
			"expected_phase": _phase_for_command(tick - 1, variant),
			"command": {
				"steer": float(command.steer),
				"throttle": float(command.throttle),
				"brake": float(command.brake),
				"handbrake": float(command.handbrake),
				"reset_requested": bool(command.reset_requested),
				"reset_held": bool(command.reset_held),
			},
			"callback_index": callback_index,
			"status": int(entry["status"]),
			"road_station_m": station,
			"speed_m_s": velocity.length(),
			"forward_speed_m_s": velocity.dot(axis),
			"lateral_speed_m_s": lateral_speed,
			"heading_rad": heading,
			"gear_index": int(entry["gear_index"]),
			"reverse_engaged": bool(entry["reverse_engaged"]),
			"grounded": bool(entry["grounded"]),
			"contact": bool(entry["contact"]),
			"wall_contact": bool(entry["wall_contact"]),
			"substeps": int(entry["substeps"]),
		})

	if trace.is_empty():
		max_station = 0.0
		min_station = 0.0
		last_station = 0.0

	var endpoint = {}
	if state != null:
		endpoint = {
			"position_m": [state.position_m.x, state.position_m.y],
			"road_station_m": float(telemetry["road_station_m"]),
			"trace_station_m": last_station,
			"station_cross_check_delta_m": absf(last_station - float(telemetry["road_station_m"])),
			"velocity_m_s": [state.velocity_m_s.x, state.velocity_m_s.y],
			"speed_m_s": state.speed_m_s(),
			"forward_speed_m_s": state.forward_speed_m_s(),
			"heading_rad": state.heading_rad,
			"heading_deg": rad_to_deg(state.heading_rad),
			"gear_index": int(state.gear_index),
			"reverse_engaged": bool(state.reverse_engaged),
			"grounded": bool(state.grounded),
			"surface_id": String(state.surface_id),
			"drift_active": bool(state.drift_active),
			"drift_slip_deg": state.drift_slip_deg,
		}
	else:
		endpoint = {"absent": true}

	var checks = {
		"not_failed": not bool(lab.failed),
		"completed": bool(lab.completed),
		"halt_is_completion": (not bool(lab.halted)) or bool(lab.completed),
		"expected_tick_count": ticks == expected_ticks,
		"no_dropped_records": int(lab.tick_log_dropped) == 0,
		"tick_log_matches_ticks": tick_log.size() == ticks,
		"one_step_per_committed_tick": steps == ticks,
		"consecutive_tick_indices": consecutive_tick,
		"consecutive_callback_indices": consecutive_callback,
	}
	var coherent = true
	for check in checks.values():
		coherent = coherent and bool(check)

	return {
		"schema": "roadstorm.frame_trace.result.v1",
		"mode": {
			"nominal_fixed_fps": int(fps_text),
			"variant": variant,
			"control": variant != "full",
			"control_note": "" if variant == "full" else (
				"deliberate control: " + (
					"every third command idle" if variant == "drop"
					else "final command withheld; completes one committed tick early"
				)
			),
		},
		"engine": {
			"version": Engine.get_version_info(),
			"backend": str(ProjectSettings.get_setting("physics/3d/physics_engine")),
			"physics_ticks_per_second_pre_set": pre_set_physics_ticks,
			"physics_ticks_per_second_pinned": pinned_physics_ticks,
			"physics_ticks_per_second_observed": Engine.get_physics_ticks_per_second(),
			"max_fps_pre_set": pre_set_max_fps,
			"max_fps_observed": int(Engine.max_fps),
			"max_physics_steps_per_frame": Engine.max_physics_steps_per_frame,
			"fixed_fps_argument": int(fps_text),
		},
		"timing": {
			"wall_ms": wall_ms,
			"wall_s": wall_s,
			"physics_frames": physics_frames,
			"process_frames": process_frames,
			"physics_callbacks": callbacks,
			"observed_physics_frames_per_s": (float(physics_frames) / wall_s) if wall_s > 0.0 else null,
			"observed_process_frames_per_s": (float(process_frames) / wall_s) if wall_s > 0.0 else null,
			"observed_physics_per_process_frame": (float(physics_frames) / process_frames) if process_frames > 0 else null,
			"guard_frames_used": guard,
		},
		"laboratory": {
			"scene": DriveLabScenePath,
			"straight_length_m": straight_length,
			"course_end_limit_station_m": end_limit,
			"course_start_limit_station_m": start_limit,
			"hull_half_length_m": half_length,
			"tuning": _tuning_snapshot(lab.tuning),
			"adapter_config": _config_snapshot(lab.adapter_config),
			"gearbox_config": lab.get_gearbox_config_snapshot(),
			"gearbox_state": lab.get_gearbox_snapshot(),
		},
		"schedule": {
			"logical_ticks": SCHEDULE_TICKS,
			"expected_committed_ticks": expected_ticks,
			"commands_scheduled": schedule.size(),
			"one_command_per_committed_tick": true,
			"traffic_free": true,
			"phases": _schedule_phases(),
		},
		"run": {
			"steps_called": steps,
			"ticks_committed": ticks,
			"physics_callbacks": callbacks,
			"commands_consumed": steps,
			"tick_log_entries": tick_log.size(),
			"tick_log_dropped": int(lab.tick_log_dropped),
			"completed": bool(lab.completed),
			"halted": bool(lab.halted),
			"halt_reason": String(lab.halt_reason),
			"failed": bool(lab.failed),
			"failure_reason": String(lab.failure_reason),
			"tick_indices_consecutive": consecutive_tick,
			"callback_indices_consecutive": consecutive_callback,
			"heading_constant_rad": heading_constant,
			"max_road_station_m": max_station,
			"min_road_station_m": min_station,
			"within_straight_boundaries": (
				max_station <= end_limit + 1e-6 and min_station >= start_limit - 1e-6
			),
			"telemetry": telemetry,
			"gearbox_telemetry": gearbox_telemetry,
			"wall_event_telemetry": wall_telemetry,
		},
		"endpoint": endpoint,
		"counts": {
			"gear_shift_events": int(gearbox_telemetry["shift_event_count"]),
			"gear_shift_events_dropped": int(gearbox_telemetry["shift_events_dropped"]),
			"gearbox_refusals": int(gearbox_telemetry["gearbox_refusals"]),
			"contact_ticks": int(telemetry["contact_ticks"]),
			"wall_contact_ticks": int(telemetry["wall_contact_ticks"]),
			"wall_events_published": int(wall_telemetry["published"]),
			"wall_events_coalesced": int(wall_telemetry["coalesced"]),
			"wall_events_refused": int(wall_telemetry["refused"]),
			"wall_event_missed_witnesses": int(wall_telemetry["missed_witnesses"]),
			"lateral_slip_ticks_proxy": lateral_slip_ticks,
			"max_speed_m_s": float(telemetry["max_speed_m_s"]),
			"total_accepted_motion_m": float(telemetry["total_accepted_motion_m"]),
			"max_substeps": int(telemetry["max_substeps"]),
		},
		"gate": {
			"station_m": GATE_STATION_M,
			"first_committed_tick": gate_tick,
		},
		"tick_trace": trace,
		"harness": {
			"coherent": coherent,
			"checks": checks,
		},
	}


func _straight_length(lab) -> float:
	var manifest: Dictionary = lab.lab_manifest
	for bay in manifest.get("bays", []):
		if String(bay.get("bay_id", "")) == "straight":
			for section in bay.get("sections", []):
				if String(section.get("section_id", "")) == "straight.main":
					return float(section.get("length_m", 0.0))
	return 0.0


func _tuning_snapshot(tuning) -> Dictionary:
	var curve: Array = []
	for point in tuning.acceleration_curve:
		curve.append({
			"speed_m_s": point.speed_m_s,
			"acceleration_m_s2": point.acceleration_m_s2,
		})
	return {
		"acceleration_curve": curve,
		"braking_acceleration_m_s2": tuning.braking_acceleration_m_s2,
		"drag_aerodynamic": tuning.drag_aerodynamic,
		"drag_rolling": tuning.drag_rolling,
		"yaw_gain_grip": tuning.yaw_gain_grip,
		"max_yaw_rate_rad_s": tuning.max_yaw_rate_rad_s,
		"lateral_damping_grip_per_s": tuning.lateral_damping_grip_per_s,
		"reverse_trigger_speed_m_s": tuning.reverse_trigger_speed_m_s,
		"reverse_hold_time_s": tuning.reverse_hold_time_s,
		"reverse_acceleration_m_s2": tuning.reverse_acceleration_m_s2,
		"reverse_top_speed_m_s": tuning.reverse_top_speed_m_s,
	}


func _config_snapshot(config) -> Dictionary:
	return {
		"hull_size_m": [config.hull_size_m.x, config.hull_size_m.y, config.hull_size_m.z],
		"substep_max_length_m": config.substep_max_length_m,
		"max_substeps": config.max_substeps,
		"sweep_margin_m": config.sweep_margin_m,
		"commit_safe_margin_m": config.commit_safe_margin_m,
		"envelope_epsilon_m": config.envelope_epsilon_m,
		"contact_stop_epsilon_m": config.contact_stop_epsilon_m,
		"wall_normal_max_up_alignment": config.wall_normal_max_up_alignment,
		"wall_restitution": config.wall_restitution,
		"wall_tangential_keep": config.wall_tangential_keep,
	}


func _env_valid(fps_text: String, variant: String, result_path: String) -> bool:
	var fps = int(fps_text) if fps_text.is_valid_int() else -1
	if not (fps in [30, 60, 120]):
		return false
	if not (variant in ALLOWED_VARIANTS):
		return false
	if result_path.is_empty() or not result_path.is_absolute_path():
		return false
	return true


func _write_result(path: String, result: Dictionary) -> bool:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[frame_trace] cannot open result file %s (error %d)"
			% [path, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	return true


func _write_error(path: String, fps_text: String, variant: String, reason: String) -> void:
	var nominal = null
	if fps_text in ["30", "60", "120"]:
		nominal = int(fps_text)
	var result = {
		"schema": "roadstorm.frame_trace.result.v1",
		"mode": {"nominal_fixed_fps": nominal, "variant": variant},
		"error": reason,
		"harness": {"coherent": false},
	}
	if not path.is_empty():
		_write_result(path, result)
	printerr("[frame_trace] " + reason)
