/**************************************************************************/
/*  physics_xpbd_self_collision.h                                         */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/math/vector3.h"

// Narrowphase for a vertex close to the INTERIOR of a non-adjacent triangle.
// Edge/edge and swept time-of-impact tests are intentionally separate future
// improvements. Use double for barycentric dot products to avoid overflow
// of the denominator on large, finite float32 coordinates.
_FORCE_INLINE_ bool physics_xpbd_self_collision_face_projection(
		const Vector3 &p_point, const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c,
		Vector3 &r_normal, Vector3 &r_barycentric, real_t &r_distance) {
	if (!p_point.is_finite() || !p_a.is_finite() || !p_b.is_finite() || !p_c.is_finite()) {
		return false;
	}

	// Compute coordinate differences BEFORE casting to real_t. Finite
	// float32 input edges can have an overflowing float32 cross product
	// (side 1e20) or an underflowing squared area (side 1e-8).
	const double ab_x = double(p_b.x) - double(p_a.x);
	const double ab_y = double(p_b.y) - double(p_a.y);
	const double ab_z = double(p_b.z) - double(p_a.z);
	const double ac_x = double(p_c.x) - double(p_a.x);
	const double ac_y = double(p_c.y) - double(p_a.y);
	const double ac_z = double(p_c.z) - double(p_a.z);
	const double point_x = double(p_point.x) - double(p_a.x);
	const double point_y = double(p_point.y) - double(p_a.y);
	const double point_z = double(p_point.z) - double(p_a.z);

	const double normal_x = ab_y * ac_z - ab_z * ac_y;
	const double normal_y = ab_z * ac_x - ab_x * ac_z;
	const double normal_z = ab_x * ac_y - ab_y * ac_x;
	const double normal_squared = normal_x * normal_x + normal_y * normal_y + normal_z * normal_z;
	const double d00 = ab_x * ab_x + ab_y * ab_y + ab_z * ab_z;
	const double d11 = ac_x * ac_x + ac_y * ac_y + ac_z * ac_z;
	const double scale_squared = d00 * d11;
	// A relative angle test is scale invariant. CMP_EPSILON^2 in world
	// units previously rejected legitimate small closed/cloth triangles.
	if (!(scale_squared > 0.0) || !Math::is_finite(scale_squared) ||
			!Math::is_finite(normal_squared) ||
			!(normal_squared > scale_squared * 1.0e-20)) {
		return false;
	}
	const double inv_normal_length = 1.0 / Math::sqrt(normal_squared);
	const double nx = normal_x * inv_normal_length;
	const double ny = normal_y * inv_normal_length;
	const double nz = normal_z * inv_normal_length;
	const double signed_distance = point_x * nx + point_y * ny + point_z * nz;
	if (!Math::is_finite(signed_distance)) {
		return false;
	}

	// The triangle basis is tangent to n, so projected-to-plane and raw
	// relative coordinates have the same dot products with each edge.
	// Use normal_squared = |ab x ac|^2 as the Gram determinant, avoiding
	// cancellation in (d00*d11 - d01*d01) for narrow triangles.
	const double d01 = ab_x * ac_x + ab_y * ac_y + ab_z * ac_z;
	const double d20 = point_x * ab_x + point_y * ab_y + point_z * ab_z;
	const double d21 = point_x * ac_x + point_y * ac_y + point_z * ac_z;
	const double v = (d11 * d20 - d01 * d21) / normal_squared;
	const double w = (d00 * d21 - d01 * d20) / normal_squared;
	const double u = 1.0 - v - w;
	if (!Math::is_finite(u) || !Math::is_finite(v) || !Math::is_finite(w) ||
			u < 0.0 || v < 0.0 || w < 0.0 || u > 1.0 || v > 1.0 || w > 1.0) {
		return false; // Footprint lies outside the triangular face.
	}

	const Vector3 normal{ real_t(nx), real_t(ny), real_t(nz) };
	const Vector3 barycentric{ real_t(u), real_t(v), real_t(w) };
	const real_t distance = real_t(signed_distance);
	if (!normal.is_finite() || !barycentric.is_finite() || !Math::is_finite(distance)) {
		return false;
	}
	// Atomic outputs: even an invalid face or huge point must not change
	// any of the narrowphase's candidate normal/barycentric/distance.
	r_normal = normal;
	r_barycentric = barycentric;
	r_distance = distance;
	return true;
}

// Unilateral XPBD distance-to-face constraint with a constant collision
// side selected from the previous positions. Positive lambda prevents a
// contact from artificially pulling separate layers together. Barycentric
// weights approximate the local geometric Jacobian of the face point.
// No allocations; positions and lambda are committed atomically.
_FORCE_INLINE_ bool physics_xpbd_solve_self_collision(
		Vector3 &r_vertex, Vector3 &r_a, Vector3 &r_b, Vector3 &r_c,
		real_t p_inv_vertex, real_t p_inv_a, real_t p_inv_b, real_t p_inv_c,
		real_t p_thickness, real_t p_alpha, int p_side, real_t &r_lambda) {
	if (!(p_thickness > 0.0) || !Math::is_finite(p_thickness) ||
			!Math::is_finite(p_alpha) || p_alpha < 0.0 ||
			!Math::is_finite(r_lambda) || r_lambda < 0.0 ||
			!Math::is_finite(p_inv_vertex) || !Math::is_finite(p_inv_a) ||
			!Math::is_finite(p_inv_b) || !Math::is_finite(p_inv_c) ||
			p_inv_vertex < 0.0 || p_inv_a < 0.0 || p_inv_b < 0.0 || p_inv_c < 0.0 ||
			(p_side != -1 && p_side != 1)) {
		return false;
	}
	Vector3 face_normal;
	Vector3 barycentric;
	real_t distance = 0.0;
	if (!physics_xpbd_self_collision_face_projection(
				r_vertex, r_a, r_b, r_c, face_normal, barycentric, distance)) {
		return false;
	}
	// Prevent the discrete solver from applying a giant impulse to a fully
	// tunneled point. A future continuous collision test must handle that.
	if (Math::abs(distance) > p_thickness * real_t(2.0)) {
		return false;
	}
	const real_t c = real_t(p_side) * distance - p_thickness;
	const double wa = double(barycentric.x);
	const double wb = double(barycentric.y);
	const double wc = double(barycentric.z);
	const double inv_mass_gradient = double(p_inv_vertex) +
			wa * wa * double(p_inv_a) +
			wb * wb * double(p_inv_b) +
			wc * wc * double(p_inv_c);
	const double denominator = inv_mass_gradient + double(p_alpha);
	if (!(inv_mass_gradient > 0.0) || !(denominator > 0.0) ||
			!Math::is_finite(denominator)) {
		return false;
	}
	const double delta_lambda = (-double(c) - double(p_alpha) * double(r_lambda)) / denominator;
	if (!Math::is_finite(delta_lambda)) {
		return false;
	}
	const double next_lambda_double = MAX(0.0, double(r_lambda) + delta_lambda);
	if (!Math::is_finite(next_lambda_double)) {
		return false;
	}
	const real_t next_lambda = real_t(next_lambda_double);
	if (!Math::is_finite(next_lambda)) {
		return false;
	}
	const double impulse = next_lambda_double - double(r_lambda);
	const Vector3 gradient = face_normal * real_t(p_side);
	const Vector3 next_vertex(
			real_t(double(r_vertex.x) + double(gradient.x) * double(p_inv_vertex) * impulse),
			real_t(double(r_vertex.y) + double(gradient.y) * double(p_inv_vertex) * impulse),
			real_t(double(r_vertex.z) + double(gradient.z) * double(p_inv_vertex) * impulse));
	const Vector3 next_a(
			real_t(double(r_a.x) - double(gradient.x) * wa * double(p_inv_a) * impulse),
			real_t(double(r_a.y) - double(gradient.y) * wa * double(p_inv_a) * impulse),
			real_t(double(r_a.z) - double(gradient.z) * wa * double(p_inv_a) * impulse));
	const Vector3 next_b(
			real_t(double(r_b.x) - double(gradient.x) * wb * double(p_inv_b) * impulse),
			real_t(double(r_b.y) - double(gradient.y) * wb * double(p_inv_b) * impulse),
			real_t(double(r_b.z) - double(gradient.z) * wb * double(p_inv_b) * impulse));
	const Vector3 next_c(
			real_t(double(r_c.x) - double(gradient.x) * wc * double(p_inv_c) * impulse),
			real_t(double(r_c.y) - double(gradient.y) * wc * double(p_inv_c) * impulse),
			real_t(double(r_c.z) - double(gradient.z) * wc * double(p_inv_c) * impulse));
	if (!next_vertex.is_finite() || !next_a.is_finite() ||
			!next_b.is_finite() || !next_c.is_finite()) {
		return false;
	}
	r_vertex = next_vertex;
	r_a = next_a;
	r_b = next_b;
	r_c = next_c;
	r_lambda = next_lambda;
	return true;
}
