/**************************************************************************/
/*  test_cgame_rendering_data.h                                           */
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

#include "../probe_volume.h"
#include "../sh_lighting.h"
#include "../virtual_shadow_pages.h"
#include "../virtual_texture_page_cache.h"

#include "core/object/callable_mp.h"
#include "tests/test_macros.h"

namespace TestCgameRenderingData {

// ---------------------------------------------------------------- virtual texture

static Ref<Image> vt_provider(int p_mip, int p_px, int p_py) {
	Ref<Image> img = Image::create_empty(8, 8, false, Image::FORMAT_RGBA8);
	img->fill(Color::from_rgba8(p_mip * 40 + 10, p_px * 20, p_py * 20, 255));
	return img;
}

static Ref<VirtualTexturePageCache> make_vt(int p_px, int p_py) {
	Ref<VirtualTexturePageCache> vt;
	vt.instantiate();
	vt->set_provider(callable_mp_static(&vt_provider));
	vt->setup(64, 8, p_px, p_py, 2); // 8x8 pages at mip0, mips 0..3
	return vt;
}

static PackedInt32Array pages(std::initializer_list<int> p_keys) {
	PackedInt32Array a;
	for (int k : p_keys) {
		a.push_back(k);
	}
	return a;
}

static int blue_mip(const Color &p_c) {
	return (int)Math::round(p_c.b * 255.0f);
}

TEST_CASE("[VirtualTexturePageCache] Residency and budget") {
	Ref<VirtualTexturePageCache> vt = make_vt(2, 2);
	CHECK(vt->get_top_mip() == 3);
	CHECK(vt->is_resident(3, 0, 0));
	vt->request_from_feedback(pages({ VirtualTexturePageCache::pack_page(0, 1, 1), VirtualTexturePageCache::pack_page(0, 1, 1),
			VirtualTexturePageCache::pack_page(2, 0, 0), VirtualTexturePageCache::pack_page(0, 5, 5) }));
	CHECK(vt->pending_count() == 3);
	CHECK(vt->update(1) == 1);
	CHECK(vt->is_resident(2, 0, 0));
	CHECK(vt->is_resident(3, 0, 0));
	CHECK(vt->update(10) == 2);
	CHECK(vt->resident_count() == 4);
}

TEST_CASE("[VirtualTexturePageCache] LRU eviction") {
	Ref<VirtualTexturePageCache> v2 = make_vt(2, 2);
	int a = VirtualTexturePageCache::pack_page(0, 0, 0);
	int b = VirtualTexturePageCache::pack_page(0, 1, 0);
	int c = VirtualTexturePageCache::pack_page(0, 2, 0);
	int d = VirtualTexturePageCache::pack_page(0, 3, 0);
	v2->request_from_feedback(pages({ a, b, c }));
	v2->update(8);
	CHECK(v2->resident_count() == 4);
	v2->request_from_feedback(pages({ a, c, d }));
	v2->update(8);
	CHECK(v2->is_resident(0, 3, 0));
	CHECK_FALSE(v2->is_resident(0, 1, 0));
	CHECK(v2->is_resident(0, 0, 0));
	CHECK(v2->is_resident(0, 2, 0));
	CHECK(v2->is_resident(3, 0, 0));
	CHECK(v2->get_stat_evictions() == 1);
	v2->request_from_feedback(pages({ a, c, d, VirtualTexturePageCache::pack_page(0, 4, 0) }));
	v2->update(8);
	CHECK_FALSE(v2->is_resident(0, 4, 0));
	CHECK(v2->is_resident(0, 0, 0));
	CHECK(v2->is_resident(0, 2, 0));
	CHECK(v2->is_resident(0, 3, 0));
}

TEST_CASE("[VirtualTexturePageCache] Indirection, fallback, atlas and stats") {
	Ref<VirtualTexturePageCache> v3 = make_vt(4, 4);
	Ref<Image> ind = v3->indirection_image();
	CHECK(ind->get_width() == 8);
	CHECK(blue_mip(ind->get_pixel(5, 6)) == 3);
	v3->request_from_feedback(pages({ VirtualTexturePageCache::pack_page(1, 2, 3) }));
	v3->update(4);
	CHECK(blue_mip(v3->indirection_image()->get_pixel(4, 6)) == 1);
	CHECK(blue_mip(v3->indirection_image()->get_pixel(0, 0)) == 3);
	v3->request_from_feedback(pages({ VirtualTexturePageCache::pack_page(0, 4, 6) }));
	v3->update(4);
	Color px = v3->indirection_image()->get_pixel(4, 6);
	CHECK(blue_mip(px) == 0);
	Dictionary info = v3->lookup(Vector2(4.5f / 8.0f, 6.5f / 8.0f), 0);
	Vector2i slot = info["slot"];
	CHECK((int)info["resident_mip"] == 0);
	CHECK((int)Math::round(px.r * 255.0f) == slot.x);
	CHECK((int)Math::round(px.g * 255.0f) == slot.y);
	CHECK((int)v3->lookup(Vector2(0.9f, 0.9f), 0)["resident_mip"] == 3);

	int slot_px = 8 + 2 * 2;
	Ref<Image> atlas = v3->physical_atlas();
	Color inner = atlas->get_pixel(slot.x * slot_px + 2 + 3, slot.y * slot_px + 2 + 3);
	CHECK(inner.to_html(false) == Color::from_rgba8(10, 80, 120, 255).to_html(false));
	Color edge = atlas->get_pixel(slot.x * slot_px, slot.y * slot_px);
	CHECK(edge.to_html(false) == inner.to_html(false));
	Dictionary st = v3->stats();
	CHECK((int)st["misses"] == 2);
	CHECK((int)st["hits"] == 0);
	v3->request_from_feedback(pages({ VirtualTexturePageCache::pack_page(0, 4, 6) }));
	CHECK((int)v3->stats()["hits"] == 1);
	CHECK((int)v3->stats()["resident_pages"] == 3);
}

// ---------------------------------------------------------------- SH lighting + probe volume

static bool wall_green = false;
static Dictionary world_trace(const Vector3 &p_o, const Vector3 &p_d) {
	const AABB box(Vector3(1.5, 2.5, 1.5), Vector3(3.0, 1.0, 3.0));
	Dictionary r;
	if (box.has_point(p_o)) {
		r["hit"] = true;
		r["color"] = Color(0, 0, 0);
		r["distance"] = 0.0;
		r["backface"] = true;
		return r;
	}
	float best = Math::INF;
	Color col(0, 0, 0);
	Vector3 hp;
	bool box_inside = false;
	if (box.find_intersects_ray(p_o, p_d, box_inside, &hp)) {
		best = p_o.distance_to(hp);
		col = p_d.y > 0.0f ? Color(0.03, 0.03, 0.03) : Color(0.8, 0.8, 0.8);
	}
	if (p_d.x > 0.001f) {
		float tw = (6.0f - p_o.x) / p_d.x;
		if (tw > 0.0f && tw < best) {
			best = tw;
			col = wall_green ? Color(0, 1, 0) : Color(1, 0, 0);
		}
	}
	if (best == Math::INF) {
		r["hit"] = false;
		return r;
	}
	r["hit"] = true;
	r["color"] = col;
	r["distance"] = best;
	return r;
}

static float lum(const Color &p_c) {
	return p_c.r * 0.3f + p_c.g * 0.6f + p_c.b * 0.1f;
}

TEST_CASE("[SHLighting] Constant radiance gives constant irradiance") {
	const int n = 256;
	float w = 4.0f * (float)Math::PI / (float)n;
	PackedColorArray sh = SHLighting::create();
	for (int i = 0; i < n; i++) {
		sh = SHLighting::accumulate(sh, SHLighting::fibonacci_dir(i, n), Color(0.5f * w, 0.25f * w, 1.0f * w, 0.0f));
	}
	Vector3 normals[4] = { Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(1, 1, 0).normalized(), Vector3(0.3, -0.7, 0.2).normalized() };
	for (const Vector3 &nrm : normals) {
		Color e = SHLighting::evaluate_irradiance(sh, nrm);
		CHECK(e.r == doctest::Approx(0.5).epsilon(0.04));
		CHECK(e.b == doctest::Approx(1.0).epsilon(0.02));
	}
	PackedColorArray one = SHLighting::project_direction(Vector3(0, 1, 0), Color(1, 2, 3));
	CHECK(one[0].r == doctest::Approx(SHLighting::C0).epsilon(0.001));
	CHECK(one[1].g == doctest::Approx(SHLighting::C1 * 2.0).epsilon(0.001));
}

TEST_CASE("[SHLighting] Directional light, ops and rotation") {
	PackedColorArray sky = SHLighting::from_sky(Vector3(0, 1, 0), Color(1, 1, 1), Color(0, 0, 0), Color(0, 0, 0), 64);
	Color toward = SHLighting::evaluate_irradiance(sky, Vector3(0, 1, 0));
	Color away = SHLighting::evaluate_irradiance(sky, Vector3(0, -1, 0));
	Color side = SHLighting::evaluate_irradiance(sky, Vector3(1, 0, 0));
	CHECK(toward.r > 0.8f);
	CHECK(toward.r < 1.3f);
	CHECK(toward.r > side.r);
	CHECK(side.r > away.r - 0.0001f);
	float mn = 1.0f;
	for (int i = 0; i < 200; i++) {
		Color e2 = SHLighting::evaluate_irradiance(sky, SHLighting::fibonacci_dir(i, 200));
		mn = MIN(mn, MIN(e2.r, MIN(e2.g, e2.b)));
	}
	CHECK(mn >= 0.0f);

	PackedColorArray a = SHLighting::from_sky(Vector3(), Color(0, 0, 0), Color(1, 1, 1), Color(1, 1, 1), 32);
	PackedColorArray b2 = SHLighting::scale(a, 0.0f);
	PackedColorArray mid = SHLighting::lerp_sh(a, b2, 0.5f);
	CHECK(SHLighting::evaluate_irradiance(mid, Vector3(0, 1, 0)).r == doctest::Approx(0.5).epsilon(0.04));
	CHECK(SHLighting::evaluate_irradiance(SHLighting::add(a, a), Vector3(0, 1, 0)).r == doctest::Approx(2.0).epsilon(0.04));
	Basis rot(Vector3(0, 0, -1), (float)Math::PI * 0.5f);
	PackedColorArray rotated = SHLighting::rotate(sky, rot);
	CHECK(SHLighting::evaluate_irradiance(rotated, rot.xform(Vector3(0, 1, 0))).r == doctest::Approx(toward.r).epsilon(0.06));
}

static Variant density_left(const Vector3 &p_c) {
	return p_c.x < 4.0f ? 1.0 : 0.0;
}

static Variant density_zero(const Vector3 &p_c) {
	return 0.0;
}

TEST_CASE("[ProbeVolume] Adaptive placement") {
	Ref<ProbeVolume> dense;
	dense.instantiate();
	dense->build(AABB(Vector3(), Vector3(8, 2, 8)), 2.0, callable_mp_static(&density_left));
	int left = 0;
	int right = 0;
	for (int i = 0; i < dense->probe_count(); i++) {
		float px = dense->probe_position(i).x;
		if (px < 3.9f) {
			left++;
		} else if (px > 4.1f) {
			right++;
		}
	}
	CHECK(left > right * 2);
	Ref<ProbeVolume> flat;
	flat.instantiate();
	flat->build(AABB(Vector3(), Vector3(8, 2, 8)), 2.0, callable_mp_static(&density_zero));
	CHECK(flat->probe_count() == 5 * 2 * 5);
	CHECK(dense->probe_count() > flat->probe_count());
}

TEST_CASE("[ProbeVolume] Bake, sampling, streaming and temporal update") {
	wall_green = false;
	Ref<ProbeVolume> vol;
	vol.instantiate();
	vol->build(AABB(Vector3(), Vector3(6, 4, 6)), 1.0, callable_mp_static(&density_zero));
	Callable trace = callable_mp_static(&world_trace);
	vol->bake(trace, 32, 7);
	Color under = vol->sample(Vector3(3, 2, 3), Vector3(0, 1, 0));
	Color open = vol->sample(Vector3(0, 2, 0), Vector3(0, 1, 0));
	CHECK(lum(under) < lum(open) * 0.5f);
	int inside_idx = vol->find_probe(Vector3(3, 3, 3));
	CHECK(inside_idx >= 0);
	CHECK_FALSE(vol->is_probe_valid(inside_idx));
	CHECK(vol->is_probe_valid(vol->find_probe(Vector3(3, 2, 3))));
	Color near_slab = vol->sample(Vector3(3, 2.5f, 3), Vector3(0, 1, 0));
	Color direct = SHLighting::evaluate_irradiance(vol->probe_sh(vol->find_probe(Vector3(3, 2, 3))), Vector3(0, 1, 0));
	CHECK(near_slab.r == doctest::Approx(direct.r).epsilon(0.001));

	// sampling continuity
	Color prev = vol->sample(Vector3(4.6f, 1.5f, 5.2f), Vector3(1, 0, 0));
	float worst = 0.0f;
	float span_total = 0.0f;
	for (int i = 1; i < 131; i++) {
		Color cur = vol->sample(Vector3(4.6f + 0.01f * i, 1.5f, 5.2f), Vector3(1, 0, 0));
		worst = MAX(worst, Math::abs(cur.r - prev.r));
		span_total += Math::abs(cur.r - prev.r);
		prev = cur;
	}
	CHECK(worst < 0.02f);
	CHECK(span_total > 0.0f);

	// streaming
	TypedArray<Vector3i> cells = vol->cells_needed(Vector3(3, 2, 3), 100.0);
	CHECK(cells.size() == 18);
	CHECK(vol->cells_needed(Vector3(0.1f, 0.1f, 0.1f), 0.5f).size() == 1);
	Vector3i cell = cells[0];
	PackedInt32Array ids = vol->cell_probe_ids(cell);
	PackedColorArray before = vol->probe_sh(ids[0]);
	PackedByteArray bytes = vol->unload_cell(cell);
	CHECK_FALSE(vol->is_cell_resident(cell));
	CHECK(vol->probe_sh(ids[0]).is_empty());
	CHECK(vol->load_cell(cell, bytes));
	PackedColorArray after = vol->probe_sh(ids[0]);
	bool same = before.size() == after.size();
	for (int j = 0; j < SHLighting::COEFFS && same; j++) {
		same = before[j] == after[j];
	}
	CHECK(same);
	PackedByteArray junk;
	junk.push_back(1);
	junk.push_back(2);
	junk.push_back(3);
	CHECK_FALSE(vol->load_cell(cell, junk));

	vol->set_memory_budget_bytes(9000);
	for (int i = 0; i < cells.size(); i++) {
		vol->touch_cell(cells[i]);
	}
	Vector3i first = cells[0];
	Vector3i last = cells[cells.size() - 1];
	CHECK(vol->enforce_budget() > 0);
	CHECK(vol->resident_bytes() <= 9000);
	CHECK(vol->is_cell_resident(last));
	CHECK_FALSE(vol->is_cell_resident(first));
	Color fallback = vol->sample(vol->probe_position(vol->cell_probe_ids(first)[0]), Vector3(0, 1, 0));
	CHECK(fallback.r >= 0.0f);
	CHECK(Math::is_finite(fallback.r));
	CHECK(vol->request_cell(first));
	CHECK(vol->is_cell_resident(first));
	CHECK(vol->resident_bytes() <= 9000);
	vol->set_memory_budget_bytes(0);
	for (int i = 0; i < cells.size(); i++) {
		vol->request_cell(cells[i]);
	}

	// temporal update converges to the changed light without snapping
	Vector3 probe_p(5, 2, 5);
	Color red = vol->sample(probe_p, Vector3(1, 0, 0));
	CHECK(red.r > red.g * 3.0f);
	wall_green = true;
	int count = vol->temporal_update(0.5f, trace, 11);
	CHECK(count > 0);
	CHECK(count < vol->probe_count());
	Color half = vol->sample(probe_p, Vector3(1, 0, 0));
	for (int f = 0; f < 23; f++) {
		vol->temporal_update(0.5f, trace, 11);
	}
	Color green = vol->sample(probe_p, Vector3(1, 0, 0));
	CHECK(green.g > green.r * 3.0f);
	CHECK(half.r > green.r);
	wall_green = false;
}

// ---------------------------------------------------------------- virtual shadow pages

static Ref<VirtualShadowPages> make_vsp(int p_pool) {
	Ref<VirtualShadowPages> v;
	v.instantiate();
	// 4 levels, 64m level 0, 128px pages, 1024 virtual -> 8x8 pages per level.
	v->setup(4, 64.0, 128, 1024, p_pool);
	return v;
}

static PackedVector3Array vsp_scene() {
	PackedVector3Array pts;
	for (int i = 0; i < 12; i++) {
		pts.push_back(Vector3((float)i * 3.0f - 16.0f, 0.0f, (float)(i % 4) * 4.0f - 6.0f));
	}
	return pts;
}

static PackedFloat32Array vsp_fp(int p_n, float p_value) {
	PackedFloat32Array a;
	for (int i = 0; i < p_n; i++) {
		a.push_back(p_value);
	}
	return a;
}

static const Vector3 LIGHT(0.0f, -1.0f, 0.0f);

TEST_CASE("[VirtualShadowPages] Level selection and cache reuse") {
	Ref<VirtualShadowPages> v = make_vsp(256);
	v->begin_frame(LIGHT, Vector3());
	CHECK(v->level_for_footprint(0.01f) == 0);
	CHECK(v->level_for_footprint(0.5f) > 0);
	CHECK(v->level_for_footprint(1000.0f) == 3);
	PackedVector3Array pts = vsp_scene();
	v->request_for_receivers(pts, vsp_fp(pts.size(), 0.01f));
	Dictionary fine = v->end_frame();
	Ref<VirtualShadowPages> v2 = make_vsp(256);
	v2->begin_frame(LIGHT, Vector3());
	v2->request_for_receivers(pts, vsp_fp(pts.size(), 0.5f));
	Dictionary coarse = v2->end_frame();
	CHECK((int)fine["allocated"] > (int)coarse["allocated"]);
	CHECK((int)fine["reused"] == 0);
	CHECK((int)fine["rendered"] == (int)fine["allocated"]);

	Ref<VirtualShadowPages> s = make_vsp(256);
	s->begin_frame(LIGHT, Vector3());
	s->request_for_receivers(pts, vsp_fp(pts.size(), 0.02f));
	Dictionary f1 = s->end_frame();
	s->begin_frame(LIGHT, Vector3());
	s->request_for_receivers(pts, vsp_fp(pts.size(), 0.02f));
	Dictionary f2 = s->end_frame();
	CHECK((int)f2["rendered"] == 0);
	CHECK((int)f2["reused"] == (int)f1["allocated"]);
	PackedInt32Array table = s->page_table();
	int mapped = 0;
	for (int e : table) {
		if (e >= 0) {
			mapped++;
		}
	}
	CHECK(mapped == s->resident_count());

	// caster invalidation
	s->begin_frame(LIGHT, Vector3());
	s->request_for_receivers(pts, vsp_fp(pts.size(), 0.02f));
	Array moved;
	moved.push_back(AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2)));
	s->invalidate_casters(moved);
	Dictionary f3 = s->end_frame();
	CHECK((int)f3["rendered"] > 0);
	CHECK((int)f3["rendered"] < (int)f3["requested"]);
	CHECK((int)f3["rendered"] + (int)f3["reused"] == (int)f3["requested"]);
	s->begin_frame(LIGHT, Vector3());
	s->request_for_receivers(pts, vsp_fp(pts.size(), 0.02f));
	CHECK((int)s->end_frame()["rendered"] == 0);
}

TEST_CASE("[VirtualShadowPages] Clipmap recentring and LRU eviction") {
	PackedVector3Array pts = vsp_scene();
	Ref<VirtualShadowPages> r = make_vsp(256);
	r->begin_frame(LIGHT, Vector3());
	r->request_for_receivers(pts, vsp_fp(pts.size(), 0.02f));
	Dictionary g1 = r->end_frame();
	float shift = r->page_world_size(0) * 2.0f;
	r->begin_frame(LIGHT, Vector3(shift + 0.01f, 0.0f, 0.0f));
	r->request_for_receivers(pts, vsp_fp(pts.size(), 0.02f));
	Dictionary g2 = r->end_frame();
	CHECK((int)g2["reused"] > 0);
	CHECK((int)g2["rendered"] == (int)g2["allocated"]);
	CHECK((int)g2["reused"] <= (int)g1["allocated"]);
	CHECK(r->clipmap_center(0).x == 2);

	Ref<VirtualShadowPages> p = make_vsp(6);
	p->begin_frame(LIGHT, Vector3());
	PackedVector3Array line_a;
	PackedVector3Array line_b;
	for (int i = 0; i < 6; i++) {
		line_a.push_back(Vector3((float)i * 8.0f - 15.0f, 0.0f, 1.0f));
		line_b.push_back(Vector3((float)i * 8.0f - 15.0f, 0.0f, 20.0f));
	}
	p->request_for_receivers(line_a, vsp_fp(6, 0.01f));
	Dictionary h1 = p->end_frame();
	CHECK((int)h1["resident"] == 6);
	p->begin_frame(LIGHT, Vector3());
	p->request_for_receivers(line_b, vsp_fp(6, 0.01f));
	Dictionary h2 = p->end_frame();
	CHECK((int)h2["evicted"] == (int)h2["allocated"]);
	CHECK((int)h2["resident"] <= 6);
	CHECK((int)h2["allocated"] > 0);
}


TEST_CASE("[VirtualShadowPages] Active clipmap aliases and deterministic render jobs") {
	Ref<VirtualShadowPages> v;
	v.instantiate();
	v->setup(1, 64.0, 128, 512, 8); // 4 pages per axis.
	PackedVector3Array point;
	point.push_back(Vector3(0, 0, 0));
	v->begin_frame(LIGHT, Vector3());
	CHECK(v->get_render_jobs().is_empty());
	v->request_for_receivers(point, vsp_fp(1, 0.01f));
	Dictionary first = v->end_frame();
	const PackedInt32Array jobs1 = v->get_render_jobs();
	REQUIRE(jobs1.size() == 4);
	CHECK(jobs1[0] == 0); // level
	CHECK(jobs1[1] == 0); // global page X
	CHECK(jobs1[2] == 0); // global page Y
	CHECK((int)first["rendered"] == jobs1.size() / 4);
	CHECK(v->page_table()[0] == jobs1[3]);
	const int old_slot = jobs1[3];

	// Keep the original page cached while walking one WHOLE clipmap width.
	// Both pages alias index (gx mod N)==0, but only the current one may
	// appear in the GPU indirection table.
	const real_t shift = v->page_world_size(0) * 4.0;
	v->begin_frame(LIGHT, Vector3(shift, 0, 0));
	CHECK(v->get_render_jobs().is_empty());
	point.set(0, Vector3(shift, 0, 0));
	v->request_for_receivers(point, vsp_fp(1, 0.01f));
	Dictionary second = v->end_frame();
	const PackedInt32Array jobs2 = v->get_render_jobs();
	REQUIRE(jobs2.size() == 4);
	CHECK(jobs2[0] == 0);
	CHECK(jobs2[1] == 4);
	CHECK(jobs2[2] == 0);
	CHECK(jobs2[3] != old_slot);
	CHECK((int)second["allocated"] == 1);
	CHECK(v->is_resident(0, 0, 0)); // Old page retained for future reuse.
	CHECK(v->is_resident(0, 4, 0));
	CHECK(v->resident_count() == 2);
	CHECK(v->page_table()[0] == jobs2[3]); // Never let old page overwrite new one.

	v->begin_frame(LIGHT, Vector3(shift, 0, 0));
	v->request_for_receivers(point, vsp_fp(1, 0.01f));
	CHECK((int)v->end_frame()["rendered"] == 0);
	CHECK(v->get_render_jobs().is_empty());
	Array moved;
	moved.push_back(AABB(Vector3(shift - 1.0, -1.0, -1.0), Vector3(2, 2, 2)));
	v->begin_frame(LIGHT, Vector3(shift, 0, 0));
	v->request_for_receivers(point, vsp_fp(1, 0.01f));
	v->invalidate_casters(moved);
	CHECK((int)v->end_frame()["rendered"] == 1);
	const PackedInt32Array rerender = v->get_render_jobs();
	REQUIRE(rerender.size() == 4);
	CHECK(rerender[3] == jobs2[3]); // Dirty re-render uses the existing slot.

	// Single-page clipmap must accept its centre (legacy half=0 skipped all).
	v->setup(1, 16.0, 128, 128, 1);
	v->begin_frame(LIGHT, Vector3());
	point.set(0, Vector3(0, 0, 0));
	v->request_for_receivers(point, vsp_fp(1, 0.01f));
	CHECK((int)v->end_frame()["allocated"] == 1);
	CHECK(v->page_table().size() == 1);
	CHECK(v->page_table()[0] == 0);

	// An odd-sized 3x3 clipmap must accept all three X columns.
	v->setup(1, 48.0, 128, 384, 9);
	v->begin_frame(LIGHT, Vector3());
	const real_t pw = v->page_world_size(0);
	PackedVector3Array three;
	three.push_back(Vector3(-pw, 0, 0));
	three.push_back(Vector3(0, 0, 0));
	three.push_back(Vector3(pw, 0, 0));
	v->request_for_receivers(three, vsp_fp(3, 0.01f));
	CHECK((int)v->end_frame()["allocated"] == 3);
	CHECK(v->get_render_jobs().size() == 12);
}

} //namespace TestCgameRenderingData
