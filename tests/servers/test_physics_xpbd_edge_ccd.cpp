/**************************************************************************/
/*  test_physics_xpbd_edge_ccd.cpp                                        */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "servers/physics_xpbd_edge_ccd.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_xpbd_edge_ccd)

namespace TestPhysicsXPBDEdgeCCD {

static void crossing(Vector3 &r_prev_a, Vector3 &r_curr_a,
		Vector3 &r_prev_b, Vector3 &r_curr_b,
		Vector3 &r_c, Vector3 &r_d) {
	r_prev_a = Vector3(-1, 0, 0.4);
	r_prev_b = Vector3(1, 0, 0.4);
	r_curr_a = Vector3(-1, 0, -0.4);
	r_curr_b = Vector3(1, 0, -0.4);
	r_c = Vector3(0, -1, 0);
	r_d = Vector3(0, 1, 0);
}

TEST_CASE("[PhysicsEdgeCCD] Swept interior crossing detected after tunnelling") {
	Vector3 a0, a1, b0, b1, c, d;
	crossing(a0, a1, b0, b1, c, d);
	PhysicsXPBDEdgeCCDHit hit;
	CHECK(physics_xpbd_swept_edges(a0, a1, b0, b1, c, c, d, d, 0.12, hit));
	CHECK(hit.time == doctest::Approx(0.5).epsilon(1e-5));
	CHECK(hit.first_weight == doctest::Approx(0.5).epsilon(1e-5));
	CHECK(hit.second_weight == doctest::Approx(0.5).epsilon(1e-5));
	CHECK(hit.separating_normal.z == doctest::Approx(1.0).epsilon(1e-5));
}

TEST_CASE("[PhysicsEdgeCCD] Impact witness restores the previous side despite distant endpoint") {
	Vector3 a0, a1, b0, b1, c, d;
	crossing(a0, a1, b0, b1, c, d);
	PhysicsXPBDEdgeCCDHit hit;
	REQUIRE(physics_xpbd_swept_edges(a0, a1, b0, b1, c, c, d, d, 0.12, hit));
	real_t lambda = 0.0;
	CHECK(physics_xpbd_solve_swept_edges(a1, b1, c, d,
			1, 1, 0, 0, 0.12, 0, hit, lambda));
	CHECK(a1.z == doctest::Approx(0.12).epsilon(1e-5));
	CHECK(b1.z == doctest::Approx(0.12).epsilon(1e-5));
	CHECK(c == Vector3(0, -1, 0));
	CHECK(d == Vector3(0, 1, 0));
	CHECK(lambda > 0);
}

TEST_CASE("[PhysicsEdgeCCD] Moving second edge and pins preserve first edge") {
	Vector3 a0, a1, b0, b1, c, d;
	crossing(a0, a1, b0, b1, c, d);
	const Vector3 fixed_a(-1, 0, 0), fixed_b(1, 0, 0);
	const Vector3 c0(0, -1, 0.4), d0(0, 1, 0.4);
	Vector3 c1(0, -1, -0.4), d1(0, 1, -0.4);
	PhysicsXPBDEdgeCCDHit hit;
	REQUIRE(physics_xpbd_swept_edges(fixed_a, fixed_a, fixed_b, fixed_b,
			c0, c1, d0, d1, 0.12, hit));
	CHECK(hit.separating_normal.z == doctest::Approx(-1.0).epsilon(1e-5));
	Vector3 a = fixed_a, b = fixed_b;
	real_t lambda = 0;
	CHECK(physics_xpbd_solve_swept_edges(a, b, c1, d1,
			0, 0, 1, 1, 0.12, 0, hit, lambda));
	CHECK(a == fixed_a);
	CHECK(b == fixed_b);
	CHECK(c1.z == doctest::Approx(0.12).epsilon(1e-5));
	CHECK(d1.z == doctest::Approx(0.12).epsilon(1e-5));
}

TEST_CASE("[PhysicsEdgeCCD] Symmetric free contact conserves linear momentum") {
	Vector3 a0, a1, b0, b1, c, d;
	crossing(a0, a1, b0, b1, c, d);
	PhysicsXPBDEdgeCCDHit hit;
	REQUIRE(physics_xpbd_swept_edges(a0, a1, b0, b1, c, c, d, d, 0.12, hit));
	const Vector3 original_a = a1, original_b = b1, original_c = c, original_d = d;
	real_t lambda = 0;
	REQUIRE(physics_xpbd_solve_swept_edges(a1, b1, c, d,
			1, 1, 1, 1, 0.12, 0, hit, lambda));
	CHECK(((a1 - original_a) + (b1 - original_b) +
			(c - original_c) + (d - original_d)).length() < real_t(1e-5));
	CHECK(a1.z > original_a.z);
	CHECK(c.z < original_c.z);
}

TEST_CASE("[PhysicsEdgeCCD] Plane crossing outside segment interiors is rejected") {
	Vector3 a0, a1, b0, b1, c, d;
	crossing(a0, a1, b0, b1, c, d);
	a0.x += 5;
	a1.x += 5;
	b0.x += 5;
	b1.x += 5;
	PhysicsXPBDEdgeCCDHit hit;
	CHECK_FALSE(physics_xpbd_swept_edges(a0, a1, b0, b1, c, c, d, d, 0.12, hit));
}

TEST_CASE("[PhysicsEdgeCCD] Uncrossed, parallel and static coplanar edges are skipped") {
	Vector3 a0, a1, b0, b1, c, d;
	crossing(a0, a1, b0, b1, c, d);
	PhysicsXPBDEdgeCCDHit hit;
	CHECK_FALSE(physics_xpbd_swept_edges(a0, a0, b0, b0, c, c, d, d, 0.12, hit));
	CHECK_FALSE(physics_xpbd_swept_edges(a0, a1, b0, b1,
			Vector3(-1, 1, 0), Vector3(-1, 1, 0),
			Vector3(1, 1, 0), Vector3(1, 1, 0), 0.12, hit));
	CHECK_FALSE(physics_xpbd_swept_edges(Vector3(-1, 0, 0), Vector3(-1, 0, 0),
			Vector3(1, 0, 0), Vector3(1, 0, 0), c, c, d, d, 0.12, hit));
}

TEST_CASE("[PhysicsEdgeCCD] Invalid masses, fully pinned contact and nonfinite values are atomic") {
	Vector3 a0, a1, b0, b1, c, d;
	crossing(a0, a1, b0, b1, c, d);
	PhysicsXPBDEdgeCCDHit hit;
	REQUIRE(physics_xpbd_swept_edges(a0, a1, b0, b1, c, c, d, d, 0.12, hit));
	const Vector3 old_a = a1, old_b = b1, old_c = c, old_d = d;
	real_t lambda = 0;
	CHECK_FALSE(physics_xpbd_solve_swept_edges(a1, b1, c, d,
			0, 0, 0, 0, 0.12, 0, hit, lambda));
	CHECK_FALSE(physics_xpbd_solve_swept_edges(a1, b1, c, d,
			-1, 1, 1, 1, 0.12, 0, hit, lambda));
	CHECK_FALSE(physics_xpbd_solve_swept_edges(a1, b1, c, d,
			1, 1, 1, 1, 0.12, -1, hit, lambda));
	lambda = std::numeric_limits<real_t>::infinity();
	CHECK_FALSE(physics_xpbd_solve_swept_edges(a1, b1, c, d,
			1, 1, 1, 1, 0.12, 0, hit, lambda));
	CHECK(a1 == old_a);
	CHECK(b1 == old_b);
	CHECK(c == old_c);
	CHECK(d == old_d);
	lambda = 0;
	const real_t inf = std::numeric_limits<real_t>::infinity();
	CHECK_FALSE(physics_xpbd_swept_edges(a0, Vector3(inf, 0, 0),
			b0, b1, c, c, d, d, 0.12, hit));
}

} // namespace TestPhysicsXPBDEdgeCCD
