extends SceneTree
## Headless black-box runner for the M1.1 automatic-gear indication slice.
##
## Run from an isolated project copy (tools/gear_lab/run_validation.sh stages
## one and imports first):
##   godot --headless --fixed-fps 60 --path <project> \
##       --script res://tools/gear_lab/validate_gear_lab.gd
##
## Optional `--case=<id>` selects one case; the default runs every case.
## `--case=intentional_failure` always exits nonzero to prove the harness
## detects a failing check. Each case prints its own machine-readable result;
## the runner prints one GEAR_LAB_RESULT line, one CHECKS_TOTAL line and calls
## `quit` on every path.
##
## These are pure-kernel checks only: no scene, body, physics query, clock,
## input routing, audio or gameplay claim. Car states are explicit scripted
## inputs, not integrated motor physics. The component indicates gears and
## shift events only; nothing here commits `CarState.gear_index` or produces
## audible shifts, and no integrated automatic transmission is claimed.

const DriverScript = preload("res://tools/gear_lab/gear_lab_driver.gd")
const GearboxScript = preload("res://src/simulation/automatic_gearbox.gd")

const CASE_IDS := [
	"custom_config_boundaries",
	"acceleration_through_each_threshold",
	"downshifts",
	"boundary_dithering",
	"reverse_latch_transition",
	"rpm_bounds",
	"invalid_atomicity",
	"reset_replay",
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
		"schema": "roadstorm.gear_lab.validation.v1",
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
	var from_environment := OS.get_environment("GEAR_LAB_CASE")
	if from_environment != "":
		return from_environment
	return "all"


func _run_case(case_id: String) -> Dictionary:
	var driver := DriverScript.new()
	match case_id:
		"custom_config_boundaries":
			_case_custom_config_boundaries(driver)
		"acceleration_through_each_threshold":
			_case_acceleration_through_each_threshold(driver)
		"downshifts":
			_case_downshifts(driver)
		"boundary_dithering":
			_case_boundary_dithering(driver)
		"reverse_latch_transition":
			_case_reverse_latch_transition(driver)
		"rpm_bounds":
			_case_rpm_bounds(driver)
		"invalid_atomicity":
			_case_invalid_atomicity(driver)
		"reset_replay":
			_case_reset_replay(driver)
	_checks += driver.checks
	for failure in driver.failures:
		_failures.append("%s: %s" % [case_id, failure])
	_measured[case_id] = driver.measured
	print(
		"CASE %s checks=%d failures=%d pass=%s"
		% [case_id, driver.checks, driver.failures.size(), str(driver.failures.is_empty())]
	)
	return {
		"id": case_id,
		"checks": driver.checks,
		"pass": driver.failures.is_empty(),
		"failures": driver.failures.duplicate(),
	}


# --- Shared assertions --------------------------------------------------------


func _expect_event(
	driver,
	proposal,
	label: String,
	direction: int,
	from_gear: int,
	to_gear: int
) -> void:
	driver.check(proposal != null, "%s evaluation exists" % label)
	if proposal == null:
		return
	driver.check(proposal.has_event(), "%s emits one shift event" % label)
	if proposal.event == null:
		return
	driver.check_eq(int(proposal.event.direction), direction, "%s event direction" % label)
	driver.check_eq(int(proposal.event.from_gear), from_gear, "%s event from gear" % label)
	driver.check_eq(int(proposal.event.to_gear), to_gear, "%s event to gear" % label)


func _rpm_probe(driver, speed: float, reverse: bool = false) -> float:
	var proposal = driver.step(driver.fresh_gearbox(), driver.make_car(speed, reverse))
	if proposal == null:
		return NAN
	return proposal.normalized_rpm


func _upshift() -> int:
	return int(GearboxScript.ShiftDirection.UPSHIFT)


func _downshift() -> int:
	return int(GearboxScript.ShiftDirection.DOWNSHIFT)


func _enter_reverse() -> int:
	return int(GearboxScript.ShiftDirection.ENTER_REVERSE)


func _exit_reverse() -> int:
	return int(GearboxScript.ShiftDirection.EXIT_REVERSE)


# --- Cases ------------------------------------------------------------------


func _case_custom_config_boundaries(driver) -> void:
	var config = driver.config(3, [10.0, 20.0], [6.0, 14.0], 0.1, 0.5, 0.5, 30.0)
	driver.check(config.is_valid(), "custom three-gear config is valid")
	var gearbox = driver.fresh_gearbox(config)
	if gearbox == null:
		driver.check(false, "custom three-gear config is refused by create")
		return

	# Exact upshift boundary: strictly above is required.
	var proposal = driver.step(gearbox, driver.make_car(10.0))
	if proposal == null:
		driver.check(false, "custom config first evaluation is null")
		return
	driver.check_eq(int(proposal.gear_index), 1, "exact upshift threshold does not shift")
	driver.check(not proposal.has_event(), "exact upshift threshold emits no event")
	proposal = driver.step(gearbox, driver.make_car(10.0 + 1e-6))
	driver.check_eq(int(proposal.gear_index), 2, "just above custom threshold upshifts")
	_expect_event(
		driver, proposal, "custom threshold upshift", _upshift(), 1, 2
	)

	# Acceleration through both custom thresholds.
	gearbox = driver.fresh_gearbox(config)
	var accel_events := []
	var previous_gear := 0
	for index in range(0, 301):
		proposal = driver.step(gearbox, driver.make_car(float(index) * 0.1))
		if proposal == null:
			driver.check(false, "custom accel evaluation is null at %.1f" % (float(index) * 0.1))
			break
		driver.check(
			int(proposal.gear_index) >= previous_gear,
			"custom accel gear never decreases (speed %.1f)" % (float(index) * 0.1)
		)
		previous_gear = int(proposal.gear_index)
		if proposal.has_event():
			accel_events.append(proposal)
	driver.check_eq(accel_events.size(), 2, "custom accel emits exactly two upshifts")
	if accel_events.size() == 2:
		_expect_event(driver, accel_events[0], "custom accel first upshift", _upshift(), 1, 2)
		_expect_event(driver, accel_events[1], "custom accel second upshift", _upshift(), 2, 3)
	driver.check_eq(previous_gear, 3, "custom accel reaches gear 3")

	# Downshift through both custom thresholds, after a settled start.
	gearbox = driver.fresh_gearbox(config)
	proposal = driver.step(gearbox, driver.make_car(30.0))
	if proposal == null:
		driver.check(false, "custom decel setup evaluation is null")
		return
	driver.check_eq(int(proposal.gear_index), 3, "custom top speed reaches gear 3")
	for _index in range(12):
		driver.step(gearbox, driver.make_car(30.0))
	var down_events := []
	previous_gear = 3
	for index in range(300, -1, -1):
		proposal = driver.step(gearbox, driver.make_car(float(index) * 0.1))
		if proposal == null:
			driver.check(false, "custom decel evaluation is null at %.1f" % (float(index) * 0.1))
			break
		driver.check(
			int(proposal.gear_index) <= previous_gear,
			"custom decel gear never increases (speed %.1f)" % (float(index) * 0.1)
		)
		previous_gear = int(proposal.gear_index)
		if proposal.has_event():
			down_events.append(proposal)
	driver.check_eq(down_events.size(), 2, "custom decel emits exactly two downshifts")
	if down_events.size() == 2:
		_expect_event(driver, down_events[0], "custom decel first downshift", _downshift(), 3, 2)
		_expect_event(driver, down_events[1], "custom decel second downshift", _downshift(), 2, 1)
	driver.check_eq(previous_gear, 1, "custom decel ends in gear 1")

	# Single-forward-gear configuration: never shifts forward, reverse still
	# obeys the latch, and the rpm span is bounded by the top reference.
	var single = driver.config(1, [], [], 0.0, 0.5, 0.5, 20.0)
	driver.check(single.is_valid(), "single-gear config is valid")
	var single_gearbox = driver.fresh_gearbox(single)
	if single_gearbox == null:
		driver.check(false, "single-gear config is refused by create")
		return
	for speed in [-10.0, 0.0, 5.0, 19.9, 20.0, 60.0]:
		proposal = driver.step(single_gearbox, driver.make_car(speed))
		if proposal == null:
			driver.check(false, "single-gear evaluation is null at %.1f" % speed)
			continue
		driver.check_eq(int(proposal.gear_index), 1, "single-gear config stays in gear 1")
		driver.check(not proposal.has_event(), "single-gear config emits no forward event")
	proposal = driver.step(single_gearbox, driver.make_car(0.0, true))
	driver.check_eq(int(proposal.gear_index), -1, "single-gear config still reports reverse")
	_expect_event(driver, proposal, "single-gear reverse entry", _enter_reverse(), 1, -1)
	proposal = driver.step(single_gearbox, driver.make_car(0.4, false))
	driver.check_eq(int(proposal.gear_index), -1, "below reverse exit speed stays reverse")
	proposal = driver.step(single_gearbox, driver.make_car(0.5, false))
	driver.check_eq(int(proposal.gear_index), 1, "at reverse exit speed releases reverse")
	_expect_event(driver, proposal, "single-gear reverse release", _exit_reverse(), -1, 1)


func _case_acceleration_through_each_threshold(driver) -> void:
	var config = driver.default_config()
	var gearbox = driver.fresh_gearbox(config)
	if gearbox == null:
		driver.check(false, "default config is refused by create")
		return
	var events := []
	var previous_gear := 0
	var first_event_speed := INF
	for index in range(0, 451):
		var speed := float(index) * 0.1
		var proposal = driver.step(gearbox, driver.make_car(speed))
		if proposal == null:
			driver.check(false, "acceleration evaluation is null at %.1f" % speed)
			break
		driver.check_between(proposal.normalized_rpm, 0.0, 1.0, "acceleration rpm bounded at %.1f" % speed)
		if proposal.has_event():
			driver.check_between(proposal.event.normalized_rpm, 0.0, 1.0, "acceleration event rpm bounded")
			driver.check_close(
				proposal.event.normalized_rpm, proposal.normalized_rpm, 1e-12,
				"event rpm matches post-shift rpm"
			)
			if events.is_empty():
				first_event_speed = speed
			events.append({"speed": speed, "proposal": proposal})
		driver.check(
			int(proposal.gear_index) >= previous_gear,
			"acceleration gear never decreases at %.1f" % speed
		)
		previous_gear = int(proposal.gear_index)

	var expected_pairs := [[1, 2], [2, 3], [3, 4], [4, 5], [5, 6]]
	var expected_upshifts := [8.0, 14.0, 21.0, 29.0, 38.0]
	driver.check_eq(events.size(), 5, "acceleration emits exactly five upshifts")
	for index in range(mini(events.size(), expected_pairs.size())):
		var entry = events[index]
		var proposal = entry["proposal"]
		var speed: float = entry["speed"]
		_expect_event(
			driver, proposal, "acceleration shift %d" % index, _upshift(),
			expected_pairs[index][0], expected_pairs[index][1]
		)
		driver.check(
			speed > expected_upshifts[index],
			"acceleration shift %d occurs strictly above its threshold (%.3f)" % [index, speed]
		)
		driver.check(
			speed <= expected_upshifts[index] + 0.1 + 1e-6,
			"acceleration shift %d occurs at the first sample above its threshold (%.3f)" % [index, speed]
		)
	driver.check_eq(previous_gear, 6, "acceleration reaches sixth gear")
	driver.measure("ticks_to_first_shift", int(round(first_event_speed / 0.1)))

	# Exact-boundary probe: a speed exactly on the threshold must not shift;
	# one millionth of a metre per second above it must.
	gearbox = driver.fresh_gearbox(config)
	var exact = driver.step(gearbox, driver.make_car(8.0))
	if exact == null:
		driver.check(false, "exact-threshold probe is null")
		return
	driver.check_eq(int(exact.gear_index), 1, "speed exactly on threshold stays in gear 1")
	driver.check(not exact.has_event(), "speed exactly on threshold emits no event")
	driver.check_close(exact.normalized_rpm, 1.0, 1e-12, "threshold speed saturates gear-1 rpm")
	var above = driver.step(gearbox, driver.make_car(8.0 + 1e-6))
	driver.check_eq(int(above.gear_index), 2, "one micro-unit above threshold upshifts")
	_expect_event(driver, above, "boundary upshift", _upshift(), 1, 2)


func _case_downshifts(driver) -> void:
	var config = driver.default_config()
	var gearbox = driver.fresh_gearbox(config)
	if gearbox == null:
		driver.check(false, "default config is refused by create")
		return

	var top = driver.step(gearbox, driver.make_car(45.0))
	if top == null:
		driver.check(false, "downshift setup evaluation is null")
		return
	driver.check_eq(int(top.gear_index), 6, "top speed reaches sixth gear")
	_expect_event(driver, top, "direct top-speed shift", _upshift(), 1, 6)

	# Settle the minimum dwell before sweeping down.
	for _index in range(20):
		var settled = driver.step(gearbox, driver.make_car(45.0))
		driver.check(settled != null and not settled.has_event(), "settled top speed emits no shift")

	var events := []
	var previous_gear := 6
	for index in range(450, -1, -1):
		var speed := float(index) * 0.1
		var proposal = driver.step(gearbox, driver.make_car(speed))
		if proposal == null:
			driver.check(false, "downshift evaluation is null at %.1f" % speed)
			break
		driver.check_between(proposal.normalized_rpm, 0.0, 1.0, "downshift rpm bounded at %.1f" % speed)
		driver.check(
			int(proposal.gear_index) <= previous_gear,
			"downshift gear never increases at %.1f" % speed
		)
		previous_gear = int(proposal.gear_index)
		if proposal.has_event():
			events.append({"speed": speed, "proposal": proposal})

	var expected_pairs := [[6, 5], [5, 4], [4, 3], [3, 2], [2, 1]]
	var expected_downshifts := [31.0, 23.0, 16.0, 10.0, 5.0]
	driver.check_eq(events.size(), 5, "deceleration emits exactly five downshifts")
	for index in range(mini(events.size(), expected_pairs.size())):
		var entry = events[index]
		var proposal = entry["proposal"]
		var speed: float = entry["speed"]
		_expect_event(
			driver, proposal, "deceleration shift %d" % index, _downshift(),
			expected_pairs[index][0], expected_pairs[index][1]
		)
		driver.check(
			speed < expected_downshifts[index],
			"deceleration shift %d occurs strictly below its threshold (%.3f)" % [index, speed]
		)
		driver.check(
			speed >= expected_downshifts[index] - 0.1 - 1e-6,
			"deceleration shift %d occurs at the first sample below its threshold (%.3f)" % [index, speed]
		)
	driver.check_eq(previous_gear, 1, "deceleration ends in first gear")

	# Exact downshift boundary on one settled threshold.
	gearbox = driver.fresh_gearbox(config)
	var setup = driver.step(gearbox, driver.make_car(45.0))
	if setup == null:
		driver.check(false, "downshift boundary setup is null")
		return
	driver.check_eq(int(setup.gear_index), 6, "boundary setup reaches sixth gear")
	for _index in range(20):
		driver.step(gearbox, driver.make_car(45.0))
	var mid = driver.step(gearbox, driver.make_car(15.0))
	if mid == null:
		driver.check(false, "downshift boundary midpoint is null")
		return
	driver.check_eq(int(mid.gear_index), 3, "boundary setup settles in third gear")
	for _index in range(20):
		driver.step(gearbox, driver.make_car(15.0))
	var exact = driver.step(gearbox, driver.make_car(10.0))
	if exact == null:
		driver.check(false, "exact downshift probe is null")
		return
	driver.check_eq(int(exact.gear_index), 3, "speed exactly on downshift threshold stays in gear")
	driver.check(not exact.has_event(), "speed exactly on downshift threshold emits no event")
	var below = driver.step(gearbox, driver.make_car(10.0 - 1e-6))
	driver.check_eq(int(below.gear_index), 2, "one micro-unit below threshold downshifts")
	_expect_event(driver, below, "boundary downshift", _downshift(), 3, 2)


func _case_boundary_dithering(driver) -> void:
	var config = driver.default_config()

	# Dither around the first upshift threshold: the first sample above it
	# shifts once, and the validated hysteresis band keeps it there even when
	# speed returns above the threshold much later.
	var gearbox = driver.fresh_gearbox(config)
	var initial = driver.step(gearbox, driver.make_car(8.2))
	if initial == null:
		driver.check(false, "up-threshold dither entry is null")
		return
	driver.check_eq(int(initial.gear_index), 2, "dither up enters second gear")
	_expect_event(driver, initial, "dither up entry", _upshift(), 1, 2)
	var extra_up_events := 0
	for index in range(100):
		var speed := 7.8 if index % 2 == 0 else 8.2
		var proposal = driver.step(gearbox, driver.make_car(speed))
		if proposal == null:
			driver.check(false, "up-threshold dither evaluation is null")
			break
		driver.check_eq(int(proposal.gear_index), 2, "up-threshold dither stays in second gear")
		if proposal.has_event():
			extra_up_events += 1
	driver.check_eq(extra_up_events, 0, "up-threshold dither emits no further shift events")

	# Dither around the first downshift threshold.
	gearbox = driver.fresh_gearbox(config)
	initial = driver.step(gearbox, driver.make_car(8.2))
	if initial == null:
		driver.check(false, "down-threshold dither entry is null")
		return
	driver.check_eq(int(initial.gear_index), 2, "dither down starts in second gear")
	# Settle the dwell at a mid-band speed before dithering.
	for _index in range(20):
		var settled = driver.step(gearbox, driver.make_car(5.3))
		driver.check(settled != null and int(settled.gear_index) == 2, "dither down stays settled in second gear")
	var down_events := 0
	var down_event_proposal = null
	for index in range(100):
		var speed := 4.9 if index % 2 == 0 else 5.3
		var proposal = driver.step(gearbox, driver.make_car(speed))
		if proposal == null:
			driver.check(false, "down-threshold dither evaluation is null")
			break
		driver.check_eq(int(proposal.gear_index), 1, "down-threshold dither stays in first gear")
		if proposal.has_event():
			down_events += 1
			down_event_proposal = proposal
	driver.check_eq(down_events, 1, "down-threshold dither shifts exactly once")
	_expect_event(driver, down_event_proposal, "dither down shift", _downshift(), 2, 1)

	# Minimum dwell suppresses an immediate opposite shift. The release is
	# measured in ticks so the configured dwell is checked, not assumed.
	var dwell_config = driver.default_config()
	dwell_config.min_shift_dwell_s = 0.5
	gearbox = driver.fresh_gearbox(dwell_config)
	var up = driver.step(gearbox, driver.make_car(8.5))
	if up == null:
		driver.check(false, "dwell probe upshift is null")
		return
	driver.check_eq(int(up.gear_index), 2, "dwell probe upshifts into second gear")
	driver.check_close(up.state.shift_cooldown_s, 0.5, 1e-12, "dwell sets the full cooldown")
	var blocked_ticks := 0
	var release_ticks := -1
	for index in range(60):
		var proposal = driver.step(gearbox, driver.make_car(4.5))
		if proposal == null:
			driver.check(false, "dwell probe evaluation is null")
			break
		if proposal.has_event():
			release_ticks = index + 1
			driver.check_eq(int(proposal.gear_index), 1, "dwell release downshifts to first gear")
			_expect_event(driver, proposal, "dwell release", _downshift(), 2, 1)
			break
		blocked_ticks += 1
		driver.check_eq(int(proposal.gear_index), 2, "dwell blocks the opposite shift while active")
	driver.check(release_ticks > 0, "dwell eventually releases the opposite shift")
	if release_ticks > 0:
		driver.measure("dwell_release_ticks", release_ticks)
		driver.check_close(
			float(release_ticks) * GearboxScript.DT, 0.5, 2.5 * GearboxScript.DT,
			"dwell release happens at about the configured dwell"
		)
	driver.measure("dwell_blocked_ticks", blocked_ticks)


func _case_reverse_latch_transition(driver) -> void:
	var config = driver.default_config()

	# Latch engagement overrides signed velocity in both directions.
	var gearbox = driver.fresh_gearbox(config)
	var proposal = driver.step(gearbox, driver.make_car(20.0, true))
	if proposal == null:
		driver.check(false, "reverse latch evaluation is null")
		return
	driver.check_eq(int(proposal.gear_index), -1, "engaged latch selects reverse at positive speed")
	_expect_event(driver, proposal, "latch engagement", _enter_reverse(), 1, -1)

	proposal = driver.step(gearbox, driver.make_car(0.0, true))
	driver.check_eq(int(proposal.gear_index), -1, "latched reverse holds at zero speed")
	driver.check(not proposal.has_event(), "held latch emits no repeated event")
	proposal = driver.step(gearbox, driver.make_car(20.0, true))
	driver.check_eq(int(proposal.gear_index), -1, "positive speed cannot leave an engaged latch")
	driver.check(not proposal.has_event(), "engaged latch ignores positive travel")

	proposal = driver.step(gearbox, driver.make_car(20.0, false))
	driver.check_eq(int(proposal.gear_index), 3, "released latch at speed selects a forward gear")
	_expect_event(driver, proposal, "latch release at speed", _exit_reverse(), -1, 3)

	# Negative signed speed alone must never select reverse while the latch is
	# released.
	gearbox = driver.fresh_gearbox(config)
	proposal = driver.step(gearbox, driver.make_car(-5.0, false))
	driver.check_eq(int(proposal.gear_index), 1, "negative speed with released latch stays forward")
	driver.check(not proposal.has_event(), "released-latch backward roll emits no shift yet")
	gearbox = driver.fresh_gearbox(config)
	proposal = driver.step(gearbox, driver.make_car(-20.0, false))
	driver.check_eq(int(proposal.gear_index), 3, "fast backward roll with released latch selects a forward gear")
	driver.check(
		int(proposal.gear_index) > 0,
		"signed velocity alone never selects the reverse indication"
	)

	# Release hysteresis: a cleared latch stays reverse during backward roll and
	# only releases at/above the configured forward exit speed.
	gearbox = driver.fresh_gearbox(config)
	proposal = driver.step(gearbox, driver.make_car(0.0, true))
	driver.check_eq(int(proposal.gear_index), -1, "exit-hysteresis probe engages reverse")
	proposal = driver.step(gearbox, driver.make_car(-2.0, false))
	driver.check_eq(int(proposal.gear_index), -1, "cleared latch stays reverse while rolling backward")
	driver.check(not proposal.has_event(), "backward roll after release emits no forward event")
	proposal = driver.step(gearbox, driver.make_car(0.0, false))
	driver.check_eq(int(proposal.gear_index), -1, "cleared latch holds reverse at zero")
	proposal = driver.step(gearbox, driver.make_car(0.4, false))
	driver.check_eq(int(proposal.gear_index), -1, "below the exit speed stays reverse")
	driver.check(not proposal.has_event(), "below the exit speed emits no release")
	proposal = driver.step(gearbox, driver.make_car(0.5, false))
	driver.check_eq(int(proposal.gear_index), 1, "at the exit speed releases reverse")
	_expect_event(driver, proposal, "exit-speed release", _exit_reverse(), -1, 1)
	proposal = driver.step(gearbox, driver.make_car(-2.0, false))
	driver.check_eq(int(proposal.gear_index), 1, "released latch does not re-engage from backward roll")

	# The latch wins over high forward speed in both directions.
	gearbox = driver.fresh_gearbox(config)
	proposal = driver.step(gearbox, driver.make_car(45.0, false))
	driver.check_eq(int(proposal.gear_index), 6, "high-speed baseline reaches sixth gear")
	proposal = driver.step(gearbox, driver.make_car(45.0, true))
	driver.check_eq(int(proposal.gear_index), -1, "latch overrides high forward speed")
	_expect_event(driver, proposal, "high-speed latch override", _enter_reverse(), 6, -1)
	proposal = driver.step(gearbox, driver.make_car(45.0, false))
	driver.check_eq(int(proposal.gear_index), 6, "latch release restores the speed-selected gear")
	_expect_event(driver, proposal, "high-speed latch release", _exit_reverse(), -1, 6)


func _case_rpm_bounds(driver) -> void:
	var speeds := [-60.0, -20.5, -5.0, 0.0, 0.5, 4.0, 8.0, 12.0, 20.0, 30.0, 45.0, 60.0]
	for speed in speeds:
		var gearbox = driver.fresh_gearbox()
		var proposal = driver.step(gearbox, driver.make_car(speed))
		if proposal == null:
			driver.check(false, "rpm sweep evaluation is null at %.1f" % speed)
			continue
		driver.check_between(
			proposal.normalized_rpm, 0.0, 1.0, "rpm bounded at %.1f" % speed
		)
		if proposal.has_event():
			driver.check_between(
				proposal.event.normalized_rpm, 0.0, 1.0, "event rpm bounded at %.1f" % speed
			)
		var reverse = driver.step(gearbox, driver.make_car(speed, true))
		driver.check(reverse != null, "reverse rpm evaluation exists at %.1f" % speed)
		if reverse != null:
			driver.check_eq(int(reverse.gear_index), -1, "reverse rpm sweep reports reverse")
			driver.check_between(
				reverse.normalized_rpm, 0.0, 1.0, "reverse rpm bounded at %.1f" % speed
			)

	driver.check_close(_rpm_probe(driver, 0.0), 0.0, 1e-12, "zero speed has zero rpm")
	driver.check_close(_rpm_probe(driver, 4.0), 0.5, 1e-12, "mid first band maps to half rpm")
	driver.check_close(_rpm_probe(driver, 8.0), 1.0, 1e-12, "first-band top clamps to one")
	driver.check_close(_rpm_probe(driver, -60.0), 1.0, 1e-12, "large reverse roll magnitude clamps to one")

	# Banded values after the corresponding upshifts.
	var gearbox = driver.fresh_gearbox()
	var proposal = driver.step(gearbox, driver.make_car(8.5))
	if proposal == null:
		driver.check(false, "second-band probe is null")
		return
	driver.check_eq(int(proposal.gear_index), 2, "band probe reaches second gear")
	driver.check_close(proposal.normalized_rpm, (8.5 - 5.0) / (14.0 - 5.0), 1e-12, "second-band rpm value")
	gearbox = driver.fresh_gearbox()
	proposal = driver.step(gearbox, driver.make_car(14.5))
	if proposal == null:
		driver.check(false, "third-band probe is null")
		return
	driver.check_eq(int(proposal.gear_index), 3, "band probe reaches third gear")
	driver.check_close(proposal.normalized_rpm, (14.5 - 10.0) / (21.0 - 10.0), 1e-12, "third-band rpm value")
	gearbox = driver.fresh_gearbox()
	proposal = driver.step(gearbox, driver.make_car(45.0))
	if proposal == null:
		driver.check(false, "top-band probe is null")
		return
	driver.check_eq(int(proposal.gear_index), 6, "band probe reaches top gear")
	driver.check_close(proposal.normalized_rpm, 1.0, 1e-12, "top-band maximum is one")
	gearbox = driver.fresh_gearbox()
	proposal = driver.step(gearbox, driver.make_car(10.0, true))
	if proposal == null:
		driver.check(false, "reverse-band probe is null")
		return
	driver.check_eq(int(proposal.gear_index), -1, "reverse band probe reports reverse")
	driver.check_close(proposal.normalized_rpm, 10.0 / 45.0, 1e-12, "reverse rpm uses the top reference span")


func _case_invalid_atomicity(driver) -> void:
	# Invalid configurations are refused by both is_valid() and create().
	driver.check(GearboxScript.create(null) == null, "null config is refused")

	var invalid_specs := []
	var zero_gears = driver.default_config()
	zero_gears.forward_gear_count = 0
	invalid_specs.append({"label": "zero gears", "config": zero_gears})
	var too_many_gears = driver.default_config()
	too_many_gears.forward_gear_count = 9
	invalid_specs.append({"label": "nine gears", "config": too_many_gears})
	var short_arrays = driver.default_config()
	driver.set_upshift_speeds(short_arrays, [8.0, 14.0, 21.0, 29.0])
	invalid_specs.append({"label": "short upshift array", "config": short_arrays})
	var wrong_pair_length = driver.default_config()
	wrong_pair_length.forward_gear_count = 2
	invalid_specs.append({"label": "pair length mismatch", "config": wrong_pair_length})
	var negative = driver.default_config()
	negative.upshift_speeds_m_s[0] = -1.0
	invalid_specs.append({"label": "negative upshift", "config": negative})
	var nan_value = driver.default_config()
	nan_value.upshift_speeds_m_s[1] = NAN
	invalid_specs.append({"label": "nonfinite upshift", "config": nan_value})
	var unsorted_up = driver.default_config()
	driver.set_upshift_speeds(unsorted_up, [8.0, 14.0, 12.0, 29.0, 38.0])
	invalid_specs.append({"label": "unsorted upshift", "config": unsorted_up})
	var unsorted_down = driver.default_config()
	driver.set_downshift_speeds(unsorted_down, [5.0, 16.0, 10.0, 23.0, 31.0])
	invalid_specs.append({"label": "unsorted downshift", "config": unsorted_down})
	var tight_gap = driver.default_config()
	tight_gap.downshift_speeds_m_s[0] = 7.9
	invalid_specs.append({"label": "hysteresis gap violated", "config": tight_gap})
	var tiny_gap = driver.default_config()
	tiny_gap.min_hysteresis_gap_m_s = 0.1
	invalid_specs.append({"label": "hysteresis floor violated", "config": tiny_gap})
	var nan_gap = driver.default_config()
	nan_gap.min_hysteresis_gap_m_s = NAN
	invalid_specs.append({"label": "nonfinite hysteresis", "config": nan_gap})
	var negative_dwell = driver.default_config()
	negative_dwell.min_shift_dwell_s = -0.1
	invalid_specs.append({"label": "negative dwell", "config": negative_dwell})
	var nan_dwell = driver.default_config()
	nan_dwell.min_shift_dwell_s = NAN
	invalid_specs.append({"label": "nonfinite dwell", "config": nan_dwell})
	var negative_exit = driver.default_config()
	negative_exit.reverse_exit_forward_speed_m_s = -0.1
	invalid_specs.append({"label": "negative reverse exit", "config": negative_exit})
	var nan_exit = driver.default_config()
	nan_exit.reverse_exit_forward_speed_m_s = NAN
	invalid_specs.append({"label": "nonfinite reverse exit", "config": nan_exit})
	var low_top = driver.default_config()
	low_top.top_reference_speed_m_s = 38.0
	invalid_specs.append({"label": "top reference at last upshift", "config": low_top})
	var lower_top = driver.default_config()
	lower_top.top_reference_speed_m_s = 10.0
	invalid_specs.append({"label": "top reference below last upshift", "config": lower_top})
	var nan_top = driver.default_config()
	nan_top.top_reference_speed_m_s = NAN
	invalid_specs.append({"label": "nonfinite top reference", "config": nan_top})

	for spec in invalid_specs:
		var label := String(spec["label"])
		var candidate = spec["config"]
		driver.check(not candidate.is_valid(), "%s config fails is_valid" % label)
		driver.check(GearboxScript.create(candidate) == null, "%s config fails create" % label)

	# Refusals leave the live gearbox untouched and do not mutate the car.
	var gearbox = driver.fresh_gearbox()
	var car = driver.make_car(20.0)
	var accepted = driver.step(gearbox, car)
	driver.check(accepted != null, "atomicity setup evaluation is valid")
	if accepted == null:
		return
	driver.check_eq(int(accepted.gear_index), 3, "atomicity setup selects third gear")
	var snapshot_before: Dictionary = gearbox.snapshot()
	var car_before: Dictionary = driver.snapshot_car(car)

	var nan_car = driver.make_car(20.0)
	nan_car.velocity_m_s = Vector2(NAN, 20.0)
	driver.check(gearbox.propose(nan_car) == null, "nonfinite velocity is refused")
	var inf_car = driver.make_car(20.0)
	inf_car.heading_rad = INF
	driver.check(gearbox.propose(inf_car) == null, "infinite heading is refused")
	driver.check(gearbox.propose(null) == null, "null car is refused")
	for bad_dt in [0.0, -1.0, 1.0 / 30.0, INF, NAN]:
		driver.check(gearbox.propose(car, bad_dt) == null, "invalid dt %s is refused" % str(bad_dt))

	driver.check(gearbox.snapshot() == snapshot_before, "refusals leave gearbox state unchanged")
	driver.check(driver.snapshot_car(car) == car_before, "refusals leave the car record unchanged")

	# Full committed-record contract: a nonfinite numeric field the gearbox does
	# not consume still refuses atomically, before any derivation or write.
	# Position is the reviewed gap; `valid_progress_m` is an inert documented
	# seam. Both cars have finite motion and would shift on the old narrower
	# motion-only guard, so a refusal also proves no shift was committed.
	var record_probe = driver.fresh_gearbox()
	var record_snapshot: Dictionary = record_probe.snapshot()

	var nan_position_car = driver.make_car(20.0)
	nan_position_car.position_m = Vector2(NAN, 20.0)
	driver.check(not nan_position_car.is_finite(), "position probe really is nonfinite")
	var nan_position_result = record_probe.propose(nan_position_car)
	driver.check(nan_position_result == null, "nonfinite position is refused")
	driver.check(
		not (nan_position_result != null and nan_position_result.has_event()),
		"nonfinite position emits no shift event"
	)
	driver.check(is_nan(nan_position_car.position_m.x), "nonfinite position is left untouched")
	driver.check(record_probe.snapshot() == record_snapshot, "nonfinite position leaves gearbox state unchanged")

	var inf_progress_car = driver.make_car(20.0)
	inf_progress_car.valid_progress_m = INF
	driver.check(not inf_progress_car.is_finite(), "inert-seam probe really is nonfinite")
	var inf_progress_result = record_probe.propose(inf_progress_car)
	driver.check(inf_progress_result == null, "nonfinite inert progress seam is refused")
	driver.check(
		not (inf_progress_result != null and inf_progress_result.has_event()),
		"nonfinite inert progress seam emits no shift event"
	)
	driver.check(is_inf(inf_progress_car.valid_progress_m), "inert progress seam is left untouched")
	driver.check(record_probe.snapshot() == record_snapshot, "inert-seam refusal leaves gearbox state unchanged")

	var after_refusals = driver.step(gearbox, car)
	driver.check(after_refusals != null, "valid input still evaluates after refusals")
	if after_refusals != null:
		driver.check_eq(int(after_refusals.gear_index), 3, "post-refusal evaluation matches prior state")

	# Configuration is copied at creation: later caller mutation cannot alter a
	# live gearbox or make create accept the mutated values.
	var config = driver.default_config()
	var live = GearboxScript.create(config)
	driver.check(live != null, "config-copy setup creates a gearbox")
	config.upshift_speeds_m_s[0] = 1.0
	config.forward_gear_count = 2
	driver.check(GearboxScript.create(config) == null, "mutated config is rejected after creation")
	var live_proposal = driver.step(live, driver.make_car(20.0))
	driver.check(live_proposal != null, "live gearbox still evaluates after caller mutation")
	if live_proposal != null:
		driver.check_eq(int(live_proposal.gear_index), 3, "caller mutation does not change a live gearbox")


func _case_reset_replay(driver) -> void:
	var specs := []
	# First upshift, then settle past the dwell.
	specs.append({"s": 20.0, "r": false})
	for _index in range(20):
		specs.append({"s": 20.0, "r": false})
	# Reverse engagement, held latch, backward roll after release, then exit.
	specs.append({"s": 20.0, "r": true})
	specs.append({"s": 0.0, "r": true})
	specs.append({"s": -2.0, "r": false})
	specs.append({"s": 0.0, "r": false})
	specs.append({"s": 0.5, "r": false})
	for _index in range(20):
		specs.append({"s": 0.5, "r": false})
	# Multi-gear upshift, multi-gear downshift, final downshift and reverse.
	specs.append({"s": 45.0, "r": false})
	for _index in range(20):
		specs.append({"s": 45.0, "r": false})
	specs.append({"s": 10.0, "r": false})
	for _index in range(20):
		specs.append({"s": 10.0, "r": false})
	specs.append({"s": 0.0, "r": false})
	specs.append({"s": 0.0, "r": true})

	var first = driver.replay_trace(null, specs)
	var second = driver.replay_trace(null, specs)
	driver.check(first == second, "identical schedules replay exactly")
	driver.measure("replay_ticks", first.size())
	driver.check(first.size() == specs.size(), "replay records one entry per tick")
	driver.check_eq(driver.event_count(first), 7, "replay schedule exercises a stable seven-event trace")

	var directions := {}
	for entry in first:
		if entry != null and entry.has("event") and entry["event"] != null:
			directions[int(entry["event"]["direction"])] = true
	for direction in [_upshift(), _downshift(), _enter_reverse(), _exit_reverse()]:
		driver.check(directions.has(direction), "replay exercised direction %d" % direction)

	var fresh_snapshot: Dictionary = driver.fresh_gearbox().snapshot()
	var gearbox = driver.fresh_gearbox()
	var partial = driver.step(gearbox, driver.make_car(45.0))
	driver.check(partial != null and int(partial.gear_index) == 6, "reset probe advances away from initial")
	gearbox.reset()
	driver.check(gearbox.snapshot() == fresh_snapshot, "reset restores the deterministic initial state")
	var replayed = driver.replay_trace(null, specs, gearbox)
	driver.check(replayed == first, "post-reset replay matches the original trace exactly")

	var independent = driver.fresh_gearbox()
	var untouched: Dictionary = independent.snapshot()
	driver.step(gearbox, driver.make_car(8.5))
	driver.check(independent.snapshot() == untouched, "separate gearboxes keep independent state")
	var reset_event = driver.step(gearbox, driver.make_car(0.0))
	driver.check(reset_event != null, "post-reset evaluation succeeds")
	if reset_event != null:
		driver.check(not reset_event.has_event(), "post-reset neutral tick emits no event")


# --- Deliberate failure proof ----------------------------------------------


func _run_intentional_failure() -> Dictionary:
	var driver := DriverScript.new()
	var gearbox = driver.fresh_gearbox()
	var proposal = driver.step(gearbox, driver.make_car(8.0))
	# Deliberately false expectation: a speed exactly on the upshift threshold
	# must not shift, so this assertion must fail and the process must exit
	# nonzero.
	driver.check(
		bool(proposal != null and proposal.has_event()),
		"intentional failure probe: exact-threshold speed unexpectedly shifted"
	)
	var proof := {
		"schema": "roadstorm.gear_lab.validation.v1",
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
	"Pure-kernel checks only: no Godot body, scene, physics query, clock, rendering, audio device or input routing is exercised.",
	"Car states are explicit scripted values, not integrated motor, contact or airborne physics; the gearbox consumes committed road-plane records only.",
	"Reverse selection follows the committed CarState.reverse_engaged latch and does not model how the motor engages or releases that latch; it makes no reverse-drive physics claim.",
	"The gearbox changes no physics and writes no CarState field. The future integrator owns committing gear_index and routing ShiftEvent to presentation/audio.",
	"No audible shift is produced or faked here; normalized rpm is a bounded indication value, not measured engine speed.",
	"Airborne behaviour, throttle/brake awareness, launch control and shift-torque effects are out of scope; the same fixed-step contract as ArcadeMotor is enforced but no motor torque is applied.",
	"Default thresholds, dwell, hysteresis and reverse-exit values are provisional M1.1 choices spanning the committed 0-45 m/s laboratory envelope; they are not frozen handling coefficients and await M1.6/M1.7 measurements.",
	"Headless engine dummy display/audio drivers; no platform, controller, gameplay or integrated-automatic-transmission acceptance claim and no M1 acceptance claim.",
]


func _finish(report: Dictionary, forced_exit: int = -1) -> void:
	if _finished:
		return
	_finished = true
	var passed := _failures.is_empty() and int(report.get("failed_cases", 0)) == 0
	var code := forced_exit
	if code < 0:
		code = 0 if passed else 1
	print("GEAR_LAB_RESULT " + JSON.stringify(report))
	print("CHECKS_TOTAL=%d CHECKS_FAILED=%d" % [_checks, _failures.size()])
	quit(code)
