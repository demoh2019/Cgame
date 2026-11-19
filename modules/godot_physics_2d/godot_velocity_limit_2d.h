/**************************************************************************/
/*  godot_velocity_limit_2d.h                                             */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
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

#include "core/math/vector2.h"

// Optional Box2D-style speed limit. Compute the length using scaled components:
// squaring an extreme finite velocity directly can overflow in float builds.
// Do not hide invalid user-provided velocities; keep the existing error behavior.
_FORCE_INLINE_ Vector2 godot_physics_2d_limit_linear_velocity(const Vector2 &p_velocity, real_t p_limit) {
	if (!(p_limit > 0.0) || !Math::is_finite(p_limit) || !p_velocity.is_finite()) {
		return p_velocity;
	}

	const real_t largest_component = MAX(Math::abs(p_velocity.x), Math::abs(p_velocity.y));
	if (largest_component <= p_limit * real_t(0.7071067811865475)) {
		// Both squared components together cannot exceed the speed limit.
		return p_velocity;
	}

	if (largest_component <= p_limit) {
		const Vector2 scaled = p_velocity / p_limit;
		const real_t length_squared = scaled.length_squared();
		return length_squared > 1.0 ? p_velocity / Math::sqrt(length_squared) : p_velocity;
	}

	const Vector2 scaled = p_velocity / largest_component;
	return scaled * (p_limit / Math::sqrt(scaled.length_squared()));
}
