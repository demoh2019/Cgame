/**************************************************************************/
/*  physics_pbf_density_pressure_3d.h                                     */
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

// Predictive density-pressure stage for the existing PBF solver.
// Using the discrete SPH continuity equation at the current positions:
//   rho_predicted_i = rho_i + dt * sum_j m (v_i - v_j) . grad_i W_ij
//   density_error_i = max((rho_predicted_i - rho_rest)/rho_rest, 0)
//
// To solve an equivalent velocity constraint, divide that error by dt:
//   C_i^v = density_error_i/dt
//   lambda_i = -C_i^v/(sum_j |(m/rho_rest)*grad_i W_ij|^2
//                 + |sum_j (m/rho_rest)*grad_i W_ij|^2 + epsilon)
//   delta_v_i = (m/rho_rest) sum_j (lambda_i+lambda_j) grad_i W_ij
//
// The lambda and correction formulas match the separate PBF velocity
// divergence projector, but the numerator additionally contains the
// *existing density excess*. Hence a compressed fluid at rest receives
// outward pressure BEFORE positions are predicted.
//
// This is an intermediate DFSPH-inspired predictive pressure projection,
// not the full DFSPH two-solve warm-started pressure algorithm, and it
// does NOT guarantee global volume conservation. Neighbor caps, finite
// regularization, per-particle velocity caps and the existing PBF
// positional solve can introduce non-conservative error.
struct PhysicsPBFDensityPressure3D {
	static _FORCE_INLINE_ real_t predicted_density(
			double p_density, double p_density_rate, double p_delta) {
		if (!(p_density >= 0.0) || !Math::is_finite(p_density) ||
				!Math::is_finite(p_density_rate) ||
				!(p_delta > 0.0) || !Math::is_finite(p_delta)) {
			return 0.0;
		}
		const double predicted = p_density + p_delta * p_density_rate;
		if (!Math::is_finite(predicted)) {
			return 0.0;
		}
		const real_t result = real_t(MAX(predicted, 0.0));
		return Math::is_finite(result) ? result : real_t(0.0);
	}

	static _FORCE_INLINE_ real_t positive_density_error(
			double p_predicted_density, double p_rest_density) {
		if (!Math::is_finite(p_predicted_density) ||
				!(p_rest_density > 0.0) || !Math::is_finite(p_rest_density)) {
			return 0.0;
		}
		const double excess = MAX(p_predicted_density / p_rest_density - 1.0, 0.0);
		const real_t result = real_t(excess);
		return Math::is_finite(result) ? result : real_t(0.0);
	}

	static _FORCE_INLINE_ real_t pressure_rate_constraint(
			double p_predicted_density, double p_rest_density, double p_delta) {
		if (!(p_delta > 0.0) || !Math::is_finite(p_delta)) {
			return 0.0;
		}
		const double error = positive_density_error(p_predicted_density, p_rest_density);
		const double rate = error / p_delta;
		const real_t result = real_t(rate);
		return Math::is_finite(result) ? result : real_t(0.0);
	}
};
