/**************************************************************************/
/*  physics_ccd_rotating_capsule_segment_toi.h                            */
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

#include "servers/physics_ccd_capsule_pair_toi.h"
#include "servers/physics_ccd_rotating_capsule_toi.h"

// Conservative nonlinear TOI for a rotating 2D capsule versus a fixed
// finite segment. Rotation is around the body's WORLD-space center of mass;
// translations are handled by the existing linear CCD implementation.
//
// Every point of the capsule's axial segment travels at no more than
// |omega| * (|center - pivot| + half_segment) world units per second.
// Since distance between compact sets is 1-Lipschitz under this motion,
// advancing by a fraction of gap / maximum travel cannot step past the
// first true overlap. Use the segment/segment closest-point formula at
// every angular sample, so neither segment endpoint is missed.
//
// The specialized path is opt-in through rotational CCD bounds. On initial
// contact, invalid geometry or iteration exhaustion it returns FALLBACK;
// it never allocates memory or changes body velocities itself.
_FORCE_INLINE_ PhysicsCCDRotatingCapsuleTOIResult physics_ccd_rotating_capsule_segment_toi(
		const Vector2 &p_capsule_center, const Vector2 &p_capsule_axis,
		const Vector2 &p_world_center_of_mass,
		const Vector2 &p_segment_a, const Vector2 &p_segment_b,
		real_t p_omega, real_t p_step,
		double p_half_segment, double p_capsule_radius, double &r_fraction) {
	if (!p_capsule_center.is_finite() || !p_capsule_axis.is_finite() ||
			!p_world_center_of_mass.is_finite() ||
			!p_segment_a.is_finite() || !p_segment_b.is_finite() ||
			!(p_step > 0.0) || !Math::is_finite(p_step) ||
			!(p_half_segment >= 0.0) || !Math::is_finite(p_half_segment) ||
			!(p_capsule_radius > 0.0) || !Math::is_finite(p_capsule_radius) ||
			!Math::is_finite(p_omega)) {
		return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK;
	}
	const double axis_length = double(p_capsule_axis.length());
	const double angular_speed = Math::abs(double(p_omega));
	const double center_radius = double((p_capsule_center - p_world_center_of_mass).length());
	if (!(axis_length > 0.0 && angular_speed > 0.0) ||
			!Math::is_finite(axis_length) || !Math::is_finite(center_radius)) {
		return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK;
	}
	const double maximum_travel = angular_speed * double(p_step) * (center_radius + p_half_segment);
	if (!(maximum_travel > 0.0) || !Math::is_finite(maximum_travel)) {
		return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK;
	}

	using namespace PhysicsCCDCapsulePairInternal;
	const Vec3 target_origin = { double(p_segment_a.x), double(p_segment_a.y), 0.0 };
	const Vec3 target_segment = { double(p_segment_b.x) - double(p_segment_a.x),
		double(p_segment_b.y) - double(p_segment_a.y), 0.0 };
	const double target_length_squared = dot(target_segment, target_segment);
	if (!Math::is_finite(target_length_squared)) {
		return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK;
	}

	const Vector2 initial_axis = p_capsule_axis / real_t(axis_length);
	const Vector2 initial_center_offset = p_capsule_center - p_world_center_of_mass;
	const double epsilon = MAX(1e-6, p_capsule_radius * 1e-5);
	double fraction = 0.0;

	for (int i = 0; i < 48; ++i) {
		const double seconds = fraction * double(p_step);
		const Vector2 center = p_world_center_of_mass + physics_ccd_rotate_vector(initial_center_offset, p_omega, seconds);
		const Vector2 axis = physics_ccd_rotate_vector(initial_axis, p_omega, seconds);
		if (!center.is_finite() || !axis.is_finite()) {
			return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK;
		}

		const Vec3 capsule_axis = { double(axis.x) * (2.0 * p_half_segment),
			double(axis.y) * (2.0 * p_half_segment), 0.0 };
		const Vec3 relative_start = {
			double(center.x) - double(axis.x) * p_half_segment - target_origin.x,
			double(center.y) - double(axis.y) * p_half_segment - target_origin.y, 0.0
		};
		const Distance nearest = distance_at(relative_start, Vec3{ 0.0, 0.0, 0.0 },
				capsule_axis, target_segment, dot(capsule_axis, capsule_axis),
				target_length_squared, dot(capsule_axis, target_segment), 0.0);
		if (!(nearest.squared >= 0.0) || !Math::is_finite(nearest.squared)) {
			return PhysicsCCDRotatingCapsuleTOIResult::FALLBACK;
		}
		const double gap = Math::sqrt(nearest.squared) - p_capsule_radius;
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
		if (gap - epsilon > maximum_travel * remaining) {
			return PhysicsCCDRotatingCapsuleTOIResult::MISS;
		}
		const double progress = gap * 0.95 / maximum_travel;
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
