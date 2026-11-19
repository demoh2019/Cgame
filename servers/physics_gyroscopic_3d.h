/**************************************************************************/
/*  physics_gyroscopic_3d.h                                               */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/math/basis.h"
#include "core/math/math_funcs.h"
#include "core/math/vector3.h"

// Free rigid-body Euler equation in the principal inertia frame:
//     dL/dt = -omega x L,       L = I omega.
// Following Jolt's approach, rescale the explicit momentum update to keep
// its magnitude constant and avoid the angular momentum growth that a bare
// explicit gyroscopic force can produce. A single, allocation-free update
// is used once per physics frame; never called on the default/off path.
//
// The caller converts between world and orthonormal principal inertia axes.
// Invalid/singular principal moments are skipped instead of dividing by zero.
struct GodotPhysicsGyroscopic3D {
	static _FORCE_INLINE_ Vector3 integrate_principal(const Vector3 &p_omega, const Vector3 &p_inv_inertia, real_t p_step) {
		if (!(p_step > 0.0) || !Math::is_finite(p_step) ||
				!p_omega.is_finite() || !p_inv_inertia.is_finite() ||
				!(p_inv_inertia.x > 0.0) || !(p_inv_inertia.y > 0.0) || !(p_inv_inertia.z > 0.0)) {
			return p_omega;
		}
		const Vector3 inertia(real_t(1.0) / p_inv_inertia.x, real_t(1.0) / p_inv_inertia.y, real_t(1.0) / p_inv_inertia.z);
		if (!inertia.is_finite()) {
			return p_omega;
		}
		const Vector3 momentum(inertia.x * p_omega.x, inertia.y * p_omega.y, inertia.z * p_omega.z);
		if (!momentum.is_finite()) {
			return p_omega;
		}
		const Vector3 gyroscopic_change = p_omega.cross(momentum) * p_step;
		if (gyroscopic_change == Vector3()) {
			// Isotropic inertia or rotation around a principal axis.
			return p_omega;
		}
		const Vector3 updated_momentum = momentum - gyroscopic_change;
		const real_t old_squared = momentum.length_squared();
		const real_t new_squared = updated_momentum.length_squared();
		if (!(old_squared > 0.0) || !(new_squared > 0.0) ||
				!Math::is_finite(old_squared) || !Math::is_finite(new_squared)) {
			return p_omega;
		}
		const real_t length_correction = Math::sqrt(old_squared / new_squared);
		const Vector3 corrected_momentum = updated_momentum * length_correction;
		const Vector3 corrected_omega(corrected_momentum.x * p_inv_inertia.x,
				corrected_momentum.y * p_inv_inertia.y, corrected_momentum.z * p_inv_inertia.z);
		return corrected_omega.is_finite() ? corrected_omega : p_omega;
	}

	// Implicit midpoint for torque-free Euler rotation, inspired by the
	// energy-preserving geometric rigid-body integrators used for demanding
	// tumbling simulations. With L_mid = (L_old + L_new) / 2:
	//   L_new = L_old + dt * (L_mid x (I^-1 L_mid)).
	// Because the increment is perpendicular to both L_mid and omega_mid,
	// the converged solution preserves |L| and 0.5 * L dot I^-1 L.
	// Newton's 3x3 solve uses only stack values. If a very large timestep or
	// ill-conditioned inertia prevents convergence, fall back to the existing
	// bounded normalized Euler update instead of producing invalid motion.
	static _FORCE_INLINE_ Vector3 integrate_principal_midpoint(const Vector3 &p_omega, const Vector3 &p_inv_inertia, real_t p_step) {
		if (!(p_step > 0.0) || !Math::is_finite(p_step) ||
				!p_omega.is_finite() || !p_inv_inertia.is_finite() ||
				!(p_inv_inertia.x > 0.0) || !(p_inv_inertia.y > 0.0) || !(p_inv_inertia.z > 0.0)) {
			return p_omega;
		}

		const Vector3 inertia(real_t(1.0) / p_inv_inertia.x,
				real_t(1.0) / p_inv_inertia.y, real_t(1.0) / p_inv_inertia.z);
		const Vector3 old_momentum(inertia.x * p_omega.x,
				inertia.y * p_omega.y, inertia.z * p_omega.z);
		if (!old_momentum.is_finite()) {
			return p_omega;
		}
		const Vector3 initial_change = old_momentum.cross(p_omega);
		if (initial_change == Vector3()) {
			return p_omega;
		}

		Vector3 next_momentum = old_momentum + initial_change * p_step;
		if (!next_momentum.is_finite()) {
			return integrate_principal(p_omega, p_inv_inertia, p_step);
		}
		const real_t tolerance_squared = real_t(1e-12) * MAX(real_t(1.0), old_momentum.length_squared());
		if (!Math::is_finite(tolerance_squared)) {
			return integrate_principal(p_omega, p_inv_inertia, p_step);
		}

		for (int iteration = 0; iteration < 8; iteration++) {
			const Vector3 mid_momentum = (old_momentum + next_momentum) * real_t(0.5);
			const Vector3 mid_omega(mid_momentum.x * p_inv_inertia.x,
					mid_momentum.y * p_inv_inertia.y, mid_momentum.z * p_inv_inertia.z);
			const Vector3 residual = next_momentum - old_momentum - mid_momentum.cross(mid_omega) * p_step;
			if (!residual.is_finite()) {
				break;
			}
			if (residual.length_squared() <= tolerance_squared) {
				const Vector3 result(next_momentum.x * p_inv_inertia.x,
						next_momentum.y * p_inv_inertia.y, next_momentum.z * p_inv_inertia.z);
				return result.is_finite() ? result : integrate_principal(p_omega, p_inv_inertia, p_step);
			}

			// Residual derivative J dL = dL - dt/2 *
			// (dL x omega_mid + L_mid x (I^-1 dL)).
			const real_t half_step = p_step * real_t(0.5);
			const Vector3 unit_x(1, 0, 0);
			const Vector3 unit_y(0, 1, 0);
			const Vector3 unit_z(0, 0, 1);
			const Vector3 column_x = unit_x - (unit_x.cross(mid_omega) +
					mid_momentum.cross(unit_x * p_inv_inertia.x)) * half_step;
			const Vector3 column_y = unit_y - (unit_y.cross(mid_omega) +
					mid_momentum.cross(unit_y * p_inv_inertia.y)) * half_step;
			const Vector3 column_z = unit_z - (unit_z.cross(mid_omega) +
					mid_momentum.cross(unit_z * p_inv_inertia.z)) * half_step;
			const Basis jacobian(column_x, column_y, column_z);
			const real_t determinant = jacobian.determinant();
			if (!Math::is_finite(determinant) || Math::abs(determinant) <= CMP_EPSILON) {
				break;
			}
			const Vector3 correction = jacobian.inverse().xform(residual);
			if (!correction.is_finite()) {
				break;
			}
			next_momentum -= correction;
			if (!next_momentum.is_finite()) {
				break;
			}
		}
		return integrate_principal(p_omega, p_inv_inertia, p_step);
	}
};
