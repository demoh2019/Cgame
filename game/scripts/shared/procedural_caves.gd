extends RefCounted
## Cellular-automata caves with guaranteed connectivity.
##
## Technique: classic cave-generation cellular automaton (random fill, repeated
## 8-neighbour majority smoothing) as described in public tutorials and in
## Johnson, Yannakakis, Togelius, "Cellular Automata for Real-Time Generation of
## Infinite Cave Levels" (PCGames 2010). Region labelling is a plain flood fill;
## disconnected regions are joined with L-shaped tunnels between their closest
## cells (the "connect rooms" step popular in roguelike dev write-ups).
## Implementation written from the published algorithm descriptions (no code
## copied). Source: https://www.roguebasin.com/index.php/Cellular_Automata_Method_for_Generating_Random_Cave-Like_Levels
## (algorithm description) and the paper above. License: published algorithms only, no code copied.

@warning_ignore_start("integer_division")

## Cell value: 1 = rock, 0 = open floor. Index = y * width + x.


static func generate(width: int, height: int, seed: int, fill: float = 0.47, steps: int = 5) -> PackedByteArray:
	var w: int = maxi(width, 3)
	var h: int = maxi(height, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var grid := PackedByteArray()
	grid.resize(w * h)
	for y in h:
		for x in w:
			var border: bool = x == 0 or y == 0 or x == w - 1 or y == h - 1
			grid[y * w + x] = 1 if (border or rng.randf() < fill) else 0
	for _s in maxi(steps, 0):
		grid = _smooth(grid, w, h)
	_connect_regions(grid, w, h)
	return grid


static func _smooth(grid: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h)
	for y in h:
		for x in w:
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				out[y * w + x] = 1
				continue
			var n: int = 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					n += grid[(y + dy) * w + (x + dx)]
			var cur: int = grid[y * w + x]
			if n >= 5:
				out[y * w + x] = 1
			elif n <= 3:
				out[y * w + x] = 0
			else:
				out[y * w + x] = cur
	return out


## Flood-fill the open cells (4-connected). Returns an Array of PackedInt32Array
## (cell indices), one per region, ordered by discovery.
static func regions(grid: PackedByteArray, w: int, h: int) -> Array:
	var result: Array = []
	var seen := PackedByteArray()
	seen.resize(w * h)
	for start in w * h:
		if grid[start] != 0 or seen[start] != 0:
			continue
		var cells := PackedInt32Array()
		var stack := PackedInt32Array([start])
		seen[start] = 1
		while not stack.is_empty():
			var c: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			cells.append(c)
			var cx: int = c % w
			var cy: int = c / w
			if cx > 0:
				_visit(grid, seen, stack, c - 1)
			if cx < w - 1:
				_visit(grid, seen, stack, c + 1)
			if cy > 0:
				_visit(grid, seen, stack, c - w)
			if cy < h - 1:
				_visit(grid, seen, stack, c + w)
		result.append(cells)
	return result


static func _visit(grid: PackedByteArray, seen: PackedByteArray, stack: PackedInt32Array, idx: int) -> void:
	if grid[idx] == 0 and seen[idx] == 0:
		seen[idx] = 1
		stack.append(idx)


## Centroids (snapped to the nearest open cell of the region, in cell
## coordinates) of every region with at least min_size cells. Good spots for
## loot, bosses or spawners. Ordered by region size, largest first.
static func chambers(grid: PackedByteArray, w: int, h: int, min_size: int) -> Array:
	var regs: Array = regions(grid, w, h)
	regs.sort_custom(func(a: PackedInt32Array, b: PackedInt32Array) -> bool: return a.size() > b.size())
	var out: Array = []
	for r in regs:
		var cells: PackedInt32Array = r
		if cells.size() < min_size:
			continue
		var sum := Vector2.ZERO
		for c in cells:
			sum += Vector2(c % w, c / w)
		var centroid: Vector2 = sum / float(cells.size())
		var best: Vector2 = Vector2(cells[0] % w, cells[0] / w)
		var best_d: float = INF
		for c in cells:
			var p := Vector2(c % w, c / w)
			var d: float = p.distance_squared_to(centroid)
			if d < best_d:
				best_d = d
				best = p
		out.append(best)
	return out


static func _connect_regions(grid: PackedByteArray, w: int, h: int) -> void:
	var regs: Array = regions(grid, w, h)
	if regs.size() <= 1:
		return
	regs.sort_custom(func(a: PackedInt32Array, b: PackedInt32Array) -> bool: return a.size() > b.size())
	var connected: PackedInt32Array = regs[0]
	for i in range(1, regs.size()):
		var other: PackedInt32Array = regs[i]
		var total: float = float(other.size()) * float(connected.size())
		var stride: int = maxi(1, int(ceil(total / 400000.0)))
		var best_a: int = other[0]
		var best_b: int = connected[0]
		var best_d: int = 1 << 60
		for a in other:
			var ax: int = a % w
			var ay: int = a / w
			var j: int = 0
			while j < connected.size():
				var b: int = connected[j]
				var dx: int = ax - b % w
				var dy: int = ay - b / w
				var d: int = dx * dx + dy * dy
				if d < best_d:
					best_d = d
					best_a = a
					best_b = b
				j += stride
		_carve(grid, w, best_a, best_b)
		connected.append_array(other)


## L-shaped tunnel: horizontal along a's row, then vertical along b's column.
static func _carve(grid: PackedByteArray, w: int, a: int, b: int) -> void:
	var ax: int = a % w
	var ay: int = a / w
	var bx: int = b % w
	var by: int = b / w
	var x: int = ax
	var step_x: int = 1 if bx > ax else -1
	while x != bx:
		grid[ay * w + x] = 0
		x += step_x
	var y: int = ay
	var step_y: int = 1 if by > ay else -1
	while y != by:
		grid[y * w + bx] = 0
		y += step_y
	grid[by * w + bx] = 0
