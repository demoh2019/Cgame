/**************************************************************************/
/*  physics_fem_tetra_min_jacobian.h                                       */
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

#include "servers/physics_fem_tetra_neo_hookean.h"

#include <limits>

// Current deformation Jacobian J = det(Ds) / det(Dm).
// J=1 at rest, J=0 when flat and J<0 for an inverted tetrahedron.
// The ratio keeps the convention correct for both valid rest windings.
// Evaluation uses double relative positions to avoid float32 cross-product
// overflow from translating/scaling the mesh. Failures leave r_j unchanged.
_FORCE_INLINE_ static bool physics_fem_tetra_deformation_jacobian(
		const Vector3 &p_a, const Vector3 &p_b,
		const Vector3 &p_c, const Vector3 &p_d,
		const PhysicsFEMTetraRest &p_rest, double &r_j) {
	if (!p_a.is_finite() || !p_b.is_finite() ||
			!p_c.is_finite() || !p_d.is_finite() ||
			!Math::is_finite(p_rest.signed_det) ||
			p_rest.signed_det == 0.0) {
		return false;
	}
	const double u[3] = { double(p_b.x) - double(p_a.x),
		double(p_b.y) - double(p_a.y), double(p_b.z) - double(p_a.z) };
	const double v[3] = { double(p_c.x) - double(p_a.x),
		double(p_c.y) - double(p_a.y), double(p_c.z) - double(p_a.z) };
	const double w[3] = { double(p_d.x) - double(p_a.x),
		double(p_d.y) - double(p_a.y), double(p_d.z) - double(p_a.z) };
	const double cross_vw[3] = {
		v[1] * w[2] - v[2] * w[1],
		v[2] * w[0] - v[0] * w[2],
		v[0] * w[1] - v[1] * w[0]
	};
	const double det = u[0] * cross_vw[0] + u[1] * cross_vw[1] + u[2] * cross_vw[2];
	const double j = det / p_rest.signed_det;
	if (!Math::is_finite(j)) {
		return false;
	}
	r_j = j;
	return true;
}

// Unilateral XPBD anti-collapse / inversion-recovery constraint:
//   C(x) = det(Ds)/det(Dm) - minimum_J >= 0
//   lambda >= 0; lambda*C = 0 at the rigid (alpha=0) solution.
//
// Gradients follow directly from the triple-product determinant:
//   grad_b J = cross(c-a,d-a)/det(Dm)
//   grad_c J = cross(d-a,b-a)/det(Dm)
//   grad_d J = cross(b-a,c-a)/det(Dm)
//   grad_a J = -(grad_b+grad_c+grad_d).
//
// This correction remains defined at J=0 and for inverted tets, unlike
// Neo-Hookean log(J), so it can pull a flattened or inverted tet back toward
// valid orientation. When all four positions coincide the gradients vanish;
// that singular case cannot be repaired without an external direction.
// Use a separate nonnegative lambda per tet, reset once each physics step.
// No extra allocation in the hot path. All changes are transactional.
_FORCE_INLINE_ static bool physics_fem_tetra_solve_min_jacobian(
		Vector3 &r_a, Vector3 &r_b, Vector3 &r_c, Vector3 &r_d,
		real_t p_inv_a, real_t p_inv_b, real_t p_inv_c, real_t p_inv_d,
		const PhysicsFEMTetraRest &p_rest, real_t p_minimum_j,
		double p_alpha, double &r_lambda) {
	if (!r_a.is_finite() || !r_b.is_finite() ||
			!r_c.is_finite() || !r_d.is_finite() ||
			!Math::is_finite(p_inv_a) || !Math::is_finite(p_inv_b) ||
			!Math::is_finite(p_inv_c) || !Math::is_finite(p_inv_d) ||
			p_inv_a < 0.0 || p_inv_b < 0.0 ||
			p_inv_c < 0.0 || p_inv_d < 0.0 ||
			!Math::is_finite(p_minimum_j) ||
			!(p_minimum_j > 0.0 && p_minimum_j <= 1.0) ||
			!Math::is_finite(p_alpha) || p_alpha < 0.0 ||
			!Math::is_finite(r_lambda) || r_lambda < 0.0 ||
			!Math::is_finite(p_rest.signed_det) ||
			p_rest.signed_det == 0.0) {
		return false;
	}

	const double inverse_masses[4] = {
		double(p_inv_a), double(p_inv_b), double(p_inv_c), double(p_inv_d)
	};
	if (!(inverse_masses[0] + inverse_masses[1] +
					inverse_masses[2] + inverse_masses[3] > 0.0)) {
		return false;
	}
	double current_j = 0.0;
	if (!physics_fem_tetra_deformation_jacobian(r_a, r_b, r_c, r_d, p_rest, current_j)) {
		return false;
	}
	const double constraint = current_j - double(p_minimum_j);
	if (constraint >= 0.0 && r_lambda == 0.0) {
		return false; // Inactive inequality: no position correction.
	}

	const double u[3] = { double(r_b.x) - double(r_a.x),
		double(r_b.y) - double(r_a.y), double(r_b.z) - double(r_a.z) };
	const double v[3] = { double(r_c.x) - double(r_a.x),
		double(r_c.y) - double(r_a.y), double(r_c.z) - double(r_a.z) };
	const double w[3] = { double(r_d.x) - double(r_a.x),
		double(r_d.y) - double(r_a.y), double(r_d.z) - double(r_a.z) };
	const double inv_rest_det = 1.0 / p_rest.signed_det;
	const double gradients[4][3] = {
		{ 0.0, 0.0, 0.0 },
		{ (v[1] * w[2] - v[2] * w[1]) * inv_rest_det,
			(v[2] * w[0] - v[0] * w[2]) * inv_rest_det,
			(v[0] * w[1] - v[1] * w[0]) * inv_rest_det },
		{ (w[1] * u[2] - w[2] * u[1]) * inv_rest_det,
			(w[2] * u[0] - w[0] * u[2]) * inv_rest_det,
			(w[0] * u[1] - w[1] * u[0]) * inv_rest_det },
		{ (u[1] * v[2] - u[2] * v[1]) * inv_rest_det,
			(u[2] * v[0] - u[0] * v[2]) * inv_rest_det,
			(u[0] * v[1] - u[1] * v[0]) * inv_rest_det }
	};
	double grad[4][3] = {};
	double weighted = 0.0;
	for (int axis = 0; axis < 3; ++axis) {
		grad[1][axis] = gradients[1][axis];
		grad[2][axis] = gradients[2][axis];
		grad[3][axis] = gradients[3][axis];
		grad[0][axis] = -grad[1][axis] - grad[2][axis] - grad[3][axis];
	}
	for (int i = 0; i < 4; ++i) {
		double length_squared = 0.0;
		for (int axis = 0; axis < 3; ++axis) {
			if (!Math::is_finite(grad[i][axis])) {
				return false;
			}
			length_squared += grad[i][axis] * grad[i][axis];
		}
		weighted += inverse_masses[i] * length_squared;
	}
	const double denominator = weighted + p_alpha;
	if (!(weighted > 0.0) || !Math::is_finite(weighted) ||
			!(denominator > 0.0) || !Math::is_finite(denominator)) {
		return false;
	}
	const double unconstrained_delta = -(constraint + p_alpha * r_lambda) / denominator;
	const double next_lambda = MAX(0.0, r_lambda + unconstrained_delta);
	const double delta = next_lambda - r_lambda;
	if (!Math::is_finite(next_lambda) || !Math::is_finite(delta) || delta == 0.0) {
		return false;
	}

	// Limit the step if a huge correction becomes non-finite or makes the
	// unilateral bound worse. In particular, a positive lambda increment
	// must increase the determinant J, even for an inverted starting tet.
	const Vector3 originals[4] = { r_a, r_b, r_c, r_d };
	const double max_component = double(std::numeric_limits<real_t>::max());
	for (int attempt = 0; attempt < 12; ++attempt) {
		const double fraction = 1.0 / double(1u << attempt);
		Vector3 next[4];
		bool valid = true;
		for (int i = 0; i < 4; ++i) {
			for (int axis = 0; axis < 3; ++axis) {
				const double component = double(originals[i][axis]) +
						inverse_masses[i] * delta * fraction * grad[i][axis];
				if (!Math::is_finite(component) || Math::abs(component) > max_component) {
					valid = false;
					break;
				}
				next[i][axis] = real_t(component);
			}
			if (!valid) {
				break;
			}
		}
		if (!valid) {
			continue;
		}
		double candidate_j = 0.0;
		if (!physics_fem_tetra_deformation_jacobian(
					next[0], next[1], next[2], next[3], p_rest, candidate_j)) {
			continue;
		}
		if ((delta > 0.0 && !(candidate_j > current_j)) ||
				(delta < 0.0 && constraint >= 0.0 && candidate_j < double(p_minimum_j))) {
			continue;
		}
		const double accepted_lambda = r_lambda + delta * fraction;
		if (!Math::is_finite(accepted_lambda) || accepted_lambda < 0.0) {
			return false;
		}
		r_a = next[0];
		r_b = next[1];
		r_c = next[2];
		r_d = next[3];
		r_lambda = accepted_lambda;
		return true;
	}
	return false;
}
