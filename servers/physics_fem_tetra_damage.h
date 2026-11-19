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
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER ARISING FROM, OUT OF OR IN */
/* CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/**************************************************************************/

#pragma once

#include "servers/physics_fem_tetra_neo_hookean.h"

// Experimental, isotropic finite-strain DAMAGE (not mesh fracture).
// Per-tetra irreversible scalar damage D in [0, max_damage] reduces the
// effective FEM stiffness by increasing XPBD compliance alpha/(1-D).
//
// The trigger uses the objective Green-Lagrange tensor
// E=(F^T F-I)/2, F=Ds*inverse(Dm). Its normalized norm
// sqrt((2/3)*E:E) detects shear, tension and compression without
// depending on rigid-body translation or rotation. Pure rotations
// have E=0. Inverted or singular elements are rejected atomically.
//
// This is phenomenological softening, not plastic flow or a continuum
// damage/fracture model. The original rest state/topology stay intact.
// The solver hot path has no heap allocations.
_FORCE_INLINE_ static bool physics_fem_tetra_damage_strain(
		const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c,
		const Vector3 &p_d, const PhysicsFEMTetraRest &p_rest,
		double &r_strain) {
	if (!p_a.is_finite() || !p_b.is_finite() ||
			!p_c.is_finite() || !p_d.is_finite() ||
			!(p_rest.volume > 0.0) || !Math::is_finite(p_rest.volume) ||
			!Math::is_finite(p_rest.signed_det) || p_rest.signed_det == 0.0) {
		return false;
	}
	const Vector3 positions[4] = { p_a, p_b, p_c, p_d };
	double f[3][3] = {};
	for (int row = 0; row < 3; ++row) {
		for (int col = 0; col < 3; ++col) {
			for (int edge = 0; edge < 3; ++edge) {
				const double inv = p_rest.inv_dm[edge][col];
				if (!Math::is_finite(inv)) {
					return false;
				}
				f[row][col] +=
						(double(positions[edge + 1][row]) - double(positions[0][row])) * inv;
			}
			if (!Math::is_finite(f[row][col])) {
				return false;
			}
		}
	}
	const double det =
			f[0][0] * (f[1][1] * f[2][2] - f[1][2] * f[2][1]) -
			f[0][1] * (f[1][0] * f[2][2] - f[1][2] * f[2][0]) +
			f[0][2] * (f[1][0] * f[2][1] - f[1][1] * f[2][0]);
	if (!(det > 1e-9) || !Math::is_finite(det)) {
		return false;
	}
	double norm_squared = 0.0;
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			double inner = 0.0;
			for (int k = 0; k < 3; ++k) {
				inner += f[k][i] * f[k][j];
			}
			const double e = 0.5 * (inner - (i == j ? 1.0 : 0.0));
			norm_squared += e * e;
		}
	}
	const double strain = Math::sqrt((2.0 / 3.0) * norm_squared);
	if (!(strain >= 0.0) || !Math::is_finite(strain)) {
		return false;
	}
	r_strain = strain;
	return true;
}

// One irreversible damage update per physics tick, on PREDICTED (pre-XPBD)
// positions. The excessive strain is saturated so huge but finite
// deformation cannot immediately cause numerical overflow.
// The exponential rate handles varying dt for constant strain.
_FORCE_INLINE_ static bool physics_fem_tetra_accumulate_damage(
		double p_strain, double p_yield_strain, double p_rate,
		double p_delta, double p_max_damage, real_t &r_damage) {
	if (!Math::is_finite(p_strain) || p_strain < 0.0 ||
			!Math::is_finite(p_yield_strain) || p_yield_strain < 0.0 ||
			!Math::is_finite(p_rate) || p_rate <= 0.0 ||
			!Math::is_finite(p_delta) || p_delta <= 0.0 ||
			!Math::is_finite(p_max_damage) || p_max_damage <= 0.0 ||
			p_max_damage > 0.95 ||
			!Math::is_finite(r_damage) || r_damage < 0.0 ||
			r_damage > p_max_damage || p_strain <= p_yield_strain) {
		return false;
	}
	const double excess = p_strain - p_yield_strain;
	const double intensity = excess / (1.0 + excess);
	const double fraction = -Math::expm1(-p_rate * p_delta);
	if (!(intensity > 0.0) || !Math::is_finite(intensity) ||
			!(fraction > 0.0) || !Math::is_finite(fraction)) {
		return false;
	}
	const double result = MIN(p_max_damage,
			double(r_damage) + (p_max_damage - double(r_damage)) *
					fraction * intensity);
	const real_t next = real_t(result);
	if (!Math::is_finite(next) || next < r_damage || next > p_max_damage) {
		return false;
	}
	if (next == r_damage) {
		return false;
	}
	r_damage = next;
	return true;
}

// Damage-dependent compliance, bounded by max_damage < 1 to avoid
// destroying the XPBD denominator or generating infinite softness.
_FORCE_INLINE_ static bool physics_fem_tetra_damage_alpha(
		double p_alpha, real_t p_damage, double &r_alpha) {
	if (!(p_alpha >= 0.0) || !Math::is_finite(p_alpha) ||
			!Math::is_finite(p_damage) || p_damage < 0.0 ||
			p_damage > 0.95) {
		return false;
	}
	const double adjusted = p_alpha / (1.0 - double(p_damage));
	if (!Math::is_finite(adjusted)) {
		return false;
	}
	r_alpha = adjusted;
	return true;
}
