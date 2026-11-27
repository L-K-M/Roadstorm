class_name CameraRig
extends Node3D
## Presentation-only camera rig for one eventual local player slot (M1.5).
##
## PLAN.md M1.5 slice: chase, near-chase and hood placement, a momentary rear
## view and a per-slot FOV preference, all on one shared-world camera. This is an
## M1.5 component, not an integrated race camera: it has no route knowledge, no
## wall avoidance, no corner look-ahead, no comfort/shake tuning, no input
## mapping and no claim about four-player cost or actual-device behaviour.
##
## Ownership: the rig creates and owns exactly one `Camera3D` child. Slot code
## attaches the rig to a slot viewport with `attach_to_viewport()`, feeds the
## slot's visual target with `set_target()`/`set_target_pose()`, and drives it
## once per rendered frame with `update_target_pose()`. The rig never moves or
## rotates its target and never writes simulation state; it only assigns its own
## camera transform.
##
## Frame convention: local +Y up, -Z forward, +X right. Horizon stabilization
## builds the camera basis from the world +Y axis, so target bank/roll does not
## roll the camera. Every offset and FOV default below is provisional authored
## M1.5 values; they are runtime-configurable and must be tuned against
## playtesting before M3/M8 freezes presentation.
##
## Determinism: smoothing is opt-in and disabled by default. With smoothing
## disabled, or when `snap_to_target()` is used, a given target transform
## produces the same camera transform on every run.

enum Mode {
	CHASE = 0,
	NEAR_CHASE = 1,
	HOOD = 2,
}

enum TargetState {
	NO_TARGET = 0,
	OK = 1,
	INVALID = 2,
}

const MODE_COUNT := 3

## User-facing FOV preference bounds. These bound a preference, not a validated
## comfort envelope.
const MIN_FOV_DEGREES := 30.0
const MAX_FOV_DEGREES := 120.0

const MIN_SMOOTHING_RESPONSE_S := 0.01
const DEFAULT_SMOOTHING_RESPONSE_S := 0.12

## Squared-length guard for degenerate look directions.
const DIRECTION_EPSILON_SQ := 1e-12

const WORLD_UP := Vector3.UP

## Provisional authored offsets in the target's local frame (+Y up, -Z forward,
## +X right): chase sits behind/above, near chase is closer, hood is ahead of
## the origin at dash height. Configurable at runtime.
const DEFAULT_OFFSETS: Array[Vector3] = [
	Vector3(0.0, 2.8, 7.2), # CHASE
	Vector3(0.0, 1.5, 4.0), # NEAR_CHASE
	Vector3(0.0, 1.05, -1.1), # HOOD
]

## Provisional look points in the target's local frame. They bias the camera
## slightly ahead of the car without any route knowledge.
const DEFAULT_LOOK_OFFSETS: Array[Vector3] = [
	Vector3(0.0, 1.2, -6.0), # CHASE
	Vector3(0.0, 1.0, -6.0), # NEAR_CHASE
	Vector3(0.0, 0.9, -8.0), # HOOD
]

const DEFAULT_FOVS: Array[float] = [70.0, 75.0, 80.0]

const MODE_NAMES: Array[String] = ["chase", "near_chase", "hood"]

var _mode: Mode = Mode.CHASE
var _offsets: Array[Vector3] = []
var _look_offsets: Array[Vector3] = []
var _fovs: Array[float] = []
var _target: Node3D = null
var _explicit_pose: Transform3D = Transform3D.IDENTITY
var _has_explicit_pose := false
var _last_pose: Transform3D = Transform3D.IDENTITY
var _target_state: TargetState = TargetState.NO_TARGET
var _rear_held := false
var _smoothing_enabled := false
var _smoothing_response_s := DEFAULT_SMOOTHING_RESPONSE_S
var _camera: Camera3D = null


func _init() -> void:
	_reset_mode_arrays()


func _ready() -> void:
	_ensure_camera()


# --- Slot-facing API -------------------------------------------------------


## Attaches this rig (and its single camera) to a slot viewport's scene tree.
## Returns false and changes nothing when the viewport is absent or not in the
## tree. The camera becomes current in that viewport.
func attach_to_viewport(viewport: Viewport) -> bool:
	if viewport == null or not viewport.is_inside_tree():
		return false
	if get_parent() != viewport:
		var parent := get_parent()
		if parent != null:
			parent.remove_child(self)
		viewport.add_child(self)
	_ensure_camera().current = true
	return true


## Removes the rig from its parent and deactivates its camera. Slot teardown
## only; no viewport state is invented here.
func detach_from_viewport() -> void:
	if _camera != null and is_instance_valid(_camera):
		_camera.current = false
	var parent := get_parent()
	if parent != null:
		parent.remove_child(self)


## Selects a mode. Invalid enum values are refused and leave the mode unchanged.
func select_mode(mode: Mode) -> bool:
	if not _valid_mode(mode):
		return false
	_mode = mode
	_apply_fov_to_camera()
	if has_valid_target():
		update_target_pose(0.0)
	return true


## Advances CHASE -> NEAR_CHASE -> HOOD -> CHASE and returns the new mode.
func cycle_mode() -> Mode:
	var next := ((_mode + 1) % MODE_COUNT) as Mode
	select_mode(next)
	return _mode


func get_mode() -> Mode:
	return _mode


func get_mode_name(mode: Mode) -> String:
	if not _valid_mode(mode):
		return ""
	return MODE_NAMES[mode]


## Follows a visual target node. The node is never moved or rotated. A null
## target clears the follow state. Nonfinite target transforms are rejected
## and leave the rig's last safe camera pose untouched.
func set_target(target: Node3D) -> bool:
	if target == null:
		clear_target()
		return true
	if not is_instance_valid(target) or not target.is_inside_tree():
		_target = null
		_has_explicit_pose = false
		_target_state = TargetState.INVALID
		return false
	var pose := target.global_transform
	if not _is_finite_transform(pose):
		_target = null
		_has_explicit_pose = false
		_target_state = TargetState.INVALID
		return false
	_target = target
	_has_explicit_pose = false
	_last_pose = pose
	_target_state = TargetState.OK
	update_target_pose(0.0)
	return true


## Supplies the target pose explicitly instead of following a node. Rejects
## nonfinite transforms without touching the camera.
func set_target_pose(pose: Transform3D) -> bool:
	if not _is_finite_transform(pose):
		_target = null
		_has_explicit_pose = false
		_target_state = TargetState.INVALID
		return false
	_target = null
	_has_explicit_pose = true
	_explicit_pose = pose
	_last_pose = pose
	_target_state = TargetState.OK
	update_target_pose(0.0)
	return true


## Drops the target. The rig keeps its last valid finite camera pose and stops
## following; it does not emit nonfinite state.
func clear_target() -> void:
	_target = null
	_has_explicit_pose = false
	_target_state = TargetState.NO_TARGET


func has_valid_target() -> bool:
	return _target_state == TargetState.OK


func get_target_state() -> TargetState:
	return _target_state


func get_target_node() -> Node3D:
	return _target


## Momentary rear view. While held, the same camera node redirects backwards
## from its current mode position; releasing restores the selected forward
## mode. No second camera or viewport is created.
func hold_rear(active: bool) -> void:
	if _rear_held == active:
		return
	_rear_held = active
	update_target_pose(0.0)


func is_rear_held() -> bool:
	return _rear_held


## Clamps a finite user FOV preference into [MIN_FOV_DEGREES, MAX_FOV_DEGREES].
## Nonfinite preferences are refused and leave the stored value unchanged.
func set_fov_preference(mode: Mode, fov_degrees: float) -> bool:
	if not _valid_mode(mode):
		return false
	if not is_finite(fov_degrees):
		return false
	_fovs[mode] = clampf(fov_degrees, MIN_FOV_DEGREES, MAX_FOV_DEGREES)
	if mode == _mode:
		_apply_fov_to_camera()
	return true


func get_fov_preference(mode: Mode) -> float:
	if not _valid_mode(mode):
		return -1.0
	return _fovs[mode]


func set_mode_offset(mode: Mode, offset: Vector3) -> bool:
	if not _valid_mode(mode) or not _is_finite_vec(offset):
		return false
	_offsets[mode] = offset
	if mode == _mode and has_valid_target():
		update_target_pose(0.0)
	return true


func get_mode_offset(mode: Mode) -> Vector3:
	if not _valid_mode(mode):
		return Vector3.ZERO
	return _offsets[mode]


func set_mode_look_offset(mode: Mode, offset: Vector3) -> bool:
	if not _valid_mode(mode) or not _is_finite_vec(offset):
		return false
	_look_offsets[mode] = offset
	if mode == _mode and has_valid_target():
		update_target_pose(0.0)
	return true


func get_mode_look_offset(mode: Mode) -> Vector3:
	if not _valid_mode(mode):
		return Vector3.ZERO
	return _look_offsets[mode]


## Restores the provisional authored offsets and FOV defaults.
func reset_mode_configuration() -> void:
	_reset_mode_arrays()
	_apply_fov_to_camera()
	if has_valid_target():
		update_target_pose(0.0)


## Smoothing is opt-in and off by default. When enabled it only interpolates
## toward the computed pose; it never changes the target or hides its forward
## direction. Snap/test consumers keep it off or call `snap_to_target()`.
func set_smoothing_enabled(enabled: bool) -> void:
	_smoothing_enabled = enabled


func is_smoothing_enabled() -> bool:
	return _smoothing_enabled


func set_smoothing_response_seconds(response_s: float) -> bool:
	if not is_finite(response_s) or response_s < MIN_SMOOTHING_RESPONSE_S:
		return false
	_smoothing_response_s = response_s
	return true


func get_smoothing_response_seconds() -> float:
	return _smoothing_response_s


func get_camera() -> Camera3D:
	return _ensure_camera()


## Per-frame entry point. Reads the current target pose, refuses invalid or
## missing targets (leaving the last safe camera pose untouched), computes the
## desired pose and either snaps or smooths toward it.
func update_target_pose(delta: float = 0.0) -> void:
	if not _refresh_pose():
		return
	var desired := _desired_camera_transform()
	if _smoothing_enabled and is_finite(delta) and delta > 0.0:
		_apply_smoothed(desired, delta)
	else:
		_assign_camera_transform(desired)


## Deterministic immediate placement: no smoothing and no dependence on frame
## timing. Safe to call from tests and replays.
func snap_to_target() -> void:
	update_target_pose(0.0)


# --- Internals -------------------------------------------------------------


func _reset_mode_arrays() -> void:
	_offsets.assign(DEFAULT_OFFSETS)
	_look_offsets.assign(DEFAULT_LOOK_OFFSETS)
	_fovs.assign(DEFAULT_FOVS)


func _valid_mode(mode: int) -> bool:
	return mode >= 0 and mode < MODE_COUNT


func _ensure_camera() -> Camera3D:
	if _camera == null or not is_instance_valid(_camera):
		var created := Camera3D.new()
		created.name = "SlotCamera"
		add_child(created)
		_camera = created
		_apply_fov_to_camera()
	return _camera


func _apply_fov_to_camera() -> void:
	_ensure_camera().fov = clampf(_fovs[_mode], MIN_FOV_DEGREES, MAX_FOV_DEGREES)


func _refresh_pose() -> bool:
	var pose: Transform3D
	if _has_explicit_pose:
		pose = _explicit_pose
	elif _target != null and is_instance_valid(_target):
		if not _target.is_inside_tree():
			_target_state = TargetState.NO_TARGET
			return false
		pose = _target.global_transform
		if not _is_finite_transform(pose):
			_target_state = TargetState.INVALID
			return false
	else:
		_target_state = TargetState.NO_TARGET
		return false
	_last_pose = pose
	_target_state = TargetState.OK
	return true


## SEAM (unimplemented, M3/M8): future wall avoidance, corner look-ahead and
## comfort tuning (shake, drift rotation) hook into this method. It currently
## returns the desired pose unchanged, so no unimplemented feature is claimed.
func refine_desired_pose(desired: Transform3D, _delta: float) -> Transform3D:
	return desired


func _desired_camera_transform() -> Transform3D:
	var target_pose := _last_pose
	var camera_position := target_pose * _offsets[_mode]
	var look_point := target_pose * _look_offsets[_mode]

	var forward: Vector3
	if _rear_held:
		# Rear view looks along the target's backward axis (+Z local).
		forward = target_pose.basis.z
	else:
		forward = look_point - camera_position
		if forward.length_squared() < DIRECTION_EPSILON_SQ:
			forward = -target_pose.basis.z
	forward = forward.normalized()

	# Horizon stabilization: derive the lateral and vertical axes from the
	# world-up vector, not from the target's rolled/pitched basis.
	var right := forward.cross(WORLD_UP)
	if right.length_squared() < DIRECTION_EPSILON_SQ:
		right = forward.cross(target_pose.basis.x)
		if right.length_squared() < DIRECTION_EPSILON_SQ:
			right = forward.cross(Vector3.RIGHT)
	right = right.normalized()
	var up := right.cross(forward).normalized()

	var pose := Transform3D(Basis(right, up, -forward), camera_position)
	return refine_desired_pose(pose, 0.0)


func _apply_smoothed(desired: Transform3D, delta: float) -> void:
	var weight := clampf(1.0 - exp(-delta / _smoothing_response_s), 0.0, 1.0)
	var current := _ensure_camera().global_transform
	var position := current.origin.lerp(desired.origin, weight)
	var basis := Basis(
		Quaternion(current.basis).slerp(Quaternion(desired.basis), weight)
	).orthonormalized()
	_assign_camera_transform(Transform3D(basis, position))


func _assign_camera_transform(pose: Transform3D) -> void:
	if not _is_finite_transform(pose):
		# Never propagate a nonfinite camera transform. The last safe pose
		# remains active and the invalid target state is reported.
		return
	_ensure_camera().global_transform = pose


func _is_finite_vec(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _is_finite_transform(transform: Transform3D) -> bool:
	return (
		_is_finite_vec(transform.origin)
		and _is_finite_vec(transform.basis.x)
		and _is_finite_vec(transform.basis.y)
		and _is_finite_vec(transform.basis.z)
	)
