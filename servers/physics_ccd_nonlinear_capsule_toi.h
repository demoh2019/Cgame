/**************************************************************************/
/*  physics_ccd_nonlinear_capsule_toi.h                                   */
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

#include "servers/physics_ccd_rotating_capsule_toi.h"

// Conservative nonlinear CCD for a uniformly scaled rigid capsule combining
// linear translation with angular rotation, against a stationary sphere.
// All inputs are world-space; p_linear_motion is displacement over p_step,
// not velocity. The capsule rotates about the body's world-space center of
// mass while that center moves by p_linear_motion * fraction.
//
// If the center segment moves and rotates, every point travels at most
// |linear_motion| + |omega| * step * (|center - pivot| + half_segment)
// over one normalized timestep. Distance to the finite capsule axis is
// 1-Lipschitz under this bound. Advancing conservatively by 95% of the
// current gap cannot jump over an impact that occurs between samples.
//
// HIT is the first near-contact time. MISS is a conclusive separation.
// FALLBACK preserves existing CCD for overlap, invalid data or iteration
// exhaustion. This has bounded work (64 samples), no heap allocations.
template <typename TVector, typename TAngularVelocity>
_FORCE_INLINE_ PhysicsCCDRotatingCapsuleTOIResult physics_ccd_nonlinear_capsule_toi(
        const TVector &p_capsule_center, const TVector &p_capsule_axis,
        const TVector &p_world_center_of_mass, const TVector &p_static_sphere_center,
        const TVector &p_linear_motion, const TAngularVelocity &p_omega,
        real_t p_step, double p_half_segment, double p_combined_radius,
        double &r_fraction) {
    if (!p_capsule_center.is_finite() || !p_capsule_axis.is_finite() ||
            !p_world_center_of_mass.is_finite() || !p_static_sphere_center.is_finite() ||
            !p_linear_motion.is_finite() || !(p_step > 0.0) || !Math::is_finite(p_step) ||
            !(p_half_segment >= 0.0) || !Math::is_finite(p_half_segment) ||
            !(p_combined_radius > 0.0) || !Math::is_finite(p_combined_radius)) {
        return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK;
    }

    const double angular_speed = physics_ccd_rotation_speed(p_omega);
    const double axis_length = double(p_capsule_axis.length());
    const double center_radius = double((p_capsule_center - p_world_center_of_mass).length());
    const double linear_distance = double(p_linear_motion.length());
    if (!(angular_speed > 0.0) || !(axis_length > 0.0) ||
            !Math::is_finite(angular_speed) || !Math::is_finite(axis_length) ||
            !Math::is_finite(center_radius) || !Math::is_finite(linear_distance)) {
        return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK;
    }

    const double maximal_travel = linear_distance +
            angular_speed * double(p_step) * (center_radius + p_half_segment);
    if (!(maximal_travel > 0.0) || !Math::is_finite(maximal_travel)) {
        return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK;
    }
    const TVector initial_axis = p_capsule_axis / real_t(axis_length);
    const TVector center_from_pivot = p_capsule_center - p_world_center_of_mass;
    const double epsilon = MAX(1e-6, p_combined_radius * 1e-5);
    double fraction = 0.0;

    for (int i = 0; i < 64; ++i) {
        const double seconds = fraction * double(p_step);
        const TVector center = p_world_center_of_mass +
                p_linear_motion * real_t(fraction) +
                physics_ccd_rotate_vector(center_from_pivot, p_omega, seconds);
        const TVector axis = physics_ccd_rotate_vector(initial_axis, p_omega, seconds);
        if (!center.is_finite() || !axis.is_finite()) {
            return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK;
        }

        const TVector delta = p_static_sphere_center - center;
        const double projected = CLAMP(double(delta.dot(axis)), -p_half_segment, p_half_segment);
        const TVector nearest = center + axis * real_t(projected);
        const double distance = double((p_static_sphere_center - nearest).length());
        if (!Math::is_finite(distance)) {
            return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK;
        }
        const double gap = distance - p_combined_radius;
        if (gap <= epsilon) {
            if (fraction == 0.0) {
                return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK;
            }
            r_fraction = fraction;
            return PhysicsCCDRotatingCapsuleTOIResult::HIT;
        }
        if (fraction >= 1.0) {
            return PhysicsCCDRotatingCapsuleTOIResult::MISS;
        }
        const double remaining = 1.0 - fraction;
        if (gap - epsilon > maximal_travel * remaining) {
            return PhysicsCCDRotatingCapsuleTOIResult::MISS;
        }
        const double progress = gap * 0.95 / maximal_travel;
        if (!(progress > 0.0) || !Math::is_finite(progress)) {
            return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK;
        }
        const double next_fraction = MIN(1.0, fraction + progress);
        if (!(next_fraction > fraction)) {
            return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK;
        }
        fraction = next_fraction;
    }
    return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK;
}
