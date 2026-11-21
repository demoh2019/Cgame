/**************************************************************************/
/*  cgame_occlusion_raster.cpp                                            */
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

#include "cgame_occlusion_raster.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

#include <cmath>

void CgameOcclusionRaster::begin(const Projection &p_view_proj, int p_width, int p_height) {
	if (depth.size() > 0) {
		prev_depth = depth;
		prev_w = width;
		prev_h = height;
		has_prev = true;
	}
	view_proj = p_view_proj;
	width = MAX(1, p_width);
	height = MAX(1, p_height);
	depth.resize((uint32_t)width * (uint32_t)height);
	float *d = depth.ptr();
	const uint32_t n = depth.size();
	for (uint32_t i = 0; i < n; i++) {
		d[i] = Math::INF;
	}
	hiz_dirty = true;
	tested = 0;
	culled = 0;
	occluder_triangles = 0;
	pixels_written = 0;
}

Vector3 CgameOcclusionRaster::_to_screen(const ClipVertex &p_clip) const {
	const float inv_w = 1.0f / p_clip.w;
	return Vector3(
			(p_clip.x * inv_w * 0.5f + 0.5f) * (float)width,
			(0.5f - p_clip.y * inv_w * 0.5f) * (float)height,
			inv_w);
}

void CgameOcclusionRaster::rasterize_occluder(const PackedVector3Array &p_triangles) {
	ERR_FAIL_COND_MSG(width <= 0 || height <= 0 || depth.is_empty(), "CgameOcclusionRaster: call begin() first.");
	const int tri_count = p_triangles.size() / 3;
	const Vector3 *tr = p_triangles.ptr();
	for (int i = 0; i < tri_count; i++) {
		// Sutherland-Hodgman against the plane w = NEAR_W; a triangle yields at most 4 vertices.
		ClipVertex in[3];
		for (int k = 0; k < 3; k++) {
			const Vector4 c = view_proj.xform(Vector4(tr[i * 3 + k].x, tr[i * 3 + k].y, tr[i * 3 + k].z, 1.0f));
			in[k] = { (float)c.x, (float)c.y, (float)c.z, (float)c.w };
		}
		ClipVertex poly[4];
		int pc = 0;
		for (int k = 0; k < 3; k++) {
			const ClipVertex &a = in[k];
			const ClipVertex &b = in[(k + 1) % 3];
			const float da = a.w - NEAR_W;
			const float db = b.w - NEAR_W;
			if (da >= 0.0f) {
				poly[pc++] = a;
			}
			if ((da >= 0.0f) != (db >= 0.0f)) {
				const float t = da / (da - db);
				poly[pc++] = { a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t, a.w + (b.w - a.w) * t };
			}
		}
		if (pc < 3) {
			continue;
		}
		occluder_triangles++;
		float pts[4][3];
		for (int k = 0; k < pc; k++) {
			const Vector3 s = _to_screen(poly[k]);
			pts[k][0] = s.x;
			pts[k][1] = s.y;
			pts[k][2] = s.z;
		}
		for (int k = 1; k < pc - 1; k++) {
			_raster_tri(pts[0], pts[k], pts[k + 1]);
		}
	}
	hiz_dirty = true;
}

// Edge-function rasterizer. Vertices are (screen x, screen y, 1/w). Pixel centres only; keeps the nearest depth.
// Barycentrics are affine in (x, y), so each row is a branch-light loop over contiguous memory that
// compilers can auto-vectorize apart from the pixels_written bookkeeping.
void CgameOcclusionRaster::_raster_tri(const float *p_a, const float *p_b, const float *p_c) {
	const float ax = p_a[0], ay = p_a[1], az = p_a[2];
	const float bx = p_b[0], by = p_b[1], bz = p_b[2];
	const float cx = p_c[0], cy = p_c[1], cz = p_c[2];
	const float area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
	if (Math::abs(area) < 1e-9f) {
		return;
	}
	const float inv_area = 1.0f / area;
	const int x_min = MAX(0, (int)Math::floor(MIN(ax, MIN(bx, cx))));
	const int x_max = MIN(width - 1, (int)Math::ceil(MAX(ax, MAX(bx, cx))));
	const int y_min = MAX(0, (int)Math::floor(MIN(ay, MIN(by, cy))));
	const int y_max = MIN(height - 1, (int)Math::ceil(MAX(ay, MAX(by, cy))));
	if (x_min > x_max || y_min > y_max) {
		return;
	}
	// wa(px,py) = ((bx-px)*(cy-py) - (by-py)*(cx-px)) / area = wa0 + wa_x*px + wa_y*py
	const float wa0 = (bx * cy - by * cx) * inv_area;
	const float wa_x = (by - cy) * inv_area;
	const float wa_y = (cx - bx) * inv_area;
	const float wb0 = (cx * ay - cy * ax) * inv_area;
	const float wb_x = (cy - ay) * inv_area;
	const float wb_y = (ax - cx) * inv_area;
	float *buf = depth.ptr();
	int written = 0;
	for (int y = y_min; y <= y_max; y++) {
		const float py = (float)y + 0.5f;
		const float ra = wa0 + wa_y * py;
		const float rb = wb0 + wb_y * py;
		float *row = buf + (size_t)y * (size_t)width;
		for (int x = x_min; x <= x_max; x++) {
			const float px = (float)x + 0.5f;
			const float wa = ra + wa_x * px;
			const float wb = rb + wb_x * px;
			const float wc = 1.0f - wa - wb;
			if (wa < 0.0f || wb < 0.0f || wc < 0.0f) {
				continue;
			}
			const float inv_w = wa * az + wb * bz + wc * cz;
			if (inv_w <= 0.0f) {
				continue;
			}
			const float d = (1.0f / inv_w) * (1.0f + DEPTH_BIAS);
			if (d < row[x]) {
				if (std::isinf(row[x])) {
					written++;
				}
				row[x] = d;
			}
		}
	}
	pixels_written += written;
}

Vector3 CgameOcclusionRaster::_unproject_at_w(const Projection &p_inv, const Projection &p_vp, float p_ndc_x, float p_ndc_y, float p_w) const {
	const Vector4 p0 = p_inv.xform(Vector4(p_ndc_x, p_ndc_y, 0.0f, 1.0f));
	const Vector4 p1 = p_inv.xform(Vector4(p_ndc_x, p_ndc_y, 0.5f, 1.0f));
	const Vector3 a = Vector3(p0.x, p0.y, p0.z) / p0.w;
	const Vector3 b = Vector3(p1.x, p1.y, p1.z) / p1.w;
	const float wa = p_vp.xform(Vector4(a.x, a.y, a.z, 1.0f)).w;
	const float wb = p_vp.xform(Vector4(b.x, b.y, b.z, 1.0f)).w;
	if (Math::abs(wb - wa) < 1e-6f) {
		return a;
	}
	return a.lerp(b, (p_w - wa) / (wb - wa));
}

void CgameOcclusionRaster::temporal_reproject(const Projection &p_prev_view_proj) {
	if (!has_prev || prev_depth.size() != (uint32_t)(prev_w * prev_h) || depth.is_empty()) {
		return;
	}
	const Projection inv = p_prev_view_proj.inverse();
	for (int y = 0; y < prev_h; y++) {
		for (int x = 0; x < prev_w; x++) {
			const float d = prev_depth[y * prev_w + x];
			if (std::isinf(d)) {
				continue;
			}
			const float ndc_x = ((float)x + 0.5f) / (float)prev_w * 2.0f - 1.0f;
			const float ndc_y = 1.0f - ((float)y + 0.5f) / (float)prev_h * 2.0f;
			const Vector3 world = _unproject_at_w(inv, p_prev_view_proj, ndc_x, ndc_y, d);
			const Vector4 c = view_proj.xform(Vector4(world.x, world.y, world.z, 1.0f));
			if (c.w <= NEAR_W) {
				continue;
			}
			const Vector3 s = _to_screen({ (float)c.x, (float)c.y, (float)c.z, (float)c.w });
			const int px = (int)Math::floor(s.x);
			const int py = (int)Math::floor(s.y);
			if (px < 0 || py < 0 || px >= width || py >= height) {
				continue;
			}
			const float nd = (float)c.w * 1.05f;
			if (nd < depth[py * width + px]) {
				depth[py * width + px] = nd;
			}
		}
	}
	hiz_dirty = true;
}

void CgameOcclusionRaster::build_hiz() {
	levels.clear();
	level_w.clear();
	level_h.clear();
	levels.push_back(depth);
	level_w.push_back(width);
	level_h.push_back(height);
	int cw = width;
	int ch = height;
	while (cw > 1 || ch > 1) {
		const int nw = (cw + 1) >> 1;
		const int nh = (ch + 1) >> 1;
		const float *src = levels[levels.size() - 1].ptr();
		LocalVector<float> dst;
		dst.resize((uint32_t)nw * (uint32_t)nh);
		for (int y = 0; y < nh; y++) {
			const int y0 = y * 2;
			const int y1 = MIN(y0 + 1, ch - 1);
			for (int x = 0; x < nw; x++) {
				const int x0 = x * 2;
				const int x1 = MIN(x0 + 1, cw - 1);
				dst[y * nw + x] = MAX(MAX(src[y0 * cw + x0], src[y0 * cw + x1]), MAX(src[y1 * cw + x0], src[y1 * cw + x1]));
			}
		}
		levels.push_back(dst);
		level_w.push_back(nw);
		level_h.push_back(nh);
		cw = nw;
		ch = nh;
	}
	hiz_dirty = false;
}

void CgameOcclusionRaster::_ensure_hiz() {
	if (hiz_dirty || levels.is_empty()) {
		build_hiz();
	}
}

int CgameOcclusionRaster::hiz_level_count() {
	ERR_FAIL_COND_V_MSG(depth.is_empty(), 0, "CgameOcclusionRaster: call begin() first.");
	_ensure_hiz();
	return (int)levels.size();
}

Vector2i CgameOcclusionRaster::hiz_size(int p_level) {
	ERR_FAIL_COND_V_MSG(depth.is_empty(), Vector2i(), "CgameOcclusionRaster: call begin() first.");
	_ensure_hiz();
	ERR_FAIL_INDEX_V(p_level, (int)levels.size(), Vector2i());
	return Vector2i(level_w[p_level], level_h[p_level]);
}

float CgameOcclusionRaster::hiz_get(int p_level, int p_x, int p_y) {
	ERR_FAIL_COND_V_MSG(depth.is_empty(), 0.0f, "CgameOcclusionRaster: call begin() first.");
	_ensure_hiz();
	ERR_FAIL_INDEX_V(p_level, (int)levels.size(), 0.0f);
	ERR_FAIL_INDEX_V(p_x, level_w[p_level], 0.0f);
	ERR_FAIL_INDEX_V(p_y, level_h[p_level], 0.0f);
	return levels[p_level][p_y * level_w[p_level] + p_x];
}

bool CgameOcclusionRaster::_test(const AABB &p_aabb) {
	_ensure_hiz();
	float min_x = Math::INF;
	float min_y = Math::INF;
	float max_x = -Math::INF;
	float max_y = -Math::INF;
	float nearest = Math::INF;
	const Vector3 p = p_aabb.position;
	const Vector3 e = p_aabb.size;
	for (int c = 0; c < 8; c++) {
		const Vector4 clip = view_proj.xform(Vector4(
				p.x + ((c & 1) ? e.x : 0.0f),
				p.y + ((c & 2) ? e.y : 0.0f),
				p.z + ((c & 4) ? e.z : 0.0f),
				1.0f));
		if (clip.w <= NEAR_W) {
			return true; // Crossing or behind the near plane: stay conservative.
		}
		const Vector3 s = _to_screen({ (float)clip.x, (float)clip.y, (float)clip.z, (float)clip.w });
		min_x = MIN(min_x, (float)s.x);
		max_x = MAX(max_x, (float)s.x);
		min_y = MIN(min_y, (float)s.y);
		max_y = MAX(max_y, (float)s.y);
		nearest = MIN(nearest, (float)clip.w);
	}
	// Fully off-screen is a frustum-culling matter, not occlusion.
	if (max_x < 0.0f || max_y < 0.0f || min_x > (float)width || min_y > (float)height) {
		return true;
	}
	// Expand by one pixel: occluder coverage is sampled at pixel centres.
	const int x0 = CLAMP((int)Math::floor(min_x) - 1, 0, width - 1);
	const int x1 = CLAMP((int)Math::floor(max_x) + 1, 0, width - 1);
	const int y0 = CLAMP((int)Math::floor(min_y) - 1, 0, height - 1);
	const int y1 = CLAMP((int)Math::floor(max_y) + 1, 0, height - 1);
	const int size = MAX(x1 - x0 + 1, y1 - y0 + 1);
	int log2_ceil = 0;
	while ((1 << log2_ceil) < size) {
		log2_ceil++;
	}
	const int level = CLAMP(log2_ceil - 1, 0, (int)levels.size() - 1);
	const int lw = level_w[level];
	const int lh = level_h[level];
	const int tx0 = CLAMP(x0 >> level, 0, lw - 1);
	const int tx1 = CLAMP(x1 >> level, 0, lw - 1);
	const int ty0 = CLAMP(y0 >> level, 0, lh - 1);
	const int ty1 = CLAMP(y1 >> level, 0, lh - 1);
	const float *buf = levels[level].ptr();
	float far_most = 0.0f;
	for (int ty = ty0; ty <= ty1; ty++) {
		for (int tx = tx0; tx <= tx1; tx++) {
			far_most = MAX(far_most, buf[ty * lw + tx]);
		}
	}
	// Occluded only when even the nearest point of the box is behind the farthest occluder in the region.
	return !(nearest > far_most);
}

bool CgameOcclusionRaster::is_visible(const AABB &p_aabb) {
	ERR_FAIL_COND_V_MSG(depth.is_empty(), true, "CgameOcclusionRaster: call begin() first.");
	tested++;
	const bool visible = _test(p_aabb);
	if (!visible) {
		culled++;
	}
	return visible;
}

PackedByteArray CgameOcclusionRaster::test_many(const Array &p_aabbs) {
	PackedByteArray out;
	out.resize(p_aabbs.size());
	ERR_FAIL_COND_V_MSG(depth.is_empty(), out, "CgameOcclusionRaster: call begin() first.");
	_ensure_hiz();
	uint8_t *w = out.ptrw();
	for (int i = 0; i < p_aabbs.size(); i++) {
		const AABB bb = p_aabbs[i];
		w[i] = is_visible(bb) ? 1 : 0;
	}
	return out;
}

void CgameOcclusionRaster::_bind_methods() {
	ClassDB::bind_method(D_METHOD("begin", "view_proj", "width", "height"), &CgameOcclusionRaster::begin, DEFVAL(256), DEFVAL(128));
	ClassDB::bind_method(D_METHOD("rasterize_occluder", "triangles"), &CgameOcclusionRaster::rasterize_occluder);
	ClassDB::bind_method(D_METHOD("temporal_reproject", "prev_view_proj"), &CgameOcclusionRaster::temporal_reproject);
	ClassDB::bind_method(D_METHOD("build_hiz"), &CgameOcclusionRaster::build_hiz);
	ClassDB::bind_method(D_METHOD("hiz_level_count"), &CgameOcclusionRaster::hiz_level_count);
	ClassDB::bind_method(D_METHOD("hiz_size", "level"), &CgameOcclusionRaster::hiz_size);
	ClassDB::bind_method(D_METHOD("hiz_get", "level", "x", "y"), &CgameOcclusionRaster::hiz_get);
	ClassDB::bind_method(D_METHOD("is_visible", "aabb"), &CgameOcclusionRaster::is_visible);
	ClassDB::bind_method(D_METHOD("test_many", "aabbs"), &CgameOcclusionRaster::test_many);
	ClassDB::bind_method(D_METHOD("get_width"), &CgameOcclusionRaster::get_width);
	ClassDB::bind_method(D_METHOD("get_height"), &CgameOcclusionRaster::get_height);
	ClassDB::bind_method(D_METHOD("get_tested"), &CgameOcclusionRaster::get_tested);
	ClassDB::bind_method(D_METHOD("get_culled"), &CgameOcclusionRaster::get_culled);
	ClassDB::bind_method(D_METHOD("get_occluder_triangles"), &CgameOcclusionRaster::get_occluder_triangles);
	ClassDB::bind_method(D_METHOD("get_pixels_written"), &CgameOcclusionRaster::get_pixels_written);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "width", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_width");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "height", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_height");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "tested", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_tested");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "culled", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_culled");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "occluder_triangles", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_occluder_triangles");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "pixels_written", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_pixels_written");
}
