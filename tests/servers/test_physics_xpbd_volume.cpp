/**************************************************************************/
/*  test_physics_xpbd_volume.cpp                                          */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_physics_xpbd_volume)

#include "servers/physics_xpbd_volume.h"

namespace TestPhysicsXPBDVolume {

// A positive-winding unit tetrahedron with outward-oriented faces.
static constexpr int FACE[4][3] = {
	{ 0, 2, 1 }, { 0, 1, 3 }, { 0, 3, 2 }, { 1, 2, 3 }
};

static real_t tetra_volume_and_gradients(const Vector3 p[4], Vector3 r_gradients[4]) {
	for (int i = 0; i < 4; ++i) {
		r_gradients[i] = Vector3();
	}
	const Vector3 origin = p[0];
	real_t volume = 0.0;
	for (int f = 0; f < 4; ++f) {
		const int a = FACE[f][0], b = FACE[f][1], c = FACE[f][2];
		Vector3 ga, gb, gc;
		volume += physics_xpbd_triangle_volume_terms(p[a] - origin, p[b] - origin, p[c] - origin, ga, gb, gc);
		r_gradients[a] += ga;
		r_gradients[b] += gb;
		r_gradients[c] += gc;
	}
	return volume;
}

static real_t tetra_volume(const Vector3 p[4]) {
	Vector3 gradients[4];
	return tetra_volume_and_gradients(p, gradients);
}

static bool solve_tetra_volume(Vector3 p[4], const real_t inv_mass[4], real_t rest, real_t alpha, real_t &lambda) {
	Vector3 grad[4];
	const real_t current = tetra_volume_and_gradients(p, grad);
	real_t weighted_norm = 0.0;
	for (int i = 0; i < 4; ++i) {
		weighted_norm += inv_mass[i] * grad[i].length_squared();
	}
	real_t delta_lambda;
	if (!physics_xpbd_volume_delta(current - rest, weighted_norm, alpha, lambda, delta_lambda)) {
		return false;
	}
	for (int i = 0; i < 4; ++i) {
		p[i] += grad[i] * (inv_mass[i] * delta_lambda);
	}
	return true;
}

TEST_CASE("[Physics] XPBD enclosed tetra volume and gradients are translation invariant") {
	Vector3 p[4] = {
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)
	};
	Vector3 gradients[4];
	const real_t volume = tetra_volume_and_gradients(p, gradients);
	CHECK(volume == doctest::Approx(1.0 / 6.0).epsilon(1e-5));
	Vector3 gradient_sum;
	for (const Vector3 &gradient : gradients) {
		gradient_sum += gradient;
	}
	CHECK(gradient_sum.length() < real_t(1e-5));

	Vector3 shifted[4];
	for (int i = 0; i < 4; ++i) {
		shifted[i] = p[i] + Vector3(1000, -2000, 3000);
	}
	CHECK(tetra_volume(shifted) == doctest::Approx(1.0 / 6.0).epsilon(1e-5));

	// The analytical gradient must agree with a finite-difference of V.
	p[3].z += real_t(0.001);
	const real_t finite_difference = (tetra_volume(p) - volume) / real_t(0.001);
	CHECK(finite_difference == doctest::Approx(gradients[3].z).epsilon(0.001));
}

TEST_CASE("[Physics] XPBD soft volume moves movable particles toward rest volume") {
	Vector3 p[4] = {
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 0.5)
	};
	const real_t inv_mass[4] = { 0, 1, 1, 1 }; // First vertex pinned.
	const Vector3 pinned = p[0];
	const real_t rest = real_t(1.0 / 6.0);
	const real_t before = Math::abs(tetra_volume(p) - rest);
	real_t lambda = 0.0;
	for (int iteration = 0; iteration < 8; ++iteration) {
		CHECK(solve_tetra_volume(p, inv_mass, rest, 0.0, lambda));
	}
	CHECK(Math::abs(tetra_volume(p) - rest) < before * real_t(0.05));
	CHECK(p[0] == pinned);
	for (const Vector3 &vertex : p) {
		CHECK(vertex.is_finite());
	}
}

TEST_CASE("[Physics] XPBD volume compliance softens correction and avoids singular pinned meshes") {
	Vector3 p[4] = {
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 0.5)
	};
	Vector3 stiff[4], compliant[4];
	for (int i = 0; i < 4; ++i) {
		stiff[i] = p[i];
		compliant[i] = p[i];
	}
	const real_t inv_mass[4] = { 1, 1, 1, 1 };
	real_t stiff_lambda = 0.0;
	real_t compliant_lambda = 0.0;
	CHECK(solve_tetra_volume(stiff, inv_mass, 1.0 / 6.0, 0.0, stiff_lambda));
	CHECK(solve_tetra_volume(compliant, inv_mass, 1.0 / 6.0, 5.0, compliant_lambda));
	CHECK(Math::abs(tetra_volume(stiff) - real_t(1.0 / 6.0)) <
			Math::abs(tetra_volume(compliant) - real_t(1.0 / 6.0)));

	const real_t fixed_mass[4] = { 0, 0, 0, 0 };
	real_t lambda = 0.0, delta_lambda = 4.0;
	CHECK_FALSE(physics_xpbd_volume_delta(1.0, 0.0, 0.0, lambda, delta_lambda));
	CHECK_FALSE(solve_tetra_volume(p, fixed_mass, 1.0 / 6.0, 0.0, lambda));
	CHECK(lambda == 0.0);
	CHECK(delta_lambda == 4.0);
}

} // namespace TestPhysicsXPBDVolume
