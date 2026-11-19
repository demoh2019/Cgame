/**************************************************************************/
/*  test_physics_softbody_pair_contact.cpp                               */
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

#include "servers/physics_softbody_pair_contact.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_pair_contact)

namespace TestPhysicsSoftbodyPairContact {

TEST_CASE("[PhysicsSoftSoft] Dynamic vertex and triangle exchange momentum") {
	Vector3 v(0.25, 0.25, 0.02), a(0, 0, 0), b(1, 0, 0), c(0, 1, 0);
	Vector3 vv, va, vb, vc;
	const Vector3 old_v = v, old_a = a, old_b = b, old_c = c;
	real_t lambda = 0.0;
	CHECK(physics_softbody_solve_pair_vertex_face(v, a, b, c, vv, va, vb, vc,
			1.0, 2.0, 2.0, 2.0, 0.1, 0.0, 1, real_t(0.02), lambda));
	CHECK(v.z > old_v.z);
	CHECK(a.z < old_a.z);
	CHECK(b.z < old_b.z);
	CHECK(c.z < old_c.z);
	CHECK(lambda > 0.0);
	// Inverse mass 2 means half the mass of the vertex.
	const real_t weighted_displacement = v.z - old_v.z +
			real_t(0.5) * ((a.z - old_a.z) + (b.z - old_b.z) + (c.z - old_c.z));
	CHECK(Math::abs(weighted_displacement) < real_t(1e-5));
	CHECK(vv.z == doctest::Approx((v.z - old_v.z) / real_t(0.02)).epsilon(1e-5));
	CHECK(va.z == doctest::Approx((a.z - old_a.z) / real_t(0.02)).epsilon(1e-5));
}

TEST_CASE("[PhysicsSoftSoft] Pinned face receives no position or velocity correction") {
	Vector3 v(0.25, 0.25, 0.02), a(0, 0, 0), b(1, 0, 0), c(0, 1, 0);
	Vector3 vv, va, vb, vc;
	const Vector3 old_a = a, old_b = b, old_c = c;
	real_t lambda = 0.0;
	CHECK(physics_softbody_solve_pair_vertex_face(v, a, b, c, vv, va, vb, vc,
			1.0, 0.0, 0.0, 0.0, 0.1, 0.0, 1, real_t(0.01), lambda));
	CHECK(v.z == doctest::Approx(0.1).epsilon(1e-5));
	CHECK(a == old_a);
	CHECK(b == old_b);
	CHECK(c == old_c);
	CHECK(va == Vector3());
	CHECK(vb == Vector3());
	CHECK(vc == Vector3());
}

TEST_CASE("[PhysicsSoftSoft] Pinned vertex transfers penetration to movable face") {
	Vector3 v(0.25, 0.25, -0.02), a(0, 0, 0), b(1, 0, 0), c(0, 1, 0);
	Vector3 vv, va, vb, vc;
	real_t lambda = 0.0;
	CHECK(physics_softbody_solve_pair_vertex_face(v, a, b, c, vv, va, vb, vc,
			0.0, 1.0, 1.0, 1.0, 0.1, 0.0, -1, real_t(0.02), lambda));
	CHECK(v == Vector3(0.25, 0.25, -0.02));
	CHECK(vv == Vector3());
	CHECK(a.z > 0.0);
	CHECK(b.z > 0.0);
	CHECK(c.z > 0.0);
}

TEST_CASE("[PhysicsSoftSoft] Separate layers do not attract") {
	Vector3 v(0.25, 0.25, 0.4), a(0, 0, 0), b(1, 0, 0), c(0, 1, 0);
	Vector3 vv, va, vb, vc;
	real_t lambda = 0.0;
	const Vector3 original = v;
	CHECK_FALSE(physics_softbody_solve_pair_vertex_face(v, a, b, c, vv, va, vb, vc,
			1.0, 1.0, 1.0, 1.0, 0.1, 0.0, 1, real_t(0.01), lambda));
	CHECK(v == original);
	CHECK(lambda == real_t(0.0));
}

TEST_CASE("[PhysicsSoftSoft] Invalid timestep and fully pinned contact are atomic") {
	Vector3 v(0.25, 0.25, 0.02), a(0, 0, 0), b(1, 0, 0), c(0, 1, 0);
	Vector3 vv(1, 0, 0), va, vb, vc;
	const Vector3 old_v = v, old_a = a, old_b = b, old_c = c, old_vv = vv;
	real_t lambda = 0.0;
	CHECK_FALSE(physics_softbody_solve_pair_vertex_face(v, a, b, c, vv, va, vb, vc,
			1.0, 1.0, 1.0, 1.0, 0.1, 0.0, 1, 0.0, lambda));
	CHECK_FALSE(physics_softbody_solve_pair_vertex_face(v, a, b, c, vv, va, vb, vc,
			0.0, 0.0, 0.0, 0.0, 0.1, 0.0, 1, 0.01, lambda));
	CHECK_FALSE(physics_softbody_solve_pair_vertex_face(v, a, b, c, vv, va, vb, vc,
			1.0, 1.0, 1.0, 1.0, 0.1, 0.0, 1,
			std::numeric_limits<real_t>::infinity(), lambda));
	CHECK(v == old_v);
	CHECK(a == old_a);
	CHECK(b == old_b);
	CHECK(c == old_c);
	CHECK(vv == old_vv);
	CHECK(lambda == 0.0);
}

} // namespace TestPhysicsSoftbodyPairContact
