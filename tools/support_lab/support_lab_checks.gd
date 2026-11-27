class_name SupportLabChecks
extends RefCounted
## Assertion collectors and explicit fixtures for the M1.4 ground-support
## sensing laboratory.
##
## This helper never re-implements probe math. It builds explicit configs,
## transforms and physics stages, calls the real `GroundSupportProbe`, and
## compares measured invariants. Failures are collected so the driver can emit
## machine-readable results and control its exit code.

const ProbeScript = preload("res://src/simulation/ground_support_probe.gd")

## Body origin height above the flat laboratory floor, metres. Hull height is
## 1.0 m, so the bottom face clears the floor by 5 cm, matching the body lab.
const BODY_SUPPORT_Y := 0.55
const HULL_SIZE := Vector3(1.8, 1.0, 3.8)

const CONFIG_FIELDS := [
	"hull_size_m",
	"ray_length_m",
	"max_support_distance_m",
	"footprint_inset_fraction",
	"min_up_dot",
	"min_frame_up_dot",
	"required_footprint_hits",
	"footprint_support_spread_max_m",
]

const PROBE_LABELS := [
	"center",
	"rear_right",
	"rear_left",
	"front_right",
	"front_left",
]

var checks := 0
var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func check_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	checks += 1
	if not _finite(actual) or absf(actual - expected) > tolerance:
		failures.append(
			"%s (actual=%s expected=%s tol=%s)" % [message, actual, expected, tolerance]
		)


func check_exact_float(actual: float, expected: float, message: String) -> void:
	checks += 1
	if actual != expected:
		failures.append("%s (actual=%s expected=%s)" % [message, actual, expected])


func check_vector_close(
	actual: Vector3,
	expected: Vector3,
	tolerance: float,
	message: String
) -> void:
	checks += 1
	if actual.distance_to(expected) > tolerance:
		failures.append(
			"%s (actual=%s expected=%s tol=%s)" % [message, actual, expected, tolerance]
		)


func check_same_float(actual: float, expected: float, message: String) -> void:
	checks += 1
	if is_nan(expected):
		if not is_nan(actual):
			failures.append("%s (expected NaN, got %s)" % [message, actual])
	elif actual != expected:
		failures.append("%s (actual=%s expected=%s)" % [message, actual, expected])


# ---------------------------------------------------------------------------
# Config fixtures
# ---------------------------------------------------------------------------


## Laboratory defaults, written explicitly so the test records the exact
## sensing envelope it used. These are provisional, not product handling.
func make_config() -> ProbeScript.Config:
	var config := ProbeScript.Config.new()
	config.hull_size_m = HULL_SIZE
	config.ray_length_m = 1.0
	config.max_support_distance_m = 0.75
	config.footprint_inset_fraction = 0.15
	config.min_up_dot = 0.5
	config.required_footprint_hits = 2
	config.footprint_support_spread_max_m = 0.25
	return config


func make_config_with(
	ray_length_m: float,
	max_support_distance_m: float,
	required_footprint_hits: int,
	footprint_support_spread_max_m: float
) -> ProbeScript.Config:
	var config := make_config()
	config.ray_length_m = ray_length_m
	config.max_support_distance_m = max_support_distance_m
	config.required_footprint_hits = required_footprint_hits
	config.footprint_support_spread_max_m = footprint_support_spread_max_m
	return config


## Independent restatement of the documented footprint offset rule: inset
## each half-extent by the configured fraction. Kept separate from
## `Config.footprint_offsets()` so the wiring is checked, not merely echoed.
func expected_offsets(config: ProbeScript.Config) -> Array[Vector3]:
	var half_x := 0.5 * config.hull_size_m.x
	var half_z := 0.5 * config.hull_size_m.z
	var x := half_x * (1.0 - config.footprint_inset_fraction)
	var z := half_z * (1.0 - config.footprint_inset_fraction)
	return [
		Vector3(0.0, 0.0, 0.0),
		Vector3(x, 0.0, z),
		Vector3(-x, 0.0, z),
		Vector3(x, 0.0, -z),
		Vector3(-x, 0.0, -z),
	]


func snapshot_config(config: ProbeScript.Config) -> Dictionary:
	var snapshot := {}
	for field in CONFIG_FIELDS:
		snapshot[field] = config.get(field)
	return snapshot


func check_config_unchanged(
	config: ProbeScript.Config,
	snapshot: Dictionary,
	message: String
) -> void:
	for field in CONFIG_FIELDS:
		var expected = snapshot[field]
		if field == "required_footprint_hits":
			check(
				int(config.get(field)) == int(expected),
				"%s: %s unchanged" % [message, field]
			)
		elif field == "hull_size_m":
			check_vector_close(
				config.get(field),
				expected,
				0.0,
				"%s: %s unchanged" % [message, field]
			)
		else:
			check_same_float(config.get(field), expected, "%s: %s unchanged" % [message, field])


# ---------------------------------------------------------------------------
# Transform fixtures
# ---------------------------------------------------------------------------


func flat_transform(origin: Vector3) -> Transform3D:
	return Transform3D(Basis(), origin)


## Pose whose local up is `rotation_euler_deg` applied to +Y, placed
## `height_m` along that up axis from `top_center`. Used to sit a probe on a
## banked or pitched slab whose top face centre is `top_center`.
func plane_pose(
	top_center: Vector3,
	rotation_euler_deg: Vector3,
	height_m: float
) -> Dictionary:
	var basis := Basis.from_euler(deg_to_vec(rotation_euler_deg))
	var normal := basis * Vector3.UP
	return {
		"basis": basis,
		"origin": top_center + normal * height_m,
		"normal": normal,
	}


func plane_pose_transform(pose: Dictionary) -> Transform3D:
	return Transform3D(pose["basis"], pose["origin"])


## Centre of a slab whose top-face centre is `top_center` and whose local up
## is rotated by `rotation_euler_deg`.
func rotated_slab_center(
	top_center: Vector3,
	size: Vector3,
	rotation_euler_deg: Vector3
) -> Vector3:
	var basis := Basis.from_euler(deg_to_vec(rotation_euler_deg))
	return top_center - basis * Vector3(0.0, size.y * 0.5, 0.0)


func deg_to_vec(euler_deg: Vector3) -> Vector3:
	return Vector3(
		deg_to_rad(euler_deg.x),
		deg_to_rad(euler_deg.y),
		deg_to_rad(euler_deg.z)
	)


func check_transform_unchanged(
	actual: Transform3D,
	snapshot: Transform3D,
	message: String
) -> void:
	check(actual.origin == snapshot.origin, "%s: origin unchanged" % message)
	check(actual.basis == snapshot.basis, "%s: basis unchanged" % message)


# ---------------------------------------------------------------------------
# Result fingerprints
# ---------------------------------------------------------------------------


## Exact-order comparable view of a result, used for deterministic-repeat
## comparisons. Floats are compared with `==`, not a tolerance.
func result_fingerprint(result: ProbeScript.Result) -> Array:
	var fingerprint: Array = [
		result.status,
		result.rejection_reason,
		result.grounded,
		result.center_supported,
		result.support_count,
		result.footprint_support_count,
		result.has_support,
		result.support_probe_index,
		result.support_point,
		result.support_normal,
		result.support_distance_m,
		result.support_height_m,
		result.queries_used,
		result.frame_up_dot,
	]
	for detail in result.probes:
		fingerprint.append(
			[
				detail["index"],
				detail["label"],
				detail["offset_local"],
				detail["start"],
				detail["end"],
				detail["direction"],
				detail["hit"],
				detail["valid"],
				detail["position"],
				detail["normal"],
				detail["distance_m"],
				detail["up_dot"],
				detail["reason"],
			]
		)
	return fingerprint


func check_fingerprint_equal(
	actual: Array,
	expected: Array,
	message: String
) -> void:
	check(actual.size() == expected.size(), "%s: fingerprint length" % message)
	var limit := mini(actual.size(), expected.size())
	for index in range(limit):
		if typeof(actual[index]) == TYPE_ARRAY:
			check_fingerprint_equal(actual[index], expected[index], "%s[%d]" % [message, index])
		elif typeof(actual[index]) in [TYPE_FLOAT, TYPE_INT]:
			check(
				float(actual[index]) == float(expected[index]),
				"%s[%d]: exact value (%s vs %s)"
				% [message, index, actual[index], expected[index]]
			)
		else:
			check(
				actual[index] == expected[index],
				"%s[%d]: exact value (%s vs %s)"
				% [message, index, actual[index], expected[index]]
			)


static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)
