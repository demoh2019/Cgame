/**************************************************************************/
/*  test_godot_physics_2d_polygon_mass.cpp                                 */
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

TEST_FORCE_LINK(test_godot_physics_2d_polygon_mass)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "modules/godot_physics_2d/godot_shape_2d.h"

namespace TestGodotPhysics2DPolygonMass {

TEST_CASE("[GodotPhysics2D] Convex polygon mass uses its actual area distribution") {
	GodotConvexPolygonShape2D rectangle;
	PackedVector2Array vertices;
	vertices.push_back(Vector2(-2.0, -1.0));
	vertices.push_back(Vector2(2.0, -1.0));
	vertices.push_back(Vector2(2.0, 1.0));
	vertices.push_back(Vector2(-2.0, 1.0));
	rectangle.set_data(vertices);

	CHECK(rectangle.get_center_of_mass().is_equal_approx(Vector2()));
	CHECK(Math::is_equal_approx(rectangle.get_moment_of_inertia(real_t(12.0), Vector2(1.0, 1.0)), real_t(20.0)));
	CHECK(Math::is_equal_approx(rectangle.get_moment_of_inertia(real_t(12.0), Vector2(2.0, 0.5)), real_t(65.0)));

	for (int i = 0; i < vertices.size(); ++i) {
		vertices.set(i, vertices[i] + Vector2(7.0, -5.0));
	}
	rectangle.set_data(vertices);
	CHECK(rectangle.get_center_of_mass().is_equal_approx(Vector2(7.0, -5.0)));
	CHECK(Math::is_equal_approx(rectangle.get_moment_of_inertia(real_t(12.0), Vector2(1.0, 1.0)), real_t(20.0)));

	GodotConvexPolygonShape2D triangle;
	PackedVector2Array corners;
	corners.push_back(Vector2(0.0, 0.0));
	corners.push_back(Vector2(2.0, 0.0));
	corners.push_back(Vector2(0.0, 2.0));
	triangle.set_data(corners);
	CHECK(triangle.get_center_of_mass().is_equal_approx(Vector2(real_t(2.0 / 3.0), real_t(2.0 / 3.0))));
	CHECK(Math::is_equal_approx(triangle.get_moment_of_inertia(real_t(9.0), Vector2(1.0, 1.0)), real_t(4.0)));

	PackedVector2Array reversed;
	reversed.push_back(corners[2]);
	reversed.push_back(corners[1]);
	reversed.push_back(corners[0]);
	triangle.set_data(reversed);
	CHECK(triangle.get_center_of_mass().is_equal_approx(Vector2(real_t(2.0 / 3.0), real_t(2.0 / 3.0))));
	CHECK(Math::is_equal_approx(triangle.get_moment_of_inertia(real_t(9.0), Vector2(1.0, 1.0)), real_t(4.0)));
}

TEST_CASE("[GodotPhysics2D] Degenerate convex polygon retains bounded inertia fallback") {
	GodotConvexPolygonShape2D polygon;
	PackedVector2Array segment_vertices;
	segment_vertices.push_back(Vector2(-2.0, -1.0));
	segment_vertices.push_back(Vector2(2.0, 1.0));
	polygon.set_data(segment_vertices);
	CHECK(polygon.get_center_of_mass().is_equal_approx(Vector2()));
	CHECK(Math::is_equal_approx(polygon.get_moment_of_inertia(real_t(12.0), Vector2(1.0, 1.0)), real_t(20.0)));
}

} // namespace TestGodotPhysics2DPolygonMass

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
