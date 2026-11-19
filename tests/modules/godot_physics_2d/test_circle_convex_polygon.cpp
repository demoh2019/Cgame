/**************************************************************************/
/*  test_circle_convex_polygon.cpp                                        */
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

TEST_FORCE_LINK(test_circle_convex_polygon)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "modules/godot_physics_2d/godot_collision_solver_2d_sat.h"

namespace TestCircleConvexPolygon {

struct Contact {
	Vector2 circle_point;
	Vector2 polygon_point;
	int count = 0;

	static void record(const Vector2 &p_circle, const Vector2 &p_polygon, void *p_userdata) {
		Contact *self = static_cast<Contact *>(p_userdata);
		self->circle_point = p_circle;
		self->polygon_point = p_polygon;
		self->count++;
	}
};

static void set_square(GodotConvexPolygonShape2D &r_polygon) {
	PackedVector2Array vertices;
	vertices.push_back(Vector2(-2, -2));
	vertices.push_back(Vector2(2, -2));
	vertices.push_back(Vector2(2, 2));
	vertices.push_back(Vector2(-2, 2));
	r_polygon.set_data(vertices);
}

static bool collide(const GodotCircleShape2D &p_circle, const Transform2D &p_circle_transform,
		const GodotConvexPolygonShape2D &p_polygon, const Transform2D &p_polygon_transform,
		Contact *p_contact = nullptr, Vector2 *r_sep_axis = nullptr, const Vector2 &p_motion = Vector2(),
		real_t p_circle_margin = 0.0, real_t p_polygon_margin = 0.0) {
	return sat_2d_calculate_penetration(&p_circle, p_circle_transform, p_motion,
			&p_polygon, p_polygon_transform, Vector2(),
			p_contact ? Contact::record : nullptr, p_contact, false, r_sep_axis,
			p_circle_margin, p_polygon_margin);
}

TEST_CASE("[GodotPhysics2D] Circle-convex polygon face, corner, cache and margins") {
	GodotConvexPolygonShape2D polygon;
	set_square(polygon);
	GodotCircleShape2D circle;
	circle.set_data(real_t(1.0));
	Transform2D circle_transform;
	const Transform2D polygon_transform;

	Contact contact;
	Vector2 sep_axis(0, -1);
	circle_transform.set_origin(Vector2(real_t(2.6), 0));
	CHECK(collide(circle, circle_transform, polygon, polygon_transform, &contact, &sep_axis));
	CHECK(contact.count == 1);
	CHECK(contact.circle_point.is_equal_approx(Vector2(real_t(1.6), 0)));
	CHECK(contact.polygon_point.is_equal_approx(Vector2(2, 0)));
	CHECK(sep_axis == Vector2());

	contact = Contact();
	circle_transform.set_origin(Vector2(real_t(2.6), real_t(2.6)));
	CHECK(collide(circle, circle_transform, polygon, polygon_transform, &contact));
	CHECK(contact.count == 1);
	CHECK(contact.polygon_point.is_equal_approx(Vector2(2, 2)));

	contact = Contact();
	circle_transform.set_origin(Vector2(real_t(3.2), 0));
	CHECK(collide(circle, circle_transform, polygon, polygon_transform, &contact, nullptr,
			Vector2(), real_t(0.2), real_t(0.1)));
	CHECK(contact.count == 1);
	CHECK(contact.circle_point.is_equal_approx(Vector2(2, 0)));
	CHECK(contact.polygon_point.is_equal_approx(Vector2(real_t(2.1), 0)));

	sep_axis = Vector2();
	circle_transform.set_origin(Vector2(real_t(3.5), 0));
	CHECK_FALSE(collide(circle, circle_transform, polygon, polygon_transform, nullptr, &sep_axis));
	CHECK(sep_axis.is_equal_approx(Vector2(1, 0)));

	circle_transform.set_origin(Vector2(3, 0));
	CHECK(collide(circle, circle_transform, polygon, polygon_transform));

	// Embedded circles and coincident boundary points fall back to SAT.
	circle_transform.set_origin(Vector2(0, 0));
	CHECK(collide(circle, circle_transform, polygon, polygon_transform));
	circle_transform.set_origin(Vector2(2, 0));
	CHECK(collide(circle, circle_transform, polygon, polygon_transform));
}

TEST_CASE("[GodotPhysics2D] Circle-convex polygon external geometry grid") {
	GodotConvexPolygonShape2D polygon;
	set_square(polygon);
	GodotCircleShape2D circle;
	circle.set_data(real_t(1.0));
	Transform2D circle_transform;
	const Transform2D polygon_transform;

	// Independent squared-distance oracle for the exterior of [-2, 2]^2.
	// Interior positions intentionally use the separate SAT fallback.
	for (int x = -30; x <= 30; x++) {
		for (int y = -30; y <= 30; y++) {
			const Vector2 center(x * real_t(0.18) + real_t(0.025), y * real_t(0.17) + real_t(0.037));
			if (Math::abs(center.x) <= 2 && Math::abs(center.y) <= 2) {
				continue;
			}
			const real_t dx = MAX(Math::abs(center.x) - real_t(2.0), real_t(0.0));
			const real_t dy = MAX(Math::abs(center.y) - real_t(2.0), real_t(0.0));
			const real_t distance_squared = dx * dx + dy * dy;
			if (Math::abs(distance_squared - real_t(1.0)) <= real_t(0.0001)) {
				continue;
			}
			circle_transform.set_origin(center);
			CHECK(collide(circle, circle_transform, polygon, polygon_transform) == (distance_squared < real_t(1.0)));
		}
	}
}

TEST_CASE("[GodotPhysics2D] Circle-convex polygon rotated and reflected geometry") {
	PackedVector2Array vertices;
	vertices.push_back(Vector2(0, 0));
	vertices.push_back(Vector2(4, 0));
	vertices.push_back(Vector2(0, 3));
	GodotConvexPolygonShape2D triangle;
	triangle.set_data(vertices);

	GodotCircleShape2D circle;
	circle.set_data(real_t(1.0));
	Transform2D circle_transform;
	Contact contact;

	const Transform2D reflected(real_t(-1.0), 0, 0, real_t(1.0), 10, 0);
	circle_transform.set_origin(Vector2(8, real_t(-0.5)));
	CHECK(collide(circle, circle_transform, triangle, reflected, &contact));
	CHECK(contact.count == 1);
	CHECK(contact.circle_point.is_equal_approx(Vector2(8, real_t(0.5))));
	CHECK(contact.polygon_point.is_equal_approx(Vector2(8, 0)));

	contact = Contact();
	const Transform2D rotated(real_t(Math::PI * 0.5), Vector2(0, 0));
	circle_transform.set_origin(Vector2(real_t(0.5), 2));
	CHECK(collide(circle, circle_transform, triangle, rotated, &contact));
	CHECK(contact.count == 1);
	CHECK(contact.polygon_point.is_equal_approx(Vector2(0, 2)));
}

TEST_CASE("[GodotPhysics2D] Circle-convex polygon sweep and scaling retain SAT") {
	GodotConvexPolygonShape2D polygon;
	set_square(polygon);
	GodotCircleShape2D circle;
	circle.set_data(real_t(1.0));
	Transform2D circle_transform;
	const Transform2D polygon_transform;

	circle_transform.columns[0] = Vector2(real_t(1.5), 0);
	circle_transform.columns[1] = Vector2(0, real_t(1.5));
	circle_transform.set_origin(Vector2(real_t(3.25), 0));
	CHECK(collide(circle, circle_transform, polygon, polygon_transform));

	circle_transform.columns[0] = Vector2(1, 0);
	circle_transform.columns[1] = Vector2(0, 1);
	circle_transform.set_origin(Vector2(4, 0));
	CHECK(collide(circle, circle_transform, polygon, polygon_transform, nullptr, nullptr, Vector2(-2, 0)));
}

} // namespace TestCircleConvexPolygon

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
