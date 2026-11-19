/**************************************************************************/
/*  test_godot_physics_3d_sphere_long_ray.cpp                           */
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
/* CLAIM, DAMAGES OR OTHER LIABILITY, FITNESS FOR A PARTICULAR PURPOSE AND */
/* NONINFRINGEMENT.                                                        */
/**************************************************************************/

#include "modules/modules_enabled.gen.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_3d_sphere_long_ray)

#ifdef MODULE_GODOT_PHYSICS_3D_ENABLED

#include "modules/godot_physics_3d/godot_shape_3d.h"

namespace TestGodotPhysics3DSphereLongRay {

TEST_CASE("[GodotPhysics3D] Long sphere rays reconstruct the closest surface entry") {
	GodotSphereShape3D sphere;
	sphere.set_data(real_t(1.0));
	Vector3 point, normal;
	int face_index = -1;

	// The 2e20-unit ray squared length overflows float32, and a double
	// fraction alone cannot recover the unit-sized offset at its midpoint.
	CHECK(sphere.intersect_segment(Vector3(real_t(-1.0e20), real_t(0.5), 0.0),
			Vector3(real_t(1.0e20), real_t(0.5), 0.0), point, normal, face_index, false));
	CHECK(point.distance_to(Vector3(real_t(-0.8660254037844386), real_t(0.5), 0.0)) < real_t(0.001));
	CHECK(normal.distance_to(Vector3(real_t(-0.8660254037844386), real_t(0.5), 0.0)) < real_t(0.001));

	CHECK(sphere.intersect_segment(Vector3(real_t(1.0e20), real_t(0.5), 0.0),
			Vector3(real_t(-1.0e20), real_t(0.5), 0.0), point, normal, face_index, false));
	CHECK(point.distance_to(Vector3(real_t(0.8660254037844386), real_t(0.5), 0.0)) < real_t(0.001));
	CHECK(normal.distance_to(Vector3(real_t(0.8660254037844386), real_t(0.5), 0.0)) < real_t(0.001));
}

TEST_CASE("[GodotPhysics3D] Sphere rays support tiny crossings and reject invalid hits") {
	GodotSphereShape3D sphere;
	sphere.set_data(real_t(1.0));
	Vector3 point, normal;
	int face_index = -1;

	// Smaller than the old CMP_EPSILON length cutoff.
	CHECK(sphere.intersect_segment(Vector3(real_t(1.0) + real_t(0.000005), 0.0, 0.0),
			Vector3(real_t(1.0) - real_t(0.000005), 0.0, 0.0), point, normal, face_index, false));
	CHECK(point.distance_to(Vector3(1.0, 0.0, 0.0)) < real_t(0.0001));
	CHECK(normal.is_equal_approx(Vector3(1.0, 0.0, 0.0)));

	CHECK_FALSE(sphere.intersect_segment(Vector3(), Vector3(3.0, 0.0, 0.0), point, normal, face_index, false));
	CHECK_FALSE(sphere.intersect_segment(Vector3(3.0, 1.0, 0.0), Vector3(-3.0, 1.0, 0.0), point, normal, face_index, false));
	CHECK_FALSE(sphere.intersect_segment(Vector3(3.0, 1.01, 0.0), Vector3(-3.0, 1.01, 0.0), point, normal, face_index, false));
	CHECK_FALSE(sphere.intersect_segment(Vector3(3.0, 0.0, 0.0), Vector3(3.0, 0.0, 0.0), point, normal, face_index, false));
}

} // namespace TestGodotPhysics3DSphereLongRay

#endif // MODULE_GODOT_PHYSICS_3D_ENABLED
