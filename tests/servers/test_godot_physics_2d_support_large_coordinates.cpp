/**************************************************************************/
/*  test_godot_physics_2d_support_large_coordinates.cpp                              */
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

TEST_FORCE_LINK(test_godot_physics_2d_support_large_coordinates)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "modules/godot_physics_2d/godot_shape_2d.h"

namespace TestGodotPhysics2DSupportLargeCoordinates {

TEST_CASE("[GodotPhysics2D] Convex polygon support remains defined at huge coordinates") {
	GodotConvexPolygonShape2D polygon;
	PackedVector2Array vertices;
	vertices.push_back(Vector2(real_t(-4.0e11), real_t(-1.0e10)));
	vertices.push_back(Vector2(real_t(-2.0e11), real_t(-1.0e10)));
	vertices.push_back(Vector2(real_t(-3.0e11), real_t(2.0e10)));
	polygon.set_data(vertices);

	Vector2 supports[2];
	int count = 0;
	polygon.get_supports(Vector2(1.0, 0.0), supports, count);
	CHECK(count == 1);
	CHECK(supports[0].is_equal_approx(vertices[1]));

	polygon.get_supports(Vector2(-1.0, 0.0), supports, count);
	CHECK(count == 1);
	CHECK(supports[0].is_equal_approx(vertices[0]));
}

TEST_CASE("[GodotPhysics2D] Concave polygon support remains defined at huge coordinates") {
	GodotConcavePolygonShape2D polygon;
	PackedVector2Array edges;
	edges.push_back(Vector2(real_t(-4.0e11), real_t(-1.0e10)));
	edges.push_back(Vector2(real_t(-3.0e11), real_t(-1.0e10)));
	edges.push_back(Vector2(real_t(-3.0e11), real_t(-1.0e10)));
	edges.push_back(Vector2(real_t(-2.0e11), real_t(-1.0e10)));
	polygon.set_data(edges);

	Vector2 supports[2];
	int count = 0;
	polygon.get_supports(Vector2(1.0, 0.0), supports, count);
	CHECK(count == 1);
	CHECK(supports[0].is_equal_approx(Vector2(real_t(-2.0e11), real_t(-1.0e10))));

	polygon.get_supports(Vector2(-1.0, 0.0), supports, count);
	CHECK(count == 1);
	CHECK(supports[0].is_equal_approx(Vector2(real_t(-4.0e11), real_t(-1.0e10))));
}

} // namespace TestGodotPhysics2DSupportLargeCoordinates

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
