/**************************************************************************/
/*  physics_xpbd_compression_hardening.h                                  */
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

#include "core/math/vector3.h"

// Phenomenological compressive strain-hardening for a soft-body XPBD link.
// In compression e = max(0, 1 - length/rest_length - yield_strain):
// alpha_eff = alpha / (1 + hardening * e^2).
// The compliance is evaluated on predicted positions ONCE per physics step,
// before iterative XPBD projections, to keep the Lagrange multiplier stable.
// It may be applied after tension hardening: the strain modes are mutually
// exclusive and the previous effective alpha is retained in tension.
// This is a nonlinear edge material, not continuum hyperelasticity/FEM.
// All geometric arithmetic uses double to avoid intermediate overflow.
_FORCE_INLINE_ static bool physics_xpbd_compression_hardening_alpha(
        const Vector3 &p_a, const Vector3 &p_b,
        real_t p_rest_length, real_t p_base_alpha,
        real_t p_yield_strain, real_t p_hardening,
        real_t &r_alpha) {
    if (!p_a.is_finite() || !p_b.is_finite() ||
            !Math::is_finite(p_rest_length) || !Math::is_finite(p_base_alpha) ||
            !Math::is_finite(p_yield_strain) || !Math::is_finite(p_hardening) ||
            p_rest_length < real_t(0.0) || p_base_alpha < real_t(0.0) ||
            p_yield_strain < real_t(0.0) || p_hardening < real_t(0.0)) {
        return false;
    }

    if (p_rest_length == real_t(0.0) || p_hardening == real_t(0.0) ||
            p_base_alpha == real_t(0.0)) {
        r_alpha = p_base_alpha;
        return true;
    }

    const double dx = double(p_b.x) - double(p_a.x);
    const double dy = double(p_b.y) - double(p_a.y);
    const double dz = double(p_b.z) - double(p_a.z);
    const double length_squared = dx * dx + dy * dy + dz * dz;
    if (!(length_squared >= 0.0) || !Math::is_finite(length_squared)) {
        return false;
    }

    const double length = Math::sqrt(length_squared);
    // Rewriting as (rest-length)/rest avoids subtracting two close ratios.
    const double compression = (double(p_rest_length) - length) / double(p_rest_length);
    const double excess = compression - double(p_yield_strain);
    if (!Math::is_finite(excess)) {
        return false;
    }
    if (excess <= 0.0) {
        r_alpha = p_base_alpha;
        return true;
    }

    const double product = double(p_hardening) * excess * excess;
    const double multiplier = Math::is_finite(product) ? MIN(product, 1e6) : 1e6;
    const real_t result = real_t(double(p_base_alpha) / (1.0 + multiplier));
    if (!Math::is_finite(result) || result < real_t(0.0)) {
        return false;
    }
    r_alpha = result;
    return true;
}
