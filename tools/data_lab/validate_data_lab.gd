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
	"malformed_identity_controls",
	"negative_and_nonfinite_physical_controls",
	"dimensional_bounds",
	"missing_handling_and_curve",
	"completeness_semantics",
	"curve_accessor_safety",
]

const ROUND_TRIP_HANDLING_PATH := "res://data_lab_handling_roundtrip.tres"
const ROUND_TRIP_CAR_PATH := "res://data_lab_car_roundtrip.tres"

var _checks := 0
var _failures: Array[String] = []
var _measured: Dictionary = {}
var _finished := false


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
		"1.0.0/example.data_lab.handling@0.1.0",
		"handling identity key"
	)
	driver.check_eq(handling.status_name(), "EXAMPLE", "example handling status name")

	var car = driver.valid_car(handling)
	driver.check_eq(car.validate().size(), 0, "valid draft car reports no diagnostics")
	driver.check(not car.is_complete(), "draft car is not complete")
	driver.check_eq(car.completeness, CarScript.Completeness.DRAFT, "car completeness is DRAFT")
	driver.check(car.handling == handling, "car keeps its typed handling reference")
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
	driver.check_eq(
		driver.save_resource(handling, ROUND_TRIP_HANDLING_PATH),
		OK,
		"handling .tres saves"
	)
	driver.check_eq(
		driver.save_resource(car, ROUND_TRIP_CAR_PATH),
		OK,
		"car .tres saves"
	)

	var loaded_handling = driver.load_resource(ROUND_TRIP_HANDLING_PATH)
	driver.check(loaded_handling is HandlingDefinition, "loaded handling is a HandlingDefinition")
	if loaded_handling is HandlingDefinition:
		_assert_same_handling(driver, handling, loaded_handling)

	var loaded_car = driver.load_resource(ROUND_TRIP_CAR_PATH)
	driver.check(loaded_car is CarDefinition, "loaded car is a CarDefinition")
	if loaded_car is CarDefinition:
		_assert_same_car(driver, car, loaded_car)
		driver.check(
			loaded_car.handling != null and loaded_car.handling.is_valid(),
			"embedded handling survives the round trip and validates"
		)
		driver.check_eq(
			loaded_car.validate().size(),
			0,
			"loaded draft car still reports no diagnostics"
		)

	var rebound := driver.valid_car()
	rebound.handling = loaded_handling
	driver.check(
		rebound.is_valid(),
		"rebinding a separately loaded handling resource keeps the car valid"
	)

	_cleanup_roundtrip_files()
	driver.measure("roundtrip_handling_ok", loaded_handling is HandlingDefinition)
	driver.measure("roundtrip_car_ok", loaded_car is CarDefinition)


func _assert_same_handling(driver, expected: HandlingDefinition, actual: HandlingDefinition) -> void:
	driver.check_eq(actual.definition_id, expected.definition_id, "round trip handling ID")
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
	driver.check(actual.handling is HandlingDefinition, "round trip embedded handling type")


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
		"definition_id: malformed 'Bad Handling'",
		bad_handling_id.validate(),
		"referenced handling with a malformed ID"
	)
	driver.check(not bad_handling_id.is_valid(), "car rejects a malformed handling ID")

	var bad_handling_version := driver.valid_car()
	bad_handling_version.handling.schema_version = "9.9.9"
	driver.expect_diagnostic(
		"schema_version: unsupported '9.9.9'",
		bad_handling_version.validate(),
		"referenced handling with an unsupported schema version"
	)
	driver.check(not bad_handling_version.is_valid(), "car rejects an unsupported handling version")

	var bad_handling_revision := driver.valid_car()
	bad_handling_revision.handling.revision = "1.0"
	driver.expect_diagnostic(
		"revision: malformed '1.0'",
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
		"deferred_fields[0]: empty entry",
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


func _cleanup_roundtrip_files() -> void:
	var directory := DirAccess.open("res://")
	if directory == null:
		return
	directory.remove(ROUND_TRIP_HANDLING_PATH.get_file())
	directory.remove(ROUND_TRIP_CAR_PATH.get_file())


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
