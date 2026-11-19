/**************************************************************************/
/*  test_physics_fem_tetra_min_jacobian.cpp                                */
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

#include "servers/physics_fem_tetra_min_jacobian.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_fem_tetra_min_jacobian)

namespace TestPhysicsFEMTetraMinJacobian {

static const Vector3 base_a, base_b(1, 0, 0), base_c(0, 1, 0), base_d(0, 0, 1);

static PhysicsFEMTetraRest rest_tetra() {
	PhysicsFEMTetraRest rest;
	CHECK(physics_fem_tetra_make_rest(base_a, base_b, base_c, base_d, rest));
	return rest;
}

static double jacobian(const Vector3 &a, const Vector3 &b, const Vector3 &c,
		const Vector3 &d, const PhysicsFEMTetraRest &rest) {
	double result = -999;
	CHECK(physics_fem_tetra_deformation_jacobian(a, b, c, d, rest, result));
	return result;
}

TEST_CASE("[PhysicsFEMMinJ] Rest shape has unit deformation Jacobian") {
	const PhysicsFEMTetraRest rest = rest_tetra();
	CHECK(jacobian(base_a, base_b, base_c, base_d, rest) == doctest::Approx(1.0));
}

TEST_CASE("[PhysicsFEMMinJ] Flat tetra has zero Jacobian") {
	const PhysicsFEMTetraRest rest = rest_tetra();
	CHECK(jacobian(base_a, base_b, base_c, Vector3(0, 0, 0), rest) == doctest::Approx(0.0));
}

TEST_CASE("[PhysicsFEMMinJ] Inverted tetra has negative signed Jacobian") {
	const PhysicsFEMTetraRest rest = rest_tetra();
	CHECK(jacobian(base_a, base_b, base_c, Vector3(0, 0, -0.25), rest) == doctest::Approx(-0.25));
}

TEST_CASE("[PhysicsFEMMinJ] Fully flat element is recovered by a single pin-aware projection") {
	const PhysicsFEMTetraRest rest = rest_tetra();
	Vector3 a = base_a, b = base_b, c = base_c, d;
	double lambda = 0.0;
	CHECK(physics_fem_tetra_solve_min_jacobian(a, b, c, d,
			0, 0, 0, 1, rest, real_t(0.2), 0.0, lambda));
	CHECK(a == base_a);
	CHECK(b == base_b);
	CHECK(c == base_c);
	CHECK(d.z == doctest::Approx(0.2).epsilon(1e-5));
	CHECK(jacobian(a, b, c, d, rest) == doctest::Approx(0.2).epsilon(1e-5));
	CHECK(lambda > 0.0);
}

TEST_CASE("[PhysicsFEMMinJ] Inverted element recovers orientation without Neo-Hookean log") {
	const PhysicsFEMTetraRest rest = rest_tetra();
	Vector3 a = base_a, b = base_b, c = base_c, d(0, 0, -0.3);
	double energy = 0.0;
	Vector3 ga, gb, gc, gd;
	CHECK_FALSE(physics_fem_tetra_energy_gradient(a, b, c, d, rest,
			0.3, energy, ga, gb, gc, gd));
	double lambda = 0.0;
	CHECK(physics_fem_tetra_solve_min_jacobian(a, b, c, d,
			0, 0, 0, 1, rest, real_t(0.2), 0.0, lambda));
	CHECK(jacobian(a, b, c, d, rest) == doctest::Approx(0.2).epsilon(1e-5));
	CHECK(physics_fem_tetra_energy_gradient(a, b, c, d, rest,
			0.3, energy, ga, gb, gc, gd));
	CHECK(energy > 0.0);
}

TEST_CASE("[PhysicsFEMMinJ] Valid volume is inactive and no lambda is added") {
	const PhysicsFEMTetraRest rest = rest_tetra();
	Vector3 a = base_a, b = base_b, c = base_c, d = base_d;
	double lambda = 0.0;
	CHECK_FALSE(physics_fem_tetra_solve_min_jacobian(a, b, c, d,
			1, 1, 1, 1, rest, real_t(0.4), 0.0, lambda));
	CHECK(lambda == 0.0);
	CHECK(a == base_a);
	CHECK(b == base_b);
	CHECK(c == base_c);
	CHECK(d == base_d);
}

TEST_CASE("[PhysicsFEMMinJ] Compliant barrier is softer than hard barrier") {
	const PhysicsFEMTetraRest rest = rest_tetra();
	Vector3 a = base_a, b = base_b, c = base_c;
	Vector3 hard(0, 0, real_t(0.1)), soft = hard;
	double hard_lambda = 0.0, soft_lambda = 0.0;
	CHECK(physics_fem_tetra_solve_min_jacobian(a, b, c, hard,
			0, 0, 0, 1, rest, real_t(0.5), 0.0, hard_lambda));
	CHECK(physics_fem_tetra_solve_min_jacobian(a, b, c, soft,
			0, 0, 0, 1, rest, real_t(0.5), 1.0, soft_lambda));
	CHECK(hard.z > soft.z);
	CHECK(soft.z > real_t(0.1));
	CHECK(hard_lambda > soft_lambda);
}

TEST_CASE("[PhysicsFEMMinJ] All four pinned vertices remain unchanged") {
	const PhysicsFEMTetraRest rest = rest_tetra();
	Vector3 a = base_a, b = base_b, c = base_c, d(0, 0, -1);
	const Vector3 initial = d;
	double lambda = 0.0;
	CHECK_FALSE(physics_fem_tetra_solve_min_jacobian(a, b, c, d,
			0, 0, 0, 0, rest, real_t(0.2), 0.0, lambda));
	CHECK(d == initial);
	CHECK(lambda == 0.0);
}

TEST_CASE("[PhysicsFEMMinJ] Releasing a stored unilateral lambda cannot pull volume below bound") {
	const PhysicsFEMTetraRest rest = rest_tetra();
	Vector3 a = base_a, b = base_b, c = base_c, d(0, 0, real_t(1.2));
	double lambda = 0.01;
	CHECK(physics_fem_tetra_solve_min_jacobian(a, b, c, d,
			0, 0, 0, 1, rest, real_t(0.3), 0.0, lambda));
	CHECK(lambda >= 0.0);
	CHECK(lambda < 0.01);
	CHECK(jacobian(a, b, c, d, rest) >= 0.3);
}

TEST_CASE("[PhysicsFEMMinJ] Negative winding rest tetra has same recovery law") {
	PhysicsFEMTetraRest rest;
	CHECK(physics_fem_tetra_make_rest(base_a, base_c, base_b, base_d, rest));
	CHECK(rest.signed_det < 0);
	Vector3 a = base_a, b = base_c, c = base_b, d(0, 0, -0.4);
	CHECK(jacobian(a, b, c, d, rest) == doctest::Approx(-0.4));
	double lambda = 0.0;
	CHECK(physics_fem_tetra_solve_min_jacobian(a, b, c, d,
			0, 0, 0, 1, rest, real_t(0.25), 0.0, lambda));
	CHECK(jacobian(a, b, c, d, rest) == doctest::Approx(0.25).epsilon(1e-5));
}

TEST_CASE("[PhysicsFEMMinJ] Rigid translations do not change volume ratio") {
	const PhysicsFEMTetraRest rest = rest_tetra();
	const Vector3 translation(1000, -2000, 500);
	const double shifted = jacobian(base_a + translation,
			base_b + translation, base_c + translation,
			Vector3(0, 0, real_t(0.6)) + translation, rest);
	CHECK(shifted == doctest::Approx(0.6).epsilon(1e-5));
}

TEST_CASE("[PhysicsFEMMinJ] Rigid rotations preserve J") {
	const PhysicsFEMTetraRest rest = rest_tetra();
	// Proper rotation around Z by +90 degrees.
	const Vector3 a, b(0, 1, 0), c(-1, 0, 0), d(0, 0, real_t(0.7));
	CHECK(jacobian(a, b, c, d, rest) == doctest::Approx(0.7).epsilon(1e-5));
}

TEST_CASE("[PhysicsFEMMinJ] Microscopic tetrahedron can be recovered") {
	const real_t s = real_t(0.0001);
	PhysicsFEMTetraRest rest;
	CHECK(physics_fem_tetra_make_rest(base_a * s, base_b * s,
			base_c * s, base_d * s, rest));
	Vector3 a = base_a * s, b = base_b * s, c = base_c * s;
	Vector3 d(0, 0, real_t(-0.25) * s);
	double lambda = 0.0;
	CHECK(physics_fem_tetra_solve_min_jacobian(a, b, c, d,
			0, 0, 0, 1, rest, real_t(0.2), 0.0, lambda));
	CHECK(jacobian(a, b, c, d, rest) == doctest::Approx(0.2).epsilon(1e-4));
}

TEST_CASE("[PhysicsFEMMinJ] Fully coincident points have no recovery gradient") {
	const PhysicsFEMTetraRest rest = rest_tetra();
	Vector3 a, b, c, d;
	double lambda = 0.0;
	CHECK_FALSE(physics_fem_tetra_solve_min_jacobian(a, b, c, d,
			1, 1, 1, 1, rest, real_t(0.2), 0.0, lambda));
	CHECK(a == Vector3());
	CHECK(b == Vector3());
	CHECK(c == Vector3());
	CHECK(d == Vector3());
	CHECK(lambda == 0.0);
}

TEST_CASE("[PhysicsFEMMinJ] Invalid bounds and nonfinite inputs are atomic") {
	const PhysicsFEMTetraRest rest = rest_tetra();
	Vector3 a = base_a, b = base_b, c = base_c, d(0, 0, -1);
	const Vector3 initial = d;
	double lambda = 1.0;
	const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
	const real_t inf = std::numeric_limits<real_t>::infinity();
	CHECK_FALSE(physics_fem_tetra_solve_min_jacobian(a, b, c, d,
			0, 0, 0, 1, rest, 0, 0.0, lambda));
	CHECK_FALSE(physics_fem_tetra_solve_min_jacobian(a, b, c, d,
			0, 0, 0, 1, rest, real_t(1.1), 0.0, lambda));
	CHECK_FALSE(physics_fem_tetra_solve_min_jacobian(a, b, c, d,
			0, 0, 0, 1, rest, real_t(0.3), -1.0, lambda));
	double bad_lambda = std::numeric_limits<double>::quiet_NaN();
	CHECK_FALSE(physics_fem_tetra_solve_min_jacobian(a, b, c, d,
			0, 0, 0, 1, rest, real_t(0.3), 0.0, bad_lambda));
	CHECK(Math::is_nan(bad_lambda));
	CHECK_FALSE(physics_fem_tetra_solve_min_jacobian(a, b, c, d,
			0, 0, 0, inf, rest, real_t(0.3), 0.0, lambda));
	CHECK_FALSE(physics_fem_tetra_solve_min_jacobian(a, b, c, d,
			0, 0, 0, 1, rest, nan, 0.0, lambda));
	CHECK(d == initial);
	CHECK(lambda == 1.0);
}

} // namespace TestPhysicsFEMTetraMinJacobian
