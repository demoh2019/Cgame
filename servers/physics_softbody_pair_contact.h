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

// Friction for a contact between DIFFERENT soft bodies, applied as an
// instantaneous mass-weighted tangential velocity impulse. The preceding
// unilateral XPBD projection supplies the normal multiplier (position units).
// Its corresponding impulse scale is lambda / dt. We use the Coulomb bound
// |J_t| <= mu * lambda / dt, and never change the contact normal velocity.
//
// Unlike intra-body positional self-friction, this post-solve form operates
// on the current velocities. It is applied ONCE after normal iterations,
// requires no persistent contact state and never creates artificial motion
// if the two sides have equal tangential velocity. Both bodies' four
// velocities are validated before ANY write. Pins have zero inverse mass.
_FORCE_INLINE_ static bool physics_softbody_solve_pair_friction(
		const Vector3 &p_vertex, const Vector3 &p_a,
		const Vector3 &p_b, const Vector3 &p_c,
		Vector3 &r_v_vertex, Vector3 &r_v_a,
		Vector3 &r_v_b, Vector3 &r_v_c,
		real_t p_inv_vertex, real_t p_inv_a, real_t p_inv_b, real_t p_inv_c,
		real_t p_mu, real_t p_normal_lambda,
		real_t p_thickness, real_t p_delta) {
	if (!(p_mu > real_t(0.0)) || !(p_normal_lambda > real_t(0.0)) ||
			!(p_thickness > real_t(0.0)) || !(p_delta > real_t(0.0)) ||
			!Math::is_finite(p_mu) || !Math::is_finite(p_normal_lambda) ||
			!Math::is_finite(p_thickness) || !Math::is_finite(p_delta) ||
			!Math::is_finite(p_inv_vertex) || !Math::is_finite(p_inv_a) ||
			!Math::is_finite(p_inv_b) || !Math::is_finite(p_inv_c) ||
			p_inv_vertex < real_t(0.0) || p_inv_a < real_t(0.0) ||
			p_inv_b < real_t(0.0) || p_inv_c < real_t(0.0) ||
			!r_v_vertex.is_finite() || !r_v_a.is_finite() ||
			!r_v_b.is_finite() || !r_v_c.is_finite()) {
		return false;
	}

	Vector3 normal, barycentric;
	real_t signed_distance = real_t(0.0);
	if (!physics_xpbd_self_collision_face_projection(
				p_vertex, p_a, p_b, p_c, normal, barycentric, signed_distance) ||
			Math::abs(double(signed_distance)) > 2.0 * double(p_thickness)) {
		return false;
	}

	const double weights[4] = { 1.0, double(barycentric.x),
		double(barycentric.y), double(barycentric.z) };
	const double masses[4] = { double(p_inv_vertex), double(p_inv_a),
		double(p_inv_b), double(p_inv_c) };
	Vector3 *velocities[4] = { &r_v_vertex, &r_v_a, &r_v_b, &r_v_c };
	double effective_inverse_mass = 0.0;
	double relative[3] = { double(r_v_vertex.x), double(r_v_vertex.y),
		double(r_v_vertex.z) };
	for (int i = 0; i < 4; ++i) {
		effective_inverse_mass += masses[i] * weights[i] * weights[i];
		if (i == 0) {
			continue;
		}
		relative[0] -= weights[i] * double(velocities[i]->x);
		relative[1] -= weights[i] * double(velocities[i]->y);
		relative[2] -= weights[i] * double(velocities[i]->z);
	}
	if (!(effective_inverse_mass > 0.0) ||
			!Math::is_finite(effective_inverse_mass)) {
		return false;
	}

	const double projection = relative[0] * double(normal.x) +
			relative[1] * double(normal.y) + relative[2] * double(normal.z);
	const double tangent[3] = {
		relative[0] - projection * double(normal.x),
		relative[1] - projection * double(normal.y),
		relative[2] - projection * double(normal.z)
	};
	const double tangent_squared =
			tangent[0] * tangent[0] + tangent[1] * tangent[1] + tangent[2] * tangent[2];
	if (!(tangent_squared > 0.0) || !Math::is_finite(tangent_squared)) {
		return false;
	}
	const double tangent_speed = Math::sqrt(tangent_squared);
	const double budget = double(p_mu) * double(p_normal_lambda) / double(p_delta);
	if (!(budget > 0.0) || !Math::is_finite(budget)) {
		return false;
	}
	// Applying at most the exact cancelling impulse ensures that kinetic
	// energy never increases (up to floating point roundoff).
	const double scale = MIN(1.0 / effective_inverse_mass, budget / tangent_speed);
	if (!(scale > 0.0) || !Math::is_finite(scale)) {
		return false;
	}

	const double impulse[3] = { -tangent[0] * scale,
		-tangent[1] * scale, -tangent[2] * scale };
	Vector3 next_velocities[4];
	for (int i = 0; i < 4; ++i) {
		const double signed_weight = i == 0 ? 1.0 : -weights[i];
		const double dv = masses[i] * signed_weight;
		const Vector3 &v = *velocities[i];
		next_velocities[i] = Vector3(
				real_t(double(v.x) + impulse[0] * dv),
				real_t(double(v.y) + impulse[1] * dv),
				real_t(double(v.z) + impulse[2] * dv));
		if (!next_velocities[i].is_finite()) {
			return false;
		}
	}
	for (int i = 0; i < 4; ++i) {
		*velocities[i] = next_velocities[i];
	}
	return true;
}
