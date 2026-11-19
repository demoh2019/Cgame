/**************************************************************************/
/*  test_physics_xpbd_strain_limit.cpp                                    */
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

#include "servers/physics_xpbd_strain_limit.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_xpbd_strain_limit)

namespace TestPhysicsXPBDStrainLimit {

TEST_CASE("[PhysicsXPBD] Stretch limit clamps a long link without moving its center") {
	Vector3 a, b(2, 0, 0);
	PhysicsXPBDStrainLimitLambdas lambda;
	CHECK(physics_xpbd_solve_strain_limits(a, b, 1.0, 1.0, 1.0, 0.0, 1.25, 0.0, lambda));
	CHECK(a.x == doctest::Approx(0.375));
	CHECK(b.x == doctest::Approx(1.625));
	CHECK(lambda.stretch == doctest::Approx(-0.375));
	CHECK(lambda.compression == doctest::Approx(0.0));
}

TEST_CASE("[PhysicsXPBD] Compression limit restores separation and preserves a pin") {
	Vector3 a, b(real_t(0.2), 0, 0);
	PhysicsXPBDStrainLimitLambdas lambda;
	CHECK(physics_xpbd_solve_strain_limits(a, b, 0.0, 1.0, 1.0, 0.5, 0.0, 0.0, lambda));
	CHECK(a == Vector3());
	CHECK(b.x == doctest::Approx(0.5));
	CHECK(lambda.compression == doctest::Approx(-0.3));
	CHECK(lambda.stretch == doctest::Approx(0.0));
}

TEST_CASE("[PhysicsXPBD] Slack links do not cause artificial attraction or repulsion") {
	Vector3 a, b(real_t(1.2), 0, 0);
	PhysicsXPBDStrainLimitLambdas lambda;
	CHECK_FALSE(physics_xpbd_solve_strain_limits(a, b, 1.0, 1.0, 1.0, 0.5, 1.5, 0.0, lambda));
	CHECK(a == Vector3());
	CHECK(b == Vector3(real_t(1.2), 0, 0));
	CHECK(lambda.stretch == 0.0);
	CHECK(lambda.compression == 0.0);
}

TEST_CASE("[PhysicsXPBD] Compliant strain limit retains its multiplier between iterations") {
	Vector3 a, b(2, 0, 0);
	PhysicsXPBDStrainLimitLambdas lambda;
	CHECK(physics_xpbd_solve_strain_limits(a, b, 1.0, 1.0, 1.0, 0.0, 1.25, 0.5, lambda));
	for (int i = 0; i < 16; ++i) {
		physics_xpbd_solve_strain_limits(a, b, 1.0, 1.0, 1.0, 0.0, 1.25, 0.5, lambda);
	}
	CHECK((b - a).length() == doctest::Approx(1.4).epsilon(1e-5));
	CHECK(lambda.stretch == doctest::Approx(-0.3).epsilon(1e-5));
}

TEST_CASE("[PhysicsXPBD] Constraint multipliers can release when the link becomes slack") {
	Vector3 a, b(2, 0, 0);
	PhysicsXPBDStrainLimitLambdas lambda;
	CHECK(physics_xpbd_solve_strain_limits(a, b, 1.0, 1.0, 1.0, 0.0, 1.25, 0.0, lambda));
	b.x = a.x + real_t(0.1);
	CHECK(physics_xpbd_solve_strain_limits(a, b, 1.0, 1.0, 1.0, 0.0, 1.25, 0.0, lambda));
	CHECK(lambda.stretch == doctest::Approx(0.0));
	CHECK((b - a).length() <= real_t(1.25));
}

TEST_CASE("[PhysicsXPBD] Very small and large representable links retain valid bounds") {
	const real_t scales[] = { real_t(1e-8), real_t(1e20) };
	for (real_t scale : scales) {
		Vector3 a, b(real_t(2.0) * scale, 0, 0);
		PhysicsXPBDStrainLimitLambdas lambda;
		CHECK(physics_xpbd_solve_strain_limits(a, b, 0.0, 1.0, scale, 0.0, 1.25, 0.0, lambda));
		CHECK(a == Vector3());
		CHECK((b.x / scale) == doctest::Approx(1.25).epsilon(1e-5));
		CHECK(Math::is_finite(lambda.stretch));
	}
}

TEST_CASE("[PhysicsXPBD] Invalid, pinned and coincident links are not mutated") {
	Vector3 a, b(2, 0, 0);
	PhysicsXPBDStrainLimitLambdas lambda;
	CHECK_FALSE(physics_xpbd_solve_strain_limits(a, b, 0.0, 0.0, 1.0, 0.5, 1.5, 0.0, lambda));
	CHECK_FALSE(physics_xpbd_solve_strain_limits(a, b, 1.0, 1.0, 1.0, real_t(-1), 1.5, 0.0, lambda));
	CHECK_FALSE(physics_xpbd_solve_strain_limits(a, b, 1.0, 1.0, 1.0, 0.5, 1.5,
			std::numeric_limits<double>::infinity(), lambda));
	CHECK_FALSE(physics_xpbd_solve_strain_limits(a, b, 1.0, 1.0, 1.0, 0.0, 0.0, 0.0, lambda));
	CHECK(a == Vector3());
	CHECK(b == Vector3(2, 0, 0));
	CHECK(lambda.stretch == 0.0);
	CHECK(lambda.compression == 0.0);
	Vector3 coincident;
	CHECK_FALSE(physics_xpbd_solve_strain_limits(a, coincident, 1.0, 1.0, 1.0, 0.5, 0.0, 0.0, lambda));
	CHECK(coincident == Vector3());
}

} // namespace TestPhysicsXPBDStrainLimit
