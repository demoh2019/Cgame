/**************************************************************************/
/*  test_godot_physics_2d_closest_segment.cpp                              */
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

TEST_FORCE_LINK(test_godot_physics_2d_closest_segment)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "modules/godot_physics_2d/godot_shape_2d.h"

namespace TestGodotPhysics2DClosestSegment {

TEST_CASE("[GodotPhysics2D] Concave segment casts retain closest hit from both directions") {
	PackedVector2Array edges;
	// Intentionally insert far and near edges in a non-monotonic order.
	const real_t positions[] = { real_t(11.0), real_t(3.0), real_t(6.0) };
	for (real_t x : positions) {
		edges.push_back(Vector2(x, -2.0));
		edges.push_back(Vector2(x, 2.0));
	}
	GodotConcavePolygonShape2D shape;
	shape.set_data(edges);

	Vector2 point, normal;
	CHECK(shape.intersect_segment(Vector2(0.0, 0.0), Vector2(20.0, 0.0), point, normal));
	CHECK(point.is_equal_approx(Vector2(3.0, 0.0)));
	CHECK(normal.is_equal_approx(Vector2(-1.0, 0.0)));

	CHECK(shape.intersect_segment(Vector2(20.0, 0.0), Vector2(0.0, 0.0), point, normal));
	CHECK(point.is_equal_approx(Vector2(11.0, 0.0)));
	CHECK(normal.is_equal_approx(Vector2(1.0, 0.0)));

	CHECK_FALSE(shape.intersect_segment(Vector2(0.0, 10.0), Vector2(20.0, 10.0), point, normal));
}

TEST_CASE("[GodotPhysics2D] Closest segment casts work far from the world origin") {
	const real_t origin_x = real_t(2.0e10);
	const real_t near_x = origin_x + real_t(1.0e8);
	const real_t far_x = origin_x + real_t(3.0e8);
	const Vector2 from(origin_x, 0.0);
	const Vector2 to(origin_x + real_t(5.0e8), 0.0);

	PackedVector2Array edges;
	edges.push_back(Vector2(far_x, -2.0));
	edges.push_back(Vector2(far_x, 2.0));
	edges.push_back(Vector2(near_x, -2.0));
	edges.push_back(Vector2(near_x, 2.0));
	GodotConcavePolygonShape2D concave;
	concave.set_data(edges);

	Vector2 point, normal;
	CHECK(concave.intersect_segment(from, to, point, normal));
	CHECK(point.is_equal_approx(Vector2(near_x, 0.0)));

	PackedVector2Array vertices;
	vertices.push_back(Vector2(near_x, -2.0));
	vertices.push_back(Vector2(far_x, -2.0));
	vertices.push_back(Vector2(far_x, 2.0));
	vertices.push_back(Vector2(near_x, 2.0));
	GodotConvexPolygonShape2D convex;
	convex.set_data(vertices);

	CHECK(convex.intersect_segment(from, to, point, normal));
	CHECK(point.is_equal_approx(Vector2(near_x, 0.0)));
}

} // namespace TestGodotPhysics2DClosestSegment

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
