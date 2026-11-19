/**************************************************************************/
/*  physics_softbody_pair_ccd.h                                           */
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

#include "servers/physics_xpbd_soft_ccd.h"

// Two-way swept vertex/triangle contact between DIFFERENT soft bodies.
// Reuse the monotonic-interval cubic time-of-impact narrowphase and XPBD
// projection used by self-CCD. Because pair collisions run AFTER local
// velocity reconstruction, apply delta-position/dt to each particle's
// velocity as well. Position, velocity and lambda commits are atomic.
//
// The caller must only use a hit from physics_xpbd_swept_vertex_triangle
// and choose candidates via a swept-face BVH. This is linear vertex/face
// CCD, not edge/edge CCD, and it does not rewind the entire simulation.
_FORCE_INLINE_ static bool physics_softbody_solve_pair_swept_face(
		Vector3 &r_vertex, Vector3 &r_a, Vector3 &r_b, Vector3 &r_c,
		Vector3 &r_velocity_vertex, Vector3 &r_velocity_a,
		Vector3 &r_velocity_b, Vector3 &r_velocity_c,
		real_t p_inv_vertex, real_t p_inv_a, real_t p_inv_b, real_t p_inv_c,
		real_t p_thickness, real_t p_alpha,
		const PhysicsXPBDSoftCCDSweepHit &p_hit,
		real_t p_delta, real_t &r_lambda) {
	if (!(p_delta > real_t(0.0)) || !Math::is_finite(p_delta) ||
			!r_velocity_vertex.is_finite() || !r_velocity_a.is_finite() ||
			!r_velocity_b.is_finite() || !r_velocity_c.is_finite() ||
			!Math::is_finite(p_hit.time) || p_hit.time < real_t(0.0) ||
			p_hit.time > real_t(1.0)) {
		return false;
	}

	const Vector3 previous[4] = { r_vertex, r_a, r_b, r_c };
	Vector3 positions[4] = { r_vertex, r_a, r_b, r_c };
	Vector3 *velocities[4] = {
		&r_velocity_vertex, &r_velocity_a, &r_velocity_b, &r_velocity_c
	};
	const real_t inverse_masses[4] = {
		p_inv_vertex, p_inv_a, p_inv_b, p_inv_c
	};
	real_t lambda = r_lambda;
	if (!physics_xpbd_solve_swept_vertex_face(
				positions[0], positions[1], positions[2], positions[3],
				p_inv_vertex, p_inv_a, p_inv_b, p_inv_c,
				p_thickness, p_alpha, p_hit, lambda)) {
		return false;
	}

	Vector3 corrected_velocities[4];
	const double inverse_dt = 1.0 / double(p_delta);
	for (int i = 0; i < 4; ++i) {
		const Vector3 &v = *velocities[i];
		if (inverse_masses[i] == real_t(0.0)) {
			corrected_velocities[i] = v;
			continue;
		}
		corrected_velocities[i] = Vector3(
				real_t(double(v.x) + (double(positions[i].x) - double(previous[i].x)) * inverse_dt),
				real_t(double(v.y) + (double(positions[i].y) - double(previous[i].y)) * inverse_dt),
				real_t(double(v.z) + (double(positions[i].z) - double(previous[i].z)) * inverse_dt));
		if (!corrected_velocities[i].is_finite()) {
			return false;
		}
	}

	r_vertex = positions[0];
	r_a = positions[1];
	r_b = positions[2];
	r_c = positions[3];
	r_velocity_vertex = corrected_velocities[0];
	r_velocity_a = corrected_velocities[1];
	r_velocity_b = corrected_velocities[2];
	r_velocity_c = corrected_velocities[3];
	r_lambda = lambda;
	return true;
}
