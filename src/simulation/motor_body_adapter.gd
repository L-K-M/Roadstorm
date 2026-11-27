class_name MotorBodyAdapter
extends RefCounted
## One-tick integration seam between the pure `ArcadeMotor` and one actual
## `CharacterBody3D` in a Godot/Jolt physics world (M1.1 laboratory slice).
##
## The adapter is deliberately not a `Node` and owns no clock, scene tree or
## automatic physics loop. A coordinator calls `step()` exactly once per 60 Hz
## physics tick; the adapter performs the nonmutating swept prediction for that
## tick, commits the accepted displacement with `CharacterBody3D.move_and_collide()`
## and reports the outcome. It never calls `move_and_slide()`, never integrates
## velocity a second time, and never writes a provisional body pose mid-tick.
##
## Contract:
##   * road-plane to world mapping on the flat +Y support plane is fixed:
##     CarState x -> world +X, CarState y -> world -Z. `heading_rad` rotates the
##     nose within that plane; positive heading points the nose toward +X;
##   * the tick-start transform is the body's actual `global_transform`, snapshotted
##     before any query or movement;
##   * all swept queries and the single accepted commit per substep use that
##     explicit simulated transform, so no query depends on the body having
##     already moved;
##   * invalid state/command/tuning/config/dt, a hull/config mismatch, or travel
##     above the configured substep envelope leaves the body and every caller
##     input untouched;
##   * work caps and comparison epsilons are absolutely bounded; any unapplied
##     travel beyond the tight epsilon is refused unless a genuine contact stop
##     ended the sweep (reported through `remainder_m`);
##   * a wall-like contact removes the inward normal component of the committed
##     velocity and applies the configured bounded tangential retention. Any
##     further contact response (deflection shaping, restitution tuning,
##     depenetration, multi-car response) is M1.4 work.
##
## This is one-car flat-ground laboratory work. It does not implement ground
## adhesion, jumps, drift, reset, controls, surfaces or multi-car contacts, and
## it makes no M1 acceptance claim.

const DT := 1.0 / 60.0
## Absolute tolerance for accepting a caller-supplied step size as 60 Hz.
const DT_TOLERANCE_S := 1e-6
## The only support basis this slice implements: flat ground, +Y up.
const SUPPORT_UP := Vector3(0.0, 1.0, 0.0)
## Tolerance for requiring the actual collision shape to match the documented
## hull envelope in `Config.hull_size_m`.
const HULL_MATCH_TOLERANCE_M := 1e-6
## Below this segment length the sweep loop stops; it is a work guard, not a
## physical threshold.
const MIN_SEGMENT_LENGTH_M := 1e-9
## Conservative absolute work bounds. 32 substeps retains the default 65 m/s
## case (5 substeps at 0.25 m) with headroom. A 1.0 m substep stays below the
## laboratory's 2 m wall thickness and its 3.8 m hull length, so one missed
## swept query still cannot carry the hull across the wall.
const ABSOLUTE_MAX_SUBSTEPS := 32
const ABSOLUTE_MAX_SUBSTEP_LENGTH_M := 1.0
## Epsilon ceilings are tiny fractions of one substep (with small absolute
## caps) so a comparison epsilon can never authorize dropping meaningful
## motion. At the 0.25 m default substep the envelope epsilon ceiling is
## 2.5e-4 m and the contact-stop ceiling is 2.5e-4 m.
const MAX_ENVELOPE_EPSILON_FRACTION := 1e-3
const MAX_ENVELOPE_EPSILON_M := 1e-3
const MAX_CONTACT_STOP_EPSILON_FRACTION := 1e-3

## Step outcome. `COMMITTED` means the body was moved and a committed state was
## produced. The other statuses are refusals that leave the body at its
## tick-start pose and leave every input object unchanged.
enum Status {
	COMMITTED,
	REJECTED_INVALID_INPUT,
	REFUSED_MOTION_BOUND,
}

## Explicit, caller-supplied envelope and contact-response values.
##
## The adapter contains no handling math and no hidden coefficients: every
## physical/work number used by `step()` is a field here, supplied by the
## caller. The initializers are documented laboratory defaults, not frozen
## product handling. A future coordinator or car resource supplies its own
## values; changing them changes the laboratory envelope only.
class Config extends RefCounted:
	## Collision hull envelope (width X, height Y, length Z) in metres. Must
	## match the body's actual BoxShape3D so the audited no-tunneling envelope
	## describes the real hull. Derived from the schema's car dimension range;
	## this value is a laboratory choice, not a car specification.
	var hull_size_m := Vector3(1.8, 1.0, 3.8)
	## Maximum length of one swept substep, metres. Kept well below the hull
	## length and the thick static wall used by the laboratory so a single
	## substep cannot cross the wall even if a query misses.
	var substep_max_length_m := 0.25
	## Hard substep work cap per tick. Must be in
	## [1, `ABSOLUTE_MAX_SUBSTEPS`]; 32 retains the 65 m/s laboratory case with
	## headroom.
	var max_substeps := 16
	## Margin passed to the nonmutating shape-motion and `test_move` queries.
	## Zero reproduces the committed `move_and_collide()` travel; a nonzero
	## margin stops the prediction early (measured on the pinned Jolt build).
	var sweep_margin_m := 0.0
	## Safe margin passed to the committed `move_and_collide()` call.
	var commit_safe_margin_m := 0.0
	## Slack for the over-envelope and remainder comparisons, metres. Must be
	## at most `MAX_ENVELOPE_EPSILON_FRACTION` of one substep and at most
	## `MAX_ENVELOPE_EPSILON_M`, so it cannot authorize dropped motion.
	var envelope_epsilon_m := 1e-6
	## A collision whose travelled length is at least the segment minus this
	## epsilon did not stop the motion, so the sweep continues. Must be at most
	## `MAX_CONTACT_STOP_EPSILON_FRACTION` of one substep.
	var contact_stop_epsilon_m := 1e-6
	## A contact is treated as a wall when the absolute alignment of its normal
	## with the support up axis is at most this value. Floor/ceiling contacts
	## are reported but receive no wall velocity response.
	var wall_normal_max_up_alignment := 0.5
	## Bounded normal restitution applied only to wall contacts. Zero removes
	## the inward normal velocity without bouncing; values are clamped to [0, 1].
	var wall_restitution := 0.0
	## Fraction of the tangential wall-contact velocity retained, clamped to
	## [0, 1]. One scrubs nothing; lower values are explicit wall-brush tuning.
	var wall_tangential_keep := 1.0


	## Hard per-tick travel envelope: `substep_max_length_m * max_substeps`.
	func max_tick_travel_m() -> float:
		return substep_max_length_m * float(max_substeps)


	func is_valid() -> bool:
		if not MotorBodyAdapter._finite_vector3_positive(hull_size_m):
			return false
		if not MotorBodyAdapter._finite(substep_max_length_m) or substep_max_length_m <= 0.0:
			return false
		# A single swept substep must stay below the absolute conservative cap
		# and below the hull diagonal; otherwise the no-tunneling envelope no
		# longer describes the motion.
		if substep_max_length_m > ABSOLUTE_MAX_SUBSTEP_LENGTH_M:
			return false
		if substep_max_length_m > hull_size_m.length():
			return false
		if max_substeps < 1 or max_substeps > ABSOLUTE_MAX_SUBSTEPS:
			return false
		# The envelope product must be finite even for finite extreme fields.
		if not MotorBodyAdapter._finite(max_tick_travel_m()):
			return false
		# Margins only shift where sweeps stop; they are capped at one substep so
		# an absurd margin cannot hide a whole segment from the accounting.
		if (
			not MotorBodyAdapter._finite(sweep_margin_m)
			or sweep_margin_m < 0.0
			or sweep_margin_m > substep_max_length_m
		):
			return false
		if (
			not MotorBodyAdapter._finite(commit_safe_margin_m)
			or commit_safe_margin_m < 0.0
			or commit_safe_margin_m > substep_max_length_m
		):
			return false
		# Comparison epsilons are tightly bounded relative to one substep. A
		# large epsilon is the reported silent-truncation bypass: it let a
		# one-substep config accept multi-substep travel and report COMMITTED.
		if not MotorBodyAdapter._finite(envelope_epsilon_m) or envelope_epsilon_m < 0.0:
			return false
		if (
			envelope_epsilon_m
			> minf(
				substep_max_length_m * MAX_ENVELOPE_EPSILON_FRACTION,
				MAX_ENVELOPE_EPSILON_M
			)
		):
			return false
		if not MotorBodyAdapter._finite(contact_stop_epsilon_m) or contact_stop_epsilon_m < 0.0:
			return false
		if contact_stop_epsilon_m > substep_max_length_m * MAX_CONTACT_STOP_EPSILON_FRACTION:
			return false
		if (
			not MotorBodyAdapter._finite(wall_normal_max_up_alignment)
			or wall_normal_max_up_alignment < 0.0
			or wall_normal_max_up_alignment > 1.0
		):
			return false
		if not MotorBodyAdapter._finite(wall_restitution) or wall_restitution < 0.0 or wall_restitution > 1.0:
			return false
		if (
			not MotorBodyAdapter._finite(wall_tangential_keep)
			or wall_tangential_keep < 0.0
			or wall_tangential_keep > 1.0
		):
			return false
		return true


## Result of one adapter step. All motion fields are world-space metres.
class Result extends RefCounted:
	var status: Status = Status.COMMITTED
	var rejection_reason := ""
	## Pure motor result for the accepted inputs. Null on refusal.
	var proposed_state: CarState = null
	## Motor state after the accepted contact response. Null on refusal.
	var committed_state: CarState = null
	## Motor-proposed road-plane displacement expressed in world axes.
	var proposed_motion_m := Vector3.ZERO
	## Sum of the nonmutating body-motion predictions actually used, world axes.
	var predicted_motion_m := Vector3.ZERO
	## Secondary diagnostic travel from `CharacterBody3D.test_move`, world axes.
	var test_move_predicted_motion_m := Vector3.ZERO
	## Sum of committed `move_and_collide()` travel, world axes.
	var accepted_motion_m := Vector3.ZERO
	## Commanded travel left unapplied at the end of the tick. Zero on a clean
	## open-ground tick. A nonzero value with `status == COMMITTED` means a
	## wall stopped the motion early; a nonzero value with
	## `REFUSED_MOTION_BOUND` means the bounded work cap refused the command.
	var remainder_m := 0.0
	## True when `remainder_m` is nonzero because a genuine contact stop ended
	## the sweep early (`status == COMMITTED`). False on a clean tick and on
	## refusal.
	var contact_limited_remainder := false
	## Worst per-substep distance between the predicted and committed endpoints.
	var prediction_commit_discrepancy_m := 0.0
	## Worst per-substep distance between the `test_move` and committed endpoints.
	var test_move_commit_discrepancy_m := 0.0
	## True when any collision stopped a substep.
	var contact := false
	## True when a collision normal was classified as wall-like.
	var wall_contact := false
	var contact_normal := Vector3.ZERO
	var contact_point := Vector3.ZERO
	var substeps := 0
	var start_transform := Transform3D()
	var committed_transform := Transform3D()
	var motor_yaw_delta_rad := 0.0


## Advance one logical 60 Hz tick for `body`.
##
## `state_in` is the committed road-plane state, `command` a normalized
## driver command and `tuning` valid motor tuning. `config` supplies the
## envelope and contact-response values. The body's `global_transform` at call
## time is the tick-start snapshot; it must already correspond to `state_in`
## under the flat-support mapping documented above (the adapter does not guess
## an offset between them).
##
## Returns a `Result`. Refusals (`REJECTED_INVALID_INPUT`,
## `REFUSED_MOTION_BOUND`) do not touch the body and do not mutate any input.
static func step(
	body: CharacterBody3D,
	hull_shape: BoxShape3D,
	state_in: CarState,
	command: DriverCommand,
	tuning: ArcadeMotor.MotorTuning,
	config: Config,
	dt: float = DT
) -> Result:
	# ---- Validate everything before reading or writing the body. ----------
	var result := Result.new()
	if body == null or hull_shape == null or state_in == null or command == null \
			or tuning == null or config == null:
		return _reject(result, "null body/shape/state/command/tuning/config")
	if not config.is_valid():
		return _reject(result, "invalid motor-body config")
	if body.get_world_3d() == null:
		return _reject(result, "body is not inside a physics world")
	if not body.scale.is_equal_approx(Vector3.ONE):
		return _reject(result, "scaled body is outside the documented box-hull envelope")
	if not state_in.is_finite():
		return _reject(result, "nonfinite car state")
	if not command.is_normalized():
		return _reject(result, "unnormalized or nonfinite driver command")
	if not tuning.is_valid():
		return _reject(result, "invalid motor tuning")
	if not _finite(dt) or dt <= 0.0 or absf(dt - DT) > DT_TOLERANCE_S:
		return _reject(result, "dt is not the declared 60 Hz tick")
	if hull_shape.size.distance_to(config.hull_size_m) > HULL_MATCH_TOLERANCE_M:
		return _reject(result, "collision hull does not match the documented envelope")

	var proposal := ArcadeMotor.propose(state_in, command, tuning, dt)
	if proposal == null:
		return _reject(result, "pure motor refused the validated inputs")

	result.proposed_state = proposal.state
	result.proposed_motion_m = road_vector_to_world(proposal.displacement_m)
	result.motor_yaw_delta_rad = proposal.yaw_delta_rad

	# Fail closed before any movement when the commanded chord cannot be applied
	# within the bounded substep work cap. The remainder is never dropped.
	var desired := result.proposed_motion_m
	if desired.length() > config.max_tick_travel_m() + config.envelope_epsilon_m:
		result.status = Status.REFUSED_MOTION_BOUND
		result.rejection_reason = (
			"proposed travel %.6f m exceeds envelope %.6f m"
			% [desired.length(), config.max_tick_travel_m()]
		)
		result.committed_state = state_in.copy()
		result.remainder_m = desired.length()
		return result

	# ---- Sweep and commit the tick. ----------------------------------------
	var start := body.global_transform
	result.start_transform = start
	var simulated := start
	var remaining := desired
	var accepted := Vector3.ZERO
	var predicted := Vector3.ZERO
	var test_predicted := Vector3.ZERO
	var worst_prediction_error := 0.0
	var worst_test_move_error := 0.0
	var hit := false
	var wall_hit := false
	var stopped_short := false
	var hit_normal := Vector3.ZERO
	var hit_point := Vector3.ZERO
	var substeps := 0

	while remaining.length() > MIN_SEGMENT_LENGTH_M and substeps < config.max_substeps:
		var segment_length: float = minf(remaining.length(), config.substep_max_length_m)
		var motion := remaining.normalized() * segment_length

		# Primary nonmutating body-motion prediction from the explicit
		# simulated transform. Margin 0 is deliberate: see Config.
		var safe_fraction := _cast_safe_fraction(body, hull_shape, simulated, motion, config)
		var predicted_segment := motion * safe_fraction
		# Secondary named diagnostic: CharacterBody3D.test_move. Its travel can
		# carry a depenetration/recovery offset near contacts; it is recorded,
		# not used to gate the commit.
		var test_travel := _test_move_travel(body, simulated, motion, config)

		# Single committed call for this accepted segment.
		var collision := body.move_and_collide(
			motion, false, config.commit_safe_margin_m, false, 8
		)
		var actual := motion
		if collision != null:
			actual = collision.get_travel()
			hit = true
			hit_normal = collision.get_normal()
			hit_point = collision.get_position()
			if absf(hit_normal.normalized().dot(SUPPORT_UP)) \
					<= config.wall_normal_max_up_alignment:
				wall_hit = true

		var committed_end := simulated.origin + actual
		worst_prediction_error = maxf(
			worst_prediction_error,
			committed_end.distance_to(simulated.origin + predicted_segment)
		)
		worst_test_move_error = maxf(
			worst_test_move_error,
			committed_end.distance_to(simulated.origin + test_travel)
		)

		simulated.origin = committed_end
		accepted += actual
		predicted += predicted_segment
		test_predicted += test_travel
		remaining = desired - accepted
		substeps += 1
		if collision != null and actual.length() < segment_length - config.contact_stop_epsilon_m:
			stopped_short = true
			break

	# Defence in depth: any unapplied travel beyond the tight epsilon is a
	# refusal unless a genuine contact stop ended the sweep. A prior version
	# only checked this when no collision had occurred, so a small max_substeps
	# plus a large epsilon could report COMMITTED after one partial segment.
	if remaining.length() > config.envelope_epsilon_m and not stopped_short:
		body.global_transform = start
		result.status = Status.REFUSED_MOTION_BOUND
		result.rejection_reason = (
			"unapplied remainder %.6f m after %d substeps"
			% [remaining.length(), substeps]
		)
		result.committed_state = state_in.copy()
		result.remainder_m = remaining.length()
		return result

	# ---- Commit the logical state from the accepted motion. ----------------
	var committed := proposal.state.copy()
	committed.position_m = state_in.position_m + world_vector_to_road(accepted)

	var velocity_world := road_vector_to_world(proposal.state.velocity_m_s)
	if wall_hit:
		velocity_world = _apply_wall_response(velocity_world, hit_normal, config)
	committed.velocity_m_s = world_vector_to_road(velocity_world)

	var committed_transform := Transform3D(
		basis_from_heading(committed.heading_rad), start.origin + accepted
	)
	body.global_transform = committed_transform

	result.status = Status.COMMITTED
	result.committed_state = committed
	result.accepted_motion_m = accepted
	result.remainder_m = remaining.length()
	result.contact_limited_remainder = (
		stopped_short and remaining.length() > config.envelope_epsilon_m
	)
	result.predicted_motion_m = predicted
	result.test_move_predicted_motion_m = test_predicted
	result.prediction_commit_discrepancy_m = worst_prediction_error
	result.test_move_commit_discrepancy_m = worst_test_move_error
	result.contact = hit
	result.wall_contact = wall_hit
	result.contact_normal = hit_normal
	result.contact_point = hit_point
	result.substeps = substeps
	result.committed_transform = committed_transform
	return result


## World displacement of a road-plane free vector (fixed axis mapping).
static func road_vector_to_world(road: Vector2) -> Vector3:
	return Vector3(road.x, 0.0, -road.y)


## Road-plane free vector from a world vector (fixed axis mapping, no heading).
static func world_vector_to_road(world: Vector3) -> Vector2:
	return Vector2(world.x, -world.z)


## Nose forward direction in world space for a road-plane heading.
static func nose_forward_world(heading_rad: float) -> Vector3:
	return Vector3(sin(heading_rad), 0.0, -cos(heading_rad))


## Nose right direction in world space for a road-plane heading.
static func nose_right_world(heading_rad: float) -> Vector3:
	return Vector3(cos(heading_rad), 0.0, sin(heading_rad))


## Body basis for a road-plane heading on the flat +Y support plane.
static func basis_from_heading(heading_rad: float) -> Basis:
	var right := nose_right_world(heading_rad)
	var back := -nose_forward_world(heading_rad)
	return Basis(right, SUPPORT_UP, back)


## Nonmutating shape-motion prediction: fraction of `motion` reachable from
## `from` before contact. Zero margin reproduces the committed travel measured
## on the pinned Jolt build; a nonzero margin stops the prediction early.
static func _cast_safe_fraction(
	body: CharacterBody3D,
	hull_shape: BoxShape3D,
	from: Transform3D,
	motion: Vector3,
	config: Config
) -> float:
	var space := body.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hull_shape
	query.transform = from
	query.motion = motion
	query.margin = config.sweep_margin_m
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [body.get_rid()]
	var fractions: Array = space.cast_motion(query)
	if fractions.is_empty():
		return 1.0
	return clampf(float(fractions[0]), 0.0, 1.0)


## Secondary nonmutating prediction using the named CharacterBody3D query.
## Returns the travel vector it reports (the full segment when it reports no
## collision).
static func _test_move_travel(
	body: CharacterBody3D,
	from: Transform3D,
	motion: Vector3,
	config: Config
) -> Vector3:
	var collision := KinematicCollision3D.new()
	var hit := body.test_move(from, motion, collision, config.sweep_margin_m, false, 8)
	if not hit:
		return motion
	return collision.get_travel()


## Bounded wall response: remove the inward normal component (with the
## configured capped restitution) and retain at most the configured fraction of
## the tangential component. It never adds speed and never reverses the normal
## component past zero at restitution 0.
static func _apply_wall_response(
	velocity_world: Vector3,
	normal: Vector3,
	config: Config
) -> Vector3:
	var unit_normal := normal.normalized()
	if unit_normal.length_squared() < 0.5:
		return velocity_world
	var normal_speed := velocity_world.dot(unit_normal)
	if normal_speed >= 0.0:
		return velocity_world
	var restitution := clampf(config.wall_restitution, 0.0, 1.0)
	var corrected := velocity_world - unit_normal * normal_speed * (1.0 + restitution)
	var corrected_normal_speed := corrected.dot(unit_normal)
	var tangent := corrected - unit_normal * corrected_normal_speed
	var keep := clampf(config.wall_tangential_keep, 0.0, 1.0)
	return unit_normal * corrected_normal_speed + tangent * keep


static func _reject(result: Result, reason: String) -> Result:
	result.status = Status.REJECTED_INVALID_INPUT
	result.rejection_reason = reason
	result.committed_state = null
	return result


static func _finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)


static func _finite_vector3_positive(value: Vector3) -> bool:
	return (
		_finite(value.x) and value.x > 0.0
		and _finite(value.y) and value.y > 0.0
		and _finite(value.z) and value.z > 0.0
	)
