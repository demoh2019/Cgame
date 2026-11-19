# True convex hull displacement (tetrahedron) versus an AABB-shaped box.
# Run with GodotPhysics 3D, not the separate Jolt backend:
# --headless --path tests/stress --script res://physics_convex_hydrostatic_3d_regression.gd
extends SceneTree

const SETTINGS := {
	"physics/3d/fluid_plane/enabled": true,
	"physics/3d/fluid_plane/surface_height": 0.0,
	"physics/3d/fluid_plane/density": 0.75,
	"physics/3d/fluid_plane/drag_coefficient": 0.0,
	"physics/3d/fluid_plane/angular_drag": 0.0,
	"physics/3d/fluid_plane/flow_velocity": Vector3.ZERO,
	"physics/3d/solver/fluid_buoyancy": 0.0,
	"physics/3d/solver/fluid_linear_drag": 0.0,
	"physics/3d/solver/fluid_angular_drag": 0.0,
}


func _initialize() -> void:
	_run.call_deferred()


func _body(space: RID, shape: RID, transform: Transform3D) -> RID:
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_MASS, 1.0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, transform)
	PhysicsServer3D.body_set_space(body, space)
	return body


func _run() -> void:
	var original: Dictionary = {}
	for name in SETTINGS:
		original[name] = ProjectSettings.get_setting(name)
		ProjectSettings.set_setting(name, SETTINGS[name])

	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, 9.8)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, Vector3.DOWN)

	# Same broadphase AABB as an axis-aligned box: volume 8.
	# Exact tetrahedron volume is 4/3 and, with the water plane y=0,
	# 7/8 of that volume is wet: displaced volume = 7/6.
	# rho=0.75 -> buoyancy is 0.875*m*g, so the tetrahedron SINKS.
	# The AABB half-volume approximation yields rho*4=3: it would float.
	var hull := PhysicsServer3D.convex_polygon_shape_create()
	PhysicsServer3D.shape_set_data(hull, PackedVector3Array([
		Vector3(-1, -1, -1), Vector3(1, -1, -1),
		Vector3(-1, 1, -1), Vector3(-1, -1, 1)
	]))
	var box := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(box, Vector3.ONE)

	var tetra := _body(space, hull, Transform3D.IDENTITY)
	var box_body := _body(space, box, Transform3D(Basis(), Vector3(10, 0, 0)))
	var dry := _body(space, hull, Transform3D(Basis(), Vector3(20, 10, 0)))
	var tilted := _body(space, hull, Transform3D(Basis(Vector3(0, 0, 1), 0.4), Vector3(30, 0, 0)))

	PhysicsServer3D.space_set_active(space, true)
	for _frame in range(9):
		await physics_frame
	await process_frame

	var tetra_v: Vector3 = PhysicsServer3D.body_get_state(tetra, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var box_v: Vector3 = PhysicsServer3D.body_get_state(box_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var dry_v: Vector3 = PhysicsServer3D.body_get_state(dry, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var tilted_v: Vector3 = PhysicsServer3D.body_get_state(tilted, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var tetra_spin: Vector3 = PhysicsServer3D.body_get_state(tetra, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)

	var convex_sinks := tetra_v.y < -0.01
	var box_floats := box_v.y > 0.01
	var dry_falls_more := dry_v.y < tetra_v.y
	var buoyant_torque := tetra_spin.length() > 0.001
	var tilted_finite := tilted_v.is_finite()

	PhysicsServer3D.space_set_active(space, false)
	for body in [tetra, box_body, dry, tilted]:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(hull)
	PhysicsServer3D.free_rid(box)
	PhysicsServer3D.free_rid(space)
	for name in original:
		ProjectSettings.set_setting(name, original[name])

	if not (convex_sinks and box_floats and dry_falls_more and buoyant_torque and tilted_finite):
		printerr("Exact convex hydrostatics FAILED: tetra=", tetra_v,
				" box=", box_v, " dry=", dry_v, " tilted=", tilted_v,
				" torque=", tetra_spin)
		quit(1)
		return
	print("Exact convex hydrostatics passed: tetra=", tetra_v,
			" box=", box_v, " dry=", dry_v, " tilted=", tilted_v,
			" torque=", tetra_spin)
	quit(0)
