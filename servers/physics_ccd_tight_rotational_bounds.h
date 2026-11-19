/**************************************************************************/
/*  physics_ccd_tight_rotational_bounds.h                                 */
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

#include "core/math/aabb.h"
#include "core/math/rect2.h"
#include "servers/physics_ccd_rotational_bounds.h"

// Broadphase *candidate* envelope, not an angular time-of-impact test.
// A rigid rotation of a point about a fixed pivot follows
//   coordinate(t) = center + cos_coefficient * cos(t)
//                          + sin_coefficient * sin(t).
// On a bounded angular interval, extrema occur at the ends or when the
// derivative vanishes. Evaluating the extremum analytically gives a much
// smaller conservative envelope than growing every AABB axis by the maximum
// rotation chord. We bound every corner of the starting world-space AABB;
// this contains the actual collision shape, including compound offsets.
// Translating the body linearly adds the Minkowski sum with [0, motion].

_FORCE_INLINE_ static bool godot_physics_ccd_angle_in_sweep(real_t p_critical_angle, real_t p_start, real_t p_span) {
	const real_t full_turn = real_t(Math::TAU);
	// A tolerance around interval boundaries can only enlarge the envelope.
	const real_t distance = Math::fposmod(p_critical_angle - p_start, full_turn);
	return distance <= p_span + real_t(0.000001) || distance >= full_turn - real_t(0.000001);
}

_FORCE_INLINE_ static void godot_physics_ccd_arc_component(real_t p_center, real_t p_cos_coefficient,
		real_t p_sin_coefficient, real_t p_cos_end, real_t p_sin_end,
		real_t p_start, real_t p_span, real_t &r_min, real_t &r_max) {
	const real_t start_value = p_center + p_cos_coefficient;
	const real_t end_value = p_center + p_cos_coefficient * p_cos_end + p_sin_coefficient * p_sin_end;
	r_min = MIN(start_value, end_value);
	r_max = MAX(start_value, end_value);

	const real_t amplitude = Vector2(p_cos_coefficient, p_sin_coefficient).length();
	if (amplitude == real_t(0.0)) {
		return;
	}
	const real_t full_turn = real_t(Math::TAU);
	if (p_span >= full_turn) {
		r_min = MIN(r_min, p_center - amplitude);
		r_max = MAX(r_max, p_center + amplitude);
		return;
	}
	const real_t peak = Math::atan2(p_sin_coefficient, p_cos_coefficient);
	if (godot_physics_ccd_angle_in_sweep(peak, p_start, p_span)) {
		r_max = MAX(r_max, p_center + amplitude);
	}
	if (godot_physics_ccd_angle_in_sweep(peak + real_t(Math::PI), p_start, p_span)) {
		r_min = MIN(r_min, p_center - amplitude);
	}
}

_FORCE_INLINE_ static Rect2 godot_physics_ccd_tight_rotational_bounds(
		const Rect2 &p_bounds, const Vector2 &p_pivot, real_t p_angle, const Vector2 &p_motion) {
	Rect2 swept = p_bounds.merge(Rect2(p_bounds.position + p_motion, p_bounds.size));
	if (p_angle == real_t(0.0) || !p_bounds.is_finite() || !p_pivot.is_finite() ||
			!p_motion.is_finite() || !Math::is_finite(p_angle)) {
		return swept;
	}

	const real_t cos_end = Math::cos(p_angle);
	const real_t sin_end = Math::sin(p_angle);
	const real_t start = MIN(real_t(0.0), p_angle);
	const real_t span = Math::abs(p_angle);
	Vector2 min_bound = p_bounds.position;
	Vector2 max_bound = p_bounds.get_end();
	for (int corner = 0; corner < 4; corner++) {
		const Vector2 position((corner & 1) ? p_bounds.position.x : p_bounds.get_end().x,
				(corner & 2) ? p_bounds.position.y : p_bounds.get_end().y);
		const Vector2 delta = position - p_pivot;
		real_t low_x, high_x, low_y, high_y;
		godot_physics_ccd_arc_component(p_pivot.x, delta.x, -delta.y, cos_end, sin_end, start, span, low_x, high_x);
		godot_physics_ccd_arc_component(p_pivot.y, delta.y, delta.x, cos_end, sin_end, start, span, low_y, high_y);
		min_bound.x = MIN(min_bound.x, low_x);
		min_bound.y = MIN(min_bound.y, low_y);
		max_bound.x = MAX(max_bound.x, high_x);
		max_bound.y = MAX(max_bound.y, high_y);
	}
	// The actual translation happens gradually; the Cartesian product of
	// rotation envelope and translation segment always contains that path.
	min_bound.x += MIN(real_t(0.0), p_motion.x);
	min_bound.y += MIN(real_t(0.0), p_motion.y);
	max_bound.x += MAX(real_t(0.0), p_motion.x);
	max_bound.y += MAX(real_t(0.0), p_motion.y);
	if (!min_bound.is_finite() || !max_bound.is_finite()) {
		// An invalid calculation must not cull any previously eligible pair.
		const real_t factor = godot_physics_ccd_rotational_factor(p_angle);
		return swept.grow(godot_physics_ccd_rotational_padding(p_bounds, p_pivot, factor));
	}

	const real_t precision = real_t(8.0) * CMP_EPSILON * MAX(real_t(1.0),
			MAX(min_bound.abs().max_axis_index() == 0 ? Math::abs(min_bound.x) : Math::abs(min_bound.y),
					max_bound.abs().max_axis_index() == 0 ? Math::abs(max_bound.x) : Math::abs(max_bound.y)));
	return Rect2(min_bound, max_bound - min_bound).grow(precision);
}

_FORCE_INLINE_ static AABB godot_physics_ccd_tight_rotational_bounds(
		const AABB &p_bounds, const Vector3 &p_pivot, const Vector3 &p_angular_step, const Vector3 &p_motion) {
	AABB swept = p_bounds;
	swept.merge_with(AABB(p_bounds.position + p_motion, p_bounds.size));
	if (!p_bounds.is_finite() || !p_pivot.is_finite() || !p_angular_step.is_finite() || !p_motion.is_finite()) {
		return swept;
	}
	const real_t angle = p_angular_step.length();
	if (!(angle > real_t(0.0)) || !Math::is_finite(angle)) {
		return swept;
	}
	const Vector3 axis = p_angular_step / angle;
	const real_t cos_end = Math::cos(angle);
	const real_t sin_end = Math::sin(angle);
	Vector3 min_bound = p_bounds.position;
	Vector3 max_bound = p_bounds.get_end();
	for (int corner = 0; corner < 8; corner++) {
		const Vector3 position((corner & 1) ? p_bounds.position.x : p_bounds.get_end().x,
				(corner & 2) ? p_bounds.position.y : p_bounds.get_end().y,
				(corner & 4) ? p_bounds.position.z : p_bounds.get_end().z);
		const Vector3 delta = position - p_pivot;
		const Vector3 parallel = axis * axis.dot(delta);
		const Vector3 perpendicular = delta - parallel;
		const Vector3 sine_coefficient = axis.cross(delta);
		const Vector3 center = p_pivot + parallel;
		for (int component = 0; component < 3; component++) {
			real_t low, high;
			godot_physics_ccd_arc_component(center[component], perpendicular[component],
					sine_coefficient[component], cos_end, sin_end, real_t(0.0), angle, low, high);
			min_bound[component] = MIN(min_bound[component], low);
			max_bound[component] = MAX(max_bound[component], high);
		}
	}
	for (int component = 0; component < 3; component++) {
		min_bound[component] += MIN(real_t(0.0), p_motion[component]);
		max_bound[component] += MAX(real_t(0.0), p_motion[component]);
	}
	if (!min_bound.is_finite() || !max_bound.is_finite()) {
		const real_t factor = godot_physics_ccd_rotational_factor(angle);
		swept.grow_by(godot_physics_ccd_rotational_padding(p_bounds, p_pivot, factor));
		return swept;
	}
	const real_t precision = real_t(8.0) * CMP_EPSILON * MAX(real_t(1.0),
			MAX(min_bound.abs().max_axis_index() == 0 ? Math::abs(min_bound.x) : (min_bound.abs().max_axis_index() == 1 ? Math::abs(min_bound.y) : Math::abs(min_bound.z)),
					max_bound.abs().max_axis_index() == 0 ? Math::abs(max_bound.x) : (max_bound.abs().max_axis_index() == 1 ? Math::abs(max_bound.y) : Math::abs(max_bound.z))));
	AABB tight(min_bound, max_bound - min_bound);
	tight.grow_by(precision);
	return tight;
}
