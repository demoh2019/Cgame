/**************************************************************************/
/*  test_physics_softbody_self_collision.cpp                               */
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

TEST_FORCE_LINK(test_physics_softbody_self_collision)

#include "servers/physics_softbody_self_collision.h"

#include <limits>

namespace TestPhysicsSoftBodySelfCollision {

TEST_CASE("[Physics] Self-collision triangle closest point covers all Voronoi regions") {
	const Vector3 a(0, 0, 0), b(1, 0, 0), c(0, 1, 0);
	Vector3 closest, bary;
	REQUIRE(physics_softbody_closest_triangle_point(Vector3(0.25, 0.25, 0.7), a, b, c, closest, bary));
	CHECK(closest.distance_to(Vector3(0.25, 0.25, 0)) < real_t(1e-5));
	CHECK(bary.distance_to(Vector3(0.5, 0.25, 0.25)) < real_t(1e-5));
	REQUIRE(physics_softbody_closest_triangle_point(Vector3(-1, -1, 0), a, b, c, closest, bary));
	CHECK(closest == a);
	CHECK(bary == Vector3(1, 0, 0));
	REQUIRE(physics_softbody_closest_triangle_point(Vector3(2, 0, 0), a, b, c, closest, bary));
	CHECK(closest == b);
	CHECK(bary == Vector3(0, 1, 0));
	REQUIRE(physics_softbody_closest_triangle_point(Vector3(0, 2, 0), a, b, c, closest, bary));
	CHECK(closest == c);
	CHECK(bary == Vector3(0, 0, 1));
	REQUIRE(physics_softbody_closest_triangle_point(Vector3(2, 2, 0), a, b, c, closest, bary));
	CHECK(closest.distance_to(Vector3(0.5, 0.5, 0)) < real_t(1e-5));
	CHECK(bary.distance_to(Vector3(0, 0.5, 0.5)) < real_t(1e-5));
	REQUIRE(physics_softbody_closest_triangle_point(Vector3(-1, 0.2, 0), a, b, c, closest, bary));
	CHECK(closest.distance_to(Vector3(0, 0.2, 0)) < real_t(1e-5));
	REQUIRE(physics_softbody_closest_triangle_point(Vector3(0.2, -1, 0), a, b, c, closest, bary));
	CHECK(closest.distance_to(Vector3(0.2, 0, 0)) < real_t(1e-5));
}

TEST_CASE("[Physics] Self-collision separates vertex from pinned triangle to thickness") {
	Vector3 p(0.25, 0.25, 0.02), a(0, 0, 0), b(1, 0, 0), c(0, 1, 0);
	const Vector3 prior_a = a, prior_b = b, prior_c = c;
	CHECK(physics_softbody_project_self_contact(p, a, b, c,
			1, 0, 0, 0, real_t(0.1), 0, Vector3(0.25, 0.25, 0.2)));
	CHECK(Math::abs(p.z - real_t(0.1)) < real_t(1e-5));
	CHECK(a == prior_a);
	CHECK(b == prior_b);
	CHECK(c == prior_c);
	CHECK_FALSE(physics_softbody_project_self_contact(p, a, b, c,
			1, 0, 0, 0, real_t(0.1), 0, p));

	// Coincident vertex/face: choose the side from previous position.
	p = Vector3(0.25, 0.25, 0.0);
	CHECK(physics_softbody_project_self_contact(p, a, b, c,
			1, 0, 0, 0, real_t(0.1), 0, Vector3(0.25, 0.25, -0.2)));
	CHECK(Math::abs(p.z + real_t(0.1)) < real_t(1e-5));
}

TEST_CASE("[Physics] Self-collision mass weighting respects pinned vertices and compliant contacts") {
	Vector3 pinned_point(0.25, 0.25, 0.01), a(0, 0, 0), b(1, 0, 0), c(0, 1, 0);
	const Vector3 old_point = pinned_point;
	CHECK(physics_softbody_project_self_contact(pinned_point, a, b, c,
			0, 1, 1, 1, real_t(0.1), 0, old_point));
	CHECK(pinned_point == old_point);
	CHECK(a.z < 0.0 || b.z < 0.0 || c.z < 0.0);
	CHECK(a.is_finite());
	CHECK(b.is_finite());
	CHECK(c.is_finite());

	Vector3 stiff(0.25, 0.25, 0.01), compliant = stiff;
	Vector3 a0(0, 0, 0), b0(1, 0, 0), c0(0, 1, 0);
	Vector3 a1 = a0, b1 = b0, c1 = c0;
	CHECK(physics_softbody_project_self_contact(stiff, a0, b0, c0,
			1, 0, 0, 0, real_t(0.1), 0, stiff));
	CHECK(physics_softbody_project_self_contact(compliant, a1, b1, c1,
			1, 0, 0, 0, real_t(0.1), 5, compliant));
	CHECK(stiff.z > compliant.z);

	const Vector3 all_fixed_p(0.2, 0.2, 0.01);
	Vector3 fixed_p = all_fixed_p, fixed_a(0, 0, 0), fixed_b(1, 0, 0), fixed_c(0, 1, 0);
	CHECK_FALSE(physics_softbody_project_self_contact(fixed_p, fixed_a, fixed_b, fixed_c,
			0, 0, 0, 0, real_t(0.1), 0, all_fixed_p));
	CHECK(fixed_p == all_fixed_p);
}

TEST_CASE("[Physics] Self-collision rejects invalid and degenerate triangles without mutation") {
	Vector3 p(0.25, 0.25, 0), a(0, 0, 0), b(1, 0, 0), c(0, 1, 0);
	const Vector3 original_p = p;
	CHECK_FALSE(physics_softbody_project_self_contact(p, a, b, c,
			1, 1, 1, 1, 0, 0, p));
	CHECK_FALSE(physics_softbody_project_self_contact(p, a, b, c,
			1, 1, 1, 1, real_t(0.1), -1, p));
	CHECK_FALSE(physics_softbody_project_self_contact(p, a, b, c,
			-1, 1, 1, 1, real_t(0.1), 0, p));
	CHECK_FALSE(physics_softbody_project_self_contact(p, a, b, c,
			1, 1, 1, 1, real_t(0.1),
			std::numeric_limits<real_t>::infinity(), p));
	CHECK(p == original_p);
	b = a; // Zero-area triangle.
	Vector3 closest, bary;
	CHECK_FALSE(physics_softbody_closest_triangle_point(p, a, b, c, closest, bary));
	CHECK_FALSE(physics_softbody_project_self_contact(p, a, b, c,
			1, 1, 1, 1, real_t(0.1), 0, p));
	CHECK(p == original_p);
}

} // namespace TestPhysicsSoftBodySelfCollision
