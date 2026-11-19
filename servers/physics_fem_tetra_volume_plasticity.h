/**************************************************************************/
/*  physics_fem_tetra_volume_plasticity.h                                */
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
/**************************************************************************/

#pragma once

#include "servers/physics_fem_tetra_neo_hookean.h"

#include <algorithm>
#include <cmath>

// Local per-tetra isotropic VISCOPLASTICITY for the existing Neo-Hookean and
// Mooney-Rivlin FEM solvers. The undeformed rest shape is allowed to expand or
// shrink irreversibly, unlike damage which only softens stiffness.
//
// For J = det(current edge matrix) / det(mechanical rest edge matrix) > 0,
// logarithmic volumetric strain e = ln(J) is additive. Outside |e| <= yield:
//   dlogVp = (1-exp(-rate*dt)) * sign(e) * (|e|-yield).
// The accumulated plastic volume scale Vp/Vp0 is clamped to [0.2,5.0].
// The REST edge matrix is scaled by cbrt(relative plastic volume change),
// and its inverse rows are divided by the same factor. Signed rest
// determinant and undeformed volume are both multiplied by relative volume.
//
// This uses only 1 additional double per cached tetrahedron. Its finite,
// candidate-only update leaves the FEM rest matrices untouched on failure;
// rigid translation/rotation and inverted tetrahedra generate no creep.
// It runs once per physics tick on PREDICTED positions, not per XPBD iteration.
//
// Note: this is scalar ISOTROPIC volumetric plasticity, NOT tensorial
// multiplicative J2 metal plasticity, local fracture or remeshing.
_FORCE_INLINE_ static bool physics_fem_tetra_creep_volume_rest(
		const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c,
		const Vector3 &p_d, real_t p_log_yield, double p_fraction,
		PhysicsFEMTetraRest &r_rest, double &r_plastic_volume_scale) {
	if (!p_a.is_finite() || !p_b.is_finite() || !p_c.is_finite() || !p_d.is_finite() ||
			!Math::is_finite(p_log_yield) || p_log_yield < real_t(0.0) ||
			p_log_yield > real_t(2.0) ||
			!Math::is_finite(p_fraction) || !(p_fraction > 0.0 && p_fraction <= 1.0) ||
			!Math::is_finite(r_plastic_volume_scale) ||
			r_plastic_volume_scale < 0.2 || r_plastic_volume_scale > 5.0 ||
			!(r_rest.volume > 0.0) || !Math::is_finite(r_rest.volume) ||
			r_rest.signed_det == 0.0 || !Math::is_finite(r_rest.signed_det)) {
		return false;
	}
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			if (!Math::is_finite(r_rest.inv_dm[i][j])) {
				return false;
			}
		}
	}

	// Relative-coordinate double intermediates are robust to huge world
	// positions (same determinant convention as PhysicsFEMTetraRest).
	const double u[3] = { double(p_b.x) - double(p_a.x), double(p_b.y) - double(p_a.y), double(p_b.z) - double(p_a.z) };
	const double v[3] = { double(p_c.x) - double(p_a.x), double(p_c.y) - double(p_a.y), double(p_c.z) - double(p_a.z) };
	const double w[3] = { double(p_d.x) - double(p_a.x), double(p_d.y) - double(p_a.y), double(p_d.z) - double(p_a.z) };
	const double determinant =
			u[0] * (v[1] * w[2] - v[2] * w[1]) +
			u[1] * (v[2] * w[0] - v[0] * w[2]) +
			u[2] * (v[0] * w[1] - v[1] * w[0]);
	const double jacobian = determinant / r_rest.signed_det;
	if (!(jacobian > 1e-9) || !Math::is_finite(jacobian)) {
		return false; // Inversion/collapse is handled by the FEM recovery pass.
	}

	const double log_j = std::log(jacobian);
	if (!Math::is_finite(log_j) || std::abs(log_j) <= double(p_log_yield)) {
		return false; // Elastic response inside the logarithmic yield window.
	}
	const double excess = log_j > 0.0 ?
			log_j - double(p_log_yield) : log_j + double(p_log_yield);
	const double log_scale = std::log(r_plastic_volume_scale);
	// Clamp in log-space before exponentiation to prevent overflow under
	// extreme finite stretches and keep the new rest matrix well conditioned.
	const double target_log = std::min(std::log(5.0),
			std::max(std::log(0.2), log_scale + p_fraction * excess));
	if (!Math::is_finite(target_log) || std::abs(target_log - log_scale) <= 1e-14) {
		return false;
	}
	const double next_scale = std::min(5.0, std::max(0.2, std::exp(target_log)));
	const double relative_volume = next_scale / r_plastic_volume_scale;
	const double linear_factor = std::cbrt(relative_volume);
	if (!(linear_factor > 0.0) || !Math::is_finite(linear_factor)) {
		return false;
	}

	PhysicsFEMTetraRest candidate = r_rest;
	candidate.volume *= relative_volume;
	candidate.signed_det *= relative_volume;
	if (!(candidate.volume > 0.0) || !Math::is_finite(candidate.volume) ||
			candidate.signed_det == 0.0 || !Math::is_finite(candidate.signed_det)) {
		return false;
	}
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			candidate.inv_dm[i][j] /= linear_factor;
			if (!Math::is_finite(candidate.inv_dm[i][j])) {
				return false; // Atomic update, old rest is unchanged.
			}
		}
	}
	r_rest = candidate;
	r_plastic_volume_scale = next_scale;
	return true;
}
