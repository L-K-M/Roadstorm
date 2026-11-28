class_name CarRecipeMapper
extends RefCounted
## Pure source-recipe to typed car-DRAFT mapper for the M0.2 slice.
##
## Stable API:
##
##     var result := CarRecipeMapper.map_draft(recipe, handling)
##     if result.ok:
##         var car := result.car  # fully validated partial CarDefinition
##     else:
##         for diagnostic in result.diagnostics: ...
##
## `map_draft(recipe: Dictionary, handling: HandlingDefinition) -> Result` is
## pure. It reads the supplied recipe and the already mapped typed handling,
## constructs a new `CarDefinition` in memory and never writes to either input,
## a nested member, a file, a resource or the scene tree. It applies no
## physics, imports no motor and guesses no coefficient. Callers must not read
## `car` unless `ok` is true.
##
## Scope. Exactly one externally checked version 1.1.0 motor-ready source
## recipe and its already mapped `HandlingDefinition` are accepted. The mapper
## copies identity, status, dimensions including optional nulls, intact mass,
## the contact shape/roof/underside description and a deep copy of the
## verified typed handling. Presentation meshes/LODs/paints/icons, engine top speed,
## upgrades, detachable parts and every deferred handling field stay absent
## exactly as `CarDefinition.DEFERRED_FIELDS_V1` declares them.
##
## Prerequisites and defensive scope. Full JSON Schema validation, strict JSON
## parsing, duplicate-member rejection, canonical content-hash verification
## and the source null/`unknowns` honesty pairing are external prerequisites
## owned by `tools/car_recipe_schema/validate_car_recipe.py`. This class does
## not re-implement those document-wide rules. It defensively refuses malformed
## dictionaries reaching it directly: unsupported or mistyped versions, a
## missing/wrong/non-validating handling, a handling whose content disagrees
## with the source recipe, missing or wrong units/coordinate frame,
## missing/null/unknown required mapped dimensions, mass or contact shape,
## resolved optional values that are also listed in `unknowns`, non-finite or
## wrongly typed numbers, out-of-envelope dimensions and malformed contact
## descriptions.
##
## Version dispatch is exact. Only source `schema_version` `"1.1.0"` can
## produce a draft. `"1.0.0"` is refused with the five missing `handling.*`
## paths added by 1.1.0; every other value, including a missing, non-string
## or trailing-newline version, is refused as unsupported. There is no
## migration between source versions.
##
## Handling agreement. The passed `handling` must exist and its derived ID
## (`<car_id>.handling`), revision, status and typed schema version must agree
## with the source recipe. The mapper then independently derives the expected
## typed handling from the same recipe with the committed
## `HandlingRecipeMapper.map_handling(recipe)` and requires that derivation to
## succeed; a missing or invalid source handling block refuses the draft with
## path-specific diagnostics instead of substituting typed defaults. Every
## core exported handling field is compared exactly with the expected one:
## the derived display name, both acceleration curve arrays element-by-element
## in order, braking, aerodynamic/rolling drag, grip yaw, finite-or-unlimited
## max yaw, lateral damping and all four reverse values. Comparison is exact
## binary64 equality (signed zero included); no tolerance is applied and the
## expected handling is never substituted for the passed one. Any difference
## refuses with a path-specific `handling-content-mismatch` diagnostic.
## The constructed car runs the referenced handling's full validation through
## `CarDefinition.validate()`, so a physically or identity-invalid handling
## makes the draft invalid. Changing a car's inline handling therefore requires
## a car revision change.
##
## The attached handling is a deep copy of the now-verified passed handling,
## so later caller mutation cannot invalidate an already returned draft. The
## external checker remains the authority for whole-document JSON Schema,
## strict-parse, duplicate-member, canonical content-hash and source
## null/`unknowns` honesty rules; this class does not claim those guarantees.
##
## Completeness. Every draft is INCOMPLETE with a fixed honest note and the
## exact `CarDefinition.DEFERRED_FIELDS_V1` list. COMPLETE is never claimed and
## no production-readiness, measured-status or motor authorization is implied.
## Validation alone does not authorize a motor.
##
## Diagnostics are `"<dotted.path>: <code>: <message>"` strings addressing
## source paths, except the final `CarDefinition.validate()` diagnostics,
## which use the typed resource's own paths. A success carries `ok == true`, a
## fully valid car and an empty diagnostic list. A refusal carries
## `ok == false`, `car == null` and at least one path-level diagnostic; no
## half-mapped result is ever returned.

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

## Source lifecycle names accepted by the source schema, in typed enum order.
const SOURCE_STATUS_NAMES: Array[String] = [
	"provisional", "measured", "frozen", "superseded", "example",
]

## Fixed completeness note for every mapped draft. It states the partial-slice
## truth and never claims motor readiness, a measured status or production
## completeness.
const DRAFT_COMPLETENESS_NOTE := (
	"M0.2 partial draft mapped from a source recipe; "
	+ "CarDefinition.DEFERRED_FIELDS_V1 remain open; "
	+ "not motor-ready, measured or production-complete."
)

## Outcome of `map_draft`. `ok` is the only success signal: a refusal always
## has a null `car`, and a success always has an empty `diagnostics` list.
class Result extends RefCounted:
	var ok := false
	var car: CarDefinition = null
	var diagnostics: Array[String] = []
	var source_schema_version := ""

	func is_ok() -> bool:
		return ok and car != null and diagnostics.is_empty()


## Validated identity copied into the typed resource.
class _SourceIdentity extends RefCounted:
	var car_id := ""
	var display_name := ""
	var revision := ""
	var status := 0


## Mapped source values after defensive reading. Every member is only
## meaningful when the mapper returns no diagnostics.
class _DraftFields extends RefCounted:
	var length_m := 0.0
	var width_m := 0.0
	var height_m := 0.0
	var wheelbase_m: Variant = null
	var ground_clearance_m: Variant = null
	var jump_envelope_m: Variant = null
	var mass_kg := 0.0
	var contact_shape: CarDefinition.ContactProxyShape = CarDefinition.ContactProxyShape.ROUNDED_BOX
	var contact_roof: Variant = null
	var contact_underside: Variant = null


## Map one externally checked 1.1.0 source recipe and its already mapped typed
## handling to a validated partial `CarDefinition`, or refuse it with
## path-level diagnostics. See the class documentation for the stable API,
## prerequisites, agreement rules and refusal guarantees.
static func map_draft(recipe: Dictionary, handling: HandlingDefinition) -> Result:
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
	if not diagnostics.is_empty():
		result.diagnostics = diagnostics
		return result

	_check_handling_agreement(handling, identity, diagnostics)
	var expected_handling_result := HandlingRecipeMapper.map_handling(recipe)
	if not expected_handling_result.ok:
		diagnostics.append(
			"handling: handling-content-mismatch: the source recipe does not "
			+ "derive the expected typed handling"
		)
		diagnostics.append_array(expected_handling_result.diagnostics)
	else:
		_check_handling_content(handling, expected_handling_result.handling, diagnostics)
	_read_units(recipe, diagnostics)
	_read_coordinate_frame(recipe, diagnostics)

	var fields := _DraftFields.new()
	var unknown_paths := _unknown_paths(recipe)
	_read_dimensions(recipe, unknown_paths, fields, diagnostics)
	_read_mass(recipe, unknown_paths, fields, diagnostics)
	_read_contact_proxy(recipe, unknown_paths, fields, diagnostics)
	if not diagnostics.is_empty():
		result.diagnostics = diagnostics
		return result

	var car := _build_car(identity, fields, handling)
	var validation := car.validate()
	if not validation.is_empty():
		result.diagnostics = validation
		return result

	result.ok = true
	result.car = car
	return result


# --- Identity ----------------------------------------------------------------


static func _read_identity(recipe: Dictionary, diagnostics: Array[String]) -> _SourceIdentity:
	var identity := _SourceIdentity.new()

	var car_id: Variant = recipe.get("car_id")
	if typeof(car_id) != TYPE_STRING:
		diagnostics.append(
			"car_id: bad-car-id: expected a string, got %s" % type_string(typeof(car_id))
		)
	elif not DefinitionIdentity.is_valid_definition_id(car_id):
		diagnostics.append(
			"car_id: bad-car-id: '%s' does not match the stable semantic ID grammar" % car_id
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


# --- Handling agreement ------------------------------------------------------


## Require the already mapped handling to belong to this source recipe. The
## derived ID convention, revision, lifecycle status and typed schema version
## are pinned; the physical values and remaining identity fields are checked
## by the constructed car's own referenced-handling validation.
static func _check_handling_agreement(
	handling: HandlingDefinition,
	identity: _SourceIdentity,
	diagnostics: Array[String]
) -> void:
	if handling == null:
		diagnostics.append(
			"handling: missing-handling: an already mapped HandlingDefinition "
			+ "agreeing with the source recipe is required"
		)
		return

	var expected_id := "%s.handling" % identity.car_id
	if handling.definition_id != expected_id:
		diagnostics.append(
			"handling.definition_id: handling-identity-mismatch: expected '%s', got '%s'"
			% [expected_id, handling.definition_id]
		)
	if handling.revision != identity.revision:
		diagnostics.append(
			"handling.revision: handling-revision-mismatch: expected '%s', got '%s'"
			% [identity.revision, handling.revision]
		)
	if int(handling.status) != int(identity.status):
		diagnostics.append(
			"handling.status: handling-status-mismatch: expected %d, got %d"
			% [int(identity.status), int(handling.status)]
		)
	if handling.schema_version != TYPED_SCHEMA_VERSION:
		diagnostics.append(
			"handling.schema_version: handling-schema-version-mismatch: expected '%s', got '%s'"
			% [TYPED_SCHEMA_VERSION, handling.schema_version]
		)


# --- Units and coordinate frame ---------------------------------------------


## Require every core exported handling field to agree exactly with the typed
## handling derived from this same source recipe. Identity tags are checked
## separately; a null passed handling is already diagnosed as missing.
static func _check_handling_content(
	handling: HandlingDefinition,
	expected: HandlingDefinition,
	diagnostics: Array[String]
) -> void:
	if handling == null:
		return
	if handling.display_name != expected.display_name:
		_content_mismatch(
			"handling.display_name",
			"'%s'" % expected.display_name,
			"'%s'" % handling.display_name,
			diagnostics,
		)
	_compare_float_array(
		"handling.acceleration_curve_speeds_m_s",
		expected.acceleration_curve_speeds_m_s,
		handling.acceleration_curve_speeds_m_s,
		diagnostics,
	)
	_compare_float_array(
		"handling.acceleration_curve_accelerations_m_s2",
		expected.acceleration_curve_accelerations_m_s2,
		handling.acceleration_curve_accelerations_m_s2,
		diagnostics,
	)
	_compare_float(
		"handling.braking_acceleration_m_s2",
		expected.braking_acceleration_m_s2,
		handling.braking_acceleration_m_s2,
		diagnostics,
	)
	_compare_float(
		"handling.drag_aerodynamic",
		expected.drag_aerodynamic,
		handling.drag_aerodynamic,
		diagnostics,
	)
	_compare_float(
		"handling.drag_rolling",
		expected.drag_rolling,
		handling.drag_rolling,
		diagnostics,
	)
	_compare_float(
		"handling.yaw_gain_grip",
		expected.yaw_gain_grip,
		handling.yaw_gain_grip,
		diagnostics,
	)
	# INF is the authored unlimited-yaw encoding. Comparing it exactly keeps
	# finite/unlimited distinct instead of treating both as "large enough".
	_compare_float(
		"handling.max_yaw_rate_rad_s",
		expected.max_yaw_rate_rad_s,
		handling.max_yaw_rate_rad_s,
		diagnostics,
	)
	_compare_float(
		"handling.lateral_damping_grip_per_s",
		expected.lateral_damping_grip_per_s,
		handling.lateral_damping_grip_per_s,
		diagnostics,
	)
	_compare_float(
		"handling.reverse_trigger_speed_m_s",
		expected.reverse_trigger_speed_m_s,
		handling.reverse_trigger_speed_m_s,
		diagnostics,
	)
	_compare_float(
		"handling.reverse_hold_time_s",
		expected.reverse_hold_time_s,
		handling.reverse_hold_time_s,
		diagnostics,
	)
	_compare_float(
		"handling.reverse_acceleration_m_s2",
		expected.reverse_acceleration_m_s2,
		handling.reverse_acceleration_m_s2,
		diagnostics,
	)
	_compare_float(
		"handling.reverse_top_speed_m_s",
		expected.reverse_top_speed_m_s,
		handling.reverse_top_speed_m_s,
		diagnostics,
	)


## Exact binary64 equality for one mapped coefficient. NaN never agrees with
## itself; +0.0 and -0.0 compare equal in GDScript but differ in sign bit, so
## their reciprocals distinguish them without lossy string formatting or a
## tolerance that could hide a one-bit difference.
static func _same_float(expected: float, actual: float) -> bool:
	if is_nan(expected) or is_nan(actual):
		return false
	if expected != actual:
		return false
	return (1.0 / expected) == (1.0 / actual)


static func _compare_float(
	path: String,
	expected: float,
	actual: float,
	diagnostics: Array[String]
) -> void:
	if not _same_float(expected, actual):
		_content_mismatch(path, str(expected), str(actual), diagnostics)


static func _compare_float_array(
	path: String,
	expected: Array[float],
	actual: Array[float],
	diagnostics: Array[String]
) -> void:
	if expected.size() != actual.size():
		_content_mismatch(
			path,
			"an array of %d entries" % expected.size(),
			"an array of %d entries" % actual.size(),
			diagnostics,
		)
		return
	for index in range(expected.size()):
		if not _same_float(expected[index], actual[index]):
			_content_mismatch(
				"%s[%d]" % [path, index],
				str(expected[index]),
				str(actual[index]),
				diagnostics,
			)


static func _content_mismatch(
	path: String,
	expected: String,
	actual: String,
	diagnostics: Array[String]
) -> void:
	diagnostics.append(
		"%s: handling-content-mismatch: expected %s, got %s"
		% [path, expected, actual]
	)


static func _read_units(recipe: Dictionary, diagnostics: Array[String]) -> void:
	var units: Variant = recipe.get("units")
	if typeof(units) != TYPE_DICTIONARY:
		diagnostics.append(
			"units: bad-units: expected an object declaring length '%s', mass '%s', "
			% [DefinitionIdentity.UNIT_LENGTH, DefinitionIdentity.UNIT_MASS]
			+ "time '%s', angle '%s', got %s"
			% [DefinitionIdentity.UNIT_TIME, DefinitionIdentity.UNIT_ANGLE, type_string(typeof(units))]
		)
		return
	var units_dict: Dictionary = units
	var expected := {
		"length": DefinitionIdentity.UNIT_LENGTH,
		"mass": DefinitionIdentity.UNIT_MASS,
		"time": DefinitionIdentity.UNIT_TIME,
		"angle": DefinitionIdentity.UNIT_ANGLE,
	}
	for key in expected.keys():
		var path := "units.%s" % key
		if not units_dict.has(key):
			_missing_field(path, diagnostics)
			continue
		var value: Variant = units_dict[key]
		if typeof(value) != TYPE_STRING or value != expected[key]:
			diagnostics.append(
				"%s: bad-unit: expected '%s' (the documented car unit), got %s"
				% [path, expected[key], str(value)]
			)


static func _read_coordinate_frame(recipe: Dictionary, diagnostics: Array[String]) -> void:
	var frame: Variant = recipe.get("coordinate_frame")
	if typeof(frame) != TYPE_DICTIONARY:
		diagnostics.append(
			"coordinate_frame: bad-coordinate-frame: expected an object declaring "
			+ "forward '%s', up '%s', origin '%s', got %s"
			% [
				DefinitionIdentity.FRAME_FORWARD,
				DefinitionIdentity.FRAME_UP,
				DefinitionIdentity.FRAME_ORIGIN,
				type_string(typeof(frame)),
			]
		)
		return
	var frame_dict: Dictionary = frame
	var expected := {
		"forward": DefinitionIdentity.FRAME_FORWARD,
		"up": DefinitionIdentity.FRAME_UP,
		"origin": DefinitionIdentity.FRAME_ORIGIN,
	}
	for key in expected.keys():
		var path := "coordinate_frame.%s" % key
		if not frame_dict.has(key):
			_missing_field(path, diagnostics)
			continue
		var value: Variant = frame_dict[key]
		if typeof(value) != TYPE_STRING or value != expected[key]:
			diagnostics.append(
				"%s: bad-frame: expected '%s' (the documented car frame), got %s"
				% [path, expected[key], str(value)]
			)


# --- Dimensions, mass and contact envelope ----------------------------------


static func _read_dimensions(
	recipe: Dictionary,
	unknown_paths: Array[String],
	fields: _DraftFields,
	diagnostics: Array[String]
) -> void:
	var dimensions: Variant = recipe.get("dimensions")
	if typeof(dimensions) != TYPE_DICTIONARY:
		diagnostics.append(
			"dimensions: bad-dimensions: expected an object, got %s"
			% type_string(typeof(dimensions))
		)
		return
	var dimensions_dict: Dictionary = dimensions

	var length: Variant = _read_required_float(
		dimensions_dict, "length_m", "dimensions.length_m", unknown_paths, diagnostics
	)
	if length != null:
		fields.length_m = float(length)
	var width: Variant = _read_required_float(
		dimensions_dict, "width_m", "dimensions.width_m", unknown_paths, diagnostics
	)
	if width != null:
		fields.width_m = float(width)
	var height: Variant = _read_required_float(
		dimensions_dict, "height_m", "dimensions.height_m", unknown_paths, diagnostics
	)
	if height != null:
		fields.height_m = float(height)

	fields.wheelbase_m = _read_optional_number(
		dimensions_dict, "wheelbase_m", "dimensions.wheelbase_m", unknown_paths, diagnostics
	)
	fields.ground_clearance_m = _read_optional_number(
		dimensions_dict,
		"ground_clearance_m",
		"dimensions.ground_clearance_m",
		unknown_paths,
		diagnostics,
	)
	fields.jump_envelope_m = _read_optional_number(
		dimensions_dict,
		"jump_envelope_m",
		"dimensions.jump_envelope_m",
		unknown_paths,
		diagnostics,
	)


static func _read_mass(
	recipe: Dictionary,
	unknown_paths: Array[String],
	fields: _DraftFields,
	diagnostics: Array[String]
) -> void:
	var mass: Variant = _read_required_float(
		recipe, "mass_kg", "mass_kg", unknown_paths, diagnostics
	)
	if mass != null:
		fields.mass_kg = float(mass)


static func _read_contact_proxy(
	recipe: Dictionary,
	unknown_paths: Array[String],
	fields: _DraftFields,
	diagnostics: Array[String]
) -> void:
	var proxy: Variant = recipe.get("contact_proxy")
	if typeof(proxy) != TYPE_DICTIONARY:
		diagnostics.append(
			"contact_proxy: bad-contact-proxy: expected an object, got %s"
			% type_string(typeof(proxy))
		)
		return
	var proxy_dict: Dictionary = proxy

	const SHAPE_PATH := "contact_proxy.shape"
	if not proxy_dict.has("shape"):
		_missing_field(SHAPE_PATH, diagnostics)
	elif _path_is_unknown(SHAPE_PATH, unknown_paths):
		_unknown_input(SHAPE_PATH, diagnostics)
	else:
		var shape: Variant = proxy_dict["shape"]
		if shape == null:
			_unresolved_input(SHAPE_PATH, diagnostics)
		elif typeof(shape) != TYPE_STRING:
			diagnostics.append(
				"%s: bad-contact-shape: expected 'rounded_box' or 'convex_hull', got %s"
				% [SHAPE_PATH, type_string(typeof(shape))]
			)
		elif shape == "rounded_box":
			fields.contact_shape = CarDefinition.ContactProxyShape.ROUNDED_BOX
		elif shape == "convex_hull":
			fields.contact_shape = CarDefinition.ContactProxyShape.CONVEX_HULL
		else:
			diagnostics.append(
				"%s: bad-contact-shape: expected 'rounded_box' or 'convex_hull', got '%s'"
				% [SHAPE_PATH, shape]
			)

	const DERIVED_PATH := "contact_proxy.derived_from"
	if not proxy_dict.has("derived_from"):
		_missing_field(DERIVED_PATH, diagnostics)
	else:
		var derived: Variant = proxy_dict["derived_from"]
		if typeof(derived) != TYPE_STRING or derived != "declared_dimensions":
			diagnostics.append(
				"%s: bad-derived-from: expected 'declared_dimensions', got %s"
				% [DERIVED_PATH, str(derived)]
			)

	fields.contact_roof = _read_optional_text(
		proxy_dict, "roof", "contact_proxy.roof", unknown_paths, diagnostics
	)
	fields.contact_underside = _read_optional_text(
		proxy_dict, "underside", "contact_proxy.underside", unknown_paths, diagnostics
	)


# --- Field readers -----------------------------------------------------------


## Read a required numeric member. Returns null after appending a diagnostic
## on any defect; every valid source number converts to a finite float.
static func _read_required_float(
	container: Dictionary,
	key: String,
	path: String,
	unknown_paths: Array[String],
	diagnostics: Array[String]
) -> Variant:
	if not container.has(key):
		_missing_field(path, diagnostics)
		return null
	if _path_is_unknown(path, unknown_paths):
		_unknown_input(path, diagnostics)
		return null
	var value: Variant = container[key]
	if value == null:
		_unresolved_input(path, diagnostics)
		return null
	return _as_finite_number(value, path, diagnostics)


## Read an optional numeric member. A present null stays null and is preserved;
## a resolved value that is also listed in `unknowns` is refused because a
## resolved value may not also be undetermined. A wrongly typed or non-finite
## value is left for `CarDefinition.validate()` to diagnose at the same path.
static func _read_optional_number(
	container: Dictionary,
	key: String,
	path: String,
	unknown_paths: Array[String],
	diagnostics: Array[String]
) -> Variant:
	if not container.has(key):
		_missing_field(path, diagnostics)
		return null
	var value: Variant = container[key]
	if _path_is_unknown(path, unknown_paths):
		if value == null:
			return null
		diagnostics.append(
			"%s: resolved-value-unknown: the resolved value %s is also listed "
			% [path, str(value)]
			+ "in unknowns; a resolved value may not also be undetermined"
		)
		return null
	return value


## Read an optional contact description. Null is preserved; a resolved value
## listed in `unknowns` is refused, and a non-string resolved value is
## diagnosed at the source path.
static func _read_optional_text(
	container: Dictionary,
	key: String,
	path: String,
	unknown_paths: Array[String],
	diagnostics: Array[String]
) -> Variant:
	if not container.has(key):
		_missing_field(path, diagnostics)
		return null
	var value: Variant = container[key]
	if _path_is_unknown(path, unknown_paths):
		if value == null:
			return null
		diagnostics.append(
			"%s: resolved-value-unknown: the resolved value %s is also listed "
			% [path, str(value)]
			+ "in unknowns; a resolved value may not also be undetermined"
		)
		return null
	if value == null:
		return null
	if typeof(value) != TYPE_STRING:
		diagnostics.append(
			"%s: bad-contact-description: expected a string description or null, got %s"
			% [path, type_string(typeof(value))]
		)
		return null
	return value


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
		diagnostics.append("%s: %s: non-finite number %s" % [path, code, str(number)])
		return null
	return number


# --- Unknowns ---------------------------------------------------------------


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
			paths.append(candidate)
	return paths


## A mapped value counts as listed in `unknowns` when an entry names it
## exactly or names an enclosing object/array prefix of it.
static func _path_is_unknown(path: String, unknown_paths: Array[String]) -> bool:
	for candidate in unknown_paths:
		if path == candidate or path.begins_with(candidate + "."):
			return true
	return false


# --- Draft construction -----------------------------------------------------


## Build the partial car from only the read fields and a deep copy of the
## verified passed handling. Optional undetermined dimensions/contact
## descriptions stay null; deferred fields are declared exactly as
## `CarDefinition.DEFERRED_FIELDS_V1` lists them; completeness is INCOMPLETE
## with the fixed honest note.
static func _build_car(
	identity: _SourceIdentity,
	fields: _DraftFields,
	handling: HandlingDefinition
) -> CarDefinition:
	var car := CarDefinition.new()
	car.schema_version = TYPED_SCHEMA_VERSION
	car.definition_id = identity.car_id
	car.display_name = identity.display_name
	car.revision = identity.revision
	car.status = int(identity.status)
	car.length_m = fields.length_m
	car.width_m = fields.width_m
	car.height_m = fields.height_m
	car.wheelbase_m = fields.wheelbase_m
	car.ground_clearance_m = fields.ground_clearance_m
	car.jump_envelope_m = fields.jump_envelope_m
	car.mass_kg = fields.mass_kg
	car.contact_proxy_shape = fields.contact_shape
	car.contact_roof = fields.contact_roof
	car.contact_underside = fields.contact_underside
	car.handling = _copy_verified_handling(handling)
	car.completeness = CarDefinition.Completeness.INCOMPLETE
	car.completeness_note = DRAFT_COMPLETENESS_NOTE
	var deferred := PackedStringArray()
	for path in CarDefinition.DEFERRED_FIELDS_V1:
		deferred.append(String(path))
	car.deferred_fields = deferred
	return car


## Attach an independent in-memory copy of the already content-verified
## handling. Pinned Godot 4.7.2 duplicates the resource, its script and its
## exported values, including the two typed float arrays; the explicit array
## duplicates make that independence robust regardless of container sharing.
## The original `.tres` export/reload contract is untouched: the copy has the
## same script and exported property types as the supplied resource.
static func _copy_verified_handling(handling: HandlingDefinition) -> HandlingDefinition:
	var copy := handling.duplicate(true) as HandlingDefinition
	copy.acceleration_curve_speeds_m_s = copy.acceleration_curve_speeds_m_s.duplicate()
	copy.acceleration_curve_accelerations_m_s2 = (
		copy.acceleration_curve_accelerations_m_s2.duplicate()
	)
	return copy


# --- Diagnostic helpers ------------------------------------------------------


static func _missing_field(path: String, diagnostics: Array[String]) -> void:
	diagnostics.append("%s: missing-field: required member is absent" % path)


static func _unresolved_input(path: String, diagnostics: Array[String]) -> void:
	diagnostics.append(
		"%s: motor-input-unresolved: null/unresolved; a draft mapper must refuse "
		% path
		+ "rather than substitute a typed default"
	)


static func _unknown_input(path: String, diagnostics: Array[String]) -> void:
	diagnostics.append(
		"%s: motor-input-unknown: required mapped input is listed in unknowns; "
		% path
		+ "a resolved value may not also be undetermined"
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
