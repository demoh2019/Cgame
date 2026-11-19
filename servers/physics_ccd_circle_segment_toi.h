/**************************************************************************/
/*  physics_ccd_circle_segment_toi.h                                      */
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

#include "servers/physics_ccd_capsule_toi.h"

enum class PhysicsCCDCircleSegmentTOIResult {
	HIT,
	MISS,
	FALLBACK,
};

// A circle moving linearly against an arbitrary world-space segment is
// equivalent to a moving point entering a capsule around that segment.
// Transform to the capsule's axial coordinates in double precision, so no
// segment triangulation, support-ray approximation or allocations are needed.
//
// HIT/MISS apply to initially separated finite geometry. Initial overlap
// and nonfinite inputs request the regular contact solver via FALLBACK.
_FORCE_INLINE_ PhysicsCCDCircleSegmentTOIResult physics_ccd_circle_segment_toi(
		const Vector2 &p_circle_center, const Vector2 &p_relative_motion,
		const Vector2 &p_segment_a, const Vector2 &p_segment_b,
		double p_circle_radius, double &r_fraction) {
	if (!(p_circle_radius > 0.0) || !Math::is_finite(p_circle_radius)) {
		return PhysicsCCDCircleSegmentTOIResult::FALLBACK;
	}

	const double cx = double(p_circle_center.x);
	const double cy = double(p_circle_center.y);
	const double mx = double(p_relative_motion.x);
	const double my = double(p_relative_motion.y);
	const double ax = double(p_segment_a.x);
	const double ay = double(p_segment_a.y);
	const double bx = double(p_segment_b.x);
	const double by = double(p_segment_b.y);
	if (!Math::is_finite(cx) || !Math::is_finite(cy) ||
			!Math::is_finite(mx) || !Math::is_finite(my) ||
			!Math::is_finite(ax) || !Math::is_finite(ay) ||
			!Math::is_finite(bx) || !Math::is_finite(by)) {
		return PhysicsCCDCircleSegmentTOIResult::FALLBACK;
	}

	const double sx = bx - ax;
	const double sy = by - ay;
	const double length_squared = sx * sx + sy * sy;
	const double radius_squared = p_circle_radius * p_circle_radius;
	if (!Math::is_finite(length_squared) || !Math::is_finite(radius_squared)) {
		return PhysicsCCDCircleSegmentTOIResult::FALLBACK;
	}

	// Preserve existing manifold handling when the circle is already
	// touching the segment. It must not be misclassified as a CCD miss.
	const double start_x = cx - ax;
	const double start_y = cy - ay;
	const double along = length_squared > 0.0 ? CLAMP((start_x * sx + start_y * sy) / length_squared, 0.0, 1.0) : 0.0;
	const double nearest_x = start_x - along * sx;
	const double nearest_y = start_y - along * sy;
	if (!Math::is_finite(nearest_x) || !Math::is_finite(nearest_y)) {
		return PhysicsCCDCircleSegmentTOIResult::FALLBACK;
	}
	if (nearest_x * nearest_x + nearest_y * nearest_y <= radius_squared) {
		return PhysicsCCDCircleSegmentTOIResult::FALLBACK;
	}
	if (mx == 0.0 && my == 0.0) {
		return PhysicsCCDCircleSegmentTOIResult::MISS;
	}

	// Local Y follows the segment axis, local X is perpendicular. For a
	// zero-length segment, the capsule degenerates into a circle.
	double local_x = start_x;
	double local_y = start_y;
	double motion_x = mx;
	double motion_y = my;
	double half_segment = 0.0;
	if (length_squared > 0.0) {
		const double length = Math::sqrt(length_squared);
		const double ux = sx / length;
		const double uy = sy / length;
		const double center_x = 0.5 * (ax + bx);
		const double center_y = 0.5 * (ay + by);
		const double dx = cx - center_x;
		const double dy = cy - center_y;
		local_x = dx * uy - dy * ux;
		local_y = dx * ux + dy * uy;
		motion_x = mx * uy - my * ux;
		motion_y = mx * ux + my * uy;
		half_segment = 0.5 * length;
	}

	if (!Math::is_finite(local_x) || !Math::is_finite(local_y) ||
			!Math::is_finite(motion_x) || !Math::is_finite(motion_y)) {
		return PhysicsCCDCircleSegmentTOIResult::FALLBACK;
	}
	return physics_ccd_capsule_toi(local_x, local_y, 0.0,
			motion_x, motion_y, 0.0, p_circle_radius, half_segment, r_fraction) ?
			PhysicsCCDCircleSegmentTOIResult::HIT : PhysicsCCDCircleSegmentTOIResult::MISS;
}
