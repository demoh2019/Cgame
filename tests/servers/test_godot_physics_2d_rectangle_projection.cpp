/**************************************************************************/
/*  test_godot_physics_2d_rectangle_projection.cpp                         */
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

TEST_FORCE_LINK(test_godot_physics_2d_rectangle_projection)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "modules/godot_physics_2d/godot_shape_2d.h"

namespace TestGodotPhysics2DRectangleProjection {

TEST_CASE("[GodotPhysics2D] Rectangle SAT projections match all transformed corners") {
	GodotRectangleShape2D rectangle;
	rectangle.set_data(Vector2(2.0, 3.0));

	const Transform2D transforms[] = {
		Transform2D(),
		Transform2D(real_t(0.6), Vector2(3.0, -4.0)),
		Transform2D(Vector2(2.0, 0.3), Vector2(0.4, 0.8), Vector2(-5.0, 6.0)),
		Transform2D(Vector2(-1.0, 0.0), Vector2(0.0, 2.0), Vector2(12.0, -4.0)),
		Transform2D(Vector2(0.0, 0.0), Vector2(0.0, 3.0), Vector2())
	};
	const Vector2 axes[] = {
		Vector2(1.0, 0.0),
		Vector2(0.0, 1.0),
		Vector2(1.0, 1.0).normalized(),
		Vector2(-2.0, 3.0),
		Vector2()
	};
	const Vector2 cast_motion(1.7, -2.3);

	for (const Transform2D &transform : transforms) {
		for (const Vector2 &axis : axes) {
			real_t expected_min = 1e20;
			real_t expected_max = -1e20;
			real_t cast_min = 1e20;
			real_t cast_max = -1e20;
			for (int i = 0; i < 4; i++) {
				const Vector2 corner((i & 1) ? real_t(2.0) : real_t(-2.0),
						(i & 2) ? real_t(3.0) : real_t(-3.0));
				const real_t distance = axis.dot(transform.xform(corner));
				expected_min = MIN(expected_min, distance);
				expected_max = MAX(expected_max, distance);
				const real_t swept_distance = distance + axis.dot(cast_motion);
				cast_min = MIN(cast_min, MIN(distance, swept_distance));
				cast_max = MAX(cast_max, MAX(distance, swept_distance));
			}

			real_t actual_min = 0.0;
			real_t actual_max = 0.0;
			rectangle.project_range(axis, transform, actual_min, actual_max);
			CHECK(Math::is_equal_approx(actual_min, expected_min));
			CHECK(Math::is_equal_approx(actual_max, expected_max));

			real_t actual_cast_min = 0.0;
			real_t actual_cast_max = 0.0;
			rectangle.project_range_cast(cast_motion, axis, transform, actual_cast_min, actual_cast_max);
			CHECK(Math::is_equal_approx(actual_cast_min, cast_min));
			CHECK(Math::is_equal_approx(actual_cast_max, cast_max));
		}
	}
}

} // namespace TestGodotPhysics2DRectangleProjection

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
