/**************************************************************************/
/*  test_physics_softbody_link_damping.cpp                                */
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

#include "servers/physics_softbody_link_damping.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_link_damping)

namespace TestPhysicsSoftBodyLinkDamping {

TEST_CASE("[PhysicsLinkDamping] Full damping removes longitudinal relative velocity") {
	Vector3 a(0, 3, 0), b(10, 5, 0);
	CHECK(physics_softbody_damp_link(Vector3(), Vector3(2, 0, 0), a, b, 1.0, 1.0, 1.0));
	CHECK(a.x == doctest::Approx(5.0));
	CHECK(b.x == doctest::Approx(5.0));
	CHECK(a.y == doctest::Approx(3.0));
	CHECK(b.y == doctest::Approx(5.0));
}

TEST_CASE("[PhysicsLinkDamping] One pinned particle stays fixed") {
	Vector3 pinned, free(8, 2, 0);
	CHECK(physics_softbody_damp_link(Vector3(), Vector3(1, 0, 0), pinned, free, 0.0, 2.0, 1.0));
	CHECK(pinned == Vector3());
	CHECK(free.x == doctest::Approx(0.0));
	CHECK(free.y == doctest::Approx(2.0));
}

TEST_CASE("[PhysicsLinkDamping] Asymmetric mass preserves center-of-mass momentum") {
	Vector3 heavy, light(8, 0, 0);
	CHECK(physics_softbody_damp_link(Vector3(), Vector3(1, 0, 0), heavy, light, 1.0, 3.0, 1.0));
	CHECK(heavy.x == doctest::Approx(2.0));
	CHECK(light.x == doctest::Approx(2.0));
	CHECK(heavy.x + light.x / 3.0 == doctest::Approx(8.0 / 3.0));
}

TEST_CASE("[PhysicsLinkDamping] Partial damping decreases kinetic energy without changing tangents") {
	Vector3 a(0, 1, 0), b(8, 4, 0);
	CHECK(physics_softbody_damp_link(Vector3(), Vector3(2, 0, 0), a, b, 1.0, 1.0, 0.25));
	CHECK(a.x == doctest::Approx(1.0));
	CHECK(b.x == doctest::Approx(7.0));
	CHECK(a.y == doctest::Approx(1.0));
	CHECK(b.y == doctest::Approx(4.0));
	CHECK(a.x * a.x + b.x * b.x < real_t(64.0));
}

TEST_CASE("[PhysicsLinkDamping] Rigid rotation does not generate damping") {
	Vector3 a(0, -4, 0), b(0, 4, 0);
	CHECK(physics_softbody_damp_link(Vector3(-1, 0, 0), Vector3(1, 0, 0), a, b, 1.0, 1.0, 1.0));
	CHECK(a == Vector3(0, -4, 0));
	CHECK(b == Vector3(0, 4, 0));
}

TEST_CASE("[PhysicsLinkDamping] Repeated half steps equal one three-quarter relaxation") {
	Vector3 a, b(8, 0, 0);
	CHECK(physics_softbody_damp_link(Vector3(), Vector3(1, 0, 0), a, b, 1.0, 1.0, 0.5));
	CHECK(physics_softbody_damp_link(Vector3(), Vector3(1, 0, 0), a, b, 1.0, 1.0, 0.5));
	Vector3 one_a, one_b(8, 0, 0);
	CHECK(physics_softbody_damp_link(Vector3(), Vector3(1, 0, 0), one_a, one_b, 1.0, 1.0, 0.75));
	CHECK(a.is_equal_approx(one_a));
	CHECK(b.is_equal_approx(one_b));
}

TEST_CASE("[PhysicsLinkDamping] Tiny and very large finite links remain valid") {
	Vector3 a, b(10, 0, 0);
	CHECK(physics_softbody_damp_link(Vector3(), Vector3(real_t(1e-8), 0, 0), a, b, 1.0, 1.0, 1.0));
	CHECK(a.x == doctest::Approx(5.0));
	CHECK(b.x == doctest::Approx(5.0));
	a = Vector3();
	b = Vector3(10, 0, 0);
	CHECK(physics_softbody_damp_link(Vector3(real_t(-1e20), 0, 0),
			Vector3(real_t(1e20), 0, 0), a, b, 1.0, 1.0, 1.0));
	CHECK(a.x == doctest::Approx(5.0));
	CHECK(b.x == doctest::Approx(5.0));
}

TEST_CASE("[PhysicsLinkDamping] Invalid and degenerate links do not alter velocities") {
	Vector3 a(1, 2, 3), b(4, 5, 6);
	const Vector3 orig_a = a, orig_b = b;
	CHECK_FALSE(physics_softbody_damp_link(Vector3(), Vector3(), a, b, 1.0, 1.0, 1.0));
	CHECK_FALSE(physics_softbody_damp_link(Vector3(), Vector3(1, 0, 0), a, b, 0.0, 0.0, 1.0));
	CHECK_FALSE(physics_softbody_damp_link(Vector3(), Vector3(1, 0, 0), a, b, -1.0, 1.0, 1.0));
	CHECK_FALSE(physics_softbody_damp_link(Vector3(), Vector3(1, 0, 0), a, b, 1.0, 1.0, 1.1));
	CHECK_FALSE(physics_softbody_damp_link(Vector3(), Vector3(1, 0, 0), a, b, 1.0, 1.0,
			std::numeric_limits<double>::infinity()));
	CHECK(a == orig_a);
	CHECK(b == orig_b);
}

} // namespace TestPhysicsSoftBodyLinkDamping
