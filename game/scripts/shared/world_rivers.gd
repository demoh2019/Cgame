extends RefCounted
## Rivers and lakes, generated once per world seed and shared by server and client.
## Sources sit high in the hills; each river follows the steepest descent of the land (as rain
## water would), its surface only ever going down, until it reaches the sea. A river that gets
## trapped in a hollow fills it as a lake. The terrain is carved under them (a channel with
## sloping banks), so height_at, movement and rendering all agree. Rivers are spline polylines
## smoothed with Chaikin's algorithm and widen downstream.

const Defs = preload("res://scripts/shared/defs.gd")

const SOURCE_GRID := 380.0 # Candidate sources: one per grid cell, the highest sample.
const SOURCE_MIN_HEIGHT := 26.0
const MAX_RIVERS := 16
const STEP := 22.0
const MAX_STEPS := 140
const MIN_LENGTH := 260.0
const WIDTH_START := 2.2
const WIDTH_END := 9.0
const BANK := 11.0 # Sloping bank beyond the water's edge.
const DEPTH := 1.25 # Water depth in mid channel.
const MAX_GORGE := 22.0 # A river does not saw deeper than this through a ridge: it ends there.
const CELL := 64.0
const LAKE_MIN_RADIUS := 26.0
const LAKE_MAX_RADIUS := 58.0

var world
var rivers: Array = [] # [{"points": PackedVector2Array, "surface": PackedFloat32Array, "width": PackedFloat32Array}]
var lakes: Array = [] # [{"x", "z", "radius", "surface"}]
var _segments_by_cell: Dictionary = {} # Vector2i -> Array of segment dictionaries
var _lakes_by_cell: Dictionary = {}
var _built := false
var _building := false


func _init(p_world) -> void:
	world = p_world


func ensure_built() -> void:
	if _built or _building:
		return
	_building = true
	_build()
	_building = false
	_built = true


## Ground with river channels and lake basins cut in (base = the natural land).
func carve(x: float, z: float, base: float) -> float:
	if not _built:
		return base
	var key := Vector2i(floori(x / CELL), floori(z / CELL))
	var result: float = base
	for seg in _segments_by_cell.get(key, []):
		var a: Vector2 = seg["a"]
		var ab: Vector2 = seg["ab"]
		var t: float = clampf((Vector2(x, z) - a).dot(ab) * float(seg["inv_len2"]), 0.0, 1.0)
		var d: float = Vector2(x, z).distance_to(a + ab * t)
		var w: float = lerpf(seg["w0"], seg["w1"], t)
		if d > w + BANK:
			continue
		var surface: float = lerpf(seg["s0"], seg["s1"], t)
		# Rounded bed: deepest in the middle, rising to the water's edge, then the bank slope.
		var bed: float = surface - DEPTH * (1.0 - (d / maxf(w, 0.1)) * (d / maxf(w, 0.1))) if d < w else surface + (d - w) / BANK * 2.2 - 0.25
		var shaped: float = lerpf(bed, base, smoothstep(w, w + BANK, d)) if d >= w else bed
		result = minf(result, shaped)
	for lake in _lakes_by_cell.get(key, []):
		var d2: float = Vector2(x, z).distance_to(Vector2(lake["x"], lake["z"]))
		var r: float = lake["radius"]
		if d2 > r + BANK * 1.5:
			continue
		var bowl: float = float(lake["surface"]) - 2.6 * (1.0 - (d2 / r) * (d2 / r)) if d2 < r else float(lake["surface"]) + (d2 - r) / (BANK * 1.5) * 2.0 - 0.3
		result = minf(result, lerpf(bowl, base, smoothstep(r, r + BANK * 1.5, d2)) if d2 >= r else bowl)
	return result


## River or lake water surface over this point, or -INF when there is none.
func surface_at(x: float, z: float) -> float:
	if not _built:
		return -INF
	var key := Vector2i(floori(x / CELL), floori(z / CELL))
	var best: float = -INF
	for seg in _segments_by_cell.get(key, []):
		var a: Vector2 = seg["a"]
		var ab: Vector2 = seg["ab"]
		var t: float = clampf((Vector2(x, z) - a).dot(ab) * float(seg["inv_len2"]), 0.0, 1.0)
		if Vector2(x, z).distance_to(a + ab * t) <= lerpf(seg["w0"], seg["w1"], t):
			best = maxf(best, lerpf(seg["s0"], seg["s1"], t))
	for lake in _lakes_by_cell.get(key, []):
		if Vector2(x, z).distance_to(Vector2(lake["x"], lake["z"])) <= float(lake["radius"]):
			best = maxf(best, float(lake["surface"]))
	return best


func segments_in_cell(cell: Vector2i) -> Array:
	return _segments_by_cell.get(cell, [])


func lakes_in_cell(cell: Vector2i) -> Array:
	return _lakes_by_cell.get(cell, [])


func _build() -> void:
	var sources: Array = []
	var reach: float = world.EDGE_START - 150.0
	var cells: int = int(reach / SOURCE_GRID)
	for gx in range(-cells, cells + 1):
		for gz in range(-cells, cells + 1):
			var best := Vector2.ZERO
			var best_h := -INF
			for k in 6:
				var h: int = world.mix(gx, gz, world.world_seed, 900 + k)
				var p := Vector2((float(gx) + float(h % 1000) / 1000.0) * SOURCE_GRID, (float(gz) + float((h / 1000) % 1000) / 1000.0) * SOURCE_GRID)
				if p.length() > reach or p.length() < world.HUB_BLEND_END + 80.0:
					continue
				var y: float = world._base_height(p.x, p.y)
				if y > best_h:
					best_h = y
					best = p
			if best_h >= SOURCE_MIN_HEIGHT:
				sources.append([best_h, best])
	sources.sort_custom(func(a, b) -> bool: return a[0] > b[0])
	for entry in sources:
		if rivers.size() >= MAX_RIVERS:
			break
		_trace(entry[1])
	for river in rivers:
		_index_river(river)
	for lake in lakes:
		_index_lake(lake)


func _trace(source: Vector2) -> void:
	# Do not start a river right next to an existing one.
	for river in rivers:
		for p in river["points"]:
			if p.distance_to(source) < SOURCE_GRID * 0.6:
				return
	var points := PackedVector2Array([source])
	var surface: float = world._base_height(source.x, source.y) - 0.4
	var heading := Vector2.ZERO
	var ended_in_lake := false
	for n in MAX_STEPS:
		var here: Vector2 = points[points.size() - 1]
		var best := here
		var best_h := INF
		for k in 12:
			var dir := Vector2.from_angle(TAU * float(k) / 12.0)
			if heading != Vector2.ZERO and dir.dot(heading) < -0.2:
				continue # No doubling back.
			var p: Vector2 = here + dir * STEP
			var h: float = world._base_height(p.x, p.y) - dir.dot(heading) * 0.6 # Prefer to keep flowing on.
			if h < best_h:
				best_h = h
				best = p
		var ground: float = world._base_height(best.x, best.y)
		if ground < Defs.WATER_LEVEL - 0.3 or best.length() > world.EDGE_START:
			points.append(best)
			break # Reached the sea.
		if ground - surface > MAX_GORGE:
			ended_in_lake = true
			break # Trapped in a hollow: it pools.
		# Circling on flat ground, coming back to its own path: it pools into a lake there.
		var looped := false
		for i in maxi(points.size() - 3, 0):
			if points[i].distance_to(best) < STEP * 1.4:
				looped = true
				break
		if looped or n == MAX_STEPS - 1:
			ended_in_lake = true
			break
		# Crossing another river: join it.
		var joined := false
		for river in rivers:
			for p in river["points"]:
				if p.distance_to(best) < STEP:
					joined = true
					break
			if joined:
				break
		heading = (best - here).normalized()
		points.append(best)
		surface = maxf(minf(surface, ground - 0.4), Defs.WATER_LEVEL + 0.05)
		if joined:
			break
	if float(points.size()) * STEP < MIN_LENGTH:
		return
	points = _chaikin(_chaikin(points))
	var surfaces := PackedFloat32Array()
	var widths := PackedFloat32Array()
	var level: float = INF
	var length: float = 0.0
	for i in points.size():
		if i > 0:
			length += points[i].distance_to(points[i - 1])
		level = minf(level, world._base_height(points[i].x, points[i].y) - 0.45)
		level = maxf(level, Defs.WATER_LEVEL + 0.05)
		surfaces.append(level)
	var total: float = maxf(length, 1.0)
	length = 0.0
	for i in points.size():
		if i > 0:
			length += points[i].distance_to(points[i - 1])
		widths.append(lerpf(WIDTH_START, WIDTH_END, sqrt(length / total)))
	rivers.append({"points": points, "surface": surfaces, "width": widths})
	if ended_in_lake:
		var end: Vector2 = points[points.size() - 1]
		var h: int = world.mix(int(end.x), int(end.y), world.world_seed, 77)
		lakes.append({"x": end.x, "z": end.y, "radius": lerpf(LAKE_MIN_RADIUS, LAKE_MAX_RADIUS, float(h % 100) / 100.0),
			"surface": surfaces[surfaces.size() - 1]})


static func _chaikin(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var out := PackedVector2Array([points[0]])
	for i in points.size() - 1:
		out.append(points[i].lerp(points[i + 1], 0.25))
		out.append(points[i].lerp(points[i + 1], 0.75))
	out.append(points[points.size() - 1])
	return out


func _index_river(river: Dictionary) -> void:
	var points: PackedVector2Array = river["points"]
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var ab: Vector2 = b - a
		var seg := {"a": a, "b": b, "ab": ab, "inv_len2": 1.0 / maxf(ab.length_squared(), 0.0001),
			"s0": river["surface"][i], "s1": river["surface"][i + 1], "w0": river["width"][i], "w1": river["width"][i + 1]}
		var reach: float = maxf(seg["w0"], seg["w1"]) + BANK
		_add_to_cells(_segments_by_cell, seg, Vector2(minf(a.x, b.x) - reach, minf(a.y, b.y) - reach), Vector2(maxf(a.x, b.x) + reach, maxf(a.y, b.y) + reach))


func _index_lake(lake: Dictionary) -> void:
	var reach: float = float(lake["radius"]) + BANK * 1.5
	_add_to_cells(_lakes_by_cell, lake, Vector2(lake["x"] - reach, lake["z"] - reach), Vector2(lake["x"] + reach, lake["z"] + reach))


static func _add_to_cells(index: Dictionary, item: Dictionary, low: Vector2, high: Vector2) -> void:
	for cx in range(floori(low.x / CELL), floori(high.x / CELL) + 1):
		for cz in range(floori(low.y / CELL), floori(high.y / CELL) + 1):
			var key := Vector2i(cx, cz)
			if not index.has(key):
				index[key] = []
			index[key].append(item)
