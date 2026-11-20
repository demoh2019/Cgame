extends RefCounted
## Dirt roads that join the hub and the places of the island, worked out from the seed like everything else. Every place
## that people built is linked to its two nearest neighbours (and the hub to its four), and each link winds a little so
## it does not look ruled. Roads are scenery: they cost nothing to the server and do not change movement.
##
## The client asks per chunk: the road pieces crossing it (to paint the ground) and the signposts standing in it.

const Defs = preload("res://scripts/shared/defs.gd")

const HALF_WIDTH := 2.1
const STEP := 14.0 # Spacing of the points along a road.
const MAX_LINK := 720.0 # Longest road between two places.
const NEIGHBOURS := 2
const HUB_LINKS := 4
const HUB_START := 19.0 # Roads leave the hub at the edge of its plaza.
const SIGN_OFFSET := 26.0 # Signposts stand this far out along each road from where it leaves a place.
const LINKED_KINDS := ["village", "farm", "camp", "depot", "outpost", "tower", "mine", "city", "bunker", "lighthouse", "dock"]
const REGION_REACH := 13 # Sites of regions -13..12 on both axes: the whole island.

var world
var _pieces_by_cell: Dictionary = {} # Vector2i -> Array of [Vector2 a, Vector2 b]
var _signs_by_cell: Dictionary = {} # Vector2i -> Array of sign dictionaries
var roads: Array = [] # Every road: {"from": name, "to": name, "points": PackedVector2Array}
var _built := false


func _init(p_world) -> void:
	world = p_world


## The road pieces (segments) that pass close enough to a chunk to colour it.
func pieces_in_cell(cell: Vector2i) -> Array:
	_build()
	return _pieces_by_cell.get(cell, [])


## Signposts in a chunk: {"x", "z", "yaw", "lines": [[name, metres], ...]}.
func signs_in_cell(cell: Vector2i) -> Array:
	_build()
	return _signs_by_cell.get(cell, [])


func all_roads() -> Array:
	_build()
	return roads


func _build() -> void:
	if _built:
		return
	_built = true
	var places: Array = [{"name": "Hub", "x": 0.0, "z": 0.0, "radius": 0.0, "end": HUB_START, "id": -1}]
	for rx in range(-REGION_REACH, REGION_REACH):
		for rz in range(-REGION_REACH, REGION_REACH):
			for site in world.poi.sites_in_region(rx, rz):
				if LINKED_KINDS.has(str(site["kind"])):
					places.append({"name": str(site["display"]), "x": float(site["x"]), "z": float(site["z"]), "radius": float(site["radius"]),
						"end": minf(float(site["radius"]) * 0.35, 20.0), "id": int(site["id"])})
	# Links: each place to its nearest neighbours; links are undirected and kept once.
	var links: Dictionary = {}
	for i in places.size():
		var here := Vector2(places[i]["x"], places[i]["z"])
		var nearest: Array = []
		for j in places.size():
			if i == j:
				continue
			var distance: float = here.distance_to(Vector2(places[j]["x"], places[j]["z"]))
			if distance <= MAX_LINK:
				nearest.append([distance, j])
		nearest.sort_custom(func(a, b) -> bool: return a[0] < b[0])
		var wanted: int = HUB_LINKS if i == 0 else NEIGHBOURS
		for k in mini(wanted, nearest.size()):
			var j: int = nearest[k][1]
			links[Vector2i(mini(i, j), maxi(i, j))] = true
	for key in links:
		_lay_road(places[key.x], places[key.y])


func _lay_road(a: Dictionary, b: Dictionary) -> void:
	var start := Vector2(a["x"], a["z"])
	var finish := Vector2(b["x"], b["z"])
	var direction := (finish - start).normalized()
	start += direction * float(a["end"])
	finish -= direction * float(b["end"])
	var length: float = start.distance_to(finish)
	if length < STEP * 2.0:
		return
	var side := Vector2(-direction.y, direction.x)
	var seed_value: int = world.mix(int(a["x"]), int(b["z"]), int(a["z"]) + int(b["x"]), world.world_seed)
	var phase: float = float(seed_value % 1000) / 1000.0 * TAU
	var wiggle: float = clampf(length * 0.06, 6.0, 28.0)
	var count: int = int(length / STEP) + 1
	var points := PackedVector2Array()
	for n in count + 1:
		var t: float = float(n) / float(count)
		# Two gentle waves, held at zero at both ends so the road meets the places squarely.
		var bend: float = (sin(t * PI * 2.0 + phase) * 0.7 + sin(t * PI * 5.0 + phase * 1.7) * 0.3) * wiggle * sin(t * PI)
		points.append(start.lerp(finish, t) + side * bend)
	roads.append({"from": a["name"], "to": b["name"], "points": points})
	for n in points.size() - 1:
		var p: Vector2 = points[n]
		var q: Vector2 = points[n + 1]
		# Pieces in the sea are left out: the road stops at the shore and starts again on the other side.
		if world.is_water(p.x, p.y) and world.is_water(q.x, q.y):
			continue
		_add_piece(p, q)
	# Near each end, a sign that names the place at the other end.
	_add_sign(points, b, length, true)
	_add_sign(points, a, length, false)


func _add_piece(p: Vector2, q: Vector2) -> void:
	var reach: float = HALF_WIDTH + 1.5
	var low := Vector2(minf(p.x, q.x) - reach, minf(p.y, q.y) - reach)
	var high := Vector2(maxf(p.x, q.x) + reach, maxf(p.y, q.y) + reach)
	var cell_low: Vector2i = Vector2i(floori(low.x / Defs.CHUNK_SIZE), floori(low.y / Defs.CHUNK_SIZE))
	var cell_high: Vector2i = Vector2i(floori(high.x / Defs.CHUNK_SIZE), floori(high.y / Defs.CHUNK_SIZE))
	for cx in range(cell_low.x, cell_high.x + 1):
		for cz in range(cell_low.y, cell_high.y + 1):
			var key := Vector2i(cx, cz)
			if not _pieces_by_cell.has(key):
				_pieces_by_cell[key] = []
			_pieces_by_cell[key].append([p, q])


## A signpost a little way along the road from one end (the start when `at_start`), naming and pointing to `destination`
## at the other end.
func _add_sign(points: PackedVector2Array, destination: Dictionary, length: float, at_start: bool) -> void:
	var index: int = clampi(int(SIGN_OFFSET / STEP), 1, points.size() - 2)
	if not at_start:
		index = points.size() - 1 - index
	var spot: Vector2 = points[index]
	var toward: Vector2 = (points[index + 1] - points[index - 1]).normalized()
	if not at_start:
		toward = -toward
	# Stand beside the road, not on it.
	var beside: Vector2 = spot + Vector2(-toward.y, toward.x) * (HALF_WIDTH + 1.2)
	if world.is_water(beside.x, beside.y):
		return
	var cell := Vector2i(floori(beside.x / Defs.CHUNK_SIZE), floori(beside.y / Defs.CHUNK_SIZE))
	if not _signs_by_cell.has(cell):
		_signs_by_cell[cell] = []
	var target_name: String = str(destination["name"])
	# The sign names the place at the far end of the road.
	_signs_by_cell[cell].append({"x": beside.x, "z": beside.y, "yaw": atan2(toward.x, toward.y), "to": target_name, "metres": int(round(length))})
