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
const UpgradeScript = preload("res://src/data/upgrade_definition.gd")

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


## Count diagnostics containing `token`. Used by the source-recipe mapping
## cases to assert that a specific dotted path or code was reported.
func count_diagnostics(token: String, diagnostics: Array[String]) -> int:
	var count := 0
	for entry in diagnostics:
		if token in entry:
			count += 1
	return count


## Synthetic valid handling fixture. Values are explicit test inputs chosen to
## exercise every validated field, not handling coefficients. Its ID follows
## the documented baker derivation `<car_id>.handling` for the matching
## `valid_car()` fixture; the typed validator does not enforce that derivation,
## so other fixtures may reference a differently named valid handling.
func valid_handling() -> HandlingDefinition:
	var handling := HandlingDefinition.new()
	handling.schema_version = HandlingDefinition.SUPPORTED_SCHEMA_VERSION
	handling.definition_id = "example.data_lab.car.handling"
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
	# Non-default authored contact fields: a round trip that silently drops them
	# would reload the defaults (ROUNDED_BOX / null) and still compare equal if
	# the fixture used the defaults.
	car.contact_proxy_shape = CarDefinition.ContactProxyShape.CONVEX_HULL
	car.contact_roof = "Authored rounded-edge convex roof"
	car.contact_underside = "Authored flat underside pan"
	car.handling = handling if handling != null else valid_handling()
	car.completeness = CarDefinition.Completeness.DRAFT
	car.completeness_note = (
		"M0.2 structural draft: presentation, engine, upgrades, damage and "
		+ "remaining handling fields are not authored yet."
	)
	car.deferred_fields = PackedStringArray(CarDefinition.DEFERRED_FIELDS_V1)
	return car


## Synthetic valid upgrade fixture. Values are explicit test inputs chosen to
## exercise every validated field, not product upgrade content. Its ID uses
## the documented `example.data_lab.*` vocabulary with the category and level
## as stable segments, and it carries a non-default status EXAMPLE. The car ID
## is the same stable semantic ID family as `valid_car()`.
func valid_upgrade(
	category: UpgradeDefinition.Category = UpgradeDefinition.Category.ENGINE,
	level: int = 1
) -> UpgradeDefinition:
	var category_name := String(UpgradeDefinition.Category.keys()[category]).to_lower()
	var upgrade := UpgradeDefinition.new()
	upgrade.schema_version = DefinitionIdentity.SUPPORTED_SCHEMA_VERSION
	upgrade.definition_id = "example.data_lab.car.upgrade.%s.%d" % [category_name, level]
	upgrade.revision = "0.1.0"
	upgrade.display_name = "Data Lab Example %s Upgrade %d" % [
		String(UpgradeDefinition.Category.keys()[category]),
		level,
	]
	upgrade.status = DefinitionIdentity.Status.EXAMPLE
	upgrade.notes = (
		"Synthetic validation fixture; arbitrary authored values, not product upgrade content."
	)
	upgrade.car_id = "example.data_lab.car"
	upgrade.category = category
	upgrade.level = level
	upgrade.price_credits = int(UpgradeDefinition.PRICE_BY_LEVEL[level])
	return upgrade


## Synthetic version-1.1.0 source-recipe fixture for the handling mapper.
## Values are explicit test inputs chosen to exercise every mapped field, not
## measured handling coefficients. The shape follows
## schemas/handling_config_v1_1.schema.json; the mapper under test consumes only
## the motor-ready subset and never writes to the returned Dictionary. Pass a
## Dictionary as `max_yaw_rate_rad_s` to author the exact unlimited encoding.
func source_handling_recipe(
	schema_version: String = "1.1.0",
	car_id: String = "car.data_lab_mapper",
	display_name: String = "Data Lab Mapper Car",
	revision: String = "1.2.3",
	status: String = "example",
	max_yaw_rate_rad_s = 3.0,
	reverse_trigger_speed_m_s := 1.0,
	reverse_hold_time_s := 0.3,
	reverse_acceleration_m_s2 := 0.0,
	reverse_top_speed_m_s := 0.0
) -> Dictionary:
	var curve := [
		{"speed_m_s": 0.0, "acceleration_m_s2": 7.0},
		{"speed_m_s": 25.0, "acceleration_m_s2": 3.0},
	]
	return {
		"schema_version": schema_version,
		"car_id": car_id,
		"display_name": display_name,
		"revision": revision,
		"status": status,
		"units": {"length": "m", "mass": "kg", "time": "s", "angle": "deg"},
		"coordinate_frame": {
			"forward": "-Z",
			"up": "+Y",
			"origin": "ground_projection_of_axle_midpoint",
		},
		"dimensions": {
			"length_m": 4.2,
			"width_m": 1.9,
			"height_m": 1.4,
			"wheelbase_m": 2.6,
			"ground_clearance_m": 0.12,
			"jump_envelope_m": 0.4,
		},
		"mass_kg": 1100,
		"contact_proxy": {
			"shape": "rounded_box",
			"derived_from": "declared_dimensions",
			"roof": null,
			"underside": null,
		},
		"engine": {"top_speed_kmh": 220, "acceleration_curve": curve.duplicate()},
		"handling": {
			"acceleration_curve": curve.duplicate(),
			"braking_acceleration_m_s2": 8.0,
			"drag": {"aerodynamic": 0.003, "rolling": 0.3},
			"yaw_gain": {"grip": 1.5, "drift": 0.9},
			"lateral_damping": {"grip_per_s": 5.0, "drift_per_s": 1.5},
			"drift": {
				"entry_min_speed_m_s": 12.0,
				"entry_blend_s": 0.25,
				"target_slip_deg_min": 8.0,
				"target_slip_deg_max": 25.0,
				"recovery_blend_s": 0.4,
				"stability_assist_max_slip_deg": null,
			},
			"surge": {
				"candidate_deltas_m_s": [0.5, 1.0, 1.5],
				"duration_s": 1.5,
				"cooldown_s": 8.0,
				"stackable": false,
				"selected_delta_m_s": null,
			},
			"drafting": {
				"min_gap_m": 5.0,
				"max_gap_m": 20.0,
				"cone_deg": 10.0,
				"lateral_separation_m": 1.5,
				"eligible_s": 0.5,
				"fade_s": 1.0,
				"max_drag_reduction": 0.3,
				"stackable": false,
			},
			"airborne": {"gravity_m_s2": null, "adhesion_bounds": null},
			"contact_caps": {
				"solver_iterations": 8,
				"overlap_passes": 2,
				"max_single_correction_m": 0.05,
				"max_total_correction_m": 0.2,
			},
			"surfaces": [],
			"max_yaw_rate_rad_s": max_yaw_rate_rad_s,
			"reverse_trigger_speed_m_s": reverse_trigger_speed_m_s,
			"reverse_hold_time_s": reverse_hold_time_s,
			"reverse_acceleration_m_s2": reverse_acceleration_m_s2,
			"reverse_top_speed_m_s": reverse_top_speed_m_s,
		},
		"upgrades": {
			"levels": [0, 1, 2],
			"engine": {
				"acceleration_factors": [1.0, 1.1, 1.2],
				"top_speed_factors": [1.0, 1.05, 1.1],
			},
			"tires": {
				"grip_lateral_damping_factors": [1.0, 1.05, 1.1],
				"drift_exit_blend_divisors": [1.0, 1.1, 1.2],
			},
			"chassis": {
				"yaw_gain_factors": [1.0, 1.05, 1.1],
				"impact_speed_loss_factors": [0.2, 0.15, 0.1],
			},
			"max_increase_percent": {"acceleration": 20.0, "top_speed": 10.0},
		},
		"detachable_parts": [],
		"unknowns": [
			{"path": "handling.drift.stability_assist_max_slip_deg", "reason": "Not measured; synthetic fixture."},
			{"path": "handling.surge.selected_delta_m_s", "reason": "M1 selection pending."},
			{"path": "handling.airborne.gravity_m_s2", "reason": "Not authored."},
			{"path": "handling.airborne.adhesion_bounds", "reason": "Not authored."},
			{"path": "contact_proxy.roof", "reason": "Not authored."},
			{"path": "contact_proxy.underside", "reason": "Not authored."},
		],
		"provenance": {
			"source_contract": "roadstorm.handling_config.1.1.0",
			"author": "Data lab mapper fixture",
			"model": null,
			"provider": null,
			"date_utc": "2026-11-28",
			"note": "Synthetic fixture values; not measured handling.",
		},
		"content_hash": "sha256:%s" % ("0123456789abcdef" + "0123456789abcdef" + "0123456789abcdef" + "0123456789abcdef" + "0123456789abcdef" + "0123456789abcdef" + "0123456789abcdef" + "0123456789abcdef"),
	}


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
