/**************************************************************************/
/*  test_godot_physics_3d_convex_ray_clip.cpp                            */
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

#include "modules/modules_enabled.gen.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_3d_convex_ray_clip)

#ifdef MODULE_GODOT_PHYSICS_3D_ENABLED

#include "modules/godot_physics_3d/godot_shape_3d.h"

namespace TestGodotPhysics3DConvexRayClip {

static void set_cube(GodotConvexPolygonShape3D &r_shape, const Vector3 &p_center, real_t p_half_extent) {
	Vector<Vector3> vertices;
	for (int i = 0; i < 8; ++i) {
		vertices.push_back(p_center + Vector3(
				(i & 1) ? p_half_extent : -p_half_extent,
				(i & 2) ? p_half_extent : -p_half_extent,
				(i & 4) ? p_half_extent : -p_half_extent));
	}
	r_shape.set_data(vertices);
}

TEST_CASE("[GodotPhysics3D] Convex ray clipping selects nearest entering face") {
	GodotConvexPolygonShape3D cube;
	set_cube(cube, Vector3(), real_t(1.0));
	Vector3 point, normal;
	int face_index = -1;

	CHECK(cube.intersect_segment(Vector3(-4.0, 0.2, 0.3), Vector3(4.0, 0.2, 0.3), point, normal, face_index, false));
	CHECK(point.distance_to(Vector3(-1.0, 0.2, 0.3)) < real_t(0.001));
	CHECK(normal.is_equal_approx(Vector3(-1.0, 0.0, 0.0)));

	CHECK(cube.intersect_segment(Vector3(4.0, 0.2, 0.3), Vector3(-4.0, 0.2, 0.3), point, normal, face_index, false));
	CHECK(point.distance_to(Vector3(1.0, 0.2, 0.3)) < real_t(0.001));
	CHECK(normal.is_equal_approx(Vector3(1.0, 0.0, 0.0)));

	CHECK_FALSE(cube.intersect_segment(Vector3(), Vector3(4.0, 0.0, 0.0), point, normal, face_index, false));
	CHECK_FALSE(cube.intersect_segment(Vector3(0.0, 4.0, 0.0), Vector3(0.0, 6.0, 0.0), point, normal, face_index, false));
	CHECK_FALSE(cube.intersect_segment(Vector3(-4.0, 0.0, 0.0), Vector3(-4.0, 0.0, 0.0), point, normal, face_index, false));

	// Compare the ray cast with the exact cube intersection over many
	// interior and exterior lanes, avoiding edges and corner tie cases.
	for (int y = -12; y <= 12; ++y) {
		for (int z = -12; z <= 12; ++z) {
			const real_t py = (real_t(y) + real_t(0.3)) * real_t(0.11);
			const real_t pz = (real_t(z) + real_t(0.2)) * real_t(0.11);
			const bool expected = Math::abs(py) < 1.0 && Math::abs(pz) < 1.0;
			const bool hit = cube.intersect_segment(Vector3(-3.0, py, pz), Vector3(3.0, py, pz), point, normal, face_index, false);
			CHECK(hit == expected);
			if (hit) {
				CHECK(Math::abs(point.x + real_t(1.0)) < real_t(0.001));
			}
		}
	}
}

TEST_CASE("[GodotPhysics3D] Convex ray clipping stays stable for distant endpoints") {
	GodotConvexPolygonShape3D cube;
	set_cube(cube, Vector3(), real_t(1.0));
	Vector3 point, normal;
	int face_index = -1;

	CHECK(cube.intersect_segment(Vector3(real_t(-1.0e12), real_t(0.25), real_t(0.25)),
			Vector3(real_t(1.0e12), real_t(0.25), real_t(0.25)), point, normal, face_index, false));
	CHECK(point.distance_to(Vector3(real_t(-1.0), real_t(0.25), real_t(0.25))) < real_t(0.01));
	CHECK(normal.is_equal_approx(Vector3(-1.0, 0.0, 0.0)));
}

} // namespace TestGodotPhysics3DConvexRayClip

#endif // MODULE_GODOT_PHYSICS_3D_ENABLED
