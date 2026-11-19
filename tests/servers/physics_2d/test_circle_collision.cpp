/**************************************************************************/
/*  test_circle_collision.cpp                                             */
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

TEST_FORCE_LINK(test_circle_collision)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED
#include "modules/godot_physics_2d/godot_collision_solver_2d.h"

namespace TestCircleCollision2D {

struct Contact {
	int count = 0;
	Vector2 point_a;
	Vector2 point_b;
};

static void capture_contact(const Vector2 &p_a, const Vector2 &p_b, void *p_userdata) {
	Contact *contact = static_cast<Contact *>(p_userdata);
	contact->count++;
	contact->point_a = p_a;
	contact->point_b = p_b;
}

TEST_CASE("[Physics2D] Circle-circle overlap and contact points") {
	GodotCircleShape2D circle_a;
	GodotCircleShape2D circle_b;
	circle_a.set_data(1.0);
	circle_b.set_data(1.0);

	Transform2D transform_a;
	Transform2D transform_b;
	transform_b.set_origin(Vector2(1.5, 0));

	Contact contact;
	Vector2 separation_axis;
	CHECK(GodotCollisionSolver2D::solve(&circle_a, transform_a, Vector2(), &circle_b, transform_b, Vector2(), capture_contact, &contact, &separation_axis));
	CHECK(contact.count == 1);
	CHECK(contact.point_a.is_equal_approx(Vector2(1, 0)));
	CHECK(contact.point_b.is_equal_approx(Vector2(0.5, 0)));
	CHECK(separation_axis == Vector2());
}

TEST_CASE("[Physics2D] Circle-circle separation and support axis") {
	GodotCircleShape2D circle_a;
	GodotCircleShape2D circle_b;
	circle_a.set_data(1.0);
	circle_b.set_data(1.0);

	Transform2D transform_a;
	Transform2D transform_b;
	transform_b.set_origin(Vector2(3, 0));

	Contact contact;
	Vector2 separation_axis;
	CHECK_FALSE(GodotCollisionSolver2D::solve(&circle_a, transform_a, Vector2(), &circle_b, transform_b, Vector2(), capture_contact, &contact, &separation_axis));
	CHECK(contact.count == 0);
	CHECK(separation_axis.is_equal_approx(Vector2(-1, 0)));
}

TEST_CASE("[Physics2D] Circle-circle overlap with margins") {
	GodotCircleShape2D circle_a;
	GodotCircleShape2D circle_b;
	circle_a.set_data(1.0);
	circle_b.set_data(1.0);

	Transform2D transform_a;
	Transform2D transform_b;
	transform_b.set_origin(Vector2(2.25, 0));

	Contact contact;
	CHECK(GodotCollisionSolver2D::solve(&circle_a, transform_a, Vector2(), &circle_b, transform_b, Vector2(), capture_contact, &contact, nullptr, 0.25, 0.25));
	CHECK(contact.count == 1);
	CHECK(contact.point_a.is_equal_approx(Vector2(1.25, 0)));
	CHECK(contact.point_b.is_equal_approx(Vector2(1.0, 0)));
}

TEST_CASE("[Physics2D] Circle-circle coincident center fallback") {
	GodotCircleShape2D circle_a;
	GodotCircleShape2D circle_b;
	circle_a.set_data(1.0);
	circle_b.set_data(1.0);

	Transform2D transform;
	CHECK(GodotCollisionSolver2D::solve(&circle_a, transform, Vector2(), &circle_b, transform, Vector2(), nullptr, nullptr));
}

} // namespace TestCircleCollision2D

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
