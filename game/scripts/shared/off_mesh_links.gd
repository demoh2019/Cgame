extends RefCounted
## Automatic off-mesh link generation from a heightfield.
## Inspired by Recast/Detour off-mesh connections: traversals the walkable grid cannot express
## (ledge drops, small climbs, short gaps) become explicit links the navigation layer can use.
##
## Link kinds:
##   "drop" - one-way ledge down between adjacent walkable cells (height gap > walk_step, <= max_drop)
##   "jump" - bidirectional small climb: adjacent walkable cells, gap in (walk_step, max_jump_up]
##   "gap"  - bidirectional hop over 1..max_gap unwalkable cells between walkable cells of similar height
## Cells are scanned row by row (y, then x) towards +x then +y, so order is deterministic
## and every pair appears once.

const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]


static func generate(width: int, height: int, height_at: Callable, walkable: Callable,
		max_drop := 3.0, max_jump_up := 1.2, max_gap := 2, walk_step := 0.5) -> Array:
	var links: Array = []
	for y in height:
		for x in width:
			if not walkable.call(x, y):
				continue
			var here := Vector2i(x, y)
			var h0: float = height_at.call(x, y)
			for dir in DIRS:
				var n := here + dir
				if _in(n, width, height) and walkable.call(n.x, n.y):
					var dh: float = float(height_at.call(n.x, n.y)) - h0
					_step_link(links, here, n, dh, max_drop, max_jump_up, walk_step)
				else:
					_gap_link(links, here, dir, h0, width, height, height_at, walkable, max_jump_up, max_gap)
	return links


static func _in(c: Vector2i, w: int, h: int) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


static func _step_link(links: Array, a: Vector2i, b: Vector2i, dh: float,
		max_drop: float, max_jump_up: float, walk_step: float) -> void:
	var rise: float = absf(dh)
	if rise <= walk_step:
		return
	var upper: Vector2i = a if dh < 0.0 else b
	var lower: Vector2i = b if dh < 0.0 else a
	if rise <= max_jump_up:
		links.append({"from": lower, "to": upper, "kind": "jump", "bidirectional": true})
	elif rise <= max_drop:
		links.append({"from": upper, "to": lower, "kind": "drop", "bidirectional": false})


static func _gap_link(links: Array, a: Vector2i, dir: Vector2i, h0: float, w: int, h: int,
		height_at: Callable, walkable: Callable, max_jump_up: float, max_gap: int) -> void:
	var first := a + dir
	if not _in(first, w, h):
		return
	for span in range(1, max_gap + 1):
		var cell := a + dir * (span + 1)
		if not _in(cell, w, h):
			return
		if not walkable.call(cell.x, cell.y):
			continue
		var dh: float = absf(float(height_at.call(cell.x, cell.y)) - h0)
		if dh <= max_jump_up:
			links.append({"from": a, "to": cell, "kind": "gap", "bidirectional": true})
		return
