/**************************************************************************/
/*  test_godot_physics_2d_convex_projection.cpp                            */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "modules/modules_enabled.gen.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_2d_convex_projection)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "modules/godot_physics_2d/godot_shape_2d.h"

namespace TestGodotPhysics2DConvexProjection {

TEST_CASE("[GodotPhysics2D] Convex polygon SAT projections match transformed vertices") {
	// Include longer polygons, where a single axis transform is especially valuable.
	const int vertex_counts[] = { 3, 4, 8, 32, 128 };
	const Transform2D transforms[] = {
		Transform2D(),
		Transform2D(real_t(0.6), Vector2(3.0, -4.0)),
		Transform2D(Vector2(2.0, 0.3), Vector2(0.4, 0.8), Vector2(-5.0, 6.0)),
		Transform2D(Vector2(-1.0, 0.0), Vector2(0.0, 2.0), Vector2(12.0, -4.0)),
		Transform2D(Vector2(0.0, 0.0), Vector2(0.0, 3.0), Vector2()),
		Transform2D(Vector2(0.0, 0.0), Vector2(0.0, 0.0), Vector2(-4.0, 2.0))
	};
	const Vector2 axes[] = {
		Vector2(1.0, 0.0),
		Vector2(0.0, 1.0),
		Vector2(1.0, 1.0).normalized(),
		Vector2(-2.0, 3.0),
		Vector2(0.7, -2.3),
		Vector2()
	};
	const Vector2 cast_motion(1.7, -2.3);

	for (int vertex_count : vertex_counts) {
		PackedVector2Array vertices;
		for (int i = 0; i < vertex_count; ++i) {
			const real_t angle = real_t(Math::TAU) * real_t(i) / real_t(vertex_count);
			vertices.push_back(Vector2(real_t(2.0) * Math::cos(angle), real_t(3.0) * Math::sin(angle)));
		}
		GodotConvexPolygonShape2D polygon;
		polygon.set_data(vertices);

		for (const Transform2D &transform : transforms) {
			for (const Vector2 &axis : axes) {
				real_t expected_min = axis.dot(transform.xform(vertices[0]));
				real_t expected_max = expected_min;
				for (int i = 1; i < vertex_count; ++i) {
					const real_t projection = axis.dot(transform.xform(vertices[i]));
					expected_min = MIN(expected_min, projection);
					expected_max = MAX(expected_max, projection);
				}

				real_t actual_min = 0.0;
				real_t actual_max = 0.0;
				polygon.project_range(axis, transform, actual_min, actual_max);
				CHECK(Math::is_equal_approx(actual_min, expected_min));
				CHECK(Math::is_equal_approx(actual_max, expected_max));

				const real_t cast_projection = axis.dot(cast_motion);
				const real_t swept_min = expected_min + MIN(cast_projection, real_t(0.0));
				const real_t swept_max = expected_max + MAX(cast_projection, real_t(0.0));
				polygon.project_range_cast(cast_motion, axis, transform, actual_min, actual_max);
				CHECK(Math::is_equal_approx(actual_min, swept_min));
				CHECK(Math::is_equal_approx(actual_max, swept_max));
			}
		}
	}
}

} // namespace TestGodotPhysics2DConvexProjection

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
