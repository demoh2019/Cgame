extends RefCounted
## 2D FLIP/PIC fluid on a MAC (staggered) grid with solid cells and a moving circle obstacle.
##
## Method: Zhu & Bridson, "Animating Sand as a Fluid", SIGGRAPH 2005 (FLIP) and
## Harlow & Welch 1965 (MAC grid / PIC).
## The structure of the step (particle push-apart, particle-to-grid transfer with
## bilinear weights, Gauss-Seidel pressure projection with over-relaxation, density
## based drift compensation, PIC/FLIP blend on the way back) follows Matthias Müller's
## "Ten Minute Physics" tutorial 18 "How to write a FLIP water/fluid simulation",
## https://github.com/matthias-research/pages (MIT License, Copyright (c) 2022
## Matthias Müller). Re-written in GDScript with y-up coordinates, interleaved
## velocity storage, destructible walls (set_solid) and an obstacle that is also
## a particle collider. Velocity grid: component 0 = u on left cell faces,
## component 1 = v on bottom cell faces, index = (i * rows + j) * 2 + component.

const FLUID := 0
const AIR := 1
const SOLID := 2

var cols: int
var rows: int
var cs: float
var inv_cs: float
var particle_radius: float

var gravity := Vector2(0.0, -9.81)
var flip_ratio := 0.9
var pressure_iterations := 40
var push_iterations := 2
var over_relaxation := 1.9
var compensate_drift := true
var fluid_density := 1000.0

var obstacle_active := false
var obstacle_center := Vector2.ZERO
var obstacle_radius := 0.0
var obstacle_velocity := Vector2.ZERO

var last_divergence_before := 0.0

var ppos := PackedVector2Array()
var pvel := PackedVector2Array()
var pprev := PackedVector2Array()

var gv := PackedFloat32Array()
var gprev := PackedFloat32Array()
var gwt := PackedFloat32Array()
var s_open := PackedFloat32Array()
var wall := PackedByteArray()
var obst := PackedByteArray()
var cell_type := PackedInt32Array()
var cell_density := PackedFloat32Array()
var rest_particle_density := 0.0

var _pg_cols: int
var _pg_rows: int
var _pg_start := PackedInt32Array()
var _pg_items := PackedInt32Array()


func _init(p_cols: int = 32, p_rows: int = 32, p_cell_size: float = 0.1) -> void:
	cols = maxi(p_cols, 4)
	rows = maxi(p_rows, 4)
	cs = p_cell_size
	inv_cs = 1.0 / p_cell_size
	particle_radius = 0.3 * p_cell_size
	var total := cols * rows
	gv.resize(total * 2)
	gprev.resize(total * 2)
	gwt.resize(total * 2)
	s_open.resize(total)
	wall.resize(total)
	obst.resize(total)
	cell_type.resize(total)
	cell_density.resize(total)
	for i in cols:
		for j in rows:
			if i == 0 or j == 0 or i == cols - 1 or j == rows - 1:
				wall[i * rows + j] = 1
	var pcs := 2.2 * particle_radius
	_pg_cols = int(float(cols) * cs / pcs) + 2
	_pg_rows = int(float(rows) * cs / pcs) + 2
	_rebuild_solids()
	_classify()


# --- public API ------------------------------------------------------------

func particle_count() -> int:
	return ppos.size()


func particle_positions() -> PackedVector2Array:
	return ppos


func cell_of(p_pos: Vector2) -> Vector2i:
	return Vector2i(clampi(int(floor(p_pos.x * inv_cs)), 0, cols - 1), clampi(int(floor(p_pos.y * inv_cs)), 0, rows - 1))


func cell_type_at(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= cols or cell.y >= rows:
		return SOLID
	return cell_type[cell.x * rows + cell.y]


func is_wall(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= cols or cell.y >= rows:
		return true
	return wall[cell.x * rows + cell.y] != 0


## Turns a cell into a wall or opens it again (destructible barrier). The outer border is permanent.
func set_solid(cell: Vector2i, solid: bool) -> void:
	if cell.x <= 0 or cell.y <= 0 or cell.x >= cols - 1 or cell.y >= rows - 1:
		return
	wall[cell.x * rows + cell.y] = 1 if solid else 0
	_rebuild_solids()
	_classify()


func set_obstacle(center: Vector2, radius: float, velocity: Vector2 = Vector2.ZERO) -> void:
	obstacle_active = true
	obstacle_center = center
	obstacle_radius = radius
	obstacle_velocity = velocity
	_rebuild_solids()


func clear_obstacle() -> void:
	obstacle_active = false
	_rebuild_solids()


## Fills a box with a hex lattice of particles (skipping walls); returns how many were added.
func add_water_block(lo: Vector2, hi: Vector2) -> int:
	var added := 0
	var dxp := 2.0 * particle_radius
	var dyp := sqrt(3.0) * 0.5 * dxp
	var row_index := 0
	var y := lo.y
	while y <= hi.y:
		var x := lo.x + (0.5 * dxp if row_index % 2 == 1 else 0.0)
		while x <= hi.x:
			var p := Vector2(x, y)
			if not is_wall(cell_of(p)):
				ppos.append(p)
				pprev.append(p)
				pvel.append(Vector2.ZERO)
				added += 1
			x += dxp
		y += dyp
		row_index += 1
	return added


func step(dt: float) -> void:
	if ppos.is_empty() or dt <= 0.0:
		return
	if obstacle_active:
		obstacle_center += obstacle_velocity * dt
		_rebuild_solids()
	_integrate(dt)
	_push_apart()
	for i in ppos.size():
		_collide(i)
	_to_grid()
	_update_density()
	_solve_incompressibility()
	_from_grid()
	_classify()


## Largest |divergence| over fluid cells of the current grid velocity.
func divergence_max() -> float:
	var worst := 0.0
	for i in range(1, cols - 1):
		for j in range(1, rows - 1):
			var c := i * rows + j
			if cell_type[c] != FLUID:
				continue
			var div := gv[2 * (c + rows)] - gv[2 * c] + gv[2 * (c + 1) + 1] - gv[2 * c + 1]
			worst = maxf(worst, absf(div))
	return worst


func average_height() -> float:
	if ppos.is_empty():
		return 0.0
	var acc := 0.0
	for p in ppos:
		acc += p.y
	return acc / float(ppos.size())


func kinetic_energy() -> float:
	var acc := 0.0
	for v in pvel:
		acc += 0.5 * v.length_squared()
	return acc


# --- internals -------------------------------------------------------------

func _rebuild_solids() -> void:
	obst.fill(0)
	if obstacle_active:
		var r2 := obstacle_radius * obstacle_radius
		for i in range(1, cols - 1):
			for j in range(1, rows - 1):
				var d := Vector2((float(i) + 0.5) * cs, (float(j) + 0.5) * cs) - obstacle_center
				if d.length_squared() < r2:
					obst[i * rows + j] = 1
	for c in cols * rows:
		s_open[c] = 0.0 if (wall[c] != 0 or obst[c] != 0) else 1.0


func _classify() -> void:
	var counts := PackedInt32Array()
	counts.resize(cols * rows)
	for p in ppos:
		var cell := cell_of(p)
		counts[cell.x * rows + cell.y] += 1
	for c in cols * rows:
		if s_open[c] == 0.0:
			cell_type[c] = SOLID
		else:
			cell_type[c] = FLUID if counts[c] > 0 else AIR


func _wall_at(p: Vector2) -> bool:
	return is_wall(Vector2i(int(floor(p.x * inv_cs)), int(floor(p.y * inv_cs))))


func _integrate(dt: float) -> void:
	for i in ppos.size():
		pprev[i] = ppos[i]
		pvel[i] += gravity * dt
		ppos[i] += pvel[i] * dt


func _push_apart() -> void:
	var count := ppos.size()
	var pcs := 2.2 * particle_radius
	var inv_pcs := 1.0 / pcs
	var min_dist := 2.0 * particle_radius
	var min_dist2 := min_dist * min_dist
	var cells := _pg_cols * _pg_rows
	for _it in push_iterations:
		_pg_start.resize(cells + 1)
		_pg_start.fill(0)
		var cell_ids := PackedInt32Array()
		cell_ids.resize(count)
		for i in count:
			var gx := clampi(int(ppos[i].x * inv_pcs), 0, _pg_cols - 1)
			var gy := clampi(int(ppos[i].y * inv_pcs), 0, _pg_rows - 1)
			cell_ids[i] = gx * _pg_rows + gy
			_pg_start[cell_ids[i] + 1] += 1
		for c in cells:
			_pg_start[c + 1] += _pg_start[c]
		_pg_items.resize(count)
		var cursor := _pg_start.duplicate()
		for i in count:
			_pg_items[cursor[cell_ids[i]]] = i
			cursor[cell_ids[i]] += 1
		for i in count:
			var gx2 := clampi(int(ppos[i].x * inv_pcs), 0, _pg_cols - 1)
			var gy2 := clampi(int(ppos[i].y * inv_pcs), 0, _pg_rows - 1)
			for ox in range(maxi(gx2 - 1, 0), mini(gx2 + 2, _pg_cols)):
				for oy in range(maxi(gy2 - 1, 0), mini(gy2 + 2, _pg_rows)):
					var cc := ox * _pg_rows + oy
					for e in range(_pg_start[cc], _pg_start[cc + 1]):
						var j := _pg_items[e]
						if j <= i:
							continue
						var d := ppos[j] - ppos[i]
						var d2 := d.length_squared()
						if d2 >= min_dist2 or d2 < 1e-12:
							continue
						var dl := sqrt(d2)
						var push := d * (0.5 * (min_dist - dl) / dl)
						ppos[i] -= push
						ppos[j] += push


## Keeps particle i out of walls (swept test, so thin walls are never tunnelled), out
## of the obstacle circle, and inside the domain.
func _collide(i: int) -> void:
	var p := ppos[i]
	var q := pprev[i]
	var v := pvel[i]
	var travel := p - q
	var dist := travel.length()
	if dist > 0.5 * cs and not _wall_at(q):
		var steps := int(ceil(dist / (0.5 * cs)))
		var last := q
		for n in range(1, steps + 1):
			var sample := q + travel * (float(n) / float(steps))
			if _wall_at(sample):
				var hit_x := _wall_at(Vector2(sample.x, last.y))
				var hit_y := _wall_at(Vector2(last.x, sample.y))
				if hit_x or not hit_y:
					v.x = 0.0
				if hit_y or not hit_x:
					v.y = 0.0
				p = last
				break
			last = sample
	if obstacle_active:
		var off := p - obstacle_center
		var reach := obstacle_radius + particle_radius
		var l2 := off.length_squared()
		if l2 < reach * reach:
			var l := sqrt(l2)
			var normal := off / l if l > 1e-6 else Vector2.UP
			p = obstacle_center + normal * reach
			var vn := (v - obstacle_velocity).dot(normal)
			if vn < 0.0:
				v -= normal * vn
	if _wall_at(p):
		var cell := cell_of(p)
		var best := INF
		var target := q
		var eps := 0.01 * cs
		if not is_wall(cell + Vector2i(-1, 0)):
			var dd := p.x - (float(cell.x) * cs - eps)
			if dd < best:
				best = dd
				target = Vector2(float(cell.x) * cs - eps, p.y)
		if not is_wall(cell + Vector2i(1, 0)):
			var dd2 := (float(cell.x + 1) * cs + eps) - p.x
			if dd2 < best:
				best = dd2
				target = Vector2(float(cell.x + 1) * cs + eps, p.y)
		if not is_wall(cell + Vector2i(0, -1)):
			var dd3 := p.y - (float(cell.y) * cs - eps)
			if dd3 < best:
				best = dd3
				target = Vector2(p.x, float(cell.y) * cs - eps)
		if not is_wall(cell + Vector2i(0, 1)):
			var dd4 := (float(cell.y + 1) * cs + eps) - p.y
			if dd4 < best:
				best = dd4
				target = Vector2(p.x, float(cell.y + 1) * cs + eps)
		if target.x != p.x:
			v.x = 0.0
		if target.y != p.y:
			v.y = 0.0
		p = target
		if _wall_at(p):
			p = q
	var margin := 0.01 * cs
	var lo := cs + margin
	var hi_x := float(cols - 1) * cs - margin
	var hi_y := float(rows - 1) * cs - margin
	if p.x < lo:
		p.x = lo
		v.x = 0.0
	elif p.x > hi_x:
		p.x = hi_x
		v.x = 0.0
	if p.y < lo:
		p.y = lo
		v.y = 0.0
	elif p.y > hi_y:
		p.y = hi_y
		v.y = 0.0
	ppos[i] = p
	pvel[i] = v


## Shared bilinear stencil: fills the four node indices and weights for a velocity component.
func _stencil(p: Vector2, comp: int) -> Array:
	var half := 0.5 * cs
	var dx := 0.0 if comp == 0 else half
	var dy := half if comp == 0 else 0.0
	var px := clampf(p.x, cs, float(cols - 1) * cs)
	var py := clampf(p.y, cs, float(rows - 1) * cs)
	var x0 := mini(int(floor((px - dx) * inv_cs)), cols - 2)
	var tx := ((px - dx) - float(x0) * cs) * inv_cs
	var x1 := mini(x0 + 1, cols - 2)
	var y0 := mini(int(floor((py - dy) * inv_cs)), rows - 2)
	var ty := ((py - dy) - float(y0) * cs) * inv_cs
	var y1 := mini(y0 + 1, rows - 2)
	var sx := 1.0 - tx
	var sy := 1.0 - ty
	return [
		x0 * rows + y0, x1 * rows + y0, x1 * rows + y1, x0 * rows + y1,
		sx * sy, tx * sy, tx * ty, sx * ty,
	]


func _to_grid() -> void:
	gprev = gv.duplicate()
	gv.fill(0.0)
	gwt.fill(0.0)
	var counts := PackedInt32Array()
	counts.resize(cols * rows)
	for p in ppos:
		var cell := cell_of(p)
		counts[cell.x * rows + cell.y] += 1
	for c in cols * rows:
		if s_open[c] == 0.0:
			cell_type[c] = SOLID
		else:
			cell_type[c] = FLUID if counts[c] > 0 else AIR
	for comp in 2:
		for q in ppos.size():
			var st := _stencil(ppos[q], comp)
			var component: float = pvel[q].x if comp == 0 else pvel[q].y
			for k in 4:
				var node: int = st[k]
				var w: float = st[4 + k]
				gv[2 * node + comp] += component * w
				gwt[2 * node + comp] += w
	for idx in gv.size():
		if gwt[idx] > 0.0:
			gv[idx] /= gwt[idx]
	_apply_solid_faces()


## Faces touching a solid cell carry the solid's velocity (0 for walls, obstacle velocity for the circle).
func _apply_solid_faces() -> void:
	for i in cols:
		for j in rows:
			var c := i * rows + j
			var self_solid := s_open[c] == 0.0
			var left_solid := i > 0 and s_open[c - rows] == 0.0
			if self_solid or left_solid:
				var is_ob := obst[c] != 0 or (i > 0 and obst[c - rows] != 0)
				gv[2 * c] = obstacle_velocity.x if is_ob else 0.0
			var below_solid := j > 0 and s_open[c - 1] == 0.0
			if self_solid or below_solid:
				var is_ob2 := obst[c] != 0 or (j > 0 and obst[c - 1] != 0)
				gv[2 * c + 1] = obstacle_velocity.y if is_ob2 else 0.0


func _update_density() -> void:
	cell_density.fill(0.0)
	var half := 0.5 * cs
	for p in ppos:
		var px := clampf(p.x, cs, float(cols - 1) * cs)
		var py := clampf(p.y, cs, float(rows - 1) * cs)
		var x0 := clampi(int(floor((px - half) * inv_cs)), 0, cols - 2)
		var tx := ((px - half) - float(x0) * cs) * inv_cs
		var x1 := mini(x0 + 1, cols - 2)
		var y0 := clampi(int(floor((py - half) * inv_cs)), 0, rows - 2)
		var ty := ((py - half) - float(y0) * cs) * inv_cs
		var y1 := mini(y0 + 1, rows - 2)
		var sx := 1.0 - tx
		var sy := 1.0 - ty
		cell_density[x0 * rows + y0] += sx * sy
		cell_density[x1 * rows + y0] += tx * sy
		cell_density[x1 * rows + y1] += tx * ty
		cell_density[x0 * rows + y1] += sx * ty
	if rest_particle_density == 0.0:
		var acc := 0.0
		var fluid_cells := 0
		for c in cols * rows:
			if cell_type[c] == FLUID:
				acc += cell_density[c]
				fluid_cells += 1
		if fluid_cells > 0:
			rest_particle_density = acc / float(fluid_cells)


func _solve_incompressibility() -> void:
	gprev = gv.duplicate()
	last_divergence_before = divergence_max()
	for _it in pressure_iterations:
		for i in range(1, cols - 1):
			for j in range(1, rows - 1):
				var c := i * rows + j
				if cell_type[c] != FLUID:
					continue
				var right := c + rows
				var top := c + 1
				var sx0 := s_open[c - rows]
				var sx1 := s_open[right]
				var sy0 := s_open[c - 1]
				var sy1 := s_open[top]
				var s_sum := sx0 + sx1 + sy0 + sy1
				if s_sum == 0.0:
					continue
				var div := gv[2 * right] - gv[2 * c] + gv[2 * top + 1] - gv[2 * c + 1]
				if rest_particle_density > 0.0 and compensate_drift:
					var compression := cell_density[c] - rest_particle_density
					if compression > 0.0:
						div -= compression
				var corr := -div / s_sum * over_relaxation
				gv[2 * c] -= sx0 * corr
				gv[2 * right] += sx1 * corr
				gv[2 * c + 1] -= sy0 * corr
				gv[2 * top + 1] += sy1 * corr


func _from_grid() -> void:
	for comp in 2:
		var offset := rows if comp == 0 else 1
		for q in ppos.size():
			var st := _stencil(ppos[q], comp)
			var weight_sum := 0.0
			var pic := 0.0
			var corr := 0.0
			for k in 4:
				var node: int = st[k]
				var w: float = st[4 + k]
				var other := maxi(node - offset, 0)
				if cell_type[node] != AIR or cell_type[other] != AIR:
					weight_sum += w
					pic += w * gv[2 * node + comp]
					corr += w * (gv[2 * node + comp] - gprev[2 * node + comp])
			if weight_sum > 0.0:
				pic /= weight_sum
				corr /= weight_sum
				var current: float = pvel[q].x if comp == 0 else pvel[q].y
				var blended := (1.0 - flip_ratio) * pic + flip_ratio * (current + corr)
				if comp == 0:
					pvel[q].x = blended
				else:
					pvel[q].y = blended
