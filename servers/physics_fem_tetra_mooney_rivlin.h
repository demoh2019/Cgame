/**************************************************************************/
/*  physics_fem_tetra_mooney_rivlin.h                                       */
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

// Compressible, isochoric Mooney-Rivlin hyperelastic tetra FEM.
// Separate selection from the original Neo-Hookean material: enabling this
// changes the high-strain response even at c01_fraction=0, since its
// isochoric neo variant and volumetric quadratic energy use different laws.
//
// W = C10*(J^(-2/3)*I1-3) + C01*(J^(-4/3)*I2-3) + K/2*(J-1)^2
// C10 = mu*(1-s)/2; C01=mu*s/2, 0<=s<=1;
// mu=E/[2(1+nu)], K=E/[3(1-2nu)], E normalized to 1.
// No inversion, no negative Jacobians, no permanent allocations.
// Same XPBD energy constraint and backtracking semantics as Neo-Hookean.

_FORCE_INLINE_ bool physics_fem_tetra_mooney_rivlin_energy_gradient(
		const Vector3 &p_a, const Vector3 &p_b,
		const Vector3 &p_c, const Vector3 &p_d,
		const PhysicsFEMTetraRest &p_rest, double p_poisson, double p_c01_fraction,
		double &r_energy, Vector3 &r_ga, Vector3 &r_gb,
		Vector3 &r_gc, Vector3 &r_gd) {
	if (!p_a.is_finite() || !p_b.is_finite() ||
			!p_c.is_finite() || !p_d.is_finite() ||
			!(p_rest.volume > 0.0) || !Math::is_finite(p_rest.volume) ||
			!Math::is_finite(p_rest.signed_det) || p_rest.signed_det == 0.0 ||
			!Math::is_finite(p_poisson) || p_poisson < 0.0 || p_poisson > 0.49 ||
			!Math::is_finite(p_c01_fraction) || p_c01_fraction < 0.0 || p_c01_fraction > 1.0) {
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
	// I2 = 0.5 * (trace(C)^2 - trace(C*C)). The three principal
	// 2x2 minors are positive on any nonsingular deformation.
	double c[3][3] = {};
	for (int a = 0; a < 3; ++a) {
		for (int b = 0; b < 3; ++b) {
			for (int row = 0; row < 3; ++row) {
				c[a][b] += f[row][a] * f[row][b];
			}
		}
	}
	const double i2 = c[0][0] * c[1][1] + c[0][0] * c[2][2] + c[1][1] * c[2][2] -
			c[0][1] * c[0][1] - c[0][2] * c[0][2] - c[1][2] * c[1][2];
	if (!(i2 > 0.0) || !Math::is_finite(i2)) {
		return false;
	}
	// Isochoric Mooney-Rivlin normalized to unit Young modulus at rest.
	// Two material invariants alter the large-strain response while the
	// isochoric small-strain shear modulus remains mu for every split.
	// K = E/[3(1-2nu)] penalizes changes of J independently of shear.
	const double mu = 1.0 / (2.0 * (1.0 + p_poisson));
	const double bulk = 1.0 / (3.0 * (1.0 - 2.0 * p_poisson));
	const double c10 = 0.5 * mu * (1.0 - p_c01_fraction);
	const double c01 = 0.5 * mu * p_c01_fraction;
	const double j_m23 = Math::pow(j, -2.0 / 3.0);
	const double j_m43 = j_m23 * j_m23;
	const double j_minus_one = j - 1.0;
	double density = c10 * (j_m23 * i1 - 3.0) +
			c01 * (j_m43 * i2 - 3.0) +
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
			// Exact first Piola-Kirchhoff stress dW/dF. Cofactor
			// cof[k][i] = J * F^{-T}[i][k] for this column layout.
			double fc = 0.0;
			for (int m = 0; m < 3; ++m) {
				fc += f[i][m] * c[m][k];
			}
			const double inverse_transpose = cof[k][i] / j;
			const double pk = 2.0 * c10 * j_m23 *
					(f[i][k] - (i1 / 3.0) * inverse_transpose) +
					2.0 * c01 * j_m43 *
					(i1 * f[i][k] - fc - (2.0 * i2 / 3.0) * inverse_transpose) +
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
_FORCE_INLINE_ bool physics_fem_tetra_mooney_rivlin_solve(
		Vector3 &r_a, Vector3 &r_b, Vector3 &r_c, Vector3 &r_d,
		real_t p_inv_a, real_t p_inv_b, real_t p_inv_c, real_t p_inv_d,
		const PhysicsFEMTetraRest &p_rest, double p_poisson, double p_c01_fraction,
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
	if (!physics_fem_tetra_mooney_rivlin_energy_gradient(r_a, r_b, r_c, r_d,
			p_rest, p_poisson, p_c01_fraction, energy, ga, gb, gc, gd) || !(energy > 0.0)) {
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
		if (!physics_fem_tetra_mooney_rivlin_energy_gradient(candidate[0], candidate[1],
				candidate[2], candidate[3], p_rest, p_poisson, p_c01_fraction,
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
