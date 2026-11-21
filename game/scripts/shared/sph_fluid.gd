extends RefCounted
## 3D position-based fluids (PBF) particle solver.
##
## Algorithm: Macklin & Müller, "Position Based Fluids", ACM TOG 32(4), 2013
## (density constraint solved with Jacobi iterations, artificial pressure term
## against tensile instability, XSPH viscosity, vorticity confinement), built on
## the SPH kernels of Müller, Charypar & Gross, "Particle-Based Fluid Simulation
## for Interactive Applications", SCA 2003 (poly6 for density, spiky for gradients).
## Written from the published equations; no third-party source code copied.
## Reference implementations consulted for structure: Matthias Müller's
## Ten Minute Physics demos (MIT licence, https://github.com/matthias-research/pages).
##
## Fixed-box domain with a uniform counting-sort grid for neighbour search,
## sphere obstacles with two-way momentum transfer, optional vorticity confinement.

const BASE_DENSITY := 1000.0
const MAX_SPEED := 20.0

var spacing: float
var kernel_radius: float
var particle_mass: float
var rest_density: float
var gravity := Vector3(0.0, -9.81, 0.0)
var xsph_c := 0.02
var vorticity_epsilon := 0.0
var relaxation := 5.0
var tensile_k := 0.006
## 0 = density constraint only repels (surface particles are never pulled in); 1 = full PBF.
var attraction := 0.0
var bounds_min: Vector3
var bounds_max: Vector3
var wall_margin: float
var obstacle_gravity := false

var pos := PackedVector3Array()
var vel := PackedVector3Array()
var pred := PackedVector3Array()
var dens := PackedFloat32Array()
var lam := PackedFloat32Array()
var omega := PackedVector3Array()

var ob_center := PackedVector3Array()
var ob_next := PackedVector3Array()
var ob_radius := PackedFloat32Array()
var ob_vel := PackedVector3Array()
var ob_mass := PackedFloat32Array()
var ob_impulse := PackedVector3Array()

var _h2: float
var _poly6_coef: float
var _spiky_coef: float
var _dq_w: float
var _gx: int
var _gy: int
var _gz: int
var _grid_start := PackedInt32Array()
var _grid_items := PackedInt32Array()
var _cell_of := PackedInt32Array()
var _nb_start := PackedInt32Array()
var _nb_idx := PackedInt32Array()


func _init(p_spacing: float = 0.1, p_bounds_min: Vector3 = Vector3.ZERO, p_bounds_max: Vector3 = Vector3(2.0, 2.0, 2.0)) -> void:
	spacing = p_spacing
	kernel_radius = 2.0 * p_spacing
	bounds_min = p_bounds_min
	bounds_max = p_bounds_max
	wall_margin = 0.02 * p_spacing
	particle_mass = BASE_DENSITY * p_spacing * p_spacing * p_spacing
	_h2 = kernel_radius * kernel_radius
	var h9 := pow(kernel_radius, 9.0)
	var h6 := pow(kernel_radius, 6.0)
	_poly6_coef = 315.0 / (64.0 * PI * h9)
	_spiky_coef = 45.0 / (PI * h6)
	var dq := 0.2 * kernel_radius
	_dq_w = _poly6_coef * pow(_h2 - dq * dq, 3.0)
	_gx = int(ceil((bounds_max.x - bounds_min.x) / kernel_radius)) + 1
	_gy = int(ceil((bounds_max.y - bounds_min.y) / kernel_radius)) + 1
	_gz = int(ceil((bounds_max.z - bounds_min.z) / kernel_radius)) + 1
	_calibrate_rest_density()


## Rest density is the density a particle has inside a perfect lattice of the chosen spacing.
func _calibrate_rest_density() -> void:
	var acc := 0.0
	var reach := int(ceil(kernel_radius / spacing))
	for ix in range(-reach, reach + 1):
		for iy in range(-reach, reach + 1):
			for iz in range(-reach, reach + 1):
				var d2 := float(ix * ix + iy * iy + iz * iz) * spacing * spacing
				if d2 < _h2:
					acc += pow(_h2 - d2, 3.0)
	rest_density = particle_mass * _poly6_coef * acc


func add_particle(p_pos: Vector3, p_vel: Vector3 = Vector3.ZERO) -> void:
	pos.append(p_pos)
	vel.append(p_vel)
	pred.append(p_pos)
	dens.append(rest_density)
	lam.append(0.0)
	omega.append(Vector3.ZERO)


## Fills the axis-aligned box [lo, hi] with a cubic lattice; returns the number added.
func add_block(lo: Vector3, hi: Vector3) -> int:
	var added := 0
	var nx := int(floor((hi.x - lo.x) / spacing + 0.001)) + 1
	var ny := int(floor((hi.y - lo.y) / spacing + 0.001)) + 1
	var nz := int(floor((hi.z - lo.z) / spacing + 0.001)) + 1
	for ix in nx:
		for iy in ny:
			for iz in nz:
				add_particle(lo + Vector3(ix, iy, iz) * spacing)
				added += 1
	return added


func particle_count() -> int:
	return pos.size()


func positions() -> PackedVector3Array:
	return pos


func velocities() -> PackedVector3Array:
	return vel


func average_density() -> float:
	if dens.is_empty():
		return 0.0
	var acc := 0.0
	for value in dens:
		acc += value
	return acc / float(dens.size())


## Adds a sphere obstacle. mass <= 0 makes it kinematic (velocity never changes);
## otherwise fluid impulses change its velocity (two-way coupling). Returns its index.
func add_sphere_obstacle(center: Vector3, radius: float, velocity: Vector3 = Vector3.ZERO, p_mass: float = 0.0) -> int:
	ob_center.append(center)
	ob_next.append(center)
	ob_radius.append(radius)
	ob_vel.append(velocity)
	ob_mass.append(p_mass)
	ob_impulse.append(Vector3.ZERO)
	return ob_center.size() - 1


func obstacle_position(index: int) -> Vector3:
	return ob_center[index]


func obstacle_velocity(index: int) -> Vector3:
	return ob_vel[index]


func kinetic_energy() -> float:
	var acc := 0.0
	for v in vel:
		acc += 0.5 * particle_mass * v.length_squared()
	return acc


func total_momentum() -> Vector3:
	var acc := Vector3.ZERO
	for v in vel:
		acc += v
	return acc * particle_mass


func step(dt: float, iterations: int = 4) -> void:
	var count := pos.size()
	if count == 0 or dt <= 0.0:
		return
	for k in ob_center.size():
		ob_next[k] = ob_center[k] + ob_vel[k] * dt
		ob_impulse[k] = Vector3.ZERO
	for i in count:
		vel[i] += gravity * dt
		pred[i] = _collide(pos[i] + vel[i] * dt, dt)
	_build_neighbors()
	var inv_scale := particle_mass / rest_density
	for _it in maxi(iterations, 1):
		_solve_lambdas(count, inv_scale)
		var delta := PackedVector3Array()
		delta.resize(count)
		for i in count:
			delta[i] = _position_delta(i, inv_scale)
		for i in count:
			pred[i] = _collide(pred[i] + delta[i], dt)
	var inv_dt := 1.0 / dt
	for i in count:
		var nv := (pred[i] - pos[i]) * inv_dt
		var speed := nv.length()
		if speed > MAX_SPEED:
			nv *= MAX_SPEED / speed
		vel[i] = nv
	_apply_vorticity_and_viscosity(count, dt)
	for i in count:
		pos[i] = pred[i]
	for k in ob_center.size():
		if ob_mass[k] > 0.0:
			ob_vel[k] += ob_impulse[k] / ob_mass[k]
			if obstacle_gravity:
				ob_vel[k] += gravity * dt
		ob_center[k] = ob_next[k]


# --- internals -------------------------------------------------------------

func _cell_index(p_pos: Vector3) -> int:
	var cx := clampi(int((p_pos.x - bounds_min.x) / kernel_radius), 0, _gx - 1)
	var cy := clampi(int((p_pos.y - bounds_min.y) / kernel_radius), 0, _gy - 1)
	var cz := clampi(int((p_pos.z - bounds_min.z) / kernel_radius), 0, _gz - 1)
	return (cz * _gy + cy) * _gx + cx


@warning_ignore("integer_division")
func _build_neighbors() -> void:
	var count := pred.size()
	var cells := _gx * _gy * _gz
	_grid_start.resize(cells + 1)
	_grid_start.fill(0)
	_cell_of.resize(count)
	for i in count:
		var c := _cell_index(pred[i])
		_cell_of[i] = c
		_grid_start[c + 1] += 1
	for c in cells:
		_grid_start[c + 1] += _grid_start[c]
	_grid_items.resize(count)
	var cursor := _grid_start.duplicate()
	for i in count:
		var c2 := _cell_of[i]
		_grid_items[cursor[c2]] = i
		cursor[c2] += 1
	_nb_start.resize(count + 1)
	_nb_idx.clear()
	for i in count:
		_nb_start[i] = _nb_idx.size()
		var pi := pred[i]
		var cell := _cell_of[i]
		var cx := cell % _gx
		var cy := (cell / _gx) % _gy
		var cz := cell / (_gx * _gy)
		for oz in range(maxi(cz - 1, 0), mini(cz + 2, _gz)):
			for oy in range(maxi(cy - 1, 0), mini(cy + 2, _gy)):
				for ox in range(maxi(cx - 1, 0), mini(cx + 2, _gx)):
					var cc := (oz * _gy + oy) * _gx + ox
					for e in range(_grid_start[cc], _grid_start[cc + 1]):
						var j := _grid_items[e]
						if j != i and pi.distance_squared_to(pred[j]) < _h2:
							_nb_idx.append(j)
	_nb_start[count] = _nb_idx.size()


func _solve_lambdas(count: int, inv_scale: float) -> void:
	var self_w := _poly6_coef * pow(_h2, 3.0)
	for i in count:
		var pi := pred[i]
		var rho := particle_mass * self_w
		var grad_own := Vector3.ZERO
		var grad_sq := 0.0
		for e in range(_nb_start[i], _nb_start[i + 1]):
			var d := pi - pred[_nb_idx[e]]
			var r2 := d.length_squared()
			rho += particle_mass * _poly6_coef * pow(_h2 - r2, 3.0)
			var r := sqrt(r2)
			if r > 1e-9:
				var g := _grad_spiky(d, r) * inv_scale
				grad_own += g
				grad_sq += g.length_squared()
		grad_sq += grad_own.length_squared()
		dens[i] = rho
		var c_val := rho / rest_density - 1.0
		if c_val < 0.0:
			c_val *= attraction
		lam[i] = -c_val / (grad_sq + relaxation)


func _position_delta(i: int, inv_scale: float) -> Vector3:
	var pi := pred[i]
	var acc := Vector3.ZERO
	for e in range(_nb_start[i], _nb_start[i + 1]):
		var j := _nb_idx[e]
		var d := pi - pred[j]
		var r2 := d.length_squared()
		var r := sqrt(r2)
		if r < 1e-9:
			continue
		var w := _poly6_coef * pow(_h2 - r2, 3.0)
		var s_corr := -tensile_k * pow(w / _dq_w, 4.0)
		acc += (lam[i] + lam[j] + s_corr) * _grad_spiky(d, r)
	return acc * inv_scale


func _grad_spiky(d: Vector3, r: float) -> Vector3:
	var span := kernel_radius - r
	return d * (-_spiky_coef * span * span / r)


func _apply_vorticity_and_viscosity(count: int, dt: float) -> void:
	var inv_scale := particle_mass / rest_density
	var corrected := PackedVector3Array()
	corrected.resize(count)
	if vorticity_epsilon > 0.0:
		for i in count:
			var w_acc := Vector3.ZERO
			for e in range(_nb_start[i], _nb_start[i + 1]):
				var j := _nb_idx[e]
				var d := pred[i] - pred[j]
				var r := d.length()
				if r > 1e-9:
					w_acc += (vel[j] - vel[i]).cross(_grad_spiky(d, r)) * inv_scale
			omega[i] = w_acc
	for i in count:
		var nv := vel[i]
		var visc := Vector3.ZERO
		var eta := Vector3.ZERO
		for e in range(_nb_start[i], _nb_start[i + 1]):
			var j := _nb_idx[e]
			var d := pred[i] - pred[j]
			var r2 := d.length_squared()
			var r := sqrt(r2)
			var w := _poly6_coef * pow(_h2 - r2, 3.0)
			visc += (vel[j] - vel[i]) * (w * particle_mass / maxf(dens[j], 1e-6))
			if vorticity_epsilon > 0.0 and r > 1e-9:
				eta += _grad_spiky(d, r) * ((omega[j].length() - omega[i].length()) * inv_scale)
		nv += xsph_c * visc
		if vorticity_epsilon > 0.0 and eta.length() > 1e-6:
			var n_dir := eta.normalized()
			nv += vorticity_epsilon * n_dir.cross(omega[i]) * dt
		corrected[i] = nv
	for i in count:
		vel[i] = corrected[i]


## Keeps a position inside the box and outside all sphere obstacles; pushes on
## obstacles accumulate the reaction impulse (momentum conservation).
func _collide(p_pos: Vector3, dt: float) -> Vector3:
	var out := p_pos.clamp(bounds_min + Vector3.ONE * wall_margin, bounds_max - Vector3.ONE * wall_margin)
	for k in ob_center.size():
		var offset := out - ob_next[k]
		var reach := ob_radius[k] + wall_margin
		var l2 := offset.length_squared()
		if l2 < reach * reach:
			var l := sqrt(l2)
			var normal := offset / l if l > 1e-6 else Vector3.UP
			var surface := ob_next[k] + normal * reach
			ob_impulse[k] -= (surface - out) * (particle_mass / dt)
			out = surface
	return out
