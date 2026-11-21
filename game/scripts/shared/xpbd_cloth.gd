extends RefCounted
## XPBD cloth: distance (stretch + shear) and bending constraints with compliance, sub-stepping,
## sphere/capsule/plane collision, spatial-hash self-collision and tearing.
##
## Algorithm: Macklin, Muller, Chentanez "XPBD: Position-Based Simulation of Compliant
## Constrained Dynamics" (2016); structure follows Matthias Muller's "Ten Minute Physics"
## cloth demo (small-steps XPBD, 1 solver iteration per substep, hash-grid self collision).
## Source: https://github.com/matthias-research/pages (tenMinutePhysics), MIT License,
## (c) Matthias Muller / NVIDIA. This is a clean GDScript re-implementation from the
## published algorithm, not a verbatim copy; no GPL/LGPL code was used.
##
## Grid layout: particle (i, j) sits at origin * (i*spacing, -j*spacing, 0), so row 0 is the
## top edge, local -Y is "down the cloth" and local +Z is the front-face normal.

const KIND_STRETCH := 0
const KIND_SHEAR := 1
const KIND_BEND := 2

var gravity := Vector3(0.0, -9.81, 0.0)
## Wind velocity the air tries to drag particles toward; with wind == 0 this is plain drag.
var wind := Vector3.ZERO
## Air drag rate in 1/s toward the wind velocity.
var drag := 0.1
## Compliance (inverse stiffness, m/N) per constraint family; 0 = fully rigid.
var compliance_stretch := 0.0
var compliance_shear := 0.0001
var compliance_bend := 0.02
## Solver iterations per substep (Ten Minute Physics uses 1 with many substeps).
var iterations := 1
## Particle radius used for collider contact.
var collision_margin := 0.01
## Tangential damping on contact, 0..1.
var friction := 0.2
## Stretch constraints longer than rest * tear_threshold are removed (0 disables tearing).
var tear_threshold := 0.0
var self_collision_enabled := false
## Minimum distance kept between non-neighbouring particles when self_collision_enabled.
var thickness := 0.04

var _cols := 0
var _rows := 0
var _pos := PackedVector3Array()
var _prev := PackedVector3Array()
var _vel := PackedVector3Array()
var _rest_pos := PackedVector3Array()
var _uv := PackedVector2Array()
var _inv_mass := PackedFloat32Array()
var _base_inv_mass := PackedFloat32Array()
var _pin_mode := PackedByteArray() # 0 free, 1 fixed position, 2 attached to callable
var _pin_pos := PackedVector3Array()
var _pin_fn: Array[Callable] = []

var _ca := PackedInt32Array()
var _cb := PackedInt32Array()
var _cmid := PackedInt32Array()
var _crest := PackedFloat32Array()
var _ckind := PackedByteArray()

var _tris := PackedInt32Array()
var _tri_cell := PackedInt32Array()

var _sphere_c := PackedVector3Array()
var _sphere_r := PackedFloat32Array()
var _cap_a := PackedVector3Array()
var _cap_b := PackedVector3Array()
var _cap_r := PackedFloat32Array()
var _plane_n := PackedVector3Array()
var _plane_d := PackedFloat32Array()

var torn_count := 0


func setup_grid(width_cells: int, height_cells: int, spacing: float, origin: Transform3D, particle_mass: float = 1.0) -> void:
	_cols = maxi(width_cells, 1) + 1
	_rows = maxi(height_cells, 1) + 1
	var n := _cols * _rows
	_pos.resize(n)
	_prev.resize(n)
	_vel.resize(n)
	_rest_pos.resize(n)
	_uv.resize(n)
	_inv_mass.resize(n)
	_base_inv_mass.resize(n)
	_pin_mode.resize(n)
	_pin_pos.resize(n)
	_pin_fn.clear()
	for k in n:
		_pin_fn.append(Callable())
	var w := 1.0 / maxf(particle_mass, 0.000001)
	for j in _rows:
		for i in _cols:
			var k := j * _cols + i
			var p := origin * Vector3(i * spacing, -j * spacing, 0.0)
			_pos[k] = p
			_prev[k] = p
			_rest_pos[k] = p
			_vel[k] = Vector3.ZERO
			_uv[k] = Vector2(float(i) / float(_cols - 1), float(j) / float(_rows - 1))
			_inv_mass[k] = w
			_base_inv_mass[k] = w
			_pin_mode[k] = 0
	_ca.clear()
	_cb.clear()
	_cmid.clear()
	_crest.clear()
	_ckind.clear()
	_tris.clear()
	_tri_cell.clear()
	torn_count = 0
	for j in _rows:
		for i in _cols:
			var k := j * _cols + i
			if i + 1 < _cols:
				_add_constraint(k, k + 1, KIND_STRETCH, -1)
			if j + 1 < _rows:
				_add_constraint(k, k + _cols, KIND_STRETCH, -1)
			if i + 1 < _cols and j + 1 < _rows:
				_add_constraint(k, k + _cols + 1, KIND_SHEAR, -1)
				_add_constraint(k + 1, k + _cols, KIND_SHEAR, -1)
				var cell := j * (_cols - 1) + i
				# a=k, b=k+1, c=k+cols, d=k+cols+1; counter-clockwise seen from local +Z.
				_tris.append_array(PackedInt32Array([k, k + _cols, k + _cols + 1]))
				_tri_cell.append(cell)
				_tris.append_array(PackedInt32Array([k, k + _cols + 1, k + 1]))
				_tri_cell.append(cell)
			if i + 2 < _cols:
				_add_constraint(k, k + 2, KIND_BEND, k + 1)
			if j + 2 < _rows:
				_add_constraint(k, k + 2 * _cols, KIND_BEND, k + _cols)


func _add_constraint(a: int, b: int, kind: int, mid: int) -> void:
	_ca.append(a)
	_cb.append(b)
	_cmid.append(mid)
	_crest.append(_rest_pos[a].distance_to(_rest_pos[b]))
	_ckind.append(kind)


func particle_count() -> int:
	return _pos.size()


func constraint_count() -> int:
	return _ca.size()


func stretch_constraint_count() -> int:
	var c := 0
	for k in _ckind.size():
		if _ckind[k] == KIND_STRETCH:
			c += 1
	return c


func columns() -> int:
	return _cols


func rows() -> int:
	return _rows


func index_of(i: int, j: int) -> int:
	return j * _cols + i


## Largest |length / rest - 1| over stretch constraints (0 when none remain).
func max_stretch_error() -> float:
	var worst := 0.0
	for c in _ca.size():
		if _ckind[c] != KIND_STRETCH:
			continue
		var e := absf(_pos[_ca[c]].distance_to(_pos[_cb[c]]) / _crest[c] - 1.0)
		worst = maxf(worst, e)
	return worst


## Fix particle `index` at a world position (inverse mass becomes 0).
func pin(index: int, world_pos: Vector3) -> void:
	_pin_mode[index] = 1
	_pin_pos[index] = world_pos
	_inv_mass[index] = 0.0
	_pos[index] = world_pos
	_prev[index] = world_pos
	_vel[index] = Vector3.ZERO


## Make particle `index` follow `target_fn.call() -> Vector3` (e.g. an animated bone socket).
func attach(index: int, target_fn: Callable) -> void:
	_pin_mode[index] = 2
	_pin_fn[index] = target_fn
	_inv_mass[index] = 0.0
	var p: Vector3 = target_fn.call()
	_pos[index] = p
	_prev[index] = p
	_vel[index] = Vector3.ZERO


func unpin(index: int) -> void:
	_pin_mode[index] = 0
	_pin_fn[index] = Callable()
	_inv_mass[index] = _base_inv_mass[index]


func is_pinned(index: int) -> bool:
	return _pin_mode[index] != 0


func add_sphere(center: Vector3, radius: float) -> int:
	_sphere_c.append(center)
	_sphere_r.append(radius)
	return _sphere_c.size() - 1


func set_sphere_center(index: int, center: Vector3) -> void:
	_sphere_c[index] = center


func add_capsule(a: Vector3, b: Vector3, radius: float) -> int:
	_cap_a.append(a)
	_cap_b.append(b)
	_cap_r.append(radius)
	return _cap_a.size() - 1


func set_capsule(index: int, a: Vector3, b: Vector3) -> void:
	_cap_a[index] = a
	_cap_b[index] = b


## Half-space n . x >= offset is free; particles are pushed out of the other side.
func add_plane(normal: Vector3, offset: float) -> int:
	_plane_n.append(normal.normalized())
	_plane_d.append(offset)
	return _plane_n.size() - 1


func clear_colliders() -> void:
	_sphere_c.clear()
	_sphere_r.clear()
	_cap_a.clear()
	_cap_b.clear()
	_cap_r.clear()
	_plane_n.clear()
	_plane_d.clear()


## Teleport a free particle (position and history), e.g. to pre-fold the cloth.
func set_particle(index: int, world_pos: Vector3) -> void:
	_pos[index] = world_pos
	_prev[index] = world_pos
	_vel[index] = Vector3.ZERO


func positions() -> PackedVector3Array:
	return _pos


func velocities() -> PackedVector3Array:
	return _vel


func triangles() -> PackedInt32Array:
	return _tris


func step(dt: float, substeps: int = 8) -> void:
	if dt <= 0.0 or _pos.is_empty():
		return
	var sub := maxi(substeps, 1)
	var sdt := dt / float(sub)
	for _s in sub:
		_integrate(sdt)
		for _it in maxi(iterations, 1):
			_solve_constraints(sdt)
		if self_collision_enabled:
			_solve_self_collision()
		_collide()
		for k in _pos.size():
			if _inv_mass[k] > 0.0:
				_vel[k] = (_pos[k] - _prev[k]) / sdt
	if tear_threshold > 0.0:
		_tear()


func _integrate(sdt: float) -> void:
	var damp := clampf(drag * sdt, 0.0, 1.0)
	for k in _pos.size():
		var mode := _pin_mode[k]
		if mode != 0:
			var target := _pin_pos[k]
			if mode == 2:
				target = _pin_fn[k].call()
				_pin_pos[k] = target
			_prev[k] = target
			_pos[k] = target
			_vel[k] = Vector3.ZERO
			continue
		var v := _vel[k] + gravity * sdt
		v += (wind - v) * damp
		_prev[k] = _pos[k]
		_pos[k] += v * sdt
		_vel[k] = v


func _solve_constraints(sdt: float) -> void:
	var inv_dt2 := 1.0 / (sdt * sdt)
	var alpha_stretch := compliance_stretch * inv_dt2
	var alpha_shear := compliance_shear * inv_dt2
	var alpha_bend := compliance_bend * inv_dt2
	for c in _ca.size():
		var a := _ca[c]
		var b := _cb[c]
		var wa := _inv_mass[a]
		var wb := _inv_mass[b]
		var w := wa + wb
		if w == 0.0:
			continue
		var d := _pos[a] - _pos[b]
		var dist := d.length()
		if dist < 0.0000001:
			continue
		var kind := _ckind[c]
		var alpha := alpha_stretch
		if kind == KIND_SHEAR:
			alpha = alpha_shear
		elif kind == KIND_BEND:
			alpha = alpha_bend
		var s := -(dist - _crest[c]) / (w + alpha)
		var n := d / dist
		_pos[a] += n * (s * wa)
		_pos[b] -= n * (s * wb)


func _contact(k: int, n: Vector3, depth: float) -> void:
	_pos[k] += n * depth
	if friction > 0.0:
		var dp := _pos[k] - _prev[k]
		var tangential := dp - n * dp.dot(n)
		_prev[k] += tangential * friction


func _collide() -> void:
	if _sphere_c.is_empty() and _cap_a.is_empty() and _plane_n.is_empty():
		return
	for k in _pos.size():
		if _inv_mass[k] == 0.0:
			continue
		for s in _sphere_c.size():
			var min_d := _sphere_r[s] + collision_margin
			var d := _pos[k] - _sphere_c[s]
			var l2 := d.length_squared()
			if l2 < min_d * min_d:
				var l := sqrt(l2)
				var n := d / l if l > 0.0000001 else Vector3.UP
				_contact(k, n, min_d - l)
		for s in _cap_a.size():
			var min_d := _cap_r[s] + collision_margin
			var a := _cap_a[s]
			var ab := _cap_b[s] - a
			var denom := ab.length_squared()
			var t := 0.0
			if denom > 0.0000001:
				t = clampf((_pos[k] - a).dot(ab) / denom, 0.0, 1.0)
			var d := _pos[k] - (a + ab * t)
			var l2 := d.length_squared()
			if l2 < min_d * min_d:
				var l := sqrt(l2)
				var n := d / l if l > 0.0000001 else Vector3.UP
				_contact(k, n, min_d - l)
		for s in _plane_n.size():
			var dist := _plane_n[s].dot(_pos[k]) - _plane_d[s] - collision_margin
			if dist < 0.0:
				_contact(k, _plane_n[s], -dist)


static func _cell_key(cx: int, cy: int, cz: int) -> int:
	return ((cx & 0x1FFFFF) << 42) | ((cy & 0x1FFFFF) << 21) | (cz & 0x1FFFFF)


func _solve_self_collision() -> void:
	var cell := maxf(thickness, 0.0001)
	var grid := {}
	var n := _pos.size()
	for k in n:
		var p := _pos[k]
		var key := _cell_key(floori(p.x / cell), floori(p.y / cell), floori(p.z / cell))
		var bucket: PackedInt32Array = grid.get(key, PackedInt32Array())
		bucket.append(k)
		grid[key] = bucket
	var min2 := thickness * thickness
	for i in n:
		var pi := _pos[i]
		var cx := floori(pi.x / cell)
		var cy := floori(pi.y / cell)
		var cz := floori(pi.z / cell)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var key := _cell_key(cx + dx, cy + dy, cz + dz)
					if not grid.has(key):
						continue
					var bucket: PackedInt32Array = grid[key]
					for j in bucket:
						if j <= i:
							continue
						var w := _inv_mass[i] + _inv_mass[j]
						if w == 0.0:
							continue
						# Particles that start closer than the thickness are neighbours, not contacts.
						if _rest_pos[i].distance_squared_to(_rest_pos[j]) < min2:
							continue
						var d := _pos[j] - _pos[i]
						var l2 := d.length_squared()
						if l2 >= min2:
							continue
						var l := sqrt(l2)
						var dir := d / l if l > 0.0000001 else Vector3.UP
						var corr := (thickness - l) / w
						_pos[i] -= dir * (corr * _inv_mass[i])
						_pos[j] += dir * (corr * _inv_mass[j])


func _edge_key(a: int, b: int) -> int:
	return mini(a, b) * _pos.size() + maxi(a, b)


func _cell_torn(cell: int, torn: Dictionary) -> bool:
	var ci := cell % (_cols - 1)
	@warning_ignore("integer_division")
	var cj := cell / (_cols - 1)
	var v00 := cj * _cols + ci
	var v10 := v00 + 1
	var v01 := v00 + _cols
	var v11 := v01 + 1
	return torn.has(_edge_key(v00, v10)) or torn.has(_edge_key(v01, v11)) \
		or torn.has(_edge_key(v00, v01)) or torn.has(_edge_key(v10, v11))


func _tear() -> void:
	var torn := {}
	for c in _ca.size():
		if _ckind[c] != KIND_STRETCH:
			continue
		var l := _pos[_ca[c]].distance_to(_pos[_cb[c]])
		if l > _crest[c] * tear_threshold:
			torn[_edge_key(_ca[c], _cb[c])] = true
	if torn.is_empty():
		return
	var na := PackedInt32Array()
	var nb := PackedInt32Array()
	var nm := PackedInt32Array()
	var nr := PackedFloat32Array()
	var nk := PackedByteArray()
	for c in _ca.size():
		var a := _ca[c]
		var b := _cb[c]
		var kind := _ckind[c]
		var dead := false
		if kind == KIND_STRETCH:
			dead = torn.has(_edge_key(a, b))
		elif kind == KIND_BEND:
			var m := _cmid[c]
			dead = torn.has(_edge_key(a, m)) or torn.has(_edge_key(m, b))
		else:
			var ci := mini(a % _cols, b % _cols)
			@warning_ignore("integer_division")
			var cj := mini(a / _cols, b / _cols)
			dead = _cell_torn(cj * (_cols - 1) + ci, torn)
		if dead:
			torn_count += 1
			continue
		na.append(a)
		nb.append(b)
		nm.append(_cmid[c])
		nr.append(_crest[c])
		nk.append(kind)
	_ca = na
	_cb = nb
	_cmid = nm
	_crest = nr
	_ckind = nk
	var nt := PackedInt32Array()
	var ntc := PackedInt32Array()
	for t in _tri_cell.size():
		if _cell_torn(_tri_cell[t], torn):
			continue
		nt.append(_tris[t * 3])
		nt.append(_tris[t * 3 + 1])
		nt.append(_tris[t * 3 + 2])
		ntc.append(_tri_cell[t])
	_tris = nt
	_tri_cell = ntc


func normals() -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(_pos.size())
	for t in range(0, _tris.size(), 3):
		var a := _tris[t]
		var b := _tris[t + 1]
		var c := _tris[t + 2]
		var fn := (_pos[b] - _pos[a]).cross(_pos[c] - _pos[a])
		out[a] += fn
		out[b] += fn
		out[c] += fn
	for k in out.size():
		out[k] = out[k].normalized() if out[k].length_squared() > 0.0000001 else Vector3.BACK
	return out


func build_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if _tris.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _pos
	arrays[Mesh.ARRAY_NORMAL] = normals()
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_INDEX] = _tris
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
