/**************************************************************************/
/*  physics_softbody_pair_edge_contact.h                                  */
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
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "servers/physics_xpbd_edge_collision.h"

// Discrete contact between structural edges of DIFFERENT soft bodies.
// Reuses the existing unilateral XPBD edge distance constraint, then
// transfers the resulting position changes into velocities. This pair
// stage executes after body-local velocity reconstruction; correcting
// positions alone would lose the response on the next physics step.
//
// Proposed positions, velocities, and lambda are committed together.
// Fully pinned edges remain unchanged, intermediate operations are double
// precision, and invalid/degenerate inputs never partially modify state.
_FORCE_INLINE_ static bool physics_softbody_solve_pair_edge_contact(
		Vector3 &r_a, Vector3 &r_b, Vector3 &r_c, Vector3 &r_d,
		Vector3 &r_va, Vector3 &r_vb, Vector3 &r_vc, Vector3 &r_vd,
		real_t p_inv_a, real_t p_inv_b, real_t p_inv_c, real_t p_inv_d,
		real_t p_thickness, real_t p_alpha, const Vector3 &p_normal,
		real_t p_delta, real_t &r_lambda) {
	if (!(p_delta > real_t(0.0)) || !Math::is_finite(p_delta) ||
			!r_va.is_finite() || !r_vb.is_finite() ||
			!r_vc.is_finite() || !r_vd.is_finite()) {
		return false;
	}

	const Vector3 previous[4] = { r_a, r_b, r_c, r_d };
	Vector3 positions[4] = { r_a, r_b, r_c, r_d };
	Vector3 *velocities[4] = { &r_va, &r_vb, &r_vc, &r_vd };
	const real_t inv_mass[4] = { p_inv_a, p_inv_b, p_inv_c, p_inv_d };
	real_t lambda = r_lambda;
	if (!physics_xpbd_solve_edge_collision(
				positions[0], positions[1], positions[2], positions[3],
				p_inv_a, p_inv_b, p_inv_c, p_inv_d,
				p_thickness, p_alpha, p_normal, lambda)) {
		return false;
	}

	const double inverse_delta = 1.0 / double(p_delta);
	Vector3 next_velocities[4];
	for (int i = 0; i < 4; ++i) {
		const Vector3 &velocity = *velocities[i];
		if (inv_mass[i] == real_t(0.0)) {
			next_velocities[i] = velocity;
			continue;
		}
		next_velocities[i] = Vector3(
				real_t(double(velocity.x) + (double(positions[i].x) - double(previous[i].x)) * inverse_delta),
				real_t(double(velocity.y) + (double(positions[i].y) - double(previous[i].y)) * inverse_delta),
				real_t(double(velocity.z) + (double(positions[i].z) - double(previous[i].z)) * inverse_delta));
		if (!next_velocities[i].is_finite()) {
			return false;
		}
	}

	r_a = positions[0];
	r_b = positions[1];
	r_c = positions[2];
	r_d = positions[3];
	r_va = next_velocities[0];
	r_vb = next_velocities[1];
	r_vc = next_velocities[2];
	r_vd = next_velocities[3];
	r_lambda = lambda;
	return true;
}
