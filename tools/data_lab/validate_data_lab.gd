extends SceneTree
## Headless black-box runner for the M0.2 typed-resource data lab.
##
## Run from an isolated project copy (tools/data_lab/run_validation.sh stages
## one and imports first):
##   godot --headless --fixed-fps 60 --path <project> \
##       --script res://tools/data_lab/validate_data_lab.gd
##
## Optional `--case=<id>` selects one case; the default runs every case.
## `--case=intentional_failure` always exits nonzero to prove the harness
## detects a failing assertion. Each case prints its own machine-readable
## result; the runner prints one DATA_LAB_RESULT line, CHECKS_TOTAL and
## CHECKS_FAILED lines, and quits with a controlled exit code.
##
## This exercises pure resource validation and .tres serialization only: no
## scene, body, physics query, clock, rendering, audio device, input routing,
## motor integration or gameplay claim. A parse/load failure appears in the
## engine log before this script runs; the runner treats engine SCRIPT ERROR /
## Parse Error lines as a distinct parse/load failure, never as an assertion
## pass.

const DriverScript = preload("res://tools/data_lab/data_lab_checks.gd")
const IdentityScript = preload("res://src/data/definition_identity.gd")
const HandlingScript = preload("res://src/data/handling_definition.gd")
const CarScript = preload("res://src/data/car_definition.gd")

const CASE_IDS := [
	"valid_in_memory_definition",
	"tres_round_trip",
	"enum_domain_controls",
	"handling_diagnostic_attribution",
	"deferred_fields_declaration",
	"scratch_reservation_control",
	"scratch_cleanup_controls",
	"malformed_identity_controls",
	"negative_and_nonfinite_physical_controls",
	"dimensional_bounds",
	"missing_handling_and_curve",
	"completeness_semantics",
	"curve_accessor_safety",
]

## Fixed basenames that earlier lab revisions wrote at `res://`. The validator
## only reads them; `run_validation.sh` populates distinct sentinels in its own
## fresh private stage before this case observes and re-checks their bytes.
const LEGACY_ROUNDTRIP_HANDLING_PATH := "res://data_lab_handling_roundtrip.tres"
const LEGACY_ROUNDTRIP_CAR_PATH := "res://data_lab_car_roundtrip.tres"
## Every validator run reserves its own scratch directory under `res://` so a
## direct execution cannot clobber files another process owns.
const SCRATCH_DIR_NAME_PREFIX := "data_lab_scratch_"
const SCRATCH_DIR_PREFIX := "res://" + SCRATCH_DIR_NAME_PREFIX
## The only file basenames this validator creates inside a reservation. Cleanup
## removes these after checking they are not directories; any other entry is
## retained and reported, never deleted or traversed.
const KNOWN_SCRATCH_FILE_NAMES := [
	"handling_roundtrip.tres",
	"car_roundtrip.tres",
	"bad_enum.tres",
	"owned.txt",
]

var _checks := 0
var _failures: Array[String] = []
var _measured: Dictionary = {}
var _finished := false
var _scratch_dirs: Array[String] = []
var _scratch_cleanup_reports: Array[String] = []


func _initialize() -> void:
	# Marker printed only when every const preload parsed. If a global class
	# failed to register, Godot emits SCRIPT ERROR before this line and the
	# runner reports a parse/load failure instead of an assertion result.
	print("DATA_LAB_STAGE preloads_resolved=1")
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
		"schema": "roadstorm.data_lab.validation.v1",
		"engine_version": Engine.get_version_info(),
		"cases": results.size(),
		"checks_total": _checks,
		"checks_failed": _failures.size(),
		"failed_cases": failed_cases,
		"case_results": results,
		"measured": _measured,
		"scratch_cleanup_reports": _scratch_cleanup_reports.duplicate(),
		"limitations": LIMITATIONS,
	}
	_finish(report)


func _requested_case() -> String:
	for argument in OS.get_cmdline_args():
		if argument.begins_with("--case="):
			return argument.substr(7)
	var from_environment := OS.get_environment("DATA_LAB_CASE")
	if from_environment != "":
		return from_environment
	return "all"


func _run_case(case_id: String) -> Dictionary:
	var driver := DataLabDriver.new()
	match case_id:
		"valid_in_memory_definition":
			_case_valid_in_memory_definition(driver)
		"tres_round_trip":
			_case_tres_round_trip(driver)
		"enum_domain_controls":
			_case_enum_domain_controls(driver)
		"handling_diagnostic_attribution":
			_case_handling_diagnostic_attribution(driver)
		"deferred_fields_declaration":
			_case_deferred_fields_declaration(driver)
		"scratch_reservation_control":
			_case_scratch_reservation_control(driver)
		"scratch_cleanup_controls":
			_case_scratch_cleanup_controls(driver)
		"malformed_identity_controls":
			_case_malformed_identity_controls(driver)
		"negative_and_nonfinite_physical_controls":
			_case_negative_and_nonfinite_physical_controls(driver)
		"dimensional_bounds":
			_case_dimensional_bounds(driver)
		"missing_handling_and_curve":
			_case_missing_handling_and_curve(driver)
		"completeness_semantics":
			_case_completeness_semantics(driver)
		"curve_accessor_safety":
			_case_curve_accessor_safety(driver)
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


# --- Cases ------------------------------------------------------------------


func _case_valid_in_memory_definition(driver: DataLabDriver) -> void:
	var handling = driver.valid_handling()
	driver.check_eq(handling.validate().size(), 0, "valid handling reports no diagnostics")
	driver.check(handling.is_valid(), "valid handling is_valid agrees")
	driver.check_eq(
		handling.identity_key(),
		"1.0.0/example.data_lab.car.handling@0.1.0",
		"handling identity key"
	)
	driver.check_eq(handling.status_name(), "EXAMPLE", "example handling status name")

	var car = driver.valid_car(handling)
	driver.check_eq(car.validate().size(), 0, "valid draft car reports no diagnostics")
	driver.check(not car.is_complete(), "draft car is not complete")
	driver.check_eq(car.completeness, CarScript.Completeness.DRAFT, "car completeness is DRAFT")
	driver.check(car.handling == handling, "car keeps its typed handling reference")
	driver.check_eq(
		car.handling.definition_id,
		car.definition_id + ".handling",
		"default fixture handling ID follows the documented <car_id>.handling derivation"
	)
	driver.check_eq(
		car.deferred_fields.size(),
		CarScript.DEFERRED_FIELDS_V1.size(),
		"draft car lists every v1 deferred field"
	)
	driver.check(
		car.deferred_fields.size() > 0,
		"deferred field list is explicit rather than implied"
	)

	var units := car.documented_units()
	driver.check_eq(units["length"], "m", "documented length unit")
	driver.check_eq(units["mass"], "kg", "documented mass unit")
	driver.check_eq(units["time"], "s", "documented time unit")
	driver.check_eq(units["angle"], "deg", "documented angle unit")
	var frame := car.documented_frame()
	driver.check_eq(frame["forward"], "-Z", "documented forward axis")
	driver.check_eq(frame["up"], "+Y", "documented up axis")
	driver.check_eq(
		frame["origin"],
		"ground_projection_of_axle_midpoint",
		"documented origin convention"
	)

	var fields := handling.to_motor_tuning_fields()
	for key in [
		"acceleration_curve",
		"braking_acceleration_m_s2",
		"drag_aerodynamic",
		"drag_rolling",
		"yaw_gain_grip",
		"max_yaw_rate_rad_s",
		"lateral_damping_grip_per_s",
		"reverse_trigger_speed_m_s",
		"reverse_hold_time_s",
		"reverse_acceleration_m_s2",
		"reverse_top_speed_m_s",
	]:
		driver.check(fields.has(key), "tuning projection exposes %s" % key)
	driver.check_eq(fields["braking_acceleration_m_s2"], 9.0, "tuning projection braking value")
	driver.check_eq(fields["max_yaw_rate_rad_s"], 2.5, "tuning projection yaw cap value")

	driver.check(
		IdentityScript.is_valid_definition_id("car.comet"),
		"stable ID grammar accepts a dotted lowercase ID"
	)
	driver.check(
		IdentityScript.is_valid_definition_id("fixture.handling.sweeper"),
		"stable ID grammar accepts a longer dotted ID"
	)
	driver.check(
		not IdentityScript.is_valid_definition_id("Comet"),
		"stable ID grammar rejects an uppercase ID"
	)
	driver.check(
		not IdentityScript.is_valid_definition_id("car..comet"),
		"stable ID grammar rejects an empty segment"
	)
	driver.check(
		IdentityScript.is_valid_revision("10.20.30"),
		"revision grammar accepts multi-digit components"
	)
	driver.check(
		not IdentityScript.is_valid_revision("01.0.0"),
		"revision grammar rejects leading zeros"
	)
	driver.check(
		not IdentityScript.is_valid_revision("1.0"),
		"revision grammar rejects a two-component revision"
	)

	driver.measure("deferred_field_count", car.deferred_fields.size())
	driver.measure("handling_curve_points", handling.get_acceleration_points().size())


func _case_tres_round_trip(driver: DataLabDriver) -> void:
	var handling = driver.valid_handling()
	var car = driver.valid_car(handling)
	var scratch := _reserve_scratch_dir()
	driver.check(scratch != "", "unique scratch directory reserved for the round trip")
	if scratch == "":
		driver.measure("roundtrip_handling_ok", false)
		driver.measure("roundtrip_car_ok", false)
		return
	var handling_path := scratch.path_join("handling_roundtrip.tres")
	var car_path := scratch.path_join("car_roundtrip.tres")
	driver.check_eq(
		driver.save_resource(handling, handling_path),
		OK,
		"handling .tres saves into reserved scratch"
	)
	driver.check_eq(
		driver.save_resource(car, car_path),
		OK,
		"car .tres saves into reserved scratch"
	)

	var loaded_handling = driver.load_resource(handling_path)
	driver.check(loaded_handling is HandlingDefinition, "loaded handling is a HandlingDefinition")
	if loaded_handling is HandlingDefinition:
		_assert_same_handling(driver, handling, loaded_handling)

	var loaded_car = driver.load_resource(car_path)
	driver.check(loaded_car is CarDefinition, "loaded car is a CarDefinition")
	if loaded_car is CarDefinition:
		_assert_same_car(driver, car, loaded_car)
		# A changed but still-parseable schema version must be detected by the
		# car comparator too; comparing only the physical fields would let it
		# through.
		var car_version_before: String = loaded_car.schema_version
		loaded_car.schema_version = "9.9.9"
		_assert_detects_car_alteration(
			driver, car, loaded_car, "altered car schema version"
		)
		loaded_car.schema_version = car_version_before
		if loaded_car.handling is HandlingDefinition:
			# The car `.tres` references the separately saved handling `.tres`
			# as an external resource; compare the reloaded contents in full, not
			# only their validity: a different valid ID, revision, schema version
			# or curve must fail this round trip.
			_assert_same_handling(driver, handling, loaded_car.handling)
			_assert_referenced_handling_controls(driver, handling, loaded_car)
		else:
			driver.check(false, "referenced handling is a HandlingDefinition")
		driver.check(
			loaded_car.handling != null and loaded_car.handling.is_valid(),
			"referenced handling survives the round trip and validates"
		)
		driver.check_eq(
			loaded_car.validate().size(),
			0,
			"loaded draft car still reports no diagnostics"
		)

	var rebound := driver.valid_car()
	if loaded_handling is HandlingDefinition:
		rebound.handling = loaded_handling
	driver.check(
		rebound.is_valid(),
		"rebinding a separately loaded handling resource keeps the car valid"
	)

	_cleanup_scratch_dirs()
	driver.check(not DirAccess.dir_exists_absolute(scratch), "round trip scratch reservation is removed")
	driver.measure("roundtrip_handling_ok", loaded_handling is HandlingDefinition)
	driver.measure("roundtrip_car_ok", loaded_car is CarDefinition)


## Deliberate-alteration controls: a changed but still-valid referenced
## handling ID, schema version or curve must be detected by
## `_assert_same_handling`. The old check only asked `is_valid()`, so all three
## alterations passed it; these controls would fail against that old behavior.
## Restores each field after proving detection. The handling is an external
## resource reference here, not an embedded subresource.
func _assert_referenced_handling_controls(
	driver: DataLabDriver,
	original: HandlingDefinition,
	loaded_car: CarDefinition
) -> void:
	var id_before := loaded_car.handling.definition_id
	loaded_car.handling.definition_id = "example.data_lab.altered"
	_assert_detects_alteration(
		driver, original, loaded_car.handling, "altered referenced handling ID"
	)
	loaded_car.handling.definition_id = id_before

	var acceleration_before := loaded_car.handling.acceleration_curve_accelerations_m_s2[1]
	loaded_car.handling.acceleration_curve_accelerations_m_s2[1] = 123.0
	_assert_detects_alteration(
		driver, original, loaded_car.handling, "altered referenced handling curve"
	)
	loaded_car.handling.acceleration_curve_accelerations_m_s2[1] = acceleration_before

	var version_before := loaded_car.handling.schema_version
	loaded_car.handling.schema_version = "9.9.9"
	_assert_detects_alteration(
		driver, original, loaded_car.handling, "altered referenced handling schema version"
	)
	loaded_car.handling.schema_version = version_before


func _assert_detects_alteration(
	driver: DataLabDriver,
	original: HandlingDefinition,
	altered: HandlingDefinition,
	label: String
) -> void:
	var checks_before := driver.checks
	var failures_before := driver.failures.size()
	_assert_same_handling(driver, original, altered)
	var detected := driver.failures.size() > failures_before
	# The expected mismatch diagnostics are consumed by the control itself.
	driver.failures.resize(failures_before)
	driver.checks = checks_before
	driver.check(detected, "%s is detected by the referenced handling comparison" % label)


func _assert_detects_car_alteration(
	driver: DataLabDriver,
	original: CarDefinition,
	altered: CarDefinition,
	label: String
) -> void:
	var checks_before := driver.checks
	var failures_before := driver.failures.size()
	_assert_same_car(driver, original, altered)
	var detected := driver.failures.size() > failures_before
	# The expected mismatch diagnostics are consumed by the control itself.
	driver.failures.resize(failures_before)
	driver.checks = checks_before
	driver.check(detected, "%s is detected by the car comparison" % label)


func _assert_same_handling(driver, expected: HandlingDefinition, actual: HandlingDefinition) -> void:
	driver.check_eq(actual.definition_id, expected.definition_id, "round trip handling ID")
	driver.check_eq(
		actual.schema_version, expected.schema_version, "round trip handling schema version"
	)
	driver.check_eq(actual.revision, expected.revision, "round trip handling revision")
	driver.check_eq(actual.display_name, expected.display_name, "round trip handling display name")
	driver.check_eq(actual.status, expected.status, "round trip handling status")
	driver.check_eq(actual.notes, expected.notes, "round trip handling notes")
	driver.check_eq(
		actual.acceleration_curve_speeds_m_s.size(),
		expected.acceleration_curve_speeds_m_s.size(),
		"round trip curve speed count"
	)
	driver.check_eq(
		actual.acceleration_curve_accelerations_m_s2.size(),
		expected.acceleration_curve_accelerations_m_s2.size(),
		"round trip curve acceleration count"
	)
	for index in range(mini(
		actual.acceleration_curve_speeds_m_s.size(),
		expected.acceleration_curve_speeds_m_s.size()
	)):
		driver.check_float_eq(
			actual.acceleration_curve_speeds_m_s[index],
			expected.acceleration_curve_speeds_m_s[index],
			1e-9,
			"round trip curve point %d speed" % index
		)
		driver.check_float_eq(
			actual.acceleration_curve_accelerations_m_s2[index],
			expected.acceleration_curve_accelerations_m_s2[index],
			1e-9,
			"round trip curve point %d acceleration" % index
		)
	driver.check_float_eq(
		actual.braking_acceleration_m_s2,
		expected.braking_acceleration_m_s2,
		1e-9,
		"round trip braking acceleration"
	)
	driver.check_float_eq(
		actual.drag_aerodynamic, expected.drag_aerodynamic, 1e-9, "round trip aerodynamic drag"
	)
	driver.check_float_eq(
		actual.drag_rolling, expected.drag_rolling, 1e-9, "round trip rolling drag"
	)
	driver.check_float_eq(
		actual.yaw_gain_grip, expected.yaw_gain_grip, 1e-9, "round trip grip yaw gain"
	)
	driver.check_eq(
		actual.max_yaw_rate_rad_s, expected.max_yaw_rate_rad_s, "round trip yaw-rate cap"
	)
	driver.check_float_eq(
		actual.lateral_damping_grip_per_s,
		expected.lateral_damping_grip_per_s,
		1e-9,
		"round trip lateral damping"
	)
	driver.check_float_eq(
		actual.reverse_trigger_speed_m_s,
		expected.reverse_trigger_speed_m_s,
		1e-9,
		"round trip reverse trigger"
	)
	driver.check_float_eq(
		actual.reverse_hold_time_s, expected.reverse_hold_time_s, 1e-9, "round trip reverse hold"
	)
	driver.check_float_eq(
		actual.reverse_acceleration_m_s2,
		expected.reverse_acceleration_m_s2,
		1e-9,
		"round trip reverse acceleration"
	)
	driver.check_float_eq(
		actual.reverse_top_speed_m_s,
		expected.reverse_top_speed_m_s,
		1e-9,
		"round trip reverse top speed"
	)


func _assert_same_car(driver, expected: CarDefinition, actual: CarDefinition) -> void:
	driver.check_eq(actual.definition_id, expected.definition_id, "round trip car ID")
	driver.check_eq(
		actual.schema_version, expected.schema_version, "round trip car schema version"
	)
	driver.check_eq(actual.revision, expected.revision, "round trip car revision")
	driver.check_eq(actual.display_name, expected.display_name, "round trip car display name")
	driver.check_eq(actual.status, expected.status, "round trip car status")
	driver.check_float_eq(actual.length_m, expected.length_m, 1e-9, "round trip length")
	driver.check_float_eq(actual.width_m, expected.width_m, 1e-9, "round trip width")
	driver.check_float_eq(actual.height_m, expected.height_m, 1e-9, "round trip height")
	_check_optional_number(driver, actual.wheelbase_m, expected.wheelbase_m, "round trip wheelbase")
	_check_optional_number(
		driver, actual.ground_clearance_m, expected.ground_clearance_m, "round trip ground clearance"
	)
	_check_optional_number(
		driver, actual.jump_envelope_m, expected.jump_envelope_m, "round trip jump envelope"
	)
	driver.check_float_eq(actual.mass_kg, expected.mass_kg, 1e-9, "round trip intact mass")
	driver.check_eq(
		actual.contact_proxy_shape, expected.contact_proxy_shape, "round trip contact proxy shape"
	)
	driver.check_eq(actual.contact_roof, expected.contact_roof, "round trip contact roof")
	driver.check_eq(
		actual.contact_underside, expected.contact_underside, "round trip contact underside"
	)
	driver.check_eq(actual.completeness, expected.completeness, "round trip completeness")
	driver.check_eq(actual.completeness_note, expected.completeness_note, "round trip completeness note")
	driver.check_eq(
		actual.deferred_fields.size(), expected.deferred_fields.size(), "round trip deferred count"
	)
	for index in range(mini(actual.deferred_fields.size(), expected.deferred_fields.size())):
		driver.check_eq(
			actual.deferred_fields[index],
			expected.deferred_fields[index],
			"round trip deferred field %d" % index
		)
	driver.check(
		actual.handling is HandlingDefinition, "round trip referenced handling type"
	)


func _check_optional_number(driver, actual: Variant, expected: Variant, label: String) -> void:
	if expected == null:
		driver.check(actual == null, "%s stays undetermined (null)" % label)
		return
	driver.check(actual != null, "%s remains authored after save/load" % label)
	if actual != null and expected != null:
		driver.check_float_eq(float(actual), float(expected), 1e-9, label)


func _case_malformed_identity_controls(driver: DataLabDriver) -> void:
	var unsupported := driver.valid_car()
	unsupported.schema_version = "2.0.0"
	driver.expect_diagnostic(
		"schema_version: unsupported '2.0.0'",
		unsupported.validate(),
		"unsupported schema version"
	)
	driver.check(not unsupported.is_valid(), "unsupported schema version is invalid")

	var bad_id := driver.valid_car()
	bad_id.definition_id = "Bad ID"
	driver.expect_diagnostic(
		"definition_id: malformed 'Bad ID'", bad_id.validate(), "uppercase/space ID"
	)

	var leading_digit := driver.valid_car()
	leading_digit.definition_id = "1car"
	driver.expect_diagnostic(
		"definition_id: malformed '1car'", leading_digit.validate(), "leading-digit ID"
	)

	var bad_revision := driver.valid_car()
	bad_revision.revision = "1.0"
	driver.expect_diagnostic(
		"revision: malformed '1.0'", bad_revision.validate(), "two-component revision"
	)

	var zero_revision := driver.valid_car()
	zero_revision.revision = "01.0.0"
	driver.expect_diagnostic(
		"revision: malformed '01.0.0'", zero_revision.validate(), "leading-zero revision"
	)

	# Whole-string matching: `$` may stop before a final line feed, so the
	# validator must reject IDs/revisions carrying one rather than embed it in
	# identity_key(). These are grammar checks, not loosened stable-ID rules.
	driver.check(
		not IdentityScript.is_valid_definition_id("car.comet\n"),
		"stable ID grammar rejects a trailing newline"
	)
	driver.check(
		not IdentityScript.is_valid_definition_id("car.comet "),
		"stable ID grammar rejects a trailing space"
	)
	driver.check(
		not IdentityScript.is_valid_definition_id("car.comet suffix"),
		"stable ID grammar rejects a trailing suffix"
	)
	driver.check(
		not IdentityScript.is_valid_revision("1.0.0\n"),
		"revision grammar rejects a trailing newline"
	)
	driver.check(
		not IdentityScript.is_valid_revision("v1.0.0"),
		"revision grammar rejects a non-numeric prefix"
	)

	var newline_id := driver.valid_car()
	newline_id.definition_id = "car.comet\n"
	driver.expect_diagnostic(
		"definition_id: malformed", newline_id.validate(), "ID with a trailing newline"
	)
	var newline_revision := driver.valid_car()
	newline_revision.revision = "1.0.0\n"
	driver.expect_diagnostic(
		"revision: malformed", newline_revision.validate(), "revision with a trailing newline"
	)

	var no_display := driver.valid_car()
	no_display.display_name = ""
	driver.expect_diagnostic(
		"display_name: empty", no_display.validate(), "empty display name"
	)

	# The car must run the referenced handling's full validation, including its
	# identity fields, not only the physical subset.
	var bad_handling_id := driver.valid_car()
	bad_handling_id.handling.definition_id = "Bad Handling"
	driver.expect_diagnostic(
		"handling.definition_id: malformed 'Bad Handling'",
		bad_handling_id.validate(),
		"referenced handling with a malformed ID"
	)
	driver.check(not bad_handling_id.is_valid(), "car rejects a malformed handling ID")

	var bad_handling_version := driver.valid_car()
	bad_handling_version.handling.schema_version = "9.9.9"
	driver.expect_diagnostic(
		"handling.schema_version: unsupported '9.9.9'",
		bad_handling_version.validate(),
		"referenced handling with an unsupported schema version"
	)
	driver.check(not bad_handling_version.is_valid(), "car rejects an unsupported handling version")

	var bad_handling_revision := driver.valid_car()
	bad_handling_revision.handling.revision = "1.0"
	driver.expect_diagnostic(
		"handling.revision: malformed '1.0'",
		bad_handling_revision.validate(),
		"referenced handling with a malformed revision"
	)


func _case_negative_and_nonfinite_physical_controls(driver: DataLabDriver) -> void:
	var braking := driver.valid_handling()
	braking.braking_acceleration_m_s2 = -1.0
	driver.expect_diagnostic(
		"handling.braking_acceleration_m_s2: negative",
		braking.validate(),
		"negative braking acceleration"
	)

	var drag_aero := driver.valid_handling()
	drag_aero.drag_aerodynamic = -0.1
	driver.expect_diagnostic(
		"handling.drag_aerodynamic: negative",
		drag_aero.validate(),
		"negative aerodynamic drag"
	)

	var drag_roll := driver.valid_handling()
	drag_roll.drag_rolling = NAN
	driver.expect_diagnostic(
		"handling.drag_rolling: nonfinite",
		drag_roll.validate(),
		"nonfinite rolling drag"
	)

	var yaw := driver.valid_handling()
	yaw.yaw_gain_grip = -0.2
	driver.expect_diagnostic(
		"handling.yaw_gain_grip: negative", yaw.validate(), "negative grip yaw gain"
	)

	var yaw_cap := driver.valid_handling()
	yaw_cap.max_yaw_rate_rad_s = -INF
	driver.expect_diagnostic(
		"handling.max_yaw_rate_rad_s: negative infinity",
		yaw_cap.validate(),
		"negative-infinity yaw cap"
	)

	var damping := driver.valid_handling()
	damping.lateral_damping_grip_per_s = -1.0
	driver.expect_diagnostic(
		"handling.lateral_damping_grip_per_s: negative",
		damping.validate(),
		"negative lateral damping"
	)

	var trigger := driver.valid_handling()
	trigger.reverse_trigger_speed_m_s = 1.5
	driver.expect_diagnostic(
		"handling.reverse_trigger_speed_m_s: 1.5 exceeds the docs/GAME_DESIGN.md:11 ceiling",
		trigger.validate(),
		"reverse trigger above the design ceiling"
	)

	var hold := driver.valid_handling()
	hold.reverse_hold_time_s = 0.1
	driver.expect_diagnostic(
		"handling.reverse_hold_time_s: 0.1 is below the docs/GAME_DESIGN.md:11 minimum",
		hold.validate(),
		"reverse hold below the design minimum"
	)

	var reverse := driver.valid_handling()
	reverse.reverse_acceleration_m_s2 = 4.0
	reverse.reverse_top_speed_m_s = 0.0
	driver.expect_diagnostic(
		"handling.reverse_top_speed_m_s: reverse drive with acceleration",
		reverse.validate(),
		"reverse drive without a positive top speed"
	)

	var negative_point := driver.valid_handling()
	negative_point.acceleration_curve_accelerations_m_s2[1] = -2.0
	driver.expect_diagnostic(
		"handling.acceleration_curve[1].acceleration_m_s2: negative",
		negative_point.validate(),
		"negative curve acceleration"
	)

	var negative_speed := driver.valid_handling()
	negative_speed.acceleration_curve_speeds_m_s[0] = -1.0
	driver.expect_diagnostic(
		"handling.acceleration_curve[0].speed_m_s: negative",
		negative_speed.validate(),
		"negative curve speed"
	)

	var nonfinite_point := driver.valid_handling()
	nonfinite_point.acceleration_curve_speeds_m_s[1] = NAN
	driver.expect_diagnostic(
		"handling.acceleration_curve[1]: nonfinite",
		nonfinite_point.validate(),
		"nonfinite curve speed"
	)

	var unordered := driver.valid_handling()
	unordered.acceleration_curve_speeds_m_s[2] = 18.0
	driver.expect_diagnostic(
		"does not strictly exceed previous speed",
		unordered.validate(),
		"non-increasing curve speeds"
	)

	var empty_curve := driver.valid_handling()
	empty_curve.clear_acceleration_curve()
	driver.expect_diagnostic(
		"handling.acceleration_curve: empty",
		empty_curve.validate(),
		"empty acceleration curve"
	)
	driver.check(not empty_curve.is_valid(), "empty curve definition is invalid")


func _case_dimensional_bounds(driver: DataLabDriver) -> void:
	var short := driver.valid_car()
	short.length_m = 3.0
	driver.expect_diagnostic(
		"dimensions.length_m: 3.0 is below the documented envelope minimum",
		short.validate(),
		"short length"
	)

	var long := driver.valid_car()
	long.length_m = 5.0
	driver.expect_diagnostic(
		"dimensions.length_m: 5.0 is above the documented envelope maximum",
		long.validate(),
		"long length"
	)

	var narrow := driver.valid_car()
	narrow.width_m = 1.5
	driver.expect_diagnostic(
		"dimensions.width_m: 1.5 is below the documented envelope minimum",
		narrow.validate(),
		"narrow width"
	)

	var wide := driver.valid_car()
	wide.width_m = 2.5
	driver.expect_diagnostic(
		"dimensions.width_m: 2.5 is above the documented envelope maximum",
		wide.validate(),
		"wide width"
	)

	var low := driver.valid_car()
	low.height_m = 0.9
	driver.expect_diagnostic(
		"dimensions.height_m: 0.9 is below the documented envelope minimum",
		low.validate(),
		"low height"
	)

	var tall := driver.valid_car()
	tall.height_m = 2.0
	driver.expect_diagnostic(
		"dimensions.height_m: 2.0 is above the documented envelope maximum",
		tall.validate(),
		"tall height"
	)

	var zero_wheelbase := driver.valid_car()
	zero_wheelbase.wheelbase_m = 0.0
	driver.expect_diagnostic(
		"dimensions.wheelbase_m: non-positive",
		zero_wheelbase.validate(),
		"zero wheelbase"
	)

	var long_wheelbase := driver.valid_car()
	long_wheelbase.wheelbase_m = 4.5
	driver.expect_diagnostic(
		"dimensions.wheelbase_m: 4.5 exceeds length_m",
		long_wheelbase.validate(),
		"wheelbase longer than the car"
	)

	var negative_clearance := driver.valid_car()
	negative_clearance.ground_clearance_m = -0.05
	driver.expect_diagnostic(
		"dimensions.ground_clearance_m: negative",
		negative_clearance.validate(),
		"negative ground clearance"
	)

	var tall_clearance := driver.valid_car()
	tall_clearance.ground_clearance_m = 1.5
	driver.expect_diagnostic(
		"dimensions.ground_clearance_m: 1.5 exceeds height_m",
		tall_clearance.validate(),
		"ground clearance above the roof"
	)

	var negative_jump := driver.valid_car()
	negative_jump.jump_envelope_m = -0.1
	driver.expect_diagnostic(
		"dimensions.jump_envelope_m: negative",
		negative_jump.validate(),
		"negative jump envelope"
	)

	var zero_mass := driver.valid_car()
	zero_mass.mass_kg = 0.0
	driver.expect_diagnostic("mass_kg: non-positive", zero_mass.validate(), "zero mass")

	var nan_mass := driver.valid_car()
	nan_mass.mass_kg = NAN
	driver.expect_diagnostic("mass_kg: nonfinite", nan_mass.validate(), "nonfinite mass")

	var edge := driver.valid_car()
	edge.length_m = CarScript.MIN_LENGTH_M
	edge.width_m = CarScript.MIN_WIDTH_M
	edge.height_m = CarScript.MIN_HEIGHT_M
	edge.wheelbase_m = CarScript.MIN_LENGTH_M
	edge.ground_clearance_m = CarScript.MIN_HEIGHT_M
	edge.jump_envelope_m = 0.0
	driver.check(edge.is_valid(), "inclusive documented envelope boundaries are accepted")


func _case_missing_handling_and_curve(driver: DataLabDriver) -> void:
	var no_handling := driver.valid_car()
	no_handling.handling = null
	driver.expect_diagnostic(
		"handling: missing typed handling reference",
		no_handling.validate(),
		"missing handling reference"
	)
	driver.check(not no_handling.is_valid(), "car without handling is invalid")

	var empty_handling := HandlingDefinition.new()
	empty_handling.definition_id = "example.data_lab.empty_handling"
	empty_handling.display_name = "Data Lab Empty Handling"
	var with_empty := driver.valid_car(empty_handling)
	driver.expect_diagnostic(
		"handling.acceleration_curve: empty",
		with_empty.validate(),
		"referenced handling with an empty curve"
	)

	var minimal := HandlingDefinition.new()
	minimal.definition_id = "example.data_lab.minimal_handling"
	minimal.display_name = "Data Lab Minimal Handling"
	minimal.set_acceleration_points([HandlingDefinition.AccelerationPoint.make(0.0, 5.0)])
	driver.check(minimal.is_valid(), "single-point authored curve with inert defaults validates")
	var with_minimal := driver.valid_car(minimal)
	driver.check(with_minimal.is_valid(), "car accepts a minimal valid handling reference")


func _case_completeness_semantics(driver: DataLabDriver) -> void:
	var no_note := driver.valid_car()
	no_note.completeness_note = "   "
	driver.expect_diagnostic(
		"completeness_note: required when completeness is draft or incomplete",
		no_note.validate(),
		"draft without a completion note"
	)

	var no_deferred := driver.valid_car()
	no_deferred.deferred_fields = PackedStringArray()
	driver.expect_diagnostic(
		"deferred_fields: required when completeness is draft or incomplete",
		no_deferred.validate(),
		"draft without declared deferred fields"
	)

	var complete_but_deferred := driver.valid_car()
	complete_but_deferred.completeness = CarScript.Completeness.COMPLETE
	driver.expect_diagnostic(
		"completeness: COMPLETE cannot be claimed by this M0.2 partial slice",
		complete_but_deferred.validate(),
		"COMPLETE car in the partial slice"
	)
	driver.expect_diagnostic(
		"deferred_fields: empty required when completeness is complete",
		complete_but_deferred.validate(),
		"complete car that still lists deferred fields"
	)
	driver.check(not complete_but_deferred.is_complete(), "invalid COMPLETE never reports completion")

	var empty_entry := driver.valid_car()
	empty_entry.deferred_fields = PackedStringArray([""])
	driver.expect_diagnostic(
		"deferred_fields: blank or whitespace-only entry at index 0",
		empty_entry.validate(),
		"blank deferred-field entry"
	)

	var incomplete := driver.valid_car()
	incomplete.completeness = CarScript.Completeness.INCOMPLETE
	driver.check(incomplete.is_valid(), "declared incomplete car with note and gaps validates")

	# Even a cleared deferred list cannot claim COMPLETE in this partial slice:
	# DEFERRED_FIELDS_V1 are not representable here yet.
	var false_complete := driver.valid_car()
	false_complete.completeness = CarScript.Completeness.COMPLETE
	false_complete.deferred_fields = PackedStringArray()
	false_complete.completeness_note = ""
	driver.expect_diagnostic(
		"completeness: COMPLETE cannot be claimed by this M0.2 partial slice",
		false_complete.validate(),
		"COMPLETE with an empty deferred list"
	)
	driver.check(not false_complete.is_valid(), "partial slice rejects a false COMPLETE")
	driver.check(not false_complete.is_complete(), "false COMPLETE never reports completion")


func _case_enum_domain_controls(driver: DataLabDriver) -> void:
	var bad_status := driver.valid_car()
	bad_status.status = 99
	driver.expect_diagnostic(
		"status: out-of-range value 99", bad_status.validate(), "out-of-range status"
	)
	driver.check(not bad_status.is_valid(), "out-of-range status is invalid")
	driver.check_eq(bad_status.status_name(), "INVALID", "invalid status_name stays safe")

	var negative_status := driver.valid_car()
	negative_status.status = -1
	driver.expect_diagnostic(
		"status: out-of-range value -1", negative_status.validate(), "negative status"
	)
	driver.check_eq(negative_status.status_name(), "INVALID", "negative status_name stays safe")

	var past_last_status := driver.valid_car()
	past_last_status.status = IdentityScript.Status.size()
	driver.expect_diagnostic(
		"status: out-of-range value 5", past_last_status.validate(), "status past the last member"
	)

	# The base identity validator owns status for every subclass.
	var bad_handling_status := driver.valid_handling()
	bad_handling_status.status = 99
	driver.expect_diagnostic(
		"status: out-of-range value 99",
		bad_handling_status.validate(),
		"handling with out-of-range status"
	)
	driver.check(not bad_handling_status.is_valid(), "handling with out-of-range status is invalid")

	var bad_shape := driver.valid_car()
	bad_shape.contact_proxy_shape = 99
	driver.expect_diagnostic(
		"contact_proxy_shape: out-of-range value 99",
		bad_shape.validate(),
		"out-of-range contact proxy shape"
	)
	driver.check(not bad_shape.is_valid(), "out-of-range contact proxy shape is invalid")

	var negative_shape := driver.valid_car()
	negative_shape.contact_proxy_shape = -1
	driver.expect_diagnostic(
		"contact_proxy_shape: out-of-range value -1",
		negative_shape.validate(),
		"negative contact proxy shape"
	)

	var bad_completeness := driver.valid_car()
	bad_completeness.completeness = 99
	driver.expect_diagnostic(
		"completeness: out-of-range value 99",
		bad_completeness.validate(),
		"out-of-range completeness"
	)
	driver.check(not bad_completeness.is_valid(), "out-of-range completeness is invalid")
	driver.check(
		not bad_completeness.is_complete(), "out-of-range completeness never claims completion"
	)

	var negative_completeness := driver.valid_car()
	negative_completeness.completeness = -1
	driver.expect_diagnostic(
		"completeness: out-of-range value -1",
		negative_completeness.validate(),
		"negative completeness"
	)

	# Malformed serialized input: a hand-authored `.tres` carrying
	# out-of-range integer enum values must load and be rejected.
	var scratch := _reserve_scratch_dir()
	driver.check(scratch != "", "unique scratch directory reserved for malformed .tres input")
	if scratch != "":
		var bad_path := scratch.path_join("bad_enum.tres")
		driver.check(_write_text_file(bad_path, _bad_enum_tres()), "malformed .tres fixture written")
		var loaded = ResourceLoader.load(bad_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		driver.check(loaded is CarDefinition, "malformed .tres loads as a CarDefinition")
		if loaded is CarDefinition:
			driver.check_eq(
				loaded.status, 99, "serialized status preserves the authored out-of-range value"
			)
			driver.check_eq(
				loaded.contact_proxy_shape,
				99,
				"serialized shape preserves the authored out-of-range value"
			)
			driver.check_eq(
				loaded.completeness,
				99,
				"serialized completeness preserves the authored out-of-range value"
			)
			driver.expect_diagnostic(
				"status: out-of-range value 99", loaded.validate(), "serialized out-of-range status"
			)
			driver.expect_diagnostic(
				"contact_proxy_shape: out-of-range value 99",
				loaded.validate(),
				"serialized out-of-range contact shape"
			)
			driver.expect_diagnostic(
				"completeness: out-of-range value 99",
				loaded.validate(),
				"serialized out-of-range completeness"
			)
			driver.check(not loaded.is_valid(), "serialized out-of-range enums are invalid")
			driver.check_eq(loaded.status_name(), "INVALID", "serialized invalid status_name stays safe")
		_cleanup_scratch_dirs()


func _bad_enum_tres() -> String:
	var lines := PackedStringArray([
		"[gd_resource type=\"Resource\" script_class=\"CarDefinition\" load_steps=2 format=3]",
		"",
		"[ext_resource type=\"Script\" path=\"res://src/data/car_definition.gd\" id=\"1\"]",
		"",
		"[resource]",
		"script = ExtResource(\"1\")",
		"schema_version = \"1.0.0\"",
		"definition_id = \"example.data_lab.bad_enum\"",
		"revision = \"0.1.0\"",
		"display_name = \"Data Lab Bad Enum\"",
		"status = 99",
		"length_m = 4.2",
		"width_m = 1.9",
		"height_m = 1.3",
		"mass_kg = 1250.0",
		"contact_proxy_shape = 99",
		"completeness = 99",
	])
	return "\n".join(lines) + "\n"


func _case_handling_diagnostic_attribution(driver: DataLabDriver) -> void:
	# The car and its referenced handling can carry the same bad ID; the two
	# diagnostics must remain distinguishable by field path.
	var shared_bad_id := driver.valid_car()
	shared_bad_id.definition_id = "Bad Shared"
	shared_bad_id.handling.definition_id = "Bad Shared"
	var shared_diagnostics := shared_bad_id.validate()
	driver.expect_diagnostic(
		"definition_id: malformed 'Bad Shared'",
		shared_diagnostics,
		"car's own shared bad ID"
	)
	driver.expect_diagnostic(
		"handling.definition_id: malformed 'Bad Shared'",
		shared_diagnostics,
		"referenced handling's shared bad ID"
	)
	var own_identity := 0
	var nested_identity := 0
	for entry in shared_diagnostics:
		if entry.begins_with("handling.definition_id:"):
			nested_identity += 1
		elif entry.begins_with("definition_id:"):
			own_identity += 1
	driver.check_eq(own_identity, 1, "exactly one car-level identity diagnostic")
	driver.check_eq(nested_identity, 1, "exactly one handling-level identity diagnostic")

	var bad_status := driver.valid_car()
	bad_status.handling.status = 99
	driver.expect_diagnostic(
		"handling.status: out-of-range value 99",
		bad_status.validate(),
		"referenced handling status attribution"
	)

	var no_display := driver.valid_car()
	no_display.handling.display_name = ""
	driver.expect_diagnostic(
		"handling.display_name: empty",
		no_display.validate(),
		"referenced handling display-name attribution"
	)

	var bad_schema := driver.valid_car()
	bad_schema.handling.schema_version = "9.9.9"
	driver.expect_diagnostic(
		"handling.schema_version: unsupported '9.9.9'",
		bad_schema.validate(),
		"referenced handling schema-version attribution"
	)

	var bad_revision := driver.valid_car()
	bad_revision.handling.revision = "1.0"
	driver.expect_diagnostic(
		"handling.revision: malformed '1.0'",
		bad_revision.validate(),
		"referenced handling revision attribution"
	)

	# Physical handling diagnostics already carry the prefix; they pass through
	# exactly once rather than being doubled.
	var negative_braking := driver.valid_car()
	negative_braking.handling.braking_acceleration_m_s2 = -1.0
	var physical := negative_braking.validate()
	driver.expect_diagnostic(
		"handling.braking_acceleration_m_s2: negative",
		physical,
		"referenced handling physical diagnostic"
	)
	var physical_count := 0
	for entry in physical:
		if "handling.braking_acceleration_m_s2: negative" in entry:
			physical_count += 1
	driver.check_eq(physical_count, 1, "physical handling diagnostic is reported exactly once")


func _case_deferred_fields_declaration(driver: DataLabDriver) -> void:
	var arbitrary := driver.valid_car()
	arbitrary.deferred_fields = PackedStringArray(["todo"])
	driver.expect_diagnostic(
		"deferred_fields: missing 13 required DEFERRED_FIELDS_V1 path(s)",
		arbitrary.validate(),
		"arbitrary deferred list"
	)
	driver.check(not arbitrary.is_valid(), "arbitrary deferred list is invalid")

	var missing_one: PackedStringArray = []
	for index in range(CarScript.DEFERRED_FIELDS_V1.size() - 1):
		missing_one.append(CarScript.DEFERRED_FIELDS_V1[index])
	var missing := driver.valid_car()
	missing.deferred_fields = missing_one
	driver.expect_diagnostic(
		"deferred_fields: missing 1 required DEFERRED_FIELDS_V1 path(s): handling.surfaces",
		missing.validate(),
		"one-field-missing deferred list"
	)

	var duplicate := driver.valid_car()
	var duplicate_fields: PackedStringArray = duplicate.deferred_fields.duplicate()
	duplicate_fields.append(duplicate_fields[0])
	duplicate.deferred_fields = duplicate_fields
	driver.expect_diagnostic(
		"deferred_fields: duplicate entry 'presentation.mesh_id'",
		duplicate.validate(),
		"duplicate deferred entry"
	)

	# Full required declaration plus two malformed extras: both blank forms
	# must be refused while the nonblank future extension still validates.
	var blank := driver.valid_car()
	var blank_fields: PackedStringArray = blank.deferred_fields.duplicate()
	blank_fields.append("")
	blank_fields.append("   \t")
	blank.deferred_fields = blank_fields
	driver.expect_diagnostic(
		"deferred_fields: blank or whitespace-only entry at index 13",
		blank.validate(),
		"empty deferred entry"
	)
	driver.expect_diagnostic(
		"deferred_fields: blank or whitespace-only entry at index 14",
		blank.validate(),
		"whitespace-only deferred entry"
	)
	driver.check(not blank.is_valid(), "blank deferred entries are refused")

	# Surrounding whitespace is malformed rather than silently stripped: the
	# exact spelling is required, and the padded entry must not count toward
	# its required v1 slot.
	var padded := driver.valid_car()
	var padded_fields: PackedStringArray = padded.deferred_fields.duplicate()
	padded_fields[0] = "  presentation.mesh_id\t"
	padded.deferred_fields = padded_fields
	driver.expect_diagnostic(
		"deferred_fields: entry at index 0 carries surrounding whitespace '  presentation.mesh_id\t'",
		padded.validate(),
		"padded deferred entry"
	)
	driver.expect_diagnostic(
		"deferred_fields: missing 1 required DEFERRED_FIELDS_V1 path(s): presentation.mesh_id",
		padded.validate(),
		"padded deferred entry does not satisfy its required path"
	)
	driver.check(not padded.is_valid(), "padded deferred entry is refused")

	var full := driver.valid_car()
	driver.check(full.is_valid(), "full v1 deferred declaration validates")
	driver.check_eq(
		full.deferred_fields.size(),
		CarScript.DEFERRED_FIELDS_V1.size(),
		"full declaration keeps every v1 path"
	)

	var extended := driver.valid_car()
	var extended_fields: PackedStringArray = extended.deferred_fields.duplicate()
	extended_fields.append("future.slice.field")
	extended.deferred_fields = extended_fields
	driver.check(
		extended.is_valid(), "full declaration plus a later-slice gap validates"
	)


func _case_scratch_reservation_control(driver: DataLabDriver) -> void:
	# This validator is read-only at the legacy fixed basenames. The shell
	# runner populates distinct sentinels in its own fresh private stage before
	# this case runs; a direct execution without externally prepopulated
	# sentinels must fail here rather than silently claim preservation coverage.
	var handling_present := FileAccess.file_exists(LEGACY_ROUNDTRIP_HANDLING_PATH)
	var car_present := FileAccess.file_exists(LEGACY_ROUNDTRIP_CAR_PATH)
	driver.check(handling_present, "preexisting handling sentinel is present at the fixed path")
	driver.check(car_present, "preexisting car sentinel is present at the fixed path")
	if not handling_present or not car_present:
		return
	var expected_handling := _read_bytes(LEGACY_ROUNDTRIP_HANDLING_PATH)
	var expected_car := _read_bytes(LEGACY_ROUNDTRIP_CAR_PATH)

	var first := _reserve_scratch_dir()
	driver.check(first != "", "first unique scratch reservation succeeds")
	var second := _reserve_scratch_dir()
	driver.check(
		second != "" and second != first,
		"each validator run reserves a distinct scratch directory"
	)
	# Put a file inside the first reservation: cleanup must remove the
	# reservation including its contents, never the fixed basenames.
	if first != "":
		var owned_file := first.path_join("owned.txt")
		var writer := FileAccess.open(owned_file, FileAccess.WRITE)
		if writer != null:
			writer.store_string("reserved scratch content")
			writer.close()
		driver.check(
			FileAccess.file_exists(owned_file),
			"reservation owns its scratch content"
		)

	_cleanup_scratch_dirs()
	for path in [first, second]:
		if path != "":
			driver.check(
				not DirAccess.dir_exists_absolute(path),
				"cleanup removes only reserved scratch %s" % path.get_file()
			)

	var actual_handling := _read_bytes(LEGACY_ROUNDTRIP_HANDLING_PATH)
	var actual_car := _read_bytes(LEGACY_ROUNDTRIP_CAR_PATH)
	driver.check(
		actual_handling == expected_handling,
		"fixed handling roundtrip path stays byte-identical (actual %d bytes, expected %d)"
		% [actual_handling.size(), expected_handling.size()]
	)
	driver.check(
		actual_car == expected_car,
		"fixed car roundtrip path stays byte-identical (actual %d bytes, expected %d)"
		% [actual_car.size(), expected_car.size()]
	)


## Focused controls for the known-output-only cleanup policy: a reservation
## holding only files this validator created is emptied and removed; unrelated,
## nested and hidden entries are retained, reported and left untouched.
func _case_scratch_cleanup_controls(driver: DataLabDriver) -> void:
	var expected_handling := _read_bytes(LEGACY_ROUNDTRIP_HANDLING_PATH)
	var expected_car := _read_bytes(LEGACY_ROUNDTRIP_CAR_PATH)
	var reports_before := _scratch_cleanup_reports.size()

	var known := _reserve_scratch_dir()
	driver.check(known != "", "known-output reservation succeeds")
	if known != "":
		driver.check(_write_text_file(known.path_join("owned.txt"), "known output"), "known output written")

	var unexpected := _reserve_scratch_dir()
	driver.check(unexpected != "", "unexpected-entry reservation succeeds")
	if unexpected != "":
		driver.check(
			_write_text_file(unexpected.path_join("unexpected.txt"), "unrelated content"),
			"unexpected entry written"
		)

	var nested := _reserve_scratch_dir()
	driver.check(nested != "", "nested-directory reservation succeeds")
	if nested != "":
		driver.check(
			DirAccess.make_dir_absolute(nested.path_join("subdir")) == OK,
			"subdirectory created inside reservation"
		)
		driver.check(
			_write_text_file(nested.path_join("subdir").path_join("inside.txt"), "nested content"),
			"nested file written"
		)

	var hidden := _reserve_scratch_dir()
	driver.check(hidden != "", "hidden-entry reservation succeeds")
	if hidden != "":
		driver.check(
			_write_text_file(hidden.path_join(".hidden.txt"), "hidden content"),
			"hidden entry written"
		)

	_cleanup_scratch_dirs()
	var reports := _scratch_cleanup_reports.slice(reports_before)

	driver.check(
		not DirAccess.dir_exists_absolute(known),
		"reservation holding only known outputs is removed once empty"
	)
	driver.check(
		DirAccess.dir_exists_absolute(unexpected),
		"reservation with an unexpected entry is retained"
	)
	if unexpected != "":
		driver.check(
			FileAccess.file_exists(unexpected.path_join("unexpected.txt")),
			"unexpected entry survives cleanup"
		)
		driver.check_eq(
			_read_bytes(unexpected.path_join("unexpected.txt")).get_string_from_utf8(),
			"unrelated content",
			"unexpected entry bytes survive cleanup"
		)
	driver.check(
		DirAccess.dir_exists_absolute(nested),
		"reservation with a subdirectory is retained without traversal"
	)
	if nested != "":
		driver.check(
			FileAccess.file_exists(nested.path_join("subdir").path_join("inside.txt")),
			"nested content survives cleanup"
		)
	driver.check(
		DirAccess.dir_exists_absolute(hidden),
		"reservation with a hidden entry is retained"
	)
	if hidden != "":
		driver.check(
			FileAccess.file_exists(hidden.path_join(".hidden.txt")),
			"hidden entry survives cleanup"
		)

	var reported := 0
	for report in reports:
		if "unexpected.txt" in report or "subdir" in report or ".hidden.txt" in report:
			reported += 1
	driver.check(
		reported >= 3,
		"unexpected, nested and hidden retention are all reported (%d matched)" % reported
	)

	# Separate, tightly scoped teardown of only the fixtures this case created.
	# Production cleanup above deliberately retained them; here each exact
	# captured path is re-verified as the same regular file with the same bytes
	# before it is removed, then the now-empty subdirectory and reservations are
	# removed. Changed, replaced, non-empty or unexpected state is retained and
	# reported rather than deleted. No recursive removal and no glob cleanup.
	var teardown_reports: Array[String] = []
	if unexpected != "":
		teardown_reports.append_array(
			_teardown_regular_file(
				unexpected.path_join("unexpected.txt"), "unexpected.txt", "unrelated content"
			)
		)
		teardown_reports.append_array(_teardown_reserved_directory(unexpected))
	if nested != "":
		teardown_reports.append_array(
			_teardown_regular_file(
				nested.path_join("subdir").path_join("inside.txt"),
				"inside.txt",
				"nested content"
			)
		)
		teardown_reports.append_array(_teardown_named_directory(nested.path_join("subdir"), "subdir"))
		teardown_reports.append_array(_teardown_reserved_directory(nested))
	if hidden != "":
		teardown_reports.append_array(
			_teardown_regular_file(hidden.path_join(".hidden.txt"), ".hidden.txt", "hidden content")
		)
		teardown_reports.append_array(_teardown_reserved_directory(hidden))
	for report in teardown_reports:
		printerr("data lab: fixture teardown: %s" % report)
	driver.check(
		teardown_reports.is_empty(),
		"test-fixture teardown removes only its exact files and empty directories"
	)

	# Final residue check: none of the four reservations this case created may
	# remain, and the normal project path holds no data_lab_scratch_* debris.
	for path in [known, unexpected, nested, hidden]:
		if path != "":
			driver.check(
				not DirAccess.dir_exists_absolute(path),
				"test-created reservation %s is fully removed" % path.get_file()
			)
	var root_leftovers := _list_scratch_residue()
	driver.check(
		root_leftovers.is_empty(),
		"normal project path holds no data_lab_scratch_* residue (found %d)" % root_leftovers.size()
	)
	if not root_leftovers.is_empty():
		printerr("data lab: scratch residue retained: %s" % ", ".join(PackedStringArray(root_leftovers)))

	var actual_handling := _read_bytes(LEGACY_ROUNDTRIP_HANDLING_PATH)
	var actual_car := _read_bytes(LEGACY_ROUNDTRIP_CAR_PATH)
	driver.check(
		actual_handling == expected_handling,
		"legacy handling roundtrip path stays byte-identical during cleanup controls"
	)
	driver.check(
		actual_car == expected_car,
		"legacy car roundtrip path stays byte-identical during cleanup controls"
	)


## Test-only teardown for one exact file this case created. Removes it only
## when the basename is the expected one, it is still a regular file (not a
## directory) and its bytes are unchanged. Anything else is retained and
## reported. Reading follows a symlink, but removal only unlinks the entry
## itself; there is no recursive traversal.
func _teardown_regular_file(
	path: String,
	expected_name: String,
	expected_text: String
) -> Array[String]:
	if path.get_file() != expected_name:
		return ["%s: teardown refused, unexpected basename (expected %s)" % [path, expected_name]]
	if not FileAccess.file_exists(path):
		return ["%s: teardown found the test file missing" % path]
	if DirAccess.dir_exists_absolute(path):
		return ["%s: teardown found a directory where the test created a file; retained" % path]
	if _read_bytes(path).get_string_from_utf8() != expected_text:
		return ["%s: teardown found changed content; retained" % path]
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		return ["%s: teardown removal failed (error %d); retained" % [path, err]]
	return []


## Test-only teardown for a named directory (`subdir` here): removes it only
## when it is empty, including hidden entries. Never recurses.
func _teardown_named_directory(path: String, expected_name: String) -> Array[String]:
	if path.get_file() != expected_name:
		return ["%s: teardown refused, unexpected basename (expected %s)" % [path, expected_name]]
	return _teardown_empty_directory(path)


## Test-only teardown for a reservation this run created. Requires the atomic
## scratch basename prefix before touching the directory.
func _teardown_reserved_directory(path: String) -> Array[String]:
	if not path.get_file().begins_with(SCRATCH_DIR_NAME_PREFIX):
		return ["%s: teardown refused, not a reserved data-lab scratch directory" % path]
	return _teardown_empty_directory(path)


func _teardown_empty_directory(path: String) -> Array[String]:
	if not DirAccess.dir_exists_absolute(path):
		return ["%s: teardown found the directory missing" % path]
	var access := DirAccess.open(path)
	if access == null:
		return ["%s: teardown could not open the directory" % path]
	access.set_include_navigational(false)
	access.set_include_hidden(true)
	access.list_dir_begin()
	var entries: Array[String] = []
	var name := access.get_next()
	while name != "":
		entries.append(name)
		name = access.get_next()
	access.list_dir_end()
	access = null
	if not entries.is_empty():
		return [
			"%s: teardown found unexpected entries (%s); retained"
			% [path, ", ".join(PackedStringArray(entries))]
		]
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		return ["%s: teardown removal of empty directory failed (error %d)" % [path, err]]
	return []


## Read-only residue check over the normal project path.
func _list_scratch_residue() -> Array[String]:
	var residue: Array[String] = []
	var access := DirAccess.open("res://")
	if access == null:
		return ["res:// could not be listed"]
	access.set_include_navigational(false)
	access.set_include_hidden(true)
	access.list_dir_begin()
	var name := access.get_next()
	while name != "":
		if name.begins_with(SCRATCH_DIR_NAME_PREFIX):
			residue.append(name)
		name = access.get_next()
	access.list_dir_end()
	access = null
	return residue


## Atomically reserve a fresh scratch directory under res://. The mkdir either
## creates exactly this run's directory or fails, so ownership never depends
## on a preexisting path.
func _reserve_scratch_dir() -> String:
	var stamp := int(Time.get_unix_time_from_system())
	var ticks := Time.get_ticks_usec()
	var pid := OS.get_process_id()
	for attempt in range(10000):
		var candidate := "%s%d_%d_%d_%d" % [SCRATCH_DIR_PREFIX, stamp, ticks, pid, attempt]
		var err := DirAccess.make_dir_absolute(candidate)
		if err == OK:
			_scratch_dirs.append(candidate)
			return candidate
		if err != ERR_ALREADY_EXISTS:
			printerr("data lab: scratch reservation failed with error %d" % err)
			return ""
	printerr("data lab: could not reserve a unique scratch directory")
	return ""


## Remove only the files this validator created inside each reservation, then
## remove the reservation directory itself only when no unexpected entry
## remains. Unexpected content is retained and reported; nothing is recursed
## into, so a symlinked directory cannot pull cleanup outside the reservation.
func _cleanup_scratch_dirs() -> void:
	var reports: Array[String] = []
	for path in _scratch_dirs:
		reports.append_array(_cleanup_scratch_dir(path))
	_scratch_dirs.clear()
	if reports.is_empty():
		return
	_scratch_cleanup_reports.append_array(reports)
	printerr("data lab: scratch cleanup retained %d entr%s:\n%s" % [
		reports.size(),
		"y" if reports.size() == 1 else "ies",
		"\n".join(PackedStringArray(reports)),
	])


func _cleanup_scratch_dir(path: String) -> Array[String]:
	var access := DirAccess.open(path)
	if access == null:
		return ["%s: reserved scratch directory could not be opened" % path.get_file()]
	# Report hidden entries instead of skipping them, but never include the
	# navigational `.`/`..` entries. Snapshot the listing before removing
	# anything so cleanup does not mutate a live directory enumeration.
	access.set_include_navigational(false)
	access.set_include_hidden(true)
	access.list_dir_begin()
	var names: Array[String] = []
	var is_dirs: Array[bool] = []
	var name := access.get_next()
	while name != "":
		names.append(name)
		is_dirs.append(access.current_is_dir())
		name = access.get_next()
	access.list_dir_end()
	access = null
	var retained: Array[String] = []
	for index in range(names.size()):
		var entry_name := names[index]
		if not KNOWN_SCRATCH_FILE_NAMES.has(entry_name):
			retained.append("%s: unexpected entry retained" % entry_name)
		elif is_dirs[index]:
			retained.append("%s: directory retained without traversal" % entry_name)
		else:
			var err := DirAccess.remove_absolute(path.path_join(entry_name))
			if err != OK:
				retained.append("%s: removal failed (error %d); retained" % [entry_name, err])
	if not retained.is_empty():
		return retained
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		return ["%s: empty reserved directory removal failed (error %d)" % [path.get_file(), err]]
	return []


func _read_bytes(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)


func _write_text_file(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


func _case_curve_accessor_safety(driver) -> void:
	var valid = driver.valid_handling()
	driver.check_eq(
		valid.get_acceleration_points().size(),
		3,
		"valid curve exposes three code-facing points"
	)

	var mismatched = driver.valid_handling()
	mismatched.acceleration_curve_speeds_m_s.append(60.0)
	driver.check_eq(
		mismatched.get_acceleration_points().size(),
		0,
		"mismatched arrays refuse to yield a truncated point list"
	)
	driver.expect_diagnostic(
		"handling.acceleration_curve: speed/acceleration entry counts differ",
		mismatched.validate(),
		"mismatched curve arrays"
	)
	driver.check(not mismatched.is_valid(), "mismatched curve arrays are invalid")

	var target = driver.valid_handling()
	var bad_points: Array[HandlingDefinition.AccelerationPoint] = []
	bad_points.append(null)
	driver.check_eq(
		target.set_acceleration_points(bad_points),
		false,
		"set_acceleration_points refuses a null point"
	)
	driver.check_eq(
		target.get_acceleration_points().size(),
		3,
		"refused set leaves the existing curve unchanged"
	)

	var good_points: Array[HandlingDefinition.AccelerationPoint] = [
		HandlingDefinition.AccelerationPoint.make(0.0, 2.0),
	]
	driver.check_eq(
		target.set_acceleration_points(good_points),
		true,
		"set_acceleration_points accepts typed points"
	)
	driver.check_eq(
		target.get_acceleration_points().size(),
		1,
		"accepted set replaces the serialized curve"
	)


# --- Deliberate failure proof ----------------------------------------------


func _run_intentional_failure() -> Dictionary:
	var driver := DataLabDriver.new()
	var handling = driver.valid_handling()
	# Deliberately false expectation: an empty acceleration curve must not
	# validate, so this assertion must fail and the process must exit nonzero.
	handling.clear_acceleration_curve()
	driver.check(
		handling.is_valid(),
		"intentional failure probe: empty curve unexpectedly validated"
	)
	var proof := {
		"schema": "roadstorm.data_lab.validation.v1",
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
	"Pure resource checks only: no Godot body, scene, physics query, clock, rendering, audio device, input routing or gameplay claim is exercised.",
	"The fixtures are synthetic EXAMPLE resources with arbitrary authored numbers; no value is measured, frozen product handling or a Roadstorm vehicle.",
	"The car and handling definitions are not integrated with ArcadeMotor: no motor proposal, world step, gear selection, surface transition, contact or race state is run.",
	"Only the M0.2 core MotorTuning overlap is typed; drift, surge, drafting, airborne, contact caps, surfaces, engine top speed, presentation, upgrades and detachable parts are deferred fields, not absent features.",
	"No track, event, upgrade, AI profile, ghost, model, observation or scenario resource is defined here; those remain later slices.",
	"Tres round-trip coverage is limited to the M0.2 fields; it does not establish importer/cache behavior across Godot versions or exported templates.",
	"Headless engine dummy display/audio drivers; no platform, controller, visual or release claim.",
]


func _finish(report: Dictionary, forced_exit: int = -1) -> void:
	if _finished:
		return
	_finished = true
	var passed := _failures.is_empty() and int(report.get("failed_cases", 0)) == 0
	var code := forced_exit
	if code < 0:
		code = 0 if passed else 1
	print("DATA_LAB_RESULT " + JSON.stringify(report))
	print("CHECKS_TOTAL=%d CHECKS_FAILED=%d" % [_checks, _failures.size()])
	quit(code)
