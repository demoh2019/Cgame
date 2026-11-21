extends RefCounted
## Terrain edit layers: brushes, non-destructive layers, splat, undo, dirty chunks, collision queue.

const TerrainEditLayers = preload("res://scripts/shared/terrain_edit_layers.gd")


func _make(w: int, h: int, cs: int, base_h: float = 0.0) -> TerrainEditLayers:
	var base := PackedFloat32Array()
	base.resize(w * h)
	base.fill(base_h)
	var ter := TerrainEditLayers.new()
	ter.setup(w, h, cs, base)
	return ter


func _variance(a: PackedFloat32Array) -> float:
	var mean := 0.0
	for v in a:
		mean += v
	mean /= float(a.size())
	var s := 0.0
	for v in a:
		s += (v - mean) * (v - mean)
	return s / float(a.size())


func run(t) -> void:
	t.current = "brush radius"
	var ter := _make(33, 33, 16)
	var l := ter.add_layer("sculpt")
	ter.apply_brush(l, TerrainEditLayers.Brush.RAISE, Vector2(16, 16), 4.0, 2.0, TerrainEditLayers.Falloff.CONSTANT)
	t.near(ter.composite_height(16, 16), 2.0, 0.0001, "centre raised")
	t.near(ter.composite_height(18, 16), 2.0, 0.0001, "inside radius raised")
	t.eq(ter.composite_height(21, 16), 0.0, "outside radius untouched")
	t.eq(ter.composite_height(0, 0), 0.0, "far corner untouched")
	var soft := _make(33, 33, 16)
	var sl := soft.add_layer("s")
	soft.apply_brush(sl, TerrainEditLayers.Brush.RAISE, Vector2(16, 16), 6.0, 3.0, TerrainEditLayers.Falloff.LINEAR)
	t.check(soft.composite_height(16, 16) > soft.composite_height(19, 16), "falloff decreases with distance")
	ter.apply_brush(l, TerrainEditLayers.Brush.LOWER, Vector2(16, 16), 4.0, 1.0, TerrainEditLayers.Falloff.CONSTANT)
	t.near(ter.composite_height(16, 16), 1.0, 0.0001, "lower brush reduces")

	t.current = "non destructive layers"
	var nd := _make(17, 17, 16, 5.0)
	var la := nd.add_layer("a")
	nd.apply_brush(la, TerrainEditLayers.Brush.RAISE, Vector2(8, 8), 3.0, 4.0, TerrainEditLayers.Falloff.CONSTANT)
	t.near(nd.composite_height(8, 8), 9.0, 0.0001, "raised over base")
	nd.set_layer_visible(la, false)
	t.eq(nd.composite_height(8, 8), 5.0, "hiding restores base")
	nd.set_layer_visible(la, true)
	t.near(nd.composite_height(8, 8), 9.0, 0.0001, "showing brings edit back")
	nd.set_layer_opacity(la, 0.5)
	t.near(nd.composite_height(8, 8), 7.0, 0.0001, "opacity scales add layer")
	nd.set_layer_opacity(la, 1.0)
	t.near(nd.composite_height(8, 8), 9.0, 0.0001, "opacity restored")

	t.current = "layer order and blend"
	var ob := _make(9, 9, 8, 0.0)
	var add_l := ob.add_layer("add", TerrainEditLayers.Blend.ADD)
	var rep_l := ob.add_layer("rep", TerrainEditLayers.Blend.REPLACE)
	ob.fill_layer_rect(add_l, Rect2i(0, 0, 9, 9), 3.0)
	ob.fill_layer_rect(rep_l, Rect2i(0, 0, 9, 9), 1.0, 1.0)
	t.near(ob.composite_height(4, 4), 1.0, 0.0001, "replace on top overrides add")
	ob.move_layer(rep_l, 0)
	t.eq(ob.layer_ids()[0], rep_l, "reorder moves layer to bottom")
	t.near(ob.composite_height(4, 4), 4.0, 0.0001, "add on top of replace stacks")
	ob.set_layer_blend(add_l, TerrainEditLayers.Blend.MAX)
	t.near(ob.composite_height(4, 4), 3.0, 0.0001, "max keeps the higher candidate")
	ob.set_layer_blend(add_l, TerrainEditLayers.Blend.ADD)
	ob.fill_layer_rect(rep_l, Rect2i(0, 0, 9, 9), 1.0, 0.5)
	t.near(ob.composite_height(4, 4), 1.0 * 0.5 + 3.0, 0.0001, "replace alpha blends")
	t.check(ob.remove_layer(rep_l), "remove layer ok")
	t.eq(ob.layer_count(), 1, "one layer left")
	t.near(ob.composite_height(4, 4), 3.0, 0.0001, "removing layer drops its edit")

	t.current = "smooth and flatten"
	var sm := _make(33, 33, 16)
	var nl := sm.add_layer("noise")
	sm.apply_brush(nl, TerrainEditLayers.Brush.NOISE, Vector2(16, 16), 10.0, 4.0, TerrainEditLayers.Falloff.CONSTANT, 0.0, 7)
	var region := Rect2i(8, 8, 17, 17)
	var before := _variance(sm.composite_region(region))
	t.check(before > 0.1, "noise adds variance")
	for i in 4:
		sm.apply_brush(nl, TerrainEditLayers.Brush.SMOOTH, Vector2(16, 16), 12.0, 1.0, TerrainEditLayers.Falloff.CONSTANT)
	t.check(_variance(sm.composite_region(region)) < before * 0.5, "smooth reduces variance")
	sm.apply_brush(nl, TerrainEditLayers.Brush.FLATTEN, Vector2(16, 16), 6.0, 1.0, TerrainEditLayers.Falloff.CONSTANT, 2.5)
	t.near(sm.composite_height(16, 16), 2.5, 0.0001, "flatten hits target at centre")
	t.near(sm.composite_height(14, 17), 2.5, 0.0001, "flatten hits target inside radius")
	var er := _make(17, 17, 16)
	var el := er.add_layer("e")
	er.fill_layer_rect(el, Rect2i(8, 8, 1, 1), 10.0)
	er.apply_brush(el, TerrainEditLayers.Brush.ERODE, Vector2(8, 8), 2.0, 3.0, TerrainEditLayers.Falloff.CONSTANT)
	t.check(er.composite_height(8, 8) < 10.0, "erode lowers a spike")

	t.current = "splat"
	var sp := _make(17, 17, 8)
	sp.setup_splat(4)
	t.eq(sp.splat_weights(3, 3)[0], 1.0, "default material is layer 0")
	sp.paint_splat(2, Vector2(8, 8), 3.0, 0.6, TerrainEditLayers.Falloff.CONSTANT)
	sp.paint_splat(1, Vector2(8, 8), 3.0, 0.3, TerrainEditLayers.Falloff.CONSTANT)
	var all_ok := true
	for y in 17:
		for x in 17:
			var w := sp.splat_weights(x, y)
			var sum := w[0] + w[1] + w[2] + w[3]
			if absf(sum - 1.0) > 0.0001:
				all_ok = false
			for v in w:
				if v < -0.0001 or v > 1.0001:
					all_ok = false
	t.check(all_ok, "weights normalised to 1 everywhere")
	t.near(sp.splat_weights(8, 8)[2], 0.6 * 0.7, 0.0001, "earlier paint scaled by later paint")
	t.eq(sp.splat_weights(0, 0)[0], 1.0, "outside brush unchanged")
	sp.paint_splat(3, Vector2(8, 8), 3.0, 5.0, TerrainEditLayers.Falloff.CONSTANT)
	t.near(sp.splat_weights(8, 8)[3], 1.0, 0.0001, "strong paint saturates")
	t.check(sp.undo(), "splat undo")
	t.near(sp.splat_weights(8, 8)[3], 0.0, 0.0001, "splat undo restores weights")

	t.current = "undo redo"
	var ur := _make(33, 33, 16)
	var ul := ur.add_layer("u")
	var snap0 := ur.composite_region(Rect2i(0, 0, 33, 33))
	ur.apply_brush(ul, TerrainEditLayers.Brush.RAISE, Vector2(10, 10), 5.0, 3.0)
	ur.apply_brush(ul, TerrainEditLayers.Brush.NOISE, Vector2(12, 11), 6.0, 2.0, TerrainEditLayers.Falloff.SMOOTH, 0.0, 3)
	var snap2 := ur.composite_region(Rect2i(0, 0, 33, 33))
	t.check(ur.can_undo() and not ur.can_redo(), "history state after edits")
	t.check(ur.undo() and ur.undo(), "two undos")
	t.check(ur.composite_region(Rect2i(0, 0, 33, 33)) == snap0, "undo restores exactly")
	t.check(not ur.can_undo() and ur.can_redo(), "history state after undo")
	t.check(ur.redo() and ur.redo(), "two redos")
	t.check(ur.composite_region(Rect2i(0, 0, 33, 33)) == snap2, "redo restores exactly")
	ur.undo()
	ur.apply_brush(ul, TerrainEditLayers.Brush.RAISE, Vector2(20, 20), 3.0, 1.0)
	t.check(not ur.can_redo(), "new edit clears redo")
	var mem := _make(65, 65, 16)
	var ml := mem.add_layer("m")
	mem.max_undo_bytes = 20000
	for i in 200:
		mem.apply_brush(ml, TerrainEditLayers.Brush.RAISE, Vector2(10 + (i % 40), 20), 6.0, 0.1)
	t.check(mem.undo_bytes() <= 20000, "undo memory bounded")
	t.check(mem.undo_depth() > 1 and mem.undo_depth() < 200, "oldest strokes dropped")
	var one_stroke := 0
	var tiny := _make(65, 65, 16)
	var tl := tiny.add_layer("t")
	tiny.apply_brush(tl, TerrainEditLayers.Brush.RAISE, Vector2(30, 30), 3.0, 1.0)
	one_stroke = tiny.undo_bytes()
	t.check(one_stroke > 0 and one_stroke < 2000, "stroke stores only its rect")

	t.current = "dirty chunks"
	var dc := _make(65, 65, 16)
	var dl := dc.add_layer("d")
	var first := dc.take_dirty_chunks()
	t.eq(first.size(), 16, "setup marks everything dirty once")
	t.eq(dc.take_dirty_chunks().size(), 0, "cleared after taking")
	dc.apply_brush(dl, TerrainEditLayers.Brush.RAISE, Vector2(24, 24), 3.0, 1.0)
	var d1 := dc.take_dirty_chunks()
	t.eq(d1.size(), 1, "interior edit touches one chunk")
	t.eq(d1[0], Vector2i(1, 1), "correct chunk")
	dc.apply_brush(dl, TerrainEditLayers.Brush.RAISE, Vector2(16, 16), 2.0, 1.0)
	var d2 := dc.take_dirty_chunks()
	t.eq(d2.size(), 4, "seam corner edit touches four chunks")
	t.check(d2.has(Vector2i(0, 0)) and d2.has(Vector2i(1, 1)) and d2.has(Vector2i(0, 1)) and d2.has(Vector2i(1, 0)), "all seam neighbours present")
	dc.apply_brush(dl, TerrainEditLayers.Brush.RAISE, Vector2(8, 24), 2.0, 1.0)
	t.eq(dc.take_dirty_chunks().size(), 1, "edit in chunk centre stays local")
	dc.set_layer_visible(dl, false)
	t.check(dc.take_dirty_chunks().size() >= 1, "toggling visibility dirties affected chunks")

	t.current = "collision jobs"
	var cj := _make(65, 65, 16)
	var cl := cj.add_layer("c")
	cj.collision_jobs(100)
	t.eq(cj.pending_collision_count(), 0, "queue drained")
	cj.apply_brush(cl, TerrainEditLayers.Brush.RAISE, Vector2(8, 8), 2.0, 1.0)
	cj.apply_brush(cl, TerrainEditLayers.Brush.RAISE, Vector2(9, 8), 2.0, 1.0)
	cj.apply_brush(cl, TerrainEditLayers.Brush.RAISE, Vector2(16, 40), 2.0, 1.0)
	cj.apply_brush(cl, TerrainEditLayers.Brush.RAISE, Vector2(40, 40), 2.0, 1.0)
	var total := cj.pending_collision_count()
	t.eq(total, 4, "repeated edits dedupe to four pending chunks")
	var seen := {}
	var batches := 0
	var max_batch := 0
	while cj.pending_collision_count() > 0:
		var batch := cj.collision_jobs(2)
		batches += 1
		max_batch = maxi(max_batch, batch.size())
		for c in batch:
			seen[c] = seen.get(c, 0) + 1
	t.check(max_batch <= 2, "per-frame limit respected")
	t.eq(batches, ceili(float(total) / 2.0), "work spread across frames")
	var dup := false
	for k in seen.keys():
		if int(seen[k]) > 1:
			dup = true
	t.check(not dup, "chunks deduped in queue")
	t.eq(seen.size(), total, "every pending chunk yielded once")
	cj.apply_brush(cl, TerrainEditLayers.Brush.RAISE, Vector2(8, 8), 2.0, 1.0)
	t.check(cj.collision_jobs(0).is_empty(), "zero budget yields nothing")
	t.check(cj.collision_jobs(8).has(Vector2i(0, 0)), "re-dirtied chunk is requeued")

	t.current = "chunk export"
	var ex := _make(33, 33, 16)
	var xl := ex.add_layer("x")
	ex.apply_brush(xl, TerrainEditLayers.Brush.NOISE, Vector2(16, 16), 20.0, 5.0, TerrainEditLayers.Falloff.CONSTANT, 0.0, 11)
	var h00 := ex.export_chunk_heights(Vector2i(0, 0))
	var h10 := ex.export_chunk_heights(Vector2i(1, 0))
	t.eq(h00.size(), 19 * 19, "export has 1 texel border")
	var seam_ok := true
	for j in 19:
		# chunk0 column cs (=16) and chunk1 column 0 are the same texel row-wise; compare shared texels.
		if absf(h00[j * 19 + 17] - h10[j * 19 + 1]) > 0.00001:
			seam_ok = false
		if absf(h00[j * 19 + 18] - h10[j * 19 + 2]) > 0.00001:
			seam_ok = false
	t.check(seam_ok, "border matches neighbour data")
	t.near(h00[1 * 19 + 1 + 16], ex.composite_height(16, 0), 0.00001, "export texel matches composite")
	t.eq(ex.export_chunk_heights(Vector2i(5, 5)).size(), 0, "invalid chunk exports nothing")

	t.current = "chunk mesh"
	var ms := _make(33, 33, 16)
	var mm := ms.build_chunk_mesh(Vector2i(0, 0), 2.0)
	t.eq(mm.get_surface_count(), 1, "one surface")
	var arrays := mm.surface_get_arrays(0)
	var mv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var mi: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	t.eq(mv.size(), 17 * 17, "vertex count (cs+1)^2")
	t.eq(mi.size(), 16 * 16 * 6, "index count")
	t.near(mv[mv.size() - 1].x, 32.0, 0.0001, "cell size applied")
	var mn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	t.near(mn[0].y, 1.0, 0.0001, "flat terrain normal points up")
	var slope := _make(33, 33, 16)
	var sll := slope.add_layer("ramp")
	slope.fill_layer_rect(sll, Rect2i(16, 0, 17, 33), 4.0)
	var sm0 := slope.build_chunk_mesh(Vector2i(0, 0), 1.0).surface_get_arrays(0)
	var sn0: PackedVector3Array = sm0[Mesh.ARRAY_NORMAL]
	t.check(sn0[16].x < -0.1, "seam normal sees neighbour chunk data")
	ms.setup_splat(4)
	var colored := ms.build_chunk_mesh(Vector2i(1, 1), 1.0).surface_get_arrays(0)
	var cc: PackedColorArray = colored[Mesh.ARRAY_COLOR]
	t.eq(cc.size(), 17 * 17, "splat colours emitted")
