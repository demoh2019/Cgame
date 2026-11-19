/**************************************************************************/
/*  physics_speculative_sphere_contact.h                                  */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/math/vector2.h"
#include "core/math/vector3.h"

// Return an unpenetrated contact for an approaching pair of actual circles
// or spheres, not the inflated points from a shape-margin SAT query.
// Normals point from A to B; depth = dot(pointA - pointB, normal) is negative.
// This is conservative in scope: broadphase must already own the pair,
// both shapes must retain spherical geometry, and neither may rotate.
template <typename Vector>
_FORCE_INLINE_ bool physics_speculative_sphere_contact(
		const Vector &p_center_a, real_t p_radius_a, const Vector &p_center_b, real_t p_radius_b,
		const Vector &p_velocity_a, const Vector &p_velocity_b,
		real_t p_step, real_t p_max_gap,
		Vector &r_point_a, Vector &r_point_b, Vector &r_normal) {
	if (!p_center_a.is_finite() || !p_center_b.is_finite() ||
			!p_velocity_a.is_finite() || !p_velocity_b.is_finite() ||
			!Math::is_finite(p_radius_a) || !Math::is_finite(p_radius_b) ||
			!Math::is_finite(p_step) || !Math::is_finite(p_max_gap) ||
			p_radius_a <= 0.0 || p_radius_b <= 0.0 || p_step <= 0.0 || p_max_gap <= 0.0) {
		return false;
	}

	const Vector center_delta = p_center_b - p_center_a;
	const real_t distance_squared = center_delta.length_squared();
	if (!Math::is_finite(distance_squared) || distance_squared <= 0.0) {
		return false;
	}
	const real_t distance = Math::sqrt(distance_squared);
	const real_t gap = distance - (p_radius_a + p_radius_b);
	if (!(gap > 0.0 && gap <= p_max_gap)) {
		return false;
	}
	const Vector normal = center_delta / distance;
	const real_t closing_speed = -(p_velocity_b - p_velocity_a).dot(normal);
	// A speculative constraint is only needed when this pair would reach
	// its surface in the current step. This excludes all separating and
	// stationary near-misses without allocating contact storage.
	if (!Math::is_finite(closing_speed) || !(closing_speed > 0.0 && closing_speed * p_step >= gap)) {
		return false;
	}
	const Vector point_a = p_center_a + normal * p_radius_a;
	const Vector point_b = p_center_b - normal * p_radius_b;
	if (!point_a.is_finite() || !point_b.is_finite()) {
		return false;
	}
	r_point_a = point_a;
	r_point_b = point_b;
	r_normal = normal;
	return true;
}
