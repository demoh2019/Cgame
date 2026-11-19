/**************************************************************************/
/*  physics_pbf_divergence_3d.h                                           */
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

// Divergence-error velocity projection for an existing PBF position solver.
//
// SPH continuity (uniform particle masses):
//   rho_dot_i = Sum_j m (v_i - v_j) . grad_i W_ij
// Positive rho_dot denotes a *compressing* velocity field.
// Free-surface / underdense particles only constrain positive divergence:
//
//   C_i = max(rho_dot_i / rho0, 0)
//   lambda_i = -C_i / (Sum_j |dC_i/dv_j|^2 + |dC_i/dv_i|^2 + eps)
//   delta_v_i = m/rho0 * Sum_j (lambda_i + lambda_j) grad_i W_ij
//
// The signs are the SAME as PBF position projection. The linearization
// is local; this is a DFSPH-inspired *velocity divergence projection*
// added after PBF, not a full two-pressure-Poisson DFSPH replacement.
// Exact global momentum conservation requires an uncapped, symmetric
// neighbor list and no per-particle correction caps.
//
// Kernel computations use double intermediates and reject nonfinite
// inputs. All operations are allocation-free and independent of Godot
// scene/server objects so the actual header can be compiled separately.
struct PhysicsPBFDivergence3D {
	static _FORCE_INLINE_ real_t density_rate_pair(
			const Vector3 &p_self_velocity, const Vector3 &p_other_velocity,
			const Vector3 &p_kernel_gradient, real_t p_particle_mass) {
		if (!p_self_velocity.is_finite() || !p_other_velocity.is_finite() ||
				!p_kernel_gradient.is_finite() || !(p_particle_mass > real_t(0.0)) ||
				!Math::is_finite(p_particle_mass)) {
			return 0.0;
		}
		const Vector3 delta = p_self_velocity - p_other_velocity;
		const double rate = double(p_particle_mass) * double(delta.dot(p_kernel_gradient));
		return Math::is_finite(rate) ? real_t(rate) : real_t(0.0);
	}

	static _FORCE_INLINE_ real_t compressive_rate_fraction(
			double p_density_rate, double p_rest_density) {
		if (!Math::is_finite(p_density_rate) ||
				!(p_rest_density > 0.0) || !Math::is_finite(p_rest_density)) {
			return 0.0;
		}
		const double positive = MAX(p_density_rate / p_rest_density, 0.0);
		return Math::is_finite(positive) ? real_t(positive) : real_t(0.0);
	}

	static _FORCE_INLINE_ real_t lagrange_multiplier(
			double p_compressive_rate_fraction, double p_gradient_squared,
			double p_regularization = 1e-6) {
		if (!(p_compressive_rate_fraction > 0.0) ||
				!Math::is_finite(p_compressive_rate_fraction) ||
				!(p_gradient_squared >= 0.0) || !Math::is_finite(p_gradient_squared) ||
				!(p_regularization > 0.0) || !Math::is_finite(p_regularization)) {
			return 0.0;
		}
		const double lambda = -p_compressive_rate_fraction /
				(p_gradient_squared + p_regularization);
		return Math::is_finite(lambda) ? real_t(MAX(lambda, -1e6)) : real_t(0.0);
	}

	static _FORCE_INLINE_ Vector3 pair_velocity_correction(
			const Vector3 &p_kernel_gradient, real_t p_self_multiplier,
			real_t p_other_multiplier, real_t p_mass_over_rest_density) {
		if (!p_kernel_gradient.is_finite() ||
				!Math::is_finite(p_self_multiplier) || !Math::is_finite(p_other_multiplier) ||
				!(p_mass_over_rest_density > real_t(0.0)) ||
				!Math::is_finite(p_mass_over_rest_density)) {
			return Vector3();
		}
		const double scale = double(p_mass_over_rest_density) *
				(double(p_self_multiplier) + double(p_other_multiplier));
		const Vector3 result = p_kernel_gradient * real_t(scale);
		return result.is_finite() ? result : Vector3();
	}

	static _FORCE_INLINE_ Vector3 bounded_correction(
			const Vector3 &p_velocity_correction, real_t p_relaxation,
			real_t p_max_velocity_change) {
		if (!p_velocity_correction.is_finite() ||
				!(p_relaxation > real_t(0.0)) || !(p_relaxation <= real_t(1.0)) ||
				!Math::is_finite(p_relaxation) ||
				!(p_max_velocity_change > real_t(0.0)) ||
				!Math::is_finite(p_max_velocity_change)) {
			return Vector3();
		}
		const Vector3 relaxed = p_velocity_correction * p_relaxation;
		if (!relaxed.is_finite()) {
			return Vector3();
		}
		const double magnitude_squared = double(relaxed.length_squared());
		const double cap_squared = double(p_max_velocity_change) * double(p_max_velocity_change);
		if (!(magnitude_squared > 0.0)) {
			return Vector3();
		}
		if (magnitude_squared <= cap_squared) {
			return relaxed;
		}
		const double magnitude = Math::sqrt(magnitude_squared);
		const Vector3 result = relaxed * real_t(double(p_max_velocity_change) / magnitude);
		return result.is_finite() ? result : Vector3();
	}
};
