extends SceneTree
## Headless black-box runner for the M0.2 car-DRAFT mapper lab.
##
## Run from an isolated project copy (tools/car_draft_lab/run_validation.sh
## stages one and imports first):
##   godot --headless --fixed-fps 60 --path <project> \
##       --script res://tools/car_draft_lab/validate_car_draft_lab.gd
##
## Optional `--case=<id>` selects one case; the default runs every case.
## `--case=intentional_failure` always exits nonzero to prove the harness
## detects a failing assertion. Each case prints its own machine-readable
## result; this script prints one CAR_DRAFT_LAB_RESULT line, CHECKS_TOTAL and
## CHECKS_FAILED lines, and quits with a controlled exit code.
##
## This exercises pure in-memory source-recipe to typed draft mapping only: no
## scene, body, physics query, clock, rendering, audio device, input routing,
## motor integration, `.tres` write, bake manifest or gameplay claim. A
## parse/load failure appears in the engine log before this script runs; the
## runner treats engine SCRIPT ERROR / Parse Error lines as a distinct
## parse/load failure, never as an assertion pass.

const HandlingMapperScript = preload("res://src/data/handling_recipe_mapper.gd")
const CarMapperScript = preload("res://src/data/car_recipe_mapper.gd")
const IdentityScript = preload("res://src/data/definition_identity.gd")
const HandlingScript = preload("res://src/data/handling_definition.gd")
const CarScript = preload("res://src/data/car_definition.gd")

## Externally checked (motor-ready) positive source fixture. Full JSON
## Schema/strict-parse/content-hash validation stays with
## tools/car_recipe_schema/validate_car_recipe.py; this lab parses it through
## Godot's JSON reader and the committed mappers.
const FIXTURE_PATH := "res://fixtures/car_recipe/positive/example_rookie_finite.json"
const UNLIMITED_FIXTURE_PATH := "res://fixtures/car_recipe/positive/example_rookie_unlimited.json"

const CASE_IDS := [
	"positive_fixture_mapping",
	"positive_unlimited_fixture_mapping",
	"optional_null_preservation",
	"version_units_frame_refusals",
	"handling_agreement_refusals",
	"required_mapped_field_refusals",
	"invalid_dimensions_and_contact_refusals",
	"no_half_mapped_result",
]

var _checks := 0
var _failures: Array[String] = []
var _measured: Dictionary = {}
var _finished := false


func _initialize() -> void:
	# Marker printed only when every const preload parsed. If a global class
	# failed to register, Godot emits SCRIPT ERROR before this line and the
	# runner reports a parse/load failure instead of an assertion result.
	print("CAR_DRAFT_LAB_STAGE preloads_resolved=1")
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
		"schema": "roadstorm.car_draft_lab.validation.v1",
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
	var from_environment := OS.get_environment("CAR_DRAFT_LAB_CASE")
	if from_environment != "":
		return from_environment
	return "all"


func _run_case(case_id: String) -> Dictionary:
	var checks_before := _checks
	var failures_before := _failures.size()
	match case_id:
		"positive_fixture_mapping":
			_case_positive_fixture_mapping()
		"positive_unlimited_fixture_mapping":
			_case_positive_unlimited_fixture_mapping()
		"optional_null_preservation":
			_case_optional_null_preservation()
		"version_units_frame_refusals":
			_case_version_units_frame_refusals()
		"handling_agreement_refusals":
			_case_handling_agreement_refusals()
		"required_mapped_field_refusals":
			_case_required_mapped_field_refusals()
		"invalid_dimensions_and_contact_refusals":
			_case_invalid_dimensions_and_contact_refusals()
		"no_half_mapped_result":
			_case_no_half_mapped_result()
	var failures := _failures.slice(failures_before)
	_measured[case_id] = {
		"checks": _checks - checks_before,
		"failures": failures.size(),
	}
	print(
		"CASE %s checks=%d failures=%d pass=%s"
		% [case_id, _checks - checks_before, failures.size(), str(failures.is_empty())]
	)
	return {
		"id": case_id,
		"checks": _checks - checks_before,
		"pass": failures.is_empty(),
		"failures": failures.duplicate(),
	}


# --- Assertion helpers ------------------------------------------------------


func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func check_eq(actual, expected, message: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append(
			"%s (actual=%s expected=%s)" % [message, str(actual), str(expected)]
		)


func check_float_eq(actual: float, expected: float, tolerance: float, message: String) -> void:
	_checks += 1
	if (
		is_nan(actual) or is_inf(actual) or is_nan(expected) or is_inf(expected)
		or absf(actual - expected) > tolerance
	):
		_failures.append(
			"%s (actual=%s expected=%s tol=%s)"
			% [message, str(actual), str(expected), str(tolerance)]
		)


func expect_diagnostic(token: String, diagnostics: Array[String], label: String) -> void:
	_checks += 1
	for entry in diagnostics:
		if token in entry:
			return
	_failures.append("%s: no diagnostic contains '%s'" % [label, token])


func count_diagnostics(token: String, diagnostics: Array[String]) -> int:
	var count := 0
	for entry in diagnostics:
		if token in entry:
			count += 1
	return count


func expect_refusal(result, token: String, label: String) -> void:
	check(result != null, "%s: mapper returned a null result" % label)
	if result == null:
		return
	check(not bool(result.ok), "%s: mapper accepted an invalid recipe" % label)
	check(result.car == null, "%s: refusal returned a car" % label)
	check(
		result.diagnostics.size() > 0,
		"%s: refusal carried no diagnostics" % label
	)
	expect_diagnostic(token, result.diagnostics, label)


# --- Fixture helpers --------------------------------------------------------


func _load_json_fixture() -> Dictionary:
	return _load_json(FIXTURE_PATH)


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _fixture_recipe() -> Dictionary:
	var recipe := _load_json_fixture()
	if recipe.is_empty():
		check(false, "positive fixture parsed into a non-empty Dictionary")
	return recipe


func _mapped_handling(recipe: Dictionary) -> HandlingDefinition:
	var result = HandlingMapperScript.map_handling(recipe)
	if not result.ok:
		check(false, "fixture handling mapping failed: %s" % str(result.diagnostics))
		return null
	return result.handling


## Deep-copy a recipe for a single mutation so concurrent cases and later
## assertions cannot observe another case's edits.
func _copy_recipe(recipe: Dictionary) -> Dictionary:
	return recipe.duplicate(true)


func _add_unknown(recipe: Dictionary, path: String) -> void:
	if not recipe.has("unknowns") or typeof(recipe["unknowns"]) != TYPE_ARRAY:
		recipe["unknowns"] = []
	var unknowns: Array = recipe["unknowns"]
	var entry := {"path": path, "reason": "lab mutation"}
	unknowns.append(entry)


func _remove_unknown(recipe: Dictionary, path: String) -> void:
	if not recipe.has("unknowns") or typeof(recipe["unknowns"]) != TYPE_ARRAY:
		return
	var unknowns: Array = recipe["unknowns"]
	for index in range(unknowns.size() - 1, -1, -1):
		var entry: Variant = unknowns[index]
		if typeof(entry) == TYPE_DICTIONARY and entry["path"] == path:
			unknowns.remove_at(index)


# --- Cases ------------------------------------------------------------------


func _case_positive_fixture_mapping() -> void:
	var recipe := _fixture_recipe()
	if recipe.is_empty():
		return
	var handling_result = HandlingMapperScript.map_handling(recipe)
	check(handling_result.ok, "positive fixture maps to a typed handling")
	if not handling_result.ok:
		return
	var handling: HandlingDefinition = handling_result.handling

	var serialized_before := JSON.stringify(recipe)
	var unknown_count_before: int = 0
	if recipe.has("unknowns") and typeof(recipe["unknowns"]) == TYPE_ARRAY:
		unknown_count_before = (recipe["unknowns"] as Array).size()

	var result = CarMapperScript.map_draft(recipe, handling)
	check(result.ok, "positive fixture maps to a draft car")
	if not result.ok:
		for entry in result.diagnostics:
			print("REFUSAL_DIAGNOSTIC %s" % entry)
		return
	var car: CarDefinition = result.car
	check(car != null, "success carries a car")
	if car == null:
		return

	check(car.is_valid(), "draft car validates with no diagnostics")
	check(not car.is_complete(), "draft car never claims completion")
	check_eq(car.schema_version, "1.0.0", "typed car schema version")
	check_eq(car.definition_id, "car.example_rookie", "mapped car ID")
	check_eq(car.display_name, "Example Rookie", "mapped car display name")
	check_eq(car.revision, "0.1.0", "copied car revision")
	check_eq(car.status, IdentityScript.Status.EXAMPLE, "mapped car lifecycle status")
	check_eq(result.source_schema_version, "1.1.0", "source contract version recorded")

	check(car.handling == handling, "car keeps the passed typed handling reference")
	if car.handling is HandlingDefinition:
		check_eq(
			car.handling.definition_id,
			"car.example_rookie.handling",
			"referenced handling uses the documented derived ID"
		)

	check_float_eq(car.length_m, 4.2, 1e-9, "mapped length")
	check_float_eq(car.width_m, 1.9, 1e-9, "mapped width")
	check_float_eq(car.height_m, 1.4, 1e-9, "mapped height")
	check_float_eq(float(car.wheelbase_m), 2.6, 1e-9, "mapped wheelbase")
	check_float_eq(float(car.ground_clearance_m), 0.12, 1e-9, "mapped ground clearance")
	check_float_eq(float(car.jump_envelope_m), 0.4, 1e-9, "mapped jump envelope")
	check_float_eq(car.mass_kg, 1200.0, 1e-9, "mapped intact mass")
	check_eq(
		car.contact_proxy_shape,
		CarScript.ContactProxyShape.ROUNDED_BOX,
		"mapped contact proxy shape"
	)
	check(car.contact_roof == null, "authored null contact roof stays null")
	check(car.contact_underside == null, "authored null contact underside stays null")

	check_eq(
		car.completeness,
		CarScript.Completeness.INCOMPLETE,
		"draft completeness is INCOMPLETE"
	)
	check(
		not car.completeness_note.strip_edges().is_empty(),
		"draft completeness note is non-blank"
	)
	check_eq(
		car.completeness_note,
		CarMapperScript.DRAFT_COMPLETENESS_NOTE,
		"draft completeness note is the fixed honest note"
	)
	check_eq(
		car.deferred_fields.size(),
		CarScript.DEFERRED_FIELDS_V1.size(),
		"draft lists every v1 deferred field"
	)
	for index in range(mini(car.deferred_fields.size(), CarScript.DEFERRED_FIELDS_V1.size())):
		check_eq(
			car.deferred_fields[index],
			String(CarScript.DEFERRED_FIELDS_V1[index]),
			"deferred field %d is declared exactly" % index
		)

	# Source nonmutation: the mapper must not edit the recipe, its nested
	# members or its unknowns list.
	check_eq(
		JSON.stringify(recipe),
		serialized_before,
		"source recipe bytes are unchanged after mapping"
	)
	var unknown_count_after: int = 0
	if recipe.has("unknowns") and typeof(recipe["unknowns"]) == TYPE_ARRAY:
		unknown_count_after = (recipe["unknowns"] as Array).size()
	check_eq(unknown_count_after, unknown_count_before, "source unknowns count is unchanged")

	_measured["fixture_id"] = car.definition_id
	_measured["fixture_handling_id"] = car.handling.identity_key()
	_measured["fixture_deferred_count"] = car.deferred_fields.size()


func _case_positive_unlimited_fixture_mapping() -> void:
	var recipe := _load_json(UNLIMITED_FIXTURE_PATH)
	if recipe.is_empty():
		check(false, "unlimited positive fixture parsed into a non-empty Dictionary")
		return
	var handling_result = HandlingMapperScript.map_handling(recipe)
	check(handling_result.ok, "unlimited fixture maps to a typed handling")
	if not handling_result.ok:
		return
	var handling: HandlingDefinition = handling_result.handling
	check(
		is_inf(handling.max_yaw_rate_rad_s) and handling.max_yaw_rate_rad_s > 0.0,
		"unlimited source encoding maps to positive Godot INF"
	)

	var result = CarMapperScript.map_draft(recipe, handling)
	check(result.ok, "unlimited fixture maps to a draft car")
	if not result.ok:
		for entry in result.diagnostics:
			print("REFUSAL_DIAGNOSTIC %s" % entry)
		return
	var car: CarDefinition = result.car
	check(car != null and car.is_valid(), "unlimited draft car validates")
	check(not car.is_complete(), "unlimited draft never claims completion")
	check_eq(
		car.completeness,
		CarScript.Completeness.INCOMPLETE,
		"unlimited draft completeness is INCOMPLETE"
	)
	check_eq(car.definition_id, "car.example_rookie", "unlimited draft maps the car ID")
	check(car.handling == handling, "unlimited draft keeps its typed handling reference")
	check_eq(car.revision, "0.1.0", "unlimited draft copies the revision")
	check_float_eq(car.mass_kg, 1200.0, 1e-9, "unlimited draft maps intact mass")


func _case_optional_null_preservation() -> void:
	var recipe := _fixture_recipe()
	if recipe.is_empty():
		return
	recipe = _copy_recipe(recipe)
	var dimensions: Dictionary = recipe["dimensions"]
	dimensions["wheelbase_m"] = null
	dimensions["ground_clearance_m"] = null
	dimensions["jump_envelope_m"] = null
	_add_unknown(recipe, "dimensions.wheelbase_m")
	_add_unknown(recipe, "dimensions.ground_clearance_m")
	_add_unknown(recipe, "dimensions.jump_envelope_m")

	var handling := _mapped_handling(recipe)
	if handling == null:
		return
	var result = CarMapperScript.map_draft(recipe, handling)
	check(result.ok, "optional-null recipe maps to a draft car")
	if not result.ok:
		for entry in result.diagnostics:
			print("REFUSAL_DIAGNOSTIC %s" % entry)
		return
	var car: CarDefinition = result.car
	check(car.wheelbase_m == null, "undetermined wheelbase stays null")
	check(car.ground_clearance_m == null, "undetermined ground clearance stays null")
	check(car.jump_envelope_m == null, "undetermined jump envelope stays null")
	check(car.contact_roof == null, "undetermined contact roof stays null")
	check(car.contact_underside == null, "undetermined contact underside stays null")
	check(car.is_valid(), "optional-null draft still validates")

	# A resolved optional value that is also listed as unknown is refused.
	var contradictory := _fixture_recipe()
	if contradictory.is_empty():
		return
	contradictory = _copy_recipe(contradictory)
	(contradictory["dimensions"] as Dictionary)["wheelbase_m"] = 2.6
	_add_unknown(contradictory, "dimensions.wheelbase_m")
	var contradictory_result = CarMapperScript.map_draft(contradictory, handling)
	expect_refusal(
		contradictory_result,
		"dimensions.wheelbase_m: resolved-value-unknown",
		"resolved optional dimension listed as unknown"
	)


func _case_version_units_frame_refusals() -> void:
	var valid_handling := _mapped_handling(_fixture_recipe())
	if valid_handling == null:
		return

	# Version dispatch.
	var old_version := _copy_recipe(_fixture_recipe())
	old_version["schema_version"] = "1.0.0"
	var old_result = CarMapperScript.map_draft(old_version, valid_handling)
	expect_refusal(
		old_result, "handling.max_yaw_rate_rad_s: missing-field", "1.0.0 recipe refusal"
	)
	check_eq(
		count_diagnostics("missing-field: source contract 1.0.0", old_result.diagnostics),
		5,
		"1.0.0 refusal names all five missing handling paths"
	)

	var unsupported := _copy_recipe(_fixture_recipe())
	unsupported["schema_version"] = "2.0.0"
	expect_refusal(
		CarMapperScript.map_draft(unsupported, valid_handling),
		"unsupported-schema-version",
		"unsupported version"
	)

	var mistyped_version := _copy_recipe(_fixture_recipe())
	mistyped_version["schema_version"] = 1.1
	expect_refusal(
		CarMapperScript.map_draft(mistyped_version, valid_handling),
		"unsupported-schema-version",
		"mistyped version"
	)

	var missing_version := _copy_recipe(_fixture_recipe())
	missing_version.erase("schema_version")
	expect_refusal(
		CarMapperScript.map_draft(missing_version, valid_handling),
		"unsupported-schema-version",
		"missing version"
	)

	var newline_version := _copy_recipe(_fixture_recipe())
	newline_version["schema_version"] = "1.1.0\n"
	expect_refusal(
		CarMapperScript.map_draft(newline_version, valid_handling),
		"unsupported-schema-version",
		"trailing-newline version"
	)

	# Units.
	var no_units := _copy_recipe(_fixture_recipe())
	no_units.erase("units")
	expect_refusal(
		CarMapperScript.map_draft(no_units, valid_handling), "units: bad-units", "missing units"
	)

	var bad_length_unit := _copy_recipe(_fixture_recipe())
	(bad_length_unit["units"] as Dictionary)["length"] = "ft"
	expect_refusal(
		CarMapperScript.map_draft(bad_length_unit, valid_handling),
		"units.length: bad-unit",
		"wrong length unit"
	)

	var missing_angle_unit := _copy_recipe(_fixture_recipe())
	(missing_angle_unit["units"] as Dictionary).erase("angle")
	expect_refusal(
		CarMapperScript.map_draft(missing_angle_unit, valid_handling),
		"units.angle: missing-field",
		"missing angle unit"
	)

	var units_array := _copy_recipe(_fixture_recipe())
	units_array["units"] = []
	expect_refusal(
		CarMapperScript.map_draft(units_array, valid_handling),
		"units: bad-units",
		"mistyped units"
	)

	# Coordinate frame.
	var no_frame := _copy_recipe(_fixture_recipe())
	no_frame.erase("coordinate_frame")
	expect_refusal(
		CarMapperScript.map_draft(no_frame, valid_handling),
		"coordinate_frame: bad-coordinate-frame",
		"missing coordinate frame"
	)

	var bad_forward := _copy_recipe(_fixture_recipe())
	(bad_forward["coordinate_frame"] as Dictionary)["forward"] = "+Z"
	expect_refusal(
		CarMapperScript.map_draft(bad_forward, valid_handling),
		"coordinate_frame.forward: bad-frame",
		"wrong forward axis"
	)

	var missing_up := _copy_recipe(_fixture_recipe())
	(missing_up["coordinate_frame"] as Dictionary).erase("up")
	expect_refusal(
		CarMapperScript.map_draft(missing_up, valid_handling),
		"coordinate_frame.up: missing-field",
		"missing up axis"
	)

	var bad_origin := _copy_recipe(_fixture_recipe())
	(bad_origin["coordinate_frame"] as Dictionary)["origin"] = "rear_axle"
	expect_refusal(
		CarMapperScript.map_draft(bad_origin, valid_handling),
		"coordinate_frame.origin: bad-frame",
		"wrong frame origin"
	)


func _case_handling_agreement_refusals() -> void:
	var recipe := _fixture_recipe()
	if recipe.is_empty():
		return
	var handling := _mapped_handling(recipe)
	if handling == null:
		return

	expect_refusal(
		CarMapperScript.map_draft(recipe, null),
		"handling: missing-handling",
		"missing handling"
	)

	var wrong_id := _copy_recipe(recipe)
	var wrong_id_handling := _mapped_handling(wrong_id)
	wrong_id_handling.definition_id = "car.some_other_car.handling"
	expect_refusal(
		CarMapperScript.map_draft(wrong_id, wrong_id_handling),
		"handling.definition_id: handling-identity-mismatch",
		"wrong handling ID"
	)

	var wrong_revision := _copy_recipe(recipe)
	var wrong_revision_handling := _mapped_handling(wrong_revision)
	wrong_revision_handling.revision = "9.9.9"
	expect_refusal(
		CarMapperScript.map_draft(wrong_revision, wrong_revision_handling),
		"handling.revision: handling-revision-mismatch",
		"wrong handling revision"
	)

	var wrong_status := _copy_recipe(recipe)
	var wrong_status_handling := _mapped_handling(wrong_status)
	wrong_status_handling.status = IdentityScript.Status.MEASURED
	expect_refusal(
		CarMapperScript.map_draft(wrong_status, wrong_status_handling),
		"handling.status: handling-status-mismatch",
		"wrong handling status"
	)

	var wrong_version := _copy_recipe(recipe)
	var wrong_version_handling := _mapped_handling(wrong_version)
	wrong_version_handling.schema_version = "9.9.9"
	expect_refusal(
		CarMapperScript.map_draft(wrong_version, wrong_version_handling),
		"handling.schema_version: handling-schema-version-mismatch",
		"wrong typed handling schema version"
	)

	# A handling that disagrees with the source physically must not be rescued
	# by the identity agreement checks: the constructed car validates the full
	# referenced handling and refuses.
	var invalid_physical := _copy_recipe(recipe)
	var invalid_physical_handling := _mapped_handling(invalid_physical)
	invalid_physical_handling.braking_acceleration_m_s2 = -1.0
	var invalid_result = CarMapperScript.map_draft(invalid_physical, invalid_physical_handling)
	expect_refusal(
		invalid_result,
		"handling.braking_acceleration_m_s2: negative",
		"physically invalid handling"
	)


func _case_required_mapped_field_refusals() -> void:
	var recipe := _fixture_recipe()
	if recipe.is_empty():
		return
	var handling := _mapped_handling(recipe)
	if handling == null:
		return

	var missing_length := _copy_recipe(recipe)
	(missing_length["dimensions"] as Dictionary).erase("length_m")
	expect_refusal(
		CarMapperScript.map_draft(missing_length, handling),
		"dimensions.length_m: missing-field",
		"missing required length"
	)

	var null_width := _copy_recipe(recipe)
	(null_width["dimensions"] as Dictionary)["width_m"] = null
	expect_refusal(
		CarMapperScript.map_draft(null_width, handling),
		"dimensions.width_m: motor-input-unresolved",
		"null required width"
	)

	var unknown_height := _copy_recipe(recipe)
	_add_unknown(unknown_height, "dimensions.height_m")
	expect_refusal(
		CarMapperScript.map_draft(unknown_height, handling),
		"dimensions.height_m: motor-input-unknown",
		"unknown required height"
	)

	var unknown_ancestor := _copy_recipe(recipe)
	_add_unknown(unknown_ancestor, "dimensions")
	expect_refusal(
		CarMapperScript.map_draft(unknown_ancestor, handling),
		"dimensions.length_m: motor-input-unknown",
		"unknown dimensions ancestor"
	)

	var missing_mass := _copy_recipe(recipe)
	missing_mass.erase("mass_kg")
	expect_refusal(
		CarMapperScript.map_draft(missing_mass, handling),
		"mass_kg: missing-field",
		"missing mass"
	)

	var null_mass := _copy_recipe(recipe)
	null_mass["mass_kg"] = null
	expect_refusal(
		CarMapperScript.map_draft(null_mass, handling),
		"mass_kg: motor-input-unresolved",
		"null mass"
	)

	var unknown_mass := _copy_recipe(recipe)
	_add_unknown(unknown_mass, "mass_kg")
	expect_refusal(
		CarMapperScript.map_draft(unknown_mass, handling),
		"mass_kg: motor-input-unknown",
		"unknown mass"
	)

	var missing_proxy := _copy_recipe(recipe)
	missing_proxy.erase("contact_proxy")
	expect_refusal(
		CarMapperScript.map_draft(missing_proxy, handling),
		"contact_proxy: bad-contact-proxy",
		"missing contact proxy"
	)

	var missing_shape := _copy_recipe(recipe)
	(missing_shape["contact_proxy"] as Dictionary).erase("shape")
	expect_refusal(
		CarMapperScript.map_draft(missing_shape, handling),
		"contact_proxy.shape: missing-field",
		"missing contact shape"
	)

	var null_shape := _copy_recipe(recipe)
	(null_shape["contact_proxy"] as Dictionary)["shape"] = null
	expect_refusal(
		CarMapperScript.map_draft(null_shape, handling),
		"contact_proxy.shape: motor-input-unresolved",
		"null contact shape"
	)

	var unknown_shape := _copy_recipe(recipe)
	_add_unknown(unknown_shape, "contact_proxy.shape")
	expect_refusal(
		CarMapperScript.map_draft(unknown_shape, handling),
		"contact_proxy.shape: motor-input-unknown",
		"unknown contact shape"
	)

	var bad_shape := _copy_recipe(recipe)
	(bad_shape["contact_proxy"] as Dictionary)["shape"] = "sphere"
	expect_refusal(
		CarMapperScript.map_draft(bad_shape, handling),
		"contact_proxy.shape: bad-contact-shape",
		"out-of-domain contact shape"
	)

	var mistyped_shape := _copy_recipe(recipe)
	(mistyped_shape["contact_proxy"] as Dictionary)["shape"] = 1
	expect_refusal(
		CarMapperScript.map_draft(mistyped_shape, handling),
		"contact_proxy.shape: bad-contact-shape",
		"mistyped contact shape"
	)

	var bad_derived := _copy_recipe(recipe)
	(bad_derived["contact_proxy"] as Dictionary)["derived_from"] = "artist_mesh"
	expect_refusal(
		CarMapperScript.map_draft(bad_derived, handling),
		"contact_proxy.derived_from: bad-derived-from",
		"contact proxy not derived from declared dimensions"
	)

	# Optional fields: present null is preserved (covered above); a resolved
	# value listed as unknown is refused, including through an ancestor entry.
	var resolved_unknown_roof := _copy_recipe(recipe)
	(resolved_unknown_roof["contact_proxy"] as Dictionary)["roof"] = "flat_panel"
	_add_unknown(resolved_unknown_roof, "contact_proxy.roof")
	expect_refusal(
		CarMapperScript.map_draft(resolved_unknown_roof, handling),
		"contact_proxy.roof: resolved-value-unknown",
		"resolved contact roof listed as unknown"
	)

	var resolved_unknown_clearance := _copy_recipe(recipe)
	_add_unknown(resolved_unknown_clearance, "dimensions")
	expect_refusal(
		CarMapperScript.map_draft(resolved_unknown_clearance, handling),
		"dimensions.wheelbase_m: resolved-value-unknown",
		"resolved optional dimension under an unknown ancestor"
	)

	var missing_optional := _copy_recipe(recipe)
	(missing_optional["dimensions"] as Dictionary).erase("wheelbase_m")
	expect_refusal(
		CarMapperScript.map_draft(missing_optional, handling),
		"dimensions.wheelbase_m: missing-field",
		"missing optional dimension member"
	)


func _case_invalid_dimensions_and_contact_refusals() -> void:
	var recipe := _fixture_recipe()
	if recipe.is_empty():
		return
	var handling := _mapped_handling(recipe)
	if handling == null:
		return

	var short := _copy_recipe(recipe)
	(short["dimensions"] as Dictionary)["length_m"] = 3.0
	expect_refusal(
		CarMapperScript.map_draft(short, handling),
		"dimensions.length_m: 3.0 is below the documented envelope minimum",
		"out-of-envelope length"
	)

	var long := _copy_recipe(recipe)
	(long["dimensions"] as Dictionary)["length_m"] = 5.0
	expect_refusal(
		CarMapperScript.map_draft(long, handling),
		"dimensions.length_m: 5.0 is above the documented envelope maximum",
		"out-of-envelope length"
	)

	var nan_height := _copy_recipe(recipe)
	(nan_height["dimensions"] as Dictionary)["height_m"] = NAN
	expect_refusal(
		CarMapperScript.map_draft(nan_height, handling),
		"dimensions.height_m: bad-number: non-finite number",
		"non-finite required dimension"
	)

	var inf_width := _copy_recipe(recipe)
	(inf_width["dimensions"] as Dictionary)["width_m"] = INF
	expect_refusal(
		CarMapperScript.map_draft(inf_width, handling),
		"dimensions.width_m: bad-number: non-finite number",
		"infinite required dimension"
	)

	var string_length := _copy_recipe(recipe)
	(string_length["dimensions"] as Dictionary)["length_m"] = "4.2"
	expect_refusal(
		CarMapperScript.map_draft(string_length, handling),
		"dimensions.length_m: bad-number: expected a finite number, got String",
		"mistyped required dimension"
	)

	var boolean_mass := _copy_recipe(recipe)
	boolean_mass["mass_kg"] = true
	expect_refusal(
		CarMapperScript.map_draft(boolean_mass, handling),
		"mass_kg: bad-number: expected a finite number, got bool",
		"boolean mass"
	)

	var zero_mass := _copy_recipe(recipe)
	zero_mass["mass_kg"] = 0.0
	expect_refusal(
		CarMapperScript.map_draft(zero_mass, handling),
		"mass_kg: non-positive",
		"zero mass"
	)

	var negative_mass := _copy_recipe(recipe)
	negative_mass["mass_kg"] = -12.0
	expect_refusal(
		CarMapperScript.map_draft(negative_mass, handling),
		"mass_kg: non-positive",
		"negative mass"
	)

	var nan_mass := _copy_recipe(recipe)
	nan_mass["mass_kg"] = NAN
	expect_refusal(
		CarMapperScript.map_draft(nan_mass, handling),
		"mass_kg: bad-number: non-finite number",
		"non-finite mass"
	)

	var long_wheelbase := _copy_recipe(recipe)
	(long_wheelbase["dimensions"] as Dictionary)["wheelbase_m"] = 5.0
	expect_refusal(
		CarMapperScript.map_draft(long_wheelbase, handling),
		"dimensions.wheelbase_m: 5.0 exceeds length_m",
		"wheelbase longer than the car"
	)

	var negative_clearance := _copy_recipe(recipe)
	(negative_clearance["dimensions"] as Dictionary)["ground_clearance_m"] = -0.1
	expect_refusal(
		CarMapperScript.map_draft(negative_clearance, handling),
		"dimensions.ground_clearance_m: negative",
		"negative ground clearance"
	)

	var negative_jump := _copy_recipe(recipe)
	(negative_jump["dimensions"] as Dictionary)["jump_envelope_m"] = -0.1
	expect_refusal(
		CarMapperScript.map_draft(negative_jump, handling),
		"dimensions.jump_envelope_m: negative",
		"negative jump envelope"
	)

	var text_wheelbase := _copy_recipe(recipe)
	(text_wheelbase["dimensions"] as Dictionary)["wheelbase_m"] = "2.6"
	expect_refusal(
		CarMapperScript.map_draft(text_wheelbase, handling),
		"dimensions.wheelbase_m: expected a number or null, got String",
		"mistyped optional dimension"
	)

	var numeric_roof := _copy_recipe(recipe)
	_remove_unknown(numeric_roof, "contact_proxy.roof")
	(numeric_roof["contact_proxy"] as Dictionary)["roof"] = 5
	expect_refusal(
		CarMapperScript.map_draft(numeric_roof, handling),
		"contact_proxy.roof: bad-contact-description",
		"mistyped contact roof"
	)

	var array_underside := _copy_recipe(recipe)
	_remove_unknown(array_underside, "contact_proxy.underside")
	(array_underside["contact_proxy"] as Dictionary)["underside"] = []
	expect_refusal(
		CarMapperScript.map_draft(array_underside, handling),
		"contact_proxy.underside: bad-contact-description",
		"mistyped contact underside"
	)


func _case_no_half_mapped_result() -> void:
	var recipe := _fixture_recipe()
	if recipe.is_empty():
		return
	var handling := _mapped_handling(recipe)
	if handling == null:
		return

	var mutated: Array[Dictionary] = []
	var variants: Array[Dictionary] = []

	var no_handling := _copy_recipe(recipe)
	variants.append(no_handling)

	var bad_id := _copy_recipe(recipe)
	var bad_id_handling := _mapped_handling(bad_id)
	bad_id_handling.definition_id = "car.wrong.handling"
	variants.append(bad_id)

	var bad_version := _copy_recipe(recipe)
	bad_version["schema_version"] = "1.0.0"
	variants.append(bad_version)

	var missing_dimensions := _copy_recipe(recipe)
	missing_dimensions.erase("dimensions")
	variants.append(missing_dimensions)

	var missing_contact := _copy_recipe(recipe)
	missing_contact.erase("contact_proxy")
	variants.append(missing_contact)

	var bad_length := _copy_recipe(recipe)
	(bad_length["dimensions"] as Dictionary)["length_m"] = 1.0
	variants.append(bad_length)

	for variant in variants:
		var variant_handling := handling
		if variant == bad_id:
			variant_handling = bad_id_handling
		var result = CarMapperScript.map_draft(variant, variant_handling)
		check(not bool(result.ok), "refusal sets ok=false")
		check(result.car == null, "refusal returns no car")
		check(
			result.diagnostics.size() > 0,
			"refusal returns at least one path-level diagnostic"
		)
		for entry in result.diagnostics:
			check(":" in entry, "diagnostic is path-level: %s" % entry)

	# Success is complete-or-nothing too: a valid draft is fully valid and
	# never claims completion or production readiness.
	var good = CarMapperScript.map_draft(_fixture_recipe(), handling)
	check(good.ok, "valid recipe maps successfully")
	if good.ok:
		check(good.car.is_valid(), "successful draft is fully valid")
		check(not good.car.is_complete(), "successful draft never claims completion")
		check_eq(
			good.car.completeness,
			CarScript.Completeness.INCOMPLETE,
			"successful draft stays INCOMPLETE"
		)
		check(
			"production-complete" in good.car.completeness_note
			and "not motor-ready" in good.car.completeness_note,
			"draft note states the partial-slice limits honestly"
		)


# --- Deliberate failure proof ----------------------------------------------


func _run_intentional_failure() -> Dictionary:
	# Deliberately false expectation: a valid fixture recipe with its mapped
	# handling must produce a car, so asserting a null car must fail and the
	# process must exit nonzero.
	var recipe := _fixture_recipe()
	var handling := _mapped_handling(recipe)
	var result = CarMapperScript.map_draft(recipe, handling)
	check(
		result.car == null,
		"intentional failure probe: a valid draft unexpectedly had no car"
	)
	var proof := {
		"schema": "roadstorm.car_draft_lab.validation.v1",
		"proof": "intentional_failure",
		"expected_nonzero_exit": true,
		"observed_checks_failed": _failures.size(),
		"pass": _failures.is_empty(),
		"failures": _failures.duplicate(),
	}
	print("INTENTIONAL_FAILURE_PROOF " + JSON.stringify(proof))
	return proof


# --- Report -----------------------------------------------------------------


const LIMITATIONS := [
	"Pure in-memory mapping only: no scene, body, physics query, clock, rendering, audio device, input routing, motor integration, .tres write, bake manifest or gameplay claim is exercised.",
	"The positive fixture is the authored synthetic example recipe, not measured handling or production car content; its numbers are test inputs.",
	"Full JSON Schema, strict-parse, duplicate-member, content-hash and source null/unknowns pairing validation remains the external prerequisite owned by tools/car_recipe_schema/validate_car_recipe.py.",
	"Only identity, dimensions including optional nulls, intact mass, contact shape/roof/underside and the typed handling reference are mapped; every DEFERRED_FIELDS_V1 field stays absent and no coefficient is guessed.",
	"The draft is always INCOMPLETE: validation alone does not authorize a motor, a measured status or product-complete content.",
	"Headless pinned local engine only; no cross-version, exported-template, platform, controller, visual or release claim.",
]


func _finish(report: Dictionary, forced_exit: int = -1) -> void:
	if _finished:
		return
	_finished = true
	var passed := _failures.is_empty() and int(report.get("failed_cases", 0)) == 0
	var code := forced_exit
	if code < 0:
		code = 0 if passed else 1
	print("CAR_DRAFT_LAB_RESULT " + JSON.stringify(report))
	print("CHECKS_TOTAL=%d CHECKS_FAILED=%d" % [_checks, _failures.size()])
	quit(code)
