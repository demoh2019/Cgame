/**************************************************************************/
/*  physics_fem_tetra_inversion_recovery.h                                */
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
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "servers/physics_fem_tetra_neo_hookean.h"

// Conservative inversion recovery inspired by unilateral XPBD tetra volume
// constraints. The positive orientation Jacobian is J = det(Ds) / det(Dm).
// When J falls below min_J (default .05), apply a mass-weighted projected
// correction in the direction of grad(J):
//   lambda = (min_J - J) / sum(w_i |grad(J)_i|^2),
//   x'_i   = x_i + w_i grad(J)_i lambda.
//
// The constraint is nonlinear, so each of 8 Gauss-Seidel passes recomputes
// its gradient; a 12-level backtracking search accepts only progress and
// J <= 1 (avoids recovering an inverted element by grossly inflating it).
// Both the input and output are validated. All four vertices are committed
// atomically, with no allocation or modification of FEM rest matrices.
//
// This is not a topology change. For unreachable configurations (e.g. all
// nodes pinned), the function returns false without changing anything.
// A successful call means progress toward min_J, not a guarantee the target
// was met under extreme deformation. The next solver iteration may continue.
_FORCE_INLINE_ static bool physics_fem_tetra_recovery_jacobian(
		const Vector3 p_points[4], const PhysicsFEMTetraRest &p_rest,
		double &r_jacobian, double r_gradient[4][3]) {
	if (!p_points || !Math::is_finite(p_rest.signed_det) ||
			p_rest.signed_det == 0.0 || !(p_rest.volume > 0.0) ||
			!Math::is_finite(p_rest.volume)) {
		return false;
	}
	for (int i = 0; i < 4; ++i) {
		if (!p_points[i].is_finite()) {
			return false;
		}
	}
	double u[3], v[3], w[3];
	for (int j = 0; j < 3; ++j) {
		u[j] = double(p_points[1][j]) - double(p_points[0][j]);
		v[j] = double(p_points[2][j]) - double(p_points[0][j]);
		w[j] = double(p_points[3][j]) - double(p_points[0][j]);
	}
	const double cu[3] = {
		v[1] * w[2] - v[2] * w[1],
		v[2] * w[0] - v[0] * w[2],
		v[0] * w[1] - v[1] * w[0]
	};
	const double cv[3] = {
		w[1] * u[2] - w[2] * u[1],
		w[2] * u[0] - w[0] * u[2],
		w[0] * u[1] - w[1] * u[0]
	};
	const double cw[3] = {
		u[1] * v[2] - u[2] * v[1],
		u[2] * v[0] - u[0] * v[2],
		u[0] * v[1] - u[1] * v[0]
	};
	const double determinant = u[0] * cu[0] + u[1] * cu[1] + u[2] * cu[2];
	const double jacobian = determinant / p_rest.signed_det;
	if (!Math::is_finite(jacobian)) {
		return false;
	}
	const double inverse_rest_det = 1.0 / p_rest.signed_det;
	double candidate_gradients[4][3];
	for (int j = 0; j < 3; ++j) {
		candidate_gradients[1][j] = cu[j] * inverse_rest_det;
		candidate_gradients[2][j] = cv[j] * inverse_rest_det;
		candidate_gradients[3][j] = cw[j] * inverse_rest_det;
		candidate_gradients[0][j] = -(candidate_gradients[1][j] +
				candidate_gradients[2][j] + candidate_gradients[3][j]);
		for (int vertex = 0; vertex < 4; ++vertex) {
			if (!Math::is_finite(candidate_gradients[vertex][j])) {
				return false;
			}
		}
	}
	for (int vertex = 0; vertex < 4; ++vertex) {
		for (int j = 0; j < 3; ++j) {
			r_gradient[vertex][j] = candidate_gradients[vertex][j];
		}
	}
	r_jacobian = jacobian;
	return true;
}

_FORCE_INLINE_ static bool physics_fem_tetra_recover_orientation(
		Vector3 &r_a, Vector3 &r_b, Vector3 &r_c, Vector3 &r_d,
		real_t p_inv_a, real_t p_inv_b, real_t p_inv_c, real_t p_inv_d,
		const PhysicsFEMTetraRest &p_rest, double p_min_j) {
	if (!Math::is_finite(p_min_j) || !(p_min_j >= 0.001 && p_min_j <= 0.5)) {
		return false;
	}
	const double inverse_mass[4] = { double(p_inv_a), double(p_inv_b), double(p_inv_c), double(p_inv_d) };
	double sum_inverse_mass = 0.0;
	for (int i = 0; i < 4; ++i) {
		if (!Math::is_finite(inverse_mass[i]) || inverse_mass[i] < 0.0) {
			return false;
		}
		sum_inverse_mass += inverse_mass[i];
	}
	if (!(sum_inverse_mass > 0.0) || !Math::is_finite(sum_inverse_mass)) {
		return false;
	}
	Vector3 points[4] = { r_a, r_b, r_c, r_d };
	bool progressed = false;
	for (int iteration = 0; iteration < 8; ++iteration) {
		double jacobian, gradients[4][3];
		if (!physics_fem_tetra_recovery_jacobian(points, p_rest, jacobian, gradients)) {
			break;
		}
		if (jacobian >= p_min_j) {
			break;
		}
		double effective_inverse_mass = 0.0;
		for (int i = 0; i < 4; ++i) {
			for (int j = 0; j < 3; ++j) {
				effective_inverse_mass += inverse_mass[i] * gradients[i][j] * gradients[i][j];
			}
		}
		if (!(effective_inverse_mass > 0.0) || !Math::is_finite(effective_inverse_mass)) {
			break;
		}
		const double correction = (p_min_j - jacobian) / effective_inverse_mass;
		if (!(correction > 0.0) || !Math::is_finite(correction)) {
			break;
		}
		bool accepted = false;
		for (int attempt = 0; attempt < 12; ++attempt) {
			const double step = correction / double(1u << attempt);
			Vector3 next[4];
			bool finite = true;
			for (int i = 0; i < 4; ++i) {
				double c[3];
				for (int j = 0; j < 3; ++j) {
					c[j] = double(points[i][j]) + step * inverse_mass[i] * gradients[i][j];
				}
				next[i] = Vector3(real_t(c[0]), real_t(c[1]), real_t(c[2]));
				finite = finite && next[i].is_finite();
			}
			if (!finite) {
				continue;
			}
			double next_jacobian, next_gradients[4][3];
			if (!physics_fem_tetra_recovery_jacobian(next, p_rest, next_jacobian, next_gradients) ||
					!(next_jacobian > jacobian + 1e-12) ||
					next_jacobian > 1.0 + 1e-9) {
				continue;
			}
			for (int i = 0; i < 4; ++i) {
				points[i] = next[i];
			}
			progressed = accepted = true;
			break;
		}
		if (!accepted) {
			break;
		}
	}
	if (!progressed) {
		return false;
	}
	r_a = points[0];
	r_b = points[1];
	r_c = points[2];
	r_d = points[3];
	return true;
}
