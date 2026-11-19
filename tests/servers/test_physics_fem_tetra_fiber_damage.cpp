/**************************************************************************/
/*  test_physics_fem_tetra_fiber_damage.cpp                               */
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
#include "servers/physics_fem_tetra_fiber.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_fem_tetra_fiber_damage)

namespace TestPhysicsFEMTetraFiberDamage {

static PhysicsFEMTetraRest unit_rest() {
	PhysicsFEMTetraRest rest;
	physics_fem_tetra_make_rest(Vector3(), Vector3(1, 0, 0),
			Vector3(0, 1, 0), Vector3(0, 0, 1), rest);
	return rest;
}

static real_t solve_fiber(real_t p_alpha, double p_damage) {
	Vector3 a, b(1.5, 0, 0), c(0, 1, 0), d(0, 0, 1);
	double adjusted = 0.0;
	if (!PhysicsFEMTetraDamage::effective_compliance(p_alpha, p_damage, adjusted)) {
		return -1.0;
	}
	double lambda = 0.0;
	if (!physics_fem_tetra_solve_fiber(a, b, c, d,
			1.0, 1.0, 1.0, 1.0, unit_rest(), Vector3(1, 0, 0),
			adjusted, lambda)) {
		return -1.0;
	}
	return (b - a).length();
}

TEST_CASE("[PhysicsFEMDamageFiber] Undamaged reinforcement retains baseline compliance") {
	double result = 0.0;
	REQUIRE(PhysicsFEMTetraDamage::effective_compliance(0.1, 0.0, result));
	CHECK(result == doctest::Approx(0.1));
	const real_t length = solve_fiber(0.1, 0.0);
	CHECK(length > real_t(1.0));
	CHECK(length < real_t(1.5));
}

TEST_CASE("[PhysicsFEMDamageFiber] Damage makes stretched fibers progressively softer") {
	const real_t intact = solve_fiber(0.1, 0.0);
	const real_t damaged = solve_fiber(0.1, 0.5);
	const real_t heavily_damaged = solve_fiber(0.1, 0.95);
	CHECK(intact > real_t(1.0));
	CHECK(damaged > intact);
	CHECK(heavily_damaged > damaged);
	CHECK(heavily_damaged < real_t(1.5));
}

TEST_CASE("[PhysicsFEMDamageFiber] Maximum damage cannot make compliance infinite") {
	double adjusted = -1.0;
	CHECK(PhysicsFEMTetraDamage::effective_compliance(0.001, 0.95, adjusted));
	CHECK(Math::is_finite(adjusted));
	CHECK(adjusted == doctest::Approx(0.02));
	CHECK_FALSE(PhysicsFEMTetraDamage::effective_compliance(0.001, 1.0, adjusted));
	CHECK_FALSE(PhysicsFEMTetraDamage::effective_compliance(
			std::numeric_limits<double>::infinity(), 0.5, adjusted));
	CHECK(adjusted == doctest::Approx(0.02));
}

TEST_CASE("[PhysicsFEMDamageFiber] Damage-induced softening respects pinned vertices") {
	Vector3 a, b(1.5, 0, 0), c(0, 1, 0), d(0, 0, 1);
	double adjusted = 0.0, lambda = 0.0;
	REQUIRE(PhysicsFEMTetraDamage::effective_compliance(0.02, 0.8, adjusted));
	REQUIRE(physics_fem_tetra_solve_fiber(a, b, c, d,
			0, 1, 1, 1, unit_rest(), Vector3(1, 0, 0), adjusted, lambda));
	CHECK(a == Vector3());
	CHECK(b.x < real_t(1.5));
	CHECK(b.x > real_t(1.0));
	CHECK(c == Vector3(0, 1, 0));
	CHECK(d == Vector3(0, 0, 1));
}

TEST_CASE("[PhysicsFEMDamageFiber] Rigid material rotation leaves fiber strain slack") {
	Vector3 a(3, 4, 5), b(3, 5, 5), c(2, 4, 5), d(3, 4, 6);
	double lambda = 0.0, adjusted = 0.0;
	REQUIRE(PhysicsFEMTetraDamage::effective_compliance(0.01, 0.5, adjusted));
	CHECK_FALSE(physics_fem_tetra_solve_fiber(a, b, c, d,
			1, 1, 1, 1, unit_rest(), Vector3(1, 0, 0), adjusted, lambda));
	CHECK(lambda == 0.0);
}

TEST_CASE("[PhysicsFEMDamageFiber] Irreversible damage increases fiber compliance") {
	double damage = 0.0;
	double previous_alpha = 0.0;
	REQUIRE(PhysicsFEMTetraDamage::effective_compliance(0.01, damage, previous_alpha));
	for (int i = 0; i < 10; ++i) {
		PhysicsFEMTetraDamage::evolve(0.6, 0.2, 4.0, 0.016, damage);
		double alpha = 0.0;
		REQUIRE(PhysicsFEMTetraDamage::effective_compliance(0.01, damage, alpha));
		CHECK(alpha >= previous_alpha);
		previous_alpha = alpha;
	}
	CHECK(damage > 0.0);
	CHECK(damage <= 0.95);
}

} // namespace TestPhysicsFEMTetraFiberDamage
