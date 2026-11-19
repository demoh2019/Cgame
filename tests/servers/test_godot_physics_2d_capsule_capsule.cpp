/**************************************************************************/
/*  test_godot_physics_2d_capsule_capsule.cpp                              */
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

TEST_FORCE_LINK(test_godot_physics_2d_capsule_capsule)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "modules/godot_physics_2d/godot_collision_solver_2d_sat.h"

namespace TestGodotPhysics2DCapsuleCapsule {

struct Contact {
	int count = 0;
	Vector2 point_a;
	Vector2 point_b;
};

static void record_contact(const Vector2 &p_a, const Vector2 &p_b, void *p_userdata) {
	Contact *contact = static_cast<Contact *>(p_userdata);
	contact->point_a = p_a;
	contact->point_b = p_b;
	contact->count++;
}

TEST_CASE("[GodotPhysics2D] Capsule-capsule analytic early rejection") {
	GodotCapsuleShape2D capsule_a;
	capsule_a.set_data(Vector2(1.0, 6.0));
	GodotCapsuleShape2D capsule_b;
	capsule_b.set_data(Vector2(1.0, 6.0));

	Transform2D transform_a;
	Transform2D transform_b;
	Vector2 separating_axis;
	Contact contact;

	SUBCASE("Separated enclosing circles") {
		transform_b.set_origin(Vector2(8.0, 0.0));
		CHECK_FALSE(sat_2d_calculate_penetration(&capsule_a, transform_a, Vector2(), &capsule_b, transform_b, Vector2(), record_contact, &contact, false, &separating_axis));
		CHECK(contact.count == 0);
		CHECK(separating_axis.is_equal_approx(Vector2(-1.0, 0.0)));
	}

	SUBCASE("Overlapping enclosing circles but separated capsules") {
		transform_b.set_origin(Vector2(3.0, 0.0));
		CHECK_FALSE(sat_2d_calculate_penetration(&capsule_a, transform_a, Vector2(), &capsule_b, transform_b, Vector2(), record_contact, &contact, false, &separating_axis));
		CHECK(contact.count == 0);
		CHECK(separating_axis.is_equal_approx(Vector2(-1.0, 0.0)));
	}

	SUBCASE("Overlapping parallel capsules retain SAT contacts") {
		transform_b.set_origin(Vector2(1.5, 0.0));
		CHECK(sat_2d_calculate_penetration(&capsule_a, transform_a, Vector2(), &capsule_b, transform_b, Vector2(), record_contact, &contact, false, &separating_axis));
		CHECK(contact.count > 0);
		CHECK(separating_axis == Vector2());
	}

	SUBCASE("Overlap-only query short-circuits without contact generation") {
		transform_b.set_origin(Vector2(1.5, 0.0));
		separating_axis = Vector2(1.0, 0.0);
		CHECK(sat_2d_calculate_penetration(&capsule_a, transform_a, Vector2(), &capsule_b, transform_b, Vector2(), nullptr, nullptr, false, &separating_axis));
		CHECK(separating_axis == Vector2());
	}

	SUBCASE("Longitudinal end caps overlap") {
		transform_b.set_origin(Vector2(0.0, 4.5));
		CHECK(sat_2d_calculate_penetration(&capsule_a, transform_a, Vector2(), &capsule_b, transform_b, Vector2(), record_contact, &contact));
		CHECK(contact.count > 0);
	}

	SUBCASE("Separated along long axes") {
		transform_b.set_origin(Vector2(0.0, 7.0));
		CHECK_FALSE(sat_2d_calculate_penetration(&capsule_a, transform_a, Vector2(), &capsule_b, transform_b, Vector2(), nullptr, nullptr));
	}

	SUBCASE("Rotated segments whose AABBs can overlap") {
		transform_b = Transform2D(real_t(Math_PI / 2.0), Vector2(4.0, 3.0));
		CHECK_FALSE(sat_2d_calculate_penetration(&capsule_a, transform_a, Vector2(), &capsule_b, transform_b, Vector2(), nullptr, nullptr));
	}

	SUBCASE("Overlap-only query honors both margins") {
		transform_b.set_origin(Vector2(2.3, 0.0));
		CHECK_FALSE(sat_2d_calculate_penetration(&capsule_a, transform_a, Vector2(), &capsule_b, transform_b, Vector2(), nullptr, nullptr));
		CHECK(sat_2d_calculate_penetration(&capsule_a, transform_a, Vector2(), &capsule_b, transform_b, Vector2(), nullptr, nullptr, false, nullptr, real_t(0.2), real_t(0.3)));
	}

	SUBCASE("Nonuniform scaling remains on SAT path") {
		transform_b.columns[0] = Vector2(2.0, 0.0);
		transform_b.set_origin(Vector2(2.0, 0.0));
		CHECK(sat_2d_calculate_penetration(&capsule_a, transform_a, Vector2(), &capsule_b, transform_b, Vector2(), record_contact, &contact));
		CHECK(contact.count > 0);
	}

	SUBCASE("Swept shapes remain on SAT path") {
		transform_b.set_origin(Vector2(8.0, 0.0));
		CHECK(sat_2d_calculate_penetration(&capsule_a, transform_a, Vector2(7.0, 0.0), &capsule_b, transform_b, Vector2(), record_contact, &contact));
		CHECK(contact.count > 0);
	}
}

} // namespace TestGodotPhysics2DCapsuleCapsule

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
