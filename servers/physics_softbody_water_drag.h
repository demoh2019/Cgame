/**************************************************************************/
/*  physics_softbody_water_drag.h                                         */
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

// Quadratic, two-sided underwater drag of an arbitrarily oriented soft-body
// triangle, clipped against a horizontal water plane. Unlike buoyancy this
// works on open cloth as well as sealed surfaces. The relative water current,
// face normal and optional skin drag affect every moving particle.
//
// Uses one-point quadrature per clipped subtriangle, with barycentric
// interpolation of velocity and nodal force. Damping is integrated implicitly
// for each component to avoid velocity reversal on high-drag time steps.
// The per-subtriangle effective inverse mass is sum(w_i^2 * inv_mass_i).
// No allocations, and all 3 output forces commit atomically on valid inputs.
namespace PhysicsSoftBodyWaterDragInternal {

struct Vertex {
	double position[3];
	double weight[3];
};

_FORCE_INLINE_ Vertex interpolate(const Vertex &p_a, const Vertex &p_b, double p_t) {
	Vertex v;
	for (int i = 0; i < 3; ++i) {
		v.position[i] = p_a.position[i] + p_t * (p_b.position[i] - p_a.position[i]);
		v.weight[i] = p_a.weight[i] + p_t * (p_b.weight[i] - p_a.weight[i]);
	}
	return v;
}

// Fraction of a relative-velocity component removed in one implicit
// quadratic-drag time step. For huge finite inputs, saturate to one instead
// of calculating an indeterminate infinity/infinity ratio.
_FORCE_INLINE_ bool relaxation(double p_strength, double p_speed,
		double p_delta, double p_inverse_mass, double &r_fraction) {
	const double k = p_strength * p_speed * p_delta * p_inverse_mass;
	if (k < 0.0 || Math::is_nan(k)) {
		return false;
	}
	r_fraction = Math::is_finite(k) ? 1.0 - 1.0 / (1.0 + k) : 1.0;
	return true;
}

} // namespace PhysicsSoftBodyWaterDragInternal

_FORCE_INLINE_ bool physics_softbody_water_drag_face(
		const Vector3 p_position[3], const Vector3 p_velocity[3],
		const real_t p_inv_mass[3], real_t p_water_height,
		real_t p_density, real_t p_drag_coefficient,
		real_t p_tangential_ratio, const Vector3 &p_water_flow,
		real_t p_delta, Vector3 r_force[3]) {
	using namespace PhysicsSoftBodyWaterDragInternal;

	if (!Math::is_finite(p_water_height) || !Math::is_finite(p_density) ||
			!Math::is_finite(p_drag_coefficient) || !Math::is_finite(p_tangential_ratio) ||
			!Math::is_finite(p_delta) || !p_water_flow.is_finite() ||
			p_density < 0.0 || p_drag_coefficient < 0.0 ||
			p_tangential_ratio < 0.0 || !(p_delta > 0.0)) {
		return false;
	}
	double inverse_masses[3];
	double positions[3][3];
	double velocities[3][3];
	double sum_inverse_masses = 0.0;
	for (int i = 0; i < 3; ++i) {
		if (!p_position[i].is_finite() || !p_velocity[i].is_finite() ||
				!Math::is_finite(p_inv_mass[i]) || p_inv_mass[i] < 0.0) {
			return false;
		}
		inverse_masses[i] = double(p_inv_mass[i]);
		sum_inverse_masses += inverse_masses[i];
		positions[i][0] = double(p_position[i].x);
		positions[i][1] = double(p_position[i].y);
		positions[i][2] = double(p_position[i].z);
		velocities[i][0] = double(p_velocity[i].x) - double(p_water_flow.x);
		velocities[i][1] = double(p_velocity[i].y) - double(p_water_flow.y);
		velocities[i][2] = double(p_velocity[i].z) - double(p_water_flow.z);
	}
	if (!(sum_inverse_masses > 0.0) || p_density == 0.0 ||
			p_drag_coefficient == 0.0 ||
			(p_position[0].y > p_water_height &&
					p_position[1].y > p_water_height &&
					p_position[2].y > p_water_height)) {
		r_force[0] = Vector3();
		r_force[1] = Vector3();
		r_force[2] = Vector3();
		return true;
	}

	const double ab[3] = {
		positions[1][0] - positions[0][0],
		positions[1][1] - positions[0][1],
		positions[1][2] - positions[0][2]
	};
	const double ac[3] = {
		positions[2][0] - positions[0][0],
		positions[2][1] - positions[0][1],
		positions[2][2] - positions[0][2]
	};
	const double n[3] = {
		ab[1] * ac[2] - ab[2] * ac[1],
		ab[2] * ac[0] - ab[0] * ac[2],
		ab[0] * ac[1] - ab[1] * ac[0]
	};
	const double normal_length = Math::sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
	if (!(normal_length > 0.0) || !Math::is_finite(normal_length)) {
		return false;
	}
	const double normal[3] = {
		n[0] / normal_length, n[1] / normal_length, n[2] / normal_length
	};

	Vertex polygon[6] = {
		{ { positions[0][0], positions[0][1], positions[0][2] }, { 1.0, 0.0, 0.0 } },
		{ { positions[1][0], positions[1][1], positions[1][2] }, { 0.0, 1.0, 0.0 } },
		{ { positions[2][0], positions[2][1], positions[2][2] }, { 0.0, 0.0, 1.0 } }
	};
	Vertex clipped[6];
	int count = 0;
	const double water_height = double(p_water_height);
	for (int i = 0; i < 3; ++i) {
		const Vertex &a = polygon[i];
		const Vertex &b = polygon[(i + 1) % 3];
		const bool a_wet = a.position[1] <= water_height;
		const bool b_wet = b.position[1] <= water_height;
		if (a_wet != b_wet) {
			const double denominator = b.position[1] - a.position[1];
			if (!(Math::abs(denominator) > 0.0)) {
				return false;
			}
			const double t = CLAMP((water_height - a.position[1]) / denominator, 0.0, 1.0);
			if (!Math::is_finite(t)) {
				return false;
			}
			clipped[count++] = interpolate(a, b, t);
		}
		if (b_wet) {
			clipped[count++] = b;
		}
	}
	if (count < 3) {
		r_force[0] = Vector3();
		r_force[1] = Vector3();
		r_force[2] = Vector3();
		return true;
	}

	double accumulated[3][3] = {};
	const double flow_multiplier = 0.5 * double(p_density) * double(p_drag_coefficient);
	const double dt = double(p_delta);
	for (int t = 1; t + 1 < count; ++t) {
		const Vertex *v[3] = { &clipped[0], &clipped[t], &clipped[t + 1] };
		const double u[3] = {
			v[1]->position[0] - v[0]->position[0],
			v[1]->position[1] - v[0]->position[1],
			v[1]->position[2] - v[0]->position[2]
		};
		const double w[3] = {
			v[2]->position[0] - v[0]->position[0],
			v[2]->position[1] - v[0]->position[1],
			v[2]->position[2] - v[0]->position[2]
		};
		const double cross[3] = {
			u[1] * w[2] - u[2] * w[1],
			u[2] * w[0] - u[0] * w[2],
			u[0] * w[1] - u[1] * w[0]
		};
		const double area = 0.5 * Math::sqrt(cross[0] * cross[0] +
				cross[1] * cross[1] + cross[2] * cross[2]);
		if (!Math::is_finite(area)) {
			return false;
		}
		if (!(area > 0.0)) {
			continue;
		}
		double weights[3];
		double inverse_mass = 0.0;
		double velocity[3] = {};
		for (int i = 0; i < 3; ++i) {
			weights[i] = (v[0]->weight[i] + v[1]->weight[i] + v[2]->weight[i]) / 3.0;
			inverse_mass += weights[i] * weights[i] * inverse_masses[i];
			for (int j = 0; j < 3; ++j) {
				velocity[j] += weights[i] * velocities[i][j];
			}
		}
		if (!(inverse_mass > 0.0) || !Math::is_finite(inverse_mass)) {
			continue; // All contributing particles are pinned.
		}
		const double vn = velocity[0] * normal[0] +
				velocity[1] * normal[1] + velocity[2] * normal[2];
		const double tangent[3] = {
			velocity[0] - vn * normal[0],
			velocity[1] - vn * normal[1],
			velocity[2] - vn * normal[2]
		};
		const double tangent_speed = Math::sqrt(tangent[0] * tangent[0] +
				tangent[1] * tangent[1] + tangent[2] * tangent[2]);
		if (!Math::is_finite(vn) || !Math::is_finite(tangent_speed)) {
			return false;
		}
		double normal_fraction = 0.0;
		double tangent_fraction = 0.0;
		if (!relaxation(flow_multiplier * area, Math::abs(vn), dt, inverse_mass, normal_fraction) ||
				(p_tangential_ratio > 0.0 &&
						!relaxation(flow_multiplier * area * double(p_tangential_ratio),
								tangent_speed, dt, inverse_mass, tangent_fraction))) {
			return false;
		}
		const double denom = dt * inverse_mass;
		if (!(denom > 0.0) || !Math::is_finite(denom)) {
			return false;
		}
		double force[3];
		for (int j = 0; j < 3; ++j) {
			force[j] = -(normal[j] * vn * normal_fraction +
					tangent[j] * tangent_fraction) / denom;
		}
		for (int i = 0; i < 3; ++i) {
			if (inverse_masses[i] == 0.0) {
				continue;
			}
			for (int j = 0; j < 3; ++j) {
				accumulated[i][j] += weights[i] * force[j];
			}
		}
	}

	const double max_component = double(std::numeric_limits<real_t>::max());
	Vector3 output[3];
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			if (!Math::is_finite(accumulated[i][j]) ||
					Math::abs(accumulated[i][j]) > max_component) {
				return false;
			}
		}
		output[i] = Vector3(real_t(accumulated[i][0]), real_t(accumulated[i][1]),
				real_t(accumulated[i][2]));
	}
	r_force[0] = output[0];
	r_force[1] = output[1];
	r_force[2] = output[2];
	return true;
}
