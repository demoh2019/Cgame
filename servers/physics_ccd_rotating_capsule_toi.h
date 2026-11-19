/**************************************************************************/
/*  physics_ccd_rotating_capsule_toi.h                                    */
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

#include "core/math/basis.h"
#include "core/math/math_funcs.h"
#include "core/math/vector2.h"
#include "core/math/vector3.h"

// Nonlinear angular TOI for a uniformly scaled capsule spinning around its
// rigid body's (possibly offset) center of mass, against a stationary
// sphere/circle. Both centers are expressed in the SAME frame. There is no
// translation: that case must continue through the existing linear CCD path.
//
// Conservative advancement uses an upper bound on the speed of every point
// on the rotating capsule centerline: |omega| * (|center - pivot| + half_seg).
// Since the distance-to-segment function is 1-Lipschitz, advancing by at
// most the current gap / bound cannot skip a true first contact, even if
// the shape crosses the target and separates again during one step.
//
// HIT supplies a fraction of the angular step at first near-contact.
// MISS is only returned after proving that the remaining rotation cannot
// close the gap. FALLBACK means invalid geometry, existing overlap, or
// nonconvergence: caller must preserve the existing collision behavior.
// Every temporary is stack-local; maximum 48 evaluations, no allocations.
enum class PhysicsCCDRotatingCapsuleTOIResult {
	HIT,
	MISS,
	FALLBACK,
};

_FORCE_INLINE_ static Vector2 physics_ccd_rotate_vector(const Vector2 &p_vector, real_t p_omega, double p_seconds) {
	return p_vector.rotated(p_omega * real_t(p_seconds));
}

_FORCE_INLINE_ static Vector3 physics_ccd_rotate_vector(const Vector3 &p_vector, const Vector3 &p_omega, double p_seconds) {
	const real_t magnitude = p_omega.length();
	if (!(magnitude > 0.0)) {
		return p_vector;
	}
	return Basis(p_omega / magnitude, magnitude * real_t(p_seconds)).xform(p_vector);
}

_FORCE_INLINE_ static double physics_ccd_rotation_speed(real_t p_omega) {
	return Math::abs(double(p_omega));
}

_FORCE_INLINE_ static double physics_ccd_rotation_speed(const Vector3 &p_omega) {
	return double(p_omega.length());
}

template <typename TVector, typename TAngularVelocity>
_FORCE_INLINE_ static PhysicsCCDRotatingCapsuleTOIResult physics_ccd_rotating_capsule_toi(
		const TVector &p_capsule_center, const TVector &p_capsule_axis,
		const TVector &p_center_of_mass, const TVector &p_static_sphere_center,
		const TAngularVelocity &p_omega, real_t p_step,
		double p_half_segment, double p_combined_radius, double &r_fraction) {
	if (!p_capsule_center.is_finite() || !p_capsule_axis.is_finite() ||
			!p_center_of_mass.is_finite() || !p_static_sphere_center.is_finite() ||
			!(p_step > 0.0) || !Math::is_finite(p_step) ||
			!(p_half_segment >= 0.0) || !Math::is_finite(p_half_segment) ||
			!(p_combined_radius > 0.0) || !Math::is_finite(p_combined_radius)) {
		return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK;
	}
	const double angular_speed = physics_ccd_rotation_speed(p_omega);
	if (!(angular_speed > 0.0) || !Math::is_finite(angular_speed)) {
		return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK;
	}

	const double axis_length = double(p_capsule_axis.length());
	const double center_radius = double((p_capsule_center - p_center_of_mass).length());
	if (!(axis_length > 0.0) || !Math::is_finite(axis_length) ||
			!Math::is_finite(center_radius)) {
		return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK;
	}
	const TVector axis = p_capsule_axis / real_t(axis_length);
	const TVector center_from_pivot = p_capsule_center - p_center_of_mass;
	const double maximal_travel = angular_speed * double(p_step) * (center_radius + p_half_segment);
	if (!(maximal_travel > 0.0) || !Math::is_finite(maximal_travel)) {
		return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK;
	}
	const double epsilon = MAX(1e-6, p_combined_radius * 1e-5);
	double fraction = 0.0;

	for (int i = 0; i < 48; ++i) {
		const double time = fraction * double(p_step);
		const TVector center = p_center_of_mass + physics_ccd_rotate_vector(center_from_pivot, p_omega, time);
		const TVector direction = physics_ccd_rotate_vector(axis, p_omega, time);
		if (!center.is_finite() || !direction.is_finite()) {
			return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK;
		}
		const TVector center_to_sphere = p_static_sphere_center - center;
		const double closest_on_axis = CLAMP(double(center_to_sphere.dot(direction)), -p_half_segment, p_half_segment);
		const TVector nearest = center + direction * real_t(closest_on_axis);
		const double distance = double((p_static_sphere_center - nearest).length());
		if (!Math::is_finite(distance)) {
			return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK;
		}
		const double gap = distance - p_combined_radius;
		if (gap <= epsilon) {
			if (fraction == 0.0) {
				return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK; // Already touching or overlapping.
			}
			r_fraction = fraction;
			return PhysicsCCDRotatingCapsuleTOIResult::HIT;
		}
		if (fraction >= 1.0) {
			return PhysicsCCDRotatingCapsuleTOIResult::MISS;
		}

		// A 95% safety factor leaves room for floating point rounding.
		// If even the most aggressive closing trajectory cannot touch
		// before the end of this step, the miss is conclusive.
		const double remaining = 1.0 - fraction;
		if (gap - epsilon > maximal_travel * remaining) {
			return PhysicsCCDRotatingCapsuleTOIResult::MISS;
		}
		// Advance by a fraction of the full gap, not gap-minus-epsilon:
		// subtracting epsilon here asymptotically approaches epsilon
		// without ever reaching the HIT condition.
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
