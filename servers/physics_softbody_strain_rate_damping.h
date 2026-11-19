/**************************************************************************/
/*  physics_softbody_strain_rate_damping.h                                */
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

#include "servers/physics_softbody_link_damping.h"

// Strain-rate-sensitive viscoelastic soft-body link dashpot (shear-thickening
// style response for fast compression / stretching).
//
// strain_rate = abs(dot(v_b-v_a, n)) / rest_length [1/s]
// effective_rate = coefficient * max(0, strain_rate - yield_rate) [1/s]
// fraction = 1 - exp(-effective_rate * dt).
//
// This is a rate-dependent longitudinal damping model, not a full
// non-Newtonian fluid or a finite-element constitutive equation.
// The mass-weighted two-particle impulse below conserves linear momentum
// and dissipates (never adds) relative longitudinal kinetic energy.
// Link coordinates and velocities are never mutated on invalid inputs.
// With coefficient=0, callers skip the entire pass at zero runtime cost.
_FORCE_INLINE_ static bool physics_softbody_damp_strain_rate(
        const Vector3 &p_position_a, const Vector3 &p_position_b,
        Vector3 &r_velocity_a, Vector3 &r_velocity_b,
        real_t p_inverse_mass_a, real_t p_inverse_mass_b,
        real_t p_rest_length, real_t p_coefficient, real_t p_yield_rate,
        double p_delta) {
    if (!p_position_a.is_finite() || !p_position_b.is_finite() ||
            !r_velocity_a.is_finite() || !r_velocity_b.is_finite() ||
            !Math::is_finite(p_inverse_mass_a) || !Math::is_finite(p_inverse_mass_b) ||
            p_inverse_mass_a < real_t(0.0) || p_inverse_mass_b < real_t(0.0) ||
            !(p_inverse_mass_a > real_t(0.0) || p_inverse_mass_b > real_t(0.0)) ||
            !Math::is_finite(p_rest_length) || !(p_rest_length > real_t(0.0)) ||
            !Math::is_finite(p_coefficient) || !(p_coefficient > real_t(0.0)) ||
            !Math::is_finite(p_yield_rate) || p_yield_rate < real_t(0.0) ||
            !Math::is_finite(p_delta) || !(p_delta > 0.0)) {
        return false;
    }

    const double dx = double(p_position_b.x) - double(p_position_a.x);
    const double dy = double(p_position_b.y) - double(p_position_a.y);
    const double dz = double(p_position_b.z) - double(p_position_a.z);
    const double separation_squared = dx * dx + dy * dy + dz * dz;
    if (!(separation_squared > 0.0) || !Math::is_finite(separation_squared)) {
        return false;
    }
    const double inv_separation = 1.0 / Math::sqrt(separation_squared);
    const double dvx = double(r_velocity_b.x) - double(r_velocity_a.x);
    const double dvy = double(r_velocity_b.y) - double(r_velocity_a.y);
    const double dvz = double(r_velocity_b.z) - double(r_velocity_a.z);
    const double relative_speed = Math::abs((dvx * dx + dvy * dy + dvz * dz) * inv_separation);
    if (!Math::is_finite(relative_speed)) {
        return false;
    }
    const double strain_rate = relative_speed / double(p_rest_length);
    const double excess_rate = strain_rate - double(p_yield_rate);
    if (!(excess_rate > 0.0)) {
        return false;
    }
    const double exponent = double(p_coefficient) * p_delta * excess_rate;
    const double fraction = !Math::is_finite(exponent) || exponent >= 50.0 ?
            1.0 : 1.0 - Math::exp(-exponent);
    if (!(fraction > 0.0)) {
        return false;
    }
    return physics_softbody_damp_link(p_position_a, p_position_b,
            r_velocity_a, r_velocity_b,
            p_inverse_mass_a, p_inverse_mass_b, fraction);
}
