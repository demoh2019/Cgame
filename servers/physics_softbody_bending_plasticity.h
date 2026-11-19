/**************************************************************************/
/*  physics_softbody_bending_plasticity.h                                 */
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
/* MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/math/math_funcs.h"

// Viscoplastic creasing for XPBD cloth hinges. Angles are signed radians.
// The yield angle is the maximum recoverable bend from the current rest
// angle. Beyond yield, the rest angle creeps toward the nearest point on
// the elastic interval, along the shortest arc on the circle.
// p_creep_fraction = 1 - exp(-rate * dt), evaluated once per physics step.
// No heap allocation, and a failed update never changes the rest state.
_FORCE_INLINE_ static bool physics_softbody_creep_rest_dihedral(
		real_t p_current_angle, real_t p_yield_angle,
		double p_creep_fraction, real_t &r_rest_angle) {
	if (!Math::is_finite(p_current_angle) || !Math::is_finite(r_rest_angle) ||
			!Math::is_finite(p_yield_angle) || !Math::is_finite(p_creep_fraction) ||
			p_yield_angle < real_t(0.0) || double(p_yield_angle) > Math_PI ||
			!(p_creep_fraction > 0.0 && p_creep_fraction <= 1.0)) {
		return false;
	}

	// atan2(sin, cos) avoids a discontinuity at +/-PI, including when
	// the rest mesh already contains a fold across the branch cut.
	const double difference = double(p_current_angle) - double(r_rest_angle);
	const double delta = Math::atan2(Math::sin(difference), Math::cos(difference));
	const double yield = double(p_yield_angle);
	if (!(Math::abs(delta) > yield)) {
		return false;
	}

	const double excess = delta > 0.0 ? delta - yield : delta + yield;
	const double next_angle = double(r_rest_angle) + excess * p_creep_fraction;
	const double wrapped = Math::atan2(Math::sin(next_angle), Math::cos(next_angle));
	if (!Math::is_finite(wrapped)) {
		return false;
	}
	const real_t next_rest_angle = real_t(wrapped);
	if (!Math::is_finite(next_rest_angle) || next_rest_angle == r_rest_angle) {
		return false;
	}
	r_rest_angle = next_rest_angle;
	return true;
}
