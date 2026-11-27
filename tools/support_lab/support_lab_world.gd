class_name SupportLabWorld
extends RefCounted
## Deterministic physics stage for the M1.4 ground-support sensing laboratory.
##
## Builds real Godot/Jolt static colliders and one or more `CharacterBody3D`
## probe carriers from explicit dictionaries. The stage owns no clock: the
## driver awaits engine physics frames, then calls `GroundSupportProbe.probe()`
## with explicit world transforms.
##
## Staging format:
##   slab: {name, size, center, rotation_deg (Vector3, optional), layer}
##   area: {name, size, center, rotation_deg (Vector3, optional), layer}
##   car:  {name, position, basis (optional), layer, mask}

const ProbeScript = preload("res://src/simulation/ground_support_probe.gd")

var root: Node3D = null
var hull_size := Vector3.ZERO
## Probe carrier bodies keyed by name.
var bodies: Dictionary = {}
## BoxShape3D of each carrier, keyed by name.
var hull_shapes: Dictionary = {}


static func build(
	tree_root: Node,
	hull_size: Vector3,
	slabs: Array[Dictionary],
	areas: Array[Dictionary],
	cars: Array[Dictionary]
) -> SupportLabWorld:
	var world := SupportLabWorld.new()
	world.hull_size = hull_size
	world.root = Node3D.new()
	world.root.name = "SupportLabWorld"
	tree_root.add_child(world.root)

	for spec in slabs:
		var body := StaticBody3D.new()
		body.name = String(spec.get("name", "Slab"))
		body.collision_layer = int(spec.get("layer", 1))
		body.collision_mask = 0
		var shape_node := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec["size"]
		shape_node.shape = box
		body.add_child(shape_node)
		body.position = spec["center"]
		body.rotation = _deg_to_rad(spec.get("rotation_deg", Vector3.ZERO))
		world.root.add_child(body)

	for spec in areas:
		var area := Area3D.new()
		area.name = String(spec.get("name", "Area"))
		area.collision_layer = int(spec.get("layer", 1))
		area.collision_mask = 0
		var shape_node := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec["size"]
		shape_node.shape = box
		area.add_child(shape_node)
		area.position = spec["center"]
		area.rotation = _deg_to_rad(spec.get("rotation_deg", Vector3.ZERO))
		world.root.add_child(area)

	for spec in cars:
		var body := CharacterBody3D.new()
		body.name = String(spec.get("name", "Car"))
		body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		body.collision_layer = int(spec.get("layer", 1))
		body.collision_mask = int(spec.get("mask", 1))
		var shape_node := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = hull_size
		shape_node.shape = box
		body.add_child(shape_node)
		body.position = spec.get("position", Vector3.ZERO)
		var basis: Basis = spec.get("basis", Basis())
		body.global_transform = Transform3D(basis, body.position)
		world.root.add_child(body)
		world.bodies[body.name] = body
		world.hull_shapes[body.name] = box

	return world


func body(car_name: String) -> CharacterBody3D:
	return bodies[car_name]


func hull_shape(car_name: String) -> BoxShape3D:
	return hull_shapes[car_name]


static func _deg_to_rad(euler_deg: Vector3) -> Vector3:
	return Vector3(
		deg_to_rad(euler_deg.x),
		deg_to_rad(euler_deg.y),
		deg_to_rad(euler_deg.z)
	)


func destroy() -> void:
	if root != null and is_instance_valid(root):
		var parent := root.get_parent()
		if parent != null:
			parent.remove_child(root)
		root.free()
	root = null
	bodies = {}
	hull_shapes = {}
