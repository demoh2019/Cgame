/**************************************************************************/
/*  physics_xpbd_self_friction.h                                          */
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

#include "servers/physics_xpbd_self_collision.h"

// XPBD/PBD-style Coulomb-limited tangential position correction for a
// non-adjacent vertex/triangle contact. Used once AFTER the normal contact
// iterations, before SoftBody3D reconstructs velocity from x - q.
//
// The friction budget is mu * accumulated normal XPBD lambda (units of a
// mass-weighted position correction). This is an approximation to Coulomb
// friction, not a persistent static-friction manifold. It reduces relative
// slide without changing the contact's normal separation in the linearized
// model, and shares the normal constraint's barycentric mass weighting.
//
// No buffers or allocations. All four candidate positions are computed in
// double and validated before any particle or multiplier is modified.
_FORCE_INLINE_ static bool physics_xpbd_solve_self_friction(
		Vector3 &r_vertex, Vector3 &r_a, Vector3 &r_b, Vector3 &r_c,
		const Vector3 &p_prev_vertex, const Vector3 &p_prev_a,
		const Vector3 &p_prev_b, const Vector3 &p_prev_c,
		real_t p_inv_vertex, real_t p_inv_a, real_t p_inv_b, real_t p_inv_c,
		real_t p_friction, real_t p_normal_lambda, real_t p_thickness) {
	if (!(p_friction > real_t(0.0)) || !(p_normal_lambda > real_t(0.0)) ||
			!(p_thickness > real_t(0.0)) ||
			!Math::is_finite(p_friction) || !Math::is_finite(p_normal_lambda) ||
			!Math::is_finite(p_thickness) ||
			!Math::is_finite(p_inv_vertex) || !Math::is_finite(p_inv_a) ||
			!Math::is_finite(p_inv_b) || !Math::is_finite(p_inv_c) ||
			p_inv_vertex < real_t(0.0) || p_inv_a < real_t(0.0) ||
			p_inv_b < real_t(0.0) || p_inv_c < real_t(0.0) ||
			!p_prev_vertex.is_finite() || !p_prev_a.is_finite() ||
			!p_prev_b.is_finite() || !p_prev_c.is_finite()) {
		return false;
	}

	Vector3 normal;
	Vector3 barycentric;
	real_t signed_distance = real_t(0.0);
	if (!physics_xpbd_self_collision_face_projection(
				r_vertex, r_a, r_b, r_c, normal, barycentric, signed_distance) ||
			Math::abs(double(signed_distance)) > 2.0 * double(p_thickness)) {
		return false; // Separation or degenerate/outside-triangle contact.
	}

	const double wa = double(barycentric.x);
	const double wb = double(barycentric.y);
	const double wc = double(barycentric.z);
	const double m0 = double(p_inv_vertex);
	const double m1 = double(p_inv_a);
	const double m2 = double(p_inv_b);
	const double m3 = double(p_inv_c);
	const double weighted_mass = m0 + wa * wa * m1 + wb * wb * m2 + wc * wc * m3;
	if (!(weighted_mass > 0.0) || !Math::is_finite(weighted_mass)) {
		return false; // All nodes pinned or mass calculation invalid.
	}

	// The relative displacement is measured over the whole physics step,
	// before position-based velocity reconstruction. Double subtraction
	// avoids overflow in the presence of large but finite real_t positions.
	const double dx = (double(r_vertex.x) - double(p_prev_vertex.x)) -
			(wa * (double(r_a.x) - double(p_prev_a.x)) +
					wb * (double(r_b.x) - double(p_prev_b.x)) +
					wc * (double(r_c.x) - double(p_prev_c.x)));
	const double dy = (double(r_vertex.y) - double(p_prev_vertex.y)) -
			(wa * (double(r_a.y) - double(p_prev_a.y)) +
					wb * (double(r_b.y) - double(p_prev_b.y)) +
					wc * (double(r_c.y) - double(p_prev_c.y)));
	const double dz = (double(r_vertex.z) - double(p_prev_vertex.z)) -
			(wa * (double(r_a.z) - double(p_prev_a.z)) +
					wb * (double(r_b.z) - double(p_prev_b.z)) +
					wc * (double(r_c.z) - double(p_prev_c.z)));
	const double dot_normal = dx * double(normal.x) +
			dy * double(normal.y) + dz * double(normal.z);
	const double tx = dx - dot_normal * double(normal.x);
	const double ty = dy - dot_normal * double(normal.y);
	const double tz = dz - dot_normal * double(normal.z);
	const double tangent_length_sq = tx * tx + ty * ty + tz * tz;
	if (!(tangent_length_sq > 0.0) || !Math::is_finite(tangent_length_sq)) {
		return false;
	}

	// Coulomb cap on the *mass-weighted* tangent impulse. Avoid computing
	// an intermediate real_t impulse that may overflow before saturation.
	const double tangent_length = Math::sqrt(tangent_length_sq);
	const double max_impulse = double(p_friction) * double(p_normal_lambda);
	const double correction_scale = MIN(1.0 / weighted_mass, max_impulse / tangent_length);
	if (!(correction_scale > 0.0) || !Math::is_finite(correction_scale)) {
		return false;
	}
	const double ix = -tx * correction_scale;
	const double iy = -ty * correction_scale;
	const double iz = -tz * correction_scale;
	const Vector3 next_vertex(real_t(double(r_vertex.x) + m0 * ix),
			real_t(double(r_vertex.y) + m0 * iy), real_t(double(r_vertex.z) + m0 * iz));
	const Vector3 next_a(real_t(double(r_a.x) - m1 * wa * ix),
			real_t(double(r_a.y) - m1 * wa * iy), real_t(double(r_a.z) - m1 * wa * iz));
	const Vector3 next_b(real_t(double(r_b.x) - m2 * wb * ix),
			real_t(double(r_b.y) - m2 * wb * iy), real_t(double(r_b.z) - m2 * wb * iz));
	const Vector3 next_c(real_t(double(r_c.x) - m3 * wc * ix),
			real_t(double(r_c.y) - m3 * wc * iy), real_t(double(r_c.z) - m3 * wc * iz));
	if (!next_vertex.is_finite() || !next_a.is_finite() ||
			!next_b.is_finite() || !next_c.is_finite()) {
		return false;
	}
	r_vertex = next_vertex;
	r_a = next_a;
	r_b = next_b;
	r_c = next_c;
	return true;
}
