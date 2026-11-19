extends Area3D
class_name CgameWaterVolume3D
## Rigid-body interaction with a horizontal, world-space water surface.
## An Area3D CollisionShape3D determines which bodies are eligible.
## Use a CgameFluidBody3D child to specify shape/volume approximations.

const FluidMath = preload("res://addons/advanced_physics/fluid_math.gd")

@export var enabled: bool = true
@export var surface_height: float = 0.0
@export var fluid_density: float = 997.0 # kg/m^3, fresh water at room temperature
@export var fluid_velocity: Vector3 = Vector3.ZERO # current, m/s
@export var gravity_vector: Vector3 = Vector3(0.0, -9.81, 0.0) # m/s^2
@export_range(0.0, 10.0, 0.01, "or_greater") var drag_coefficient: float = 0.8
@export_range(0.0, 10.0, 0.001, "or_greater") var dynamic_viscosity: float = 0.001 # Pa*s
@export_range(0.0, 10.0, 0.01, "or_greater") var angular_drag_coefficient: float = 0.05


func _ready() -> void:
	monitoring = true


func _physics_process(delta: float) -> void:
	if not enabled or delta <= 0.0 or fluid_density <= 0.0:
		return

	for candidate in get_overlapping_bodies():
		var body: RigidBody3D = candidate as RigidBody3D
		if body == null or body.freeze or body.mass <= 0.0:
			continue
		var profile: CgameFluidBody3D = CgameFluidBody3D.find_for(body)
		if profile == null:
			continue

		var offsets: Array[Vector3] = profile.get_offsets()
		var count: int = offsets.size()
		var volume_per_sample: float = profile.displaced_volume / float(count)
		var area_per_sample: float = profile.drag_area / float(count)
		var submerged_sum: float = 0.0

		for local_offset in offsets:
			var point: Vector3 = body.global_transform * local_offset
			var immersion: Vector2 = FluidMath.sphere_submersion(surface_height, point.y, profile.sample_radius)
			if immersion.x <= 0.0:
				continue
			submerged_sum += immersion.x
			var center_of_buoyancy: Vector3 = point + Vector3(0.0, immersion.y, 0.0)
			var lever_arm: Vector3 = center_of_buoyancy - body.global_position
			var point_velocity: Vector3 = body.linear_velocity + body.angular_velocity.cross(lever_arm)
			var relative_velocity: Vector3 = point_velocity - fluid_velocity

			var buoyancy: Vector3 = FluidMath.buoyancy_force(fluid_density, volume_per_sample, immersion.x, gravity_vector)
			var drag: Vector3 = FluidMath.quadratic_drag(fluid_density, drag_coefficient, area_per_sample * immersion.x, relative_velocity)
			drag += FluidMath.stokes_drag(dynamic_viscosity, profile.sample_radius, relative_velocity) * immersion.x
			drag = FluidMath.limit_opposing_force(drag, relative_velocity, body.mass, delta, count)

			var total_force: Vector3 = buoyancy + drag
			if total_force.is_finite() and total_force.length_squared() > 0.0:
				body.apply_force(total_force, lever_arm)

		if submerged_sum > 0.0:
			var torque: Vector3 = FluidMath.angular_drag(fluid_density, angular_drag_coefficient, profile.angular_drag_radius, body.angular_velocity) * (submerged_sum / float(count))
			if torque.is_finite() and torque.length_squared() > 0.0:
				body.apply_torque(torque)
