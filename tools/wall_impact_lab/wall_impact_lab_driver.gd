extends Node
## Headless M1.8 wall-impact publication validator.
##
## Runs the pure `WallImpactProducer` against explicit synthetic witnesses and
## prints one machine-readable `WALL_IMPACT_LAB_RESULT <json>` per case plus a
## final `WALL_IMPACT_LAB_SUMMARY`. The last case drives one real pinned-Jolt
## wall hit through `tools/body_lab/body_lab_world.gd` and feeds the committed
## adapter result to the producer.
##
## Exit 0 means every case passed. This proves the producer's publication
## contract and one real witness path; it does not implement car-car impact
## production, presentation wiring, cosmetic damage, full M1.8 or M1
## acceptance.

const ProducerScript = preload("res://src/simulation/wall_impact_producer.gd")
const AdapterScript = preload("res://src/simulation/motor_body_adapter.gd")
const ChecksScript = preload("res://tools/wall_impact_lab/wall_impact_lab_checks.gd")
const WorldScript = preload("res://tools/body_lab/body_lab_world.gd")
const BodyLabChecksScript = preload("res://tools/body_lab/body_lab_checks.gd")

const CASE_IDS: Array[String] = [
	"four_regions_and_corner_ties",
	"head_on_and_oblique_severity",
	"tilted_normal_road_plane_projection",
	"zero_imparted_motion_is_explicit",
	"witness_refusals_fail_closed",
	"ledger_publication_duplicate_conflict",
	"input_and_result_nonmutation",
	"producer_source_contract",
	"corner_near_tie_response_normal",
	"post_velocity_canonical_agreement",
	"collision_time_frame_discrimination",
]

const JOLT_CASE_ID := "real_jolt_wall_integration"
const STEERING_JOLT_CASE_ID := "real_jolt_steering_corner"
const NONZERO_HEADING_JOLT_CASE_ID := "real_jolt_nonzero_heading_corner"
const NARROW_WALL_END_JOLT_CASE_ID := "real_jolt_narrow_wall_end"

## Frames allowed for static colliders to reach the physics server.
const SETTLE_FRAMES := 8
## Extra frames after teleporting the body before its first tick.
const POSE_SETTLE_FRAMES := 3
const WALL_THICKNESS_M := 2.0
const WALL_WIDTH_M := 20.0
const STRAIGHT_WALL_Z := -20.0
## Enough ticks for the laboratory car to reach the wall at 30 m/s.
const JOLT_MAX_TICKS := 80
## Ticks for the steering-corner scenarios. Contact begins on tick 2 of the
## pinned probe scenario and persists through the end of the run.
const STEERING_CORNER_TICKS := 30
## Matches the reviewer sweep that exposed nonzero-heading corner noise.
const NONZERO_HEADING_CORNER_TICKS := 40
## Wide wall so a steering car cannot leave the wall footprint mid-scenario.
const STEERING_WALL_WIDTH_M := 60.0
## Narrow wall whose vertical convex end can slide along the car's side face.
const NARROW_WALL_WIDTH_M := 0.6
## Corner-band and normal-axis thresholds mirrored from the producer's
## published contract. Kept as explicit literals so a silent threshold change
## is visible here. The old normalized band is retained only as a negative
## control for the regression coverage.
const LAB_REGION_CORNER_BAND_M := 0.035
const LAB_REGION_NORMAL_AXIS_MARGIN := 1e-3
const OLD_NORMALIZED_REGION_TIE_MARGIN := 1e-2

var d := ChecksScript.new()
var measurements: Dictionary = {}
var _results: Array[Dictionary] = []


## Give synthetic cases stable caller-owned identities. Explicit-identity cases
## pass their own values through this helper. The producer API itself still
## requires the primary car and event IDs from the caller.
func _produce(
	result, config,
	primary_id := WallImpactLabChecks.PRIMARY_CAR_ID,
	event_id := WallImpactLabChecks.EVENT_ID,
	contact_id := WallImpactLabChecks.CONTACT_ID,
	tick_index := WallImpactLabChecks.TICK_INDEX
) -> WallImpactProducer.BuildOutcome:
	return ProducerScript.produce(
		result, config, primary_id, event_id, contact_id, tick_index
	)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func _run() -> void:
	for case_id in CASE_IDS:
		_results.append(_run_case(case_id))
	_results.append(await _case_real_jolt_wall_integration())
	_results.append(await _case_real_jolt_steering_corner())
	_results.append(await _case_real_jolt_nonzero_heading_corner())
	_results.append(await _case_real_jolt_narrow_wall_end())
	for case_result in _results:
		print("WALL_IMPACT_LAB_RESULT ", JSON.stringify(case_result))

	var total_checks := 0
	var total_failures := 0
	var failed_cases := 0
	var jolt_cases_passed := 0
	for result in _results:
		total_checks += int(result["checks"])
		total_failures += int(result["checks_failed"])
		if not bool(result["pass"]):
			failed_cases += 1
		var case_name := String(result["case"])
		if (case_name == JOLT_CASE_ID or case_name == STEERING_JOLT_CASE_ID \
				or case_name == NONZERO_HEADING_JOLT_CASE_ID \
				or case_name == NARROW_WALL_END_JOLT_CASE_ID) \
				and bool(result["pass"]):
			jolt_cases_passed += 1
	var summary := {
		"schema": "roadstorm.wall_impact_lab.summary.v1",
		"cases": _results.size(),
		"checks": total_checks,
		"checks_failed": total_failures,
		"failed_cases": failed_cases,
		"pass": failed_cases == 0,
		# Synthetic witnesses prove the producer contract. The pinned-Jolt
		# cases prove real witness paths, not general physical authority.
		"witness_sources": ["synthetic", "pinned_jolt"] \
			if jolt_cases_passed > 0 else ["synthetic"],
		"physical_authority_verified": false,
		"full_m1_8_acceptance": false,
		"m1_acceptance": false,
	}
	print("WALL_IMPACT_LAB_SUMMARY ", JSON.stringify(summary))
	print("CHECKS_TOTAL=", total_checks, " CHECKS_FAILED=", total_failures)
	get_tree().quit(0 if failed_cases == 0 else 1)


func _run_case(case_id: String) -> Dictionary:
	d = ChecksScript.new()
	measurements = {}
	match case_id:
		"four_regions_and_corner_ties":
			_case_four_regions_and_corner_ties()
		"head_on_and_oblique_severity":
			_case_head_on_and_oblique_severity()
		"tilted_normal_road_plane_projection":
			_case_tilted_normal_road_plane_projection()
		"zero_imparted_motion_is_explicit":
			_case_zero_imparted_motion()
		"witness_refusals_fail_closed":
			_case_witness_refusals()
		"ledger_publication_duplicate_conflict":
			_case_ledger_publication()
		"input_and_result_nonmutation":
			_case_input_and_result_nonmutation()
		"producer_source_contract":
			_case_producer_source_contract()
		"corner_near_tie_response_normal":
			_case_corner_near_tie_response_normal()
		"post_velocity_canonical_agreement":
			_case_post_velocity_canonical_agreement()
		"collision_time_frame_discrimination":
			_case_collision_time_frame_discrimination()
		_:
			d.check(false, "unknown case %s" % case_id)
	return {
		"case": case_id,
		"pass": d.failures.is_empty(),
		"checks": d.checks,
		"checks_failed": d.failures.size(),
		"failures": d.failures.duplicate(),
		"measurements": measurements.duplicate(),
	}


# --- Cases ----------------------------------------------------------------


func _case_four_regions_and_corner_ties() -> void:
	# Region uses the local point expressed in the collision-time frame. Face
	# centres cover all four regions; normalized half-extents make the long
	# hull's longitudinal faces win over an absolute-coordinate comparison.
	var config := d.make_config()
	var half := WallImpactLabChecks.HALF_EXTENTS_M
	var faces := {
		"front": Vector3(0.0, 0.0, -half.z),
		"rear": Vector3(0.0, 0.0, half.z),
		"left": Vector3(-half.x, 0.0, 0.0),
		"right": Vector3(half.x, 0.0, 0.0),
	}
	var expected := {
		"front": ImpactEvent.ContactRegion.FRONT,
		"rear": ImpactEvent.ContactRegion.REAR,
		"left": ImpactEvent.ContactRegion.LEFT,
		"right": ImpactEvent.ContactRegion.RIGHT,
	}
	var names := {
		"front": "front",
		"rear": "rear",
		"left": "left",
		"right": "right",
	}
	for label in faces:
		var result := d.make_result(faces[label])
		var outcome := _produce(
			result, config, WallImpactLabChecks.PRIMARY_CAR_ID,
			WallImpactLabChecks.EVENT_ID, WallImpactLabChecks.CONTACT_ID,
			WallImpactLabChecks.TICK_INDEX
		)
		d.check(outcome.is_ok(), "region.%s.published" % label)
		if not outcome.is_ok():
			continue
		var event := outcome.event
		d.check(event.region == expected[label], "region.%s.region" % label)
		d.check_string(event.region_name(), names[label], "region.%s.name" % label)
		d.check_vector_close(
			event.contact_point_local_m, faces[label],
			WallImpactLabChecks.VECTOR_TOLERANCE, "region.%s.local_point" % label
		)
		d.check_vector_close(
			event.contact_point_world_m, result.wall_contact_transform * faces[label],
			WallImpactLabChecks.VECTOR_TOLERANCE, "region.%s.world_point" % label
		)
		d.check_exact_float(event.severity_m_s, 20.0, "region.%s.severity" % label)
		d.check(
			event.imparted_motion_m == Vector3.ZERO, "region.%s.zero_motion" % label
		)

	# Axis normalization: a point closer to the side face in metres can still be
	# a front contact because the hull is much longer than it is wide, and the
	# reverse comparison makes it a right contact.
	var normalized_cases := {
		"longitudinal_wins": {
			"point": Vector3(0.45, 0.0, -half.z),
			"region": ImpactEvent.ContactRegion.FRONT,
		},
		"lateral_wins": {
			"point": Vector3(half.x, 0.0, -0.5 * half.z),
			"region": ImpactEvent.ContactRegion.RIGHT,
		},
	}
	for label in normalized_cases:
		var point: Vector3 = normalized_cases[label]["point"]
		var outcome := _produce(d.make_result(point), config)
		d.check(outcome.is_ok(), "region.%s.published" % label)
		if outcome.is_ok():
			d.check(
				outcome.event.region == normalized_cases[label]["region"],
				"region.%s.classified_by_normalized_half_extents" % label
			)

	# Exact corner ties are deterministic: normalized lateral equals normalized
	# longitudinal. Each fixture supplies the response normal that faces that
	# hull region, so the tie resolves by the physical response direction.
	var corner_cases := {
		"front_right": {
			"point": Vector3(half.x, 0.0, -half.z),
			"region": ImpactEvent.ContactRegion.FRONT,
			"normal": Vector3(0.0, 0.0, 1.0),
			"pre": Vector3(0.0, 0.0, -20.0),
		},
		"front_left": {
			"point": Vector3(-half.x, 0.0, -half.z),
			"region": ImpactEvent.ContactRegion.FRONT,
			"normal": Vector3(0.0, 0.0, 1.0),
			"pre": Vector3(0.0, 0.0, -20.0),
		},
		"rear_right": {
			"point": Vector3(half.x, 0.0, half.z),
			"region": ImpactEvent.ContactRegion.REAR,
			"normal": Vector3(0.0, 0.0, -1.0),
			"pre": Vector3(0.0, 0.0, 20.0),
		},
		"rear_left": {
			"point": Vector3(-half.x, 0.0, half.z),
			"region": ImpactEvent.ContactRegion.REAR,
			"normal": Vector3(0.0, 0.0, -1.0),
			"pre": Vector3(0.0, 0.0, 20.0),
		},
	}
	for label in corner_cases:
		var point: Vector3 = corner_cases[label]["point"]
		var normal: Vector3 = corner_cases[label]["normal"]
		var pre: Vector3 = corner_cases[label]["pre"]
		var witness := d.make_witness(point, pre, Vector3.ZERO, normal)
		var first := _produce(witness, config)
		var second := _produce(d.make_witness(point, pre, Vector3.ZERO, normal), config)
		d.check(first.is_ok() and second.is_ok(), "corner.%s.published_twice" % label)
		if first.is_ok() and second.is_ok():
			d.check(
				first.event.region == corner_cases[label]["region"],
				"corner.%s.tie_is_front_or_rear" % label
			)
			d.check(
				first.event.region == second.event.region,
				"corner.%s.deterministic" % label
			)

	# A rotated collision-time frame must produce the same local point and
	# therefore the same region as the unrotated fixture.
	var heading := 0.3
	var origin := Vector3(2.0, 0.5, -18.0)
	var rotated_outcome := _produce(
		d.make_result(
			Vector3(0.0, 0.0, -half.z),
			WallImpactLabChecks.HULL_SIZE_M,
			heading,
			origin
		),
		config
	)
	d.check(rotated_outcome.is_ok(), "region.rotated_frame.published")
	if rotated_outcome.is_ok():
		d.check_vector_close(
			rotated_outcome.event.contact_point_local_m,
			Vector3(0.0, 0.0, -half.z),
			# Godot's Vector3 uses float32 here; inversion after an 18 m
			# translation measured a 2e-6 m round-trip error on the pin.
			5e-6,
			"region.rotated_frame.local_recovered"
		)
		d.check(
			rotated_outcome.event.region == ImpactEvent.ContactRegion.FRONT,
			"region.rotated_frame.front"
		)

	measurements["regions_checked"] = faces.size() + normalized_cases.size() \
		+ corner_cases.size()


func _case_head_on_and_oblique_severity() -> void:
	var config := d.make_config()

	# Head-on: the whole approach speed is the contact change.
	var head_on := _produce(
		d.make_witness(
			Vector3(0.0, 0.0, -WallImpactLabChecks.HALF_EXTENTS_M.z),
			Vector3(0.0, 0.0, -20.0), Vector3.ZERO, Vector3(0.0, 0.0, 1.0)
		),
		config
	)
	d.check(head_on.is_ok(), "severity.head_on.published")
	if head_on.is_ok():
		d.check_exact_float(head_on.event.severity_m_s, 20.0, "severity.head_on.value")
		d.check(
			head_on.event.post_contact_velocity_world_m_s == Vector3.ZERO,
			"severity.head_on.post_is_witness"
		)
		d.check(
			head_on.event.severity_m_s != head_on.event.imparted_motion_magnitude_m(),
			"severity.head_on.not_motion_magnitude"
		)

	# Oblique: only the inward normal component changes, tangent survives.
	var normal := Vector3(0.5, 0.0, 0.8660254037844386)
	var pre := Vector3(0.0, 0.0, -20.0)
	var inward := pre.dot(normal)
	var oblique_post := pre - normal * inward
	var oblique := _produce(
		d.make_witness(
			Vector3(0.0, 0.0, -WallImpactLabChecks.HALF_EXTENTS_M.z),
			pre, oblique_post, normal
		),
		config
	)
	d.check(oblique.is_ok(), "severity.oblique.published")
	if oblique.is_ok():
		d.check_close(
			oblique.event.severity_m_s, absf(inward),
			WallImpactLabChecks.NORM_TOLERANCE, "severity.oblique.inward_component"
		)
		d.check_close(
			oblique.event.post_contact_velocity_world_m_s.distance_to(oblique_post),
			0.0, WallImpactLabChecks.VECTOR_TOLERANCE,
			"severity.oblique.post_is_witness"
		)
		d.check_close(
			oblique.event.post_contact_velocity_world_m_s.dot(normal), 0.0,
			WallImpactLabChecks.NORM_TOLERANCE,
			"severity.oblique.no_inward_component_remains"
		)
		var expected_change := pre - oblique_post
		d.check_close(
			oblique.event.severity_m_s,
			ImpactEvent.stable_norm(expected_change),
			WallImpactLabChecks.NORM_TOLERANCE,
			"severity.oblique.stable_norm_wiring"
		)
		measurements["oblique_severity_m_s"] = oblique.event.severity_m_s
		measurements["oblique_tangent_kept"] = (
			oblique.event.post_contact_velocity_world_m_s.length()
		)

	# A large finite pre/post difference must stay finite through the scaled
	# norm instead of overflowing to INF.
	var large := _produce(
		d.make_witness(
			Vector3(0.0, 0.0, -WallImpactLabChecks.HALF_EXTENTS_M.z),
			Vector3(3.0e38, 0.0, 0.0), Vector3.ZERO, Vector3(1.0, 0.0, 0.0)
		),
		config
	)
	d.check(large.is_ok(), "severity.large_finite.published")
	if large.is_ok():
		d.check(
			is_finite(large.event.severity_m_s),
			"severity.large_finite.stays_finite"
		)
		d.check_close(
			large.event.severity_m_s, 3.0e38, 1.0e30,
			"severity.large_finite.magnitude"
		)


func _case_tilted_normal_road_plane_projection() -> void:
	var config := d.make_config()
	# Unit raw normal with a vertical tilt; only its road-plane projection may
	# be published, normalized to unit length.
	var raw_normal := Vector3(0.5, 0.5, 0.7071067811865476)
	var projected := Vector3(raw_normal.x, 0.0, raw_normal.z)
	var unit_normal := projected.normalized()
	var pre := Vector3(0.0, 0.0, -20.0)
	var inward := pre.dot(unit_normal)
	var post := pre - unit_normal * inward
	var result := d.make_witness(
		Vector3(0.0, 0.0, -WallImpactLabChecks.HALF_EXTENTS_M.z),
		pre, post, raw_normal
	)
	# The generic first-contact normal is deliberately different; the producer
	# must ignore it and use the authoritative wall normal.
	result.contact_normal = Vector3(1.0, 0.0, 0.0)
	var outcome := _produce(result, config)
	d.check(outcome.is_ok(), "tilt.published")
	if outcome.is_ok():
		d.check_vector_close(
			outcome.event.contact_normal_world_m, unit_normal,
			WallImpactLabChecks.VECTOR_TOLERANCE, "tilt.projected_unit_normal"
		)
		d.check_exact_float(outcome.event.contact_normal_world_m.y, 0.0, "tilt.vertical_removed")
		d.check(
			outcome.event.contact_normal_world_m.distance_to(raw_normal) > 0.01,
			"tilt.raw_normal_not_published"
		)
		d.check_close(
			outcome.event.severity_m_s, absf(inward),
			WallImpactLabChecks.NORM_TOLERANCE, "tilt.severity_uses_projected_normal"
		)

	# A non-unit raw normal must normalize to the same direction.
	var scaled_raw := raw_normal * 3.0
	var scaled_outcome := _produce(
		d.make_witness(
			Vector3(0.0, 0.0, -WallImpactLabChecks.HALF_EXTENTS_M.z),
			pre, post, scaled_raw
		),
		config
	)
	d.check(scaled_outcome.is_ok(), "tilt.non_unit.published")
	if scaled_outcome.is_ok():
		d.check_vector_close(
			scaled_outcome.event.contact_normal_world_m, unit_normal,
			WallImpactLabChecks.VECTOR_TOLERANCE, "tilt.non_unit_same_direction"
		)
		measurements["tilt_projected_normal"] = outcome.event.contact_normal_world_m


func _case_zero_imparted_motion() -> void:
	var config := d.make_config()
	var accepted_motions := [
		Vector3(0.25, 0.0, 0.1),
		Vector3(1.0e6, 0.0, -2.0e6),
		Vector3(0.0, 0.0, 0.0),
	]
	for index in range(accepted_motions.size()):
		var accepted: Vector3 = accepted_motions[index]
		var result := d.make_witness(
			Vector3(0.0, 0.0, -WallImpactLabChecks.HALF_EXTENTS_M.z),
			Vector3(0.0, 0.0, -20.0), Vector3.ZERO, Vector3(0.0, 0.0, 1.0),
			accepted
		)
		var outcome := _produce(result, config)
		d.check(outcome.is_ok(), "motion.case_%d.published" % index)
		if not outcome.is_ok():
			continue
		d.check(
			outcome.event.imparted_motion_m == Vector3.ZERO,
			"motion.case_%d.exactly_zero" % index
		)
		d.check_exact_float(
			outcome.event.imparted_motion_magnitude_m(), 0.0,
			"motion.case_%d.zero_magnitude" % index
		)
		if accepted != Vector3.ZERO:
			d.check(
				outcome.event.imparted_motion_m != accepted,
				"motion.case_%d.total_travel_not_substituted" % index
			)
		# The total travel stays on the result, untouched.
		d.check(
			result.accepted_motion_m == accepted,
			"motion.case_%d.result_travel_untouched" % index
		)


func _case_witness_refusals() -> void:
	var config := d.make_config()
	var base := d.make_result()

	# Null and config failures.
	_expect_refusal(null, config, "null_result", "null adapter result")
	_expect_refusal(base, null, "null_config", "null motor-body config")
	var invalid_config := d.make_config()
	invalid_config.max_substeps = 0
	_expect_refusal(
		base, invalid_config, "invalid_config", "invalid motor-body config"
	)
	_expect_refusal(
		base, config, "empty_primary", "empty primary car id", ""
	)
	_expect_refusal(
		base, config, "empty_event", "empty event id",
		WallImpactLabChecks.PRIMARY_CAR_ID, ""
	)
	_expect_refusal(
		base, config, "negative_tick", "negative tick index",
		WallImpactLabChecks.PRIMARY_CAR_ID, WallImpactLabChecks.EVENT_ID, -1
	)

	# Status and witness flags.
	var statuses := {
		"refused_motion_bound": MotorBodyAdapter.Status.REFUSED_MOTION_BOUND,
		"rejected_invalid_input": MotorBodyAdapter.Status.REJECTED_INVALID_INPUT,
	}
	for status_label in statuses:
		var result := d.make_result()
		result.status = statuses[status_label]
		result.rejection_reason = "synthetic " + status_label
		_expect_refusal(
			result, config, "status_" + status_label, "not COMMITTED"
		)
	var no_response := d.make_result()
	no_response.has_wall_response_witness = false
	_expect_refusal(
		no_response, config, "no_response_witness", "missing wall response witness"
	)
	var no_point := d.make_result()
	no_point.has_wall_contact_point = false
	_expect_refusal(
		no_point, config, "no_point_witness", "missing wall contact point witness"
	)

	# Committed-state failures.
	var no_state := d.make_result()
	no_state.committed_state = null
	_expect_refusal(
		no_state, config, "null_committed_state", "missing committed state"
	)
	var nonfinite_state := d.make_result()
	nonfinite_state.committed_state.position_m = Vector2(NAN, 0.0)
	_expect_refusal(
		nonfinite_state, config, "nonfinite_committed_state",
		"nonfinite committed state"
	)

	# Velocity failures.
	var nan_pre := d.make_result()
	nan_pre.wall_pre_response_velocity_world_m_s = Vector3(NAN, 0.0, 0.0)
	_expect_refusal(nan_pre, config, "nan_pre", "nonfinite pre-response velocity")
	var inf_post := d.make_result()
	inf_post.wall_post_response_velocity_world_m_s = Vector3(INF, 0.0, 0.0)
	_expect_refusal(
		inf_post, config, "infinite_post", "nonfinite post-response velocity"
	)
	var inconsistent := d.make_witness(
		Vector3(0.0, 0.0, -WallImpactLabChecks.HALF_EXTENTS_M.z),
		Vector3(0.0, 0.0, -20.0), Vector3.ZERO, Vector3(0.0, 0.0, 1.0)
	)
	inconsistent.committed_state.velocity_m_s = Vector2(9.0, 9.0)
	_expect_refusal(
		inconsistent, config, "inconsistent_post", "disagrees with committed state"
	)

	# Normal/point/frame failures.
	var vertical_normal := d.make_witness(
		Vector3(0.0, 0.0, -WallImpactLabChecks.HALF_EXTENTS_M.z),
		Vector3(0.0, 0.0, -20.0), Vector3.ZERO, Vector3(0.0, 1.0, 0.0)
	)
	_expect_refusal(
		vertical_normal, config, "degenerate_normal", "degenerate wall contact normal"
	)
	var nan_normal := d.make_result()
	nan_normal.wall_contact_normal = Vector3(NAN, 0.0, 0.0)
	_expect_refusal(nan_normal, config, "nan_normal", "nonfinite wall contact normal")
	var nan_point := d.make_result()
	nan_point.wall_contact_point = Vector3(NAN, 0.0, 0.0)
	_expect_refusal(nan_point, config, "nan_point", "nonfinite wall contact point")
	var nan_frame := d.make_result()
	nan_frame.wall_contact_transform.origin = Vector3(NAN, 0.0, 0.0)
	_expect_refusal(
		nan_frame, config, "nan_frame",
		"nonfinite or degenerate wall contact transform"
	)
	var degenerate_frame := d.make_result()
	degenerate_frame.wall_contact_transform = Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO)
	_expect_refusal(
		degenerate_frame, config, "degenerate_frame",
		"nonfinite or degenerate wall contact transform"
	)
	var huge_frame := d.make_result()
	huge_frame.wall_contact_transform = Transform3D(
		AdapterScript.basis_from_heading(0.0), Vector3(3.0e38, 0.0, 0.0)
	)
	huge_frame.wall_contact_point = Vector3(-3.0e38, 0.0, 0.0)
	_expect_refusal(
		huge_frame, config, "nonfinite_local", "nonfinite local contact point"
	)

	# Severity failure: a finite pre/post pair whose difference overflows.
	var overflow := d.make_witness(
		Vector3(0.0, 0.0, -WallImpactLabChecks.HALF_EXTENTS_M.z),
		Vector3(3.0e38, 0.0, 0.0), Vector3(-3.0e38, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0)
	)
	_expect_refusal(overflow, config, "nonfinite_severity", "nonfinite severity")

	# None of the refusals may create or mutate a ledger. The ledger stays
	# empty and its counters stay at zero until an explicit publish attempt.
	var ledger := ImpactEvent.Ledger.new()
	var empty_digest := ledger.content_digest()
	d.check(ledger.event_count() == 0, "refusal.ledger_empty")
	d.check(empty_digest.is_empty(), "refusal.empty_digest")
	var null_outcome := WallImpactProducer.publish(null, ledger)
	d.check(null_outcome.is_refused(), "refusal.publish_null_refused")
	d.check(ledger.published_count == 0, "refusal.nothing_published")
	d.check(ledger.coalesced_count == 0, "refusal.nothing_coalesced")
	d.check(ledger.conflict_count == 0, "refusal.nothing_conflicted")
	d.check(
		ledger.content_digest() == empty_digest, "refusal.digest_unchanged_by_refusal"
	)
	measurements["refusal_probes"] = 22


func _expect_refusal(
	result,
	config,
	label: String,
	fragment := "",
	primary_id := WallImpactLabChecks.PRIMARY_CAR_ID,
	event_id := WallImpactLabChecks.EVENT_ID,
	tick_index := WallImpactLabChecks.TICK_INDEX
) -> void:
	var outcome := _produce(
		result, config, primary_id, event_id, "", tick_index
	)
	d.check(outcome.is_refused(), "refusal.%s.refused" % label)
	d.check(outcome.event == null, "refusal.%s.no_event" % label)
	d.check(not outcome.reason.is_empty(), "refusal.%s.reason_present" % label)
	if not fragment.is_empty():
		d.check_reason_contains(
			outcome.reason, fragment, "refusal.%s.reason_names_cause" % label
		)


func _case_ledger_publication() -> void:
	var config := d.make_config()
	var ledger := ImpactEvent.Ledger.new()

	var first := _produce(
		d.make_result(), config, WallImpactLabChecks.PRIMARY_CAR_ID,
		WallImpactLabChecks.EVENT_ID, WallImpactLabChecks.CONTACT_ID,
		WallImpactLabChecks.TICK_INDEX
	)
	d.check(first.is_ok(), "ledger.first.built")
	if not first.is_ok():
		return
	# Caller-assigned identity and wall semantics survive publication.
	var event := first.event
	d.check_string(event.event_id, WallImpactLabChecks.EVENT_ID, "ledger.first.event_id")
	d.check(event.tick_index == WallImpactLabChecks.TICK_INDEX, "ledger.first.tick_index")
	d.check_string(
		event.primary_car_id, WallImpactLabChecks.PRIMARY_CAR_ID, "ledger.first.primary"
	)
	d.check_string(event.contact_id, WallImpactLabChecks.CONTACT_ID, "ledger.first.contact_id")
	d.check(not event.has_other_car(), "ledger.first.wall_has_no_other_car")

	var outcome := WallImpactProducer.publish(event, ledger)
	d.check(outcome.is_published(), "ledger.first.published")
	d.check(ledger.event_count() == 1, "ledger.first.event_count")
	d.check(not ledger.content_digest().is_empty(), "ledger.first.digest_nonempty")
	var retained := ledger.find_by_id(WallImpactLabChecks.EVENT_ID)
	d.check(retained != null, "ledger.first.retained")
	if retained != null:
		d.check(retained.same_payload(event), "ledger.first.payload_round_trip")

	# Identical retry under the same ID coalesces.
	var retry := _produce(
		d.make_result(), config, WallImpactLabChecks.PRIMARY_CAR_ID,
		WallImpactLabChecks.EVENT_ID, WallImpactLabChecks.CONTACT_ID,
		WallImpactLabChecks.TICK_INDEX
	)
	var retry_outcome := WallImpactProducer.publish(retry.event, ledger)
	d.check(retry_outcome.is_coalesced(), "ledger.retry.coalesced")
	d.check(ledger.coalesced_count == 1, "ledger.retry.coalesced_count")
	d.check(ledger.event_count() == 1, "ledger.retry.count_stable")
	d.check(ledger.conflict_count == 0, "ledger.retry.no_conflict")

	# A conflicting payload under the retained ID refuses and leaves the
	# retained record untouched.
	var conflicting := _produce(
		d.make_witness(
			Vector3(0.0, 0.0, WallImpactLabChecks.HALF_EXTENTS_M.z),
			Vector3(0.0, 0.0, -7.0), Vector3.ZERO, Vector3(0.0, 0.0, 1.0)
		),
		config, WallImpactLabChecks.PRIMARY_CAR_ID,
		WallImpactLabChecks.EVENT_ID, WallImpactLabChecks.CONTACT_ID,
		WallImpactLabChecks.TICK_INDEX
	)
	var base_digest := ledger.content_digest()
	d.check(conflicting.is_ok(), "ledger.conflict.built")
	if conflicting.is_ok():
		var conflict_outcome := WallImpactProducer.publish(conflicting.event, ledger)
		d.check(conflict_outcome.is_refused(), "ledger.conflict.refused")
		d.check(
			conflict_outcome.reason.begins_with("conflicting payload"),
			"ledger.conflict.reason"
		)
		d.check(ledger.conflict_count == 1, "ledger.conflict.counted")
		d.check(ledger.event_count() == 1, "ledger.conflict.count_stable")
		d.check(
			ledger.content_digest() == base_digest,
			"ledger.conflict.retained_content_unchanged"
		)
		var still_first := ledger.find_by_id(WallImpactLabChecks.EVENT_ID)
		d.check(still_first != null, "ledger.conflict.first_still_retained")
		if still_first != null:
			d.check_exact_float(still_first.severity_m_s, 20.0, "ledger.conflict.first_payload_kept")

	# A cross-tick reuse of the same ID is also a conflict.
	var later := _produce(
		d.make_result(), config, WallImpactLabChecks.PRIMARY_CAR_ID,
		WallImpactLabChecks.EVENT_ID, WallImpactLabChecks.CONTACT_ID,
		WallImpactLabChecks.TICK_INDEX + 1
	)
	if later.is_ok():
		var later_outcome := WallImpactProducer.publish(later.event, ledger)
		d.check(later_outcome.is_refused(), "ledger.cross_tick.refused")
		d.check(ledger.conflict_count == 2, "ledger.cross_tick.counted")

	# Optional contact link: the ledger's duplicate-perspective rule applies to
	# linked records, so a new event ID for the same (contact, primary) pair is
	# refused while the retained record survives.
	var replay := _produce(
		d.make_result(), config, WallImpactLabChecks.PRIMARY_CAR_ID,
		WallImpactLabChecks.OTHER_EVENT_ID, WallImpactLabChecks.CONTACT_ID,
		WallImpactLabChecks.TICK_INDEX
	)
	if replay.is_ok():
		var replay_outcome := WallImpactProducer.publish(replay.event, ledger)
		d.check(replay_outcome.is_refused(), "ledger.dup_perspective.refused")
		d.check(
			replay_outcome.reason.begins_with("duplicate perspective"),
			"ledger.dup_perspective.reason"
		)
		d.check(ledger.event_count() == 1, "ledger.dup_perspective.count_stable")
		d.check(ledger.conflict_count == 2, "ledger.dup_perspective.not_an_id_conflict")

	# Unlinked wall records never enter the pair index; a different event ID for
	# the same primary publishes normally.
	var unlinked := _produce(
		d.make_result(), config, WallImpactLabChecks.PRIMARY_CAR_ID,
		WallImpactLabChecks.OTHER_EVENT_ID, "", WallImpactLabChecks.TICK_INDEX
	)
	if unlinked.is_ok():
		d.check(
			WallImpactProducer.publish(unlinked.event, ledger).is_published(),
			"ledger.unlinked.published"
		)
		d.check(ledger.event_count() == 2, "ledger.unlinked.count")

	# A null ledger refuses locally rather than crashing.
	var null_ledger_outcome := WallImpactProducer.publish(event, null)
	d.check(null_ledger_outcome.is_refused(), "ledger.null_ledger.refused")
	d.check_string(null_ledger_outcome.reason, "null ledger", "ledger.null_ledger.reason")


func _case_input_and_result_nonmutation() -> void:
	var config := d.make_config()
	var result := d.make_result(
		Vector3(0.0, 0.0, -WallImpactLabChecks.HALF_EXTENTS_M.z),
		WallImpactLabChecks.HULL_SIZE_M, 0.2, Vector3(1.0, 0.5, -18.0),
		Vector3(0.0, 0.0, -20.0), Vector3.ZERO, Vector3(0.0, 0.0, 1.0),
		Vector3(0.25, 0.0, 0.1)
	)
	var result_snapshot := d.snapshot_result(result)
	var config_snapshot := d.snapshot_config(config)
	var committed_reference = result.committed_state

	var first := _produce(result, config)
	var second := _produce(result, config)
	d.check(first.is_ok() and second.is_ok(), "nonmutation.both_built")
	d.check(
		d.snapshot_result(result) == result_snapshot,
		"nonmutation.result_byte_identical"
	)
	d.check(
		d.snapshot_config(config) == config_snapshot,
		"nonmutation.config_identical"
	)
	d.check(
		result.committed_state == committed_reference,
		"nonmutation.committed_state_identity_kept"
	)
	if first.is_ok() and second.is_ok():
		d.check(
			first.event.same_payload(second.event),
			"nonmutation.repeat_identical_event"
		)

	# Producing builds no ledger and touches none.
	var ledger := ImpactEvent.Ledger.new()
	d.check(ledger.event_count() == 0, "nonmutation.no_implicit_ledger")
	d.check(ledger.content_digest().is_empty(), "nonmutation.empty_digest")



func _case_producer_source_contract() -> void:
	var path := "res://src/simulation/wall_impact_producer.gd"
	var source := _read_source(path)
	d.check(not source.is_empty(), "source.readable")
	if source.is_empty():
		return
	var executable := _strip_full_line_comments(source)
	# Severity is the stable norm of the witness difference, and the producer
	# performs no response physics of its own.
	d.check(
		executable.contains("ImpactEvent.stable_norm("),
		"source.uses_stable_norm"
	)
	d.check(
		not executable.contains("_apply_wall_response"),
		"source.no_duplicate_response_physics"
	)
	# Sweep travel is never substituted for contact-induced motion.
	d.check(
		not executable.contains("accepted_motion_m"),
		"source.never_reads_total_travel"
	)
	d.check(
		executable.contains("builder.imparted_motion_m = Vector3.ZERO"),
		"source.explicit_zero_imparted_motion"
	)
	# Existing ImpactEvent validation and mapping helpers are reused.
	d.check(
		executable.contains("MotorBodyAdapter.road_vector_to_world"),
		"source.reuses_road_plane_mapping"
	)
	d.check(
		executable.contains("ImpactEvent.Builder.new()"),
		"source.builds_via_builder"
	)
	d.check(
		executable.contains("affine_inverse()"),
		"source.uses_collision_time_frame_inverse"
	)
	d.check(
		executable.contains("has_wall_response_witness")
		and executable.contains("has_wall_contact_point"),
		"source.gates_on_both_witness_flags"
	)
	# No duplicate hashing surface.
	d.check(
		not executable.contains("encode_for_digest")
		and not executable.contains("content_digest"),
		"source.no_duplicate_hashing"
	)
	d.check(
		not executable.contains("Ledger.new"),
		"source.builds_no_ledger"
	)


func _case_corner_near_tie_response_normal() -> void:
	# Pinned probe geometry: a hull-vertex contact whose normalized lateral
	# distance exceeds the longitudinal one by 1.75e-3, inside the documented
	# near-tie band but on the side-face side of the point-only comparison.
	var config := d.make_config()
	var half := WallImpactLabChecks.HALF_EXTENTS_M
	var corner_point := Vector3(-0.897592, 0.0, -1.891584)
	var nose_normal := Vector3(0.298703, 0.0, 0.954346)
	var rear_normal := Vector3(nose_normal.x, 0.0, -nose_normal.z)

	var front_cases := {
		"front_left": {"point": corner_point, "normal": nose_normal},
		"front_right": {
			"point": Vector3(-corner_point.x, corner_point.y, corner_point.z),
			"normal": Vector3(-nose_normal.x, nose_normal.y, nose_normal.z),
		},
	}
	for label in front_cases:
		var point: Vector3 = front_cases[label]["point"]
		var normal: Vector3 = front_cases[label]["normal"]
		var result := d.make_witness(
			point, -normal * 20.0, Vector3.ZERO, normal
		)
		var outcome := _produce(result, config)
		d.check(outcome.is_ok(), "near_tie.%s.published" % label)
		if not outcome.is_ok():
			continue
		var baseline_region := _baseline_point_only_region(
			point, config.hull_size_m
		)
		d.check(
			baseline_region == ImpactEvent.ContactRegion.LEFT
				or baseline_region == ImpactEvent.ContactRegion.RIGHT,
			"near_tie.%s.baseline_rule_names_side" % label
		)
		d.check(
			outcome.event.region == ImpactEvent.ContactRegion.FRONT,
			"near_tie.%s.response_normal_resolves_front" % label
		)
		var local_normal := _local_response_normal(result)
		d.check(
			absf(local_normal.z) > absf(local_normal.x),
			"near_tie.%s.local_normal_is_nose_facing" % label
		)
		d.check_vector_close(
			outcome.event.contact_point_local_m, point,
			WallImpactLabChecks.VECTOR_TOLERANCE,
			"near_tie.%s.local_point_preserved" % label
		)
		measurements["near_tie_%s_baseline" % label] = (
			ImpactEvent.REGION_NAMES[baseline_region]
		)

	var rear_cases := {
		"rear_left": {
			"point": Vector3(corner_point.x, corner_point.y, -corner_point.z),
			"normal": rear_normal,
		},
		"rear_right": {
			"point": Vector3(-corner_point.x, corner_point.y, -corner_point.z),
			"normal": Vector3(-rear_normal.x, rear_normal.y, rear_normal.z),
		},
	}
	for label in rear_cases:
		var point: Vector3 = rear_cases[label]["point"]
		var normal: Vector3 = rear_cases[label]["normal"]
		var result := d.make_witness(
			point, -normal * 20.0, Vector3.ZERO, normal
		)
		var outcome := _produce(result, config)
		d.check(outcome.is_ok(), "near_tie.%s.published" % label)
		if outcome.is_ok():
			d.check(
				_baseline_point_only_region(point, config.hull_size_m)
					!= ImpactEvent.ContactRegion.REAR,
				"near_tie.%s.baseline_rule_disagrees" % label
			)
			d.check(
				outcome.event.region == ImpactEvent.ContactRegion.REAR,
				"near_tie.%s.rearward_normal_resolves_rear" % label
			)

	# A side-facing response normal names the side face even when the point
	# sits marginally on the front side of the tie band.
	var side_normal := Vector3(-0.954346, 0.0, 0.298703)
	var side_override := d.make_witness(
		Vector3(0.895, 0.0, -1.899),
		-side_normal * 20.0, Vector3.ZERO, side_normal
	)
	var side_outcome := _produce(side_override, config)
	d.check(side_outcome.is_ok(), "near_tie.side_override.published")
	if side_outcome.is_ok():
		d.check(
			_baseline_point_only_region(
				side_override.wall_contact_transform.affine_inverse()
					* side_override.wall_contact_point,
				config.hull_size_m
			) == ImpactEvent.ContactRegion.FRONT,
			"near_tie.side_override.baseline_says_front"
		)
		d.check(
			side_outcome.event.region == ImpactEvent.ContactRegion.RIGHT,
			"near_tie.side_override.rightward_normal_resolves_right"
		)

	# The metre corner band covers the larger inset measured on pinned Jolt
	# even when the old normalized near-tie difference is outside 0.01.
	var wide_point := Vector3(-0.889209, 0.0, -1.896407)
	var wide_normal := Vector3(0.934434, 0.0, 0.356136)
	var wide := d.make_witness(
		wide_point, -wide_normal * 20.0, Vector3.ZERO, wide_normal
	)
	var wide_outcome := _produce(wide, config)
	d.check(wide_outcome.is_ok(), "near_tie.wide_solver_inset.published")
	if wide_outcome.is_ok():
		var wide_lateral := absf(wide_point.x) / half.x
		var wide_longitudinal := absf(wide_point.z) / half.z
		d.check(
			absf(wide_lateral - wide_longitudinal)
				> OLD_NORMALIZED_REGION_TIE_MARGIN,
			"near_tie.wide_solver_inset.outside_old_normalized_band"
		)
		d.check(
			half.x - absf(wide_point.x) <= LAB_REGION_CORNER_BAND_M
				and half.z - absf(wide_point.z) <= LAB_REGION_CORNER_BAND_M,
			"near_tie.wide_solver_inset.inside_metre_corner_band"
		)
		d.check(
			_baseline_point_only_region(wide_point, config.hull_size_m)
				== ImpactEvent.ContactRegion.FRONT,
			"near_tie.wide_solver_inset.baseline_says_front"
		)
		d.check(
			wide_outcome.event.region == ImpactEvent.ContactRegion.LEFT,
			"near_tie.wide_solver_inset.consistent_normal_resolves_left"
		)

	# The narrow wall end measured by the independent pinned-Jolt probe was
	# still a side-face contact when its point sat 0.0288 m inside the nose
	# plane and 0.0160 m inside the side plane. Exercise that boundary in all
	# quadrants with a clearly dominant, sign-compatible side normal.
	var measured_side_inset_m := 0.0160
	var measured_end_inset_m := 0.0288
	var wall_end_normal := Vector3(0.914, 0.0, 0.406)
	var wall_end_cases := {
		"front_left": {
			"point": Vector3(
				-(half.x - measured_side_inset_m), 0.0,
				-(half.z - measured_end_inset_m)
			),
			"normal": wall_end_normal,
			"region": ImpactEvent.ContactRegion.LEFT,
		},
		"front_right": {
			"point": Vector3(
				half.x - measured_side_inset_m, 0.0,
				-(half.z - measured_end_inset_m)
			),
			"normal": Vector3(
				-wall_end_normal.x, wall_end_normal.y, wall_end_normal.z
			),
			"region": ImpactEvent.ContactRegion.RIGHT,
		},
		"rear_left": {
			"point": Vector3(
				-(half.x - measured_side_inset_m), 0.0,
				half.z - measured_end_inset_m
			),
			"normal": Vector3(
				wall_end_normal.x, wall_end_normal.y, -wall_end_normal.z
			),
			"region": ImpactEvent.ContactRegion.LEFT,
		},
		"rear_right": {
			"point": Vector3(
				half.x - measured_side_inset_m, 0.0,
				half.z - measured_end_inset_m
			),
			"normal": Vector3(
				-wall_end_normal.x, wall_end_normal.y, -wall_end_normal.z
			),
			"region": ImpactEvent.ContactRegion.RIGHT,
		},
	}
	for label in wall_end_cases:
		var point: Vector3 = wall_end_cases[label]["point"]
		var normal: Vector3 = wall_end_cases[label]["normal"]
		var outcome := _produce(
			d.make_witness(point, -normal * 20.0, Vector3.ZERO, normal),
			config
		)
		d.check(outcome.is_ok(), "near_tie.wall_end_%s.published" % label)
		if not outcome.is_ok():
			continue
		var side_inset := half.x - absf(point.x)
		var end_inset := half.z - absf(point.z)
		d.check_close(
			side_inset, measured_side_inset_m, 1e-7,
			"near_tie.wall_end_%s.side_inset" % label
		)
		d.check_close(
			end_inset, measured_end_inset_m, 1e-7,
			"near_tie.wall_end_%s.end_inset" % label
		)
		d.check(
			side_inset <= LAB_REGION_CORNER_BAND_M
				and end_inset <= LAB_REGION_CORNER_BAND_M,
			"near_tie.wall_end_%s.inside_measured_corner_band" % label
		)
		var baseline_region := _baseline_point_only_region(
			point, config.hull_size_m
		)
		d.check(
			baseline_region == ImpactEvent.ContactRegion.FRONT
				or baseline_region == ImpactEvent.ContactRegion.REAR,
			"near_tie.wall_end_%s.point_rule_names_end" % label
		)
		d.check(
			outcome.event.region == wall_end_cases[label]["region"],
			"near_tie.wall_end_%s.sign_compatible_normal_names_side" % label
		)

	# A malformed response normal must not publish the face opposite the
	# contacted quadrant. This exact corner falls back to the deterministic
	# point rule instead of accepting the side-inconsistent normal.
	var malformed_normal := Vector3(-0.954346, 0.0, 0.298703)
	var malformed := d.make_witness(
		Vector3(-half.x, 0.0, -half.z),
		-malformed_normal * 20.0, Vector3.ZERO, malformed_normal
	)
	var malformed_outcome := _produce(malformed, config)
	d.check(malformed_outcome.is_ok(), "near_tie.malformed_sign.published")
	if malformed_outcome.is_ok():
		d.check(
			malformed_outcome.event.region != ImpactEvent.ContactRegion.RIGHT,
			"near_tie.malformed_sign.does_not_publish_opposite_face"
		)
		d.check(
			malformed_outcome.event.region == ImpactEvent.ContactRegion.FRONT,
			"near_tie.malformed_sign.falls_back_to_point_rule"
		)

	# A diagonal normal within the axis margin identifies no face; the
	# deterministic point fallback applies instead.
	var diagonal_normal := Vector3(0.7071067811865476, 0.0, 0.7071067811865476)
	var diagonal := d.make_witness(
		corner_point, -diagonal_normal * 20.0, Vector3.ZERO, diagonal_normal
	)
	var diagonal_outcome := _produce(diagonal, config)
	d.check(diagonal_outcome.is_ok(), "near_tie.diagonal.published")
	if diagonal_outcome.is_ok():
		d.check(
			diagonal_outcome.event.region == _baseline_point_only_region(
				corner_point, config.hull_size_m
			),
			"near_tie.diagonal.falls_back_to_point_rule"
		)
		var diagonal_local := _local_response_normal(diagonal)
		d.check(
			absf(absf(diagonal_local.x) - absf(diagonal_local.z))
				<= LAB_REGION_NORMAL_AXIS_MARGIN,
			"near_tie.diagonal.normal_is_ambiguous"
		)

	# A near-diagonal normal just inside the declared axis margin is still
	# ambiguous. If the margin were ignored, its small X advantage would name
	# LEFT at this front-left wall-end point; the fallback must name FRONT.
	var near_diagonal_point := Vector3(
		-(half.x - measured_side_inset_m), 0.0,
		-(half.z - measured_end_inset_m)
	)
	var diagonal_component := 0.7071067811865476
	var near_diagonal_normal := Vector3(
		diagonal_component + 5.0e-4, 0.0, diagonal_component
	)
	var near_diagonal := d.make_witness(
		near_diagonal_point,
		-near_diagonal_normal * 20.0,
		Vector3.ZERO,
		near_diagonal_normal
	)
	var near_diagonal_outcome := _produce(near_diagonal, config)
	d.check(
		near_diagonal_outcome.is_ok(), "near_tie.near_diagonal_margin.published"
	)
	if near_diagonal_outcome.is_ok():
		var near_diagonal_local := _local_response_normal(near_diagonal)
		var axis_difference := absf(
			absf(near_diagonal_local.x) - absf(near_diagonal_local.z)
		)
		d.check(
			axis_difference > 0.0
				and axis_difference <= LAB_REGION_NORMAL_AXIS_MARGIN,
			"near_tie.near_diagonal_margin.normal_is_inside_margin"
		)
		d.check(
			_baseline_point_only_region(near_diagonal_point, config.hull_size_m)
				== ImpactEvent.ContactRegion.FRONT,
			"near_tie.near_diagonal_margin.point_rule_names_front"
		)
		d.check(
			near_diagonal_outcome.event.region == ImpactEvent.ContactRegion.FRONT,
			"near_tie.near_diagonal_margin.falls_back_to_point_rule"
		)

	# Outside the tie band the point alone classifies, whatever the normal.
	var unambiguous := {
		"front_face": {
			"point": Vector3(0.0, 0.0, -half.z),
			"region": ImpactEvent.ContactRegion.FRONT,
		},
		"left_face": {
			"point": Vector3(-half.x, 0.0, 0.0),
			"region": ImpactEvent.ContactRegion.LEFT,
		},
		"right_face": {
			"point": Vector3(half.x, 0.0, 0.0),
			"region": ImpactEvent.ContactRegion.RIGHT,
		},
	}
	for label in unambiguous:
		var point: Vector3 = unambiguous[label]["point"]
		var outcome := _produce(
			d.make_witness(
				point, Vector3(0.0, 0.0, -20.0), Vector3.ZERO,
				Vector3(0.0, 0.0, 1.0)
			),
			config
		)
		d.check(outcome.is_ok(), "near_tie.%s.published" % label)
		if outcome.is_ok():
			d.check(
				outcome.event.region == unambiguous[label]["region"],
				"near_tie.%s.point_classifies_outside_band" % label
			)

	# Just outside the chosen end-axis band the point rule still wins. This
	# point uses the measured side inset but sits 0.040 m inside the nose
	# plane; its clearly front-facing normal would win inside the band, so it
	# brackets the upper edge instead of allowing unconditional normal-first
	# classification or unbounded widening.
	var outside_end_inset_m := 0.040
	var outside_band_point := Vector3(
		-(half.x - measured_side_inset_m), 0.0,
		-(half.z - outside_end_inset_m)
	)
	var outside_band_normal := Vector3(0.2, 0.0, 0.98)
	var outside_band := d.make_witness(
		outside_band_point,
		-outside_band_normal * 20.0,
		Vector3.ZERO,
		outside_band_normal
	)
	var outside_band_outcome := _produce(outside_band, config)
	d.check(outside_band_outcome.is_ok(), "near_tie.outside_band.published")
	if outside_band_outcome.is_ok():
		d.check(
			half.x - absf(outside_band_point.x) <= LAB_REGION_CORNER_BAND_M
				and half.z - absf(outside_band_point.z)
					> LAB_REGION_CORNER_BAND_M,
			"near_tie.outside_band.only_one_axis_outside"
		)
		d.check(
			_baseline_point_only_region(outside_band_point, config.hull_size_m)
				== ImpactEvent.ContactRegion.LEFT,
			"near_tie.outside_band.point_rule_names_left"
		)
		d.check(
			outside_band_outcome.event.region == ImpactEvent.ContactRegion.LEFT,
			"near_tie.outside_band.point_rule_wins"
		)

	# The same near-tie must resolve through a rotated collision-time frame,
	# proving the normal is transformed by that frame rather than read in
	# world axes. At 1.2 rad the untransformed world normal is side-dominant,
	# so a world-axis implementation cannot accidentally pass this control.
	var heading := 1.2
	var frame_origin := Vector3(2.0, 0.5, -18.0)
	var frame := Transform3D(
		AdapterScript.basis_from_heading(heading), frame_origin
	)
	var world_normal := frame.basis * nose_normal
	var rotated := d.make_witness(
		corner_point, -world_normal * 20.0, Vector3.ZERO, world_normal
	)
	rotated.wall_contact_transform = frame
	rotated.wall_contact_point = frame * corner_point
	var rotated_outcome := _produce(rotated, config)
	d.check(rotated_outcome.is_ok(), "near_tie.rotated_frame.published")
	if rotated_outcome.is_ok():
		d.check_vector_close(
			rotated_outcome.event.contact_point_local_m, corner_point,
			5e-6, "near_tie.rotated_frame.local_recovered"
		)
		d.check(
			rotated_outcome.event.region == ImpactEvent.ContactRegion.FRONT,
			"near_tie.rotated_frame.front"
		)
		var rotated_local := _local_response_normal(rotated)
		d.check(
			absf(rotated_local.z) > absf(rotated_local.x),
			"near_tie.rotated_frame.local_normal_nose_facing"
		)
		var world_projected := _road_plane_unit_normal(world_normal)
		d.check(
			absf(world_projected.x)
				> absf(world_projected.z) + LAB_REGION_NORMAL_AXIS_MARGIN,
			"near_tie.rotated_frame.world_axes_would_name_side"
		)

	measurements["near_tie_cases"] = (
		front_cases.size() + rear_cases.size() + unambiguous.size()
		+ wall_end_cases.size() + 7
	)


func _case_post_velocity_canonical_agreement() -> void:
	var config := d.make_config()
	var point := Vector3(0.0, 0.0, -WallImpactLabChecks.HALF_EXTENTS_M.z)
	var pre := Vector3(0.0, 0.0, -20.0)
	var normal := Vector3(0.0, 0.0, 1.0)
	var snapshots: Array[Dictionary] = []

	# Bit-exact round trip between the witness post velocity and the committed
	# planar velocity mapping.
	var samples := [
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.0, 0.0, -20.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(-3.5, 0.0, 7.25),
	]
	for index in range(samples.size()):
		var round_trip := AdapterScript.road_vector_to_world(
			AdapterScript.world_vector_to_road(samples[index])
		)
		d.check(
			round_trip == samples[index],
			"post_velocity.round_trip_%d.bit_exact" % index
		)

	# Canonical agreement publishes; the event post is the committed mapped
	# vector and severity is measured against it.
	var canonical := d.make_witness(point, pre, Vector3.ZERO, normal)
	snapshots.append(d.snapshot_result(canonical))
	var canonical_outcome := _produce(canonical, config)
	d.check(canonical_outcome.is_ok(), "post_velocity.canonical.published")
	if canonical_outcome.is_ok():
		d.check(
			canonical_outcome.event.post_contact_velocity_world_m_s == Vector3.ZERO,
			"post_velocity.canonical.post_is_committed_zero"
		)
		d.check_exact_float(
			canonical_outcome.event.severity_m_s, 20.0,
			"post_velocity.canonical.severity"
		)
	d.check(
		d.snapshot_result(canonical) == snapshots[0],
		"post_velocity.canonical.input_unmutated"
	)

	var moving := d.make_witness(point, pre, Vector3(0.0, 0.0, -12.0), normal)
	snapshots.append(d.snapshot_result(moving))
	var moving_outcome := _produce(moving, config)
	d.check(moving_outcome.is_ok(), "post_velocity.moving.published")
	if moving_outcome.is_ok():
		d.check(
			moving_outcome.event.post_contact_velocity_world_m_s
				== Vector3(0.0, 0.0, -12.0),
			"post_velocity.moving.post_is_committed_mapped"
		)
		d.check_exact_float(
			moving_outcome.event.severity_m_s, 8.0,
			"post_velocity.moving.severity_uses_committed_vector"
		)
	d.check(
		d.snapshot_result(moving) == snapshots[1],
		"post_velocity.moving.input_unmutated"
	)

	# Every mismatch below is far smaller than a physical disagreement but is
	# not bit-equal, so it must fail closed. Each refusal also proves the input
	# is untouched.
	var mismatches := {
		"one_ulp_at_1": {
			"committed": Vector2(1.0, 0.0),
			"post": Vector3(_next_float32(1.0), 0.0, 0.0),
		},
		"one_ulp_at_20": {
			"committed": Vector2(0.0, 20.0),
			"post": Vector3(0.0, 0.0, -_next_float32(20.0)),
		},
		"small_1e_9": {
			"committed": Vector2(0.0, 0.0),
			"post": Vector3(1.0e-9, 0.0, 0.0),
		},
		"small_1e_7": {
			"committed": Vector2(0.0, 0.0),
			"post": Vector3(1.0e-7, 0.0, 0.0),
		},
		"small_1e_6": {
			"committed": Vector2(0.0, 0.0),
			"post": Vector3(1.0e-6, 0.0, 0.0),
		},
		"vertical_component": {
			"committed": Vector2(0.0, 0.0),
			"post": Vector3(0.0, 1.0e-3, 0.0),
		},
	}
	for label in mismatches:
		var committed: Vector2 = mismatches[label]["committed"]
		var post: Vector3 = mismatches[label]["post"]
		var witness := d.make_witness(point, pre, post, normal)
		witness.committed_state.velocity_m_s = committed
		var snapshot := d.snapshot_result(witness)
		var outcome := _produce(witness, config)
		d.check(outcome.is_refused(), "post_velocity.%s.refused" % label)
		d.check_reason_contains(
			outcome.reason, "post-response velocity disagrees",
			"post_velocity.%s.reason_names_cause" % label
		)
		d.check(outcome.event == null, "post_velocity.%s.no_event" % label)
		d.check(
			d.snapshot_result(witness) == snapshot,
		"post_velocity.%s.input_unmutated" % label
		)
		measurements["post_mismatch_" + label + "_reason"] = outcome.reason

	measurements["post_velocity_probes"] = 2 + mismatches.size()


func _case_collision_time_frame_discrimination() -> void:
	var config := d.make_config()
	var half := WallImpactLabChecks.HALF_EXTENTS_M
	# The collision-time pose and the finalized post-yaw pose differ in both
	# yaw and origin. The committed transform is the wrong-frame control.
	var collision_heading := 0.3
	var collision_origin := Vector3(2.0, 0.5, -18.0)
	var committed_heading := 0.75
	var committed_origin := Vector3(3.2, 0.5, -17.0)
	var collision_frame := Transform3D(
		AdapterScript.basis_from_heading(collision_heading), collision_origin
	)
	var committed_frame := Transform3D(
		AdapterScript.basis_from_heading(committed_heading), committed_origin
	)
	var local_point := Vector3(0.0, 0.0, -half.z)
	var world_point := collision_frame * local_point
	var raw_normal := collision_frame.basis * Vector3(0.0, 0.0, 1.0)
	var pre := -raw_normal.normalized() * 20.0
	var witness := d.make_witness(local_point, pre, Vector3.ZERO, raw_normal)
	witness.wall_contact_transform = collision_frame
	witness.wall_contact_point = world_point
	witness.committed_transform = committed_frame
	witness.committed_state.position_m = Vector2(
		committed_origin.x, -committed_origin.z
	)
	witness.committed_state.heading_rad = committed_heading
	var snapshot := d.snapshot_result(witness)
	var outcome := _produce(witness, config)
	d.check(outcome.is_ok(), "frame.published")
	if outcome.is_ok():
		var event := outcome.event
		d.check(
			event.contact_point_world_m == world_point,
			"frame.world_point_is_collision_frame_point"
		)
		d.check_vector_close(
			event.contact_point_local_m, local_point,
			# Engine Vector3 is float32; an affine inverse after an 18 m
			# translation measured a 2e-6 m round-trip error on the pin.
			5e-6,
			"frame.local_point_follows_collision_frame"
		)
		d.check(
			event.region == ImpactEvent.ContactRegion.FRONT,
			"frame.region_is_front_in_collision_frame"
		)
		d.check_vector_close(
			event.contact_normal_world_m, _road_plane_unit_normal(raw_normal),
			WallImpactLabChecks.VECTOR_TOLERANCE,
			"frame.normal_is_road_projection"
		)
		d.check(event.is_valid(), "frame.event_valid")
		var wrong_local: Vector3 = committed_frame.affine_inverse() * world_point
		d.check(
			wrong_local.distance_to(local_point) > 0.1,
			"frame.committed_pose_is_materially_different"
		)
		d.check(
			_baseline_point_only_region(wrong_local, config.hull_size_m)
				== ImpactEvent.ContactRegion.LEFT,
			"frame.wrong_frame_control_names_side"
		)
		d.check(
			committed_frame.origin.distance_to(collision_frame.origin) > 0.5
				and absf(committed_heading - collision_heading) > 0.1,
			"frame.fixtures_are_distinct"
		)
		measurements["frame_wrong_local"] = wrong_local
		measurements["frame_wrong_local_distance_m"] = (
			wrong_local.distance_to(local_point)
		)
	d.check(
		d.snapshot_result(witness) == snapshot,
		"frame.input_unmutated"
	)
	measurements["frame_yaw_delta_rad"] = absf(
		committed_heading - collision_heading
	)
	measurements["frame_origin_gap_m"] = committed_origin.distance_to(
		collision_origin
	)


func _case_real_jolt_wall_integration() -> Dictionary:
	d = ChecksScript.new()
	measurements = {}
	var config := d.make_config()
	var body_checks := BodyLabChecksScript.new()
	var tuning := body_checks.make_tuning()
	var idle := body_checks.make_idle_command()
	var wall_spec := {
		"point": Vector3(0.0, 2.0, STRAIGHT_WALL_Z),
		"yaw_deg": 0.0,
		"thickness_m": WALL_THICKNESS_M,
		"width_m": WALL_WIDTH_M,
	}
	var world: BodyLabWorld = WorldScript.build(get_tree().root, config, wall_spec)
	await _await_frames(SETTLE_FRAMES)

	var state := body_checks.make_state(Vector2.ZERO, Vector2(0.0, 30.0), 0.0)
	world.set_pose(state, BodyLabChecksScript.BODY_SUPPORT_Y)
	await _await_frames(POSE_SETTLE_FRAMES)

	var records: Array[Dictionary] = []
	var current = state
	for _index in range(JOLT_MAX_TICKS):
		var result = AdapterScript.step(
			world.body, world.hull_shape, current, idle, tuning, config
		)
		records.append({"result": result, "state_in": current})
		if result.committed_state != null:
			current = result.committed_state
		await get_tree().physics_frame

	var contact_index := -1
	for index in range(records.size()):
		var result = records[index]["result"]
		if result.has_wall_response_witness and result.has_wall_contact_point:
			contact_index = index
			break
	d.check(contact_index >= 0, "jolt: committed wall witness occurred")
	if contact_index >= 0:
		var impact = records[contact_index]["result"]
		var outcome := _produce(
			impact, config, "car-jolt", "evt-jolt-wall", "contact-jolt-1",
			contact_index
		)
		d.check(outcome.is_ok(), "jolt: producer accepts the real witness")
		if outcome.is_ok():
			var event := outcome.event
			var expected_severity := ImpactEvent.stable_norm(
				impact.wall_pre_response_velocity_world_m_s
				- impact.wall_post_response_velocity_world_m_s
			)
			d.check_close(
				event.severity_m_s, expected_severity,
				WallImpactLabChecks.NORM_TOLERANCE,
				"jolt: severity is the stable witness change"
			)
			d.check(
				event.post_contact_velocity_world_m_s
					== impact.wall_post_response_velocity_world_m_s,
				"jolt: post is the witness value"
			)
			d.check_vector_close(
				event.contact_point_world_m, impact.wall_contact_point,
				WallImpactLabChecks.VECTOR_TOLERANCE,
				"jolt: world point is the selected witness point"
			)
			var expected_local: Vector3 = (
				impact.wall_contact_transform.affine_inverse()
				* impact.wall_contact_point
			)
			d.check_vector_close(
				event.contact_point_local_m, expected_local,
				WallImpactLabChecks.VECTOR_TOLERANCE,
				"jolt: local point is the collision-time frame inverse"
			)
			d.check(
				event.imparted_motion_m == Vector3.ZERO,
				"jolt: imparted motion is zero"
			)
			d.check(
				event.region == ImpactEvent.ContactRegion.FRONT,
				"jolt: head-on wall is FRONT"
			)
			d.check_vector_close(
				event.contact_normal_world_m, Vector3(0.0, 0.0, 1.0),
				WallImpactLabChecks.VECTOR_TOLERANCE,
				"jolt: wall normal projects to +Z"
			)
			d.check(
				absf(event.contact_point_local_m.z)
					<= config.hull_size_m.z * 0.5 + 0.1,
				"jolt: local contact stays near the hull envelope"
			)
			d.check(event.is_valid(), "jolt: published event is valid")
			var ledger := ImpactEvent.Ledger.new()
			d.check(
				WallImpactProducer.publish(event, ledger).is_published(),
				"jolt: real witness event publishes"
			)
			measurements["jolt_tick_index"] = contact_index
			measurements["jolt_severity_m_s"] = event.severity_m_s
			measurements["jolt_region"] = event.region_name()
			measurements["jolt_pre_speed_m_s"] = (
				impact.wall_pre_response_velocity_world_m_s.length()
			)
			measurements["jolt_post_speed_m_s"] = (
				impact.wall_post_response_velocity_world_m_s.length()
			)

	world.destroy()
	await _await_frames(6)
	return {
		"case": JOLT_CASE_ID,
		"pass": d.failures.is_empty(),
		"checks": d.checks,
		"checks_failed": d.failures.size(),
		"failures": d.failures.duplicate(),
		"measurements": measurements.duplicate(),
	}


func _case_real_jolt_steering_corner() -> Dictionary:
	d = ChecksScript.new()
	measurements = {}
	var body_checks := BodyLabChecksScript.new()
	# Pinned probe scenarios: both steering signs into the same straight wall.
	# The response normal stays nose-facing while the point-only rule names the
	# inside side face on the sustained corner contact.
	var scenarios := [
		{
			"label": "near_steer_pos",
			"steer": 1.0,
			"side_region": ImpactEvent.ContactRegion.LEFT,
			"start_position": Vector2(0.0, 17.5),
			"velocity": Vector2(0.0, 20.0),
			"heading": 0.0,
			"command": body_checks.make_steer_command(1.0, 1.0),
		},
		{
			"label": "near_steer_neg",
			"steer": -1.0,
			"side_region": ImpactEvent.ContactRegion.RIGHT,
			"start_position": Vector2(0.0, 17.5),
			"velocity": Vector2(0.0, 20.0),
			"heading": 0.0,
			"command": body_checks.make_steer_command(-1.0, 1.0),
		},
	]
	for scenario in scenarios:
		var label: String = scenario["label"]
		var side_region: ImpactEvent.ContactRegion = scenario["side_region"]
		var report: Dictionary = await _run_steering_scenario(
			label, scenario["start_position"], scenario["velocity"],
			scenario["heading"], scenario["command"], STEERING_CORNER_TICKS
		)
		var witnesses: Array = report["witnesses"]
		var config: MotorBodyAdapter.Config = report["config"]
		var half_extents := config.hull_size_m * 0.5
		d.check(witnesses.size() >= 2, "%s.witness_stream_observed" % label)
		var front_count := 0
		var side_rule_count := 0
		var first := {}
		for witness_record in witnesses:
			var result: MotorBodyAdapter.Result = witness_record["result"]
			var tick_index: int = witness_record["index"]
			var event_id := "evt-%s-%d" % [label, tick_index]
			var outcome := ProducerScript.produce(
				result, config, "car-steer-" + label, event_id, "", tick_index
			)
			d.check(outcome.is_ok(), "%s.tick_%d.produced" % [label, tick_index])
			if not outcome.is_ok():
				continue
			var event := outcome.event
			var committed_world := AdapterScript.road_vector_to_world(
				result.committed_state.velocity_m_s
			)
			d.check(
				event.post_contact_velocity_world_m_s == committed_world,
				"%s.tick_%d.post_is_committed_canonical" % [label, tick_index]
			)
			var expected_severity := ImpactEvent.stable_norm(
				result.wall_pre_response_velocity_world_m_s - committed_world
			)
			d.check_close(
				event.severity_m_s, expected_severity,
				WallImpactLabChecks.NORM_TOLERANCE,
				"%s.tick_%d.severity_matches_witness_change" % [label, tick_index]
			)
			d.check(
				is_finite(event.severity_m_s) and event.severity_m_s > 0.0,
				"%s.tick_%d.severity_positive_finite" % [label, tick_index]
			)
			var expected_local: Vector3 = (
				result.wall_contact_transform.affine_inverse()
				* result.wall_contact_point
			)
			d.check_vector_close(
				event.contact_point_local_m, expected_local,
				WallImpactLabChecks.VECTOR_TOLERANCE,
				"%s.tick_%d.local_point_uses_collision_frame"
					% [label, tick_index]
			)
			d.check(
				event.contact_point_world_m == result.wall_contact_point,
				"%s.tick_%d.world_point_is_witness" % [label, tick_index]
			)
			var local_normal := _local_response_normal(result)
			d.check(
				absf(local_normal.z)
					> absf(local_normal.x) + LAB_REGION_NORMAL_AXIS_MARGIN,
				"%s.tick_%d.response_normal_is_nose_facing"
					% [label, tick_index]
			)
			d.check(
				absf(event.contact_point_local_m.x) <= half_extents.x + 1e-4
				and absf(event.contact_point_local_m.z) <= half_extents.z + 1e-4,
				"%s.tick_%d.local_point_on_hull_envelope"
					% [label, tick_index]
			)
			d.check(
				event.contact_point_local_m.x * float(scenario["steer"]) < 0.0,
				"%s.tick_%d.struck_corner_follows_steering_sign"
					% [label, tick_index]
			)
			d.check(
				event.region == ImpactEvent.ContactRegion.FRONT,
				"%s.tick_%d.region_is_front" % [label, tick_index]
			)
			if event.region == ImpactEvent.ContactRegion.FRONT:
				front_count += 1
			var baseline_region := _baseline_point_only_region(
				expected_local, config.hull_size_m
			)
			if baseline_region == side_region:
				side_rule_count += 1
			if first.is_empty():
				first = {
					"tick_index": tick_index,
					"severity_m_s": event.severity_m_s,
					"local_point": event.contact_point_local_m,
					"local_normal": local_normal,
					"baseline_region": ImpactEvent.REGION_NAMES[baseline_region],
					"collision_origin": result.wall_contact_transform.origin,
					"committed_origin": result.committed_transform.origin,
					"wrong_frame_local": (
						result.committed_transform.affine_inverse()
						* result.wall_contact_point
					),
				}
		d.check(
			front_count == witnesses.size(),
			"%s.every_witness_is_front" % label
		)
		d.check(
			side_rule_count >= 1,
			"%s.old_point_rule_misclassified_side" % label
		)
		if not first.is_empty():
			d.check(
				first["severity_m_s"] > 10.0,
				"%s.first_hit_is_high_speed" % label
			)
			var wrong_local: Vector3 = first["wrong_frame_local"]
			var wrong_gap := wrong_local.distance_to(first["local_point"])
			d.check(
				wrong_gap > 1e-3,
				"%s.committed_frame_would_differ" % label
			)
			measurements[label + "_witnesses"] = witnesses.size()
			measurements[label + "_front_witnesses"] = front_count
			measurements[label + "_old_side_rule_witnesses"] = side_rule_count
			measurements[label + "_first_tick"] = first["tick_index"]
			measurements[label + "_first_severity_m_s"] = first["severity_m_s"]
			measurements[label + "_first_local_point"] = first["local_point"]
			measurements[label + "_first_baseline_region"] = (
				first["baseline_region"]
			)
			measurements[label + "_first_wrong_frame_gap_m"] = wrong_gap
			measurements[label + "_collision_origin"] = first["collision_origin"]
			measurements[label + "_committed_origin"] = first["committed_origin"]
	return {
		"case": STEERING_JOLT_CASE_ID,
		"pass": d.failures.is_empty(),
		"checks": d.checks,
		"checks_failed": d.failures.size(),
		"failures": d.failures.duplicate(),
		"measurements": measurements.duplicate(),
	}


func _case_real_jolt_nonzero_heading_corner() -> Dictionary:
	d = ChecksScript.new()
	measurements = {}
	var body_checks := BodyLabChecksScript.new()
	var scenarios := [
		{
			"label": "v20_h0.900_s0_t0",
			"speed": 20.0,
			"heading": 0.9,
			"steer": 0.0,
			"throttle": 0.0,
		},
		{
			"label": "v35_h1.100_s1_t0",
			"speed": 35.0,
			"heading": 1.1,
			"steer": 1.0,
			"throttle": 0.0,
		},
	]
	for scenario in scenarios:
		var label: String = scenario["label"]
		var heading: float = scenario["heading"]
		var report: Dictionary = await _run_steering_scenario(
			label, _nonzero_heading_probe_start(heading),
			Vector2(0.0, scenario["speed"]), heading,
			body_checks.make_steer_command(
				scenario["steer"], scenario["throttle"]
			),
			NONZERO_HEADING_CORNER_TICKS
		)
		var witnesses: Array = report["witnesses"]
		var config: MotorBodyAdapter.Config = report["config"]
		var half_extents := config.hull_size_m * 0.5
		d.check(witnesses.size() >= 1, "%s.witness_stream_observed" % label)
		var left_count := 0
		var outside_old_band_count := 0
		var baseline_front_count := 0
		var first_normal := Vector3.ZERO
		var have_first_normal := false
		var first := {}
		for witness_record in witnesses:
			var result: MotorBodyAdapter.Result = witness_record["result"]
			var tick_index: int = witness_record["index"]
			var outcome := ProducerScript.produce(
				result, config, "car-nonzero-" + label,
				"evt-%s-%d" % [label, tick_index], "", tick_index
			)
			d.check(outcome.is_ok(), "%s.tick_%d.produced" % [label, tick_index])
			if not outcome.is_ok():
				continue
			var event := outcome.event
			var local_point := event.contact_point_local_m
			var local_normal := _local_response_normal(result)
			d.check(
				local_point.x < 0.0 and local_point.z < 0.0,
				"%s.tick_%d.contacts_front_left_quadrant" % [label, tick_index]
			)
			d.check(
				local_normal.x > 0.0
					and absf(local_normal.x)
						> absf(local_normal.z) + LAB_REGION_NORMAL_AXIS_MARGIN,
				"%s.tick_%d.local_normal_left_dominant" % [label, tick_index]
			)
			if not have_first_normal:
				first_normal = local_normal
				have_first_normal = true
			else:
				d.check_vector_close(
					local_normal, first_normal, 1e-5,
					"%s.tick_%d.local_normal_stable" % [label, tick_index]
				)
			d.check(
				event.region == ImpactEvent.ContactRegion.LEFT,
				"%s.tick_%d.region_is_left" % [label, tick_index]
			)
			if event.region == ImpactEvent.ContactRegion.LEFT:
				left_count += 1
			var lateral := absf(local_point.x) / half_extents.x
			var longitudinal := absf(local_point.z) / half_extents.z
			if absf(lateral - longitudinal) > OLD_NORMALIZED_REGION_TIE_MARGIN:
				outside_old_band_count += 1
			var baseline_region := _baseline_point_only_region(
				local_point, config.hull_size_m
			)
			if baseline_region == ImpactEvent.ContactRegion.FRONT:
				baseline_front_count += 1
			if first.is_empty():
				first = {
					"tick_index": tick_index,
					"severity_m_s": event.severity_m_s,
					"local_point": local_point,
					"local_normal": local_normal,
					"baseline_region": ImpactEvent.REGION_NAMES[baseline_region],
					"normalized_axis_difference": lateral - longitudinal,
				}
		d.check(
			left_count == witnesses.size(),
			"%s.every_witness_is_left" % label
		)
		d.check(
			baseline_front_count >= 1,
			"%s.old_point_rule_names_front" % label
		)
		d.check(
			outside_old_band_count >= 1,
			"%s.covers_outside_old_normalized_band" % label
		)
		if label == "v20_h0.900_s0_t0":
			d.check(
				witnesses.size() >= 2,
				"%s.continuing_contact_stream_observed" % label
			)
		if not first.is_empty():
			if label == "v35_h1.100_s1_t0":
				d.check(
					first["severity_m_s"] > 20.0,
					"%s.first_hit_is_high_speed" % label
				)
				d.check(
					first["baseline_region"] == "front",
					"%s.first_hit_old_rule_names_front" % label
				)
			measurements[label + "_witnesses"] = witnesses.size()
			measurements[label + "_left_witnesses"] = left_count
			measurements[label + "_outside_old_band_witnesses"] = (
				outside_old_band_count
			)
			measurements[label + "_first_tick"] = first["tick_index"]
			measurements[label + "_first_severity_m_s"] = first["severity_m_s"]
			measurements[label + "_first_local_point"] = first["local_point"]
			measurements[label + "_first_local_normal"] = first["local_normal"]
			measurements[label + "_first_baseline_region"] = (
				first["baseline_region"]
			)
			measurements[label + "_first_normalized_axis_difference"] = (
				first["normalized_axis_difference"]
			)
	return {
		"case": NONZERO_HEADING_JOLT_CASE_ID,
		"pass": d.failures.is_empty(),
		"checks": d.checks,
		"checks_failed": d.failures.size(),
		"failures": d.failures.duplicate(),
		"measurements": measurements.duplicate(),
	}


func _case_real_jolt_narrow_wall_end() -> Dictionary:
	d = ChecksScript.new()
	measurements = {}
	var body_checks := BodyLabChecksScript.new()
	# The independent reviewer's two wall-centred narrow-wall witnesses. The
	# vertical end of a 0.6 m wall slides along the left face, reaches the
	# measured near-nose side contact, then transitions to a genuine front
	# contact on the next tick.
	var scenarios := [
		{
			"label": "v20_h0.785_s-1_t0",
			"speed": 20.0,
			"heading": 0.785398,
			"steer": -1.0,
			"throttle": 0.0,
			"edge_tick": 27,
			"edge_inset_x_m": 0.0159773,
			"edge_inset_z_m": 0.0282234,
			"edge_severity_m_s": 5.3809494,
		},
		{
			"label": "v20_h0.785_s-1_t1",
			"speed": 20.0,
			"heading": 0.785398,
			"steer": -1.0,
			"throttle": 1.0,
			"edge_tick": 30,
			"edge_inset_x_m": 0.0157603,
			"edge_inset_z_m": 0.0287956,
			"edge_severity_m_s": 6.4013944,
		},
	]
	for scenario in scenarios:
		var label: String = scenario["label"]
		var heading: float = scenario["heading"]
		var report: Dictionary = await _run_steering_scenario(
			label, _nonzero_heading_probe_start(heading),
			Vector2(0.0, scenario["speed"]), heading,
			body_checks.make_steer_command(
				scenario["steer"], scenario["throttle"]
			),
			NONZERO_HEADING_CORNER_TICKS,
			NARROW_WALL_WIDTH_M
		)
		var witnesses: Array = report["witnesses"]
		var config: MotorBodyAdapter.Config = report["config"]
		var half_extents := config.hull_size_m * 0.5
		d.check(witnesses.size() >= 3, "%s.witness_stream_observed" % label)
		var edge_count := 0
		var edge_tick := -1
		var edge := {}
		var pre_edge_left_count := 0
		var front_normal_after_count := 0
		var first_front_tick := -1
		var first_front := {}
		var max_inset_x := -1.0e30
		var max_inset_z := -1.0e30
		var max_band_inset_x := 0.0
		var max_band_inset_z := 0.0
		for witness_record in witnesses:
			var result: MotorBodyAdapter.Result = witness_record["result"]
			var tick_index: int = witness_record["index"]
			var outcome := ProducerScript.produce(
				result, config, "car-narrow-end-" + label,
				"evt-%s-%d" % [label, tick_index], "", tick_index
			)
			d.check(outcome.is_ok(), "%s.tick_%d.produced" % [label, tick_index])
			if not outcome.is_ok():
				continue
			var event := outcome.event
			var local_point := event.contact_point_local_m
			var local_normal := _local_response_normal(result)
			var inset_x := half_extents.x - absf(local_point.x)
			var inset_z := half_extents.z - absf(local_point.z)
			max_inset_x = maxf(max_inset_x, inset_x)
			max_inset_z = maxf(max_inset_z, inset_z)
			var in_corner_band := (
				inset_x <= LAB_REGION_CORNER_BAND_M
				and inset_z <= LAB_REGION_CORNER_BAND_M
			)
			if in_corner_band:
				max_band_inset_x = maxf(max_band_inset_x, inset_x)
				max_band_inset_z = maxf(max_band_inset_z, inset_z)
			var x_dominance := absf(local_normal.x) - absf(local_normal.z)
			var z_dominance := -x_dominance
			var left_normal_clear := (
				local_normal.x > 0.0
				and x_dominance > LAB_REGION_NORMAL_AXIS_MARGIN
			)
			var front_normal_clear := (
				local_normal.z > 0.0
				and z_dominance > LAB_REGION_NORMAL_AXIS_MARGIN
			)
			var baseline_region := _baseline_point_only_region(
				local_point, config.hull_size_m
			)
			var edge_candidate := (
				in_corner_band
				and baseline_region == ImpactEvent.ContactRegion.FRONT
				and left_normal_clear
			)
			d.check(
				local_point.x < 0.0 and local_point.z < 0.0,
				"%s.tick_%d.contacts_front_left_quadrant" % [label, tick_index]
			)
			d.check(event.is_valid(), "%s.tick_%d.event_valid" % [label, tick_index])
			if edge_candidate:
				edge_count += 1
				if edge_tick < 0:
					edge_tick = tick_index
					edge = {
						"severity_m_s": event.severity_m_s,
						"local_point": local_point,
						"local_normal": local_normal,
						"inset_x_m": inset_x,
						"inset_z_m": inset_z,
						"x_dominance": x_dominance,
					}
				d.check(
					event.region == ImpactEvent.ContactRegion.LEFT,
					"%s.tick_%d.wall_end_edge_is_left" % [label, tick_index]
				)
				d.check(
					x_dominance > 0.25,
					"%s.tick_%d.edge_normal_is_clearly_left" % [label, tick_index]
				)
			elif edge_tick < 0:
				d.check(
					event.region == ImpactEvent.ContactRegion.LEFT,
					"%s.tick_%d.preceding_edge_contact_is_left" % [label, tick_index]
				)
				if event.region == ImpactEvent.ContactRegion.LEFT:
					pre_edge_left_count += 1
			if edge_tick >= 0 and tick_index > edge_tick and front_normal_clear:
				front_normal_after_count += 1
				if first_front_tick < 0:
					first_front_tick = tick_index
					first_front = {
						"severity_m_s": event.severity_m_s,
						"local_point": local_point,
						"local_normal": local_normal,
						"inset_x_m": inset_x,
						"inset_z_m": inset_z,
						"z_dominance": z_dominance,
					}
				d.check(
					event.region == ImpactEvent.ContactRegion.FRONT,
					"%s.tick_%d.later_front_transition_is_front" % [label, tick_index]
				)
				d.check(
					z_dominance > 0.25,
					"%s.tick_%d.front_normal_is_clearly_front" % [label, tick_index]
				)
		d.check(edge_count == 1, "%s.one_measured_wall_end_edge" % label)
		d.check(
			edge_tick == int(scenario["edge_tick"]),
			"%s.measured_wall_end_edge_tick" % label
		)
		d.check(
			pre_edge_left_count >= 3,
			"%s.preceding_left_contact_run" % label
		)
		d.check(
			front_normal_after_count >= 1,
			"%s.later_genuine_front_observed" % label
		)
		d.check(
			first_front_tick == edge_tick + 1,
			"%s.front_transition_follows_edge" % label
		)
		if not edge.is_empty():
			d.check(
				float(edge["inset_z_m"]) > 0.025
					and float(edge["inset_z_m"]) <= LAB_REGION_CORNER_BAND_M,
				"%s.edge_outside_old_band_inside_new_band" % label
			)
			d.check_close(
				float(edge["inset_x_m"]), float(scenario["edge_inset_x_m"]),
				5.0e-4, "%s.edge_inset_x_matches_measurement" % label
			)
			d.check_close(
				float(edge["inset_z_m"]), float(scenario["edge_inset_z_m"]),
				5.0e-4, "%s.edge_inset_z_matches_measurement" % label
			)
			d.check_close(
				float(edge["severity_m_s"]), float(scenario["edge_severity_m_s"]),
				0.25, "%s.edge_severity_matches_measurement" % label
			)
			d.check(
				float(edge["severity_m_s"]) > 1.0,
				"%s.edge_severity_is_significant" % label
			)
		if not first_front.is_empty():
			d.check(
				float(first_front["severity_m_s"]) > 1.0,
				"%s.front_transition_severity_is_significant" % label
			)
		measurements[label + "_scenario"] = {
			"speed_m_s": scenario["speed"],
			"heading_rad": heading,
			"steer": scenario["steer"],
			"throttle": scenario["throttle"],
			"wall_width_m": NARROW_WALL_WIDTH_M,
		}
		measurements[label + "_witnesses"] = witnesses.size()
		measurements[label + "_pre_edge_left_witnesses"] = pre_edge_left_count
		measurements[label + "_edge_tick"] = edge_tick
		measurements[label + "_first_front_tick"] = first_front_tick
		measurements[label + "_front_normal_after_count"] = (
			front_normal_after_count
		)
		measurements[label + "_max_inset_x_m"] = max_inset_x
		measurements[label + "_max_inset_z_m"] = max_inset_z
		measurements[label + "_max_band_inset_x_m"] = max_band_inset_x
		measurements[label + "_max_band_inset_z_m"] = max_band_inset_z
		if not edge.is_empty():
			measurements[label + "_edge_severity_m_s"] = edge["severity_m_s"]
			measurements[label + "_edge_inset_x_m"] = edge["inset_x_m"]
			measurements[label + "_edge_inset_z_m"] = edge["inset_z_m"]
			measurements[label + "_edge_local_point"] = edge["local_point"]
			measurements[label + "_edge_local_normal"] = edge["local_normal"]
		if not first_front.is_empty():
			measurements[label + "_front_severity_m_s"] = (
				first_front["severity_m_s"]
			)
			measurements[label + "_front_inset_x_m"] = first_front["inset_x_m"]
			measurements[label + "_front_inset_z_m"] = first_front["inset_z_m"]
			measurements[label + "_front_local_normal"] = (
				first_front["local_normal"]
			)
	return {
		"case": NARROW_WALL_END_JOLT_CASE_ID,
		"pass": d.failures.is_empty(),
		"checks": d.checks,
		"checks_failed": d.failures.size(),
		"failures": d.failures.duplicate(),
		"measurements": measurements.duplicate(),
	}


# --- Helpers --------------------------------------------------------------


## Start one metre before the straight wall in the same road-plane forward
## coordinate used by the reviewer sweep. `heading` rotates the rectangular
## hull, so the clearance accounts for its forward-projected half-extent.
func _nonzero_heading_probe_start(heading: float) -> Vector2:
	var half := WallImpactLabChecks.HALF_EXTENTS_M
	var forward_extent := half.z * cos(heading) + half.x * sin(heading)
	var wall_front_y := absf(STRAIGHT_WALL_Z) - WALL_THICKNESS_M * 0.5
	return Vector2(0.0, wall_front_y - forward_extent - 1.0)


func _run_steering_scenario(
	label: String,
	start_position: Vector2,
	velocity: Vector2,
	heading: float,
	command,
	ticks: int,
	wall_width_m := STEERING_WALL_WIDTH_M
) -> Dictionary:
	var config := d.make_config()
	var body_checks := BodyLabChecksScript.new()
	var tuning := body_checks.make_tuning()
	var wall_spec := {
		"point": Vector3(0.0, 2.0, STRAIGHT_WALL_Z),
		"yaw_deg": 0.0,
		"thickness_m": WALL_THICKNESS_M,
		"width_m": wall_width_m,
	}
	var world: BodyLabWorld = WorldScript.build(
		get_tree().root, config, wall_spec
	)
	await _await_frames(SETTLE_FRAMES)
	var initial = body_checks.make_state(start_position, velocity, heading)
	world.set_pose(initial, BodyLabChecksScript.BODY_SUPPORT_Y)
	await _await_frames(POSE_SETTLE_FRAMES)
	var current = initial
	var witnesses: Array[Dictionary] = []
	for index in range(ticks):
		var result = AdapterScript.step(
			world.body, world.hull_shape, current, command, tuning, config
		)
		if result.committed_state != null:
			current = result.committed_state
		if result.status == MotorBodyAdapter.Status.COMMITTED \
				and result.has_wall_response_witness \
				and result.has_wall_contact_point:
			witnesses.append({"index": index, "result": result})
		await get_tree().physics_frame
	world.destroy()
	await _await_frames(6)
	return {"config": config, "witnesses": witnesses}


func _await_frames(count: int) -> void:
	for _index in range(count):
		await get_tree().physics_frame


func _read_source(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _strip_full_line_comments(source: String) -> String:
	var kept := ""
	for line in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		kept += line + "\n"
	return kept


## Baseline point-only classifier from the pre-repair producer, used only as
## a negative control to show the repaired normal rule changes the label.
func _baseline_point_only_region(
	local_point: Vector3,
	hull_size_m: Vector3
) -> ImpactEvent.ContactRegion:
	var half_extents := hull_size_m * 0.5
	var lateral := absf(local_point.x) / half_extents.x
	var longitudinal := absf(local_point.z) / half_extents.z
	if longitudinal >= lateral:
		return (
			ImpactEvent.ContactRegion.FRONT
			if local_point.z < 0.0
			else ImpactEvent.ContactRegion.REAR
		)
	return (
		ImpactEvent.ContactRegion.RIGHT
		if local_point.x > 0.0
		else ImpactEvent.ContactRegion.LEFT
	)


func _road_plane_unit_normal(normal: Vector3) -> Vector3:
	var projected := Vector3(normal.x, 0.0, normal.z)
	var length := ImpactEvent.stable_norm(projected)
	if not is_finite(length) or length <= 0.0:
		return Vector3.ZERO
	return Vector3(projected.x / length, 0.0, projected.z / length)


func _local_response_normal(result: MotorBodyAdapter.Result) -> Vector3:
	return (
		result.wall_contact_transform.basis.inverse()
		* _road_plane_unit_normal(result.wall_contact_normal)
	)


## Next representable engine float32 above `base`, for one-bit mismatch probes.
func _next_float32(base: float) -> float:
	return base + absf(base) * 2.0 ** -23
