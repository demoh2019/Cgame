# Analytical hydrostatic regression: affine ellipsoid versus a sphere with
# identical true volume and vertical half-height. At the waterline both
# displace 5*pi/24 m^3, sink with unit mass and density 1, and experience
# almost the same upward force. The old AABB-only ellipsoid approximation
# displaces pi/3 m^3, incorrectly causing the ellipsoid to rise.
# Run: --headless --path tests/stress --script res://physics_ellipsoid_buoyancy_3d_regression.gd
extends SceneTree

const SETTINGS := {
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


func _make_body(space: RID, shape: RID, basis: Basis, position: Vector3) -> RID:
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(body, shape, Transform3D(basis, Vector3.ZERO))
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_MASS, 1.0)
	PhysicsServer3D.body_set_collision_layer(body, 0)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(), position))
	PhysicsServer3D.body_set_space(body, space)
	return body


func _run() -> void:
	var original: Dictionary = {}
	for setting in SETTINGS:
		original[setting] = ProjectSettings.get_setting(setting)
		ProjectSettings.set_setting(setting, SETTINGS[setting])
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, 9.8)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, Vector3.DOWN)
	var sphere := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(sphere, 1.0)
	var unit_basis := Basis()
	var affine_basis := Basis.from_scale(Vector3(2.0, 1.0, 0.5))
	var control := _make_body(space, sphere, unit_basis, Vector3(0, 0.5, 0))
	var ellipsoid := _make_body(space, sphere, affine_basis, Vector3(8, 0.5, 0))
	var dry := _make_body(space, sphere, affine_basis, Vector3(16, 5, 0))

	PhysicsServer3D.space_set_active(space, true)
	for _frame in range(5):
		await physics_frame
	await process_frame

	var sphere_velocity: Vector3 = PhysicsServer3D.body_get_state(control,
			PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var ellipsoid_velocity: Vector3 = PhysicsServer3D.body_get_state(ellipsoid,
			PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var dry_velocity: Vector3 = PhysicsServer3D.body_get_state(dry,
			PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)

	var ellipsoid_sinks := ellipsoid_velocity.y < -0.005
	var sphere_sinks := sphere_velocity.y < -0.005
	var same_buoyant_acceleration := absf(ellipsoid_velocity.y - sphere_velocity.y) < 0.05
	var dry_falls_faster := dry_velocity.y < ellipsoid_velocity.y - 0.05
	var finite := sphere_velocity.is_finite() and ellipsoid_velocity.is_finite() and dry_velocity.is_finite()

	PhysicsServer3D.space_set_active(space, false)
	for body in [control, ellipsoid, dry]:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(sphere)
	PhysicsServer3D.free_rid(space)
	for setting in original:
		ProjectSettings.set_setting(setting, original[setting])

	if not (finite and ellipsoid_sinks and sphere_sinks and same_buoyant_acceleration and dry_falls_faster):
		printerr("Affine ellipsoid buoyancy FAILED: sphere=", sphere_velocity,
				" ellipsoid=", ellipsoid_velocity, " dry=", dry_velocity)
		quit(1)
		return
	print("Affine ellipsoid buoyancy passed: sphere=", sphere_velocity,
			" ellipsoid=", ellipsoid_velocity, " dry=", dry_velocity)
	quit(0)
