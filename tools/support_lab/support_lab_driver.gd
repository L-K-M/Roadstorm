extends Node
## Headless M1.4 ground-support sensing laboratory driver.
##
## Builds real Godot/Jolt geometry stages, calls `GroundSupportProbe.probe()`
## with explicit world transforms, and prints one machine-readable
## `SLICE_RESULT <json>` line per case plus a final `SLICE_SUMMARY <json>` line.
##
## Scope: bounded downward support sensing only. It proves the five-query
## contract, legal-normal and distance gating, seam/footprint grounding,
## ceiling/overpass and steep-surface rejection, mask and area behaviour,
## atomic refusal with zero queries, deterministic repeatability, and stable
## hit/support identity telemetry. It does not implement adhesion, attraction,
## landing recovery, route eligibility or M1.4 acceptance.

const ProbeScript = preload("res://src/simulation/ground_support_probe.gd")
const ChecksScript = preload("res://tools/support_lab/support_lab_checks.gd")
const WorldScript = preload("res://tools/support_lab/support_lab_world.gd")

## Frames allowed for static colliders to reach the physics server.
const SETTLE_FRAMES := 8
## Frames after freeing a stage before the next stage is built.
const DESTROY_FRAMES := 6

const FLOOR_SIZE := Vector3(20.0, 1.0, 20.0)
const SEAM_HALF_WIDTH := 0.15
## Seam/distance scenarios need rays long enough to see the lower floor while
## the support bound still rejects it.
const LONG_RAY_LENGTH_M := 1.6
const SUPPORT_BOUND_M := 0.75
const UNEVEN_SUPPORT_BOUND_M := 1.0
## Lower-shoulder drop used by the coherent-cluster case, metres.
const SHOULDER_DROP_M := 0.30
## Closer-outlier slab top height and bank used by the witness-binding case.
## Its top sits 0.20 m below the probe origin, closer than the three agreeing
## road hits at 0.55 m, and its tilted normal differs from world up.
const CLOSER_OUTLIER_TOP_Y := 0.35
const CLOSER_OUTLIER_TILT_DEG := 10.0

## Internal wall-clock guard: a stalled await must not leave a headless
## engine running forever. The runner bounds every invocation as well.
const DRIVER_WATCHDOG_S := 100.0

const CASE_IDS := [
	"flat_floor",
	"bank_and_ramp",
	"frame_orientation_gate",
	"center_gap_seam",
	"near_edge_partial_support",
	"ceiling_overpass_rejection",
	"distant_support",
	"uneven_support_spread",
	"coherent_cluster_three_plus_one",
	"cluster_closer_outlier",
	"too_steep_surface",
	"absent_floor",
	"mask_exclusion",
	"invalid_input_unchanged",
	"deterministic_repeat",
	"exactly_five_queries",
	"support_identity",
]

var d := ChecksScript.new()
var measurements: Dictionary = {}
var _case_results: Array[Dictionary] = []
var requested_case := "all"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_args(OS.get_cmdline_args())
	var watchdog := get_tree().create_timer(DRIVER_WATCHDOG_S)
	watchdog.timeout.connect(_on_watchdog)
	_run()


func _on_watchdog() -> void:
	printerr("support_lab: internal watchdog fired before the suite completed")
	print(
		"SLICE_SUMMARY "
		+ JSON.stringify({"cases": 0, "checks": 0, "failed_cases": 1, "pass": false})
	)
	get_tree().quit(3)


func _parse_args(args: Array) -> void:
	for argument in args:
		if argument.begins_with("--case="):
			requested_case = argument.substr(7)
	var from_environment := OS.get_environment("SUPPORT_LAB_CASE")
	if from_environment != "":
		requested_case = from_environment


func _run() -> void:
	if requested_case == "intentional_failure":
		var result := _run_intentional_failure()
		_finish_with([result])
		return
	if requested_case != "all" and not CASE_IDS.has(requested_case):
		printerr(
			"unknown case '%s'; use all, one of %s, or intentional_failure"
			% [requested_case, str(CASE_IDS)]
		)
		var bad := {
			"cases": 0,
			"checks": 0,
			"failed_cases": 1,
			"pass": false,
		}
		print("SLICE_SUMMARY " + JSON.stringify(bad))
		get_tree().quit(2)
		return
	var cases_to_run: Array = CASE_IDS if requested_case == "all" else [requested_case]
	for case_id in cases_to_run:
		_case_results.append(await _run_case(case_id))
	_finish_with(_case_results)


func _finish_with(results: Array[Dictionary]) -> void:
	var total_checks := 0
	var failed_cases := 0
	for result in results:
		total_checks += int(result["checks"])
		if not result["pass"]:
			failed_cases += 1
	var summary := {
		"cases": results.size(),
		"checks": total_checks,
		"failed_cases": failed_cases,
		"pass": failed_cases == 0,
	}
	print("SLICE_SUMMARY " + JSON.stringify(summary))
	get_tree().quit(0 if failed_cases == 0 else 1)


func _run_case(case_id: String) -> Dictionary:
	d = ChecksScript.new()
	measurements = {}
	match case_id:
		"flat_floor":
			await _case_flat_floor()
		"bank_and_ramp":
			await _case_bank_and_ramp()
		"frame_orientation_gate":
			await _case_frame_orientation_gate()
		"center_gap_seam":
			await _case_center_gap_seam()
		"near_edge_partial_support":
			await _case_near_edge_partial_support()
		"ceiling_overpass_rejection":
			await _case_ceiling_overpass()
		"distant_support":
			await _case_distant_support()
		"uneven_support_spread":
			await _case_uneven_support_spread()
		"coherent_cluster_three_plus_one":
			await _case_coherent_cluster_three_plus_one()
		"cluster_closer_outlier":
			await _case_cluster_closer_outlier()
		"too_steep_surface":
			await _case_too_steep_surface()
		"absent_floor":
			await _case_absent_floor()
		"mask_exclusion":
			await _case_mask_exclusion()
		"invalid_input_unchanged":
			await _case_invalid_input_unchanged()
		"deterministic_repeat":
			await _case_deterministic_repeat()
		"exactly_five_queries":
			await _case_exactly_five_queries()
		"support_identity":
			await _case_support_identity()
	# Guard against a case id that reaches the dispatcher without a match arm:
	# such a case would otherwise report a vacuous zero-check pass.
	d.check(d.checks > 0, "%s: case emitted at least one assertion" % case_id)
	var result := {
		"case": case_id,
		"pass": d.failures.is_empty(),
		"checks": d.checks,
		"failures": d.failures.duplicate(),
		"measurements": measurements.duplicate(),
	}
	print("SLICE_RESULT " + JSON.stringify(result))
	return result


## Structural equality for fingerprint arrays; GDScript array `==` is not
## relied upon for nested arrays.
func _fingerprints_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for index in range(a.size()):
		if typeof(a[index]) == TYPE_ARRAY:
			if not _fingerprints_equal(a[index], b[index]):
				return false
		elif a[index] != b[index]:
			return false
	return true


## Read the newer cluster diagnostics safely. The historical-probe negative
## control replaces the probe script with an older Result shape, so `get()`
## keeps that run loadable instead of raising a missing-property error.
func _cluster_size_of(result: ProbeScript.Result) -> int:
	var value = result.get("grounding_cluster_size")
	return int(value) if typeof(value) == TYPE_INT else 0


func _cluster_indices_of(result: ProbeScript.Result) -> Array:
	var value = result.get("grounding_cluster_indices")
	return value if typeof(value) == TYPE_ARRAY else []

## Identity readers tolerant of an older Result/detail shape. The
## historical-source control replaces the probe script with a source that has
## no identity fields, so these return the documented absent defaults instead
## of raising a missing-property error. An old source therefore fails only
## assertions that expect a real identity, never the behavioural checks.
func _detail_int(detail: Dictionary, key: String) -> int:
	var value = detail.get(key)
	return int(value) if typeof(value) == TYPE_INT else -1


func _detail_rid(detail: Dictionary, key: String) -> RID:
	var value = detail.get(key)
	return value if typeof(value) == TYPE_RID else RID()


func _result_identity_int(result: ProbeScript.Result, field: String) -> int:
	var value = result.get(field)
	return int(value) if typeof(value) == TYPE_INT else -1


func _result_identity_rid(result: ProbeScript.Result, field: String) -> RID:
	var value = result.get(field)
	return value if typeof(value) == TYPE_RID else RID()

## Witness readers tolerant of an older Result shape, matching the identity
## readers above. The historical probe has no witness fields.
func _result_witness_indices(result: ProbeScript.Result) -> Array:
	var value = result.get("grounding_witness_indices")
	return value if typeof(value) == TYPE_ARRAY else []

func _result_support_is_witness(result: ProbeScript.Result) -> bool:
	var value = result.get("support_is_grounding_witness")
	return value if typeof(value) == TYPE_BOOL else false


func _run_intentional_failure() -> Dictionary:
	d = ChecksScript.new()
	measurements = {"intentional": true}
	d.check(false, "intentional failure mode: this assertion always fails")
	d.check(true, "intentional-failure control check")
	print("INTENTIONAL_FAILURE_PROOF pass=false")
	return {
		"case": "intentional_failure",
		"pass": false,
		"checks": d.checks,
		"failures": d.failures.duplicate(),
		"measurements": measurements.duplicate(),
	}


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------


func _await_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().physics_frame


func _build(
	slabs: Array,
	areas: Array,
	cars: Array
) -> SupportLabWorld:
	# Callers frequently concatenate fixture arrays; normalise the untyped
	# results into the typed arrays the staging helper declares.
	var slab_list: Array[Dictionary] = []
	for spec in slabs:
		slab_list.append(spec)
	var area_list: Array[Dictionary] = []
	for spec in areas:
		area_list.append(spec)
	var car_list: Array[Dictionary] = []
	for spec in cars:
		car_list.append(spec)
	var world: SupportLabWorld = WorldScript.build(
		get_tree().root, d.HULL_SIZE, slab_list, area_list, car_list
	)
	await _await_frames(SETTLE_FRAMES)
	return world


func _destroy(world: SupportLabWorld) -> void:
	world.destroy()
	await _await_frames(DESTROY_FRAMES)


func _probe(
	world: SupportLabWorld,
	car_name: String,
	config: ProbeScript.Config,
	transform: Transform3D
) -> ProbeScript.Result:
	return ProbeScript.probe(
		world.body(car_name), world.hull_shape(car_name), config, transform
	)


func _slab(
	name: String,
	size: Vector3,
	center: Vector3,
	layer: int = 1,
	rotation_deg: Vector3 = Vector3.ZERO
) -> Dictionary:
	return {
		"name": name,
		"size": size,
		"center": center,
		"rotation_deg": rotation_deg,
		"layer": layer,
	}


func _area(
	name: String,
	size: Vector3,
	center: Vector3,
	layer: int = 1
) -> Dictionary:
	return {"name": name, "size": size, "center": center, "layer": layer}


func _car_spec(
	car_name: String,
	position: Vector3,
	mask: int = 1,
	basis: Basis = Basis(),
	layer: int = 1
) -> Dictionary:
	return {
		"name": car_name,
		"position": position,
		"basis": basis,
		"mask": mask,
		"layer": layer,
	}


func _floor_slabs() -> Array[Dictionary]:
	return [_slab("Floor", FLOOR_SIZE, Vector3(0.0, -0.5, 0.0))]


func _gap_slabs(top_y: float) -> Array[Dictionary]:
	var slab_size := Vector3(
		0.5 * (FLOOR_SIZE.x - 2.0 * SEAM_HALF_WIDTH),
		FLOOR_SIZE.y,
		FLOOR_SIZE.z
	)
	var center_x := SEAM_HALF_WIDTH + 0.5 * slab_size.x
	return [
		_slab(
			"FloorLeft",
			slab_size,
			Vector3(-center_x, top_y - 0.5, 0.0)
		),
		_slab(
			"FloorRight",
			slab_size,
			Vector3(center_x, top_y - 0.5, 0.0)
		),
	]


## Three road-level footprint surfaces plus one lower shoulder. A 0.30 m
## central seam leaves the centre ray unsupported: the right side carries two
## road footprints, the rear left carries one, and the front left reads the
## shoulder at `shoulder_top_y`.
func _three_road_plus_shoulder_slabs(shoulder_top_y: float) -> Array[Dictionary]:
	var side_width := FLOOR_SIZE.x - SEAM_HALF_WIDTH
	var side_depth := 0.5 * FLOOR_SIZE.z
	var side_center_x := -(SEAM_HALF_WIDTH + 0.5 * side_width)
	return [
		_slab(
			"RoadRight",
			Vector3(side_width, FLOOR_SIZE.y, FLOOR_SIZE.z),
			Vector3(SEAM_HALF_WIDTH + 0.5 * side_width, -0.5, 0.0)
		),
		_slab(
			"RoadRearLeft",
			Vector3(side_width, FLOOR_SIZE.y, side_depth),
			Vector3(side_center_x, -0.5, 0.25 * FLOOR_SIZE.z)
		),
		_slab(
			"ShoulderFrontLeft",
			Vector3(side_width, FLOOR_SIZE.y, side_depth),
			Vector3(side_center_x, shoulder_top_y - 0.5, -0.25 * FLOOR_SIZE.z)
		),
	]


## Three road-level footprint surfaces plus one closer outlier above the
## front-left footprint. A 0.30 m central seam leaves the centre ray
## unsupported; the right half carries two road footprints, the rear left
## carries one, and the front left reads the tilted outlier slab whose top is
## closer to the probe origin than the road. The outlier is a distinct
## collider with a distinct normal.
func _three_road_plus_closer_outlier_slabs(
	outlier_top_y: float, front_left_offset: Vector3
) -> Array[Dictionary]:
	var side_width := FLOOR_SIZE.x - SEAM_HALF_WIDTH
	var side_depth := 0.5 * FLOOR_SIZE.z
	var side_center_x := -(SEAM_HALF_WIDTH + 0.5 * side_width)
	var euler := Vector3(0.0, 0.0, CLOSER_OUTLIER_TILT_DEG)
	# Narrow enough that neither the central ray nor any other footprint
	# reaches it: its rotated x extent stays below the 0.15 m seam half-width.
	var outlier_size := Vector3(1.2, FLOOR_SIZE.y, 4.0)
	var top_center := Vector3(front_left_offset.x, outlier_top_y, front_left_offset.z)
	return [
		_slab(
			"RoadRight",
			Vector3(side_width, FLOOR_SIZE.y, FLOOR_SIZE.z),
			Vector3(SEAM_HALF_WIDTH + 0.5 * side_width, -0.5, 0.0)
		),
		_slab(
			"RoadRearLeft",
			Vector3(side_width, FLOOR_SIZE.y, side_depth),
			Vector3(side_center_x, -0.5, 0.25 * FLOOR_SIZE.z)
		),
		_slab(
			"CloserOutlier",
			outlier_size,

			d.rotated_slab_center(top_center, outlier_size, euler),
			1,
			euler
		),
	]


func _check_common_ok_result(
	result: ProbeScript.Result,
	config: ProbeScript.Config,
	expected_queries: int,
	message: String
) -> void:
	d.check(
		result.status == ProbeScript.Status.OK,
		"%s: status OK (got %s, %s)"
		% [message, result.status, result.rejection_reason]
	)
	d.check(result.rejection_reason == "", "%s: no rejection reason" % message)
	d.check(
		result.queries_used == expected_queries,
		"%s: exactly %d ray queries (got %d)" % [message, expected_queries, result.queries_used]
	)
	d.check(
		result.probes.size() == ProbeScript.PROBE_COUNT,
		"%s: %d probe details (got %d)"
		% [message, ProbeScript.PROBE_COUNT, result.probes.size()]
	)
	var labels: Array = []
	for detail in result.probes:
		labels.append(detail["label"])
	d.check(labels == d.PROBE_LABELS, "%s: fixed probe order/labels" % message)


# ---------------------------------------------------------------------------
# Cases
# ---------------------------------------------------------------------------


func _case_flat_floor() -> void:
	var world := await _build(_floor_slabs(), [], [_car_spec("Car", Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))])
	var car := world.body("Car")
	var config := d.make_config()
	var config_snapshot := d.snapshot_config(config)
	var pose_before := car.global_transform
	var transform := d.flat_transform(Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))

	var result := _probe(world, "Car", config, transform)
	_check_common_ok_result(result, config, ProbeScript.PROBE_COUNT, "flat")
	d.check(result.grounded, "flat: grounded on open floor")
	d.check(result.center_supported, "flat: central probe supports")
	d.check(result.support_count == 5, "flat: all five probes valid (got %d)" % result.support_count)
	d.check(
		result.footprint_support_count == 4,
		"flat: four footprint probes valid (got %d)" % result.footprint_support_count
	)
	d.check(result.has_support, "flat: has support")
	d.check(result.support_probe_index == 0, "flat: closest support is the central hit")
	d.check(
		_result_witness_indices(result) == [0],
		"flat: witness set is the centre hit (got %s)" % str(_result_witness_indices(result))
	)
	d.check(
		_result_support_is_witness(result),
		"flat: selected support is the centre grounding witness"
	)
	d.check_vector_close(
		result.support_point, Vector3.ZERO, 1e-5, "flat: support point on the floor"
	)
	d.check_close(
		result.support_distance_m, d.BODY_SUPPORT_Y, 1e-5, "flat: support distance"
	)
	d.check_close(
		result.support_height_m, d.BODY_SUPPORT_Y, 1e-5, "flat: support height"
	)
	d.check_vector_close(
		result.support_normal, Vector3.UP, 1e-6, "flat: averaged normal is world up"
	)
	var expected_offsets := d.expected_offsets(config)
	for index in range(result.probes.size()):
		var detail: Dictionary = result.probes[index]
		var label: String = d.PROBE_LABELS[index]
		d.check(detail["hit"], "flat %s: ray hit" % label)
		d.check(detail["valid"], "flat %s: legal support" % label)
		d.check(detail["reason"] == "ok", "flat %s: reason ok (got %s)" % [label, detail["reason"]])
		d.check_vector_close(
			detail["direction"], Vector3.DOWN, 1e-9, "flat %s: downward direction" % label
		)
		d.check_vector_close(
			detail["start"],
			transform * expected_offsets[index],
			1e-9,
			"flat %s: start at inset offset" % label
		)
		d.check_close(
			detail["distance_m"], d.BODY_SUPPORT_Y, 1e-5, "flat %s: distance" % label
		)
		d.check_close(detail["up_dot"], 1.0, 1e-9, "flat %s: up dot" % label)
	d.check_config_unchanged(config, config_snapshot, "flat")
	d.check(
		car.global_transform.origin == pose_before.origin
		and car.global_transform.basis == pose_before.basis,
		"flat: body transform unchanged"
	)

	# A hypothetical pose away from the body still senses that pose, and the
	# body stays where it was.
	var distant := _probe(world, "Car", config, d.flat_transform(Vector3(5.0, d.BODY_SUPPORT_Y, 0.0)))
	d.check(distant.grounded, "flat hypothetical: grounded at x=5")
	d.check_vector_close(
		distant.support_point, Vector3(5.0, 0.0, 0.0), 1e-5,
		"flat hypothetical: support point follows the supplied transform"
	)
	d.check(
		car.global_transform.origin == pose_before.origin,
		"flat hypothetical: body origin unchanged"
	)

	measurements["min_support_distance_m"] = result.support_distance_m
	measurements["max_probe_up_dot"] = 1.0
	await _destroy(world)


func _case_bank_and_ramp() -> void:
	var configs := [
		{"name": "bank", "euler": Vector3(0.0, 0.0, 12.0), "expected_up_dot": cos(deg_to_rad(12.0))},
		{"name": "ramp", "euler": Vector3(8.0, 0.0, 0.0), "expected_up_dot": cos(deg_to_rad(8.0))},
	]
	for scenario in configs:
		var name: String = scenario["name"]
		var euler: Vector3 = scenario["euler"]
		var expected_up_dot: float = scenario["expected_up_dot"]
		var pose: Dictionary = d.plane_pose(Vector3.ZERO, euler, d.BODY_SUPPORT_Y)
		var slab_center := d.rotated_slab_center(Vector3.ZERO, FLOOR_SIZE, euler)
		var world := await _build(
			[_slab("Floor", FLOOR_SIZE, slab_center, 1, euler)],
			[],
			[_car_spec("Car", pose["origin"], 1, pose["basis"])]
		)
		var config := d.make_config()
		var result := _probe(world, "Car", config, d.plane_pose_transform(pose))
		_check_common_ok_result(result, config, ProbeScript.PROBE_COUNT, name)
		d.check(result.grounded, "%s: grounded" % name)
		d.check(result.center_supported, "%s: central support" % name)
		d.check(result.support_count == 5, "%s: all five probes valid" % name)
		d.check_vector_close(
			result.support_normal,
			pose["normal"],
			1e-6,
			"%s: averaged normal matches the bank/ramp normal" % name
		)
		d.check_vector_close(
			result.support_point, Vector3.ZERO, 1e-5,
			"%s: central support on the surface centre" % name
		)
		d.check_close(
			result.support_distance_m, d.BODY_SUPPORT_Y, 1e-5,
			"%s: support distance along local down" % name
		)
		d.check_close(
			result.support_height_m, pose["origin"].y, 1e-5,
			"%s: world vertical drop" % name
		)
		for index in range(result.probes.size()):
			var detail: Dictionary = result.probes[index]
			d.check(detail["valid"], "%s probe %d: valid" % [name, index])
			d.check_close(
				detail["up_dot"], expected_up_dot, 1e-6,
				"%s probe %d: up dot" % [name, index]
			)
			d.check_vector_close(
				detail["normal"], pose["normal"], 1e-6,
				"%s probe %d: surface normal" % [name, index]
			)
		measurements["%s_support_distance_m" % name] = result.support_distance_m
		measurements["%s_expected_up_dot" % name] = expected_up_dot
		await _destroy(world)


## A slab whose front-face normal is `(0.6, 0.6, 0.529150)`: world-up
## alignment 0.6, above the 0.5 surface threshold, with its top-face centre
## 0.4 m along the sideways cast direction (-X). A pre-guard sensor casting
## horizontally through a sideways frame reads legal support here.
func _sideways_support_slab(origin: Vector3) -> Dictionary:
	var euler_deg := Vector3(53.1301024, 48.5903779, 0.0)
	var top_center := origin + Vector3(-0.4, 0.0, 0.0)
	return _slab(
		"SidewaysSupport",
		FLOOR_SIZE,
		d.rotated_slab_center(top_center, FLOOR_SIZE, euler_deg),
		1,
		euler_deg
	)


func _case_frame_orientation_gate() -> void:
	var origin := Vector3(0.0, d.BODY_SUPPORT_Y, 0.0)
	var config := d.make_config()

	# Positive controls under the default 0.5 gate: upright and 12 degree bank.
	var world := await _build(_floor_slabs(), [], [_car_spec("Car", origin)])
	var upright := _probe(world, "Car", config, d.flat_transform(origin))
	_check_common_ok_result(upright, config, ProbeScript.PROBE_COUNT, "gate-flat")
	d.check(upright.grounded, "gate: upright frame senses the floor")
	d.check_close(upright.frame_up_dot, 1.0, 1e-9, "gate: upright up dot")
	await _destroy(world)

	var bank := Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(12.0)))
	world = await _build(_floor_slabs(), [], [_car_spec("Car", origin, 1, bank)])
	var bank_result := _probe(world, "Car", config, Transform3D(bank, origin))
	d.check(bank_result.status == ProbeScript.Status.OK, "gate: 12 degree bank admitted")
	d.check(bank_result.grounded, "gate: 12 degree bank grounded")
	d.check_close(
		bank_result.frame_up_dot, cos(deg_to_rad(12.0)), 1e-6,
		"gate: bank up dot"
	)
	await _destroy(world)

	# A 30 degree tilt stays inside the gate and its tilted rays still reach
	# the floor within the support bound.
	var tilt := Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(30.0)))
	world = await _build(_floor_slabs(), [], [_car_spec("Car", origin, 1, tilt)])
	var tilt_result := _probe(world, "Car", config, Transform3D(tilt, origin))
	d.check(tilt_result.status == ProbeScript.Status.OK, "gate: 30 degree tilt admitted")
	d.check(tilt_result.grounded, "gate: 30 degree tilt grounded")
	d.check_close(
		tilt_result.frame_up_dot, cos(deg_to_rad(30.0)), 1e-6,
		"gate: 30 degree up dot"
	)
	await _destroy(world)

	# Sideways frame with a support-shaped surface along the horizontal cast.
	var sideways := Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(-90.0)))
	world = await _build(
		[_sideways_support_slab(origin)],
		[],
		[_car_spec("Car", origin, 1, sideways)]
	)
	var car := world.body("Car")
	var pose_before := car.global_transform
	var config_snapshot := d.snapshot_config(config)
	var side := _probe(world, "Car", config, Transform3D(sideways, origin))
	d.check(
		side.status == ProbeScript.Status.REJECTED_INVALID_INPUT,
		"gate: sideways frame refused (got %s, %s)" % [side.status, side.rejection_reason]
	)
	d.check(
		side.rejection_reason.contains("upright"),
		"gate: sideways refusal names the gate (%s)" % side.rejection_reason
	)
	d.check(side.queries_used == 0, "gate: sideways issues zero queries")
	d.check(side.probes.is_empty(), "gate: sideways exposes no probes")
	d.check_close(side.frame_up_dot, 0.0, 1e-6, "gate: sideways up dot")
	d.check(
		car.global_transform.origin == pose_before.origin
		and car.global_transform.basis == pose_before.basis,
		"gate: sideways leaves body unchanged"
	)
	d.check_config_unchanged(config, config_snapshot, "gate sideways")
	await _destroy(world)

	# Inverted frame beneath an overhead slab.
	var inverted := Basis.from_euler(Vector3(deg_to_rad(180.0), 0.0, 0.0))
	var ceiling := _slab("Overhead", FLOOR_SIZE, Vector3(0.0, 1.5, 0.0))
	world = await _build([ceiling], [], [_car_spec("Car", origin, 1, inverted)])
	var inv := _probe(world, "Car", config, Transform3D(inverted, origin))
	d.check(
		inv.status == ProbeScript.Status.REJECTED_INVALID_INPUT,
		"gate: inverted frame refused (got %s, %s)" % [inv.status, inv.rejection_reason]
	)
	d.check(inv.queries_used == 0, "gate: inverted issues zero queries")
	d.check(inv.probes.is_empty(), "gate: inverted exposes no probes")
	d.check_close(inv.frame_up_dot, -1.0, 1e-9, "gate: inverted up dot")
	await _destroy(world)

	# Configurable threshold: a 61 degree tilt is refused by the 0.5 default
	# and admitted at 0.45 (cos 61 = 0.4848). A low origin keeps the tilted
	# rays inside the support bound once the gate admits them.
	var low_origin := Vector3(0.0, 0.2, 0.0)
	var steep_tilt := Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(61.0)))
	world = await _build(
		_floor_slabs(),
		[],
		[_car_spec("Car", low_origin, 1, steep_tilt)]
	)
	var refused := _probe(world, "Car", config, Transform3D(steep_tilt, low_origin))
	d.check(
		refused.status == ProbeScript.Status.REJECTED_INVALID_INPUT,
		"gate: 61 degree tilt refused at 0.5"
	)
	var relaxed_gate := d.make_config()
	relaxed_gate.min_frame_up_dot = 0.45
	var admitted := _probe(world, "Car", relaxed_gate, Transform3D(steep_tilt, low_origin))
	d.check(admitted.status == ProbeScript.Status.OK, "gate: 61 degree tilt admitted at 0.45")
	d.check(admitted.grounded, "gate: relaxed-gate tilted probe reaches the floor")
	d.check_close(
		admitted.frame_up_dot, cos(deg_to_rad(61.0)), 1e-6,
		"gate: 61 degree up dot"
	)
	await _destroy(world)

	measurements["sideways_frame_up_dot"] = side.frame_up_dot
	measurements["inverted_frame_up_dot"] = inv.frame_up_dot


func _case_center_gap_seam() -> void:
	var world := await _build(
		_gap_slabs(0.0),
		[],
		[_car_spec("Car", Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))]
	)
	var config := d.make_config()
	var transform := d.flat_transform(Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))
	var result := _probe(world, "Car", config, transform)
	_check_common_ok_result(result, config, ProbeScript.PROBE_COUNT, "seam")
	var center: Dictionary = result.probes[0]
	d.check(not center["hit"], "seam: central ray finds no floor in the gap")
	d.check(center["reason"] == "no_hit", "seam: central reason no_hit")
	d.check(not result.center_supported, "seam: central probe unsupported")
	d.check(
		result.footprint_support_count == 4,
		"seam: four footprint probes reach floor (got %d)" % result.footprint_support_count
	)
	d.check(result.grounded, "seam: footprint support grounds the body")
	d.check(result.support_count == 4, "seam: four valid supports")
	d.check(result.has_support, "seam: has support")
	d.check(result.support_probe_index != 0, "seam: support chosen from a footprint")
	d.check_close(
		result.support_distance_m, d.BODY_SUPPORT_Y, 1e-5, "seam: support distance"
	)
	d.check_vector_close(result.support_normal, Vector3.UP, 1e-6, "seam: averaged up normal")

	# Requiring all four footprint hits keeps the same decision.
	var strict := d.make_config()
	strict.required_footprint_hits = 4
	var strict_result := _probe(world, "Car", strict, transform)
	d.check(strict_result.grounded, "seam: four-of-four requirement still grounds")
	d.check(
		strict_result.footprint_support_count == 4,
		"seam: strict requirement sees four hits"
	)

	# One-sided floor under only two footprints is a separate case; here all
	# four sides have nearby legal floor.
	measurements["footprint_support_count"] = result.footprint_support_count
	measurements["support_distance_m"] = result.support_distance_m
	await _destroy(world)


func _case_near_edge_partial_support() -> void:
	var edge_slab := _slab(
		"FloorEdge", FLOOR_SIZE, Vector3(-10.0, -0.5, 0.0)
	)
	var world := await _build(
		[edge_slab],
		[],
		[_car_spec("Car", Vector3(0.15, d.BODY_SUPPORT_Y, 0.0))]
	)
	var transform := d.flat_transform(Vector3(0.15, d.BODY_SUPPORT_Y, 0.0))

	var default_config := d.make_config()
	var default_result := _probe(world, "Car", default_config, transform)
	_check_common_ok_result(default_result, default_config, ProbeScript.PROBE_COUNT, "near-edge")
	d.check(
		default_result.footprint_support_count == 2,
		"near-edge: two footprints on the slab (got %d)" % default_result.footprint_support_count
	)
	d.check(default_result.grounded, "near-edge: two hits satisfy the default requirement")
	d.check(not default_result.center_supported, "near-edge: centre over the void")

	var strict := d.make_config()
	strict.required_footprint_hits = 3
	var strict_result := _probe(world, "Car", strict, transform)
	d.check(
		not strict_result.grounded,
		"near-edge: three required hits refuse two-hit support"
	)

	var lenient := d.make_config()
	lenient.required_footprint_hits = 1
	var lenient_result := _probe(world, "Car", lenient, transform)
	d.check(lenient_result.grounded, "near-edge: one required hit accepts two")

	d.check_close(
		default_result.support_distance_m, d.BODY_SUPPORT_Y, 1e-5, "near-edge: distance"
	)
	d.check_vector_close(
		default_result.support_normal, Vector3.UP, 1e-6, "near-edge: averaged normal"
	)
	measurements["footprint_support_count"] = default_result.footprint_support_count
	await _destroy(world)


func _case_ceiling_overpass() -> void:
	var ceiling := _slab("Overpass", FLOOR_SIZE, Vector3(0.0, 1.7, 0.0))
	var world := await _build(
		_floor_slabs() + [ceiling],
		[],
		[_car_spec("Car", Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))]
	)
	var config := d.make_config()
	var result := _probe(world, "Car", config, d.flat_transform(Vector3(0.0, d.BODY_SUPPORT_Y, 0.0)))
	_check_common_ok_result(result, config, ProbeScript.PROBE_COUNT, "overpass")
	d.check(result.grounded, "overpass: grounded on the floor below")
	d.check(result.center_supported, "overpass: central floor support")
	d.check(result.support_count == 5, "overpass: all five probes read the floor")
	d.check_close(
		result.support_distance_m, d.BODY_SUPPORT_Y, 1e-5,
		"overpass: support distance stays at the floor, not the deck"
	)
	d.check_vector_close(result.support_normal, Vector3.UP, 1e-6, "overpass: floor normal")
	var highest_hit := -INF
	for detail in result.probes:
		highest_hit = maxf(highest_hit, detail["position"].y)
	d.check(
		highest_hit < 1.0,
		"overpass: no probe reports the overhead deck (highest y %.6f)" % highest_hit
	)
	measurements["highest_hit_y"] = highest_hit
	await _destroy(world)


func _case_distant_support() -> void:
	var lower := _slab("LowerFloor", FLOOR_SIZE, Vector3(0.0, -1.5, 0.0))
	var world := await _build(
		_gap_slabs(0.0) + [lower],
		[],
		[_car_spec("Car", Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))]
	)
	var transform := d.flat_transform(Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))
	var config := d.make_config_with(
		LONG_RAY_LENGTH_M, SUPPORT_BOUND_M, 2, 0.25
	)
	var result := _probe(world, "Car", config, transform)
	_check_common_ok_result(result, config, ProbeScript.PROBE_COUNT, "distant")
	var center: Dictionary = result.probes[0]
	d.check(center["hit"], "distant: central ray reaches the lower floor")
	d.check(
		not center["valid"],
		"distant: lower floor is beyond the support bound"
	)
	d.check(
		center["reason"] == "beyond_max_support",
		"distant: central reason beyond_max_support (got %s)" % center["reason"]
	)
	d.check_close(
		center["distance_m"], 1.55, 1e-5, "distant: central distance to lower floor"
	)
	d.check(not result.center_supported, "distant: central support rejected")
	d.check(
		result.footprint_support_count == 4,
		"distant: four upper-floor footprints valid"
	)
	d.check(result.grounded, "distant: upper floor still grounds the body")
	d.check_close(
		result.support_distance_m, d.BODY_SUPPORT_Y, 1e-5,
		"distant: support is the close upper floor"
	)
	d.check_vector_close(result.support_normal, Vector3.UP, 1e-6, "distant: floor normal")
	d.check(
		result.support_probe_index != 0,
		"distant: support probe is not the central lower-floor reading"
	)

	# Positive control: widening the support bound to the ray length admits
	# the lower floor through the central ray. The centre is then the
	# grounding witness, so the selected support must come from it even though
	# the upper-floor footprints are closer.
	var wide := d.make_config_with(LONG_RAY_LENGTH_M, LONG_RAY_LENGTH_M, 2, 0.25)
	var wide_result := _probe(world, "Car", wide, transform)
	d.check(wide_result.center_supported, "distant control: widened bound admits the central hit")
	d.check(
		wide_result.grounded, "distant control: grounded through the central ray"
	)
	d.check_close(
		wide_result.probes[0]["distance_m"], 1.55, 1e-5,
		"distant control: central ray reaches the lower floor"
	)
	d.check(
		wide_result.support_probe_index == 0,
		"distant control: centre witness supplies the selected support"
	)
	d.check(
		_result_witness_indices(wide_result) == [0],
		"distant control: witness set is the centre hit (got %s)"
		% str(_result_witness_indices(wide_result))
	)
	d.check(
		_result_support_is_witness(wide_result),
		"distant control: selected support is the centre witness"
	)
	d.check_close(
		wide_result.support_distance_m, 1.55, 1e-5,
		"distant control: selected distance is the lower-floor centre reading"
	)
	measurements["rejected_central_distance_m"] = center["distance_m"]
	measurements["accepted_control_distance_m"] = wide_result.support_distance_m
	await _destroy(world)


func _case_uneven_support_spread() -> void:
	var left := _slab("FloorHigh", Vector3(9.85, 1.0, 20.0), Vector3(-5.075, -0.5, 0.0))
	var right := _slab("FloorLow", Vector3(9.85, 1.0, 20.0), Vector3(5.075, -0.85, 0.0))
	var world := await _build(
		[left, right],
		[],
		[_car_spec("Car", Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))]
	)
	var transform := d.flat_transform(Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))
	var config := d.make_config_with(
		LONG_RAY_LENGTH_M, UNEVEN_SUPPORT_BOUND_M, 2, 0.25
	)
	var result := _probe(world, "Car", config, transform)
	_check_common_ok_result(result, config, ProbeScript.PROBE_COUNT, "uneven")
	d.check(result.support_count == 4, "uneven: four legal hits")
	d.check(not result.center_supported, "uneven: centre over the gap")
	d.check(
		not result.grounded,
		"uneven: equal 2+2 clusters are ambiguous and remain ungrounded"
	)
	d.check(
		_cluster_size_of(result) == 0,
		"uneven: no uniquely largest cluster is reported (got %d)"
		% _cluster_size_of(result)
	)
	var distances := []
	for index in range(1, result.probes.size()):
		distances.append(result.probes[index]["distance_m"])
	d.check_close(
		distances.max() - distances.min(), 0.35, 1e-5, "uneven: measured spread"
	)
	d.check_close(
		result.support_distance_m, d.BODY_SUPPORT_Y, 1e-5,
		"uneven: closest legal support is still reported"
	)
	d.check(
		_result_witness_indices(result).is_empty(),
		"uneven: ungrounded diagnostic exposes no witness set"
	)
	d.check(
		not _result_support_is_witness(result),
		"uneven: ungrounded diagnostic support is not a grounding witness"
	)

	# Tie handling is independent of the required count: lowering it does not
	# turn an equal-size split into one coherent cluster.
	var lenient := d.make_config_with(
		LONG_RAY_LENGTH_M, UNEVEN_SUPPORT_BOUND_M, 1, 0.25
	)
	var lenient_result := _probe(world, "Car", lenient, transform)
	d.check(
		not lenient_result.grounded,
		"uneven: required=1 still refuses an equal 2+2 split"
	)

	# Sensitivity control: widening the spread bound makes all four hits one
	# coherent cluster and grounds the body.
	var relaxed := d.make_config_with(
		LONG_RAY_LENGTH_M, UNEVEN_SUPPORT_BOUND_M, 2, 0.5
	)
	var relaxed_result := _probe(world, "Car", relaxed, transform)
	d.check(relaxed_result.grounded, "uneven control: relaxed spread grounds")
	d.check(
		_cluster_size_of(relaxed_result) == 4,
		"uneven control: relaxed cluster contains all four hits (got %d)"
		% _cluster_size_of(relaxed_result)
	)
	measurements["measured_spread_m"] = distances.max() - distances.min()
	await _destroy(world)


func _case_coherent_cluster_three_plus_one() -> void:
	# Three footprints on road level and one on a legal shoulder 0.30 m
	# lower, with the central ray in a 0.30 m seam. The three road hits form
	# the uniquely largest coherent cluster, so the documented rule grounds;
	# the historical all-legal-hits spread rule rejected this pose.
	var config := d.make_config_with(
		LONG_RAY_LENGTH_M, UNEVEN_SUPPORT_BOUND_M, 2, 0.25
	)
	var transform := d.flat_transform(Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))
	var world := await _build(
		_three_road_plus_shoulder_slabs(-SHOULDER_DROP_M),
		[],
		[_car_spec("Car", Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))]
	)
	var result := _probe(world, "Car", config, transform)
	_check_common_ok_result(result, config, ProbeScript.PROBE_COUNT, "coherent")
	d.check(not result.center_supported, "coherent: centre ray misses the seam")
	d.check(
		result.footprint_support_count == 4,
		"coherent: four legal footprint hits (got %d)" % result.footprint_support_count
	)
	d.check(
		result.grounded,
		"coherent: three agreeing road hits ground despite a lower shoulder"
	)
	d.check(result.support_count == 4, "coherent: four valid supports")
	d.check(
		_cluster_size_of(result) == 3,
		"coherent: unique cluster size is three (got %d)" % _cluster_size_of(result)
	)
	d.check(
		_cluster_indices_of(result) == [1, 2, 3],
		"coherent: cluster is rear_right, rear_left and front_right (got %s)"
		% str(_cluster_indices_of(result))
	)
	var road_hits := 0
	var shoulder_hits := 0
	for index in range(1, result.probes.size()):
		var detail: Dictionary = result.probes[index]
		var distance: float = detail["distance_m"]
		if absf(distance - d.BODY_SUPPORT_Y) <= 1e-5:
			road_hits += 1
		elif absf(distance - (d.BODY_SUPPORT_Y + SHOULDER_DROP_M)) <= 1e-5:
			shoulder_hits += 1
	d.check(
		road_hits == 3 and shoulder_hits == 1,
		"coherent: three road hits and one shoulder hit (got %d/%d)"
		% [road_hits, shoulder_hits]
	)
	var all_hit_spread: float = (
		result.probes[4]["distance_m"] - result.probes[1]["distance_m"]
	)
	d.check_close(all_hit_spread, SHOULDER_DROP_M, 1e-5, "coherent: all-hit spread")
	d.check(
		all_hit_spread > config.footprint_support_spread_max_m,
		"coherent: all-hit spread exceeds the provisional tolerance"
	)

	# Non-monotonicity control: the same shoulder deeper than the support
	# bound is discarded, leaving the same three-hit road cluster grounded.
	# Destroy the shallow stage first so its shoulder cannot lie above the deep
	# one along the same ray.
	await _destroy(world)
	var deep_world := await _build(
		_three_road_plus_shoulder_slabs(-0.8),
		[],
		[_car_spec("Car", Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))]
	)
	var deep := _probe(deep_world, "Car", config, transform)
	_check_common_ok_result(deep, config, ProbeScript.PROBE_COUNT, "coherent-deep")
	var deep_shoulder: Dictionary = deep.probes[4]
	d.check(
		not deep_shoulder["valid"],
		"coherent-deep: shoulder beyond the support bound is not legal"
	)
	d.check(
		deep_shoulder["reason"] == "beyond_max_support",
		"coherent-deep: shoulder reason beyond_max_support (got %s)"
		% deep_shoulder["reason"]
	)
	d.check(
		deep.footprint_support_count == 3,
		"coherent-deep: three legal footprint hits remain (got %d)"
		% deep.footprint_support_count
	)
	d.check(
		deep.grounded,
		"coherent-deep: three road hits still ground without the far shoulder"
	)
	d.check(
		_cluster_size_of(deep) == 3,
		"coherent-deep: remaining cluster size is three (got %d)"
		% _cluster_size_of(deep)
	)
	measurements["coherent_cluster_size"] = _cluster_size_of(result)
	measurements["coherent_all_hit_spread_m"] = all_hit_spread
	measurements["coherent_deep_cluster_size"] = _cluster_size_of(deep)
	await _destroy(deep_world)


## Witness-binding case: a centre miss with three agreeing road hits plus a
## fourth legal hit from a closer, tilted outlier slab. Grounding comes from
## the three-hit road cluster, so the selected support identity, point,
## distance, height and normal must all belong to that cluster, never to the
## closer outlier. The historical selection rule picked the closest legal hit
## of all, which is exactly the outlier here.
func _case_cluster_closer_outlier() -> void:
	var config := d.make_config_with(
		LONG_RAY_LENGTH_M, UNEVEN_SUPPORT_BOUND_M, 2, 0.25
	)
	var transform := d.flat_transform(Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))
	var offsets := d.expected_offsets(config)
	var world := await _build(
		_three_road_plus_closer_outlier_slabs(CLOSER_OUTLIER_TOP_Y, offsets[4]),
		[],
		[_car_spec("Car", Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))]
	)
	var road_right := world.root.get_node_or_null("RoadRight")
	var road_rear_left := world.root.get_node_or_null("RoadRearLeft")
	var outlier := world.root.get_node_or_null("CloserOutlier")
	d.check(road_right != null, "closer-outlier: right road stage present")
	d.check(road_rear_left != null, "closer-outlier: rear-left road stage present")
	d.check(outlier != null, "closer-outlier: outlier stage present")

	var result := _probe(world, "Car", config, transform)
	_check_common_ok_result(result, config, ProbeScript.PROBE_COUNT, "closer-outlier")
	var center: Dictionary = result.probes[0]
	d.check(not center["hit"], "closer-outlier: central ray misses the seam")
	d.check(
		center["reason"] == "no_hit",
		"closer-outlier: central reason no_hit (got %s)" % center["reason"]
	)
	d.check(not result.center_supported, "closer-outlier: central probe unsupported")
	d.check(
		result.footprint_support_count == 4,
		"closer-outlier: four legal footprint hits (got %d)"
		% result.footprint_support_count
	)
	d.check(result.grounded, "closer-outlier: three agreeing road hits ground")
	d.check(
		_cluster_size_of(result) == 3,
		"closer-outlier: unique cluster size is three (got %d)"
		% _cluster_size_of(result)
	)
	d.check(
		_cluster_indices_of(result) == [1, 2, 3],
		"closer-outlier: cluster is rear_right, rear_left, front_right (got %s)"
		% str(_cluster_indices_of(result))
	)

	# The closer outlier really is legal, closer than every road hit, and a
	# distinct collider with a distinct normal.
	var outlier_detail: Dictionary = result.probes[4]
	d.check(outlier_detail["valid"], "closer-outlier: outlier hit is legal support")
	d.check_close(
		outlier_detail["distance_m"], d.BODY_SUPPORT_Y - CLOSER_OUTLIER_TOP_Y, 1e-5,
		"closer-outlier: outlier distance is closer than the road"
	)
	d.check(
		outlier_detail["distance_m"] < result.probes[1]["distance_m"],
		"closer-outlier: outlier is closer than the agreeing road hits"
	)
	d.check_vector_close(
		outlier_detail["normal"],
		Vector3(
			-sin(deg_to_rad(CLOSER_OUTLIER_TILT_DEG)),
			cos(deg_to_rad(CLOSER_OUTLIER_TILT_DEG)),
			0.0
		),
		1e-6,
		"closer-outlier: outlier normal is distinct from up"
	)
	if outlier != null:
		d.check(
			_detail_int(outlier_detail, "collider_id") == outlier.get_instance_id(),
			"closer-outlier: outlier detail reports the outlier collider"
		)

	# Selected support must belong to the grounding cluster: identity, point,
	# distance, height and normal.
	var witness_indices := _cluster_indices_of(result)
	d.check(
		witness_indices.has(result.support_probe_index),
		"closer-outlier: selected support probe is in the grounding cluster (got %d)"
		% result.support_probe_index
	)
	d.check(
		result.support_probe_index == 1,
		"closer-outlier: deterministic tie selects rear_right (got %d)"
		% result.support_probe_index
	)
	d.check(
		result.support_probe_index != 4,
		"closer-outlier: selected support is not the closer outlier probe"
	)
	d.check(
		_result_witness_indices(result) == witness_indices,
		"closer-outlier: exposed witness set is the grounding cluster (got %s)"
		% str(_result_witness_indices(result))
	)
	d.check(
		_result_support_is_witness(result),
		"closer-outlier: selected support is flagged as the grounding witness"
	)
	if road_right != null:
		d.check(
			_result_identity_int(result, "support_collider_id") == road_right.get_instance_id(),
			"closer-outlier: selected identity is the road cluster collider"
		)
	if outlier != null:
		d.check(
			_result_identity_rid(result, "support_rid") != outlier.get_rid(),
			"closer-outlier: selected rid is not the outlier"
		)
	d.check_vector_close(
		result.support_point,
		Vector3(offsets[1].x, 0.0, offsets[1].z),
		1e-5,
		"closer-outlier: selected point lies on the road surface"
	)
	d.check_close(
		result.support_distance_m, d.BODY_SUPPORT_Y, 1e-5,
		"closer-outlier: selected distance is the road distance"
	)
	d.check_close(
		result.support_height_m, d.BODY_SUPPORT_Y, 1e-5,
		"closer-outlier: selected height is the road drop"
	)
	d.check_vector_close(
		result.support_normal,
		Vector3.UP,
		1e-6,
		"closer-outlier: selected normal excludes the tilted outlier"
	)
	measurements["closer_outlier_selected_probe_index"] = result.support_probe_index
	measurements["closer_outlier_selected_distance_m"] = result.support_distance_m
	await _destroy(world)


func _case_too_steep_surface() -> void:
	var euler := Vector3(0.0, 0.0, 70.0)
	var pose: Dictionary = d.plane_pose(Vector3.ZERO, euler, d.BODY_SUPPORT_Y)
	var slab_center := d.rotated_slab_center(Vector3.ZERO, FLOOR_SIZE, euler)
	var world := await _build(
		[_slab("SteepFace", FLOOR_SIZE, slab_center, 1, euler)],
		[],
		[_car_spec("Car", pose["origin"], 1, pose["basis"])]
	)
	# The steep-surface probe deliberately rolls the body 70 degrees so the
	# rays meet the face perpendicularly. Relax only the attitude gate
	# (cos 70 = 0.342 >= 0.2); the surface-normal threshold stays at default.
	var config := d.make_config()
	config.min_frame_up_dot = 0.2
	var result := _probe(world, "Car", config, d.plane_pose_transform(pose))
	_check_common_ok_result(result, config, ProbeScript.PROBE_COUNT, "steep")
	for index in range(result.probes.size()):
		var detail: Dictionary = result.probes[index]
		var label: String = d.PROBE_LABELS[index]
		d.check(detail["hit"], "steep %s: ray reaches the surface" % label)
		d.check(
			not detail["valid"],
			"steep %s: 70 degree surface is not legal support" % label
		)
		d.check(
			detail["reason"] == "steep_normal",
			"steep %s: reason steep_normal (got %s)" % [label, detail["reason"]]
		)
		d.check_close(
			detail["up_dot"], cos(deg_to_rad(70.0)), 1e-6,
			"steep %s: measured up dot" % label
		)
	d.check(not result.grounded, "steep: not grounded")
	d.check(result.support_count == 0, "steep: zero legal supports")
	d.check(not result.has_support, "steep: no support reported")
	d.check_vector_close(result.support_normal, Vector3.ZERO, 0.0, "steep: no averaged normal")

	# Sensitivity control: a threshold below the measured alignment accepts
	# the same surface.
	var relaxed := d.make_config()
	relaxed.min_frame_up_dot = 0.2
	relaxed.min_up_dot = 0.2
	var relaxed_result := _probe(world, "Car", relaxed, d.plane_pose_transform(pose))
	d.check(relaxed_result.grounded, "steep control: relaxed threshold accepts")
	d.check(
		relaxed_result.support_count == 5,
		"steep control: all five hits accepted"
	)
	d.check_vector_close(
		relaxed_result.support_normal, pose["normal"], 1e-6,
		"steep control: averaged normal matches"
	)
	measurements["measured_up_dot"] = result.probes[0]["up_dot"]
	await _destroy(world)


func _case_absent_floor() -> void:
	var world := await _build([], [], [_car_spec("Car", Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))])
	var config := d.make_config()
	var result := _probe(world, "Car", config, d.flat_transform(Vector3(0.0, d.BODY_SUPPORT_Y, 0.0)))
	_check_common_ok_result(result, config, ProbeScript.PROBE_COUNT, "absent")
	d.check(not result.grounded, "absent: not grounded")
	d.check(result.support_count == 0, "absent: zero supports")
	d.check(not result.has_support, "absent: no support")
	d.check_vector_close(result.support_normal, Vector3.ZERO, 0.0, "absent: no averaged normal")
	for index in range(result.probes.size()):
		var detail: Dictionary = result.probes[index]
		d.check(not detail["hit"], "absent %d: no hit" % index)
		d.check(
			detail["reason"] == "no_hit",
			"absent %d: reason no_hit (got %s)" % [index, detail["reason"]]
		)
	await _destroy(world)


func _case_mask_exclusion() -> void:
	var obstacle := _slab(
		"Obstacle", Vector3(4.0, 0.8, 4.0), Vector3.ZERO, 2
	)
	# The area's top (y=0.3) is closer than the obstacle top (y=0.4), so an
	# area-including query would report a different support distance.
	var area := _area("SensorArea", Vector3(4.0, 0.4, 4.0), Vector3(0.0, 0.1, 0.0), 1)
	var world := await _build(
		[obstacle],
		[area],
		[
			_car_spec("CarMasked", Vector3(0.0, d.BODY_SUPPORT_Y, 0.0), 1),
			_car_spec("CarWide", Vector3(0.0, d.BODY_SUPPORT_Y, 0.0), 3),
		]
	)
	var config := d.make_config()
	var transform := d.flat_transform(Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))

	var masked := _probe(world, "CarMasked", config, transform)
	_check_common_ok_result(masked, config, ProbeScript.PROBE_COUNT, "mask-masked")
	d.check(not masked.grounded, "mask-masked: layer-2 obstacle excluded by mask")
	d.check(
		masked.support_count == 0,
		"mask-masked: no legal support (got %d)" % masked.support_count
	)
	for index in range(masked.probes.size()):
		d.check(
			not masked.probes[index]["hit"],
			"mask-masked %d: no hit through the mask" % index
		)

	var wide := _probe(world, "CarWide", config, transform)
	_check_common_ok_result(wide, config, ProbeScript.PROBE_COUNT, "mask-wide")
	d.check(wide.grounded, "mask-wide: layer-2 obstacle becomes visible")
	d.check(wide.support_count == 5, "mask-wide: all five probes hit the obstacle")
	d.check_close(
		wide.support_distance_m, 0.15, 1e-5,
		"mask-wide: obstacle top is 0.15 m below the origin"
	)
	d.check_vector_close(
		wide.support_point, Vector3(0.0, 0.4, 0.0), 1e-5,
		"mask-wide: support point on the obstacle, not the nearer area"
	)
	d.check_vector_close(wide.support_normal, Vector3.UP, 1e-6, "mask-wide: up normal")
	measurements["masked_support_count"] = masked.support_count
	measurements["wide_support_distance_m"] = wide.support_distance_m
	await _destroy(world)


func _case_invalid_input_unchanged() -> void:
	var world := await _build(_floor_slabs(), [], [_car_spec("Car", Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))])
	var car := world.body("Car")
	var shape := world.hull_shape("Car")
	var valid_config := d.make_config()
	var valid_transform := d.flat_transform(Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))
	var pose_before := car.global_transform

	var nan_hull := d.make_config()
	nan_hull.hull_size_m = Vector3(NAN, 1.0, 3.8)
	var zero_ray := d.make_config()
	zero_ray.ray_length_m = 0.0
	var huge_ray := d.make_config()
	huge_ray.ray_length_m = ProbeScript.ABSOLUTE_MAX_RAY_LENGTH_M + 0.5
	var huge_support := d.make_config()
	huge_support.max_support_distance_m = 1.5
	var negative_inset := d.make_config()
	negative_inset.footprint_inset_fraction = -0.1
	var collapsed_inset := d.make_config()
	collapsed_inset.footprint_inset_fraction = 0.5
	var high_up_dot := d.make_config()
	high_up_dot.min_up_dot = 1.5
	var negative_up_dot := d.make_config()
	negative_up_dot.min_up_dot = -0.1
	var zero_required := d.make_config()
	zero_required.required_footprint_hits = 0
	var many_required := d.make_config()
	many_required.required_footprint_hits = 5
	var nan_spread := d.make_config()
	nan_spread.footprint_support_spread_max_m = NAN
	var hull_mismatch := d.make_config()
	hull_mismatch.hull_size_m = Vector3(1.9, 1.0, 3.8)

	var scaled_basis := Transform3D(
		Basis(
			Vector3(2.0, 0.0, 0.0),
			Vector3(0.0, 2.0, 0.0),
			Vector3(0.0, 0.0, 2.0)
		),
		Vector3.ZERO
	)
	var skewed_basis := Transform3D(
		Basis(
			Vector3(1.0, 0.0, 0.0),
			Vector3(1.0, 1.0, 0.0),
			Vector3(0.0, 0.0, 1.0)
		),
		Vector3.ZERO
	)
	var nan_origin := Transform3D(Basis(), Vector3(NAN, 0.0, 0.0))
	var nan_basis := Transform3D(
		Basis(
			Vector3(NAN, 0.0, 0.0),
			Vector3.UP,
			Vector3.BACK
		),
		Vector3.ZERO
	)

	var nan_shape := BoxShape3D.new()
	nan_shape.size = Vector3(NAN, 1.0, 3.8)

	var mismatched_shape_world := await _build(
		_floor_slabs(),
		[],
		[_car_spec("OtherCar", Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))]
	)
	var mismatched_shape := BoxShape3D.new()
	mismatched_shape.size = Vector3(1.7, 1.0, 3.8)
	mismatched_shape_world.body("OtherCar").get_child(0).shape = mismatched_shape
	await _await_frames(2)

	var variants := [
		{"name": "null body", "body": null, "shape": shape, "config": valid_config, "transform": valid_transform, "check_body": false},
		{"name": "null shape", "body": car, "shape": null, "config": valid_config, "transform": valid_transform, "check_body": true},
		{"name": "null config", "body": car, "shape": shape, "config": null, "transform": valid_transform, "check_body": true},
		{"name": "nan hull", "body": car, "shape": shape, "config": nan_hull, "transform": valid_transform, "check_body": true},
		{"name": "zero ray length", "body": car, "shape": shape, "config": zero_ray, "transform": valid_transform, "check_body": true},
		{"name": "ray above absolute cap", "body": car, "shape": shape, "config": huge_ray, "transform": valid_transform, "check_body": true},
		{"name": "support bound above ray", "body": car, "shape": shape, "config": huge_support, "transform": valid_transform, "check_body": true},
		{"name": "negative inset", "body": car, "shape": shape, "config": negative_inset, "transform": valid_transform, "check_body": true},
		{"name": "collapsed inset", "body": car, "shape": shape, "config": collapsed_inset, "transform": valid_transform, "check_body": true},
		{"name": "up dot above one", "body": car, "shape": shape, "config": high_up_dot, "transform": valid_transform, "check_body": true},
		{"name": "negative up dot", "body": car, "shape": shape, "config": negative_up_dot, "transform": valid_transform, "check_body": true},
		{"name": "zero required hits", "body": car, "shape": shape, "config": zero_required, "transform": valid_transform, "check_body": true},
		{"name": "five required hits", "body": car, "shape": shape, "config": many_required, "transform": valid_transform, "check_body": true},
		{"name": "nan spread", "body": car, "shape": shape, "config": nan_spread, "transform": valid_transform, "check_body": true},
		{"name": "hull mismatch", "body": car, "shape": shape, "config": hull_mismatch, "transform": valid_transform, "check_body": true},
		{"name": "nan hull shape", "body": car, "shape": nan_shape, "config": valid_config, "transform": valid_transform, "check_body": true},
		{"name": "scaled transform", "body": car, "shape": shape, "config": valid_config, "transform": scaled_basis, "check_body": true},
		{"name": "skewed transform", "body": car, "shape": shape, "config": valid_config, "transform": skewed_basis, "check_body": true},
		{"name": "nan origin", "body": car, "shape": shape, "config": valid_config, "transform": nan_origin, "check_body": true},
		{"name": "nan basis", "body": car, "shape": shape, "config": valid_config, "transform": nan_basis, "check_body": true},
		{"name": "mismatched shape", "body": mismatched_shape_world.body("OtherCar"), "shape": mismatched_shape, "config": valid_config, "transform": valid_transform, "check_body": true},
	]

	for variant in variants:
		var label: String = variant["name"]
		var variant_config = variant["config"]
		var variant_body: CharacterBody3D = variant["body"]
		var body_pose_snapshot := Transform3D()
		if variant["check_body"] and variant_body != null:
			body_pose_snapshot = variant_body.global_transform
		var config_snapshot := {}
		if variant_config != null:
			config_snapshot = d.snapshot_config(variant_config)
		var result: ProbeScript.Result = ProbeScript.probe(
			variant["body"], variant["shape"], variant_config, variant["transform"]
		)
		d.check(
			result.status == ProbeScript.Status.REJECTED_INVALID_INPUT,
			"%s: REJECTED_INVALID_INPUT (got %s, %s)"
			% [label, result.status, result.rejection_reason]
		)
		d.check(
			result.queries_used == 0,
			"%s: zero queries issued (got %d)" % [label, result.queries_used]
		)
		d.check(result.probes.is_empty(), "%s: no probe details exposed" % label)
		if variant["check_body"] and variant_body != null:
			d.check(
				variant_body.global_transform.origin == body_pose_snapshot.origin
				and variant_body.global_transform.basis == body_pose_snapshot.basis,
				"%s: body transform unchanged" % label
			)
		if variant_config != null:
			d.check_config_unchanged(variant_config, config_snapshot, label)

	# Scaled carrier: refused, and the scale itself is untouched.
	car.scale = Vector3(2.0, 2.0, 2.0)
	var scale_snapshot := car.scale
	var scaled_result := ProbeScript.probe(car, shape, valid_config, valid_transform)
	d.check(
		scaled_result.status == ProbeScript.Status.REJECTED_INVALID_INPUT,
		"scaled body: refused"
	)
	d.check(scaled_result.queries_used == 0, "scaled body: zero queries")
	d.check(car.scale == scale_snapshot, "scaled body: scale unchanged")
	car.scale = Vector3.ONE
	d.check(
		car.global_transform.origin == pose_before.origin,
		"invalid suite: body origin never moved"
	)

	await _destroy(mismatched_shape_world)
	await _destroy(world)


func _case_deterministic_repeat() -> void:
	var fingerprints: Array = []
	var world := await _build(_floor_slabs(), [], [_car_spec("Car", Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))])
	var config := d.make_config()
	var transform := d.flat_transform(Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))
	for _index in range(5):
		fingerprints.append(d.result_fingerprint(_probe(world, "Car", config, transform)))
	await _destroy(world)
	var first_flat: Array = fingerprints[0]
	var mismatches := 0
	for index in range(1, fingerprints.size()):
		if not _fingerprints_equal(fingerprints[index], first_flat):
			mismatches += 1
	d.check(mismatches == 0, "repeat flat: five identical fingerprints (%d mismatches)" % mismatches)

	# Fresh stage, same geometry: the query results must still match exactly.
	var rebuilt := await _build(_floor_slabs(), [], [_car_spec("Car", Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))])
	var rebuilt_fingerprint := d.result_fingerprint(_probe(rebuilt, "Car", config, transform))
	d.check_fingerprint_equal(
		rebuilt_fingerprint, first_flat, "repeat rebuild"
	)
	await _destroy(rebuilt)

	var euler := Vector3(0.0, 0.0, 12.0)
	var pose: Dictionary = d.plane_pose(Vector3.ZERO, euler, d.BODY_SUPPORT_Y)
	var slab_center := d.rotated_slab_center(Vector3.ZERO, FLOOR_SIZE, euler)
	var banked := await _build(
		[_slab("Bank", FLOOR_SIZE, slab_center, 1, euler)],
		[],
		[_car_spec("Car", pose["origin"], 1, pose["basis"])]
	)
	var banked_fingerprints: Array = []
	for _index in range(3):
		banked_fingerprints.append(
			d.result_fingerprint(_probe(banked, "Car", config, d.plane_pose_transform(pose)))
		)
	await _destroy(banked)
	var banked_first: Array = banked_fingerprints[0]
	var banked_mismatches := 0
	for index in range(1, banked_fingerprints.size()):
		if not _fingerprints_equal(banked_fingerprints[index], banked_first):
			banked_mismatches += 1
	d.check(
		banked_mismatches == 0,
		"repeat bank: three identical fingerprints (%d mismatches)" % banked_mismatches
	)
	measurements["flat_repeats"] = fingerprints.size()
	measurements["flat_mismatches"] = mismatches
	measurements["bank_repeats"] = banked_fingerprints.size()
	measurements["bank_mismatches"] = banked_mismatches


func _case_exactly_five_queries() -> void:
	var world := await _build(_floor_slabs(), [], [_car_spec("Car", Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))])
	var config := d.make_config()
	var transform := d.flat_transform(Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))
	var result := _probe(world, "Car", config, transform)
	_check_common_ok_result(result, config, ProbeScript.PROBE_COUNT, "queries")

	d.check(result.queries_used == 5, "queries: exactly five intersect_ray calls")
	d.check(result.probes.size() == 5, "queries: exactly five probe records")
	var expected_offsets := d.expected_offsets(config)
	var center_count := 0
	var footprint_count := 0
	for index in range(result.probes.size()):
		var detail: Dictionary = result.probes[index]
		var offset: Vector3 = detail["offset_local"]
		d.check_vector_close(
			offset, expected_offsets[index], 1e-9,
			"queries %d: offset matches the documented inset rule" % index
		)
		if offset.is_equal_approx(Vector3.ZERO):
			center_count += 1
			d.check(detail["label"] == "center", "queries: zero offset is the central probe")
		else:
			footprint_count += 1
			d.check(
				absf(absf(offset.x) - absf(expected_offsets[index].x)) < 1e-9
				and absf(absf(offset.z) - absf(expected_offsets[index].z)) < 1e-9,
				"queries %d: footprint inset inside the hull edge" % index
			)
		d.check_vector_close(
			detail["end"] - detail["start"],
			detail["direction"] * config.ray_length_m,
			1e-9,
			"queries %d: ray length capped at configuration" % index
		)
		d.check(
			detail["direction"].dot(transform.basis.y) <= -1.0 + 1e-9,
			"queries %d: cast along local down" % index
		)
	d.check(center_count == 1, "queries: exactly one central probe")
	d.check(footprint_count == 4, "queries: exactly four footprint probes")

	# Refusal path issues no query at all.
	var bad_config := d.make_config()
	bad_config.ray_length_m = 0.0
	var refused := _probe(world, "Car", bad_config, transform)
	d.check(
		refused.status == ProbeScript.Status.REJECTED_INVALID_INPUT,
		"queries: invalid config refused"
	)
	d.check(refused.queries_used == 0, "queries: refusal issues zero queries")
	d.check(refused.probes.is_empty(), "queries: refusal exposes no probe records")
	await _destroy(world)


## Identity telemetry case: a candidate body held above the road can only
## reach a same-mask second car roof. The rays must report the second car's
## stable identity rather than the road's, and replacing that roof with an
## eligible road slab at the same height must change the selected identity.
## The case also pins the absent identity defaults for no-hit, refusal and
## self-exclusion probes. It claims no route eligibility.
func _case_support_identity() -> void:
	var candidate_position := Vector3(0.0, 2.55, 0.0)
	var roof_top_y := 2.0
	var roof_center_y := roof_top_y - 0.5 * d.HULL_SIZE.y
	var config := d.make_config()
	var transform := d.flat_transform(candidate_position)
	d.check(
		candidate_position.y > config.ray_length_m,
		"identity roof: road is outside the configured ray reach"
	)

	var world := await _build(
		_floor_slabs(),
		[],
		[
			_car_spec("Probe", candidate_position),
			_car_spec("RoofCar", Vector3(0.0, roof_center_y, 0.0)),
		]
	)
	var roof_car := world.body("RoofCar")
	var road = world.root.get_node_or_null("Floor")
	d.check(road != null, "identity roof: road stage present")

	var result := _probe(world, "Probe", config, transform)
	_check_common_ok_result(result, config, ProbeScript.PROBE_COUNT, "identity-roof")
	d.check(result.grounded, "identity roof: grounded on the same-mask car roof")
	d.check(result.center_supported, "identity roof: central probe supports")
	d.check(
		result.support_count == ProbeScript.PROBE_COUNT,
		"identity roof: all five rays read the roof (got %d)" % result.support_count
	)
	d.check_close(
		result.support_distance_m, candidate_position.y - roof_top_y, 1e-5,
		"identity roof: support distance to the roof"
	)
	d.check_vector_close(
		result.support_point, Vector3(0.0, roof_top_y, 0.0), 1e-5,
		"identity roof: support point on the roof"
	)
	for index in range(result.probes.size()):
		var detail: Dictionary = result.probes[index]
		d.check(detail["hit"], "identity roof %d: ray hit" % index)
		d.check(detail["valid"], "identity roof %d: legal support" % index)
		d.check(
			_detail_int(detail, "collider_id") == roof_car.get_instance_id(),
			"identity roof %d: collider id is the second car (got %d, want %d)"
			% [index, _detail_int(detail, "collider_id"), roof_car.get_instance_id()]
		)
		d.check(
			_detail_rid(detail, "rid") == roof_car.get_rid(),
			"identity roof %d: rid is the second car" % index
		)
		d.check(
			_detail_int(detail, "shape_index") == 0,
			"identity roof %d: shape index is zero (got %d)"
			% [index, _detail_int(detail, "shape_index")]
		)
		if road != null:
			d.check(
				_detail_rid(detail, "rid") != road.get_rid(),
				"identity roof %d: ray does not report the road" % index
			)
	d.check(result.support_probe_index == 0, "identity roof: closest support is central")
	d.check(
		_result_identity_int(result, "support_collider_id") == roof_car.get_instance_id(),
		"identity roof: selected collider id is the second car"
	)
	d.check(
		_result_identity_rid(result, "support_rid") == roof_car.get_rid(),
		"identity roof: selected rid is the second car"
	)
	d.check(
		_result_identity_int(result, "support_shape_index") == 0,
		"identity roof: selected shape index is zero"
	)
	if road != null:
		d.check(
			_result_identity_rid(result, "support_rid") != road.get_rid(),
			"identity roof: selected identity is not the road"
		)
	var roof_collider_id := roof_car.get_instance_id()
	var roof_rid := roof_car.get_rid()
	await _destroy(world)

	# Replace the car roof with an eligible road slab at the same height. The
	# behavioural outputs stay the same; the selected identity must move.
	var high_road_world := await _build(
		[_slab("HighRoad", FLOOR_SIZE, Vector3(0.0, roof_top_y - 0.5, 0.0))],
		[],
		[_car_spec("Probe", candidate_position)]
	)
	var road_collider: CollisionObject3D = (
		high_road_world.root.get_node_or_null("HighRoad") as CollisionObject3D
	)
	if road_collider == null:
		d.check(false, "identity road: road slab stage present")
	else:
		var road_result := _probe(high_road_world, "Probe", config, transform)
		_check_common_ok_result(road_result, config, ProbeScript.PROBE_COUNT, "identity-road")
		d.check(road_result.grounded, "identity road: grounded on the road slab")
		d.check(
			road_result.support_count == ProbeScript.PROBE_COUNT,
			"identity road: all five rays read the road slab (got %d)"
			% road_result.support_count
		)
		d.check_close(
			road_result.support_distance_m, candidate_position.y - roof_top_y, 1e-5,
			"identity road: unchanged support distance"
		)
		for index in range(road_result.probes.size()):
			var detail: Dictionary = road_result.probes[index]
			d.check(
				_detail_int(detail, "collider_id") == road_collider.get_instance_id(),
				"identity road %d: collider id is the road slab (got %d, want %d)"
				% [index, _detail_int(detail, "collider_id"), road_collider.get_instance_id()]
			)
			d.check(
				_detail_rid(detail, "rid") == road_collider.get_rid(),
				"identity road %d: rid is the road slab" % index
			)
		d.check(
			_result_identity_int(road_result, "support_collider_id") == road_collider.get_instance_id(),
			"identity road: selected collider id changed to the road slab"
		)
		d.check(
			_result_identity_rid(road_result, "support_rid") == road_collider.get_rid(),
			"identity road: selected rid changed to the road slab"
		)
		d.check(
			_result_identity_rid(road_result, "support_rid") != roof_rid,
			"identity road: selected identity differs from the car roof"
		)
		d.check(
			_result_identity_int(road_result, "support_collider_id") != roof_collider_id,
			"identity road: selected collider id differs from the car roof"
		)
		measurements["roof_collider_id"] = roof_collider_id
		measurements["road_collider_id"] = road_collider.get_instance_id()
	await _destroy(high_road_world)

	# No-hit defaults: absent geometry leaves per-probe and selected identity
	# at the documented absent values.
	var empty_world := await _build(
		[], [], [_car_spec("Probe", Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))]
	)
	var empty_transform := d.flat_transform(Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))
	var empty_result := _probe(empty_world, "Probe", config, empty_transform)
	_check_common_ok_result(empty_result, config, ProbeScript.PROBE_COUNT, "identity-absent")
	d.check(not empty_result.has_support, "identity absent: no selected support")
	d.check(
		_result_identity_int(empty_result, "support_collider_id") == -1,
		"identity absent: selected collider id default"
	)
	d.check(
		_result_identity_rid(empty_result, "support_rid") == RID(),
		"identity absent: selected rid default"
	)
	d.check(
		_result_identity_int(empty_result, "support_shape_index") == -1,
		"identity absent: selected shape index default"
	)
	for index in range(empty_result.probes.size()):
		var detail: Dictionary = empty_result.probes[index]
		d.check(not detail["hit"], "identity absent %d: no hit" % index)
		d.check(
			_detail_int(detail, "collider_id") == -1,
			"identity absent %d: detail collider id default" % index
		)
		d.check(
			_detail_rid(detail, "rid") == RID(),
			"identity absent %d: detail rid default" % index
		)
		d.check(
			_detail_int(detail, "shape_index") == -1,
			"identity absent %d: detail shape index default" % index
		)
	await _destroy(empty_world)

	# Refusal defaults: an invalid config issues zero queries and exposes no
	# identity.
	var bad_config := d.make_config()
	bad_config.ray_length_m = 0.0
	var refuse_world := await _build(
		_floor_slabs(), [], [_car_spec("Probe", Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))]
	)
	var refused := _probe(refuse_world, "Probe", bad_config, empty_transform)
	d.check(
		refused.status == ProbeScript.Status.REJECTED_INVALID_INPUT,
		"identity refusal: refused"
	)
	d.check(refused.queries_used == 0, "identity refusal: zero queries")
	d.check(refused.probes.is_empty(), "identity refusal: no probe details")
	d.check(
		_result_identity_int(refused, "support_collider_id") == -1,
		"identity refusal: selected collider id default"
	)
	d.check(
		_result_identity_rid(refused, "support_rid") == RID(),
		"identity refusal: selected rid default"
	)
	d.check(
		_result_identity_int(refused, "support_shape_index") == -1,
		"identity refusal: selected shape index default"
	)
	await _destroy(refuse_world)

	# Positive control: a separate car roof in the same relative ray path is
	# reported, so the exclusion test below is meaningful.
	var target_position := Vector3(5.0, d.BODY_SUPPORT_Y, 0.0)
	var target_transform := d.flat_transform(Vector3(5.0, d.BODY_SUPPORT_Y + 1.0, 0.0))
	var target_world := await _build(
		_floor_slabs(),
		[],
		[
			_car_spec("Probe", Vector3(0.0, d.BODY_SUPPORT_Y, 0.0)),
			_car_spec("Target", target_position),
		]
	)
	var target := target_world.body("Target")
	var target_result := _probe(target_world, "Probe", config, target_transform)
	_check_common_ok_result(target_result, config, ProbeScript.PROBE_COUNT, "identity-target")
	d.check(target_result.grounded, "identity target: separate roof grounds")
	d.check(
		_result_identity_int(target_result, "support_collider_id") == target.get_instance_id(),
		"identity target: selected collider id is the separate car"
	)
	d.check(
		_result_identity_rid(target_result, "support_rid") == target.get_rid(),
		"identity target: selected rid is the separate car"
	)
	await _destroy(target_world)

	# Self-exclusion: the candidate's own roof occupies the same ray path as
	# the positive control, but its RID is excluded and the road is out of
	# reach, so no hit is reported and identity stays at its defaults.
	var self_world := await _build(
		_floor_slabs(), [], [_car_spec("Probe", Vector3(0.0, d.BODY_SUPPORT_Y, 0.0))]
	)
	var self_transform := d.flat_transform(Vector3(0.0, d.BODY_SUPPORT_Y + 1.0, 0.0))
	var self_result := _probe(self_world, "Probe", config, self_transform)
	_check_common_ok_result(self_result, config, ProbeScript.PROBE_COUNT, "identity-self")
	d.check(not self_result.grounded, "identity self: excluded own roof does not ground")
	d.check(self_result.support_count == 0, "identity self: zero legal supports")
	d.check(not self_result.has_support, "identity self: no selected support")
	d.check(
		_result_identity_int(self_result, "support_collider_id") == -1,
		"identity self: selected collider id default"
	)
	d.check(
		_result_identity_rid(self_result, "support_rid") == RID(),
		"identity self: selected rid default"
	)
	d.check(
		_result_identity_int(self_result, "support_shape_index") == -1,
		"identity self: selected shape index default"
	)
	for index in range(self_result.probes.size()):
		var detail: Dictionary = self_result.probes[index]
		d.check(not detail["hit"], "identity self %d: no self hit" % index)
		d.check(
			_detail_int(detail, "collider_id") == -1,
			"identity self %d: detail collider id default" % index
		)
		d.check(
			_detail_rid(detail, "rid") == RID(),
			"identity self %d: detail rid default" % index
		)
		d.check(
			_detail_int(detail, "shape_index") == -1,
			"identity self %d: detail shape index default" % index
		)
	await _destroy(self_world)
