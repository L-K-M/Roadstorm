extends SceneTree
## Headless camera-rig validation entry point (PLAN.md M1.5 slice).
##
## Run from an isolated project copy after importing resources:
##   godot --headless --fixed-fps 60 --path <project> \
##       --script res://tools/camera_lab/validate_camera_rig.gd
##
## Exercises the presentation-only `CameraRig` component: all three mode
## placements/directions on translated and yawed targets, bank/pitch horizon
## stabilization, FOV preference bounds, target immutability, rear-view
## same-node identity and restore, missing/invalid target safety, nonfinite
## input rejection, determinism and optional smoothing direction.
##
## `--expect-failure` deliberately records a failure so the nonzero exit path
## is observable. The bounded wrapper tools/camera_lab/run_validation.sh runs
## the pass case and this proof.
##
## Scope: structural/behavioural headless checks only. No rendering, no game
## viewport integration, no wall avoidance, corner look-ahead, four-player
## performance or M1.5/M1 acceptance claim.

const RIG_SCRIPT_PATH := "res://src/presentation/camera_rig.gd"
const CameraRigScript := preload("res://src/presentation/camera_rig.gd")

const EXPECTED_MAJOR := 4
const EXPECTED_MINOR := 7
const EXPECTED_PATCH := 2
const EXPECTED_STATUS := "stable"
const EXPECTED_BUILD := "official"
const EXPECTED_COMMIT_PREFIX := "ed1daf0bf"

## Provisional authored defaults mirrored here as an independent oracle. They
## are not validated camera constants and may change during tuning.
const EXPECTED_CHASE_OFFSET := Vector3(0.0, 2.8, 7.2)
const EXPECTED_NEAR_OFFSET := Vector3(0.0, 1.5, 4.0)
const EXPECTED_HOOD_OFFSET := Vector3(0.0, 1.05, -1.1)
const EXPECTED_CHASE_LOOK_OFFSET := Vector3(0.0, 1.2, -6.0)
const EXPECTED_NEAR_LOOK_OFFSET := Vector3(0.0, 1.0, -6.0)
const EXPECTED_HOOD_LOOK_OFFSET := Vector3(0.0, 0.9, -8.0)
const EXPECTED_MODE_NAMES: Array[String] = ["chase", "near_chase", "hood"]
const EXPECTED_DEFAULT_FOVS: Array[float] = [70.0, 75.0, 80.0]
const MIN_FOV_DEGREES := 30.0
const MAX_FOV_DEGREES := 120.0

const VECTOR_TOLERANCE := 1e-4
const POSE_TOLERANCE := 1e-6
const UP_TOLERANCE := 1e-3
const DIRECTION_TOLERANCE_DEG := 0.5
const REVERSE_TOLERANCE_DEG := 1.0
const SMOOTHING_SETTLE_DEG := 1.0
const MAX_STARTUP_FRAMES := 120

## Test double for the documented `refine_desired_pose` seam: it deliberately
## returns a collapsed pose so the resulting-camera boundary can be exercised.
class CollapsingCameraRig extends CameraRig:
	func refine_desired_pose(
		desired: Transform3D,
		_delta: float
	) -> Transform3D:
		return Transform3D(
			Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO),
			desired.origin
		)

var _checks := 0
var _failures: Array[String] = []
var _measured: Dictionary = {}
var _finished := false
var _rig: CameraRig = null
var _aux: CameraRig = null
var _oracle: CameraRig = null
var _target: Node3D = null
var _started := false
var _wait_frames := 0


func _initialize() -> void:
	print("[camera-lab] engine ", Engine.get_version_info()["string"])
	_check_engine()

	if not ResourceLoader.exists(RIG_SCRIPT_PATH):
		_record_failure("script.exists", "missing %s" % RIG_SCRIPT_PATH)
		_finish()
		return

	_rig = CameraRigScript.new()
	_aux = CameraRigScript.new()
	_oracle = CameraRigScript.new()
	_target = Node3D.new()
	_target.name = "CameraLabTarget"
	# The scene tree is not fully initialised during _initialize, so defer the
	# additions and run the checks on the first process frame, once every node
	# reports is_inside_tree().
	root.add_child.call_deferred(_rig)
	root.add_child.call_deferred(_aux)
	root.add_child.call_deferred(_oracle)
	root.add_child.call_deferred(_target)
	process_frame.connect(_on_first_frame)


func _on_first_frame() -> void:
	if _finished or _started:
		return
	if not (
		_rig.is_inside_tree()
		and _aux.is_inside_tree()
		and _oracle.is_inside_tree()
		and _target.is_inside_tree()
	):
		_wait_frames += 1
		if _wait_frames > MAX_STARTUP_FRAMES:
			_record_failure(
				"startup.nodes_in_tree",
				"rig/target nodes never entered the scene tree within %d frames" % MAX_STARTUP_FRAMES
			)
			_finish()
		return
	_started = true
	_run_checks()
	_finish()


# --- Check groups ----------------------------------------------------------


func _run_checks() -> void:
	_check_structure()
	_check_attach_rejection()
	_check_mode_placements()
	_check_translated_and_yawed_targets()
	_check_horizon_stabilization()
	_check_fov_preference()
	_check_target_immutability()
	_check_rear_view()
	_check_target_safety()
	_check_off_tree_target()
	_check_degenerate_and_scaled_targets()
	_check_nonfinite_inputs()
	_check_determinism()
	_check_smoothing_direction()
	_check_viewport_attach_detach()

	if _has_user_flag("--expect-failure"):
		_check(
			false,
			"expect_failure.deliberate",
			"--expect-failure requested: proving a failing check exits nonzero"
		)


func _check_structure() -> void:
	_check(_rig is Node3D, "structure.rig_is_node3d", str(_rig))
	var camera := _rig.get_camera()
	_check(camera != null and camera is Camera3D, "structure.camera_owned", str(camera))
	_check(_count_cameras(_rig) == 1, "structure.single_camera", str(_count_cameras(_rig)))
	_check(
		_rig.get_mode() == CameraRig.Mode.CHASE,
		"structure.default_mode_chase",
		str(_rig.get_mode())
	)
	_check(
		_rig.get_target_state() == CameraRig.TargetState.NO_TARGET,
		"structure.initial_no_target",
		str(_rig.get_target_state())
	)
	_check(not _rig.has_valid_target(), "structure.initial_has_no_target", "")
	_check(
		absf(_rig.get_fov_preference(CameraRig.Mode.CHASE) - EXPECTED_DEFAULT_FOVS[0]) <= 1e-6,
		"structure.default_fov",
		str(_rig.get_fov_preference(CameraRig.Mode.CHASE))
	)

	# Missing target: the camera must stay finite and unchanged.
	var initial := camera.global_transform
	_rig.update_target_pose(0.0)
	_check(_finite_transform(camera.global_transform), "structure.missing_target_finite", str(camera.global_transform))
	_check(
		_transforms_equal(camera.global_transform, initial, 0.0),
		"structure.missing_target_pose_unchanged",
		"update with no target changed the camera"
	)
	_measured["initial_camera_finite"] = true


func _check_attach_rejection() -> void:
	# Attachment itself belongs to slot integration; only the rejection paths
	# that have no rendering side effects are checked here.
	_check(not _rig.attach_to_viewport(null), "attach.null_viewport_refused", "")
	var off_tree := SubViewport.new()
	_check(not _rig.attach_to_viewport(off_tree), "attach.off_tree_viewport_refused", "")
	_check(_rig.get_parent() == root, "attach.off_tree_kept_parent", str(_rig.get_parent()))
	off_tree.free()


func _check_mode_placements() -> void:
	_apply_target(Transform3D.IDENTITY)
	var offsets := [
		EXPECTED_CHASE_OFFSET,
		EXPECTED_NEAR_OFFSET,
		EXPECTED_HOOD_OFFSET,
	]
	var looks := [
		EXPECTED_CHASE_LOOK_OFFSET,
		EXPECTED_NEAR_LOOK_OFFSET,
		EXPECTED_HOOD_LOOK_OFFSET,
	]
	for index in range(offsets.size()):
		var mode: CameraRig.Mode = _mode_at(index)
		_check(_rig.select_mode(mode), "modes.select.%d" % index, "refused")
		_rig.snap_to_target()
		var camera := _rig.get_camera()
		var expected_position: Vector3 = Transform3D.IDENTITY * offsets[index]
		_check(
			_vec_close(camera.global_transform.origin, expected_position, VECTOR_TOLERANCE),
			"modes.position.%s" % EXPECTED_MODE_NAMES[index],
			"%s vs %s" % [camera.global_transform.origin, expected_position]
		)
		var expected_forward: Vector3 = (
			(Transform3D.IDENTITY * looks[index]) - expected_position
		).normalized()
		_check(
			_angle_deg(_forward(camera), expected_forward) <= DIRECTION_TOLERANCE_DEG,
			"modes.direction.%s" % EXPECTED_MODE_NAMES[index],
			"%s vs %s" % [_forward(camera), expected_forward]
		)
		_check(
			absf(camera.fov - EXPECTED_DEFAULT_FOVS[index]) <= 1e-6,
			"modes.fov.%s" % EXPECTED_MODE_NAMES[index],
			str(camera.fov)
		)
		_check(
			_rig.get_mode_name(mode) == EXPECTED_MODE_NAMES[index],
			"modes.name.%s" % EXPECTED_MODE_NAMES[index],
			_rig.get_mode_name(mode)
		)
		_check(
			_up_close_to_expected_stabilized_up(camera),
			"modes.up_stabilized.%s" % EXPECTED_MODE_NAMES[index],
			str(_up(camera))
		)
		_measured["mode_%s_position" % EXPECTED_MODE_NAMES[index]] = camera.global_transform.origin

	# Relative ordering: near is closer than chase; hood is ahead of the target.
	_rig.select_mode(CameraRig.Mode.CHASE)
	_rig.snap_to_target()
	var chase_distance := _rig.get_camera().global_transform.origin.length()
	_rig.select_mode(CameraRig.Mode.NEAR_CHASE)
	_rig.snap_to_target()
	var near_distance := _rig.get_camera().global_transform.origin.length()
	_rig.select_mode(CameraRig.Mode.HOOD)
	_rig.snap_to_target()
	var hood_position := _rig.get_camera().global_transform.origin
	_check(near_distance < chase_distance, "modes.near_closer_than_chase", "%f vs %f" % [near_distance, chase_distance])
	_check(hood_position.z < 0.0, "modes.hood_ahead_of_target", str(hood_position))

	# Cycling wraps through all three modes and back to chase.
	_rig.select_mode(CameraRig.Mode.CHASE)
	var cycled: Array[int] = []
	for _index in range(3):
		cycled.append(_rig.cycle_mode())
	_check(
		cycled == [CameraRig.Mode.NEAR_CHASE, CameraRig.Mode.HOOD, CameraRig.Mode.CHASE],
		"modes.cycle_wraps",
		str(cycled)
	)

	# An invalid mode value is refused without changing the mode.
	var invalid := 99 as CameraRig.Mode
	_check(not _rig.select_mode(invalid), "modes.invalid_refused", "select_mode accepted 99")
	_check(_rig.get_mode() == CameraRig.Mode.CHASE, "modes.invalid_kept_mode", str(_rig.get_mode()))


func _check_translated_and_yawed_targets() -> void:
	var target_transform := Transform3D(
		Basis(Vector3.UP, deg_to_rad(90.0)),
		Vector3(10.0, 3.0, -5.0)
	)
	_apply_target(target_transform)
	var offsets := [
		EXPECTED_CHASE_OFFSET,
		EXPECTED_NEAR_OFFSET,
		EXPECTED_HOOD_OFFSET,
	]
	var looks := [
		EXPECTED_CHASE_LOOK_OFFSET,
		EXPECTED_NEAR_LOOK_OFFSET,
		EXPECTED_HOOD_LOOK_OFFSET,
	]
	for index in range(offsets.size()):
		var mode: CameraRig.Mode = _mode_at(index)
		_rig.select_mode(mode)
		_rig.snap_to_target()
		var camera := _rig.get_camera()
		var expected_position: Vector3 = target_transform * offsets[index]
		_check(
			_vec_close(camera.global_transform.origin, expected_position, VECTOR_TOLERANCE),
			"transformed.position.%s" % EXPECTED_MODE_NAMES[index],
			"%s vs %s" % [camera.global_transform.origin, expected_position]
		)
		var expected_forward: Vector3 = (
			(target_transform * looks[index]) - expected_position
		).normalized()
		_check(
			_angle_deg(_forward(camera), expected_forward) <= DIRECTION_TOLERANCE_DEG,
			"transformed.direction.%s" % EXPECTED_MODE_NAMES[index],
			"%s vs %s" % [_forward(camera), expected_forward]
		)
		_check(
			_up_close_to_expected_stabilized_up(camera),
			"transformed.up_stabilized.%s" % EXPECTED_MODE_NAMES[index],
			str(_up(camera))
		)


func _check_horizon_stabilization() -> void:
	# Pure roll about the target's forward axis: the horizon must stay level.
	var rolled := Transform3D(
		Basis(Vector3.UP, deg_to_rad(12.0)) * Basis(Vector3.BACK, deg_to_rad(30.0)),
		Vector3(-4.0, 2.0, 7.0)
	)
	_apply_target(rolled)
	_rig.select_mode(CameraRig.Mode.CHASE)
	_rig.snap_to_target()
	var camera := _rig.get_camera()
	# Roll must not introduce camera roll: the lateral axis stays horizontal.
	_check(
		absf(_right(camera).y) <= UP_TOLERANCE,
		"horizon.roll_right_horizontal",
		str(_right(camera))
	)
	_check(
		_up_close_to_expected_stabilized_up(camera),
		"horizon.roll_up_stabilized",
		str(_up(camera))
	)

	# Combined bank, pitch and yaw: the up vector remains the world-up
	# projection onto the view plane rather than following the car's roll.
	var banked := Transform3D(
		Basis(Vector3.UP, deg_to_rad(25.0))
		* Basis(Vector3.RIGHT, deg_to_rad(18.0))
		* Basis(Vector3.BACK, deg_to_rad(30.0)),
		Vector3(6.0, -1.0, -8.0)
	)
	_apply_target(banked)
	_rig.snap_to_target()
	camera = _rig.get_camera()
	var forward := _forward(camera)
	var expected_up := _expected_stabilized_up(forward)
	_check(
		_vec_close(_up(camera), expected_up, UP_TOLERANCE),
		"horizon.bank_projection",
		"%s vs %s" % [_up(camera), expected_up]
	)
	_check(
		absf(_right(camera).dot(Vector3.UP)) <= UP_TOLERANCE,
		"horizon.bank_right_perpendicular_to_up",
		str(_right(camera))
	)
	_check(_finite_transform(camera.global_transform), "horizon.finite", str(camera.global_transform))


func _check_fov_preference() -> void:
	_rig.select_mode(CameraRig.Mode.CHASE)
	_check(_rig.set_fov_preference(CameraRig.Mode.CHASE, 10.0), "fov.clamp_low_accepted", "")
	_check(absf(_rig.get_camera().fov - MIN_FOV_DEGREES) <= 1e-6, "fov.clamp_low", str(_rig.get_camera().fov))
	_check(_rig.set_fov_preference(CameraRig.Mode.CHASE, 200.0), "fov.clamp_high_accepted", "")
	_check(absf(_rig.get_camera().fov - MAX_FOV_DEGREES) <= 1e-6, "fov.clamp_high", str(_rig.get_camera().fov))
	_check(_rig.set_fov_preference(CameraRig.Mode.CHASE, 65.0), "fov.value_accepted", "")
	_check(absf(_rig.get_camera().fov - 65.0) <= 1e-6, "fov.value_applied", str(_rig.get_camera().fov))

	# Nonfinite preferences are rejected and leave the stored/applied value alone.
	var before := _rig.get_fov_preference(CameraRig.Mode.CHASE)
	_check(not _rig.set_fov_preference(CameraRig.Mode.CHASE, NAN), "fov.nan_refused", "")
	_check(not _rig.set_fov_preference(CameraRig.Mode.CHASE, INF), "fov.inf_refused", "")
	_check(not _rig.set_fov_preference(CameraRig.Mode.CHASE, -INF), "fov.negative_inf_refused", "")
	_check(
		absf(_rig.get_fov_preference(CameraRig.Mode.CHASE) - before) <= 1e-9,
		"fov.nonfinite_unchanged",
		"%f vs %f" % [_rig.get_fov_preference(CameraRig.Mode.CHASE), before]
	)
	_check(
		absf(_rig.get_camera().fov - before) <= 1e-9,
		"fov.nonfinite_camera_unchanged",
		str(_rig.get_camera().fov)
	)

	# A preference for another mode does not disturb the active mode, and
	# selecting that mode applies it.
	_check(_rig.set_fov_preference(CameraRig.Mode.HOOD, 90.0), "fov.other_mode_accepted", "")
	_check(absf(_rig.get_camera().fov - before) <= 1e-9, "fov.other_mode_not_active", str(_rig.get_camera().fov))
	_rig.select_mode(CameraRig.Mode.HOOD)
	_check(absf(_rig.get_camera().fov - 90.0) <= 1e-6, "fov.selected_mode_applied", str(_rig.get_camera().fov))

	# Invalid mode enum is refused.
	_check(
		not _rig.set_fov_preference(99 as CameraRig.Mode, 60.0),
		"fov.invalid_mode_refused",
		""
	)


func _check_target_immutability() -> void:
	var target_transform := Transform3D(
		Basis(Vector3.UP, deg_to_rad(40.0)) * Basis(Vector3.BACK, deg_to_rad(15.0)),
		Vector3(7.0, 1.0, -2.0)
	)
	_apply_target(target_transform)
	var before := _target.transform
	for index in range(EXPECTED_MODE_NAMES.size()):
		_rig.select_mode(_mode_at(index))
		_rig.snap_to_target()
	_rig.hold_rear(true)
	_rig.snap_to_target()
	_rig.hold_rear(false)
	_rig.snap_to_target()
	_rig.update_target_pose(1.0 / 60.0)
	_check(_transforms_equal(_target.transform, before, 0.0), "immutability.transform", "target moved")
	_check(_vec_close(_target.global_position, before.origin, 0.0), "immutability.position", "target moved")
	_check(
		_vec_close(_target.transform.basis.get_euler(), before.basis.get_euler(), 0.0),
		"immutability.rotation",
		"target rotated"
	)


func _check_rear_view() -> void:
	var target_transform := Transform3D(
		Basis(Vector3.UP, deg_to_rad(35.0)),
		Vector3(2.0, 1.0, -3.0)
	)
	_apply_target(target_transform)
	_rig.select_mode(CameraRig.Mode.CHASE)
	_rig.snap_to_target()

	var camera := _rig.get_camera()
	var node_before: Camera3D = camera
	var position_before := camera.global_transform.origin
	var target_forward := (
		(target_transform * EXPECTED_CHASE_LOOK_OFFSET)
		- (target_transform * EXPECTED_CHASE_OFFSET)
	).normalized()
	var target_backward := target_transform.basis.z.normalized()
	_check(
		_angle_deg(_forward(camera), target_forward) <= DIRECTION_TOLERANCE_DEG,
		"rear.forward_before_hold",
		"%s vs %s" % [_forward(camera), target_forward]
	)

	_rig.hold_rear(true)
	_check(_rig.is_rear_held(), "rear.state_held", "")
	_check(_rig.get_camera() == node_before, "rear.same_node_identity", "camera node replaced")
	_check(_count_cameras(_rig) == 1, "rear.single_camera", str(_count_cameras(_rig)))
	_check(
		_vec_close(camera.global_transform.origin, position_before, POSE_TOLERANCE),
		"rear.position_kept",
		"%s vs %s" % [camera.global_transform.origin, position_before]
	)
	_check(
		_angle_deg(_forward(camera), target_backward) <= REVERSE_TOLERANCE_DEG,
		"rear.direction_reversed",
		"%s vs %s" % [_forward(camera), target_backward]
	)
	_check(_rig.get_mode() == CameraRig.Mode.CHASE, "rear.mode_unchanged", str(_rig.get_mode()))
	_check(
		_up_close_to_expected_stabilized_up(camera),
		"rear.up_stabilized",
		str(_up(camera))
	)

	_rig.hold_rear(false)
	_check(not _rig.is_rear_held(), "rear.state_released", "")
	_check(_rig.get_camera() == node_before, "rear.restore_same_node", "camera node replaced")
	_check(_count_cameras(_rig) == 1, "rear.restore_single_camera", str(_count_cameras(_rig)))
	_check(
		_vec_close(camera.global_transform.origin, position_before, POSE_TOLERANCE),
		"rear.restore_position",
		str(camera.global_transform.origin)
	)
	_check(
		_angle_deg(_forward(camera), target_forward) <= DIRECTION_TOLERANCE_DEG,
		"rear.restore_direction",
		"%s vs %s" % [_forward(camera), target_forward]
	)

	# Hood rear view redirects the same forward-mode camera backwards too.
	_rig.select_mode(CameraRig.Mode.HOOD)
	_rig.snap_to_target()
	var hood_forward := (
		(target_transform * EXPECTED_HOOD_LOOK_OFFSET)
		- (target_transform * EXPECTED_HOOD_OFFSET)
	).normalized()
	position_before = camera.global_transform.origin
	_rig.hold_rear(true)
	_check(_rig.get_camera() == node_before, "rear.hood_same_node", "camera node replaced")
	_check(
		_angle_deg(_forward(camera), target_backward) <= REVERSE_TOLERANCE_DEG,
		"rear.hood_direction_reversed",
		"%s vs %s" % [_forward(camera), target_backward]
	)
	_check(
		_vec_close(camera.global_transform.origin, position_before, POSE_TOLERANCE),
		"rear.hood_position_kept",
		str(camera.global_transform.origin)
	)
	_rig.hold_rear(false)
	_check(
		_angle_deg(_forward(camera), hood_forward) <= DIRECTION_TOLERANCE_DEG,
		"rear.hood_restore_direction",
		"%s vs %s" % [_forward(camera), hood_forward]
	)


func _check_target_safety() -> void:
	_apply_target(Transform3D.IDENTITY)
	_rig.select_mode(CameraRig.Mode.CHASE)
	_rig.snap_to_target()
	var camera := _rig.get_camera()
	var last_pose := camera.global_transform

	_rig.clear_target()
	_rig.update_target_pose(0.0)
	_check(_rig.get_target_state() == CameraRig.TargetState.NO_TARGET, "safety.clear_state", str(_rig.get_target_state()))
	_check(not _rig.has_valid_target(), "safety.clear_invalid", "")
	_check(_finite_transform(camera.global_transform), "safety.missing_finite", str(camera.global_transform))
	_check(_transforms_equal(camera.global_transform, last_pose, 0.0), "safety.missing_pose_kept", "pose changed")

	_rig.update_target_pose(1.0 / 60.0)
	_check(_transforms_equal(camera.global_transform, last_pose, 0.0), "safety.missing_update_noop", "pose changed")

	# Explicit nonfinite pose is rejected.
	var nan_pose := Transform3D(Basis.IDENTITY, Vector3(NAN, 0.0, 0.0))
	_check(not _rig.set_target_pose(nan_pose), "safety.nan_pose_refused", "")
	_check(_rig.get_target_state() == CameraRig.TargetState.INVALID, "safety.nan_pose_state", str(_rig.get_target_state()))
	_check(_transforms_equal(camera.global_transform, last_pose, 0.0), "safety.nan_pose_camera_kept", "pose changed")

	# A nonfinite target node is rejected.
	var bad_target := Node3D.new()
	bad_target.name = "CameraLabBadTarget"
	root.add_child(bad_target)
	bad_target.transform = Transform3D(
		Basis(Vector3(INF, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0)),
		Vector3.ZERO
	)
	_check(not _rig.set_target(bad_target), "safety.bad_node_refused", "")
	_check(_rig.get_target_state() == CameraRig.TargetState.INVALID, "safety.bad_node_state", str(_rig.get_target_state()))
	_check(_transforms_equal(camera.global_transform, last_pose, 0.0), "safety.bad_node_camera_kept", "pose changed")
	bad_target.queue_free()

	# Restoring a valid target resumes following.
	_apply_target(Transform3D(Basis(Vector3.UP, deg_to_rad(20.0)), Vector3(1.0, 0.0, 1.0)))
	_check(_rig.has_valid_target(), "safety.restore_valid", "")
	_check(_rig.get_target_state() == CameraRig.TargetState.OK, "safety.restore_state", str(_rig.get_target_state()))
	_rig.snap_to_target()
	_check(
		_vec_close(
			camera.global_transform.origin,
			Transform3D(Basis(Vector3.UP, deg_to_rad(20.0)), Vector3(1.0, 0.0, 1.0)) * EXPECTED_CHASE_OFFSET,
			VECTOR_TOLERANCE
		),
		"safety.restore_follows",
		str(camera.global_transform.origin)
	)

	_check(_rig.set_target(null), "safety.null_clears", "")
	_check(_rig.get_target_state() == CameraRig.TargetState.NO_TARGET, "safety.null_state", str(_rig.get_target_state()))


func _check_off_tree_target() -> void:
	var spare := Node3D.new()
	spare.name = "CameraLabSpareTarget"
	root.add_child(spare)
	spare.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(15.0)), Vector3(2.0, 0.5, -1.0))
	_check(_rig.set_target(spare), "offtree.valid_target_accepted", "")
	_rig.snap_to_target()
	var camera := _rig.get_camera()
	var pose_before := camera.global_transform

	# A target outside the scene tree has no world pose; following must stop
	# and keep the last safe camera transform.
	root.remove_child(spare)
	_rig.update_target_pose(0.0)
	_check(
		_rig.get_target_state() == CameraRig.TargetState.NO_TARGET,
		"offtree.removed_state",
		str(_rig.get_target_state())
	)
	_check(
		_transforms_equal(camera.global_transform, pose_before, 0.0),
		"offtree.removed_camera_kept",
		"camera changed while target was off-tree"
	)

	root.add_child(spare)
	_rig.update_target_pose(0.0)
	_check(_rig.has_valid_target(), "offtree.readded_resumes", "")
	_check(_rig.get_target_state() == CameraRig.TargetState.OK, "offtree.readded_state", str(_rig.get_target_state()))
	_rig.clear_target()

	# A supplied but never-added node is rejected outright.
	var unattached := Node3D.new()
	_check(not _rig.set_target(unattached), "offtree.unattached_refused", "")
	_check(
		_rig.get_target_state() == CameraRig.TargetState.INVALID,
		"offtree.unattached_state",
		str(_rig.get_target_state())
	)
	unattached.free()


func _check_nonfinite_inputs() -> void:
	var mode: CameraRig.Mode = CameraRig.Mode.CHASE
	var fov_before := _rig.get_fov_preference(mode)
	_check(not _rig.set_fov_preference(mode, NAN), "input.fov_nan_refused", "")
	_check(not _rig.set_fov_preference(mode, INF), "input.fov_inf_refused", "")
	_check(absf(_rig.get_fov_preference(mode) - fov_before) <= 1e-9, "input.fov_unchanged", "")

	var offset_before := _rig.get_mode_offset(mode)
	_check(not _rig.set_mode_offset(mode, Vector3(NAN, 0.0, 0.0)), "input.offset_nan_refused", "")
	_check(not _rig.set_mode_offset(mode, Vector3(INF, 0.0, 0.0)), "input.offset_inf_refused", "")
	_check(_vec_close(_rig.get_mode_offset(mode), offset_before, 0.0), "input.offset_unchanged", "")

	var look_before := _rig.get_mode_look_offset(mode)
	_check(not _rig.set_mode_look_offset(mode, Vector3(0.0, NAN, 0.0)), "input.look_nan_refused", "")
	_check(_vec_close(_rig.get_mode_look_offset(mode), look_before, 0.0), "input.look_unchanged", "")

	var response_before := _rig.get_smoothing_response_seconds()
	_check(not _rig.set_smoothing_response_seconds(NAN), "input.smooth_nan_refused", "")
	_check(not _rig.set_smoothing_response_seconds(0.0), "input.smooth_zero_refused", "")
	_check(
		absf(_rig.get_smoothing_response_seconds() - response_before) <= 1e-9,
		"input.smooth_unchanged",
		""
	)

	var inf_basis_pose := Transform3D(
		Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, INF)),
		Vector3.ZERO
	)
	_check(not _rig.set_target_pose(inf_basis_pose), "input.pose_inf_basis_refused", "")
	_check(_rig.get_target_state() == CameraRig.TargetState.INVALID, "input.pose_inf_state", str(_rig.get_target_state()))

	# A finite explicit pose is accepted again afterwards.
	_check(_rig.set_target_pose(Transform3D.IDENTITY), "input.valid_pose_restored", "")


func _check_determinism() -> void:
	var pose := Transform3D(
		Basis(Vector3.UP, deg_to_rad(-40.0)) * Basis(Vector3.RIGHT, deg_to_rad(8.0)),
		Vector3(3.0, 1.5, -9.0)
	)
	_rig.set_target_pose(pose)
	_rig.snap_to_target()
	var first := _rig.get_camera().global_transform
	_rig.snap_to_target()
	var repeated := _rig.get_camera().global_transform
	_check(_transforms_equal(first, repeated, 0.0), "determinism.repeated_snap", "second snap differs")

	_aux.set_target_pose(pose)
	_aux.snap_to_target()
	var second_rig := _aux.get_camera().global_transform
	_check(_transforms_equal(first, second_rig, POSE_TOLERANCE), "determinism.two_instances", "instances differ")

	_rig.update_target_pose(0.0)
	_check(_transforms_equal(first, _rig.get_camera().global_transform, 0.0), "determinism.delta_zero_equals_snap", "")
	_check(_finite_transform(_rig.get_camera().global_transform), "determinism.finite", "")


func _check_smoothing_direction() -> void:
	# Dedicated auxiliary rig so the main rig stays deterministic.
	_oracle.set_target(_target)
	_oracle.select_mode(CameraRig.Mode.CHASE)
	_oracle.snap_to_target()

	_aux.set_smoothing_enabled(true)
	_aux.set_smoothing_response_seconds(0.08)
	_aux.select_mode(CameraRig.Mode.CHASE)
	_aux.set_target(_target)
	_aux.snap_to_target()

	var start_transform := Transform3D(Basis(Vector3.UP, deg_to_rad(10.0)), Vector3(1.0, 2.0, 3.0))
	_target.transform = start_transform
	_aux.update_target_pose(0.0)
	_oracle.snap_to_target()
	var start_forward := _forward(_oracle.get_camera())

	var final_transform := Transform3D(Basis(Vector3.UP, deg_to_rad(80.0)), Vector3(20.0, 4.0, -12.0))
	_target.transform = final_transform
	var target_before := _target.transform
	_oracle.snap_to_target()
	var final_forward := _forward(_oracle.get_camera())

	var direction_hidden := false
	var nonfinite_seen := false
	for _frame in range(120):
		_aux.update_target_pose(1.0 / 60.0)
		var forward := _forward(_aux.get_camera())
		if not _finite_vec(forward):
			nonfinite_seen = true
		if forward.dot(final_forward) < -1e-6:
			direction_hidden = true
	_check(not nonfinite_seen, "smoothing.no_nonfinite_camera", "")
	_check(not direction_hidden, "smoothing.direction_never_hidden", "camera crossed behind the target")
	_check(
		_angle_deg(_forward(_aux.get_camera()), final_forward) <= SMOOTHING_SETTLE_DEG,
		"smoothing.converges",
		str(_angle_deg(_forward(_aux.get_camera()), final_forward))
	)
	_check(
		_transforms_equal(_target.transform, target_before, 0.0),
		"smoothing.target_immutable",
		"smoothing moved the target"
	)
	_check(
		start_forward.dot(Vector3(0.0, 0.0, -1.0)) > 0.0,
		"smoothing.start_forward_sane",
		str(start_forward)
	)

	# Smoothing off snaps immediately to the final pose.
	_aux.set_smoothing_enabled(false)
	_aux.update_target_pose(1.0 / 60.0)
	_check(
		_angle_deg(_forward(_aux.get_camera()), final_forward) <= POSE_TOLERANCE,
		"smoothing.off_snaps",
		str(_forward(_aux.get_camera()))
	)


func _check_viewport_attach_detach() -> void:
	# Positive headless SubViewport check: attach must reparent the single
	# owned camera into that viewport, make it current there, leave the target
	# untouched, add no second camera or viewport, and detach must deactivate.
	# No rendered image or four-player evidence is claimed.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 64)
	root.add_child(viewport)

	var rig: CameraRig = CameraRigScript.new()
	root.add_child(rig)
	var target_transform := Transform3D(
		Basis(Vector3.UP, deg_to_rad(-25.0)),
		Vector3(5.0, 2.0, -4.0)
	)
	_target.transform = target_transform
	var target_before := _target.transform
	_check(rig.set_target(_target), "viewport.target_accepted", "")
	rig.snap_to_target()

	var camera: Camera3D = rig.get_camera()
	var viewports_before := _count_subviewports(root)
	_check(_count_cameras(rig) == 1, "viewport.single_camera_owned", str(_count_cameras(rig)))

	_check(rig.attach_to_viewport(viewport), "viewport.attach_succeeded", "")
	_check(rig.get_parent() == viewport, "viewport.rig_reparented", str(rig.get_parent()))
	_check(camera.current, "viewport.camera_current", "")
	_check(
		viewport.get_camera_3d() == camera,
		"viewport.viewport_active_camera",
		str(viewport.get_camera_3d())
	)
	_check(_count_cameras(rig) == 1, "viewport.still_single_camera", str(_count_cameras(rig)))
	_check(viewport.get_child_count() == 1, "viewport.no_extra_children", str(viewport.get_child_count()))
	_check(
		_count_subviewports(root) == viewports_before,
		"viewport.no_extra_viewport",
		"%d vs %d" % [_count_subviewports(root), viewports_before]
	)

	rig.update_target_pose(0.0)
	_check(
		_transforms_equal(_target.transform, target_before, 0.0),
		"viewport.target_immutable",
		"attach/update moved the target"
	)
	_check(
		_finite_transform(camera.global_transform),
		"viewport.camera_finite_after_update",
		str(camera.global_transform)
	)

	rig.detach_from_viewport()
	_check(not camera.current, "viewport.camera_deactivated", "")
	_check(
		viewport.get_camera_3d() == null,
		"viewport.active_camera_cleared",
		str(viewport.get_camera_3d())
	)
	_check(rig.get_parent() == null, "viewport.rig_detached", str(rig.get_parent()))

	rig.free()
	viewport.free()


func _check_degenerate_and_scaled_targets() -> void:
	# Establish a usable camera pose that every rejection must preserve.
	_apply_target(Transform3D.IDENTITY)
	_rig.select_mode(CameraRig.Mode.CHASE)
	_rig.snap_to_target()
	var camera := _rig.get_camera()
	var good_pose := camera.global_transform
	var zero_basis := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)

	_check(
		not _rig.set_target_pose(Transform3D(zero_basis, Vector3.ZERO)),
		"degenerate.zero_explicit_refused",
		""
	)
	_check(
		_rig.get_target_state() == CameraRig.TargetState.INVALID,
		"degenerate.zero_explicit_state",
		str(_rig.get_target_state())
	)
	_check(
		_transforms_equal(camera.global_transform, good_pose, 0.0),
		"degenerate.zero_explicit_camera_kept",
		"camera changed on rejected pose"
	)

	var collinear := Basis(
		Vector3(1.0, 0.0, 0.0),
		Vector3(2.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 1.0)
	)
	_check(
		not _rig.set_target_pose(Transform3D(collinear, Vector3(1.0, 2.0, 3.0))),
		"degenerate.collinear_explicit_refused",
		""
	)
	_check(
		_rig.get_target_state() == CameraRig.TargetState.INVALID,
		"degenerate.collinear_state",
		str(_rig.get_target_state())
	)
	_check(
		_transforms_equal(camera.global_transform, good_pose, 0.0),
		"degenerate.collinear_camera_kept",
		"camera changed on rejected pose"
	)

	var bad_node := Node3D.new()
	bad_node.name = "CameraLabZeroBasisTarget"
	root.add_child(bad_node)
	bad_node.transform = Transform3D(zero_basis, Vector3.ZERO)
	_check(not _rig.set_target(bad_node), "degenerate.zero_node_refused", "")
	_check(
		_rig.get_target_state() == CameraRig.TargetState.INVALID,
		"degenerate.zero_node_state",
		str(_rig.get_target_state())
	)
	_check(
		_transforms_equal(camera.global_transform, good_pose, 0.0),
		"degenerate.zero_node_camera_kept",
		"camera changed on rejected node"
	)
	bad_node.queue_free()

	# Mid-follow degeneration and recovery.
	var live_target := Node3D.new()
	live_target.name = "CameraLabScaledTarget"
	root.add_child(live_target)
	var live := Transform3D(
		Basis(Vector3.UP, deg_to_rad(30.0)),
		Vector3(4.0, 1.0, -2.0)
	)
	live_target.transform = live
	_check(_rig.set_target(live_target), "degenerate.live_target_accepted", "")
	_rig.snap_to_target()
	var stable_pose := camera.global_transform

	live_target.transform = Transform3D(zero_basis, Vector3.ZERO)
	_rig.update_target_pose(0.0)
	_check(
		_rig.get_target_state() == CameraRig.TargetState.INVALID,
		"degenerate.mid_follow_state",
		str(_rig.get_target_state())
	)
	_check(
		_finite_transform(camera.global_transform),
		"degenerate.mid_follow_finite",
		str(camera.global_transform)
	)
	_check(
		_transforms_equal(camera.global_transform, stable_pose, 0.0),
		"degenerate.mid_follow_camera_kept",
		"collapsed target changed the camera"
	)

	live_target.transform = live
	_rig.update_target_pose(0.0)
	_check(_rig.has_valid_target(), "degenerate.recovery_valid", "")
	_check(
		_rig.get_target_state() == CameraRig.TargetState.OK,
		"degenerate.recovery_state",
		str(_rig.get_target_state())
	)
	_check(
		_is_orthonormal_camera(camera),
		"degenerate.recovery_orthonormal",
		str(camera.global_transform.basis)
	)
	_check(
		_vec_close(camera.global_transform.origin, live * EXPECTED_CHASE_OFFSET, VECTOR_TOLERANCE),
		"degenerate.recovery_position",
		str(camera.global_transform.origin)
	)

	# Uniformly scaled targets: accepted, offsets follow the scaled frame,
	# direction is scale-independent and the camera basis stays orthonormal in
	# both forward and rear modes.
	for scale_value in [2.5, 0.5]:
		var scale_label := str(scale_value)
		var scaled := Transform3D(
			Basis(
				Vector3(scale_value, 0.0, 0.0),
				Vector3(0.0, scale_value, 0.0),
				Vector3(0.0, 0.0, scale_value)
			),
			Vector3(3.0 * scale_value, scale_value, -2.0 * scale_value)
		)
		live_target.transform = scaled
		_rig.hold_rear(false)
		_rig.update_target_pose(0.0)
		_check(_rig.has_valid_target(), "scaled.%s.accepted" % scale_label, "")
		_check(
			_finite_transform(camera.global_transform),
			"scaled.%s.forward_finite" % scale_label,
			str(camera.global_transform)
		)
		_check(
			_is_orthonormal_camera(camera),
			"scaled.%s.forward_orthonormal" % scale_label,
			str(camera.global_transform.basis)
		)
		var expected_position: Vector3 = scaled * EXPECTED_CHASE_OFFSET
		_check(
			_vec_close(
				camera.global_transform.origin,
				expected_position,
				VECTOR_TOLERANCE * maxf(1.0, scale_value)
			),
			"scaled.%s.forward_offset" % scale_label,
			"%s vs %s" % [camera.global_transform.origin, expected_position]
		)
		var expected_forward: Vector3 = (
			(scaled * EXPECTED_CHASE_LOOK_OFFSET) - expected_position
		).normalized()
		_check(
			_angle_deg(_forward(camera), expected_forward) <= DIRECTION_TOLERANCE_DEG,
			"scaled.%s.forward_direction" % scale_label,
			"%s vs %s" % [_forward(camera), expected_forward]
		)

		_rig.hold_rear(true)
		_rig.update_target_pose(0.0)
		_check(
			_is_orthonormal_camera(camera),
			"scaled.%s.rear_orthonormal" % scale_label,
			str(camera.global_transform.basis)
		)
		_check(
			_angle_deg(_forward(camera), scaled.basis.z.normalized()) <= DIRECTION_TOLERANCE_DEG,
			"scaled.%s.rear_direction" % scale_label,
			"%s vs %s" % [_forward(camera), scaled.basis.z.normalized()]
		)
		_rig.hold_rear(false)

	live_target.queue_free()

	# Resulting-camera boundary: even if the refinement seam returns a collapsed
	# pose, assignment must be refused and the previous camera must remain.
	var collapsing := CollapsingCameraRig.new()
	root.add_child(collapsing)
	var collapsing_camera := collapsing.get_camera()
	var collapsing_initial := collapsing_camera.global_transform
	var valid_pose := Transform3D(Basis(Vector3.UP, 1.0), Vector3(1.0, 2.0, 3.0))
	_check(collapsing.set_target_pose(valid_pose), "output.valid_input_accepted", "")
	collapsing.snap_to_target()
	_check(
		_transforms_equal(collapsing_camera.global_transform, collapsing_initial, 0.0),
		"output.collapsed_basis_refused",
		"collapsed seam pose was assigned"
	)
	_check(
		_finite_transform(collapsing_camera.global_transform),
		"output.collapsed_basis_finite",
		str(collapsing_camera.global_transform)
	)
	_check(
		_is_orthonormal_camera(collapsing_camera),
		"output.collapsed_basis_kept_usable",
		str(collapsing_camera.global_transform.basis)
	)
	collapsing.free()


# --- Helpers ---------------------------------------------------------------


func _mode_at(index: int) -> CameraRig.Mode:
	match index:
		0:
			return CameraRig.Mode.CHASE
		1:
			return CameraRig.Mode.NEAR_CHASE
		2:
			return CameraRig.Mode.HOOD
	return CameraRig.Mode.CHASE


func _apply_target(transform: Transform3D) -> bool:
	_target.transform = transform
	return _rig.set_target(_target)


func _count_cameras(node: Node) -> int:
	var count := 0
	if node is Camera3D:
		count += 1
	for child in node.get_children():
		count += _count_cameras(child)
	return count


func _is_orthonormal_camera(camera: Camera3D) -> bool:
	return _is_orthonormal_basis(camera.global_transform.basis)


func _is_orthonormal_basis(basis: Basis) -> bool:
	var x := basis.x
	var y := basis.y
	var z := basis.z
	if not (_finite_vec(x) and _finite_vec(y) and _finite_vec(z)):
		return false
	var tolerance := 1e-6
	if absf(x.length_squared() - 1.0) > tolerance:
		return false
	if absf(y.length_squared() - 1.0) > tolerance:
		return false
	if absf(z.length_squared() - 1.0) > tolerance:
		return false
	if absf(x.dot(y)) > tolerance or absf(x.dot(z)) > tolerance or absf(y.dot(z)) > tolerance:
		return false
	return true


func _count_subviewports(node: Node) -> int:
	var count := 0
	if node is SubViewport:
		count += 1
	for child in node.get_children():
		count += _count_subviewports(child)
	return count


func _forward(camera: Camera3D) -> Vector3:
	return (-camera.global_transform.basis.z).normalized()


func _up(camera: Camera3D) -> Vector3:
	return camera.global_transform.basis.y.normalized()


func _right(camera: Camera3D) -> Vector3:
	return camera.global_transform.basis.x.normalized()


func _up_close_to_expected_stabilized_up(camera: Camera3D) -> bool:
	return _vec_close(_up(camera), _expected_stabilized_up(_forward(camera)), UP_TOLERANCE)


func _expected_stabilized_up(forward: Vector3) -> Vector3:
	var f := forward.normalized()
	var projection := Vector3.UP - f * Vector3.UP.dot(f)
	if projection.length_squared() <= 1e-12:
		return Vector3.ZERO
	return projection.normalized()


func _vec_close(a: Vector3, b: Vector3, tolerance: float) -> bool:
	return a.distance_to(b) <= tolerance


func _angle_deg(a: Vector3, b: Vector3) -> float:
	if a.length_squared() <= 1e-12 or b.length_squared() <= 1e-12:
		return INF
	return rad_to_deg(a.angle_to(b))


func _transforms_equal(a: Transform3D, b: Transform3D, tolerance: float) -> bool:
	return (
		_vec_close(a.origin, b.origin, tolerance)
		and _vec_close(a.basis.x, b.basis.x, tolerance)
		and _vec_close(a.basis.y, b.basis.y, tolerance)
		and _vec_close(a.basis.z, b.basis.z, tolerance)
	)


func _finite_vec(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _finite_transform(transform: Transform3D) -> bool:
	return (
		_finite_vec(transform.origin)
		and _finite_vec(transform.basis.x)
		and _finite_vec(transform.basis.y)
		and _finite_vec(transform.basis.z)
	)


func _has_user_flag(flag: String) -> bool:
	return flag in OS.get_cmdline_user_args()


func _check(ok: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if not ok:
		if detail.is_empty():
			_failures.append(label)
		else:
			_failures.append("%s (%s)" % [label, detail])


func _record_failure(label: String, detail: String) -> void:
	_check(false, label, detail)


func _check_engine() -> void:
	var version: Dictionary = Engine.get_version_info()
	_check(version["major"] == EXPECTED_MAJOR, "engine.major", str(version["major"]))
	_check(version["minor"] == EXPECTED_MINOR, "engine.minor", str(version["minor"]))
	_check(version["patch"] == EXPECTED_PATCH, "engine.patch", str(version["patch"]))
	_check(version["status"] == EXPECTED_STATUS, "engine.status", str(version["status"]))
	_check(version["build"] == EXPECTED_BUILD, "engine.build", str(version["build"]))
	_check(
		String(version["hash"]).begins_with(EXPECTED_COMMIT_PREFIX),
		"engine.commit",
		str(version["hash"])
	)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	var report := {
		"schema": "roadstorm.camera_lab.validation.v1",
		"component": RIG_SCRIPT_PATH,
		"backend": str(ProjectSettings.get_setting("physics/3d/physics_engine")),
		"engine_version": Engine.get_version_info(),
		"checks_total": _checks,
		"checks_failed": _failures.size(),
		"failures": _failures,
		"measured": _measured,
		"limitations": [
			"Headless dummy display/audio drivers; no rendering, visual comfort or device verification.",
			"One in-tree SubViewport attach/detach is checked structurally; no rendered split-screen layout or four-player cost is verified.",
			"All offsets, look points and FOVs are provisional M1.5 authored values, not tuned presentation constants.",
			"Wall avoidance, corner look-ahead and comfort/shake/drift rotation are unimplemented seams; this suite does not claim them.",
			"No four-player cost, integrated race-camera or M1.5/M1 acceptance claim; the coordinator integrates the component.",
		],
	}
	print("CAM_RESULT ", JSON.stringify(report))
	print("CHECKS_TOTAL=", _checks, " CHECKS_FAILED=", _failures.size())
	quit(1 if _failures.size() > 0 else 0)
