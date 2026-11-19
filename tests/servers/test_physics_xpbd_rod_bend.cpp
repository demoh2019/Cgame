/**************************************************************************/
/*  test_physics_xpbd_rod_bend.cpp                                        */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "servers/physics_xpbd_rod_bend.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_xpbd_rod_bend)

namespace TestPhysicsXPBDRodBend {

TEST_CASE("[PhysicsXPBD] Rod centerline angle distinguishes straight, bent and folded chains") {
	real_t straight = -1, bent = -1, folded = -1;
	CHECK(physics_xpbd_rod_bend_angle(Vector3(-1, 0, 0), Vector3(), Vector3(1, 0, 0), straight));
	CHECK(physics_xpbd_rod_bend_angle(Vector3(-1, 0, 0), Vector3(), Vector3(1, 1, 0), bent));
	CHECK(physics_xpbd_rod_bend_angle(Vector3(-1, 0, 0), Vector3(), Vector3(-1, 0, 0), folded));
	CHECK(straight == doctest::Approx(0.0));
	CHECK(bent == doctest::Approx(Math::PI / 4).epsilon(1e-5));
	CHECK(folded == doctest::Approx(Math::PI).epsilon(1e-5));
}

TEST_CASE("[PhysicsXPBD] Compliant discrete rod bending reduces angle without overshoot") {
	Vector3 a(-1, 0, 0), middle, c(1, real_t(0.4), 0);
	real_t before = 0;
	CHECK(physics_xpbd_rod_bend_angle(a, middle, c, before));
	real_t lambda = 0;
	for (int iteration = 0; iteration < 12; ++iteration) {
		CHECK(physics_xpbd_solve_rod_bend(a, middle, c, 0, 0, 1,
				0, real_t(0.1), lambda));
	}
	real_t after = 0;
	CHECK(physics_xpbd_rod_bend_angle(a, middle, c, after));
	CHECK(a == Vector3(-1, 0, 0));
	CHECK(middle == Vector3());
	CHECK(after >= 0);
	CHECK(after < before);
}

TEST_CASE("[PhysicsXPBD] Rod bending is stiffer for smaller XPBD compliance") {
	Vector3 stiff_a(-1, 0, 0), stiff_mid, stiff_c(1, real_t(0.4), 0);
	Vector3 soft_a = stiff_a, soft_mid = stiff_mid, soft_c = stiff_c;
	real_t stiff_lambda = 0, soft_lambda = 0;
	for (int iteration = 0; iteration < 12; ++iteration) {
		CHECK(physics_xpbd_solve_rod_bend(stiff_a, stiff_mid, stiff_c,
				0, 0, 1, 0, real_t(0.1), stiff_lambda));
		CHECK(physics_xpbd_solve_rod_bend(soft_a, soft_mid, soft_c,
				0, 0, 1, 0, real_t(5.0), soft_lambda));
	}
	real_t stiff = 0, soft = 0;
	CHECK(physics_xpbd_rod_bend_angle(stiff_a, stiff_mid, stiff_c, stiff));
	CHECK(physics_xpbd_rod_bend_angle(soft_a, soft_mid, soft_c, soft));
	CHECK(stiff < soft);
}

TEST_CASE("[PhysicsXPBD] Rod bend conserves momentum when all masses are equal") {
	Vector3 a(-1, 0, 0), middle, c(1, 0.4, 0);
	const Vector3 centroid = a + middle + c;
	real_t lambda = 0;
	CHECK(physics_xpbd_solve_rod_bend(a, middle, c, 1, 1, 1, 0, real_t(0.1), lambda));
	CHECK((a + middle + c).distance_to(centroid) < real_t(1e-5));
}

TEST_CASE("[PhysicsXPBD] Rod angle is invariant under rigid translations and rotation") {
	real_t original = 0, transformed = 0;
	CHECK(physics_xpbd_rod_bend_angle(Vector3(-1, 0, 0), Vector3(), Vector3(1, 0.5, 0), original));
	CHECK(physics_xpbd_rod_bend_angle(
			Vector3(5, -3, 1), Vector3(5, -2, 1), Vector3(4.5, -1, 1), transformed));
	CHECK(original == doctest::Approx(transformed).epsilon(1e-5));
}

TEST_CASE("[PhysicsXPBD] Precurved rod retains the preferred rest angle") {
	const Vector3 a(-1, 0, 0), middle, c(1, real_t(0.35), 0);
	real_t rest = 0, current = 0;
	CHECK(physics_xpbd_rod_bend_angle(a, middle, c, rest));
	Vector3 a2 = a, b2 = middle, c2 = c;
	real_t lambda = 0;
	CHECK(physics_xpbd_solve_rod_bend(a2, b2, c2, 1, 1, 1,
			rest, real_t(0.1), lambda));
	CHECK(a2 == a);
	CHECK(b2 == middle);
	CHECK(c2 == c);
	CHECK(lambda == 0);
	CHECK(physics_xpbd_rod_bend_angle(a2, b2, c2, current));
	CHECK(current == doctest::Approx(rest));
}

TEST_CASE("[PhysicsXPBD] Straight rod in its rest pose is stable and unchanged") {
	Vector3 a(-1, 0, 0), middle, c(1, 0, 0);
	real_t lambda = 0;
	CHECK(physics_xpbd_solve_rod_bend(a, middle, c, 1, 1, 1, 0, real_t(0.1), lambda));
	CHECK(a == Vector3(-1, 0, 0));
	CHECK(middle == Vector3());
	CHECK(c == Vector3(1, 0, 0));
	CHECK(lambda == 0);
}

TEST_CASE("[PhysicsXPBD] Pinned ends cannot move under rod bending") {
	Vector3 a(-1, 0, 0), middle, c(1, real_t(0.2), 0);
	real_t lambda = 0;
	CHECK(physics_xpbd_solve_rod_bend(a, middle, c,
			0, 1, 0, 0, real_t(0.2), lambda));
	CHECK(a == Vector3(-1, 0, 0));
	CHECK(c == Vector3(1, real_t(0.2), 0));
	CHECK(middle.is_finite());
}

TEST_CASE("[PhysicsXPBD] Invalid three-node rod bending cannot mutate solver state") {
	const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
	Vector3 a(-1, 0, 0), middle, c(1, 1, 0);
	real_t lambda = real_t(23);
	CHECK_FALSE(physics_xpbd_solve_rod_bend(a, middle, c, -1, 1, 1, 0, 1, lambda));
	CHECK_FALSE(physics_xpbd_solve_rod_bend(a, middle, c, 1, 1, 1, -1, 1, lambda));
	CHECK_FALSE(physics_xpbd_solve_rod_bend(a, middle, c, 1, 1, 1, 0, -1, lambda));
	CHECK_FALSE(physics_xpbd_solve_rod_bend(a, middle, c, 1, 1, 1, 0, nan, lambda));
	CHECK(a == Vector3(-1, 0, 0));
	CHECK(middle == Vector3());
	CHECK(c == Vector3(1, 1, 0));
	CHECK(lambda == 23);
}

TEST_CASE("[PhysicsXPBD] Degenerate rod lengths are rejected without mutation") {
	Vector3 a, middle, c(1, 0, 0);
	real_t rest_angle = real_t(42);
	real_t lambda = 0;
	CHECK_FALSE(physics_xpbd_rod_bend_angle(a, middle, c, rest_angle));
	CHECK(rest_angle == 42);
	CHECK_FALSE(physics_xpbd_solve_rod_bend(a, middle, c, 1, 1, 1, 0, 1, lambda));
	CHECK(a == Vector3());
	CHECK(middle == Vector3());
	CHECK(c == Vector3(1, 0, 0));
	CHECK(lambda == 0);
}

} // namespace TestPhysicsXPBDRodBend
