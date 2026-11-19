/**************************************************************************/
/*  physics_softbody_membrane_damping.h                                   */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "servers/physics_xpbd_membrane.h"

// Objective, mass-weighted membrane velocity damping. The three independent
// Green-Lagrange strain rates (E00, E11 and E01) are projected sequentially,
// using the current deformation gradient F and analytic strain Jacobians.
//
// The velocity correction is proportional to mass inverse * strain gradient.
// Each projection removes a bounded fraction of strain-rate kinetic energy
// and preserves linear and angular momentum (to floating-point accuracy).
// In particular, rigid translation and rigid rotation have zero strain rate.
// Pins with zero inverse mass are EXACTLY unaffected.
//
// p_fraction = 1-exp(-damping_rate * dt), computed once by the caller.
// Unlike global drag, this is intrinsic to the surface and dissipates only
// local deformation rates. This is a simple projective viscoelastic dashpot,
// not a calibrated Kelvin-Voigt continuum constitutive integration.
//
// Every numerical intermediate uses double and local scratch arrays. The
// complete three-mode pass is transactional: all three velocities must be
// representable before ANY caller-owned velocity is written. No allocations.
_FORCE_INLINE_ bool physics_softbody_damp_membrane(
		const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c,
		Vector3 &r_v_a, Vector3 &r_v_b, Vector3 &r_v_c,
		real_t p_inv_a, real_t p_inv_b, real_t p_inv_c,
		const PhysicsXPBDMembraneRest &p_rest, double p_fraction) {
	if (!p_a.is_finite() || !p_b.is_finite() || !p_c.is_finite() ||
			!r_v_a.is_finite() || !r_v_b.is_finite() || !r_v_c.is_finite() ||
			!Math::is_finite(p_inv_a) || !Math::is_finite(p_inv_b) ||
			!Math::is_finite(p_inv_c) || p_inv_a < 0.0 ||
			p_inv_b < 0.0 || p_inv_c < 0.0 ||
			!Math::is_finite(p_fraction) || !(p_fraction > 0.0) ||
			p_fraction > 1.0 ||
			!(p_rest.inv_u > 0.0) || !(p_rest.inv_height > 0.0) ||
			!(p_rest.area > 0.0) || !Math::is_finite(p_rest.inv_u) ||
			!Math::is_finite(p_rest.inv_height) || !Math::is_finite(p_rest.q) ||
			!Math::is_finite(p_rest.area)) {
		return false;
	}
	const double inv[3] = { double(p_inv_a), double(p_inv_b), double(p_inv_c) };
	if (!(inv[0] + inv[1] + inv[2] > 0.0)) {
		return false;
	}
	const double x[3][3] = {
		{ double(p_a.x), double(p_a.y), double(p_a.z) },
		{ double(p_b.x), double(p_b.y), double(p_b.z) },
		{ double(p_c.x), double(p_c.y), double(p_c.z) }
	};
	double v[3][3] = {
		{ double(r_v_a.x), double(r_v_a.y), double(r_v_a.z) },
		{ double(r_v_b.x), double(r_v_b.y), double(r_v_b.z) },
		{ double(r_v_c.x), double(r_v_c.y), double(r_v_c.z) }
	};
	double f0[3], f1[3];
	for (int k = 0; k < 3; ++k) {
		const double ab = x[1][k] - x[0][k];
		const double ac = x[2][k] - x[0][k];
		f0[k] = p_rest.inv_u * ab;
		f1[k] = p_rest.q * ab + p_rest.inv_height * ac;
		if (!Math::is_finite(f0[k]) || !Math::is_finite(f1[k])) {
			return false;
		}
	}

	bool corrected = false;
	for (int mode = 0; mode < 3; ++mode) {
		// dE00/dF0 = F0, dE11/dF1 = F1.
		// dE01/dF0 = F1/2, dE01/dF1 = F0/2.
		double g[3][3];
		for (int k = 0; k < 3; ++k) {
			const double df0 = mode == 0 ? f0[k] : (mode == 2 ? 0.5 * f1[k] : 0.0);
			const double df1 = mode == 1 ? f1[k] : (mode == 2 ? 0.5 * f0[k] : 0.0);
			g[1][k] = p_rest.inv_u * df0 + p_rest.q * df1;
			g[2][k] = p_rest.inv_height * df1;
			g[0][k] = -g[1][k] - g[2][k];
			if (!Math::is_finite(g[0][k]) || !Math::is_finite(g[1][k]) ||
					!Math::is_finite(g[2][k])) {
				return false;
			}
		}

		double strain_rate = 0.0;
		double inv_effective_mass = 0.0;
		for (int j = 0; j < 3; ++j) {
			for (int k = 0; k < 3; ++k) {
				strain_rate += g[j][k] * v[j][k];
				inv_effective_mass += inv[j] * g[j][k] * g[j][k];
			}
		}
		if (!Math::is_finite(strain_rate) || !Math::is_finite(inv_effective_mass)) {
			return false;
		}
		if (!(inv_effective_mass > 0.0) || strain_rate == 0.0) {
			continue;
		}
		const double impulse = -p_fraction * strain_rate / inv_effective_mass;
		if (!Math::is_finite(impulse)) {
			return false;
		}
		for (int j = 0; j < 3; ++j) {
			for (int k = 0; k < 3; ++k) {
				v[j][k] += inv[j] * impulse * g[j][k];
				if (!Math::is_finite(v[j][k])) {
					return false;
				}
			}
		}
		corrected = true;
	}
	if (!corrected) {
		return false;
	}

	const Vector3 next_a = Vector3(real_t(v[0][0]), real_t(v[0][1]), real_t(v[0][2]));
	const Vector3 next_b = Vector3(real_t(v[1][0]), real_t(v[1][1]), real_t(v[1][2]));
	const Vector3 next_c = Vector3(real_t(v[2][0]), real_t(v[2][1]), real_t(v[2][2]));
	if (!next_a.is_finite() || !next_b.is_finite() || !next_c.is_finite()) {
		return false;
	}
	r_v_a = next_a;
	r_v_b = next_b;
	r_v_c = next_c;
	return true;
}
