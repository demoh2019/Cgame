/**************************************************************************/
/*  physics_softbody_hydrodynamic_drag.h                                  */
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

#include "servers/physics_softbody_fluid_clipping.h"

#include <limits>

// Quadratic hydrodynamic drag on a partially immersed SoftBody3D triangle.
// Clip to y <= water surface (shared hydrostatic polygon clip); triangulate
// the resulting <=4 vertex polygon on the stack. Sample body velocity at each
// submerged subtriangle centroid via barycentric coordinates of the original
// mesh. Integrate drag as a centroid quadrature per subtriangle:
//
//   J = -(rho * Cd * A / 2) * dt *
//       [ n (u . n) |u . n| + tangent_ratio * u_t |u_t| ]
//   u = v_surface - v_fluid
//
// Each subtriangle impulse is distributed to original vertices according to
// its centroid barycentric weights. Force is independent of face winding;
// unlike hydrostatic pressure, drag does not require a sealed mesh.
//
// Rather than clamping each subtriangle independently (which can overshoot on
// partially immersed quads), sum impulses for the whole face, then perform an
// energy-safe line search. With J_i the nodal impulses and w_i inverse mass,
//   delta E_rel(s) = s * sum_i dot(J_i, v_i-fluid)
//                  + s^2/2 * sum_i w_i |J_i|^2
// Choose s = min(1, -power/quadratic), so relative kinetic energy cannot grow.
// Caller updates velocities IMMEDIATELY after each face; applying all face
// impulses to stale velocities would defeat this guarantee on a dense mesh.
//
// This is an approximate fluid drag law, not Navier-Stokes or two-way coupling.
// All math uses double intermediates; output is committed only after full
// validation. Zero coefficient/density/delta/submersion yields zero velocity
// changes. No allocations and no persistent per-face storage.
_FORCE_INLINE_ static bool physics_softbody_hydrodynamic_drag_face(
		const Vector3 (&p_position)[3], const Vector3 (&p_velocity)[3],
		const real_t (&p_inverse_mass)[3], const Vector3 &p_fluid_velocity,
		double p_surface_y, double p_density, double p_drag_coefficient,
		double p_tangential_ratio, double p_delta,
		Vector3 (&r_delta_velocity)[3]) {
	if (!p_fluid_velocity.is_finite() || !Math::is_finite(p_surface_y) ||
			!Math::is_finite(p_density) || !Math::is_finite(p_drag_coefficient) ||
			!Math::is_finite(p_tangential_ratio) || !Math::is_finite(p_delta) ||
			p_density < 0.0 || p_drag_coefficient < 0.0 ||
			p_tangential_ratio < 0.0 || p_delta < 0.0) {
		return false;
	}
	for (int i = 0; i < 3; ++i) {
		if (!p_position[i].is_finite() || !p_velocity[i].is_finite() ||
				!Math::is_finite(p_inverse_mass[i]) || p_inverse_mass[i] < real_t(0.0)) {
			return false;
		}
	}
	PhysicsSoftBodyFluidVertex clipped[4];
	int count = 0;
	if (!physics_softbody_clip_fluid_triangle(
			p_position[0], p_position[1], p_position[2], p_surface_y, clipped, count)) {
		return false;
	}
	Vector3 zero[3];
	if (count < 3 || p_density == 0.0 || p_drag_coefficient == 0.0 || p_delta == 0.0 ||
			(p_inverse_mass[0] == 0.0 && p_inverse_mass[1] == 0.0 && p_inverse_mass[2] == 0.0)) {
		for (int i = 0; i < 3; ++i) {
			r_delta_velocity[i] = zero[i];
		}
		return true;
	}

	const double fluid[3] = {
		double(p_fluid_velocity.x),
		double(p_fluid_velocity.y),
		double(p_fluid_velocity.z),
	};
	const double velocity[3][3] = {
		{ double(p_velocity[0].x), double(p_velocity[0].y), double(p_velocity[0].z) },
		{ double(p_velocity[1].x), double(p_velocity[1].y), double(p_velocity[1].z) },
		{ double(p_velocity[2].x), double(p_velocity[2].y), double(p_velocity[2].z) },
	};
	double impulses[3][3] = {};
	for (int triangle = 1; triangle + 1 < count; ++triangle) {
		const PhysicsSoftBodyFluidVertex &a = clipped[0];
		const PhysicsSoftBodyFluidVertex &b = clipped[triangle];
		const PhysicsSoftBodyFluidVertex &c = clipped[triangle + 1];
		const double e1[3] = { b.x - a.x, b.y - a.y, b.z - a.z };
		const double e2[3] = { c.x - a.x, c.y - a.y, c.z - a.z };
		const double cross[3] = {
			e1[1] * e2[2] - e1[2] * e2[1],
			e1[2] * e2[0] - e1[0] * e2[2],
			e1[0] * e2[1] - e1[1] * e2[0],
		};
		const double cross_length = Math::sqrt(
				cross[0] * cross[0] + cross[1] * cross[1] + cross[2] * cross[2]);
		if (!Math::is_finite(cross_length)) {
			return false;
		}
		if (!(cross_length > 0.0)) {
			continue;
		}
		const double area = cross_length * 0.5;
		const double normal[3] = {
			cross[0] / cross_length, cross[1] / cross_length, cross[2] / cross_length,
		};
		const double bary[3] = {
			(a.bary[0] + b.bary[0] + c.bary[0]) / 3.0,
			(a.bary[1] + b.bary[1] + c.bary[1]) / 3.0,
			(a.bary[2] + b.bary[2] + c.bary[2]) / 3.0,
		};
		double relative[3] = { -fluid[0], -fluid[1], -fluid[2] };
		for (int node = 0; node < 3; ++node) {
			for (int component = 0; component < 3; ++component) {
				relative[component] += bary[node] * velocity[node][component];
			}
		}
		const double vn = relative[0] * normal[0] +
				relative[1] * normal[1] + relative[2] * normal[2];
		const double tangent[3] = {
			relative[0] - vn * normal[0],
			relative[1] - vn * normal[1],
			relative[2] - vn * normal[2],
		};
		const double tangential_speed = Math::sqrt(
				tangent[0] * tangent[0] + tangent[1] * tangent[1] + tangent[2] * tangent[2]);
		const double strength = 0.5 * p_density * p_drag_coefficient * area * p_delta;
		if (!Math::is_finite(strength) || !Math::is_finite(tangential_speed)) {
			return false;
		}
		for (int component = 0; component < 3; ++component) {
			const double impulse = -strength * (
					vn * Math::abs(vn) * normal[component] +
					p_tangential_ratio * tangential_speed * tangent[component]);
			if (!Math::is_finite(impulse)) {
				return false;
			}
			for (int node = 0; node < 3; ++node) {
				impulses[node][component] += bary[node] * impulse;
			}
		}
	}

	double power = 0.0;
	double quadratic = 0.0;
	for (int node = 0; node < 3; ++node) {
		for (int component = 0; component < 3; ++component) {
			const double impulse = impulses[node][component];
			power += impulse * (velocity[node][component] - fluid[component]);
			quadratic += double(p_inverse_mass[node]) * impulse * impulse;
		}
	}
	if (!Math::is_finite(power) || !Math::is_finite(quadratic)) {
		return false;
	}
	if (!(power < 0.0) || !(quadratic > 0.0)) {
		for (int i = 0; i < 3; ++i) {
			r_delta_velocity[i] = Vector3();
		}
		return true;
	}
	// -power/quadratic minimizes quadratic relative kinetic energy;
	// scaling is applied after summing all submerged subtriangles.
	const double scale = MIN(1.0, -power / quadratic);
	if (!Math::is_finite(scale) || !(scale >= 0.0)) {
		return false;
	}
	Vector3 candidate[3];
	const double max_coord = double(std::numeric_limits<real_t>::max());
	for (int node = 0; node < 3; ++node) {
		double v[3];
		for (int component = 0; component < 3; ++component) {
			v[component] = double(p_inverse_mass[node]) * impulses[node][component] * scale;
			if (!Math::is_finite(v[component]) || Math::abs(v[component]) > max_coord ||
					!Math::is_finite(v[component] + velocity[node][component])) {
				return false;
			}
		}
		candidate[node] = Vector3(real_t(v[0]), real_t(v[1]), real_t(v[2]));
		if (!candidate[node].is_finite() || !(p_velocity[node] + candidate[node]).is_finite()) {
			return false;
		}
	}
	for (int i = 0; i < 3; ++i) {
		r_delta_velocity[i] = candidate[i];
	}
	return true;
}
