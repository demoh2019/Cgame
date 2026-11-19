/**************************************************************************/
/*  physics_ccd_capsule_segment_toi.h                                     */
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

// Linear capsule/segment shape cast, including both rounded capsule ends
// and both finite segment endpoints. A capsule is a line segment swept by
// its radius; a zero-radius segment is the same Minkowski construction.
// Reuse the exact finite-segment distance TOI for arbitrary axis angles.
//
// The capsule and segment are in world coordinates. The relative motion
// displaces the capsule versus the fixed segment over one step. HIT and
// MISS are definitive when their geometry is valid and initially separated;
// FALLBACK requests the legacy contact path for initial overlap, invalid
// transforms or other numerical uncertainty. No heap allocations.
_FORCE_INLINE_ PhysicsCCDCapsulePairTOIResult physics_ccd_capsule_segment_toi(
		const Vector2 &p_capsule_center, const Vector2 &p_relative_motion,
		const Vector2 &p_capsule_axis, double p_capsule_half_segment,
		double p_capsule_radius, const Vector2 &p_segment_a,
		const Vector2 &p_segment_b, double &r_fraction) {
	if (!(p_capsule_radius > 0.0 && p_capsule_half_segment >= 0.0) ||
			!Math::is_finite(p_capsule_radius) || !Math::is_finite(p_capsule_half_segment)) {
		return PhysicsCCDCapsulePairTOIResult::FALLBACK;
	}

	const double ax = double(p_segment_a.x);
	const double ay = double(p_segment_a.y);
	const double bx = double(p_segment_b.x);
	const double by = double(p_segment_b.y);
	const double sx = bx - ax;
	const double sy = by - ay;
	const double length_squared = sx * sx + sy * sy;
	if (!Math::is_finite(length_squared) || !Math::is_finite(ax) ||
			!Math::is_finite(ay) || !Math::is_finite(bx) || !Math::is_finite(by)) {
		return PhysicsCCDCapsulePairTOIResult::FALLBACK;
	}

	const double half_segment = Math::sqrt(length_squared) * 0.5;
	const Vector2 segment_axis = half_segment > 0.0 ?
			Vector2(real_t(sx / (2.0 * half_segment)), real_t(sy / (2.0 * half_segment))) :
			Vector2(0.0, 1.0);
	const Vector2 segment_center = Vector2(real_t(ax + 0.5 * sx), real_t(ay + 0.5 * sy));
	if (!segment_center.is_finite() || !segment_axis.is_finite()) {
		return PhysicsCCDCapsulePairTOIResult::FALLBACK;
	}

	return physics_ccd_capsule_pair_toi(
			p_capsule_center - segment_center, p_relative_motion,
			p_capsule_axis, segment_axis,
			p_capsule_half_segment, half_segment, p_capsule_radius, r_fraction);
}
