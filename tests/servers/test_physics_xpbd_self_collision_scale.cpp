/**************************************************************************/
/*  test_physics_xpbd_self_collision_scale.cpp                            */
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

#include "servers/physics_xpbd_self_collision.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_xpbd_self_collision_scale)

namespace TestXPBDSelfCollisionScale {

TEST_CASE("[PhysicsSelfCollisionScale] Large finite triangles do not overflow cross products") {
	const real_t scale = real_t(1e20);
	const Vector3 p(real_t(0.25) * scale, real_t(0.25) * scale, real_t(0.01) * scale);
	const Vector3 a, b(scale, 0, 0), c(0, scale, 0);
	Vector3 normal, bary;
	real_t signed_distance = 0;
	CHECK(physics_xpbd_self_collision_face_projection(p, a, b, c, normal, bary, signed_distance));
	CHECK(normal.x == doctest::Approx(0.0).epsilon(1e-5));
	CHECK(normal.y == doctest::Approx(0.0).epsilon(1e-5));
	CHECK(normal.z == doctest::Approx(1.0).epsilon(1e-5));
	CHECK(bary.x == doctest::Approx(0.5).epsilon(1e-5));
	CHECK(bary.y == doctest::Approx(0.25).epsilon(1e-5));
	CHECK(bary.z == doctest::Approx(0.25).epsilon(1e-5));
	CHECK(signed_distance / scale == doctest::Approx(0.01).epsilon(1e-5));
}

TEST_CASE("[PhysicsSelfCollisionScale] Small valid triangles are not discarded by absolute epsilon") {
	const real_t scale = real_t(1e-8);
	const Vector3 p(real_t(0.25) * scale, real_t(0.25) * scale, real_t(0.1) * scale);
	const Vector3 a, b(scale, 0, 0), c(0, scale, 0);
	Vector3 normal, bary;
	real_t signed_distance = 0;
	CHECK(physics_xpbd_self_collision_face_projection(p, a, b, c, normal, bary, signed_distance));
	CHECK(normal.z == doctest::Approx(1.0).epsilon(1e-5));
	CHECK(bary.x == doctest::Approx(0.5).epsilon(1e-5));
	CHECK(bary.y == doctest::Approx(0.25).epsilon(1e-5));
	CHECK(bary.z == doctest::Approx(0.25).epsilon(1e-5));
	CHECK(signed_distance / scale == doctest::Approx(0.1).epsilon(1e-5));
}

TEST_CASE("[PhysicsSelfCollisionScale] Reversed winding flips normal and signed distance") {
	const Vector3 p(real_t(0.2), real_t(0.3), real_t(0.1));
	const Vector3 a, b(1, 0, 0), c(0, 1, 0);
	Vector3 normal, bary;
	real_t signed_distance = 0;
	CHECK(physics_xpbd_self_collision_face_projection(p, a, c, b, normal, bary, signed_distance));
	CHECK(normal.z == doctest::Approx(-1.0).epsilon(1e-5));
	CHECK(signed_distance == doctest::Approx(-0.1).epsilon(1e-5));
	CHECK(bary.x == doctest::Approx(0.5).epsilon(1e-5));
	CHECK(bary.y == doctest::Approx(0.3).epsilon(1e-5));
	CHECK(bary.z == doctest::Approx(0.2).epsilon(1e-5));
}

TEST_CASE("[PhysicsSelfCollisionScale] Nearly collinear faces are rejected without changing outputs") {
	Vector3 normal(3, 4, 5), bary(6, 7, 8);
	real_t signed_distance = 9;
	CHECK_FALSE(physics_xpbd_self_collision_face_projection(
			Vector3(real_t(0.5), 0, 0), Vector3(), Vector3(1, 0, 0),
			Vector3(2, real_t(1e-12), 0), normal, bary, signed_distance));
	CHECK(normal == Vector3(3, 4, 5));
	CHECK(bary == Vector3(6, 7, 8));
	CHECK(signed_distance == real_t(9));
}

TEST_CASE("[PhysicsSelfCollisionScale] Outside-face and invalid positions leave outputs unchanged") {
	Vector3 normal(3, 4, 5), bary(6, 7, 8);
	real_t signed_distance = 9;
	const Vector3 a, b(1, 0, 0), c(0, 1, 0);
	CHECK_FALSE(physics_xpbd_self_collision_face_projection(
			Vector3(2, 2, real_t(0.01)), a, b, c, normal, bary, signed_distance));
	CHECK_FALSE(physics_xpbd_self_collision_face_projection(
			Vector3(std::numeric_limits<real_t>::infinity(), 0, 0), a, b, c,
			normal, bary, signed_distance));
	CHECK(normal == Vector3(3, 4, 5));
	CHECK(bary == Vector3(6, 7, 8));
	CHECK(signed_distance == real_t(9));
}

TEST_CASE("[PhysicsSelfCollisionScale] Normal XPBD contact solver supports huge finite pinned triangles") {
	const real_t scale = real_t(1e20);
	Vector3 vertex(real_t(0.25) * scale, real_t(0.25) * scale, real_t(0.001) * scale);
	Vector3 a, b(scale, 0, 0), c(0, scale, 0);
	real_t lambda = 0;
	CHECK(physics_xpbd_solve_self_collision(vertex, a, b, c,
			1.0, 0.0, 0.0, 0.0, real_t(0.01) * scale, 0.0, 1, lambda));
	CHECK(lambda > real_t(0.0));
	CHECK(vertex.is_finite());
	CHECK(vertex.z / scale == doctest::Approx(0.01).epsilon(1e-5));
	CHECK(a == Vector3());
	CHECK(b == Vector3(scale, 0, 0));
	CHECK(c == Vector3(0, scale, 0));
}

} // namespace TestXPBDSelfCollisionScale
