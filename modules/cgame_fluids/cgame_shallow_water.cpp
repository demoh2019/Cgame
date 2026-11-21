/**************************************************************************/
/*  cgame_shallow_water.cpp                                               */
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

#include "cgame_shallow_water.h"

#include "core/math/math_funcs.h"

void CgameShallowWater::setup(int p_width, int p_height, real_t p_cell_size, const Vector<float> &p_terrain) {
	ERR_FAIL_COND_MSG(p_width <= 0 || p_height <= 0, "CgameShallowWater: grid size must be positive.");
	ERR_FAIL_COND_MSG(p_cell_size <= 0.0, "CgameShallowWater: cell_size must be positive.");
	width = p_width;
	height = p_height;
	cell_size = p_cell_size;
	const int count = width * height;
	terrain = p_terrain;
	terrain.resize(count); // Missing entries are filled with 0.
	if (p_terrain.size() < count) {
		float *t = terrain.ptrw();
		for (int i = p_terrain.size(); i < count; i++) {
			t[i] = 0.0;
		}
	}
	Vector<float> *buffers[] = { &depth, &f_left, &f_right, &f_up, &f_down };
	for (Vector<float> *b : buffers) {
		b->resize(count);
		b->fill(0.0);
	}
}

void CgameShallowWater::add_water(const Vector2i &p_cell, real_t p_depth) {
	if (!_in_bounds(p_cell)) {
		return;
	}
	const int idx = p_cell.y * width + p_cell.x;
	depth.write[idx] = MAX(depth[idx] + p_depth, real_t(0.0));
}

real_t CgameShallowWater::depth_at(const Vector2i &p_cell) const {
	if (!_in_bounds(p_cell)) {
		return 0.0;
	}
	return depth[p_cell.y * width + p_cell.x];
}

real_t CgameShallowWater::terrain_at(const Vector2i &p_cell) const {
	if (!_in_bounds(p_cell)) {
		return 0.0;
	}
	return terrain[p_cell.y * width + p_cell.x];
}

real_t CgameShallowWater::total_volume() const {
	double sum = 0.0;
	const float *d = depth.ptr();
	for (int i = 0; i < depth.size(); i++) {
		sum += d[i];
	}
	return real_t(sum * double(cell_size) * double(cell_size));
}

Vector2 CgameShallowWater::velocity_at(const Vector2i &p_cell) const {
	if (!_in_bounds(p_cell)) {
		return Vector2();
	}
	const int x = p_cell.x;
	const int y = p_cell.y;
	const int idx = y * width + x;
	const real_t d = depth[idx];
	if (d < 1e-4) {
		return Vector2();
	}
	const real_t in_l = x > 0 ? f_right[idx - 1] : 0.0f;
	const real_t in_r = x < width - 1 ? f_left[idx + 1] : 0.0f;
	const real_t in_u = y > 0 ? f_down[idx - width] : 0.0f;
	const real_t in_d = y < height - 1 ? f_up[idx + width] : 0.0f;
	const real_t dwx = 0.5 * (in_l - f_left[idx] + f_right[idx] - in_r);
	const real_t dwy = 0.5 * (in_u - f_up[idx] + f_down[idx] - in_d);
	const real_t denom = cell_size * d;
	return Vector2(dwx / denom, dwy / denom);
}

void CgameShallowWater::step(real_t p_delta) {
	if (width == 0 || p_delta <= 0.0) {
		return;
	}
	real_t max_depth = 0.0;
	const float *d = depth.ptr();
	for (int i = 0; i < depth.size(); i++) {
		max_depth = MAX(max_depth, real_t(d[i]));
	}
	// CFL-style substep: wave speed sqrt(g*d) must not cross a cell per substep.
	const real_t wave = Math::sqrt(GRAVITY * MAX(max_depth, real_t(0.01)));
	const real_t max_dt = 0.5 * cell_size / wave;
	const int subs = CLAMP(int(Math::ceil(p_delta / max_dt)), 1, MAX_SUBSTEPS);
	const real_t dt = p_delta / real_t(subs);
	for (int s = 0; s < subs; s++) {
		_substep(dt);
	}
}

void CgameShallowWater::_substep(real_t p_dt) {
	const real_t area = cell_size * cell_size;
	const real_t gain = p_dt * GRAVITY * cell_size;
	const int w = width;
	const int h = height;
	const float *ter = terrain.ptr();
	const float *dep = depth.ptr();
	float *fl_w = f_left.ptrw();
	float *fr_w = f_right.ptrw();
	float *fu_w = f_up.ptrw();
	float *fd_w = f_down.ptrw();

	// Pass 1: update outgoing fluxes. Reads depth/terrain and the cell's own flux only.
	CgameFluids::parallel_for(h, 8, [&](int p_from, int p_to) {
		for (int y = p_from; y < p_to; y++) {
			for (int x = 0; x < w; x++) {
				const int idx = y * w + x;
				const real_t surf = ter[idx] + dep[idx];
				real_t fl = 0.0;
				real_t fr = 0.0;
				real_t fu = 0.0;
				real_t fd = 0.0;
				if (x > 0) {
					fl = MAX(fl_w[idx] * FLUX_DAMPING + gain * (surf - ter[idx - 1] - dep[idx - 1]), real_t(0.0));
				}
				if (x < w - 1) {
					fr = MAX(fr_w[idx] * FLUX_DAMPING + gain * (surf - ter[idx + 1] - dep[idx + 1]), real_t(0.0));
				}
				if (y > 0) {
					fu = MAX(fu_w[idx] * FLUX_DAMPING + gain * (surf - ter[idx - w] - dep[idx - w]), real_t(0.0));
				}
				if (y < h - 1) {
					fd = MAX(fd_w[idx] * FLUX_DAMPING + gain * (surf - ter[idx + w] - dep[idx + w]), real_t(0.0));
				}
				const real_t total = (fl + fr + fu + fd) * p_dt;
				const real_t avail = dep[idx] * area;
				if (total > avail && total > 0.0) {
					const real_t k = avail / total;
					fl *= k;
					fr *= k;
					fu *= k;
					fd *= k;
				}
				fl_w[idx] = fl;
				fr_w[idx] = fr;
				fu_w[idx] = fu;
				fd_w[idx] = fd;
			}
		}
	});

	// Pass 2: update depth from the new fluxes. Each cell writes only its own depth.
	float *dep_w = depth.ptrw();
	const float *fl_r = f_left.ptr();
	const float *fr_r = f_right.ptr();
	const float *fu_r = f_up.ptr();
	const float *fd_r = f_down.ptr();
	CgameFluids::parallel_for(h, 8, [&](int p_from, int p_to) {
		for (int y = p_from; y < p_to; y++) {
			for (int x = 0; x < w; x++) {
				const int idx = y * w + x;
				real_t inflow = 0.0;
				if (x > 0) {
					inflow += fr_r[idx - 1];
				}
				if (x < w - 1) {
					inflow += fl_r[idx + 1];
				}
				if (y > 0) {
					inflow += fd_r[idx - w];
				}
				if (y < h - 1) {
					inflow += fu_r[idx + w];
				}
				const real_t outflow = fl_r[idx] + fr_r[idx] + fu_r[idx] + fd_r[idx];
				dep_w[idx] = MAX(dep_w[idx] + p_dt * (inflow - outflow) / area, real_t(0.0));
			}
		}
	});
}

Ref<Image> CgameShallowWater::depth_image() const {
	ERR_FAIL_COND_V(width == 0, Ref<Image>());
	Vector<uint8_t> raw;
	raw.resize(depth.size() * int(sizeof(float)));
	memcpy(raw.ptrw(), depth.ptr(), raw.size());
	return Image::create_from_data(width, height, false, Image::FORMAT_RF, raw);
}

Ref<Image> CgameShallowWater::surface_image() const {
	ERR_FAIL_COND_V(width == 0, Ref<Image>());
	Vector<uint8_t> raw;
	raw.resize(depth.size() * int(sizeof(float)));
	float *dst = reinterpret_cast<float *>(raw.ptrw());
	const float *t = terrain.ptr();
	const float *d = depth.ptr();
	for (int i = 0; i < depth.size(); i++) {
		dst[i] = t[i] + d[i];
	}
	return Image::create_from_data(width, height, false, Image::FORMAT_RF, raw);
}

void CgameShallowWater::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "grid_w", "grid_h", "cell", "terrain"), &CgameShallowWater::setup);
	ClassDB::bind_method(D_METHOD("add_water", "cell", "depth"), &CgameShallowWater::add_water);
	ClassDB::bind_method(D_METHOD("depth_at", "cell"), &CgameShallowWater::depth_at);
	ClassDB::bind_method(D_METHOD("terrain_at", "cell"), &CgameShallowWater::terrain_at);
	ClassDB::bind_method(D_METHOD("total_volume"), &CgameShallowWater::total_volume);
	ClassDB::bind_method(D_METHOD("velocity_at", "cell"), &CgameShallowWater::velocity_at);
	ClassDB::bind_method(D_METHOD("step", "delta"), &CgameShallowWater::step);
	ClassDB::bind_method(D_METHOD("get_depth"), &CgameShallowWater::get_depth);
	ClassDB::bind_method(D_METHOD("get_terrain"), &CgameShallowWater::get_terrain);
	ClassDB::bind_method(D_METHOD("depth_image"), &CgameShallowWater::depth_image);
	ClassDB::bind_method(D_METHOD("surface_image"), &CgameShallowWater::surface_image);

	CGF_BIND_READONLY_PROPERTY(CgameShallowWater, Variant::INT, width)
	CGF_BIND_READONLY_PROPERTY(CgameShallowWater, Variant::INT, height)
	CGF_BIND_READONLY_PROPERTY(CgameShallowWater, Variant::FLOAT, cell_size)
}
