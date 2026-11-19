# Opt-in submerged-volume buoyancy, asymmetric torque, and moving-water drag.
# Run: --headless --path tests/stress \
#   --script res://physics_submerged_fluid_plane_3d_regression.gd
extends SceneTree

const SETTINGS := {
	"physics/3d/fluid_plane/enabled": true,
	"physics/3d/fluid_plane/surface_height": 0.0,
	"physics/3d/fluid_plane/density": 6.0,
	"physics/3d/fluid_plane/drag_coefficient": 1.0,
	"physics/3d/fluid_plane/angular_drag": 0.1,
	"physics/3d/fluid_plane/flow_velocity": Vector3(4, 0, 0),
}


func _initialize() -> void:
	_run.call_deferred()


func _new_body(space: RID, shape: RID, origin: Vector3) -> RID:
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_MASS, 1.0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(), origin))
	PhysicsServer3D.body_set_space(body, space)
	return body


func _run() -> void:
	var original: Dictionary = {}
	for key in SETTINGS:
		original[key] = ProjectSettings.get_setting(key)
		ProjectSettings.set_setting(key, SETTINGS[key])

	var shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, 0.5)
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, 9.8)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, Vector3.DOWN)

	var full := _new_body(space, shape, Vector3(0, -2, 0))
	var partial := _new_body(space, shape, Vector3(5, 0, 0))
	var dry := _new_body(space, shape, Vector3(10, 3, 0))

	# Two equally massive components with different immersion fractions
	# give a nonzero buoyancy torque about their combined mass center.
	var compound := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(compound, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_set_param(compound, PhysicsServer3D.BODY_PARAM_MASS, 1.0)
	PhysicsServer3D.body_add_shape(compound, shape,
			Transform3D(Basis(), Vector3(-1, -1, 0)))
	PhysicsServer3D.body_add_shape(compound, shape,
			Transform3D(Basis(), Vector3(1, 1, 0)))
	PhysicsServer3D.body_set_state(compound, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(), Vector3(20, 0, 0)))
	PhysicsServer3D.body_set_space(compound, space)
	PhysicsServer3D.space_set_active(space, true)

	for _step in range(12):
		await physics_frame
	await process_frame

	var full_v: Vector3 = PhysicsServer3D.body_get_state(full, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var partial_v: Vector3 = PhysicsServer3D.body_get_state(partial, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var dry_v: Vector3 = PhysicsServer3D.body_get_state(dry, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var compound_omega: Vector3 = PhysicsServer3D.body_get_state(compound, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)

	var full_floats := full_v.y > 0.0 and full_v.y > partial_v.y
	var partial_floats := partial_v.y > dry_v.y
	var dry_falls := dry_v.y < 0.0
	var current_moves_wet := full_v.x > 0.0 and partial_v.x > 0.0 and absf(dry_v.x) < 0.01
	var offcenter_torque := absf(compound_omega.z) > 0.01

	# The exact old behavior must be preserved when the optional water
	# plane is turned off, even for a submerged body.
	ProjectSettings.set_setting("physics/3d/fluid_plane/enabled", false)
	var legacy_space := PhysicsServer3D.space_create()
	PhysicsServer3D.area_set_param(legacy_space, PhysicsServer3D.AREA_PARAM_GRAVITY, 9.8)
	PhysicsServer3D.area_set_param(legacy_space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, Vector3.DOWN)
	var legacy := _new_body(legacy_space, shape, Vector3(30, -2, 0))
	PhysicsServer3D.space_set_active(legacy_space, true)
	for _step in range(8):
		await physics_frame
	await process_frame
	var legacy_v: Vector3 = PhysicsServer3D.body_get_state(legacy, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var off_is_legacy := legacy_v.y < 0.0 and absf(legacy_v.x) < 0.01

	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.space_set_active(legacy_space, false)
	for body in [full, partial, dry, compound, legacy]:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)
	PhysicsServer3D.free_rid(legacy_space)
	for key in original:
		ProjectSettings.set_setting(key, original[key])

	if not (full_floats and partial_floats and dry_falls and current_moves_wet and offcenter_torque and off_is_legacy):
		printerr("3D fluid plane regression FAILED: full=", full_v, " partial=", partial_v,
				" dry=", dry_v, " torque=", compound_omega, " disabled=", legacy_v)
		quit(1)
		return
	print("3D fluid plane regression OK: full=", full_v, " partial=", partial_v,
			" dry=", dry_v, " torque=", compound_omega, " disabled=", legacy_v)
	quit(0)
