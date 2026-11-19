/**************************************************************************/
/*  test_godot_physics_3d_capsule_ray_precision.cpp                       */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "modules/modules_enabled.gen.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_3d_capsule_ray_precision)

#ifdef MODULE_GODOT_PHYSICS_3D_ENABLED

#include "modules/godot_physics_3d/godot_shape_3d.h"

namespace TestGodotPhysics3DCapsuleRayPrecision {

static void make_capsule(GodotCapsuleShape3D &r_capsule) {
	Dictionary data;
	data["radius"] = real_t(1.0);
	data["height"] = real_t(4.0);
	r_capsule.set_data(data);
}

TEST_CASE("[GodotPhysics3D] Capsule long ray returns cylinder side entry and normal") {
	GodotCapsuleShape3D capsule;
	make_capsule(capsule);
	Vector3 point;
	Vector3 normal;
	int face_index = -1;

	CHECK(capsule.intersect_segment(Vector3(real_t(-1e20), 0.0, 0.0), Vector3(real_t(1e20), 0.0, 0.0), point, normal, face_index, false));
	CHECK(point.distance_to(Vector3(-1.0, 0.0, 0.0)) < real_t(0.001));
	CHECK(normal.distance_to(Vector3(-1.0, 0.0, 0.0)) < real_t(0.001));

	CHECK(capsule.intersect_segment(Vector3(real_t(1e20), 0.0, 0.0), Vector3(real_t(-1e20), 0.0, 0.0), point, normal, face_index, false));
	CHECK(point.distance_to(Vector3(1.0, 0.0, 0.0)) < real_t(0.001));
	CHECK(normal.distance_to(Vector3(1.0, 0.0, 0.0)) < real_t(0.001));

	CHECK(capsule.intersect_segment(Vector3(-3.0, 0.0, 0.3), Vector3(3.0, 0.0, 0.3), point, normal, face_index, false));
	CHECK(Math::abs(point.x + Math::sqrt(real_t(0.91))) < real_t(0.001));
	CHECK(Math::abs(point.z - real_t(0.3)) < real_t(0.001));
	CHECK(Math::abs(normal.length() - real_t(1.0)) < real_t(0.001));
}

TEST_CASE("[GodotPhysics3D] Capsule long ray hits rounded hemisphere, not its internal cylinder") {
	GodotCapsuleShape3D capsule;
	make_capsule(capsule);
	Vector3 point;
	Vector3 normal;
	int face_index = -1;
	const real_t entry = real_t(0.8660254037844386);

	// The central cylinder ends at Y=1. Ray Y=1.5 must strike the top cap.
	CHECK(capsule.intersect_segment(Vector3(real_t(-1e20), 1.5, 0.0), Vector3(real_t(1e20), 1.5, 0.0), point, normal, face_index, false));
	CHECK(point.distance_to(Vector3(-entry, 1.5, 0.0)) < real_t(0.001));
	CHECK(normal.distance_to(Vector3(-entry, 0.5, 0.0)) < real_t(0.001));

	CHECK(capsule.intersect_segment(Vector3(real_t(1e20), 1.5, 0.0), Vector3(real_t(-1e20), 1.5, 0.0), point, normal, face_index, false));
	CHECK(point.distance_to(Vector3(entry, 1.5, 0.0)) < real_t(0.001));
	CHECK(normal.distance_to(Vector3(entry, 0.5, 0.0)) < real_t(0.001));

	CHECK(capsule.intersect_segment(Vector3(-3.0, -1.5, 0.0), Vector3(3.0, -1.5, 0.0), point, normal, face_index, false));
	CHECK(point.distance_to(Vector3(-entry, -1.5, 0.0)) < real_t(0.001));
	CHECK(normal.distance_to(Vector3(-entry, -0.5, 0.0)) < real_t(0.001));
}

TEST_CASE("[GodotPhysics3D] Capsule ray misses, zero-length and inside rays") {
	GodotCapsuleShape3D capsule;
	make_capsule(capsule);
	Vector3 point;
	Vector3 normal;
	int face_index = -1;

	CHECK_FALSE(capsule.intersect_segment(Vector3(-3.0, 2.1, 0.0), Vector3(3.0, 2.1, 0.0), point, normal, face_index, false));
	CHECK_FALSE(capsule.intersect_segment(Vector3(-3.0, 0.0, 1.5), Vector3(3.0, 0.0, 1.5), point, normal, face_index, false));
	CHECK_FALSE(capsule.intersect_segment(Vector3(-3.0, 0.0, 0.0), Vector3(-3.0, 0.0, 0.0), point, normal, face_index, false));
	CHECK_FALSE(capsule.intersect_segment(Vector3(), Vector3(4.0, 0.0, 0.0), point, normal, face_index, false));
	CHECK_FALSE(capsule.intersect_segment(Vector3(0.0, 1.5, 0.0), Vector3(0.0, 5.0, 0.0), point, normal, face_index, false));
}

} // namespace TestGodotPhysics3DCapsuleRayPrecision

#endif // MODULE_GODOT_PHYSICS_3D_ENABLED
