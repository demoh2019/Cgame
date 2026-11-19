/**************************************************************************/
/*  test_physics_softbody_pair_edge_sweep.cpp                             */
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
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER ARISING FROM, OUT OF OR IN */
/* CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
/**************************************************************************/

#include "servers/physics_softbody_pair_edge_sweep.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_pair_edge_sweep)

namespace TestPhysicsSoftBodyPairEdgeSweep {

static const Vector3 A(-1, 0, 0);
static const Vector3 B(1, 0, 0);
static const Vector3 C(0, -1, 0);
static const Vector3 D(0, 1, 0);

TEST_CASE("[PhysicsSoftPairEdgeSweep] Fast crossing detected despite separated endpoints") {
	const Vector3 prev_a = A + Vector3(0, 0, -0.38);
	const Vector3 prev_b = B + Vector3(0, 0, -0.38);
	const Vector3 curr_a = A + Vector3(0, 0, 0.28);
	const Vector3 curr_b = B + Vector3(0, 0, 0.28);
	PhysicsSoftBodyPairEdgeSweepHit hit;
	REQUIRE(physics_softbody_swept_edge_edge(prev_a, curr_a, prev_b, curr_b,
			C, C, D, D, 0.1, hit));
	CHECK(hit.time == doctest::Approx((0.38 - 0.1) / 0.66).epsilon(1e-4));
	CHECK(hit.s == doctest::Approx(0.5));
	CHECK(hit.t == doctest::Approx(0.5));
	CHECK(hit.normal.z < real_t(-0.9));
	// Neither endpoint is within the contact thickness.
	CHECK(curr_a.z > real_t(0.1));
	CHECK(curr_b.z > real_t(0.1));
}

TEST_CASE("[PhysicsSoftPairEdgeSweep] Swept hit produces two-way position and velocity response") {
	const Vector3 prev_a = A + Vector3(0, 0, -0.38);
	const Vector3 prev_b = B + Vector3(0, 0, -0.38);
	Vector3 a = A + Vector3(0, 0, 0.28);
	Vector3 b = B + Vector3(0, 0, 0.28);
	Vector3 c = C, d = D;
	PhysicsSoftBodyPairEdgeSweepHit hit;
	REQUIRE(physics_softbody_swept_edge_edge(prev_a, a, prev_b, b,
			c, c, d, d, 0.1, hit));
	Vector3 va(0, 0, 33), vb(0, 0, 33), vc, vd;
	const Vector3 before_momentum = va + vb + vc / 2.0 + vd / 3.0;
	real_t lambda = 0;
	REQUIRE(physics_softbody_solve_swept_pair_edges(a, b, c, d,
			va, vb, vc, vd, 1.0, 1.0, 2.0, 3.0, 0.1, 0.0, hit, 0.02, lambda));
	CHECK(lambda > 0.0);
	CHECK(a.z < real_t(0.28));
	CHECK(b.z < real_t(0.28));
	CHECK(c.z > real_t(0.0));
	CHECK(d.z > real_t(0.0));
	CHECK((va + vb + vc / 2.0 + vd / 3.0).is_equal_approx(before_momentum));
	CHECK((a.z - c.z) < real_t(0.28));
}

TEST_CASE("[PhysicsSoftPairEdgeSweep] Fast opposite body motion works and swaps hit normal") {
	const Vector3 prev_c = C + Vector3(0, 0, 0.38);
	const Vector3 prev_d = D + Vector3(0, 0, 0.38);
	const Vector3 curr_c = C + Vector3(0, 0, -0.28);
	const Vector3 curr_d = D + Vector3(0, 0, -0.28);
	PhysicsSoftBodyPairEdgeSweepHit hit;
	REQUIRE(physics_softbody_swept_edge_edge(A, A, B, B,
			prev_c, curr_c, prev_d, curr_d, 0.1, hit));
	CHECK(hit.time == doctest::Approx((0.38 - 0.1) / 0.66).epsilon(1e-4));
	CHECK(hit.normal.z < real_t(-0.9));
	PhysicsSoftBodyPairEdgeSweepHit reversed;
	REQUIRE(physics_softbody_swept_edge_edge(
			prev_c, curr_c, prev_d, curr_d, A, A, B, B, 0.1, reversed));
	CHECK(hit.time == doctest::Approx(reversed.time).epsilon(1e-5));
	CHECK(hit.normal.dot(reversed.normal) < real_t(-0.9));
}

TEST_CASE("[PhysicsSoftPairEdgeSweep] Pinned mesh remains fixed and other mesh separates") {
	const Vector3 prev_a = A + Vector3(0, 0, -0.38);
	const Vector3 prev_b = B + Vector3(0, 0, -0.38);
	Vector3 a = A + Vector3(0, 0, 0.28), b = B + Vector3(0, 0, 0.28);
	Vector3 c = C, d = D;
	Vector3 va(0, 0, 33), vb(0, 0, 33), vc, vd;
	PhysicsSoftBodyPairEdgeSweepHit hit;
	REQUIRE(physics_softbody_swept_edge_edge(prev_a, a, prev_b, b,
			c, c, d, d, 0.1, hit));
	const Vector3 prev_c = c, prev_d = d;
	real_t lambda = 0;
	REQUIRE(physics_softbody_solve_swept_pair_edges(a, b, c, d,
			va, vb, vc, vd, 1.0, 1.0, 0.0, 0.0, 0.1, 0.0, hit, 0.02, lambda));
	CHECK(c == prev_c);
	CHECK(d == prev_d);
	CHECK(vc == Vector3());
	CHECK(vd == Vector3());
	CHECK(a.z == doctest::Approx(-0.1).epsilon(1e-5));
	CHECK(b.z == doctest::Approx(-0.1).epsilon(1e-5));
}

TEST_CASE("[PhysicsSoftPairEdgeSweep] No crossing, initial proximity, and degenerate segments") {
	PhysicsSoftBodyPairEdgeSweepHit hit;
	CHECK_FALSE(physics_softbody_swept_edge_edge(
			A + Vector3(0, 0, -0.38), A + Vector3(0, 0, -0.8),
			B + Vector3(0, 0, -0.38), B + Vector3(0, 0, -0.8),
			C, C, D, D, 0.1, hit));
	CHECK_FALSE(physics_softbody_swept_edge_edge(
			A + Vector3(0, 0, -0.03), A + Vector3(0, 0, 0.3),
			B + Vector3(0, 0, -0.03), B + Vector3(0, 0, 0.3),
			C, C, D, D, 0.1, hit));
	CHECK_FALSE(physics_softbody_swept_edge_edge(
			A, A, A, A, C, C, D, D, 0.1, hit));
	CHECK_FALSE(physics_softbody_swept_edge_edge(
			A, A, B, B, C, C, D, D, 0.1, hit));
}

TEST_CASE("[PhysicsSoftPairEdgeSweep] Invalid inputs do not modify output") {
	PhysicsSoftBodyPairEdgeSweepHit hit;
	hit.time = 0.77;
	CHECK_FALSE(physics_softbody_swept_edge_edge(
			A, A, B, B, C, C, D, D,
			std::numeric_limits<real_t>::quiet_NaN(), hit));
	CHECK(hit.time == doctest::Approx(0.77));
	Vector3 a = A, b = B, c = C, d = D, va, vb, vc, vd;
	const Vector3 old_a = a, old_b = b, old_c = c, old_d = d;
	hit.time = 0.5;
	hit.normal = Vector3(0, 0, 1);
	hit.s = 0.5;
	hit.t = 0.5;
	real_t lambda = 0.0;
	CHECK_FALSE(physics_softbody_solve_swept_pair_edges(a, b, c, d,
			va, vb, vc, vd, 1.0, 1.0, 1.0, 1.0, 0.1, 0.0, hit, 0.0, lambda));
	CHECK_FALSE(physics_softbody_solve_swept_pair_edges(a, b, c, d,
			va, vb, vc, vd, -1.0, 1.0, 1.0, 1.0, 0.1, 0.0, hit, 0.02, lambda));
	CHECK(a == old_a);
	CHECK(b == old_b);
	CHECK(c == old_c);
	CHECK(d == old_d);
	CHECK(va == Vector3());
	CHECK(vb == Vector3());
	CHECK(vc == Vector3());
	CHECK(vd == Vector3());
	CHECK(lambda == 0.0);
}

} // namespace TestPhysicsSoftBodyPairEdgeSweep
