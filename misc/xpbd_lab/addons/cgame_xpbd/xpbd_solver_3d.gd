extends RefCounted
class_name CgameXPBDSolver3D
## Standalone CPU XPBD point-mass solver for ropes and cloth.
## Units: meters, kilograms, seconds. Integrates independently of Jolt.
## Collision support is intentionally one-way against user supplied static
## planes and spheres; no two-way rigid body coupling is claimed.

var positions: Array[Vector3] = []
var previous_positions: Array[Vector3] = []
var velocities: Array[Vector3] = []
var inverse_masses: PackedFloat32Array = PackedFloat32Array()
var constraints: Array[Dictionary] = []

var solver_iterations: int = 12
var substeps: int = 2
var velocity_damping: float = 0.015 # 1/s
var wind_drag: float = 0.4 # 1/s toward wind velocity
var particle_radius: float = 0.04
var collision_friction: float = 0.15
var floor_enabled: bool = false
var floor_height: float = 0.0
var sphere_colliders: Array[Dictionary] = []


func reset() -> void:
	positions.clear()
	previous_positions.clear()
	velocities.clear()
	inverse_masses = PackedFloat32Array()
	constraints.clear()
	sphere_colliders.clear()


func particle_count() -> int:
	return positions.size()


func add_particle(point: Vector3, mass: float = 1.0, pinned: bool = false) -> int:
	var index: int = positions.size()
	positions.append(point)
	previous_positions.append(point)
	velocities.append(Vector3.ZERO)
	inverse_masses.append(0.0 if pinned or mass <= 0.0 else 1.0 / mass)
	return index


func pin_particle(index: int, point: Vector3) -> void:
	if index < 0 or index >= particle_count():
		return
	inverse_masses[index] = 0.0
	positions[index] = point
	previous_positions[index] = point
	velocities[index] = Vector3.ZERO


func add_distance_constraint(a: int, b: int, compliance: float = 0.0, tear_strain: float = 0.0, kind: String = "stretch") -> int:
	if a < 0 or b < 0 or a >= particle_count() or b >= particle_count() or a == b:
		return -1
	var rest_length: float = positions[a].distance_to(positions[b])
	if rest_length <= 0.000001:
		return -1
	constraints.append({
		"a": a,
		"b": b,
		"rest": rest_length,
		"compliance": maxf(0.0, compliance), # m/N
		"tear_strain": maxf(0.0, tear_strain), # 0 disables tearing
		"lambda": 0.0,
		"active": true,
		"kind": kind,
	})
	return constraints.size() - 1


func add_sphere_collider(center: Vector3, radius: float) -> void:
	if radius > 0.0:
		sphere_colliders.append({"center": center, "radius": radius})


func clear_sphere_colliders() -> void:
	sphere_colliders.clear()


func create_rope(start: Vector3, finish: Vector3, segments: int, total_mass: float = 1.0, compliance: float = 0.000001, bend_compliance: float = 0.0001, pin_start: bool = true, pin_end: bool = false, tear_strain: float = 0.0) -> void:
	reset()
	var n: int = maxi(1, segments)
	var mass_per_particle: float = maxf(0.000001, total_mass / float(n + 1))
	for i in range(n + 1):
		var t: float = float(i) / float(n)
		add_particle(start.lerp(finish, t), mass_per_particle, (i == 0 and pin_start) or (i == n and pin_end))
	for i in range(n):
		add_distance_constraint(i, i + 1, compliance, tear_strain, "stretch")
	for i in range(n - 1):
		add_distance_constraint(i, i + 2, bend_compliance, tear_strain, "bend")


func create_cloth(origin: Vector3, columns: int, rows: int, spacing: float = 0.25, total_mass: float = 1.0, stretch_compliance: float = 0.000001, shear_compliance: float = 0.00001, bend_compliance: float = 0.0005, pin_top_corners: bool = true, tear_strain: float = 0.0) -> void:
	reset()
	var cols: int = maxi(2, columns)
	var nrows: int = maxi(2, rows)
	var step: float = maxf(0.0001, spacing)
	var mass_per_particle: float = maxf(0.000001, total_mass / float(cols * nrows))
	for y in range(nrows):
		for x in range(cols):
			var pin: bool = pin_top_corners and y == 0 and (x == 0 or x == cols - 1)
			add_particle(origin + Vector3(float(x) * step, -float(y) * step, 0.0), mass_per_particle, pin)
	for y in range(nrows):
		for x in range(cols):
			var a: int = y * cols + x
			if x + 1 < cols:
				add_distance_constraint(a, a + 1, stretch_compliance, tear_strain, "stretch")
			if y + 1 < nrows:
				add_distance_constraint(a, a + cols, stretch_compliance, tear_strain, "stretch")
			if x + 1 < cols and y + 1 < nrows:
				add_distance_constraint(a, a + cols + 1, shear_compliance, tear_strain, "shear")
				add_distance_constraint(a + 1, a + cols, shear_compliance, tear_strain, "shear")
			if x + 2 < cols:
				add_distance_constraint(a, a + 2, bend_compliance, tear_strain, "bend")
			if y + 2 < nrows:
				add_distance_constraint(a, a + 2 * cols, bend_compliance, tear_strain, "bend")


func step(delta: float, gravity: Vector3 = Vector3(0.0, -9.81, 0.0), wind_velocity: Vector3 = Vector3.ZERO) -> void:
	if delta <= 0.0 or not is_finite(delta) or positions.is_empty():
		return
	# Bound the total integration step to protect the prototype from hitches.
	# This deliberately slows simulated time if a frame is very long.
	var dt: float = minf(delta, 1.0 / 15.0)
	var h: float = dt / float(maxi(1, mini(substeps, 16)))
	var damping_factor: float = exp(-maxf(0.0, velocity_damping) * h)
	var wind_factor: float = 1.0 - exp(-maxf(0.0, wind_drag) * h)
	for substep in range(maxi(1, mini(substeps, 16))):
		# Pin positions have inv_mass=0 and remain entirely unchanged.
		for i in range(particle_count()):
			previous_positions[i] = positions[i]
			if inverse_masses[i] == 0.0:
				velocities[i] = Vector3.ZERO
				continue
			var v: Vector3 = velocities[i] * damping_factor + gravity * h
			v += (wind_velocity - v) * wind_factor
			velocities[i] = v
			positions[i] += v * h

		for j in range(constraints.size()):
			var c: Dictionary = constraints[j]
			c["lambda"] = 0.0
			constraints[j] = c

		var touched: PackedByteArray = PackedByteArray()
		touched.resize(particle_count())
		var normals: Array[Vector3] = []
		normals.resize(particle_count())
		normals.fill(Vector3.UP)
		for iteration in range(maxi(1, mini(solver_iterations, 64))):
			for j in range(constraints.size()):
				_project_distance(j, h)
			_project_collisions(touched, normals)

		for i in range(particle_count()):
			if inverse_masses[i] == 0.0:
				continue
			var next_v: Vector3 = (positions[i] - previous_positions[i]) / h
			if touched[i] != 0:
				var normal: Vector3 = normals[i]
				var tangent: Vector3 = next_v - normal * next_v.dot(normal)
				next_v -= tangent * clampf(collision_friction, 0.0, 1.0)
			velocities[i] = next_v if next_v.is_finite() else Vector3.ZERO


func _project_distance(index: int, h: float) -> void:
	var c: Dictionary = constraints[index]
	if not c["active"]:
		return
	var a: int = c["a"]
	var b: int = c["b"]
	var w_a: float = inverse_masses[a]
	var w_b: float = inverse_masses[b]
	if w_a + w_b <= 0.0:
		return
	var delta_position: Vector3 = positions[a] - positions[b]
	var distance: float = delta_position.length()
	if distance < 0.0000001:
		return
	var rest: float = c["rest"]
	var tear: float = c["tear_strain"]
	if tear > 0.0 and distance > rest * (1.0 + tear):
		c["active"] = false
		c["lambda"] = 0.0
		constraints[index] = c
		return
	# XPBD: Δλ=(-C-αλ)/(Σw|∇C|²+α), α=compliance/h².
	var alpha: float = c["compliance"] / (h * h)
	var grad: Vector3 = delta_position / distance
	var dlambda: float = (-(distance - rest) - alpha * c["lambda"]) / (w_a + w_b + alpha)
	if not is_finite(dlambda):
		return
	positions[a] += grad * (w_a * dlambda)
	positions[b] -= grad * (w_b * dlambda)
	c["lambda"] += dlambda
	constraints[index] = c


func _project_collisions(touched: PackedByteArray, normals: Array[Vector3]) -> void:
	var radius: float = maxf(0.0, particle_radius)
	for i in range(particle_count()):
		if inverse_masses[i] == 0.0:
			continue
		var point: Vector3 = positions[i]
		if floor_enabled and point.y < floor_height + radius:
			point.y = floor_height + radius
			touched[i] = 1
			normals[i] = Vector3.UP
		for sphere in sphere_colliders:
			var center: Vector3 = sphere["center"]
			var target_radius: float = sphere["radius"] + radius
			var diff: Vector3 = point - center
			var distance_squared: float = diff.length_squared()
			if distance_squared >= target_radius * target_radius:
				continue
			var outward: Vector3 = diff.normalized() if distance_squared > 0.0000000001 else Vector3.UP
			point = center + outward * target_radius
			touched[i] = 1
			normals[i] = outward
		positions[i] = point


func broken_constraint_count() -> int:
	var count: int = 0
	for c in constraints:
		if not c["active"]:
			count += 1
	return count


func active_constraint_count() -> int:
	return constraints.size() - broken_constraint_count()


func max_relative_stretch() -> float:
	var biggest: float = 0.0
	for c in constraints:
		if c["active"]:
			var length: float = positions[c["a"]].distance_to(positions[c["b"]])
			biggest = maxf(biggest, absf(length / c["rest"] - 1.0))
	return biggest
