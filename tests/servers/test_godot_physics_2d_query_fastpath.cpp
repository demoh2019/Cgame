/**************************************************************************/
/*  test_godot_physics_2d_query_fastpath.cpp                               */
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

#include "modules/modules_enabled.gen.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_2d_query_fastpath)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "modules/godot_physics_2d/godot_shape_2d.h"

namespace TestGodotPhysics2DQueryFastpath {

TEST_CASE("[GodotPhysics2D] Circle ray casts handle zero length, entry, tangency and retreat") {
	GodotCircleShape2D circle;
	circle.set_data(real_t(1.0));
	Vector2 point(99, 98);
	Vector2 normal(97, 96);

	CHECK_FALSE(circle.intersect_segment(Vector2(0, 0), Vector2(0, 0), point, normal));
	CHECK_FALSE(circle.intersect_segment(Vector2(1, 0), Vector2(1, 0), point, normal));
	CHECK_FALSE(circle.intersect_segment(Vector2(3, 0), Vector2(3, 0), point, normal));
	CHECK(point == Vector2(99, 98));
	CHECK(normal == Vector2(97, 96));

	CHECK(circle.intersect_segment(Vector2(-3, 0), Vector2(3, 0), point, normal));
	CHECK(point.is_equal_approx(Vector2(-1, 0)));
	CHECK(normal.is_equal_approx(Vector2(-1, 0)));

	CHECK(circle.intersect_segment(Vector2(-2, 1), Vector2(2, 1), point, normal));
	CHECK(point.is_equal_approx(Vector2(0, 1)));
	CHECK(normal.is_equal_approx(Vector2(0, 1)));

	CHECK_FALSE(circle.intersect_segment(Vector2(-3, 0), Vector2(-4, 0), point, normal));
	CHECK_FALSE(circle.intersect_segment(Vector2(-3, 0), Vector2(-2, 0), point, normal));
	CHECK_FALSE(circle.intersect_segment(Vector2(0, 0), Vector2(3, 0), point, normal));
}

TEST_CASE("[GodotPhysics2D] Capsule ray casts handle zero length and select the first surface") {
	GodotCapsuleShape2D capsule;
	capsule.set_data(Vector2(1, 4)); // Vector2 order is radius, height.
	const Vector2 stored_shape_data = capsule.get_data();
	CHECK(stored_shape_data.is_equal_approx(Vector2(1, 4)));
	Vector2 point(99, 98);
	Vector2 normal(97, 96);

	CHECK_FALSE(capsule.intersect_segment(Vector2(0, 0), Vector2(0, 0), point, normal));
	CHECK_FALSE(capsule.intersect_segment(Vector2(1, 0), Vector2(1, 0), point, normal));
	CHECK_FALSE(capsule.intersect_segment(Vector2(4, 0), Vector2(4, 0), point, normal));
	CHECK(point == Vector2(99, 98));
	CHECK(normal == Vector2(97, 96));

	CHECK(capsule.intersect_segment(Vector2(-3, 0), Vector2(3, 0), point, normal));
	CHECK(point.is_equal_approx(Vector2(-1, 0)));
	CHECK(normal.is_equal_approx(Vector2(-1, 0)));

	CHECK(capsule.intersect_segment(Vector2(0, -4), Vector2(0, 4), point, normal));
	CHECK(point.is_equal_approx(Vector2(0, -2)));
	CHECK(normal.is_equal_approx(Vector2(0, -1)));

	CHECK(capsule.intersect_segment(Vector2(-3, -2), Vector2(3, -2), point, normal));
	CHECK(point.is_equal_approx(Vector2(0, -2)));
	CHECK(normal.is_equal_approx(Vector2(0, -1)));

	CHECK_FALSE(capsule.intersect_segment(Vector2(-3, 0), Vector2(-4, 0), point, normal));
	CHECK_FALSE(capsule.intersect_segment(Vector2(-3, 3), Vector2(3, 3), point, normal));
}

TEST_CASE("[GodotPhysics2D] Convex polygon half-planes reject outside points in either winding") {
	PackedVector2Array vertices;
	vertices.push_back(Vector2(-2, -1));
	vertices.push_back(Vector2(2, -1));
	vertices.push_back(Vector2(2, 1));
	vertices.push_back(Vector2(-2, 1));

	GodotConvexPolygonShape2D polygon;
	for (int orientation = 0; orientation < 2; orientation++) {
		polygon.set_data(vertices);
		CHECK(polygon.contains_point(Vector2(0, 0)));
		CHECK(polygon.contains_point(Vector2(-2, 0)));
		CHECK(polygon.contains_point(Vector2(2, 0)));
		CHECK_FALSE(polygon.contains_point(Vector2(3, 0)));
		CHECK_FALSE(polygon.contains_point(Vector2(0, -2)));
		CHECK_FALSE(polygon.contains_point(Vector2(-3, 2)));

		for (int x = -20; x <= 20; x++) {
			for (int y = -20; y <= 20; y++) {
				const Vector2 p(x * real_t(0.18) + real_t(0.037), y * real_t(0.14) + real_t(0.029));
				const bool expected = p.x >= -2.0 && p.x <= 2.0 && p.y >= -1.0 && p.y <= 1.0;
				CHECK(polygon.contains_point(p) == expected);
			}
		}
		PackedVector2Array reversed;
		for (int i = vertices.size() - 1; i >= 0; i--) {
			reversed.push_back(vertices[i]);
		}
		vertices = reversed;
	}
}

} // namespace TestGodotPhysics2DQueryFastpath

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
