extends SceneTree
## Headless one-slot control normalizer validation entry point.
##
## Run from an isolated project copy after importing resources:
##   godot --headless --fixed-fps 60 --path <project> \
##       --script res://tools/input_lab/validate_one_slot_controls.gd
##
## Exercises `src/input/one_slot_controls.gd` and its M1.1 seam partners:
## provisional defaults, atomic configure, analog deadzone boundaries and
## sensitivity, digital ramp rate/dt/reversal/simultaneous buttons,
## digital-vs-analog precedence and release decay, rising-edge reset and
## repress, the new normalized `reset_held` level and its lifecycle
## suppression, nonfinite/negative-dt rejection without stored-state
## mutation, range clamping, fresh-command isolation, instance independence
## and every lifecycle clear trigger.
##
## It also exercises the pure `src/input/reset_hold_gate.gd`: the exact
## one-second boundary, sustained hold without repeat, early release clearing
## progress, release-and-repress rearming, zero-dt no-advance, atomic refusal
## of malformed dt/commands, lifecycle clear cancellation, focus-loss
## suppression through OneSlotControls and deterministic replay.
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
const DRIVER_COMMAND_SCRIPT_PATH := "res://src/simulation/driver_command.gd"
const DriverCommandScript := preload("res://src/simulation/driver_command.gd")
const RESET_GATE_SCRIPT_PATH := "res://src/input/reset_hold_gate.gd"
const ResetHoldGateScript := preload("res://src/input/reset_hold_gate.gd")

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
	_check_driver_command_reset_fields()
	_check_reset_held_signal()
	_check_clamping()
	_check_invalid_atomicity()
	_check_lifecycle_clear()
	_check_fresh_commands_and_instances()
	_check_reset_hold_gate_structure()
	_check_reset_hold_gate_boundary()
	_check_reset_hold_gate_early_release_and_rearm()
	_check_reset_hold_gate_zero_dt()
	_check_reset_hold_gate_invalid_atomicity()
	_check_reset_hold_gate_lifecycle_clear()
	_check_reset_hold_gate_focus_loss_suppression()
	_check_reset_hold_gate_replay()

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


# --- DriverCommand reset flags ---------------------------------------------


func _check_driver_command_reset_fields() -> void:
	var default_command := DriverCommandScript.create()
	_check(
		default_command != null and not default_command.reset_held,
		"command.reset_held_defaults_false",
		str(default_command)
	)

	var edge_only := DriverCommandScript.create(0.0, 0.0, 0.0, 0.0, true)
	_check(
		edge_only != null and edge_only.reset_requested and not edge_only.reset_held,
		"command.five_argument_edge_still_accepted",
		str(edge_only)
	)

	var held_only := DriverCommandScript.create(0.0, 0.0, 0.0, 0.0, false, true)
	_check(
		held_only != null and not held_only.reset_requested and held_only.reset_held,
		"command.held_without_edge_accepted",
		str(held_only)
	)

	var both := DriverCommandScript.create(0.1, 0.2, 0.3, 0.4, true, true)
	_check(
		both != null and both.reset_requested and both.reset_held and both.is_normalized(),
		"command.both_reset_flags_accepted",
		str(both)
	)

	var clamped := DriverCommandScript.create(2.0, -1.0, 7.0, 5.0, true, true)
	_check(
		clamped != null and clamped.is_normalized() and clamped.reset_held,
		"command.clamp_preserves_reset_held",
		str(clamped)
	)

	var updated := DriverCommandScript.create()
	var applied := updated.set_from_raw(0.0, 0.0, 0.0, 0.0, true, true)
	_check(
		applied and updated.reset_requested and updated.reset_held,
		"command.set_from_raw_stores_both_flags",
		str(updated)
	)

	var rejected := updated.set_from_raw(NAN, 1.0, 1.0, 1.0, false, false)
	_check(
		not rejected and updated.reset_requested and updated.reset_held,
		"command.rejected_update_keeps_reset_flags",
		str(updated)
	)

	var source := DriverCommandScript.create(0.2, 0.0, 0.0, 0.0, true, true)
	var duplicate := source.copy()
	_check(
		duplicate != null and duplicate != source
		and duplicate.reset_requested and duplicate.reset_held,
		"command.copy_covers_reset_flags",
		str(duplicate)
	)
	if duplicate != null:
		duplicate.reset_requested = false
		duplicate.reset_held = false
		_check(
			source.reset_requested and source.reset_held,
			"command.copy_isolates_reset_flags",
			str(source)
		)


# --- Normalized reset_held level -------------------------------------------


func _check_reset_held_signal() -> void:
	var controls := OneSlotControls.new()

	var released := _sample(controls, 0.0, 0.0, 0.0, 0.0, false, DEFAULT_DT)
	_check(
		released != null and not released.reset_held,
		"held.unpressed_is_false",
		str(released)
	)

	var pressed := _sample(controls, 0.0, 0.0, 0.0, 0.0, true, DEFAULT_DT)
	_check(
		pressed != null and pressed.reset_requested and pressed.reset_held,
		"held.fresh_press_true",
		str(pressed)
	)

	var continuing := _sample(controls, 0.0, 0.0, 0.0, 0.0, true, DEFAULT_DT)
	_check(
		continuing != null and not continuing.reset_requested and continuing.reset_held,
		"held.continuing_press_stays_true",
		str(continuing)
	)

	var let_go := _sample(controls, 0.0, 0.0, 0.0, 0.0, false, DEFAULT_DT)
	_check(let_go != null and not let_go.reset_held, "held.release_false", str(let_go))

	var repress := _sample(controls, 0.0, 0.0, 0.0, 0.0, true, DEFAULT_DT)
	_check(
		repress != null and repress.reset_requested and repress.reset_held,
		"held.repress_true",
		str(repress)
	)

	var invalid_probe := OneSlotControls.new()
	_sample(invalid_probe, 0.0, 0.0, 0.0, 0.0, true, DEFAULT_DT)
	var rejected := _sample(invalid_probe, NAN, 0.0, 0.0, 0.0, true, DEFAULT_DT)
	_check(rejected == null, "held.invalid_returns_null", str(rejected))
	var resumed := _sample(invalid_probe, 0.0, 0.0, 0.0, 0.0, true, DEFAULT_DT)
	_check(
		resumed != null and not resumed.reset_requested and resumed.reset_held,
		"held.invalid_does_not_advance_state",
		str(resumed)
	)

	var suppressed := OneSlotControls.new()
	_sample(suppressed, 0.0, 0.0, 0.0, 0.0, true, DEFAULT_DT)
	suppressed.clear_lifecycle_state()
	var held_after_clear := _sample(suppressed, 0.0, 0.0, 0.0, 0.0, true, DEFAULT_DT)
	_check(
		held_after_clear != null
		and not held_after_clear.reset_requested
		and not held_after_clear.reset_held,
		"held.clear_while_held_suppresses_level",
		str(held_after_clear)
	)

	suppressed.clear_lifecycle_state()
	var repeat_clear := _sample(suppressed, 0.0, 0.0, 0.0, 0.0, true, DEFAULT_DT)
	_check(
		repeat_clear != null and not repeat_clear.reset_held,
		"held.repeat_clear_keeps_suppression",
		str(repeat_clear)
	)

	_sample(suppressed, 0.0, 0.0, 0.0, 0.0, false, DEFAULT_DT)
	var fresh_press := _sample(suppressed, 0.0, 0.0, 0.0, 0.0, true, DEFAULT_DT)
	_check(
		fresh_press != null and fresh_press.reset_requested and fresh_press.reset_held,
		"held.repress_after_suppression_true",
		str(fresh_press)
	)

	var idle := OneSlotControls.new()
	_sample(idle, 0.0, 0.0, 0.0, 0.0, false, DEFAULT_DT)
	idle.clear_lifecycle_state()
	var idle_press := _sample(idle, 0.0, 0.0, 0.0, 0.0, true, DEFAULT_DT)
	_check(
		idle_press != null and idle_press.reset_requested and idle_press.reset_held,
		"held.idle_clear_keeps_new_press",
		str(idle_press)
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


# --- Reset hold gate --------------------------------------------------------


func _check_reset_hold_gate_structure() -> void:
	var gate := ResetHoldGateScript.new()
	_check(gate != null, "gate.instance_created", str(gate))
	var as_object: Object = gate
	_check(
		as_object is RefCounted and not (as_object is Node),
		"gate.refcounted_not_node",
		str(gate)
	)
	_check(
		gate.get_script() == ResetHoldGateScript,
		"gate.script_attached",
		str(gate.get_script())
	)
	_check(
		_near(ResetHoldGateScript.HOLD_SECONDS_S, 1.0),
		"gate.hold_constant_one_second",
		str(ResetHoldGateScript.HOLD_SECONDS_S)
	)
	_measured["gate_hold_seconds"] = ResetHoldGateScript.HOLD_SECONDS_S


func _check_reset_hold_gate_boundary() -> void:
	var gate := ResetHoldGateScript.new()
	var held := _gate_command(true)
	_check(not gate.sample(held, 0.5), "gate.half_second_no_fire", "")
	_check(not gate.sample(held, 0.25), "gate.three_quarters_no_fire", "")
	_check(not gate.sample(held, 0.125), "gate.seven_eighths_no_fire", "")
	_check(not gate.sample(held, 0.0625), "gate.just_under_one_second_no_fire", "")
	_check(gate.sample(held, 0.0625), "gate.exactly_one_second_fires", "")

	for index in 10:
		_check(
			not gate.sample(held, DEFAULT_DT),
			"gate.sustained_hold_does_not_repeat_%d" % index,
			""
		)
	_check(not gate.sample(held, 1.0), "gate.long_hold_after_fire_no_repeat", "")

	var near := ResetHoldGateScript.new()
	_check(not near.sample(held, 0.9375), "gate.setup_just_under_threshold", "")
	_check(not near.sample(held, 0.062499), "gate.epsilon_under_threshold_no_fire", "")
	_check(near.sample(held, 0.000002), "gate.epsilon_over_threshold_fires", "")

	var level_only := ResetHoldGateScript.new()
	_check(
		level_only.sample(_gate_command(true, false), 1.0),
		"gate.held_without_edge_fires",
		""
	)

	var edge_gate := ResetHoldGateScript.new()
	var edge_only := _gate_command(false, true)
	var edge_fired := false
	for index in 60:
		if edge_gate.sample(edge_only, DEFAULT_DT):
			edge_fired = true
			break
	_check(not edge_fired, "gate.edge_alone_never_fires", "")
	_check(
		not edge_gate.sample(_gate_command(true, false), 0.5),
		"gate.edge_ticks_do_not_accumulate",
		""
	)


func _check_reset_hold_gate_early_release_and_rearm() -> void:
	var gate := ResetHoldGateScript.new()
	var held := _gate_command(true)
	var released := _gate_command(false)

	_check(not gate.sample(held, 0.6), "gate.early_release_partial_no_fire", "")
	_check(not gate.sample(released, 0.1), "gate.release_clears_progress", "")
	_check(
		not gate.sample(held, 0.6),
		"gate.rehold_after_release_needs_full_second",
		""
	)
	_check(gate.sample(held, 0.4), "gate.rehold_completes_one_second", "")

	var threshold_release := ResetHoldGateScript.new()
	_check(not threshold_release.sample(held, 0.99), "gate.threshold_release_setup", "")
	_check(
		not threshold_release.sample(released, 0.5),
		"gate.release_at_threshold_does_not_fire",
		""
	)
	_check(not threshold_release.sample(held, 0.99), "gate.threshold_release_rehold_partial", "")
	_check(
		threshold_release.sample(held, 0.01),
		"gate.threshold_release_full_hold_fires",
		""
	)

	for index in 5:
		_check(
			not gate.sample(held, DEFAULT_DT),
			"gate.post_fire_hold_no_repeat_%d" % index,
			""
		)
	_check(not gate.sample(released, DEFAULT_DT), "gate.post_fire_release_no_repeat", "")
	_check(not gate.sample(held, 0.5), "gate.rearm_needs_full_second", "")
	_check(gate.sample(held, 0.5), "gate.rearmed_second_hold_fires", "")


func _check_reset_hold_gate_zero_dt() -> void:
	var gate := ResetHoldGateScript.new()
	var held := _gate_command(true)
	_check(not gate.sample(held, 0.9), "gate.zero_dt_setup_below_threshold", "")
	for index in 10:
		_check(
			not gate.sample(held, 0.0),
			"gate.zero_dt_does_not_advance_%d" % index,
			""
		)
	_check(gate.sample(held, 0.1), "gate.zero_dt_then_positive_dt_fires", "")


func _check_reset_hold_gate_invalid_atomicity() -> void:
	var held := _gate_command(true)
	var malformed_range := DriverCommandScript.create()
	malformed_range.steer = 2.0
	var malformed_nonfinite := DriverCommandScript.create()
	malformed_nonfinite.throttle = NAN

	var dt_variants: Array[float] = [NAN, INF, -0.1]
	for index in dt_variants.size():
		var gate := ResetHoldGateScript.new()
		_check(not gate.sample(held, 0.6), "gate.invalid_dt_setup_%d" % index, "")
		_check(
			not gate.sample(held, dt_variants[index]),
			"gate.invalid_dt_refused_%d" % index,
			""
		)
		var reference := ResetHoldGateScript.new()
		_check(not reference.sample(held, 0.6), "gate.invalid_dt_reference_%d" % index, "")
		_check(
			_gate_replays_match(gate, reference, [0.1, 0.1, 0.1, 0.1]),
			"gate.invalid_dt_leaves_progress_untouched_%d" % index,
			""
		)

	var command_variants: Array = [null, malformed_range, malformed_nonfinite]
	for index in command_variants.size():
		var probe: DriverCommand = command_variants[index]
		var gate := ResetHoldGateScript.new()
		_check(not gate.sample(held, 0.6), "gate.invalid_command_setup_%d" % index, "")
		_check(
			not gate.sample(probe, 0.5),
			"gate.invalid_command_refused_%d" % index,
			""
		)
		var reference := ResetHoldGateScript.new()
		_check(not reference.sample(held, 0.6), "gate.invalid_command_reference_%d" % index, "")
		_check(
			_gate_replays_match(gate, reference, [0.1, 0.1, 0.1, 0.1]),
			"gate.invalid_command_leaves_progress_untouched_%d" % index,
			""
		)

	var rearm := ResetHoldGateScript.new()
	_check(rearm.sample(held, 1.0), "gate.invalid_rearm_fire_setup", "")
	_check(not rearm.sample(_gate_command(false), DEFAULT_DT), "gate.invalid_rearm_release", "")
	_check(not rearm.sample(held, 0.6), "gate.invalid_rearm_partial", "")
	_check(not rearm.sample(held, INF), "gate.invalid_rearm_inf_dt_refused", "")
	_check(rearm.sample(held, 0.4), "gate.invalid_rearm_still_completable", "")


func _check_reset_hold_gate_lifecycle_clear() -> void:
	var gate := ResetHoldGateScript.new()
	var held := _gate_command(true)
	_check(not gate.sample(held, 0.6), "gate.clear_partial_no_fire", "")
	gate.clear_lifecycle_state()
	_check(not gate.sample(held, 0.6), "gate.clear_cancels_progress", "")
	_check(gate.sample(held, 0.4), "gate.after_clear_needs_full_second", "")

	var refire := ResetHoldGateScript.new()
	_check(refire.sample(held, 1.0), "gate.clear_refire_setup", "")
	refire.clear_lifecycle_state()
	_check(refire.sample(held, 1.0), "gate.clear_cancels_fired_latch", "")


func _check_reset_hold_gate_focus_loss_suppression() -> void:
	var controls := OneSlotControls.new()
	var gate := ResetHoldGateScript.new()

	var first := _sample(controls, 0.0, 0.0, 0.0, 0.0, true, 0.25)
	_check(first != null and first.reset_held, "focus.first_press_held", str(first))
	_check(not gate.sample(first, 0.25), "focus.first_tick_no_fire", "")

	var second := _sample(controls, 0.0, 0.0, 0.0, 0.0, true, 0.25)
	_check(second != null and second.reset_held, "focus.second_tick_held", str(second))
	_check(not gate.sample(second, 0.25), "focus.half_second_no_fire", "")

	controls.clear_lifecycle_state()
	var suppressed_fires := 0
	for index in 4:
		var suppressed := _sample(controls, 0.0, 0.0, 0.0, 0.0, true, 0.25)
		_check(
			suppressed != null and not suppressed.reset_held,
			"focus.suppressed_physical_hold_%d" % index,
			str(suppressed)
		)
		if suppressed != null and gate.sample(suppressed, 0.25):
			suppressed_fires += 1
	_check(
		suppressed_fires == 0,
		"focus.suppressed_physical_hold_never_fires",
		"fires=%d" % suppressed_fires
	)

	_sample(controls, 0.0, 0.0, 0.0, 0.0, false, 0.25)
	var rearmed_fires := 0
	var fired_index := -1
	for index in 4:
		var fresh := _sample(controls, 0.0, 0.0, 0.0, 0.0, true, 0.25)
		_check(
			fresh != null and fresh.reset_held,
			"focus.repressed_hold_%d" % index,
			str(fresh)
		)
		if fresh != null and gate.sample(fresh, 0.25):
			rearmed_fires += 1
			fired_index = index
	_check(
		rearmed_fires == 1 and fired_index == 3,
		"focus.rearmed_hold_fires_once_at_one_second",
		"fires=%d index=%d" % [rearmed_fires, fired_index]
	)


func _check_reset_hold_gate_replay() -> void:
	var schedule := [
		{"held": true, "dt": 0.25},
		{"held": true, "dt": 0.25},
		{"held": true, "dt": 0.25},
		{"held": true, "dt": 0.25},
		{"held": true, "dt": 0.5},
		{"held": false, "dt": 0.25},
		{"held": true, "dt": 0.5},
		{"held": true, "dt": 0.5},
		{"held": true, "dt": -1.0},
		{"held": true, "dt": 0.25},
		{"held": false, "dt": 0.1},
		{"held": true, "dt": 0.25},
		{"held": true, "dt": 0.25},
		{"held": true, "dt": 0.25},
		{"held": true, "dt": 0.25},
	]
	var expected := [
		false, false, false, true, false, false, false, true,
		false, false, false, false, false, false, true,
	]
	var first := _run_gate_schedule(schedule)
	var second := _run_gate_schedule(schedule)
	_check(first == expected, "gate.replay_expected_actions", str(first))
	_check(first == second, "gate.replay_deterministic", str(second))
	_measured["replay_actions"] = first


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


func _gate_command(p_held: bool, p_edge := false) -> DriverCommand:
	return DriverCommandScript.create(0.0, 0.0, 0.0, 0.0, p_edge, p_held)


func _run_gate_schedule(p_schedule: Array) -> Array:
	var gate := ResetHoldGateScript.new()
	var outputs := []
	for entry in p_schedule:
		outputs.append(gate.sample(_gate_command(entry["held"], false), entry["dt"]))
	return outputs


func _gate_replays_match(
	p_left: ResetHoldGate,
	p_right: ResetHoldGate,
	p_steps: Array[float]
) -> bool:
	for index in p_steps.size():
		var left_output: bool = p_left.sample(_gate_command(true, false), p_steps[index])
		var right_output: bool = p_right.sample(_gate_command(true, false), p_steps[index])
		if left_output != right_output:
			return false
	return true


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
		"command_component": DRIVER_COMMAND_SCRIPT_PATH,
		"reset_gate_component": RESET_GATE_SCRIPT_PATH,
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
			"The reset hold gate times an explicit hold only; it places no car, chooses no route anchor, integrates no RaceSession, and does not implement the Practice pause menu's immediate reset path.",
			"The deliberate-failure case proves only that a failing check exits nonzero; it does not prove the engine harness or hardware path.",
			"No M1/M3 acceptance claim; the coordinator independently verifies and integrates the components.",
		],
	}
	print("INPUT_LAB_RESULT ", JSON.stringify(report))
	print("CHECKS_TOTAL=", _checks, " CHECKS_FAILED=", _failures.size())
	quit(1 if _failures.size() > 0 else 0)
