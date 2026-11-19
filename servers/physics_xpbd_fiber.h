/**************************************************************************/
/*  physics_xpbd_fiber.h                                                  */
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

#include "core/math/vector3.h"

#include <limits>

// XPBD compliance for a structural link of a woven, anisotropic soft mesh.
// The fiber axis is in the original mesh's local (source) coordinates.
// A link aligned with the axis uses p_fiber_ratio * p_base_alpha; a link
// perpendicular to it uses p_base_alpha. Intermediate directions blend
// quadratically (the squared cosine of the rest-direction angle).
//
// This only modifies the *compliance*; the distance constraint, inverse
// masses, rest length, and per-step Lagrange multiplier are unchanged.
// Input validation falls back to isotropic compliance and the calculation
// is scaled to avoid squaring huge rest-coordinate differences.
_FORCE_INLINE_ real_t physics_xpbd_fiber_alpha(const Vector3 &p_rest_a,
		const Vector3 &p_rest_b, real_t p_base_alpha, int p_axis,
		real_t p_fiber_ratio) {
	if (!Math::is_finite(p_base_alpha) || p_base_alpha < real_t(0.0)) {
		return real_t(0.0);
	}
	if (p_base_alpha == real_t(0.0) || p_fiber_ratio == real_t(1.0) ||
			p_axis < 0 || p_axis > 2 || !Math::is_finite(p_fiber_ratio) ||
			!(p_fiber_ratio > real_t(0.0)) ||
			!p_rest_a.is_finite() || !p_rest_b.is_finite()) {
		return p_base_alpha;
	}

	const double dx = double(p_rest_b.x) - double(p_rest_a.x);
	const double dy = double(p_rest_b.y) - double(p_rest_a.y);
	const double dz = double(p_rest_b.z) - double(p_rest_a.z);
	const double scale = MAX(MAX(Math::abs(dx), Math::abs(dy)), Math::abs(dz));
	if (!(scale > 0.0) || !Math::is_finite(scale)) {
		return p_base_alpha;
	}

	const double x = dx / scale;
	const double y = dy / scale;
	const double z = dz / scale;
	const double denominator = x * x + y * y + z * z;
	const double aligned = p_axis == 0 ? x : p_axis == 1 ? y : z;
	const double cosine_squared = aligned * aligned / denominator;
	const double multiplier = 1.0 + (double(p_fiber_ratio) - 1.0) * cosine_squared;
	const double result = double(p_base_alpha) * multiplier;
	if (!Math::is_finite(result)) {
		return std::numeric_limits<real_t>::max();
	}
	return real_t(MIN(result, double(std::numeric_limits<real_t>::max())));
}
