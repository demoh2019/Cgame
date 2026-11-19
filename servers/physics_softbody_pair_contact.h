/**************************************************************************/
/*  physics_softbody_pair_contact.h                                      */
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

#include "servers/physics_xpbd_self_collision.h"

// One vertex of soft body A against one triangle of soft body B.
// Reuses the proven unilateral XPBD projection and adds a transactional
// velocity correction so a post-solve pair pass preserves the response
// through the next physics step. All 4 positions, velocities, and lambda
// are updated together or not at all. Pinned nodes (zero inverse mass)
// keep both their positions and velocities unchanged.
//
// p_side is chosen from the current signed point-plane distance; this is
// a DISCRETE contact, not continuous collision detection. The caller must
// query only nearby triangles (BVH) and bound contact count.
_FORCE_INLINE_ static bool physics_softbody_solve_pair_vertex_face(
		Vector3 &r_vertex, Vector3 &r_a, Vector3 &r_b, Vector3 &r_c,
		Vector3 &r_velocity_vertex, Vector3 &r_velocity_a,
		Vector3 &r_velocity_b, Vector3 &r_velocity_c,
		real_t p_inv_vertex, real_t p_inv_a, real_t p_inv_b, real_t p_inv_c,
		real_t p_thickness, real_t p_alpha, int p_side,
		real_t p_delta, real_t &r_lambda) {
	if (!(p_delta > real_t(0.0)) || !Math::is_finite(p_delta) ||
			!r_velocity_vertex.is_finite() || !r_velocity_a.is_finite() ||
			!r_velocity_b.is_finite() || !r_velocity_c.is_finite()) {
		return false;
	}

	const Vector3 original[4] = { r_vertex, r_a, r_b, r_c };
	Vector3 corrected[4] = { r_vertex, r_a, r_b, r_c };
	Vector3 *velocities[4] = { &r_velocity_vertex, &r_velocity_a, &r_velocity_b, &r_velocity_c };
	const real_t inverse_masses[4] = { p_inv_vertex, p_inv_a, p_inv_b, p_inv_c };
	real_t next_lambda = r_lambda;
	if (!physics_xpbd_solve_self_collision(
				corrected[0], corrected[1], corrected[2], corrected[3],
				p_inv_vertex, p_inv_a, p_inv_b, p_inv_c,
				p_thickness, p_alpha, p_side, next_lambda)) {
		return false;
	}
	// The projection can validly return a zero displacement when an old
	// multiplier is released. No useless velocity writes in that case.
	Vector3 next_velocities[4];
	const double inverse_delta = 1.0 / double(p_delta);
	for (int i = 0; i < 4; ++i) {
		if (inverse_masses[i] == real_t(0.0)) {
			next_velocities[i] = *velocities[i];
			continue;
		}
		next_velocities[i] = Vector3(
				real_t(double(velocities[i]->x) + (double(corrected[i].x) - double(original[i].x)) * inverse_delta),
				real_t(double(velocities[i]->y) + (double(corrected[i].y) - double(original[i].y)) * inverse_delta),
				real_t(double(velocities[i]->z) + (double(corrected[i].z) - double(original[i].z)) * inverse_delta));
		if (!next_velocities[i].is_finite()) {
			return false;
		}
	}

	r_vertex = corrected[0];
	r_a = corrected[1];
	r_b = corrected[2];
	r_c = corrected[3];
	r_velocity_vertex = next_velocities[0];
	r_velocity_a = next_velocities[1];
	r_velocity_b = next_velocities[2];
	r_velocity_c = next_velocities[3];
	r_lambda = next_lambda;
	return true;
}
