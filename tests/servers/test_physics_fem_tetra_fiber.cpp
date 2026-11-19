/**************************************************************************/
/*  test_physics_fem_tetra_fiber.cpp                                      */
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
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE, ARISING FROM, OUT OF OR IN */
/* CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/**************************************************************************/

#include "servers/physics_fem_tetra_fiber.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_fem_tetra_fiber)

namespace TestPhysicsFEMTetraFiber {

static PhysicsFEMTetraRest rest_unit() {
	PhysicsFEMTetraRest result;
	physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), result);
	return result;
}

TEST_CASE("[PhysicsFEMFiber] Unilateral reinforcement restores an elongated fiber") {
	const PhysicsFEMTetraRest rest = rest_unit();
	Vector3 a, b(1.5, 0, 0), c(0, 1, 0), d(0, 0, 1);
	const Vector3 original_com = a + b + c + d;
	double lambda = 0.0;
	REQUIRE(physics_fem_tetra_solve_fiber(a, b, c, d,
			1.0, 1.0, 1.0, 1.0, rest, Vector3(1, 0, 0), 0.0, lambda));
	CHECK(lambda > 0.0);
	CHECK((a + b + c + d).is_equal_approx(original_com));
	CHECK((b - a).length() == doctest::Approx(1.0).epsilon(1e-5));
	CHECK(d == Vector3(0, 0, 1));
	CHECK(c == Vector3(0, 1, 0));
}

TEST_CASE("[PhysicsFEMFiber] Compressed fiber and transverse stretch are slack") {
	const PhysicsFEMTetraRest rest = rest_unit();
	Vector3 a, b(0.7, 0, 0), c(0, 1, 0), d(0, 0, 1);
	double lambda = 0.0;
	CHECK_FALSE(physics_fem_tetra_solve_fiber(a, b, c, d,
			1, 1, 1, 1, rest, Vector3(1, 0, 0), 0.0, lambda));
	b = Vector3(1, 0, 0);
	c = Vector3(0, 1.5, 0);
	CHECK_FALSE(physics_fem_tetra_solve_fiber(a, b, c, d,
			1, 1, 1, 1, rest, Vector3(1, 0, 0), 0.0, lambda));
	CHECK(lambda == 0.0);
	CHECK(b == Vector3(1, 0, 0));
	CHECK(c == Vector3(0, 1.5, 0));
}

TEST_CASE("[PhysicsFEMFiber] Rigid rotation does not change material stretch") {
	const PhysicsFEMTetraRest rest = rest_unit();
	Vector3 a, b(0, 1.5, 0), c(-1, 0, 0), d(0, 0, 1);
	double lambda = 0.0;
	CHECK(physics_fem_tetra_solve_fiber(a, b, c, d,
			1, 1, 1, 1, rest, Vector3(1, 0, 0), 0.0, lambda));
	CHECK((b-a).length() == doctest::Approx(1.0).epsilon(1e-5));
	CHECK(b.x == doctest::Approx(0.0).epsilon(1e-5));
	CHECK(lambda > 0.0);
}

TEST_CASE("[PhysicsFEMFiber] Mass weighting and exact pins are respected") {
	const PhysicsFEMTetraRest rest = rest_unit();
	Vector3 a, b(1.5, 0, 0), c(0, 1, 0), d(0, 0, 1);
	double lambda = 0.0;
	CHECK(physics_fem_tetra_solve_fiber(a, b, c, d,
			0, 1, 1, 1, rest, Vector3(1, 0, 0), 0.0, lambda));
	CHECK(a == Vector3());
	CHECK(b.x == doctest::Approx(1.0).epsilon(1e-5));
	CHECK(c == Vector3(0, 1, 0));
	CHECK(d == Vector3(0, 0, 1));
}

TEST_CASE("[PhysicsFEMFiber] Compliance permits more stretch and lambda retains across iterations") {
	const PhysicsFEMTetraRest rest = rest_unit();
	Vector3 a, b(1.5, 0, 0), c(0, 1, 0), d(0, 0, 1);
	double lambda = 0.0;
	CHECK(physics_fem_tetra_solve_fiber(a, b, c, d,
			1, 1, 1, 1, rest, Vector3(1, 0, 0), 0.1, lambda));
	const real_t after_first = (b-a).length();
	CHECK(after_first > real_t(1.0));
	CHECK(after_first < real_t(1.5));
	const double previous_lambda = lambda;
	// Applying the same XPBD constraint again should not create a
	// second full stiffness impulse when the multiplier persists.
	physics_fem_tetra_solve_fiber(a, b, c, d,
			1, 1, 1, 1, rest, Vector3(1, 0, 0), 0.1, lambda);
	CHECK(Math::abs(lambda - previous_lambda) < 1e-4);
}

TEST_CASE("[PhysicsFEMFiber] Inverted, degenerate and invalid inputs are transactional") {
	const PhysicsFEMTetraRest rest = rest_unit();
	Vector3 a, b(1.5, 0, 0), c(0, 1, 0), d(0, 0, -1);
	const Vector3 old_b = b;
	double lambda = 0.0;
	CHECK_FALSE(physics_fem_tetra_solve_fiber(a, b, c, d,
			1, 1, 1, 1, rest, Vector3(1, 0, 0), 0.0, lambda));
	CHECK(b == old_b);
	d = Vector3(0, 0, 1);
	CHECK_FALSE(physics_fem_tetra_solve_fiber(a, b, c, d,
			1, 1, 1, 1, rest, Vector3(), 0.0, lambda));
	CHECK_FALSE(physics_fem_tetra_solve_fiber(a, b, c, d,
			-1, 1, 1, 1, rest, Vector3(1, 0, 0), 0.0, lambda));
	CHECK_FALSE(physics_fem_tetra_solve_fiber(a, b, c, d,
			1, 1, 1, 1, rest, Vector3(1, 0, 0),
			std::numeric_limits<double>::infinity(), lambda));
	CHECK(lambda == 0.0);
	CHECK(b == old_b);
}

TEST_CASE("[PhysicsFEMFiber] Fully pinned tetra cannot receive impulses") {
	const PhysicsFEMTetraRest rest = rest_unit();
	Vector3 a, b(1.5, 0, 0), c(0, 1, 0), d(0, 0, 1);
	double lambda = 0.0;
	CHECK_FALSE(physics_fem_tetra_solve_fiber(a, b, c, d,
			0, 0, 0, 0, rest, Vector3(1, 0, 0), 0.0, lambda));
	CHECK(b == Vector3(1.5, 0, 0));
	CHECK(lambda == 0.0);
}

} // namespace TestPhysicsFEMTetraFiber
