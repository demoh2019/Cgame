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
};
