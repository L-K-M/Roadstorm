class_name GearLabExtensions
extends RefCounted
## M1.1 gearbox follow-up checks that depend on the extended gearbox API.
##
## These cases are loaded dynamically by `validate_gear_lab.gd` so the
## historical-source negative control (`--legacy-gearbox`) can still parse and
## run the legacy case against the older `AutomaticGearbox`, which predates
## `MAX_SHIFT_DWELL_S` and `restore_and_mirror()`. The checks themselves call
## the real gearbox; they never re-implement its math.

const GearboxScript = preload("res://src/simulation/automatic_gearbox.gd")


func run_dwell_domain(driver) -> void:
	# The ordinary default behavior is unchanged: gear 1 -> 2 above the first
	# upshift threshold and the configured 0.25 s dwell.
	var default_box = driver.fresh_gearbox()
	driver.check(default_box != null, "default gearbox creates")
	if default_box == null:
		return
	var default_proposal = driver.step(default_box, driver.make_car(8.5))
	driver.check(default_proposal != null, "default dwell probe evaluation exists")
	if default_proposal == null:
		return
	driver.check_eq(
		int(default_proposal.gear_index), 2,
		"default probe still upshifts into second gear"
	)
	driver.check_close(
		default_proposal.state.shift_cooldown_s, 0.25, 1e-12,
		"default probe keeps the 0.25 s dwell"
	)

	# Inclusive maximum boundary: config, create and restore all accept it.
	var max_config = driver.default_config()
	max_config.min_shift_dwell_s = GearboxScript.MAX_SHIFT_DWELL_S
	driver.check(max_config.is_valid(), "dwell at the inclusive maximum validates")
	var max_box = GearboxScript.create(max_config)
	driver.check(max_box != null, "dwell at the inclusive maximum creates")

	var max_state = GearboxScript.GearboxState.new()
	max_state.gear_index = 2
	max_state.shift_cooldown_s = GearboxScript.MAX_SHIFT_DWELL_S
	max_state.normalized_rpm = 0.5
	driver.check(max_state.is_valid(), "state at the inclusive maximum dwell is valid")
	driver.check(max_box.restore_state(max_state), "restore accepts the inclusive maximum dwell")
	driver.check_close(
		float(max_box.snapshot()["shift_cooldown_s"]),
		GearboxScript.MAX_SHIFT_DWELL_S, 1e-12,
		"restored maximum dwell is preserved"
	)

	# Just above the maximum, and the reported giant value, are refused by both
	# validation entry points instead of being clamped.
	var just_over = driver.default_config()
	just_over.min_shift_dwell_s = GearboxScript.MAX_SHIFT_DWELL_S + 1e-3
	driver.check(not just_over.is_valid(), "dwell just above the maximum fails is_valid")
	driver.check(
		GearboxScript.create(just_over) == null,
		"dwell just above the maximum fails create"
	)

	var huge = driver.default_config()
	huge.min_shift_dwell_s = 1e16
	driver.check(not huge.is_valid(), "1e16 dwell fails is_valid")
	driver.check(GearboxScript.create(huge) == null, "1e16 dwell fails create")

	var huge_state = GearboxScript.GearboxState.new()
	huge_state.shift_cooldown_s = 1e16
	driver.check(not huge_state.is_valid(), "1e16 state dwell is globally invalid")
	driver.check(not max_box.restore_state(huge_state), "restore refuses a 1e16 dwell")

	# The same inclusive/exclusive boundary applies to a restorable state.
	var just_over_state = GearboxScript.GearboxState.new()
	just_over_state.shift_cooldown_s = GearboxScript.MAX_SHIFT_DWELL_S + 1e-3
	driver.check(not just_over_state.is_valid(), "state dwell just above the maximum is invalid")
	driver.check(
		not max_box.restore_state(just_over_state),
		"restore refuses a dwell just above the maximum"
	)

	driver.check(
		max_box.snapshot()["shift_cooldown_s"] == max_state.shift_cooldown_s,
		"giant-dwell refusal leaves the restored maximum dwell unchanged"
	)

	# An accepted maximum dwell counts down by exactly one tick, proving the cap
	# is not a value too large for fixed-step arithmetic.
	var count_box = GearboxScript.create(max_config)
	driver.check(count_box != null, "countdown probe creates")
	if count_box != null:
		var shifted = driver.step(count_box, driver.make_car(8.5))
		driver.check(shifted != null and shifted.has_event(), "countdown probe upshifts")
		if shifted != null:
			driver.check_close(
				shifted.state.shift_cooldown_s, GearboxScript.MAX_SHIFT_DWELL_S, 1e-12,
				"shift installs the configured maximum dwell"
			)
		var settled = driver.step(count_box, driver.make_car(8.5))
		driver.check(settled != null, "countdown second tick exists")
		if settled != null:
			driver.check(
				settled.state.shift_cooldown_s < GearboxScript.MAX_SHIFT_DWELL_S,
				"accepted maximum dwell counts down below its initial value"
			)
			driver.check_close(
				settled.state.shift_cooldown_s,
				GearboxScript.MAX_SHIFT_DWELL_S - GearboxScript.DT, 1e-9,
				"accepted maximum dwell decrements by one fixed tick"
			)


func run_restore_and_mirror(driver) -> void:
	var box = driver.fresh_gearbox()
	driver.check(box != null, "restore_and_mirror setup creates")
	if box == null:
		return

	var candidate = GearboxScript.GearboxState.new()
	candidate.gear_index = 3
	candidate.shift_cooldown_s = 0.2
	candidate.normalized_rpm = 0.7
	driver.check(candidate.is_valid(), "candidate pair state is globally valid")

	var car = driver.make_car(20.0)
	car.gear_index = 99
	var car_before: Dictionary = driver.snapshot_car(car)

	var repaired = box.restore_and_mirror(candidate, car)
	driver.check(repaired != null, "valid pair restores and mirrors")
	if repaired != null:
		driver.check_eq(int(repaired.gear_index), 3, "repaired copy publishes the candidate gear")
		repaired.gear_index = 7
	driver.check_eq(int(car.gear_index), 99, "success leaves the input car unchanged")
	driver.check(driver.snapshot_car(car) == car_before, "input car snapshot is unchanged on success")

	var committed: Dictionary = box.snapshot()
	driver.check_eq(int(committed["gear_index"]), 3, "canonical gear is committed")
	driver.check_close(
		float(committed["shift_cooldown_s"]), 0.2, 1e-12, "nonzero cooldown is restored"
	)
	driver.check_close(
		float(committed["normalized_rpm"]), 0.7, 1e-12, "nonzero rpm is restored"
	)
	candidate.gear_index = 8
	driver.check_eq(
		int(box.snapshot()["gear_index"]), 3,
		"committed state is a copy, not the candidate object"
	)
	candidate.gear_index = 3

	# A bad car refuses atomically: gearbox and input record both untouched.
	var baseline: Dictionary = box.snapshot()
	var nan_car = driver.make_car(20.0)
	nan_car.velocity_m_s = Vector2(NAN, 20.0)
	driver.check(box.restore_and_mirror(candidate, nan_car) == null, "nonfinite car is refused")
	driver.check(box.snapshot() == baseline, "bad-car refusal leaves the gearbox unchanged")
	driver.check(is_nan(nan_car.velocity_m_s.x), "bad-car refusal leaves the input car unchanged")

	# An invalid candidate also refuses atomically.
	var bad_gear = GearboxScript.GearboxState.new()
	bad_gear.gear_index = 99
	var finite_car = driver.make_car(20.0)
	var finite_before: Dictionary = driver.snapshot_car(finite_car)
	driver.check(box.restore_and_mirror(bad_gear, finite_car) == null, "invalid candidate state is refused")
	var over_dwell = GearboxScript.GearboxState.new()
	over_dwell.shift_cooldown_s = 1e16
	driver.check(box.restore_and_mirror(over_dwell, finite_car) == null, "giant dwell candidate is refused")
	driver.check(box.restore_and_mirror(null, finite_car) == null, "null candidate is refused")
	driver.check(box.snapshot() == baseline, "bad-candidate refusals leave the gearbox unchanged")
	driver.check(
		driver.snapshot_car(finite_car) == finite_before,
		"bad-candidate refusals leave the car unchanged"
	)

	# Stale or foreign proposals cannot influence either helper: mirror reads
	# the current canonical state, and restore_and_mirror publishes the
	# validated candidate rather than any retained proposal.
	var stale = driver.fresh_gearbox()
	var retained = driver.step(stale, driver.make_car(45.0))
	driver.check(
		retained != null and int(retained.gear_index) == 6,
		"stale-proposal setup reaches sixth gear"
	)
	for _index in range(30):
		driver.step(stale, driver.make_car(2.0))
	var foreign = driver.make_car(2.0)
	foreign.gear_index = 99
	var published = stale.mirror_gear(foreign)
	driver.check(published != null, "stale-proposal mirror succeeds")
	if published != null:
		driver.check_eq(
			int(published.gear_index), 1,
			"mirror follows the current canonical gear, not the retained proposal"
		)
	var republish_candidate = GearboxScript.GearboxState.new()
	republish_candidate.gear_index = 3
	republish_candidate.shift_cooldown_s = 0.1
	republish_candidate.normalized_rpm = 0.4
	var republished = stale.restore_and_mirror(republish_candidate, foreign)
	driver.check(republished != null, "restore_and_mirror succeeds after the stale proposal")
	if republished != null:
		driver.check_eq(
			int(republished.gear_index), int(republish_candidate.gear_index),
			"restore_and_mirror publishes the candidate gear, not a retained proposal"
		)
