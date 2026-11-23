/**************************************************************************/
/*  test_cgame_raytrace.h                                                 */
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

#include "../cgame_bvh.h"
#include "../cgame_path_tracer.h"

#include "core/math/random_number_generator.h"
#include "tests/test_macros.h"

namespace TestCgameRaytrace {

static void _quad(PackedVector3Array &r_tris, const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c, const Vector3 &p_d) {
	r_tris.push_back(p_a);
	r_tris.push_back(p_b);
	r_tris.push_back(p_c);
	r_tris.push_back(p_a);
	r_tris.push_back(p_c);
	r_tris.push_back(p_d);
}

// Floor y=0 (20x20), optional wall at x=0 (z -10..10, y 0..4).
static PackedVector3Array _floor_scene(bool p_with_wall) {
	PackedVector3Array tris;
	_quad(tris, Vector3(-10, 0, -10), Vector3(-10, 0, 10), Vector3(10, 0, 10), Vector3(10, 0, -10));
	if (p_with_wall) {
		_quad(tris, Vector3(0, 0, -10), Vector3(0, 4, -10), Vector3(0, 4, 10), Vector3(0, 0, 10));
	}
	return tris;
}

// Floor plus a 6x6 plate hovering at y=1.
static PackedVector3Array _plate_scene() {
	PackedVector3Array tris = _floor_scene(false);
	_quad(tris, Vector3(-3, 1, -3), Vector3(-3, 1, 3), Vector3(3, 1, 3), Vector3(3, 1, -3));
	return tris;
}

static PackedVector3Array _up(int p_n) {
	PackedVector3Array arr;
	arr.resize(p_n);
	arr.fill(Vector3(0, 1, 0));
	return arr;
}

static PackedColorArray _grey_albedo(int p_n) {
	PackedColorArray alb;
	for (int i = 0; i < p_n; i++) {
		alb.push_back(Color(0.8f, 0.8f, 0.8f));
	}
	return alb;
}

// Independent reference: brute-force Moller-Trumbore over every triangle.
static float _brute(const PackedVector3Array &p_tris, const Vector3 &p_o, const Vector3 &p_d, float p_t_max) {
	float best = Math::INF;
	for (int i = 0; i < p_tris.size() / 3; i++) {
		const Vector3 v0 = p_tris[i * 3];
		const Vector3 e1 = p_tris[i * 3 + 1] - v0;
		const Vector3 e2 = p_tris[i * 3 + 2] - v0;
		const Vector3 pv = p_d.cross(e2);
		const float det = e1.dot(pv);
		if (Math::abs(det) < 0.000000000001f) {
			continue;
		}
		const float inv = 1.0f / det;
		const Vector3 tv = p_o - v0;
		const float u = tv.dot(pv) * inv;
		if (u < 0.0f || u > 1.0f) {
			continue;
		}
		const Vector3 qv = tv.cross(e1);
		const float v = p_d.dot(qv) * inv;
		if (v < 0.0f || u + v > 1.0f) {
			continue;
		}
		const float t = e2.dot(qv) * inv;
		if (t > CgameBVH::T_MIN && t < p_t_max && t < best) {
			best = t;
		}
	}
	return best;
}

TEST_CASE("[CgameBVH] Matches brute force on random rays") {
	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed(1234);

	PackedVector3Array soup;
	for (int i = 0; i < 150; i++) {
		const Vector3 c(rng->randf_range(-8, 8), rng->randf_range(-8, 8), rng->randf_range(-8, 8));
		for (int k = 0; k < 3; k++) {
			soup.push_back(c + Vector3(rng->randf_range(-3, 3), rng->randf_range(-3, 3), rng->randf_range(-3, 3)));
		}
	}
	Ref<CgameBVH> bvh;
	bvh.instantiate();
	bvh->build(soup);

	int mismatches = 0;
	int anyhit_mismatch = 0;
	int hits = 0;
	for (int r = 0; r < 250; r++) {
		const Vector3 o(rng->randf_range(-12, 12), rng->randf_range(-12, 12), rng->randf_range(-12, 12));
		const Vector3 d = Vector3(rng->randf_range(-1, 1), rng->randf_range(-1, 1), rng->randf_range(-1, 1)).normalized();
		const float t_max = rng->randf_range(2.0, 30.0);
		const float want = _brute(soup, o, d, t_max);
		const Dictionary got = bvh->intersect(o, d, t_max);
		const bool got_hit = got["hit"];
		const float got_t = got["t"];
		if (got_hit != (want < Math::INF) || (got_hit && Math::abs(got_t - want) > 0.0001f)) {
			mismatches++;
		}
		if (got_hit) {
			hits++;
		}
		if (bvh->occluded(o, d, t_max) != (want < Math::INF)) {
			anyhit_mismatch++;
		}
	}
	CHECK_MESSAGE(mismatches == 0, "Closest hit equals brute force.");
	CHECK_MESSAGE(anyhit_mismatch == 0, "Any-hit equals brute force.");
	CHECK_MESSAGE(hits > 10, "Random rays hit geometry.");

	const Dictionary st = bvh->get_stats();
	CHECK(int(st["triangles"]) == 150);
	CHECK(int(st["nodes"]) > 1);
	CHECK(int(st["leaves"]) > 1);
	CHECK(float(st["avg_leaf_size"]) <= float(CgameBVH::FORCE_SPLIT));
	CHECK(float(st["sah_cost"]) > 0.0f);
}

TEST_CASE("[CgameBVH] Empty hierarchy never hits") {
	Ref<CgameBVH> bvh;
	bvh.instantiate();
	bvh->build(PackedVector3Array());
	const Dictionary none = bvh->intersect(Vector3(), Vector3(0, 1, 0));
	CHECK_FALSE(bool(none["hit"]));
	CHECK_FALSE(bvh->occluded(Vector3(), Vector3(0, 1, 0)));
	CHECK(bvh->get_triangle_count() == 0);
}

TEST_CASE("[CgameBVH] Hit record") {
	Ref<CgameBVH> fl;
	fl.instantiate();
	fl->build(_floor_scene(false));
	const Dictionary hd = fl->intersect(Vector3(1, 5, 1), Vector3(0, -1, 0));
	CHECK(bool(hd["hit"]));
	CHECK(Math::abs(float(hd["t"]) - 5.0f) < 0.0001f);
	const Vector3 hn = hd["normal"];
	CHECK(hn.dot(Vector3(0, 1, 0)) > 0.99f);
	const Dictionary miss = fl->intersect(Vector3(1, 5, 1), Vector3(0, 1, 0));
	CHECK_FALSE(bool(miss["hit"]));
	CHECK_FALSE(fl->occluded(Vector3(1, 5, 1), Vector3(0, -1, 0), 3.0f));
	CHECK(fl->occluded(Vector3(1, 5, 1), Vector3(0, -1, 0), 6.0f));
}

TEST_CASE("[CgamePathTracer] Ambient occlusion: corner darker than open floor") {
	Ref<CgameBVH> corner;
	corner.instantiate();
	corner->build(_floor_scene(true));
	PackedVector3Array pts;
	pts.push_back(Vector3(0.2f, 0, 0));
	pts.push_back(Vector3(8, 0, 0));
	const PackedFloat32Array ao = CgamePathTracer::bake_ambient_occlusion(corner, pts, _up(2), 64, 3.0f, 5);
	REQUIRE(ao.size() == 2);
	CHECK(ao[0] < ao[1] - 0.2f);
	CHECK(ao[1] > 0.95f);
}

TEST_CASE("[CgamePathTracer] Vertex lighting: shadow, bounce and sky") {
	Ref<CgameBVH> scene;
	scene.instantiate();
	scene->build(_plate_scene());
	const PackedColorArray alb = _grey_albedo(4);
	PackedVector3Array verts;
	verts.push_back(Vector3(7, 0, 0));
	verts.push_back(Vector3(0, 0, 0));
	verts.push_back(Vector3(0, 0, 1));
	const Vector3 sun_dir(0, -1, 0);
	const Color dark(0, 0, 0);
	const Color white(1, 1, 1);

	const PackedColorArray lit = CgamePathTracer::bake_vertex_lighting(scene, verts, _up(3), alb, sun_dir, white, dark, 4, 0, 9);
	REQUIRE(lit.size() == 3);
	CHECK(Math::abs(lit[0].r - 0.8f) < 0.01f);
	CHECK(Math::abs(lit[1].r) < 0.0001f);

	const PackedColorArray bounced = CgamePathTracer::bake_vertex_lighting(scene, verts, _up(3), alb, sun_dir, white, dark, 400, 3, 9);
	CHECK(bounced[1].r > 0.003f);
	CHECK(bounced[1].r < lit[0].r);

	const PackedColorArray sky_lit = CgamePathTracer::bake_vertex_lighting(scene, verts, _up(3), alb, sun_dir, dark, white, 64, 0, 9);
	CHECK(sky_lit[0].r > 0.7f);
	CHECK(sky_lit[1].r < sky_lit[0].r);
}

TEST_CASE("[CgamePathTracer] Determinism per seed") {
	Ref<CgameBVH> scene;
	scene.instantiate();
	scene->build(_plate_scene());
	const PackedColorArray alb = _grey_albedo(4);
	PackedVector3Array verts;
	for (int i = 0; i < 24; i++) {
		verts.push_back(Vector3(float(i) * 0.3f - 3.0f, 0, 0.5f));
	}
	const Color sun(1, 1, 1);
	const Color sky(0.3f, 0.4f, 0.5f);
	const Vector3 sd(0, -1, 0);
	const PackedColorArray a = CgamePathTracer::bake_vertex_lighting(scene, verts, _up(24), alb, sd, sun, sky, 16, 2, 77);
	const PackedColorArray b = CgamePathTracer::bake_vertex_lighting(scene, verts, _up(24), alb, sd, sun, sky, 16, 2, 77);
	const PackedColorArray c = CgamePathTracer::bake_vertex_lighting(scene, verts, _up(24), alb, sd, sun, sky, 16, 2, 78);
	CHECK(a == b);
	CHECK(a != c);
}

TEST_CASE("[CgamePathTracer] Image render and progressive accumulation") {
	Ref<CgameBVH> scene;
	scene.instantiate();
	scene->build(_plate_scene());
	const PackedColorArray alb = _grey_albedo(4);

	Transform3D cam = Transform3D(Basis(), Vector3(0, 3, 12)).looking_at(Vector3(0, 0, 0), Vector3(0, 1, 0));
	const Dictionary light = CgamePathTracer::make_light(Vector3(-0.3f, -1, -0.2f), Color(1, 1, 1), Color(0.3f, 0.4f, 0.6f), alb, 1);
	Ref<Image> img = CgamePathTracer::render_image(scene, cam, 50.0f, Vector2i(16, 12), 2, light, 3);
	REQUIRE(img.is_valid());
	CHECK(img->get_size() == Vector2i(16, 12));
	CHECK(img->get_format() == Image::FORMAT_RGB8);
	float sum = 0.0f;
	for (int y = 0; y < 12; y++) {
		for (int x = 0; x < 16; x++) {
			sum += img->get_pixel(x, y).get_luminance();
		}
	}
	CHECK(sum > 1.0f);

	Ref<Image> img2 = CgamePathTracer::render_image(scene, cam, 50.0f, Vector2i(16, 12), 2, light, 3);
	CHECK_MESSAGE(img->get_data() == img2->get_data(), "Same seed renders an identical image.");

	Ref<CgamePathTracer> prog;
	prog.instantiate();
	prog->begin_progressive(Vector2i(8, 6), 4);
	prog->accumulate(scene, cam, 50.0f, 1, light);
	prog->accumulate(scene, cam, 50.0f, 1, light);
	CHECK(prog->get_passes() == 2);
	CHECK(prog->get_samples() == 2);
	const Ref<Image> preview = prog->to_image();
	CHECK(preview->get_size() == Vector2i(8, 6));

	Ref<Image> reference = Image::create_empty(8, 6, false, Image::FORMAT_RGB8);
	for (int y = 0; y < 6; y++) {
		for (int x = 0; x < 8; x++) {
			const Vector3 c = prog->get_pixel(x, y).clamp(Vector3(), Vector3(1, 1, 1));
			reference->set_pixel(x, y, Color(Math::pow(float(c.x), 0.4545f), Math::pow(float(c.y), 0.4545f), Math::pow(float(c.z), 0.4545f)));
		}
	}
	CHECK(preview->get_data() == reference->get_data());
}

TEST_CASE("[CgamePathTracer] Progressive linear image preserves HDR radiance") {
	Ref<CgamePathTracer> tracer;
	tracer.instantiate();
	CHECK(tracer->to_linear_image()->get_size() == Vector2i(1, 1));

	tracer->begin_progressive(Vector2i(3, 0));
	CHECK(tracer->to_image()->get_size() == Vector2i(3, 1));
	CHECK(tracer->to_linear_image()->get_size() == Vector2i(3, 1));

	tracer->begin_progressive(Vector2i(3, 2));
	CHECK(tracer->to_image()->get_pixel(2, 1) == Color(0, 0, 0));
	CHECK(tracer->to_linear_image()->get_pixel(2, 1) == Color(0, 0, 0));

	Ref<CgameBVH> empty_scene;
	empty_scene.instantiate();
	const Color sky(2.5f, 0.25f, 1.5f);
	tracer->accumulate(empty_scene, Transform3D(), 50.0f, 2, CgamePathTracer::make_light(Vector3(), Color(), sky));
	tracer->accumulate(empty_scene, Transform3D(), 50.0f, 1, CgamePathTracer::make_light(Vector3(), Color(), Color(1, 1, 0)));

	const Ref<Image> linear = tracer->to_linear_image();
	CHECK(linear->get_format() == Image::FORMAT_RGBF);
	CHECK(linear->get_size() == Vector2i(3, 2));
	CHECK(linear->get_pixel(0, 0) == Color(2, 0.5f, 1));
	CHECK(linear->get_pixel(2, 1) == Color(2, 0.5f, 1));
	const Ref<Image> preview = tracer->to_image();
	CHECK(preview->get_format() == Image::FORMAT_RGB8);
	CHECK(preview->get_pixel(2, 1).r == 1.0f);
}

} // namespace TestCgameRaytrace
