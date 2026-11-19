# Analytic hydrostatic regression for uniformly scaled spheres and upright
# capsules. AABB-height buoyancy incorrectly lifts BOTH test bodies here;
# exact circular cross-section integration produces an initial sinking force.
# Run: --headless --path tests/stress \
#   --script res://physics_exact_primitive_buoyancy_3d_regression.gd
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


func _make_body(space: RID, shape: RID, position: Vector3) -> RID:
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_MASS, 1.0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM,
			Transform3D(Basis(), position))
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

	var sphere := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(sphere, 1.0)
	var capsule := PhysicsServer3D.capsule_shape_create()
	PhysicsServer3D.shape_set_data(capsule, {"radius": 1.0, "height": 4.0})

	# Both bottoms are at y=-0.5; both wet volumes at t=0 are
	# pi * 5 / 24 m^3. Their analytic initial buoyant accelerations
	# should therefore match for mass 1 and density 1.
	var sphere_body := _make_body(space, sphere, Vector3(0, 0.5, 0))
	var capsule_body := _make_body(space, capsule, Vector3(8, 1.5, 0))
	var dry_body := _make_body(space, sphere, Vector3(16, 5, 0))

	PhysicsServer3D.space_set_active(space, true)
	for _frame in range(5):
		await physics_frame
	await process_frame

	var sphere_v: Vector3 = PhysicsServer3D.body_get_state(sphere_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var capsule_v: Vector3 = PhysicsServer3D.body_get_state(capsule_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var dry_v: Vector3 = PhysicsServer3D.body_get_state(dry_body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)

	# For the previous AABB approximation: sphere Vwet = 4*pi/3*0.25
	# and capsule Vwet = 10*pi/3*0.125; both are > 1, so they would
	# incorrectly accelerate UP. The exact wet cap volume is ~0.6545.
	var exact_sphere_sinks := sphere_v.y < -0.005
	var exact_capsule_sinks := capsule_v.y < -0.005
	var same_displacement := absf(sphere_v.y - capsule_v.y) < 0.035
	var dry_falls_faster := dry_v.y < sphere_v.y and dry_v.y < capsule_v.y

	PhysicsServer3D.space_set_active(space, false)
	for body in [sphere_body, capsule_body, dry_body]:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(sphere)
	PhysicsServer3D.free_rid(capsule)
	PhysicsServer3D.free_rid(space)
	for key in originals:
		ProjectSettings.set_setting(key, originals[key])

	if not (exact_sphere_sinks and exact_capsule_sinks and same_displacement and dry_falls_faster):
		printerr("Analytic primitive buoyancy FAILED: sphere=", sphere_v,
				" capsule=", capsule_v, " dry=", dry_v,
				" checks=", [exact_sphere_sinks, exact_capsule_sinks, same_displacement, dry_falls_faster])
		quit(1)
		return
	print("Analytic sphere/capsule buoyancy passed: sphere=", sphere_v,
			" capsule=", capsule_v, " dry=", dry_v)
	quit(0)
