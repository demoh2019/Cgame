/**************************************************************************/
/*  test_physics_speculative_capsule_contact.cpp                          */
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

#include "servers/physics_speculative_capsule_contact.h"
#include "servers/physics_contact_recycling.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_speculative_capsule_contact)

namespace TestPhysicsSpeculativeCapsuleContact {

TEST_CASE("[PhysicsSpeculativeCapsule] 2D side contact keeps real surface anchors and negative gap") {
	Vector2 point_circle, point_capsule, normal;
	CHECK(physics_speculative_sphere_capsule_contact(Vector2(-3, 0),
			real_t(0.5), real_t(0.5), real_t(1.5), Vector2(5, 0), real_t(3),
			point_circle, point_capsule, normal));
	CHECK(point_circle.is_equal_approx(Vector2(-2.5, 0)));
	CHECK(point_capsule.is_equal_approx(Vector2(-0.5, 0)));
	CHECK(normal.is_equal_approx(Vector2(1, 0)));
	CHECK(Math::is_equal_approx((point_circle - point_capsule).dot(normal), real_t(-2)));
	// The same points form a correctly oriented contact in reverse pair order.
	CHECK(Math::is_equal_approx((point_capsule - point_circle).dot(-normal), real_t(-2)));
}

TEST_CASE("[PhysicsSpeculativeCapsule] 2D hemisphere grazing hit and tangential miss") {
	Vector2 circle_point, capsule_point, normal;
	CHECK(physics_speculative_sphere_capsule_contact(Vector2(-4, real_t(2.2)),
			real_t(0.5), real_t(0.5), real_t(1.5), Vector2(8, 0), real_t(4),
			circle_point, capsule_point, normal));
	CHECK(normal.x > 0.0);
	CHECK(normal.y < 0.0);
	CHECK((circle_point - capsule_point).dot(normal) < 0.0);
	CHECK_FALSE(physics_speculative_sphere_capsule_contact(Vector2(-4, real_t(2.51)),
			real_t(0.5), real_t(0.5), real_t(1.5), Vector2(8, 0), real_t(4),
			circle_point, capsule_point, normal));
	CHECK_FALSE(physics_speculative_sphere_capsule_contact(Vector2(-3, 0),
			real_t(0.5), real_t(0.5), real_t(1.5), Vector2(5, 20), real_t(3),
			circle_point, capsule_point, normal));
}

TEST_CASE("[PhysicsSpeculativeCapsule] 2D rejects separated, stationary and slow pairs") {
	Vector2 point_a, point_b, normal;
	CHECK_FALSE(physics_speculative_sphere_capsule_contact(Vector2(-3, 0),
			real_t(0.5), real_t(0.5), real_t(1.5), Vector2(), real_t(3),
			point_a, point_b, normal));
	CHECK_FALSE(physics_speculative_sphere_capsule_contact(Vector2(-3, 0),
			real_t(0.5), real_t(0.5), real_t(1.5), Vector2(-5, 0), real_t(3),
			point_a, point_b, normal));
	CHECK_FALSE(physics_speculative_sphere_capsule_contact(Vector2(-3, 0),
			real_t(0.5), real_t(0.5), real_t(1.5), Vector2(1, 0), real_t(3),
			point_a, point_b, normal));
	CHECK_FALSE(physics_speculative_sphere_capsule_contact(Vector2(-3, 0),
			real_t(0.5), real_t(0.5), real_t(1.5), Vector2(5, 0), real_t(1),
			point_a, point_b, normal));
	// Contact is handled by the ordinary narrowphase after penetration.
	CHECK_FALSE(physics_speculative_sphere_capsule_contact(Vector2(real_t(0.6), 0),
			real_t(0.5), real_t(0.5), real_t(1.5), Vector2(1, 0), real_t(3),
			point_a, point_b, normal));
}

TEST_CASE("[PhysicsSpeculativeCapsule] 3D side and end-cap contacts use correct normals") {
	Vector3 point_sphere, point_capsule, normal;
	CHECK(physics_speculative_sphere_capsule_contact(Vector3(-3, 0, 0),
			real_t(0.5), real_t(0.5), real_t(1.5), Vector3(5, 0, 0), real_t(3),
			point_sphere, point_capsule, normal));
	CHECK(normal.is_equal_approx(Vector3(1, 0, 0)));
	CHECK(Math::is_equal_approx((point_sphere - point_capsule).dot(normal), real_t(-2)));
	CHECK(physics_speculative_sphere_capsule_contact(Vector3(-4, real_t(2.2), 0),
			real_t(0.5), real_t(0.5), real_t(1.5), Vector3(8, 0, 0), real_t(4),
			point_sphere, point_capsule, normal));
	CHECK(normal.x > 0.0);
	CHECK(normal.y < 0.0);
	CHECK((point_sphere - point_capsule).dot(normal) < 0.0);
	CHECK(physics_speculative_sphere_capsule_contact(Vector3(-4, 0, real_t(0.7)),
			real_t(0.5), real_t(0.5), real_t(1.5), Vector3(8, 0, 0), real_t(4),
			point_sphere, point_capsule, normal));
	CHECK(normal.x > 0.0);
	CHECK(normal.z < 0.0);
	CHECK_FALSE(physics_speculative_sphere_capsule_contact(Vector3(-4, 0, real_t(1.01)),
			real_t(0.5), real_t(0.5), real_t(1.5), Vector3(8, 0, 0), real_t(4),
			point_sphere, point_capsule, normal));
}

TEST_CASE("[PhysicsSpeculativeCapsule] Zero-length capsule behaves like sphere") {
	Vector2 point_a2, point_b2, normal2;
	CHECK(physics_speculative_sphere_capsule_contact(Vector2(-3, 0),
			real_t(0.5), real_t(0.5), real_t(0), Vector2(5, 0), real_t(3),
			point_a2, point_b2, normal2));
	CHECK(normal2.is_equal_approx(Vector2(1, 0)));

	Vector3 point_a3, point_b3, normal3;
	CHECK(physics_speculative_sphere_capsule_contact(Vector3(-3, 0, 0),
			real_t(0.5), real_t(0.5), real_t(0), Vector3(5, 0, 0), real_t(3),
			point_a3, point_b3, normal3));
	CHECK(normal3.is_equal_approx(Vector3(1, 0, 0)));
}

TEST_CASE("[PhysicsSpeculativeCapsule] Rejects degenerate inputs and nonfinite motion") {
	Vector2 a, b, n;
	CHECK_FALSE(physics_speculative_sphere_capsule_contact(Vector2(-3, 0),
			real_t(0), real_t(0.5), real_t(1.5), Vector2(5, 0), real_t(3), a, b, n));
	CHECK_FALSE(physics_speculative_sphere_capsule_contact(Vector2(-3, 0),
			real_t(0.5), real_t(0), real_t(1.5), Vector2(5, 0), real_t(3), a, b, n));
	CHECK_FALSE(physics_speculative_sphere_capsule_contact(Vector2(-3, 0),
			real_t(0.5), real_t(0.5), real_t(-1), Vector2(5, 0), real_t(3), a, b, n));
	CHECK_FALSE(physics_speculative_sphere_capsule_contact(Vector2(-3, 0),
			real_t(0.5), real_t(0.5), real_t(1.5),
			Vector2(std::numeric_limits<real_t>::infinity(), 0), real_t(3), a, b, n));
}

TEST_CASE("[PhysicsSpeculativeCapsule] Changing velocity invalidates cached 2D and 3D separation") {
	GodotPhysicsContactRecycling recycling;
	recycling.remember(31, 42, false);
	CHECK(recycling.can_reuse_separation(31, 42, false));
	CHECK_FALSE(recycling.can_reuse_separation(31, 42, false, true));
	recycling.remember(31, 42, true);
	recycling.speculative_contact = true;
	CHECK_FALSE(recycling.can_reuse(31, 42, true, 1, false, recycling.speculative_contact));
	recycling.speculative_contact = false;
	CHECK(recycling.can_reuse(31, 42, true, 1, false, recycling.speculative_contact));
}

TEST_CASE("[PhysicsSpeculativeCapsule] Randomized 2D candidate filter agrees with exact capsule TOI") {
	uint32_t state = 0x3F3B7211U;
	auto random = [&]() -> real_t {
		state = state * 1664525U + 1013904223U;
		return real_t((state >> 8) % 10001U) / real_t(10000);
	};
	Vector2 a, b, normal;
	for (int i = 0; i < 2048; ++i) {
		const Vector2 center(real_t(2.1) + random() * 5, (random() - real_t(0.5)) * 6);
		const Vector2 motion((random() - real_t(0.5)) * 16, (random() - real_t(0.5)) * 16);
		const real_t half_segment = real_t(1);
		const real_t combined_radius = real_t(1);
		const real_t nearest_y = CLAMP(center.y, -half_segment, half_segment);
		const real_t distance = Vector2(center.x, center.y - nearest_y).length();
		const bool eligible = distance > combined_radius && distance - combined_radius <= real_t(10);
		double toi = 0.0;
		const bool expected = eligible && physics_ccd_capsule_toi(center, motion, 1.0, 1.0, toi);
		const bool actual = physics_speculative_sphere_capsule_contact(center, real_t(0.5),
				real_t(0.5), half_segment, motion, real_t(10), a, b, normal);
		CHECK(actual == expected);
	}
}

TEST_CASE("[PhysicsSpeculativeCapsule] Randomized 3D candidate filter agrees with exact capsule TOI") {
	uint32_t state = 0x29A85123U;
	auto random = [&]() -> real_t {
		state = state * 1103515245U + 12345U;
		return real_t((state >> 8) % 10001U) / real_t(10000);
	};
	Vector3 a, b, normal;
	for (int i = 0; i < 2048; ++i) {
		const Vector3 center(real_t(2.1) + random() * 5,
				(random() - real_t(0.5)) * 6, (random() - real_t(0.5)) * 6);
		const Vector3 motion((random() - real_t(0.5)) * 16,
				(random() - real_t(0.5)) * 16, (random() - real_t(0.5)) * 16);
		const real_t half_segment = real_t(1);
		const real_t combined_radius = real_t(1);
		const real_t nearest_y = CLAMP(center.y, -half_segment, half_segment);
		const real_t distance = Vector3(center.x, center.y - nearest_y, center.z).length();
		const bool eligible = distance > combined_radius && distance - combined_radius <= real_t(10);
		double toi = 0.0;
		const bool expected = eligible && physics_ccd_capsule_toi(center, motion, 1.0, 1.0, toi);
		const bool actual = physics_speculative_sphere_capsule_contact(center, real_t(0.5),
				real_t(0.5), half_segment, motion, real_t(10), a, b, normal);
		CHECK(actual == expected);
	}
}

} // namespace TestPhysicsSpeculativeCapsuleContact
