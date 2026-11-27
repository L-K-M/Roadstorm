extends SceneTree
## Separate atomic-refusal fixture for bad motor-body configurations.
##
## Run from an isolated project copy:
##   godot --headless --fixed-fps 60 --path <project> \
##       --script res://tools/drive_lab/bad_config_fixture.gd
##
## Proves that an invalid `MotorBodyAdapter.Config` or a hull/config mismatch
## refuses through the real adapter without touching the body or the caller
## state, and that the drive laboratory itself refuses to run on such a config.
## Exit code 0 means every refusal was atomic; 1 means a check failed.


func _initialize() -> void:
	var driver := BadConfigDriver.new()
	driver.name = "DriveLabBadConfigFixture"
	root.add_child.call_deferred(driver)


class BadConfigDriver extends Node:
	const ChecksScript := preload("res://tools/drive_lab/drive_lab_checks.gd")
	const AdapterScript := preload("res://src/simulation/motor_body_adapter.gd")
	const CarStateScript := preload("res://src/simulation/car_state.gd")
	const DriveLabScenePath := "res://scenes/laboratory/drive_lab.tscn"
	const SETTLE_FRAMES := 10

	var d := ChecksScript.new()

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_run()

	func _run() -> void:
		var packed: PackedScene = load(DriveLabScenePath)
		d.check(packed != null, "scene.load")
		if packed == null:
			_finish()
			return
		var lab = packed.instantiate()
		var invalid := d.make_config()
		invalid.max_substeps = 0
		var configured: bool = lab.configure(d.make_tuning(), invalid, [])
		d.check(not configured, "configure.invalid_config_refused")
		d.check(lab.failed, "lab.failed_on_invalid_config")
		get_tree().root.add_child(lab)
		await _frames(SETTLE_FRAMES)
		d.check(int(lab.steps_called) == 0, "lab.made_no_adapter_calls")
		d.check(lab.body != null, "lab.body_present_for_direct_probe")
		if lab.body == null or lab.hull_shape == null:
			_finish()
			return

		var pose: Transform3D = lab.body.global_transform
		var state = CarStateScript.new()
		state.position_m = lab.state.position_m
		state.heading_rad = lab.state.heading_rad
		var command := d.idle_command()

		var variants: Array = []
		var zero_steps := d.make_config()
		zero_steps.max_substeps = 0
		variants.append({"name": "zero_max_substeps", "config": zero_steps})
		var huge_step := d.make_config()
		huge_step.substep_max_length_m = AdapterScript.ABSOLUTE_MAX_SUBSTEP_LENGTH_M + 0.5
		variants.append({"name": "substep_above_absolute_cap", "config": huge_step})
		var large_epsilon := d.make_config()
		large_epsilon.envelope_epsilon_m = 0.01
		variants.append({"name": "envelope_epsilon_too_large", "config": large_epsilon})
		var negative_margin := d.make_config()
		negative_margin.sweep_margin_m = -0.1
		variants.append({"name": "negative_sweep_margin", "config": negative_margin})
		var nan_hull := d.make_config()
		nan_hull.hull_size_m = Vector3(NAN, 1.0, 3.8)
		variants.append({"name": "nonfinite_hull", "config": nan_hull})
		var mismatched := d.make_config()
		mismatched.hull_size_m = Vector3(1.79, 1.0, 3.8)
		variants.append({"name": "hull_config_mismatch", "config": mismatched})

		for variant in variants:
			var label: String = variant["name"]
			var bad_config = variant["config"]
			var state_before := d.snapshot_state(state)
			var command_before := d.snapshot_command(command)
			var result = AdapterScript.step(
				lab.body, lab.hull_shape, state, command, d.make_tuning(), bad_config,
				AdapterScript.DT
			)
			d.check(
				int(result.status) == int(AdapterScript.Status.REJECTED_INVALID_INPUT),
				label + ".rejected_invalid_input"
			)
			d.check(str(result.rejection_reason) != "", label + ".reason_reported")
			d.check(result.committed_state == null, label + ".no_committed_state_leaked")
			d.check(
				lab.body.global_transform == pose,
				label + ".body_transform_unchanged"
			)
			d.check_state_unchanged(state, state_before, label)
			d.check_command_unchanged(command, command_before, label)

		# Positive control: the same body accepts a valid config and moves.
		var control_state := CarStateScript.new()
		control_state.position_m = lab.state.position_m
		control_state.heading_rad = lab.state.heading_rad
		var control = AdapterScript.step(
			lab.body, lab.hull_shape, control_state, d.throttle_command(1.0),
			d.make_tuning(), d.make_config(), AdapterScript.DT
		)
		d.check(
			int(control.status) == int(AdapterScript.Status.COMMITTED),
			"control.valid_config_commits"
		)
		if control.committed_state != null:
			d.check(control.committed_state.is_finite(), "control.finite_state")
			d.check(
				lab.body.global_transform.origin.z < pose.origin.z,
				"control.body_moved_forward"
			)
			d.check(
				not lab.body.global_transform.origin.is_equal_approx(pose.origin),
				"control.pose_changed"
			)

		_finish()

	func _frames(count: int) -> void:
		for _index in range(count):
			await get_tree().physics_frame

	func _finish() -> void:
		var report := {
			"schema": "roadstorm.drive_lab.bad_config.v1",
			"checks": d.checks,
			"failures": d.failures.duplicate(),
			"pass": d.failures.is_empty(),
		}
		print("BAD_CONFIG_RESULT ", JSON.stringify(report))
		print("CHECKS_TOTAL=", d.checks, " CHECKS_FAILED=", d.failures.size())
		get_tree().quit(0 if d.failures.is_empty() else 1)
