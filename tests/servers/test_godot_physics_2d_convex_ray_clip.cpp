/**************************************************************************/
/*  test_godot_physics_2d_convex_ray_clip.cpp                              */
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

TEST_FORCE_LINK(test_godot_physics_2d_convex_ray_clip)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "core/math/geometry_2d.h"
#include "modules/godot_physics_2d/godot_shape_2d.h"

namespace TestGodotPhysics2DConvexRayClip {

static bool intersect_edges_reference(const PackedVector2Array &p_vertices, const Vector2 &p_begin, const Vector2 &p_end, Vector2 &r_hit) {
	const Vector2 direction = (p_end - p_begin).normalized();
	real_t closest = 0.0;
	bool found = false;
	for (int i = 0; i < p_vertices.size(); ++i) {
		Vector2 hit;
		if (!Geometry2D::segment_intersects_segment(p_begin, p_end,
					p_vertices[i], p_vertices[(i + 1) % p_vertices.size()], &hit)) {
			continue;
		}
		const real_t distance = direction.dot(hit);
		if (!found || distance < closest) {
			closest = distance;
			r_hit = hit;
			found = true;
		}
	}
	return found;
}

TEST_CASE("[GodotPhysics2D] Convex ray clipping agrees with independent edge tests") {
	const Vector2 corners[] = {
		Vector2(-2.0, -1.0), Vector2(2.0, -1.0),
		Vector2(2.0, 1.0), Vector2(-2.0, 1.0)
	};
	for (int winding = 0; winding < 2; ++winding) {
		PackedVector2Array vertices;
		for (int i = 0; i < 4; ++i) {
			vertices.push_back(corners[winding ? 3 - i : i]);
		}
		GodotConvexPolygonShape2D polygon;
		polygon.set_data(vertices);

		Vector2 hit, normal;
		CHECK(polygon.intersect_segment(Vector2(-4.0, 0.0), Vector2(4.0, 0.0), hit, normal));
		CHECK(hit.is_equal_approx(Vector2(-2.0, 0.0)));
		CHECK(normal.is_equal_approx(Vector2(winding ? 1.0 : -1.0, 0.0)));

		CHECK(polygon.intersect_segment(Vector2(), Vector2(4.0, 0.0), hit, normal));
		CHECK(hit.is_equal_approx(Vector2(2.0, 0.0)));

		CHECK(polygon.intersect_segment(Vector2(-2.0, 0.0), Vector2(), hit, normal));
		CHECK(hit.is_equal_approx(Vector2(-2.0, 0.0)));

		CHECK_FALSE(polygon.intersect_segment(Vector2(4.0, 4.0), Vector2(5.0, 5.0), hit, normal));
		CHECK_FALSE(polygon.intersect_segment(Vector2(), Vector2(), hit, normal));

		// Avoid edges and exact corners in this equivalence sweep to keep
		// the test independent of tie-breaking at a shared vertex.
		for (int iy = -15; iy <= 15; ++iy) {
			const real_t y = real_t(iy) * real_t(0.19);
			const Vector2 from(-4.0, y);
			const Vector2 to(4.0, y + real_t(0.073));
			Vector2 expected;
			const bool expected_hit = intersect_edges_reference(vertices, from, to, expected);
			const bool clipped_hit = polygon.intersect_segment(from, to, hit, normal);
			CHECK(expected_hit == clipped_hit);
			if (expected_hit && clipped_hit) {
				CHECK(hit.distance_to(expected) < real_t(0.0002));
			}
		}
	}
}

TEST_CASE("[GodotPhysics2D] Convex ray clipping handles far-away polygons") {
	PackedVector2Array vertices;
	const real_t center = real_t(2.0e10);
	const real_t width = real_t(1.0e8);
	vertices.push_back(Vector2(center - width, -width));
	vertices.push_back(Vector2(center + width, -width));
	vertices.push_back(Vector2(center + width, width));
	vertices.push_back(Vector2(center - width, width));
	GodotConvexPolygonShape2D polygon;
	polygon.set_data(vertices);

	Vector2 hit, normal;
	CHECK(polygon.intersect_segment(Vector2(center - real_t(5.0e8), 0.0),
			Vector2(center + real_t(5.0e8), 0.0), hit, normal));
	CHECK(hit.is_equal_approx(Vector2(center - width, 0.0)));
}

TEST_CASE("[GodotPhysics2D] Degenerate convex polygons retain segment-based ray casts") {
	PackedVector2Array vertices;
	vertices.push_back(Vector2(-1.0, 0.0));
	vertices.push_back(Vector2(1.0, 0.0));
	GodotConvexPolygonShape2D polygon;
	polygon.set_data(vertices);
	Vector2 hit, normal;
	CHECK(polygon.intersect_segment(Vector2(0.0, -2.0), Vector2(0.0, 2.0), hit, normal));
	CHECK(hit.is_equal_approx(Vector2()));
}

} // namespace TestGodotPhysics2DConvexRayClip

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
