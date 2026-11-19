# GodotPhysics3D integration regression: true immersed V and centroid
# for a cylinder oriented sideways vs its world AABB approximation.
# AABB: V_wet = pi * 1 = 3.14159 for a radius-one, length-four cylinder
# with its bottom at -0.5. Exact V_wet = 4*(acos(0.5)-0.5*sqrt(0.75))
# = 2.45674, which is < mass 2.8 and must initially SINK, not float.
# Run: --headless --path tests/stress --script res://physics_cylinder_buoyancy_3d_regression.gd
extends SceneTree

const OPTIONS := {
	"physics/3d/fluid_plane/enabled": true,
	"physics/3d/fluid_plane/surface_height": 0.0,
	"physics/3d/fluid_plane/density": 1.0,
	"physics/3d/fluid_plane/drag_coefficient": 0.0,
	"physics/3d/fluid_plane/angular_drag": 0.0,
	"physics/3d/fluid_plane/flow_velocity": Vector3.ZERO,
	"physics/3d/solver/fluid_buoyancy": 0.0,
	"physics/3d/solver/fluid_linear_drag": 0.0,
	"physics/3d/solver/fluid_angular_drag": 0.0,
}


func _initialize() -> void:
	_run.call_deferred()


func _make_body(space: RID, shape: RID, position: Vector3, angle: float) -> RID:
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(body, shape,
			Transform3D(Basis(Vector3(0, 0, 1), angle), Vector3.ZERO))
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_MASS, 2.8)
	PhysicsServer3D.body_set_collision_layer(body, 0)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(), position))
	PhysicsServer3D.body_set_space(body, space)
	return body


func _velocity(body: RID) -> Vector3:
	return PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)


func _omega(body: RID) -> Vector3:
	return PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)


func _run() -> void:
	var original: Dictionary = {}
	for key in OPTIONS:
		original[key] = ProjectSettings.get_setting(key)
		ProjectSettings.set_setting(key, OPTIONS[key])
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, 9.8)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, Vector3.DOWN)

	var shape := PhysicsServer3D.cylinder_shape_create()
	PhysicsServer3D.shape_set_data(shape, {"radius": 1.0, "height": 4.0})
	var horizontal := _make_body(space, shape, Vector3(0, 0.5, 0), -PI / 2.0)
	var upright := _make_body(space, shape, Vector3(12, 1.5, 0), 0.0)
	var dry := _make_body(space, shape, Vector3(24, 6.0, 0), 0.0)
	var tilted_left := _make_body(space, shape, Vector3(36, 0, 0), -PI / 4.0)
	var tilted_right := _make_body(space, shape, Vector3(48, 0, 0), PI / 4.0)

	PhysicsServer3D.space_set_active(space, true)
	for _frame in range(7):
		await physics_frame
	await process_frame

	var horizontal_v := _velocity(horizontal)
	var upright_v := _velocity(upright)
	var dry_v := _velocity(dry)
	var left_spin := _omega(tilted_left)
	var right_spin := _omega(tilted_right)
	var cylinder_sinks := horizontal_v.y < -0.005
	var upright_sinks_faster := upright_v.y < horizontal_v.y - 0.01
	var dry_falls_faster := dry_v.y < upright_v.y - 0.01
	var tilt_torque := (
			left_spin.z < -0.005 and right_spin.z > 0.005
			and absf(left_spin.z + right_spin.z) < 0.05
	)
	var finite := (
			horizontal_v.is_finite() and upright_v.is_finite()
			and dry_v.is_finite() and left_spin.is_finite()
			and right_spin.is_finite()
	)

	PhysicsServer3D.space_set_active(space, false)
	for body in [horizontal, upright, dry, tilted_left, tilted_right]:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)
	for key in original:
		ProjectSettings.set_setting(key, original[key])

	if not (cylinder_sinks and upright_sinks_faster and dry_falls_faster and tilt_torque and finite):
		printerr("Exact cylinder buoyancy FAILED: horizontal=", horizontal_v,
				" upright=", upright_v, " dry=", dry_v,
				" tilted_left=", left_spin, " tilted_right=", right_spin)
		quit(1)
		return
	print("Exact cylinder buoyancy passed: horizontal=", horizontal_v,
			" upright=", upright_v, " dry=", dry_v,
			" left/right spin=", left_spin, " / ", right_spin)
	quit(0)
