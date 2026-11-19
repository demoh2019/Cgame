/**************************************************************************/
/*  test_godot_physics_3d_sphere_narrowphase.cpp                           */
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

TEST_FORCE_LINK(test_godot_physics_3d_sphere_narrowphase)

#ifdef MODULE_GODOT_PHYSICS_3D_ENABLED

#include "modules/godot_physics_3d/godot_collision_solver_3d_sat.h"

namespace TestGodotPhysics3DSphereNarrowphase {

struct Contact {
	Vector3 point_a;
	Vector3 point_b;
	Vector3 normal;
	int count = 0;
};

static void record_contact(const Vector3 &p_a, int, const Vector3 &p_b, int, const Vector3 &p_normal, void *p_userdata) {
	Contact *contact = static_cast<Contact *>(p_userdata);
	contact->point_a = p_a;
	contact->point_b = p_b;
	contact->normal = p_normal;
	contact->count++;
}

TEST_CASE("[GodotPhysics3D] Sphere-sphere squared-distance narrowphase") {
	GodotSphereShape3D sphere_a;
	sphere_a.set_data(real_t(1.0));
	GodotSphereShape3D sphere_b;
	sphere_b.set_data(real_t(1.0));

	Transform3D transform_a;
	Transform3D transform_b;
	Contact contact;

	SUBCASE("Separated spheres") {
		transform_b.origin = Vector3(3.0, 0.0, 0.0);
		CHECK_FALSE(sat_calculate_penetration(&sphere_a, transform_a, &sphere_b, transform_b, record_contact, &contact));
		CHECK(contact.count == 0);
	}

	SUBCASE("Overlapping spheres") {
		transform_b.origin = Vector3(1.5, 0.0, 0.0);
		CHECK(sat_calculate_penetration(&sphere_a, transform_a, &sphere_b, transform_b, record_contact, &contact));
		CHECK(contact.count == 1);
		CHECK(contact.point_a.is_equal_approx(Vector3(1.0, 0.0, 0.0)));
		CHECK(contact.point_b.is_equal_approx(Vector3(0.5, 0.0, 0.0)));
		CHECK(contact.normal.is_equal_approx(Vector3(-1.0, 0.0, 0.0)));
	}

	SUBCASE("Exact tangency") {
		transform_b.origin = Vector3(2.0, 0.0, 0.0);
		CHECK(sat_calculate_penetration(&sphere_a, transform_a, &sphere_b, transform_b, record_contact, &contact));
		CHECK(contact.count == 1);
		CHECK(contact.point_a.is_equal_approx(contact.point_b));
	}

	SUBCASE("Overlap-only queries need no contact callback") {
		transform_b.origin = Vector3(1.5, 0.0, 0.0);
		CHECK(sat_calculate_penetration(&sphere_a, transform_a, &sphere_b, transform_b, nullptr, nullptr));
		transform_b.origin = Vector3(3.0, 0.0, 0.0);
		CHECK_FALSE(sat_calculate_penetration(&sphere_a, transform_a, &sphere_b, transform_b, nullptr, nullptr));
	}

	SUBCASE("Per-shape margins") {
		transform_b.origin = Vector3(2.2, 0.0, 0.0);
		CHECK(sat_calculate_penetration(&sphere_a, transform_a, &sphere_b, transform_b, record_contact, &contact, false, nullptr, real_t(0.2), real_t(0.1)));
		CHECK(contact.count == 1);
		CHECK(contact.point_a.is_equal_approx(Vector3(1.2, 0.0, 0.0)));
		CHECK(contact.point_b.is_equal_approx(Vector3(1.1, 0.0, 0.0)));
	}

	SUBCASE("Negative combined radius cannot collide") {
		transform_b.origin = Vector3(1.0, 0.0, 0.0);
		CHECK_FALSE(sat_calculate_penetration(&sphere_a, transform_a, &sphere_b, transform_b, record_contact, &contact, false, nullptr, real_t(-3.0), real_t(0.0)));
		CHECK(contact.count == 0);
	}

	SUBCASE("Scaled sphere") {
		transform_a.basis.scale(Vector3(2.0, 2.0, 2.0));
		transform_b.origin = Vector3(2.5, 0.0, 0.0);
		CHECK(sat_calculate_penetration(&sphere_a, transform_a, &sphere_b, transform_b, record_contact, &contact));
		CHECK(contact.count == 1);
		CHECK(contact.point_a.is_equal_approx(Vector3(2.0, 0.0, 0.0)));
		CHECK(contact.point_b.is_equal_approx(Vector3(1.5, 0.0, 0.0)));
	}

	SUBCASE("Swapped callback") {
		transform_b.origin = Vector3(1.5, 0.0, 0.0);
		CHECK(sat_calculate_penetration(&sphere_a, transform_a, &sphere_b, transform_b, record_contact, &contact, true));
		CHECK(contact.count == 1);
		CHECK(contact.point_a.is_equal_approx(Vector3(0.5, 0.0, 0.0)));
		CHECK(contact.point_b.is_equal_approx(Vector3(1.0, 0.0, 0.0)));
		CHECK(contact.normal.is_equal_approx(Vector3(1.0, 0.0, 0.0)));
	}
}

TEST_CASE("[GodotPhysics3D] Sphere-box squared-distance narrowphase") {
	GodotSphereShape3D sphere;
	sphere.set_data(real_t(1.0));
	GodotBoxShape3D box;
	box.set_data(Vector3(1.0, 1.0, 1.0));

	Transform3D sphere_transform;
	Transform3D box_transform;
	Contact contact;

	SUBCASE("Separated") {
		sphere_transform.origin = Vector3(2.5, 0.0, 0.0);
		CHECK_FALSE(sat_calculate_penetration(&sphere, sphere_transform, &box, box_transform, record_contact, &contact));
		CHECK(contact.count == 0);
	}

	SUBCASE("Overlapping face") {
		sphere_transform.origin = Vector3(1.5, 0.0, 0.0);
		CHECK(sat_calculate_penetration(&sphere, sphere_transform, &box, box_transform, record_contact, &contact));
		CHECK(contact.count == 1);
		CHECK(contact.point_a.is_equal_approx(Vector3(0.5, 0.0, 0.0)));
		CHECK(contact.point_b.is_equal_approx(Vector3(1.0, 0.0, 0.0)));
	}

	SUBCASE("Tangency and overlap-only query") {
		sphere_transform.origin = Vector3(2.0, 0.0, 0.0);
		CHECK(sat_calculate_penetration(&sphere, sphere_transform, &box, box_transform, nullptr, nullptr));
		sphere_transform.origin = Vector3(2.5, 0.0, 0.0);
		CHECK_FALSE(sat_calculate_penetration(&sphere, sphere_transform, &box, box_transform, nullptr, nullptr));
	}

	SUBCASE("Per-shape margins") {
		sphere_transform.origin = Vector3(2.25, 0.0, 0.0);
		CHECK(sat_calculate_penetration(&sphere, sphere_transform, &box, box_transform, record_contact, &contact, false, nullptr, real_t(0.2), real_t(0.1)));
		CHECK(contact.count == 1);
	}

	SUBCASE("Contained sphere uses nearest exit face") {
		sphere_transform.origin = Vector3(0.5, 0.0, 0.0);
		CHECK(sat_calculate_penetration(&sphere, sphere_transform, &box, box_transform, record_contact, &contact));
		CHECK(contact.count == 1);
		CHECK(contact.point_a.is_equal_approx(Vector3(-0.5, 0.0, 0.0)));
		CHECK(contact.point_b.is_equal_approx(Vector3(1.0, 0.0, 0.0)));
		CHECK(contact.normal.is_equal_approx(Vector3(1.0, 0.0, 0.0)));
	}

	SUBCASE("Coincident centers produce a stable nonzero contact normal") {
		CHECK(sat_calculate_penetration(&sphere, sphere_transform, &box, box_transform, record_contact, &contact));
		CHECK(contact.count == 1);
		CHECK(contact.point_a.is_equal_approx(Vector3(-1.0, 0.0, 0.0)));
		CHECK(contact.point_b.is_equal_approx(Vector3(1.0, 0.0, 0.0)));
		CHECK(contact.normal.is_equal_approx(Vector3(1.0, 0.0, 0.0)));
	}

	SUBCASE("Rotated box chooses rotated exit face") {
		box_transform.basis = Basis(Vector3(0.0, 0.0, 1.0), real_t(Math_PI / 2.0));
		sphere_transform.origin = box_transform.xform(Vector3(0.5, 0.0, 0.0));
		CHECK(sat_calculate_penetration(&sphere, sphere_transform, &box, box_transform, record_contact, &contact));
		CHECK(contact.count == 1);
		CHECK(contact.point_a.is_equal_approx(box_transform.xform(Vector3(-0.5, 0.0, 0.0))));
		CHECK(contact.point_b.is_equal_approx(box_transform.xform(Vector3(1.0, 0.0, 0.0))));
		CHECK(contact.normal.is_equal_approx(Vector3(0.0, 1.0, 0.0)));
	}

	SUBCASE("Nonuniform box scale uses world-space face distance") {
		box_transform.basis.scale(Vector3(4.0, 1.0, 2.0));
		sphere_transform.origin = Vector3(0.0, 0.25, 0.0);
		CHECK(sat_calculate_penetration(&sphere, sphere_transform, &box, box_transform, record_contact, &contact));
		CHECK(contact.count == 1);
		CHECK(contact.point_a.is_equal_approx(Vector3(0.0, -0.75, 0.0)));
		CHECK(contact.point_b.is_equal_approx(Vector3(0.0, 1.0, 0.0)));
		CHECK(contact.normal.is_equal_approx(Vector3(0.0, 1.0, 0.0)));
	}

	SUBCASE("Contained sphere with margins exits outwards") {
		sphere_transform.origin = Vector3(0.5, 0.0, 0.0);
		CHECK(sat_calculate_penetration(&sphere, sphere_transform, &box, box_transform, record_contact, &contact, false, nullptr, real_t(0.2), real_t(0.1)));
		CHECK(contact.count == 1);
		CHECK(contact.point_a.is_equal_approx(Vector3(-0.7, 0.0, 0.0)));
		CHECK(contact.point_b.is_equal_approx(Vector3(1.1, 0.0, 0.0)));
		CHECK(contact.normal.is_equal_approx(Vector3(1.0, 0.0, 0.0)));
	}
}

TEST_CASE("[GodotPhysics3D] Sphere-cylinder squared-distance narrowphase") {
	GodotSphereShape3D sphere;
	sphere.set_data(real_t(1.0));
	GodotCylinderShape3D cylinder;
	Dictionary cylinder_data;
	cylinder_data["radius"] = real_t(1.0);
	cylinder_data["height"] = real_t(4.0);
	cylinder.set_data(cylinder_data);

	Transform3D sphere_transform;
	Transform3D cylinder_transform;
	Contact contact;

	SUBCASE("Separated from side") {
		sphere_transform.origin = Vector3(2.5, 0.0, 0.0);
		CHECK_FALSE(sat_calculate_penetration(&sphere, sphere_transform, &cylinder, cylinder_transform, record_contact, &contact));
		CHECK(contact.count == 0);
	}

	SUBCASE("Overlapping side") {
		sphere_transform.origin = Vector3(1.5, 0.0, 0.0);
		CHECK(sat_calculate_penetration(&sphere, sphere_transform, &cylinder, cylinder_transform, record_contact, &contact));
		CHECK(contact.count == 1);
		CHECK(contact.point_a.is_equal_approx(Vector3(0.5, 0.0, 0.0)));
		CHECK(contact.point_b.is_equal_approx(Vector3(1.0, 0.0, 0.0)));
	}

	SUBCASE("Separated from end cap") {
		sphere_transform.origin = Vector3(0.0, 3.5, 0.0);
		CHECK_FALSE(sat_calculate_penetration(&sphere, sphere_transform, &cylinder, cylinder_transform, nullptr, nullptr));
	}

	SUBCASE("Overlap-only tangency and margins") {
		sphere_transform.origin = Vector3(2.0, 0.0, 0.0);
		CHECK(sat_calculate_penetration(&sphere, sphere_transform, &cylinder, cylinder_transform, nullptr, nullptr));
		sphere_transform.origin = Vector3(2.25, 0.0, 0.0);
		CHECK(sat_calculate_penetration(&sphere, sphere_transform, &cylinder, cylinder_transform, nullptr, nullptr, false, nullptr, real_t(0.2), real_t(0.1)));
	}
}

} // namespace TestGodotPhysics3DSphereNarrowphase

#endif // MODULE_GODOT_PHYSICS_3D_ENABLED
