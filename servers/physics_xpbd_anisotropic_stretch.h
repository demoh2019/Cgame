/**************************************************************************/
/*  physics_xpbd_anisotropic_stretch.h                                    */
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

#include "core/math/math_funcs.h"
#include "core/math/vector3.h"

#include <limits>

// Rest-frame orthotropic *edge* compliance for XPBD cloth / soft bodies.
// The material axis and link endpoints are specified in the undeformed mesh's
// LOCAL coordinate system, so rotating the instance does not rotate its
// material relative to the mesh. This is a directional edge approximation,
// NOT a full orthotropic continuum/FEM constitutive model.
//
//   alignment = cos^2(angle between edge_rest and material_axis)
//   effective_alpha = base_alpha * (1 + (parallel_ratio - 1) * alignment)
//
// parallel_ratio < 1: stiffer along the fiber direction; > 1: more compliant.
// The perpendicular compliance remains the original alpha. The result must
// be calculated ONCE per physics step before the iterative XPBD projection;
// no new lambda is introduced. Invalid inputs never modify r_alpha.
//
// Uses double intermediates to avoid overflow from large finite float32
// coordinates. It tolerates a collapsed rest edge by returning base_alpha.
_FORCE_INLINE_ static bool physics_xpbd_anisotropic_stretch_alpha(
        const Vector3 &p_rest_a, const Vector3 &p_rest_b,
        const Vector3 &p_material_axis, real_t p_base_alpha,
        real_t p_parallel_ratio, real_t &r_alpha) {
    if (!p_rest_a.is_finite() || !p_rest_b.is_finite() ||
            !p_material_axis.is_finite() ||
            !Math::is_finite(p_base_alpha) || p_base_alpha < real_t(0.0) ||
            !Math::is_finite(p_parallel_ratio) || p_parallel_ratio <= real_t(0.0)) {
        return false;
    }
    if (p_parallel_ratio == real_t(1.0) || p_base_alpha == real_t(0.0)) {
        r_alpha = p_base_alpha;
        return true;
    }

    const double dx = double(p_rest_b.x) - double(p_rest_a.x);
    const double dy = double(p_rest_b.y) - double(p_rest_a.y);
    const double dz = double(p_rest_b.z) - double(p_rest_a.z);
    const double ax = double(p_material_axis.x);
    const double ay = double(p_material_axis.y);
    const double az = double(p_material_axis.z);
    const double edge_sq = dx * dx + dy * dy + dz * dz;
    const double axis_sq = ax * ax + ay * ay + az * az;
    if (!(edge_sq >= 0.0) || !Math::is_finite(edge_sq) ||
            !(axis_sq > 0.0) || !Math::is_finite(axis_sq)) {
        return false;
    }
    if (edge_sq == 0.0) {
        r_alpha = p_base_alpha;
        return true;
    }

    // Normalize in double precision, using magnitude products, to prevent
    // alpha depending on the magnitude of the supplied axis.
    const double dot = dx * ax + dy * ay + dz * az;
    const double cosine = dot / Math::sqrt(edge_sq) / Math::sqrt(axis_sq);
    if (!Math::is_finite(cosine)) {
        return false;
    }
    const double alignment = CLAMP(cosine * cosine, 0.0, 1.0);
    const double multiplier = 1.0 + (double(p_parallel_ratio) - 1.0) * alignment;
    const double value = double(p_base_alpha) * multiplier;
    if (!(value >= 0.0) || !Math::is_finite(value) ||
            value > double(std::numeric_limits<real_t>::max())) {
        return false;
    }
    r_alpha = real_t(value);
    return true;
}
