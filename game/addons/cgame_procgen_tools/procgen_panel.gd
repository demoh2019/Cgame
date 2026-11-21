@tool
extends VBoxContainer
## Procedural generators panel: river network, settlements (lots + buildings), road network with
## river-crossing detection, and caves. Headless-usable: generate_all(seed, heightfield) returns plain data,
## export_scene() turns it into scene-ready nodes (id, type, Transform3D, data), and regenerate()
## re-runs the generators while keeping manual overrides keyed by stable node ids.
##
## Heightfield format: {"heights": PackedFloat32Array (y * width + x), "width": int, "height": int, "cell_size": float}.
## World position of a cell is (x, y) * cell_size on the XZ plane (Vector2 = (x, z)).
##
## Credits (algorithms re-implemented from published descriptions, no third-party code copied):
##  - Depression filling / flow directions: Barnes, Lehman, Mulla, "Priority-Flood: An Optimal
##    Depression-Filling and Watershed-Labeling Algorithm for Digital Elevation Models" (2014), paper only
##    (the RichDEM reference implementation is GPL and was NOT used).
##  - Steepest-descent (D8) river tracing: O'Callaghan & Mark (1984), published method.
##  - Settlements, roads, caves: scripts/shared/procedural_buildings.gd (Bridson Poisson disk, BSP),
##    road_network.gd (Delaunay + Kruskal), procedural_caves.gd (cellular automata), terrain_splines.gd.
## Panel code is original.

const ProceduralBuildings = preload("res://scripts/shared/procedural_buildings.gd")
const RoadNetwork = preload("res://scripts/shared/road_network.gd")
const ProceduralCaves = preload("res://scripts/shared/procedural_caves.gd")
const TerrainSplines = preload("res://scripts/shared/terrain_splines.gd")

const FLOOD_EPS := 0.001
const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]

signal generated

var site_count: int = 3
var settlement_radius: float = 24.0
var lots_per_settlement: int = 10
var river_sources: int = 4
var cave_count: int = 1
var cave_size: int = 32
var seed_value: int = 1
var heightfield: Dictionary = {}
var last_result: Dictionary = {}
var last_scene: Dictionary = {}
## id -> {"position": Vector3, "rotation_y": float, "scale": Vector3, "deleted": bool}; all keys optional.
var overrides: Dictionary = {}

var _seed_spin: SpinBox = null
var _radius_spin: SpinBox = null
var _count_spin: SpinBox = null
var _preview: TextureRect = null
var _status: Label = null


class MinHeap extends RefCounted:
	var keys: PackedFloat32Array = PackedFloat32Array()
	var vals: PackedInt32Array = PackedInt32Array()

	func is_empty() -> bool:
		return keys.is_empty()

	func push(key: float, val: int) -> void:
		keys.append(key)
		vals.append(val)
		var i: int = keys.size() - 1
		while i > 0:
			@warning_ignore("integer_division")
			var p: int = (i - 1) / 2
			if keys[p] <= keys[i]:
				break
			_swap(i, p)
			i = p

	func pop() -> int:
		var top: int = vals[0]
		var last: int = keys.size() - 1
		keys[0] = keys[last]
		vals[0] = vals[last]
		keys.resize(last)
		vals.resize(last)
		var i: int = 0
		while true:
			var l: int = i * 2 + 1
			var r: int = l + 1
			var m: int = i
			if l < keys.size() and keys[l] < keys[m]:
				m = l
			if r < keys.size() and keys[r] < keys[m]:
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return top

	func _swap(a: int, b: int) -> void:
		var tk: float = keys[a]
		keys[a] = keys[b]
		keys[b] = tk
		var tv: int = vals[a]
		vals[a] = vals[b]
		vals[b] = tv


func _init() -> void:
	name = "ProcgenPanel"
	_build_ui()


# ------------------------------------------------------------------ heightfield helpers

static func make_heightfield(heights: PackedFloat32Array, width: int, height: int, cell_size: float = 1.0) -> Dictionary:
	return {"heights": heights, "width": width, "height": height, "cell_size": cell_size}


## Smooth demo terrain (FastNoiseLite), deterministic per seed.
static func demo_heightfield(noise_seed: int, width: int, height: int, cell_size: float = 1.0, amplitude: float = 20.0) -> Dictionary:
	var n := FastNoiseLite.new()
	n.seed = noise_seed
	n.frequency = 0.02
	var hs := PackedFloat32Array()
	hs.resize(width * height)
	for y in height:
		for x in width:
			hs[y * width + x] = (n.get_noise_2d(float(x), float(y)) * 0.5 + 0.5) * amplitude
	return make_heightfield(hs, width, height, cell_size)


static func height_at(hf: Dictionary, p: Vector2) -> float:
	var hs: PackedFloat32Array = hf["heights"]
	var w: int = int(hf["width"])
	var h: int = int(hf["height"])
	var cs: float = float(hf["cell_size"])
	var fx: float = clampf(p.x / cs, 0.0, float(w - 1))
	var fy: float = clampf(p.y / cs, 0.0, float(h - 1))
	var x0: int = mini(int(fx), w - 2)
	var y0: int = mini(int(fy), h - 2)
	var tx: float = fx - float(x0)
	var ty: float = fy - float(y0)
	var a: float = lerpf(hs[y0 * w + x0], hs[y0 * w + x0 + 1], tx)
	var b: float = lerpf(hs[(y0 + 1) * w + x0], hs[(y0 + 1) * w + x0 + 1], tx)
	return lerpf(a, b, ty)


# ------------------------------------------------------------------ rivers

## Pit-filled copy of the heights (strictly descending towards the map edge, which is the outlet).
## Returns {"filled": PackedFloat32Array, "parent": PackedInt32Array (-1 for outlet cells)}.
static func fill_pits(hs: PackedFloat32Array, w: int, h: int) -> Dictionary:
	var filled: PackedFloat32Array = hs.duplicate()
	var closed := PackedByteArray()
	closed.resize(w * h)
	var parent := PackedInt32Array()
	parent.resize(w * h)
	parent.fill(-1)
	var heap := MinHeap.new()
	for y in h:
		for x in w:
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				var i: int = y * w + x
				closed[i] = 1
				heap.push(filled[i], i)
	while not heap.is_empty():
		var c: int = heap.pop()
		@warning_ignore("integer_division")
		var cy: int = c / w
		var cx: int = c - cy * w
		for o in NEIGHBOURS:
			var nx: int = cx + o.x
			var ny: int = cy + o.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var ni: int = ny * w + nx
			if closed[ni] == 1:
				continue
			closed[ni] = 1
			parent[ni] = c
			filled[ni] = maxf(hs[ni], filled[c] + FLOOD_EPS)
			heap.push(filled[ni], ni)
	return {"filled": filled, "parent": parent}


static func _descend(filled: PackedFloat32Array, parent: PackedInt32Array, w: int, h: int, c: int) -> int:
	if parent[c] < 0:
		return -1
	@warning_ignore("integer_division")
	var cy: int = c / w
	var cx: int = c - cy * w
	var best: int = parent[c]
	var best_slope: float = -INF
	for o in NEIGHBOURS:
		var nx: int = cx + o.x
		var ny: int = cy + o.y
		if nx < 0 or ny < 0 or nx >= w or ny >= h:
			continue
		var ni: int = ny * w + nx
		var drop: float = filled[c] - filled[ni]
		if drop <= 0.0:
			continue
		var slope: float = drop / (1.4142135 if o.x != 0 and o.y != 0 else 1.0)
		if slope > best_slope:
			best_slope = slope
			best = ni
	return best


## River network: sources on high ground flow by steepest descent over the pit-filled surface until
## they reach the map edge or an existing river (merge -> tree). Returns an Array of
## {"id", "cells", "points" (world XZ), "levels" (filled heights, strictly decreasing),
##  "merges_into": id or "", "merge_cell": int}.
func generate_rivers(gen_seed: int, hf: Dictionary, source_count: int) -> Array:
	var hs: PackedFloat32Array = hf["heights"]
	var w: int = int(hf["width"])
	var h: int = int(hf["height"])
	var cs: float = float(hf["cell_size"])
	var rivers: Array = []
	if w < 5 or h < 5 or source_count <= 0 or hs.size() != w * h:
		return rivers
	var fp: Dictionary = fill_pits(hs, w, h)
	var filled: PackedFloat32Array = fp["filled"]
	var parent: PackedInt32Array = fp["parent"]
	var lo: float = hs[0]
	var hi: float = hs[0]
	for v in hs:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var threshold: float = lo + (hi - lo) * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = gen_seed
	var spacing: float = maxf(3.0, float(mini(w, h)) / 8.0)
	var sources: Array[Vector2i] = []
	var tries: int = 0
	while sources.size() < source_count and tries < source_count * 80:
		tries += 1
		var sx: int = rng.randi_range(1, w - 2)
		var sy: int = rng.randi_range(1, h - 2)
		if hs[sy * w + sx] < threshold:
			continue
		var ok: bool = true
		for s in sources:
			if Vector2(s).distance_to(Vector2(sx, sy)) < spacing:
				ok = false
				break
		if ok:
			sources.append(Vector2i(sx, sy))
	sources.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ha: float = hs[a.y * w + a.x]
		var hb: float = hs[b.y * w + b.x]
		if ha != hb:
			return ha > hb
		return a.y * w + a.x < b.y * w + b.x)
	var owner_of: Dictionary = {}
	for s in sources:
		var start: int = s.y * w + s.x
		if owner_of.has(start):
			continue
		var idx: int = rivers.size()
		var cells := PackedInt32Array()
		var pts := PackedVector2Array()
		var levels := PackedFloat32Array()
		var merges: String = ""
		var merge_cell: int = -1
		var cur: int = start
		while cur >= 0:
			cells.append(cur)
			@warning_ignore("integer_division")
			var cy: int = cur / w
			pts.append(Vector2(float(cur - cy * w), float(cy)) * cs)
			levels.append(filled[cur])
			if cells.size() > 1 and owner_of.has(cur):
				var other: int = int(owner_of[cur])
				var od: Dictionary = rivers[other]
				merges = str(od["id"])
				merge_cell = cur
				break
			cur = _descend(filled, parent, w, h, cur)
		for c in cells:
			if c != merge_cell:
				owner_of[c] = idx
		rivers.append({"id": "river_%d" % idx, "cells": cells, "points": pts, "levels": levels,
			"merges_into": merges, "merge_cell": merge_cell})
	return rivers


# ------------------------------------------------------------------ sites / settlements

func generate_sites(gen_seed: int, hf: Dictionary, rivers: Array, count: int, margin: float, clearance: float) -> PackedVector2Array:
	var w: int = int(hf["width"])
	var h: int = int(hf["height"])
	var cs: float = float(hf["cell_size"])
	var rng := RandomNumberGenerator.new()
	rng.seed = gen_seed
	var sites := PackedVector2Array()
	var min_gap: float = margin * 2.0
	var tries: int = 0
	while sites.size() < count and tries < count * 200:
		tries += 1
		var lo_x: float = minf(margin, float(w - 1) * cs * 0.5)
		var lo_z: float = minf(margin, float(h - 1) * cs * 0.5)
		var p := Vector2(rng.randf_range(lo_x, float(w - 1) * cs - lo_x), rng.randf_range(lo_z, float(h - 1) * cs - lo_z))
		var ok: bool = true
		for s in sites:
			if s.distance_to(p) < min_gap:
				ok = false
				break
		if ok:
			for r in rivers:
				var rd: Dictionary = r
				var rp: PackedVector2Array = rd["points"]
				if TerrainSplines.distance_to_polyline(p, rp) < clearance:
					ok = false
					break
		if ok:
			sites.append(p)
	return sites


func generate_settlement(gen_seed: int, index: int, center: Vector2, radius: float, count: int) -> Dictionary:
	var parts: Array = ProceduralBuildings.settlement(gen_seed, center, radius, count)
	var plaza: Dictionary = {}
	var lots: Array = []
	for e in parts:
		var d: Dictionary = e
		if str(d["kind"]) == "plaza":
			plaza = d
		else:
			var fp: Vector2i = d["footprint"]
			var floors: int = int(d["floors"])
			var b: Dictionary = ProceduralBuildings.building(int(d["seed"]), fp, floors)
			var rooms: Array = b["rooms"]
			lots.append({"id": "lot_%d_%d" % [index, lots.size()], "center": d["center"], "rect": d["rect"],
				"footprint": fp, "floors": floors, "seed": d["seed"], "rooms": rooms.size()})
	return {"id": "settlement_%d" % index, "center": center, "radius": radius, "plaza": plaza, "lots": lots}


# ------------------------------------------------------------------ roads

func generate_roads(gen_seed: int, hf: Dictionary, sites: PackedVector2Array, rivers: Array) -> Dictionary:
	var roads: Array = []
	var edges: Array = RoadNetwork.connect_sites(sites, 0.15, gen_seed)
	var height_fn: Callable = func(p: Vector2) -> float: return height_at(hf, p)
	for e in edges:
		var ed: Dictionary = e
		var a: int = int(ed["a"])
		var b: int = int(ed["b"])
		var pa: Vector2 = sites[a]
		var pb: Vector2 = sites[b]
		var steps: int = maxi(1, int(ceil(pa.distance_to(pb) / 8.0)))
		var pts := PackedVector2Array()
		for i in steps + 1:
			pts.append(pa.lerp(pb, float(i) / float(steps)))
		roads.append({"id": "road_%d_%d" % [a, b], "a": a, "b": b, "length": float(ed["length"]),
			"cost": RoadNetwork.route_cost(pa, pb, height_fn, 2.0), "points": pts})
	return {"roads": roads, "crossings": find_crossings(roads, rivers)}


## Road/river intersections: [{"id", "road", "river", "point": Vector2}], deduplicated per pair.
static func find_crossings(roads: Array, rivers: Array) -> Array:
	var out: Array = []
	for r in roads:
		var rd: Dictionary = r
		var rp: PackedVector2Array = rd["points"]
		for v in rivers:
			var vd: Dictionary = v
			var vp: PackedVector2Array = vd["points"]
			var found: Array[Vector2] = []
			for i in rp.size() - 1:
				for j in vp.size() - 1:
					var hit: Variant = Geometry2D.segment_intersects_segment(rp[i], rp[i + 1], vp[j], vp[j + 1])
					if hit == null:
						continue
					var hp: Vector2 = hit
					var dup: bool = false
					for f in found:
						if f.distance_to(hp) < 0.5:
							dup = true
							break
					if not dup:
						found.append(hp)
			for k in found.size():
				out.append({"id": "bridge_%s_%s_%d" % [str(rd["id"]), str(vd["id"]), k],
					"road": rd["id"], "river": vd["id"], "point": found[k]})
	return out


# ------------------------------------------------------------------ caves

func generate_caves(gen_seed: int, hf: Dictionary, count: int, size: int) -> Array:
	var caves: Array = []
	var w: int = int(hf["width"])
	var h: int = int(hf["height"])
	var cs: float = float(hf["cell_size"])
	var rng := RandomNumberGenerator.new()
	rng.seed = gen_seed
	for i in count:
		var best := Vector2.ZERO
		var best_slope: float = -1.0
		for _k in 8:
			var p := Vector2(rng.randf_range(1.0, float(w - 2)), rng.randf_range(1.0, float(h - 2))) * cs
			var s: float = absf(height_at(hf, p + Vector2(cs, 0.0)) - height_at(hf, p - Vector2(cs, 0.0))) \
				+ absf(height_at(hf, p + Vector2(0.0, cs)) - height_at(hf, p - Vector2(0.0, cs)))
			if s > best_slope:
				best_slope = s
				best = p
		var grid: PackedByteArray = ProceduralCaves.generate(size, size, gen_seed * 31 + i)
		var open_cells: int = 0
		for c in grid:
			if c == 0:
				open_cells += 1
		var chambers: Array = ProceduralCaves.chambers(grid, size, size, 8)
		var regions: Array = ProceduralCaves.regions(grid, size, size)
		caves.append({"id": "cave_%d" % i, "position": best, "size": size, "open_cells": open_cells,
			"chambers": chambers, "regions": regions.size(), "grid": grid})
	return caves


# ------------------------------------------------------------------ orchestration

## Runs every generator. Deterministic for a given (seed, heightfield, panel parameters).
func generate_all(gen_seed: int, hf: Dictionary) -> Dictionary:
	var cs: float = float(hf["cell_size"])
	var rivers: Array = generate_rivers(gen_seed, hf, river_sources)
	var margin: float = settlement_radius + 2.0 * cs
	var sites: PackedVector2Array = generate_sites(gen_seed + 101, hf, rivers, site_count, margin, 4.0 * cs)
	var settlements: Array = []
	for i in sites.size():
		settlements.append(generate_settlement(gen_seed * 7919 + i, i, sites[i], settlement_radius, lots_per_settlement))
	var road_data: Dictionary = generate_roads(gen_seed + 202, hf, sites, rivers)
	var caves: Array = generate_caves(gen_seed + 303, hf, cave_count, cave_size)
	last_result = {"seed": gen_seed, "rivers": rivers, "sites": sites, "settlements": settlements,
		"roads": road_data["roads"], "crossings": road_data["crossings"], "caves": caves}
	heightfield = hf
	_refresh_preview()
	generated.emit()
	return last_result


# ------------------------------------------------------------------ export / overrides

func set_override(id: String, data: Dictionary) -> void:
	var cur: Dictionary = overrides.get(id, {})
	cur.merge(data, true)
	overrides[id] = cur


func clear_override(id: String) -> void:
	overrides.erase(id)


func _node(id: String, type: String, origin: Vector3, data: Dictionary, parent: String = "") -> Dictionary:
	return {"id": id, "type": type, "parent": parent, "transform": Transform3D(Basis.IDENTITY, origin), "data": data}


func _local_points(world: PackedVector2Array, hf: Dictionary, origin: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in world:
		out.append(Vector3(p.x, height_at(hf, p), p.y) - origin)
	return out


## Scene-ready description of `result`: {"seed", "nodes": [{"id","type","parent","transform": Transform3D,"data"}],
## "overridden": [ids]}. Transforms are global. Overrides (by id) replace position/rotation/scale or drop the node.
func export_scene(result: Dictionary, hf: Dictionary) -> Dictionary:
	var nodes: Array = []
	var rivers: Array = result["rivers"]
	for r in rivers:
		var rd: Dictionary = r
		var rp: PackedVector2Array = rd["points"]
		var o := Vector3(rp[0].x, height_at(hf, rp[0]), rp[0].y)
		nodes.append(_node(str(rd["id"]), "river", o, {"points": _local_points(rp, hf, o),
			"merges_into": rd["merges_into"]}))
	var settlements: Array = result["settlements"]
	for s in settlements:
		var sd: Dictionary = s
		var c: Vector2 = sd["center"]
		var sid: String = str(sd["id"])
		nodes.append(_node(sid, "settlement", Vector3(c.x, height_at(hf, c), c.y), {"radius": sd["radius"]}))
		var lots: Array = sd["lots"]
		for l in lots:
			var ld: Dictionary = l
			var lc: Vector2 = ld["center"]
			nodes.append(_node(str(ld["id"]), "building", Vector3(lc.x, height_at(hf, lc), lc.y),
				{"footprint": ld["footprint"], "floors": ld["floors"], "seed": ld["seed"], "rooms": ld["rooms"]}, sid))
	var roads: Array = result["roads"]
	for r in roads:
		var rd: Dictionary = r
		var rp: PackedVector2Array = rd["points"]
		var o := Vector3(rp[0].x, height_at(hf, rp[0]), rp[0].y)
		nodes.append(_node(str(rd["id"]), "road", o, {"points": _local_points(rp, hf, o), "length": rd["length"],
			"cost": rd["cost"], "from": rd["a"], "to": rd["b"]}))
	var crossings: Array = result["crossings"]
	for x in crossings:
		var xd: Dictionary = x
		var xp: Vector2 = xd["point"]
		nodes.append(_node(str(xd["id"]), "bridge", Vector3(xp.x, height_at(hf, xp), xp.y),
			{"road": xd["road"], "river": xd["river"]}))
	var caves: Array = result["caves"]
	for cv in caves:
		var cd: Dictionary = cv
		var cp: Vector2 = cd["position"]
		nodes.append(_node(str(cd["id"]), "cave", Vector3(cp.x, height_at(hf, cp), cp.y),
			{"size": cd["size"], "open_cells": cd["open_cells"], "chambers": cd["chambers"], "regions": cd["regions"]}))
	var applied: Array = []
	var kept: Array = []
	for n in nodes:
		var nd: Dictionary = n
		var nid: String = str(nd["id"])
		if not overrides.has(nid):
			kept.append(nd)
			continue
		var ov: Dictionary = overrides[nid]
		applied.append(nid)
		if bool(ov.get("deleted", false)):
			continue
		var tr: Transform3D = nd["transform"]
		var origin: Vector3 = ov.get("position", tr.origin)
		var basis: Basis = tr.basis
		if ov.has("rotation_y"):
			basis = Basis(Vector3.UP, float(ov["rotation_y"]))
		if ov.has("scale"):
			basis = basis.scaled(ov["scale"])
		nd["transform"] = Transform3D(basis, origin)
		kept.append(nd)
	return {"seed": result["seed"], "nodes": kept, "overridden": applied}


## Regenerates with a (possibly new) seed/heightfield and re-applies the manual overrides.
func regenerate(gen_seed: int, hf: Dictionary) -> Dictionary:
	var res: Dictionary = generate_all(gen_seed, hf)
	last_scene = export_scene(res, hf)
	return last_scene


# ------------------------------------------------------------------ preview

func preview_image(result: Dictionary, hf: Dictionary) -> Image:
	var w: int = int(hf["width"])
	var h: int = int(hf["height"])
	var cs: float = float(hf["cell_size"])
	var hs: PackedFloat32Array = hf["heights"]
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGB8)
	var lo: float = hs[0]
	var hi: float = hs[0]
	for v in hs:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var span: float = maxf(hi - lo, 0.0001)
	for y in h:
		for x in w:
			var t: float = 0.25 + 0.5 * (hs[y * w + x] - lo) / span
			img.set_pixel(x, y, Color(t, t, t))
	var rivers: Array = result["rivers"]
	for r in rivers:
		var rd: Dictionary = r
		var rp: PackedVector2Array = rd["points"]
		for p in rp:
			_plot(img, p / cs, Color(0.2, 0.4, 1.0))
	var roads: Array = result["roads"]
	for r in roads:
		var rd: Dictionary = r
		var rp: PackedVector2Array = rd["points"]
		for p in rp:
			_plot(img, p / cs, Color(0.7, 0.5, 0.2))
	var settlements: Array = result["settlements"]
	for s in settlements:
		var sd: Dictionary = s
		var lots: Array = sd["lots"]
		for l in lots:
			var ld: Dictionary = l
			var rc: Rect2 = ld["rect"]
			var x0: int = int(rc.position.x / cs)
			var y0: int = int(rc.position.y / cs)
			for yy in range(y0, int(rc.end.y / cs) + 1):
				for xx in range(x0, int(rc.end.x / cs) + 1):
					_plot(img, Vector2(xx, yy), Color(0.9, 0.2, 0.2))
	var crossings: Array = result["crossings"]
	for x in crossings:
		var xd: Dictionary = x
		var xp: Vector2 = xd["point"]
		_plot(img, xp / cs, Color(1.0, 1.0, 0.2))
	var caves: Array = result["caves"]
	for c in caves:
		var cd: Dictionary = c
		var cp: Vector2 = cd["position"]
		_plot(img, cp / cs, Color(0.8, 0.2, 0.9))
	return img


static func _plot(img: Image, cell: Vector2, color: Color) -> void:
	var x: int = roundi(cell.x)
	var y: int = roundi(cell.y)
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, color)


# ------------------------------------------------------------------ UI

func _build_ui() -> void:
	_seed_spin = _spin("Seed", 0.0, 99999.0, float(seed_value), func(v: float) -> void: seed_value = int(v))
	_radius_spin = _spin("Radius", 8.0, 200.0, settlement_radius, func(v: float) -> void: settlement_radius = v)
	_count_spin = _spin("Lots", 1.0, 100.0, float(lots_per_settlement), func(v: float) -> void: lots_per_settlement = int(v))
	var row := HBoxContainer.new()
	add_child(row)
	row.add_child(_button("Generate", func() -> void:
		if heightfield.is_empty():
			heightfield = demo_heightfield(seed_value, 96, 96)
		regenerate(seed_value, heightfield)))
	row.add_child(_button("Export", func() -> void:
		if not last_result.is_empty():
			last_scene = export_scene(last_result, heightfield)
			_status.text = "%d nodes" % (last_scene["nodes"] as Array).size()))
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(160, 160)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_preview)
	_status = Label.new()
	add_child(_status)


func _spin(label: String, lo: float, hi: float, value: float, cb: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = label
	row.add_child(lab)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	s.value_changed.connect(cb)
	row.add_child(s)
	add_child(row)
	return s


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _refresh_preview() -> void:
	if _preview == null or last_result.is_empty():
		return
	_preview.texture = ImageTexture.create_from_image(preview_image(last_result, heightfield))
	var rivers: Array = last_result["rivers"]
	_status.text = "%d rivers, %d settlements" % [rivers.size(), (last_result["settlements"] as Array).size()]
