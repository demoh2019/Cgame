/**************************************************************************/
/*  physics_xpbd_volume.h                                                 */
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

// Scalar XPBD correction for a global volume constraint. A zero inverse
// mass gradient (all particles pinned or degenerate geometry) is a no-op.
//
// The accumulated lambda is reset at the beginning of every physics step,
// and p_alpha_tilde is compliance / (dt * dt).
static inline bool physics_xpbd_volume_delta(real_t p_error, real_t p_weighted_gradient_norm, real_t p_alpha_tilde, real_t &r_lambda, real_t &r_delta_lambda) {
	if (!(p_weighted_gradient_norm > CMP_EPSILON) || p_alpha_tilde < 0.0) {
		return false;
	}
	const real_t denominator = p_weighted_gradient_norm + p_alpha_tilde;
	if (!(denominator > 0.0) || !Math::is_finite(denominator)) {
		return false;
	}
	const real_t delta_lambda = -(p_error + p_alpha_tilde * r_lambda) / denominator;
	if (!Math::is_finite(delta_lambda)) {
		return false;
	}
	r_lambda += delta_lambda;
	r_delta_lambda = delta_lambda;
	return true;
}

// Signed volume and its gradients for a triangle with respect to a common
// reference origin. Sum over all consistently oriented faces of a closed
// triangle mesh. One-sixth is required for actual volume (rather than the
// six-times tetrahedron determinant).
static inline real_t physics_xpbd_triangle_volume_terms(const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c, Vector3 &r_grad_a, Vector3 &r_grad_b, Vector3 &r_grad_c) {
	constexpr real_t ONE_SIXTH = real_t(1.0 / 6.0);
	r_grad_a = p_b.cross(p_c) * ONE_SIXTH;
	r_grad_b = p_c.cross(p_a) * ONE_SIXTH;
	r_grad_c = p_a.cross(p_b) * ONE_SIXTH;
	return p_a.dot(p_b.cross(p_c)) * ONE_SIXTH;
}
