/**************************************************************************/
/*  physics_ccd_swept_bounds.h                                            */
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

#include "core/math/aabb.h"
#include "core/math/rect2.h"

#include <limits>

// Conservative swept-AABB rejection for linearly moving, fixed-orientation
// shapes. A moving box intersects a target only when their time intervals
// overlap on EVERY axis. Touches and unknown arithmetic stay eligible.
// World-boundary and rotating shapes must bypass this prefilter.

// Use slab time intervals rather than the union of start/end AABBs.
// A diagonal trajectory can miss an obstacle even when the union overlaps.
// Expanding the entry/exit fractions slightly avoids rejecting a grazing
// contact due to floating-point rounding. Indeterminate arithmetic keeps
// the original narrowphase path (conservative fallback).
_FORCE_INLINE_ bool physics_ccd_swept_bounds_clip_axis(double p_moving_min, double p_moving_max,
		double p_target_min, double p_target_max, double p_motion,
		double &r_first, double &r_last) {
	if (p_motion == 0.0) {
		return p_moving_min <= p_target_max && p_moving_max >= p_target_min;
	}
	double first = (p_target_min - p_moving_max) / p_motion;
	double last = (p_target_max - p_moving_min) / p_motion;
	if (!Math::is_finite(first) || !Math::is_finite(last)) {
		// Overflowing double math must never produce a false negative.
		return true;
	}
	if (first > last) {
		SWAP(first, last);
	}
	const double tolerance = 32.0 * std::numeric_limits<double>::epsilon() *
			MAX(1.0, MAX(Math::abs(first), Math::abs(last)));
	if (!Math::is_finite(tolerance)) {
		return true;
	}
	r_first = MAX(r_first, first - tolerance);
	r_last = MIN(r_last, last + tolerance);
	return r_first <= r_last;
}

_FORCE_INLINE_ bool physics_ccd_swept_bounds_may_overlap(const Rect2 &p_moving, const Rect2 &p_target, const Vector2 &p_relative_motion, real_t p_backtrack_fraction = 0.0) {
	if (!p_moving.is_finite() || !p_target.is_finite() || !p_relative_motion.is_finite() ||
			!Math::is_finite(p_backtrack_fraction) || p_backtrack_fraction < 0.0 ||
			p_moving.size.x < 0.0 || p_moving.size.y < 0.0 ||
			p_target.size.x < 0.0 || p_target.size.y < 0.0) {
		return true;
	}
	// Mirror the support-ray interval [-backtrack, 1]. Real_t overflow
	// means that the cast cannot be safely culled.
	const Vector2 translated = p_moving.position + p_relative_motion;
	const Vector2 backtracked = p_moving.position - p_relative_motion * p_backtrack_fraction;
	const Vector2 moving_end = p_moving.get_end();
	const Vector2 target_end = p_target.get_end();
	if (!translated.is_finite() || !backtracked.is_finite() ||
			!moving_end.is_finite() || !target_end.is_finite()) {
		return true;
	}

	double first = -double(p_backtrack_fraction);
	double last = 1.0;
	return physics_ccd_swept_bounds_clip_axis(double(p_moving.position.x), double(moving_end.x),
					double(p_target.position.x), double(target_end.x), double(p_relative_motion.x), first, last) &&
			physics_ccd_swept_bounds_clip_axis(double(p_moving.position.y), double(moving_end.y),
					double(p_target.position.y), double(target_end.y), double(p_relative_motion.y), first, last);
}

_FORCE_INLINE_ bool physics_ccd_swept_bounds_may_overlap(const AABB &p_moving, const AABB &p_target, const Vector3 &p_relative_motion, real_t p_backtrack_fraction = 0.0) {
	if (!p_moving.is_finite() || !p_target.is_finite() || !p_relative_motion.is_finite() ||
			!Math::is_finite(p_backtrack_fraction) || p_backtrack_fraction < 0.0 ||
			p_moving.size.x < 0.0 || p_moving.size.y < 0.0 || p_moving.size.z < 0.0 ||
			p_target.size.x < 0.0 || p_target.size.y < 0.0 || p_target.size.z < 0.0) {
		return true;
	}
	const Vector3 translated = p_moving.position + p_relative_motion;
	const Vector3 backtracked = p_moving.position - p_relative_motion * p_backtrack_fraction;
	const Vector3 moving_end = p_moving.get_end();
	const Vector3 target_end = p_target.get_end();
	if (!translated.is_finite() || !backtracked.is_finite() ||
			!moving_end.is_finite() || !target_end.is_finite()) {
		return true;
	}

	double first = -double(p_backtrack_fraction);
	double last = 1.0;
	return physics_ccd_swept_bounds_clip_axis(double(p_moving.position.x), double(moving_end.x),
					double(p_target.position.x), double(target_end.x), double(p_relative_motion.x), first, last) &&
			physics_ccd_swept_bounds_clip_axis(double(p_moving.position.y), double(moving_end.y),
					double(p_target.position.y), double(target_end.y), double(p_relative_motion.y), first, last) &&
			physics_ccd_swept_bounds_clip_axis(double(p_moving.position.z), double(moving_end.z),
					double(p_target.position.z), double(target_end.z), double(p_relative_motion.z), first, last);
}
