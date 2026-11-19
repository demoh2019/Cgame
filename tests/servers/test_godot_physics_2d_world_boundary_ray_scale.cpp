/**************************************************************************/
/*  test_godot_physics_2d_world_boundary_ray_scale.cpp                    */
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

TEST_FORCE_LINK(test_godot_physics_2d_world_boundary_ray_scale)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "modules/godot_physics_2d/godot_shape_2d.h"

namespace TestGodotPhysics2DWorldBoundaryRayScale {

static void configure_boundary(GodotWorldBoundaryShape2D &r_boundary, const Vector2 &p_normal, real_t p_distance) {
	Array data;
	data.push_back(p_normal);
	data.push_back(p_distance);
	r_boundary.set_data(data);
}

TEST_CASE("[GodotPhysics2D] Boundary ray intersection does not reject tiny crossings") {
	GodotWorldBoundaryShape2D boundary;
	configure_boundary(boundary, Vector2(1.0, 0.0), real_t(0.0));

	Vector2 point(77.0, 88.0);
	Vector2 normal(11.0, 22.0);
	CHECK(boundary.intersect_segment(Vector2(real_t(1e-7), 0.0),
			Vector2(real_t(-1e-7), 0.0), point, normal));
	CHECK(Math::abs(point.x) < real_t(1e-8));
	CHECK(Math::abs(point.y) < real_t(1e-8));
	CHECK(normal == Vector2(1.0, 0.0));

	CHECK_FALSE(boundary.intersect_segment(Vector2(real_t(1e-7), 0.0),
			Vector2(real_t(1e-7), real_t(1000000.0)), point, normal));
	CHECK_FALSE(boundary.intersect_segment(Vector2(2.0, 0.0), Vector2(1.0, 0.0), point, normal));
	CHECK_FALSE(boundary.intersect_segment(Vector2(), Vector2(), point, normal));
}

TEST_CASE("[GodotPhysics2D] Boundary ray intersection remains correct for long segments") {
	GodotWorldBoundaryShape2D boundary;
	configure_boundary(boundary, Vector2(2.0, 0.0), real_t(2.0));

	Vector2 point;
	Vector2 normal;
	CHECK(boundary.intersect_segment(Vector2(0.0, -4.0), Vector2(2.0, 4.0), point, normal));
	CHECK(point.is_equal_approx(Vector2(1.0, 0.0)));
	CHECK(normal == Vector2(2.0, 0.0));

	configure_boundary(boundary, Vector2(1.0, 0.0), real_t(0.0));
	CHECK(boundary.intersect_segment(Vector2(real_t(1.0e20), 0.0),
			Vector2(real_t(-1.0e20), 0.0), point, normal));
	CHECK(Math::abs(point.x) < real_t(1000.0));
	CHECK(normal == Vector2(1.0, 0.0));

	configure_boundary(boundary, Vector2(), real_t(0.0));
	CHECK_FALSE(boundary.intersect_segment(Vector2(1.0, 0.0),
			Vector2(-1.0, 0.0), point, normal));
}

} // namespace TestGodotPhysics2DWorldBoundaryRayScale

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
