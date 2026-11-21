extends RefCounted
## Shallow-water heightfield solver using the virtual pipes method (Mei, Decaudin,
## Hu 2007, "Fast Hydraulic Erosion Simulation and Visualization on GPU").
## Each cell exchanges water with its 4 neighbours through pipes driven by the
## surface height difference. Outflow is scaled so a cell never gives away more
## than it holds (depth stays >= 0) and boundaries are closed, so volume is
## conserved. Intended for floods and puddles, in the spirit of Unreal's
## Water/Fluid Flux and flood systems in survival games.

const GRAVITY: float = 9.81
const FLUX_DAMPING: float = 0.999
const MAX_SUBSTEPS: int = 32

var width: int = 0
var height: int = 0
var cell_size: float = 1.0

var _terrain: PackedFloat32Array = PackedFloat32Array()
var _depth: PackedFloat32Array = PackedFloat32Array()
# Outflow volume rates (m^3/s) toward -x, +x, -y, +y neighbours.
var _f_left: PackedFloat32Array = PackedFloat32Array()
var _f_right: PackedFloat32Array = PackedFloat32Array()
var _f_up: PackedFloat32Array = PackedFloat32Array()
var _f_down: PackedFloat32Array = PackedFloat32Array()


func setup(grid_w: int, grid_h: int, cell: float, terrain: PackedFloat32Array) -> void:
	width = grid_w
	height = grid_h
	cell_size = cell
	var count: int = width * height
	_terrain = terrain.duplicate()
	_terrain.resize(count)
	_depth = PackedFloat32Array()
	_depth.resize(count)
	_f_left = _depth.duplicate()
	_f_right = _depth.duplicate()
	_f_up = _depth.duplicate()
	_f_down = _depth.duplicate()


func add_water(cell: Vector2i, depth: float) -> void:
	if not _in_bounds(cell):
		return
	var idx: int = cell.y * width + cell.x
	_depth[idx] = maxf(_depth[idx] + depth, 0.0)


func depth_at(cell: Vector2i) -> float:
	if not _in_bounds(cell):
		return 0.0
	return _depth[cell.y * width + cell.x]


func terrain_at(cell: Vector2i) -> float:
	if not _in_bounds(cell):
		return 0.0
	return _terrain[cell.y * width + cell.x]


func total_volume() -> float:
	var sum: float = 0.0
	for d in _depth:
		sum += d
	return sum * cell_size * cell_size


func velocity_at(cell: Vector2i) -> Vector2:
	if not _in_bounds(cell):
		return Vector2.ZERO
	var x: int = cell.x
	var y: int = cell.y
	var idx: int = y * width + x
	var d: float = _depth[idx]
	if d < 1e-4:
		return Vector2.ZERO
	var in_l: float = _f_right[idx - 1] if x > 0 else 0.0
	var in_r: float = _f_left[idx + 1] if x < width - 1 else 0.0
	var in_u: float = _f_down[idx - width] if y > 0 else 0.0
	var in_d: float = _f_up[idx + width] if y < height - 1 else 0.0
	var dwx: float = 0.5 * (in_l - _f_left[idx] + _f_right[idx] - in_r)
	var dwy: float = 0.5 * (in_u - _f_up[idx] + _f_down[idx] - in_d)
	var denom: float = cell_size * d
	return Vector2(dwx / denom, dwy / denom)


func step(delta: float) -> void:
	if width == 0 or delta <= 0.0:
		return
	var max_depth: float = 0.0
	for d in _depth:
		max_depth = maxf(max_depth, d)
	# CFL-style substep: wave speed sqrt(g*d) must not cross a cell per substep.
	var wave: float = sqrt(GRAVITY * maxf(max_depth, 0.01))
	var max_dt: float = 0.5 * cell_size / wave
	var subs: int = clampi(ceili(delta / max_dt), 1, MAX_SUBSTEPS)
	var dt: float = delta / float(subs)
	for s in subs:
		_substep(dt)


func _substep(dt: float) -> void:
	var area: float = cell_size * cell_size
	var gain: float = dt * GRAVITY * cell_size
	for y in height:
		for x in width:
			var idx: int = y * width + x
			var surf: float = _terrain[idx] + _depth[idx]
			var fl: float = 0.0
			var fr: float = 0.0
			var fu: float = 0.0
			var fd: float = 0.0
			if x > 0:
				fl = maxf(_f_left[idx] * FLUX_DAMPING + gain * (surf - _terrain[idx - 1] - _depth[idx - 1]), 0.0)
			if x < width - 1:
				fr = maxf(_f_right[idx] * FLUX_DAMPING + gain * (surf - _terrain[idx + 1] - _depth[idx + 1]), 0.0)
			if y > 0:
				fu = maxf(_f_up[idx] * FLUX_DAMPING + gain * (surf - _terrain[idx - width] - _depth[idx - width]), 0.0)
			if y < height - 1:
				fd = maxf(_f_down[idx] * FLUX_DAMPING + gain * (surf - _terrain[idx + width] - _depth[idx + width]), 0.0)
			var total: float = (fl + fr + fu + fd) * dt
			var avail: float = _depth[idx] * area
			if total > avail and total > 0.0:
				var k: float = avail / total
				fl *= k
				fr *= k
				fu *= k
				fd *= k
			_f_left[idx] = fl
			_f_right[idx] = fr
			_f_up[idx] = fu
			_f_down[idx] = fd
	for y in height:
		for x in width:
			var idx: int = y * width + x
			var inflow: float = 0.0
			if x > 0:
				inflow += _f_right[idx - 1]
			if x < width - 1:
				inflow += _f_left[idx + 1]
			if y > 0:
				inflow += _f_down[idx - width]
			if y < height - 1:
				inflow += _f_up[idx + width]
			var outflow: float = _f_left[idx] + _f_right[idx] + _f_up[idx] + _f_down[idx]
			_depth[idx] = maxf(_depth[idx] + dt * (inflow - outflow) / area, 0.0)


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height
