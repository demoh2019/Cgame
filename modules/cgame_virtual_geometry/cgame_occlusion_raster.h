/**************************************************************************/
/*  cgame_occlusion_raster.h                                              */
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

#include "core/math/aabb.h"
#include "core/math/projection.h"
#include "core/object/ref_counted.h"
#include "core/templates/local_vector.h"
#include "core/variant/variant.h"

// Software occlusion culling: a low-resolution conservative depth rasterizer plus a
// max-depth Hi-Z pyramid. Depth is the view distance (clip-space w), so it is linear
// and independent of the engine's clip conventions. Larger is farther; empty texels
// hold infinity. All answers are conservative: when unsure, the box is visible.
//
// Per frame: begin() -> rasterize_occluder()* -> is_visible() / test_many().
class CgameOcclusionRaster : public RefCounted {
	GDCLASS(CgameOcclusionRaster, RefCounted);

public:
	static constexpr float NEAR_W = 0.05f; // Clip-space w below which occluders are clipped and occludees assumed visible.
	static constexpr float DEPTH_BIAS = 0.01f; // Relative push of occluder depth away from the camera.

private:
	int width = 0;
	int height = 0;
	Projection view_proj;

	int tested = 0;
	int culled = 0;
	int occluder_triangles = 0;
	int pixels_written = 0;

	LocalVector<float> depth;
	LocalVector<LocalVector<float>> levels;
	LocalVector<int> level_w;
	LocalVector<int> level_h;
	bool hiz_dirty = true;
	LocalVector<float> prev_depth;
	int prev_w = 0;
	int prev_h = 0;
	bool has_prev = false;

	struct ClipVertex {
		float x, y, z, w;
	};

	void _raster_tri(const float *p_a, const float *p_b, const float *p_c);
	bool _test(const AABB &p_aabb);
	Vector3 _to_screen(const ClipVertex &p_clip) const;
	Vector3 _unproject_at_w(const Projection &p_inv, const Projection &p_vp, float p_ndc_x, float p_ndc_y, float p_w) const;
	void _ensure_hiz();

protected:
	static void _bind_methods();

public:
	void begin(const Projection &p_view_proj, int p_width = 256, int p_height = 128);
	void rasterize_occluder(const PackedVector3Array &p_triangles);
	void temporal_reproject(const Projection &p_prev_view_proj);
	void build_hiz();
	int hiz_level_count();
	Vector2i hiz_size(int p_level);
	float hiz_get(int p_level, int p_x, int p_y);
	bool is_visible(const AABB &p_aabb);
	PackedByteArray test_many(const Array &p_aabbs);

	int get_width() const { return width; }
	int get_height() const { return height; }
	int get_tested() const { return tested; }
	int get_culled() const { return culled; }
	int get_occluder_triangles() const { return occluder_triangles; }
	int get_pixels_written() const { return pixels_written; }
};
