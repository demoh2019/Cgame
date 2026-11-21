@tool
extends RefCounted
## Foliage painting with procedural (PCG) merge and non-destructive per-instance overrides.
##
## Original GDScript implementation. Concepts follow the publicly documented
## workflows of Unreal Engine's Foliage Mode / PCG "edit a generated instance" and
## Terrain3D's instancer; Poisson-disk spacing uses plain dart throwing (Cook 1986 /
## Bridson 2007 are algorithms, no code copied). The 64-bit hash is PcgGraphScript.mix64
## (SplitMix64 finaliser, CC0 / public domain).
##
## Instances live per foliage type in `layers[type]`:
##   {positions: PackedVector3Array, scales: PackedFloat32Array (uniform),
##    rotations: PackedFloat32Array (yaw), ids: PackedInt64Array, proc: PackedByteArray}
## `proc[i] == 1` marks an instance produced by regenerate_from_pcg(). Procedural
## instances keep a stable id (the PCG point seed); edit_instance() and erase() store an
## override keyed by that id, so the edit survives every regeneration.

const PcgGraphScript = preload("res://scripts/shared/pcg_graph.gd")

const ID_MANUAL_BASE: int = 1 << 40
const MAX_UNDO: int = 100

## Optional terrain queries. height_at(x, z) -> float; normal_at(x, z) -> Vector3.
var height_at: Callable = Callable()
var normal_at: Callable = Callable()
## type -> {spacing, min_height, max_height, max_slope_deg, scale_min, scale_max}
var rules: Dictionary = {}
var layers: Dictionary = {}
## type -> {instance id (int) -> {deleted: bool, position, scale, rotation}}
var overrides: Dictionary = {}

## World XZ area covered by the density masks, and their resolution (texels per side).
var mask_rect: Rect2 = Rect2(-128.0, -128.0, 256.0, 256.0)
var mask_resolution: int = 128

var _masks: Dictionary = {}
var _proc_base: Dictionary = {}
var _next_id: int = ID_MANUAL_BASE
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []


# ---------------------------------------------------------------- rules / queries

func set_rules(type: String, r: Dictionary) -> void:
	var cur: Dictionary = rules.get(type, {})
	for k: String in r:
		cur[k] = r[k]
	rules[type] = cur


func _rule(type: String, key: String, default_value: float) -> float:
	var r: Dictionary = rules.get(type, {})
	return float(r.get(key, default_value))


func _terrain_height(x: float, z: float, fallback: float = 0.0) -> float:
	if height_at.is_valid():
		return float(height_at.call(x, z))
	return fallback


func _terrain_normal(x: float, z: float) -> Vector3:
	if normal_at.is_valid():
		return normal_at.call(x, z)
	if height_at.is_valid():
		var e: float = 0.5
		var n := Vector3(
			float(height_at.call(x - e, z)) - float(height_at.call(x + e, z)), 2.0 * e,
			float(height_at.call(x, z - e)) - float(height_at.call(x, z + e)))
		return n.normalized()
	return Vector3.UP


func _passes_rules(type: String, x: float, y: float, z: float) -> bool:
	if y < _rule(type, "min_height", -INF) or y > _rule(type, "max_height", INF):
		return false
	var max_slope: float = _rule(type, "max_slope_deg", 90.0)
	if max_slope < 90.0:
		var n: Vector3 = _terrain_normal(x, z)
		if n.y < cos(deg_to_rad(max_slope)):
			return false
	return true


func _spacing(type: String, density: float) -> float:
	var s: float = _rule(type, "spacing", 0.0)
	if s > 0.0:
		return s
	return 0.6 / sqrt(maxf(density, 0.0001))


# ---------------------------------------------------------------- layer access

func _layer(type: String) -> Dictionary:
	if not layers.has(type):
		layers[type] = {
			"positions": PackedVector3Array(), "scales": PackedFloat32Array(),
			"rotations": PackedFloat32Array(), "ids": PackedInt64Array(), "proc": PackedByteArray(),
		}
	return layers[type]


func types() -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in layers:
		out.append(k)
	return out


func count(type: String) -> int:
	if not layers.has(type):
		return 0
	var l: Dictionary = layers[type]
	var p: PackedVector3Array = l["positions"]
	return p.size()


func procedural_count(type: String) -> int:
	if not layers.has(type):
		return 0
	var l: Dictionary = layers[type]
	var pr: PackedByteArray = l["proc"]
	var n: int = 0
	for b in pr:
		n += int(b)
	return n


func positions(type: String) -> PackedVector3Array:
	if not layers.has(type):
		return PackedVector3Array()
	var l: Dictionary = layers[type]
	return l["positions"]


func instance_id(type: String, index: int) -> int:
	if not layers.has(type):
		return -1
	var l: Dictionary = layers[type]
	var ids: PackedInt64Array = l["ids"]
	return ids[index] if index >= 0 and index < ids.size() else -1


func index_of_id(type: String, id: int) -> int:
	if not layers.has(type):
		return -1
	var l: Dictionary = layers[type]
	var ids: PackedInt64Array = l["ids"]
	return ids.find(id)


func instance_transform(type: String, index: int) -> Transform3D:
	var l: Dictionary = _layer(type)
	var p: PackedVector3Array = l["positions"]
	if index < 0 or index >= p.size():
		return Transform3D.IDENTITY
	var sc: PackedFloat32Array = l["scales"]
	var rt: PackedFloat32Array = l["rotations"]
	return Transform3D(Basis(Vector3.UP, rt[index]).scaled(Vector3.ONE * sc[index]), p[index])


func _add_instance(l: Dictionary, pos: Vector3, scale_v: float, rot: float, id: int, is_proc: bool) -> void:
	var p: PackedVector3Array = l["positions"]
	var sc: PackedFloat32Array = l["scales"]
	var rt: PackedFloat32Array = l["rotations"]
	var ids: PackedInt64Array = l["ids"]
	var pr: PackedByteArray = l["proc"]
	p.append(pos)
	sc.append(scale_v)
	rt.append(rot)
	ids.append(id)
	pr.append(1 if is_proc else 0)
	l["positions"] = p
	l["scales"] = sc
	l["rotations"] = rt
	l["ids"] = ids
	l["proc"] = pr


# ---------------------------------------------------------------- density masks

func _mask_image(type: String) -> Image:
	if not _masks.has(type):
		var img := Image.create(maxi(mask_resolution, 2), maxi(mask_resolution, 2), false, Image.FORMAT_RF)
		img.fill(Color(1.0, 0.0, 0.0, 1.0))
		_masks[type] = img
	return _masks[type]


## Density multiplier (0..1) at a world position; 1 where nothing was painted.
func mask_at(type: String, x: float, z: float) -> float:
	if not _masks.has(type):
		return 1.0
	var img: Image = _masks[type]
	var u: float = (x - mask_rect.position.x) / mask_rect.size.x
	var v: float = (z - mask_rect.position.y) / mask_rect.size.y
	if u < 0.0 or v < 0.0 or u >= 1.0 or v >= 1.0:
		return 1.0
	return img.get_pixel(int(u * float(img.get_width())), int(v * float(img.get_height()))).r


## Paints `value` (0 = no foliage, 1 = full) into the type's density mask. The mask
## scales both new painting and procedural output (procedural instances are re-filtered).
func paint_density_mask(type: String, center: Vector3, radius: float, value: float, strength: float = 1.0) -> void:
	if radius <= 0.0:
		return
	_push(true)
	var img: Image = _mask_image(type)
	var w: int = img.get_width()
	var h: int = img.get_height()
	var sx: float = mask_rect.size.x / float(w)
	var sz: float = mask_rect.size.y / float(h)
	var x0: int = clampi(floori((center.x - radius - mask_rect.position.x) / sx), 0, w - 1)
	var x1: int = clampi(ceili((center.x + radius - mask_rect.position.x) / sx), 0, w - 1)
	var y0: int = clampi(floori((center.z - radius - mask_rect.position.y) / sz), 0, h - 1)
	var y1: int = clampi(ceili((center.z + radius - mask_rect.position.y) / sz), 0, h - 1)
	for py in range(y0, y1 + 1):
		for px in range(x0, x1 + 1):
			var wx: float = mask_rect.position.x + (float(px) + 0.5) * sx
			var wz: float = mask_rect.position.y + (float(py) + 0.5) * sz
			var d: float = Vector2(wx, wz).distance_to(Vector2(center.x, center.z))
			if d > radius:
				continue
			var a: float = clampf(smoothstep(0.0, 1.0, (1.0 - d / radius) * 2.0) * strength, 0.0, 1.0)
			var old: float = img.get_pixel(px, py).r
			img.set_pixel(px, py, Color(lerpf(old, clampf(value, 0.0, 1.0), a), 0.0, 0.0, 1.0))
	if _proc_base.has(type):
		_rebuild_procedural(type)


func get_mask_image(type: String) -> Image:
	return _mask_image(type)


# ---------------------------------------------------------------- painting

## Scatters instances of `type` in a disc using Poisson-disk (dart throwing) spacing,
## respecting the type's slope/height rules and density mask. Tops the disc up to
## `density_per_m2` (instances already there count), so repeated strokes saturate.
## Returns the number of instances added.
func paint(center: Vector3, radius: float, type: String, density_per_m2: float, seed_value: int = 0) -> int:
	if radius <= 0.0 or density_per_m2 <= 0.0:
		return 0
	_push(false)
	var l: Dictionary = _layer(type)
	var spacing: float = _spacing(type, density_per_m2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var grid: Dictionary = {}
	var existing: int = 0
	var ex_pos: PackedVector3Array = l["positions"]
	for q in ex_pos:
		var dd: float = Vector2(q.x, q.z).distance_to(Vector2(center.x, center.z))
		if dd <= radius + spacing:
			_grid_add(grid, Vector2(q.x, q.z), spacing)
			if dd <= radius:
				existing += 1
	var target: float = density_per_m2 * PI * radius * radius - float(existing)
	var want: int = maxi(0, floori(target))
	if rng.randf() < target - floorf(target) and target > 0.0:
		want += 1
	var smin: float = _rule(type, "scale_min", 0.8)
	var smax: float = _rule(type, "scale_max", 1.2)
	var added: int = 0
	# One "slot" per wanted instance: the density mask thins slots (no retry), while
	# rule/spacing failures retry with a fresh dart.
	for slot in want:
		for attempt in 40:
			var ang: float = rng.randf() * TAU
			var r: float = radius * sqrt(rng.randf())
			var x: float = center.x + cos(ang) * r
			var z: float = center.z + sin(ang) * r
			if rng.randf() > mask_at(type, x, z):
				break
			var y: float = _terrain_height(x, z, center.y)
			if not _passes_rules(type, x, y, z):
				continue
			if _grid_blocked(grid, Vector2(x, z), spacing):
				continue
			_grid_add(grid, Vector2(x, z), spacing)
			var sc: float = rng.randf_range(smin, maxf(smin, smax))
			var id: int = _next_id
			_next_id += 1
			_add_instance(l, Vector3(x, y, z), sc, rng.randf() * TAU, id, false)
			added += 1
			break
	if added == 0:
		_undo.pop_back()
	return added


func _grid_key(p: Vector2, cell: float) -> Vector2i:
	return Vector2i(floori(p.x / cell), floori(p.y / cell))


func _grid_add(grid: Dictionary, p: Vector2, cell: float) -> void:
	var k: Vector2i = _grid_key(p, cell)
	if not grid.has(k):
		grid[k] = []
	var arr: Array = grid[k]
	arr.append(p)


func _grid_blocked(grid: Dictionary, p: Vector2, cell: float) -> bool:
	var k: Vector2i = _grid_key(p, cell)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var kk := Vector2i(k.x + dx, k.y + dy)
			if not grid.has(kk):
				continue
			var arr: Array = grid[kk]
			for q: Vector2 in arr:
				if q.distance_to(p) < cell:
					return true
	return false


## Removes instances of `type` within `radius` (XZ). Procedural instances are recorded
## as deleted overrides so regeneration does not bring them back. Returns the count.
func erase(center: Vector3, radius: float, type: String) -> int:
	if not layers.has(type) or radius <= 0.0:
		return 0
	var l: Dictionary = layers[type]
	var p: PackedVector3Array = l["positions"]
	var hit := PackedInt32Array()
	var c2 := Vector2(center.x, center.z)
	for i in p.size():
		if Vector2(p[i].x, p[i].z).distance_to(c2) <= radius:
			hit.append(i)
	if hit.is_empty():
		return 0
	_push(false)
	var ids: PackedInt64Array = l["ids"]
	var pr: PackedByteArray = l["proc"]
	var ov: Dictionary = overrides.get(type, {})
	for i in hit:
		if pr[i] == 1:
			ov[ids[i]] = {"deleted": true}
	overrides[type] = ov
	_remove_indices(l, hit)
	return hit.size()


func _remove_indices(l: Dictionary, hit: PackedInt32Array) -> void:
	var drop: Dictionary = {}
	for i in hit:
		drop[i] = true
	var p: PackedVector3Array = l["positions"]
	var sc: PackedFloat32Array = l["scales"]
	var rt: PackedFloat32Array = l["rotations"]
	var ids: PackedInt64Array = l["ids"]
	var pr: PackedByteArray = l["proc"]
	var np := PackedVector3Array()
	var ns := PackedFloat32Array()
	var nr := PackedFloat32Array()
	var ni := PackedInt64Array()
	var npr := PackedByteArray()
	for i in p.size():
		if drop.has(i):
			continue
		np.append(p[i])
		ns.append(sc[i])
		nr.append(rt[i])
		ni.append(ids[i])
		npr.append(pr[i])
	l["positions"] = np
	l["scales"] = ns
	l["rotations"] = nr
	l["ids"] = ni
	l["proc"] = npr


# ---------------------------------------------------------------- overrides

## Replaces one instance's transform (position, uniform scale, yaw). For procedural
## instances the edit is stored as an override keyed by the stable id, so it is
## re-applied after every regenerate_from_pcg(); the link to the generator is kept.
func edit_instance(type: String, index: int, xform: Transform3D) -> bool:
	if not layers.has(type):
		return false
	var l: Dictionary = layers[type]
	var p: PackedVector3Array = l["positions"]
	if index < 0 or index >= p.size():
		return false
	_push(false)
	var sc: PackedFloat32Array = l["scales"]
	var rt: PackedFloat32Array = l["rotations"]
	var ids: PackedInt64Array = l["ids"]
	var pr: PackedByteArray = l["proc"]
	var s: float = xform.basis.get_scale().x
	var yaw: float = xform.basis.orthonormalized().get_euler().y
	p[index] = xform.origin
	sc[index] = s
	rt[index] = yaw
	l["positions"] = p
	l["scales"] = sc
	l["rotations"] = rt
	if pr[index] == 1:
		var ov: Dictionary = overrides.get(type, {})
		ov[ids[index]] = {"deleted": false, "position": xform.origin, "scale": s, "rotation": yaw}
		overrides[type] = ov
	return true


func is_overridden(type: String, id: int) -> bool:
	var ov: Dictionary = overrides.get(type, {})
	return ov.has(id)


func override_count(type: String) -> int:
	var ov: Dictionary = overrides.get(type, {})
	return ov.size()


## Drops the override for a procedural instance id and restores the generated version.
func revert_instance(type: String, id: int) -> bool:
	var ov: Dictionary = overrides.get(type, {})
	if not ov.has(id):
		return false
	_push(false)
	ov.erase(id)
	overrides[type] = ov
	_rebuild_procedural(type)
	return true


# ---------------------------------------------------------------- PCG merge

## Runs `graph.execute(inputs)` and replaces the type's procedural instances with its
## `points` output (pin `output`, default: the only output), filtered by rules and the
## density mask, then re-applies overrides by stable id (PCG point seed). Manually
## painted instances are untouched. Returns the number of procedural instances, or -1
## when the graph did not yield point data.
func regenerate_from_pcg(graph: PcgGraphScript, inputs: Dictionary, type: String, output: String = "") -> int:
	var result: Dictionary = graph.execute(inputs)
	var data: Variant = null
	if output != "":
		data = result.get(output)
	elif result.size() == 1:
		data = result.values()[0]
	if not (data is Dictionary):
		return -1
	var d: Dictionary = data
	if str(d.get("type", "")) != PcgGraphScript.T_POINTS:
		return -1
	var pos: PackedVector3Array = d["positions"]
	var attrs: Dictionary = d["attrs"]
	var sc: PackedFloat32Array = attrs["scale"]
	var rt: PackedFloat32Array = attrs["rotation_y"]
	var sd: PackedInt64Array = attrs["seed"]
	var ids := PackedInt64Array()
	var seen: Dictionary = {}
	for i in pos.size():
		var id: int = sd[i]
		while seen.has(id) or id >= ID_MANUAL_BASE and id < ID_MANUAL_BASE * 2:
			id = PcgGraphScript.mix64(id + 1)
		seen[id] = true
		ids.append(id)
	_push(false)
	_proc_base[type] = {"positions": pos.duplicate(), "scales": sc.duplicate(), "rotations": rt.duplicate(), "ids": ids}
	_rebuild_procedural(type)
	return procedural_count(type)


## Re-derives the procedural instances of `type` from the last PCG output
## (rules + density mask + overrides). Called automatically when masks change.
func _rebuild_procedural(type: String) -> void:
	var l: Dictionary = _layer(type)
	var pr: PackedByteArray = l["proc"]
	var drop := PackedInt32Array()
	for i in pr.size():
		if pr[i] == 1:
			drop.append(i)
	_remove_indices(l, drop)
	if not _proc_base.has(type):
		return
	var b: Dictionary = _proc_base[type]
	var pos: PackedVector3Array = b["positions"]
	var sc: PackedFloat32Array = b["scales"]
	var rt: PackedFloat32Array = b["rotations"]
	var ids: PackedInt64Array = b["ids"]
	var ov: Dictionary = overrides.get(type, {})
	for i in pos.size():
		var id: int = ids[i]
		if ov.has(id):
			var o: Dictionary = ov[id]
			if bool(o.get("deleted", false)):
				continue
			_add_instance(l, o["position"], float(o["scale"]), float(o["rotation"]), id, true)
			continue
		var p: Vector3 = pos[i]
		if not _passes_rules(type, p.x, p.y, p.z):
			continue
		var m: float = mask_at(type, p.x, p.z)
		if m < 1.0 and PcgGraphScript.rand01(PcgGraphScript.mix64(id ^ 0x5bd1e995)) >= m:
			continue
		_add_instance(l, p, sc[i], rt[i], id, true)


# ---------------------------------------------------------------- output

func to_multimesh(type: String, mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var n: int = count(type)
	mm.instance_count = n
	for i in n:
		mm.set_instance_transform(i, instance_transform(type, i))
	return mm


# ---------------------------------------------------------------- undo / redo

func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo() -> bool:
	if _undo.is_empty():
		return false
	var e: Dictionary = _undo.pop_back()
	var cur: Dictionary = _snapshot(e.has("masks"))
	_restore(e)
	_redo.append(cur)
	return true


func redo() -> bool:
	if _redo.is_empty():
		return false
	var e: Dictionary = _redo.pop_back()
	var cur: Dictionary = _snapshot(e.has("masks"))
	_restore(e)
	_undo.append(cur)
	return true


func _push(with_masks: bool) -> void:
	_undo.append(_snapshot(with_masks))
	_redo.clear()
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()


func _snapshot(with_masks: bool) -> Dictionary:
	var s: Dictionary = {
		"layers": _clone(layers), "overrides": _clone(overrides),
		"base": _clone(_proc_base), "next": _next_id,
	}
	if with_masks:
		var m: Dictionary = {}
		for k: String in _masks:
			var img: Image = _masks[k]
			m[k] = img.duplicate()
		s["masks"] = m
	return s


func _restore(s: Dictionary) -> void:
	layers = s["layers"]
	overrides = s["overrides"]
	_proc_base = s["base"]
	_next_id = int(s["next"])
	if s.has("masks"):
		_masks = s["masks"]


func _clone(v: Variant) -> Variant:
	if v is Dictionary:
		var src: Dictionary = v
		var out: Dictionary = {}
		for k: Variant in src:
			out[k] = _clone(src[k])
		return out
	match typeof(v):
		TYPE_PACKED_VECTOR3_ARRAY:
			var a3: PackedVector3Array = v
			return a3.duplicate()
		TYPE_PACKED_FLOAT32_ARRAY:
			var af: PackedFloat32Array = v
			return af.duplicate()
		TYPE_PACKED_INT64_ARRAY:
			var ai: PackedInt64Array = v
			return ai.duplicate()
		TYPE_PACKED_BYTE_ARRAY:
			var ab: PackedByteArray = v
			return ab.duplicate()
	return v
