/**************************************************************************/
/*  physics_contact_velocity_friction.h                                  */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/math/math_funcs.h"

#include <limits>

// Cheap Stribeck-LIKE nonlinear friction for an impulse-based solver.
//
// The static coefficient is mu_static = mu_dynamic * static_multiplier,
// and the effective coefficient decays with the tangential slip speed:
//
//   mu_eff(v) = mu_dynamic *
//               (1 + (static_multiplier - 1) / (1 + (v / v_s)^2)).
//
// This rational approximation uses only arithmetic (no exp/pow and no
// persistent contact state), unlike a full LuGre bristle friction model.
// v_s is the half-transition speed, in metres/second. The effective
// friction cone always remains within [mu_dynamic, mu_static].
//
// The high-frequency contact solver must use a SINGLE cone of radius
// mu_eff * normal_impulse when this model is active, rather than applying
// a second static multiplier. With v_s == 0 or multiplier == 1 the
// regular Coulomb model is returned exactly.
_FORCE_INLINE_ static real_t godot_physics_stribeck_friction_coefficient(
		real_t p_dynamic_friction, real_t p_static_multiplier,
		real_t p_slip_speed, real_t p_transition_speed) {
	if (!Math::is_finite(p_dynamic_friction) || p_dynamic_friction <= real_t(0.0)) {
		return real_t(0.0);
	}
	if (!Math::is_finite(p_static_multiplier) || p_static_multiplier <= real_t(1.0) ||
			!Math::is_finite(p_slip_speed) || p_slip_speed < real_t(0.0) ||
			!Math::is_finite(p_transition_speed) || p_transition_speed <= real_t(0.0)) {
		return p_dynamic_friction;
	}
	const double ratio = double(p_slip_speed) / double(p_transition_speed);
	// Beyond a million transition speeds, weakening is negligible.
	// Avoid unnecessary squaring at astronomical ratios.
	if (!(ratio < 1e6)) {
		return p_dynamic_friction;
	}

	const double falloff = 1.0 / (1.0 + ratio * ratio);
	const double multiplier = 1.0 + (double(p_static_multiplier) - 1.0) * falloff;
	const double coefficient = double(p_dynamic_friction) * multiplier;
	const double maximum = double(std::numeric_limits<real_t>::max());
	if (!(coefficient < maximum)) {
		return std::numeric_limits<real_t>::max();
	}
	return real_t(coefficient);
}
