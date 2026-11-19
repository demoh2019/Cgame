/**************************************************************************/
/*  physics_softbody_hydrostatic_buoyancy.h                               */
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

#include "core/math/vector3.h"

#include <limits>

// Integrate hydrostatic pressure over a face of a CLOSED, consistently wound
// deformable surface. p_outward_sign is +1 for outward and -1 for inward mesh
// winding. The caller must check manifold closure once at mesh setup.
//
// For submerged pressure p = density * g * (water_y - y), the integral of
// p times each original vertex's barycentric shape function gives its force.
// Clipping to y <= water_y yields exact integration for piecewise-linear
// depth and barycentrics, not a face-centroid approximation. This allows
// partly submerged faces to apply correct hydrostatic forces and torques.
//
// No heap allocations. Double intermediates avoid squaring float32 vectors
// and prevent partial commits on non-finite inputs or overflow.
namespace PhysicsSoftBodyHydrostaticInternal {

struct Vertex {
	double x, y, z;
	double weight[3];
};

_FORCE_INLINE_ Vertex intersect(const Vertex &p_a, const Vertex &p_b, double p_t) {
	Vertex v;
	v.x = p_a.x + p_t * (p_b.x - p_a.x);
	v.y = p_a.y + p_t * (p_b.y - p_a.y);
	v.z = p_a.z + p_t * (p_b.z - p_a.z);
	for (int i = 0; i < 3; ++i) {
		v.weight[i] = p_a.weight[i] + p_t * (p_b.weight[i] - p_a.weight[i]);
	}
	return v;
}

} // namespace PhysicsSoftBodyHydrostaticInternal

_FORCE_INLINE_ bool physics_softbody_hydrostatic_face_forces(const Vector3 &p_a,
		const Vector3 &p_b, const Vector3 &p_c, real_t p_water_height,
		real_t p_density, real_t p_gravity, int p_outward_sign,
		Vector3 &r_force_a, Vector3 &r_force_b, Vector3 &r_force_c) {
	using namespace PhysicsSoftBodyHydrostaticInternal;
	if (!p_a.is_finite() || !p_b.is_finite() || !p_c.is_finite() ||
			!Math::is_finite(p_water_height) || !Math::is_finite(p_density) ||
			!Math::is_finite(p_gravity) || p_density < 0.0 || p_gravity < 0.0 ||
			(p_outward_sign != 1 && p_outward_sign != -1)) {
		return false;
	}

	const double abx = double(p_b.x) - double(p_a.x);
	const double aby = double(p_b.y) - double(p_a.y);
	const double abz = double(p_b.z) - double(p_a.z);
	const double acx = double(p_c.x) - double(p_a.x);
	const double acy = double(p_c.y) - double(p_a.y);
	const double acz = double(p_c.z) - double(p_a.z);
	const double nx = aby * acz - abz * acy;
	const double ny = abz * acx - abx * acz;
	const double nz = abx * acy - aby * acx;
	const double normal_len = Math::sqrt(nx * nx + ny * ny + nz * nz);
	if (!(normal_len > 0.0) || !Math::is_finite(normal_len)) {
		return false;
	}

	Vertex poly[6] = {
		{ double(p_a.x), double(p_a.y), double(p_a.z), { 1.0, 0.0, 0.0 } },
		{ double(p_b.x), double(p_b.y), double(p_b.z), { 0.0, 1.0, 0.0 } },
		{ double(p_c.x), double(p_c.y), double(p_c.z), { 0.0, 0.0, 1.0 } }
	};
	int count = 3;
	Vertex clipped[6];
	int out_count = 0;
	const double height = double(p_water_height);
	for (int i = 0; i < count; ++i) {
		const Vertex &start = poly[i];
		const Vertex &end = poly[(i + 1) % count];
		const bool start_in = start.y <= height;
		const bool end_in = end.y <= height;
		if (start_in != end_in) {
			const double denominator = end.y - start.y;
			if (denominator == 0.0) {
				return false;
			}
			const double t = CLAMP((height - start.y) / denominator, 0.0, 1.0);
			clipped[out_count++] = intersect(start, end, t);
		}
		if (end_in) {
			clipped[out_count++] = end;
		}
	}
	if (out_count < 3 || p_density == 0.0 || p_gravity == 0.0) {
		r_force_a = Vector3();
		r_force_b = Vector3();
		r_force_c = Vector3();
		return true;
	}

	double loads[3] = { 0.0, 0.0, 0.0 };
	for (int j = 1; j + 1 < out_count; ++j) {
		const Vertex &v0 = clipped[0];
		const Vertex &v1 = clipped[j];
		const Vertex &v2 = clipped[j + 1];
		const double ux = v1.x - v0.x;
		const double uy = v1.y - v0.y;
		const double uz = v1.z - v0.z;
		const double vx = v2.x - v0.x;
		const double vy = v2.y - v0.y;
		const double vz = v2.z - v0.z;
		const double cx = uy * vz - uz * vy;
		const double cy = uz * vx - ux * vz;
		const double cz = ux * vy - uy * vx;
		const double area = 0.5 * Math::sqrt(cx * cx + cy * cy + cz * cz);
		if (!Math::is_finite(area)) {
			return false;
		}
		if (area == 0.0) {
			continue;
		}
		const double p0 = MAX(0.0, height - v0.y);
		const double p1 = MAX(0.0, height - v1.y);
		const double p2 = MAX(0.0, height - v2.y);
		const double sum_pressure = p0 + p1 + p2;
		for (int k = 0; k < 3; ++k) {
			const double sum_weight = v0.weight[k] + v1.weight[k] + v2.weight[k];
			const double integral = area / 12.0 * (sum_pressure * sum_weight +
					p0 * v0.weight[k] + p1 * v1.weight[k] + p2 * v2.weight[k]);
			loads[k] += integral;
		}
	}

	const double scale = -double(p_outward_sign) * double(p_density) * double(p_gravity) / normal_len;
	Vector3 output[3];
	for (int i = 0; i < 3; ++i) {
		const double fx = scale * loads[i] * nx;
		const double fy = scale * loads[i] * ny;
		const double fz = scale * loads[i] * nz;
		const double max_value = double(std::numeric_limits<real_t>::max());
		if (!Math::is_finite(fx) || !Math::is_finite(fy) || !Math::is_finite(fz) ||
				Math::abs(fx) > max_value || Math::abs(fy) > max_value ||
				Math::abs(fz) > max_value) {
			return false;
		}
		output[i] = Vector3(real_t(fx), real_t(fy), real_t(fz));
	}
	r_force_a = output[0];
	r_force_b = output[1];
	r_force_c = output[2];
	return true;
}
