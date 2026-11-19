/**************************************************************************/
/*  test_physics_fem_tetra_dual_fiber.cpp                                 */
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
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER ARISING FROM, OUT OF OR IN */
/* CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/**************************************************************************/

#include "servers/physics_fem_tetra_damage.h"
#include "servers/physics_fem_tetra_fiber_plasticity.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_fem_tetra_dual_fiber)

namespace TestPhysicsFEMTetraDualFiber {

static PhysicsFEMTetraRest unit_rest() {
	PhysicsFEMTetraRest rest;
	physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), rest);
	return rest;
}

TEST_CASE("[PhysicsFEMDualFiber] Two independent material axes resist tensile extension") {
	Vector3 a, b(real_t(1.6), 0, 0), c(0, real_t(1.35), 0), d(0, 0, 1);
	double primary_lambda = 0.0, secondary_lambda = 0.0;
	const PhysicsFEMTetraRest rest = unit_rest();
	REQUIRE(physics_fem_tetra_solve_fiber(
			a, b, c, d, 0, 1, 1, 1, rest, Vector3(1, 0, 0),
			0.02, primary_lambda));
	const real_t after_x = b.x;
	CHECK(primary_lambda > 0.0);
	CHECK(after_x < real_t(1.6));
	CHECK(c.y == real_t(1.35));
	REQUIRE(physics_fem_tetra_solve_fiber(
			a, b, c, d, 0, 1, 1, 1, rest, Vector3(0, 1, 0),
			0.07, secondary_lambda));
	CHECK(secondary_lambda > 0.0);
	CHECK(b.x == after_x);
	CHECK(c.y < real_t(1.35));
	CHECK(a == Vector3());
	CHECK(d == Vector3(0, 0, 1));
}

TEST_CASE("[PhysicsFEMDualFiber] Secondary family alone does not exert primary-axis forces") {
	Vector3 a, b(real_t(1.8), 0, 0), c(0, real_t(1.4), 0), d(0, 0, 1);
	double secondary_lambda = 0.0;
	REQUIRE(physics_fem_tetra_solve_fiber(
			a, b, c, d, 0, 1, 1, 1, unit_rest(), Vector3(0, 1, 0),
			0.04, secondary_lambda));
	CHECK(b.x == real_t(1.8));
	CHECK(c.y < real_t(1.4));
	CHECK(secondary_lambda > 0.0);
}

TEST_CASE("[PhysicsFEMDualFiber] Oblique fibers preserve weighted linear momentum") {
	Vector3 a, b(real_t(1.5), 0, 0), c(0, real_t(1.3), 0), d(0, 0, 1);
	const Vector3 original[4] = { a, b, c, d };
	const real_t inv_mass[4] = { real_t(0.5), real_t(1.5), real_t(1.0), real_t(2.0) };
	double lambda_x = 0.0, lambda_oblique = 0.0;
	REQUIRE(physics_fem_tetra_solve_fiber(a, b, c, d,
			inv_mass[0], inv_mass[1], inv_mass[2], inv_mass[3],
			unit_rest(), Vector3(1, 0, 0), 0.01, lambda_x));
	REQUIRE(physics_fem_tetra_solve_fiber(a, b, c, d,
			inv_mass[0], inv_mass[1], inv_mass[2], inv_mass[3],
			unit_rest(), Vector3(1, 1, 0), 0.03, lambda_oblique));
	const Vector3 momentum_residual =
			(a - original[0]) / inv_mass[0] +
			(b - original[1]) / inv_mass[1] +
			(c - original[2]) / inv_mass[2] +
			(d - original[3]) / inv_mass[3];
	CHECK(momentum_residual.length() < real_t(1e-5));
	CHECK(lambda_x > 0.0);
	CHECK(lambda_oblique > 0.0);
}

TEST_CASE("[PhysicsFEMDualFiber] Pure rigid rotation does not stretch either family") {
	Vector3 a(2, 4, 6), b(2, 5, 6), c(1, 4, 6), d(2, 4, 7);
	double lambda_a = 0.0, lambda_b = 0.0;
	CHECK_FALSE(physics_fem_tetra_solve_fiber(a, b, c, d,
			1, 1, 1, 1, unit_rest(), Vector3(1, 0, 0), 0.01, lambda_a));
	CHECK_FALSE(physics_fem_tetra_solve_fiber(a, b, c, d,
			1, 1, 1, 1, unit_rest(), Vector3(0, 1, 0), 0.01, lambda_b));
	CHECK(lambda_a == 0.0);
	CHECK(lambda_b == 0.0);
}

TEST_CASE("[PhysicsFEMDualFiber] Family-specific permanent stretch reduces only its tension") {
	Vector3 a, b(real_t(1.5), 0, 0), c(0, real_t(1.4), 0), d(0, 0, 1);
	double primary_lambda = 0.0, secondary_lambda = 0.0;
	real_t secondary_rest = real_t(1.0);
	REQUIRE(physics_fem_tetra_fiber_creep_rest_stretch(
			1.4, 0.1, 10.0, .1, 2.0, secondary_rest));
	CHECK(secondary_rest > real_t(1.0));
	REQUIRE(physics_fem_tetra_solve_fiber(a, b, c, d,
			0, 1, 1, 1, unit_rest(), Vector3(1, 0, 0),
			0.02, primary_lambda));
	const real_t primary_result = b.x;
	REQUIRE(physics_fem_tetra_solve_fiber(a, b, c, d,
			0, 1, 1, 1, unit_rest(), Vector3(0, 1, 0),
			0.02, secondary_lambda, double(secondary_rest)));
	CHECK(b.x == primary_result);
	CHECK(c.y > secondary_rest);
	CHECK(c.y < real_t(1.4));
	CHECK(primary_lambda > 0.0);
	CHECK(secondary_lambda > 0.0);
}

TEST_CASE("[PhysicsFEMDualFiber] FEM damage softens both axis constraints independently") {
	double weak_x = 0.0, weak_y = 0.0;
	REQUIRE(PhysicsFEMTetraDamage::effective_compliance(0.02, 0.6, weak_x));
	REQUIRE(PhysicsFEMTetraDamage::effective_compliance(0.07, 0.6, weak_y));
	CHECK(weak_x == doctest::Approx(0.05));
	CHECK(weak_y == doctest::Approx(0.175));
	Vector3 a, b(real_t(1.5), 0, 0), c(0, real_t(1.4), 0), d(0, 0, 1);
	double lambda_x = 0.0, lambda_y = 0.0;
	REQUIRE(physics_fem_tetra_solve_fiber(a, b, c, d,
			0, 1, 1, 1, unit_rest(), Vector3(1, 0, 0), weak_x, lambda_x));
	REQUIRE(physics_fem_tetra_solve_fiber(a, b, c, d,
			0, 1, 1, 1, unit_rest(), Vector3(0, 1, 0), weak_y, lambda_y));
	CHECK(lambda_x > 0.0);
	CHECK(lambda_y > 0.0);
}

TEST_CASE("[PhysicsFEMDualFiber] Compression, invalid axes and inversions are transactional") {
	Vector3 a, b(real_t(.8), 0, 0), c(0, real_t(.7), 0), d(0, 0, 1);
	double lambda = 0.0;
	CHECK_FALSE(physics_fem_tetra_solve_fiber(a, b, c, d,
			1, 1, 1, 1, unit_rest(), Vector3(0, 1, 0), .01, lambda));
	CHECK(lambda == 0.0);
	CHECK_FALSE(physics_fem_tetra_solve_fiber(a, b, c, d,
			1, 1, 1, 1, unit_rest(), Vector3(), .01, lambda));
	CHECK_FALSE(physics_fem_tetra_solve_fiber(a, b, c, d,
			1, 1, 1, 1, unit_rest(), Vector3(0, 1, 0), .01, lambda,
			std::numeric_limits<double>::quiet_NaN()));
	d = Vector3(0, 0, -1);
	CHECK_FALSE(physics_fem_tetra_solve_fiber(a, b, c, d,
			1, 1, 1, 1, unit_rest(), Vector3(0, 1, 0), .01, lambda));
	CHECK(a == Vector3());
	CHECK(b.x == real_t(.8));
	CHECK(c.y == real_t(.7));
	CHECK(lambda == 0.0);
}

} // namespace TestPhysicsFEMTetraDualFiber
