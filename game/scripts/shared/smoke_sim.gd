extends RefCounted
## Volumetric smoke / fire simulation on a small 3D grid.
##
## Algorithm: Jos Stam, "Stable Fluids" (SIGGRAPH 1999) semi-Lagrangian advection and
## pressure projection (Jacobi relaxation); buoyancy and vorticity confinement after
## Fedkiw, Stam & Jensen, "Visual Simulation of Smoke" (SIGGRAPH 2001) and the
## GPU Gems 3 ch.30 (Crane, Llamas, Tariq) description of the same pipeline. Fire is a
## simple fuel -> heat + smoke reaction. This is an independent GDScript implementation
## written from those published papers (the papers describe algorithms, not code); no
## third-party source code is copied. Released with the project under its own licence.
##
## Units: cells and seconds. Cell centres sit at integer coordinates. Faces of the grid
## are open (zero pressure), obstacle voxels are solid walls.

const DEFAULT_SIZE := 24

const _DX := [1, -1, 0, 0, 0, 0]
const _DY := [0, 0, 1, -1, 0, 0]
const _DZ := [0, 0, 0, 0, 1, -1]

var size: int = DEFAULT_SIZE
var cell_count: int = 0
var wind: Vector3 = Vector3.ZERO
var wind_drag: float = 1.5            ## how fast velocity relaxes toward wind (1/s)
var buoyancy: float = 30.0            ## upward acceleration per unit temperature
var weight: float = 0.0               ## downward acceleration per unit density
var vorticity_strength: float = 2.0
var cooling: float = 0.8              ## temperature decay rate (1/s)
var density_decay: float = 0.05
var ignition_temperature: float = 0.4
var burn_rate: float = 4.0            ## fraction of fuel burnt per second
var heat_yield: float = 2.0           ## temperature released per unit fuel burnt
var smoke_yield: float = 1.0          ## density released per unit fuel burnt
var jacobi_iterations: int = 16
var max_speed: float = 40.0

var vx: PackedFloat32Array
var vy: PackedFloat32Array
var vz: PackedFloat32Array
var density: PackedFloat32Array
var temperature: PackedFloat32Array
var fuel: PackedFloat32Array
var obstacle: PackedByteArray

var _s0: PackedFloat32Array
var _s1: PackedFloat32Array
var _s2: PackedFloat32Array
var _pressure: PackedFloat32Array
var _div: PackedFloat32Array
var _ox: PackedFloat32Array
var _oy: PackedFloat32Array
var _oz: PackedFloat32Array
var _om: PackedFloat32Array


func _init(grid_size: int = DEFAULT_SIZE) -> void:
	size = maxi(4, grid_size)
	cell_count = size * size * size
	for name in ["vx", "vy", "vz", "density", "temperature", "fuel", "_s0", "_s1", "_s2", "_pressure", "_div", "_ox", "_oy", "_oz", "_om"]:
		var a := PackedFloat32Array()
		a.resize(cell_count)
		a.fill(0.0)
		set(name, a)
	obstacle = PackedByteArray()
	obstacle.resize(cell_count)
	obstacle.fill(0)


func index(x: int, y: int, z: int) -> int:
	return x + size * (y + size * z)


func in_bounds(cell: Vector3i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.z >= 0 and cell.x < size and cell.y < size and cell.z < size


func clear() -> void:
	for a in [vx, vy, vz, density, temperature, fuel]:
		(a as PackedFloat32Array).fill(0.0)


func add_source(cell: Vector3i, dens: float, temp: float = 0.0, fuel_amount: float = 0.0, velocity: Vector3 = Vector3.ZERO) -> void:
	if not in_bounds(cell):
		return
	var i := index(cell.x, cell.y, cell.z)
	if obstacle[i] != 0:
		return
	density[i] += dens
	temperature[i] += temp
	fuel[i] += fuel_amount
	vx[i] += velocity.x
	vy[i] += velocity.y
	vz[i] += velocity.z


func set_obstacle(cell: Vector3i, solid: bool) -> void:
	if not in_bounds(cell):
		return
	var i := index(cell.x, cell.y, cell.z)
	obstacle[i] = 1 if solid else 0
	if solid:
		_kill_cell(i)


func is_obstacle(cell: Vector3i) -> bool:
	return in_bounds(cell) and obstacle[index(cell.x, cell.y, cell.z)] != 0


func _kill_cell(i: int) -> void:
	vx[i] = 0.0
	vy[i] = 0.0
	vz[i] = 0.0
	density[i] = 0.0
	temperature[i] = 0.0
	fuel[i] = 0.0


func step(dt: float) -> void:
	if dt <= 0.0:
		return
	_apply_forces(dt)
	_vorticity_confinement(dt)
	_combust(dt)
	project()
	_advect(vx, _s0, dt)
	_advect(vy, _s1, dt)
	_advect(vz, _s2, dt)
	var tx := vx
	var ty := vy
	var tz := vz
	vx = _s0
	vy = _s1
	vz = _s2
	_s0 = tx
	_s1 = ty
	_s2 = tz
	project()
	_advect(density, _s0, dt)
	var td := density
	density = _s0
	_s0 = td
	_advect(temperature, _s0, dt)
	var tt := temperature
	temperature = _s0
	_s0 = tt
	_advect(fuel, _s0, dt)
	var tf := fuel
	fuel = _s0
	_s0 = tf
	_decay(dt)
	_enforce_obstacles()


func _apply_forces(dt: float) -> void:
	var drag := clampf(wind_drag * dt, 0.0, 1.0)
	for i in cell_count:
		if obstacle[i] != 0:
			continue
		vx[i] += (wind.x - vx[i]) * drag
		vy[i] += (wind.y - vy[i]) * drag
		vz[i] += (wind.z - vz[i]) * drag
		vy[i] += (buoyancy * temperature[i] - weight * density[i]) * dt
		vx[i] = clampf(vx[i], -max_speed, max_speed)
		vy[i] = clampf(vy[i], -max_speed, max_speed)
		vz[i] = clampf(vz[i], -max_speed, max_speed)


func _combust(dt: float) -> void:
	var frac := 1.0 - exp(-burn_rate * dt)
	for i in cell_count:
		var f := fuel[i]
		if f <= 0.0 or temperature[i] < ignition_temperature or obstacle[i] != 0:
			continue
		var burnt := f * frac
		fuel[i] = f - burnt
		temperature[i] += burnt * heat_yield
		density[i] += burnt * smoke_yield


func _decay(dt: float) -> void:
	var t_k := exp(-cooling * dt)
	var d_k := exp(-density_decay * dt)
	for i in cell_count:
		temperature[i] *= t_k
		density[i] *= d_k


func _enforce_obstacles() -> void:
	for i in cell_count:
		if obstacle[i] != 0:
			_kill_cell(i)


func _vorticity_confinement(dt: float) -> void:
	if vorticity_strength <= 0.0:
		return
	var n := size
	for z in n:
		for y in n:
			for x in n:
				var i := index(x, y, z)
				var wx := (_c(vz, x, y + 1, z) - _c(vz, x, y - 1, z) - _c(vy, x, y, z + 1) + _c(vy, x, y, z - 1)) * 0.5
				var wy := (_c(vx, x, y, z + 1) - _c(vx, x, y, z - 1) - _c(vz, x + 1, y, z) + _c(vz, x - 1, y, z)) * 0.5
				var wz := (_c(vy, x + 1, y, z) - _c(vy, x - 1, y, z) - _c(vx, x, y + 1, z) + _c(vx, x, y - 1, z)) * 0.5
				_ox[i] = wx
				_oy[i] = wy
				_oz[i] = wz
				_om[i] = sqrt(wx * wx + wy * wy + wz * wz)
	for z in range(1, n - 1):
		for y in range(1, n - 1):
			for x in range(1, n - 1):
				var i := index(x, y, z)
				if obstacle[i] != 0:
					continue
				var gx := (_om[index(x + 1, y, z)] - _om[index(x - 1, y, z)]) * 0.5
				var gy := (_om[index(x, y + 1, z)] - _om[index(x, y - 1, z)]) * 0.5
				var gz := (_om[index(x, y, z + 1)] - _om[index(x, y, z - 1)]) * 0.5
				var len := sqrt(gx * gx + gy * gy + gz * gz)
				if len < 1e-5:
					continue
				gx /= len
				gy /= len
				gz /= len
				var wx := _ox[i]
				var wy := _oy[i]
				var wz := _oz[i]
				var k := vorticity_strength * dt
				vx[i] += k * (gy * wz - gz * wy)
				vy[i] += k * (gz * wx - gx * wz)
				vz[i] += k * (gx * wy - gy * wx)


## Clamped fetch.
func _c(f: PackedFloat32Array, x: int, y: int, z: int) -> float:
	return f[clampi(x, 0, size - 1) + size * (clampi(y, 0, size - 1) + size * clampi(z, 0, size - 1))]


func sample(f: PackedFloat32Array, px: float, py: float, pz: float) -> float:
	var hi := float(size - 1)
	px = clampf(px, 0.0, hi)
	py = clampf(py, 0.0, hi)
	pz = clampf(pz, 0.0, hi)
	var x0 := int(px)
	var y0 := int(py)
	var z0 := int(pz)
	var x1 := mini(x0 + 1, size - 1)
	var y1 := mini(y0 + 1, size - 1)
	var z1 := mini(z0 + 1, size - 1)
	var fx := px - x0
	var fy := py - y0
	var fz := pz - z0
	var n := size
	var b00 := x0 + n * (y0 + n * z0)
	var b10 := x1 + n * (y0 + n * z0)
	var b01 := x0 + n * (y1 + n * z0)
	var b11 := x1 + n * (y1 + n * z0)
	var t00 := x0 + n * (y0 + n * z1)
	var t10 := x1 + n * (y0 + n * z1)
	var t01 := x0 + n * (y1 + n * z1)
	var t11 := x1 + n * (y1 + n * z1)
	var a := lerpf(lerpf(f[b00], f[b10], fx), lerpf(f[b01], f[b11], fx), fy)
	var b := lerpf(lerpf(f[t00], f[t10], fx), lerpf(f[t01], f[t11], fx), fy)
	return lerpf(a, b, fz)


## Stam semi-Lagrangian advection: trace each cell centre back along the velocity field.
func _advect(src: PackedFloat32Array, dst: PackedFloat32Array, dt: float) -> void:
	var n := size
	for z in n:
		for y in n:
			for x in n:
				var i := x + n * (y + n * z)
				if obstacle[i] != 0:
					dst[i] = 0.0
					continue
				dst[i] = sample(src, x - dt * vx[i], y - dt * vy[i], z - dt * vz[i])


func _nvel(f: PackedFloat32Array, i: int, x: int, y: int, z: int) -> float:
	if x < 0 or y < 0 or z < 0 or x >= size or y >= size or z >= size:
		return f[i]
	var j := x + size * (y + size * z)
	if obstacle[j] != 0:
		return 0.0
	return f[j]


func _compute_divergence() -> void:
	var n := size
	for z in n:
		for y in n:
			for x in n:
				var i := x + n * (y + n * z)
				if obstacle[i] != 0:
					_div[i] = 0.0
					continue
				_div[i] = 0.5 * (
					_nvel(vx, i, x + 1, y, z) - _nvel(vx, i, x - 1, y, z)
					+ _nvel(vy, i, x, y + 1, z) - _nvel(vy, i, x, y - 1, z)
					+ _nvel(vz, i, x, y, z + 1) - _nvel(vz, i, x, y, z - 1))


## Root-mean-square divergence over fluid cells (0 = incompressible).
func divergence_rms() -> float:
	_compute_divergence()
	var s := 0.0
	var c := 0
	for i in cell_count:
		if obstacle[i] == 0:
			s += _div[i] * _div[i]
			c += 1
	return sqrt(s / maxf(1.0, float(c)))


## Pressure projection: solve laplacian(p) = div(v) with Jacobi and subtract grad(p).
func project() -> void:
	_compute_divergence()
	var n := size
	_pressure.fill(0.0)
	for _it in jacobi_iterations:
		for z in n:
			for y in n:
				for x in n:
					var i := x + n * (y + n * z)
					if obstacle[i] != 0:
						_s0[i] = 0.0
						continue
					var sum := 0.0
					var cnt := 0
					for d in 6:
						var nx: int = x + _DX[d]
						var ny: int = y + _DY[d]
						var nz: int = z + _DZ[d]
						if nx < 0 or ny < 0 or nz < 0 or nx >= n or ny >= n or nz >= n:
							cnt += 1
							continue
						var j := nx + n * (ny + n * nz)
						if obstacle[j] != 0:
							continue
						cnt += 1
						sum += _pressure[j]
					_s0[i] = (sum - _div[i]) / float(cnt) if cnt > 0 else 0.0
		var t := _pressure
		_pressure = _s0
		_s0 = t
	for z in n:
		for y in n:
			for x in n:
				var i := x + n * (y + n * z)
				if obstacle[i] != 0:
					continue
				vx[i] -= 0.5 * (_pn(i, x + 1, y, z) - _pn(i, x - 1, y, z))
				vy[i] -= 0.5 * (_pn(i, x, y + 1, z) - _pn(i, x, y - 1, z))
				vz[i] -= 0.5 * (_pn(i, x, y, z + 1) - _pn(i, x, y, z - 1))


func _pn(i: int, x: int, y: int, z: int) -> float:
	if x < 0 or y < 0 or z < 0 or x >= size or y >= size or z >= size:
		return 0.0
	var j := x + size * (y + size * z)
	if obstacle[j] != 0:
		return _pressure[i]
	return _pressure[j]


func total_density() -> float:
	return _sum(density)


func total_temperature() -> float:
	return _sum(temperature)


func total_fuel() -> float:
	return _sum(fuel)


func _sum(f: PackedFloat32Array) -> float:
	var s := 0.0
	for v in f:
		s += v
	return s


func max_temperature() -> float:
	var m := 0.0
	for v in temperature:
		m = maxf(m, v)
	return m


## Density-weighted centre of mass in cell coordinates.
func density_centroid() -> Vector3:
	var total := 0.0
	var c := Vector3.ZERO
	for z in size:
		for y in size:
			for x in size:
				var d := density[index(x, y, z)]
				total += d
				c += Vector3(x, y, z) * d
	return c / total if total > 1e-9 else Vector3.ZERO


func is_finite_state() -> bool:
	for a in [vx, vy, vz, density, temperature, fuel]:
		for v in (a as PackedFloat32Array):
			if is_nan(v) or is_inf(v):
				return false
	return true


## One RG float image per z slice (R = density, G = temperature) for ImageTexture3D.create.
func density_image_slices() -> Array[Image]:
	var out: Array[Image] = []
	var n := size
	for z in n:
		var raw := PackedFloat32Array()
		raw.resize(n * n * 2)
		for y in n:
			for x in n:
				var i := x + n * (y + n * z)
				var o := 2 * (x + n * y)
				raw[o] = density[i]
				raw[o + 1] = temperature[i]
		out.append(Image.create_from_data(n, n, false, Image.FORMAT_RGF, raw.to_byte_array()))
	return out


func to_image3d() -> ImageTexture3D:
	var tex := ImageTexture3D.new()
	var err := tex.create(Image.FORMAT_RGF, size, size, size, false, density_image_slices())
	return tex if err == OK else null


## Refreshes an existing texture in place (cheaper than re-creating it every frame).
func update_image3d(tex: ImageTexture3D) -> void:
	tex.update(density_image_slices())
