/**************************************************************************/
/*  physics_xpbd_edge_friction.h                                          */
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

#include "servers/physics_xpbd_edge_collision.h"

// One Coulomb-limited tangential XPBD position correction for a pair of
// non-adjacent *interior* structural edges. Called after normal projection,
// before SoftBody3D reconstructs velocity from position differences.
//
// The four particles share the correction through their closest-point
// barycentric weights. The normal row's accumulated nonnegative lambda
// supplies the tangential impulse budget. This deliberately does not attempt
// persistent static friction or continuous edge/edge collision detection.
// Purely opt-in: no allocations, persistent contact state or default cost.
// Every proposed position is checked before committing any update.
_FORCE_INLINE_ bool physics_xpbd_solve_edge_friction(
		Vector3 &r_a, Vector3 &r_b, Vector3 &r_c, Vector3 &r_d,
		const Vector3 &p_prev_a, const Vector3 &p_prev_b,
		const Vector3 &p_prev_c, const Vector3 &p_prev_d,
		real_t p_inv_a, real_t p_inv_b, real_t p_inv_c, real_t p_inv_d,
		real_t p_friction, real_t p_normal_lambda, real_t p_thickness,
		const Vector3 &p_normal) {
	if (!(p_friction > real_t(0.0)) || !(p_normal_lambda > real_t(0.0)) ||
			!(p_thickness > real_t(0.0)) ||
			!Math::is_finite(p_friction) || !Math::is_finite(p_normal_lambda) ||
			!Math::is_finite(p_thickness) || !p_normal.is_finite() ||
			!Math::is_finite(p_inv_a) || !Math::is_finite(p_inv_b) ||
			!Math::is_finite(p_inv_c) || !Math::is_finite(p_inv_d) ||
			p_inv_a < real_t(0.0) || p_inv_b < real_t(0.0) ||
			p_inv_c < real_t(0.0) || p_inv_d < real_t(0.0) ||
			!p_prev_a.is_finite() || !p_prev_b.is_finite() ||
			!p_prev_c.is_finite() || !p_prev_d.is_finite()) {
		return false;
	}

	const double nx = double(p_normal.x);
	const double ny = double(p_normal.y);
	const double nz = double(p_normal.z);
	const double normal_len_sq = nx * nx + ny * ny + nz * nz;
	if (!Math::is_finite(normal_len_sq) || Math::abs(normal_len_sq - 1.0) > 0.01) {
		return false; // The normal solver is expected to provide a unit vector.
	}

	real_t s = 0.0, t = 0.0, distance = 0.0;
	Vector3 computed_normal;
	if (!physics_xpbd_closest_edges(r_a, r_b, r_c, r_d,
				s, t, computed_normal, distance) ||
			double(distance) > 2.0 * double(p_thickness)) {
		return false;
	}

	const double wa = 1.0 - double(s);
	const double wb = double(s);
	const double wc = 1.0 - double(t);
	const double wd = double(t);
	const double ma = double(p_inv_a);
	const double mb = double(p_inv_b);
	const double mc = double(p_inv_c);
	const double md = double(p_inv_d);
	const double weighted_mass =
			ma * wa * wa + mb * wb * wb + mc * wc * wc + md * wd * wd;
	if (!(weighted_mass > 0.0) || !Math::is_finite(weighted_mass)) {
		return false;
	}

	// Relative particle displacements since the previous physics step.
	// Explicit double differences prevent real_t intermediate overflow.
	const double dx =
			wa * (double(r_a.x) - double(p_prev_a.x)) +
			wb * (double(r_b.x) - double(p_prev_b.x)) -
			wc * (double(r_c.x) - double(p_prev_c.x)) -
			wd * (double(r_d.x) - double(p_prev_d.x));
	const double dy =
			wa * (double(r_a.y) - double(p_prev_a.y)) +
			wb * (double(r_b.y) - double(p_prev_b.y)) -
			wc * (double(r_c.y) - double(p_prev_c.y)) -
			wd * (double(r_d.y) - double(p_prev_d.y));
	const double dz =
			wa * (double(r_a.z) - double(p_prev_a.z)) +
			wb * (double(r_b.z) - double(p_prev_b.z)) -
			wc * (double(r_c.z) - double(p_prev_c.z)) -
			wd * (double(r_d.z) - double(p_prev_d.z));
	const double dot_normal = dx * nx + dy * ny + dz * nz;
	const double tx = dx - dot_normal * nx;
	const double ty = dy - dot_normal * ny;
	const double tz = dz - dot_normal * nz;
	const double tangent_len_sq = tx * tx + ty * ty + tz * tz;
	if (!(tangent_len_sq > 0.0) || !Math::is_finite(tangent_len_sq)) {
		return false;
	}

	const double max_impulse = double(p_friction) * double(p_normal_lambda);
	const double scale = MIN(1.0 / weighted_mass, max_impulse / Math::sqrt(tangent_len_sq));
	if (!(scale > 0.0) || !Math::is_finite(scale)) {
		return false;
	}
	const double ix = -tx * scale;
	const double iy = -ty * scale;
	const double iz = -tz * scale;
	const Vector3 next_a(real_t(double(r_a.x) + ma * wa * ix),
			real_t(double(r_a.y) + ma * wa * iy),
			real_t(double(r_a.z) + ma * wa * iz));
	const Vector3 next_b(real_t(double(r_b.x) + mb * wb * ix),
			real_t(double(r_b.y) + mb * wb * iy),
			real_t(double(r_b.z) + mb * wb * iz));
	const Vector3 next_c(real_t(double(r_c.x) - mc * wc * ix),
			real_t(double(r_c.y) - mc * wc * iy),
			real_t(double(r_c.z) - mc * wc * iz));
	const Vector3 next_d(real_t(double(r_d.x) - md * wd * ix),
			real_t(double(r_d.y) - md * wd * iy),
			real_t(double(r_d.z) - md * wd * iz));
	if (!next_a.is_finite() || !next_b.is_finite() ||
			!next_c.is_finite() || !next_d.is_finite()) {
		return false;
	}

	r_a = next_a;
	r_b = next_b;
	r_c = next_c;
	r_d = next_d;
	return true;
}
