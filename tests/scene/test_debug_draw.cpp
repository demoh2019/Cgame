/**************************************************************************/
/*  test_debug_draw.cpp                                                   */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_debug_draw)

#include "scene/main/debug_draw.h"
#include "scene/main/debug_draw_buffer.h"
#include "scene/main/debug_draw_geometry.h"

namespace TestDebugDraw {

using namespace DebugDrawGeometry;

TEST_CASE("[DebugDraw] Circle and sphere segments lie on the shape") {
	LocalVector<DebugSegment3D> segments;
	circle_3d(segments, Vector3(1, 2, 3), Vector3(0, 0, 5), 2.0, Color(1, 0, 0), 16);
	CHECK(segments.size() == 16);
	for (const DebugSegment3D &segment : segments) {
		// Every vertex is at the radius from the center and inside the plane z = 3.
		CHECK((segment.a - Vector3(1, 2, 3)).length() == doctest::Approx(2.0));
		CHECK(segment.a.z == doctest::Approx(3.0));
		CHECK(segment.color == Color(1, 0, 0));
	}
	// The ring is closed.
	CHECK(segments[15].b.is_equal_approx(segments[0].a));

	segments.clear();
	sphere_3d(segments, Vector3(), 1.5, Color(), 12);
	CHECK(segments.size() == 36);
	for (const DebugSegment3D &segment : segments) {
		CHECK(segment.a.length() == doctest::Approx(1.5));
		CHECK(segment.b.length() == doctest::Approx(1.5));
	}

	// Degenerate input is repaired instead of producing NaN.
	segments.clear();
	circle_3d(segments, Vector3(), Vector3(), 1.0, Color(), 1);
	CHECK(segments.size() == MIN_SEGMENTS);
	for (const DebugSegment3D &segment : segments) {
		CHECK(segment.a.is_finite());
	}
	CHECK(clamp_segments(100000) == MAX_SEGMENTS);
}

TEST_CASE("[DebugDraw] Box has twelve distinct edges of the right length") {
	LocalVector<DebugSegment3D> segments;
	const Transform3D transform(Basis(Vector3(0, 1, 0), real_t(0.7)), Vector3(5, 0, 0));
	box_3d(segments, transform, Vector3(2, 4, 6), Color());
	CHECK(segments.size() == 12);
	int lengths[3] = { 0, 0, 0 };
	for (const DebugSegment3D &segment : segments) {
		const real_t length = segment.a.distance_to(segment.b);
		if (Math::is_equal_approx(length, real_t(2.0))) {
			lengths[0]++;
		} else if (Math::is_equal_approx(length, real_t(4.0))) {
			lengths[1]++;
		} else if (Math::is_equal_approx(length, real_t(6.0))) {
			lengths[2]++;
		}
	}
	CHECK(lengths[0] == 4);
	CHECK(lengths[1] == 4);
	CHECK(lengths[2] == 4);

	segments.clear();
	aabb_3d(segments, AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)), Color());
	CHECK(segments.size() == 12);
	// Negative sizes are normalized.
	segments.clear();
	aabb_3d(segments, AABB(Vector3(1, 1, 1), Vector3(-2, -2, -2)), Color());
	for (const DebugSegment3D &segment : segments) {
		CHECK(segment.a.distance_to(segment.b) == doctest::Approx(2.0));
	}
}

TEST_CASE("[DebugDraw] Arrow, cross, axes and paths") {
	LocalVector<DebugSegment3D> segments;
	arrow_3d(segments, Vector3(), Vector3(0, 0, 10), Color(), 1.0);
	CHECK(segments.size() == 5); // Shaft + four head lines.
	for (uint32_t i = 1; i < segments.size(); i++) {
		CHECK(segments[i].a.is_equal_approx(Vector3(0, 0, 10))); // All head lines start at the tip.
		CHECK(segments[i].b.z < real_t(10.0));
	}
	// A zero-length arrow draws only the (degenerate) shaft and no NaNs.
	segments.clear();
	arrow_3d(segments, Vector3(1, 1, 1), Vector3(1, 1, 1), Color(), 1.0);
	CHECK(segments.size() == 1);
	// A head longer than the shaft is capped to the shaft.
	segments.clear();
	arrow_3d(segments, Vector3(), Vector3(0, 0, 0.1), Color(), 5.0);
	for (const DebugSegment3D &segment : segments) {
		CHECK(segment.b.is_finite());
		CHECK(segment.b.length() < real_t(0.2));
	}

	segments.clear();
	cross_3d(segments, Vector3(1, 2, 3), 2.0, Color());
	CHECK(segments.size() == 3);
	CHECK(segments[0].a.is_equal_approx(Vector3(0, 2, 3)));
	CHECK(segments[0].b.is_equal_approx(Vector3(2, 2, 3)));

	segments.clear();
	axes_3d(segments, Transform3D(Basis::from_scale(Vector3(5, 5, 5)), Vector3(1, 0, 0)), 2.0);
	CHECK(segments.size() == 3);
	CHECK(segments[0].b.is_equal_approx(Vector3(3, 0, 0))); // Unit length regardless of scale.
	CHECK(segments[0].color.r > segments[0].color.g);
	CHECK(segments[1].color.g > segments[1].color.r);
	CHECK(segments[2].color.b > segments[2].color.r);

	Vector<Vector3> points;
	points.push_back(Vector3(0, 0, 0));
	points.push_back(Vector3(1, 0, 0));
	points.push_back(Vector3(1, 1, 0));
	segments.clear();
	path_3d(segments, points, Color(), false);
	CHECK(segments.size() == 2);
	segments.clear();
	path_3d(segments, points, Color(), true);
	CHECK(segments.size() == 3);
	CHECK(segments[2].b.is_equal_approx(Vector3()));
	segments.clear();
	path_3d(segments, Vector<Vector3>(), Color(), true);
	CHECK(segments.is_empty());
}

TEST_CASE("[DebugDraw] 2D shapes") {
	LocalVector<DebugSegment2D> segments;
	circle_2d(segments, Vector2(10, 10), 4.0, Color(), 20);
	CHECK(segments.size() == 20);
	for (const DebugSegment2D &segment : segments) {
		CHECK(segment.a.distance_to(Vector2(10, 10)) == doctest::Approx(4.0));
	}

	segments.clear();
	rect_2d(segments, Rect2(Vector2(5, 5), Vector2(-3, -2)), Color());
	CHECK(segments.size() == 4);
	for (const DebugSegment2D &segment : segments) {
		CHECK(segment.a.x >= real_t(2.0));
		CHECK(segment.a.x <= real_t(5.0));
		CHECK(segment.a.y >= real_t(3.0));
		CHECK(segment.a.y <= real_t(5.0));
	}

	segments.clear();
	arrow_2d(segments, Vector2(), Vector2(10, 0), Color(), 2.0);
	CHECK(segments.size() == 3);
	CHECK(segments[1].a.is_equal_approx(Vector2(10, 0)));
	CHECK(segments[1].b.x < real_t(10.0));
	CHECK(segments[1].b.y == doctest::Approx(-segments[2].b.y));

	segments.clear();
	cross_2d(segments, Vector2(3, 3), 4.0, Color());
	CHECK(segments.size() == 2);
}

TEST_CASE("[DebugDraw] One-frame shapes survive until they were drawn once") {
	DebugDrawBuffer<DebugSegment3D> buffer;
	const DebugSegment3D segment = { Vector3(), Vector3(1, 0, 0), Color() };

	buffer.add(segment, 10.0, 0.0, 5);
	// A physics-time call with no rendered frame in between must not lose the shape.
	buffer.begin_frame(10.016, 6);
	CHECK(buffer.size() == 1);
	buffer.mark_drawn();
	buffer.begin_frame(10.033, 7);
	CHECK(buffer.size() == 0);

	// Without a renderer nothing is ever marked drawn: age eventually removes the shape.
	buffer.add(segment, 20.0, 0.0, 100);
	buffer.begin_frame(20.01, 101);
	CHECK(buffer.size() == 1);
	buffer.begin_frame(20.02, 102);
	CHECK(buffer.size() == 0);
}

TEST_CASE("[DebugDraw] Timed shapes live for their duration") {
	DebugDrawBuffer<DebugSegment3D> buffer;
	const DebugSegment3D segment = { Vector3(), Vector3(0, 1, 0), Color() };

	buffer.add(segment, 100.0, 2.0, 1);
	buffer.add(segment, 100.0, 0.0, 1);
	buffer.mark_drawn();
	buffer.begin_frame(101.0, 2);
	CHECK(buffer.size() == 1); // The one-frame shape is gone, the 2 s shape stays.
	buffer.begin_frame(101.99, 3);
	CHECK(buffer.size() == 1);
	buffer.begin_frame(102.0, 4);
	CHECK(buffer.size() == 0);
}

TEST_CASE("[DebugDraw] Buffer is capped and keeps counting what it dropped") {
	DebugDrawBuffer<DebugSegment2D> buffer;
	buffer.set_max_entries(3);
	const DebugSegment2D segment = { Vector2(), Vector2(1, 1), Color() };
	for (int i = 0; i < 5; i++) {
		buffer.add(segment, 0.0, 10.0, 0);
	}
	CHECK(buffer.size() == 3);
	CHECK(buffer.get_dropped_count() == 2);
	buffer.clear();
	CHECK(buffer.is_empty());
}

TEST_CASE("[SceneTree][DebugDraw] Singleton queues shapes and respects enabled and clear") {
	DebugDraw *draw = DebugDraw::get_singleton();
	REQUIRE(draw != nullptr);
	const bool was_enabled = draw->is_enabled();
	draw->set_enabled(true);
	draw->clear();

	draw->line(Vector3(), Vector3(1, 1, 1), Color(), 5.0);
	CHECK(draw->get_segment_count_3d() == 1);
	draw->sphere(Vector3(), 1.0, Color(), 5.0, 8);
	CHECK(draw->get_segment_count_3d() == 1 + 24);
	draw->line_2d(Vector2(), Vector2(10, 10), Color(), 5.0);
	draw->rect_2d(Rect2(0, 0, 4, 4), Color(), 5.0);
	CHECK(draw->get_segment_count_2d() == 5);

	draw->clear();
	CHECK(draw->get_segment_count_3d() == 0);
	CHECK(draw->get_segment_count_2d() == 0);

	draw->line(Vector3(), Vector3(1, 0, 0), Color(), 5.0);
	draw->set_enabled(false);
	CHECK(draw->get_segment_count_3d() == 0); // Disabling removes queued shapes...
	draw->line(Vector3(), Vector3(1, 0, 0), Color(), 5.0);
	CHECK(draw->get_segment_count_3d() == 0); // ...and later calls are no-ops.

	draw->set_enabled(was_enabled);
	draw->clear();
}

} // namespace TestDebugDraw
