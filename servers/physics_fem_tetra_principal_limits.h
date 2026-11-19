/**************************************************************************/
/*  physics_fem_tetra_principal_limits.h                                       */
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

#include "servers/physics_fem_tetra_neo_hookean.h"

// Independent XPBD unilateral limits on the MINIMUM and MAXIMUM singular
// value of a tetrahedral deformation gradient F = Ds * inv(Dm).
//
// This captures the full 3D principal stretch/shear, unlike per-edge strain
// limits on the shell. Each principal stretch sigma_i is sqrt(eigenvalue_i)
// of the right Cauchy-Green tensor C = F^T F. The exact gradient
//   d sigma / d F = (F*u) u^T / sigma
// uses its material-frame right singular vector u. It is invariant under
// rigid translations/rotations and works for reversed REST face winding.
//
// Each cap is unilateral: max(sigma) <= upper, min(sigma) >= lower.
// Both constraints use positive violation C and a non-positive XPBD
// multiplier. A pair of lambdas persists within a tick, reset at the next.
// This local safety constraint does not replace real hyperelastic stresses,
// mesh topology, or volumetric inversion recovery. Inverted tets are rejected.

struct PhysicsFEMTetraPrincipalLambdas {
	double minimum = 0.0;
	double maximum = 0.0;
};

_FORCE_INLINE_ bool physics_fem_tetra_principal_spectrum(
		const Vector3 p_x[4], const PhysicsFEMTetraRest &p_rest,
		double r_singular[3], double r_axes[3][3], double r_f[3][3]) {
	if (!p_x || !r_singular || !r_axes || !r_f ||
			!(p_rest.volume > 0.0) || !Math::is_finite(p_rest.volume) ||
			!Math::is_finite(p_rest.signed_det) || p_rest.signed_det == 0.0) {
		return false;
	}
	for (int i = 0; i < 4; ++i) {
		if (!p_x[i].is_finite()) {
			return false;
		}
	}
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			if (!Math::is_finite(p_rest.inv_dm[i][j])) {
				return false;
			}
		}
	}
	double ds[3][3], f[3][3], c[3][3] = {};
	for (int row = 0; row < 3; ++row) {
		for (int col = 0; col < 3; ++col) {
			ds[row][col] = double(p_x[col + 1][row]) - double(p_x[0][row]);
		}
	}
	for (int row = 0; row < 3; ++row) {
		for (int col = 0; col < 3; ++col) {
			f[row][col] = 0.0;
			for (int j = 0; j < 3; ++j) {
				f[row][col] += ds[row][j] * p_rest.inv_dm[j][col];
			}
			if (!Math::is_finite(f[row][col])) {
				return false;
			}
		}
	}
	const double det = f[0][0] * (f[1][1] * f[2][2] - f[1][2] * f[2][1]) -
			f[0][1] * (f[1][0] * f[2][2] - f[1][2] * f[2][0]) +
			f[0][2] * (f[1][0] * f[2][1] - f[1][1] * f[2][0]);
	if (!(det > 1e-9) || !Math::is_finite(det)) {
		return false;
	}
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			for (int k = 0; k < 3; ++k) {
				c[i][j] += f[k][i] * f[k][j];
			}
			if (!Math::is_finite(c[i][j])) {
				return false;
			}
		}
	}
	// Deterministic cyclic Jacobi diagonalization of symmetric C (3x3).
	double v[3][3] = {
		{ 1.0, 0.0, 0.0 },
		{ 0.0, 1.0, 0.0 },
		{ 0.0, 0.0, 1.0 }
	};
	for (int sweep = 0; sweep < 20; ++sweep) {
		bool changed = false;
		for (int pair = 0; pair < 3; ++pair) {
			const int p = pair == 0 ? 0 : (pair == 1 ? 0 : 1);
			const int q = pair == 0 ? 1 : 2;
			const double apq = c[p][q];
			const double scale = Math::sqrt(Math::abs(c[p][p] * c[q][q]));
			if (Math::abs(apq) <= 1e-15 * MAX(1.0, scale)) {
				continue;
			}
			changed = true;
			const double tau = (c[q][q] - c[p][p]) / (2.0 * apq);
			const double t = (tau >= 0.0 ? 1.0 : -1.0) /
					(Math::abs(tau) + Math::sqrt(1.0 + tau * tau));
			const double cs = 1.0 / Math::sqrt(1.0 + t * t);
			const double sn = t * cs;
			const double pp = c[p][p], qq = c[q][q];
			c[p][p] = pp - t * apq;
			c[q][q] = qq + t * apq;
			c[p][q] = c[q][p] = 0.0;
			for (int k = 0; k < 3; ++k) {
				if (k != p && k != q) {
					const double kp = c[k][p], kq = c[k][q];
					c[k][p] = c[p][k] = cs * kp - sn * kq;
					c[k][q] = c[q][k] = sn * kp + cs * kq;
				}
				const double vp = v[k][p], vq = v[k][q];
				v[k][p] = cs * vp - sn * vq;
				v[k][q] = sn * vp + cs * vq;
			}
		}
		if (!changed) {
			break;
		}
	}
	const double largest = MAX(c[0][0], MAX(c[1][1], c[2][2]));
	if (!(largest > 0.0) || !Math::is_finite(largest)) {
		return false;
	}
	for (int p = 0; p < 3; ++p) {
		for (int q = p + 1; q < 3; ++q) {
			if (!Math::is_finite(c[p][q]) || Math::abs(c[p][q]) > largest * 1e-10) {
				return false;
			}
		}
	}
	double stretches[3];
	for (int i = 0; i < 3; ++i) {
		if (!(c[i][i] > largest * 1e-14) || !Math::is_finite(c[i][i])) {
			return false;
		}
		stretches[i] = Math::sqrt(c[i][i]);
		if (!(stretches[i] > 0.0) || !Math::is_finite(stretches[i])) {
			return false;
		}
	}
	// Sort material axes and singular values together, ascending:
	// sigma[0] is MIN and sigma[2] is MAX.
	for (int i = 0; i < 3; ++i) {
		for (int j = i + 1; j < 3; ++j) {
			if (stretches[j] < stretches[i]) {
				const double temp = stretches[i];
				stretches[i] = stretches[j];
				stretches[j] = temp;
				for (int k = 0; k < 3; ++k) {
					const double axis = v[k][i];
					v[k][i] = v[k][j];
					v[k][j] = axis;
				}
			}
		}
	}
	for (int i = 0; i < 3; ++i) {
		r_singular[i] = stretches[i];
		for (int k = 0; k < 3; ++k) {
			r_axes[k][i] = v[k][i];
			r_f[k][i] = f[k][i];
		}
	}
	return true;
}

_FORCE_INLINE_ bool physics_fem_tetra_principal_constraint(
		const Vector3 p_x[4], const PhysicsFEMTetraRest &p_rest,
		bool p_lower, double p_bound, double &r_violation,
		Vector3 r_gradients[4]) {
	if (!r_gradients || !Math::is_finite(p_bound) ||
			!(p_bound > 0.0) ||
			(p_lower && p_bound > 1.0) ||
			(!p_lower && p_bound < 1.0)) {
		return false;
	}
	double singular[3], axes[3][3], f[3][3];
	if (!physics_fem_tetra_principal_spectrum(
			p_x, p_rest, singular, axes, f)) {
		return false;
	}
	const int eig = p_lower ? 0 : 2;
	const double sigma = singular[eig];
	const double violation = p_lower ? p_bound - sigma : sigma - p_bound;
	const double sign = p_lower ? -1.0 : 1.0;
	double f_axis[3] = {};
	for (int row = 0; row < 3; ++row) {
		for (int col = 0; col < 3; ++col) {
			f_axis[row] += f[row][col] * axes[col][eig];
		}
	}
	double grad[4][3] = {};
	for (int v = 1; v < 4; ++v) {
		double material_weight = 0.0;
		for (int k = 0; k < 3; ++k) {
			material_weight += axes[k][eig] * p_rest.inv_dm[v - 1][k];
		}
		for (int row = 0; row < 3; ++row) {
			grad[v][row] = sign * (f_axis[row] / sigma) * material_weight;
		}
	}
	for (int row = 0; row < 3; ++row) {
		grad[0][row] = -grad[1][row] - grad[2][row] - grad[3][row];
	}
	Vector3 candidates[4];
	for (int v = 0; v < 4; ++v) {
		for (int row = 0; row < 3; ++row) {
			if (!Math::is_finite(grad[v][row])) {
				return false;
			}
		}
		candidates[v] = Vector3(real_t(grad[v][0]), real_t(grad[v][1]), real_t(grad[v][2]));
		if (!candidates[v].is_finite()) {
			return false;
		}
	}
	if (!Math::is_finite(violation)) {
		return false;
	}
	r_violation = violation;
	for (int v = 0; v < 4; ++v) {
		r_gradients[v] = candidates[v];
	}
	return true;
}

_FORCE_INLINE_ bool physics_fem_tetra_principal_solve(
		Vector3 &r_a, Vector3 &r_b, Vector3 &r_c, Vector3 &r_d,
		real_t p_inv_a, real_t p_inv_b, real_t p_inv_c, real_t p_inv_d,
		const PhysicsFEMTetraRest &p_rest, bool p_lower,
		double p_bound, double p_alpha, double &r_lambda) {
	if (!Math::is_finite(p_alpha) || p_alpha < 0.0 ||
			!Math::is_finite(r_lambda) || r_lambda > 0.0) {
		return false;
	}
	const double w[4] = { double(p_inv_a), double(p_inv_b), double(p_inv_c), double(p_inv_d) };
	for (int i = 0; i < 4; ++i) {
		if (!Math::is_finite(w[i]) || w[i] < 0.0) {
			return false;
		}
	}
	const Vector3 original[4] = { r_a, r_b, r_c, r_d };
	double violation;
	Vector3 gradients[4];
	if (!physics_fem_tetra_principal_constraint(original, p_rest, p_lower, p_bound,
			violation, gradients)) {
		return false;
	}
	// No pressure when feasible; discard stale contact-like XPBD impulse.
	if (!(violation > 0.0)) {
		r_lambda = 0.0;
		return false;
	}
	double weighted = 0.0;
	for (int i = 0; i < 4; ++i) {
		weighted += w[i] * (double(gradients[i].x) * double(gradients[i].x) +
					double(gradients[i].y) * double(gradients[i].y) +
					double(gradients[i].z) * double(gradients[i].z));
	}
	const double denom = weighted + p_alpha;
	if (!(weighted > 0.0) || !(denom > 0.0) || !Math::is_finite(denom)) {
		return false;
	}
	const double proposed = r_lambda - (violation + p_alpha * r_lambda) / denom;
	if (!Math::is_finite(proposed)) {
		return false;
	}
	const double new_lambda = proposed < 0.0 ? proposed : 0.0;
	const double delta_lambda = new_lambda - r_lambda;
	if (!(delta_lambda != 0.0) || !Math::is_finite(delta_lambda)) {
		return false;
	}
	// Backtrack large nonlinear corrections: never move an element to
	// non-positive orientation or INCREASE the current violation.
	for (int attempt = 0; attempt < 12; ++attempt) {
		const double factor = double(1u << attempt);
		Vector3 candidate[4];
		bool finite = true;
		for (int v = 0; v < 4; ++v) {
			const double amount = w[v] * delta_lambda / factor;
			candidate[v] = Vector3(
				real_t(double(original[v].x) + amount * double(gradients[v].x)),
				real_t(double(original[v].y) + amount * double(gradients[v].y)),
				real_t(double(original[v].z) + amount * double(gradients[v].z)));
			finite = finite && candidate[v].is_finite();
		}
		if (!finite) {
			continue;
		}
		double after_violation;
		Vector3 after_gradient[4];
		if (!physics_fem_tetra_principal_constraint(candidate, p_rest, p_lower,
				p_bound, after_violation, after_gradient) ||
				after_violation > violation + 1e-9 * MAX(1.0, Math::abs(violation))) {
			continue;
		}
		const double accepted_lambda = r_lambda + delta_lambda / factor;
		if (!Math::is_finite(accepted_lambda) || accepted_lambda > 0.0) {
			return false;
		}
		r_a = candidate[0];
		r_b = candidate[1];
		r_c = candidate[2];
		r_d = candidate[3];
		r_lambda = accepted_lambda;
		return true;
	}
	return false;
}
