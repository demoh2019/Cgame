/**************************************************************************/
/*  test_physics_speculative_capsule_pair_contact.cpp                     */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "servers/physics_speculative_capsule_pair_contact.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_physics_speculative_capsule_pair_contact)

namespace TestPhysicsSpeculativeCapsulePairContact {

TEST_CASE("[PhysicsSpeculativeCapsulePair] Parallel 2D capsules use surface anchors") {
	Vector2 a, b, normal;
	CHECK(physics_speculative_capsule_pair_contact(
			Vector2(-4, 0), Vector2(), Vector2(0, 1), Vector2(0, 1),
			real_t(1), real_t(1), real_t(0.5), real_t(0.5),
			Vector2(5, 0), real_t(4), a, b, normal));
	CHECK(normal.is_equal_approx(Vector2(1, 0)));
	CHECK(Math::is_equal_approx((a - b).dot(normal), real_t(-3)));
	CHECK(Math::is_equal_approx((b - a).dot(-normal), real_t(-3)));
}

TEST_CASE("[PhysicsSpeculativeCapsulePair] Skew 2D capsules preserve earliest TOI") {
	Vector2 a, b, normal;
	CHECK(physics_speculative_capsule_pair_contact(
			Vector2(-4, 0), Vector2(), Vector2(0, 1), Vector2(1, 0),
			real_t(1), real_t(1), real_t(0.5), real_t(0.5),
			Vector2(4, 0), real_t(3), a, b, normal));
	CHECK(normal.is_equal_approx(Vector2(1, 0)));
	CHECK(Math::is_equal_approx((a - b).dot(normal), real_t(-2)));
	CHECK_FALSE(physics_speculative_capsule_pair_contact(
			Vector2(-4, 3), Vector2(), Vector2(0, 1), Vector2(1, 0),
			real_t(1), real_t(1), real_t(0.5), real_t(0.5),
			Vector2(4, 0), real_t(4), a, b, normal));
}

TEST_CASE("[PhysicsSpeculativeCapsulePair] Skew 3D capsules hit and miss correctly") {
	Vector3 a, b, normal;
	CHECK(physics_speculative_capsule_pair_contact(
			Vector3(-4, 0, 0), Vector3(), Vector3(0, 1, 0), Vector3(1, 0, 0),
			real_t(1), real_t(1), real_t(0.5), real_t(0.5),
			Vector3(4, 0, 0), real_t(3), a, b, normal));
	CHECK(normal.is_equal_approx(Vector3(1, 0, 0)));
	CHECK(Math::is_equal_approx((a - b).dot(normal), real_t(-2)));
	CHECK_FALSE(physics_speculative_capsule_pair_contact(
			Vector3(-4, 0, 2), Vector3(), Vector3(0, 1, 0), Vector3(1, 0, 0),
			real_t(1), real_t(1), real_t(0.5), real_t(0.5),
			Vector3(4, 0, 0), real_t(4), a, b, normal));
}

TEST_CASE("[PhysicsSpeculativeCapsulePair] Capsule pairs do not produce ghost stationary contacts") {
	Vector3 a, b, n;
	CHECK_FALSE(physics_speculative_capsule_pair_contact(
			Vector3(-4, 0, 0), Vector3(), Vector3(0, 1, 0), Vector3(1, 0, 0),
			real_t(1), real_t(1), real_t(0.5), real_t(0.5),
			Vector3(), real_t(3), a, b, n));
	CHECK_FALSE(physics_speculative_capsule_pair_contact(
			Vector3(-4, 0, 0), Vector3(), Vector3(0, 1, 0), Vector3(1, 0, 0),
			real_t(1), real_t(1), real_t(0.5), real_t(0.5),
			Vector3(-5, 0, 0), real_t(3), a, b, n));
	CHECK_FALSE(physics_speculative_capsule_pair_contact(
			Vector3(-4, 0, 0), Vector3(), Vector3(0, 1, 0), Vector3(1, 0, 0),
			real_t(1), real_t(1), real_t(0.5), real_t(0.5),
			Vector3(4, 0, 0), real_t(1), a, b, n));
}

TEST_CASE("[PhysicsSpeculativeCapsulePair] Collapsed capsules reduce to a sphere pair") {
	Vector2 a, b, normal;
	CHECK(physics_speculative_capsule_pair_contact(
			Vector2(-3, 0), Vector2(), Vector2(0, 1), Vector2(0, 1),
			real_t(0), real_t(0), real_t(0.5), real_t(0.5),
			Vector2(4, 0), real_t(3), a, b, normal));
	CHECK(Math::is_equal_approx((a - b).dot(normal), real_t(-2)));
}

TEST_CASE("[PhysicsSpeculativeCapsulePair] Invalid axes and radii cannot produce contacts") {
	Vector2 a, b, n;
	CHECK_FALSE(physics_speculative_capsule_pair_contact(
			Vector2(-4, 0), Vector2(), Vector2(), Vector2(0, 1),
			real_t(1), real_t(1), real_t(0.5), real_t(0.5),
			Vector2(4, 0), real_t(3), a, b, n));
	CHECK_FALSE(physics_speculative_capsule_pair_contact(
			Vector2(-4, 0), Vector2(), Vector2(0, 1), Vector2(0, 1),
			real_t(1), real_t(1), real_t(-0.5), real_t(0.5),
			Vector2(4, 0), real_t(3), a, b, n));
	CHECK_FALSE(physics_speculative_capsule_pair_contact(
			Vector2(-4, 0), Vector2(), Vector2(0, 1), Vector2(0, 1),
			real_t(1), real_t(-1), real_t(0.5), real_t(0.5),
			Vector2(4, 0), real_t(3), a, b, n));
}

TEST_CASE("[PhysicsSpeculativeCapsulePair] Randomized 2D early cull agrees with CCD TOI") {
	uint32_t state = 0x3427C1U;
	auto random = [&]() -> real_t {
		state = state * 1664525U + 1013904223U;
		return real_t((state >> 8) % 10001U) / real_t(10000);
	};
	Vector2 point_a, point_b, normal;
	for (int i = 0; i < 2048; i++) {
		const Vector2 center_a(real_t(-3) + random(), random());
		const Vector2 center_b(0, 0);
		const Vector2 axis_a(0, 1);
		const Vector2 axis_b = Vector2(real_t(1), real_t(0.15) + random()).normalized();
		const Vector2 motion(real_t(8) * random() - real_t(1),
				real_t(4) * random() - real_t(2));
		Vector2 a, b;
		physics_speculative_capsule_closest_points(center_a - axis_a, center_a + axis_a,
				center_b - axis_b, center_b + axis_b, a, b);
		const real_t gap = a.distance_to(b) - real_t(1);
		const bool eligible = gap > 0.0 && gap <= real_t(4);
		double fraction = 0.0;
		const bool expected = eligible && physics_ccd_capsule_pair_toi(
				center_a - center_b, motion, axis_a, axis_b,
				1.0, 1.0, 1.0, fraction) == PhysicsCCDCapsulePairTOIResult::HIT;
		const bool actual = physics_speculative_capsule_pair_contact(
				center_a, center_b, axis_a, axis_b,
				real_t(1), real_t(1), real_t(0.5), real_t(0.5),
				motion, real_t(4), point_a, point_b, normal);
		CHECK(expected == actual);
	}
}

TEST_CASE("[PhysicsSpeculativeCapsulePair] Randomized 3D early cull agrees with CCD TOI") {
	uint32_t state = 0x512DC71U;
	auto random = [&]() -> real_t {
		state = state * 1103515245U + 12345U;
		return real_t((state >> 8) % 10001U) / real_t(10000);
	};
	Vector3 point_a, point_b, normal;
	for (int i = 0; i < 2048; i++) {
		const Vector3 center_a(real_t(-3) + random(), random(), random() - real_t(0.5));
		const Vector3 center_b(0, 0, 0);
		const Vector3 axis_a(0, 1, 0);
		const Vector3 axis_b = Vector3(real_t(1), real_t(0.15) + random(), random()).normalized();
		const Vector3 motion(real_t(8) * random() - real_t(1),
				real_t(4) * random() - real_t(2), real_t(4) * random() - real_t(2));
		Vector3 a, b;
		physics_speculative_capsule_closest_points(center_a - axis_a, center_a + axis_a,
				center_b - axis_b, center_b + axis_b, a, b);
		const real_t gap = a.distance_to(b) - real_t(1);
		const bool eligible = gap > 0.0 && gap <= real_t(4);
		double fraction = 0.0;
		const bool expected = eligible && physics_ccd_capsule_pair_toi(
				center_a - center_b, motion, axis_a, axis_b,
				1.0, 1.0, 1.0, fraction) == PhysicsCCDCapsulePairTOIResult::HIT;
		const bool actual = physics_speculative_capsule_pair_contact(
				center_a, center_b, axis_a, axis_b,
				real_t(1), real_t(1), real_t(0.5), real_t(0.5),
				motion, real_t(4), point_a, point_b, normal);
		CHECK(expected == actual);
	}
}

} // namespace TestPhysicsSpeculativeCapsulePairContact
