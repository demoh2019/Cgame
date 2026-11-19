/**************************************************************************/
/*  test_physics_xpbd_self_friction.cpp                                   */
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

#include "servers/physics_xpbd_self_friction.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_xpbd_self_friction)

namespace TestPhysicsXPBDSelfFriction {

// The reference face lies in z = 0; the vertex is inside the face at z = 0.01.
static void make_contact(Vector3 &r_vertex, Vector3 &r_a, Vector3 &r_b, Vector3 &r_c) {
	r_vertex = Vector3(0.45, 0.25, 0.01);
	r_a = Vector3(0, 0, 0);
	r_b = Vector3(1, 0, 0);
	r_c = Vector3(0, 1, 0);
}

TEST_CASE("[PhysicsSelfFriction] Static triangle stops tangential sliding without changing normal gap") {
	Vector3 vertex, a, b, c;
	make_contact(vertex, a, b, c);
	const Vector3 q_vertex(0.25, 0.25, 0.01);
	const Vector3 prev_a = a, prev_b = b, prev_c = c;
	CHECK(physics_xpbd_solve_self_friction(vertex, a, b, c,
			q_vertex, prev_a, prev_b, prev_c,
			1.0, 0.0, 0.0, 0.0, 1.0, 0.5, 0.05));
	CHECK(vertex.x == doctest::Approx(q_vertex.x).epsilon(1e-5));
	CHECK(vertex.y == doctest::Approx(q_vertex.y).epsilon(1e-5));
	CHECK(vertex.z == doctest::Approx(0.01).epsilon(1e-5));
	CHECK(a == prev_a);
	CHECK(b == prev_b);
	CHECK(c == prev_c);
}

TEST_CASE("[PhysicsSelfFriction] Coulomb budget caps per-step sliding correction") {
	Vector3 vertex, a, b, c;
	make_contact(vertex, a, b, c);
	const Vector3 q_vertex(0.25, 0.25, 0.01);
	CHECK(physics_xpbd_solve_self_friction(vertex, a, b, c,
			q_vertex, a, b, c, 1.0, 0.0, 0.0, 0.0, 0.05, 0.5, 0.05));
	// |lambda_t| <= mu * lambda_n = 0.025, inverse mass is 1.
	CHECK(vertex.x == doctest::Approx(0.425).epsilon(1e-5));
	CHECK(vertex.z == doctest::Approx(0.01).epsilon(1e-5));
}

TEST_CASE("[PhysicsSelfFriction] No normal contact reaction means no friction") {
	Vector3 vertex, a, b, c;
	make_contact(vertex, a, b, c);
	const Vector3 original = vertex;
	const Vector3 q_vertex(0.25, 0.25, 0.01);
	CHECK_FALSE(physics_xpbd_solve_self_friction(vertex, a, b, c,
			q_vertex, a, b, c, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.05));
	CHECK_FALSE(physics_xpbd_solve_self_friction(vertex, a, b, c,
			q_vertex, a, b, c, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.05));
	CHECK(vertex == original);
}

TEST_CASE("[PhysicsSelfFriction] Movable face shares tangential correction and conserves linear momentum") {
	Vector3 vertex, a, b, c;
	make_contact(vertex, a, b, c);
	const Vector3 original_vertex = vertex, original_a = a, original_b = b, original_c = c;
	const Vector3 prev_vertex(0.25, 0.25, 0.01);
	CHECK(physics_xpbd_solve_self_friction(vertex, a, b, c,
			prev_vertex, a, b, c, 1.0, 1.0, 1.0, 1.0, 1.0, 0.5, 0.05));
	const Vector3 sum = (vertex - original_vertex) + (a - original_a) +
			(b - original_b) + (c - original_c);
	CHECK(sum.length() < real_t(1e-5));
	CHECK(vertex.x < original_vertex.x);
	CHECK(a.x > original_a.x);
	CHECK(b.x > original_b.x);
	CHECK(c.x > original_c.x);
	CHECK(vertex.z == doctest::Approx(original_vertex.z).epsilon(1e-5));
}

TEST_CASE("[PhysicsSelfFriction] A pinned vertex stays fixed while the moving face loses slide") {
	Vector3 vertex, a, b, c;
	make_contact(vertex, a, b, c);
	const Vector3 original = vertex;
	// The face moved to the right by 0.2 relative to its previous positions.
	const Vector3 q_a = a - Vector3(0.2, 0, 0);
	const Vector3 q_b = b - Vector3(0.2, 0, 0);
	const Vector3 q_c = c - Vector3(0.2, 0, 0);
	CHECK(physics_xpbd_solve_self_friction(vertex, a, b, c,
			vertex, q_a, q_b, q_c, 0.0, 1.0, 1.0, 1.0, 1.0, 0.5, 0.05));
	CHECK(vertex == original);
	CHECK(a.x < real_t(0.0));
	CHECK(b.x < real_t(1.0));
	CHECK(c.x < real_t(0.0));
}

TEST_CASE("[PhysicsSelfFriction] Tangential relative translation only is invariant under world offset") {
	Vector3 vertex, a, b, c;
	make_contact(vertex, a, b, c);
	const Vector3 q_vertex(0.25, 0.25, 0.01);
	const Vector3 original_vertex = vertex, original_a = a, original_b = b, original_c = c;
	CHECK(physics_xpbd_solve_self_friction(vertex, a, b, c,
			q_vertex, a, b, c, 1.0, 0.0, 0.0, 0.0, 1.0, 0.5, 0.05));
	const Vector3 shift(100, -200, 50);
	Vector3 shifted_vertex = original_vertex + shift;
	Vector3 shifted_a = original_a + shift;
	Vector3 shifted_b = original_b + shift;
	Vector3 shifted_c = original_c + shift;
	CHECK(physics_xpbd_solve_self_friction(shifted_vertex, shifted_a, shifted_b, shifted_c,
			q_vertex + shift, original_a + shift, original_b + shift, original_c + shift,
			1.0, 0.0, 0.0, 0.0, 1.0, 0.5, 0.05));
	CHECK((shifted_vertex - shift).is_equal_approx(vertex));
}

TEST_CASE("[PhysicsSelfFriction] All pins and outside-face contacts do nothing") {
	Vector3 vertex, a, b, c;
	make_contact(vertex, a, b, c);
	const Vector3 old_vertex = vertex;
	const Vector3 q_vertex(0.25, 0.25, 0.01);
	CHECK_FALSE(physics_xpbd_solve_self_friction(vertex, a, b, c,
			q_vertex, a, b, c, 0.0, 0.0, 0.0, 0.0, 1.0, 0.5, 0.05));
	CHECK(vertex == old_vertex);
	vertex = Vector3(2, 2, 0.01);
	CHECK_FALSE(physics_xpbd_solve_self_friction(vertex, a, b, c,
			q_vertex, a, b, c, 1.0, 0.0, 0.0, 0.0, 1.0, 0.5, 0.05));
	CHECK(vertex == Vector3(2, 2, 0.01));
}

TEST_CASE("[PhysicsSelfFriction] Invalid inputs do not partially change any node") {
	Vector3 vertex, a, b, c;
	make_contact(vertex, a, b, c);
	const Vector3 old_vertex = vertex, old_a = a, old_b = b, old_c = c;
	const Vector3 prev_vertex(0.25, 0.25, 0.01);
	CHECK_FALSE(physics_xpbd_solve_self_friction(vertex, a, b, c, prev_vertex, a, b, c,
			-1.0, 1.0, 1.0, 1.0, 1.0, 0.5, 0.05));
	CHECK_FALSE(physics_xpbd_solve_self_friction(vertex, a, b, c, prev_vertex, a, b, c,
			1.0, 1.0, 1.0, 1.0, std::numeric_limits<real_t>::infinity(), 0.5, 0.05));
	CHECK_FALSE(physics_xpbd_solve_self_friction(vertex, a, b, c, prev_vertex, a, b, c,
			1.0, 1.0, 1.0, 1.0, 1.0, 0.5, 0.0));
	CHECK(vertex == old_vertex);
	CHECK(a == old_a);
	CHECK(b == old_b);
	CHECK(c == old_c);
}

} // namespace TestPhysicsXPBDSelfFriction
