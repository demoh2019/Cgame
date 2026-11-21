extends RefCounted
## XPBD rope: a particle chain with distance (and optional bending) constraints, sphere/plane
## collision, segment-segment self-collision through a spatial hash and a crossing-number
## knot heuristic.
##
## Algorithm: Macklin, Muller, Chentanez "XPBD: Position-Based Simulation of Compliant
## Constrained Dynamics" (2016); small-steps solver layout after Matthias Muller's
## "Ten Minute Physics" demos. Source: https://github.com/matthias-research/pages
## (tenMinutePhysics), MIT License, (c) Matthias Muller / NVIDIA. Clean GDScript
## re-implementation from the published algorithm; closest-point-between-segments is the
## textbook (Ericson, Real-Time Collision Detection) formulation. No GPL/LGPL code was used.

var gravity := Vector3(0.0, -9.81, 0.0)
var wind := Vector3.ZERO
var drag := 0.05
## Compliance of the segment distance constraints; 0 = inextensible.
var compliance := 0.0
## Compliance of the skip-one bending constraint; negative disables bending resistance.
var bend_compliance := -1.0
var iterations := 1
## Rope radius, used for collider contact and self-collision (contact at 2 * radius).
var radius := 0.02
var friction := 0.3
var self_collision_enabled := false

var _pos := PackedVector3Array()
var _prev := PackedVector3Array()
var _vel := PackedVector3Array()
var _inv_mass := PackedFloat32Array()
var _base_inv_mass := PackedFloat32Array()
var _pin_mode := PackedByteArray()
var _pin_pos := PackedVector3Array()
var _pin_fn: Array[Callable] = []
var _seg_rest := PackedFloat32Array()
var _rest_length := 0.0

var _sphere_c := PackedVector3Array()
var _sphere_r := PackedFloat32Array()
var _plane_n := PackedVector3Array()
var _plane_d := PackedFloat32Array()


## Straight rope from start to end with `segments` segments (segments + 1 particles).
func setup(start: Vector3, end: Vector3, segments: int, particle_mass: float = 0.1) -> void:
	var count := maxi(segments, 1) + 1
	var pts := PackedVector3Array()
	for k in count:
		pts.append(start.lerp(end, float(k) / float(count - 1)))
	setup_points(pts, particle_mass)


## Rope through an explicit polyline; rest lengths are the polyline's segment lengths.
func setup_points(points: PackedVector3Array, particle_mass: float = 0.1) -> void:
	var n := points.size()
	_pos = points.duplicate()
	_prev = points.duplicate()
	_vel.resize(n)
	_inv_mass.resize(n)
	_base_inv_mass.resize(n)
	_pin_mode.resize(n)
	_pin_pos.resize(n)
	_pin_fn.clear()
	var w := 1.0 / maxf(particle_mass, 0.000001)
	for k in n:
		_vel[k] = Vector3.ZERO
		_inv_mass[k] = w
		_base_inv_mass[k] = w
		_pin_mode[k] = 0
		_pin_fn.append(Callable())
	_seg_rest.resize(maxi(n - 1, 0))
	_rest_length = 0.0
	for k in n - 1:
		_seg_rest[k] = points[k].distance_to(points[k + 1])
		_rest_length += _seg_rest[k]


func particle_count() -> int:
	return _pos.size()


func segment_count() -> int:
	return maxi(_pos.size() - 1, 0)


func positions() -> PackedVector3Array:
	return _pos


## Current arc length of the rope.
func length() -> float:
	var total := 0.0
	for k in _pos.size() - 1:
		total += _pos[k].distance_to(_pos[k + 1])
	return total


func rest_length() -> float:
	return _rest_length


func pin(index: int, world_pos: Vector3) -> void:
	_pin_mode[index] = 1
	_pin_pos[index] = world_pos
	_inv_mass[index] = 0.0
	_pos[index] = world_pos
	_prev[index] = world_pos
	_vel[index] = Vector3.ZERO


func attach(index: int, target_fn: Callable) -> void:
	_pin_mode[index] = 2
	_pin_fn[index] = target_fn
	_inv_mass[index] = 0.0
	var p: Vector3 = target_fn.call()
	_pos[index] = p
	_prev[index] = p
	_vel[index] = Vector3.ZERO


func attach_start(target_fn: Callable) -> void:
	attach(0, target_fn)


func attach_end(target_fn: Callable) -> void:
	attach(_pos.size() - 1, target_fn)


func unpin(index: int) -> void:
	_pin_mode[index] = 0
	_pin_fn[index] = Callable()
	_inv_mass[index] = _base_inv_mass[index]


func add_sphere(center: Vector3, sphere_radius: float) -> int:
	_sphere_c.append(center)
	_sphere_r.append(sphere_radius)
	return _sphere_c.size() - 1


func set_sphere_center(index: int, center: Vector3) -> void:
	_sphere_c[index] = center


## Half-space n . x >= offset is free.
func add_plane(normal: Vector3, offset: float) -> int:
	_plane_n.append(normal.normalized())
	_plane_d.append(offset)
	return _plane_n.size() - 1


func clear_colliders() -> void:
	_sphere_c.clear()
	_sphere_r.clear()
	_plane_n.clear()
	_plane_d.clear()


func step(dt: float, substeps: int = 8) -> void:
	if dt <= 0.0 or _pos.size() < 2:
		return
	var sub := maxi(substeps, 1)
	var sdt := dt / float(sub)
	for _s in sub:
		_integrate(sdt)
		for _it in maxi(iterations, 1):
			_solve_distance(sdt)
		if self_collision_enabled:
			_solve_self_collision()
		_collide()
		for k in _pos.size():
			if _inv_mass[k] > 0.0:
				_vel[k] = (_pos[k] - _prev[k]) / sdt


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


func _project(a: int, b: int, rest: float, alpha: float) -> void:
	var wa := _inv_mass[a]
	var wb := _inv_mass[b]
	var w := wa + wb
	if w == 0.0:
		return
	var d := _pos[a] - _pos[b]
	var dist := d.length()
	if dist < 0.0000001:
		return
	var s := -(dist - rest) / (w + alpha)
	var n := d / dist
	_pos[a] += n * (s * wa)
	_pos[b] -= n * (s * wb)


func _solve_distance(sdt: float) -> void:
	var inv_dt2 := 1.0 / (sdt * sdt)
	var alpha := compliance * inv_dt2
	for k in _pos.size() - 1:
		_project(k, k + 1, _seg_rest[k], alpha)
	if bend_compliance >= 0.0:
		var alpha_b := bend_compliance * inv_dt2
		for k in _pos.size() - 2:
			_project(k, k + 2, _seg_rest[k] + _seg_rest[k + 1], alpha_b)


func _contact(k: int, n: Vector3, depth: float) -> void:
	_pos[k] += n * depth
	if friction > 0.0:
		var dp := _pos[k] - _prev[k]
		_prev[k] += (dp - n * dp.dot(n)) * friction


func _collide() -> void:
	if _sphere_c.is_empty() and _plane_n.is_empty():
		return
	for k in _pos.size():
		if _inv_mass[k] == 0.0:
			continue
		for s in _sphere_c.size():
			var min_d := _sphere_r[s] + radius
			var d := _pos[k] - _sphere_c[s]
			var l2 := d.length_squared()
			if l2 < min_d * min_d:
				var l := sqrt(l2)
				var n := d / l if l > 0.0000001 else Vector3.UP
				_contact(k, n, min_d - l)
		for s in _plane_n.size():
			var dist := _plane_n[s].dot(_pos[k]) - _plane_d[s] - radius
			if dist < 0.0:
				_contact(k, _plane_n[s], -dist)


static func _cell_key(cx: int, cy: int, cz: int) -> int:
	return ((cx & 0x1FFFFF) << 42) | ((cy & 0x1FFFFF) << 21) | (cz & 0x1FFFFF)


## Closest points between segments p1-q1 and p2-q2; returns Vector2(s, t) parameters.
static func closest_params(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Vector2:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 0.0000001 and e <= 0.0000001:
		return Vector2.ZERO
	if a <= 0.0000001:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 0.0000001:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			if denom > 0.0000001:
				s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return Vector2(s, t)


## Smallest distance between two rope segments (indices into the segment list).
func segment_distance(i: int, j: int) -> float:
	var st := closest_params(_pos[i], _pos[i + 1], _pos[j], _pos[j + 1])
	var c1 := _pos[i].lerp(_pos[i + 1], st.x)
	var c2 := _pos[j].lerp(_pos[j + 1], st.y)
	return c1.distance_to(c2)


## Smallest distance between any two non-adjacent segments.
func min_self_distance() -> float:
	var best := INF
	var segs := segment_count()
	for i in segs:
		for j in range(i + 2, segs):
			best = minf(best, segment_distance(i, j))
	return best


func _solve_self_collision() -> void:
	var segs := segment_count()
	var longest := 0.0
	for k in segs:
		longest = maxf(longest, _seg_rest[k])
	var cell := maxf(longest * 1.25 + 2.0 * radius, 0.0001)
	var grid := {}
	for k in segs:
		var m := (_pos[k] + _pos[k + 1]) * 0.5
		var key := _cell_key(floori(m.x / cell), floori(m.y / cell), floori(m.z / cell))
		var bucket: PackedInt32Array = grid.get(key, PackedInt32Array())
		bucket.append(k)
		grid[key] = bucket
	var min_d := 2.0 * radius
	for i in segs:
		var mi := (_pos[i] + _pos[i + 1]) * 0.5
		var cx := floori(mi.x / cell)
		var cy := floori(mi.y / cell)
		var cz := floori(mi.z / cell)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var key := _cell_key(cx + dx, cy + dy, cz + dz)
					if not grid.has(key):
						continue
					var bucket: PackedInt32Array = grid[key]
					for j in bucket:
						if j < i + 2:
							continue
						_separate_segments(i, j, min_d)


func _separate_segments(i: int, j: int, min_d: float) -> void:
	var st := closest_params(_pos[i], _pos[i + 1], _pos[j], _pos[j + 1])
	var s := st.x
	var t := st.y
	var c1 := _pos[i].lerp(_pos[i + 1], s)
	var c2 := _pos[j].lerp(_pos[j + 1], t)
	var d := c1 - c2
	var dist := d.length()
	if dist >= min_d:
		return
	var n := Vector3.UP
	if dist > 0.0000001:
		n = d / dist
	else:
		var cr := (_pos[i + 1] - _pos[i]).cross(_pos[j + 1] - _pos[j])
		if cr.length_squared() > 0.0000001:
			n = cr.normalized()
	var wa := _inv_mass[i] * (1.0 - s)
	var wb := _inv_mass[i + 1] * s
	var wc := _inv_mass[j] * (1.0 - t)
	var wd := _inv_mass[j + 1] * t
	var denom := wa * (1.0 - s) + wb * s + wc * (1.0 - t) + wd * t
	if denom <= 0.0:
		return
	var lam := (min_d - dist) / denom
	_pos[i] += n * (lam * wa)
	_pos[i + 1] += n * (lam * wb)
	_pos[j] -= n * (lam * wc)
	_pos[j + 1] -= n * (lam * wd)


## Number of self-crossings of the polyline projected along its thinnest axis.
func crossing_number() -> int:
	var n := _pos.size()
	if n < 4:
		return 0
	var lo := _pos[0]
	var hi := _pos[0]
	for p in _pos:
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	var ext := hi - lo
	var drop := 2
	if ext.x <= ext.y and ext.x <= ext.z:
		drop = 0
	elif ext.y <= ext.z:
		drop = 1
	var pts := PackedVector2Array()
	for p in _pos:
		match drop:
			0:
				pts.append(Vector2(p.y, p.z))
			1:
				pts.append(Vector2(p.x, p.z))
			_:
				pts.append(Vector2(p.x, p.y))
	var crossings := 0
	var segs := n - 1
	for i in segs:
		for j in range(i + 2, segs):
			if _proper_cross(pts[i], pts[i + 1], pts[j], pts[j + 1]):
				crossings += 1
	return crossings


static func _proper_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var d1 := (b - a).cross(c - a)
	var d2 := (b - a).cross(d - a)
	var d3 := (d - c).cross(a - c)
	var d4 := (d - c).cross(b - c)
	return ((d1 > 0.0 and d2 < 0.0) or (d1 < 0.0 and d2 > 0.0)) and ((d3 > 0.0 and d4 < 0.0) or (d3 < 0.0 and d4 > 0.0))


## Heuristic: the simplest non-trivial knot (trefoil) needs 3 projected crossings, so every
## three crossings count as one knot; a single loop or a clasp of two crossings is not a knot.
func knot_count() -> int:
	@warning_ignore("integer_division")
	return crossing_number() / 3
