/**************************************************************************/
/*  test_physics_fem_tetra_principal_limits.cpp                                       */
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

#include "servers/physics_fem_tetra_principal_limits.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_physics_fem_tetra_principal_limits)

namespace TestPhysicsFEMTetraPrincipalLimits {

static PhysicsFEMTetraRest rest() {
	PhysicsFEMTetraRest r;
	CHECK(physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), r));
	return r;
}

static bool spectrum(const Vector3 (&x)[4], const PhysicsFEMTetraRest &r,
		double (&sigmas)[3]) {
	double axes[3][3], f[3][3];
	return physics_fem_tetra_principal_spectrum(x, r, sigmas, axes, f);
}

static double constraint(const Vector3 (&x)[4], const PhysicsFEMTetraRest &r,
		bool lower, double bound) {
	double value = 1234;
	Vector3 grad[4];
	CHECK(physics_fem_tetra_principal_constraint(x, r, lower, bound, value, grad));
	return value;
}

TEST_CASE("[PhysicsFEM] Principal rest stretches are all one") {
	const Vector3 x[4] = { Vector3(), Vector3(1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, 0, 1) };
	double sigmas[3];
	CHECK(spectrum(x, rest(), sigmas));
	for (double s : sigmas) {
		CHECK(s == doctest::Approx(1.0));
	}
}

TEST_CASE("[PhysicsFEM] Principal stretches ignore rigid rotation and translation") {
	const Vector3 x[4] = { Vector3(9, 3, 4), Vector3(9, 4, 4),
		Vector3(8, 3, 4), Vector3(9, 3, 5) };
	double sigmas[3];
	CHECK(spectrum(x, rest(), sigmas));
	for (double s : sigmas) {
		CHECK(s == doctest::Approx(1.0));
	}
}

TEST_CASE("[PhysicsFEM] Principal stretches are ordered by magnitude") {
	const Vector3 x[4] = { Vector3(), Vector3(real_t(1.5), 0, 0),
		Vector3(0, real_t(0.75), 0), Vector3(0, 0, real_t(1.2)) };
	double sigmas[3];
	CHECK(spectrum(x, rest(), sigmas));
	CHECK(sigmas[0] == doctest::Approx(0.75).epsilon(1e-5));
	CHECK(sigmas[1] == doctest::Approx(1.2).epsilon(1e-5));
	CHECK(sigmas[2] == doctest::Approx(1.5).epsilon(1e-5));
}

TEST_CASE("[PhysicsFEM] Maximum-stretch cap shortens an elongated tetra") {
	const PhysicsFEMTetraRest r = rest();
	Vector3 a, b(real_t(1.7), 0, 0), c(0, 1, 0), d(0, 0, 1);
	double lambda = 0.0;
	const double before = b.x;
	CHECK(physics_fem_tetra_principal_solve(a, b, c, d, 0, 1, 0, 0,
			r, false, 1.25, 0.0, lambda));
	CHECK(b.x < before);
	CHECK(b.x > real_t(0.0));
	CHECK(lambda < 0.0);
}

TEST_CASE("[PhysicsFEM] Minimum-stretch cap expands a compressed tetra") {
	const PhysicsFEMTetraRest r = rest();
	Vector3 a, b(real_t(0.5), 0, 0), c(0, 1, 0), d(0, 0, 1);
	double lambda = 0.0;
	CHECK(physics_fem_tetra_principal_solve(a, b, c, d, 0, 1, 0, 0,
			r, true, 0.8, 0.0, lambda));
	CHECK(b.x > real_t(0.5));
	CHECK(lambda < 0.0);
}

TEST_CASE("[PhysicsFEM] Shear changes both principal stretch extremes") {
	const Vector3 x[4] = { Vector3(), Vector3(1, 0, 0),
		Vector3(real_t(0.6), 1, 0), Vector3(0, 0, 1) };
	double s[3];
	CHECK(spectrum(x, rest(), s));
	CHECK(s[0] < 1.0);
	CHECK(s[2] > 1.0);
	CHECK(constraint(x, rest(), true, 0.9) > 0.0);
	CHECK(constraint(x, rest(), false, 1.1) > 0.0);
}

TEST_CASE("[PhysicsFEM] Principal upper cap respects pinned particles") {
	Vector3 a, b(real_t(1.6), 0, 0), c(0, 1, 0), d(0, 0, 1);
	double lambda = 0.0;
	CHECK(physics_fem_tetra_principal_solve(a, b, c, d, 0, 1, 0, 0,
			rest(), false, 1.2, 0.001, lambda));
	CHECK(a == Vector3());
	CHECK(c == Vector3(0, 1, 0));
	CHECK(d == Vector3(0, 0, 1));
	CHECK(b.x < real_t(1.6));
}

TEST_CASE("[PhysicsFEM] Principal solver cannot move all pinned tetra") {
	Vector3 a, b(real_t(1.6), 0, 0), c(0, 1, 0), d(0, 0, 1);
	double lambda = 0.0;
	CHECK_FALSE(physics_fem_tetra_principal_solve(a, b, c, d, 0, 0, 0, 0,
			rest(), false, 1.2, 0.0, lambda));
	CHECK(b == Vector3(real_t(1.6), 0, 0));
	CHECK(lambda == 0.0);
}

TEST_CASE("[PhysicsFEM] Principal gradient agrees with finite differences") {
	const PhysicsFEMTetraRest r = rest();
	const Vector3 x[4] = { Vector3(), Vector3(real_t(1.3), real_t(0.15), 0),
		Vector3(real_t(0.2), real_t(0.85), 0), Vector3(0, 0, real_t(1.1)) };
	double value = 0.0;
	Vector3 grad[4];
	CHECK(physics_fem_tetra_principal_constraint(x, r, false, 1.1, value, grad));
	const real_t eps = real_t(0.0005);
	const Vector3 xp[4] = { x[0], Vector3(x[1].x + eps, x[1].y, x[1].z), x[2], x[3] };
	const Vector3 xm[4] = { x[0], Vector3(x[1].x - eps, x[1].y, x[1].z), x[2], x[3] };
	const double numeric = (constraint(xp, r, false, 1.1) -
			constraint(xm, r, false, 1.1)) / (2.0 * double(eps));
	CHECK(double(grad[1].x) == doctest::Approx(numeric).epsilon(0.005));
	CHECK((grad[0] + grad[1] + grad[2] + grad[3]).length() < real_t(1e-5));
}

TEST_CASE("[PhysicsFEM] Negative rest winding preserves exact stretches") {
	PhysicsFEMTetraRest r;
	CHECK(physics_fem_tetra_make_rest(Vector3(), Vector3(0, 1, 0),
			Vector3(1, 0, 0), Vector3(0, 0, 1), r));
	const Vector3 x[4] = { Vector3(), Vector3(0, real_t(1.5), 0),
		Vector3(1, 0, 0), Vector3(0, 0, 1) };
	double s[3];
	CHECK(spectrum(x, r, s));
	CHECK(s[0] == doctest::Approx(1.0));
	CHECK(s[2] == doctest::Approx(1.5).epsilon(1e-5));
}

TEST_CASE("[PhysicsFEM] Inverted tetra is rejected without changing outputs") {
	const Vector3 x[4] = { Vector3(), Vector3(1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, 0, -1) };
	double violation = 42.0;
	Vector3 grad[4];
	CHECK_FALSE(physics_fem_tetra_principal_constraint(x, rest(), false,
			1.2, violation, grad));
	CHECK(violation == 42.0);
}

TEST_CASE("[PhysicsFEM] Compliance makes principal caps less rigid") {
	Vector3 a, b(real_t(1.6), 0, 0), c(0, 1, 0), d(0, 0, 1);
	Vector3 soft_a = a, soft_b = b, soft_c = c, soft_d = d;
	double lambda0 = 0.0, lambda1 = 0.0;
	CHECK(physics_fem_tetra_principal_solve(a, b, c, d, 0, 1, 0, 0,
			rest(), false, 1.2, 0.0, lambda0));
	CHECK(physics_fem_tetra_principal_solve(soft_a, soft_b, soft_c, soft_d,
			0, 1, 0, 0, rest(), false, 1.2, 1.0, lambda1));
	CHECK(soft_b.x > b.x);
}

TEST_CASE("[PhysicsFEM] Invalid caps and inverse masses are rejected") {
	Vector3 a, b(real_t(1.6), 0, 0), c(0, 1, 0), d(0, 0, 1);
	double lambda = 0.0;
	CHECK_FALSE(physics_fem_tetra_principal_solve(a, b, c, d, -1, 1, 0, 0,
			rest(), false, 1.2, 0.0, lambda));
	CHECK_FALSE(physics_fem_tetra_principal_solve(a, b, c, d, 0, 1, 0, 0,
			rest(), false, 0.6, 0.0, lambda));
	CHECK_FALSE(physics_fem_tetra_principal_solve(a, b, c, d, 0, 1, 0, 0,
			rest(), true, 1.2, 0.0, lambda));
	CHECK_FALSE(physics_fem_tetra_principal_solve(a, b, c, d, 0, 1, 0, 0,
			rest(), false, 1.2, -1.0, lambda));
	CHECK(b == Vector3(real_t(1.6), 0, 0));
}

TEST_CASE("[PhysicsFEM] Feasible principal cap releases multiplier") {
	Vector3 a, b(real_t(1.05), 0, 0), c(0, 1, 0), d(0, 0, 1);
	double lambda = -0.12;
	CHECK_FALSE(physics_fem_tetra_principal_solve(a, b, c, d, 0, 1, 0, 0,
			rest(), false, 1.2, 0.01, lambda));
	CHECK(lambda == 0.0);
}

TEST_CASE("[PhysicsFEM] Deformed material with pure rigid rotation retains stretches") {
	const Vector3 x[4] = { Vector3(10, 20, 0), Vector3(real_t(10.0), real_t(21.5), 0),
		Vector3(real_t(9.25), real_t(20.0), 0), Vector3(10, 20, real_t(1.2)) };
	double s[3];
	CHECK(spectrum(x, rest(), s));
	CHECK(s[0] == doctest::Approx(0.75).epsilon(1e-5));
	CHECK(s[1] == doctest::Approx(1.2).epsilon(1e-5));
	CHECK(s[2] == doctest::Approx(1.5).epsilon(1e-5));
}

} // namespace TestPhysicsFEMTetraPrincipalLimits
