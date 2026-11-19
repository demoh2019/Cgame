/**************************************************************************/
/*  physics_softbody_fatigue_damage.h                                     */
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

// Irreversible, bounded edge damage for XPBD soft bodies. The damage D lies
// in [0, max_damage] and does not change when strain is below the yield.
// For strain excess e and rate k, evolve via
//
//   D_next = max_damage - (max_damage - D_old) * exp(-k * e * dt).
//
// This remains monotonically bounded for any valid timestep; at constant
// strain, two half steps equal one whole step (ignoring roundoff). Calculations
// use double intermediates to prevent float32 overflow. The caller must
// retain D across simulation steps and reset it when the mesh topology changes.
//
// This is a phenomenological edge-weakening model, NOT mesh cutting/tearing,
// Miner fatigue cycle counting, continuum damage FEM, or crack propagation.
_FORCE_INLINE_ static bool physics_softbody_accumulate_fatigue_damage(
        const Vector3 &p_a, const Vector3 &p_b,
        real_t p_rest_length, real_t p_yield_strain,
        real_t p_damage_rate, real_t p_max_damage,
        double p_delta, real_t &r_damage) {
    if (!p_a.is_finite() || !p_b.is_finite() ||
            !Math::is_finite(p_rest_length) || !(p_rest_length > real_t(0.0)) ||
            !Math::is_finite(p_yield_strain) || p_yield_strain < real_t(0.0) ||
            !Math::is_finite(p_damage_rate) || p_damage_rate < real_t(0.0) ||
            !Math::is_finite(p_max_damage) || p_max_damage < real_t(0.0) ||
            p_max_damage > real_t(0.99) ||
            !Math::is_finite(p_delta) || p_delta < 0.0 ||
            !Math::is_finite(r_damage) || r_damage < real_t(0.0) ||
            r_damage > p_max_damage) {
        return false;
    }
    if (p_damage_rate == real_t(0.0) || p_delta == 0.0 ||
            r_damage >= p_max_damage || p_max_damage == real_t(0.0)) {
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
    const double strain = Math::abs(length / double(p_rest_length) - 1.0);
    if (!Math::is_finite(strain)) {
        return false;
    }
    const double excess = strain - double(p_yield_strain);
    if (!(excess > 0.0)) {
        return true;
    }

    const double exponent = double(p_damage_rate) * excess * p_delta;
    const double remaining = !Math::is_finite(exponent) || exponent >= 50.0 ?
            0.0 : Math::exp(-exponent);
    const double damage = double(p_max_damage) -
            (double(p_max_damage) - double(r_damage)) * remaining;
    if (!Math::is_finite(damage)) {
        return false;
    }
    const real_t next = real_t(CLAMP(damage, double(r_damage), double(p_max_damage)));
    if (!Math::is_finite(next)) {
        return false;
    }
    r_damage = next;
    return true;
}

// Elastic stiffness scales by (1 - D); compliance alpha therefore grows
// as alpha / (1 - D). Caller must apply this after all other material
// multipliers and before the iterative solver. Damage is bounded at 0.99,
// keeping the compliance finite and avoiding singular zero-stiffness links.
_FORCE_INLINE_ static bool physics_softbody_fatigue_compliance_alpha(
        real_t p_alpha, real_t p_damage, real_t &r_alpha) {
    if (!Math::is_finite(p_alpha) || p_alpha < real_t(0.0) ||
            !Math::is_finite(p_damage) || p_damage < real_t(0.0) ||
            p_damage > real_t(0.99)) {
        return false;
    }
    if (p_damage == real_t(0.0)) {
        r_alpha = p_alpha;
        return true;
    }
    const double value = double(p_alpha) / (1.0 - double(p_damage));
    if (!(value >= 0.0) || !Math::is_finite(value) ||
            value > double(std::numeric_limits<real_t>::max())) {
        return false;
    }
    r_alpha = real_t(value);
    return true;
}
