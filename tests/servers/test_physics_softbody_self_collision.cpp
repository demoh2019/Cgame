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
#include "servers/physics_softbody_ccd.h"

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

TEST_CASE("[Physics] Self-collision edge pairs detect crossed segments with distant endpoints") {
	// The four endpoints are 1m from the crossing point, so a 5cm
	// vertex/triangle proximity check alone cannot detect the overlap.
	const Vector3 a(-1, 0, 0), b(1, 0, 0);
	const Vector3 c(0, -1, 0), d(0, 1, 0);
	Vector3 closest_ab, closest_cd;
	real_t s = -1, t = -1;
	REQUIRE(physics_softbody_closest_segment_points(a, b, c, d,
			closest_ab, closest_cd, s, t));
	CHECK(closest_ab.distance_to(closest_cd) < real_t(1e-5));
	CHECK(Math::abs(s - real_t(0.5)) < real_t(1e-5));
	CHECK(Math::abs(t - real_t(0.5)) < real_t(1e-5));

	// Both endpoints of AB are pinned. The crossing CD edge must separate
	// by the requested thickness, using the previous CD side.
	Vector3 pa = a, pb = b, pc = c, pd = d;
	const Vector3 old_c = c + Vector3(0, 0, -0.2);
	const Vector3 old_d = d + Vector3(0, 0, -0.2);
	REQUIRE(physics_softbody_project_edge_contact(pa, pb, pc, pd,
			0.0, 0.0, 1.0, 1.0, real_t(0.1), 0.0,
			a, b, old_c, old_d));
	CHECK(pa == a);
	CHECK(pb == b);
	REQUIRE(physics_softbody_closest_segment_points(pa, pb, pc, pd,
			closest_ab, closest_cd, s, t));
	CHECK(Math::abs(closest_ab.distance_to(closest_cd) - real_t(0.1)) < real_t(1e-5));
	CHECK(pc.z < 0.0);
	CHECK(pd.z < 0.0);
}

TEST_CASE("[Physics] Self-collision finite segments handle skew and parallel edges") {
	const Vector3 a(-1, 0, 0), b(1, 0, 0);
	Vector3 closest_ab, closest_cd;
	real_t s, t;

	// Interior closest points of two skew edges.
	REQUIRE(physics_softbody_closest_segment_points(a, b,
			Vector3(0, -1, 0.04), Vector3(0, 1, 0.04),
			closest_ab, closest_cd, s, t));
	CHECK(Math::abs(s - real_t(0.5)) < real_t(1e-5));
	CHECK(Math::abs(t - real_t(0.5)) < real_t(1e-5));
	CHECK(Math::abs(closest_ab.distance_to(closest_cd) - real_t(0.04)) < real_t(1e-5));

	// Clamped endpoints are required; infinite-line proximity would be wrong.
	REQUIRE(physics_softbody_closest_segment_points(a, b,
			Vector3(2, -1, 0), Vector3(2, 1, 0),
			closest_ab, closest_cd, s, t));
	CHECK(Math::abs(s - real_t(1.0)) < real_t(1e-5));
	CHECK(Math::abs(t - real_t(0.5)) < real_t(1e-5));
	CHECK(Math::abs(closest_ab.distance_to(closest_cd) - real_t(1.0)) < real_t(1e-5));

	// Parallel overlapping projected edges should not divide by zero.
	REQUIRE(physics_softbody_closest_segment_points(a, b,
			Vector3(-1, 0.04, 0), Vector3(1, 0.04, 0),
			closest_ab, closest_cd, s, t));
	CHECK(Math::abs(closest_ab.distance_to(closest_cd) - real_t(0.04)) < real_t(1e-5));
}

TEST_CASE("[Physics] Self-collision edge contact compliance and pinned particles") {
	const Vector3 a(-1, 0, 0), b(1, 0, 0);
	const Vector3 c(0, -1, 0.02), d(0, 1, 0.02);
	Vector3 stiff_a = a, stiff_b = b, stiff_c = c, stiff_d = d;
	Vector3 soft_a = a, soft_b = b, soft_c = c, soft_d = d;
	REQUIRE(physics_softbody_project_edge_contact(stiff_a, stiff_b, stiff_c, stiff_d,
			0, 0, 1, 1, real_t(0.1), 0, a, b, c, d));
	REQUIRE(physics_softbody_project_edge_contact(soft_a, soft_b, soft_c, soft_d,
			0, 0, 1, 1, real_t(0.1), 5, a, b, c, d));
	CHECK(stiff_a == a);
	CHECK(stiff_b == b);
	CHECK(soft_a == a);
	CHECK(soft_b == b);
	CHECK(stiff_c.z > soft_c.z);
	CHECK(stiff_d.z > soft_d.z);
	CHECK(stiff_c.is_finite());
	CHECK(stiff_d.is_finite());

	// Pinned endpoints on both edges: no contact impulse can be applied.
	Vector3 p_a = a, p_b = b, p_c = c, p_d = d;
	CHECK_FALSE(physics_softbody_project_edge_contact(p_a, p_b, p_c, p_d,
			0, 0, 0, 0, real_t(0.1), 0, a, b, c, d));
	CHECK(p_a == a);
	CHECK(p_c == c);
}

TEST_CASE("[Physics] Self-collision edge contact ignores degeneracy and invalid inputs") {
	Vector3 a(0, 0, 0), b(0, 0, 0), c(0, -1, 0), d(0, 1, 0);
	const Vector3 old_a = a, old_b = b;
	Vector3 on_ab, on_cd;
	real_t s, t;
	CHECK_FALSE(physics_softbody_closest_segment_points(a, b, c, d, on_ab, on_cd, s, t));
	CHECK_FALSE(physics_softbody_project_edge_contact(a, b, c, d,
			1, 1, 1, 1, 0.1, 0, a, b, c, d));
	CHECK(a == old_a);
	CHECK(b == old_b);

	b = Vector3(1, 0, 0);
	CHECK_FALSE(physics_softbody_project_edge_contact(a, b, c, d,
			1, 1, 1, 1, real_t(0.1), -1, a, b, c, d));
	CHECK_FALSE(physics_softbody_project_edge_contact(a, b, c, d,
			-1, 1, 1, 1, real_t(0.1), 0, a, b, c, d));
	CHECK_FALSE(physics_softbody_project_edge_contact(a, b, c, d,
			1, 1, 1, 1, real_t(0.1),
			std::numeric_limits<real_t>::infinity(), a, b, c, d));
	CHECK(a == old_a);
	CHECK(c == Vector3(0, -1, 0));
}

TEST_CASE("[Physics] Swept soft-body CCD catches vertex crossing a static triangle") {
	const Vector3 a(0, 0, 0), b(2, 0, 0), c(0, 2, 0);
	const Vector3 before(0.5, 0.5, 1), after(0.5, 0.5, -1);
	const real_t thickness = real_t(0.05);
	// Both endpoints are far outside the discrete thickness and would
	// be missed by a single end-of-step vertex/triangle proximity test.
	Vector3 closest, bary;
	REQUIRE(physics_softbody_closest_triangle_point(after, a, b, c, closest, bary));
	CHECK(after.distance_to(closest) > thickness);

	real_t toi = -1.0;
	CHECK(physics_softbody_ccd_point_triangle(before, after,
			a, a, b, b, c, c, thickness, toi));
	CHECK(toi > real_t(0.45));
	CHECK(toi < real_t(0.5));
	CHECK(before.lerp(after, toi).z > real_t(0.0));
	CHECK(before.lerp(after, toi).z < real_t(0.051));
}

TEST_CASE("[Physics] Swept soft-body CCD supports a moving triangle and crossing edges") {
	const Vector3 point(0.5, 0.5, 0);
	const Vector3 a(0, 0, 1), b(2, 0, 1), c(0, 2, 1);
	const Vector3 shift(0, 0, -2);
	real_t toi = -1.0;
	CHECK(physics_softbody_ccd_point_triangle(point, point,
			a, a + shift, b, b + shift, c, c + shift,
			real_t(0.05), toi));
	CHECK(toi > real_t(0.45));
	CHECK(toi < real_t(0.5));

	// The endpoints of each long edge remain far from the other edge,
	// so a vertex/face discrete test cannot detect this middle crossing.
	const Vector3 p(-1, 0, 0), q(1, 0, 0);
	const Vector3 r(0, -1, 1), s(0, 1, 1);
	toi = -1.0;
	CHECK(physics_softbody_ccd_edge_edge(p, p, q, q,
			r, r + shift, s, s + shift, real_t(0.05), toi));
	CHECK(toi > real_t(0.45));
	CHECK(toi < real_t(0.5));
}

TEST_CASE("[Physics] Swept soft-body CCD rejects near misses and zero relative motion") {
	const Vector3 a(0, 0, 0), b(2, 0, 0), c(0, 2, 0);
	real_t toi = real_t(0.75);
	CHECK_FALSE(physics_softbody_ccd_point_triangle(
			Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.3),
			a, a, b, b, c, c, real_t(0.05), toi));
	CHECK(toi == real_t(0.75)); // Failed CCD does not clobber output.
	CHECK_FALSE(physics_softbody_ccd_point_triangle(
			Vector3(0.5, 0.5, 0), Vector3(0.5, 0.5, 0.2),
			a, a, b, b, c, c, real_t(0.05), toi)); // Initially penetrating.
	CHECK_FALSE(physics_softbody_ccd_point_triangle(
			Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5),
			a, a, b, b, c, c, real_t(0.05), toi)); // Stationary.
	const Vector3 p(-1, 0, 0), q(1, 0, 0);
	CHECK_FALSE(physics_softbody_ccd_edge_edge(p, p, q, q,
			Vector3(0, -1, 0.3), Vector3(0, -1, 0.15),
			Vector3(0, 1, 0.3), Vector3(0, 1, 0.15), real_t(0.05), toi));
	CHECK(toi == real_t(0.75));
}

TEST_CASE("[Physics] Swept soft-body CCD preserves Galilean motion invariance") {
	const Vector3 a(0, 0, 0), b(2, 0, 0), c(0, 2, 0);
	const Vector3 shift(100, -30, 20);
	const Vector3 motion(1, 2, -3);
	real_t reference_t = -1, translated_t = -1;
	const Vector3 before(0.5, 0.5, 1), after(0.5, 0.5, -1);
	REQUIRE(physics_softbody_ccd_point_triangle(before, after,
			a, a, b, b, c, c, real_t(0.05), reference_t));
	REQUIRE(physics_softbody_ccd_point_triangle(before + shift, after + shift + motion,
			a + shift, a + shift + motion,
			b + shift, b + shift + motion,
			c + shift, c + shift + motion, real_t(0.05), translated_t));
	CHECK(Math::abs(reference_t - translated_t) < real_t(0.001));
}

} // namespace TestPhysicsSoftBodySelfCollision
