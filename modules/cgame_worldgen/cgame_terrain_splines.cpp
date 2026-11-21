/**************************************************************************/
/*  cgame_terrain_splines.cpp                                             */
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

#include "cgame_terrain_splines.h"

#include "core/object/class_db.h"

#include "cgame_worldgen_util.h"

#include "core/math/math_funcs.h"

PackedVector3Array CgameTerrainSplines::catmull_rom(const PackedVector3Array &p_points, int p_samples_per_segment) {
	const int n = p_points.size();
	if (n < 2) {
		return p_points.duplicate();
	}
	PackedVector3Array out;
	const int samples = MAX(1, p_samples_per_segment);
	const Vector3 *pts = p_points.ptr();
	for (int i = 0; i < n - 1; i++) {
		const Vector3 p0 = pts[MAX(i - 1, 0)];
		const Vector3 p1 = pts[i];
		const Vector3 p2 = pts[i + 1];
		const Vector3 p3 = pts[MIN(i + 2, n - 1)];
		for (int s = 0; s < samples; s++) {
			const double t = (double)s / (double)samples;
			const real_t t1 = (real_t)t;
			const real_t t2 = (real_t)(t * t);
			const real_t t3 = (real_t)(t * t * t);
			out.push_back(((p1 * 2.0f) + (p2 - p0) * t1 + (p0 * 2.0f - p1 * 5.0f + p2 * 4.0f - p3) * t2 + (-p0 + p1 * 3.0f - p2 * 3.0f + p3) * t3) * 0.5f);
		}
	}
	out.push_back(pts[n - 1]);
	return out;
}

double CgameTerrainSplines::distance_to_polyline(const Vector2 &p_point, const PackedVector2Array &p_polyline) {
	if (p_polyline.is_empty()) {
		return Math::INF;
	}
	const Vector2 *pl = p_polyline.ptr();
	if (p_polyline.size() == 1) {
		return p_point.distance_to(pl[0]);
	}
	double best = Math::INF;
	for (int i = 0; i < p_polyline.size() - 1; i++) {
		const Vector2 a = pl[i];
		const Vector2 ab = pl[i + 1] - a;
		const double len2 = ab.length_squared();
		const double t = len2 <= 0.0 ? 0.0 : CLAMP((double)(p_point - a).dot(ab) / len2, 0.0, 1.0);
		best = MIN(best, (double)p_point.distance_to(a + ab * (real_t)t));
	}
	return best;
}

// Returns (distance, interpolated spline height) of the closest point on the XZ polyline.
Vector2 CgameTerrainSplines::_nearest(const Vector2 &p_point, const Vector3 *p_spline, int p_count) {
	double best_d = Math::INF;
	double best_h = 0.0;
	for (int i = 0; i < p_count - 1; i++) {
		const Vector2 a(p_spline[i].x, p_spline[i].z);
		const Vector2 b(p_spline[i + 1].x, p_spline[i + 1].z);
		const Vector2 ab = b - a;
		const double len2 = ab.length_squared();
		const double t = len2 <= 0.0 ? 0.0 : CLAMP((double)(p_point - a).dot(ab) / len2, 0.0, 1.0);
		const double d = p_point.distance_to(a + ab * (real_t)t);
		if (d < best_d) {
			best_d = d;
			best_h = Math::lerp((double)p_spline[i].y, (double)p_spline[i + 1].y, t);
		}
	}
	return Vector2((real_t)best_d, (real_t)best_h);
}

double CgameTerrainSplines::_sample_height(const float *p_heights, int p_width, int p_height, double p_cell_size, double p_wx, double p_wz) {
	const double fx = CLAMP(p_wx / p_cell_size, 0.0, (double)(p_width - 1));
	const double fy = CLAMP(p_wz / p_cell_size, 0.0, (double)(p_height - 1));
	const int x0 = MIN((int)fx, p_width - 2);
	const int y0 = MIN((int)fy, p_height - 2);
	const double tx = fx - (double)x0;
	const double ty = fy - (double)y0;
	const int i = y0 * p_width + x0;
	return Math::lerp(Math::lerp((double)p_heights[i], (double)p_heights[i + 1], tx), Math::lerp((double)p_heights[i + p_width], (double)p_heights[i + p_width + 1], tx), ty);
}

PackedFloat32Array CgameTerrainSplines::deform(const PackedFloat32Array &p_heights, int p_width, int p_height, double p_cell_size, const PackedVector3Array &p_spline, double p_half_width, double p_falloff, const String &p_mode) {
	PackedFloat32Array out = p_heights.duplicate();
	if (p_spline.size() < 2 || (int64_t)p_heights.size() != (int64_t)p_width * p_height) {
		return out;
	}
	enum Mode { FLATTEN,
		CARVE,
		RAISE,
		NONE };
	Mode mode = NONE;
	if (p_mode == "flatten") {
		mode = FLATTEN;
	} else if (p_mode == "carve") {
		mode = CARVE;
	} else if (p_mode == "raise") {
		mode = RAISE;
	}
	const double reach = p_half_width + MAX(p_falloff, 0.0);
	const double depth = 1.0;
	const float *src = p_heights.ptr();
	float *dst = out.ptrw();
	const Vector3 *spline = p_spline.ptr();
	const int count = p_spline.size();
	const bool threaded = (int64_t)p_width * p_height >= CgameWorldgen::PARALLEL_CELL_THRESHOLD;
	CgameWorldgen::parallel_for(p_height, threaded, [&](int y) {
		for (int x = 0; x < p_width; x++) {
			const Vector2 p((real_t)((double)x * p_cell_size), (real_t)((double)y * p_cell_size));
			const Vector2 near = _nearest(p, spline, count);
			if (near.x > reach) {
				continue;
			}
			double w = 1.0;
			if (near.x > p_half_width) {
				w = 1.0 - Math::smoothstep(0.0, 1.0, ((double)near.x - p_half_width) / MAX(p_falloff, 0.0001));
			}
			const int i = y * p_width + x;
			const double h = src[i];
			switch (mode) {
				case FLATTEN: {
					dst[i] = Math::lerp(h, (double)near.y, w);
				} break;
				case CARVE: {
					const double profile = 1.0 - Math::smoothstep(0.0, reach, (double)near.x);
					dst[i] = Math::lerp(h, MIN(h, (double)near.y - depth * profile), w);
				} break;
				case RAISE: {
					dst[i] = Math::lerp(h, MAX(h, (double)near.y), w);
				} break;
				case NONE: {
				} break;
			}
		}
	});
	return out;
}

TypedArray<Dictionary> CgameTerrainSplines::bridge_spans(const PackedFloat32Array &p_heights, int p_width, int p_height, double p_cell_size, const PackedVector3Array &p_spline, double p_clearance) {
	TypedArray<Dictionary> spans;
	if (p_width < 2 || p_height < 2 || (int64_t)p_heights.size() != (int64_t)p_width * p_height) {
		return spans;
	}
	int start = -1;
	const int n = p_spline.size();
	for (int i = 0; i < n; i++) {
		const Vector3 s = p_spline[i];
		const double gap = (double)s.y - _sample_height(p_heights.ptr(), p_width, p_height, p_cell_size, s.x, s.z);
		if (gap > p_clearance) {
			if (start < 0) {
				start = i;
			}
		} else if (start >= 0) {
			Dictionary span;
			span["start"] = start;
			span["end"] = i - 1;
			spans.push_back(span);
			start = -1;
		}
	}
	if (start >= 0) {
		Dictionary span;
		span["start"] = start;
		span["end"] = n - 1;
		spans.push_back(span);
	}
	return spans;
}

void CgameTerrainSplines::_bind_methods() {
	ClassDB::bind_static_method("CgameTerrainSplines", D_METHOD("catmull_rom", "points", "samples_per_segment"), &CgameTerrainSplines::catmull_rom);
	ClassDB::bind_static_method("CgameTerrainSplines", D_METHOD("distance_to_polyline", "point", "polyline"), &CgameTerrainSplines::distance_to_polyline);
	ClassDB::bind_static_method("CgameTerrainSplines", D_METHOD("deform", "heights", "width", "height", "cell_size", "spline", "half_width", "falloff", "mode"), &CgameTerrainSplines::deform);
	ClassDB::bind_static_method("CgameTerrainSplines", D_METHOD("bridge_spans", "heights", "width", "height", "cell_size", "spline", "clearance"), &CgameTerrainSplines::bridge_spans, DEFVAL(2.0));
}
