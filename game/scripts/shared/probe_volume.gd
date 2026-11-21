extends RefCounted
## Adaptive irradiance probe volume with L2 SH probes, temporal radiance-cache
## style updates and LRU-budgeted cell streaming.
##
## Concepts (re-implemented from published descriptions; no third-party code):
##  - Majercik et al., "Dynamic Diffuse Global Illumination with Ray-Traced
##    Irradiance Fields" (JCGT 2019): probe rays, hysteresis blending, backface
##    weighting (dot+1)/2 squared + 0.2, invalid probes inside geometry.
##  - Unity Adaptive Probe Volumes: bricks subdivided where density is high,
##    streaming in cells.
##  - Ramamoorthi & Hanrahan 2001 / Sloan 2008 for SH irradiance (see sh_lighting.gd).
## Geometry is abstracted behind a trace Callable(origin, dir) -> Dictionary
## {hit: bool, color: Color (outgoing radiance), distance: float, backface: bool (optional)}.

const SHLighting = preload("res://scripts/shared/sh_lighting.gd")

const MAX_LEVEL: int = 2
## Streaming cell edge, in base bricks.
const CELL_SPAN: int = 2
## Serialized record: s32 index + u8 valid + 27 float32.
const RECORD_BYTES: int = 4 + 1 + SHLighting.COEFFS * 3 * 4

var bounds: AABB = AABB()
var base_spacing: float = 2.0
var hysteresis: float = 0.7
var min_hit_distance: float = 0.02
var invalid_fraction: float = 0.5
var sky_top: Color = Color(0.6, 0.75, 1.0)
var sky_bottom: Color = Color(0.15, 0.13, 0.12)
## 0 means unlimited.
var memory_budget_bytes: int = 0

var _positions := PackedVector3Array()
var _sh: Array = []
var _valid := PackedByteArray()
var _probe_cell: Array = []
var _index_of: Dictionary = {}
var _leaf_start: Dictionary = {}
var _leaf_level: Dictionary = {}
var _leaves := PackedInt32Array()
var _leaf_count: int = 0
var _counts: Vector3i = Vector3i.ONE
var _unit: float = 1.0
var _cell_probes: Dictionary = {}
var _resident: Dictionary = {}
var _store: Dictionary = {}
var _tick: int = 0
var _cursor: int = 0
var _frame: int = 0
var _rays: int = 32
var _sky_sh := PackedColorArray()


func clear() -> void:
	_positions = PackedVector3Array()
	_sh = []
	_valid = PackedByteArray()
	_probe_cell = []
	_index_of = {}
	_leaf_start = {}
	_leaf_level = {}
	_leaves = PackedInt32Array()
	_leaf_count = 0
	_cell_probes = {}
	_resident = {}
	_store = {}
	_cursor = 0
	_sky_sh = PackedColorArray()


func probe_count() -> int:
	return _positions.size()


func probe_position(i: int) -> Vector3:
	return _positions[i]


func probe_sh(i: int) -> PackedColorArray:
	return _sh[i]


func is_probe_valid(i: int) -> bool:
	return _valid[i] != 0


func find_probe(pos: Vector3) -> int:
	var key := _key_of(pos)
	if _index_of.has(key):
		return int(_index_of[key])
	return -1


func sky(dir: Vector3) -> Color:
	return sky_bottom.lerp(sky_top, clampf(dir.y * 0.5 + 0.5, 0.0, 1.0))


# --- placement -------------------------------------------------------------

func _key_of(pos: Vector3) -> Vector3i:
	var rel := pos - bounds.position
	return Vector3i(roundi(rel.x / _unit), roundi(rel.y / _unit), roundi(rel.z / _unit))


func _cell_of_base(bc: Vector3i) -> Vector3i:
	return Vector3i(floori(float(bc.x) / float(CELL_SPAN)), floori(float(bc.y) / float(CELL_SPAN)), floori(float(bc.z) / float(CELL_SPAN)))


func _base_coord(pos: Vector3) -> Vector3i:
	var rel := (pos - bounds.position) / base_spacing
	var bc := Vector3i(floori(rel.x), floori(rel.y), floori(rel.z))
	return Vector3i(clampi(bc.x, 0, _counts.x - 1), clampi(bc.y, 0, _counts.y - 1), clampi(bc.z, 0, _counts.z - 1))


func cell_of_position(pos: Vector3) -> Vector3i:
	return _cell_of_base(_base_coord(pos))


## Builds bricks of base_spacing; density_at(center: Vector3) -> float in 0..1
## picks the subdivision level (0..MAX_LEVEL). Returns the probe count.
func build(p_bounds: AABB, p_base_spacing: float, density_at: Callable) -> int:
	clear()
	bounds = p_bounds
	base_spacing = maxf(p_base_spacing, 0.01)
	_counts = Vector3i(
		maxi(1, ceili(bounds.size.x / base_spacing)),
		maxi(1, ceili(bounds.size.y / base_spacing)),
		maxi(1, ceili(bounds.size.z / base_spacing)))
	_unit = base_spacing / float(1 << MAX_LEVEL)
	for cz in _counts.z:
		for cy in _counts.y:
			for cx in _counts.x:
				var bc := Vector3i(cx, cy, cz)
				var origin := bounds.position + Vector3(bc) * base_spacing
				var center := origin + Vector3(0.5, 0.5, 0.5) * base_spacing
				var d: float = 0.0
				if density_at.is_valid():
					d = clampf(float(density_at.call(center)), 0.0, 1.0)
				var level: int = 0
				if d >= 0.67:
					level = 2
				elif d >= 0.34:
					level = 1
				_leaf_start[bc] = _leaf_count
				_leaf_level[bc] = level
				var n: int = 1 << level
				var leaf_size: float = base_spacing / float(n)
				for lz in n:
					for ly in n:
						for lx in n:
							for k in 8:
								var off := Vector3(lx + (k & 1), ly + ((k >> 1) & 1), lz + ((k >> 2) & 1))
								_leaves.append(_probe_at(origin + off * leaf_size))
							_leaf_count += 1
	return _positions.size()


func _probe_at(pos: Vector3) -> int:
	var key := _key_of(pos)
	if _index_of.has(key):
		return int(_index_of[key])
	var idx: int = _positions.size()
	_index_of[key] = idx
	_positions.append(pos)
	_sh.append(SHLighting.create())
	_valid.append(1)
	var cell := cell_of_position(pos)
	_probe_cell.append(cell)
	if not _cell_probes.has(cell):
		_cell_probes[cell] = PackedInt32Array()
	var ids: PackedInt32Array = _cell_probes[cell]
	ids.append(idx)
	_cell_probes[cell] = ids
	_resident[cell] = 0
	return idx


# --- baking ----------------------------------------------------------------

## Traces rays from probe i; returns {sh, inside} where inside is the fraction of
## rays that start inside geometry (backface or hit closer than min_hit_distance).
func _compute_probe(i: int, trace: Callable, rng_seed: int, salt: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed * 1000003 + i * 7919 + salt * 104729
	var axis := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0) + 1.5, rng.randf_range(-1.0, 1.0)).normalized()
	var rot := Basis(axis, rng.randf() * TAU)
	var pos: Vector3 = _positions[i]
	var n: int = _rays
	var w: float = 4.0 * PI / float(n)
	var sh := SHLighting.create()
	var inside: int = 0
	for r in n:
		var d: Vector3 = rot * SHLighting.fibonacci_dir(r, n)
		var res: Dictionary = trace.call(pos, d)
		var rad: Color
		var hit: bool = res.get("hit", false)
		if hit:
			var dist: float = res.get("distance", 0.0)
			var back: bool = res.get("backface", false)
			if back or dist < min_hit_distance:
				inside += 1
				continue
			rad = res.get("color", Color.BLACK)
		else:
			rad = sky(d)
		sh = SHLighting.accumulate(sh, d, Color(rad.r * w, rad.g * w, rad.b * w, 0.0))
	return {"sh": sh, "inside": float(inside) / float(n)}


func bake(trace: Callable, rays_per_probe: int, rng_seed: int) -> void:
	_rays = maxi(rays_per_probe, 4)
	for i in _positions.size():
		var res := _compute_probe(i, trace, rng_seed, 0)
		var inside: float = res["inside"]
		if inside >= invalid_fraction:
			_valid[i] = 0
			_sh[i] = SHLighting.create()
		else:
			_valid[i] = 1
			_sh[i] = res["sh"]
	for cell in _cell_probes.keys():
		_touch(cell)


## Updates a rotating subset (fraction of all probes) and blends with the old
## value using `hysteresis`. Returns the number of probes updated.
func temporal_update(fraction: float, trace: Callable, rng_seed: int) -> int:
	var n: int = _positions.size()
	if n == 0:
		return 0
	var cnt: int = clampi(ceili(fraction * float(n)), 1, n)
	_frame += 1
	var updated: int = 0
	for k in cnt:
		var i: int = (_cursor + k) % n
		var cell: Vector3i = _probe_cell[i]
		if not _resident.has(cell):
			continue
		var res := _compute_probe(i, trace, rng_seed, _frame)
		var inside: float = res["inside"]
		if inside >= invalid_fraction:
			_valid[i] = 0
			_sh[i] = SHLighting.create()
		else:
			var fresh: PackedColorArray = res["sh"]
			if _valid[i] == 0:
				_sh[i] = fresh
			else:
				var old: PackedColorArray = _sh[i]
				_sh[i] = SHLighting.lerp_sh(fresh, old, hysteresis)
			_valid[i] = 1
		updated += 1
	_cursor = (_cursor + cnt) % n
	return updated


# --- sampling --------------------------------------------------------------

func _ambient(normal: Vector3) -> Color:
	if _sky_sh.is_empty():
		_sky_sh = SHLighting.from_sky(Vector3.ZERO, Color.BLACK, sky_top, sky_bottom, 64)
	return SHLighting.evaluate_irradiance(_sky_sh, normal)


## Irradiance / pi at pos for surface normal, interpolated from the 8 corner
## probes of the containing leaf (trilinear x validity x backface weight).
func sample(pos: Vector3, normal: Vector3) -> Color:
	if _positions.is_empty():
		return _ambient(normal)
	var rel := (pos - bounds.position) / base_spacing
	var ext := Vector3(_counts)
	if rel.x < 0.0 or rel.y < 0.0 or rel.z < 0.0 or rel.x > ext.x or rel.y > ext.y or rel.z > ext.z:
		return _ambient(normal)
	var bc := _base_coord(pos)
	_touch(_cell_of_base(bc))
	var level: int = _leaf_level[bc]
	var n: int = 1 << level
	var lf := (rel - Vector3(bc)) * float(n)
	var li := Vector3i(clampi(floori(lf.x), 0, n - 1), clampi(floori(lf.y), 0, n - 1), clampi(floori(lf.z), 0, n - 1))
	var t := lf - Vector3(li)
	var start: int = _leaf_start[bc]
	var leaf: int = start + li.x + n * (li.y + n * li.z)
	var acc := SHLighting.create()
	var total: float = 0.0
	var nrm := normal.normalized()
	for k in 8:
		var ox: int = k & 1
		var oy: int = (k >> 1) & 1
		var oz: int = (k >> 2) & 1
		var idx: int = _leaves[leaf * 8 + k]
		if _valid[idx] == 0:
			continue
		var cell: Vector3i = _probe_cell[idx]
		if not _resident.has(cell):
			continue
		var wx: float = t.x if ox == 1 else 1.0 - t.x
		var wy: float = t.y if oy == 1 else 1.0 - t.y
		var wz: float = t.z if oz == 1 else 1.0 - t.z
		var w: float = wx * wy * wz
		if w <= 0.0:
			continue
		var to_probe := (_positions[idx] - pos)
		if to_probe.length_squared() > 1e-10:
			var facing: float = (to_probe.normalized().dot(nrm) + 1.0) * 0.5
			w *= facing * facing + 0.2
		var s: PackedColorArray = _sh[idx]
		acc = SHLighting.add(acc, SHLighting.scale(s, w))
		total += w
	if total <= 1e-6:
		return _ambient(normal)
	return SHLighting.evaluate_irradiance(SHLighting.scale(acc, 1.0 / total), nrm)


# --- streaming -------------------------------------------------------------

func _touch(cell: Vector3i) -> void:
	if _resident.has(cell):
		_tick += 1
		_resident[cell] = _tick


func touch_cell(cell: Vector3i) -> void:
	_touch(cell)


func is_cell_resident(cell: Vector3i) -> bool:
	return _resident.has(cell)


func cell_probe_ids(cell: Vector3i) -> PackedInt32Array:
	var ids: PackedInt32Array = _cell_probes.get(cell, PackedInt32Array())
	return ids


func resident_bytes() -> int:
	var total: int = 0
	for cell in _resident.keys():
		var ids: PackedInt32Array = _cell_probes[cell]
		total += ids.size() * RECORD_BYTES
	return total


## Cells whose volume intersects the sphere (view_pos, radius), nearest first.
func cells_needed(view_pos: Vector3, radius: float) -> Array:
	var pairs: Array = []
	var cell_size: float = base_spacing * float(CELL_SPAN)
	for cell in _cell_probes.keys():
		var c: Vector3i = cell
		var lo := bounds.position + Vector3(c) * cell_size
		var closest := Vector3(
			clampf(view_pos.x, lo.x, lo.x + cell_size),
			clampf(view_pos.y, lo.y, lo.y + cell_size),
			clampf(view_pos.z, lo.z, lo.z + cell_size))
		var dist: float = closest.distance_to(view_pos)
		if dist <= radius:
			pairs.append([dist, c])
	pairs.sort_custom(func(a: Array, b: Array) -> bool:
		var da: float = a[0]
		var db: float = b[0]
		return da < db)
	var out: Array = []
	for p in pairs:
		var pa: Array = p
		out.append(pa[1])
	return out


func serialize_cell(cell: Vector3i) -> PackedByteArray:
	if not _resident.has(cell):
		var stored: PackedByteArray = _store.get(cell, PackedByteArray())
		return stored
	var ids: PackedInt32Array = _cell_probes.get(cell, PackedInt32Array())
	var buf := PackedByteArray()
	buf.resize(4 + ids.size() * RECORD_BYTES)
	buf.encode_s32(0, ids.size())
	var off: int = 4
	for idx in ids:
		buf.encode_s32(off, idx)
		buf.encode_u8(off + 4, _valid[idx])
		var s: PackedColorArray = _sh[idx]
		var o: int = off + 5
		for j in SHLighting.COEFFS:
			var c: Color = s[j]
			buf.encode_float(o, c.r)
			buf.encode_float(o + 4, c.g)
			buf.encode_float(o + 8, c.b)
			o += 12
		off += RECORD_BYTES
	return buf


## Restores a serialized cell, marks it resident and enforces the budget
## (never evicting the cell just loaded). Returns false on malformed data.
func load_cell(cell: Vector3i, bytes: PackedByteArray) -> bool:
	if bytes.size() < 4 or not _cell_probes.has(cell):
		return false
	var count: int = bytes.decode_s32(0)
	if count < 0 or bytes.size() != 4 + count * RECORD_BYTES:
		return false
	var off: int = 4
	for r in count:
		var idx: int = bytes.decode_s32(off)
		if idx < 0 or idx >= _positions.size():
			return false
		_valid[idx] = bytes.decode_u8(off + 4)
		var s := SHLighting.create()
		var o: int = off + 5
		for j in SHLighting.COEFFS:
			s[j] = Color(bytes.decode_float(o), bytes.decode_float(o + 4), bytes.decode_float(o + 8), 0.0)
			o += 12
		_sh[idx] = s
		off += RECORD_BYTES
	_store.erase(cell)
	_resident[cell] = 0
	_touch(cell)
	enforce_budget(cell)
	return true


## Serializes, stores and frees a cell's probe data. Returns the bytes.
func unload_cell(cell: Vector3i) -> PackedByteArray:
	var bytes := serialize_cell(cell)
	if not _resident.has(cell):
		return bytes
	_store[cell] = bytes
	var ids: PackedInt32Array = _cell_probes[cell]
	for idx in ids:
		_sh[idx] = PackedColorArray()
	_resident.erase(cell)
	return bytes


## Loads an evicted cell from the internal store.
func request_cell(cell: Vector3i) -> bool:
	if _resident.has(cell):
		_touch(cell)
		return true
	if _store.has(cell):
		var bytes: PackedByteArray = _store[cell]
		return load_cell(cell, bytes)
	return false


## Evicts least-recently-used cells until resident_bytes() <= memory_budget_bytes.
## The `protect` cell and the most recently used cell are kept. Returns evictions.
func enforce_budget(protect: Vector3i = Vector3i(-99999, -99999, -99999)) -> int:
	if memory_budget_bytes <= 0:
		return 0
	var evicted: int = 0
	while resident_bytes() > memory_budget_bytes and _resident.size() > 1:
		var oldest: Vector3i = Vector3i.ZERO
		var best: int = 1 << 60
		var newest: int = -1
		for cell in _resident.keys():
			var tk: int = _resident[cell]
			newest = maxi(newest, tk)
		for cell in _resident.keys():
			var c: Vector3i = cell
			var tk: int = _resident[c]
			if c == protect or tk == newest:
				continue
			if tk < best:
				best = tk
				oldest = c
		if best == 1 << 60:
			break
		unload_cell(oldest)
		evicted += 1
	return evicted
