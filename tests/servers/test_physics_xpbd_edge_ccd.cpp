/**************************************************************************/
/*  test_physics_xpbd_edge_ccd.cpp                                        */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
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

#include "tests/test_macros.h"
#include "servers/physics_xpbd_edge_ccd.h"

TEST_FORCE_LINK(test_physics_xpbd_edge_ccd)

namespace TestPhysicsXPBDEdgeCCD {

TEST_CASE("[Physics] Swept edge-edge CCD catches a fast crossing with distant final endpoints") {
	const Vector3 a(-1, 0, 0), b(1, 0, 0);
	const Vector3 c(0, -1, 1), d(0, 1, 1);
	const Vector3 velocity(0, 0, -2);
	const Vector3 end_c = c + velocity, end_d = d + velocity;
	real_t s, t, distance;
	Vector3 normal;
	REQUIRE(physics_xpbd_closest_edges(a, b, end_c, end_d, s, t, normal, distance));
	CHECK(distance > real_t(0.5)); // Discrete final-time test misses crossing.

	PhysicsXPBDEdgeCCDHit hit;
	REQUIRE(physics_xpbd_swept_edge_edge(a, a, b, b,
			c, end_c, d, end_d, hit));
	CHECK(hit.time == doctest::Approx(0.5).epsilon(0.0001));
	CHECK(hit.s == doctest::Approx(0.5).epsilon(0.0001));
	CHECK(hit.t == doctest::Approx(0.5).epsilon(0.0001));
	CHECK(hit.normal.z < real_t(-0.9));

	// Rewind to slightly before impact; only the moving upper edge may
	// move. Project using the impact-time witness and fixed separating side.
	Vector3 fixed_a = a, fixed_b = b;
	Vector3 movable_c = c.lerp(end_c, hit.time - real_t(0.0001));
	Vector3 movable_d = d.lerp(end_d, hit.time - real_t(0.0001));
	real_t lambda = 0.0;
	REQUIRE(physics_xpbd_solve_swept_edge_edge(fixed_a, fixed_b, movable_c, movable_d,
			0, 0, 1, 1, real_t(0.1), 0, hit, lambda));
	CHECK(fixed_a == a);
	CHECK(fixed_b == b);
	CHECK(movable_c.z >= real_t(0.099));
	CHECK(movable_d.z >= real_t(0.099));
	CHECK(lambda > 0.0);
}

TEST_CASE("[Physics] Swept edge-edge CCD rejects non-crossing, parallel and infinite-line contacts") {
	const Vector3 a(-1, 0, 0), b(1, 0, 0);
	const Vector3 c(0, -1, 1), d(0, 1, 1);
	const Vector3 shift(0, 0, -2);
	PhysicsXPBDEdgeCCDHit hit;
	CHECK_FALSE(physics_xpbd_swept_edge_edge(a, a, b, b,
			c, c + Vector3(0, 0, -0.3), d, d + Vector3(0, 0, -0.3), hit));
	CHECK_FALSE(physics_xpbd_swept_edge_edge(a, a, b, b,
			c + Vector3(2.5, 0, 0), c + Vector3(2.5, 0, 0) + shift,
			d + Vector3(2.5, 0, 0), d + Vector3(2.5, 0, 0) + shift, hit));
	// Coplanar/parallel projections do not define a reliable single
	// edge-edge crossing: they are left to the discrete solver.
	const Vector3 parallel_c(-1, 0, 1), parallel_d(1, 0, 1);
	CHECK_FALSE(physics_xpbd_swept_edge_edge(a, a, b, b,
			parallel_c, parallel_c + shift, parallel_d, parallel_d + shift, hit));
	CHECK_FALSE(physics_xpbd_swept_edge_edge(a, a, b, b,
			c, c, d, d, hit));
	CHECK(hit.time == 1.0); // Failed queries must not modify output.
}

TEST_CASE("[Physics] Swept edge-edge CCD is translation and common-velocity invariant") {
	const Vector3 a(-1, 0, 0), b(1, 0, 0);
	const Vector3 c(0, -1, 1), d(0, 1, 1), shift(0, 0, -2);
	const Vector3 offset(150, -23, 11), velocity(3, -1, 2);
	PhysicsXPBDEdgeCCDHit base, moved;
	REQUIRE(physics_xpbd_swept_edge_edge(a, a, b, b,
			c, c + shift, d, d + shift, base));
	REQUIRE(physics_xpbd_swept_edge_edge(a + offset, a + offset + velocity,
			b + offset, b + offset + velocity,
			c + offset, c + offset + velocity + shift,
			d + offset, d + offset + velocity + shift, moved));
	CHECK(Math::abs(moved.time - base.time) < real_t(0.00005));
	CHECK(Math::abs(moved.s - base.s) < real_t(0.00005));
	CHECK(Math::abs(moved.t - base.t) < real_t(0.00005));
}

TEST_CASE("[Physics] Swept edge XPBD projection is pin-safe and rejects invalid witnesses") {
	const Vector3 a(-1, 0, 0), b(1, 0, 0), c(0, -1, 0.02), d(0, 1, 0.02);
	PhysicsXPBDEdgeCCDHit hit;
	hit.s = 0.5;
	hit.t = 0.5;
	hit.time = 0.5;
	hit.normal = Vector3(0, 0, -1);
	Vector3 pa = a, pb = b, pc = c, pd = d;
	real_t lambda = 0.0;
	CHECK_FALSE(physics_xpbd_solve_swept_edge_edge(pa, pb, pc, pd,
			0, 0, 0, 0, real_t(0.1), 0, hit, lambda));
	CHECK(pa == a);
	CHECK(pc == c);
	CHECK(lambda == real_t(0.0));
	CHECK_FALSE(physics_xpbd_solve_swept_edge_edge(pa, pb, pc, pd,
			1, 1, 1, 1, real_t(0.1), -1, hit, lambda));
	hit.s = 1.2; // Invalid barycentric witness must never move vertices.
	CHECK_FALSE(physics_xpbd_solve_swept_edge_edge(pa, pb, pc, pd,
			1, 1, 1, 1, real_t(0.1), 0, hit, lambda));
	CHECK(pa == a);
	CHECK(pb == b);
	CHECK(pc == c);
	CHECK(pd == d);
}

} // namespace TestPhysicsXPBDEdgeCCD
