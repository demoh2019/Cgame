/**************************************************************************/
/*  physics_fem_tetra_standard_linear_solid.h                                       */
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

#include <cmath>

// A finite-strain Standard Linear Solid (Zener-type) material branch for
// existing tetrahedral SoftBody3D XPBD. The normal FEM material supplies
// equilibrium elasticity; this branch adds a Maxwell spring in parallel.
//
// E = (F^T F - I)/2 is the *objective* Green-Lagrange strain.
// H(t+dt) = exp(-dt/tau) H(t) + (1-exp(-dt/tau)) E(t+dt)
// is a relaxing internal viscous strain in the rest material frame.
// The transient elastic energy is
//   W = V0 * [mu |E-H|^2 + lambda/2 tr(E-H)^2], Young modulus=1.
// P = F [2mu(E-H) + lambda tr(E-H)I] is its exact first Piola stress.
//
// The extra XPBD compliance sets transient stiffness. The equilibrium
// constitutive law is unchanged. This model is an experimental one-arm
// finite-strain SLS approximation (Green-strain branch), not a calibrated
// finite-strain generalized Maxwell/Prony series or fluid rheology.
// H persists across physics steps; XPBD lambda is reset once per step.
// No state allocation or computation if this feature is disabled.
struct PhysicsFEMTetraSLSState {
	double relaxing_strain[3][3] = {}; // Symmetric material tensor.
	double lambda = 0.0;
};

_FORCE_INLINE_ bool physics_fem_tetra_sls_deformation(
		const Vector3 p_x[4], const PhysicsFEMTetraRest &p_rest,
		double r_f[3][3], double r_e[3][3]) {
	if (!p_x || !r_f || !r_e || !(p_rest.volume > 0.0) ||
			!Math::is_finite(p_rest.volume) ||
			!Math::is_finite(p_rest.signed_det) || p_rest.signed_det == 0.0) {
		return false;
	}
	for (int v = 0; v < 4; ++v) {
		if (!p_x[v].is_finite()) {
			return false;
		}
	}
	double ds[3][3], f[3][3], e[3][3];
	for (int row = 0; row < 3; ++row) {
		for (int col = 0; col < 3; ++col) {
			if (!Math::is_finite(p_rest.inv_dm[row][col])) {
				return false;
			}
			ds[row][col] = double(p_x[col + 1][row]) - double(p_x[0][row]);
		}
	}
	for (int row = 0; row < 3; ++row) {
		for (int col = 0; col < 3; ++col) {
			f[row][col] = 0.0;
			for (int axis = 0; axis < 3; ++axis) {
				f[row][col] += ds[row][axis] * p_rest.inv_dm[axis][col];
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
	for (int a = 0; a < 3; ++a) {
		for (int b = 0; b < 3; ++b) {
			double c_ab = 0.0;
			for (int row = 0; row < 3; ++row) {
				c_ab += f[row][a] * f[row][b];
			}
			e[a][b] = 0.5 * (c_ab - (a == b ? 1.0 : 0.0));
			if (!Math::is_finite(e[a][b])) {
				return false;
			}
		}
	}
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			r_f[i][j] = f[i][j];
			r_e[i][j] = e[i][j];
		}
	}
	return true;
}

// Exact exponential internal-state integration under a frozen strain
// during the step. Call ONCE on predicted positions before XPBD iterations.
// Invalid/inverted states never overwrite a previously valid history.
_FORCE_INLINE_ bool physics_fem_tetra_sls_relax(
		const Vector3 p_x[4], const PhysicsFEMTetraRest &p_rest,
		double p_tau, double p_delta, PhysicsFEMTetraSLSState &r_state) {
	if (!(p_tau > 0.0) || !Math::is_finite(p_tau) ||
			!(p_delta >= 0.0) || !Math::is_finite(p_delta)) {
		return false;
	}
	double f[3][3], e[3][3];
	if (!physics_fem_tetra_sls_deformation(p_x, p_rest, f, e)) {
		return false;
	}
	const double decay = std::exp(-p_delta / p_tau);
	if (!(decay >= 0.0) || decay > 1.0 || !Math::is_finite(decay)) {
		return false;
	}
	double new_strain[3][3];
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			if (!Math::is_finite(r_state.relaxing_strain[i][j])) {
				return false;
			}
			new_strain[i][j] = decay * r_state.relaxing_strain[i][j] + (1.0 - decay) * e[i][j];
			if (!Math::is_finite(new_strain[i][j])) {
				return false;
			}
		}
	}
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			r_state.relaxing_strain[i][j] = new_strain[i][j];
		}
	}
	return true;
}

_FORCE_INLINE_ bool physics_fem_tetra_sls_energy_gradient(
		const Vector3 &p_a, const Vector3 &p_b,
		const Vector3 &p_c, const Vector3 &p_d,
		const PhysicsFEMTetraRest &p_rest, const PhysicsFEMTetraSLSState &p_state,
		double p_poisson, double &r_energy,
		Vector3 &r_ga, Vector3 &r_gb, Vector3 &r_gc, Vector3 &r_gd) {
	if (!Math::is_finite(p_poisson) || p_poisson < 0.0 || p_poisson > 0.49) {
		return false;
	}
	const Vector3 x[4] = { p_a, p_b, p_c, p_d };
	double f[3][3], e[3][3];
	if (!physics_fem_tetra_sls_deformation(x, p_rest, f, e)) {
		return false;
	}
	const double mu = 1.0 / (2.0 * (1.0 + p_poisson));
	const double lame = p_poisson / ((1.0 + p_poisson) * (1.0 - 2.0 * p_poisson));
	double a[3][3], tr = 0.0, squares = 0.0;
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			if (!Math::is_finite(p_state.relaxing_strain[i][j])) {
				return false;
			}
			a[i][j] = e[i][j] - p_state.relaxing_strain[i][j];
			if (!Math::is_finite(a[i][j])) {
				return false;
			}
			squares += a[i][j] * a[i][j];
		}
		tr += a[i][i];
	}
	const double energy = p_rest.volume * (mu * squares + 0.5 * lame * tr * tr);
	if (!(energy >= 0.0) || !Math::is_finite(energy)) {
		return false;
	}
	double stress[3][3], grad[4][3] = {};
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			stress[i][j] = 2.0 * mu * a[i][j] + (i == j ? lame * tr : 0.0);
		}
	}
	for (int row = 0; row < 3; ++row) {
		for (int col = 0; col < 3; ++col) {
			double first_piola = 0.0;
			for (int k = 0; k < 3; ++k) {
				first_piola += f[row][k] * stress[k][col];
			}
			for (int v = 1; v < 4; ++v) {
				grad[v][row] += p_rest.volume * first_piola * p_rest.inv_dm[v - 1][col];
			}
		}
		grad[0][row] = -grad[1][row] - grad[2][row] - grad[3][row];
	}
	Vector3 g[4];
	for (int v = 0; v < 4; ++v) {
		for (int row = 0; row < 3; ++row) {
			if (!Math::is_finite(grad[v][row])) {
				return false;
			}
		}
		g[v] = Vector3(real_t(grad[v][0]), real_t(grad[v][1]), real_t(grad[v][2]));
		if (!g[v].is_finite()) {
			return false;
		}
	}
	r_energy = energy;
	r_ga = g[0];
	r_gb = g[1];
	r_gc = g[2];
	r_gd = g[3];
	return true;
}

// SoftBody3D supplies one cached XPBD multiplier per SLS tetra. The
// stress branch is conservative for fixed H and dissipates energy only
// through exponential relaxation of H once per time step.
// Unilateral inversion guard: an XPBD step is backtracked if it would
// collapse or flip a valid tetrahedron. No state is changed on failure.
_FORCE_INLINE_ bool physics_fem_tetra_sls_solve(
		Vector3 &r_a, Vector3 &r_b, Vector3 &r_c, Vector3 &r_d,
		real_t p_inv_a, real_t p_inv_b, real_t p_inv_c, real_t p_inv_d,
		const PhysicsFEMTetraRest &p_rest, const PhysicsFEMTetraSLSState &p_state,
		double p_poisson, double p_alpha, double &r_lambda) {
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
	if (!physics_fem_tetra_sls_energy_gradient(r_a, r_b, r_c, r_d,
			p_rest, p_state, p_poisson, energy, ga, gb, gc, gd) || !(energy > 0.0)) {
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
		if (!physics_fem_tetra_sls_energy_gradient(candidate[0], candidate[1],
				candidate[2], candidate[3], p_rest, p_state, p_poisson,
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
