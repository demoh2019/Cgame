/**************************************************************************/
/*  physics_fem_tetra_damage.h                                           */
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

#include "core/math/vector3.h"

#include <cmath>
#include <limits>

// Progressive scalar continuum damage for an XPBD Neo-Hookean tetrahedron.
// D=0 intact, D<=0.95 prevents the entire element from losing stiffness.
//
// Dimensionless density = Neo-Hookean energy / undeformed tetra volume,
// evaluated using the existing solver's UNIT Young modulus convention.
//
// When density exceeds yield, severity = clamp(density/yield-1, 0, 32).
// Remaining integrity decays exponentially under constant loading:
// D_new = 1 - (1-D_old) * exp(-rate * dt * severity).
// The 0.95 cap bounds compliance amplification to 20x.
//
// This is a phenomenological energy-driven damage/softening model, not
// topology fracture; no nodes are disconnected and no crack faces created.
// Evaluate once per physics tick on predicted positions (before XPBD).
//
// Invalid inputs and sub-yield strains NEVER mutate r_damage.
_FORCE_INLINE_ static bool physics_fem_tetra_accumulate_damage(
		double p_energy_density, double p_yield_energy_density,
		double p_damage_rate, double p_delta, double &r_damage) {
	if (!Math::is_finite(p_energy_density) || p_energy_density < 0.0 ||
			!Math::is_finite(p_yield_energy_density) || !(p_yield_energy_density > 0.0) ||
			!Math::is_finite(p_damage_rate) || !(p_damage_rate > 0.0) ||
			!Math::is_finite(p_delta) || !(p_delta > 0.0) ||
			!Math::is_finite(r_damage) || r_damage < 0.0 || r_damage > 0.95) {
		return false;
	}
	if (!(p_energy_density > p_yield_energy_density) || r_damage >= 0.95) {
		return false;
	}
	// Saturate extreme energy ratios safely; infinity means maximal severity.
	const double energy_ratio = p_energy_density / p_yield_energy_density;
	const double severity = energy_ratio > 33.0 ? 32.0 : energy_ratio - 1.0;
	if (!(severity > 0.0)) {
		return false;
	}
	const double exponent = -p_damage_rate * p_delta * severity;
	const double survival = exponent < -700.0 ? 0.0 : std::exp(exponent);
	const double candidate = MIN(0.95, r_damage + (1.0 - r_damage) * (1.0 - survival));
	if (!(candidate > r_damage) || !Math::is_finite(candidate)) {
		return false;
	}
	r_damage = candidate;
	return true;
}

// Corresponding nonlinear material compliance; exact identity for D=0.
// Guard extreme alpha so the constraint solver never receives Infinity.
_FORCE_INLINE_ static double physics_fem_tetra_damage_alpha(double p_alpha, double p_damage) {
	if (!(p_alpha > 0.0) || !Math::is_finite(p_alpha) ||
			!Math::is_finite(p_damage) || p_damage <= 0.0) {
		return p_alpha;
	}
	const double remaining = 1.0 - MIN(0.95, p_damage);
	const double scale = 1.0 / remaining;
	return p_alpha > std::numeric_limits<double>::max() / scale ?
			std::numeric_limits<double>::max() : p_alpha * scale;
}
