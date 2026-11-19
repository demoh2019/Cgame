/**************************************************************************/
/*  test_godot_physics_2d_swept_projection.cpp                            */
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

TEST_FORCE_LINK(test_godot_physics_2d_swept_projection)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "modules/godot_physics_2d/godot_shape_2d.h"

namespace TestGodotPhysics2DSweptProjection {

TEST_CASE("[GodotPhysics2D] Swept projections match independent start and end projections") {
	GodotSegmentShape2D segment;
	segment.set_data(Rect2(Vector2(-2.0, 1.0), Vector2(2.0, -1.0)));

	GodotCircleShape2D circle;
	circle.set_data(real_t(1.25));

	GodotRectangleShape2D rectangle;
	rectangle.set_data(Vector2(3.0, 2.0));

	GodotCapsuleShape2D capsule;
	capsule.set_data(Vector2(0.6, 3.5));

	GodotConvexPolygonShape2D polygon;
	PackedVector2Array vertices;
	vertices.push_back(Vector2(-2.0, -1.0));
	vertices.push_back(Vector2(2.0, -1.0));
	vertices.push_back(Vector2(1.0, 2.0));
	vertices.push_back(Vector2(-1.0, 1.0));
	polygon.set_data(vertices);

	const GodotShape2D *shapes[] = { &segment, &circle, &rectangle, &capsule, &polygon };
	const Transform2D transforms[] = {
		Transform2D(),
		Transform2D(real_t(0.7), Vector2(3.0, -4.0)),
		Transform2D(Vector2(1.5, 0.25), Vector2(-0.4, 0.8), Vector2(-8.0, 3.0)),
		Transform2D(Vector2(-1.0, 0.0), Vector2(0.0, 2.0), Vector2(2.0, 6.0))
	};
	const Vector2 axes[] = {
		Vector2(1.0, 0.0),
		Vector2(0.0, 1.0),
		Vector2(-2.0, 3.0),
		Vector2(1.0, -1.0).normalized(),
		Vector2()
	};
	const Vector2 motions[] = {
		Vector2(),
		Vector2(4.0, 0.0),
		Vector2(-2.0, 0.5),
		Vector2(1.7, -3.1)
	};

	for (const GodotShape2D *shape : shapes) {
		for (const Transform2D &transform : transforms) {
			for (const Vector2 &axis : axes) {
				for (const Vector2 &motion : motions) {
					Transform2D moved_transform = transform;
					moved_transform.set_origin(transform.get_origin() + motion);

					real_t start_min = 0.0, start_max = 0.0;
					real_t end_min = 0.0, end_max = 0.0;
					shape->project_rangev(axis, transform, start_min, start_max);
					shape->project_rangev(axis, moved_transform, end_min, end_max);

					real_t cast_min = 0.0, cast_max = 0.0;
					shape->project_range_castv(motion, axis, transform, cast_min, cast_max);

					CHECK(Math::is_equal_approx(cast_min, MIN(start_min, end_min)));
					CHECK(Math::is_equal_approx(cast_max, MAX(start_max, end_max)));
				}
			}
		}
	}
}

} // namespace TestGodotPhysics2DSweptProjection

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
