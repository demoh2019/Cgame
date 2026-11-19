/**************************************************************************/
/*  physics_fem_tetra_damage.h                                            */
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

#include "servers/physics_fem_tetra_neo_hookean.h"

#include <cmath>

// Scalar continuum-damage approximation for a Neo-Hookean tetrahedron.
// Uses the UNDAMAGED normalized material energy density to produce an
// equivalent dimensionless strain measure sqrt(2 * W / rest_volume).
// Evaluating undamaged energy prevents damage from disappearing when a
// previously softened element unloads. A rigid motion has zero damage drive.
//
// d in [0, 0.95] is irreversible and strictly local to each tetrahedron.
// No vertex detachment, mesh fracture, or remeshing is implied.
// This phenomenological model is not a calibrated brittle-fracture law.
//
// Each tick, d <- d + (0.95-d) * (1-exp(-rate*max(0,strain-yield)*dt)).
// Using the remaining damage capacity makes d nondecreasing and
// independent of the physics iteration count. 0.95 leaves residual
// stiffness, which keeps a finite positive XPBD compliance.
struct PhysicsFEMTetraDamage {
	static constexpr double MAX_DAMAGE = 0.95;

	_FORCE_INLINE_ static bool equivalent_strain(
			const Vector3 p_positions[4], const PhysicsFEMTetraRest &p_rest,
			double p_poisson, double &r_strain) {
		if (!p_positions || !(p_rest.volume > 0.0) ||
				!Math::is_finite(p_rest.volume)) {
			return false;
		}
		double energy;
		Vector3 ga, gb, gc, gd;
		if (!physics_fem_tetra_energy_gradient(
					p_positions[0], p_positions[1], p_positions[2], p_positions[3],
					p_rest, p_poisson, energy, ga, gb, gc, gd)) {
			return false;
		}
		const double squared = 2.0 * energy / p_rest.volume;
		if (!(squared >= 0.0) || !Math::is_finite(squared)) {
			return false;
		}
		const double result = Math::sqrt(squared);
		if (!Math::is_finite(result)) {
			return false;
		}
		r_strain = result;
		return true;
	}

	_FORCE_INLINE_ static bool evolve(
			double p_strain, double p_yield, double p_rate,
			double p_delta, double &r_damage) {
		if (!Math::is_finite(p_strain) || p_strain < 0.0 ||
				!Math::is_finite(p_yield) || p_yield < 0.0 ||
				!Math::is_finite(p_rate) || p_rate < 0.0 ||
				!Math::is_finite(p_delta) || p_delta < 0.0 ||
				!Math::is_finite(r_damage) ||
				r_damage < 0.0 || r_damage > MAX_DAMAGE) {
			return false;
		}
		if (!(p_rate > 0.0) || !(p_delta > 0.0) ||
				!(p_strain > p_yield) || r_damage == MAX_DAMAGE) {
			return false;
		}
		const double exponent = p_rate * p_delta * (p_strain - p_yield);
		// Exponent overflow at extreme *finite* rates is a full-damage
		// increment. exp(-infinity)==0; no NaN is introduced.
		const double fraction = 1.0 - std::exp(-exponent);
		if (!(fraction > 0.0) || !Math::is_finite(fraction)) {
			return false;
		}
		const double proposed = r_damage + (MAX_DAMAGE - r_damage) * fraction;
		if (!Math::is_finite(proposed) || proposed < r_damage) {
			return false;
		}
		r_damage = MIN(MAX_DAMAGE, proposed);
		return true;
	}

	// XPBD compliance is inverse material stiffness. Multiplication by
	// 1/(1-d) models progressive softening without changing element rest
	// geometry or any other XPBD material constraint.
	_FORCE_INLINE_ static bool effective_compliance(
			double p_base_compliance, double p_damage, double &r_compliance) {
		if (!(p_base_compliance > 0.0) || !Math::is_finite(p_base_compliance) ||
				!Math::is_finite(p_damage) || p_damage < 0.0 || p_damage > MAX_DAMAGE) {
			return false;
		}
		const double result = p_base_compliance / (1.0 - p_damage);
		if (!(result > 0.0) || !Math::is_finite(result)) {
			return false;
		}
		r_compliance = result;
		return true;
	}
};
