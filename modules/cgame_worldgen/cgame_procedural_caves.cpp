/**************************************************************************/
/*  cgame_procedural_caves.cpp                                            */
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

#include "cgame_procedural_caves.h"

#include "core/object/class_db.h"

#include "cgame_worldgen_util.h"

#include "core/math/random_number_generator.h"
#include "core/templates/sort_array.h"

namespace {
struct RegionSizeDescending {
	bool operator()(const Vector<int32_t> &p_a, const Vector<int32_t> &p_b) const {
		return p_a.size() > p_b.size();
	}
};
} // namespace

PackedByteArray CgameProceduralCaves::generate(int p_width, int p_height, int64_t p_seed, double p_fill, int p_steps) {
	const int w = MAX(p_width, 3);
	const int h = MAX(p_height, 3);
	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed((uint64_t)p_seed);
	PackedByteArray grid;
	grid.resize((int64_t)w * h);
	uint8_t *g = grid.ptrw();
	for (int y = 0; y < h; y++) {
		for (int x = 0; x < w; x++) {
			const bool border = x == 0 || y == 0 || x == w - 1 || y == h - 1;
			// rng is only consulted for interior cells (short-circuit), like the reference script.
			g[y * w + x] = (border || (double)rng->randf() < p_fill) ? 1 : 0;
		}
	}
	for (int s = 0; s < MAX(p_steps, 0); s++) {
		grid = _smooth(grid, w, h);
	}
	_connect_regions(grid, w, h);
	return grid;
}

PackedByteArray CgameProceduralCaves::_smooth(const PackedByteArray &p_grid, int p_w, int p_h) {
	PackedByteArray out;
	out.resize((int64_t)p_w * p_h);
	const uint8_t *src = p_grid.ptr();
	uint8_t *dst = out.ptrw();
	const bool threaded = (int64_t)p_w * p_h >= CgameWorldgen::PARALLEL_CELL_THRESHOLD;
	CgameWorldgen::parallel_for(p_h, threaded, [&](int y) {
		for (int x = 0; x < p_w; x++) {
			if (x == 0 || y == 0 || x == p_w - 1 || y == p_h - 1) {
				dst[y * p_w + x] = 1;
				continue;
			}
			int n = 0;
			for (int dy = -1; dy <= 1; dy++) {
				for (int dx = -1; dx <= 1; dx++) {
					if (dx == 0 && dy == 0) {
						continue;
					}
					n += src[(y + dy) * p_w + (x + dx)];
				}
			}
			const uint8_t cur = src[y * p_w + x];
			if (n >= 5) {
				dst[y * p_w + x] = 1;
			} else if (n <= 3) {
				dst[y * p_w + x] = 0;
			} else {
				dst[y * p_w + x] = cur;
			}
		}
	});
	return out;
}

Vector<Vector<int32_t>> CgameProceduralCaves::_regions(const uint8_t *p_grid, int p_w, int p_h) {
	Vector<Vector<int32_t>> result;
	const int64_t total = (int64_t)p_w * p_h;
	Vector<uint8_t> seen;
	seen.resize(total);
	seen.fill(0);
	uint8_t *seen_w = seen.ptrw();
	Vector<int32_t> stack;
	for (int64_t start = 0; start < total; start++) {
		if (p_grid[start] != 0 || seen_w[start] != 0) {
			continue;
		}
		Vector<int32_t> cells;
		stack.clear();
		stack.push_back((int32_t)start);
		seen_w[start] = 1;
		while (!stack.is_empty()) {
			const int32_t c = stack[stack.size() - 1];
			stack.resize(stack.size() - 1);
			cells.push_back(c);
			const int cx = c % p_w;
			const int cy = c / p_w;
			const int32_t neighbors[4] = { cx > 0 ? c - 1 : -1, cx < p_w - 1 ? c + 1 : -1, cy > 0 ? c - p_w : -1, cy < p_h - 1 ? c + p_w : -1 };
			for (int k = 0; k < 4; k++) {
				const int32_t idx = neighbors[k];
				if (idx >= 0 && p_grid[idx] == 0 && seen_w[idx] == 0) {
					seen_w[idx] = 1;
					stack.push_back(idx);
				}
			}
		}
		result.push_back(cells);
	}
	return result;
}

Array CgameProceduralCaves::regions(const PackedByteArray &p_grid, int p_w, int p_h) {
	Array out;
	if (p_w <= 0 || p_h <= 0 || (int64_t)p_grid.size() != (int64_t)p_w * p_h) {
		return out;
	}
	Vector<Vector<int32_t>> regs = _regions(p_grid.ptr(), p_w, p_h);
	for (const Vector<int32_t> &r : regs) {
		PackedInt32Array cells;
		cells.resize(r.size());
		for (int i = 0; i < r.size(); i++) {
			cells.set(i, r[i]);
		}
		out.push_back(cells);
	}
	return out;
}

Array CgameProceduralCaves::chambers(const PackedByteArray &p_grid, int p_w, int p_h, int p_min_size) {
	Array out;
	if (p_w <= 0 || p_h <= 0 || (int64_t)p_grid.size() != (int64_t)p_w * p_h) {
		return out;
	}
	Vector<Vector<int32_t>> regs = _regions(p_grid.ptr(), p_w, p_h);
	regs.sort_custom<RegionSizeDescending>();
	for (const Vector<int32_t> &cells : regs) {
		if (cells.size() < p_min_size) {
			continue;
		}
		Vector2 sum;
		for (int32_t c : cells) {
			sum += Vector2(c % p_w, c / p_w);
		}
		const Vector2 centroid = sum / (real_t)cells.size();
		Vector2 best(cells[0] % p_w, cells[0] / p_w);
		double best_d = Math::INF;
		for (int32_t c : cells) {
			const Vector2 p(c % p_w, c / p_w);
			const double d = p.distance_squared_to(centroid);
			if (d < best_d) {
				best_d = d;
				best = p;
			}
		}
		out.push_back(best);
	}
	return out;
}

void CgameProceduralCaves::_connect_regions(PackedByteArray &r_grid, int p_w, int p_h) {
	Vector<Vector<int32_t>> regs = _regions(r_grid.ptr(), p_w, p_h);
	if (regs.size() <= 1) {
		return;
	}
	regs.sort_custom<RegionSizeDescending>();
	Vector<int32_t> connected = regs[0];
	for (int i = 1; i < regs.size(); i++) {
		const Vector<int32_t> &other = regs[i];
		const double total = (double)other.size() * (double)connected.size();
		const int stride = MAX(1, (int)Math::ceil(total / 400000.0));
		int best_a = other[0];
		int best_b = connected[0];
		int64_t best_d = (int64_t)1 << 60;
		for (int a : other) {
			const int ax = a % p_w;
			const int ay = a / p_w;
			for (int j = 0; j < connected.size(); j += stride) {
				const int b = connected[j];
				const int64_t dx = ax - b % p_w;
				const int64_t dy = ay - b / p_w;
				const int64_t d = dx * dx + dy * dy;
				if (d < best_d) {
					best_d = d;
					best_a = a;
					best_b = b;
				}
			}
		}
		_carve(r_grid.ptrw(), p_w, best_a, best_b);
		connected.append_array(other);
	}
}

// L-shaped tunnel: horizontal along a's row, then vertical along b's column.
void CgameProceduralCaves::_carve(uint8_t *r_grid, int p_w, int p_a, int p_b) {
	const int ax = p_a % p_w;
	const int ay = p_a / p_w;
	const int bx = p_b % p_w;
	const int by = p_b / p_w;
	int x = ax;
	const int step_x = bx > ax ? 1 : -1;
	while (x != bx) {
		r_grid[ay * p_w + x] = 0;
		x += step_x;
	}
	int y = ay;
	const int step_y = by > ay ? 1 : -1;
	while (y != by) {
		r_grid[y * p_w + bx] = 0;
		y += step_y;
	}
	r_grid[by * p_w + bx] = 0;
}

void CgameProceduralCaves::_bind_methods() {
	ClassDB::bind_static_method("CgameProceduralCaves", D_METHOD("generate", "width", "height", "seed", "fill", "steps"), &CgameProceduralCaves::generate, DEFVAL(0.47), DEFVAL(5));
	ClassDB::bind_static_method("CgameProceduralCaves", D_METHOD("regions", "grid", "w", "h"), &CgameProceduralCaves::regions);
	ClassDB::bind_static_method("CgameProceduralCaves", D_METHOD("chambers", "grid", "w", "h", "min_size"), &CgameProceduralCaves::chambers);
}
