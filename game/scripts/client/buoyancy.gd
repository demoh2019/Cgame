extends Node
## Rigid-body buoyancy. Every RigidBody3D in the "buoyant" group that dips below the water surface
## (sea, river or lake: WorldGen.water_level_at) is pushed up in proportion to how deep it sits,
## damped in the water, and drifts with river current and the wind - so debris, severed limbs and
## dropped wreckage float, bob and drift instead of sinking through the surface.

const GROUP := "buoyant"
const DENSITY_LIFT := 1.7 # Upward force at full submersion, in units of the body's weight.
const DEPTH_FOR_FULL := 0.35
const WATER_DAMP := 2.4

var world


func _physics_process(_delta: float) -> void:
	if world == null:
		return
	var wind: Vector3 = RenderingServer.global_shader_parameter_get("aa_vegetation_wind") if RenderingServer.has_method("global_shader_parameter_get") else Vector3.ZERO
	for node in get_tree().get_nodes_in_group(GROUP):
		var body := node as RigidBody3D
		if body == null or not body.is_inside_tree() or body.freeze:
			continue
		var p: Vector3 = body.global_position
		var surface: float = world.water_level_at(p.x, p.z)
		if world.ground_at(p.x, p.z) >= surface:
			body.linear_damp = 0.0
			continue
		var depth: float = surface - p.y
		if depth <= -0.1:
			body.linear_damp = 0.0
			continue
		var submerged: float = clampf((depth + 0.1) / DEPTH_FOR_FULL, 0.0, 1.0)
		body.sleeping = false
		body.apply_central_force(Vector3.UP * body.mass * 9.8 * DENSITY_LIFT * submerged)
		body.linear_damp = WATER_DAMP * submerged
		body.angular_damp = WATER_DAMP * submerged
		# Surface drift with the wind.
		body.apply_central_force(Vector3(wind.x, 0.0, wind.y) * body.mass * 0.6 * submerged * clampf(wind.z, 0.0, 1.0))
