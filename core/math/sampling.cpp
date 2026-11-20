/**************************************************************************/
/*  sampling.cpp                                                          */
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

#include "sampling.h"

#include "core/math/random_pcg.h"
#include "core/object/class_db.h"
#include "core/templates/local_vector.h"

double Sampling::halton(int64_t p_index, int64_t p_base) {
	ERR_FAIL_COND_V_MSG(p_base < 2, 0.0, "Halton base must be 2 or greater.");
	ERR_FAIL_COND_V_MSG(p_index < 0, 0.0, "Halton index must not be negative.");
	double f = 1.0;
	double r = 0.0;
	int64_t i = p_index;
	while (i > 0) {
		f /= double(p_base);
		r += f * double(i % p_base);
		i /= p_base;
	}
	return r;
}

PackedVector2Array Sampling::halton_2d(int64_t p_count, int64_t p_offset) {
	PackedVector2Array points;
	ERR_FAIL_COND_V_MSG(p_count < 0, points, "Halton point count must not be negative.");
	ERR_FAIL_COND_V_MSG(p_offset < 0, points, "Halton offset must not be negative.");
	points.resize(p_count);
	Vector2 *w = points.ptrw();
	for (int64_t i = 0; i < p_count; i++) {
		w[i] = Vector2(real_t(halton(i + p_offset, 2)), real_t(halton(i + p_offset, 3)));
	}
	return points;
}

PackedVector2Array Sampling::poisson_disk_2d(const Vector2 &p_size, real_t p_radius, int64_t p_seed, int64_t p_max_attempts, int64_t p_max_points) {
	PackedVector2Array result;
	ERR_FAIL_COND_V_MSG(!(p_radius > real_t(0.0)), result, "Poisson disk radius must be greater than zero.");
	ERR_FAIL_COND_V_MSG(!(p_size.x > real_t(0.0)) || !(p_size.y > real_t(0.0)), result, "Poisson disk area size must be positive.");
	ERR_FAIL_COND_V_MSG(p_max_attempts < 1, result, "Poisson disk max_attempts must be at least 1.");
	if (p_max_points < 1) {
		return result;
	}

	const real_t cell = p_radius / real_t(Math::SQRT2);
	const int64_t grid_w = MAX(int64_t(Math::ceil(p_size.x / cell)), int64_t(1));
	const int64_t grid_h = MAX(int64_t(Math::ceil(p_size.y / cell)), int64_t(1));
	ERR_FAIL_COND_V_MSG(grid_w * grid_h > int64_t(64) * 1024 * 1024, result, "Poisson disk area is too large for this radius.");

	LocalVector<int32_t> grid;
	grid.resize(uint32_t(grid_w * grid_h));
	for (uint32_t i = 0; i < grid.size(); i++) {
		grid[i] = -1;
	}

	RandomPCG rng = RandomPCG(uint64_t(p_seed));
	LocalVector<Vector2> points;
	LocalVector<int32_t> active;
	const real_t radius_sq = p_radius * p_radius;

	auto cell_of = [&](const Vector2 &p) -> int64_t {
		const int64_t gx = CLAMP(int64_t(p.x / cell), int64_t(0), grid_w - 1);
		const int64_t gy = CLAMP(int64_t(p.y / cell), int64_t(0), grid_h - 1);
		return gy * grid_w + gx;
	};
	auto fits = [&](const Vector2 &p) -> bool {
		if (p.x < 0 || p.y < 0 || p.x >= p_size.x || p.y >= p_size.y) {
			return false;
		}
		const int64_t gx = int64_t(p.x / cell);
		const int64_t gy = int64_t(p.y / cell);
		for (int64_t y = MAX(gy - 2, int64_t(0)); y <= MIN(gy + 2, grid_h - 1); y++) {
			for (int64_t x = MAX(gx - 2, int64_t(0)); x <= MIN(gx + 2, grid_w - 1); x++) {
				const int32_t idx = grid[uint32_t(y * grid_w + x)];
				if (idx >= 0 && points[idx].distance_squared_to(p) < radius_sq) {
					return false;
				}
			}
		}
		return true;
	};
	auto add = [&](const Vector2 &p) {
		const int32_t idx = int32_t(points.size());
		points.push_back(p);
		active.push_back(idx);
		grid[uint32_t(cell_of(p))] = idx;
	};

	add(Vector2(rng.randf() * p_size.x, rng.randf() * p_size.y));

	while (!active.is_empty() && int64_t(points.size()) < p_max_points) {
		const uint32_t slot = rng.rand(active.size());
		const Vector2 origin = points[active[slot]];
		bool found = false;
		for (int64_t attempt = 0; attempt < p_max_attempts; attempt++) {
			const real_t angle = rng.randf() * real_t(Math::TAU);
			const real_t dist = p_radius * (real_t(1.0) + rng.randf());
			const Vector2 candidate = origin + Vector2(Math::cos(angle), Math::sin(angle)) * dist;
			if (fits(candidate)) {
				add(candidate);
				found = true;
				break;
			}
		}
		if (!found) {
			active[slot] = active[active.size() - 1];
			active.resize(active.size() - 1);
		}
	}

	result.resize(points.size());
	Vector2 *w = result.ptrw();
	for (uint32_t i = 0; i < points.size(); i++) {
		w[i] = points[i];
	}
	return result;
}

void Sampling::_bind_methods() {
	ClassDB::bind_static_method("Sampling", D_METHOD("halton", "index", "base"), &Sampling::halton);
	ClassDB::bind_static_method("Sampling", D_METHOD("halton_2d", "count", "offset"), &Sampling::halton_2d, DEFVAL(1));
	ClassDB::bind_static_method("Sampling", D_METHOD("poisson_disk_2d", "size", "radius", "seed", "max_attempts", "max_points"), &Sampling::poisson_disk_2d, DEFVAL(0), DEFVAL(30), DEFVAL(100000));
}
