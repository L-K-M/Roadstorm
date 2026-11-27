class_name DataLabDriver
extends RefCounted
## Shared builders and assertion helpers for the M0.2 typed-resource data lab.
##
## The builders construct explicit synthetic fixtures, never production car
## content: IDs are `example.data_lab.*`, status is EXAMPLE, and every numeric
## value is an arbitrary authored test input. No coefficient here is measured,
## frozen or representative of a Roadstorm vehicle. This driver only builds
## resources, calls their real validation/save/load APIs and compares results;
## it does not re-implement validation rules.

const HandlingScript = preload("res://src/data/handling_definition.gd")
const CarScript = preload("res://src/data/car_definition.gd")

var checks := 0
var failures: Array[String] = []
var measured: Dictionary = {}


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func check_eq(actual, expected, message: String) -> void:
	checks += 1
	if actual != expected:
		failures.append(
			"%s (actual=%s expected=%s)" % [message, str(actual), str(expected)]
		)


func check_float_eq(actual: float, expected: float, tolerance: float, message: String) -> void:
	checks += 1
	if (
		is_nan(actual) or is_inf(actual) or is_nan(expected) or is_inf(expected)
		or absf(actual - expected) > tolerance
	):
		failures.append(
			"%s (actual=%s expected=%s tol=%s)"
			% [message, str(actual), str(expected), str(tolerance)]
		)


func check_between(value: float, low: float, high: float, message: String) -> void:
	checks += 1
	if is_nan(value) or is_inf(value) or value < low or value > high:
		failures.append(
			"%s (value=%s range=[%s,%s])"
			% [message, str(value), str(low), str(high)]
		)


func measure(key: String, value) -> void:
	measured[key] = value


## Synthetic valid handling fixture. Values are explicit test inputs chosen to
## exercise every validated field, not handling coefficients.
func valid_handling() -> HandlingDefinition:
	var handling := HandlingDefinition.new()
	handling.schema_version = HandlingDefinition.SUPPORTED_SCHEMA_VERSION
	handling.definition_id = "example.data_lab.handling"
	handling.revision = "0.1.0"
	handling.display_name = "Data Lab Example Handling"
	handling.status = DefinitionIdentity.Status.EXAMPLE
	handling.notes = "Synthetic validation fixture; arbitrary authored values, not measured handling."
	handling.set_acceleration_points([
		HandlingDefinition.AccelerationPoint.make(0.0, 6.0),
		HandlingDefinition.AccelerationPoint.make(20.0, 4.0),
		HandlingDefinition.AccelerationPoint.make(45.0, 0.5),
	])
	handling.braking_acceleration_m_s2 = 9.0
	handling.drag_aerodynamic = 0.002
	handling.drag_rolling = 0.4
	handling.yaw_gain_grip = 0.35
	handling.max_yaw_rate_rad_s = 2.5
	handling.lateral_damping_grip_per_s = 8.0
	handling.reverse_trigger_speed_m_s = 1.0
	handling.reverse_hold_time_s = 0.3
	handling.reverse_acceleration_m_s2 = 3.0
	handling.reverse_top_speed_m_s = 6.0
	return handling


## Synthetic draft car fixture. It deliberately lists every v1 deferred field,
## so it validates as an explicit DRAFT rather than pretending completeness.
func valid_car(handling = null) -> CarDefinition:
	var car := CarDefinition.new()
	car.schema_version = DefinitionIdentity.SUPPORTED_SCHEMA_VERSION
	car.definition_id = "example.data_lab.car"
	car.revision = "0.1.0"
	car.display_name = "Data Lab Example Car"
	car.status = DefinitionIdentity.Status.EXAMPLE
	car.notes = "Synthetic structural draft; no production car content."
	car.length_m = 4.2
	car.width_m = 1.9
	car.height_m = 1.3
	car.wheelbase_m = 2.7
	car.ground_clearance_m = 0.12
	car.jump_envelope_m = 0.6
	car.mass_kg = 1250.0
	car.contact_proxy_shape = CarDefinition.ContactProxyShape.ROUNDED_BOX
	car.handling = handling if handling != null else valid_handling()
	car.completeness = CarDefinition.Completeness.DRAFT
	car.completeness_note = (
		"M0.2 structural draft: presentation, engine, upgrades, damage and "
		+ "remaining handling fields are not authored yet."
	)
	car.deferred_fields = PackedStringArray(CarDefinition.DEFERRED_FIELDS_V1)
	return car


func save_resource(resource: Resource, path: String) -> Error:
	return ResourceSaver.save(resource, path)


func load_resource(path: String):
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


## Assert that a diagnostic list contains at least one entry containing
## `token`. Returns the first matching entry, or "" when none matches.
func expect_diagnostic(token: String, diagnostics: Array[String], label: String) -> String:
	check(not diagnostics.is_empty(), "%s produces at least one diagnostic" % label)
	for entry in diagnostics:
		if token in entry:
			return entry
	check(
		false,
		"%s diagnostic mentions '%s' (diagnostics=%s)"
		% [label, token, str(diagnostics)]
	)
	return ""
