# Exact hydrostatics for rotated BoxShape3D, compared to a convex hull
# with exactly the same geometry. The old box AABB immersion incorrectly
# makes this heavy box float and cannot generate the lateral buoyant torque.
# Run on GodotPhysics 3D (not the separate Jolt backend):
# --headless --path tests/stress --script res://physics_fluid_oriented_box_3d_regression.gd
extends SceneTree

const WATER_SETTINGS := {
	"physics/3d/fluid_plane/enabled": true,
	"physics/3d/fluid_plane/surface_height": 0.0,
	"physics/3d/fluid_plane/density": 0.6,
	"physics/3d/fluid_plane/drag_coefficient": 0.0,
	"physics/3d/fluid_plane/angular_drag": 0.0,
	"physics/3d/fluid_plane/flow_velocity": Vector3.ZERO,
	"physics/3d/solver/fluid_buoyancy": 0.0,
	"physics/3d/solver/fluid_linear_drag": 0.0,
	"physics/3d/solver/fluid_angular_drag": 0.0,
}


func _initialize() -> void:
	_run.call_deferred()


func _rigid(space: RID, shape: RID, transform: Transform3D) -> RID:
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_MASS, 1.0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, transform)
	PhysicsServer3D.body_set_space(body, space)
	return body


func _run() -> void:
	var prior: Dictionary = {}
	for name in WATER_SETTINGS:
		prior[name] = ProjectSettings.get_setting(name)
		ProjectSettings.set_setting(name, WATER_SETTINGS[name])

	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, 9.8)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, Vector3.DOWN)

	var box := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(box, Vector3.ONE)
	var hull := PhysicsServer3D.convex_polygon_shape_create()
	PhysicsServer3D.shape_set_data(hull, PackedVector3Array([
		Vector3(-1, -1, -1), Vector3(1, -1, -1),
		Vector3(1, 1, -1), Vector3(-1, 1, -1),
		Vector3(-1, -1, 1), Vector3(1, -1, 1),
		Vector3(1, 1, 1), Vector3(-1, 1, 1),
	]))

	var tilted_basis := Basis(Vector3(0, 0, 1), deg_to_rad(30))
	var box_body := _rigid(space, box, Transform3D(tilted_basis, Vector3(0, 0.7, 0)))
	var hull_body := _rigid(space, hull, Transform3D(tilted_basis, Vector3(12, 0.7, 0)))
	var dry_body := _rigid(space, box, Transform3D(Basis(), Vector3(24, 6, 0)))

	# Analytic clipped-tetra model: for a 30-degree tilted 2x2x2 box
	# centered at y=.7, displaced volume is ~1.0244 (fraction .12805).
	# With fluid density .6 and mass 1 the object must still SINK.
	# The old world-AABB fraction is .2979 -> displaced volume 2.3834,
	# which would incorrectly cause the body to float.
	PhysicsServer3D.space_set_active(space, true)
	for _frame in range(6):
		await physics_frame
	await process_frame

	var box_v: Vector3 = PhysicsServer3D.body_get_state(box_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var hull_v: Vector3 = PhysicsServer3D.body_get_state(hull_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var dry_v: Vector3 = PhysicsServer3D.body_get_state(dry_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var box_spin: Vector3 = PhysicsServer3D.body_get_state(box_body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	var hull_spin: Vector3 = PhysicsServer3D.body_get_state(hull_body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)

	var box_sinks := box_v.y < -0.005
	var hull_sinks := hull_v.y < -0.005
	var matching_lift := absf(box_v.y - hull_v.y) < 0.08
	var dry_faster := dry_v.y < box_v.y
	var correct_torque := box_spin.z < -0.001 and hull_spin.z < -0.001
	var finite := box_v.is_finite() and hull_v.is_finite() and box_spin.is_finite() and hull_spin.is_finite()

	PhysicsServer3D.space_set_active(space, false)
	for body in [box_body, hull_body, dry_body]:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(box)
	PhysicsServer3D.free_rid(hull)
	PhysicsServer3D.free_rid(space)
	for name in prior:
		ProjectSettings.set_setting(name, prior[name])

	if not (box_sinks and hull_sinks and matching_lift and dry_faster and correct_torque and finite):
		printerr("Oriented box buoyancy FAILED: box=", box_v,
				" hull=", hull_v, " dry=", dry_v,
				" box_spin=", box_spin, " hull_spin=", hull_spin)
		quit(1)
		return
	print("Oriented box buoyancy OK: box=", box_v,
			" hull=", hull_v, " dry=", dry_v,
			" box_spin=", box_spin, " hull_spin=", hull_spin)
	quit(0)
