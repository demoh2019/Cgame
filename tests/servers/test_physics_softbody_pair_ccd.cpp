/**************************************************************************/
/*  test_physics_softbody_pair_ccd.cpp                                    */
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
/* MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "servers/physics_softbody_pair_ccd.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_physics_softbody_pair_ccd)

namespace TestPhysicsSoftBodyPairCCD {

static const Vector3 A(0, 0, 0);
static const Vector3 B(1, 0, 0);
static const Vector3 C(0, 1, 0);

TEST_CASE("[PhysicsSoftPairCCD] Fast vertex crosses stationary pinned triangle") {
	const Vector3 prev_vertex(0.2, 0.3, 1.0);
	Vector3 vertex(0.2, 0.3, -1.0);
	Vector3 a = A, b = B, c = C;
	PhysicsXPBDSoftCCDSweepHit hit;
	REQUIRE(physics_xpbd_swept_vertex_triangle(prev_vertex, vertex,
			a, a, b, b, c, c, hit));
	CHECK(hit.time == doctest::Approx(0.5).epsilon(1e-4));
	CHECK(hit.separating_normal.z > 0.0);
	Vector3 vv(0, 0, -100), va, vb, vc;
	real_t lambda = 0.0;
	REQUIRE(physics_softbody_solve_pair_swept_face(vertex, a, b, c,
			vv, va, vb, vc, 1.0, 0.0, 0.0, 0.0,
			0.05, 0.0, hit, 0.02, lambda));
	CHECK(vertex.z == doctest::Approx(0.05).epsilon(1e-5));
	CHECK(vv.z == doctest::Approx(-47.5).epsilon(1e-5));
	CHECK(a == A);
	CHECK(b == B);
	CHECK(c == C);
	CHECK(va == Vector3());
	CHECK(vb == Vector3());
	CHECK(vc == Vector3());
	CHECK(lambda > 0.0);
}

TEST_CASE("[PhysicsSoftPairCCD] Swept moving triangle transmits impulse to face only") {
	Vector3 vertex(0.2, 0.3, 0.0);
	const Vector3 prev_a(0, 0, 1), prev_b(1, 0, 1), prev_c(0, 1, 1);
	Vector3 a(0, 0, -1), b(1, 0, -1), c(0, 1, -1);
	PhysicsXPBDSoftCCDSweepHit hit;
	REQUIRE(physics_xpbd_swept_vertex_triangle(vertex, vertex,
			prev_a, a, prev_b, b, prev_c, c, hit));
	CHECK(hit.time == doctest::Approx(0.5).epsilon(1e-4));
	CHECK(hit.separating_normal.z < 0.0);
	Vector3 vv, va(0, 0, -100), vb(0, 0, -100), vc(0, 0, -100);
	real_t lambda = 0.0;
	REQUIRE(physics_softbody_solve_pair_swept_face(vertex, a, b, c,
			vv, va, vb, vc, 0.0, 1.0, 1.0, 1.0,
			0.05, 0.0, hit, 0.02, lambda));
	CHECK(vertex == Vector3(0.2, 0.3, 0.0));
	CHECK(vv == Vector3());
	CHECK(a.z > -1.0);
	CHECK(b.z > -1.0);
	CHECK(c.z > -1.0);
	CHECK(va.z > -100.0);
	CHECK(lambda > 0.0);
}

TEST_CASE("[PhysicsSoftPairCCD] Mass-weighted two-way crossing conserves momentum") {
	const Vector3 prev_vertex(0.2, 0.3, 1.0);
	Vector3 vertex(0.2, 0.3, -1.0), a = A, b = B, c = C;
	PhysicsXPBDSoftCCDSweepHit hit;
	REQUIRE(physics_xpbd_swept_vertex_triangle(prev_vertex, vertex,
			a, a, b, b, c, c, hit));
	Vector3 vv(0, 0, -100), va, vb, vc;
	const Vector3 momentum_before = vv + va / 2.0 + vb * 2.0 + vc / 3.0;
	real_t lambda = 0.0;
	REQUIRE(physics_softbody_solve_pair_swept_face(vertex, a, b, c,
			vv, va, vb, vc, 1.0, 2.0, 0.5, 3.0,
			0.05, 0.0, hit, 0.02, lambda));
	CHECK((vv + va / 2.0 + vb * 2.0 + vc / 3.0).is_equal_approx(momentum_before));
	CHECK(vertex.z > -1.0);
	CHECK(a.z < 0.0);
	CHECK(b.z < 0.0);
	CHECK(c.z < 0.0);
}

TEST_CASE("[PhysicsSoftPairCCD] Uncrossed and outside-triangle sweeps do not collide") {
	PhysicsXPBDSoftCCDSweepHit hit;
	CHECK_FALSE(physics_xpbd_swept_vertex_triangle(
			Vector3(0.2, 0.3, 1), Vector3(0.2, 0.3, 0.2),
			A, A, B, B, C, C, hit));
	CHECK_FALSE(physics_xpbd_swept_vertex_triangle(
			Vector3(2, 2, 1), Vector3(2, 2, -1),
			A, A, B, B, C, C, hit));
	CHECK_FALSE(physics_xpbd_swept_vertex_triangle(
			Vector3(0.2, 0.3, 1), Vector3(0.2, 0.3, -1),
			A, A, A, A, C, C, hit));
}

TEST_CASE("[PhysicsSoftPairCCD] Invalid dt and time leave positions and velocities untouched") {
	Vector3 vertex(0.2, 0.3, -1.0), a = A, b = B, c = C;
	Vector3 vv(0, 0, -100), va, vb, vc;
	PhysicsXPBDSoftCCDSweepHit hit;
	REQUIRE(physics_xpbd_swept_vertex_triangle(
			Vector3(0.2, 0.3, 1), vertex, a, a, b, b, c, c, hit));
	const Vector3 old_vertex = vertex, old_vv = vv;
	real_t lambda = 0.0;
	CHECK_FALSE(physics_softbody_solve_pair_swept_face(vertex, a, b, c,
			vv, va, vb, vc, 1.0, 0.0, 0.0, 0.0,
			0.05, 0.0, hit, 0.0, lambda));
	hit.time = 2.0;
	CHECK_FALSE(physics_softbody_solve_pair_swept_face(vertex, a, b, c,
			vv, va, vb, vc, 1.0, 0.0, 0.0, 0.0,
			0.05, 0.0, hit, 0.02, lambda));
	CHECK(vertex == old_vertex);
	CHECK(vv == old_vv);
	CHECK(a == A);
	CHECK(b == B);
	CHECK(c == C);
	CHECK(lambda == 0.0);
}

} // namespace TestPhysicsSoftBodyPairCCD
