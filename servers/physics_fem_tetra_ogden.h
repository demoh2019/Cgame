/**************************************************************************/
/*  physics_fem_tetra_ogden.h                                       */
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

// One-term, compressible Ogden hyperelasticity using principal stretches
// from a symmetric Jacobi eigensystem of F^T F. The isochoric energy
// W = (2*mu/alpha^2) * (J^(-alpha/3) * sum(lambda_i^alpha) - 3)
//     + K/2 * (J-1)^2, where alpha in [1,8], mu=E/(2*(1+nu)),
// K=E/(3*(1-2*nu)), E normalized to 1.
// alpha=2 matches the first-invariant Mooney-Rivlin branch.
// No permanent heap allocation or material rest changes.
 
// Diagonalize the positive-definite right Cauchy-Green tensor with a
// deterministic cyclic Jacobi solver. Eigenvectors define the spectral
// derivative even when two principal stretches are equal; no division
// by an eigenvalue GAP is used. Validates convergence before publishing.
_FORCE_INLINE_ bool physics_fem_tetra_ogden_spectral(
		const double p_c[3][3], double p_exponent,
		double &r_stretch_sum, double r_q[3][3]) {
	double a[3][3], v[3][3] = {
		{ 1.0, 0.0, 0.0 }, { 0.0, 1.0, 0.0 }, { 0.0, 0.0, 1.0 }
	};
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			if (!Math::is_finite(p_c[i][j])) {
				return false;
			}
			a[i][j] = p_c[i][j];
		}
	}
	for (int sweep = 0; sweep < 20; ++sweep) {
		bool changed = false;
		for (int pair = 0; pair < 3; ++pair) {
			const int p = pair == 0 ? 0 : (pair == 1 ? 0 : 1);
			const int q = pair == 0 ? 1 : (pair == 1 ? 2 : 2);
			const double apq = a[p][q];
			const double scale = Math::sqrt(Math::abs(a[p][p] * a[q][q]));
			if (Math::abs(apq) <= 1e-15 * MAX(1.0, scale)) {
				continue;
			}
			changed = true;
			const double tau = (a[q][q] - a[p][p]) / (2.0 * apq);
			const double t = (tau >= 0.0 ? 1.0 : -1.0) /
					(Math::abs(tau) + Math::sqrt(1.0 + tau * tau));
			const double rotation_cos = 1.0 / Math::sqrt(1.0 + t * t);
			const double rotation_sin = t * rotation_cos;
			const double app = a[p][p];
			const double aqq = a[q][q];
			a[p][p] = app - t * apq;
			a[q][q] = aqq + t * apq;
			a[p][q] = a[q][p] = 0.0;
			for (int k = 0; k < 3; ++k) {
				if (k != p && k != q) {
					const double akp = a[k][p];
					const double akq = a[k][q];
					a[k][p] = a[p][k] = rotation_cos * akp - rotation_sin * akq;
					a[k][q] = a[q][k] = rotation_sin * akp + rotation_cos * akq;
				}
				const double vkp = v[k][p];
				const double vkq = v[k][q];
				v[k][p] = rotation_cos * vkp - rotation_sin * vkq;
				v[k][q] = rotation_sin * vkp + rotation_cos * vkq;
			}
		}
		if (!changed) {
			break;
		}
	}
	const double largest = MAX(a[0][0], MAX(a[1][1], a[2][2]));
	if (!(largest > 0.0) || !Math::is_finite(largest)) {
		return false;
	}
	for (int p = 0; p < 3; ++p) {
		for (int q = p + 1; q < 3; ++q) {
			if (!Math::is_finite(a[p][q]) || Math::abs(a[p][q]) > 1e-10 * largest) {
				return false;
			}
		}
	}
	double q_matrix[3][3] = {};
	double sum = 0.0;
	for (int k = 0; k < 3; ++k) {
		const double eigenvalue = a[k][k];
		if (!(eigenvalue > largest * 1e-14) || !Math::is_finite(eigenvalue)) {
			return false;
		}
		const double stretch_power = Math::pow(eigenvalue, 0.5 * p_exponent);
		const double derivative_power = stretch_power / eigenvalue;
		if (!Math::is_finite(stretch_power) || !Math::is_finite(derivative_power)) {
			return false;
		}
		sum += stretch_power;
		for (int i = 0; i < 3; ++i) {
			for (int j = 0; j < 3; ++j) {
				q_matrix[i][j] += derivative_power * v[i][k] * v[j][k];
			}
		}
	}
	if (!Math::is_finite(sum)) {
		return false;
	}
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			if (!Math::is_finite(q_matrix[i][j])) {
				return false;
			}
			r_q[i][j] = q_matrix[i][j];
		}
	}
	r_stretch_sum = sum;
	return true;
}

_FORCE_INLINE_ bool physics_fem_tetra_ogden_energy_gradient(
		const Vector3 &p_a, const Vector3 &p_b,
		const Vector3 &p_c, const Vector3 &p_d,
		const PhysicsFEMTetraRest &p_rest, double p_poisson, double p_exponent,
		double &r_energy, Vector3 &r_ga, Vector3 &r_gb,
		Vector3 &r_gc, Vector3 &r_gd) {
	if (!p_a.is_finite() || !p_b.is_finite() ||
			!p_c.is_finite() || !p_d.is_finite() ||
			!(p_rest.volume > 0.0) || !Math::is_finite(p_rest.volume) ||
			!Math::is_finite(p_rest.signed_det) || p_rest.signed_det == 0.0 ||
			!Math::is_finite(p_poisson) || p_poisson < 0.0 || p_poisson > 0.49 ||
			!Math::is_finite(p_exponent) || p_exponent < 1.0 || p_exponent > 8.0) {
		return false;
	}
	for (int j = 0; j < 3; ++j) {
		for (int k = 0; k < 3; ++k) {
			if (!Math::is_finite(p_rest.inv_dm[j][k])) {
				return false;
			}
		}
	}
	const double e[3][3] = {
		{ double(p_b.x) - double(p_a.x), double(p_c.x) - double(p_a.x), double(p_d.x) - double(p_a.x) },
		{ double(p_b.y) - double(p_a.y), double(p_c.y) - double(p_a.y), double(p_d.y) - double(p_a.y) },
		{ double(p_b.z) - double(p_a.z), double(p_c.z) - double(p_a.z), double(p_d.z) - double(p_a.z) }
	};
	double f[3][3];
	double i1 = 0.0;
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			f[i][j] = e[i][0] * p_rest.inv_dm[0][j] +
					e[i][1] * p_rest.inv_dm[1][j] +
					e[i][2] * p_rest.inv_dm[2][j];
			i1 += f[i][j] * f[i][j];
		}
	}
	const double cols[3][3] = {
		{ f[0][0], f[1][0], f[2][0] },
		{ f[0][1], f[1][1], f[2][1] },
		{ f[0][2], f[1][2], f[2][2] }
	};
	const double cof[3][3] = {
		{ cols[1][1] * cols[2][2] - cols[1][2] * cols[2][1],
			cols[1][2] * cols[2][0] - cols[1][0] * cols[2][2],
			cols[1][0] * cols[2][1] - cols[1][1] * cols[2][0] },
		{ cols[2][1] * cols[0][2] - cols[2][2] * cols[0][1],
			cols[2][2] * cols[0][0] - cols[2][0] * cols[0][2],
			cols[2][0] * cols[0][1] - cols[2][1] * cols[0][0] },
		{ cols[0][1] * cols[1][2] - cols[0][2] * cols[1][1],
			cols[0][2] * cols[1][0] - cols[0][0] * cols[1][2],
			cols[0][0] * cols[1][1] - cols[0][1] * cols[1][0] }
	};
	const double j = cols[0][0] * cof[0][0] + cols[0][1] * cof[0][1] + cols[0][2] * cof[0][2];
	// Reject inverted and nearly singular tetrahedra before computing log(J).
	if (!(j > 1e-9) || !Math::is_finite(j) || !Math::is_finite(i1)) {
		return false;
	}
	// Isotropic invariants of the right Cauchy-Green strain C=F^T F.
	// Right Cauchy-Green matrix and positive principal stretch powers.
	double c[3][3] = {};
	for (int i = 0; i < 3; ++i) {
		for (int k = 0; k < 3; ++k) {
			for (int row = 0; row < 3; ++row) {
				c[i][k] += f[row][i] * f[row][k];
			}
		}
	}
	double spectral_sum = 0.0, spectral_q[3][3] = {};
	if (!physics_fem_tetra_ogden_spectral(c, p_exponent, spectral_sum, spectral_q)) {
		return false;
	}
	const double mu = 1.0 / (2.0 * (1.0 + p_poisson));
	const double bulk = 1.0 / (3.0 * (1.0 - 2.0 * p_poisson));
	const double j_power = Math::pow(j, -p_exponent / 3.0);
	const double j_minus_one = j - 1.0;
	double density = (2.0 * mu / (p_exponent * p_exponent)) *
			(j_power * spectral_sum - 3.0) +
			0.5 * bulk * j_minus_one * j_minus_one;
	if (!Math::is_finite(density) || density < -1e-10) {
		return false;
	}
	// Cancel tiny negative floating-point energy at the rigid rest state.
	density = MAX(density, 0.0);
	const double energy = p_rest.volume * density;
	if (!(energy >= 0.0) || !Math::is_finite(energy)) {
		return false;
	}
	double grad[4][3] = {};
	for (int i = 0; i < 3; ++i) {
		for (int k = 0; k < 3; ++k) {
			// Exact derivative of the Ogden principal-stretch energy:
			// P = (2*mu/alpha) J^(-alpha/3)
			//   * [F * Q - sum(lambda^alpha)/3 * F^-T]
			//   + K*(J-1)*cof(F)
			// Q = sum(lambda^(alpha-2) * v_i * v_i^T).
			double spectral_product = 0.0;
			for (int m = 0; m < 3; ++m) {
				spectral_product += f[i][m] * spectral_q[m][k];
			}
			const double pk = (2.0 * mu / p_exponent) * j_power *
					(spectral_product - (spectral_sum / 3.0) * cof[k][i] / j) +
					bulk * j_minus_one * cof[k][i];
			for (int vertex = 1; vertex < 4; ++vertex) {
				grad[vertex][i] += p_rest.volume * pk * p_rest.inv_dm[vertex - 1][k];
			}
		}
		grad[0][i] = -grad[1][i] - grad[2][i] - grad[3][i];
		for (int vertex = 0; vertex < 4; ++vertex) {
			if (!Math::is_finite(grad[vertex][i])) {
				return false;
			}
		}
	}
	const Vector3 g0 = Vector3(real_t(grad[0][0]), real_t(grad[0][1]), real_t(grad[0][2]));
	const Vector3 g1 = Vector3(real_t(grad[1][0]), real_t(grad[1][1]), real_t(grad[1][2]));
	const Vector3 g2 = Vector3(real_t(grad[2][0]), real_t(grad[2][1]), real_t(grad[2][2]));
	const Vector3 g3 = Vector3(real_t(grad[3][0]), real_t(grad[3][1]), real_t(grad[3][2]));
	if (!g0.is_finite() || !g1.is_finite() || !g2.is_finite() || !g3.is_finite()) {
		return false;
	}
	r_energy = energy;
	r_ga = g0;
	r_gb = g1;
	r_gc = g2;
	r_gd = g3;
	return true;
}

// Unilateral inversion guard: an XPBD step is backtracked if it would
// collapse or flip a valid tetrahedron. No state is changed on failure.
_FORCE_INLINE_ bool physics_fem_tetra_ogden_solve(
		Vector3 &r_a, Vector3 &r_b, Vector3 &r_c, Vector3 &r_d,
		real_t p_inv_a, real_t p_inv_b, real_t p_inv_c, real_t p_inv_d,
		const PhysicsFEMTetraRest &p_rest, double p_poisson, double p_exponent,
		double p_alpha, double &r_lambda) {
	const double w[4] = { double(p_inv_a), double(p_inv_b), double(p_inv_c), double(p_inv_d) };
	if (!Math::is_finite(p_alpha) || p_alpha < 0.0 ||
			!Math::is_finite(r_lambda)) {
		return false;
	}
	double movable = 0.0;
	for (int v = 0; v < 4; ++v) {
		if (!(w[v] >= 0.0) || !Math::is_finite(w[v])) {
			return false;
		}
		movable += w[v];
	}
	if (!(movable > 0.0)) {
		return false;
	}
	double energy;
	Vector3 ga, gb, gc, gd;
	if (!physics_fem_tetra_ogden_energy_gradient(r_a, r_b, r_c, r_d,
			p_rest, p_poisson, p_exponent, energy, ga, gb, gc, gd) || !(energy > 0.0)) {
		return false;
	}
	const double constraint = Math::sqrt(2.0 * energy);
	const Vector3 gradients[4] = { ga, gb, gc, gd };
	const Vector3 original[4] = { r_a, r_b, r_c, r_d };
	double weighted = 0.0;
	for (int v = 0; v < 4; ++v) {
		const double gx = double(gradients[v].x);
		const double gy = double(gradients[v].y);
		const double gz = double(gradients[v].z);
		weighted += w[v] * (gx * gx + gy * gy + gz * gz);
	}
	weighted /= constraint * constraint;
	const double denom = weighted + p_alpha;
	if (!(denom > 0.0) || !Math::is_finite(denom)) {
		return false;
	}
	const double step_lambda = -(constraint + p_alpha * r_lambda) / denom;
	if (!Math::is_finite(step_lambda)) {
		return false;
	}
	// A single energy constraint is not sufficient to prevent inversions
	// under very large impulses. Keep the previous orientation by shortening
	// the proposed step if the deformation gradient becomes singular.
	for (int attempt = 0; attempt < 12; ++attempt) {
		const double factor = double(1u << attempt);
		Vector3 candidate[4];
		bool finite = true;
		for (int v = 0; v < 4; ++v) {
			const double step = w[v] * step_lambda / (constraint * factor);
			candidate[v] = Vector3(
					real_t(double(original[v].x) + step * double(gradients[v].x)),
					real_t(double(original[v].y) + step * double(gradients[v].y)),
					real_t(double(original[v].z) + step * double(gradients[v].z)));
			finite = finite && candidate[v].is_finite();
		}
		if (!finite) {
			continue;
		}
		double check_energy;
		Vector3 ca, cb, cc, cd;
		if (!physics_fem_tetra_ogden_energy_gradient(candidate[0], candidate[1],
				candidate[2], candidate[3], p_rest, p_poisson, p_exponent,
				check_energy, ca, cb, cc, cd)) {
			continue;
		}
		const double accepted_lambda = r_lambda + step_lambda / factor;
		if (!Math::is_finite(accepted_lambda)) {
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
