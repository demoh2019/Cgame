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

// Conservative rejection for linear CCD casts: if the union of an initial
// shape's bounds and its translated bounds misses the target, a linear sweep
// cannot hit it. Touching bounds are intentionally treated as potentially
// colliding. Nonfinite/invalid inputs cannot be safely rejected.
//
// Only use this fast path when both shapes have fixed orientations during
// the sweep and their local bounds conservatively cover their geometry.
_FORCE_INLINE_ bool physics_ccd_swept_bounds_may_overlap(const Rect2 &p_moving, const Rect2 &p_target, const Vector2 &p_relative_motion) {
	if (!p_moving.is_finite() || !p_target.is_finite() || !p_relative_motion.is_finite() ||
			p_moving.size.x < 0.0 || p_moving.size.y < 0.0 ||
			p_target.size.x < 0.0 || p_target.size.y < 0.0) {
		return true;
	}
	const Rect2 translated(p_moving.position + p_relative_motion, p_moving.size);
	if (!translated.is_finite()) {
		return true;
	}
	const Rect2 swept = p_moving.merge(translated);
	const Vector2 moving_end = swept.get_end();
	const Vector2 target_end = p_target.get_end();
	if (!swept.is_finite() || !moving_end.is_finite() || !target_end.is_finite()) {
		return true;
	}
	return swept.position.x <= target_end.x && moving_end.x >= p_target.position.x &&
			swept.position.y <= target_end.y && moving_end.y >= p_target.position.y;
}

_FORCE_INLINE_ bool physics_ccd_swept_bounds_may_overlap(const AABB &p_moving, const AABB &p_target, const Vector3 &p_relative_motion) {
	if (!p_moving.is_finite() || !p_target.is_finite() || !p_relative_motion.is_finite() ||
			p_moving.size.x < 0.0 || p_moving.size.y < 0.0 || p_moving.size.z < 0.0 ||
			p_target.size.x < 0.0 || p_target.size.y < 0.0 || p_target.size.z < 0.0) {
		return true;
	}
	const AABB translated(p_moving.position + p_relative_motion, p_moving.size);
	if (!translated.is_finite()) {
		return true;
	}
	const AABB swept = p_moving.merge(translated);
	const Vector3 moving_end = swept.get_end();
	const Vector3 target_end = p_target.get_end();
	if (!swept.is_finite() || !moving_end.is_finite() || !target_end.is_finite()) {
		return true;
	}
	return swept.position.x <= target_end.x && moving_end.x >= p_target.position.x &&
			swept.position.y <= target_end.y && moving_end.y >= p_target.position.y &&
			swept.position.z <= target_end.z && moving_end.z >= p_target.position.z;
}
