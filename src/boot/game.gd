class_name GamePlaceholder
extends Node3D
## M0 placeholder race scene.
##
## There is no track, grid, car, motor, camera work or simulation here. It
## exists to prove that a 3D scene loads in the Compatibility renderer shell;
## real race content starts at M1 (driving) and M2 (course pipeline).


func _ready() -> void:
	print("[game] placeholder race scene (no track, cars or simulation yet)")
