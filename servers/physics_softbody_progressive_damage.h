/**************************************************************************/
/*  physics_softbody_progressive_damage.h                                 */
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

// Irreversible, rate-limited TENSILE material damage for XPBD distance links.
// e = max(0, length/rest_length - 1); target damage grows linearly from
// yield_strain to failure_strain, up to the deliberately bounded value 0.95.
// A damaged link remains connected; it does NOT generate tears or change
// collision topology. Damage evolves only when current target exceeds the
// previous damage (no spontaneous healing):
//
//   D_new = D_old + (D_target - D_old) * (1 - exp(-rate * dt))
//
// When the current strain falls, D_old is preserved. This is a simple
// stress-exposure / progressive damage model, NOT a calibrated fatigue-cycle
// law or FEM fracture criterion. A per-link scalar is stored by the caller.
// Doubles avoid overflow in lengths and intermediate math. Invalid input
// never changes r_damage.
_FORCE_INLINE_ static bool physics_softbody_progressive_tension_damage(
		const Vector3 &p_a, const Vector3 &p_b, real_t p_rest_length,
		real_t p_yield_strain, real_t p_failure_strain,
		real_t p_damage_rate, real_t p_dt,
		real_t &r_damage) {
	constexpr double MAX_DAMAGE = 0.95;
	if (!p_a.is_finite() || !p_b.is_finite() ||
			!Math::is_finite(p_rest_length) || !(p_rest_length > 0.0) ||
			!Math::is_finite(p_yield_strain) || p_yield_strain < 0.0 ||
			!Math::is_finite(p_failure_strain) || !(p_failure_strain > p_yield_strain) ||
			!Math::is_finite(p_damage_rate) || p_damage_rate < 0.0 ||
			!Math::is_finite(p_dt) || p_dt < 0.0 ||
			!Math::is_finite(r_damage) || r_damage < 0.0 ||
			double(r_damage) > MAX_DAMAGE) {
		return false;
	}
	if (p_damage_rate == 0.0 || p_dt == 0.0 || r_damage >= real_t(MAX_DAMAGE)) {
		return true; // Rate 0 is a strict opt-out; no geometry work.
	}
	const double dx = double(p_b.x) - double(p_a.x);
	const double dy = double(p_b.y) - double(p_a.y);
	const double dz = double(p_b.z) - double(p_a.z);
	const double length = Math::sqrt(dx * dx + dy * dy + dz * dz);
	if (!Math::is_finite(length)) {
		return false;
	}
	const double ratio = length / double(p_rest_length);
	if (Math::is_nan(ratio)) {
		return false;
	}
	const double excess = ratio - 1.0 - double(p_yield_strain);
	if (!(excess > 0.0)) {
		return true; // Compression and sub-yield extension cannot add damage.
	}

	const double yield_range = double(p_failure_strain) - double(p_yield_strain);
	const double progress = excess >= yield_range ? 1.0 : excess / yield_range;
	const double target = MAX_DAMAGE * progress;
	if (!(target > double(r_damage))) {
		return true; // Damage is irreversible, even after unloading.
	}
	const double step_exponent = -double(p_damage_rate) * double(p_dt);
	const double fraction = 1.0 - Math::exp(step_exponent);
	const double updated = double(r_damage) + (target - double(r_damage)) * fraction;
	if (!Math::is_finite(updated) || updated < double(r_damage)) {
		return false;
	}
	const double bounded = MIN(MAX_DAMAGE, updated);
	const real_t next = real_t(bounded);
	if (!Math::is_finite(next) || next < r_damage) {
		return false;
	}
	r_damage = next;
	return true;
}

// XPBD alpha is compliance / dt²; stiffness is proportional to 1/alpha.
// Attenuating effective stiffness by (1-D) means alpha_damage = alpha/(1-D).
// Cap alpha at max(real_t) to prevent overflow with large user compliances.
// This helper accepts exactly the range emitted by the damage updater.
_FORCE_INLINE_ static bool physics_softbody_progressive_damage_alpha(
		real_t p_base_alpha, real_t p_damage, real_t &r_alpha) {
	if (!Math::is_finite(p_base_alpha) || p_base_alpha < 0.0 ||
			!Math::is_finite(p_damage) || p_damage < 0.0 ||
			double(p_damage) > 0.95) {
		return false;
	}
	const double candidate = double(p_base_alpha) /
			(1.0 - double(p_damage));
	if (Math::is_nan(candidate) || candidate < 0.0) {
		return false;
	}
	const real_t updated = real_t(MIN(candidate, double(std::numeric_limits<real_t>::max())));
	if (!Math::is_finite(updated)) {
		return false;
	}
	r_alpha = updated;
	return true;
}
