class_name HandlingRecipeMapper
extends RefCounted
## Pure source-recipe to typed handling mapper for the M0.2 slice.
##
## Stable API:
##
##     var result := HandlingRecipeMapper.map_handling(recipe)
##     if result.ok:
##         var handling := result.handling  # HandlingDefinition
##     else:
##         for diagnostic in result.diagnostics: ...
##
## `map_handling(recipe: Dictionary) -> Result` is pure. It reads the supplied
## Dictionary and constructs a new `HandlingDefinition` in memory; it never
## writes to the input or its nested members, never touches the filesystem,
## resources on disk, the scene tree or the import cache, and applies no
## physics. A success carries `ok == true`, a fully validated definition and an
## empty diagnostic list. A refusal carries `ok == false`, `handling == null`
## and at least one path-level diagnostic; the typed defaults are never
## substituted for a missing, null, unknown or invalid source coefficient.
## Callers must not read `handling` unless `ok` is true.
##
## Prerequisites and defensive scope. Full JSON Schema validation, strict JSON
## parsing, duplicate-member rejection, canonical content-hash verification and
## the null/`unknowns` honesty pairing are external prerequisites owned by the
## source recipe checker (`tools/car_recipe_schema/validate_car_recipe.py`).
## This class does not re-implement those document-wide rules. It defensively
## refuses malformed dictionaries that reach it directly: unsupported or
## mistyped versions, missing/null/unknown motor inputs, wrong JSON/GDScript
## types, non-finite or out-of-range numbers, invalid acceleration points or
## ordering, bad identity/revision/status values, wrong source units and
## inconsistent reverse fields. It maps only the motor-ready core subset;
## engine top speed and its duplicated curve question, drift, surge, drafting,
## airborne, contact caps, surfaces, upgrades, presentation and detachable
## parts stay deferred exactly as `HandlingDefinition` documents.
##
## Version dispatch is exact. Only source `schema_version` `"1.1.0"` can
## produce a definition. `"1.0.0"` is refused with the five missing
## `handling.*` paths that 1.1.0 added; every other value, including a missing,
## non-string or trailing-newline version, is refused as unsupported. There is
## no migration between source versions.
##
## Identity derivation. `definition_id` becomes `<car_id>.handling`,
## `display_name` becomes `<car display_name> handling`, and the car recipe's
## triplet `revision` and lifecycle `status` are copied after validation. The
## typed `schema_version` stays `1.0.0` (`DefinitionIdentity`'s only accepted
## version); the source version belongs in the future bake manifest and
## provenance `source_contract`, never in the typed resource.
##
## Units. The source contract declares `units.angle == "deg"`; this mapper
## requires that context and copies `max_yaw_rate_rad_s` without conversion
## because that field is the documented field-level rad/s exception required
## by `ArcadeMotor.MotorTuning`. Speeds, accelerations and times are copied as
## authored m/s, m/s^2 and s.
##
## Diagnostics are `"<dotted.path>: <code>: <message>"` strings. Refusal
## diagnostics address source paths; when the constructed definition fails its
## own `validate()`, that validator's diagnostics are returned unchanged.

## Exact source contract version this mapper dispatches.
const SOURCE_SCHEMA_VERSION := "1.1.0"
## Historical contract version refused with the five missing motor inputs.
const REFUSED_SOURCE_VERSION_1_0_0 := "1.0.0"
## Typed contract version produced here; equals
## `DefinitionIdentity.SUPPORTED_SCHEMA_VERSION` and is deliberately never the
## source version.
const TYPED_SCHEMA_VERSION := "1.0.0"

## The five `handling.*` properties added by source contract 1.1.0. A 1.0.0
## recipe cannot supply any of them, so the refusal names all five paths.
const V1_0_0_MISSING_PATHS: Array[String] = [
	"handling.max_yaw_rate_rad_s",
	"handling.reverse_trigger_speed_m_s",
	"handling.reverse_hold_time_s",
	"handling.reverse_acceleration_m_s2",
	"handling.reverse_top_speed_m_s",
]

## Every source motor input the typed core subset needs, as dotted paths. All
## eleven must be present, non-null and absent from `unknowns`.
const MOTOR_INPUT_PATHS: Array[String] = [
	"handling.acceleration_curve",
	"handling.braking_acceleration_m_s2",
	"handling.drag.aerodynamic",
	"handling.drag.rolling",
	"handling.yaw_gain.grip",
	"handling.lateral_damping.grip_per_s",
	"handling.max_yaw_rate_rad_s",
	"handling.reverse_trigger_speed_m_s",
	"handling.reverse_hold_time_s",
	"handling.reverse_acceleration_m_s2",
	"handling.reverse_top_speed_m_s",
]

## Source lifecycle names accepted by the source schema, in typed enum order.
const SOURCE_STATUS_NAMES: Array[String] = [
	"provisional", "measured", "frozen", "superseded", "example",
]

## Reverse design bounds mirrored from `HandlingDefinition`. Authored source
## values may narrow these bounds, never widen them.
const REVERSE_TRIGGER_MAX_M_S := 1.0
const REVERSE_HOLD_MIN_S := 0.3

## Required motor values resolved from one source recipe. Every member is only
## meaningful when the mapper returns no diagnostics.
class _MappedFields extends RefCounted:
	var curve_speeds: Array[float] = []
	var curve_accelerations: Array[float] = []
	var braking := 0.0
	var drag_aerodynamic := 0.0
	var drag_rolling := 0.0
	var yaw_gain_grip := 0.0
	var max_yaw_rate_rad_s := 0.0
	var lateral_damping_grip_per_s := 0.0
	var reverse_trigger_speed_m_s := 0.0
	var reverse_hold_time_s := 0.0
	var reverse_acceleration_m_s2 := 0.0
	var reverse_top_speed_m_s := 0.0


## Validated identity copied or derived into the typed resource.
class _SourceIdentity extends RefCounted:
	var car_id := ""
	var display_name := ""
	var revision := ""
	var status := 0


## Outcome of `map_handling`. `ok` is the only success signal: a refusal always
## has a null `handling`, and a success always has an empty `diagnostics` list.
class Result extends RefCounted:
	var ok := false
	var handling: HandlingDefinition = null
	var diagnostics: Array[String] = []
	var source_schema_version := ""

	func is_ok() -> bool:
		return ok and handling != null and diagnostics.is_empty()


## Map one authored source recipe Dictionary to a typed `HandlingDefinition`,
## or refuse it with path-level diagnostics. See the class documentation for
## the stable API, prerequisites and refusal guarantees.
static func map_handling(recipe: Dictionary) -> Result:
	var result := Result.new()
	if typeof(recipe) != TYPE_DICTIONARY:
		result.diagnostics.append(
			"<document>: bad-recipe: expected a Dictionary, got %s"
			% type_string(typeof(recipe))
		)
		return result

	var version: Variant = recipe.get("schema_version")
	if typeof(version) != TYPE_STRING:
		result.diagnostics.append(_unsupported_version_diagnostic(version))
		return result
	result.source_schema_version = version
	if version == REFUSED_SOURCE_VERSION_1_0_0:
		for path in V1_0_0_MISSING_PATHS:
			result.diagnostics.append(
				"%s: missing-field: source contract 1.0.0 has no such property; "
				% path
				+ "a 1.0.0 recipe cannot supply this required typed motor input"
			)
		return result
	if version != SOURCE_SCHEMA_VERSION:
		result.diagnostics.append(_unsupported_version_diagnostic(version))
		return result

	var diagnostics: Array[String] = []
	var identity := _read_identity(recipe, diagnostics)
	var fields := _read_motor_fields(recipe, diagnostics)
	if not diagnostics.is_empty():
		result.diagnostics = diagnostics
		return result

	var handling := HandlingDefinition.new()
	handling.schema_version = TYPED_SCHEMA_VERSION
	handling.definition_id = "%s.handling" % identity.car_id
	handling.revision = identity.revision
	handling.display_name = "%s handling" % identity.display_name
	handling.status = int(identity.status)
	handling.acceleration_curve_speeds_m_s = fields.curve_speeds
	handling.acceleration_curve_accelerations_m_s2 = fields.curve_accelerations
	handling.braking_acceleration_m_s2 = fields.braking
	handling.drag_aerodynamic = fields.drag_aerodynamic
	handling.drag_rolling = fields.drag_rolling
	handling.yaw_gain_grip = fields.yaw_gain_grip
	handling.max_yaw_rate_rad_s = fields.max_yaw_rate_rad_s
	handling.lateral_damping_grip_per_s = fields.lateral_damping_grip_per_s
	handling.reverse_trigger_speed_m_s = fields.reverse_trigger_speed_m_s
	handling.reverse_hold_time_s = fields.reverse_hold_time_s
	handling.reverse_acceleration_m_s2 = fields.reverse_acceleration_m_s2
	handling.reverse_top_speed_m_s = fields.reverse_top_speed_m_s

	var validation := handling.validate()
	if not validation.is_empty():
		result.diagnostics = validation
		return result

	result.ok = true
	result.handling = handling
	return result


# --- Identity ----------------------------------------------------------------


static func _read_identity(recipe: Dictionary, diagnostics: Array[String]) -> _SourceIdentity:
	var identity := _SourceIdentity.new()

	var car_id: Variant = recipe.get("car_id")
	if typeof(car_id) != TYPE_STRING:
		diagnostics.append(
			"car_id: bad-car-id: expected a string, got %s"
			% type_string(typeof(car_id))
		)
	elif not DefinitionIdentity.is_valid_definition_id(car_id):
		diagnostics.append(
			"car_id: bad-car-id: '%s' does not match the stable semantic ID grammar"
			% car_id
		)
	else:
		identity.car_id = car_id

	var display_name: Variant = recipe.get("display_name")
	if typeof(display_name) != TYPE_STRING:
		diagnostics.append(
			"display_name: bad-display-name: expected a string, got %s"
			% type_string(typeof(display_name))
		)
	elif display_name.is_empty():
		diagnostics.append("display_name: bad-display-name: must be non-empty")
	else:
		identity.display_name = display_name

	var revision: Variant = recipe.get("revision")
	if typeof(revision) != TYPE_STRING:
		diagnostics.append(
			"revision: invalid-revision: expected a string, got %s"
			% type_string(typeof(revision))
		)
	elif not DefinitionIdentity.is_valid_revision(revision):
		diagnostics.append(
			"revision: invalid-revision: '%s' is not MAJOR.MINOR.PATCH without "
			% revision
			+ "leading zeros; the source revision is copied, never rewritten"
		)
	else:
		identity.revision = revision

	var status: Variant = recipe.get("status")
	if typeof(status) != TYPE_STRING:
		diagnostics.append(
			"status: bad-status: expected one of %s, got %s"
			% [str(SOURCE_STATUS_NAMES), type_string(typeof(status))]
		)
	elif not SOURCE_STATUS_NAMES.has(status):
		diagnostics.append(
			"status: bad-status: '%s' is not one of %s"
			% [status, str(SOURCE_STATUS_NAMES)]
		)
	else:
		identity.status = _mapped_status(status)

	var units: Variant = recipe.get("units")
	if typeof(units) != TYPE_DICTIONARY:
		diagnostics.append("units: bad-unit: units must be an object declaring m/kg/s/deg")
	else:
		var units_dict: Dictionary = units
		for name in ["length", "mass", "time", "angle"]:
			var expected := ""
			match name:
				"length": expected = "m"
				"mass": expected = "kg"
				"time": expected = "s"
				"angle": expected = "deg"
			var actual: Variant = units_dict.get(name)
			if typeof(actual) != TYPE_STRING or actual != expected:
				diagnostics.append(
					"units.%s: bad-unit: expected '%s', got %s"
					% [name, expected, str(actual)]
				)

	return identity


## One-to-one lowercase source lifecycle name to typed enum value. Callers
## validate membership first, so the default branch is unreachable.
static func _mapped_status(status_name: String) -> int:
	match status_name:
		"provisional":
			return DefinitionIdentity.Status.PROVISIONAL
		"measured":
			return DefinitionIdentity.Status.MEASURED
		"frozen":
			return DefinitionIdentity.Status.FROZEN
		"superseded":
			return DefinitionIdentity.Status.SUPERSEDED
		"example":
			return DefinitionIdentity.Status.EXAMPLE
		_:
			return DefinitionIdentity.Status.PROVISIONAL


# --- Motor inputs ------------------------------------------------------------


static func _read_motor_fields(
	recipe: Dictionary, diagnostics: Array[String]
) -> _MappedFields:
	var fields := _MappedFields.new()
	var handling: Variant = recipe.get("handling")
	if typeof(handling) != TYPE_DICTIONARY:
		diagnostics.append(
			"handling: bad-handling: expected an object, got %s"
			% type_string(typeof(handling))
		)
		return fields
	var handling_dict: Dictionary = handling
	var unknown_paths := _unknown_paths(recipe)

	_read_acceleration_curve(handling_dict, unknown_paths, fields, diagnostics)

	fields.braking = _read_required_float(
		handling_dict, "braking_acceleration_m_s2",
		"handling.braking_acceleration_m_s2", 0.0, INF,
		unknown_paths, diagnostics
	)
	fields.drag_aerodynamic = _read_child_required_float(
		handling_dict, "drag", "aerodynamic",
		"handling.drag.aerodynamic", 0.0, INF, unknown_paths, diagnostics
	)
	fields.drag_rolling = _read_child_required_float(
		handling_dict, "drag", "rolling",
		"handling.drag.rolling", 0.0, INF, unknown_paths, diagnostics
	)
	fields.yaw_gain_grip = _read_child_required_float(
		handling_dict, "yaw_gain", "grip",
		"handling.yaw_gain.grip", 0.0, INF, unknown_paths, diagnostics
	)
	fields.lateral_damping_grip_per_s = _read_child_required_float(
		handling_dict, "lateral_damping", "grip_per_s",
		"handling.lateral_damping.grip_per_s", 0.0, INF, unknown_paths, diagnostics
	)

	_read_max_yaw_rate(handling_dict, unknown_paths, fields, diagnostics)

	fields.reverse_trigger_speed_m_s = _read_required_float(
		handling_dict, "reverse_trigger_speed_m_s",
		"handling.reverse_trigger_speed_m_s", 0.0, REVERSE_TRIGGER_MAX_M_S,
		unknown_paths, diagnostics
	)
	fields.reverse_hold_time_s = _read_required_float(
		handling_dict, "reverse_hold_time_s",
		"handling.reverse_hold_time_s", REVERSE_HOLD_MIN_S, INF,
		unknown_paths, diagnostics
	)
	# -1.0 is the failure sentinel: every successful read is >= 0. A failed
	# read leaves the sentinel, so the cross-field rule is evaluated only when
	# both authored values were individually resolved.
	var reverse_acceleration := _read_required_float(
		handling_dict, "reverse_acceleration_m_s2",
		"handling.reverse_acceleration_m_s2", 0.0, INF,
		unknown_paths, diagnostics
	)
	var reverse_top_speed := _read_required_float(
		handling_dict, "reverse_top_speed_m_s",
		"handling.reverse_top_speed_m_s", 0.0, INF,
		unknown_paths, diagnostics
	)
	fields.reverse_acceleration_m_s2 = reverse_acceleration
	fields.reverse_top_speed_m_s = reverse_top_speed
	if (
		reverse_acceleration >= 0.0
		and reverse_top_speed >= 0.0
		and reverse_acceleration > 0.0
		and reverse_top_speed <= 0.0
	):
		diagnostics.append(
			"handling.reverse_top_speed_m_s: reverse-cross-field: reverse "
			+ "acceleration %s > 0 requires a positive reverse_top_speed_m_s"
			% str(reverse_acceleration)
		)

	return fields


static func _read_acceleration_curve(
	handling: Dictionary,
	unknown_paths: Array[String],
	fields: _MappedFields,
	diagnostics: Array[String]
) -> void:
	const PATH := "handling.acceleration_curve"
	if not handling.has("acceleration_curve"):
		_missing_field(PATH, diagnostics)
		return
	var curve: Variant = handling["acceleration_curve"]
	if curve == null:
		_unresolved_input(PATH, diagnostics)
		return
	if _path_is_unknown(PATH, unknown_paths):
		_unknown_input(PATH, diagnostics)
		return
	if typeof(curve) != TYPE_ARRAY:
		diagnostics.append(
			"%s: bad-acceleration-curve: expected an array, got %s"
			% [PATH, type_string(typeof(curve))]
		)
		return
	if curve.is_empty():
		diagnostics.append(
			"%s: motor-input-empty: at least one authored point is required" % PATH
		)
		return

	var speeds: Array[float] = []
	var accelerations: Array[float] = []
	var previous_speed := -INF
	for index in range(curve.size()):
		var point_path := "%s[%d]" % [PATH, index]
		var point: Variant = curve[index]
		if typeof(point) != TYPE_DICTIONARY:
			diagnostics.append(
				"%s: bad-acceleration-point: expected an object, got %s"
				% [point_path, type_string(typeof(point))]
			)
			continue
		var point_dict: Dictionary = point
		if _path_is_unknown(point_path, unknown_paths):
			_unknown_input(point_path, diagnostics)
			continue
		if not point_dict.has("speed_m_s"):
			_missing_field(point_path + ".speed_m_s", diagnostics)
		if not point_dict.has("acceleration_m_s2"):
			_missing_field(point_path + ".acceleration_m_s2", diagnostics)
		if not point_dict.has("speed_m_s") or not point_dict.has("acceleration_m_s2"):
			continue
		var unresolved_point := false
		for member in ["speed_m_s", "acceleration_m_s2"]:
			var member_path: String = point_path + "." + String(member)
			if point_dict[member] == null:
				_unresolved_input(member_path, diagnostics)
				unresolved_point = true
			elif _path_is_unknown(member_path, unknown_paths):
				_unknown_input(member_path, diagnostics)
				unresolved_point = true
		if unresolved_point:
			continue
		var speed: Variant = _as_finite_number(
			point_dict["speed_m_s"], point_path + ".speed_m_s", diagnostics
		)
		var acceleration: Variant = _as_finite_number(
			point_dict["acceleration_m_s2"],
			point_path + ".acceleration_m_s2",
			diagnostics
		)
		if speed == null or acceleration == null:
			continue
		if speed < 0.0:
			diagnostics.append(
				"%s.speed_m_s: bad-number: %s is below the minimum 0.0"
				% [point_path, str(speed)]
			)
		if acceleration < 0.0:
			diagnostics.append(
				"%s.acceleration_m_s2: bad-number: %s is below the minimum 0.0"
				% [point_path, str(acceleration)]
			)
		if speed <= previous_speed:
			diagnostics.append(
				"%s.speed_m_s: motor-input-order: %s does not strictly exceed "
				% [point_path, str(speed)]
				+ "previous speed %s" % str(previous_speed)
			)
		previous_speed = speed
		speeds.append(speed)
		accelerations.append(acceleration)
	fields.curve_speeds = speeds
	fields.curve_accelerations = accelerations


## Read a required scalar directly off `handling`. Returns -1.0 on any defect;
## every valid source value is >= 0.
static func _read_required_float(
	container: Dictionary,
	key: String,
	path: String,
	minimum: float,
	maximum: float,
	unknown_paths: Array[String],
	diagnostics: Array[String]
) -> float:
	if not container.has(key):
		_missing_field(path, diagnostics)
		return -1.0
	var value: Variant = container[key]
	if value == null:
		_unresolved_input(path, diagnostics)
		return -1.0
	if _path_is_unknown(path, unknown_paths):
		_unknown_input(path, diagnostics)
		return -1.0
	var number: Variant = _as_finite_number(value, path, diagnostics)
	if number == null:
		return -1.0
	if number < minimum:
		diagnostics.append(
			"%s: bad-number: %s is below the minimum %s"
			% [path, str(number), str(minimum)]
		)
		return -1.0
	if number > maximum:
		diagnostics.append(
			"%s: bad-number: %s is above the maximum %s"
			% [path, str(number), str(maximum)]
		)
		return -1.0
	return number


## Read a required scalar from a nested handling member such as `drag`. A
## missing or non-object parent reports both the parent defect and the child
## path, then returns the -1.0 failure sentinel.
static func _read_child_required_float(
	handling: Dictionary,
	parent_key: String,
	child_key: String,
	path: String,
	minimum: float,
	maximum: float,
	unknown_paths: Array[String],
	diagnostics: Array[String]
) -> float:
	var parent: Variant = handling.get(parent_key)
	if typeof(parent) != TYPE_DICTIONARY:
		diagnostics.append(
			"handling.%s: bad-object: handling.%s must be an object, got %s"
			% [parent_key, parent_key, type_string(typeof(parent))]
		)
		_missing_field(path, diagnostics)
		return -1.0
	return _read_required_float(
		parent, child_key, path, minimum, maximum, unknown_paths, diagnostics
	)


static func _read_max_yaw_rate(
	handling: Dictionary,
	unknown_paths: Array[String],
	fields: _MappedFields,
	diagnostics: Array[String]
) -> void:
	const PATH := "handling.max_yaw_rate_rad_s"
	if not handling.has("max_yaw_rate_rad_s"):
		_missing_field(PATH, diagnostics)
		return
	var value: Variant = handling["max_yaw_rate_rad_s"]
	if value == null:
		_unresolved_input(PATH, diagnostics)
		return
	if _path_is_unknown(PATH, unknown_paths):
		_unknown_input(PATH, diagnostics)
		return
	if typeof(value) == TYPE_DICTIONARY:
		var encoding: Dictionary = value
		if encoding.size() == 1 and encoding.has("unlimited"):
			var sentinel: Variant = encoding["unlimited"]
			if typeof(sentinel) == TYPE_BOOL and sentinel == true:
				fields.max_yaw_rate_rad_s = INF
				return
		diagnostics.append(
			'%s: bad-yaw-rate: unlimited must be the exact sole-member object '
			% PATH
			+ '{"unlimited": true}; null means unresolved and no typed default '
			+ "is substituted"
		)
		return
	var number: Variant = _as_finite_number(value, PATH, diagnostics, "bad-yaw-rate")
	if number == null:
		return
	if number <= 0.0:
		diagnostics.append(
			"%s: bad-yaw-rate: %s must be positive; use {\"unlimited\": true} "
			% [PATH, str(number)]
			+ "to author an uncapped yaw rate"
		)
		return
	fields.max_yaw_rate_rad_s = number


# --- Number conversion and unknowns -----------------------------------------


## Convert a Variant number honestly. Booleans are not numbers; integers and
## floats convert through `float()`; NaN and infinities are rejected rather
## than clamped. Returns null after appending a diagnostic on any defect.
static func _as_finite_number(
	value: Variant,
	path: String,
	diagnostics: Array[String],
	code := "bad-number"
) -> Variant:
	var value_type := typeof(value)
	if value_type != TYPE_FLOAT and value_type != TYPE_INT:
		diagnostics.append(
			"%s: %s: expected a finite number, got %s"
			% [path, code, type_string(value_type)]
		)
		return null
	var number := float(value)
	if is_nan(number) or is_inf(number):
		diagnostics.append(
			"%s: %s: non-finite number %s" % [path, code, str(number)]
		)
		return null
	return number


## Collect dotted paths from the recipe's `unknowns` list. Structural validity
## of that list is the external checker's job; this mapper only needs the
## membership set, so malformed entries contribute nothing.
static func _unknown_paths(recipe: Dictionary) -> Array[String]:
	var paths: Array[String] = []
	var unknowns: Variant = recipe.get("unknowns")
	if typeof(unknowns) != TYPE_ARRAY:
		return paths
	for entry in unknowns:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if not entry.has("path"):
			continue
		var candidate: Variant = entry["path"]
		if typeof(candidate) == TYPE_STRING and not candidate.is_empty():
			paths.append(_canonical_unknown_path(candidate))
	return paths


## The source checker accepts decimal array indices with leading zeros and
## resolves `[00]` to element zero. Normalize only digit runs here so a
## direct mapper caller cannot bypass an unknown declaration by its spelling.
## This is lexical: even an enormous malformed index never reaches int().
static func _canonical_unknown_path(path: String) -> String:
	var normalized := ""
	var position := 0
	while position < path.length():
		if path.substr(position, 1) != "[":
			normalized += path.substr(position, 1)
			position += 1
			continue
		var closing := path.find("]", position + 1)
		if closing < 0:
			return path
		var digits := path.substr(position + 1, closing - position - 1)
		if digits.is_empty():
			return path
		for digit in digits:
			if digit < "0" or digit > "9":
				return path
		var first := 0
		while first < digits.length() - 1 and digits.substr(first, 1) == "0":
			first += 1
		normalized += "[" + digits.substr(first) + "]"
		position = closing + 1
	return normalized


## A required input counts as listed in `unknowns` when an entry names it
## exactly or names an enclosing object/array prefix of it.
static func _path_is_unknown(path: String, unknown_paths: Array[String]) -> bool:
	for candidate in unknown_paths:
		if path == candidate or path.begins_with(candidate + "."):
			return true
	return false


# --- Diagnostic helpers ------------------------------------------------------


static func _missing_field(path: String, diagnostics: Array[String]) -> void:
	diagnostics.append("%s: missing-field: required member is absent" % path)


static func _unresolved_input(path: String, diagnostics: Array[String]) -> void:
	diagnostics.append(
		"%s: motor-input-unresolved: null/unresolved; a baker must refuse "
		% path
		+ "rather than substitute a typed default"
	)


static func _unknown_input(path: String, diagnostics: Array[String]) -> void:
	diagnostics.append(
		"%s: motor-input-unknown: required typed motor input is listed in "
		% path
		+ "unknowns; a resolved value may not also be undetermined"
	)


static func _unsupported_version_diagnostic(version: Variant) -> String:
	var rendered := str(version)
	if typeof(version) != TYPE_STRING:
		rendered = "%s (%s)" % [rendered, type_string(typeof(version))]
	return (
		"schema_version: unsupported-schema-version: '%s' is not '%s'; "
		% [rendered, SOURCE_SCHEMA_VERSION]
		+ "refused without migration"
	)
