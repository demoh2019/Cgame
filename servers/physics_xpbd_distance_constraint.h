/**************************************************************************/
/*  physics_xpbd_distance_constraint.h                                   */
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

#include "core/math/math_funcs.h"
#include "core/math/vector3.h"

// Macklin et al. XPBD distance constraint for soft-body links.
// C = |x_b - x_a| - rest_length, alpha_tilde = compliance / dt^2.
// Accumulate lambda across solver iterations *within the same substep*;
// reset it before the next step. No allocations or per-contact state here.
// Returning false keeps positions and lambda unchanged on invalid inputs.
_FORCE_INLINE_ static bool godot_physics_xpbd_project_distance(
		Vector3 &r_position_a, Vector3 &r_position_b,
		real_t p_inv_mass_a, real_t p_inv_mass_b,
		real_t p_rest_length, double p_scaled_compliance, double &r_lambda) {
	if (!(p_inv_mass_a >= real_t(0.0) && p_inv_mass_b >= real_t(0.0) &&
			p_rest_length >= real_t(0.0) && p_scaled_compliance >= 0.0) ||
			!Math::is_finite(p_inv_mass_a) || !Math::is_finite(p_inv_mass_b) ||
			!Math::is_finite(p_rest_length) || !Math::is_finite(p_scaled_compliance) ||
			!Math::is_finite(r_lambda) ||
			!r_position_a.is_finite() || !r_position_b.is_finite()) {
		return false;
	}

	const double inv_mass_sum = double(p_inv_mass_a) + double(p_inv_mass_b);
	if (!(inv_mass_sum > 0.0)) {
		return false; // Two pinned vertices, or a disabled spring.
	}

	const Vector3 delta = r_position_b - r_position_a;
	if (!delta.is_finite()) {
		return false;
	}
	const double dx = double(delta.x);
	const double dy = double(delta.y);
	const double dz = double(delta.z);
	const double distance_squared = dx * dx + dy * dy + dz * dz;
	if (!(distance_squared > 0.0) || !Math::is_finite(distance_squared)) {
		return false; // Coincident nodes have no well-defined stretch direction.
	}
	const double distance = Math::sqrt(distance_squared);
	const double denominator = inv_mass_sum + p_scaled_compliance;
	if (!Math::is_finite(denominator) || !(denominator > 0.0)) {
		return false;
	}

	const double constraint = distance - double(p_rest_length);
	const double delta_lambda = -(constraint + p_scaled_compliance * r_lambda) / denominator;
	const double next_lambda = r_lambda + delta_lambda;
	if (!Math::is_finite(delta_lambda) || !Math::is_finite(next_lambda)) {
		return false;
	}

	// Gradients are -delta/|delta| for A and +delta/|delta| for B.
	// Compute position updates in double to avoid a tiny real_t scale
	// underflowing before multiplying by a large (but finite) separation.
	const double scale_a = -double(p_inv_mass_a) * delta_lambda / distance;
	const double scale_b = double(p_inv_mass_b) * delta_lambda / distance;
	const Vector3 next_a = r_position_a + Vector3(real_t(dx * scale_a), real_t(dy * scale_a), real_t(dz * scale_a));
	const Vector3 next_b = r_position_b + Vector3(real_t(dx * scale_b), real_t(dy * scale_b), real_t(dz * scale_b));
	if (!next_a.is_finite() || !next_b.is_finite()) {
		return false;
	}

	r_position_a = next_a;
	r_position_b = next_b;
	r_lambda = next_lambda;
	return true;
}
