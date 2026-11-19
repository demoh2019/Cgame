/**************************************************************************/
/*  physics_pbf_3d.h                                                      */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/math/vector3.h"

// 3D poly6 SPH kernel, compactly supported on [0, h]. Its analytic
// gradient is used in BOTH the PBF density constraint and its correction:
// mixing unrelated kernels would produce a non-conservative constraint.
// Normalized to integral W(r)dV = 1; all intermediate products are double.
struct PhysicsPBFKernel3D {
	static _FORCE_INLINE_ real_t poly6(double p_distance_squared, double p_h) {
		if (!(p_h > 0.0) || !Math::is_finite(p_h) ||
				!(p_distance_squared >= 0.0) || !Math::is_finite(p_distance_squared)) {
			return 0.0;
		}
		const double q2 = p_distance_squared / (p_h * p_h);
		if (!(q2 < 1.0)) {
			return 0.0;
		}
		const double t = 1.0 - q2;
		const double result = (315.0 / (64.0 * Math::PI)) * t * t * t / (p_h * p_h * p_h);
		return Math::is_finite(result) ? real_t(result) : real_t(0.0);
	}

	static _FORCE_INLINE_ Vector3 gradient(const Vector3 &p_displacement, double p_h) {
		if (!p_displacement.is_finite() || !(p_h > 0.0) || !Math::is_finite(p_h)) {
			return Vector3();
		}
		const double dx = double(p_displacement.x);
		const double dy = double(p_displacement.y);
		const double dz = double(p_displacement.z);
		const double r2 = dx * dx + dy * dy + dz * dz;
		const double q2 = r2 / (p_h * p_h);
		if (!(r2 > 0.0) || !(q2 < 1.0)) {
			return Vector3();
		}
		const double t = 1.0 - q2;
		const double factor = -(945.0 / (32.0 * Math::PI)) *
				t * t / (p_h * p_h * p_h * p_h * p_h);
		const Vector3 result(real_t(dx * factor), real_t(dy * factor), real_t(dz * factor));
		return result.is_finite() ? result : Vector3();
	}

	// PBF artificial pressure discourages tensile clumping; the ratio
	// is normalized to the kernel at 0.3*h. Not a real gas pressure.
	static _FORCE_INLINE_ real_t artificial_pressure(double p_distance_squared, double p_h, real_t p_strength) {
		if (!(p_strength > 0.0) || !Math::is_finite(p_strength)) {
			return 0.0;
		}
		const double denominator = poly6(0.09 * p_h * p_h, p_h);
		if (!(denominator > 0.0)) {
			return 0.0;
		}
		const double ratio = double(poly6(p_distance_squared, p_h)) / denominator;
		const double square = ratio * ratio;
		const double correction = -double(p_strength) * square * square;
		return Math::is_finite(correction) ? real_t(correction) : real_t(0.0);
	}
};

// Deterministic integer grid sort: no hash collisions, per-frame map
// allocation, or unbounded neighbor traversal. Each query binary-searches
// its first entry and scans at most max_neighbors across adjacent cells.
// Index breaks ties within a cell so identical inputs give identical order.
struct PhysicsPBFCell3D {
	int x = 0;
	int y = 0;
	int z = 0;
	int index = 0;

	_FORCE_INLINE_ bool operator<(const PhysicsPBFCell3D &p_other) const {
		if (x != p_other.x) {
			return x < p_other.x;
		}
		if (y != p_other.y) {
			return y < p_other.y;
		}
		if (z != p_other.z) {
			return z < p_other.z;
		}
		return index < p_other.index;
	}
};

_FORCE_INLINE_ int physics_pbf_find_cell_begin_3d(
		const PhysicsPBFCell3D *p_cells, int p_count,
		int p_x, int p_y, int p_z) {
	int low = 0;
	int high = p_count;
	while (low < high) {
		const int mid = low + ((high - low) >> 1);
		const PhysicsPBFCell3D &cell = p_cells[mid];
		const bool precedes = cell.x < p_x ||
				(cell.x == p_x && (cell.y < p_y ||
				(cell.y == p_y && cell.z < p_z)));
		if (precedes) {
			low = mid + 1;
		} else {
			high = mid;
		}
	}
	return low;
}
