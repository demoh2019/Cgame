/**************************************************************************/
/*  physics_uniform_fluid.h                                               */
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

// Uniform, fully submerged fluid approximation inspired by Jolt's
// ApplyBuoyancyImpulse. The quadratic drag equation is
//     d(v - flow)/dt = -coefficient * |v - flow| * (v - flow).
// Its constant-flow exact solution avoids explicit Euler overshoot:
//     v(t+dt) = flow + (v(t)-flow) / (1 + coefficient * dt * |v(t)-flow|).
// The coefficient is already divided by mass (for linear drag) or inertia
// (for angular drag); e.g. 0.5 * density * Cd * projected_area / body_mass.
// This is intentionally a uniform-medium model, not a partial-submersion
// test. The opt-in defaults are all zero, preserving legacy behavior.

_FORCE_INLINE_ static Vector2 godot_physics_fluid_linear_drag(const Vector2 &p_velocity, const Vector2 &p_flow, real_t p_coefficient, real_t p_step) {
	if (p_coefficient <= real_t(0.0) || p_step <= real_t(0.0)) {
		return p_velocity;
	}
	const Vector2 relative = p_velocity - p_flow;
	const real_t speed_squared = relative.length_squared();
	if (speed_squared <= real_t(0.0)) {
		return p_velocity;
	}
	return p_flow + relative / (real_t(1.0) + p_coefficient * p_step * Math::sqrt(speed_squared));
}

_FORCE_INLINE_ static Vector3 godot_physics_fluid_linear_drag(const Vector3 &p_velocity, const Vector3 &p_flow, real_t p_coefficient, real_t p_step) {
	if (p_coefficient <= real_t(0.0) || p_step <= real_t(0.0)) {
		return p_velocity;
	}
	const Vector3 relative = p_velocity - p_flow;
	const real_t speed_squared = relative.length_squared();
	if (speed_squared <= real_t(0.0)) {
		return p_velocity;
	}
	return p_flow + relative / (real_t(1.0) + p_coefficient * p_step * Math::sqrt(speed_squared));
}

_FORCE_INLINE_ static real_t godot_physics_fluid_angular_drag(real_t p_angular_velocity, real_t p_coefficient, real_t p_step) {
	if (p_coefficient <= real_t(0.0) || p_step <= real_t(0.0)) {
		return p_angular_velocity;
	}
	return p_angular_velocity / (real_t(1.0) + p_coefficient * p_step * Math::abs(p_angular_velocity));
}

_FORCE_INLINE_ static Vector3 godot_physics_fluid_angular_drag(const Vector3 &p_angular_velocity, real_t p_coefficient, real_t p_step) {
	if (p_coefficient <= real_t(0.0) || p_step <= real_t(0.0)) {
		return p_angular_velocity;
	}
	const real_t speed_squared = p_angular_velocity.length_squared();
	if (speed_squared <= real_t(0.0)) {
		return p_angular_velocity;
	}
	return p_angular_velocity / (real_t(1.0) + p_coefficient * p_step * Math::sqrt(speed_squared));
}
