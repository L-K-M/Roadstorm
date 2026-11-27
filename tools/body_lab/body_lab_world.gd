class_name BodyLabWorld
extends RefCounted
## Deterministic flat-ground physics stage for the M1.1 adapter laboratory.
##
## Builds a real Godot/Jolt world: one static ground slab, one optional thick
## static wall described by a point on its near face and a yaw, and one
## `CharacterBody3D` with a box hull. The wall's outward near-face normal is
## `R_y(yaw) * +Z`, so yaw 0 is a wall perpendicular to the car's -Z path.
##
## This is laboratory staging only. It owns no clock or automatic loop; the
## driver calls the adapter once per engine physics callback.

const AdapterScript = preload("res://src/simulation/motor_body_adapter.gd")

const GROUND_SIZE := Vector3(200.0, 1.0, 200.0)
const WALL_HEIGHT := 4.0
const WALL_CENTER_Y := 2.0

var root: Node3D = null
var body: CharacterBody3D = null
var hull_shape: BoxShape3D = null
var ground: StaticBody3D = null
var wall: StaticBody3D = null
## World-space point on the wall's near face (null when no wall was built).
var wall_point: Vector3 = Vector3.INF
## Outward near-face normal (zero when no wall was built).
var wall_normal: Vector3 = Vector3.ZERO
## Wall thickness along its normal, metres (zero when no wall was built).
var wall_thickness_m := 0.0


static func build(
	tree_root: Node,
	config: MotorBodyAdapter.Config,
	wall_spec: Dictionary
) -> BodyLabWorld:
	var world := BodyLabWorld.new()
	world.root = Node3D.new()
	world.root.name = "BodyLabWorld"
	tree_root.add_child(world.root)

	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = GROUND_SIZE
	ground_shape.shape = ground_box
	ground.add_child(ground_shape)
	ground.position = Vector3(0.0, -GROUND_SIZE.y * 0.5, 0.0)
	world.root.add_child(ground)
	world.ground = ground

	if not wall_spec.is_empty():
		var point: Vector3 = wall_spec["point"]
		var yaw_deg: float = wall_spec.get("yaw_deg", 0.0)
		var thickness: float = wall_spec.get("thickness_m", 2.0)
		var width: float = wall_spec.get("width_m", 20.0)
		var yaw := deg_to_rad(yaw_deg)
		var normal := Vector3(sin(yaw), 0.0, cos(yaw))
		var wall := StaticBody3D.new()
		wall.name = "Wall"
		var wall_shape := CollisionShape3D.new()
		var wall_box := BoxShape3D.new()
		wall_box.size = Vector3(width, WALL_HEIGHT, thickness)
		wall_shape.shape = wall_box
		wall.add_child(wall_shape)
		wall.rotation.y = yaw
		wall.position = point - normal * (thickness * 0.5)
		wall.position.y = WALL_CENTER_Y
		world.root.add_child(wall)
		world.wall = wall
		world.wall_point = Vector3(point.x, WALL_CENTER_Y, point.z)
		world.wall_normal = normal
		world.wall_thickness_m = thickness

	var body := CharacterBody3D.new()
	body.name = "LabCar"
	var body_shape := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = config.hull_size_m
	body_shape.shape = hull
	body.add_child(body_shape)
	body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	body.collision_layer = 1
	body.collision_mask = 1
	world.root.add_child(body)
	world.body = body
	world.hull_shape = hull
	return world


## Place the body origin from a committed CarState under the fixed mapping.
func set_pose(state: CarState, support_y: float) -> void:
	body.global_transform = Transform3D(
		AdapterScript.basis_from_heading(state.heading_rad),
		Vector3(state.position_m.x, support_y, -state.position_m.y)
	)


func destroy() -> void:
	if root != null and is_instance_valid(root):
		var parent := root.get_parent()
		if parent != null:
			parent.remove_child(root)
		root.free()
	root = null
	body = null
	hull_shape = null
	ground = null
	wall = null
