extends SceneTree
## Headless engine step for the M0.2 handling bake CLI.
##
## This script is invoked by `bake_handling_recipe.py` after the committed
## source checker has accepted the recipe in `motor-ready` mode. It loads the
## checked recipe, calls the committed pure mapper
## `HandlingRecipeMapper.map_handling`, runs `HandlingDefinition.validate()`,
## serializes the result as a `.tres`, reloads that `.tres` through
## `ResourceLoader` and compares every serialized field before reporting
## success. It writes its JSON report next to the resource inside the private
## staged project, and exits nonzero on every refusal.
##
## Scope: this is the M0.2 handling-definition slice only. It does not build a
## `CarDefinition`, does not import or cache resources for the game, does not
## author production content and does not claim M0.2 completion.
##
## Usage (normally driven by the Python entry point, never hand-run against a
## shared checkout because the project must be a private staged copy):
##
##   godot --headless --path <private-project> \
##       --script res://tools/car_recipe_bake/bake_handling.gd -- \
##       --recipe <checked-source-recipe.json>

const WORK_DIR := "res://car_recipe_bake_work"
const OUTPUT_RESOURCE := WORK_DIR + "/handling.tres"
const REPORT_PATH := WORK_DIR + "/bake_report.json"

## Source lifecycle names in `DefinitionIdentity.Status` declaration order.
const STATUS_NAMES: Array[String] = [
	"provisional", "measured", "frozen", "superseded", "example",
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var recipe_path := _flag_value(args, "--recipe")
	if recipe_path.is_empty():
		_fail("missing required --recipe <path>")
		return
	if not FileAccess.file_exists(recipe_path):
		_fail("recipe file does not exist: %s" % recipe_path)
		return

	var recipe_text := FileAccess.get_file_as_string(recipe_path)
	var parsed: Variant = JSON.parse_string(recipe_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("recipe is not a JSON object")
		return
	var recipe: Dictionary = parsed

	var result := HandlingRecipeMapper.map_handling(recipe)
	if not result.is_ok():
		for diagnostic in result.diagnostics:
			print("[car-recipe-bake] refusal: ", diagnostic)
		_write_report(_refusal_report(result.diagnostics, recipe))
		quit(1)
		return

	var handling: HandlingDefinition = result.handling
	var validation := handling.validate()
	if not validation.is_empty():
		for diagnostic in validation:
			print("[car-recipe-bake] validation: ", diagnostic)
		_write_report(_refusal_report(validation, recipe))
		quit(1)
		return

	var dir_error := DirAccess.make_dir_recursive_absolute(WORK_DIR)
	if dir_error != OK and not DirAccess.dir_exists_absolute(WORK_DIR):
		_fail("could not create private engine work directory %s" % WORK_DIR)
		return

	var save_error := ResourceSaver.save(handling, OUTPUT_RESOURCE)
	if save_error != OK:
		_fail("ResourceSaver.save failed with error %d for %s" % [save_error, OUTPUT_RESOURCE])
		return

	var loaded := ResourceLoader.load(
		OUTPUT_RESOURCE, "", ResourceLoader.CACHE_MODE_IGNORE
	)
	if loaded == null:
		_fail("ResourceLoader.reload returned null for %s" % OUTPUT_RESOURCE)
		return
	if not (loaded is HandlingDefinition):
		_fail(
			"ResourceLoader.reload returned %s, expected HandlingDefinition"
			% type_string(typeof(loaded))
		)
		return
	var reloaded: HandlingDefinition = loaded

	var comparison := _compare_round_trip(handling, reloaded)
	if not comparison["diagnostics"].is_empty():
		for diagnostic in comparison["diagnostics"]:
			print("[car-recipe-bake] round-trip: ", diagnostic)
		_write_report(
			_refusal_report(comparison["diagnostics"], recipe, result.source_schema_version)
		)
		quit(1)
		return

	var reloaded_validation := reloaded.validate()
	if not reloaded_validation.is_empty():
		for diagnostic in reloaded_validation:
			print("[car-recipe-bake] reloaded validation: ", diagnostic)
		_write_report(
			_refusal_report(reloaded_validation, recipe, result.source_schema_version)
		)
		quit(1)
		return

	# Report the reloaded resource, not only the in-memory mapping:
	# ResourceSaver omits properties equal to their script defaults, so an
	# in-memory value can differ from what the published .tres actually holds
	# (for example -0.0 against a +0.0 default). The bit gate below then binds
	# the source bytes to the persisted artifact.
	_write_report(
		_success_report(reloaded, result.source_schema_version, comparison["fields_compared"])
	)
	quit(0)


# --- Round trip --------------------------------------------------------------


## Compare every serialized `HandlingDefinition`/`DefinitionIdentity` field of
## the freshly mapped definition with the reloaded resource. Returns a
## Dictionary with `diagnostics` (Array[String]) and `fields_compared` (int).
func _compare_round_trip(
	original: HandlingDefinition, reloaded: HandlingDefinition
) -> Dictionary:
	var diagnostics: Array[String] = []
	var compared := 0

	compared += _compare_string(
		"schema_version", original.schema_version, reloaded.schema_version, diagnostics
	)
	compared += _compare_string(
		"definition_id", original.definition_id, reloaded.definition_id, diagnostics
	)
	compared += _compare_string(
		"revision", original.revision, reloaded.revision, diagnostics
	)
	compared += _compare_string(
		"display_name", original.display_name, reloaded.display_name, diagnostics
	)
	compared += _compare_string("notes", original.notes, reloaded.notes, diagnostics)
	compared += _compare_int("status", original.status, reloaded.status, diagnostics)

	compared += _compare_float_array(
		"acceleration_curve_speeds_m_s",
		original.acceleration_curve_speeds_m_s,
		reloaded.acceleration_curve_speeds_m_s,
		diagnostics,
	)
	compared += _compare_float_array(
		"acceleration_curve_accelerations_m_s2",
		original.acceleration_curve_accelerations_m_s2,
		reloaded.acceleration_curve_accelerations_m_s2,
		diagnostics,
	)

	compared += _compare_float(
		"braking_acceleration_m_s2",
		original.braking_acceleration_m_s2,
		reloaded.braking_acceleration_m_s2,
		diagnostics,
	)
	compared += _compare_float(
		"drag_aerodynamic", original.drag_aerodynamic, reloaded.drag_aerodynamic, diagnostics
	)
	compared += _compare_float(
		"drag_rolling", original.drag_rolling, reloaded.drag_rolling, diagnostics
	)
	compared += _compare_float(
		"yaw_gain_grip", original.yaw_gain_grip, reloaded.yaw_gain_grip, diagnostics
	)
	compared += _compare_float(
		"max_yaw_rate_rad_s",
		original.max_yaw_rate_rad_s,
		reloaded.max_yaw_rate_rad_s,
		diagnostics,
	)
	compared += _compare_float(
		"lateral_damping_grip_per_s",
		original.lateral_damping_grip_per_s,
		reloaded.lateral_damping_grip_per_s,
		diagnostics,
	)
	compared += _compare_float(
		"reverse_trigger_speed_m_s",
		original.reverse_trigger_speed_m_s,
		reloaded.reverse_trigger_speed_m_s,
		diagnostics,
	)
	compared += _compare_float(
		"reverse_hold_time_s",
		original.reverse_hold_time_s,
		reloaded.reverse_hold_time_s,
		diagnostics,
	)
	compared += _compare_float(
		"reverse_acceleration_m_s2",
		original.reverse_acceleration_m_s2,
		reloaded.reverse_acceleration_m_s2,
		diagnostics,
	)
	compared += _compare_float(
		"reverse_top_speed_m_s",
		original.reverse_top_speed_m_s,
		reloaded.reverse_top_speed_m_s,
		diagnostics,
	)

	return {"diagnostics": diagnostics, "fields_compared": compared}


static func _float_equal(left: float, right: float) -> bool:
	if is_inf(left) or is_inf(right):
		return is_inf(left) and is_inf(right) and sign(left) == sign(right)
	return left == right


func _compare_string(
	path: String, expected: String, actual: String, diagnostics: Array[String]
) -> int:
	if expected != actual:
		diagnostics.append(
			"%s: round-trip-mismatch: expected '%s', got '%s'"
			% [path, expected, actual]
		)
		return 0
	return 1


func _compare_int(path: String, expected: int, actual: int, diagnostics: Array[String]) -> int:
	if expected != actual:
		diagnostics.append(
			"%s: round-trip-mismatch: expected %d, got %d" % [path, expected, actual]
		)
		return 0
	return 1


func _compare_float(
	path: String, expected: float, actual: float, diagnostics: Array[String]
) -> int:
	if not _float_equal(expected, actual):
		diagnostics.append(
			"%s: round-trip-mismatch: expected %s, got %s"
			% [path, str(expected), str(actual)]
		)
		return 0
	return 1


func _compare_float_array(
	path: String, expected: Array[float], actual: Array[float], diagnostics: Array[String]
) -> int:
	if expected.size() != actual.size():
		diagnostics.append(
			"%s: round-trip-mismatch: expected %d entries, got %d"
			% [path, expected.size(), actual.size()]
		)
		return 0
	for index in range(expected.size()):
		if not _float_equal(expected[index], actual[index]):
			diagnostics.append(
				"%s[%d]: round-trip-mismatch: expected %s, got %s"
				% [path, index, str(expected[index]), str(actual[index])]
			)
			return 0
	return 1


# --- Reports -----------------------------------------------------------------


## Exact little-endian binary64 byte image of every numeric field in the
## reloaded `.tres`, keyed by dotted source path. Reporting the reloaded
## resource rather than the in-memory mapping means the gate compares the
## source bytes with what `ResourceSaver` actually persisted; a property that
## serialization dropped as a default cannot hide behind its mapped value.
## The Python entry point derives the same mapping from the frozen source bytes
## with the committed checker's parsing policy and refuses any difference
## before publication. Raw bits, not JSON decimal text, so a silently rounded,
## collapsed or sign-flipped value cannot pass.
func _numeric_source_bits(published: HandlingDefinition) -> Dictionary:
	var bits := {}
	for index in range(published.acceleration_curve_speeds_m_s.size()):
		bits[
			"handling.acceleration_curve[%d].speed_m_s" % index
		] = _binary64_hex(published.acceleration_curve_speeds_m_s[index])
		bits[
			"handling.acceleration_curve[%d].acceleration_m_s2" % index
		] = _binary64_hex(published.acceleration_curve_accelerations_m_s2[index])
	bits["handling.braking_acceleration_m_s2"] = _binary64_hex(
		published.braking_acceleration_m_s2
	)
	bits["handling.drag.aerodynamic"] = _binary64_hex(published.drag_aerodynamic)
	bits["handling.drag.rolling"] = _binary64_hex(published.drag_rolling)
	bits["handling.yaw_gain.grip"] = _binary64_hex(published.yaw_gain_grip)
	bits["handling.max_yaw_rate_rad_s"] = _binary64_hex(published.max_yaw_rate_rad_s)
	bits["handling.lateral_damping.grip_per_s"] = _binary64_hex(
		published.lateral_damping_grip_per_s
	)
	bits["handling.reverse_trigger_speed_m_s"] = _binary64_hex(
		published.reverse_trigger_speed_m_s
	)
	bits["handling.reverse_hold_time_s"] = _binary64_hex(published.reverse_hold_time_s)
	bits["handling.reverse_acceleration_m_s2"] = _binary64_hex(
		published.reverse_acceleration_m_s2
	)
	bits["handling.reverse_top_speed_m_s"] = _binary64_hex(
		published.reverse_top_speed_m_s
	)
	return bits


static func _binary64_hex(value: float) -> String:
	var buffer := StreamPeerBuffer.new()
	buffer.big_endian = false
	buffer.put_double(value)
	return buffer.data_array.hex_encode()


func _success_report(
	published: HandlingDefinition, source_schema_version: String, fields_compared: int
) -> Dictionary:
	var yaw_kind := "finite"
	if is_inf(published.max_yaw_rate_rad_s):
		yaw_kind = "INF"
	return {
		"ok": true,
		"source_schema_version": source_schema_version,
		"typed_schema_version": published.schema_version,
		"definition_id": published.definition_id,
		"revision": published.revision,
		"status": _status_name(published.status),
		"display_name": published.display_name,
		"validation_diagnostics": [],
		"mapping": {
			"curve_points": published.acceleration_curve_speeds_m_s.size(),
			"max_yaw_rate_rad_s": yaw_kind,
		},
		"numeric_source_bits": _numeric_source_bits(published),
		"round_trip": {
			"ok": true,
			"validated": true,
			"fields_compared": fields_compared,
		},
		"output_resource": OUTPUT_RESOURCE,
		"diagnostics": [],
	}


func _refusal_report(
	diagnostics: Array[String], recipe: Dictionary, source_schema_version := ""
) -> Dictionary:
	var car_id := ""
	if typeof(recipe.get("car_id")) == TYPE_STRING:
		car_id = recipe["car_id"]
	return {
		"ok": false,
		"source_schema_version": source_schema_version,
		"car_id": car_id,
		"validation_diagnostics": diagnostics,
		"round_trip": {"ok": false, "validated": false, "fields_compared": 0},
		"output_resource": "",
		"diagnostics": diagnostics,
	}


static func _status_name(status: int) -> String:
	if status >= 0 and status < STATUS_NAMES.size():
		return STATUS_NAMES[status]
	return "unknown"


# --- Completion --------------------------------------------------------------


func _write_report(report: Dictionary) -> void:
	var error := DirAccess.make_dir_recursive_absolute(WORK_DIR)
	if error != OK and not DirAccess.dir_exists_absolute(WORK_DIR):
		print("[car-recipe-bake] could not create report directory: ", error)
		return
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		print("[car-recipe-bake] could not open report for writing: ", REPORT_PATH)
		return
	file.store_string(JSON.stringify(report, "  ", true))
	file.close()


func _fail(message: String) -> void:
	print("[car-recipe-bake] FAIL: ", message)
	quit(1)


static func _flag_value(args: Array[String], flag: String) -> String:
	for index in range(args.size() - 1):
		if args[index] == flag:
			return args[index + 1]
	return ""
