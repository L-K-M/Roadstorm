extends SceneTree
## Headless one-slot control normalizer validation entry point.
##
## Run from an isolated project copy after importing resources:
##   godot --headless --fixed-fps 60 --path <project> \
##       --script res://tools/input_lab/validate_one_slot_controls.gd
##
## Exercises `src/input/one_slot_controls.gd`: provisional defaults,
## atomic configure, analog deadzone boundaries and sensitivity, digital
## ramp rate/dt/reversal/simultaneous buttons, digital-vs-analog precedence
## and release decay, rising-edge reset and repress, nonfinite/negative-dt
## rejection without stored-state mutation, range clamping, fresh-command
## isolation, instance independence and every lifecycle clear trigger.
##
## `--expect-failure` deliberately records a failure so the nonzero exit path
## is observable. The bounded wrapper tools/input_lab/run_validation.sh runs
## the pass case and this proof.
##
## Scope: pure headless component checks only. No device enumeration, no
## keyboard/gamepad event routing, no M3 ownership/remap/save, no assists,
## reverse rules or integrated race wiring. No M1/M3 acceptance claim.

const CONTROLS_SCRIPT_PATH := "res://src/input/one_slot_controls.gd"
const ControlsScript := preload("res://src/input/one_slot_controls.gd")

const EXPECTED_MAJOR := 4
const EXPECTED_MINOR := 7
const EXPECTED_PATCH := 2
const EXPECTED_STATUS := "stable"
const EXPECTED_BUILD := "official"
const EXPECTED_COMMIT_PREFIX := "ed1daf0bf"

## Provisional authored defaults mirrored here as an independent oracle. They
## are not validated product constants and may change during tuning.
const EXPECTED_DEFAULT_DEADZONE := 0.15
const EXPECTED_DEFAULT_SENSITIVITY := 1.0
const EXPECTED_DEFAULT_RAMP_PER_SECOND := 4.0
const DEFAULT_DT := 1.0 / 60.0

## Expected normalized analog magnitudes derived from the documented formula.
const ANALOG_OUTSIDE_EXPECTED := (0.2 - 0.15) / (1.0 - 0.15)
const ANALOG_SENSITIVITY_EXPECTED := (
	(0.2 - 0.15) / (1.0 - 0.15) * 2.0
)
const ANALOG_PASSBACK_EXPECTED := (0.7 - 0.15) / (1.0 - 0.15)

const TOLERANCE := 1e-6

var _checks := 0
var _failures: Array[String] = []
var _measured: Dictionary = {}
var _finished := false


func _initialize() -> void:
	print("[input-lab] engine ", Engine.get_version_info()["string"])
	_check_engine()

	if not ResourceLoader.exists(CONTROLS_SCRIPT_PATH):
		_record_failure("resource.exists", "missing %s" % CONTROLS_SCRIPT_PATH)
		_finish()
		return

	var controls: OneSlotControls = ControlsScript.new()
	_run_checks(controls)
	_finish()


func _run_checks(controls: OneSlotControls) -> void:
	_check_structure(controls)
	_check_configure(controls)
	_check_analog_deadzone_and_sensitivity(controls)
	_check_digital_ramp()
	_check_digital_analog_precedence()
	_check_reset_edges()
	_check_clamping()
	_check_invalid_atomicity()
	_check_lifecycle_clear()
	_check_fresh_commands_and_instances()

	if _has_user_flag("--expect-failure"):
		_check(
			false,
			"expect_failure.deliberate",
			"--expect-failure requested: proving a failing check exits nonzero"
		)


# --- Structure and configuration -------------------------------------------


func _check_structure(controls: OneSlotControls) -> void:
	_check(controls != null, "structure.instance_created", str(controls))
	var as_object: Object = controls
	_check(
		as_object is RefCounted and not (as_object is Node),
		"structure.refcounted_not_node",
		str(controls)
	)
	_check(
		controls.get_script() == ControlsScript,
		"structure.script_attached",
		str(controls.get_script())
	)
	_check(
		_near(controls.get_steer_deadzone(), EXPECTED_DEFAULT_DEADZONE),
		"structure.default_deadzone",
		str(controls.get_steer_deadzone())
	)
	_check(
		_near(controls.get_steer_sensitivity(), EXPECTED_DEFAULT_SENSITIVITY),
		"structure.default_sensitivity",
		str(controls.get_steer_sensitivity())
	)
	_check(
		_near(controls.get_digital_ramp_per_second(), EXPECTED_DEFAULT_RAMP_PER_SECOND),
		"structure.default_ramp_rate",
		str(controls.get_digital_ramp_per_second())
	)
	_measured["defaults"] = {
		"deadzone": controls.get_steer_deadzone(),
		"sensitivity": controls.get_steer_sensitivity(),
		"ramp_per_second": controls.get_digital_ramp_per_second(),
	}


func _check_configure(controls: OneSlotControls) -> void:
	var probe := OneSlotControls.new()
	_check(probe.configure(0.3, 2.0, 6.0), "configure.valid_accepted", "")
	_check(_near(probe.get_steer_deadzone(), 0.3), "configure.deadzone_applied", str(probe.get_steer_deadzone()))
	_check(_near(probe.get_steer_sensitivity(), 2.0), "configure.sensitivity_applied", str(probe.get_steer_sensitivity()))
	_check(_near(probe.get_digital_ramp_per_second(), 6.0), "configure.ramp_applied", str(probe.get_digital_ramp_per_second()))

	_check(not probe.configure(1.0, 2.0, 6.0), "configure.deadzone_one_rejected", "")
	_check(not probe.configure(-0.1, 2.0, 6.0), "configure.negative_deadzone_rejected", "")
	_check(not probe.configure(NAN, 2.0, 6.0), "configure.nan_deadzone_rejected", "")
	_check(not probe.configure(INF, 2.0, 6.0), "configure.inf_deadzone_rejected", "")
	_check(not probe.configure(0.3, 0.0, 6.0), "configure.zero_sensitivity_rejected", "")
	_check(not probe.configure(0.3, -1.0, 6.0), "configure.negative_sensitivity_rejected", "")
	_check(not probe.configure(0.3, NAN, 6.0), "configure.nan_sensitivity_rejected", "")
	_check(not probe.configure(0.3, 2.0, 0.0), "configure.zero_ramp_rejected", "")
	_check(not probe.configure(0.3, 2.0, -2.0), "configure.negative_ramp_rejected", "")
	_check(not probe.configure(0.3, 2.0, INF), "configure.inf_ramp_rejected", "")

	_check(_near(probe.get_steer_deadzone(), 0.3), "configure.atomic_deadzone_kept", str(probe.get_steer_deadzone()))
	_check(_near(probe.get_steer_sensitivity(), 2.0), "configure.atomic_sensitivity_kept", str(probe.get_steer_sensitivity()))
	_check(_near(probe.get_digital_ramp_per_second(), 6.0), "configure.atomic_ramp_kept", str(probe.get_digital_ramp_per_second()))


# --- Analog steering --------------------------------------------------------


func _check_analog_deadzone_and_sensitivity(controls: OneSlotControls) -> void:
	var command := _sample(controls, 0.0)
	_check(command != null and _near(command.steer, 0.0), "analog.zero_is_neutral", str(_steer_of(command)))

	command = _sample(controls, EXPECTED_DEFAULT_DEADZONE)
	_check(command != null and _near(command.steer, 0.0), "analog.exact_deadzone_is_neutral", str(_steer_of(command)))

	command = _sample(controls, EXPECTED_DEFAULT_DEADZONE - 0.01)
	_check(command != null and _near(command.steer, 0.0), "analog.inside_deadzone_is_neutral", str(_steer_of(command)))

	command = _sample(controls, 0.2)
	_check(
		command != null and _near(command.steer, ANALOG_OUTSIDE_EXPECTED),
		"analog.just_outside_deadzone_formula",
		"%s vs %s" % [_steer_of(command), ANALOG_OUTSIDE_EXPECTED]
	)

	command = _sample(controls, -0.2)
	_check(
		command != null and _near(command.steer, -ANALOG_OUTSIDE_EXPECTED),
		"analog.negative_mirror",
		"%s vs %s" % [_steer_of(command), -ANALOG_OUTSIDE_EXPECTED]
	)

	command = _sample(controls, 1.0)
	_check(command != null and _near(command.steer, 1.0), "analog.full_right", str(_steer_of(command)))
	command = _sample(controls, -1.0)
	_check(command != null and _near(command.steer, -1.0), "analog.full_left", str(_steer_of(command)))

	command = _sample(controls, 1.5)
	_check(command != null and _near(command.steer, 1.0), "analog.above_range_clamped", str(_steer_of(command)))
	command = _sample(controls, -1.5)
	_check(command != null and _near(command.steer, -1.0), "analog.below_range_clamped", str(_steer_of(command)))

	var sensitive := OneSlotControls.new()
	sensitive.configure(0.15, 2.0, 4.0)
	command = _sample(sensitive, 0.2)
	_check(
		command != null and _near(command.steer, ANALOG_SENSITIVITY_EXPECTED),
		"analog.sensitivity_multiplier",
		"%s vs %s" % [_steer_of(command), ANALOG_SENSITIVITY_EXPECTED]
	)
	command = _sample(sensitive, 0.6)
	_check(
		command != null and _near(command.steer, 1.0),
		"analog.sensitivity_clamps_to_full_lock",
		str(_steer_of(command))
	)

	var linear := OneSlotControls.new()
	linear.configure(0.0, 1.0, 4.0)
	command = _sample(linear, 0.25)
	_check(command != null and _near(command.steer, 0.25), "analog.zero_deadzone_linear", str(_steer_of(command)))

	var wide := OneSlotControls.new()
	wide.configure(0.5, 1.0, 4.0)
	command = _sample(wide, 0.5)
	_check(command != null and _near(command.steer, 0.0), "analog.custom_deadzone_boundary", str(_steer_of(command)))
	command = _sample(wide, 0.5002)
	_check(
		command != null and _near(command.steer, 0.0004, 1e-5),
		"analog.custom_deadzone_outside",
		str(_steer_of(command))
	)


# --- Digital ramp -----------------------------------------------------------


func _check_digital_ramp() -> void:
	var controls := OneSlotControls.new()

	var first := _sample(controls, 0.0, 0.0, 0.0, 0.0, false, DEFAULT_DT, false, true)
	_check(
		first != null and _near(first.steer, 4.0 * DEFAULT_DT),
		"digital.first_tick_uses_dt",
		"%s vs %s" % [_steer_of(first), 4.0 * DEFAULT_DT]
	)

	var last := first
	for index in 20:
		last = _sample(controls, 0.0, 0.0, 0.0, 0.0, false, DEFAULT_DT, false, true)
	_check(last != null and _near(last.steer, 1.0), "digital.ramp_saturates_at_full_lock", str(_steer_of(last)))

	var zero_dt := _sample(controls, 0.0, 0.0, 0.0, 0.0, false, 0.0, false, true)
	_check(zero_dt != null and _near(zero_dt.steer, 1.0), "digital.dt_zero_adds_no_ramp", str(_steer_of(zero_dt)))

	var big_dt := OneSlotControls.new()
	var jump := _sample(big_dt, 0.0, 0.0, 0.0, 0.0, false, 1.0, false, true)
	_check(jump != null and _near(jump.steer, 1.0), "digital.large_dt_saturates_in_one_tick", str(_steer_of(jump)))

	var reverse := OneSlotControls.new()
	_sample(reverse, 0.0, 0.0, 0.0, 0.0, false, 1.0, false, true)
	var halfway := _sample(reverse, 0.0, 0.0, 0.0, 0.0, false, 0.25, true, false)
	_check(halfway != null and _near(halfway.steer, 0.0), "digital.reversal_passes_center_smoothly", str(_steer_of(halfway)))
	var full_left := _sample(reverse, 0.0, 0.0, 0.0, 0.0, false, 0.25, true, false)
	_check(full_left != null and _near(full_left.steer, -1.0), "digital.reversal_reaches_full_left", str(_steer_of(full_left)))

	var both := OneSlotControls.new()
	_sample(both, 0.0, 0.0, 0.0, 0.0, false, 1.0, false, true)
	var canceled := _sample(both, 0.0, 0.0, 0.0, 0.0, false, 0.25, true, true)
	_check(canceled != null and _near(canceled.steer, 0.0), "digital.simultaneous_cancels_to_center", str(_steer_of(canceled)))
	var held := _sample(both, 0.0, 0.0, 0.0, 0.0, false, 0.25, true, true)
	_check(held != null and _near(held.steer, 0.0), "digital.simultaneous_held_stays_center", str(_steer_of(held)))

	var left := OneSlotControls.new()
	var left_command := _sample(left, 0.0, 0.0, 0.0, 0.0, false, 1.0, true, false)
	_check(left_command != null and _near(left_command.steer, -1.0), "digital.left_full_lock", str(_steer_of(left_command)))


# --- Digital versus analog selection ----------------------------------------


func _check_digital_analog_precedence() -> void:
	var mixed := OneSlotControls.new()
	var pressed := _sample(mixed, 0.9, 0.0, 0.0, 0.0, false, DEFAULT_DT, false, true)
	_check(
		pressed != null and _near(pressed.steer, 4.0 * DEFAULT_DT),
		"precedence.digital_overrides_deflected_stick",
		"%s vs %s" % [_steer_of(pressed), 4.0 * DEFAULT_DT]
	)

	var released := _sample(mixed, 0.9, 0.0, 0.0, 0.0, false, 1.0, false, true)
	_check(released != null and _near(released.steer, 1.0), "precedence.digital_holds_until_released", str(_steer_of(released)))

	var decayed := _sample(mixed, 0.7, 0.0, 0.0, 0.0, false, 0.125, false, false)
	_check(decayed != null and _near(decayed.steer, 0.5), "precedence.release_decays_from_stored_value", str(_steer_of(decayed)))
	var analog_back := _sample(mixed, 0.7, 0.0, 0.0, 0.0, false, 0.125, false, false)
	_check(
		analog_back != null and _near(analog_back.steer, ANALOG_PASSBACK_EXPECTED),
		"precedence.analog_resumes_after_ramp_reaches_zero",
		"%s vs %s" % [_steer_of(analog_back), ANALOG_PASSBACK_EXPECTED]
	)

	var cancel_mix := OneSlotControls.new()
	_sample(cancel_mix, 0.0, 0.0, 0.0, 0.0, false, 1.0, false, true)
	var cancel_decay := _sample(cancel_mix, 0.9, 0.0, 0.0, 0.0, false, 0.125, true, true)
	_check(cancel_decay != null and _near(cancel_decay.steer, 0.5), "precedence.simultaneous_decay_ignores_analog", str(_steer_of(cancel_decay)))


# --- Reset edges ------------------------------------------------------------


func _check_reset_edges() -> void:
	var controls := OneSlotControls.new()
	var command := _sample(controls, 0.0, 0.0, 0.0, 0.0, false, DEFAULT_DT)
	_check(command != null and not command.reset_requested, "reset.unpressed_is_false", str(_reset_of(command)))

	command = _sample(controls, 0.0, 0.0, 0.0, 0.0, true, DEFAULT_DT)
	_check(command != null and command.reset_requested, "reset.rising_edge_true", str(_reset_of(command)))

	command = _sample(controls, 0.0, 0.0, 0.0, 0.0, true, DEFAULT_DT)
	_check(command != null and not command.reset_requested, "reset.held_does_not_repeat", str(_reset_of(command)))

	command = _sample(controls, 0.0, 0.0, 0.0, 0.0, false, DEFAULT_DT)
	_check(command != null and not command.reset_requested, "reset.release_is_false", str(_reset_of(command)))

	command = _sample(controls, 0.0, 0.0, 0.0, 0.0, true, DEFAULT_DT)
	_check(command != null and command.reset_requested, "reset.repress_after_release_true", str(_reset_of(command)))

	var with_digital := OneSlotControls.new()
	_sample(with_digital, 0.0, 0.0, 0.0, 0.0, false, 0.5, false, true)
	command = _sample(with_digital, 0.0, 0.0, 0.0, 0.0, true, 0.5, false, true)
	_check(
		command != null and command.reset_requested and _near(command.steer, 1.0),
		"reset.edge_alongside_digital_ramp",
		"reset=%s steer=%s" % [_reset_of(command), _steer_of(command)]
	)


# --- Range clamping ---------------------------------------------------------


func _check_clamping() -> void:
	var controls := OneSlotControls.new()
	var command := _sample(controls, 2.0, 2.0, -1.0, 5.0, false, DEFAULT_DT)
	_check(
		command != null
		and _near(command.steer, 1.0)
		and _near(command.throttle, 1.0)
		and _near(command.brake, 0.0)
		and _near(command.handbrake, 1.0),
		"clamp.out_of_range_values",
		str(command)
	)
	_check(command != null and command.is_normalized(), "clamp.command_is_normalized", str(command))

	command = _sample(controls, -2.0, -1.0, 0.5, -0.5, false, DEFAULT_DT)
	_check(
		command != null
		and _near(command.steer, -1.0)
		and _near(command.throttle, 0.0)
		and _near(command.brake, 0.5)
		and _near(command.handbrake, 0.0),
		"clamp.negative_and_high_values",
		str(command)
	)

	command = _sample(controls, 1.0, 1.0, 0.0, 0.5, true, DEFAULT_DT)
	_check(
		command != null
		and _near(command.steer, 1.0)
		and _near(command.throttle, 1.0)
		and _near(command.brake, 0.0)
		and _near(command.handbrake, 0.5)
		and command.reset_requested,
		"clamp.in_range_passthrough",
		str(command)
	)


# --- Invalid input atomicity ------------------------------------------------


func _check_invalid_atomicity() -> void:
	var controls := OneSlotControls.new()
	for index in 3:
		_sample(controls, 0.0, 0.0, 0.0, 0.0, false, DEFAULT_DT, false, true)

	var reference := OneSlotControls.new()
	var reference_command: DriverCommand = null
	for index in 4:
		reference_command = _sample(reference, 0.0, 0.0, 0.0, 0.0, false, DEFAULT_DT, false, true)

	var invalid := _sample(controls, NAN, 0.0, 0.0, 0.0, false, DEFAULT_DT, false, true)
	_check(invalid == null, "invalid.nan_steer_returns_null", str(invalid))
	var resumed := _sample(controls, 0.0, 0.0, 0.0, 0.0, false, DEFAULT_DT, false, true)
	_check(
		resumed != null and reference_command != null and _near(resumed.steer, reference_command.steer),
		"invalid.stored_ramp_unaffected_by_nan",
		"%s vs %s" % [_steer_of(resumed), _steer_of(reference_command)]
	)

	var variants := [
		{"steer": 0.0, "throttle": INF, "brake": 0.0, "handbrake": 0.0},
		{"steer": 0.0, "throttle": 0.0, "brake": NAN, "handbrake": 0.0},
		{"steer": 0.0, "throttle": 0.0, "brake": 0.0, "handbrake": INF},
		{"steer": NAN, "throttle": NAN, "brake": NAN, "handbrake": NAN},
	]
	for index in variants.size():
		var probe := OneSlotControls.new()
		var rejected := _sample(
			probe,
			variants[index]["steer"],
			variants[index]["throttle"],
			variants[index]["brake"],
			variants[index]["handbrake"],
			false,
			DEFAULT_DT
		)
		_check(rejected == null, "invalid.nonfinite_variant_%d" % index, str(rejected))

	var dt_probe := OneSlotControls.new()
	_check(_sample(dt_probe, 0.0, 0.0, 0.0, 0.0, false, NAN) == null, "invalid.nan_dt_returns_null", "")
	_check(_sample(dt_probe, 0.0, 0.0, 0.0, 0.0, false, INF) == null, "invalid.inf_dt_returns_null", "")
	_check(_sample(dt_probe, 0.0, 0.0, 0.0, 0.0, false, -0.001) == null, "invalid.negative_dt_returns_null", "")

	var reset_probe := OneSlotControls.new()
	_sample(reset_probe, 0.0, 0.0, 0.0, 0.0, false, DEFAULT_DT)
	var reset_invalid := _sample(reset_probe, NAN, 0.0, 0.0, 0.0, true, DEFAULT_DT)
	_check(reset_invalid == null, "invalid.reset_nonfinite_returns_null", "")
	var reset_resumed := _sample(reset_probe, 0.0, 0.0, 0.0, 0.0, true, DEFAULT_DT)
	_check(
		reset_resumed != null and reset_resumed.reset_requested,
		"invalid.reset_edge_survives_rejection",
		str(_reset_of(reset_resumed))
	)

	var held_probe := OneSlotControls.new()
	_sample(held_probe, 0.0, 0.0, 0.0, 0.0, true, DEFAULT_DT)
	var held_invalid := _sample(held_probe, INF, 0.0, 0.0, 0.0, false, DEFAULT_DT)
	_check(held_invalid == null, "invalid.held_reset_rejection_returns_null", "")
	var held_resumed := _sample(held_probe, 0.0, 0.0, 0.0, 0.0, false, DEFAULT_DT)
	_check(
		held_resumed != null and not held_resumed.reset_requested,
		"invalid.held_reset_level_survives_rejection",
		str(_reset_of(held_resumed))
	)


# --- Lifecycle clear --------------------------------------------------------


func _check_lifecycle_clear() -> void:
	var controls := OneSlotControls.new()
	_sample(controls, 0.0, 0.0, 0.0, 0.0, false, 1.0, false, true)
	controls.clear_lifecycle_state()
	var restarted := _sample(controls, 0.0, 0.0, 0.0, 0.0, false, 0.125, false, true)
	_check(
		restarted != null and _near(restarted.steer, 0.5),
		"lifecycle.clear_resets_digital_ramp",
		str(_steer_of(restarted))
	)

	var reset_controls := OneSlotControls.new()
	_sample(reset_controls, 0.0, 0.0, 0.0, 0.0, true, DEFAULT_DT)
	reset_controls.clear_lifecycle_state()
	var after_hold := _sample(reset_controls, 0.0, 0.0, 0.0, 0.0, true, DEFAULT_DT)
	_check(
		after_hold != null and not after_hold.reset_requested,
		"lifecycle.clear_forces_fresh_reset_press",
		str(_reset_of(after_hold))
	)
	reset_controls.clear_lifecycle_state()
	var double_cleared := _sample(reset_controls, 0.0, 0.0, 0.0, 0.0, true, DEFAULT_DT)
	_check(
		double_cleared != null and not double_cleared.reset_requested,
		"lifecycle.repeat_clear_keeps_fresh_press_requirement",
		str(_reset_of(double_cleared))
	)
	_sample(reset_controls, 0.0, 0.0, 0.0, 0.0, false, DEFAULT_DT)
	var repress := _sample(reset_controls, 0.0, 0.0, 0.0, 0.0, true, DEFAULT_DT)
	_check(repress != null and repress.reset_requested, "lifecycle.repress_after_clear_true", str(_reset_of(repress)))

	var idle := OneSlotControls.new()
	_sample(idle, 0.0, 0.0, 0.0, 0.0, false, DEFAULT_DT)
	idle.clear_lifecycle_state()
	var new_press := _sample(idle, 0.0, 0.0, 0.0, 0.0, true, DEFAULT_DT)
	_check(
		new_press != null and new_press.reset_requested,
		"lifecycle.idle_clear_keeps_new_press_edge",
		str(_reset_of(new_press))
	)

	var configured := OneSlotControls.new()
	configured.configure(0.25, 1.5, 6.0)
	configured.clear_lifecycle_state()
	_check(
		_near(configured.get_steer_deadzone(), 0.25)
		and _near(configured.get_steer_sensitivity(), 1.5)
		and _near(configured.get_digital_ramp_per_second(), 6.0),
		"lifecycle.clear_preserves_tuning",
		"%s/%s/%s" % [
			configured.get_steer_deadzone(),
			configured.get_steer_sensitivity(),
			configured.get_digital_ramp_per_second(),
		]
	)

	var neutral_source := OneSlotControls.new()
	_sample(neutral_source, 0.0, 1.0, 1.0, 1.0, false, 1.0, false, true)
	_sample(neutral_source, 0.0, 1.0, 1.0, 1.0, true, DEFAULT_DT)
	neutral_source.clear_lifecycle_state()
	var neutral := _sample(neutral_source, 0.0, 0.0, 0.0, 0.0, false, DEFAULT_DT)
	_check(
		neutral != null
		and _near(neutral.steer, 0.0)
		and _near(neutral.throttle, 0.0)
		and _near(neutral.brake, 0.0)
		and _near(neutral.handbrake, 0.0)
		and not neutral.reset_requested,
		"lifecycle.cleared_next_tick_is_neutral",
		str(neutral)
	)


# --- Fresh commands and instance independence -------------------------------


func _check_fresh_commands_and_instances() -> void:
	var controls := OneSlotControls.new()
	var first := _sample(controls, 0.0, 0.5, 0.0, 0.0, false, DEFAULT_DT)
	var second := _sample(controls, 0.0, 0.7, 0.0, 0.0, false, DEFAULT_DT)
	_check(first != null and second != null and first != second, "fresh.distinct_command_per_tick", "")
	if first != null and second != null:
		first.throttle = 123.0
		_check(_near(second.throttle, 0.7), "fresh.command_mutation_isolated", str(second.throttle))

	var left_instance := OneSlotControls.new()
	var right_instance := OneSlotControls.new()
	_sample(left_instance, 0.0, 0.0, 0.0, 0.0, false, 1.0, false, true)
	var right_command := _sample(right_instance, 0.0, 0.0, 0.0, 0.0, false, 0.125, false, true)
	_check(
		right_command != null and _near(right_command.steer, 0.5),
		"fresh.instances_do_not_share_state",
		str(_steer_of(right_command))
	)


# --- Helpers ----------------------------------------------------------------


func _sample(
	p_controls: OneSlotControls,
	p_steer := 0.0,
	p_throttle := 0.0,
	p_brake := 0.0,
	p_handbrake := 0.0,
	p_reset := false,
	p_dt := DEFAULT_DT,
	p_left := false,
	p_right := false
) -> DriverCommand:
	return p_controls.sample(
		p_steer, p_throttle, p_brake, p_handbrake, p_reset, p_dt, p_left, p_right
	)


func _steer_of(command: DriverCommand) -> float:
	return command.steer if command != null else NAN


func _reset_of(command: DriverCommand) -> bool:
	return command.reset_requested if command != null else false


func _near(a: float, b: float, tolerance: float = TOLERANCE) -> bool:
	return absf(a - b) <= tolerance


func _has_user_flag(flag: String) -> bool:
	return flag in OS.get_cmdline_user_args()


func _check(ok: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if not ok:
		if detail.is_empty():
			_failures.append(label)
		else:
			_failures.append("%s (%s)" % [label, detail])


func _record_failure(label: String, detail: String) -> void:
	_check(false, label, detail)


func _check_engine() -> void:
	var version: Dictionary = Engine.get_version_info()
	_check(version["major"] == EXPECTED_MAJOR, "engine.major", str(version["major"]))
	_check(version["minor"] == EXPECTED_MINOR, "engine.minor", str(version["minor"]))
	_check(version["patch"] == EXPECTED_PATCH, "engine.patch", str(version["patch"]))
	_check(version["status"] == EXPECTED_STATUS, "engine.status", str(version["status"]))
	_check(version["build"] == EXPECTED_BUILD, "engine.build", str(version["build"]))
	_check(
		String(version["hash"]).begins_with(EXPECTED_COMMIT_PREFIX),
		"engine.commit",
		str(version["hash"])
	)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	var report := {
		"schema": "roadstorm.input_lab.validation.v1",
		"component": CONTROLS_SCRIPT_PATH,
		"backend": str(ProjectSettings.get_setting("physics/3d/physics_engine")),
		"engine_version": Engine.get_version_info(),
		"checks_total": _checks,
		"checks_failed": _failures.size(),
		"failures": _failures,
		"measured": _measured,
		"limitations": [
			"Pure headless component checks only; no keyboard/gamepad event routing, device enumeration or physical controller verification.",
			"No M3 slot ownership, joining, remapping, saved presets, assists, reverse/brake rules, gears or camera/menu actions are implemented or tested.",
			"All deadzone, sensitivity and ramp defaults are provisional starting values, not tuned product constants.",
			"The deliberate-failure case proves only that a failing check exits nonzero; it does not prove the engine harness or hardware path.",
			"No M1/M3 acceptance claim; the coordinator independently verifies and integrates the component.",
		],
	}
	print("INPUT_LAB_RESULT ", JSON.stringify(report))
	print("CHECKS_TOTAL=", _checks, " CHECKS_FAILED=", _failures.size())
	quit(1 if _failures.size() > 0 else 0)
