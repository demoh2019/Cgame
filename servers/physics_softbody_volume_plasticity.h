/**************************************************************************/
/*  physics_softbody_volume_plasticity.h                                  */
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

// Optional global viscoplastic volume response for a CLOSED soft-body shell.
// The XPBD mechanical rest volume changes irreversibly when relative volume
// strain exceeds yield. Signed orientation is always preserved. This models
// crushed foam-like objects and plastic swelling, not tetrahedral FEM.
//
// At a fixed current volume, the new elastic boundary is:
//   |rest_target| = |current| / (1 +/- yield_strain)
// and the new rest volume relaxes exponentially toward the boundary:
//   rest_next = rest + fraction * (rest_target - rest)
// where fraction = 1 - exp(-creep_rate * dt), computed once per STEP.
//
// Clamp accumulated plastic volume to 2%-20x its ORIGINAL geometric volume.
// This prevents irreversible collapse to zero or unbounded plastic inflation.
// Gas uses that same immutable ORIGINAL volume as its thermodynamic reference,
// so crushing the shell cannot alter the amount of gas inside.
//
// False means no plastic deformation or invalid geometry; r_rest_volume is
// left completely unchanged. All intermediate calculations use double.
_FORCE_INLINE_ static bool physics_softbody_creep_rest_volume(
		double p_current_signed_volume, double p_original_signed_volume,
		real_t p_yield_strain, double p_creep_fraction,
		double &r_rest_signed_volume) {
	if (!Math::is_finite(p_current_signed_volume) ||
			!Math::is_finite(p_original_signed_volume) ||
			!Math::is_finite(r_rest_signed_volume) ||
			!Math::is_finite(p_yield_strain) ||
			!Math::is_finite(p_creep_fraction) ||
			p_original_signed_volume == 0.0 ||
			p_current_signed_volume == 0.0 ||
			r_rest_signed_volume == 0.0 ||
			p_yield_strain < real_t(0.0) || p_yield_strain > real_t(0.95) ||
			!(p_creep_fraction > 0.0) || p_creep_fraction > 1.0) {
		return false;
	}
	const bool negative = p_original_signed_volume < 0.0;
	if ((p_current_signed_volume < 0.0) != negative ||
			(r_rest_signed_volume < 0.0) != negative) {
		return false; // Inversion or inconsistent signed winding.
	}

	const double original = Math::abs(p_original_signed_volume);
	const double rest = Math::abs(r_rest_signed_volume);
	const double current = Math::abs(p_current_signed_volume);
	const double ratio = current / rest;
	if (!(ratio > 0.0) || !Math::is_finite(ratio)) {
		return false;
	}

	const double yield = double(p_yield_strain);
	double target;
	if (ratio > 1.0 + yield) {
		target = current / (1.0 + yield);
	} else if (ratio < 1.0 - yield) {
		target = current / (1.0 - yield);
	} else {
		return false; // Within the reversible elastic range.
	}

	// Keep the accumulated rest state well conditioned even under repeated
	// crushing. Use saturation and guards for extreme finite double inputs.
	const double minimum = original * 0.02;
	const double maximum = original > std::numeric_limits<double>::max() / 20.0 ?
			std::numeric_limits<double>::max() : original * 20.0;
	if (!(minimum > 0.0) || !Math::is_finite(target) || !(maximum > 0.0)) {
		return false;
	}
	target = MIN(MAX(target, minimum), maximum);
	const double next = rest + (target - rest) * p_creep_fraction;
	if (!(next > 0.0) || !Math::is_finite(next) || next == rest) {
		return false;
	}
	const double signed_next = negative ? -next : next;
	if (!Math::is_finite(signed_next)) {
		return false;
	}
	r_rest_signed_volume = signed_next;
	return true;
}
