extends RefCounted
## ORCA (Optimal Reciprocal Collision Avoidance) in 2D for large crowds.
##
## Port of the algorithm from RVO2 Library (Agent::computeNewVelocity, linearProgram1/2/3)
## Source: https://github.com/snape/RVO2 -- Authors: Jur van den Berg, Stephen J. Guy,
## Jamie Snape, Ming C. Lin, Dinesh Manocha -- License: Apache-2.0.
## Paper: van den Berg et al., "Reciprocal n-body Collision Avoidance", ISRR 2009.
## Neighbour search uses a uniform spatial hash instead of RVO2's k-d tree (O(n) average).

const EPSILON := 0.00001


static func _det(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


## Returns new velocities (same order as input) that avoid collisions within time_horizon.
static func compute_velocities(positions: PackedVector2Array, velocities: PackedVector2Array,
		preferred: PackedVector2Array, radius: float, max_speed: float, time_horizon: float,
		neighbor_dist: float, max_neighbors: int, time_step: float = 0.1) -> PackedVector2Array:
	var n := positions.size()
	var out := PackedVector2Array()
	out.resize(n)
	if n == 0:
		return out
	# Bad array lengths or unsafe simulation parameters must not send NaNs
	# into the navigation/physics pipeline.
	if velocities.size() != n or preferred.size() != n or 			not is_finite(max_speed) or max_speed <= 0.0 or 			not is_finite(radius) or radius < 0.0 or 			not is_finite(neighbor_dist) or not is_finite(time_horizon) or 			not is_finite(time_step):
		return out
	# No neighbors/no prediction: use bounded navigation without a grid or LP.
	if max_neighbors <= 0 or neighbor_dist <= 0.0 or time_horizon <= 0.0 or 			time_step <= 0.0 or radius <= 0.0:
		for i in n:
			var target: Vector2 = preferred[i]
			if target.is_finite():
				out[i] = target.limit_length(max_speed)
		return out
	var cell: float = maxf(neighbor_dist, 0.001)
	var grid: Dictionary = {}
	for i in n:
		# Corrupt actors are excluded from the spatial hash rather than
		# contaminating the velocities of all nearby infected.
		if not positions[i].is_finite() or not velocities[i].is_finite() or 				absf(positions[i].x) > 10000000.0 or absf(positions[i].y) > 10000000.0:
			continue
		var key := Vector2i(floori(positions[i].x / cell), floori(positions[i].y / cell))
		if grid.has(key):
			var bucket: PackedInt32Array = grid[key]
			bucket.append(i)
			grid[key] = bucket
		else:
			grid[key] = PackedInt32Array([i])
	var nd_sq := neighbor_dist * neighbor_dist
	var neigh_idx := PackedInt32Array()
	var neigh_d := PackedFloat32Array()
	var line_p := PackedVector2Array()
	var line_d := PackedVector2Array()
	for i in n:
		var pi := positions[i]
		var vi := velocities[i]
		if not pi.is_finite() or not vi.is_finite() or 				absf(pi.x) > 10000000.0 or absf(pi.y) > 10000000.0:
			continue
		neigh_idx.clear()
		neigh_d.clear()
		var cx := floori(pi.x / cell)
		var cy := floori(pi.y / cell)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var key := Vector2i(cx + dx, cy + dy)
				if not grid.has(key):
					continue
				var bucket: PackedInt32Array = grid[key]
				for j in bucket:
					if j == i:
						continue
					var dsq := pi.distance_squared_to(positions[j])
					if dsq >= nd_sq:
						continue
					# Insertion into a list kept sorted by distance and capped at max_neighbors.
					if neigh_idx.size() >= max_neighbors and dsq >= neigh_d[neigh_d.size() - 1]:
						continue
					var at := neigh_idx.size()
					while at > 0 and neigh_d[at - 1] > dsq:
						at -= 1
					neigh_idx.insert(at, j)
					neigh_d.insert(at, dsq)
					if neigh_idx.size() > max_neighbors:
						neigh_idx.resize(max_neighbors)
						neigh_d.resize(max_neighbors)
		# Singletons are common in open terrain and need no linear program.
		if neigh_idx.is_empty():
			if preferred[i].is_finite():
				out[i] = preferred[i].limit_length(max_speed)
			continue
		line_p.clear()
		line_d.clear()
		var inv_t := 1.0 / maxf(time_horizon, 0.0001)
		var inv_dt := 1.0 / maxf(time_step, 0.0001)
		var combined := radius * 2.0
		var combined_sq := combined * combined
		for k in neigh_idx.size():
			var j := neigh_idx[k]
			var rel_pos := positions[j] - pi
			var rel_vel := vi - velocities[j]
			var dist_sq := rel_pos.length_squared()
			var dir := Vector2.ZERO
			var u := Vector2.ZERO
			if dist_sq > combined_sq:
				var w := rel_vel - inv_t * rel_pos
				var w_sq := w.length_squared()
				var dot1 := w.dot(rel_pos)
				if dot1 < 0.0 and dot1 * dot1 > combined_sq * w_sq:
					var w_len := sqrt(w_sq)
					var unit_w := w / w_len
					dir = Vector2(unit_w.y, -unit_w.x)
					u = (combined * inv_t - w_len) * unit_w
				else:
					var leg := sqrt(dist_sq - combined_sq)
					if _det(rel_pos, w) > 0.0:
						dir = Vector2(rel_pos.x * leg - rel_pos.y * combined, rel_pos.x * combined + rel_pos.y * leg) / dist_sq
					else:
						dir = -Vector2(rel_pos.x * leg + rel_pos.y * combined, -rel_pos.x * combined + rel_pos.y * leg) / dist_sq
					u = rel_vel.dot(dir) * dir - rel_vel
			else:
				# Already overlapping: resolve within one time step.
				var w := rel_vel - inv_dt * rel_pos
				var w_len := w.length()
				var unit_w := Vector2(1.0, 0.0) if w_len < EPSILON else w / w_len
				dir = Vector2(unit_w.y, -unit_w.x)
				u = (combined * inv_dt - w_len) * unit_w
			line_p.append(vi + 0.5 * u)
			line_d.append(dir)
		var pref: Vector2 = preferred[i]
		if not pref.is_finite():
			pref = Vector2.ZERO
		if pref.length_squared() > max_speed * max_speed:
			pref = pref.normalized() * max_speed
		var res := PackedFloat32Array([0.0, 0.0])
		var fail := _lp2(line_p, line_d, max_speed, pref, false, res)
		if fail < line_p.size():
			_lp3(line_p, line_d, fail, max_speed, res)
		var chosen := Vector2(res[0], res[1])
		out[i] = chosen.limit_length(max_speed) if chosen.is_finite() else pref
	return out


static func _lp1(lp: PackedVector2Array, ld: PackedVector2Array, line_no: int, radius: float,
		opt: Vector2, direction_opt: bool, res: PackedFloat32Array) -> bool:
	var pt := lp[line_no]
	var dr := ld[line_no]
	var dot := pt.dot(dr)
	var disc := dot * dot + radius * radius - pt.length_squared()
	if disc < 0.0:
		return false
	var sd := sqrt(disc)
	var t_left := -dot - sd
	var t_right := -dot + sd
	for i in line_no:
		var denom := _det(dr, ld[i])
		var numer := _det(ld[i], pt - lp[i])
		if absf(denom) <= EPSILON:
			if numer < 0.0:
				return false
			continue
		var t := numer / denom
		if denom >= 0.0:
			t_right = minf(t_right, t)
		else:
			t_left = maxf(t_left, t)
		if t_left > t_right:
			return false
	var r: Vector2
	if direction_opt:
		r = pt + (t_right if opt.dot(dr) > 0.0 else t_left) * dr
	else:
		r = pt + clampf(dr.dot(opt - pt), t_left, t_right) * dr
	res[0] = r.x
	res[1] = r.y
	return true


## Returns the index of the first infeasible line, or the line count when all satisfied.
static func _lp2(lp: PackedVector2Array, ld: PackedVector2Array, radius: float, opt: Vector2,
		direction_opt: bool, res: PackedFloat32Array) -> int:
	var r: Vector2
	if direction_opt:
		r = opt * radius
	elif opt.length_squared() > radius * radius:
		r = opt.normalized() * radius
	else:
		r = opt
	res[0] = r.x
	res[1] = r.y
	for i in lp.size():
		if _det(ld[i], lp[i] - Vector2(res[0], res[1])) > 0.0:
			var tmp := PackedFloat32Array([res[0], res[1]])
			if not _lp1(lp, ld, i, radius, opt, direction_opt, res):
				res[0] = tmp[0]
				res[1] = tmp[1]
				return i
	return lp.size()


## 3D fallback: minimise the maximum constraint violation when no feasible velocity exists.
static func _lp3(lp: PackedVector2Array, ld: PackedVector2Array, begin: int, radius: float,
		res: PackedFloat32Array) -> void:
	var distance := 0.0
	for i in range(begin, lp.size()):
		if _det(ld[i], lp[i] - Vector2(res[0], res[1])) > distance:
			var pp := PackedVector2Array()
			var pd := PackedVector2Array()
			for j in i:
				var d := _det(ld[i], ld[j])
				var pt: Vector2
				if absf(d) <= EPSILON:
					if ld[i].dot(ld[j]) > 0.0:
						continue
					pt = 0.5 * (lp[i] + lp[j])
				else:
					pt = lp[i] + (_det(ld[j], lp[i] - lp[j]) / d) * ld[i]
				pp.append(pt)
				pd.append((ld[j] - ld[i]).normalized())
			var tmp := PackedFloat32Array([res[0], res[1]])
			var opt := Vector2(-ld[i].y, ld[i].x)
			if _lp2(pp, pd, radius, opt, true, res) < pp.size():
				res[0] = tmp[0]
				res[1] = tmp[1]
			distance = _det(ld[i], lp[i] - Vector2(res[0], res[1]))
