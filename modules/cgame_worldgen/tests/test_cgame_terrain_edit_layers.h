/**************************************************************************/
/*  test_cgame_terrain_edit_layers.h                                      */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "../cgame_terrain_edit_layers.h"

#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

// Mirrors tests/test_terrain_edit_layers.gd: brushes, non-destructive layers, splat, undo,
// dirty chunks, collision queue, chunk export/mesh, plus the public per-texel delta API.
namespace TestCgameTerrainEditLayers {

typedef CgameTerrainEditLayers TEL;

static Ref<TEL> make_terrain(int p_w, int p_h, int p_cs, float p_base_h = 0.0f) {
	PackedFloat32Array base;
	base.resize(p_w * p_h);
	base.fill(p_base_h);
	Ref<TEL> ter;
	ter.instantiate();
	ter->setup(p_w, p_h, p_cs, base);
	return ter;
}

static double variance_of(const PackedFloat32Array &p_a) {
	double mean = 0.0;
	for (int i = 0; i < p_a.size(); i++) {
		mean += p_a[i];
	}
	mean /= (double)p_a.size();
	double s = 0.0;
	for (int i = 0; i < p_a.size(); i++) {
		s += ((double)p_a[i] - mean) * ((double)p_a[i] - mean);
	}
	return s / (double)p_a.size();
}

static bool same_array(const PackedFloat32Array &p_a, const PackedFloat32Array &p_b) {
	if (p_a.size() != p_b.size()) {
		return false;
	}
	for (int i = 0; i < p_a.size(); i++) {
		if (p_a[i] != p_b[i]) {
			return false;
		}
	}
	return true;
}

static bool near_value(double p_a, double p_b, double p_tol = 0.0001) {
	return Math::abs(p_a - p_b) <= p_tol;
}

static bool has_chunk(const TypedArray<Vector2i> &p_chunks, const Vector2i &p_c) {
	for (int i = 0; i < p_chunks.size(); i++) {
		if ((Vector2i)p_chunks[i] == p_c) {
			return true;
		}
	}
	return false;
}

TEST_CASE("[CgameTerrainEditLayers] Brush radius and falloff") {
	Ref<TEL> ter = make_terrain(33, 33, 16);
	const int l = ter->add_layer("sculpt");
	(void)ter->apply_brush(l, TEL::BRUSH_RAISE, Vector2(16, 16), 4.0, 2.0, TEL::FALLOFF_CONSTANT);
	CHECK_MESSAGE(near_value(ter->composite_height(16, 16), 2.0), "centre raised");
	CHECK_MESSAGE(near_value(ter->composite_height(18, 16), 2.0), "inside radius raised");
	CHECK_MESSAGE(ter->composite_height(21, 16) == 0.0, "outside radius untouched");
	CHECK_MESSAGE(ter->composite_height(0, 0) == 0.0, "far corner untouched");

	Ref<TEL> soft = make_terrain(33, 33, 16);
	const int sl = soft->add_layer("s");
	(void)soft->apply_brush(sl, TEL::BRUSH_RAISE, Vector2(16, 16), 6.0, 3.0, TEL::FALLOFF_LINEAR);
	CHECK_MESSAGE(soft->composite_height(16, 16) > soft->composite_height(19, 16), "falloff decreases with distance");

	(void)ter->apply_brush(l, TEL::BRUSH_LOWER, Vector2(16, 16), 4.0, 1.0, TEL::FALLOFF_CONSTANT);
	CHECK_MESSAGE(near_value(ter->composite_height(16, 16), 1.0), "lower brush reduces");
}

TEST_CASE("[CgameTerrainEditLayers] Non destructive layers") {
	Ref<TEL> nd = make_terrain(17, 17, 16, 5.0f);
	const int la = nd->add_layer("a");
	(void)nd->apply_brush(la, TEL::BRUSH_RAISE, Vector2(8, 8), 3.0, 4.0, TEL::FALLOFF_CONSTANT);
	CHECK_MESSAGE(near_value(nd->composite_height(8, 8), 9.0), "raised over base");
	nd->set_layer_visible(la, false);
	CHECK_MESSAGE(nd->composite_height(8, 8) == 5.0, "hiding restores base");
	nd->set_layer_visible(la, true);
	CHECK_MESSAGE(near_value(nd->composite_height(8, 8), 9.0), "showing brings edit back");
	nd->set_layer_opacity(la, 0.5);
	CHECK_MESSAGE(near_value(nd->composite_height(8, 8), 7.0), "opacity scales add layer");
	nd->set_layer_opacity(la, 1.0);
	CHECK_MESSAGE(near_value(nd->composite_height(8, 8), 9.0), "opacity restored");
}

TEST_CASE("[CgameTerrainEditLayers] Layer order and blend modes") {
	Ref<TEL> ob = make_terrain(9, 9, 8, 0.0f);
	const int add_l = ob->add_layer("add", TEL::BLEND_ADD);
	const int rep_l = ob->add_layer("rep", TEL::BLEND_REPLACE);
	ob->fill_layer_rect(add_l, Rect2i(0, 0, 9, 9), 3.0);
	ob->fill_layer_rect(rep_l, Rect2i(0, 0, 9, 9), 1.0, 1.0);
	CHECK_MESSAGE(near_value(ob->composite_height(4, 4), 1.0), "replace on top overrides add");
	ob->move_layer(rep_l, 0);
	CHECK_MESSAGE(ob->layer_ids()[0] == rep_l, "reorder moves layer to bottom");
	CHECK_MESSAGE(near_value(ob->composite_height(4, 4), 4.0), "add on top of replace stacks");
	ob->set_layer_blend(add_l, TEL::BLEND_MAX);
	CHECK_MESSAGE(near_value(ob->composite_height(4, 4), 3.0), "max keeps the higher candidate");
	ob->set_layer_blend(add_l, TEL::BLEND_ADD);
	ob->fill_layer_rect(rep_l, Rect2i(0, 0, 9, 9), 1.0, 0.5);
	CHECK_MESSAGE(near_value(ob->composite_height(4, 4), 1.0 * 0.5 + 3.0), "replace alpha blends");
	CHECK_MESSAGE(ob->remove_layer(rep_l), "remove layer ok");
	CHECK(ob->layer_count() == 1);
	CHECK_MESSAGE(near_value(ob->composite_height(4, 4), 3.0), "removing layer drops its edit");
	CHECK_FALSE(ob->remove_layer(9999));
}

TEST_CASE("[CgameTerrainEditLayers] Smooth, flatten and erode brushes") {
	Ref<TEL> sm = make_terrain(33, 33, 16);
	const int nl = sm->add_layer("noise");
	(void)sm->apply_brush(nl, TEL::BRUSH_NOISE, Vector2(16, 16), 10.0, 4.0, TEL::FALLOFF_CONSTANT, 0.0, 7);
	const Rect2i region(8, 8, 17, 17);
	const double before = variance_of(sm->composite_region(region));
	CHECK_MESSAGE(before > 0.1, "noise adds variance");
	for (int i = 0; i < 4; i++) {
		(void)sm->apply_brush(nl, TEL::BRUSH_SMOOTH, Vector2(16, 16), 12.0, 1.0, TEL::FALLOFF_CONSTANT);
	}
	CHECK_MESSAGE(variance_of(sm->composite_region(region)) < before * 0.5, "smooth reduces variance");
	(void)sm->apply_brush(nl, TEL::BRUSH_FLATTEN, Vector2(16, 16), 6.0, 1.0, TEL::FALLOFF_CONSTANT, 2.5);
	CHECK_MESSAGE(near_value(sm->composite_height(16, 16), 2.5), "flatten hits target at centre");
	CHECK_MESSAGE(near_value(sm->composite_height(14, 17), 2.5), "flatten hits target inside radius");

	Ref<TEL> er = make_terrain(17, 17, 16);
	const int el = er->add_layer("e");
	er->fill_layer_rect(el, Rect2i(8, 8, 1, 1), 10.0);
	(void)er->apply_brush(el, TEL::BRUSH_ERODE, Vector2(8, 8), 2.0, 3.0, TEL::FALLOFF_CONSTANT);
	CHECK_MESSAGE(er->composite_height(8, 8) < 10.0, "erode lowers a spike");
}

TEST_CASE("[CgameTerrainEditLayers] Splat painting") {
	Ref<TEL> sp = make_terrain(17, 17, 8);
	sp->setup_splat(4);
	CHECK_MESSAGE(sp->splat_weights(3, 3)[0] == 1.0f, "default material is layer 0");
	(void)sp->paint_splat(2, Vector2(8, 8), 3.0, 0.6, TEL::FALLOFF_CONSTANT);
	(void)sp->paint_splat(1, Vector2(8, 8), 3.0, 0.3, TEL::FALLOFF_CONSTANT);
	bool all_ok = true;
	for (int y = 0; y < 17; y++) {
		for (int x = 0; x < 17; x++) {
			const PackedFloat32Array w = sp->splat_weights(x, y);
			const double sum = (double)w[0] + w[1] + w[2] + w[3];
			if (Math::abs(sum - 1.0) > 0.0001) {
				all_ok = false;
			}
			for (int k = 0; k < 4; k++) {
				if (w[k] < -0.0001f || w[k] > 1.0001f) {
					all_ok = false;
				}
			}
		}
	}
	CHECK_MESSAGE(all_ok, "weights normalised to 1 everywhere");
	CHECK_MESSAGE(near_value(sp->splat_weights(8, 8)[2], 0.6 * 0.7), "earlier paint scaled by later paint");
	CHECK_MESSAGE(sp->splat_weights(0, 0)[0] == 1.0f, "outside brush unchanged");
	(void)sp->paint_splat(3, Vector2(8, 8), 3.0, 5.0, TEL::FALLOFF_CONSTANT);
	CHECK_MESSAGE(near_value(sp->splat_weights(8, 8)[3], 1.0), "strong paint saturates");
	CHECK_MESSAGE(sp->undo(), "splat undo");
	CHECK_MESSAGE(near_value(sp->splat_weights(8, 8)[3], 0.0), "splat undo restores weights");
}

TEST_CASE("[CgameTerrainEditLayers] Undo, redo and bounded history") {
	Ref<TEL> ur = make_terrain(33, 33, 16);
	const int ul = ur->add_layer("u");
	const Rect2i all(0, 0, 33, 33);
	const PackedFloat32Array snap0 = ur->composite_region(all);
	(void)ur->apply_brush(ul, TEL::BRUSH_RAISE, Vector2(10, 10), 5.0, 3.0);
	(void)ur->apply_brush(ul, TEL::BRUSH_NOISE, Vector2(12, 11), 6.0, 2.0, TEL::FALLOFF_SMOOTH, 0.0, 3);
	const PackedFloat32Array snap2 = ur->composite_region(all);
	CHECK_MESSAGE((ur->can_undo() && !ur->can_redo()), "history state after edits");
	CHECK_MESSAGE((ur->undo() && ur->undo()), "two undos");
	CHECK_MESSAGE(same_array(ur->composite_region(all), snap0), "undo restores exactly");
	CHECK_MESSAGE((!ur->can_undo() && ur->can_redo()), "history state after undo");
	CHECK_MESSAGE((ur->redo() && ur->redo()), "two redos");
	CHECK_MESSAGE(same_array(ur->composite_region(all), snap2), "redo restores exactly");
	ur->undo();
	(void)ur->apply_brush(ul, TEL::BRUSH_RAISE, Vector2(20, 20), 3.0, 1.0);
	CHECK_MESSAGE(!ur->can_redo(), "new edit clears redo");

	Ref<TEL> mem = make_terrain(65, 65, 16);
	const int ml = mem->add_layer("m");
	mem->set_max_undo_bytes(20000);
	for (int i = 0; i < 200; i++) {
		(void)mem->apply_brush(ml, TEL::BRUSH_RAISE, Vector2(10 + (i % 40), 20), 6.0, 0.1);
	}
	CHECK_MESSAGE(mem->undo_bytes() <= 20000, "undo memory bounded");
	CHECK_MESSAGE((mem->undo_depth() > 1 && mem->undo_depth() < 200), "oldest strokes dropped");

	Ref<TEL> tiny = make_terrain(65, 65, 16);
	const int tl = tiny->add_layer("t");
	(void)tiny->apply_brush(tl, TEL::BRUSH_RAISE, Vector2(30, 30), 3.0, 1.0);
	const int64_t one_stroke = tiny->undo_bytes();
	CHECK_MESSAGE((one_stroke > 0 && one_stroke < 2000), "stroke stores only its rect");
}

TEST_CASE("[CgameTerrainEditLayers] Dirty chunks") {
	Ref<TEL> dc = make_terrain(65, 65, 16);
	const int dl = dc->add_layer("d");
	CHECK_MESSAGE(dc->take_dirty_chunks().size() == 16, "setup marks everything dirty once");
	CHECK_MESSAGE(dc->take_dirty_chunks().size() == 0, "cleared after taking");
	(void)dc->apply_brush(dl, TEL::BRUSH_RAISE, Vector2(24, 24), 3.0, 1.0);
	const TypedArray<Vector2i> d1 = dc->take_dirty_chunks();
	CHECK_MESSAGE(d1.size() == 1, "interior edit touches one chunk");
	CHECK_MESSAGE((Vector2i)d1[0] == Vector2i(1, 1), "correct chunk");
	(void)dc->apply_brush(dl, TEL::BRUSH_RAISE, Vector2(16, 16), 2.0, 1.0);
	const TypedArray<Vector2i> d2 = dc->take_dirty_chunks();
	CHECK_MESSAGE(d2.size() == 4, "seam corner edit touches four chunks");
	CHECK_MESSAGE((has_chunk(d2, Vector2i(0, 0)) && has_chunk(d2, Vector2i(1, 1)) && has_chunk(d2, Vector2i(0, 1)) && has_chunk(d2, Vector2i(1, 0))), "all seam neighbours present");
	(void)dc->apply_brush(dl, TEL::BRUSH_RAISE, Vector2(8, 24), 2.0, 1.0);
	CHECK_MESSAGE(dc->take_dirty_chunks().size() == 1, "edit in chunk centre stays local");
	dc->set_layer_visible(dl, false);
	CHECK_MESSAGE(dc->take_dirty_chunks().size() >= 1, "toggling visibility dirties affected chunks");
}

TEST_CASE("[CgameTerrainEditLayers] Collision job queue") {
	Ref<TEL> cj = make_terrain(65, 65, 16);
	const int cl = cj->add_layer("c");
	cj->collision_jobs(100);
	CHECK_MESSAGE(cj->pending_collision_count() == 0, "queue drained");
	(void)cj->apply_brush(cl, TEL::BRUSH_RAISE, Vector2(8, 8), 2.0, 1.0);
	(void)cj->apply_brush(cl, TEL::BRUSH_RAISE, Vector2(9, 8), 2.0, 1.0);
	(void)cj->apply_brush(cl, TEL::BRUSH_RAISE, Vector2(16, 40), 2.0, 1.0);
	(void)cj->apply_brush(cl, TEL::BRUSH_RAISE, Vector2(40, 40), 2.0, 1.0);
	const int total = cj->pending_collision_count();
	CHECK_MESSAGE(total == 4, "repeated edits dedupe to four pending chunks");
	HashMap<Vector2i, int> seen;
	int batches = 0;
	int max_batch = 0;
	while (cj->pending_collision_count() > 0) {
		const TypedArray<Vector2i> batch = cj->collision_jobs(2);
		batches++;
		max_batch = MAX(max_batch, (int)batch.size());
		for (int i = 0; i < batch.size(); i++) {
			const Vector2i c = batch[i];
			seen[c] = seen.has(c) ? seen[c] + 1 : 1;
		}
	}
	CHECK_MESSAGE(max_batch <= 2, "per-frame limit respected");
	CHECK_MESSAGE(batches == (int)Math::ceil((double)total / 2.0), "work spread across frames");
	bool dup = false;
	for (const KeyValue<Vector2i, int> &kv : seen) {
		if (kv.value > 1) {
			dup = true;
		}
	}
	CHECK_MESSAGE(!dup, "chunks deduped in queue");
	CHECK_MESSAGE((int)seen.size() == total, "every pending chunk yielded once");
	(void)cj->apply_brush(cl, TEL::BRUSH_RAISE, Vector2(8, 8), 2.0, 1.0);
	CHECK_MESSAGE(cj->collision_jobs(0).is_empty(), "zero budget yields nothing");
	CHECK_MESSAGE(has_chunk(cj->collision_jobs(8), Vector2i(0, 0)), "re-dirtied chunk is requeued");
}

TEST_CASE("[CgameTerrainEditLayers] Chunk export and mesh") {
	Ref<TEL> ex = make_terrain(33, 33, 16);
	const int xl = ex->add_layer("x");
	(void)ex->apply_brush(xl, TEL::BRUSH_NOISE, Vector2(16, 16), 20.0, 5.0, TEL::FALLOFF_CONSTANT, 0.0, 11);
	const PackedFloat32Array h00 = ex->export_chunk_heights(Vector2i(0, 0));
	const PackedFloat32Array h10 = ex->export_chunk_heights(Vector2i(1, 0));
	CHECK_MESSAGE(h00.size() == 19 * 19, "export has 1 texel border");
	bool seam_ok = true;
	for (int j = 0; j < 19; j++) {
		if (Math::abs(h00[j * 19 + 17] - h10[j * 19 + 1]) > 0.00001f) {
			seam_ok = false;
		}
		if (Math::abs(h00[j * 19 + 18] - h10[j * 19 + 2]) > 0.00001f) {
			seam_ok = false;
		}
	}
	CHECK_MESSAGE(seam_ok, "border matches neighbour data");
	CHECK_MESSAGE(near_value(h00[1 * 19 + 1 + 16], ex->composite_height(16, 0), 0.00001), "export texel matches composite");
	CHECK_MESSAGE(ex->export_chunk_heights(Vector2i(5, 5)).size() == 0, "invalid chunk exports nothing");

	Ref<TEL> ms = make_terrain(33, 33, 16);
	Ref<ArrayMesh> mm = ms->build_chunk_mesh(Vector2i(0, 0), 2.0);
	CHECK_MESSAGE(mm->get_surface_count() == 1, "one surface");
	const Array arrays = mm->surface_get_arrays(0);
	const PackedVector3Array mv = arrays[Mesh::ARRAY_VERTEX];
	const PackedInt32Array mi = arrays[Mesh::ARRAY_INDEX];
	CHECK_MESSAGE(mv.size() == 17 * 17, "vertex count (cs+1)^2");
	CHECK_MESSAGE(mi.size() == 16 * 16 * 6, "index count");
	CHECK_MESSAGE(near_value(mv[mv.size() - 1].x, 32.0), "cell size applied");
	const PackedVector3Array mn = arrays[Mesh::ARRAY_NORMAL];
	CHECK_MESSAGE(near_value(mn[0].y, 1.0), "flat terrain normal points up");

	Ref<TEL> slope = make_terrain(33, 33, 16);
	const int sll = slope->add_layer("ramp");
	slope->fill_layer_rect(sll, Rect2i(16, 0, 17, 33), 4.0);
	const Array sm0 = slope->build_chunk_mesh(Vector2i(0, 0), 1.0)->surface_get_arrays(0);
	const PackedVector3Array sn0 = sm0[Mesh::ARRAY_NORMAL];
	CHECK_MESSAGE(sn0[16].x < -0.1f, "seam normal sees neighbour chunk data");

	ms->setup_splat(4);
	const Array colored = ms->build_chunk_mesh(Vector2i(1, 1), 1.0)->surface_get_arrays(0);
	const PackedColorArray cc = colored[Mesh::ARRAY_COLOR];
	CHECK_MESSAGE(cc.size() == 17 * 17, "splat colours emitted");
}

TEST_CASE("[CgameTerrainEditLayers] Public per-texel delta API replaces private field access") {
	Ref<TEL> ter = make_terrain(33, 33, 16, 2.0f);
	ter->take_dirty_chunks();
	const int id = ter->add_layer("paint", TEL::BLEND_ADD);

	CHECK(ter->set_layer_texel(id, 5, 6, 3.0, 1.0));
	CHECK(near_value(ter->layer_delta_at(id, 5, 6), 3.0));
	CHECK(near_value(ter->layer_alpha_at(id, 5, 6), 1.0));
	CHECK(near_value(ter->composite_height(5, 6), 5.0));
	CHECK(near_value(ter->composite_height(6, 6), 2.0));
	CHECK(ter->get_layer_bounds(id) == Rect2i(5, 6, 1, 1));
	CHECK_MESSAGE(ter->take_dirty_chunks().size() >= 1, "texel write dirties chunks");
	CHECK_FALSE(ter->set_layer_texel(id, -1, 0, 1.0));
	CHECK_FALSE(ter->set_layer_texel(id, 33, 0, 1.0));
	CHECK_FALSE(ter->set_layer_texel(12345, 0, 0, 1.0));

	// Bulk write / read of a region (what the terrain panel used to do through private fields).
	const Rect2i r(10, 12, 3, 2);
	PackedFloat32Array deltas;
	PackedFloat32Array alphas;
	for (int i = 0; i < 6; i++) {
		deltas.push_back((float)(i + 1));
		alphas.push_back(0.5f);
	}
	CHECK(ter->write_layer_region(id, r, deltas, alphas));
	CHECK(near_value(ter->layer_delta_at(id, 10, 12), 1.0));
	CHECK(near_value(ter->layer_delta_at(id, 12, 13), 6.0));
	CHECK(same_array(ter->get_layer_region_deltas(id, r), deltas));
	CHECK(same_array(ter->get_layer_region_alphas(id, r), alphas));
	CHECK(ter->get_layer_bounds(id) == Rect2i(5, 6, 8, 8));

	// Wrong sizes and out-of-map rectangles are rejected without side effects.
	CHECK_FALSE(ter->write_layer_region(id, r, PackedFloat32Array(), alphas));
	CHECK_FALSE(ter->write_layer_region(id, Rect2i(31, 31, 3, 3), deltas, alphas));
	CHECK(near_value(ter->layer_delta_at(id, 12, 13), 6.0));

	// Creating a layer from region data in one call.
	const int filled = ter->add_layer_from_region("filled", r, deltas, alphas);
	CHECK(filled > id);
	CHECK(near_value(ter->layer_delta_at(filled, 11, 12), 2.0));
	CHECK(ter->get_layer_name(filled) == "filled");
	ter->set_layer_name(filled, "renamed");
	CHECK(ter->get_layer_name(filled) == "renamed");
	CHECK(ter->get_layer_blend(filled) == TEL::BLEND_ADD);
	CHECK(near_value(ter->get_layer_opacity(filled), 1.0));
	CHECK(ter->has_layer(filled));
	CHECK_FALSE(ter->has_layer(777));

	// Texel writes are not on the undo stack; brush strokes still are.
	const int depth = ter->undo_depth();
	ter->set_layer_texel(id, 1, 1, 1.0);
	CHECK(ter->undo_depth() == depth);
}

} // namespace TestCgameTerrainEditLayers
