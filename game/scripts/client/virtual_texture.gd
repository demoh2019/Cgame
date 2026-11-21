extends RefCounted
## Sparse virtual texture: page table, feedback-driven requests, LRU physical page cache,
## mip fallback and an indirection image for shaders.
##
## Original implementation (no third-party code copied). Concepts follow the publicly
## documented sparse virtual texturing designs: Sean Barrett, "Sparse Virtual Textures"
## (GDC 2008 talk, ideas only) and the page-table/indirection scheme described for
## Unreal Engine Runtime Virtual Texture (concepts only, no source used).
##
## Page keys encode (mip, x, y) with pack_page(). The lowest (1-page) mip is pinned and
## always resident, so every virtual page can fall back to some resident ancestor.
## Atlas layout: physical slot (sx, sy) covers (page_size + 2 * border) pixels square;
## the page content sits inside, the border is edge-replicated for bilinear filtering.

var virtual_size: int = 0
var page_size: int = 0
var border: int = 4
var physical_pages_x: int = 0
var physical_pages_y: int = 0
## Callable(mip: int, page_x: int, page_y: int) -> Image (page_size x page_size content).
var provider: Callable = Callable()

var pages_mip0: int = 0
var top_mip: int = 0
var stat_hits: int = 0
var stat_misses: int = 0
var stat_evictions: int = 0

var _slot_key: PackedInt32Array = PackedInt32Array()   # -1 = free
var _slot_used: PackedInt32Array = PackedInt32Array()  # frame stamp of last touch
var _resident: Dictionary = {}                         # key (int) -> slot index (int)
var _pending: Dictionary = {}                          # key (int) -> mip (int)
var _frame: int = 1
var _atlas: Image = null
var _indirection: Image = null
var _indirection_dirty: bool = true


static func pack_page(mip: int, x: int, y: int) -> int:
	return (mip << 24) | (y << 12) | x


static func page_mip(key: int) -> int:
	return (key >> 24) & 0xFF


static func page_x(key: int) -> int:
	return key & 0xFFF


static func page_y(key: int) -> int:
	return (key >> 12) & 0xFFF


func setup(p_virtual_size: int, p_page_size: int, p_physical_x: int, p_physical_y: int, p_border: int = 4) -> void:
	virtual_size = p_virtual_size
	page_size = p_page_size
	physical_pages_x = p_physical_x
	physical_pages_y = p_physical_y
	border = p_border
	@warning_ignore("integer_division")
	pages_mip0 = maxi(1, virtual_size / page_size)
	top_mip = 0
	while (pages_mip0 >> top_mip) > 1:
		top_mip += 1
	var slots: int = physical_pages_x * physical_pages_y
	_slot_key = PackedInt32Array()
	_slot_key.resize(slots)
	_slot_key.fill(-1)
	_slot_used = PackedInt32Array()
	_slot_used.resize(slots)
	_slot_used.fill(0)
	_resident.clear()
	_pending.clear()
	_frame = 1
	stat_hits = 0
	stat_misses = 0
	stat_evictions = 0
	var slot_px: int = page_size + 2 * border
	_atlas = Image.create(physical_pages_x * slot_px, physical_pages_y * slot_px, false, Image.FORMAT_RGBA8)
	_indirection = Image.create(pages_mip0, pages_mip0, false, Image.FORMAT_RGBA8)
	_indirection_dirty = true
	_ensure_top()


func pages_at(mip: int) -> int:
	return maxi(1, pages_mip0 >> mip)


## Feedback entries are pack_page() keys read back from the screen-space feedback pass.
## Duplicates are folded; resident pages are touched (LRU) and counted as hits.
func request_from_feedback(feedback: PackedInt32Array) -> void:
	for key: int in feedback:
		var mip: int = page_mip(key)
		if mip > top_mip:
			continue
		if _resident.has(key):
			stat_hits += 1
			_touch_slot(_resident[key] as int)
		elif not _pending.has(key):
			stat_misses += 1
			_pending[key] = mip
		else:
			stat_misses += 1


func update(max_uploads_per_frame: int) -> int:
	_ensure_top()
	var order: Array = _pending.keys()
	# Coarser mips first, then stable by key.
	order.sort_custom(func(a: int, b: int) -> bool:
		var ma: int = page_mip(a)
		var mb: int = page_mip(b)
		if ma != mb:
			return ma > mb
		return a < b)
	var uploaded: int = 0
	for key: int in order:
		if uploaded >= max_uploads_per_frame:
			break
		var slot: int = _acquire_slot()
		if slot < 0:
			break
		_load_page(key, slot)
		_pending.erase(key)
		uploaded += 1
	_frame += 1
	return uploaded


func indirection_image() -> Image:
	if _indirection_dirty:
		_rebuild_indirection()
	return _indirection


func physical_atlas() -> Image:
	return _atlas


func lookup(uv: Vector2, mip: int) -> Dictionary:
	var m: int = clampi(mip, 0, top_mip)
	while m <= top_mip:
		var n: int = pages_at(m)
		var px: int = clampi(int(floor(uv.x * n)), 0, n - 1)
		var py: int = clampi(int(floor(uv.y * n)), 0, n - 1)
		var key: int = pack_page(m, px, py)
		if _resident.has(key):
			var slot: int = _resident[key] as int
			return {"slot": _slot_xy(slot), "resident_mip": m, "page": Vector2i(px, py)}
		m += 1
	return {"slot": Vector2i(-1, -1), "resident_mip": -1, "page": Vector2i(-1, -1)}


func is_resident(mip: int, x: int, y: int) -> bool:
	return _resident.has(pack_page(mip, x, y))


func resident_count() -> int:
	return _resident.size()


func pending_count() -> int:
	return _pending.size()


func stats() -> Dictionary:
	return {
		"hits": stat_hits,
		"misses": stat_misses,
		"evictions": stat_evictions,
		"resident_pages": _resident.size(),
	}


func _slot_xy(slot: int) -> Vector2i:
	return Vector2i(slot % physical_pages_x, slot / physical_pages_x)


func _touch_slot(slot: int) -> void:
	_slot_used[slot] = _frame


func _ensure_top() -> void:
	var key: int = pack_page(top_mip, 0, 0)
	if _resident.has(key) or not provider.is_valid():
		return
	var slot: int = _acquire_slot()
	if slot >= 0:
		_load_page(key, slot)
		_pending.erase(key)


## Free slot first, otherwise the least recently used slot not touched this frame and
## not holding the pinned top mip. Returns -1 when nothing can be evicted.
func _acquire_slot() -> int:
	var best: int = -1
	var best_used: int = 0x7FFFFFFF
	for s in _slot_key.size():
		var k: int = _slot_key[s]
		if k < 0:
			return s
		if _slot_used[s] >= _frame or page_mip(k) == top_mip:
			continue
		if _slot_used[s] < best_used:
			best_used = _slot_used[s]
			best = s
	if best >= 0:
		_resident.erase(_slot_key[best])
		_slot_key[best] = -1
		stat_evictions += 1
		_indirection_dirty = true
	return best


func _load_page(key: int, slot: int) -> void:
	var img: Image = null
	if provider.is_valid():
		img = provider.call(page_mip(key), page_x(key), page_y(key)) as Image
	_slot_key[slot] = key
	_slot_used[slot] = _frame
	_resident[key] = slot
	_indirection_dirty = true
	if img == null:
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != page_size or img.get_height() != page_size:
		img.resize(page_size, page_size, Image.INTERPOLATE_BILINEAR)
	var slot_px: int = page_size + 2 * border
	var origin: Vector2i = _slot_xy(slot) * slot_px
	_atlas.blit_rect(img, Rect2i(0, 0, page_size, page_size), origin + Vector2i(border, border))
	if border > 0:
		_fill_border(img, origin)


func _fill_border(img: Image, origin: Vector2i) -> void:
	var last: int = page_size - 1
	for y in range(-border, page_size + border):
		for x in range(-border, page_size + border):
			if x >= 0 and x < page_size and y >= 0 and y < page_size:
				continue
			var c: Color = img.get_pixel(clampi(x, 0, last), clampi(y, 0, last))
			_atlas.set_pixel(origin.x + border + x, origin.y + border + y, c)


func _rebuild_indirection() -> void:
	for y in pages_mip0:
		for x in pages_mip0:
			var m: int = 0
			var found: bool = false
			while m <= top_mip:
				var key: int = pack_page(m, x >> m, y >> m)
				if _resident.has(key):
					var xy: Vector2i = _slot_xy(_resident[key] as int)
					_indirection.set_pixel(x, y, Color8(xy.x, xy.y, m, 255))
					found = true
					break
				m += 1
			if not found:
				_indirection.set_pixel(x, y, Color8(0, 0, 255, 0))
	_indirection_dirty = false
