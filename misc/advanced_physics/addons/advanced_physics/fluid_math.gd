extends RefCounted
## Stateless, SI-unit force helpers shared by the water and air volumes.
## A sphere sample represents a user-configured effective displaced volume;
## its radius controls the immersion transition and submerged centroid.


static func sphere_submersion(surface_y: float, center_y: float, radius: float) -> Vector2:
	# Returns (submerged fraction, local Y of the submerged volume centroid).
	# These are exact for a sphere clipped by a horizontal plane.
	if radius <= 0.0:
		return Vector2.ZERO
	var x: float = (surface_y - center_y) / radius
	if x <= -1.0:
		return Vector2(0.0, -radius)
	if x >= 1.0:
		return Vector2(1.0, 0.0)
	var fraction: float = (1.0 + x) * (1.0 + x) * (2.0 - x) * 0.25
	# Simplified first moment: avoids catastrophic cancellation near x=-1.
	var centroid_y: float = -3.0 * radius * (1.0 - x) * (1.0 - x) / (4.0 * (2.0 - x))
	return Vector2(fraction, centroid_y)


static func buoyancy_force(density: float, displaced_volume: float, submerged_fraction: float, gravity: Vector3) -> Vector3:
	if density <= 0.0 or displaced_volume <= 0.0:
		return Vector3.ZERO
	return -gravity * density * displaced_volume * clampf(submerged_fraction, 0.0, 1.0)


static func quadratic_drag(density: float, coefficient: float, area: float, body_velocity_relative_to_fluid: Vector3) -> Vector3:
	if density <= 0.0 or coefficient <= 0.0 or area <= 0.0:
		return Vector3.ZERO
	var speed_squared: float = body_velocity_relative_to_fluid.length_squared()
	if speed_squared < 1.0e-12:
		return Vector3.ZERO
	return -0.5 * density * coefficient * area * sqrt(speed_squared) * body_velocity_relative_to_fluid


static func stokes_drag(dynamic_viscosity: float, radius: float, body_velocity_relative_to_fluid: Vector3) -> Vector3:
	if dynamic_viscosity <= 0.0 or radius <= 0.0:
		return Vector3.ZERO
	return -6.0 * PI * dynamic_viscosity * radius * body_velocity_relative_to_fluid


static func angular_drag(density: float, coefficient: float, radius: float, angular_velocity: Vector3) -> Vector3:
	# Rotational quadratic-drag approximation; force units are N*m.
	if density <= 0.0 or coefficient <= 0.0 or radius <= 0.0:
		return Vector3.ZERO
	var speed: float = angular_velocity.length()
	if speed < 1.0e-6:
		return Vector3.ZERO
	return -0.5 * density * coefficient * pow(radius, 5.0) * speed * angular_velocity


static func magnus_force(density: float, displaced_volume: float, coefficient: float, spin: Vector3, fluid_velocity_relative_to_body: Vector3) -> Vector3:
	# Simplified rotational lift, not a full vortex/wake CFD solution.
	if density <= 0.0 or displaced_volume <= 0.0 or coefficient == 0.0:
		return Vector3.ZERO
	return density * displaced_volume * coefficient * spin.cross(fluid_velocity_relative_to_body)


static func limit_opposing_force(force: Vector3, relative_velocity: Vector3, mass: float, delta: float, sample_count: int) -> Vector3:
	# Cap only the component opposing relative motion so explicit drag cannot
	# remove more than one sample's share of relative velocity per step.
	# This does not make coupled fluids or high-speed torque unconditionally stable.
	var speed_sq: float = relative_velocity.length_squared()
	if speed_sq < 1.0e-12 or mass <= 0.0 or delta <= 0.0:
		return force
	var damping: float = -force.dot(relative_velocity) / speed_sq
	if damping <= 0.0:
		return force
	var maximum_damping: float = mass / (delta * float(maxi(sample_count, 1)))
	if damping <= maximum_damping:
		return force
	return force * (maximum_damping / damping)
