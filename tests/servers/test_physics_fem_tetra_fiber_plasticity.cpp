/**************************************************************************/
/*  test_physics_fem_tetra_fiber_plasticity.cpp                            */
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

#include "servers/physics_fem_tetra_fiber_plasticity.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_fem_tetra_fiber_plasticity)

namespace TestPhysicsFEMTetraFiberPlasticity {

static PhysicsFEMTetraRest unit_rest() {
	PhysicsFEMTetraRest rest;
	physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), rest);
	return rest;
}

TEST_CASE("[PhysicsFEMFiberPlastic] Fiber stretch is objective for rigid translation and rotation") {
	const PhysicsFEMTetraRest rest = unit_rest();
	const Vector3 original[4] = {
		Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)
	};
	double measured = -1.0;
	REQUIRE(physics_fem_tetra_fiber_measure_stretch(
			original, rest, Vector3(1, 0, 0), measured));
	CHECK(measured == doctest::Approx(1.0));
	const Vector3 shifted_rotated[4] = {
		Vector3(20, -10, 7), Vector3(20, -9, 7),
		Vector3(19, -10, 7), Vector3(20, -10, 8)
	};
	REQUIRE(physics_fem_tetra_fiber_measure_stretch(
			shifted_rotated, rest, Vector3(10, 0, 0), measured));
	CHECK(measured == doctest::Approx(1.0));
}

TEST_CASE("[PhysicsFEMFiberPlastic] Fiber direction distinguishes axial and transverse stretch") {
	const PhysicsFEMTetraRest rest = unit_rest();
	Vector3 positions[4] = {
		Vector3(), Vector3(1.6, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)
	};
	double measured = 0.0;
	REQUIRE(physics_fem_tetra_fiber_measure_stretch(
			positions, rest, Vector3(1, 0, 0), measured));
	CHECK(measured == doctest::Approx(1.6));
	positions[1] = Vector3(1, 0, 0);
	positions[2] = Vector3(0, 1.6, 0);
	REQUIRE(physics_fem_tetra_fiber_measure_stretch(
			positions, rest, Vector3(1, 0, 0), measured));
	CHECK(measured == doctest::Approx(1.0));
	REQUIRE(physics_fem_tetra_fiber_measure_stretch(
			positions, rest, Vector3(0, 1, 0), measured));
	CHECK(measured == doctest::Approx(1.6));
}

TEST_CASE("[PhysicsFEMFiberPlastic] Yield threshold and compression do not creep") {
	real_t rest = real_t(1.0);
	CHECK_FALSE(physics_fem_tetra_fiber_creep_rest_stretch(
			1.2, 0.25, 10.0, 0.02, 3.0, rest));
	CHECK_FALSE(physics_fem_tetra_fiber_creep_rest_stretch(
			0.7, 0.0, 10.0, 0.02, 3.0, rest));
	CHECK(rest == real_t(1.0));
	REQUIRE(physics_fem_tetra_fiber_creep_rest_stretch(
			1.6, 0.25, 10.0, 0.02, 3.0, rest));
	CHECK(rest > real_t(1.0));
	CHECK(rest < real_t(1.6 / 1.25));
	// Further loading must exceed the NEW, enlarged yield length.
	CHECK_FALSE(physics_fem_tetra_fiber_creep_rest_stretch(
			rest * real_t(1.1), 0.25, 10.0, 0.02, 3.0, rest));
}

TEST_CASE("[PhysicsFEMFiberPlastic] Creep is irreversible and limited by maximum rest stretch") {
	real_t rest = real_t(1.0);
	for (int i = 0; i < 300; ++i) {
		const real_t before = rest;
		physics_fem_tetra_fiber_creep_rest_stretch(
				8.0, 0.1, 10.0, 0.016, 2.0, rest);
		CHECK(rest >= before);
		CHECK(rest <= real_t(2.0));
	}
	CHECK(rest > real_t(1.99));
	CHECK_FALSE(physics_fem_tetra_fiber_creep_rest_stretch(
			0.5, 0.0, 10.0, 0.016, 2.0, rest));
	CHECK(rest <= real_t(2.0));
}

TEST_CASE("[PhysicsFEMFiberPlastic] Exponential creep approximately preserves timestep subdivision") {
	real_t full = real_t(1.0);
	real_t substeps = real_t(1.0);
	REQUIRE(physics_fem_tetra_fiber_creep_rest_stretch(
			1.6, 0.1, 3.0, 0.75, 3.0, full));
	for (int i = 0; i < 75; ++i) {
		physics_fem_tetra_fiber_creep_rest_stretch(
				1.6, 0.1, 3.0, 0.01, 3.0, substeps);
	}
	CHECK(full == doctest::Approx(substeps).epsilon(1e-4));
}

TEST_CASE("[PhysicsFEMFiberPlastic] Remodeled fibers exert less tension at the same stretch") {
	const PhysicsFEMTetraRest rest = unit_rest();
	Vector3 a, b(1.6, 0, 0), c(0, 1, 0), d(0, 0, 1);
	Vector3 pa = a, pb = b, pc = c, pd = d;
	double elastic_lambda = 0.0, plastic_lambda = 0.0;
	REQUIRE(physics_fem_tetra_solve_fiber(a, b, c, d,
			1, 1, 1, 1, rest, Vector3(1, 0, 0),
			0.01, elastic_lambda));
	REQUIRE(physics_fem_tetra_solve_fiber(pa, pb, pc, pd,
			1, 1, 1, 1, rest, Vector3(1, 0, 0),
			0.01, plastic_lambda, 1.3));
	CHECK((pb - pa).length() > (b - a).length());
	CHECK(plastic_lambda < elastic_lambda);
	CHECK(pc == Vector3(0, 1, 0));
	CHECK(pd == Vector3(0, 0, 1));
}

TEST_CASE("[PhysicsFEMFiberPlastic] Pinned nodes remain exactly fixed") {
	const PhysicsFEMTetraRest rest = unit_rest();
	Vector3 a, b(1.6, 0, 0), c(0, 1, 0), d(0, 0, 1);
	double lambda = 0.0;
	REQUIRE(physics_fem_tetra_solve_fiber(a, b, c, d,
			0, 1, 1, 1, rest, Vector3(1, 0, 0), 0.0, lambda, 1.3));
	CHECK(a == Vector3());
	CHECK(b.x == doctest::Approx(1.3).epsilon(1e-5));
	CHECK(c == Vector3(0, 1, 0));
	CHECK(d == Vector3(0, 0, 1));
}

TEST_CASE("[PhysicsFEMFiberPlastic] Invalid or inverted inputs never commit changes") {
	const PhysicsFEMTetraRest rest = unit_rest();
	Vector3 inverted[4] = {
		Vector3(), Vector3(1.6, 0, 0),
		Vector3(0, 1, 0), Vector3(0, 0, -1)
	};
	double measured = 99.0;
	CHECK_FALSE(physics_fem_tetra_fiber_measure_stretch(
			inverted, rest, Vector3(1, 0, 0), measured));
	CHECK(measured == doctest::Approx(99.0));
	real_t plastic = real_t(1.0);
	CHECK_FALSE(physics_fem_tetra_fiber_creep_rest_stretch(
			std::numeric_limits<double>::infinity(), 0.1, 1, 0.02, 3, plastic));
	CHECK_FALSE(physics_fem_tetra_fiber_creep_rest_stretch(
			2.0, 0.1, -1, 0.02, 3, plastic));
	CHECK_FALSE(physics_fem_tetra_fiber_creep_rest_stretch(
			2.0, 0.1, 1, 0.02, 20, plastic));
	CHECK(plastic == real_t(1.0));
	Vector3 a, b(1.6, 0, 0), c(0, 1, 0), d(0, 0, 1);
	double lambda = 0.0;
	CHECK_FALSE(physics_fem_tetra_solve_fiber(a, b, c, d,
			1, 1, 1, 1, rest, Vector3(1, 0, 0), 0.01, lambda, 0.5));
	CHECK_FALSE(physics_fem_tetra_solve_fiber(a, b, c, d,
			1, 1, 1, 1, rest, Vector3(1, 0, 0), 0.01, lambda,
			std::numeric_limits<double>::quiet_NaN()));
	CHECK(b == Vector3(1.6, 0, 0));
	CHECK(lambda == 0.0);
}

} // namespace TestPhysicsFEMTetraFiberPlasticity
