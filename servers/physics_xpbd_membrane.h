/**************************************************************************/
/*  physics_xpbd_membrane.h                                               */
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

#include "core/math/vector3.h"

// Nonlinear St. Venant-Kirchhoff triangle membrane energy (plane stress)
// projected with XPBD. Unlike independent edge / area / shear constraints,
// this couples the full Green-Lagrange strain tensor through Poisson's ratio.
//
// This is a SURFACE membrane, not volumetric/tetrahedral FEM. It has no
// thickness, damage, fracture, contact generation or in-plane bending.
// The user-supplied compliance controls an effective Young-modulus * thickness
// (compliance divided by timestep^2), with the in-plane Poisson ratio
// clamped by the caller to (-1, 0.5). The strain energy is normalized to
// unit Young modulus and integrated over undeformed triangle area.
//
// All buffers are owned by the caller. The hot-path solve allocates nothing.
// Geometry and lambda are stored in double to preserve valid tiny/large
// triangles when Godot uses 32-bit real_t.
struct PhysicsXPBDMembraneRest {
	double inv_u = 0.0; // 1 / |b-a| in undeformed tangent frame.
	double q = 0.0; // -projection(c-a on first tangent) / (|b-a| * height).
	double inv_height = 0.0;
	double area = 0.0; // Zero is the invalid / disabled face sentinel.
};

// Face-local orthonormal rest frame and inverse rest deformation matrix.
// Rejects collapsed/near-collinear rest triangles in a scale-invariant way.
_FORCE_INLINE_ bool physics_xpbd_membrane_make_rest(const Vector3 &p_a,
		const Vector3 &p_b, const Vector3 &p_c,
		PhysicsXPBDMembraneRest &r_rest) {
	if (!p_a.is_finite() || !p_b.is_finite() || !p_c.is_finite()) {
		return false;
	}
	const double ux = double(p_b.x) - double(p_a.x);
	const double uy = double(p_b.y) - double(p_a.y);
	const double uz = double(p_b.z) - double(p_a.z);
	const double vx = double(p_c.x) - double(p_a.x);
	const double vy = double(p_c.y) - double(p_a.y);
	const double vz = double(p_c.z) - double(p_a.z);
	const double u_sq = ux * ux + uy * uy + uz * uz;
	const double v_sq = vx * vx + vy * vy + vz * vz;
	const double cx = uy * vz - uz * vy;
	const double cy = uz * vx - ux * vz;
	const double cz = ux * vy - uy * vx;
	const double cross_sq = cx * cx + cy * cy + cz * cz;
	const double area_scale = u_sq * v_sq;
	if (!(u_sq > 0.0) || !(v_sq > 0.0) || !Math::is_finite(area_scale) ||
			!(cross_sq > area_scale * 1.0e-16) || !Math::is_finite(cross_sq)) {
		return false;
	}
	const double length = Math::sqrt(u_sq);
	const double height = Math::sqrt(cross_sq) / length;
	const double along = (ux * vx + uy * vy + uz * vz) / length;
	PhysicsXPBDMembraneRest rest;
	rest.inv_u = 1.0 / length;
	rest.inv_height = 1.0 / height;
	rest.q = -along * rest.inv_u * rest.inv_height;
	rest.area = 0.5 * length * height;
	if (!(rest.inv_u > 0.0) || !(rest.inv_height > 0.0) || !(rest.area > 0.0) ||
			!Math::is_finite(rest.inv_u) || !Math::is_finite(rest.inv_height) ||
			!Math::is_finite(rest.q) || !Math::is_finite(rest.area)) {
		return false;
	}
	r_rest = rest;
	return true;
}

// Energy and its exact analytic vertex gradients. The reference membrane
// energy is W = mu * (E:E) + lambda/2 * trace(E)^2, integrated over rest area,
// E = (F^T F - I)/2. For plane stress, mu=1/(2*(1+nu)) and
// lambda=nu/(1-nu^2), with Young modulus factored into XPBD compliance.
// Returns false atomically for invalid inputs, including nonfinite strain.
_FORCE_INLINE_ bool physics_xpbd_membrane_energy_gradient(
		const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c,
		const PhysicsXPBDMembraneRest &p_rest, double p_poisson,
		double &r_energy, Vector3 &r_grad_a, Vector3 &r_grad_b, Vector3 &r_grad_c) {
	if (!p_a.is_finite() || !p_b.is_finite() || !p_c.is_finite() ||
			!(p_rest.inv_u > 0.0) || !(p_rest.inv_height > 0.0) || !(p_rest.area > 0.0) ||
			!Math::is_finite(p_rest.inv_u) || !Math::is_finite(p_rest.inv_height) ||
			!Math::is_finite(p_rest.q) || !Math::is_finite(p_rest.area) ||
			!Math::is_finite(p_poisson) || p_poisson < -0.49 || p_poisson > 0.49) {
		return false;
	}

	const double ab[3] = {
		double(p_b.x) - double(p_a.x),
		double(p_b.y) - double(p_a.y),
		double(p_b.z) - double(p_a.z)
	};
	const double ac[3] = {
		double(p_c.x) - double(p_a.x),
		double(p_c.y) - double(p_a.y),
		double(p_c.z) - double(p_a.z)
	};
	double f0[3], f1[3];
	double f00 = 0.0, f11 = 0.0, f01 = 0.0;
	for (int i = 0; i < 3; ++i) {
		f0[i] = p_rest.inv_u * ab[i];
		f1[i] = p_rest.q * ab[i] + p_rest.inv_height * ac[i];
		f00 += f0[i] * f0[i];
		f11 += f1[i] * f1[i];
		f01 += f0[i] * f1[i];
	}
	const double e00 = 0.5 * (f00 - 1.0);
	const double e11 = 0.5 * (f11 - 1.0);
	const double e01 = 0.5 * f01;
	const double trace = e00 + e11;
	const double mu = 0.5 / (1.0 + p_poisson);
	const double lambda = p_poisson / (1.0 - p_poisson * p_poisson);
	const double energy = p_rest.area * (mu * (e00 * e00 + e11 * e11 + 2.0 * e01 * e01) +
			0.5 * lambda * trace * trace);
	if (!(energy >= 0.0) || !Math::is_finite(energy)) {
		return false;
	}

	// dW/dF = F * (lambda * trace(E) * I + 2*mu*E). Apply the
	// constant rest deformation matrix to obtain nodal gradients.
	const double s00 = lambda * trace + 2.0 * mu * e00;
	const double s11 = lambda * trace + 2.0 * mu * e11;
	const double s01 = 2.0 * mu * e01;
	double ga[3], gb[3], gc[3];
	for (int i = 0; i < 3; ++i) {
		const double p0 = f0[i] * s00 + f1[i] * s01;
		const double p1 = f0[i] * s01 + f1[i] * s11;
		gb[i] = p_rest.area * (p_rest.inv_u * p0 + p_rest.q * p1);
		gc[i] = p_rest.area * p_rest.inv_height * p1;
		ga[i] = -gb[i] - gc[i];
		if (!Math::is_finite(ga[i]) || !Math::is_finite(gb[i]) ||
				!Math::is_finite(gc[i])) {
			return false;
		}
	}
	const Vector3 grad_a{ real_t(ga[0]), real_t(ga[1]), real_t(ga[2]) };
	const Vector3 grad_b{ real_t(gb[0]), real_t(gb[1]), real_t(gb[2]) };
	const Vector3 grad_c{ real_t(gc[0]), real_t(gc[1]), real_t(gc[2]) };
	if (!grad_a.is_finite() || !grad_b.is_finite() || !grad_c.is_finite()) {
		return false;
	}
	r_energy = energy;
	r_grad_a = grad_a;
	r_grad_b = grad_b;
	r_grad_c = grad_c;
	return true;
}

// Projects C = sqrt(2 * energy) to zero using a single scalar XPBD lambda.
// The effective alpha is compliance / dt^2. Pinning is exact (inverse mass
// zero). Positions/lambda are validated and committed only after all
// intermediate computations succeed.
_FORCE_INLINE_ bool physics_xpbd_membrane_solve(
		Vector3 &r_a, Vector3 &r_b, Vector3 &r_c,
		real_t p_inv_a, real_t p_inv_b, real_t p_inv_c,
		const PhysicsXPBDMembraneRest &p_rest, double p_poisson,
		double p_alpha, double &r_lambda) {
	if (!Math::is_finite(p_inv_a) || !Math::is_finite(p_inv_b) ||
			!Math::is_finite(p_inv_c) || p_inv_a < 0.0 ||
			p_inv_b < 0.0 || p_inv_c < 0.0 ||
			!Math::is_finite(p_alpha) || p_alpha < 0.0 ||
			!Math::is_finite(r_lambda)) {
		return false;
	}
	const double inv[3] = { double(p_inv_a), double(p_inv_b), double(p_inv_c) };
	if (!(inv[0] + inv[1] + inv[2] > 0.0)) {
		return false;
	}
	double energy = 0.0;
	Vector3 ga, gb, gc;
	if (!physics_xpbd_membrane_energy_gradient(r_a, r_b, r_c, p_rest,
				p_poisson, energy, ga, gb, gc) || !(energy > 0.0)) {
		return false;
	}
	const double c = Math::sqrt(2.0 * energy);
	if (!(c > 0.0) || !Math::is_finite(c)) {
		return false;
	}
	const double grad[3][3] = {
		{ double(ga.x) / c, double(ga.y) / c, double(ga.z) / c },
		{ double(gb.x) / c, double(gb.y) / c, double(gb.z) / c },
		{ double(gc.x) / c, double(gc.y) / c, double(gc.z) / c }
	};
	double weighted = 0.0;
	for (int vertex = 0; vertex < 3; ++vertex) {
		for (int axis = 0; axis < 3; ++axis) {
			weighted += inv[vertex] * grad[vertex][axis] * grad[vertex][axis];
		}
	}
	const double denom = weighted + p_alpha;
	if (!(weighted > 0.0) || !Math::is_finite(weighted) ||
			!(denom > 0.0) || !Math::is_finite(denom)) {
		return false;
	}
	const double delta_lambda = -(c + p_alpha * r_lambda) / denom;
	const double next_lambda = r_lambda + delta_lambda;
	if (!Math::is_finite(delta_lambda) || !Math::is_finite(next_lambda)) {
		return false;
	}

	const Vector3 next_a{
		real_t(double(r_a.x) + inv[0] * delta_lambda * grad[0][0]),
		real_t(double(r_a.y) + inv[0] * delta_lambda * grad[0][1]),
		real_t(double(r_a.z) + inv[0] * delta_lambda * grad[0][2])
	};
	const Vector3 next_b{
		real_t(double(r_b.x) + inv[1] * delta_lambda * grad[1][0]),
		real_t(double(r_b.y) + inv[1] * delta_lambda * grad[1][1]),
		real_t(double(r_b.z) + inv[1] * delta_lambda * grad[1][2])
	};
	const Vector3 next_c{
		real_t(double(r_c.x) + inv[2] * delta_lambda * grad[2][0]),
		real_t(double(r_c.y) + inv[2] * delta_lambda * grad[2][1]),
		real_t(double(r_c.z) + inv[2] * delta_lambda * grad[2][2])
	};
	if (!next_a.is_finite() || !next_b.is_finite() || !next_c.is_finite()) {
		return false;
	}
	r_a = next_a;
	r_b = next_b;
	r_c = next_c;
	r_lambda = next_lambda;
	return true;
}
