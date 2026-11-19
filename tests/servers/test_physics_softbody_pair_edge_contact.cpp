/**************************************************************************/
/*  test_physics_softbody_pair_edge_contact.cpp                           */
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

#include "servers/physics_softbody_pair_edge_contact.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_pair_edge_contact)

namespace TestPhysicsSoftbodyPairEdgeContact {

TEST_CASE("[PhysicsSoftPairEdges] Crossing cloth edges separate both meshes") {
	Vector3 a(-1, 0, 0), b(1, 0, 0);
	Vector3 c(0, -1, 0.02), d(0, 1, 0.02);
	Vector3 va, vb, vc, vd;
	real_t s, t, distance;
	Vector3 normal;
	REQUIRE(physics_xpbd_closest_edges(a, b, c, d, s, t, normal, distance));
	CHECK(s == doctest::Approx(0.5));
	CHECK(t == doctest::Approx(0.5));
	CHECK(distance == doctest::Approx(0.02).epsilon(1e-5));
	real_t lambda = 0.0;
	CHECK(physics_softbody_solve_pair_edge_contact(a, b, c, d,
			va, vb, vc, vd, 1.0, 1.0, 1.0, 1.0,
			0.1, 0.0, normal, 0.02, lambda));
	CHECK(a.z < 0.0);
	CHECK(b.z < 0.0);
	CHECK(c.z > 0.02);
	CHECK(d.z > 0.02);
	CHECK(lambda > 0.0);
	CHECK((va + vb + vc + vd).length() < real_t(1e-5));
	CHECK(va.z == doctest::Approx(a.z / real_t(0.02)).epsilon(1e-5));
}

TEST_CASE("[PhysicsSoftPairEdges] Fully pinned first edge keeps exact position") {
	Vector3 a(-1, 0, 0), b(1, 0, 0);
	Vector3 c(0, -1, 0.02), d(0, 1, 0.02);
	Vector3 va, vb, vc, vd;
	real_t s, t, distance;
	Vector3 normal;
	REQUIRE(physics_xpbd_closest_edges(a, b, c, d, s, t, normal, distance));
	real_t lambda = 0.0;
	CHECK(physics_softbody_solve_pair_edge_contact(a, b, c, d,
			va, vb, vc, vd, 0.0, 0.0, 1.0, 1.0,
			0.1, 0.0, normal, 0.02, lambda));
	CHECK(a == Vector3(-1, 0, 0));
	CHECK(b == Vector3(1, 0, 0));
	CHECK(va == Vector3());
	CHECK(vb == Vector3());
	CHECK(c.z > real_t(0.02));
	CHECK(d.z > real_t(0.02));
	CHECK(vc.z > 0.0);
	CHECK(vd.z > 0.0);
}

TEST_CASE("[PhysicsSoftPairEdges] Unequal inverse masses conserve linear momentum") {
	Vector3 a(-1, 0, 0), b(1, 0, 0);
	Vector3 c(0, -1, 0.02), d(0, 1, 0.02);
	Vector3 va, vb, vc, vd;
	real_t s, t, distance;
	Vector3 normal;
	REQUIRE(physics_xpbd_closest_edges(a, b, c, d, s, t, normal, distance));
	real_t lambda = 0.0;
	CHECK(physics_softbody_solve_pair_edge_contact(a, b, c, d,
			va, vb, vc, vd, 2.0, 0.5, 3.0, 1.5,
			0.1, 0.0, normal, 0.02, lambda));
	const Vector3 momentum = va / 2.0 + vb / 0.5 + vc / 3.0 + vd / 1.5;
	CHECK(momentum.length() < real_t(1e-5));
	CHECK(lambda > 0.0);
}

TEST_CASE("[PhysicsSoftPairEdges] No edge proximity or parallel edge contact") {
	Vector3 a(-1, 0, 0), b(1, 0, 0);
	Vector3 c(0, -1, 1), d(0, 1, 1);
	Vector3 va, vb, vc, vd;
	real_t s, t, distance;
	Vector3 normal;
	REQUIRE(physics_xpbd_closest_edges(a, b, c, d, s, t, normal, distance));
	real_t lambda = 0.0;
	CHECK_FALSE(physics_softbody_solve_pair_edge_contact(a, b, c, d,
			va, vb, vc, vd, 1.0, 1.0, 1.0, 1.0,
			0.1, 0.0, normal, 0.02, lambda));
	CHECK(lambda == 0.0);
	CHECK_FALSE(physics_xpbd_closest_edges(
			Vector3(-1, 0, 0), Vector3(1, 0, 0),
			Vector3(-1, 0, 0.01), Vector3(1, 0, 0.01),
			s, t, normal, distance));
}

TEST_CASE("[PhysicsSoftPairEdges] Invalid dt and inverse masses are transactional") {
	Vector3 a(-1, 0, 0), b(1, 0, 0);
	Vector3 c(0, -1, 0.02), d(0, 1, 0.02);
	const Vector3 old_a = a, old_b = b, old_c = c, old_d = d;
	Vector3 va(3, 0, 0), vb, vc, vd;
	const Vector3 old_va = va;
	real_t s, t, distance;
	Vector3 normal;
	REQUIRE(physics_xpbd_closest_edges(a, b, c, d, s, t, normal, distance));
	real_t lambda = 0.0;
	CHECK_FALSE(physics_softbody_solve_pair_edge_contact(a, b, c, d,
			va, vb, vc, vd, 1.0, 1.0, 1.0, 1.0,
			0.1, 0.0, normal, 0.0, lambda));
	CHECK_FALSE(physics_softbody_solve_pair_edge_contact(a, b, c, d,
			va, vb, vc, vd, -1.0, 1.0, 1.0, 1.0,
			0.1, 0.0, normal, 0.02, lambda));
	CHECK_FALSE(physics_softbody_solve_pair_edge_contact(a, b, c, d,
			va, vb, vc, vd, 1.0, 1.0, 1.0, 1.0,
			0.1, 0.0, normal, std::numeric_limits<real_t>::infinity(), lambda));
	CHECK(a == old_a);
	CHECK(b == old_b);
	CHECK(c == old_c);
	CHECK(d == old_d);
	CHECK(va == old_va);
	CHECK(vb == Vector3());
	CHECK(vc == Vector3());
	CHECK(vd == Vector3());
	CHECK(lambda == 0.0);
}

TEST_CASE("[PhysicsSoftPairEdges] Exact crossing uses stable edge normal") {
	Vector3 a(-1, 0, 0), b(1, 0, 0);
	Vector3 c(0, -1, 0), d(0, 1, 0);
	Vector3 va, vb, vc, vd;
	real_t s, t, distance;
	Vector3 normal;
	REQUIRE(physics_xpbd_closest_edges(a, b, c, d, s, t, normal, distance));
	CHECK(distance == doctest::Approx(0.0));
	CHECK(Math::abs(normal.z) > real_t(0.9));
	real_t lambda = 0.0;
	CHECK(physics_softbody_solve_pair_edge_contact(a, b, c, d,
			va, vb, vc, vd, 1.0, 1.0, 1.0, 1.0,
			0.1, 0.0, normal, 0.02, lambda));
	CHECK(lambda > 0.0);
	CHECK(Math::abs(a.z - c.z) > real_t(0.0));
}

} // namespace TestPhysicsSoftbodyPairEdgeContact
