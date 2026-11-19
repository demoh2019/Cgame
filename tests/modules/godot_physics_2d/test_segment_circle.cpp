/**************************************************************************/
/*  test_segment_circle.cpp                                               */
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

TEST_FORCE_LINK(test_segment_circle)

#include "modules/godot_physics_2d/godot_collision_solver_2d_sat.h"

namespace TestSegmentCircle {

struct ContactCapture {
	Vector2 point_a;
	Vector2 point_b;
	int count = 0;

	static void on_contact(const Vector2 &p_a, const Vector2 &p_b, void *p_userdata) {
		ContactCapture *capture = static_cast<ContactCapture *>(p_userdata);
		capture->point_a = p_a;
		capture->point_b = p_b;
		capture->count++;
	}
};

static bool collide(const GodotSegmentShape2D &p_segment, const Transform2D &p_segment_transform, const GodotCircleShape2D &p_circle, const Transform2D &p_circle_transform,
		ContactCapture *p_capture = nullptr, Vector2 *r_sep_axis = nullptr, const Vector2 &p_circle_motion = Vector2(), real_t p_margin_a = 0.0, real_t p_margin_b = 0.0) {
	return sat_2d_calculate_penetration(&p_segment, p_segment_transform, Vector2(), &p_circle, p_circle_transform, p_circle_motion,
			p_capture ? ContactCapture::on_contact : nullptr, p_capture, false, r_sep_axis, p_margin_a, p_margin_b);
}

TEST_CASE("[Physics2D] Segment-circle direct manifold: face, endpoint and separation") {
	GodotSegmentShape2D segment(Vector2(-2, 0), Vector2(2, 0), Vector2(0, -1));
	GodotCircleShape2D circle;
	circle.set_data(real_t(1.0));
	const Transform2D segment_transform;

	Transform2D circle_transform;
	circle_transform.columns[2] = Vector2(0, real_t(0.75));

	ContactCapture contact;
	Vector2 sep_axis(1, 0);
	CHECK(collide(segment, segment_transform, circle, circle_transform, &contact, &sep_axis));
	CHECK(contact.count == 1);
	CHECK(contact.point_a.is_equal_approx(Vector2(0, 0)));
	CHECK(contact.point_b.is_equal_approx(Vector2(0, real_t(-0.25))));
	CHECK(sep_axis == Vector2());

	circle_transform.columns[2] = Vector2(real_t(2.75), 0);
	contact = ContactCapture();
	CHECK(collide(segment, segment_transform, circle, circle_transform, &contact));
	CHECK(contact.count == 1);
	CHECK(contact.point_a.is_equal_approx(Vector2(2, 0)));
	CHECK(contact.point_b.is_equal_approx(Vector2(real_t(1.75), 0)));

	circle_transform.columns[2] = Vector2(0, real_t(1.5));
	sep_axis = Vector2();
	CHECK_FALSE(collide(segment, segment_transform, circle, circle_transform, nullptr, &sep_axis));
	CHECK(sep_axis.is_equal_approx(Vector2(0, -1)));

	circle_transform.columns[2] = Vector2(0, 1);
	CHECK(collide(segment, segment_transform, circle, circle_transform));

	// Exact centerline coincidence must fall through to the original SAT solver.
	circle_transform.columns[2] = Vector2(0, 0);
	CHECK(collide(segment, segment_transform, circle, circle_transform));
}

TEST_CASE("[Physics2D] Segment-circle direct manifold: margins and rotation") {
	GodotSegmentShape2D segment(Vector2(-2, 0), Vector2(2, 0), Vector2(0, -1));
	GodotCircleShape2D circle;
	circle.set_data(real_t(1.0));
	const Transform2D segment_transform;

	Transform2D circle_transform;
	circle_transform.columns[2] = Vector2(0, real_t(1.2));
	ContactCapture contact;
	CHECK(collide(segment, segment_transform, circle, circle_transform, &contact, nullptr, Vector2(), real_t(0.25), real_t(0.15)));
	CHECK(contact.count == 1);
	CHECK(contact.point_a.is_equal_approx(Vector2(0, real_t(0.25))));
	CHECK(contact.point_b.is_equal_approx(Vector2(0, real_t(0.05))));

	const Transform2D rotated(Math::PI * real_t(0.5), Vector2(3, 4));
	circle_transform.columns[2] = Vector2(real_t(3.75), 4);
	contact = ContactCapture();
	CHECK(collide(segment, rotated, circle, circle_transform, &contact));
	CHECK(contact.count == 1);
	CHECK(contact.point_a.is_equal_approx(Vector2(3, 4)));
	CHECK(contact.point_b.is_equal_approx(Vector2(real_t(2.75), 4)));
}

TEST_CASE("[Physics2D] Segment-circle geometry grid and SAT fallback") {
	GodotSegmentShape2D segment(Vector2(-2, 0), Vector2(2, 0), Vector2(0, -1));
	GodotCircleShape2D circle;
	circle.set_data(real_t(1.0));
	const Transform2D segment_transform;
	Transform2D circle_transform;

	// Compare all fast-path collision decisions with a separate analytic
	// squared-distance oracle (no square roots or SAT internals).
	for (int x = -20; x <= 20; x++) {
		for (int y = -20; y <= 20; y++) {
			const Vector2 center(x * real_t(0.21) + real_t(0.037), y * real_t(0.17) + real_t(0.049));
			const real_t dx = MAX(Math::abs(center.x) - real_t(2.0), real_t(0.0));
			const real_t distance_squared = dx * dx + center.y * center.y;
			if (Math::abs(distance_squared - real_t(1.0)) < real_t(0.00001)) {
				continue;
			}
			circle_transform.columns[2] = center;
			CHECK(collide(segment, segment_transform, circle, circle_transform) == (distance_squared < real_t(1.0)));
		}
	}

	// Non-uniform scaling and motion require the conservative SAT path.
	circle_transform.columns[0] = Vector2(real_t(1.5), 0);
	circle_transform.columns[1] = Vector2(0, real_t(1.5));
	circle_transform.columns[2] = Vector2(0, real_t(1.2));
	CHECK(collide(segment, segment_transform, circle, circle_transform));

	circle_transform.columns[0] = Vector2(1, 0);
	circle_transform.columns[1] = Vector2(0, 1);
	circle_transform.columns[2] = Vector2(0, real_t(1.5));
	CHECK(collide(segment, segment_transform, circle, circle_transform, nullptr, nullptr, Vector2(0, real_t(-0.75))));
}

} // namespace TestSegmentCircle
