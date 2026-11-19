# Runtime regression for rotated capsules floating across a horizontal waterline.
# A world-AABB buoyancy approximation places the lift at the body's center,
# producing no hydrostatic restoring torque for these centrally placed shapes.
# True shape integration must spin oppositely tilted capsules in opposite ways.
# Run with --headless --path tests/stress --script res://physics_tilted_capsule_buoyancy_3d_regression.gd
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


func _make_body(space: RID, shape: RID, position: Vector3, angle: float) -> RID:
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_MASS, 10.0)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 0.0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(Vector3(0, 0, 1), angle), position))
	PhysicsServer3D.body_set_space(body, space)
	return body


func _run() -> void:
	var originals: Dictionary = {}
	for key in SETTINGS:
		originals[key] = ProjectSettings.get_setting(key)
		ProjectSettings.set_setting(key, SETTINGS[key])
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, 9.8)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, Vector3.DOWN)
	var capsule := PhysicsServer3D.capsule_shape_create()
	PhysicsServer3D.shape_set_data(capsule, {"radius": 1.0, "height": 4.0})
	# Axis of each capsule is its local Y axis. Opposite tilt angles
	# exchange which end lies to the left of the wet half.
	var left := _make_body(space, capsule, Vector3(0, 0, 0), -PI / 4.0)
	var right := _make_body(space, capsule, Vector3(20, 0, 0), PI / 4.0)
	var dry := _make_body(space, capsule, Vector3(40, 10, 0), -PI / 4.0)
	PhysicsServer3D.space_set_active(space, true)
	for _frame in range(8):
		await physics_frame
	await process_frame

	var left_spin: Vector3 = PhysicsServer3D.body_get_state(left,
			PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	var right_spin: Vector3 = PhysicsServer3D.body_get_state(right,
			PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	var dry_spin: Vector3 = PhysicsServer3D.body_get_state(dry,
			PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	var orientation_signs := (
			left_spin.is_finite() and right_spin.is_finite() and dry_spin.is_finite()
			and left_spin.z < -0.01 and right_spin.z > 0.01
			and absf(dry_spin.z) < 0.01
			and absf(left_spin.z + right_spin.z) < 0.035
	)

	PhysicsServer3D.space_set_active(space, false)
	for body in [left, right, dry]:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(capsule)
	PhysicsServer3D.free_rid(space)
	for key in originals:
		ProjectSettings.set_setting(key, originals[key])

	if not orientation_signs:
		printerr("Tilted capsule buoyancy torque FAILED: negative tilt=", left_spin,
				" positive tilt=", right_spin, " dry=", dry_spin)
		quit(1)
		return
	print("Tilted capsule restoring torque passed: ", left_spin, " / ", right_spin,
			" (dry control ", dry_spin, ")")
	quit(0)
