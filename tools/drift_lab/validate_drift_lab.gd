extends SceneTree
## Headless black-box runner for the M1.3 pure drift-phase slice.
##
## Run from an isolated project copy (tools/drift_lab/run_validation.sh stages
## one and imports first):
##   godot --headless --fixed-fps 60 --path <project> \
##       --script res://tools/drift_lab/validate_drift_lab.gd
##
## Optional `--case=<id>` selects one case; the default runs every case.
## `--case=intentional_failure` always exits nonzero to prove the harness
## detects a failing check. Each case prints its own machine-readable result;
## the runner prints one DRIFT_LAB_RESULT line, one CHECKS_TOTAL line and calls
## `quit` on every path.
##
## These are pure-kernel checks only: no scene, body, physics query, clock,
## input routing or gameplay claim. Car states are explicit scripted inputs,
## not integrated physics. They make no M1.3 or M1 acceptance claim.

const DriverScript = preload("res://tools/drift_lab/drift_lab_driver.gd")
const DriftModel = preload("res://src/simulation/drift_phase_model.gd")

const CASE_IDS := [
	"handbrake_rising_edge",
	"assist_brake_alternative",
	"entry_refusals",
	"entry_blend_and_sustain",
	"countersteer_tolerance",
	"steering_unwind_recovery",
	"major_impact_recovery",
	"low_speed_recovery",
	"airborne_transition_and_landing",
	"stability_assist_factor",
	"tuning_validation",
	"invalid_input_atomicity",
	"deterministic_replay",
]

var _checks := 0
var _failures: Array[String] = []
var _measured: Dictionary = {}
var _finished := false


func _initialize() -> void:
	var requested := _requested_case()
	if requested == "intentional_failure":
		_finish(_run_intentional_failure(), 1)
		return
	var case_ids: Array = []
	if requested == "all":
		case_ids = CASE_IDS.duplicate()
	elif CASE_IDS.has(requested):
		case_ids = [requested]
	else:
		printerr(
			"unknown case '%s'; use all, one of %s, or intentional_failure"
			% [requested, str(CASE_IDS)]
		)
		quit(2)
		return
	var results := []
	for case_id in case_ids:
		results.append(_run_case(String(case_id)))
	var failed_cases := 0
	for result in results:
		if not bool(result["pass"]):
			failed_cases += 1
	var report := {
		"schema": "roadstorm.drift_lab.validation.v1",
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


func _requested_case() -> String:
	for argument in OS.get_cmdline_args():
		if argument.begins_with("--case="):
			return argument.substr(7)
	var from_environment := OS.get_environment("DRIFT_LAB_CASE")
	if from_environment != "":
		return from_environment
	return "all"


func _run_case(case_id: String) -> Dictionary:
	var driver := DriverScript.new()
	match case_id:
		"handbrake_rising_edge":
			_case_handbrake_rising_edge(driver)
		"assist_brake_alternative":
			_case_assist_brake_alternative(driver)
		"entry_refusals":
			_case_entry_refusals(driver)
		"entry_blend_and_sustain":
			_case_entry_blend_and_sustain(driver)
		"countersteer_tolerance":
			_case_countersteer_tolerance(driver)
		"steering_unwind_recovery":
			_case_steering_unwind_recovery(driver)
		"major_impact_recovery":
			_case_major_impact_recovery(driver)
		"low_speed_recovery":
			_case_low_speed_recovery(driver)
		"airborne_transition_and_landing":
			_case_airborne_transition_and_landing(driver)
		"stability_assist_factor":
			_case_stability_assist_factor(driver)
		"tuning_validation":
			_case_tuning_validation(driver)
		"invalid_input_atomicity":
			_case_invalid_input_atomicity(driver)
		"deterministic_replay":
			_case_deterministic_replay(driver)
	_checks += driver.checks
	for failure in driver.failures:
		_failures.append("%s: %s" % [case_id, failure])
	_measured[case_id] = driver.measured
	return {
		"id": case_id,
		"checks": driver.checks,
		"pass": driver.failures.is_empty(),
		"failures": driver.failures.duplicate(),
	}


# --- Cases ------------------------------------------------------------------


func _case_handbrake_rising_edge(driver) -> void:
	var tuning = driver.default_tuning()
	var car = driver.make_car(20.0)
	var drift = driver.fresh_drift_state()
	var tap = driver.command(0.8, 0.0, 0.0, 1.0)
	var first = driver.advance(car, tap, drift, tuning)
	if first == null:
		driver.check(false, "handbrake entry proposal is null")
		return
	driver.check_eq(int(first.phase), int(DriftModel.Phase.ENTRY), "tap enters entry phase")
	driver.check_eq(
		int(first.event),
		int(DriftModel.Event.DRIFT_ENTRY_HANDBRAKE),
		"handbrake tap reports handbrake entry"
	)
	driver.check_eq(first.drift_sign, 1, "right steer records positive drift sign")
	driver.check_between(first.drift_blend, 0.0, 1.0, "entry blend bounded")
	driver.check_close(first.stability_factor, 1.0, 1e-9, "low-slip stability factor untouched")

	var second = driver.advance(car, driver.command(0.8, 0.0, 0.0, 1.0), first.state, tuning)
	if second == null:
		driver.check(false, "held-handbrake continuation is null")
		return
	driver.check_eq(int(second.event), int(DriftModel.Event.NONE), "held handbrake is not a new tap")
	driver.check_close(
		second.state.previous_handbrake, 1.0, 1e-9, "previous handbrake tracks the held value"
	)
	driver.check(
		second.drift_blend > first.drift_blend,
		"entry influence grows while the phase continues"
	)

	var sustain_index := -1
	var current = second
	for index in range(40):
		if current.phase == DriftModel.Phase.SUSTAINED:
			sustain_index = index
			break
		current = driver.advance(
			car, driver.command(0.8, 0.0, 0.0, 1.0), current.state, tuning
		)
	driver.check(sustain_index >= 0, "entry reaches sustained drift")
	if sustain_index >= 0:
		driver.measure("entry_to_sustain_ticks", sustain_index + 1)
		driver.check_close(
			float(sustain_index + 1) * DriftModel.DT,
			tuning.entry_blend_time_s,
			DriftModel.DT,
			"entry blend lasts about the configured time"
		)
		current = driver.advance(
			car, driver.command(0.8, 0.0, 0.0, 1.0), current.state, tuning
		)
		driver.check_close(current.drift_blend, 1.0, 1e-9, "sustained drift holds full influence")

	var released = driver.advance(
		car, driver.command(0.8, 0.0, 0.0, 0.0), current.state, tuning
	)
	var retap = driver.advance(
		car, driver.command(0.8, 0.0, 0.0, 1.0), released.state, tuning
	)
	driver.check_eq(int(retap.event), int(DriftModel.Event.NONE), "sustained phase ignores re-taps")
	driver.check_eq(int(retap.phase), int(DriftModel.Phase.SUSTAINED), "re-tap keeps sustained drift")


func _case_assist_brake_alternative(driver) -> void:
	var tuning = driver.default_tuning()
	var car = driver.make_car(20.0)
	var first = driver.advance(
		car, driver.command(0.7, 0.0, 1.0, 0.0), driver.fresh_drift_state(), tuning
	)
	if first == null:
		driver.check(false, "assist brake entry proposal is null")
		return
	driver.check_eq(int(first.phase), int(DriftModel.Phase.ENTRY), "assist brake enters entry phase")
	driver.check_eq(
		int(first.event),
		int(DriftModel.Event.DRIFT_ENTRY_ASSIST_BRAKE),
		"assist brake tap reports its own entry reason"
	)
	var held = driver.advance(
		car, driver.command(0.7, 0.0, 1.0, 0.0), first.state, tuning
	)
	driver.check_eq(int(held.event), int(DriftModel.Event.NONE), "held brake is not a repeated tap")

	var off = driver.default_tuning()
	off.assist_mode = DriftModel.AssistMode.OFF
	var refused = driver.advance(
		car, driver.command(0.7, 0.0, 1.0, 0.0), driver.fresh_drift_state(), off
	)
	driver.check_eq(int(refused.phase), int(DriftModel.Phase.GRIP), "assist off refuses brake entry")
	driver.check_eq(int(refused.event), int(DriftModel.Event.NONE), "assist off reports no entry")

	var handbrake_off = driver.advance(
		car, driver.command(0.7, 0.0, 0.0, 1.0), driver.fresh_drift_state(), off
	)
	driver.check_eq(
		int(handbrake_off.event),
		int(DriftModel.Event.DRIFT_ENTRY_HANDBRAKE),
		"assist off still allows the handbrake path"
	)

	var no_steer = driver.advance(
		car, driver.command(0.1, 0.0, 1.0, 0.0), driver.fresh_drift_state(), tuning
	)
	driver.check_eq(int(no_steer.phase), int(DriftModel.Phase.GRIP), "brake tap without steer is refused")


func _case_entry_refusals(driver) -> void:
	var tuning = driver.default_tuning()
	var specs := [
		{
			"name": "reverse",
			"forward": -5.0,
			"steer": 0.8,
			"brake": 0.0,
			"handbrake": 1.0,
			"grounded": true,
			"phase": int(DriftModel.Phase.GRIP),
			"event": int(DriftModel.Event.NONE),
		},
		{
			"name": "low_speed",
			"forward": 11.999,
			"steer": 0.8,
			"brake": 0.0,
			"handbrake": 1.0,
			"grounded": true,
			"phase": int(DriftModel.Phase.GRIP),
			"event": int(DriftModel.Event.NONE),
		},
		{
			"name": "exact_threshold",
			"forward": 12.0,
			"steer": 0.8,
			"brake": 0.0,
			"handbrake": 1.0,
			"grounded": true,
			"phase": int(DriftModel.Phase.GRIP),
			"event": int(DriftModel.Event.NONE),
		},
		{
			"name": "above_threshold",
			"forward": 12.001,
			"steer": 0.8,
			"brake": 0.0,
			"handbrake": 1.0,
			"grounded": true,
			"phase": int(DriftModel.Phase.ENTRY),
			"event": int(DriftModel.Event.DRIFT_ENTRY_HANDBRAKE),
		},
		{
			"name": "weak_steer",
			"forward": 20.0,
			"steer": 0.49,
			"brake": 0.0,
			"handbrake": 1.0,
			"grounded": true,
			"phase": int(DriftModel.Phase.GRIP),
			"event": int(DriftModel.Event.NONE),
		},
		{
			"name": "left_drift",
			"forward": 20.0,
			"steer": -0.8,
			"brake": 0.0,
			"handbrake": 1.0,
			"grounded": true,
			"phase": int(DriftModel.Phase.ENTRY),
			"event": int(DriftModel.Event.DRIFT_ENTRY_HANDBRAKE),
		},
		{
			"name": "airborne",
			"forward": 20.0,
			"steer": 0.8,
			"brake": 0.0,
			"handbrake": 1.0,
			"grounded": false,
			"phase": int(DriftModel.Phase.AIRBORNE),
			"event": int(DriftModel.Event.AIRBORNE),
		},
		{
			"name": "assist_low_speed",
			"forward": 11.0,
			"steer": 0.8,
			"brake": 1.0,
			"handbrake": 0.0,
			"grounded": true,
			"phase": int(DriftModel.Phase.GRIP),
			"event": int(DriftModel.Event.NONE),
		},
	]
	for spec in specs:
		var name := String(spec["name"])
		var car = driver.make_car(
			float(spec["forward"]), 0.0, 0.0, bool(spec["grounded"])
		)
		var cmd = driver.command(
			float(spec["steer"]), 0.0, float(spec["brake"]), float(spec["handbrake"])
		)
		var proposal = driver.advance(car, cmd, driver.fresh_drift_state(), tuning)
		if proposal == null:
			driver.check(false, "%s: proposal is null" % name)
			continue
		driver.check_eq(
			int(proposal.phase), int(spec["phase"]), "%s: phase" % name
		)
		driver.check_eq(
			int(proposal.event), int(spec["event"]), "%s: event" % name
		)
		if name == "left_drift":
			driver.check_eq(proposal.drift_sign, -1, "left steer records negative drift sign")


func _case_entry_blend_and_sustain(driver) -> void:
	var tuning = driver.default_tuning()
	var car = driver.make_car(20.0)
	var drift = driver.fresh_drift_state()
	var proposal = driver.advance(
		car, driver.command(0.8, 0.0, 0.0, 1.0), drift, tuning
	)
	var proposals: Array = []
	if proposal != null:
		proposals.append(proposal)
	for _index in range(45):
		if proposal == null:
			break
		proposal = driver.advance(
			car, driver.command(0.8, 0.0, 0.0, 1.0), proposal.state, tuning
		)
		if proposal != null:
			proposals.append(proposal)
	if proposals.is_empty():
		driver.check(false, "no entry proposal produced")
		return

	driver.check_eq(int(proposals[0].phase), int(DriftModel.Phase.ENTRY), "first tick is entry")
	var sustain_index := -1
	var sustain_events := 0
	for index in range(proposals.size()):
		var phase = proposals[index].phase
		if phase == DriftModel.Phase.SUSTAINED:
			if sustain_index < 0:
				sustain_index = index
			sustain_events += int(proposals[index].event == DriftModel.Event.DRIFT_SUSTAINED)
	driver.check(sustain_index >= 0, "entry completes into sustained drift")
	driver.check_eq(sustain_events, 1, "sustained transition event fires once")
	if sustain_index < 0:
		return
	driver.measure("entry_to_sustain_s", float(sustain_index) * DriftModel.DT)
	driver.check_close(
		float(sustain_index) * DriftModel.DT,
		tuning.entry_blend_time_s,
		DriftModel.DT,
		"entry blend duration matches tuning"
	)

	var previous_blend := -1.0
	for index in range(sustain_index):
		var blend: float = proposals[index].drift_blend
		driver.check_between(blend, 0.0, 1.0, "entry blend bounded at tick %d" % index)
		driver.check(
			blend >= previous_blend - 1e-12,
			"entry blend does not decrease at tick %d" % index
		)
		previous_blend = blend
	driver.check_close(
		float(proposals[sustain_index].drift_blend), 1.0, 1e-9, "sustain starts at full influence"
	)
	for index in range(sustain_index + 1, proposals.size()):
		driver.check_eq(
			int(proposals[index].event), int(DriftModel.Event.NONE), "sustain emits no events"
		)
		driver.check_close(
			float(proposals[index].drift_blend), 1.0, 1e-9, "sustain keeps full influence"
		)


func _reach_sustained(driver, car, tuning, steer: float = 0.8) -> DriftModel.Proposal:
	var cmd = driver.command(steer, 0.0, 0.0, 1.0)
	var proposal = driver.advance(car, cmd, driver.fresh_drift_state(), tuning)
	for _index in range(60):
		if proposal == null:
			return null
		if proposal.phase == DriftModel.Phase.SUSTAINED:
			return proposal
		proposal = driver.advance(car, cmd, proposal.state, tuning)
	return null


func _case_countersteer_tolerance(driver) -> void:
	var tuning = driver.default_tuning()
	var car = driver.make_car(20.0)
	var sustained = _reach_sustained(driver, car, tuning)
	if sustained == null:
		driver.check(false, "could not reach sustained drift for countersteer case")
		return
	var current = sustained
	var recovery_seen := false
	for _index in range(30):
		current = driver.advance(
			car, driver.command(-0.7, 0.0, 0.0, 0.0), current.state, tuning
		)
		if current.phase == DriftModel.Phase.RECOVERY:
			recovery_seen = true
	driver.check(not recovery_seen, "ordinary countersteer does not force recovery")
	driver.check_eq(int(current.phase), int(DriftModel.Phase.SUSTAINED), "countersteer keeps sustain")
	driver.check_close(current.drift_blend, 1.0, 1e-9, "countersteer keeps full influence")

	var mild = driver.advance(
		car, driver.command(-0.3, 0.0, 0.0, 0.0), current.state, tuning
	)
	driver.check_eq(int(mild.phase), int(DriftModel.Phase.SUSTAINED), "mild countersteer keeps sustain")


func _case_steering_unwind_recovery(driver) -> void:
	var tuning = driver.default_tuning()
	var car = driver.make_car(20.0)
	var sustained = _reach_sustained(driver, car, tuning)
	if sustained == null:
		driver.check(false, "could not reach sustained drift for unwind case")
		return
	var proposals: Array = []
	var current = sustained
	for _index in range(45):
		current = driver.advance(
			car, driver.command(0.0, 0.0, 0.0, 0.0), current.state, tuning
		)
		proposals.append(current)

	var unwind_index := -1
	var grip_index := -1
	for index in range(proposals.size()):
		if unwind_index < 0 and proposals[index].event == DriftModel.Event.STEERING_UNWIND_RECOVERY:
			unwind_index = index
		if proposals[index].event == DriftModel.Event.GRIP_RESTORED:
			grip_index = index
	driver.check(unwind_index >= 0, "steering unwind triggers recovery")
	driver.check(grip_index > unwind_index, "recovery completes back to grip")
	if unwind_index < 0 or grip_index < 0:
		return
	driver.measure("unwind_recovery_s", float(unwind_index + 1) * DriftModel.DT)
	driver.check_close(
		float(unwind_index + 1) * DriftModel.DT,
		tuning.unwind_hold_s,
		DriftModel.DT,
		"unwind hold matches tuning"
	)
	driver.check_close(
		float(grip_index - unwind_index) * DriftModel.DT,
		tuning.recovery_blend_time_s,
		DriftModel.DT,
		"recovery blend matches tuning"
	)
	driver.check_eq(int(proposals[grip_index].phase), int(DriftModel.Phase.GRIP), "final phase is grip")
	driver.check_eq(proposals[grip_index].drift_sign, 0, "grip restores a neutral drift sign")
	driver.check_close(proposals[grip_index].drift_blend, 0.0, 1e-9, "grip has zero drift influence")

	var previous_blend := INF
	for index in range(unwind_index, grip_index):
		var blend: float = proposals[index].drift_blend
		driver.check(blend <= previous_blend + 1e-12, "recovery blend decreases at tick %d" % index)
		previous_blend = blend

	# One-frame chatter guard: brief unwinds reset instead of triggering recovery.
	var brief = _reach_sustained(driver, car, tuning)
	if brief == null:
		driver.check(false, "could not reach sustained drift for chatter guard")
		return
	var chatter := false
	var cursor = brief
	for _index in range(5):
		cursor = driver.advance(
			car, driver.command(0.0, 0.0, 0.0, 0.0), cursor.state, tuning
		)
		if cursor.phase == DriftModel.Phase.RECOVERY:
			chatter = true
	cursor = driver.advance(
		car, driver.command(0.8, 0.0, 0.0, 1.0), cursor.state, tuning
	)
	driver.check(not chatter, "brief unwind below the hold timer does not recover")
	driver.check_eq(int(cursor.phase), int(DriftModel.Phase.SUSTAINED), "steering again sustains")


func _case_major_impact_recovery(driver) -> void:
	var tuning = driver.default_tuning()
	var car = driver.make_car(20.0)
	var sustained = _reach_sustained(driver, car, tuning)
	if sustained == null:
		driver.check(false, "could not reach sustained drift for impact case")
		return
	var current = sustained
	for _index in range(5):
		current = driver.advance(
			car, driver.command(0.8, 0.0, 0.0, 0.0), current.state, tuning, 5.9
		)
		driver.check_eq(
			int(current.phase), int(DriftModel.Phase.SUSTAINED), "sub-threshold impact keeps sustain"
		)
	var hit = driver.advance(
		car, driver.command(0.8, 0.0, 0.0, 0.0), current.state, tuning, 6.0
	)
	driver.check_eq(
		int(hit.event), int(DriftModel.Event.MAJOR_IMPACT_RECOVERY), "major impact triggers recovery"
	)
	driver.check_eq(int(hit.phase), int(DriftModel.Phase.RECOVERY), "major impact enters recovery")

	# A second major impact mid-recovery restarts the bounded window from the
	# influence actually present, without an event or a refilled blend.
	for _index in range(5):
		current = driver.advance(
			car, driver.command(0.8, 0.0, 0.0, 0.0), hit.state, tuning, 0.0
		)
	var decayed_blend: float = current.drift_blend
	var rehit = driver.advance(
		car, driver.command(0.8, 0.0, 0.0, 0.0), current.state, tuning, 6.0
	)
	driver.check_eq(
		int(rehit.event), int(DriftModel.Event.NONE), "mid-recovery impact emits no transition event"
	)
	driver.check_eq(
		int(rehit.phase), int(DriftModel.Phase.RECOVERY), "mid-recovery impact stays in recovery"
	)
	driver.check(
		rehit.drift_blend <= decayed_blend + 1e-9,
		"mid-recovery impact does not refill the blend"
	)
	driver.check_close(
		rehit.state.recovery_start_blend, decayed_blend, 1e-9,
		"mid-recovery restart captures the current blend"
	)
	driver.check_close(
		rehit.state.phase_time_s, 0.0, 1e-9, "mid-recovery impact restarts the timer"
	)

	var restore_index := -1
	current = rehit
	for index in range(30):
		current = driver.advance(
			car, driver.command(0.8, 0.0, 0.0, 0.0), current.state, tuning, 0.0
		)
		if current.event == DriftModel.Event.GRIP_RESTORED:
			restore_index = index
			break
	driver.check(restore_index >= 0, "impact recovery completes")
	if restore_index >= 0:
		driver.check_close(
			float(restore_index + 1) * DriftModel.DT,
			tuning.recovery_blend_time_s,
			DriftModel.DT,
			"impact recovery blend matches tuning"
		)
		driver.check_eq(int(current.phase), int(DriftModel.Phase.GRIP), "impact recovery ends in grip")

	var grip_car = driver.make_car(20.0)
	var grip_hit = driver.advance(
		grip_car, driver.command(0.8), driver.fresh_drift_state(), tuning, 9.0
	)
	driver.check_eq(
		int(grip_hit.event), int(DriftModel.Event.MAJOR_IMPACT_RECOVERY), "grip impact forces recovery"
	)


func _case_low_speed_recovery(driver) -> void:
	var tuning = driver.default_tuning()
	var fast_car = driver.make_car(20.0)
	var sustained = _reach_sustained(driver, fast_car, tuning)
	if sustained == null:
		driver.check(false, "could not reach sustained drift for low-speed case")
		return
	var slow_car = driver.make_car(5.0)
	var current = sustained
	var recovery_index := -1
	var grip_index := -1
	for index in range(45):
		current = driver.advance(
			slow_car, driver.command(0.8, 0.0, 0.0, 0.0), current.state, tuning
		)
		if recovery_index < 0 and current.event == DriftModel.Event.LOW_SPEED_RECOVERY:
			recovery_index = index
		if current.event == DriftModel.Event.GRIP_RESTORED:
			grip_index = index
			break
	driver.check(recovery_index >= 0, "low speed triggers recovery")
	if recovery_index < 0:
		return
	driver.measure("low_speed_hold_s", float(recovery_index + 1) * DriftModel.DT)
	driver.check_close(
		float(recovery_index + 1) * DriftModel.DT,
		tuning.low_speed_hold_s,
		DriftModel.DT,
		"low-speed hold matches tuning"
	)
	if grip_index >= 0:
		driver.check_close(
			float(grip_index - recovery_index) * DriftModel.DT,
			tuning.recovery_blend_time_s,
			DriftModel.DT,
			"low-speed recovery blend matches tuning"
		)

	# Brief dips below the exit speed reset the hold instead of chattering.
	var brief = _reach_sustained(driver, fast_car, tuning)
	if brief == null:
		driver.check(false, "could not reach sustained drift for low-speed chatter guard")
		return
	var chatter := false
	var cursor = brief
	for _index in range(5):
		cursor = driver.advance(
			slow_car, driver.command(0.8, 0.0, 0.0, 0.0), cursor.state, tuning
		)
		if cursor.phase == DriftModel.Phase.RECOVERY:
			chatter = true
		cursor = driver.advance(
			fast_car, driver.command(0.8, 0.0, 0.0, 0.0), cursor.state, tuning
		)
	driver.check(not chatter, "brief low-speed dip does not recover")


func _case_airborne_transition_and_landing(driver) -> void:
	var tuning = driver.default_tuning()
	var car = driver.make_car(20.0)
	var sustained = _reach_sustained(driver, car, tuning)
	if sustained == null:
		driver.check(false, "could not reach sustained drift for airborne case")
		return
	var air_car = driver.make_car(20.0, 0.0, 0.0, false)
	var ground_car = driver.make_car(20.0, 0.0, 0.0, true)

	var current = driver.advance(
		air_car, driver.command(0.8, 0.0, 0.0, 0.0), sustained.state, tuning
	)
	driver.check_eq(int(current.phase), int(DriftModel.Phase.AIRBORNE), "lost ground enters airborne")
	driver.check_eq(int(current.event), int(DriftModel.Event.AIRBORNE), "airborne transition is reported")
	driver.check_close(current.drift_blend, 0.0, 1e-9, "airborne suppresses drift influence")

	var ignored = driver.advance(
		air_car, driver.command(0.8, 0.0, 0.0, 1.0), current.state, tuning
	)
	driver.check_eq(int(ignored.event), int(DriftModel.Event.NONE), "entry taps are ignored airborne")
	driver.check_eq(int(ignored.phase), int(DriftModel.Phase.AIRBORNE), "airborne phase persists")

	for _index in range(6):
		current = driver.advance(
			air_car, driver.command(0.8, 0.0, 0.0, 0.0), current.state, tuning
		)
	driver.check_eq(int(current.phase), int(DriftModel.Phase.AIRBORNE), "airborne persists while ungrounded")

	# A single grounded frame followed by another airborne frame must not land.
	current = driver.advance(
		ground_car, driver.command(0.8, 0.0, 0.0, 0.0), current.state, tuning
	)
	driver.check_eq(int(current.phase), int(DriftModel.Phase.AIRBORNE), "one grounded frame does not land")
	current = driver.advance(
		air_car, driver.command(0.8, 0.0, 0.0, 0.0), current.state, tuning
	)
	driver.check_eq(int(current.phase), int(DriftModel.Phase.AIRBORNE), "airborne resumes after a flicker")

	var landing_ticks := 0
	var landed := false
	for _index in range(10):
		current = driver.advance(
			ground_car, driver.command(0.8, 0.0, 0.0, 0.0), current.state, tuning
		)
		landing_ticks += 1
		if current.event == DriftModel.Event.LANDED_RECOVERY:
			landed = true
			break
	driver.check(landed, "confirmed landing enters recovery")
	if landed:
		driver.check_close(
			float(landing_ticks) * DriftModel.DT,
			tuning.landing_confirm_s,
			DriftModel.DT,
			"landing confirmation matches tuning"
		)
		var restore_index := -1
		for index in range(30):
			current = driver.advance(
				ground_car, driver.command(0.8, 0.0, 0.0, 0.0), current.state, tuning
			)
			if current.event == DriftModel.Event.GRIP_RESTORED:
				restore_index = index
				break
		driver.check(restore_index >= 0, "landing recovery completes")
		if restore_index >= 0:
			driver.check_close(
				float(restore_index + 1) * DriftModel.DT,
				tuning.recovery_blend_time_s,
				DriftModel.DT,
				"landing recovery blend matches tuning"
			)

	var plain_air = driver.advance(
		air_car, driver.command(0.8), driver.fresh_drift_state(), tuning
	)
	driver.check_eq(int(plain_air.event), int(DriftModel.Event.AIRBORNE), "grip airtime enters airborne")


func _case_stability_assist_factor(driver) -> void:
	var tuning = driver.default_tuning()
	var slips := [0.0, 30.0, 50.0, 60.0, 75.0, 90.0, 120.0]
	var factors: Array = []
	for slip in slips:
		var car = driver.make_car_with_slip(float(slip), 30.0)
		var proposal = driver.advance(
			car, driver.command(0.0), driver.fresh_drift_state(), tuning
		)
		if proposal == null:
			driver.check(false, "stability proposal is null at %.1f deg" % float(slip))
			factors.append(INF)
			continue
		driver.check_between(
			proposal.stability_factor, tuning.stability_floor_factor, 1.0,
			"stability factor bounded at %.1f deg" % float(slip)
		)
		factors.append(proposal.stability_factor)

	driver.check_close(float(factors[0]), 1.0, 1e-9, "zero slip leaves rotation untouched")
	driver.check_close(float(factors[2]), 1.0, 1e-9, "onset threshold leaves rotation untouched")
	for index in range(1, factors.size()):
		driver.check(
			float(factors[index]) <= float(factors[index - 1]) + 1e-12,
			"stability factor does not increase with slip at index %d" % index
		)
	driver.check(
		float(factors[3]) < 1.0 and float(factors[3]) > tuning.stability_floor_factor,
		"mid-range slip gradually reduces rotation"
	)
	driver.check_close(
		float(factors[5]), tuning.stability_floor_factor, 1e-9, "full slip reaches the floor"
	)
	driver.check_close(
		float(factors[6]), tuning.stability_floor_factor, 1e-9, "beyond full slip stays at the floor"
	)

	# Documented interpolation midpoint for a custom provisional curve.
	var custom = driver.default_tuning()
	custom.stability_start_deg = 40.0
	custom.stability_full_deg = 60.0
	custom.stability_floor_factor = 0.5
	var midpoint_car = driver.make_car_with_slip(50.0, 30.0)
	var midpoint = driver.advance(
		midpoint_car, driver.command(0.0), driver.fresh_drift_state(), custom
	)
	driver.check_close(midpoint.stability_factor, 0.75, 1e-6, "documented linear midpoint")

	var off = driver.default_tuning()
	off.assist_mode = DriftModel.AssistMode.OFF
	var off_car = driver.make_car_with_slip(120.0, 30.0)
	var off_proposal = driver.advance(
		off_car, driver.command(0.0), driver.fresh_drift_state(), off
	)
	driver.check_close(off_proposal.stability_factor, 1.0, 1e-9, "assist off disables the factor")

	var air_car = driver.make_car_with_slip(120.0, 30.0)
	air_car.grounded = false
	var air_proposal = driver.advance(
		air_car, driver.command(0.0), driver.fresh_drift_state(), tuning
	)
	driver.check_close(air_proposal.stability_factor, 1.0, 1e-9, "airborne disables the factor")


func _case_tuning_validation(driver) -> void:
	var good = driver.default_tuning()
	driver.check(good.is_valid(), "default provisional tuning is valid")

	var too_fast_entry = driver.default_tuning()
	too_fast_entry.min_entry_forward_speed_m_s = 11.999
	driver.check(not too_fast_entry.is_valid(), "entry speed below the design floor is refused")

	var raised_entry = driver.default_tuning()
	raised_entry.min_entry_forward_speed_m_s = 12.5
	raised_entry.sustain_exit_speed_m_s = 10.0
	driver.check(raised_entry.is_valid(), "entry speed above the design floor is allowed")

	var exit_not_below_entry = driver.default_tuning()
	exit_not_below_entry.sustain_exit_speed_m_s = 12.0
	driver.check(not exit_not_below_entry.is_valid(), "sustain exit speed must stay below entry speed")

	var bad_values := [
		{"field": "entry_steer_min", "value": -0.1},
		{"field": "entry_steer_min", "value": 1.1},
		{"field": "entry_blend_time_s", "value": 0.0},
		{"field": "entry_blend_time_s", "value": -0.2},
		{"field": "recovery_blend_time_s", "value": 0.0},
		{"field": "unwind_hold_s", "value": -0.1},
		{"field": "low_speed_hold_s", "value": -0.1},
		{"field": "impact_exit_speed_loss_m_s", "value": -1.0},
		{"field": "target_slip_deg_max", "value": 10.0},
		{"field": "stability_start_deg", "value": 0.0},
		{"field": "stability_start_deg", "value": 181.0},
		{"field": "stability_full_deg", "value": 50.0},
		{"field": "stability_floor_factor", "value": -0.1},
		{"field": "stability_floor_factor", "value": 1.1},
		{"field": "airborne_min_time_s", "value": -0.1},
		{"field": "landing_confirm_s", "value": -0.1},
	]
	for spec in bad_values:
		var tuning = driver.default_tuning()
		tuning.set(String(spec["field"]), float(spec["value"]))
		driver.check(
			not tuning.is_valid(),
			"invalid %s=%s refused" % [String(spec["field"]), str(spec["value"])]
		)

	var nan_fields := [
		"min_entry_forward_speed_m_s",
		"entry_steer_min",
		"entry_blend_time_s",
		"stability_full_deg",
	]
	for field in nan_fields:
		var tuning = driver.default_tuning()
		tuning.set(String(field), NAN)
		driver.check(not tuning.is_valid(), "nonfinite %s refused" % String(field))


func _case_invalid_input_atomicity(driver) -> void:
	var tuning = driver.default_tuning()
	var car = driver.make_car(20.0)
	var drift = driver.fresh_drift_state()
	var state_before = driver.snapshot_state(drift)
	var tuning_before = driver.snapshot_tuning(tuning)
	var car_before = driver.snapshot_car(car)
	var cmd = driver.command(0.8, 0.0, 0.0, 1.0)

	var bad_car = driver.make_car(20.0)
	bad_car.velocity_m_s = Vector2(NAN, 20.0)
	driver.check(
		DriftModel.propose(bad_car, cmd, drift, tuning) == null, "nonfinite car is refused"
	)
	var inf_car = driver.make_car(20.0)
	inf_car.heading_rad = INF
	driver.check(
		DriftModel.propose(inf_car, cmd, drift, tuning) == null, "infinite heading is refused"
	)
	var bad_cmd = driver.command(0.8, 0.0, 0.0, 1.0)
	bad_cmd.handbrake = NAN
	driver.check(
		DriftModel.propose(car, bad_cmd, drift, tuning) == null, "nonfinite command is refused"
	)
	var bad_drift = driver.fresh_drift_state()
	bad_drift.phase_time_s = NAN
	driver.check(
		DriftModel.propose(car, cmd, bad_drift, tuning) == null, "nonfinite drift state is refused"
	)
	var bad_tuning = driver.default_tuning()
	bad_tuning.entry_steer_min = NAN
	driver.check(
		DriftModel.propose(car, cmd, drift, bad_tuning) == null, "nonfinite tuning is refused"
	)
	var below_floor = driver.default_tuning()
	below_floor.min_entry_forward_speed_m_s = 11.0
	driver.check(
		DriftModel.propose(car, cmd, drift, below_floor) == null,
		"design-floor-violating tuning is refused"
	)
	driver.check(
		DriftModel.propose(car, cmd, drift, tuning, 0.0) == null, "zero dt is refused"
	)
	driver.check(
		DriftModel.propose(car, cmd, drift, tuning, 1.0 / 30.0) == null, "30 Hz dt is refused"
	)
	driver.check(
		DriftModel.propose(car, cmd, drift, tuning, INF) == null, "infinite dt is refused"
	)
	driver.check(
		DriftModel.propose(car, cmd, drift, tuning, DriftModel.DT, -1.0) == null,
		"negative impact loss is refused"
	)
	driver.check(
		DriftModel.propose(car, cmd, drift, tuning, DriftModel.DT, NAN) == null,
		"nonfinite impact loss is refused"
	)
	driver.check(
		DriftModel.propose(null, cmd, drift, tuning) == null, "null car is refused"
	)
	driver.check(
		DriftModel.propose(car, null, drift, tuning) == null, "null command is refused"
	)
	driver.check(
		DriftModel.propose(car, cmd, null, tuning) == null, "null drift state is refused"
	)
	driver.check(
		DriftModel.propose(car, cmd, drift, null) == null, "null tuning is refused"
	)

	driver.check(
		driver.snapshots_equal(state_before, driver.snapshot_state(drift)),
		"refusals leave the prior drift state unchanged"
	)
	driver.check(
		driver.snapshots_equal(tuning_before, driver.snapshot_tuning(tuning)),
		"refusals leave the supplied tuning unchanged"
	)
	driver.check(
		driver.snapshots_equal(car_before, driver.snapshot_car(car)),
		"refusals leave the supplied car state unchanged"
	)

	var valid = driver.advance(car, cmd, drift, tuning)
	driver.check(valid != null, "valid input still evaluates after refusals")


func _case_deterministic_replay(driver) -> void:
	var tuning = driver.default_tuning()
	var specs := [
		{"f": 20.0, "l": 0.0, "g": true, "s": 0.8, "b": 0.0, "h": 1.0},
		{"f": 20.0, "l": 0.0, "g": true, "s": 0.8, "b": 0.0, "h": 1.0},
		{"f": 20.0, "l": 0.0, "g": true, "s": 0.2, "b": 0.0, "h": 1.0},
		{"f": 20.0, "l": 0.0, "g": true, "s": -0.7, "b": 0.0, "h": 0.0},
		{"f": 20.0, "l": 0.0, "g": true, "s": 0.0, "b": 0.0, "h": 0.0},
		{"f": 20.0, "l": 0.0, "g": true, "s": 0.0, "b": 0.0, "h": 0.0},
		{"f": 5.0, "l": 0.0, "g": true, "s": 0.8, "b": 0.0, "h": 0.0},
		{"f": 20.0, "l": 0.0, "g": false, "s": 0.8, "b": 0.0, "h": 0.0},
		{"f": 20.0, "l": 0.0, "g": true, "s": 0.8, "b": 1.0, "h": 0.0},
		{"f": 20.0, "l": 0.0, "g": true, "s": 0.8, "b": 0.0, "h": 1.0},
	]
	var first := _replay_trace(driver, tuning, specs)
	var second := _replay_trace(driver, tuning, specs)
	driver.check(first == second, "identical schedules replay identically")
	driver.measure("replay_ticks", first.size())

	var drift_before = driver.snapshot_state(driver.fresh_drift_state())
	var car = driver.make_car(20.0)
	var drift = driver.fresh_drift_state()
	var input_snapshot = driver.snapshot_state(drift)
	var proposal = driver.advance(car, driver.command(0.8, 0.0, 0.0, 1.0), drift, tuning)
	driver.check(proposal != null, "immutability probe evaluates")
	driver.check(
		driver.snapshots_equal(input_snapshot, driver.snapshot_state(drift)),
		"a valid evaluation does not mutate the input drift state"
	)
	driver.check(
		driver.snapshots_equal(drift_before, driver.snapshot_state(driver.fresh_drift_state())),
		"fresh states are independent copies"
	)

	var replay_again = driver.advance(
		car, driver.command(0.8, 0.0, 0.0, 1.0), driver.fresh_drift_state(), tuning
	)
	driver.check(
		driver.snapshots_equal(
			driver.snapshot_proposal(proposal), driver.snapshot_proposal(replay_again)
		),
		"repeated identical evaluations are identical"
	)


func _replay_trace(driver, tuning, specs: Array) -> Array:
	var trace := []
	var drift = driver.fresh_drift_state()
	for spec in specs:
		var car = driver.make_car(
			float(spec["f"]), float(spec["l"]), 0.0, bool(spec["g"])
		)
		var cmd = driver.command(
			float(spec["s"]), 0.0, float(spec["b"]), float(spec["h"])
		)
		var proposal = driver.advance(car, cmd, drift, tuning)
		trace.append(driver.snapshot_proposal(proposal))
		if proposal != null:
			drift = proposal.state
	return trace


# --- Deliberate failure proof ----------------------------------------------


func _run_intentional_failure() -> Dictionary:
	var driver := DriverScript.new()
	var tuning = driver.default_tuning()
	tuning.assist_mode = DriftModel.AssistMode.OFF
	var car = driver.make_car(20.0)
	var proposal = driver.advance(
		car, driver.command(0.8, 0.0, 1.0, 0.0), driver.fresh_drift_state(), tuning
	)
	# Deliberately false expectation: assist-off brake-tap entry is required to
	# be refused, so this assertion must fail and the process must exit nonzero.
	driver.check(
		bool(
			proposal != null
			and proposal.event == DriftModel.Event.DRIFT_ENTRY_ASSIST_BRAKE
		),
		"intentional failure probe: assist-off brake entry unexpectedly accepted"
	)
	var proof := {
		"schema": "roadstorm.drift_lab.validation.v1",
		"proof": "intentional_failure",
		"expected_nonzero_exit": true,
		"observed_checks_failed": driver.failures.size(),
		"pass": driver.failures.is_empty(),
		"failures": driver.failures.duplicate(),
	}
	print("INTENTIONAL_FAILURE_PROOF " + JSON.stringify(proof))
	return proof


# --- Report -----------------------------------------------------------------


const LIMITATIONS := [
	"Pure-kernel checks only: no Godot body, scene, physics query, clock, rendering, audio or input device is exercised.",
	"Car states are explicit scripted values, not integrated motor or contact physics; the drift model consumes committed road-plane records only.",
	"The drift blend and stability factor are advisory integration seams. No yaw, lateral damping, slip enforcement, style points, surge, course-zone qualification or surface response is implemented here.",
	"A drift-phase exit alone is not a clean or qualifying exit; qualification rules are explicitly out of scope.",
	"Default tuning values are provisional M1.3 laboratory choices. Only the 12 m/s entry speed has a validation floor from docs/GAME_DESIGN.md:24.",
	"Headless engine dummy display/audio drivers; no platform, controller or gameplay claim and no M1.3/M1 acceptance claim.",
]


func _finish(report: Dictionary, forced_exit: int = -1) -> void:
	if _finished:
		return
	_finished = true
	var passed := _failures.is_empty() and int(report.get("failed_cases", 0)) == 0
	var code := forced_exit
	if code < 0:
		code = 0 if passed else 1
	print("DRIFT_LAB_RESULT " + JSON.stringify(report))
	print("CHECKS_TOTAL=%d CHECKS_FAILED=%d" % [_checks, _failures.size()])
	quit(code)
