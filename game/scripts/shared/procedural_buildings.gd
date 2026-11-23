extends RefCounted
## Shape-grammar style buildings and Poisson-disk settlements.
##
## Techniques (algorithms re-implemented from descriptions, no code copied):
## - BSP rectangle subdivision for room layout (classic roguelike/dungeon
##   technique, RogueBasin "Basic BSP Dungeon generation",
##   https://www.roguebasin.com/index.php/Basic_BSP_Dungeon_generation).
## - Door graph = randomised Kruskal spanning tree over shared room walls plus
##   a few extra edges for loops.
## - Poisson-disk sampling: Robert Bridson, "Fast Poisson Disk Sampling in
##   Arbitrary Dimensions", SIGGRAPH 2007 sketch
##   (https://www.cs.ubc.ca/~rbridson/docs/bridson-siggraph07-poissondisk.pdf).
## License: published algorithms/papers only.

@warning_ignore_start("integer_division")

const MIN_ROOM := 3
const MAX_BUILDING_SIDE := 64
const MAX_BUILDING_FLOORS := 8
const MIN_LOT := 4
const MAX_SETTLEMENT_LOTS := 96
const MAX_SETTLEMENT_RADIUS := 2048.0
const MIN_LOT_SPACING := 6.0
const LOOP_CHANCE := 0.25
const BRIDSON_TRIES := 30


## Returns {"footprint": Vector2i, "floors": int,
##  "rooms":   [{"id", "floor", "rect": Rect2i}]  (per floor the rects tile the footprint),
##  "doors":   [{"floor", "a", "b", "cell_a": Vector2i, "cell_b": Vector2i}] (a/b room ids),
##  "stairs":  [{"from_floor", "to_floor", "cell": Vector2i, "room_from", "room_to"}],
##  "windows": [{"floor", "room", "cell": Vector2i, "normal": Vector2i}],
##  "entrance": {"room", "cell": Vector2i, "normal": Vector2i}}
static func building(seed: int, footprint: Vector2i, floors: int) -> Dictionary:
	# Procedural inputs can come from generated POI data. Clamp them before
	# the per-floor O(room_count^2) doorway graph is constructed.
	var fp := Vector2i(
		clampi(footprint.x, MIN_ROOM, MAX_BUILDING_SIDE),
		clampi(footprint.y, MIN_ROOM, MAX_BUILDING_SIDE))
	var nfloors: int = clampi(floors, 1, MAX_BUILDING_FLOORS)
	var rooms: Array = []
	var doors: Array = []
	var windows: Array = []
	var stairs: Array = []
	var entrance: Dictionary = {}
	var floor_rooms: Array = []  # Array of Array of room dicts, per floor
	for f in nfloors:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed + f * 7919
		var rects: Array = []
		_split(Rect2i(Vector2i.ZERO, fp), rng, rects)
		var this_floor: Array = []
		for r in rects:
			var room: Dictionary = {"id": rooms.size(), "floor": f, "rect": r}
			rooms.append(room)
			this_floor.append(room)
		floor_rooms.append(this_floor)
		doors.append_array(_doors_for_floor(f, this_floor, rng))
		if f == 0:
			entrance = _entrance(this_floor, fp, rng)
		_windows_for_floor(f, this_floor, fp, entrance, windows)
	for f in nfloors - 1:
		var lower: Array = floor_rooms[f]
		var upper: Array = floor_rooms[f + 1]
		var best: Dictionary = lower[0]
		for rm in lower:
			var rd: Dictionary = rm
			var rr: Rect2i = rd["rect"]
			var br: Rect2i = best["rect"]
			if rr.get_area() > br.get_area():
				best = rd
		var brect: Rect2i = best["rect"]
		var cell: Vector2i = brect.get_center()
		var up_id: int = -1
		for rm in upper:
			var ud: Dictionary = rm
			var ur: Rect2i = ud["rect"]
			if ur.has_point(cell):
				up_id = ud["id"]
				break
		stairs.append({"from_floor": f, "to_floor": f + 1, "cell": cell, "room_from": best["id"], "room_to": up_id})
	return {"footprint": fp, "floors": nfloors, "rooms": rooms, "doors": doors, "stairs": stairs,
		"windows": windows, "entrance": entrance}


static func _split(rect: Rect2i, rng: RandomNumberGenerator, out: Array) -> void:
	var can_x: bool = rect.size.x >= 2 * MIN_ROOM
	var can_y: bool = rect.size.y >= 2 * MIN_ROOM
	if not can_x and not can_y:
		out.append(rect)
		return
	if rect.size.x * rect.size.y <= 40 and rng.randf() < 0.5:
		out.append(rect)
		return
	var split_x: bool
	if can_x and can_y:
		if float(rect.size.x) > float(rect.size.y) * 1.25:
			split_x = true
		elif float(rect.size.y) > float(rect.size.x) * 1.25:
			split_x = false
		else:
			split_x = rng.randf() < 0.5
	else:
		split_x = can_x
	if split_x:
		var cut: int = rng.randi_range(MIN_ROOM, rect.size.x - MIN_ROOM)
		_split(Rect2i(rect.position, Vector2i(cut, rect.size.y)), rng, out)
		_split(Rect2i(rect.position + Vector2i(cut, 0), Vector2i(rect.size.x - cut, rect.size.y)), rng, out)
	else:
		var cut: int = rng.randi_range(MIN_ROOM, rect.size.y - MIN_ROOM)
		_split(Rect2i(rect.position, Vector2i(rect.size.x, cut)), rng, out)
		_split(Rect2i(rect.position + Vector2i(0, cut), Vector2i(rect.size.x, rect.size.y - cut)), rng, out)


static func _doors_for_floor(f: int, fr: Array, rng: RandomNumberGenerator) -> Array:
	var cand: Array = []
	for i in fr.size():
		for j in range(i + 1, fr.size()):
			var da: Dictionary = fr[i]
			var db: Dictionary = fr[j]
			var a: Rect2i = da["rect"]
			var b: Rect2i = db["rect"]
			var door: Dictionary = {}
			if a.end.x == b.position.x or b.end.x == a.position.x:
				var lo: int = maxi(a.position.y, b.position.y)
				var hi: int = mini(a.end.y, b.end.y)
				if hi > lo:
					var y: int = rng.randi_range(lo, hi - 1)
					if a.end.x == b.position.x:
						door = {"ca": Vector2i(a.end.x - 1, y), "cb": Vector2i(b.position.x, y)}
					else:
						door = {"ca": Vector2i(a.position.x, y), "cb": Vector2i(b.end.x - 1, y)}
			if door.is_empty() and (a.end.y == b.position.y or b.end.y == a.position.y):
				var lo2: int = maxi(a.position.x, b.position.x)
				var hi2: int = mini(a.end.x, b.end.x)
				if hi2 > lo2:
					var x: int = rng.randi_range(lo2, hi2 - 1)
					if a.end.y == b.position.y:
						door = {"ca": Vector2i(x, a.end.y - 1), "cb": Vector2i(x, b.position.y)}
					else:
						door = {"ca": Vector2i(x, a.position.y), "cb": Vector2i(x, b.end.y - 1)}
			if not door.is_empty():
				door["i"] = i
				door["j"] = j
				cand.append(door)
	for i in range(cand.size() - 1, 0, -1):
		var k: int = rng.randi_range(0, i)
		var tmp: Variant = cand[i]
		cand[i] = cand[k]
		cand[k] = tmp
	var parent := PackedInt32Array()
	parent.resize(fr.size())
	for i in fr.size():
		parent[i] = i
	var out: Array = []
	for c in cand:
		var cd: Dictionary = c
		var ra: int = _find(parent, cd["i"])
		var rb: int = _find(parent, cd["j"])
		var take: bool = false
		if ra != rb:
			parent[ra] = rb
			take = true
		elif rng.randf() < LOOP_CHANCE:
			take = true
		if take:
			var roa: Dictionary = fr[cd["i"]]
			var rob: Dictionary = fr[cd["j"]]
			out.append({"floor": f, "a": roa["id"], "b": rob["id"], "cell_a": cd["ca"], "cell_b": cd["cb"]})
	return out


static func _find(parent: PackedInt32Array, i: int) -> int:
	var r: int = i
	while parent[r] != r:
		r = parent[r]
	return r


static func _entrance(fr: Array, fp: Vector2i, rng: RandomNumberGenerator) -> Dictionary:
	var choices: Array = []
	for rm in fr:
		var rd: Dictionary = rm
		var r: Rect2i = rd["rect"]
		if r.end.y == fp.y:
			choices.append(rd)
	var pick: Dictionary = choices[rng.randi_range(0, choices.size() - 1)]
	var pr: Rect2i = pick["rect"]
	var x: int = rng.randi_range(pr.position.x, pr.end.x - 1)
	return {"room": pick["id"], "cell": Vector2i(x, fp.y - 1), "normal": Vector2i(0, 1)}


static func _windows_for_floor(f: int, fr: Array, fp: Vector2i, entrance: Dictionary, out: Array) -> void:
	for rm in fr:
		var rd: Dictionary = rm
		var r: Rect2i = rd["rect"]
		var id: int = rd["id"]
		var spots: Array = []  # [cell, normal]
		if r.position.y == 0:
			for x in range(r.position.x + 1, r.end.x - 1, 2):
				spots.append([Vector2i(x, 0), Vector2i(0, -1)])
		if r.end.y == fp.y:
			for x in range(r.position.x + 1, r.end.x - 1, 2):
				spots.append([Vector2i(x, fp.y - 1), Vector2i(0, 1)])
		if r.position.x == 0:
			for y in range(r.position.y + 1, r.end.y - 1, 2):
				spots.append([Vector2i(0, y), Vector2i(-1, 0)])
		if r.end.x == fp.x:
			for y in range(r.position.y + 1, r.end.y - 1, 2):
				spots.append([Vector2i(fp.x - 1, y), Vector2i(1, 0)])
		for s in spots:
			var cell: Vector2i = s[0]
			if f == 0 and not entrance.is_empty() and entrance["cell"] == cell:
				continue
			out.append({"floor": f, "room": id, "cell": cell, "normal": s[1]})


## Building lots around a plaza. Returns an Array of Dictionaries; entry 0 is
## {"kind": "plaza", "center": Vector2, "radius": float}, the rest are
## {"kind": "lot", "center": Vector2, "rect": Rect2, "footprint": Vector2i,
##  "floors": int, "seed": int}. Lots never overlap each other or the plaza and
## lie completely inside the settlement circle. At most `count` lots.
static func settlement(seed: int, center: Vector2, radius: float, count: int) -> Array:
	var out: Array = []
	# Reject invalid geometry before sampling and cap the requested lots so a
	# malformed POI cannot allocate an unbounded candidate grid or lot list.
	if not center.is_finite() or not is_finite(radius) or radius <= 0.0 or \
			radius > MAX_SETTLEMENT_RADIUS or count < 0:
		return out
	var bounded_count: int = mini(count, MAX_SETTLEMENT_LOTS)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var d: float = maxf(MIN_LOT_SPACING,
		radius * sqrt(2.0 / float(maxi(bounded_count, 1))))
	var plaza_r: float = d * 0.6
	out.append({"kind": "plaza", "center": center, "radius": plaza_r})
	if bounded_count <= 0:
		return out
	var min_r: float = plaza_r + 0.5 * d
	var max_r: float = radius - 0.5 * d
	if max_r <= min_r:
		return out
	var cell: float = d / sqrt(2.0)
	var grid: Dictionary = {}
	var pts: Array = []  # Vector2 offsets from center
	var active: Array = []
	var first: Vector2 = Vector2.ZERO
	var ok: bool = false
	for _i in 200:
		var ang: float = rng.randf() * TAU
		var rr: float = sqrt(rng.randf_range(min_r * min_r, max_r * max_r))
		first = Vector2(cos(ang), sin(ang)) * rr
		ok = true
		break
	if not ok:
		return out
	pts.append(first)
	active.append(0)
	grid[Vector2i(int(floor(first.x / cell)), int(floor(first.y / cell)))] = 0
	while not active.is_empty() and pts.size() < bounded_count:
		var ai: int = rng.randi_range(0, active.size() - 1)
		var base: Vector2 = pts[active[ai]]
		var found: bool = false
		for _k in BRIDSON_TRIES:
			var ang2: float = rng.randf() * TAU
			var dist: float = d * (1.0 + rng.randf())
			var cand: Vector2 = base + Vector2(cos(ang2), sin(ang2)) * dist
			var cl: float = cand.length()
			if cl < min_r or cl > max_r:
				continue
			if _too_close(cand, pts, grid, cell, d):
				continue
			grid[Vector2i(int(floor(cand.x / cell)), int(floor(cand.y / cell)))] = pts.size()
			active.append(pts.size())
			pts.append(cand)
			found = true
			break
		if not found:
			active.remove_at(ai)
	var max_side: int = maxi(MIN_LOT, int(0.7 * d))
	for p in pts:
		var off: Vector2 = p
		var fx: int = rng.randi_range(MIN_LOT, max_side)
		var fy: int = rng.randi_range(MIN_LOT, max_side)
		var size := Vector2(fx, fy)
		var pos: Vector2 = center + off
		out.append({"kind": "lot", "center": pos, "rect": Rect2(pos - size * 0.5, size),
			"footprint": Vector2i(fx, fy), "floors": rng.randi_range(1, 3), "seed": rng.randi()})
		if out.size() > bounded_count:
			break
	return out


static func _too_close(cand: Vector2, pts: Array, grid: Dictionary, cell: float, d: float) -> bool:
	var gx: int = int(floor(cand.x / cell))
	var gy: int = int(floor(cand.y / cell))
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var key := Vector2i(gx + dx, gy + dy)
			if grid.has(key):
				var idx: int = grid[key]
				var other: Vector2 = pts[idx]
				if other.distance_to(cand) < d:
					return true
	return false
