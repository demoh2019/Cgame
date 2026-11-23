extends RefCounted
## CPU-side virtual shadow map page manager: clipmap levels, fixed-size pages,
## page requests from visible receivers, caster invalidation and an LRU
## physical page pool with cross-frame cache reuse.
##
## Concepts follow the publicly documented design of Virtual Shadow Maps
## (Epic Games, "Virtual Shadow Maps" docs / SIGGRAPH talks) and the clipmap
## idea of Tanner et al. 1998. This is an independent clean-room implementation
## from those descriptions; no Unreal Engine source code was used or copied.
## Original code, MIT-compatible.

var levels: int = 0
var level0_size: float = 0.0
var page_size: int = 128
var virtual_resolution: int = 0
var pages_per_axis: int = 0
var physical_capacity: int = 0

var _light_dir: Vector3 = Vector3(0, -1, 0)
var _right: Vector3 = Vector3.RIGHT
var _up: Vector3 = Vector3.FORWARD
var _center: Array[Vector2i] = []   # per-level clipmap centre in global page coords
var _cache: Dictionary = {}          # key:int -> {slot:int, dirty:bool, used:int, level:int, gx:int, gy:int}
var _free: Array[int] = []
var _requested: Dictionary = {}      # key:int -> true (this frame)
var _render_jobs := PackedInt32Array() # packed (level, gx, gy, physical_slot) for current frame
var _frame: int = 0
var _evicted: int = 0
var _dropped: int = 0


func setup(clipmap_levels: int, level0_world_size: float, page_size_texels: int, virtual_res: int, physical_pages: int) -> void:
	levels = maxi(clipmap_levels, 1)
	level0_size = maxf(level0_world_size, 0.001)
	page_size = maxi(page_size_texels, 1)
	virtual_resolution = maxi(virtual_res, page_size)
	@warning_ignore("integer_division")
	pages_per_axis = maxi(virtual_resolution / page_size, 1)
	physical_capacity = maxi(physical_pages, 1)
	_cache.clear()
	_requested.clear()
	_render_jobs.clear()
	_free.clear()
	for i in range(physical_capacity - 1, -1, -1):
		_free.append(i)
	_center.clear()
	for _l in levels:
		_center.append(Vector2i.ZERO)
	_frame = 0


func level_world_size(level: int) -> float:
	return level0_size * float(1 << level)


func page_world_size(level: int) -> float:
	return level_world_size(level) / float(pages_per_axis)


func texel_world_size(level: int) -> float:
	return level_world_size(level) / float(virtual_resolution)


## Starts a frame: rebuilds the light basis and recentres each clipmap by whole
## pages (global page coordinates keep cached pages valid across recentring).
func begin_frame(light_dir: Vector3, camera_pos: Vector3) -> void:
	_frame += 1
	_requested.clear()
	_render_jobs.clear()
	_evicted = 0
	_dropped = 0
	var d: Vector3 = light_dir.normalized()
	if d.length_squared() < 0.5:
		d = Vector3(0, -1, 0)
	if absf(d.dot(Vector3.UP)) > 0.99:
		_right = Vector3.RIGHT
	else:
		_right = d.cross(Vector3.UP).normalized()
	_up = _right.cross(d).normalized()
	if not d.is_equal_approx(_light_dir) and not _cache.is_empty():
		# Light moved: every cached page is stale.
		for k in _cache:
			var e: Dictionary = _cache[k]
			e["dirty"] = true
	_light_dir = d
	var cx: float = camera_pos.dot(_right)
	var cy: float = camera_pos.dot(_up)
	for l in levels:
		var pw: float = page_world_size(l)
		_center[l] = Vector2i(int(floorf(cx / pw)), int(floorf(cy / pw)))


func clipmap_center(level: int) -> Vector2i:
	return _center[level]


## Smallest level whose texel size covers the receiver's pixel footprint.
func level_for_footprint(footprint: float) -> int:
	var f: float = maxf(footprint, 0.000001)
	for l in levels:
		if texel_world_size(l) >= f:
			return l
	return levels - 1


@warning_ignore("integer_division")
func _in_current_window(level: int, gx: int, gy: int) -> bool:
	if level < 0 or level >= _center.size() or pages_per_axis < 1:
		return false
	var half: int = pages_per_axis / 2
	var dx: int = gx - _center[level].x
	var dy: int = gy - _center[level].y
	return (dx >= -half and dx < pages_per_axis - half
			and dy >= -half and dy < pages_per_axis - half)


func request_for_receivers(points: PackedVector3Array, pixel_footprints: PackedFloat32Array) -> void:
	for i in points.size():
		var fp: float = pixel_footprints[i] if i < pixel_footprints.size() else texel_world_size(0)
		var l: int = level_for_footprint(fp)
		var p: Vector3 = points[i]
		var pw: float = page_world_size(l)
		var gx: int = int(floorf(p.dot(_right) / pw))
		var gy: int = int(floorf(p.dot(_up) / pw))
		if not _in_current_window(l, gx, gy):
			continue
		_requested[_key(l, gx, gy)] = true


## Marks cached pages overlapping moved caster AABBs dirty. Static casters are
## simply never passed in, so their pages stay cached.
func invalidate_casters(aabbs_moved: Array) -> void:
	for a in aabbs_moved:
		var box: AABB = a
		var lo: Vector2 = Vector2(INF, INF)
		var hi: Vector2 = Vector2(-INF, -INF)
		for c in 8:
			var corner: Vector3 = box.get_endpoint(c)
			var q: Vector2 = Vector2(corner.dot(_right), corner.dot(_up))
			lo = lo.min(q)
			hi = hi.max(q)
		for l in levels:
			var pw: float = page_world_size(l)
			var x0: int = int(floorf(lo.x / pw))
			var x1: int = int(floorf(hi.x / pw))
			var y0: int = int(floorf(lo.y / pw))
			var y1: int = int(floorf(hi.y / pw))
			if (x1 - x0 + 1) * (y1 - y0 + 1) > _cache.size():
				# Wide box: scan the cache instead of enumerating the rect.
				for k in _cache:
					var e: Dictionary = _cache[k]
					var el: int = e["level"]
					var ex: int = e["gx"]
					var ey: int = e["gy"]
					if el == l and ex >= x0 and ex <= x1 and ey >= y0 and ey <= y1:
						e["dirty"] = true
			else:
				for gx in range(x0, x1 + 1):
					for gy in range(y0, y1 + 1):
						var key: int = _key(l, gx, gy)
						if _cache.has(key):
							var e2: Dictionary = _cache[key]
							e2["dirty"] = true


## Resolves requests against the physical pool.
## Returns {allocated, reused, rendered, evicted, dropped, requested, resident}.
func end_frame() -> Dictionary:
	var allocated: int = 0
	var reused: int = 0
	var rendered: int = 0
	var keys: Array = _requested.keys()
	keys.sort()
	# Touch cache hits first so they are never chosen as eviction victims.
	for k in keys:
		if _cache.has(k):
			var e: Dictionary = _cache[k]
			e["used"] = _frame
	for k in keys:
		if _cache.has(k):
			var e2: Dictionary = _cache[k]
			if e2["dirty"]:
				_append_render_job(e2)
				e2["dirty"] = false
				rendered += 1
			else:
				reused += 1
			continue
		var slot: int = _take_slot()
		if slot < 0:
			_dropped += 1
			continue
		var lvl: int = (k >> 48) & 0xFF
		var gx: int = ((k >> 24) & 0xFFFFFF) - 0x800000
		var gy: int = (k & 0xFFFFFF) - 0x800000
		var entry := {"slot": slot, "dirty": false, "used": _frame, "level": lvl, "gx": gx, "gy": gy}
		_cache[k] = entry
		_append_render_job(entry)
		allocated += 1
		rendered += 1
	return {
		"allocated": allocated, "reused": reused, "rendered": rendered,
		"evicted": _evicted, "dropped": _dropped, "requested": keys.size(),
		"resident": _cache.size(),
	}


func _append_render_job(entry: Dictionary) -> void:
	_render_jobs.append(int(entry["level"]))
	_render_jobs.append(int(entry["gx"]))
	_render_jobs.append(int(entry["gy"]))
	_render_jobs.append(int(entry["slot"]))


## Flattened 4-int records, one per newly assigned/invalidated page.
## Consume after end_frame() and before begin_frame() clears the batch.
func get_render_jobs() -> PackedInt32Array:
	return _render_jobs


func resident_count() -> int:
	return _cache.size()


func is_resident(level: int, gx: int, gy: int) -> bool:
	return _cache.has(_key(level, gx, gy))


## Toroidal page table for shaders: levels * pages_per_axis^2 ints holding the
## physical slot, or -1 when the page is not resident. Index:
## level*N*N + (gy mod N)*N + (gx mod N).
func page_table() -> PackedInt32Array:
	var n: int = pages_per_axis
	var table: PackedInt32Array = PackedInt32Array()
	table.resize(levels * n * n)
	table.fill(-1)
	for k in _cache:
		var e: Dictionary = _cache[k]
		var l: int = e["level"]
		var gx: int = e["gx"]
		var gy: int = e["gy"]
		var slot: int = e["slot"]
		if not _in_current_window(l, gx, gy):
			continue
		table[l * n * n + posmod(gy, n) * n + posmod(gx, n)] = slot
	return table


func _take_slot() -> int:
	if not _free.is_empty():
		return _free.pop_back()
	var victim: int = -1
	var oldest: int = 1 << 60
	for k in _cache:
		if _requested.has(k):
			continue
		var e: Dictionary = _cache[k]
		var u: int = e["used"]
		if u < oldest:
			oldest = u
			victim = k
	if victim < 0:
		return -1
	var ve: Dictionary = _cache[victim]
	var slot: int = ve["slot"]
	_cache.erase(victim)
	_evicted += 1
	return slot


func _key(level: int, gx: int, gy: int) -> int:
	return ((level & 0xFF) << 48) | (((gx + 0x800000) & 0xFFFFFF) << 24) | ((gy + 0x800000) & 0xFFFFFF)
