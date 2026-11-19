/**************************************************************************/
/*  physics_pbf_vorticity_3d.h                                            */
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

// A separately testable velocity post-process for Position Based Fluids.
// The PBF density solve and XSPH smoothing lose small-scale rotational
// motion. Vorticity confinement restores part of that lost swirling
// motion (Macklin & Mueller, Position Based Fluids 2013).
//
// Curl estimator, with the SAME grad_i W(x_i-x_j) as density projection:
//     omega_i = Sum_j (m/rho_j) grad_i W_ij x (v_j - v_i)
// For a positive rigid-body spin around +Z, omega.z is positive.
// The sign/order of this cross product matters.
//
// The SPH gradient of vorticity magnitude is
//     eta_i = Sum_j (m/rho_j) (|omega_j| - |omega_i|) grad_i W_ij
// and the added velocity is
//     delta_v_i = dt * confinement_strength * normalized(eta_i) x omega_i.
//
// strength has dimensions of velocity (m/s), not a physical viscosity
// or a calibrated turbulent-energy injection model. It is an adjustable
// visual restoration term and may add kinetic energy deliberately.
//
// This file has no allocations, scene dependencies or neighborhood scans;
// the caller supplies compact-support pairs from its spatial grid.
// To avoid overflow/unstable numerical forces, the final increment is
// capped per substep and rejected on nonfinite inputs.
struct PhysicsPBFVorticity3D {
	static _FORCE_INLINE_ Vector3 curl_pair(
			const Vector3 &p_neighbor_velocity_difference,
			const Vector3 &p_kernel_gradient, real_t p_neighbor_volume) {
		if (!p_neighbor_velocity_difference.is_finite() || !p_kernel_gradient.is_finite() ||
				!(p_neighbor_volume > real_t(0.0)) || !Math::is_finite(p_neighbor_volume)) {
			return Vector3();
		}
		const Vector3 curl = p_kernel_gradient.cross(p_neighbor_velocity_difference) * p_neighbor_volume;
		return curl.is_finite() ? curl : Vector3();
	}

	static _FORCE_INLINE_ Vector3 magnitude_gradient_pair(
			real_t p_neighbor_vorticity_magnitude, real_t p_self_vorticity_magnitude,
			const Vector3 &p_kernel_gradient, real_t p_neighbor_volume) {
		if (!Math::is_finite(p_neighbor_vorticity_magnitude) ||
				!Math::is_finite(p_self_vorticity_magnitude) ||
				!p_kernel_gradient.is_finite() || !(p_neighbor_volume > real_t(0.0)) ||
				!Math::is_finite(p_neighbor_volume)) {
			return Vector3();
		}
		const double difference = double(p_neighbor_vorticity_magnitude) - double(p_self_vorticity_magnitude);
		const Vector3 eta = p_kernel_gradient * real_t(difference * double(p_neighbor_volume));
		return eta.is_finite() ? eta : Vector3();
	}

	static _FORCE_INLINE_ Vector3 velocity_increment(
			const Vector3 &p_vorticity_magnitude_gradient, const Vector3 &p_vorticity,
			real_t p_strength, real_t p_delta, real_t p_max_increment) {
		if (!p_vorticity_magnitude_gradient.is_finite() || !p_vorticity.is_finite() ||
				!(p_strength > real_t(0.0)) || !Math::is_finite(p_strength) ||
				!(p_delta > real_t(0.0)) || !Math::is_finite(p_delta) ||
				!(p_max_increment > real_t(0.0)) || !Math::is_finite(p_max_increment)) {
			return Vector3();
		}
		const double eta_length_squared = double(p_vorticity_magnitude_gradient.length_squared());
		const double omega_length_squared = double(p_vorticity.length_squared());
		if (!(eta_length_squared > 1e-16) || !(omega_length_squared > 1e-16) ||
				!Math::is_finite(eta_length_squared) || !Math::is_finite(omega_length_squared)) {
			return Vector3();
		}
		const Vector3 unit_eta = p_vorticity_magnitude_gradient / real_t(Math::sqrt(eta_length_squared));
		const Vector3 force = unit_eta.cross(p_vorticity);
		const double magnitude_squared = double(force.length_squared());
		if (!(magnitude_squared > 0.0) || !Math::is_finite(magnitude_squared)) {
			return Vector3();
		}
		// Scaling before computing the velocity change could overflow in
		// extreme density piles. Normalize the direction first and clamp
		// the desired magnitude independently using double precision.
		const double unbounded_increment = Math::sqrt(magnitude_squared) *
				double(p_strength) * double(p_delta);
		if (!(unbounded_increment > 0.0) || !Math::is_finite(unbounded_increment)) {
			return Vector3();
		}
		const double bounded_increment = MIN(unbounded_increment, double(p_max_increment));
		const Vector3 result = (force / real_t(Math::sqrt(magnitude_squared))) * real_t(bounded_increment);
		return result.is_finite() ? result : Vector3();
	}
};
