/**************************************************************************/
/*  physics_ccd_capsule_pair_toi.h                                        */
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
#include "core/math/vector2.h"
#include "core/math/vector3.h"

// A deterministic linear-only TOI for capsules with arbitrary fixed axes.
// The distance between their center segments, as A translates relative to B,
// is convex in the time fraction. Minimize it using the monotone derivative
// of squared distance, then bisect the first crossing of the combined radius.
// Unlike casting individual support points, this catches skew-axis grazing
// collisions even when both bodies are separated at the end of the step.
//
// HIT and MISS are conclusive. FALLBACK preserves the existing CCD behavior
// for initial overlap, invalid geometry and numerically uncertain cases.
// Constant stack storage, bounded iterations and double intermediates.
enum class PhysicsCCDCapsulePairTOIResult {
	HIT,
	MISS,
	FALLBACK,
};

namespace PhysicsCCDCapsulePairInternal {

struct Vec3 {
	double x;
	double y;
	double z;

	Vec3 operator+(const Vec3 &p_other) const { return { x + p_other.x, y + p_other.y, z + p_other.z }; }
	Vec3 operator-(const Vec3 &p_other) const { return { x - p_other.x, y - p_other.y, z - p_other.z }; }
	Vec3 operator*(double p_scale) const { return { x * p_scale, y * p_scale, z * p_scale }; }
};

_FORCE_INLINE_ double dot(const Vec3 &p_a, const Vec3 &p_b) {
	return p_a.x * p_b.x + p_a.y * p_b.y + p_a.z * p_b.z;
}

_FORCE_INLINE_ Vec3 cross(const Vec3 &p_a, const Vec3 &p_b) {
	return {
		p_a.y * p_b.z - p_a.z * p_b.y,
		p_a.z * p_b.x - p_a.x * p_b.z,
		p_a.x * p_b.y - p_a.y * p_b.x,
	};
}

struct Distance {
	double squared;
	double derivative_half;
};

// Closest points on two finite segments. The first segment translates by
// p_motion * p_fraction. The derivative of squared distance with respect to
// fraction is 2 * (closest_A - closest_B).dot(motion), including at feature
// transitions, because squared distance to a convex set is differentiable.
_FORCE_INLINE_ Distance distance_at(const Vec3 &p_start_delta, const Vec3 &p_motion,
		const Vec3 &p_segment_a, const Vec3 &p_segment_b,
		double p_a, double p_e, double p_b, double p_fraction) {
	const Vec3 r = p_start_delta + p_motion * p_fraction;
	// The segment directions remain fixed during a linear sweep. Cache
	// their Gram matrix instead of recomputing it at each TOI iteration.
	const double a = p_a;
	const double e = p_e;
	const double b = p_b;
	const double f = dot(p_segment_b, r);
	double s = 0.0;
	double t = 0.0;

	if (a <= 0.0) {
		t = e > 0.0 ? CLAMP(f / e, 0.0, 1.0) : 0.0;
	} else {
		const double c = dot(p_segment_a, r);
		if (e <= 0.0) {
			s = CLAMP(-c / a, 0.0, 1.0);
		} else {
			const double denom = a * e - b * b;
			if (denom > 0.0) {
				s = CLAMP((b * f - c * e) / denom, 0.0, 1.0);
			}
			t = (b * s + f) / e;
			if (t < 0.0) {
				t = 0.0;
				s = CLAMP(-c / a, 0.0, 1.0);
			} else if (t > 1.0) {
				t = 1.0;
				s = CLAMP((b - c) / a, 0.0, 1.0);
			}
		}
	}

	const Vec3 nearest = r + p_segment_a * s - p_segment_b * t;
	return { dot(nearest, nearest), dot(nearest, p_motion) };
}

} // namespace PhysicsCCDCapsulePairInternal

_FORCE_INLINE_ PhysicsCCDCapsulePairTOIResult physics_ccd_capsule_pair_toi(
		const Vector3 &p_center_delta, const Vector3 &p_relative_motion,
		const Vector3 &p_axis_a, const Vector3 &p_axis_b,
		double p_half_segment_a, double p_half_segment_b, double p_combined_radius,
		double &r_fraction) {
	using namespace PhysicsCCDCapsulePairInternal;
	if (!(p_half_segment_a >= 0.0 && p_half_segment_b >= 0.0 && p_combined_radius > 0.0) ||
			!Math::is_finite(p_half_segment_a) || !Math::is_finite(p_half_segment_b) ||
			!Math::is_finite(p_combined_radius)) {
		return PhysicsCCDCapsulePairTOIResult::FALLBACK;
	}

	Vec3 axis_a = { double(p_axis_a.x), double(p_axis_a.y), double(p_axis_a.z) };
	Vec3 axis_b = { double(p_axis_b.x), double(p_axis_b.y), double(p_axis_b.z) };
	const double axis_a_sq = dot(axis_a, axis_a);
	const double axis_b_sq = dot(axis_b, axis_b);
	if (!(axis_a_sq > 0.0 && axis_b_sq > 0.0) ||
			!Math::is_finite(axis_a_sq) || !Math::is_finite(axis_b_sq)) {
		return PhysicsCCDCapsulePairTOIResult::FALLBACK;
	}
	axis_a = axis_a * (1.0 / Math::sqrt(axis_a_sq));
	axis_b = axis_b * (1.0 / Math::sqrt(axis_b_sq));

	const Vec3 center = { double(p_center_delta.x), double(p_center_delta.y), double(p_center_delta.z) };
	const Vec3 motion = { double(p_relative_motion.x), double(p_relative_motion.y), double(p_relative_motion.z) };
	const double motion_squared = dot(motion, motion);
	if (!Math::is_finite(motion_squared) ||
			!Math::is_finite(center.x) || !Math::is_finite(center.y) || !Math::is_finite(center.z)) {
		return PhysicsCCDCapsulePairTOIResult::FALLBACK;
	}
	if (!(motion_squared > 0.0)) {
		return PhysicsCCDCapsulePairTOIResult::MISS;
	}

	// A separating axis perpendicular to both capsule center segments
	// is a cheap necessary condition for a 3D skew-axis hit. Their
	// endpoint offsets have zero projection on this axis: if the entire
	// relative sweep stays farther than the combined radius on one
	// side of the plane, the expensive closest-distance iterations can
	// be skipped. For planar 2D capsules this test cannot reject anything.
	if (center.z != 0.0 || motion.z != 0.0 || axis_a.z != 0.0 || axis_b.z != 0.0) {
		const Vec3 normal = cross(axis_a, axis_b);
		const double normal_squared = dot(normal, normal);
		if (normal_squared > 0.0) {
			const double reach = p_combined_radius * Math::sqrt(normal_squared);
			const double separation_begin = dot(normal, center);
			const double separation_end = separation_begin + dot(normal, motion);
			if ((separation_begin > reach && separation_end > reach) ||
					(separation_begin < -reach && separation_end < -reach)) {
				return PhysicsCCDCapsulePairTOIResult::MISS;
			}
		}
	}

	const Vec3 segment_a = axis_a * (2.0 * p_half_segment_a);
	const Vec3 segment_b = axis_b * (2.0 * p_half_segment_b);
	const double segment_a_squared = dot(segment_a, segment_a);
	const double segment_b_squared = dot(segment_b, segment_b);
	const double segment_dot = dot(segment_a, segment_b);
	const Vec3 start_delta = center - axis_a * p_half_segment_a + axis_b * p_half_segment_b;
	const double radius_sq = p_combined_radius * p_combined_radius;
	if (!Math::is_finite(radius_sq)) {
		return PhysicsCCDCapsulePairTOIResult::FALLBACK;
	}
	const Distance start = distance_at(start_delta, motion, segment_a, segment_b,
			segment_a_squared, segment_b_squared, segment_dot, 0.0);
	if (!Math::is_finite(start.squared) || !Math::is_finite(start.derivative_half)) {
		return PhysicsCCDCapsulePairTOIResult::FALLBACK;
	}
	if (!(start.squared > radius_sq)) {
		return PhysicsCCDCapsulePairTOIResult::FALLBACK; // Initially contacting.
	}
	if (start.derivative_half >= 0.0) {
		return PhysicsCCDCapsulePairTOIResult::MISS; // Squared distance is convex.
	}

	// Raycast fractions are ultimately stored as real_t. A float32
	// build needs fewer bisections than a double build to get a result
	// well below one representable time fraction. Do not pay for double
	// precision in every default-precision physics pair.
	const int search_iterations = sizeof(real_t) == sizeof(float) ? 32 : 48;

	// Find the unique time of minimum squared distance, or the end of
	// the sweep when the distance is still decreasing. No allocations.
	double minimum_fraction = 1.0;
	const Distance end = distance_at(start_delta, motion, segment_a, segment_b,
			segment_a_squared, segment_b_squared, segment_dot, 1.0);
	if (!Math::is_finite(end.squared) || !Math::is_finite(end.derivative_half)) {
		return PhysicsCCDCapsulePairTOIResult::FALLBACK;
	}
	if (end.derivative_half > 0.0) {
		double low = 0.0;
		double high = 1.0;
		for (int i = 0; i < search_iterations; ++i) {
			const double mid = 0.5 * (low + high);
			const Distance value = distance_at(start_delta, motion, segment_a, segment_b,
			segment_a_squared, segment_b_squared, segment_dot, mid);
			if (value.derivative_half < 0.0) {
				low = mid;
			} else {
				high = mid;
			}
		}
		minimum_fraction = high;
	}

	const Distance minimum = distance_at(start_delta, motion, segment_a, segment_b,
			segment_a_squared, segment_b_squared, segment_dot, minimum_fraction);
	if (!Math::is_finite(minimum.squared)) {
		return PhysicsCCDCapsulePairTOIResult::FALLBACK;
	}
	if (!(minimum.squared <= radius_sq)) {
		return minimum.squared > radius_sq ? PhysicsCCDCapsulePairTOIResult::MISS : PhysicsCCDCapsulePairTOIResult::FALLBACK;
	}

	// Squared distance decreases monotonically over [0, minimum_fraction].
	// Bracket its first crossing of the capsule radius and bisect it.
	double low = 0.0;
	double high = minimum_fraction;
	for (int i = 0; i < search_iterations; ++i) {
		const double mid = 0.5 * (low + high);
		const Distance value = distance_at(start_delta, motion, segment_a, segment_b,
			segment_a_squared, segment_b_squared, segment_dot, mid);
		if (value.squared > radius_sq) {
			low = mid;
		} else {
			high = mid;
		}
	}
	if (!(high >= 0.0 && high <= 1.0)) {
		return PhysicsCCDCapsulePairTOIResult::FALLBACK;
	}
	r_fraction = high;
	return PhysicsCCDCapsulePairTOIResult::HIT;
}

_FORCE_INLINE_ PhysicsCCDCapsulePairTOIResult physics_ccd_capsule_pair_toi(
		const Vector2 &p_center_delta, const Vector2 &p_relative_motion,
		const Vector2 &p_axis_a, const Vector2 &p_axis_b,
		double p_half_segment_a, double p_half_segment_b, double p_combined_radius,
		double &r_fraction) {
	return physics_ccd_capsule_pair_toi(
			Vector3(p_center_delta.x, p_center_delta.y, 0.0),
			Vector3(p_relative_motion.x, p_relative_motion.y, 0.0),
			Vector3(p_axis_a.x, p_axis_a.y, 0.0),
			Vector3(p_axis_b.x, p_axis_b.y, 0.0),
			p_half_segment_a, p_half_segment_b, p_combined_radius, r_fraction);
}
