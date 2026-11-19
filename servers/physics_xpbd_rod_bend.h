/**************************************************************************/
/*  physics_xpbd_rod_bend.h                                               */
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

#include "core/math/math_funcs.h"
#include "core/math/vector3.h"

#include <limits>

// Rotationally invariant three-point CENTERLINE bend for a discrete elastic
// rod. The bend is theta = atan2(|t0 x t1|, -t0.t1), where t0/t1 run from
// the middle particle to its neighbors. A straight segment has theta=0.
// Unlike a two-hop distance link this constrains the ANGLE independently of
// the lengths of either segment, and supports pre-curved undeformed chains.
//
// This is a translational-only discrete rod BENDING model, not a full
// Cosserat rod: there are no independent segment quaternions, torsional
// rotations, material-frame directors, or bend-twist coupling. These require
// additional rotational DOFs. Caller retains lambda only within one XPBD
// time step and uses compliance/dt^2 for p_alpha.
_FORCE_INLINE_ static bool physics_xpbd_rod_bend_angle(
		const Vector3 &p_a, const Vector3 &p_middle, const Vector3 &p_c,
		real_t &r_angle) {
	if (!p_a.is_finite() || !p_middle.is_finite() || !p_c.is_finite()) {
		return false;
	}
	const double u[3] = {
		double(p_a.x) - double(p_middle.x),
		double(p_a.y) - double(p_middle.y),
		double(p_a.z) - double(p_middle.z),
	};
	const double v[3] = {
		double(p_c.x) - double(p_middle.x),
		double(p_c.y) - double(p_middle.y),
		double(p_c.z) - double(p_middle.z),
	};
	const double u_sq = u[0] * u[0] + u[1] * u[1] + u[2] * u[2];
	const double v_sq = v[0] * v[0] + v[1] * v[1] + v[2] * v[2];
	if (!(u_sq > 1e-24) || !(v_sq > 1e-24) ||
			!Math::is_finite(u_sq) || !Math::is_finite(v_sq)) {
		return false;
	}
	const double lu = Math::sqrt(u_sq);
	const double lv = Math::sqrt(v_sq);
	const double nu[3] = { u[0] / lu, u[1] / lu, u[2] / lu };
	const double nv[3] = { v[0] / lv, v[1] / lv, v[2] / lv };
	const double cosine = CLAMP(nu[0] * nv[0] + nu[1] * nv[1] + nu[2] * nv[2], -1.0, 1.0);
	const double cross[3] = {
		nu[1] * nv[2] - nu[2] * nv[1],
		nu[2] * nv[0] - nu[0] * nv[2],
		nu[0] * nv[1] - nu[1] * nv[0],
	};
	const double sine = Math::sqrt(cross[0] * cross[0] + cross[1] * cross[1] + cross[2] * cross[2]);
	const double theta = Math::atan2(sine, -cosine);
	if (!Math::is_finite(theta) || theta < 0.0 || theta > Math::PI) {
		return false;
	}
	r_angle = real_t(theta);
	return Math::is_finite(r_angle);
}

// XPBD angular projection using analytical gradients of bend angle.
// dtheta/du = (v_hat - dot(u_hat,v_hat) u_hat)/(length(u)*sin(phi)),
// dtheta/dv is symmetric, and middle gradient = -sum(end gradients).
// Corrections preserve linear momentum for equal/mass-weighted movable
// particles. Pinned inverse-mass-zero nodes are never modified.
// Nonfinite inputs, collinear degenerate gradients, or overflowing
// corrections abort transactionally without partially modifying vertices.
_FORCE_INLINE_ static bool physics_xpbd_solve_rod_bend(
		Vector3 &r_a, Vector3 &r_middle, Vector3 &r_c,
		real_t p_inv_a, real_t p_inv_middle, real_t p_inv_c,
		real_t p_rest_angle, real_t p_alpha, real_t &r_lambda) {
	if (!r_a.is_finite() || !r_middle.is_finite() || !r_c.is_finite() ||
			!Math::is_finite(p_inv_a) || !Math::is_finite(p_inv_middle) ||
			!Math::is_finite(p_inv_c) ||
			p_inv_a < 0.0 || p_inv_middle < 0.0 || p_inv_c < 0.0 ||
			!Math::is_finite(p_rest_angle) ||
			p_rest_angle < real_t(0.0) || p_rest_angle > real_t(Math::PI) ||
			!Math::is_finite(p_alpha) || p_alpha < real_t(0.0) ||
			!Math::is_finite(r_lambda)) {
		return false;
	}
	real_t theta = 0.0;
	if (!physics_xpbd_rod_bend_angle(r_a, r_middle, r_c, theta)) {
		return false;
	}
	const double residual = double(theta) - double(p_rest_angle);
	// An exactly straight rod does not have a defined bending plane, but
	// its zero-rest-angle configuration already satisfies the constraint.
	if (Math::abs(residual) < 1e-12 && r_lambda == real_t(0.0)) {
		return true;
	}

	const double u[3] = {
		double(r_a.x) - double(r_middle.x),
		double(r_a.y) - double(r_middle.y),
		double(r_a.z) - double(r_middle.z),
	};
	const double v[3] = {
		double(r_c.x) - double(r_middle.x),
		double(r_c.y) - double(r_middle.y),
		double(r_c.z) - double(r_middle.z),
	};
	const double lu = Math::sqrt(u[0] * u[0] + u[1] * u[1] + u[2] * u[2]);
	const double lv = Math::sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
	const double nu[3] = { u[0] / lu, u[1] / lu, u[2] / lu };
	const double nv[3] = { v[0] / lv, v[1] / lv, v[2] / lv };
	const double cosine = CLAMP(nu[0] * nv[0] + nu[1] * nv[1] + nu[2] * nv[2], -1.0, 1.0);
	const double cross[3] = {
		nu[1] * nv[2] - nu[2] * nv[1],
		nu[2] * nv[0] - nu[0] * nv[2],
		nu[0] * nv[1] - nu[1] * nv[0],
	};
	const double sine = Math::sqrt(cross[0] * cross[0] + cross[1] * cross[1] + cross[2] * cross[2]);
	if (!(sine > 1e-9) || !Math::is_finite(sine)) {
		// No unique bending plane exactly at theta=0 or theta=PI.
		return Math::abs(residual) < 1e-8 && r_lambda == real_t(0.0);
	}
	double grad[3][3];
	for (int k = 0; k < 3; ++k) {
		grad[0][k] = (nv[k] - cosine * nu[k]) / (lu * sine);
		grad[2][k] = (nu[k] - cosine * nv[k]) / (lv * sine);
		grad[1][k] = -(grad[0][k] + grad[2][k]);
	}
	const double w[3] = { double(p_inv_a), double(p_inv_middle), double(p_inv_c) };
	double effective_mass = 0.0;
	for (int i = 0; i < 3; ++i) {
		for (int j = 0; j < 3; ++j) {
			if (!Math::is_finite(grad[i][j])) {
				return false;
			}
			effective_mass += w[i] * grad[i][j] * grad[i][j];
		}
	}
	const double denominator = effective_mass + double(p_alpha);
	if (!(effective_mass > 0.0) || !Math::is_finite(effective_mass) ||
			!(denominator > 0.0) || !Math::is_finite(denominator)) {
		return false;
	}
	const double delta_lambda = -(residual + double(p_alpha) * double(r_lambda)) / denominator;
	const double next_lambda = double(r_lambda) + delta_lambda;
	if (!Math::is_finite(delta_lambda) || !Math::is_finite(next_lambda) ||
			Math::abs(next_lambda) > double(std::numeric_limits<real_t>::max())) {
		return false;
	}
	const Vector3 original[3] = { r_a, r_middle, r_c };
	Vector3 updated[3];
	for (int i = 0; i < 3; ++i) {
		if (w[i] == 0.0) {
			updated[i] = original[i];
			continue;
		}
		const double next[3] = {
			double(original[i].x) + w[i] * grad[i][0] * delta_lambda,
			double(original[i].y) + w[i] * grad[i][1] * delta_lambda,
			double(original[i].z) + w[i] * grad[i][2] * delta_lambda,
		};
		if (!Math::is_finite(next[0]) || !Math::is_finite(next[1]) || !Math::is_finite(next[2]) ||
				Math::abs(next[0]) > double(std::numeric_limits<real_t>::max()) ||
				Math::abs(next[1]) > double(std::numeric_limits<real_t>::max()) ||
				Math::abs(next[2]) > double(std::numeric_limits<real_t>::max())) {
			return false;
		}
		updated[i] = Vector3(real_t(next[0]), real_t(next[1]), real_t(next[2]));
		if (!updated[i].is_finite()) {
			return false;
		}
	}
	r_a = updated[0];
	r_middle = updated[1];
	r_c = updated[2];
	r_lambda = real_t(next_lambda);
	return true;
}
