/**************************************************************************/
/*  physics_contact_angular_friction.h                                    */
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

// A single bounded pure-angular correction for a loaded contact manifold,
// inspired by Bullet's rolling/spinning friction. For a unit torque axis,
// inv_effective_inertia = axis dot (I_A^-1 + I_B^-1) axis.
// Torque limit has angular-impulse units: friction * normal impulse * radius.
// This is applied once per physics step (not every solver iteration) so no
// per-contact accumulator or extra per-body allocation is necessary.
struct GodotPhysicsContactAngularFriction {
	static _FORCE_INLINE_ real_t clamped_impulse(real_t p_relative_angular_velocity, real_t p_inv_effective_inertia, real_t p_normal_impulse, real_t p_coefficient, real_t p_contact_radius) {
		if (!(p_inv_effective_inertia > 0.0) || !(p_normal_impulse > 0.0) ||
				!(p_coefficient > 0.0) || !(p_contact_radius > 0.0) ||
				!Math::is_finite(p_relative_angular_velocity) ||
				!Math::is_finite(p_inv_effective_inertia) || !Math::is_finite(p_normal_impulse) ||
				!Math::is_finite(p_coefficient) || !Math::is_finite(p_contact_radius)) {
			return 0.0;
		}

		const real_t max_impulse = p_coefficient * p_normal_impulse * p_contact_radius;
		if (!(max_impulse > 0.0) || !Math::is_finite(max_impulse)) {
			return 0.0;
		}

		const real_t wanted_impulse = -p_relative_angular_velocity / p_inv_effective_inertia;
		if (!Math::is_finite(wanted_impulse)) {
			// Never introduce an unbounded torque on malformed contact data.
			return 0.0;
		}
		return CLAMP(wanted_impulse, -max_impulse, max_impulse);
	}
};
