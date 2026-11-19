/**************************************************************************/
/*  test_physics_softbody_aerodynamic_drag.cpp                             */
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

#include "servers/physics_softbody_aerodynamic_drag.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_aerodynamic_drag)

namespace TestPhysicsSoftBodyAerodynamicDrag {

TEST_CASE("[Physics] Quadratic soft-body drag has an exact stable mean-velocity step") {
	Vector3 per_node;
	CHECK(physics_softbody_quadratic_aerodynamic_force(
			Vector3(0, 0, 1), Vector3(0, 0, 10), 3, 0, 2, real_t(0.5), 3, per_node));
	CHECK(Math::abs(per_node.z + real_t(100.0 / 6.0)) < real_t(0.001));
	const real_t next_speed = 10 + real_t(0.5) * per_node.z;
	CHECK(Math::abs(next_speed - real_t(10.0 / 6.0)) < real_t(0.001));
	CHECK(next_speed > 0.0); // No spurious sign reversal at stiff drag.
	CHECK(next_speed < 10.0);
}

TEST_CASE("[Physics] Face orientation does not change two-sided normal drag") {
	Vector3 a;
	Vector3 b;
	CHECK(physics_softbody_quadratic_aerodynamic_force(Vector3(0, 0, 1),
			Vector3(0, 0, -20), 1, 0, 3, real_t(0.2), 3, a));
	CHECK(physics_softbody_quadratic_aerodynamic_force(Vector3(0, 0, -1),
			Vector3(0, 0, -20), 1, 0, 3, real_t(0.2), 3, b));
	CHECK(a.is_equal_approx(b));
	CHECK(a.z > 0.0);
}

TEST_CASE("[Physics] Tangential skin drag is opt-in and dampens in-plane flow") {
	Vector3 per_node(7, 7, 7);
	CHECK(physics_softbody_quadratic_aerodynamic_force(
			Vector3(0, 0, 1), Vector3(10, 0, 0), 1, 0, 3, 1, 3, per_node));
	CHECK(per_node == Vector3());
	CHECK(physics_softbody_quadratic_aerodynamic_force(
			Vector3(0, 0, 1), Vector3(10, 0, 0), 1, real_t(0.2), 3, 1, 3, per_node));
	CHECK(Math::abs(per_node.x + 5.0) < real_t(0.001));
	CHECK(Math::abs(per_node.y) < real_t(0.001));
	CHECK(Math::abs(per_node.z) < real_t(0.001));
}

TEST_CASE("[Physics] Aerodynamic response never increases face mean kinetic energy") {
	for (int i = 1; i <= 256; ++i) {
		const real_t speed = real_t(i) * real_t(1.25);
		const Vector3 initial(speed, speed * real_t(0.4), -speed * real_t(0.2));
		Vector3 force;
		const real_t delta = real_t(0.001) * real_t(i);
		CHECK(physics_softbody_quadratic_aerodynamic_force(
				Vector3(0, 0, 1), initial, 4, real_t(0.3), 2, delta, 3, force));
		const Vector3 next = initial + delta * force;
		CHECK(next.length_squared() <= initial.length_squared() + real_t(0.01));
		CHECK(next.dot(initial) >= 0.0);
	}
}

TEST_CASE("[Physics] Pinned particles contribute no inverse mass") {
	Vector3 per_node;
	CHECK(physics_softbody_quadratic_aerodynamic_force(
			Vector3(0, 0, 1), Vector3(0, 0, 10), 3, 0, 2, 1, 1, per_node));
	const real_t new_mean = 10 + per_node.z / real_t(3);
	CHECK(Math::abs(new_mean - real_t(10.0 / (1.0 + 10.0 / 3.0))) < real_t(0.001));
	CHECK(physics_softbody_quadratic_aerodynamic_force(
			Vector3(0, 0, 1), Vector3(0, 0, 10), 3, 0, 2, 1, 0, per_node));
	CHECK(per_node == Vector3());
}

TEST_CASE("[Physics] Non-unit normals and extreme finite speeds remain robust") {
	Vector3 a;
	Vector3 b;
	CHECK(physics_softbody_quadratic_aerodynamic_force(Vector3(0, 0, 5),
			Vector3(0, 0, 10), 1, 0, 2, real_t(0.5), 3, a));
	CHECK(physics_softbody_quadratic_aerodynamic_force(Vector3(0, 0, 1),
			Vector3(0, 0, 10), 1, 0, 2, real_t(0.5), 3, b));
	CHECK(a.is_equal_approx(b));
	CHECK(physics_softbody_quadratic_aerodynamic_force(Vector3(0, 0, 1),
			Vector3(real_t(1e20), 0, real_t(-1e20)),
			real_t(1e10), real_t(0.2), real_t(1e10), real_t(1e10), real_t(1e10), a));
	CHECK(a.is_finite());
}

TEST_CASE("[Physics] Invalid input preserves aerodynamic force output") {
	const Vector3 sentinel(2, 3, 4);
	Vector3 result = sentinel;
	const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
	CHECK_FALSE(physics_softbody_quadratic_aerodynamic_force(
			Vector3(), Vector3(0, 0, 1), 1, 0, 1, 1, 3, result));
	CHECK_FALSE(physics_softbody_quadratic_aerodynamic_force(
			Vector3(0, 0, 1), Vector3(), nan, 0, 1, 1, 3, result));
	CHECK_FALSE(physics_softbody_quadratic_aerodynamic_force(
			Vector3(0, 0, 1), Vector3(), 1, -1, 1, 1, 3, result));
	CHECK_FALSE(physics_softbody_quadratic_aerodynamic_force(
			Vector3(0, 0, 1), Vector3(), 1, 0, 1, 0, 3, result));
	CHECK_FALSE(physics_softbody_quadratic_aerodynamic_force(
			Vector3(0, 0, 1), Vector3(), 1, 0, 1, 1, -1, result));
	CHECK(result == sentinel);
}

} // namespace TestPhysicsSoftBodyAerodynamicDrag
