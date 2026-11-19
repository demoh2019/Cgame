/**************************************************************************/
/*  physics_fem_tetra_fiber.h                                             */
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
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "servers/physics_fem_tetra_neo_hookean.h"

// Tension-only, material-coordinate fiber reinforcement for a Neo-Hookean
// tetrahedron. A rest-space unit direction a0 is transported by the
// deformation gradient F = Ds * inverse(Dm). The stretch |F*a0| is
// invariant under rigid world rotation of a deformed element.
//
// XPBD inequality: C=sqrt(rest_volume)*(rest_stretch-|F*a0|) >= 0,
// lambda >= 0. Plastic rest stretch is optional; defaults to one.
// Only FIBER TENSION generates resistance; it never artificially stiffens
// buckling/compression. Four positional gradients are derived exactly
// from the linear tetrahedral shape functions (sum of gradients = 0).
// A one-sided multiplier is retained across iterations within one step.
// Inversions are guarded by up to 12 backtracking trials. Outputs are
// validated and committed together; all hot-path storage is on the stack.
_FORCE_INLINE_ static bool physics_fem_tetra_solve_fiber(
		Vector3 &r_a, Vector3 &r_b, Vector3 &r_c, Vector3 &r_d,
		real_t p_inv_a, real_t p_inv_b, real_t p_inv_c, real_t p_inv_d,
		const PhysicsFEMTetraRest &p_rest, const Vector3 &p_material_axis,
		double p_alpha, double &r_lambda, double p_plastic_rest_stretch = 1.0) {
	if (!r_a.is_finite() || !r_b.is_finite() || !r_c.is_finite() || !r_d.is_finite() ||
			!p_material_axis.is_finite() || !(p_rest.volume > 0.0) ||
			!Math::is_finite(p_rest.volume) || !Math::is_finite(p_rest.signed_det) ||
			p_rest.signed_det == 0.0 || !Math::is_finite(p_alpha) ||
			p_alpha < 0.0 || !Math::is_finite(r_lambda) || r_lambda < 0.0 ||
			!(p_plastic_rest_stretch >= 1.0) || p_plastic_rest_stretch > 16.0 ||
			!Math::is_finite(p_plastic_rest_stretch)) {
		return false;
	}
	const double inv_mass[4] = {
		double(p_inv_a), double(p_inv_b), double(p_inv_c), double(p_inv_d)
	};
	for (int v = 0; v < 4; ++v) {
		if (!(inv_mass[v] >= 0.0) || !Math::is_finite(inv_mass[v])) {
			return false;
		}
	}
	const double axis[3] = {
		double(p_material_axis.x), double(p_material_axis.y),
		double(p_material_axis.z)
	};
	const double axis_sq = axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2];
	if (!(axis_sq > 0.0) || !Math::is_finite(axis_sq)) {
		return false;
	}
	const double axis_inv_len = 1.0 / Math::sqrt(axis_sq);
	double fiber_coeff[4] = {};
	for (int v = 1; v < 4; ++v) {
		for (int k = 0; k < 3; ++k) {
			const double inv = p_rest.inv_dm[v - 1][k];
			if (!Math::is_finite(inv)) {
				return false;
			}
			fiber_coeff[v] += inv * axis[k] * axis_inv_len;
		}
		if (!Math::is_finite(fiber_coeff[v])) {
			return false;
		}
		fiber_coeff[0] -= fiber_coeff[v];
	}
	const Vector3 previous[4] = { r_a, r_b, r_c, r_d };
	double edge[3][3] = {};
	double fiber[3] = {};
	for (int v = 1; v < 4; ++v) {
		for (int axis_index = 0; axis_index < 3; ++axis_index) {
			edge[axis_index][v - 1] = double(previous[v][axis_index]) -
					double(previous[0][axis_index]);
			fiber[axis_index] += edge[axis_index][v - 1] * fiber_coeff[v];
		}
	}
	// A pre-existing inverted FEM element must not be repaired by a fiber
	// projection. Neo-Hookean elasticity owns inversion recovery.
	const double initial_det =
			edge[0][0] * (edge[1][1] * edge[2][2] - edge[1][2] * edge[2][1]) +
			edge[1][0] * (edge[2][1] * edge[0][2] - edge[0][1] * edge[2][2]) +
			edge[2][0] * (edge[0][1] * edge[1][2] - edge[1][1] * edge[0][2]);
	if (!(initial_det / p_rest.signed_det > 1e-9) || !Math::is_finite(initial_det)) {
		return false;
	}
	const double stretch_sq =
			fiber[0] * fiber[0] + fiber[1] * fiber[1] + fiber[2] * fiber[2];
	if (!(stretch_sq > 0.0) || !Math::is_finite(stretch_sq)) {
		return false;
	}
	const double stretch = Math::sqrt(stretch_sq);
	const double scale = Math::sqrt(p_rest.volume);
	const double constraint = scale * (p_plastic_rest_stretch - stretch);
	if (!(constraint < 0.0) && r_lambda == 0.0) {
		return false; // Slack: no force until the material fiber is stretched.
	}
	double g[4][3] = {};
	double mass = 0.0;
	for (int v = 0; v < 4; ++v) {
		for (int axis_index = 0; axis_index < 3; ++axis_index) {
			g[v][axis_index] = -scale * fiber_coeff[v] * fiber[axis_index] / stretch;
			mass += inv_mass[v] * g[v][axis_index] * g[v][axis_index];
		}
	}
	const double denominator = mass + p_alpha;
	if (!(mass > 0.0) || !(denominator > 0.0) ||
			!Math::is_finite(mass) || !Math::is_finite(denominator) ||
			!Math::is_finite(constraint)) {
		return false;
	}
	const double delta_lambda = -(constraint + p_alpha * r_lambda) / denominator;
	if (!Math::is_finite(delta_lambda)) {
		return false;
	}
	const double target_lambda = MAX(0.0, r_lambda + delta_lambda);
	if (!Math::is_finite(target_lambda)) {
		return false;
	}
	const double step = target_lambda - r_lambda;
	if (step == 0.0) {
		return false;
	}
	for (int attempt = 0; attempt < 12; ++attempt) {
		const double fraction = 1.0 / double(1u << attempt);
		Vector3 next[4];
		bool valid = true;
		for (int v = 0; v < 4; ++v) {
			next[v] = Vector3(
					real_t(double(previous[v].x) + fraction * step * inv_mass[v] * g[v][0]),
					real_t(double(previous[v].y) + fraction * step * inv_mass[v] * g[v][1]),
					real_t(double(previous[v].z) + fraction * step * inv_mass[v] * g[v][2]));
			valid = valid && next[v].is_finite();
		}
		if (!valid) {
			continue;
		}
		const double u[3] = {
			double(next[1].x) - double(next[0].x),
			double(next[1].y) - double(next[0].y),
			double(next[1].z) - double(next[0].z)
		};
		const double v[3] = {
			double(next[2].x) - double(next[0].x),
			double(next[2].y) - double(next[0].y),
			double(next[2].z) - double(next[0].z)
		};
		const double w[3] = {
			double(next[3].x) - double(next[0].x),
			double(next[3].y) - double(next[0].y),
			double(next[3].z) - double(next[0].z)
		};
		const double determinant =
				u[0] * (v[1] * w[2] - v[2] * w[1]) +
				u[1] * (v[2] * w[0] - v[0] * w[2]) +
				u[2] * (v[0] * w[1] - v[1] * w[0]);
		if (!(determinant / p_rest.signed_det > 1e-9) ||
				!Math::is_finite(determinant)) {
			continue; // Never invert a positive-J Neo-Hookean element.
		}
		const double updated_lambda = r_lambda + step * fraction;
		if (!Math::is_finite(updated_lambda) || updated_lambda < 0.0) {
			continue;
		}
		r_a = next[0];
		r_b = next[1];
		r_c = next[2];
		r_d = next[3];
		r_lambda = updated_lambda;
		return true;
	}
	return false;
}
