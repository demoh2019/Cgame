/**************************************************************************/
/*  physics_xpbd_tension_hardening.h                                      */
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

#include "core/math/vector3.h"

// Phenomenological nonlinear tension-hardening XPBD material.
//
// For predicted tensile strain e = max(0, length/rest_length - 1):
// alpha_eff = alpha / (1 + h * max(0, e - yield)^2).
//
// Not a finite-element hyperelastic stress law. This model stiffens links
// in extension only. The caller MUST calculate compliance ONCE per link
// per simulation step, before solver iterations. Retaining lambda while
// changing alpha within each iteration causes stiffness oscillation.
// Large-scale arithmetic uses double to avoid float32 overflow.
// No allocation and no mutation of output on invalid input.
_FORCE_INLINE_ static bool physics_xpbd_tension_hardening_alpha(
		const Vector3 &p_a, const Vector3 &p_b,
		real_t p_rest_length, real_t p_base_alpha,
		real_t p_yield_strain, real_t p_hardening,
		real_t &r_alpha) {
	if (!p_a.is_finite() || !p_b.is_finite() ||
			!Math::is_finite(p_rest_length) || !Math::is_finite(p_base_alpha) ||
			!Math::is_finite(p_yield_strain) || !Math::is_finite(p_hardening) ||
			p_rest_length < real_t(0.0) || p_base_alpha < real_t(0.0) ||
			p_yield_strain < real_t(0.0) || p_hardening < real_t(0.0)) {
		return false;
	}

	// A point constraint has no reference length from which to measure
	// strain. Zero hardening skips the expensive geometry path.
	if (p_rest_length == real_t(0.0) || p_hardening == real_t(0.0) ||
			p_base_alpha == real_t(0.0)) {
		r_alpha = p_base_alpha;
		return true;
	}

	const double dx = double(p_b.x) - double(p_a.x);
	const double dy = double(p_b.y) - double(p_a.y);
	const double dz = double(p_b.z) - double(p_a.z);
	const double len_sq = dx * dx + dy * dy + dz * dz;
	if (!(len_sq >= 0.0) || !Math::is_finite(len_sq)) {
		return false;
	}
	const double length = Math::sqrt(len_sq);
	const double excess = (length - double(p_rest_length)) / double(p_rest_length) - double(p_yield_strain);
	if (!Math::is_finite(excess)) {
		return false;
	}
	if (excess <= 0.0) {
		r_alpha = p_base_alpha;
		return true;
	}

	// Prevent vanishing compliance from extreme inputs; clamp stiffness
	// multiplier to 1e6 relative to the baseline material.
	const double hardening = double(p_hardening) * excess * excess;
	const double multiplier = Math::is_finite(hardening) ? MIN(hardening, 1e6) : 1e6;
	const real_t next_alpha = real_t(double(p_base_alpha) / (1.0 + multiplier));
	if (!Math::is_finite(next_alpha) || next_alpha < real_t(0.0)) {
		return false;
	}
	r_alpha = next_alpha;
	return true;
}
