/**************************************************************************/
/*  cgame_path_tracer.cpp                                                 */
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

#include "cgame_path_tracer.h"

#include "core/config/engine.h"
#include "core/object/class_db.h"
#include "core/object/worker_thread_pool.h"

// Technique references (concepts re-implemented, no source text copied):
//  - Peter Shirley, "Ray Tracing in One Weekend" series (CC0): diffuse bounce, cosine sampling.
//  - Pharr/Jakob/Humphreys, "Physically Based Rendering" 4th ed.: next-event estimation,
//    Russian roulette, path integrator.

Vector3 CgamePathTracer::_albedo(const PackedColorArray &p_albedo, int p_tri) {
	if (p_tri >= 0 && p_tri < p_albedo.size()) {
		return _col(p_albedo[p_tri]);
	}
	return Vector3(0.7f, 0.7f, 0.7f);
}

Vector3 CgamePathTracer::_cos_dir(const Vector3 &p_n, float p_r1, float p_r2) {
	const float phi = Math::TAU * p_r1;
	const float r = Math::sqrt(p_r2);
	const float z = Math::sqrt(MAX(1.0f - p_r2, 0.0f));
	const Vector3 a = Math::abs(p_n.x) < 0.9f ? Vector3(1, 0, 0) : Vector3(0, 1, 0);
	const Vector3 t = p_n.cross(a).normalized();
	const Vector3 b = p_n.cross(t);
	return t * (r * Math::cos(phi)) + b * (r * Math::sin(phi)) + p_n * z;
}

uint64_t CgamePathTracer::_stream_seed(int64_t p_seed, int64_t p_a, int64_t p_b, int64_t p_c) {
	// Wrapping 64-bit mix; distinct (seed, index) pairs map to distinct PCG streams.
	const uint64_t s = uint64_t(p_seed) * 73856093ULL + uint64_t(p_a) * 19349663ULL + uint64_t(p_b) * 83492791ULL + uint64_t(p_c);
	return s;
}

CgamePathTracer::LightParams CgamePathTracer::_parse_light(const Dictionary &p_light) {
	LightParams l;
	Vector3 sun_dir = p_light.get("sun_dir", Vector3(-0.4f, -1.0f, -0.3f));
	l.to_sun = -sun_dir.normalized();
	l.sun = _col(p_light.get("sun_color", Color(1.0f, 0.95f, 0.85f)));
	l.sky = _col(p_light.get("sky_color", Color(0.25f, 0.35f, 0.5f)));
	l.albedo = p_light.get("albedo", PackedColorArray());
	l.bounces = p_light.get("bounces", 3);
	return l;
}

Vector3 CgamePathTracer::_radiance(const CgameBVH &p_bvh, Vector3 p_o, Vector3 p_d, RandomPCG &p_rng, const LightParams &p_light, int p_max_hits) {
	Vector3 thr(1, 1, 1);
	Vector3 acc;
	for (int depth = 0; depth <= p_max_hits; depth++) {
		CgameBVH::Hit h;
		if (!p_bvh.intersect_native(p_o, p_d, FAR_DIST, h)) {
			acc += thr * p_light.sky;
			break;
		}
		if (depth >= p_max_hits) {
			break;
		}
		const Vector3 &n = h.normal;
		const Vector3 p = p_o + p_d * h.t + n * EPS;
		const Vector3 a = _albedo(p_light.albedo, h.tri);
		const float ndl = n.dot(p_light.to_sun);
		if (ndl > 0.0f && !p_bvh.occluded_native(p, p_light.to_sun, FAR_DIST)) {
			acc += thr * a * p_light.sun * ndl;
		}
		thr *= a;
		if (depth >= 2) {
			const float q = CLAMP(MAX(thr.x, MAX(thr.y, thr.z)), 0.05f, 0.95f);
			if (p_rng.randf() > q) {
				break;
			}
			thr /= q;
		}
		p_o = p;
		const float r1 = p_rng.randf();
		const float r2 = p_rng.randf();
		p_d = _cos_dir(n, r1, r2);
	}
	return acc;
}

template <typename F>
void CgamePathTracer::_parallel_for(int p_count, F &&p_fn) {
	if (p_count <= 0) {
		return;
	}
	WorkerThreadPool *pool = WorkerThreadPool::get_singleton();
	if (pool == nullptr || pool->get_thread_count() <= 1 || p_count == 1) {
		for (int i = 0; i < p_count; i++) {
			p_fn(i);
		}
		return;
	}
	struct Ctx {
		F *fn;
	} ctx{ &p_fn };
	WorkerThreadPool::GroupID group = pool->add_native_group_task(
			[](void *p_ud, uint32_t p_index) {
				(*static_cast<Ctx *>(p_ud)->fn)(int(p_index));
			},
			&ctx, p_count, -1, false, "CgamePathTracer");
	pool->wait_for_group_task_completion(group);
}

Dictionary CgamePathTracer::make_light(const Vector3 &p_sun_dir, const Color &p_sun_color, const Color &p_sky_color, const PackedColorArray &p_albedo_per_tri, int p_bounces) {
	Dictionary d;
	d["sun_dir"] = p_sun_dir;
	d["sun_color"] = p_sun_color;
	d["sky_color"] = p_sky_color;
	d["albedo"] = p_albedo_per_tri;
	d["bounces"] = p_bounces;
	return d;
}

PackedColorArray CgamePathTracer::bake_vertex_lighting(const Ref<CgameBVH> &p_bvh, const PackedVector3Array &p_vertices, const PackedVector3Array &p_normals, const PackedColorArray &p_albedo_per_tri, const Vector3 &p_sun_dir, const Color &p_sun_color, const Color &p_sky_color, int p_samples, int p_bounces, int64_t p_seed) {
	PackedColorArray out;
	ERR_FAIL_COND_V(p_bvh.is_null(), out);
	ERR_FAIL_COND_V_MSG(p_normals.size() < p_vertices.size(), out, "CgamePathTracer: normals must have one entry per vertex.");
	const int count = p_vertices.size();
	out.resize(count);
	LightParams light;
	light.to_sun = -p_sun_dir.normalized();
	light.sun = _col(p_sun_color);
	light.sky = _col(p_sky_color);
	light.albedo = p_albedo_per_tri;
	light.bounces = p_bounces;
	const int n_samples = MAX(p_samples, 1);
	const CgameBVH &bvh = *p_bvh.ptr();
	const Vector3 *verts = p_vertices.ptr();
	const Vector3 *norms = p_normals.ptr();
	Color *dst = out.ptrw();

	_parallel_for(count, [&](int i) {
		const Vector3 n = norms[i].normalized();
		const Vector3 p = verts[i] + n * EPS;
		const Vector3 a = _albedo(p_albedo_per_tri, i / 3);
		RandomPCG rng;
		rng.seed(_stream_seed(p_seed, i, 0, 1));
		Vector3 direct;
		const float ndl = n.dot(light.to_sun);
		if (ndl > 0.0f && !bvh.occluded_native(p, light.to_sun, FAR_DIST)) {
			direct = light.sun * ndl;
		}
		Vector3 indirect;
		for (int s = 0; s < n_samples; s++) {
			const float r1 = rng.randf();
			const float r2 = rng.randf();
			indirect += _radiance(bvh, p, _cos_dir(n, r1, r2), rng, light, light.bounces);
		}
		const Vector3 lit = a * (direct + indirect / float(n_samples));
		dst[i] = Color(lit.x, lit.y, lit.z, 1.0f);
	});
	return out;
}

PackedFloat32Array CgamePathTracer::bake_ambient_occlusion(const Ref<CgameBVH> &p_bvh, const PackedVector3Array &p_vertices, const PackedVector3Array &p_normals, int p_samples, float p_max_dist, int64_t p_seed) {
	PackedFloat32Array out;
	ERR_FAIL_COND_V(p_bvh.is_null(), out);
	ERR_FAIL_COND_V_MSG(p_normals.size() < p_vertices.size(), out, "CgamePathTracer: normals must have one entry per vertex.");
	const int count = p_vertices.size();
	out.resize(count);
	const int n_samples = MAX(p_samples, 1);
	const CgameBVH &bvh = *p_bvh.ptr();
	const Vector3 *verts = p_vertices.ptr();
	const Vector3 *norms = p_normals.ptr();
	float *dst = out.ptrw();

	_parallel_for(count, [&](int i) {
		const Vector3 n = norms[i].normalized();
		const Vector3 p = verts[i] + n * EPS;
		RandomPCG rng;
		rng.seed(_stream_seed(p_seed, i, 0, 7));
		int blocked = 0;
		for (int s = 0; s < n_samples; s++) {
			const float r1 = rng.randf();
			const float r2 = rng.randf();
			if (bvh.occluded_native(p, _cos_dir(n, r1, r2), p_max_dist)) {
				blocked++;
			}
		}
		dst[i] = 1.0f - float(blocked) / float(n_samples);
	});
	return out;
}

void CgamePathTracer::begin_progressive(const Vector2i &p_size, int64_t p_seed) {
	prog_size = Vector2i(MAX(p_size.x, 0), MAX(p_size.y, 0));
	prog_seed = p_seed;
	prog_samples = 0;
	prog_passes = 0;
	prog_sum.clear();
	prog_sum.resize(prog_size.x * prog_size.y);
	prog_sum.fill(Vector3());
}

void CgamePathTracer::accumulate(const Ref<CgameBVH> &p_bvh, const Transform3D &p_camera, float p_fov_deg, int p_spp, const Dictionary &p_light) {
	ERR_FAIL_COND(p_bvh.is_null());
	ERR_FAIL_COND_MSG(prog_size.x <= 0 || prog_size.y <= 0, "CgamePathTracer: call begin_progressive() with a non-empty size first.");
	const LightParams light = _parse_light(p_light);
	const int w = prog_size.x;
	const int h = prog_size.y;
	const float aspect = float(w) / float(MAX(h, 1));
	const float tan_half = Math::tan(Math::deg_to_rad(p_fov_deg) * 0.5f);
	const int n_spp = MAX(p_spp, 1);
	const CgameBVH &bvh = *p_bvh.ptr();
	Vector3 *sum = prog_sum.ptrw();
	const int passes = prog_passes;

	_parallel_for(h, [&](int y) {
		for (int x = 0; x < w; x++) {
			const int idx = y * w + x;
			RandomPCG rng;
			rng.seed(_stream_seed(prog_seed, passes, idx, 3) + uint64_t(passes) * (19349663ULL - 1ULL) + uint64_t(idx) * (83492791ULL - 1ULL));
			Vector3 col;
			for (int s = 0; s < n_spp; s++) {
				const float jx = rng.randf();
				const float jy = rng.randf();
				const float u = (2.0f * (float(x) + jx) / float(w) - 1.0f) * aspect * tan_half;
				const float v = (1.0f - 2.0f * (float(y) + jy) / float(h)) * tan_half;
				const Vector3 d = p_camera.basis.xform(Vector3(u, v, -1.0f)).normalized();
				col += _radiance(bvh, p_camera.origin, d, rng, light, light.bounces + 1);
			}
			sum[idx] += col;
		}
	});
	prog_samples += n_spp;
	prog_passes += 1;
}

Vector3 CgamePathTracer::get_pixel(int p_x, int p_y) const {
	ERR_FAIL_INDEX_V(p_x, prog_size.x, Vector3());
	ERR_FAIL_INDEX_V(p_y, prog_size.y, Vector3());
	if (prog_samples == 0) {
		return Vector3();
	}
	return prog_sum[p_y * prog_size.x + p_x] / float(prog_samples);
}

Ref<Image> CgamePathTracer::to_image() const {
	Ref<Image> img = Image::create_empty(MAX(prog_size.x, 1), MAX(prog_size.y, 1), false, Image::FORMAT_RGB8);
	if (prog_samples == 0 || img->is_empty()) {
		return img;
	}

	const auto encode_channel = [](float p_linear) -> uint8_t {
		const float gamma = Math::pow(CLAMP(p_linear, 0.0f, 1.0f), 0.4545f);
		// Match the RGB8 rounding in Image::set_pixel().
		return static_cast<uint8_t>(CLAMP(gamma * 255.0f + 0.5f, 0.0f, 255.0f));
	};
	const Vector3 *sum = prog_sum.ptr();
	uint8_t *dst = img->ptrw();
	for (int i = 0; i < prog_sum.size(); i++, dst += 3) {
		const Vector3 c = sum[i] / float(prog_samples);
		dst[0] = encode_channel(c.x);
		dst[1] = encode_channel(c.y);
		dst[2] = encode_channel(c.z);
	}
	return img;
}

Ref<Image> CgamePathTracer::to_linear_image() const {
	Ref<Image> img = Image::create_empty(MAX(prog_size.x, 1), MAX(prog_size.y, 1), false, Image::FORMAT_RGBF);
	if (prog_samples == 0 || img->is_empty()) {
		return img;
	}

	const Vector3 *sum = prog_sum.ptr();
	float *dst = reinterpret_cast<float *>(img->ptrw());
	for (int i = 0; i < prog_sum.size(); i++, dst += 3) {
		const Vector3 c = sum[i] / float(prog_samples);
		dst[0] = c.x;
		dst[1] = c.y;
		dst[2] = c.z;
	}
	return img;
}

Ref<Image> CgamePathTracer::render_image(const Ref<CgameBVH> &p_bvh, const Transform3D &p_camera, float p_fov_deg, const Vector2i &p_size, int p_spp, const Dictionary &p_light, int64_t p_seed) {
	Ref<CgamePathTracer> tracer;
	tracer.instantiate();
	tracer->begin_progressive(p_size, p_seed);
	tracer->accumulate(p_bvh, p_camera, p_fov_deg, p_spp, p_light);
	return tracer->to_image();
}

void CgamePathTracer::_bind_methods() {
	ClassDB::bind_static_method("CgamePathTracer", D_METHOD("make_light", "sun_dir", "sun_color", "sky_color", "albedo_per_tri", "bounces"), &CgamePathTracer::make_light, DEFVAL(PackedColorArray()), DEFVAL(3));
	ClassDB::bind_static_method("CgamePathTracer", D_METHOD("bake_vertex_lighting", "bvh", "vertices", "normals", "albedo_per_tri", "sun_dir", "sun_color", "sky_color", "samples", "bounces", "seed"), &CgamePathTracer::bake_vertex_lighting);
	ClassDB::bind_static_method("CgamePathTracer", D_METHOD("bake_ambient_occlusion", "bvh", "vertices", "normals", "samples", "max_dist", "seed"), &CgamePathTracer::bake_ambient_occlusion);
	ClassDB::bind_static_method("CgamePathTracer", D_METHOD("render_image", "bvh", "camera", "fov_deg", "size", "spp", "light", "seed"), &CgamePathTracer::render_image, DEFVAL(Dictionary()), DEFVAL(1));

	ClassDB::bind_method(D_METHOD("begin_progressive", "size", "seed"), &CgamePathTracer::begin_progressive, DEFVAL(1));
	ClassDB::bind_method(D_METHOD("accumulate", "bvh", "camera", "fov_deg", "spp", "light"), &CgamePathTracer::accumulate, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("get_pixel", "x", "y"), &CgamePathTracer::get_pixel);
	ClassDB::bind_method(D_METHOD("to_image"), &CgamePathTracer::to_image);
	ClassDB::bind_method(D_METHOD("to_linear_image"), &CgamePathTracer::to_linear_image);
	ClassDB::bind_method(D_METHOD("get_progressive_size"), &CgamePathTracer::get_progressive_size);
	ClassDB::bind_method(D_METHOD("get_samples"), &CgamePathTracer::get_samples);
	ClassDB::bind_method(D_METHOD("get_passes"), &CgamePathTracer::get_passes);
}
