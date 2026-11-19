/**************************************************************************/
/*  physics_ccd_rotational_sphere_cull.h                                   */
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

#include "core/math/math_funcs.h"
#include "core/math/rect2.h"
#include "core/math/aabb.h"

// A rotating rigid collider is always contained in a sphere centered on
// its moving center of mass. Compute a conservative radius from the current
// transformed shape AABB and the body's world-space center of mass; any
// subsequent rigid rotation leaves the distance of each point to that pivot
// unchanged. Intersect the two linearly swept center-of-mass spheres to
// cheaply reject CCD shape pairs impossible to hit at ANY orientation.
//
// No time-of-impact is returned and no contacts are synthesized. Incomplete
// or nonfinite geometry falls back to the existing narrowphase (return true).
// Both Vector2/Rect2 and Vector3/AABB work with the same stack-only code.
template <typename TVector, typename TBounds>
_FORCE_INLINE_ bool physics_ccd_rotational_sphere_bounds_may_overlap(
		const TBounds &p_world_bounds_a, const TVector &p_world_pivot_a,
		const TBounds &p_world_bounds_b, const TVector &p_world_pivot_b,
		const TVector &p_relative_linear_motion) {
	if (!p_world_bounds_a.is_finite() || !p_world_bounds_b.is_finite() ||
			!p_world_pivot_a.is_finite() || !p_world_pivot_b.is_finite() ||
			!p_relative_linear_motion.is_finite()) {
		return true;
	}

	const TVector support_a = (p_world_bounds_a.get_center() - p_world_pivot_a).abs() +
			p_world_bounds_a.size.abs() * real_t(0.5);
	const TVector support_b = (p_world_bounds_b.get_center() - p_world_pivot_b).abs() +
			p_world_bounds_b.size.abs() * real_t(0.5);
	if (!support_a.is_finite() || !support_b.is_finite()) {
		return true;
	}
	// Work in double to avoid overflowing squared distances in float builds.
	const double radius_a = double(support_a.length());
	const double radius_b = double(support_b.length());
	const TVector offset = p_world_pivot_a - p_world_pivot_b;
	if (!offset.is_finite() || !Math::is_finite(radius_a) || !Math::is_finite(radius_b)) {
		return true;
	}

	const double motion_sq = double(p_relative_linear_motion.length_squared());
	const double projection = double(offset.dot(p_relative_linear_motion));
	if (!Math::is_finite(motion_sq) || !Math::is_finite(projection)) {
		return true;
	}
	const double fraction = motion_sq > 0.0 ? CLAMP(-projection / motion_sq, 0.0, 1.0) : 0.0;
	const TVector closest = offset + p_relative_linear_motion * real_t(fraction);
	if (!closest.is_finite()) {
		return true;
	}
	const double closest_sq = double(closest.length_squared());
	// Epsilon deliberately expands (never shrinks) each broadphase sphere
	// for rounding error at tangencies and in large-world float builds.
	const double radius_sum = radius_a + radius_b;
	const double slack = (radius_sum + double(offset.length()) +
			double(p_relative_linear_motion.length())) * 1e-6 + 1e-6;
	const double conservative_radius = radius_sum + slack;
	if (!Math::is_finite(closest_sq) || !Math::is_finite(conservative_radius)) {
		return true;
	}
	return closest_sq <= conservative_radius * conservative_radius;
}
