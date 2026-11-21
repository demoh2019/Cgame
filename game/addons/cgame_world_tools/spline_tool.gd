@tool
extends RefCounted
## Spline-based world authoring: roads, rivers and bridges.
##
## Original GDScript implementation. Concepts follow the publicly documented
## workflow of Unreal Engine Landscape Splines and Terrain3D/World Machine road
## tools (control points with per-point width, terrain deformation along the
## spline, auto bridge spans); no third-party source code was copied.
##
## Deformation is written into a dedicated TerrainEditLayers layer (ADD blend) as a
## delta over the terrain *without* that layer, so the base heightfield is never
## touched and hiding / removing the layer restores the original terrain.
##   road  -> "flatten" (terrain blends toward the spline height, embankment falloff)
##   river -> "carve"   (channel below the spline with smooth banks)
##   any   -> mode "raise" gives an embankment that only ever lifts terrain
##   bridge -> no terrain deformation; see bridge_segments()/build_bridge_mesh()

const TerrainSplines = preload("res://scripts/shared/terrain_splines.gd")
const TerrainEditLayers = preload("res://scripts/shared/terrain_edit_layers.gd")

signal changed

const KINDS: PackedStringArray = ["road", "river", "bridge"]
const DEFAULT_WIDTH: float = 4.0
const SAMPLES: int = 8
const MAX_UNDO: int = 200

## Spline: {id, kind, points: PackedVector3Array, widths: PackedFloat32Array, mode,
## depth, falloff, material}. Edit through the methods below so undo/redo stays valid.
var splines: Array[Dictionary] = []

var _next_id: int = 1
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []


# ---------------------------------------------------------------- editing

func add_spline(kind: String, points: PackedVector3Array = PackedVector3Array(), width: float = DEFAULT_WIDTH) -> int:
	if not KINDS.has(kind):
		return -1
	_push()
	var mode: String = "flatten"
	var material: int = 1
	if kind == "river":
		mode = "carve"
		material = 2
	elif kind == "bridge":
		mode = "none"
		material = -1
	var widths := PackedFloat32Array()
	for i in points.size():
		widths.append(width)
	var s: Dictionary = {
		"id": _next_id, "kind": kind, "points": points.duplicate(), "widths": widths,
		"mode": mode, "depth": 1.0, "falloff": 4.0, "material": material,
	}
	_next_id += 1
	splines.append(s)
	changed.emit()
	return int(s["id"])


func remove_spline(id: int) -> bool:
	var i: int = _find(id)
	if i < 0:
		return false
	_push()
	splines.remove_at(i)
	changed.emit()
	return true


func spline_ids() -> PackedInt32Array:
	var out := PackedInt32Array()
	for s in splines:
		out.append(int(s["id"]))
	return out


func get_spline(id: int) -> Dictionary:
	var i: int = _find(id)
	return splines[i] if i >= 0 else {}


func point_count(id: int) -> int:
	var i: int = _find(id)
	if i < 0:
		return 0
	var p: PackedVector3Array = splines[i]["points"]
	return p.size()


func get_point(id: int, index: int) -> Vector3:
	var i: int = _find(id)
	if i < 0:
		return Vector3.ZERO
	var p: PackedVector3Array = splines[i]["points"]
	return p[index] if index >= 0 and index < p.size() else Vector3.ZERO


func get_point_width(id: int, index: int) -> float:
	var i: int = _find(id)
	if i < 0:
		return 0.0
	var w: PackedFloat32Array = splines[i]["widths"]
	return w[index] if index >= 0 and index < w.size() else 0.0


func add_point(id: int, pos: Vector3, width: float = -1.0) -> int:
	var i: int = _find(id)
	if i < 0:
		return -1
	return insert_point(id, point_count(id), pos, width)


## Inserts before `index` (index == count appends). Width < 0 inherits the neighbour's.
func insert_point(id: int, index: int, pos: Vector3, width: float = -1.0) -> int:
	var i: int = _find(id)
	if i < 0:
		return -1
	var p: PackedVector3Array = splines[i]["points"]
	var w: PackedFloat32Array = splines[i]["widths"]
	var at: int = clampi(index, 0, p.size())
	var use_w: float = width
	if use_w < 0.0:
		if w.is_empty():
			use_w = DEFAULT_WIDTH
		else:
			use_w = w[clampi(at - 1, 0, w.size() - 1)]
	_push()
	p.insert(at, pos)
	w.insert(at, use_w)
	splines[i]["points"] = p
	splines[i]["widths"] = w
	changed.emit()
	return at


func move_point(id: int, index: int, pos: Vector3) -> bool:
	var i: int = _find(id)
	if i < 0:
		return false
	var p: PackedVector3Array = splines[i]["points"]
	if index < 0 or index >= p.size():
		return false
	_push()
	p[index] = pos
	splines[i]["points"] = p
	changed.emit()
	return true


func delete_point(id: int, index: int) -> bool:
	var i: int = _find(id)
	if i < 0:
		return false
	var p: PackedVector3Array = splines[i]["points"]
	var w: PackedFloat32Array = splines[i]["widths"]
	if index < 0 or index >= p.size():
		return false
	_push()
	p.remove_at(index)
	w.remove_at(index)
	splines[i]["points"] = p
	splines[i]["widths"] = w
	changed.emit()
	return true


func set_point_width(id: int, index: int, width: float) -> bool:
	var i: int = _find(id)
	if i < 0:
		return false
	var w: PackedFloat32Array = splines[i]["widths"]
	if index < 0 or index >= w.size():
		return false
	_push()
	w[index] = maxf(width, 0.0)
	splines[i]["widths"] = w
	changed.emit()
	return true


## mode: "flatten", "carve", "raise" or "none".
func set_spline_params(id: int, params: Dictionary) -> bool:
	var i: int = _find(id)
	if i < 0:
		return false
	_push()
	for k: String in ["mode", "depth", "falloff", "material"]:
		if params.has(k):
			splines[i][k] = params[k]
	changed.emit()
	return true


## Sets every control point's height from the terrain (composite heights excluding
## `exclude_layer`) plus `offset`.
func snap_to_terrain(id: int, terrain: TerrainEditLayers, cell_size: float = 1.0, exclude_layer: int = -1, offset: float = 0.0) -> bool:
	var i: int = _find(id)
	if i < 0:
		return false
	var full := Rect2i(0, 0, terrain.width, terrain.height)
	var hs: PackedFloat32Array = _heights_without(terrain, exclude_layer, full)
	_push()
	var p: PackedVector3Array = splines[i]["points"]
	for k in p.size():
		var v: Vector3 = p[k]
		p[k] = Vector3(v.x, TerrainSplines._sample_height(hs, terrain.width, terrain.height, cell_size, v.x, v.z) + offset, v.z)
	splines[i]["points"] = p
	changed.emit()
	return true


# ---------------------------------------------------------------- sampling

## Catmull-Rom samples of a spline (via TerrainSplines.catmull_rom).
func sample_spline(id: int, samples_per_segment: int = SAMPLES) -> PackedVector3Array:
	var i: int = _find(id)
	if i < 0:
		return PackedVector3Array()
	var sw: Dictionary = _sample_both(splines[i], samples_per_segment)
	return sw["points"]


func _sample_both(s: Dictionary, sps: int) -> Dictionary:
	var pts: PackedVector3Array = s["points"]
	var ws: PackedFloat32Array = s["widths"]
	var wv := PackedVector3Array()
	for w in ws:
		wv.append(Vector3(w, 0.0, 0.0))
	var sp: PackedVector3Array = TerrainSplines.catmull_rom(pts, sps)
	var sw: PackedVector3Array = TerrainSplines.catmull_rom(wv, sps)
	var widths := PackedFloat32Array()
	for v in sw:
		widths.append(maxf(v.x, 0.0))
	return {"points": sp, "widths": widths}


# ---------------------------------------------------------------- terrain application

## Composite heights of `rect` with `layer_id` hidden (what the spline deforms).
func _heights_without(terrain: TerrainEditLayers, layer_id: int, rect: Rect2i) -> PackedFloat32Array:
	var l: TerrainEditLayers.EditLayer = _layer_of(terrain, layer_id)
	if l == null:
		return terrain.composite_region(rect)
	var was: bool = l.visible
	if was:
		terrain.set_layer_visible(layer_id, false)
	var hs: PackedFloat32Array = terrain.composite_region(rect)
	if was:
		terrain.set_layer_visible(layer_id, true)
	return hs


func terrain_heights_without(terrain: TerrainEditLayers, layer_id: int = -1) -> PackedFloat32Array:
	return _heights_without(terrain, layer_id, Rect2i(0, 0, terrain.width, terrain.height))


func _layer_of(terrain: TerrainEditLayers, layer_id: int) -> TerrainEditLayers.EditLayer:
	for l in terrain._layers:
		if l.id == layer_id:
			return l
	return null


func _texel_rect(s: Dictionary, cell: float, terrain: TerrainEditLayers) -> Rect2i:
	var sw: Dictionary = _sample_both(s, SAMPLES)
	var pts: PackedVector3Array = sw["points"]
	var ws: PackedFloat32Array = sw["widths"]
	if pts.size() < 2:
		return Rect2i()
	var falloff: float = float(s["falloff"])
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for k in pts.size():
		var reach: float = ws[k] * 0.5 + falloff
		lo.x = minf(lo.x, pts[k].x - reach)
		lo.y = minf(lo.y, pts[k].z - reach)
		hi.x = maxf(hi.x, pts[k].x + reach)
		hi.y = maxf(hi.y, pts[k].z + reach)
	var x0: int = floori(lo.x / cell)
	var y0: int = floori(lo.y / cell)
	var x1: int = ceili(hi.x / cell) + 1
	var y1: int = ceili(hi.y / cell) + 1
	return Rect2i(x0, y0, x1 - x0, y1 - y0).intersection(Rect2i(0, 0, terrain.width, terrain.height))


## Writes the deformation of every road/river/embankment spline into `layer_id`
## (an ADD-blend edit layer; forced to ADD) and paints each spline's splat material
## along it. Re-applying replaces the layer's previous content. One undo step.
func apply(terrain: TerrainEditLayers, layer_id: int, cell_size: float = 1.0, paint_splat: bool = true) -> bool:
	var l: TerrainEditLayers.EditLayer = _layer_of(terrain, layer_id)
	if l == null or cell_size <= 0.0:
		return false
	terrain.set_layer_blend(layer_id, TerrainEditLayers.Blend.ADD)
	var rect := Rect2i()
	var has_rect: bool = false
	if l.has_bounds:
		rect = l.bounds
		has_rect = true
	for s in splines:
		if str(s["mode"]) == "none":
			continue
		var r: Rect2i = _texel_rect(s, cell_size, terrain)
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		rect = rect.merge(r) if has_rect else r
		has_rect = true
	if not has_rect:
		return false
	rect = rect.intersection(Rect2i(0, 0, terrain.width, terrain.height))
	if rect.size.x <= 0 or rect.size.y <= 0:
		return false
	var before: PackedFloat32Array = _heights_without(terrain, layer_id, rect)
	var work: PackedFloat32Array = before.duplicate()
	for s in splines:
		if str(s["mode"]) != "none":
			_deform_into(work, rect, cell_size, s)
	var depth_before: int = terrain.undo_depth()
	terrain.fill_layer_rect(layer_id, rect, 0.0, 0.0)
	var k: int = 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var d: float = work[k] - before[k]
			var i: int = y * terrain.width + x
			l.delta[i] = d
			l.alpha[i] = 1.0 if absf(d) > 0.00001 else 0.0
			k += 1
	if paint_splat and terrain.splat_count() > 0:
		for s in splines:
			_paint_material(terrain, s, cell_size)
	var entry: Dictionary = {"snap": _snapshot(), "terrain": terrain, "count": terrain.undo_depth() - depth_before}
	_push_entry(entry)
	changed.emit()
	return true


func _paint_material(terrain: TerrainEditLayers, s: Dictionary, cell: float) -> void:
	var mat: int = int(s["material"])
	if mat < 0 or mat >= terrain.splat_count():
		return
	var sw: Dictionary = _sample_both(s, SAMPLES)
	var pts: PackedVector3Array = sw["points"]
	var ws: PackedFloat32Array = sw["widths"]
	var last := Vector2(INF, INF)
	for k in pts.size():
		var c := Vector2(pts[k].x / cell, pts[k].z / cell)
		var radius: float = maxf(ws[k] * 0.5 / cell, 1.0)
		if last.distance_to(c) < radius * 0.5:
			continue
		last = c
		terrain.paint_splat(mat, c, radius, 1.0)


func _deform_into(work: PackedFloat32Array, rect: Rect2i, cell: float, s: Dictionary) -> void:
	var sw: Dictionary = _sample_both(s, SAMPLES)
	var pts: PackedVector3Array = sw["points"]
	var ws: PackedFloat32Array = sw["widths"]
	if pts.size() < 2:
		return
	var falloff: float = maxf(float(s["falloff"]), 0.0001)
	var depth: float = float(s["depth"])
	var mode: String = str(s["mode"])
	var n: int = rect.size.x * rect.size.y
	var best_d := PackedFloat32Array()
	var best_h := PackedFloat32Array()
	var best_hw := PackedFloat32Array()
	best_d.resize(n)
	best_h.resize(n)
	best_hw.resize(n)
	best_d.fill(INF)
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var ahw: float = ws[i] * 0.5
		var bhw: float = ws[i + 1] * 0.5
		var reach_max: float = maxf(ahw, bhw) + falloff
		var x0: int = maxi(floori((minf(a.x, b.x) - reach_max) / cell), rect.position.x)
		var x1: int = mini(ceili((maxf(a.x, b.x) + reach_max) / cell), rect.end.x - 1)
		var y0: int = maxi(floori((minf(a.z, b.z) - reach_max) / cell), rect.position.y)
		var y1: int = mini(ceili((maxf(a.z, b.z) + reach_max) / cell), rect.end.y - 1)
		var a2 := Vector2(a.x, a.z)
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var len2: float = ab.length_squared()
		for ty in range(y0, y1 + 1):
			for tx in range(x0, x1 + 1):
				var p := Vector2(float(tx) * cell, float(ty) * cell)
				var t: float = 0.0 if len2 <= 0.0 else clampf((p - a2).dot(ab) / len2, 0.0, 1.0)
				var d: float = p.distance_to(a2 + ab * t)
				var idx: int = (ty - rect.position.y) * rect.size.x + (tx - rect.position.x)
				if d < best_d[idx]:
					best_d[idx] = d
					best_h[idx] = lerpf(a.y, b.y, t)
					best_hw[idx] = lerpf(ahw, bhw, t)
	for idx in n:
		var d: float = best_d[idx]
		var hw: float = best_hw[idx]
		var reach: float = hw + falloff
		if d > reach:
			continue
		var w: float = 1.0
		if d > hw:
			w = 1.0 - smoothstep(0.0, 1.0, (d - hw) / falloff)
		var h: float = work[idx]
		var sh: float = best_h[idx]
		match mode:
			"flatten":
				work[idx] = lerpf(h, sh, w)
			"carve":
				var profile: float = 1.0 - smoothstep(0.0, reach, d)
				work[idx] = lerpf(h, minf(h, sh - depth * profile), w)
			"raise":
				work[idx] = lerpf(h, maxf(h, sh), w)


# ---------------------------------------------------------------- bridges

## Spans where a road/bridge spline floats more than `clearance` above the terrain
## (TerrainSplines.bridge_spans on the spline samples). Each span:
## {spline_id, start, end, points (the sample slice), length, width}.
## Pass heights from terrain_heights_without(terrain, road_layer) to detect against the
## original ground rather than the flattened road bed.
func bridge_segments(heights: PackedFloat32Array, width: int, height: int, cell_size: float, clearance: float = 2.0, samples_per_segment: int = SAMPLES) -> Array:
	var out: Array = []
	for s in splines:
		var kind: String = str(s["kind"])
		if kind != "road" and kind != "bridge":
			continue
		var sw: Dictionary = _sample_both(s, samples_per_segment)
		var pts: PackedVector3Array = sw["points"]
		var ws: PackedFloat32Array = sw["widths"]
		if pts.size() < 2:
			continue
		var spans: Array = TerrainSplines.bridge_spans(heights, width, height, cell_size, pts, clearance)
		for sp: Dictionary in spans:
			var a: int = int(sp["start"])
			var b: int = int(sp["end"])
			var slice: PackedVector3Array = pts.slice(a, b + 1)
			var len: float = 0.0
			var wsum: float = 0.0
			for k in slice.size():
				if k > 0:
					len += slice[k].distance_to(slice[k - 1])
				wsum += ws[a + k]
			out.append({
				"spline_id": int(s["id"]), "start": a, "end": b, "points": slice,
				"length": len, "width": wsum / float(maxi(slice.size(), 1)),
			})
	return out


## Deck (top, underside, edges) plus box support columns every `support_spacing`
## metres down to the ground (`height_at(x, z) -> float`, default 0).
func build_bridge_mesh(span: Dictionary, deck_width: float = -1.0, thickness: float = 0.5, support_spacing: float = 8.0, height_at: Callable = Callable(), uv_scale: float = 1.0) -> ArrayMesh:
	var pts: PackedVector3Array = span.get("points", PackedVector3Array())
	var mesh := ArrayMesh.new()
	if pts.size() < 2:
		return mesh
	var hw: float = (deck_width if deck_width > 0.0 else float(span.get("width", DEFAULT_WIDTH))) * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := PackedVector3Array()
	var dist: float = 0.0
	var dists := PackedFloat32Array()
	for k in pts.size():
		if k > 0:
			dist += pts[k].distance_to(pts[k - 1])
		dists.append(dist)
		sides.append(_side_at(pts, k))
	var down := Vector3(0.0, -thickness, 0.0)
	for k in pts.size() - 1:
		var l0: Vector3 = pts[k] - sides[k] * hw
		var r0: Vector3 = pts[k] + sides[k] * hw
		var l1: Vector3 = pts[k + 1] - sides[k + 1] * hw
		var r1: Vector3 = pts[k + 1] + sides[k + 1] * hw
		var v0: float = dists[k] * uv_scale
		var v1: float = dists[k + 1] * uv_scale
		var uvs := PackedVector2Array([Vector2(0, v0), Vector2(0, v1), Vector2(1, v1), Vector2(1, v0)])
		_quad(st, PackedVector3Array([l0, l1, r1, r0]), uvs, Vector3.UP)
		_quad(st, PackedVector3Array([l0 + down, l1 + down, r1 + down, r0 + down]), uvs, Vector3.DOWN)
		_quad(st, PackedVector3Array([l0, l1, l1 + down, l0 + down]), uvs, -sides[k])
		_quad(st, PackedVector3Array([r0, r1, r1 + down, r0 + down]), uvs, sides[k])
	# Supports: one at each end of the span and then roughly every support_spacing metres.
	var next_at: float = 0.0
	var total: float = dist
	for k in pts.size():
		var is_end: bool = k == 0 or k == pts.size() - 1
		if not is_end and dists[k] < next_at:
			continue
		next_at = dists[k] + maxf(support_spacing, 0.5)
		if not is_end and total - dists[k] < support_spacing * 0.4:
			continue
		var top: Vector3 = pts[k] + down
		var gy: float = float(height_at.call(top.x, top.z)) if height_at.is_valid() else 0.0
		if gy >= top.y - 0.05:
			continue
		_column(st, top, gy, sides[k], minf(hw * 0.5, 0.6))
	st.generate_normals()
	return st.commit()


func _column(st: SurfaceTool, top: Vector3, ground_y: float, side: Vector3, half: float) -> void:
	var fwd: Vector3 = side.cross(Vector3.UP).normalized()
	var corners: Array[Vector3] = [
		(side + fwd) * half, (side - fwd) * half, (-side - fwd) * half, (-side + fwd) * half,
	]
	for c in 4:
		var c0: Vector3 = corners[c]
		var c1: Vector3 = corners[(c + 1) % 4]
		var t0 := Vector3(top.x, top.y, top.z) + c0
		var t1 := Vector3(top.x, top.y, top.z) + c1
		var b0 := Vector3(top.x, ground_y, top.z) + c0
		var b1 := Vector3(top.x, ground_y, top.z) + c1
		var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		_quad(st, PackedVector3Array([t0, t1, b1, b0]), uvs, (c0 + c1))


## Emits two triangles for quad (a,b,c,d), winding them so the front faces `outward`.
func _quad(st: SurfaceTool, v: PackedVector3Array, uv: PackedVector2Array, outward: Vector3) -> void:
	var n: Vector3 = (v[2] - v[0]).cross(v[1] - v[0])
	var order: Array[int] = [0, 1, 2, 0, 2, 3]
	if n.dot(outward) < 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for k in order:
		st.set_uv(uv[k])
		st.add_vertex(v[k])


func _side_at(pts: PackedVector3Array, k: int) -> Vector3:
	var a: Vector3 = pts[maxi(k - 1, 0)]
	var b: Vector3 = pts[mini(k + 1, pts.size() - 1)]
	var t := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if t.length_squared() < 0.000001:
		return Vector3(0, 0, 1)
	t = t.normalized()
	return Vector3(-t.z, 0.0, t.x)


# ---------------------------------------------------------------- meshes

## Ribbon along a spline (default: first road) with two vertices per spline sample.
## `width` <= 0 uses the per-point widths. `height_at(x, z) -> float` drapes the
## ribbon over the terrain (plus `lift`); without it the spline heights are used.
func build_road_mesh(width: float = -1.0, uv_scale: float = 1.0, spline_id: int = -1, height_at: Callable = Callable(), samples_per_segment: int = SAMPLES, lift: float = 0.05) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var i: int = _find(spline_id)
	if i < 0:
		for k in splines.size():
			if str(splines[k]["kind"]) == "road":
				i = k
				break
	if i < 0:
		return mesh
	var sw: Dictionary = _sample_both(splines[i], samples_per_segment)
	var pts: PackedVector3Array = sw["points"]
	var ws: PackedFloat32Array = sw["widths"]
	if pts.size() < 2:
		return mesh
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var dist: float = 0.0
	for k in pts.size():
		if k > 0:
			dist += pts[k].distance_to(pts[k - 1])
		var hw: float = (width if width > 0.0 else ws[k]) * 0.5
		var side: Vector3 = _side_at(pts, k)
		var c: Vector3 = pts[k]
		var l: Vector3 = c - side * hw
		var r: Vector3 = c + side * hw
		if height_at.is_valid():
			l.y = float(height_at.call(l.x, l.z)) + lift
			r.y = float(height_at.call(r.x, r.z)) + lift
		else:
			l.y += lift
			r.y += lift
		verts.append(l)
		verts.append(r)
		var tan3: Vector3 = (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
		var nrm: Vector3 = side.cross(tan3).normalized()
		norms.append(nrm)
		norms.append(nrm)
		uvs.append(Vector2(0.0, dist * uv_scale))
		uvs.append(Vector2(1.0, dist * uv_scale))
	for k in pts.size() - 1:
		var l0: int = k * 2
		idx.append_array(PackedInt32Array([l0, l0 + 2, l0 + 3, l0, l0 + 3, l0 + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ---------------------------------------------------------------- river flow

## Flow direction map for a water shader: RGBA8 image covering `world_rect` (XZ).
## R,G = flow direction along the spline (x, z) * 0.5 + 0.5; B = speed (1 at the
## centre, 0 at the bank); A = 1 inside the river channel, 0 outside.
## spline_id -1 merges every river (nearest one wins).
func river_flow_map(spline_id: int, world_rect: Rect2, resolution: Vector2i, samples_per_segment: int = SAMPLES) -> Image:
	var img := Image.create(maxi(resolution.x, 1), maxi(resolution.y, 1), false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.0, 0.0))
	var chains: Array[Dictionary] = []
	for s in splines:
		if str(s["kind"]) != "river":
			continue
		if spline_id >= 0 and int(s["id"]) != spline_id:
			continue
		chains.append(_sample_both(s, samples_per_segment))
	if chains.is_empty():
		return img
	for py in img.get_height():
		for px in img.get_width():
			var p := Vector2(
				world_rect.position.x + (float(px) + 0.5) / float(img.get_width()) * world_rect.size.x,
				world_rect.position.y + (float(py) + 0.5) / float(img.get_height()) * world_rect.size.y)
			var best: Dictionary = {"d": INF}
			for ch in chains:
				var pts: PackedVector3Array = ch["points"]
				var ws: PackedFloat32Array = ch["widths"]
				for k in pts.size() - 1:
					var a := Vector2(pts[k].x, pts[k].z)
					var ab := Vector2(pts[k + 1].x, pts[k + 1].z) - a
					var len2: float = ab.length_squared()
					if len2 <= 0.0:
						continue
					var t: float = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
					var d: float = p.distance_to(a + ab * t)
					if d < float(best["d"]):
						best = {"d": d, "dir": ab.normalized(), "hw": lerpf(ws[k], ws[k + 1], t) * 0.5}
			if best.has("dir"):
				var hw: float = float(best["hw"])
				var d2: float = float(best["d"])
				if d2 <= hw:
					var dir: Vector2 = best["dir"]
					img.set_pixel(px, py, Color(dir.x * 0.5 + 0.5, dir.y * 0.5 + 0.5, 1.0 - d2 / maxf(hw, 0.0001), 1.0))
	return img


# ---------------------------------------------------------------- undo / redo

func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo() -> bool:
	if _undo.is_empty():
		return false
	var e: Dictionary = _undo.pop_back()
	_swap(e, true)
	_redo.append(e)
	changed.emit()
	return true


func redo() -> bool:
	if _redo.is_empty():
		return false
	var e: Dictionary = _redo.pop_back()
	_swap(e, false)
	_undo.append(e)
	changed.emit()
	return true


func _swap(e: Dictionary, is_undo: bool) -> void:
	var cur: Dictionary = _snapshot()
	_restore(e["snap"])
	e["snap"] = cur
	var tr: Variant = e["terrain"]
	if tr != null:
		var terrain: TerrainEditLayers = tr
		for k in int(e["count"]):
			if is_undo:
				terrain.undo()
			else:
				terrain.redo()


func _push() -> void:
	_push_entry({"snap": _snapshot(), "terrain": null, "count": 0})


func _push_entry(e: Dictionary) -> void:
	_undo.append(e)
	_redo.clear()
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()


func _snapshot() -> Dictionary:
	var copy: Array[Dictionary] = []
	for s in splines:
		copy.append(_clone_spline(s))
	return {"splines": copy, "next": _next_id}


func _restore(snap: Dictionary) -> void:
	var src: Array = snap["splines"]
	splines = []
	for s: Dictionary in src:
		splines.append(_clone_spline(s))
	_next_id = int(snap["next"])


func _clone_spline(s: Dictionary) -> Dictionary:
	var c: Dictionary = s.duplicate()
	var p: PackedVector3Array = s["points"]
	var w: PackedFloat32Array = s["widths"]
	c["points"] = p.duplicate()
	c["widths"] = w.duplicate()
	return c


func _find(id: int) -> int:
	for i in splines.size():
		if int(splines[i]["id"]) == id:
			return i
	return -1
