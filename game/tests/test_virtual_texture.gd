extends RefCounted
## Sparse virtual texture page table, LRU cache, fallback and indirection.

const VirtualTexture = preload("res://scripts/client/virtual_texture.gd")

var _calls: int = 0


func _provider(mip: int, px: int, py: int) -> Image:
	_calls += 1
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color8(mip * 40 + 10, px * 20, py * 20, 255))
	return img


func _make(phys_x: int, phys_y: int) -> VirtualTexture:
	var vt := VirtualTexture.new()
	vt.provider = _provider
	vt.setup(64, 8, phys_x, phys_y, 2)  # 8x8 pages at mip0, mips 0..3
	return vt


func run(t) -> void:
	t.current = "virtual texture residency"
	var vt := _make(2, 2)
	t.eq(vt.top_mip, 3, "64/8 pages gives 4 mips")
	t.check(vt.is_resident(3, 0, 0), "lowest mip resident after setup")
	vt.request_from_feedback(PackedInt32Array([
		VirtualTexture.pack_page(0, 1, 1), VirtualTexture.pack_page(0, 1, 1),
		VirtualTexture.pack_page(2, 0, 0), VirtualTexture.pack_page(0, 5, 5)]))
	t.eq(vt.pending_count(), 3, "duplicate requests are folded")
	var n := vt.update(1)
	t.eq(n, 1, "per-frame budget respected")
	t.check(vt.is_resident(2, 0, 0), "coarser page loaded first")
	t.check(vt.is_resident(3, 0, 0), "top mip survives")
	t.eq(vt.update(10), 2, "remaining requests fill free slots")
	# 2x2 slots: top + three requested pages.
	t.eq(vt.resident_count(), 4, "cache filled without eviction")

	t.current = "virtual texture lru"
	var v2 := _make(2, 2)  # 4 slots: top + 3
	var a := VirtualTexture.pack_page(0, 0, 0)
	var b := VirtualTexture.pack_page(0, 1, 0)
	var c := VirtualTexture.pack_page(0, 2, 0)
	var d := VirtualTexture.pack_page(0, 3, 0)
	v2.request_from_feedback(PackedInt32Array([a, b, c]))
	v2.update(8)
	t.eq(v2.resident_count(), 4, "cache full")
	# Touch a and c this frame; b is the stale one.
	v2.request_from_feedback(PackedInt32Array([a, c, d]))
	v2.update(8)
	t.check(v2.is_resident(0, 3, 0), "new page loaded")
	t.check(not v2.is_resident(0, 1, 0), "untouched page evicted")
	t.check(v2.is_resident(0, 0, 0) and v2.is_resident(0, 2, 0), "pages needed this frame kept")
	t.check(v2.is_resident(3, 0, 0), "top mip never evicted")
	t.eq(v2.stat_evictions, 1, "one eviction counted")
	# Everything needed this frame: no eviction possible, request stays pending.
	v2.request_from_feedback(PackedInt32Array([a, c, d, VirtualTexture.pack_page(0, 4, 0)]))
	v2.update(8)
	t.check(not v2.is_resident(0, 4, 0), "no slot freed while all pages needed")
	t.check(v2.is_resident(0, 0, 0) and v2.is_resident(0, 2, 0) and v2.is_resident(0, 3, 0), "needed pages survive")

	t.current = "virtual texture indirection"
	var v3 := _make(4, 4)
	var ind := v3.indirection_image()
	t.eq(ind.get_width(), 8, "indirection is one texel per mip0 page")
	var px := ind.get_pixel(5, 6)
	t.eq(int(round(px.b * 255.0)), 3, "unloaded page falls back to lowest mip")
	v3.request_from_feedback(PackedInt32Array([VirtualTexture.pack_page(1, 2, 3)]))
	v3.update(4)
	px = v3.indirection_image().get_pixel(4, 6)
	t.eq(int(round(px.b * 255.0)), 1, "children use resident parent mip")
	px = v3.indirection_image().get_pixel(0, 0)
	t.eq(int(round(px.b * 255.0)), 3, "unrelated page still lowest mip")
	v3.request_from_feedback(PackedInt32Array([VirtualTexture.pack_page(0, 4, 6)]))
	v3.update(4)
	px = v3.indirection_image().get_pixel(4, 6)
	t.eq(int(round(px.b * 255.0)), 0, "exact page wins once loaded")
	var info := v3.lookup(Vector2(4.5 / 8.0, 6.5 / 8.0), 0)
	var slot: Vector2i = info["slot"]
	t.eq(int(info["resident_mip"]), 0, "lookup finds mip0")
	t.eq(int(round(px.r * 255.0)), slot.x, "lookup slot x matches indirection")
	t.eq(int(round(px.g * 255.0)), slot.y, "lookup slot y matches indirection")
	t.eq(int(v3.lookup(Vector2(0.9, 0.9), 0)["resident_mip"]), 3, "lookup falls back to parent")

	t.current = "virtual texture atlas and stats"
	var slot_px := 8 + 2 * 2
	var atlas := v3.physical_atlas()
	var inner := atlas.get_pixel(slot.x * slot_px + 2 + 3, slot.y * slot_px + 2 + 3)
	t.eq(inner.to_html(false), Color8(10, 80, 120, 255).to_html(false), "atlas pixels match provider content")
	var edge := atlas.get_pixel(slot.x * slot_px, slot.y * slot_px)
	t.eq(edge.to_html(false), inner.to_html(false), "border replicates edge")
	var st := v3.stats()
	t.eq(int(st["misses"]), 2, "two misses counted")
	t.eq(int(st["hits"]), 0, "no hits yet")
	v3.request_from_feedback(PackedInt32Array([VirtualTexture.pack_page(0, 4, 6)]))
	t.eq(int(v3.stats()["hits"]), 1, "resident request counts as hit")
	t.eq(int(v3.stats()["resident_pages"]), 3, "resident pages counted")

	t.current = "virtual texture shader include"
	t.check(FileAccess.file_exists("res://assets/shaders/virtual_texture_sample.gdshaderinc"), "include exists")
	var f := FileAccess.open("res://assets/shaders/virtual_texture_sample.gdshaderinc", FileAccess.READ)
	t.check(f != null and f.get_as_text().contains("vt_sample"), "include defines vt_sample")
