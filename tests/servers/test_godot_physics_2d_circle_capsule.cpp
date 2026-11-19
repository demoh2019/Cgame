/**************************************************************************/
/*  test_godot_physics_2d_circle_capsule.cpp                               */
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
/* NONINFRINGEMENT.                                                        */
/**************************************************************************/

#include "modules/modules_enabled.gen.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_2d_circle_capsule)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "modules/godot_physics_2d/godot_collision_solver_2d_sat.h"

namespace TestGodotPhysics2DCircleCapsule {

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

TEST_CASE("[GodotPhysics2D] Circle-capsule analytic contact manifold") {
	GodotCircleShape2D circle;
	circle.set_data(real_t(1.0));
	GodotCapsuleShape2D capsule;
	// Vector2 capsule data is (radius, total height). Half segment is 2.
	capsule.set_data(Vector2(1.0, 6.0));

	Transform2D circle_transform;
	Transform2D capsule_transform;
	Vector2 separating_axis;
	Contact contact;

	SUBCASE("Separated from capsule side") {
		circle_transform.set_origin(Vector2(3.5, 0.0));
		CHECK_FALSE(sat_2d_calculate_penetration(&circle, circle_transform, Vector2(), &capsule, capsule_transform, Vector2(), record_contact, &contact, false, &separating_axis));
		CHECK(contact.count == 0);
		CHECK(separating_axis.is_equal_approx(Vector2(1.0, 0.0)));
	}

	SUBCASE("Capsule side contact") {
		circle_transform.set_origin(Vector2(1.5, 0.0));
		separating_axis = Vector2(1.0, 0.0);
		CHECK(sat_2d_calculate_penetration(&circle, circle_transform, Vector2(), &capsule, capsule_transform, Vector2(), record_contact, &contact, false, &separating_axis));
		CHECK(contact.count == 1);
		CHECK(contact.point_a.is_equal_approx(Vector2(0.5, 0.0)));
		CHECK(contact.point_b.is_equal_approx(Vector2(1.0, 0.0)));
		CHECK(separating_axis == Vector2());
	}

	SUBCASE("Upper end-cap contact") {
		circle_transform.set_origin(Vector2(0.0, 3.5));
		CHECK(sat_2d_calculate_penetration(&circle, circle_transform, Vector2(), &capsule, capsule_transform, Vector2(), record_contact, &contact));
		CHECK(contact.count == 1);
		CHECK(contact.point_a.is_equal_approx(Vector2(0.0, 2.5)));
		CHECK(contact.point_b.is_equal_approx(Vector2(0.0, 3.0)));
	}

	SUBCASE("Exact tangency") {
		circle_transform.set_origin(Vector2(2.0, 0.0));
		CHECK(sat_2d_calculate_penetration(&circle, circle_transform, Vector2(), &capsule, capsule_transform, Vector2(), record_contact, &contact));
		CHECK(contact.count == 1);
		CHECK(contact.point_a.is_equal_approx(contact.point_b));
	}

	SUBCASE("Rotated capsule") {
		capsule_transform = Transform2D(real_t(Math_PI / 2.0), Vector2());
		circle_transform.set_origin(capsule_transform.xform(Vector2(1.5, 0.0)));
		CHECK(sat_2d_calculate_penetration(&circle, circle_transform, Vector2(), &capsule, capsule_transform, Vector2(), record_contact, &contact));
		CHECK(contact.count == 1);
		CHECK(contact.point_a.is_equal_approx(capsule_transform.xform(Vector2(0.5, 0.0))));
		CHECK(contact.point_b.is_equal_approx(capsule_transform.xform(Vector2(1.0, 0.0))));
	}

	SUBCASE("Both shape margins") {
		circle_transform.set_origin(Vector2(2.25, 0.0));
		CHECK(sat_2d_calculate_penetration(&circle, circle_transform, Vector2(), &capsule, capsule_transform, Vector2(), record_contact, &contact, false, nullptr, real_t(0.2), real_t(0.1)));
		CHECK(contact.count == 1);
		CHECK(contact.point_a.is_equal_approx(Vector2(1.05, 0.0)));
		CHECK(contact.point_b.is_equal_approx(Vector2(1.1, 0.0)));
	}

	SUBCASE("Swapped callback points") {
		circle_transform.set_origin(Vector2(1.5, 0.0));
		CHECK(sat_2d_calculate_penetration(&circle, circle_transform, Vector2(), &capsule, capsule_transform, Vector2(), record_contact, &contact, true));
		CHECK(contact.count == 1);
		CHECK(contact.point_a.is_equal_approx(Vector2(1.0, 0.0)));
		CHECK(contact.point_b.is_equal_approx(Vector2(0.5, 0.0)));
	}

	SUBCASE("Reversed input order") {
		circle_transform.set_origin(Vector2(1.5, 0.0));
		CHECK(sat_2d_calculate_penetration(&capsule, capsule_transform, Vector2(), &circle, circle_transform, Vector2(), record_contact, &contact));
		CHECK(contact.count == 1);
		CHECK(contact.point_a.is_equal_approx(Vector2(1.0, 0.0)));
		CHECK(contact.point_b.is_equal_approx(Vector2(0.5, 0.0)));
	}

	SUBCASE("Centerline coincidence uses SAT") {
		circle_transform.set_origin(Vector2());
		CHECK(sat_2d_calculate_penetration(&circle, circle_transform, Vector2(), &capsule, capsule_transform, Vector2(), record_contact, &contact));
		CHECK(contact.count > 0);
	}

	SUBCASE("Scaled capsule uses SAT") {
		capsule_transform.columns[0] = Vector2(2.0, 0.0);
		circle_transform.set_origin(Vector2(2.5, 0.0));
		CHECK(sat_2d_calculate_penetration(&circle, circle_transform, Vector2(), &capsule, capsule_transform, Vector2(), record_contact, &contact));
		CHECK(contact.count > 0);
	}

	SUBCASE("Swept circle uses SAT") {
		circle_transform.set_origin(Vector2(4.0, 0.0));
		CHECK(sat_2d_calculate_penetration(&circle, circle_transform, Vector2(-3.0, 0.0), &capsule, capsule_transform, Vector2(), record_contact, &contact));
		CHECK(contact.count > 0);
	}
}

} // namespace TestGodotPhysics2DCircleCapsule

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
