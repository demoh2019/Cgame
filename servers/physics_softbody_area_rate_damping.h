/**************************************************************************/
/*  physics_softbody_area_rate_damping.h                                  */
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

// Local Kelvin-Voigt-style AREA RATE damping for deformable triangle meshes.
// Targets dA/dt = sum_i (grad_A_i dot v_i) using the same area Jacobian as
// the XPBD area constraint. It does not change rest area or positions.
//
// For 0 <= fraction <= 1:
//   J = -fraction * dA/dt / sum_i (inv_mass_i * |grad_A_i|^2)
//   v_i <- v_i + inv_mass_i * grad_A_i * J
//
// This removes exactly 'fraction' of the instantaneous area-change rate
// (up to rounding) and never adds kinetic energy in isolation. Because the
// area function is invariant under rigid translations and rotations, the
// impulse conserves linear and angular momentum, unlike ordinary damping.
//
// All geometry and impulses use double intermediates to avoid float32
// overflows at large/small world scales; no heap allocation or persistent
// buffers. Failures leave ALL THREE velocities unchanged. Independent of
// XPBD area compliance, membrane stiffness and hinge damping.
_FORCE_INLINE_ static bool physics_softbody_damp_triangle_area_rate(
		const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c,
		Vector3 &r_v_a, Vector3 &r_v_b, Vector3 &r_v_c,
		real_t p_inv_a, real_t p_inv_b, real_t p_inv_c,
		double p_fraction) {
	if (!(p_fraction > 0.0 && p_fraction <= 1.0) || !Math::is_finite(p_fraction) ||
			!p_a.is_finite() || !p_b.is_finite() || !p_c.is_finite() ||
			!r_v_a.is_finite() || !r_v_b.is_finite() || !r_v_c.is_finite() ||
			!Math::is_finite(p_inv_a) || !Math::is_finite(p_inv_b) ||
			!Math::is_finite(p_inv_c) ||
			p_inv_a < 0.0 || p_inv_b < 0.0 || p_inv_c < 0.0) {
		return false;
	}

	const double inv[3] = { double(p_inv_a), double(p_inv_b), double(p_inv_c) };
	if (!(inv[0] + inv[1] + inv[2] > 0.0)) {
		return false;
	}
	const double ab[3] = {
		double(p_b.x) - double(p_a.x),
		double(p_b.y) - double(p_a.y),
		double(p_b.z) - double(p_a.z)
	};
	const double ac[3] = {
		double(p_c.x) - double(p_a.x),
		double(p_c.y) - double(p_a.y),
		double(p_c.z) - double(p_a.z)
	};
	const double ab_sq = ab[0] * ab[0] + ab[1] * ab[1] + ab[2] * ab[2];
	const double ac_sq = ac[0] * ac[0] + ac[1] * ac[1] + ac[2] * ac[2];
	const double cross[3] = {
		ab[1] * ac[2] - ab[2] * ac[1],
		ab[2] * ac[0] - ab[0] * ac[2],
		ab[0] * ac[1] - ab[1] * ac[0]
	};
	const double cross_sq = cross[0] * cross[0] + cross[1] * cross[1] + cross[2] * cross[2];
	const double scale = ab_sq * ac_sq;
	if (!(scale > 0.0) || !Math::is_finite(scale) ||
			!(cross_sq > scale * 1e-16) || !Math::is_finite(cross_sq)) {
		return false;
	}
	const double inverse_normal = 1.0 / Math::sqrt(cross_sq);
	const double n[3] = { cross[0] * inverse_normal,
		cross[1] * inverse_normal, cross[2] * inverse_normal };
	if (!Math::is_finite(inverse_normal)) {
		return false;
	}

	const double gradient[3][3] = {
		{
			0.5 * ((ab[1] - ac[1]) * n[2] - (ab[2] - ac[2]) * n[1]),
			0.5 * ((ab[2] - ac[2]) * n[0] - (ab[0] - ac[0]) * n[2]),
			0.5 * ((ab[0] - ac[0]) * n[1] - (ab[1] - ac[1]) * n[0])
		},
		{
			0.5 * (ac[1] * n[2] - ac[2] * n[1]),
			0.5 * (ac[2] * n[0] - ac[0] * n[2]),
			0.5 * (ac[0] * n[1] - ac[1] * n[0])
		},
		{
			0.5 * (n[1] * ab[2] - n[2] * ab[1]),
			0.5 * (n[2] * ab[0] - n[0] * ab[2]),
			0.5 * (n[0] * ab[1] - n[1] * ab[0])
		}
	};
	const Vector3 velocity[3] = { r_v_a, r_v_b, r_v_c };

	double rate = 0.0;
	double effective_inverse_mass = 0.0;
	for (int i = 0; i < 3; ++i) {
		double grad_sq = 0.0;
		for (int j = 0; j < 3; ++j) {
			const double g = gradient[i][j];
			if (!Math::is_finite(g)) {
				return false;
			}
			rate += g * double(velocity[i][j]);
			grad_sq += g * g;
		}
		effective_inverse_mass += inv[i] * grad_sq;
	}
	if (!Math::is_finite(rate) || !(effective_inverse_mass > 0.0) ||
			!Math::is_finite(effective_inverse_mass)) {
		return false;
	}
	const double impulse = -p_fraction * rate / effective_inverse_mass;
	if (!Math::is_finite(impulse)) {
		return false;
	}

	const double max_component = double(std::numeric_limits<real_t>::max());
	Vector3 next[3];
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			const double component = double(velocity[i][j]) +
					inv[i] * gradient[i][j] * impulse;
			if (!Math::is_finite(component) || Math::abs(component) > max_component) {
				return false;
			}
			next[i][j] = real_t(component);
		}
	}
	r_v_a = next[0];
	r_v_b = next[1];
	r_v_c = next[2];
	return true;
}
