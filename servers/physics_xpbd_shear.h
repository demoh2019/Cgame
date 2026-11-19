/**************************************************************************/
/*  physics_xpbd_shear.h                                                    */
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

#include "core/math/vector3.h"

// Preserves the off-diagonal term of a triangle's rest metric (in-plane
// shear). C = ((b-a) dot (c-a) - rest_dot) / rest_scale, where rest_scale
// is the product of the two original edge lengths. Unlike the normal or
// area constraints, this also resists a parallelogram-like distortion.
// Lambda persists between iterations, but resets at each physics step.
// All input validation is atomic, so invalid geometry leaves no mutation.
_FORCE_INLINE_ bool physics_xpbd_solve_triangle_shear(
        Vector3 &r_a, Vector3 &r_b, Vector3 &r_c,
        real_t p_inv_mass_a, real_t p_inv_mass_b, real_t p_inv_mass_c,
        real_t p_rest_dot, real_t p_rest_scale, real_t p_alpha, real_t &r_lambda) {
    if (!r_a.is_finite() || !r_b.is_finite() || !r_c.is_finite() ||
            !Math::is_finite(p_inv_mass_a) || !Math::is_finite(p_inv_mass_b) ||
            !Math::is_finite(p_inv_mass_c) || !Math::is_finite(p_rest_dot) ||
            !Math::is_finite(p_rest_scale) || !Math::is_finite(p_alpha) ||
            !Math::is_finite(r_lambda) ||
            p_inv_mass_a < 0.0 || p_inv_mass_b < 0.0 || p_inv_mass_c < 0.0 ||
            !(p_rest_scale > 0.0) || p_alpha < 0.0 ||
            (p_inv_mass_a == 0.0 && p_inv_mass_b == 0.0 && p_inv_mass_c == 0.0)) {
        return false;
    }
    const Vector3 ab = r_b - r_a;
    const Vector3 ac = r_c - r_a;
    const real_t inv_scale = real_t(1.0 / double(p_rest_scale));
    if (!ab.is_finite() || !ac.is_finite() ||
            !(inv_scale > 0.0) || !Math::is_finite(inv_scale)) {
        return false;
    }
    const Vector3 grad_b = ac * inv_scale;
    const Vector3 grad_c = ab * inv_scale;
    const Vector3 grad_a = -(grad_b + grad_c);
    if (!grad_a.is_finite() || !grad_b.is_finite() || !grad_c.is_finite()) {
        return false;
    }

    const double dot = double(ab.x) * double(ac.x) +
            double(ab.y) * double(ac.y) + double(ab.z) * double(ac.z);
    const double error = (dot - double(p_rest_dot)) / double(p_rest_scale);
    const double weighted_gradient =
            double(p_inv_mass_a) * double(grad_a.length_squared()) +
            double(p_inv_mass_b) * double(grad_b.length_squared()) +
            double(p_inv_mass_c) * double(grad_c.length_squared());
    const double denominator = weighted_gradient + double(p_alpha);
    if (!Math::is_finite(error) || !(weighted_gradient > 0.0) ||
            !Math::is_finite(weighted_gradient) ||
            !(denominator > 0.0) || !Math::is_finite(denominator)) {
        return false;
    }
    const double delta_lambda = -(error + double(p_alpha) * double(r_lambda)) / denominator;
    const real_t next_lambda = real_t(double(r_lambda) + delta_lambda);
    if (!Math::is_finite(delta_lambda) || !Math::is_finite(next_lambda)) {
        return false;
    }
    // Compute all new positions before writing any of them, including pins.
    const double weight_a = double(p_inv_mass_a) * delta_lambda;
    const double weight_b = double(p_inv_mass_b) * delta_lambda;
    const double weight_c = double(p_inv_mass_c) * delta_lambda;
    const Vector3 next_a(
            real_t(double(r_a.x) + double(grad_a.x) * weight_a),
            real_t(double(r_a.y) + double(grad_a.y) * weight_a),
            real_t(double(r_a.z) + double(grad_a.z) * weight_a));
    const Vector3 next_b(
            real_t(double(r_b.x) + double(grad_b.x) * weight_b),
            real_t(double(r_b.y) + double(grad_b.y) * weight_b),
            real_t(double(r_b.z) + double(grad_b.z) * weight_b));
    const Vector3 next_c(
            real_t(double(r_c.x) + double(grad_c.x) * weight_c),
            real_t(double(r_c.y) + double(grad_c.y) * weight_c),
            real_t(double(r_c.z) + double(grad_c.z) * weight_c));
    if (!next_a.is_finite() || !next_b.is_finite() || !next_c.is_finite()) {
        return false;
    }
    r_a = next_a;
    r_b = next_b;
    r_c = next_c;
    r_lambda = next_lambda;
    return true;
}
