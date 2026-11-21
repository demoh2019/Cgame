/**************************************************************************/
/*  cgame_hydraulic_erosion.cpp                                           */
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

#include "cgame_hydraulic_erosion.h"

#include "core/object/class_db.h"

#include "cgame_worldgen_util.h"

#include "core/math/math_funcs.h"
#include "core/math/random_number_generator.h"

Dictionary CgameHydraulicErosion::get_default_params() {
	Dictionary d;
	d["inertia"] = 0.05;
	d["capacity"] = 4.0;
	d["deposition"] = 0.3;
	d["erosion"] = 0.3;
	d["evaporation"] = 0.02;
	d["gravity"] = 4.0;
	d["max_lifetime"] = 30;
	d["erosion_radius"] = 2;
	d["min_slope"] = 0.01;
	return d;
}

CgameHydraulicErosion::Sample CgameHydraulicErosion::_height_and_gradient(const float *p_map, int p_width, int p_ix, int p_iy, double p_fx, double p_fy) {
	const int i = p_iy * p_width + p_ix;
	const double h00 = p_map[i];
	const double h10 = p_map[i + 1];
	const double h01 = p_map[i + p_width];
	const double h11 = p_map[i + p_width + 1];
	Sample s;
	s.gx = (float)((h10 - h00) * (1.0 - p_fy) + (h11 - h01) * p_fy);
	s.gy = (float)((h01 - h00) * (1.0 - p_fx) + (h11 - h10) * p_fx);
	s.h = (float)(h00 * (1.0 - p_fx) * (1.0 - p_fy) + h10 * p_fx * (1.0 - p_fy) + h01 * (1.0 - p_fx) * p_fy + h11 * p_fx * p_fy);
	return s;
}

void CgameHydraulicErosion::_deposit(float *p_map, int p_width, int p_ix, int p_iy, double p_fx, double p_fy, double p_amount) {
	const int i = p_iy * p_width + p_ix;
	p_map[i] += p_amount * (1.0 - p_fx) * (1.0 - p_fy);
	p_map[i + 1] += p_amount * p_fx * (1.0 - p_fy);
	p_map[i + p_width] += p_amount * (1.0 - p_fx) * p_fy;
	p_map[i + p_width + 1] += p_amount * p_fx * p_fy;
}

double CgameHydraulicErosion::_erode_brush(float *p_map, int p_width, int p_height, int p_cx, int p_cy, double p_amount, int p_radius) {
	if (p_amount <= 0.0) {
		return 0.0;
	}
	const double r2 = (double)p_radius * (double)p_radius;
	double weight_sum = 0.0;
	for (int oy = -p_radius; oy <= p_radius; oy++) {
		for (int ox = -p_radius; ox <= p_radius; ox++) {
			const double d2 = (double)(ox * ox + oy * oy);
			if (d2 > r2) {
				continue;
			}
			const int x = p_cx + ox;
			const int y = p_cy + oy;
			if (x < 0 || y < 0 || x >= p_width || y >= p_height) {
				continue;
			}
			weight_sum += 1.0 - Math::sqrt(d2) / (double)(p_radius + 1);
		}
	}
	if (weight_sum <= 0.0) {
		return 0.0;
	}
	double removed = 0.0;
	for (int oy = -p_radius; oy <= p_radius; oy++) {
		for (int ox = -p_radius; ox <= p_radius; ox++) {
			const double d2 = (double)(ox * ox + oy * oy);
			if (d2 > r2) {
				continue;
			}
			const int x = p_cx + ox;
			const int y = p_cy + oy;
			if (x < 0 || y < 0 || x >= p_width || y >= p_height) {
				continue;
			}
			const double w = (1.0 - Math::sqrt(d2) / (double)(p_radius + 1)) / weight_sum;
			const int idx = y * p_width + x;
			const double cut = p_amount * w;
			p_map[idx] -= cut;
			removed += cut;
		}
	}
	return removed;
}

PackedFloat32Array CgameHydraulicErosion::erode(const PackedFloat32Array &p_heights, int p_width, int p_height, int p_droplets, int64_t p_seed, const Dictionary &p_params) {
	PackedFloat32Array result = p_heights.duplicate();
	if (p_width < 3 || p_height < 3 || (int64_t)p_heights.size() != (int64_t)p_width * p_height) {
		return result;
	}
	Dictionary p = get_default_params();
	p.merge(p_params, true);
	const double inertia = CLAMP((double)p["inertia"], 0.0, 0.99);
	const double capacity_k = p["capacity"];
	const double deposition_k = CLAMP((double)p["deposition"], 0.0, 1.0);
	const double erosion_k = CLAMP((double)p["erosion"], 0.0, 1.0);
	const double evaporation = CLAMP((double)p["evaporation"], 0.0, 1.0);
	const double gravity = p["gravity"];
	const int max_life = p["max_lifetime"];
	const int radius = MAX(1, (int)p["erosion_radius"]);
	const double min_slope = p["min_slope"];

	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed((uint64_t)p_seed);

	float *map = result.ptrw();
	const int width = p_width;
	const int height = p_height;

	for (int d = 0; d < p_droplets; d++) {
		double px = rng->randf_range(1.0, (double)width - 2.001);
		double py = rng->randf_range(1.0, (double)height - 2.001);
		double dx = 0.0;
		double dy = 0.0;
		double speed = 1.0;
		double water = 1.0;
		double sediment = 0.0;
		for (int step = 0; step < max_life; step++) {
			const int ix = (int)px;
			const int iy = (int)py;
			const double fx = px - (double)ix;
			const double fy = py - (double)iy;
			const Sample g = _height_and_gradient(map, width, ix, iy, fx, fy);
			dx = dx * inertia - (double)g.gx * (1.0 - inertia);
			dy = dy * inertia - (double)g.gy * (1.0 - inertia);
			const double len = Math::sqrt(dx * dx + dy * dy);
			if (len < 0.00001) {
				break;
			}
			dx /= len;
			dy /= len;
			const double nx = px + dx;
			const double ny = py + dy;
			if (nx < 1.0 || nx >= (double)width - 2.0 || ny < 1.0 || ny >= (double)height - 2.0) {
				// Leaving the map: drop the load where we stand so mass stays put.
				_deposit(map, width, ix, iy, fx, fy, sediment);
				sediment = 0.0;
				break;
			}
			const int nix = (int)nx;
			const int niy = (int)ny;
			const double new_h = _height_and_gradient(map, width, nix, niy, nx - (double)nix, ny - (double)niy).h;
			const double delta_h = new_h - (double)g.h;
			const double cap = MAX(-delta_h, min_slope) * speed * water * capacity_k;
			if (sediment > cap || delta_h > 0.0) {
				const double amount = delta_h > 0.0 ? MIN(sediment, delta_h) : (sediment - cap) * deposition_k;
				sediment -= amount;
				_deposit(map, width, ix, iy, fx, fy, amount);
			} else {
				const double take = MIN((cap - sediment) * erosion_k, -delta_h);
				sediment += _erode_brush(map, width, height, ix, iy, take, radius);
			}
			speed = Math::sqrt(MAX(speed * speed + delta_h * -gravity, 0.0));
			water *= 1.0 - evaporation;
			px = nx;
			py = ny;
		}
		if (sediment > 0.0) {
			_deposit(map, width, (int)px, (int)py, px - Math::floor(px), py - Math::floor(py), sediment);
		}
	}
	return result;
}

PackedFloat32Array CgameHydraulicErosion::thermal(const PackedFloat32Array &p_heights, int p_width, int p_height, int p_iterations, double p_talus) {
	PackedFloat32Array result = p_heights.duplicate();
	if (p_width < 3 || p_height < 3 || (int64_t)p_heights.size() != (int64_t)p_width * p_height) {
		return result;
	}
	const int w = p_width;
	const int h = p_height;
	const int64_t cells = (int64_t)w * h;
	const bool threaded = cells >= CgameWorldgen::PARALLEL_CELL_THRESHOLD;
	static const int OX[4] = { 1, -1, 0, 0 };
	static const int OY[4] = { 0, 0, 1, -1 };
	const double talus = p_talus;

	Vector<double> total;
	Vector<double> move;
	total.resize(cells);
	move.resize(cells);
	PackedFloat32Array next;
	next.resize(cells);

	for (int iter = 0; iter < p_iterations; iter++) {
		const float *map = result.ptr();
		double *total_w = total.ptrw();
		double *move_w = move.ptrw();
		float *next_w = next.ptrw();

		// Pass 1: how much every cell gives away (read only on the heights).
		CgameWorldgen::parallel_for(h, threaded, [&](int y) {
			for (int x = 0; x < w; x++) {
				const int i = y * w + x;
				const double hh = map[i];
				double tot = 0.0;
				double biggest = 0.0;
				for (int k = 0; k < 4; k++) {
					const int nx = x + OX[k];
					const int ny = y + OY[k];
					if (nx < 0 || ny < 0 || nx >= w || ny >= h) {
						continue;
					}
					const double d = hh - (double)map[ny * w + nx];
					if (d > talus) {
						tot += d - talus;
						biggest = MAX(biggest, d - talus);
					}
				}
				total_w[i] = tot;
				// Move at most half the largest excess so neighbours cannot overshoot.
				move_w[i] = tot > 0.0 ? biggest * 0.5 : 0.0;
			}
		});

		// Pass 2: gather. Contributions are applied in the same order the serial scatter loop would
		// produce (up, left, self, right, down), so the result is identical to a serial run.
		CgameWorldgen::parallel_for(h, threaded, [&](int y) {
			for (int x = 0; x < w; x++) {
				const int i = y * w + x;
				float acc = map[i];
				const double hi = map[i];
				// Incoming share from the neighbour at (x + sx, y + sy).
				auto inflow = [&](int sx, int sy) {
					const int nx = x + sx;
					const int ny = y + sy;
					if (nx < 0 || ny < 0 || nx >= w || ny >= h) {
						return;
					}
					const int j = ny * w + nx;
					if (total_w[j] <= 0.0) {
						return;
					}
					const double d = (double)map[j] - hi;
					if (d > talus) {
						acc += move_w[j] * (d - talus) / total_w[j];
					}
				};
				inflow(0, -1);
				inflow(-1, 0);
				if (total_w[i] > 0.0) {
					for (int k = 0; k < 4; k++) {
						const int nx = x + OX[k];
						const int ny = y + OY[k];
						if (nx < 0 || ny < 0 || nx >= w || ny >= h) {
							continue;
						}
						const double d = hi - (double)map[ny * w + nx];
						if (d > talus) {
							acc -= move_w[i] * (d - talus) / total_w[i];
						}
					}
				}
				inflow(1, 0);
				inflow(0, 1);
				next_w[i] = acc;
			}
		});
		SWAP(result, next);
	}
	return result;
}

double CgameHydraulicErosion::max_slope(const PackedFloat32Array &p_heights, int p_width, int p_height) {
	double best = 0.0;
	if ((int64_t)p_heights.size() != (int64_t)p_width * p_height) {
		return best;
	}
	const float *hs = p_heights.ptr();
	for (int y = 0; y < p_height; y++) {
		for (int x = 0; x < p_width; x++) {
			const double h = hs[y * p_width + x];
			if (x + 1 < p_width) {
				best = MAX(best, Math::abs(h - (double)hs[y * p_width + x + 1]));
			}
			if (y + 1 < p_height) {
				best = MAX(best, Math::abs(h - (double)hs[(y + 1) * p_width + x]));
			}
		}
	}
	return best;
}

void CgameHydraulicErosion::_bind_methods() {
	ClassDB::bind_static_method("CgameHydraulicErosion", D_METHOD("get_default_params"), &CgameHydraulicErosion::get_default_params);
	ClassDB::bind_static_method("CgameHydraulicErosion", D_METHOD("erode", "heights", "width", "height", "droplets", "seed", "params"), &CgameHydraulicErosion::erode, DEFVAL(Dictionary()));
	ClassDB::bind_static_method("CgameHydraulicErosion", D_METHOD("thermal", "heights", "width", "height", "iterations", "talus"), &CgameHydraulicErosion::thermal, DEFVAL(0.6));
	ClassDB::bind_static_method("CgameHydraulicErosion", D_METHOD("max_slope", "heights", "width", "height"), &CgameHydraulicErosion::max_slope);
}
