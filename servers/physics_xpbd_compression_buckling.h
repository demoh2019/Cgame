/**************************************************************************/
/*  physics_xpbd_compression_buckling.h                                   */
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

// Opt-in nonlinear XPBD compressive softening for thin membranes, cloth and
// ropes. For engineering compression strain e = max(0, 1 - length/rest):
//
//   t = clamp((e - yield) / transition, 0, 1)
//   alpha_eff = alpha * (1 + (softening_ratio - 1) * smoothstep(t))
//
// Compliance alpha = compliance / dt^2; increasing it makes a link easier
// to compress, allowing membrane folding/wrinkling. The model is phenomeno-
// logical, not an Euler buckling eigenproblem or finite-element shell law.
// Tensile responses are UNCHANGED. The caller must freeze alpha once per
// physics timestep to keep the XPBD lambda consistent during iterations.
// Optional mode uses the tensile-hardening alpha buffer, with no additional
// memory when both models are enabled.
//
// All calculations use double intermediates, so extreme but finite input
// does not cause overflow or NaNs. On invalid input r_alpha is not modified.
_FORCE_INLINE_ static bool physics_xpbd_compression_buckling_alpha(
		const Vector3 &p_a, const Vector3 &p_b,
		real_t p_rest_length, real_t p_base_alpha,
		real_t p_yield_strain, real_t p_transition_strain,
		real_t p_softening_ratio, real_t &r_alpha) {
	if (!p_a.is_finite() || !p_b.is_finite() ||
			!Math::is_finite(p_rest_length) || !Math::is_finite(p_base_alpha) ||
			!Math::is_finite(p_yield_strain) || !Math::is_finite(p_transition_strain) ||
			!Math::is_finite(p_softening_ratio) ||
			p_rest_length < 0.0 || p_base_alpha < 0.0 ||
			p_yield_strain < 0.0 || p_transition_strain < 0.0 ||
			p_softening_ratio < 1.0) {
		return false;
	}

	// Maintain the original XPBD response when buckling is off or when the
	// link has no meaningful rest length. Avoid all geometric work here.
	if (p_rest_length == 0.0 || p_softening_ratio == 1.0 ||
			p_base_alpha == 0.0) {
		r_alpha = p_base_alpha;
		return true;
	}
	const double dx = double(p_b.x) - double(p_a.x);
	const double dy = double(p_b.y) - double(p_a.y);
	const double dz = double(p_b.z) - double(p_a.z);
	const double length = Math::sqrt(dx * dx + dy * dy + dz * dz);
	if (!Math::is_finite(length)) {
		return false;
	}
	// Compression strain never exceeds 1 for nonnegative current length.
	// A deformed (stretched) link does not receive compressive softening.
	const double strain = 1.0 - length / double(p_rest_length);
	if (!(strain > double(p_yield_strain))) {
		r_alpha = p_base_alpha;
		return true;
	}

	double t = 1.0;
	if (p_transition_strain > 0.0) {
		t = CLAMP((strain - double(p_yield_strain)) /
						double(p_transition_strain),
				0.0, 1.0);
	}
	const double smooth = t * t * (3.0 - 2.0 * t);
	const double factor = 1.0 + (double(p_softening_ratio) - 1.0) * smooth;
	const double max_alpha = double(std::numeric_limits<real_t>::max());
	const double candidate = double(p_base_alpha) * factor;
	// A saturated finite compliance produces negligible constraint force
	// without introducing infinite alpha into XPBD denominators.
	if (Math::is_nan(candidate) || candidate < 0.0) {
		return false;
	}
	r_alpha = real_t(MIN(candidate, max_alpha));
	return true;
}
