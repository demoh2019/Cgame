/**************************************************************************/
/*  test_godot_physics_2d_circle_rectangle.cpp                             */
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

TEST_FORCE_LINK(test_godot_physics_2d_circle_rectangle)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "modules/godot_physics_2d/godot_collision_solver_2d_sat.h"

namespace TestGodotPhysics2DCircleRectangle {

struct Contact {
	Vector2 point_a;
	Vector2 point_b;
	int count = 0;
};

static void record_contact(const Vector2 &p_a, const Vector2 &p_b, void *p_userdata) {
	Contact *contact = static_cast<Contact *>(p_userdata);
	contact->point_a = p_a;
	contact->point_b = p_b;
	contact->count++;
}

TEST_CASE("[GodotPhysics2D] Circle-rectangle contact manifold") {
	GodotCircleShape2D circle;
	circle.set_data(real_t(1.0));
	GodotRectangleShape2D rectangle;
	rectangle.set_data(Vector2(2.0, 2.0));

	Transform2D circle_transform;
	Transform2D rectangle_transform;
	Vector2 separating_axis;
	Contact contact;

	SUBCASE("Separated circle") {
		circle_transform.set_origin(Vector2(4.0, 0.0));
		CHECK_FALSE(sat_2d_calculate_penetration(&circle, circle_transform, Vector2(), &rectangle, rectangle_transform, Vector2(), record_contact, &contact, false, &separating_axis));
		CHECK(contact.count == 0);
		CHECK(separating_axis.is_equal_approx(Vector2(1.0, 0.0)));
	}

	SUBCASE("Contact at a face") {
		circle_transform.set_origin(Vector2(2.5, 0.0));
		separating_axis = Vector2(1.0, 0.0);
		CHECK(sat_2d_calculate_penetration(&circle, circle_transform, Vector2(), &rectangle, rectangle_transform, Vector2(), record_contact, &contact, false, &separating_axis));
		CHECK(contact.count == 1);
		CHECK(contact.point_a.is_equal_approx(Vector2(1.5, 0.0)));
		CHECK(contact.point_b.is_equal_approx(Vector2(2.0, 0.0)));
		CHECK(separating_axis == Vector2());
	}

	SUBCASE("Contact at a corner") {
		circle_transform.set_origin(Vector2(2.6, 2.6));
		CHECK(sat_2d_calculate_penetration(&circle, circle_transform, Vector2(), &rectangle, rectangle_transform, Vector2(), record_contact, &contact));
		CHECK(contact.count == 1);
		CHECK(contact.point_b.is_equal_approx(Vector2(2.0, 2.0)));
		CHECK(contact.point_a.distance_to(Vector2(2.6, 2.6)) == doctest::Approx(1.0));
	}

	SUBCASE("Rotated rectangle") {
		rectangle_transform = Transform2D(real_t(Math::PI / 4.0), Vector2());
		circle_transform.set_origin(rectangle_transform.xform(Vector2(2.5, 0.0)));
		CHECK(sat_2d_calculate_penetration(&circle, circle_transform, Vector2(), &rectangle, rectangle_transform, Vector2(), record_contact, &contact));
		CHECK(contact.count == 1);
		CHECK(contact.point_b.is_equal_approx(rectangle_transform.xform(Vector2(2.0, 0.0))));
		CHECK(contact.point_a.is_equal_approx(rectangle_transform.xform(Vector2(1.5, 0.0))));
	}

	SUBCASE("Per-shape margins") {
		circle_transform.set_origin(Vector2(3.25, 0.0));
		CHECK(sat_2d_calculate_penetration(&circle, circle_transform, Vector2(), &rectangle, rectangle_transform, Vector2(), record_contact, &contact, false, nullptr, real_t(0.2), real_t(0.2)));
		CHECK(contact.count == 1);
		CHECK(contact.point_a.is_equal_approx(Vector2(2.05, 0.0)));
		CHECK(contact.point_b.is_equal_approx(Vector2(2.2, 0.0)));
	}

	SUBCASE("Swapped callback arguments") {
		circle_transform.set_origin(Vector2(2.5, 0.0));
		CHECK(sat_2d_calculate_penetration(&circle, circle_transform, Vector2(), &rectangle, rectangle_transform, Vector2(), record_contact, &contact, true));
		CHECK(contact.count == 1);
		CHECK(contact.point_a.is_equal_approx(Vector2(2.0, 0.0)));
		CHECK(contact.point_b.is_equal_approx(Vector2(1.5, 0.0)));
	}

	SUBCASE("Inside rectangle uses SAT") {
		circle_transform.set_origin(Vector2());
		CHECK(sat_2d_calculate_penetration(&circle, circle_transform, Vector2(), &rectangle, rectangle_transform, Vector2(), record_contact, &contact));
		CHECK(contact.count > 0);
	}

	SUBCASE("Scaled rectangle uses SAT") {
		rectangle_transform.columns[0] = Vector2(2.0, 0.0);
		circle_transform.set_origin(Vector2(4.5, 0.0));
		CHECK(sat_2d_calculate_penetration(&circle, circle_transform, Vector2(), &rectangle, rectangle_transform, Vector2(), record_contact, &contact));
		CHECK(contact.count > 0);
	}
}

} // namespace TestGodotPhysics2DCircleRectangle

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
