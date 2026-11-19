/**************************************************************************/
/*  test_physics_xpbd_distance.cpp                                        */
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

#include "servers/physics_xpbd_distance.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_xpbd_distance)

namespace TestPhysicsXPBDDistance {

TEST_CASE("[PhysicsXPBD] Rigid distance constraint restores the rest length") {
	Vector3 a, b(2, 0, 0);
	real_t lambda = 0.0;
	CHECK(physics_xpbd_solve_distance(a, b, 1.0, 1.0, 1.0, 0.0, lambda));
	CHECK(a.is_equal_approx(Vector3(real_t(0.5), 0, 0)));
	CHECK(b.is_equal_approx(Vector3(real_t(1.5), 0, 0)));
	CHECK(Math::is_equal_approx(lambda, real_t(-0.5)));
	const Vector3 once_a = a;
	const Vector3 once_b = b;
	for (int i = 0; i < 20; ++i) {
		CHECK(physics_xpbd_solve_distance(a, b, 1.0, 1.0, 1.0, 0.0, lambda));
	}
	CHECK(a.is_equal_approx(once_a));
	CHECK(b.is_equal_approx(once_b));
}

TEST_CASE("[PhysicsXPBD] Compliant link retains controlled stretch across iterations") {
	Vector3 a, b(2, 0, 0);
	real_t lambda = 0.0;
	CHECK(physics_xpbd_solve_distance(a, b, 1.0, 1.0, 1.0, 1.0, lambda));
	CHECK(Math::is_equal_approx(a.x, real_t(1.0 / 3.0)));
	CHECK(Math::is_equal_approx(b.x, real_t(5.0 / 3.0)));
	CHECK(Math::is_equal_approx(lambda, real_t(-1.0 / 3.0)));
	for (int i = 0; i < 20; ++i) {
		CHECK(physics_xpbd_solve_distance(a, b, 1.0, 1.0, 1.0, 1.0, lambda));
	}
	// The accumulated lambda prevents an increasing stiffness as more
	// solver iterations are added to the same step.
	CHECK(Math::is_equal_approx((b - a).length(), real_t(4.0 / 3.0)));
	CHECK(Math::is_equal_approx(lambda, real_t(-1.0 / 3.0)));
}

TEST_CASE("[PhysicsXPBD] Pinned soft-body particle does not move") {
	Vector3 pinned, free(3, 0, 0);
	real_t lambda = 0.0;
	CHECK(physics_xpbd_solve_distance(pinned, free, 0.0, 2.0, 1.0, 0.0, lambda));
	CHECK(pinned == Vector3());
	CHECK(free.is_equal_approx(Vector3(1, 0, 0)));
	CHECK(Math::is_equal_approx(lambda, real_t(-1)));
}

TEST_CASE("[PhysicsXPBD] Inverse mass determines weighted corrections") {
	Vector3 heavy, light(3, 0, 0);
	real_t lambda = 0.0;
	CHECK(physics_xpbd_solve_distance(heavy, light, 1.0, 3.0, 1.0, 0.0, lambda));
	CHECK(heavy.is_equal_approx(Vector3(real_t(0.5), 0, 0)));
	CHECK(light.is_equal_approx(Vector3(real_t(1.5), 0, 0)));
}

TEST_CASE("[PhysicsXPBD] Deformable links can contract toward shorter rest lengths") {
	Vector3 a, b(1, 0, 0);
	real_t lambda = 0.0;
	CHECK(physics_xpbd_solve_distance(a, b, 1.0, 1.0, real_t(0.5), real_t(0.5), lambda));
	CHECK((b - a).length() < real_t(1.0));
	CHECK((b - a).length() > real_t(0.5));
	CHECK(lambda < 0.0);
}

TEST_CASE("[PhysicsXPBD] Both pinned or degenerate links are skipped") {
	Vector3 a, b(3, 0, 0);
	real_t lambda = 0.0;
	CHECK_FALSE(physics_xpbd_solve_distance(a, b, 0.0, 0.0, 1.0, 0.0, lambda));
	CHECK(a == Vector3());
	CHECK(b == Vector3(3, 0, 0));
	CHECK(lambda == real_t(0));
	Vector3 coincident;
	CHECK_FALSE(physics_xpbd_solve_distance(a, coincident, 1.0, 1.0, 1.0, 0.0, lambda));
	CHECK(a == Vector3());
	CHECK(coincident == Vector3());
}

TEST_CASE("[PhysicsXPBD] Invalid input cannot corrupt position or multiplier") {
	Vector3 a, b(2, 0, 0);
	real_t lambda = 0.0;
	CHECK_FALSE(physics_xpbd_solve_distance(a, b, 1.0, 1.0, 1.0, real_t(-1), lambda));
	CHECK_FALSE(physics_xpbd_solve_distance(a, b, 1.0, 1.0, 1.0,
			std::numeric_limits<real_t>::infinity(), lambda));
	CHECK_FALSE(physics_xpbd_solve_distance(a, b, real_t(-1), 1.0, 1.0, 0.0, lambda));
	CHECK(a == Vector3());
	CHECK(b == Vector3(2, 0, 0));
	CHECK(lambda == real_t(0));
}

TEST_CASE("[PhysicsXPBD] Iteration convergence remains stable across a simple chain") {
	Vector3 nodes[3] = { Vector3(), Vector3(2, 0, 0), Vector3(4, 0, 0) };
	real_t lambda[2] = { 0.0, 0.0 };
	const real_t alpha = real_t(0.02);
	for (int iter = 0; iter < 64; ++iter) {
		CHECK(physics_xpbd_solve_distance(nodes[0], nodes[1], 0.0, 1.0, 1.0, alpha, lambda[0]));
		CHECK(physics_xpbd_solve_distance(nodes[1], nodes[2], 1.0, 1.0, 1.0, alpha, lambda[1]));
	}
	CHECK(nodes[0] == Vector3());
	CHECK(nodes[1].x > 0.0);
	CHECK(nodes[2].x > nodes[1].x);
	CHECK(nodes[2].x < 4.0);
	CHECK(nodes[1].is_finite());
	CHECK(nodes[2].is_finite());
}

} // namespace TestPhysicsXPBDDistance
