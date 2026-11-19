/**************************************************************************/
/*  physics_ccd_capsule_toi.h                                             */
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

// First entry of a moving point into a stationary Y-axis capsule, with
// centerline endpoints (0, +/-p_half_segment, 0). Caller expands p_radius
// by the moving sphere radius (Minkowski sum) and expresses its relative
// motion in the capsule's local coordinates. This gives exact linear
// circle/capsule and sphere/capsule time of impact without support rays.
//
// All intermediates use double, including lengths and the segment fraction.
_FORCE_INLINE_ bool physics_ccd_capsule_toi(double p_x, double p_y, double p_z,
		double p_dx, double p_dy, double p_dz, double p_radius, double p_half_segment, double &r_fraction) {
	if (!(p_radius > 0.0 && p_half_segment >= 0.0)) {
		return false;
	}
	const double a = p_dx * p_dx + p_dy * p_dy + p_dz * p_dz;
	if (!(a > 0.0)) {
		return false;
	}
	const double radius_squared = p_radius * p_radius;
	const double nearest_y = CLAMP(p_y, -p_half_segment, p_half_segment);
	const double offset_y = p_y - nearest_y;
	if (!(p_x * p_x + offset_y * offset_y + p_z * p_z > radius_squared)) {
		return false; // Already overlapping or touching at the start.
	}

	double best = double(Math::INF);
	// Entry through the straight cylinder.
	const double lateral_squared = p_dx * p_dx + p_dz * p_dz;
	if (lateral_squared > 0.0) {
		const double projection = -(p_x * p_dx + p_z * p_dz) / lateral_squared;
		if (projection >= 0.0) {
			const double closest_x = p_x + p_dx * projection;
			const double closest_z = p_z + p_dz * projection;
			const double gap = radius_squared - (closest_x * closest_x + closest_z * closest_z);
			if (gap >= 0.0) {
				const double t = projection - Math::sqrt(gap / lateral_squared);
				const double y = p_y + p_dy * t;
				if (t >= 0.0 && t <= 1.0 && y >= -p_half_segment && y <= p_half_segment) {
					best = t;
				}
			}
		}
	}

	// Entry through either hemispherical end cap, restricted to its
	// outward half. Closest approach avoids the unstable quadratic root.
	for (int i = 0; i < 2; ++i) {
		const double cap_y = (i == 0) ? -p_half_segment : p_half_segment;
		const double relative_y = p_y - cap_y;
		const double projection = -(p_x * p_dx + relative_y * p_dy + p_z * p_dz) / a;
		if (projection < 0.0) {
			continue;
		}
		const double closest_x = p_x + p_dx * projection;
		const double closest_y = relative_y + p_dy * projection;
		const double closest_z = p_z + p_dz * projection;
		const double gap = radius_squared -
				(closest_x * closest_x + closest_y * closest_y + closest_z * closest_z);
		if (gap < 0.0) {
			continue;
		}
		const double offset = Math::sqrt(gap / a);
		const double t = projection - offset;
		if (t < 0.0 || t > 1.0 || t >= best) {
			continue;
		}
		const double y = closest_y - p_dy * offset;
		if ((i == 0 && y > 0.0) || (i == 1 && y < 0.0)) {
			continue;
		}
		best = t;
	}

	if (!(best >= 0.0 && best <= 1.0)) {
		return false;
	}
	r_fraction = best;
	return true;
}

_FORCE_INLINE_ bool physics_ccd_capsule_toi(const Vector2 &p_local_center, const Vector2 &p_local_motion,
		double p_radius, double p_half_segment, double &r_fraction) {
	return physics_ccd_capsule_toi(double(p_local_center.x), double(p_local_center.y), 0.0,
			double(p_local_motion.x), double(p_local_motion.y), 0.0,
			p_radius, p_half_segment, r_fraction);
}

_FORCE_INLINE_ bool physics_ccd_capsule_toi(const Vector3 &p_local_center, const Vector3 &p_local_motion,
		double p_radius, double p_half_segment, double &r_fraction) {
	return physics_ccd_capsule_toi(double(p_local_center.x), double(p_local_center.y), double(p_local_center.z),
			double(p_local_motion.x), double(p_local_motion.y), double(p_local_motion.z),
			p_radius, p_half_segment, r_fraction);
}
