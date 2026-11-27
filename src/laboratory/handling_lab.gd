class_name HandlingLabScene
extends Node3D
## M1.2 static graybox handling laboratory scene.
##
## The scene owns no car, motor or gameplay. On ready it calls the deterministic
## builder, which constructs all visible surfaces, static colliders, surface
## metadata and spawn/recovery markers from the authored data table. The
## resulting manifest is stored in the "lab_manifest" metadata for inspection
## and headless validation.

const HandlingLabBuilderScript := preload("res://src/laboratory/handling_lab_builder.gd")


func _ready() -> void:
	var manifest: Dictionary = HandlingLabBuilderScript.build(self)
	set_meta("lab_manifest", manifest)
	print("[handling_lab] built lab ", manifest["lab_id"], " with ", manifest["bays"].size(), " bays")
