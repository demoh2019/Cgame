/**************************************************************************/
/*  physics_xpbd_3d.h                                                     */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
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

#include "core/math/math_funcs.h"
#include "core/math/vector3.h"

// Extended Position-Based Dynamics (XPBD): compliance is normalized once
// per physical step as alpha_tilde = compliance / (dt * dt). Lambda is
// accumulated only within the substep, then cleared before the next step.
//
// Returns false for immovable/degenerate constraints without touching lambda.
static inline bool godot_physics_xpbd_scalar_delta(real_t p_error, real_t p_inverse_mass_gradient_sum, real_t p_alpha_tilde, real_t &r_lambda, real_t &r_delta_lambda) {
	if (!(p_inverse_mass_gradient_sum > 0.0)) {
		return false;
	}
	const real_t denominator = p_inverse_mass_gradient_sum + p_alpha_tilde;
	if (!(denominator > CMP_EPSILON) || !Math::is_finite(denominator)) {
		return false;
	}
	const real_t delta = -(p_error + p_alpha_tilde * r_lambda) / denominator;
	if (!Math::is_finite(delta)) {
		return false;
	}
	r_lambda += delta;
	r_delta_lambda = delta;
	return true;
}

static inline bool godot_physics_xpbd_distance_3d(Vector3 &r_a, real_t p_inv_mass_a, Vector3 &r_b, real_t p_inv_mass_b, real_t p_rest_length, real_t p_alpha_tilde, real_t &r_lambda) {
	const Vector3 delta = r_b - r_a;
	const real_t length = delta.length();
	if (!(length > CMP_EPSILON) || !Math::is_finite(length)) {
		return false;
	}
	real_t delta_lambda;
	if (!godot_physics_xpbd_scalar_delta(length - p_rest_length, p_inv_mass_a + p_inv_mass_b, p_alpha_tilde, r_lambda, delta_lambda)) {
		return false;
	}
	const Vector3 correction = delta * (delta_lambda / length);
	r_a -= correction * p_inv_mass_a;
	r_b += correction * p_inv_mass_b;
	return true;
}
