/**************************************************************************/
/*  physics_softbody_fluid_clipping.h                                     */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/math/math_funcs.h"
#include "core/math/vector3.h"

// Fixed-size triangle clipping against a horizontal fluid surface.
// Every clipped vertex retains barycentric weights of its original triangle.
// Both hydrostatic pressure and hydrodynamic drag share this exact clipping
// path, so partially immersed triangles have consistent submerged areas.
// Sutherland-Hodgman clipping of 3 vertices by one halfspace yields <=4.
struct PhysicsSoftBodyFluidVertex {
	double x = 0.0;
	double y = 0.0;
	double z = 0.0;
	double bary[3] = { 0.0, 0.0, 0.0 };
};

_FORCE_INLINE_ static bool physics_softbody_clip_fluid_triangle(
		const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c,
		double p_surface_y, PhysicsSoftBodyFluidVertex (&r_clipped)[4],
		int &r_count) {
	if (!p_a.is_finite() || !p_b.is_finite() || !p_c.is_finite() ||
			!Math::is_finite(p_surface_y)) {
		return false;
	}
	PhysicsSoftBodyFluidVertex source[3];
	const Vector3 position[3] = { p_a, p_b, p_c };
	for (int i = 0; i < 3; ++i) {
		source[i].x = double(position[i].x);
		source[i].y = double(position[i].y);
		source[i].z = double(position[i].z);
		source[i].bary[i] = 1.0;
	}
	PhysicsSoftBodyFluidVertex candidates[4];
	int count = 0;
	for (int i = 0; i < 3; ++i) {
		const PhysicsSoftBodyFluidVertex &a = source[i];
		const PhysicsSoftBodyFluidVertex &b = source[(i + 1) % 3];
		const double da = p_surface_y - a.y;
		const double db = p_surface_y - b.y;
		if (!Math::is_finite(da) || !Math::is_finite(db)) {
			return false;
		}
		const bool inside_a = da >= 0.0;
		const bool inside_b = db >= 0.0;
		if (inside_a != inside_b) {
			const double denominator = da - db;
			if (!Math::is_finite(denominator) || denominator == 0.0) {
				return false;
			}
			const double t = CLAMP(da / denominator, 0.0, 1.0);
			PhysicsSoftBodyFluidVertex intersection;
			intersection.x = a.x + (b.x - a.x) * t;
			intersection.y = a.y + (b.y - a.y) * t;
			intersection.z = a.z + (b.z - a.z) * t;
			for (int j = 0; j < 3; ++j) {
				intersection.bary[j] = a.bary[j] + (b.bary[j] - a.bary[j]) * t;
			}
			if (count >= 4) {
				return false;
			}
			candidates[count++] = intersection;
		}
		if (inside_b) {
			if (count >= 4) {
				return false;
			}
			candidates[count++] = b;
		}
	}
	for (int i = 0; i < count; ++i) {
		if (!Math::is_finite(candidates[i].x) || !Math::is_finite(candidates[i].y) ||
				!Math::is_finite(candidates[i].z)) {
			return false;
		}
		for (int j = 0; j < 3; ++j) {
			if (!Math::is_finite(candidates[i].bary[j]) ||
					candidates[i].bary[j] < -1e-12 || candidates[i].bary[j] > 1.0 + 1e-12) {
				return false;
			}
		}
	}
	for (int i = 0; i < count; ++i) {
		r_clipped[i] = candidates[i];
	}
	r_count = count;
	return true;
}
