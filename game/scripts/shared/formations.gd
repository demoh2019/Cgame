extends RefCounted
## Group formations: slot layouts in leader space, minimal-distance slot
## assignment, smooth formation changes and obstacle-aware slot shifting.
##
## Leader space: +X is the leader's forward direction, +Y is to the leader's
## right (screen-space 2D, y down). Slot 0 of wedge/column sits on the leader.
##
## Algorithms (textbook, implemented from scratch):
##  - Hungarian / Kuhn-Munkres assignment with row/column potentials
##    (O(n^2 m) shortest-augmenting-path form; the algorithm is public domain,
##    this code follows the standard formulation, no third-party code copied).
##  - Formation slot patterns after Reynolds "Steering Behaviors for Autonomous
##    Characters" (1999) and Millington "AI for Games" (concepts only).

const HUNGARIAN_LIMIT := 64
const KINDS: PackedStringArray = ["line", "wedge", "circle", "column"]


## Slot offsets in leader space for `count` members at least `spacing` apart.
static func slots(kind: String, count: int, spacing: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if count <= 0:
		return out
	out.resize(count)
	match kind:
		"line":
			var half := float(count - 1) * 0.5
			for i in range(count):
				out[i] = Vector2(0.0, (float(i) - half) * spacing)
		"wedge":
			out[0] = Vector2.ZERO
			for i in range(1, count):
				@warning_ignore("integer_division")
				var row: int = (i + 1) / 2
				var side := 1.0 if i % 2 == 1 else -1.0
				out[i] = Vector2(-float(row) * spacing * 0.866, side * float(row) * spacing * 0.5)
		"circle":
			if count == 1:
				out[0] = Vector2.ZERO
			else:
				var radius := maxf(spacing, spacing / (2.0 * sin(PI / float(count))))
				for i in range(count):
					var a := TAU * float(i) / float(count)
					out[i] = Vector2(cos(a), sin(a)) * radius
		_:
			# "column" and unknown kinds: single file behind the leader.
			for i in range(count):
				out[i] = Vector2(-float(i) * spacing, 0.0)
	return out


## World-space slot targets for a leader at `leader_pos` facing `leader_heading` (radians).
static func targets(leader_pos: Vector2, leader_heading: float, kind: String, count: int, spacing: float) -> PackedVector2Array:
	var local := slots(kind, count, spacing)
	var out := PackedVector2Array()
	out.resize(local.size())
	for i in range(local.size()):
		out[i] = leader_pos + local[i].rotated(leader_heading)
	return out


## Returns result[member] = slot index, minimising the total member->slot
## distance. Hungarian for up to 64 on both sides, greedy beyond. If there are
## more members than slots the surplus members get -1.
static func assign(slots_world: PackedVector2Array, members: PackedVector2Array) -> PackedInt32Array:
	var n := members.size()
	var m := slots_world.size()
	var result := PackedInt32Array()
	result.resize(n)
	result.fill(-1)
	if n == 0 or m == 0:
		return result
	# Keep costs strictly below the Hungarian sentinel (1e18).
	for point in members:
		if not point.is_finite() or absf(point.x) > 1.0e15 or absf(point.y) > 1.0e15:
			return result
	for point in slots_world:
		if not point.is_finite() or absf(point.x) > 1.0e15 or absf(point.y) > 1.0e15:
			return result
	if n <= HUNGARIAN_LIMIT and m <= HUNGARIAN_LIMIT:
		if n <= m:
			var cost := PackedFloat64Array()
			cost.resize(n * m)
			for i in range(n):
				for j in range(m):
					cost[i * m + j] = members[i].distance_to(slots_world[j])
			var row_to_col := _hungarian(cost, n, m)
			for i in range(n):
				result[i] = row_to_col[i]
		else:
			# Transpose: rows are slots, columns are members.
			var cost_t := PackedFloat64Array()
			cost_t.resize(m * n)
			for j in range(m):
				for i in range(n):
					cost_t[j * n + i] = members[i].distance_to(slots_world[j])
			var slot_to_member := _hungarian(cost_t, m, n)
			for j in range(m):
				result[slot_to_member[j]] = j
		return result
	return _greedy(slots_world, members)


## Total member->slot distance of an assignment (-1 entries are skipped).
static func assignment_cost(slots_world: PackedVector2Array, members: PackedVector2Array, assignment: PackedInt32Array) -> float:
	var total := 0.0
	for i in range(assignment.size()):
		if assignment[i] >= 0 and i < members.size() and assignment[i] < slots_world.size():
			total += members[i].distance_to(slots_world[assignment[i]])
	return total


## Standard O(n^2 m) Hungarian algorithm for an n x m cost matrix with n <= m.
## Returns row -> column.
static func _hungarian(cost: PackedFloat64Array, n: int, m: int) -> PackedInt32Array:
	var inf := 1.0e18
	var u := PackedFloat64Array()
	u.resize(n + 1)
	var v := PackedFloat64Array()
	v.resize(m + 1)
	var p := PackedInt32Array()
	p.resize(m + 1)
	var way := PackedInt32Array()
	way.resize(m + 1)
	for i in range(1, n + 1):
		p[0] = i
		var j0 := 0
		var minv := PackedFloat64Array()
		minv.resize(m + 1)
		minv.fill(inf)
		var used := PackedByteArray()
		used.resize(m + 1)
		while true:
			used[j0] = 1
			var i0 := p[j0]
			var delta := inf
			var j1 := 0
			for j in range(1, m + 1):
				if used[j] == 0:
					var cur := cost[(i0 - 1) * m + (j - 1)] - u[i0] - v[j]
					if cur < minv[j]:
						minv[j] = cur
						way[j] = j0
					if minv[j] < delta:
						delta = minv[j]
						j1 = j
			for j in range(m + 1):
				if used[j] == 1:
					u[p[j]] += delta
					v[j] -= delta
				else:
					minv[j] -= delta
			j0 = j1
			if p[j0] == 0:
				break
		while true:
			var j1b := way[j0]
			p[j0] = p[j1b]
			j0 = j1b
			if j0 == 0:
				break
	var row_to_col := PackedInt32Array()
	row_to_col.resize(n)
	row_to_col.fill(-1)
	for j in range(1, m + 1):
		if p[j] > 0:
			row_to_col[p[j] - 1] = j - 1
	return row_to_col


## Greedy fallback: members in order each take the nearest free slot.
static func _greedy(slots_world: PackedVector2Array, members: PackedVector2Array) -> PackedInt32Array:
	var n := members.size()
	var m := slots_world.size()
	var result := PackedInt32Array()
	result.resize(n)
	result.fill(-1)
	var taken := PackedByteArray()
	taken.resize(m)
	for i in range(n):
		var best := -1
		var best_d := INF
		for j in range(m):
			if taken[j] == 1:
				continue
			var d := members[i].distance_squared_to(slots_world[j])
			if d < best_d:
				best_d = d
				best = j
		if best >= 0:
			taken[best] = 1
			result[i] = best
	return result


## Linear blend between two layouts (same size). t in 0..1.
static func blend(from_slots: PackedVector2Array, to_slots: PackedVector2Array, t: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(to_slots.size())
	for i in range(to_slots.size()):
		var a: Vector2 = from_slots[i] if i < from_slots.size() else to_slots[i]
		out[i] = a.lerp(to_slots[i], clampf(t, 0.0, 1.0))
	return out


## Frame-rate independent smoothing of the current slot positions toward a goal
## layout when the formation kind or size changes. Slots without a previous
## position start at their goal.
static func smooth(current: PackedVector2Array, goal: PackedVector2Array, dt: float, rate: float = 6.0) -> PackedVector2Array:
	var k := 1.0 - exp(-maxf(0.0, rate) * maxf(0.0, dt))
	return blend(current, goal, k)


## Moves slots that are not walkable to the nearest walkable position (ring
## search around the slot), keeping at least `spacing * 0.5` from the slots
## already placed. Falls back to pulling the slot toward the leader.
## `walkable` is Callable(Vector2) -> bool.
static func shift_slots(slots_world: PackedVector2Array, walkable: Callable, leader_pos: Vector2, spacing: float, rings: int = 6) -> PackedVector2Array:
	var out := slots_world.duplicate()
	var min_sep := spacing * 0.5
	var placed := PackedVector2Array()
	# Walkable slots keep their place first so shifted ones avoid them.
	for i in range(out.size()):
		if bool(walkable.call(out[i])):
			placed.append(out[i])
	for i in range(out.size()):
		var s := out[i]
		if bool(walkable.call(s)):
			continue
		var found := false
		var step := maxf(1.0, spacing * 0.5)
		for ring in range(1, rings + 1):
			var radius := step * float(ring)
			var samples := 8 + ring * 4
			var best := s
			var best_d := INF
			for k in range(samples):
				var a := TAU * float(k) / float(samples)
				var c := s + Vector2(cos(a), sin(a)) * radius
				if not bool(walkable.call(c)):
					continue
				if _too_close(c, placed, min_sep):
					continue
				var d := c.distance_squared_to(s)
				if d < best_d:
					best_d = d
					best = c
			if best_d < INF:
				out[i] = best
				placed.append(best)
				found = true
				break
		if not found:
			# Pull toward the leader in small steps until something is walkable.
			var to_leader := leader_pos - s
			var dist := to_leader.length()
			var dir := to_leader / maxf(0.001, dist)
			var walked := 0.0
			var fallback := leader_pos
			while walked < dist:
				walked += step
				var c2 := s + dir * minf(walked, dist)
				if bool(walkable.call(c2)):
					fallback = c2
					break
			out[i] = fallback
			placed.append(fallback)
	return out


static func _too_close(c: Vector2, placed: PackedVector2Array, min_sep: float) -> bool:
	for p in placed:
		if p.distance_to(c) < min_sep:
			return true
	return false
