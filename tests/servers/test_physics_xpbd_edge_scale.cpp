/**************************************************************************/
/*  test_physics_xpbd_edge_scale.cpp                                      */
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

#include "servers/physics_xpbd_edge_collision.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_xpbd_edge_scale)

namespace TestXPBDEdgeScale {

TEST_CASE("[PhysicsEdgeScale] Skew interior edges return closest point and separating normal") {
	const Vector3 a(-1, 0, 0), b(1, 0, 0), c(0, -1, real_t(0.1)), d(0, 1, real_t(0.1));
	real_t s = real_t(-5), t = real_t(-5), distance = real_t(-5);
	Vector3 normal(3, 4, 5);
	REQUIRE(physics_xpbd_closest_edges(a, b, c, d, s, t, normal, distance));
	CHECK(s == doctest::Approx(0.5).epsilon(1e-5));
	CHECK(t == doctest::Approx(0.5).epsilon(1e-5));
	CHECK(normal.z == doctest::Approx(-1.0).epsilon(1e-5));
	CHECK(distance == doctest::Approx(0.1).epsilon(1e-5));
}

TEST_CASE("[PhysicsEdgeScale] Large finite edge vectors avoid float32 squared-length overflow") {
	const real_t scale = real_t(1e20);
	const Vector3 a(-scale, 0, 0), b(scale, 0, 0);
	const Vector3 c(0, -scale, scale * real_t(0.1)), d(0, scale, scale * real_t(0.1));
	real_t s, t, distance;
	Vector3 normal;
	REQUIRE(physics_xpbd_closest_edges(a, b, c, d, s, t, normal, distance));
	CHECK(s == doctest::Approx(0.5).epsilon(1e-5));
	CHECK(t == doctest::Approx(0.5).epsilon(1e-5));
	CHECK(normal.z == doctest::Approx(-1.0).epsilon(1e-5));
	CHECK(distance / scale == doctest::Approx(0.1).epsilon(1e-5));
}

TEST_CASE("[PhysicsEdgeScale] Tiny valid edge lengths are independent of world-unit epsilon") {
	const real_t scale = real_t(1e-8);
	const Vector3 a(-scale, 0, 0), b(scale, 0, 0);
	const Vector3 c(0, -scale, scale * real_t(0.1)), d(0, scale, scale * real_t(0.1));
	real_t s, t, distance;
	Vector3 normal;
	REQUIRE(physics_xpbd_closest_edges(a, b, c, d, s, t, normal, distance));
	CHECK(s == doctest::Approx(0.5).epsilon(1e-5));
	CHECK(t == doctest::Approx(0.5).epsilon(1e-5));
	CHECK(normal.z == doctest::Approx(-1.0).epsilon(1e-5));
	CHECK(distance / scale == doctest::Approx(0.1).epsilon(1e-5));
}

TEST_CASE("[PhysicsEdgeScale] Crossing edges use scale-independent cross-normal fallback") {
	const real_t scale = real_t(1e-8);
	const Vector3 a(-scale, 0, 0), b(scale, 0, 0), c(0, -scale, 0), d(0, scale, 0);
	real_t s, t, distance;
	Vector3 normal;
	REQUIRE(physics_xpbd_closest_edges(a, b, c, d, s, t, normal, distance));
	CHECK(distance == doctest::Approx(0.0));
	CHECK(normal.z == doctest::Approx(1.0).epsilon(1e-5));
	CHECK(s == doctest::Approx(0.5).epsilon(1e-5));
	CHECK(t == doctest::Approx(0.5).epsilon(1e-5));
}

TEST_CASE("[PhysicsEdgeScale] Parallel and endpoint contacts leave all outputs untouched") {
	real_t s = real_t(-5), t = real_t(-6), distance = real_t(-7);
	Vector3 normal(3, 4, 5);
	CHECK_FALSE(physics_xpbd_closest_edges(
			Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), s, t, normal, distance));
	CHECK_FALSE(physics_xpbd_closest_edges(
			Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(1, -1, 0),
			Vector3(1, 1, 0), s, t, normal, distance));
	CHECK_FALSE(physics_xpbd_closest_edges(
			Vector3(), Vector3(std::numeric_limits<real_t>::infinity(), 0, 0),
			Vector3(0, -1, 0), Vector3(0, 1, 0), s, t, normal, distance));
	CHECK(s == real_t(-5));
	CHECK(t == real_t(-6));
	CHECK(distance == real_t(-7));
	CHECK(normal == Vector3(3, 4, 5));
}

TEST_CASE("[PhysicsEdgeScale] Translation preserves closest pair for moderate offsets") {
	const Vector3 a(-1, 0, 0), b(1, 0, 0), c(0, -1, real_t(0.25)), d(0, 1, real_t(0.25));
	const Vector3 offset(1024, -2048, 128);
	real_t s0, t0, distance0, s1, t1, distance1;
	Vector3 normal0, normal1;
	REQUIRE(physics_xpbd_closest_edges(a, b, c, d, s0, t0, normal0, distance0));
	REQUIRE(physics_xpbd_closest_edges(a + offset, b + offset, c + offset, d + offset,
			s1, t1, normal1, distance1));
	CHECK(s0 == doctest::Approx(s1).epsilon(1e-5));
	CHECK(t0 == doctest::Approx(t1).epsilon(1e-5));
	CHECK(distance0 == doctest::Approx(distance1).epsilon(1e-5));
	CHECK(normal0.is_equal_approx(normal1));
}

TEST_CASE("[PhysicsEdgeScale] XPBD edge correction handles large finite geometry and two pins") {
	const real_t scale = real_t(1e20);
	Vector3 a(-scale, 0, 0), b(scale, 0, 0);
	Vector3 c(0, -scale, scale * real_t(0.1)), d(0, scale, scale * real_t(0.1));
	real_t s, t, distance;
	Vector3 normal;
	REQUIRE(physics_xpbd_closest_edges(a, b, c, d, s, t, normal, distance));
	real_t lambda = real_t(0);
	CHECK(physics_xpbd_solve_edge_collision(a, b, c, d,
			real_t(1), real_t(1), real_t(0), real_t(0),
			scale * real_t(0.2), real_t(0), normal, lambda));
	CHECK(lambda > real_t(0));
	CHECK(a.is_finite());
	CHECK(b.is_finite());
	CHECK(a.z / scale == doctest::Approx(-0.1).epsilon(1e-5));
	CHECK(b.z / scale == doctest::Approx(-0.1).epsilon(1e-5));
	CHECK(c.z / scale == doctest::Approx(0.1).epsilon(1e-5));
	CHECK(d.z / scale == doctest::Approx(0.1).epsilon(1e-5));
}

} // namespace TestXPBDEdgeScale
