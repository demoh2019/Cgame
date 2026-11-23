extends RefCounted
## Dirt roads that join the hub and the places of the island, worked out from the seed like everything else. Every place
## that people built is linked to its two nearest neighbours (and the hub to its four), and each link winds a little so
## it does not look ruled. Road segments are also indexed for deterministic travel grip.
##
## The client asks per chunk: the road pieces crossing it (to paint the ground) and the signposts standing in it.

const Defs = preload("res://scripts/shared/defs.gd")
const CityLayout = preload("res://scripts/shared/city_layout.gd")

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
# Prepacked spatial cells for Cgame's native nearest-segment query; never sent over the network.
var _packed_pieces_by_cell: Dictionary = {}
var _native_nearest_segments: bool = Geometry2D.has_method("get_closest_point_on_segments")
var _signs_by_cell: Dictionary = {} # Vector2i -> Array of sign dictionaries
var roads: Array = [] # Every road: {"from": name, "to": name, "points": PackedVector2Array}
var _built := false
var bridges: Array = [] # [{"points": PackedVector2Array, "deck": PackedFloat32Array}] where roads cross rivers
var _bridges_by_cell: Dictionary = {}
const BRIDGE_MAX_SPAN := 70.0
const BRIDGE_HALF_WIDTH := 2.4


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


## Undirected nearest-neighbor graph. All locations have stable array indices.
## On Cgame a single native query handles all pairs; on stock Godot we preserve
## the original distance scan with a deterministic index tie-break.
static func compute_links(places: Array, max_link: float = MAX_LINK,
		regular_neighbors: int = NEIGHBOURS, hub_neighbors: int = HUB_LINKS,
		force_scalar: bool = false) -> Dictionary:
	var links: Dictionary = {}
	if not is_finite(max_link) or max_link < 0.0 or regular_neighbors < 0 or hub_neighbors < 0:
		return links
	var positions := PackedVector2Array()
	for place in places:
		var point := Vector2(float(place["x"]), float(place["z"]))
		if not point.is_finite():
			return {}
		positions.append(point)
	var native: Array = []
	var use_native: bool = not force_scalar and places.size() <= 4096
	use_native = use_native and maxi(regular_neighbors, hub_neighbors) <= 32
	if use_native and Geometry2D.has_method("get_nearest_neighbors"):
		native = Geometry2D.call(
				"get_nearest_neighbors", positions, maxi(regular_neighbors, hub_neighbors), max_link)
	for i in positions.size():
		var wanted: int = hub_neighbors if i == 0 else regular_neighbors
		if native.size() == positions.size():
			var matches: PackedInt32Array = native[i]
			for k in mini(wanted, matches.size()):
				var neighbor: int = matches[k]
				links[Vector2i(mini(i, neighbor), maxi(i, neighbor))] = true
			continue
		# Stock Godot fallback: track only the nearest K candidates rather than
		# allocating and sorting every one of the island's other locations.
		if wanted <= 0:
			continue
		var nearest: Array = [] # [squared distance, index], sorted ascending.
		var max_distance_squared: float = max_link * max_link
		for j in positions.size():
			if i == j:
				continue
			var distance_squared: float = positions[i].distance_squared_to(positions[j])
			if distance_squared > max_distance_squared:
				continue
			if nearest.size() == wanted:
				var tail: Array = nearest[nearest.size() - 1]
				if distance_squared > float(tail[0]) or (distance_squared == float(tail[0]) and j >= int(tail[1])):
					continue
			var insertion := 0
			while insertion < nearest.size():
				var current: Array = nearest[insertion]
				if distance_squared < float(current[0]) or (distance_squared == float(current[0]) and j < int(current[1])):
					break
				insertion += 1
			nearest.insert(insertion, [distance_squared, j])
			if nearest.size() > wanted:
				nearest.pop_back()
		for candidate in nearest:
			var neighbor: int = int(candidate[1])
			links[Vector2i(mini(i, neighbor), maxi(i, neighbor))] = true
	return links


func _build() -> void:
	if _built:
		return
	_built = true
	var places: Array = [{"name": "Hub", "x": 0.0, "z": 0.0, "radius": 0.0, "end": HUB_START, "id": -1}]
	for rx in range(-REGION_REACH, REGION_REACH):
		for rz in range(-REGION_REACH, REGION_REACH):
			for site in world.poi.sites_in_region(rx, rz):
				if LINKED_KINDS.has(str(site["kind"])):
					var place: Dictionary = {"name": str(site["display"]), "x": float(site["x"]), "z": float(site["z"]),
						"radius": float(site["radius"]), "end": minf(float(site["radius"]) * 0.35, 20.0), "id": int(site["id"])}
					if str(site["kind"]) == "city":
						var plan: Dictionary = world.poi.city_plan(site)
						place["city_paths"] = plan["paths"]
						_lay_city_streets(site)
					places.append(place)
	# Build the graph in one native nearest-neighbor pass when Cgame supports it.
	# The identical scalar fallback works on stock Godot.
	for key in compute_links(places):
		_lay_road(places[key.x], places[key.y])


## Index the local streets with the same terrain mask and authoritative road grip as intercity roads.
func _lay_city_streets(site: Dictionary) -> void:
	var center := Vector2(float(site["x"]), float(site["z"]))
	var plan: Dictionary = world.poi.city_plan(site)
	var paths: Array = plan["paths"]
	for offsets in paths:
		var points := PackedVector2Array()
		for offset in offsets:
			points.append(center + Vector2(offset))
		if points.size() < 3:
			continue
		roads.append({"from": str(site["display"]), "to": str(site["display"]), "points": points})
		for i in points.size() - 1:
			var a: Vector2 = points[i]
			var b: Vector2 = points[i + 1]
			if world.is_water(a.x, a.y) and world.is_water(b.x, b.y):
				continue
			_add_piece(a, b)


func _lay_road(a: Dictionary, b: Dictionary) -> void:
	var start := Vector2(a["x"], a["z"])
	var finish := Vector2(b["x"], b["z"])
	var direction := (finish - start).normalized()
	if a.has("city_paths"):
		var from_paths: Array = a["city_paths"]
		start += CityLayout.entrance_on_paths(from_paths, direction)
	else:
		start += direction * float(a["end"])
	if b.has("city_paths"):
		var to_paths: Array = b["city_paths"]
		finish += CityLayout.entrance_on_paths(to_paths, -direction)
	else:
		finish -= direction * float(b["end"])
	var length: float = start.distance_to(finish)
	# Preserve old non-city link spacing; a nearby city entrance still needs a short connection.
	var minimum_length: float = 3.0 if a.has("city_paths") or b.has("city_paths") else STEP * 2.0
	if length < minimum_length:
		return
	var side := Vector2(-direction.y, direction.x)
	var seed_value: int = world.mix(int(a["x"]), int(b["z"]), int(a["z"]) + int(b["x"]), world.world_seed)
	var phase: float = float(seed_value % 1000) / 1000.0 * TAU
	var wiggle: float = clampf(length * 0.06, 6.0, 28.0)
	var count: int = maxi(2, int(length / STEP) + 1)
	var points := PackedVector2Array()
	for n in count + 1:
		var t: float = float(n) / float(count)
		# Two gentle waves, held at zero at both ends so the road meets the places squarely.
		var bend: float = (sin(t * PI * 2.0 + phase) * 0.7 + sin(t * PI * 5.0 + phase * 1.7) * 0.3) * wiggle * sin(t * PI)
		points.append(start.lerp(finish, t) + side * bend)
	roads.append({"from": a["name"], "to": b["name"], "points": points})
	_find_bridges(points)
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
			# The original scalar fallback ignores degenerate segments; keep native parity.
			if _native_nearest_segments and (q - p).length_squared() >= 0.00001:
				var packed: PackedVector2Array = _packed_pieces_by_cell.get(key, PackedVector2Array())
				packed.append(p)
				packed.append(q)
				_packed_pieces_by_cell[key] = packed

## Paint a grayscale road coverage mask for one chunk. Engine-native rasterization
## avoids GDScript calls per touched texel. The scalar path preserves stock Godot.
## Endpoint coordinates are world x/z; pixel centers are at local (+0.5, +0.5).
static func rasterize_mask(pieces: Array, origin: Vector2, size: int, half: float = HALF_WIDTH,
		soft: float = 1.2, force_scalar: bool = false) -> PackedByteArray:
	if size < 1 or size > 2048 or not origin.is_finite() or not is_finite(half) or half < 0.0:
		return PackedByteArray()
	if not is_finite(soft) or soft <= 0.0:
		return PackedByteArray()
	if not force_scalar and Geometry2D.has_method("rasterize_segments_mask"):
		var endpoints := PackedVector2Array()
		for piece in pieces:
			endpoints.append(piece[0] - origin)
			endpoints.append(piece[1] - origin)
		var native: PackedByteArray = Geometry2D.call(
				"rasterize_segments_mask", endpoints, Vector2i(size, size), half, soft)
		if native.size() == size * size:
			return native

	var data := PackedByteArray()
	data.resize(size * size)
	var reach: float = half + soft
	for piece in pieces:
		var a: Vector2 = piece[0] - origin
		var b: Vector2 = piece[1] - origin
		var x0: int = maxi(0, floori(minf(a.x, b.x) - reach))
		var x1: int = mini(size - 1, ceili(maxf(a.x, b.x) + reach))
		var y0: int = maxi(0, floori(minf(a.y, b.y) - reach))
		var y1: int = mini(size - 1, ceili(maxf(a.y, b.y) + reach))
		var ab: Vector2 = b - a
		var length_squared: float = maxf(ab.length_squared(), 0.0001)
		for py in range(y0, y1 + 1):
			for px in range(x0, x1 + 1):
				var point := Vector2(float(px) + 0.5, float(py) + 0.5)
				var t_along: float = clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
				var distance: float = point.distance_to(a + ab * t_along)
				if distance >= reach:
					continue
				var value: int = int(255.0 * clampf((reach - distance) / soft, 0.0, 1.0))
				var index: int = py * size + px
				if value > data[index]:
					data[index] = value
	return data


## Nearest point on each terrain-painted segment. All road checks use the
## existing spatial cell index, never the full network on every frame.
static func coverage_on_segments(point: Vector2, segments: Array) -> float:
	if not point.is_finite():
		return 0.0
	var closest := 0.0
	for piece in segments:
		if not (piece is Array) or piece.size() != 2:
			continue
		var a: Vector2 = piece[0]
		var b: Vector2 = piece[1]
		if not a.is_finite() or not b.is_finite():
			continue
		var line: Vector2 = b - a
		var squared: float = line.length_squared()
		if squared < 0.00001:
			continue
		var t: float = clampf((point - a).dot(line) / squared, 0.0, 1.0)
		var distance: float = point.distance_to(a + line * t)
		closest = maxf(closest, 1.0 - smoothstep(
			HALF_WIDTH * 0.75, HALF_WIDTH + 1.0, distance))
		if closest >= 0.9999:
			return 1.0
	return closest

func coverage_at(x: float, z: float) -> float:
	if not is_finite(x) or not is_finite(z):
		return 0.0
	var cell := Vector2i(floori(x / Defs.CHUNK_SIZE), floori(z / Defs.CHUNK_SIZE))
	# Reject roadless cells before sampling multi-octave water/terrain noise.
	# The spatial cell index is populated once by the native/scalar road graph.
	var pieces: Array = pieces_in_cell(cell)
	if pieces.is_empty() or world.is_water(x, z):
		return 0.0
	if _native_nearest_segments:
		var packed: PackedVector2Array = _packed_pieces_by_cell.get(cell, PackedVector2Array())
		if not packed.is_empty():
			var nearest: Dictionary = Geometry2D.call("get_closest_point_on_segments", Vector2(x, z), packed)
			if not nearest.is_empty():
				var coverage: float = 1.0 - smoothstep(HALF_WIDTH * 0.75, HALF_WIDTH + 1.0, float(nearest["distance"]))
				# The scalar path short-circuits when it reaches this threshold.
				return 1.0 if coverage >= 0.9999 else coverage
	return coverage_on_segments(Vector2(x, z), pieces)


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


# --- Bridges -------------------------------------------------------------------------------------------

## Where a road runs through a river, a timber bridge spans it from bank to bank. The deck
## arches gently and is part of the terrain height (height_at), so walking, carts and the
## renderer all use the same surface.
func _find_bridges(points: PackedVector2Array) -> void:
	if world.rivers == null:
		return
	var n := 0
	while n < points.size():
		var p: Vector2 = points[n]
		if world.rivers.surface_at(p.x, p.y) == -INF:
			n += 1
			continue
		var first: int = maxi(n - 1, 0)
		var last: int = n
		while last < points.size() - 1 and world.rivers.surface_at(points[last].x, points[last].y) != -INF:
			last += 1
		var a: Vector2 = points[first]
		var b: Vector2 = points[last]
		# Reach a little onto dry land at both ends.
		a = a + (a - b).normalized() * 3.0
		b = b + (b - a).normalized() * 3.0
		if a.distance_to(b) <= BRIDGE_MAX_SPAN:
			var top: float = maxf(world.rivers.surface_at(points[n].x, points[n].y) + 1.1, 0.0)
			var ya: float = maxf(world.height_at(a.x, a.y), top - 1.0) + 0.12
			var yb: float = maxf(world.height_at(b.x, b.y), top - 1.0) + 0.12
			var bridge := {"a": a, "b": b, "ya": ya, "yb": yb, "top": top}
			bridges.append(bridge)
			var reach: float = BRIDGE_HALF_WIDTH + 1.0
			for cx in range(floori((minf(a.x, b.x) - reach) / Defs.CHUNK_SIZE), floori((maxf(a.x, b.x) + reach) / Defs.CHUNK_SIZE) + 1):
				for cz in range(floori((minf(a.y, b.y) - reach) / Defs.CHUNK_SIZE), floori((maxf(a.y, b.y) + reach) / Defs.CHUNK_SIZE) + 1):
					var key := Vector2i(cx, cz)
					if not _bridges_by_cell.has(key):
						_bridges_by_cell[key] = []
					_bridges_by_cell[key].append(bridge)
		n = last + 1


## Height of a bridge deck at this point, or -INF off every bridge.
func bridge_deck(x: float, z: float) -> float:
	_build()
	var key := Vector2i(floori(x / Defs.CHUNK_SIZE), floori(z / Defs.CHUNK_SIZE))
	var best := -INF
	for bridge in _bridges_by_cell.get(key, []):
		var a: Vector2 = bridge["a"]
		var ab: Vector2 = bridge["b"] - a
		var t: float = clampf((Vector2(x, z) - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if Vector2(x, z).distance_to(a + ab * t) > BRIDGE_HALF_WIDTH:
			continue
		best = maxf(best, deck_height(bridge, t))
	return best


static func deck_height(bridge: Dictionary, t: float) -> float:
	var straight: float = lerpf(bridge["ya"], bridge["yb"], t)
	var arch: float = maxf(float(bridge["top"]) - straight, 0.0) + 0.5
	return straight + arch * sin(t * PI)


func bridges_in_cell(cell: Vector2i) -> Array:
	_build()
	return _bridges_by_cell.get(cell, [])
