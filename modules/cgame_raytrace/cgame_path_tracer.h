/**************************************************************************/
/*  cgame_path_tracer.h                                                   */
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

#include "cgame_bvh.h"

#include "core/io/image.h"
#include "core/math/color.h"
#include "core/math/random_pcg.h"
#include "core/math/transform_3d.h"
#include "core/object/ref_counted.h"

// CPU path tracer for light baking (per-vertex lighting, ambient occlusion) and offline image
// rendering on top of CgameBVH. Multithreaded with WorkerThreadPool; every vertex and pixel owns
// its own PCG32 stream seeded from (seed, index), so results do not depend on the thread count.
//
// Conventions: sun_dir is the direction the sunlight TRAVELS. sun_color is the radiance a white
// diffuse surface facing the sun returns, sky_color is a constant-radiance environment.
// Output colours are linear.
class CgamePathTracer : public RefCounted {
	GDCLASS(CgamePathTracer, RefCounted);

	static constexpr float EPS = 0.001f;
	static constexpr float FAR_DIST = 1.0e20f;

	struct LightParams {
		Vector3 to_sun;
		Vector3 sun;
		Vector3 sky;
		PackedColorArray albedo;
		int bounces = 3;
	};

	// Progressive state.
	Vector2i prog_size;
	Vector<Vector3> prog_sum;
	int prog_samples = 0;
	int prog_passes = 0;
	int64_t prog_seed = 1;

	static Vector3 _col(const Color &p_c) { return Vector3(p_c.r, p_c.g, p_c.b); }
	static Vector3 _albedo(const PackedColorArray &p_albedo, int p_tri);
	static Vector3 _cos_dir(const Vector3 &p_n, float p_r1, float p_r2);
	static uint64_t _stream_seed(int64_t p_seed, int64_t p_a, int64_t p_b, int64_t p_c);
	static Vector3 _radiance(const CgameBVH &p_bvh, Vector3 p_o, Vector3 p_d, RandomPCG &p_rng, const LightParams &p_light, int p_max_hits);
	static LightParams _parse_light(const Dictionary &p_light);

	// Runs p_fn(index) for every index in [0, p_count) across the worker pool.
	template <typename F>
	static void _parallel_for(int p_count, F &&p_fn);

protected:
	static void _bind_methods();

public:
	static Dictionary make_light(const Vector3 &p_sun_dir, const Color &p_sun_color, const Color &p_sky_color, const PackedColorArray &p_albedo_per_tri = PackedColorArray(), int p_bounces = 3);
	static PackedColorArray bake_vertex_lighting(const Ref<CgameBVH> &p_bvh, const PackedVector3Array &p_vertices, const PackedVector3Array &p_normals, const PackedColorArray &p_albedo_per_tri, const Vector3 &p_sun_dir, const Color &p_sun_color, const Color &p_sky_color, int p_samples, int p_bounces, int64_t p_seed);
	static PackedFloat32Array bake_ambient_occlusion(const Ref<CgameBVH> &p_bvh, const PackedVector3Array &p_vertices, const PackedVector3Array &p_normals, int p_samples, float p_max_dist, int64_t p_seed);
	static Ref<Image> render_image(const Ref<CgameBVH> &p_bvh, const Transform3D &p_camera, float p_fov_deg, const Vector2i &p_size, int p_spp, const Dictionary &p_light = Dictionary(), int64_t p_seed = 1);

	// Progressive refinement: begin, then call accumulate() repeatedly.
	void begin_progressive(const Vector2i &p_size, int64_t p_seed = 1);
	void accumulate(const Ref<CgameBVH> &p_bvh, const Transform3D &p_camera, float p_fov_deg, int p_spp, const Dictionary &p_light = Dictionary());
	Vector3 get_pixel(int p_x, int p_y) const;
	Ref<Image> to_image() const;
	Ref<Image> to_linear_image() const;
	Vector2i get_progressive_size() const { return prog_size; }
	int get_samples() const { return prog_samples; }
	int get_passes() const { return prog_passes; }
};
