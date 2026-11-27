extends RigidBody3D
## Test-only dynamic body that counts its own physics-server integration steps.
##
## Used by the M0.8 dynamic-step regression: `_integrate_forces` is called once
## per PhysicsServer3D step for this body. Measured on Godot 4.7.2-stable with
## Jolt; the probe pins that engine version.

var server_steps := 0
var last_state_linear_velocity := Vector3.ZERO
## Engine physics-frame indices of the first/last counted integration. Used to
## separate body-registration latency from observation/read timing.
var first_integration_physics_frame := -1
var last_integration_physics_frame := -1


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	server_steps += 1
	var pf := Engine.get_physics_frames()
	if first_integration_physics_frame < 0:
		first_integration_physics_frame = pf
	last_integration_physics_frame = pf
	if state != null:
		last_state_linear_velocity = state.linear_velocity
