/**************************************************************************/
/*  test_physics_speculative_sphere_contact.cpp                            */
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

#include "servers/physics_speculative_sphere_contact.h"
#include "servers/physics_contact_recycling.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_physics_speculative_sphere_contact)

namespace TestPhysicsSpeculativeSphereContact {

TEST_CASE("[PhysicsSpeculative] 2D predictive circles return real surface anchors and negative depth") {
	Vector2 point_a, point_b, normal;
	const bool hit = physics_speculative_sphere_contact(
			Vector2(0, 0), real_t(1.0), Vector2(2.5, 0), real_t(1.0),
			Vector2(100, 0), Vector2(),
			real_t(0.01), real_t(0.6), point_a, point_b, normal);
	CHECK(hit);
	CHECK(point_a.is_equal_approx(Vector2(1, 0)));
	CHECK(point_b.is_equal_approx(Vector2(1.5, 0)));
	CHECK(normal.is_equal_approx(Vector2(1, 0)));
	CHECK(Math::is_equal_approx((point_a - point_b).dot(normal), real_t(-0.5)));
	// The solver permits 50 px/s of approach over a 0.5 px gap and a 0.01 s step.
	CHECK(Math::is_equal_approx(real_t(0.5) / real_t(0.01), real_t(50)));
}

TEST_CASE("[PhysicsSpeculative] 2D stationary, separating and slow circles generate no contact") {
	Vector2 a, b, n;
	const Vector2 center_a, center_b(2.5, 0);
	CHECK_FALSE(physics_speculative_sphere_contact(center_a, real_t(1), center_b, real_t(1),
			Vector2(), Vector2(), real_t(0.01), real_t(0.6), a, b, n));
	CHECK_FALSE(physics_speculative_sphere_contact(center_a, real_t(1), center_b, real_t(1),
			Vector2(-100, 0), Vector2(), real_t(0.01), real_t(0.6), a, b, n));
	CHECK_FALSE(physics_speculative_sphere_contact(center_a, real_t(1), center_b, real_t(1),
			Vector2(20, 0), Vector2(), real_t(0.01), real_t(0.6), a, b, n));
	CHECK_FALSE(physics_speculative_sphere_contact(center_a, real_t(1), center_b, real_t(1),
			Vector2(100, 0), Vector2(), real_t(0.01), real_t(0.4), a, b, n));
	CHECK_FALSE(physics_speculative_sphere_contact(center_a, real_t(1), center_b, real_t(1),
			Vector2(100, 0), Vector2(), real_t(0.01), real_t(0), a, b, n));
	CHECK_FALSE(physics_speculative_sphere_contact(center_a, real_t(1), center_b, real_t(1),
			Vector2(100, 0), Vector2(), real_t(0), real_t(0.6), a, b, n));
}

TEST_CASE("[PhysicsSpeculative] 3D spheres predict glancing contact on the right normal") {
	Vector3 point_a, point_b, normal;
	const Vector3 center_a, center_b(2.4, 0.3, 0);
	CHECK(physics_speculative_sphere_contact(center_a, real_t(1), center_b, real_t(1),
			Vector3(50, 0, 0), Vector3(), real_t(0.02), real_t(0.6), point_a, point_b, normal));
	const real_t gap = (point_b - point_a).length();
	CHECK(Math::is_equal_approx(gap, center_b.length() - real_t(2), real_t(0.0001)));
	CHECK(normal.dot(center_b) > 0.0);
	CHECK((point_a - point_b).dot(normal) < 0.0);
}

TEST_CASE("[PhysicsSpeculative] 3D relative velocity excludes co-moving spheres") {
	Vector3 a, b, n;
	CHECK_FALSE(physics_speculative_sphere_contact(
			Vector3(0, 0, 0), real_t(1), Vector3(2.3, 0, 0), real_t(1),
			Vector3(300, 0, 0), Vector3(300, 0, 0), real_t(0.02), real_t(0.5), a, b, n));
	CHECK(physics_speculative_sphere_contact(
			Vector3(0, 0, 0), real_t(1), Vector3(2.3, 0, 0), real_t(1),
			Vector3(100, 0, 0), Vector3(60, 0, 0), real_t(0.02), real_t(0.5), a, b, n));
}

TEST_CASE("[PhysicsSpeculative] 2D and 3D reject already-overlapping or invalid spheres") {
	Vector2 a2, b2, n2;
	CHECK_FALSE(physics_speculative_sphere_contact(
			Vector2(), real_t(1), Vector2(1.5, 0), real_t(1),
			Vector2(100, 0), Vector2(), real_t(0.01), real_t(1), a2, b2, n2));
	CHECK_FALSE(physics_speculative_sphere_contact(
			Vector2(), real_t(0), Vector2(2.5, 0), real_t(1),
			Vector2(100, 0), Vector2(), real_t(0.01), real_t(1), a2, b2, n2));

	Vector3 a3, b3, n3;
	CHECK_FALSE(physics_speculative_sphere_contact(
			Vector3(), real_t(1), Vector3(), real_t(1),
			Vector3(100, 0, 0), Vector3(), real_t(0.01), real_t(1), a3, b3, n3));
	CHECK_FALSE(physics_speculative_sphere_contact(
			Vector3(), real_t(1), Vector3(1000, 0, 0), real_t(1),
			Vector3(100000, 0, 0), Vector3(), real_t(0.01), real_t(0.5), a3, b3, n3));
}

TEST_CASE("[PhysicsSpeculative] Tangential near-misses do not create ghost contacts") {
	Vector2 point_a, point_b, normal;
	// The normal component closes the gap in one step, but strong
	// perpendicular motion moves the circle past the target.
	CHECK_FALSE(physics_speculative_sphere_contact(
			Vector2(-3, 0), real_t(1), Vector2(), real_t(1),
			Vector2(5, 20), Vector2(), real_t(0.5), real_t(1.1), point_a, point_b, normal));

	// A glancing hit inside the combined-radius tube must still be retained.
	CHECK(physics_speculative_sphere_contact(
			Vector2(-3, 0), real_t(1), Vector2(0, 1.8), real_t(1),
			Vector2(10, 0), Vector2(), real_t(0.5), real_t(1.6), point_a, point_b, normal));
	CHECK(normal.is_normalized());
	CHECK((point_a - point_b).dot(normal) < 0.0);

	Vector3 a3, b3, n3;
	CHECK_FALSE(physics_speculative_sphere_contact(
			Vector3(-3, 0, 0), real_t(1), Vector3(), real_t(1),
			Vector3(5, 20, 0), Vector3(), real_t(0.5), real_t(1.1), a3, b3, n3));
	CHECK(physics_speculative_sphere_contact(
			Vector3(-3, 0, 0), real_t(1), Vector3(0, 0, 1.8), real_t(1),
			Vector3(10, 0, 0), Vector3(), real_t(0.5), real_t(1.6), a3, b3, n3));
}


TEST_CASE("[PhysicsSpeculative] Reevaluate a previously separated 2D pair when velocity changes") {
	GodotPhysicsContactRecycling recycling;
	Vector2 point_a, point_b, normal;
	const Vector2 center_a, center_b(real_t(2.5), 0);
	const real_t step = real_t(0.01);
	const real_t prediction_distance = real_t(0.6);

	// The geometry stays fixed between setup calls; only velocity changes.
	CHECK_FALSE(physics_speculative_sphere_contact(center_a, real_t(1), center_b, real_t(1),
			Vector2(), Vector2(), step, prediction_distance, point_a, point_b, normal));
	recycling.remember(13, 21, false);
	CHECK(recycling.can_reuse_separation(13, 21, false)); // Legacy geometry-only cache.
	CHECK_FALSE(recycling.can_reuse_separation(13, 21, false, true)); // Predictive pair.

	CHECK(physics_speculative_sphere_contact(center_a, real_t(1), center_b, real_t(1),
			Vector2(100, 0), Vector2(), step, prediction_distance, point_a, point_b, normal));
	recycling.remember(13, 21, true);
	CHECK(recycling.can_reuse(13, 21, true, 1, false));
	CHECK_FALSE(recycling.can_reuse(13, 21, true, 1, false, true));

	// The next frame might reverse the velocity without changing the pose.
	CHECK_FALSE(physics_speculative_sphere_contact(center_a, real_t(1), center_b, real_t(1),
			Vector2(-100, 0), Vector2(), step, prediction_distance, point_a, point_b, normal));
	CHECK_FALSE(recycling.can_reuse(13, 21, true, 1, false, true));
}

TEST_CASE("[PhysicsSpeculative] Reevaluate a previously separated 3D pair when velocity changes") {
	GodotPhysicsContactRecycling recycling;
	Vector3 point_a, point_b, normal;
	const Vector3 center_a, center_b(real_t(2.4), 0, 0);
	const real_t step = real_t(0.01);
	const real_t prediction_distance = real_t(0.6);
	recycling.remember(70, 90, false);
	CHECK(recycling.can_reuse_separation(70, 90, false));
	CHECK_FALSE(recycling.can_reuse_separation(70, 90, false, true));
	CHECK(physics_speculative_sphere_contact(center_a, real_t(1), center_b, real_t(1),
			Vector3(100, 0, 0), Vector3(), step, prediction_distance, point_a, point_b, normal));
	recycling.remember(70, 90, true);
	CHECK(recycling.can_reuse(70, 90, true, 1, false));
	CHECK_FALSE(recycling.can_reuse(70, 90, true, 1, false, true));
	CHECK_FALSE(recycling.can_reuse(70, 90, true, 1, true, false));
}

TEST_CASE("[PhysicsSpeculative] Velocity-sensitive caching retains legacy behavior for nonpredictive shapes") {
	GodotPhysicsContactRecycling recycling;
	recycling.remember(100, 200, true);
	CHECK(recycling.can_reuse(100, 200, true, 2, false));
	CHECK(recycling.can_reuse(100, 200, true, 2, false, false));
	CHECK_FALSE(recycling.can_reuse(100, 201, true, 2, false));
	CHECK_FALSE(recycling.can_reuse(100, 200, true, 0, false));
	CHECK_FALSE(recycling.can_reuse(100, 200, true, 2, true));
	recycling.remember(100, 200, false);
	CHECK(recycling.can_reuse_separation(100, 200, false));
	CHECK_FALSE(recycling.can_reuse_separation(100, 200, true));
}

} // namespace TestPhysicsSpeculativeSphereContact
