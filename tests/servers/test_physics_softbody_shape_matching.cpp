/**************************************************************************/
/*  test_physics_softbody_shape_matching.cpp                              */
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

#include "servers/physics_softbody_shape_matching.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_softbody_shape_matching)

namespace TestPhysicsSoftBodyShapeMatching {

TEST_CASE("[PhysicsSoftBody] Shape matching recovers rigid rotation and translation") {
	const Vector3 rest[5] = { Vector3(), Vector3(1, 0, 0), Vector3(0, 2, 0),
		Vector3(0, 0, 3), Vector3(2, 1, 1) };
	const Quaternion expected(Vector3(1, 2, 3).normalized(), real_t(1.1));
	const Vector3 translation(10, -20, 5);
	Vector3 c0, c1;
	for (const Vector3 &p : rest) {
		c0 += p * real_t(0.2);
		c1 += (expected.xform(p) + translation) * real_t(0.2);
	}
	PhysicsSoftBodyShapeMatchingCovariance covariance;
	for (const Vector3 &p : rest) {
		covariance.add(p - c0, expected.xform(p) + translation - c1);
	}
	Quaternion rotation;
	CHECK(covariance.solve_rotation(rotation));
	for (const Vector3 &p : rest) {
		CHECK(rotation.xform(p - c0).distance_to(expected.xform(p - c0)) < real_t(1e-4));
	}
}

TEST_CASE("[PhysicsSoftBody] Shape matching corrects deformation without overshoot") {
	Vector3 point(2, 0, 0);
	CHECK(physics_softbody_shape_matching_project(point, Vector3(1, 0, 0),
			Vector3(), Quaternion(), 0.5, 1));
	CHECK(point.is_equal_approx(Vector3(1.5, 0, 0)));
	CHECK(physics_softbody_shape_matching_project(point, Vector3(1, 0, 0),
			Vector3(), Quaternion(), 1, 1));
	CHECK(point.is_equal_approx(Vector3(1, 0, 0)));
}

TEST_CASE("[PhysicsSoftBody] Shape matching leaves pinned vertices untouched") {
	Vector3 point(3, 4, 5);
	CHECK_FALSE(physics_softbody_shape_matching_project(point, Vector3(),
			Vector3(), Quaternion(), 1, 0));
	CHECK(point == Vector3(3, 4, 5));
}

TEST_CASE("[PhysicsSoftBody] Shape matching rejects invalid stiffness and infinities") {
	Vector3 point(3, 4, 5);
	CHECK_FALSE(physics_softbody_shape_matching_project(point, Vector3(),
			Vector3(), Quaternion(), 0, 1));
	CHECK_FALSE(physics_softbody_shape_matching_project(point, Vector3(),
			Vector3(), Quaternion(), real_t(1.1), 1));
	CHECK_FALSE(physics_softbody_shape_matching_project(point,
			Vector3(std::numeric_limits<real_t>::infinity(), 0, 0),
			Vector3(), Quaternion(), 1, 1));
	CHECK(point == Vector3(3, 4, 5));
}

TEST_CASE("[PhysicsSoftBody] Shape matching covariance rejects empty or invalid clouds") {
	PhysicsSoftBodyShapeMatchingCovariance covariance;
	Quaternion rotation;
	CHECK_FALSE(covariance.solve_rotation(rotation));
	covariance.add(Vector3(std::numeric_limits<real_t>::infinity(), 0, 0), Vector3(1, 0, 0));
	CHECK_FALSE(covariance.solve_rotation(rotation));
}

TEST_CASE("[PhysicsSoftBody] Shape matching rejects reflection and retains proper rotation") {
	PhysicsSoftBodyShapeMatchingCovariance covariance;
	const Vector3 rest[4] = {
		Vector3(1, 1, 1), Vector3(-1, -1, 1),
		Vector3(-1, 1, -1), Vector3(1, -1, -1)
	};
	for (const Vector3 &p : rest) {
		covariance.add(p, Vector3(-p.x, p.y, p.z));
	}
	Quaternion rotation;
	CHECK(covariance.solve_rotation(rotation));
	CHECK(rotation.xform(Vector3(1, 0, 0)).cross(
			rotation.xform(Vector3(0, 1, 0))).dot(
			rotation.xform(Vector3(0, 0, 1))) > real_t(0.99));
}

TEST_CASE("[PhysicsSoftBody] Shape matching handles rotated planar rest geometry") {
	PhysicsSoftBodyShapeMatchingCovariance covariance;
	const Quaternion expected(Vector3(0, 1, 0), real_t(0.7));
	for (int x = -1; x <= 1; ++x) {
		for (int y = -1; y <= 1; ++y) {
			const Vector3 p(x, y, 0);
			covariance.add(p, expected.xform(p));
		}
	}
	Quaternion rotation;
	CHECK(covariance.solve_rotation(rotation));
	CHECK(rotation.xform(Vector3(1, 0, 0)).distance_to(
			expected.xform(Vector3(1, 0, 0))) < real_t(1e-4));
}

TEST_CASE("[PhysicsSoftBody] Shape matching preserves rigid goal position") {
	const Quaternion expected(Vector3(0, 0, 1), real_t(0.6));
	const Vector3 rest(1, 2, 3), center(100, -20, 9);
	Vector3 point = expected.xform(rest) + center;
	const Vector3 original = point;
	CHECK(physics_softbody_shape_matching_project(point, rest, center, expected, 1, 1));
	CHECK(point.distance_to(original) < real_t(1e-4));
}

} // namespace TestPhysicsSoftBodyShapeMatching
