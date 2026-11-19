/**************************************************************************/
/*  test_physics_xpbd_edge_friction.cpp                                   */
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

#include "servers/physics_xpbd_edge_friction.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_xpbd_edge_friction)

namespace TestPhysicsXPBDEdgeFriction {

static void make_edges(Vector3 &r_a, Vector3 &r_b, Vector3 &r_c, Vector3 &r_d) {
	r_a = Vector3(-1, 0, 0.01);
	r_b = Vector3(1, 0, 0.01);
	r_c = Vector3(0, -1, 0);
	r_d = Vector3(0, 1, 0);
}

TEST_CASE("[PhysicsEdgeFriction] Fixed second edge stops tangential slip") {
	Vector3 a, b, c, d;
	make_edges(a, b, c, d);
	const Vector3 old_c = c, old_d = d;
	CHECK(physics_xpbd_solve_edge_friction(a, b, c, d,
			a - Vector3(0.2, 0, 0), b - Vector3(0.2, 0, 0), c, d,
			1, 1, 0, 0, 1, 1, 0.05, Vector3(0, 0, 1)));
	CHECK(a.x == doctest::Approx(-1.2).epsilon(1e-5));
	CHECK(b.x == doctest::Approx(0.8).epsilon(1e-5));
	CHECK(a.z == doctest::Approx(0.01).epsilon(1e-5));
	CHECK(b.z == doctest::Approx(0.01).epsilon(1e-5));
	CHECK(c == old_c);
	CHECK(d == old_d);
}

TEST_CASE("[PhysicsEdgeFriction] Friction correction respects the Coulomb budget") {
	Vector3 a, b, c, d;
	make_edges(a, b, c, d);
	CHECK(physics_xpbd_solve_edge_friction(a, b, c, d,
			a - Vector3(0.2, 0, 0), b - Vector3(0.2, 0, 0), c, d,
			1, 1, 0, 0, 0.05, 0.5, 0.05, Vector3(0, 0, 1)));
	// Impulse cap is 0.025 and each free endpoint has weight 0.5.
	CHECK(a.x == doctest::Approx(-1.0125).epsilon(1e-5));
	CHECK(b.x == doctest::Approx(0.9875).epsilon(1e-5));
}

TEST_CASE("[PhysicsEdgeFriction] Movable edges conserve free-particle linear momentum") {
	Vector3 a, b, c, d;
	make_edges(a, b, c, d);
	const Vector3 old_a = a, old_b = b, old_c = c, old_d = d;
	CHECK(physics_xpbd_solve_edge_friction(a, b, c, d,
			a - Vector3(0.2, 0, 0), b - Vector3(0.2, 0, 0), c, d,
			1, 1, 1, 1, 1, 1, 0.05, Vector3(0, 0, 1)));
	CHECK(((a - old_a) + (b - old_b) + (c - old_c) + (d - old_d)).length() < real_t(1e-5));
	CHECK(a.x < old_a.x);
	CHECK(c.x > old_c.x);
}

TEST_CASE("[PhysicsEdgeFriction] Pinned first edge stays stationary") {
	Vector3 a, b, c, d;
	make_edges(a, b, c, d);
	const Vector3 old_a = a, old_b = b;
	CHECK(physics_xpbd_solve_edge_friction(a, b, c, d,
			a, b, c + Vector3(0.2, 0, 0), d + Vector3(0.2, 0, 0),
			0, 0, 1, 1, 1, 1, 0.05, Vector3(0, 0, 1)));
	CHECK(a == old_a);
	CHECK(b == old_b);
	CHECK(c.x > 0);
	CHECK(d.x > 0);
}

TEST_CASE("[PhysicsEdgeFriction] Normal motion alone does not create friction") {
	Vector3 a, b, c, d;
	make_edges(a, b, c, d);
	const Vector3 old_a = a, old_b = b, old_c = c, old_d = d;
	CHECK_FALSE(physics_xpbd_solve_edge_friction(a, b, c, d,
			a - Vector3(0, 0, 0.2), b - Vector3(0, 0, 0.2), c, d,
			1, 1, 1, 1, 1, 1, 0.05, Vector3(0, 0, 1)));
	CHECK(a == old_a);
	CHECK(b == old_b);
	CHECK(c == old_c);
	CHECK(d == old_d);
}

TEST_CASE("[PhysicsEdgeFriction] No normal reaction or zero friction is a no-op") {
	Vector3 a, b, c, d;
	make_edges(a, b, c, d);
	const Vector3 old_a = a, old_b = b;
	const Vector3 prev_a = a - Vector3(0.2, 0, 0);
	const Vector3 prev_b = b - Vector3(0.2, 0, 0);
	CHECK_FALSE(physics_xpbd_solve_edge_friction(a, b, c, d,
			prev_a, prev_b, c, d, 1, 1, 0, 0, 1, 0, 0.05, Vector3(0, 0, 1)));
	CHECK_FALSE(physics_xpbd_solve_edge_friction(a, b, c, d,
			prev_a, prev_b, c, d, 1, 1, 0, 0, 0, 1, 0.05, Vector3(0, 0, 1)));
	CHECK(a == old_a);
	CHECK(b == old_b);
}

TEST_CASE("[PhysicsEdgeFriction] Parallel and degenerate edges are rejected") {
	Vector3 a, b, c, d;
	make_edges(a, b, c, d);
	c = Vector3(-1, 0, 0);
	d = Vector3(1, 0, 0);
	const Vector3 old_a = a, old_b = b;
	CHECK_FALSE(physics_xpbd_solve_edge_friction(a, b, c, d,
			a - Vector3(0.2, 0, 0), b - Vector3(0.2, 0, 0), c, d,
			1, 1, 1, 1, 1, 1, 0.05, Vector3(0, 0, 1)));
	CHECK(a == old_a);
	CHECK(b == old_b);
}

TEST_CASE("[PhysicsEdgeFriction] Nonfinite and negative inputs cannot partially update positions") {
	Vector3 a, b, c, d;
	make_edges(a, b, c, d);
	const Vector3 old_a = a, old_b = b, old_c = c, old_d = d;
	const Vector3 prev_a = a - Vector3(0.2, 0, 0);
	const Vector3 prev_b = b - Vector3(0.2, 0, 0);
	CHECK_FALSE(physics_xpbd_solve_edge_friction(a, b, c, d,
			prev_a, prev_b, c, d, -1, 1, 1, 1, 1, 1, 0.05, Vector3(0, 0, 1)));
	CHECK_FALSE(physics_xpbd_solve_edge_friction(a, b, c, d,
			prev_a, prev_b, c, d, 1, 1, 1, 1,
			std::numeric_limits<real_t>::infinity(), 1, 0.05, Vector3(0, 0, 1)));
	CHECK_FALSE(physics_xpbd_solve_edge_friction(a, b, c, d,
			prev_a, prev_b, Vector3(std::numeric_limits<real_t>::infinity(), 0, 0), d,
			1, 1, 1, 1, 1, 1, 0.05, Vector3(0, 0, 1)));
	CHECK_FALSE(physics_xpbd_solve_edge_friction(a, b, c, d,
			prev_a, prev_b, c, d, 1, 1, 1, 1, 1, 1, 0.05, Vector3(0, 0, 0)));
	CHECK(a == old_a);
	CHECK(b == old_b);
	CHECK(c == old_c);
	CHECK(d == old_d);
}

} // namespace TestPhysicsXPBDEdgeFriction
