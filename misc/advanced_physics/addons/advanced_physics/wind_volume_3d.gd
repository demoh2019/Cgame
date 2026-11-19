extends Area3D
class_name CgameWindVolume3D
## Aerodynamic forces on opted-in RigidBody3D nodes inside this Area3D.

const FluidMath = preload("res://addons/advanced_physics/fluid_math.gd")

@export var enabled: bool = true
@export var wind_velocity: Vector3 = Vector3(6.0, 0.0, 0.0) # m/s
@export var air_density: float = 1.225 # kg/m^3 at sea level
@export_range(0.0, 10.0, 0.01, "or_greater") var drag_coefficient: float = 1.0
@export_range(0.0, 10.0, 0.01, "or_greater") var angular_drag_coefficient: float = 0.1
@export_range(0.0, 10.0, 0.01, "or_greater") var magnus_coefficient: float = 0.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var gust_amplitude: float = 0.0
@export_range(0.0, 100.0, 0.01, "or_greater") var gust_frequency_hz: float = 0.2
@export var gust_direction: Vector3 = Vector3.RIGHT

var _simulation_time: float = 0.0


func _ready() -> void:
	monitoring = true


func _physics_process(delta: float) -> void:
	if not enabled or delta <= 0.0 or air_density <= 0.0:
		return
	_simulation_time += delta
	var air_velocity: Vector3 = wind_velocity
	if gust_amplitude > 0.0 and gust_frequency_hz > 0.0 and gust_direction.length_squared() > 1.0e-12:
		air_velocity += gust_direction.normalized() * gust_amplitude * sin(TAU * gust_frequency_hz * _simulation_time)

	for candidate in get_overlapping_bodies():
		var body: RigidBody3D = candidate as RigidBody3D
		if body == null or body.freeze or body.mass <= 0.0:
			continue
		var profile: CgameFluidBody3D = CgameFluidBody3D.find_for(body)
		if profile == null:
			continue

		var offsets: Array[Vector3] = profile.get_offsets()
		var count: int = offsets.size()
		var area_per_sample: float = profile.drag_area / float(count)
		for local_offset in offsets:
			var point: Vector3 = body.global_transform * local_offset
			var lever_arm: Vector3 = point - body.global_position
			var point_velocity: Vector3 = body.linear_velocity + body.angular_velocity.cross(lever_arm)
			var relative_velocity: Vector3 = point_velocity - air_velocity
			var drag: Vector3 = FluidMath.quadratic_drag(air_density, drag_coefficient, area_per_sample, relative_velocity)
			drag = FluidMath.limit_opposing_force(drag, relative_velocity, body.mass, delta, count)
			if drag.is_finite() and drag.length_squared() > 0.0:
				body.apply_force(drag, lever_arm)

		var magnus: Vector3 = FluidMath.magnus_force(air_density, profile.displaced_volume, magnus_coefficient, body.angular_velocity, air_velocity - body.linear_velocity)
		if magnus.is_finite() and magnus.length_squared() > 0.0:
			body.apply_central_force(magnus)

		var torque: Vector3 = FluidMath.angular_drag(air_density, angular_drag_coefficient, profile.angular_drag_radius, body.angular_velocity)
		if torque.is_finite() and torque.length_squared() > 0.0:
			body.apply_torque(torque)
