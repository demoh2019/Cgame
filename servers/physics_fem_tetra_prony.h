/**************************************************************************/
/*  physics_fem_tetra_prony.h                                       */
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

#include "servers/physics_fem_tetra_standard_linear_solid.h"

// Additional two-arm Green-strain generalized Maxwell (Prony) spectrum.
// The EXISTING one-arm SLS memory is the optional first branch. Each
// additional branch has independent positive compliance (inverse spring
// modulus) and time constant. Enabled branches are assembled into one
// energy constraint, rather than applying the independent springs in
// an order-dependent sequential projection.
//
// W_total = sum_i W_unit(E-H_i) / compliance_i
// H_i(t+dt) = exp(-dt/tau_i) H_i(t)
//             + (1-exp(-dt/tau_i)) E(predicted)
// P_total = sum_i P_unit(E-H_i) / compliance_i
// C = sqrt(2 W_total); XPBD alpha = 1 / dt^2.
//
// In the single active branch case this normalization is algebraically
// equivalent to the existing SLS solver with alpha=compliance/dt^2.
// Distinct timescales approximate a Prony relaxation spectrum. The
// equilibrium elastic branch remains in the existing Neo-Hookean /
// Mooney-Rivlin / Ogden solver. NOT thermomechanical nonlinear QLV.
// Maximum 3 arms, no runtime allocations in the numerical kernel.

struct PhysicsFEMTetraPronyState {
	PhysicsFEMTetraSLSState fast;
	PhysicsFEMTetraSLSState slow;
	double lambda = 0.0; // Combined XPBD multiplier, reset every tick.
};

// Atomic update of enabled additional strain-memory branches. The
// pre-existing SLS arm is updated separately by its existing path.
// p_fast_tau/p_slow_tau are ignored for disabled arms.
_FORCE_INLINE_ bool physics_fem_tetra_prony_relax(
		const Vector3 p_x[4], const PhysicsFEMTetraRest &p_rest,
		bool p_fast_enabled, double p_fast_tau,
		bool p_slow_enabled, double p_slow_tau,
		double p_delta, PhysicsFEMTetraPronyState &r_state) {
	if ((!p_fast_enabled && !p_slow_enabled) ||
			!(p_delta >= 0.0) || !Math::is_finite(p_delta)) {
		return false;
	}
	PhysicsFEMTetraPronyState candidate = r_state;
	if (p_fast_enabled &&
			!physics_fem_tetra_sls_relax(p_x, p_rest, p_fast_tau, p_delta,
					candidate.fast)) {
		return false;
	}
	if (p_slow_enabled &&
			!physics_fem_tetra_sls_relax(p_x, p_rest, p_slow_tau, p_delta,
					candidate.slow)) {
		return false;
	}
	r_state = candidate;
	return true;
}

// Sum the NORMALIZED SLS energies and exact analytic gradients. The
// inverse compliance acts as the strength of the Maxwell arm. A nullptr
// arm must have compliance=0 and is skipped. Outputs stay unchanged if
// any active arm or its gradient is invalid. The caller provides at
// least one enabled branch.
_FORCE_INLINE_ bool physics_fem_tetra_prony_energy_gradient(
		const Vector3 &p_a, const Vector3 &p_b,
		const Vector3 &p_c, const Vector3 &p_d,
		const PhysicsFEMTetraRest &p_rest,
		const PhysicsFEMTetraSLSState *const p_arms[3],
		const double p_compliances[3], double p_poisson,
		double &r_energy, Vector3 &r_ga, Vector3 &r_gb,
		Vector3 &r_gc, Vector3 &r_gd) {
	if (!p_arms || !p_compliances ||
			!Math::is_finite(p_poisson) || p_poisson < 0.0 || p_poisson > 0.49) {
		return false;
	}
	double total_energy = 0.0, grad[4][3] = {};
	bool any = false;
	for (int i = 0; i < 3; ++i) {
		const double compliance = p_compliances[i];
		if (!Math::is_finite(compliance) || compliance < 0.0 ||
				(p_arms[i] == nullptr && compliance != 0.0) ||
				(p_arms[i] != nullptr && compliance == 0.0)) {
			return false;
		}
		if (p_arms[i] == nullptr) {
			continue;
		}
		any = true;
		const double inverse_compliance = 1.0 / compliance;
		if (!(inverse_compliance > 0.0) || !Math::is_finite(inverse_compliance)) {
			return false;
		}
		double unit_energy = 0.0;
		Vector3 ga, gb, gc, gd;
		if (!physics_fem_tetra_sls_energy_gradient(p_a, p_b, p_c, p_d,
				p_rest, *p_arms[i], p_poisson, unit_energy, ga, gb, gc, gd)) {
			return false;
		}
		total_energy += unit_energy * inverse_compliance;
		const Vector3 current[4] = { ga, gb, gc, gd };
		for (int v = 0; v < 4; ++v) {
			for (int axis = 0; axis < 3; ++axis) {
				grad[v][axis] += double(current[v][axis]) * inverse_compliance;
			}
		}
	}
	if (!any || !(total_energy >= 0.0) || !Math::is_finite(total_energy)) {
		return false;
	}
	Vector3 result[4];
	for (int v = 0; v < 4; ++v) {
		for (int axis = 0; axis < 3; ++axis) {
			if (!Math::is_finite(grad[v][axis])) {
				return false;
			}
		}
		result[v] = Vector3(real_t(grad[v][0]), real_t(grad[v][1]), real_t(grad[v][2]));
		if (!result[v].is_finite()) {
			return false;
		}
	}
	r_energy = total_energy;
	r_ga = result[0];
	r_gb = result[1];
	r_gc = result[2];
	r_gd = result[3];
	return true;
}

// Fixed-memory XPBD projection of the COMBINED multi-exponential spring
// energy. The internal material memory never updates during iterations;
// backtracking preserves positive tet orientation and decreasing energy.
// Unilateral inversion guard: an XPBD step is backtracked if it would
// collapse or flip a valid tetrahedron. No state is changed on failure.
_FORCE_INLINE_ bool physics_fem_tetra_prony_solve(
		Vector3 &r_a, Vector3 &r_b, Vector3 &r_c, Vector3 &r_d,
		real_t p_inv_a, real_t p_inv_b, real_t p_inv_c, real_t p_inv_d,
		const PhysicsFEMTetraRest &p_rest,
		const PhysicsFEMTetraSLSState *const p_arms[3],
		const double p_compliances[3], double p_poisson,
		double p_delta, double &r_lambda) {
	const double w[4] = { double(p_inv_a), double(p_inv_b), double(p_inv_c), double(p_inv_d) };
	if (!(p_delta > 0.0) || !Math::is_finite(p_delta)) {
		return false;
	}
	const double p_alpha = 1.0 / (p_delta * p_delta);
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
	if (!physics_fem_tetra_prony_energy_gradient(r_a, r_b, r_c, r_d,
			p_rest, p_arms, p_compliances, p_poisson, energy, ga, gb, gc, gd) || !(energy > 0.0)) {
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
		if (!physics_fem_tetra_prony_energy_gradient(candidate[0], candidate[1],
				candidate[2], candidate[3], p_rest, p_arms, p_compliances, p_poisson,
				check_energy, ca, cb, cc, cd)) {
			continue;
		}
		// Do not accept a nonlinear correction that INCREASES the
		// sum of stored Prony branch energies.
		if (check_energy > energy + 1e-9 * MAX(1.0, energy)) {
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
