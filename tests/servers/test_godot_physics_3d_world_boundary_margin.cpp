/**************************************************************************/
/*  test_godot_physics_3d_world_boundary_margin.cpp                           */
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

TEST_FORCE_LINK(test_godot_physics_3d_world_boundary_margin)

#ifdef MODULE_GODOT_PHYSICS_3D_ENABLED

#include "modules/godot_physics_3d/godot_collision_solver_3d.h"

namespace TestGodotPhysics3DWorldBoundaryMargin {

struct Contact {
	Vector3 plane_point;
	Vector3 shape_point;
	int count = 0;
};

static void record_contact(const Vector3 &p_a, int, const Vector3 &p_b, int, const Vector3 &, void *p_userdata) {
	Contact *contact = static_cast<Contact *>(p_userdata);
	contact->plane_point = p_a;
	contact->shape_point = p_b;
	contact->count++;
}

TEST_CASE("[GodotPhysics3D] World boundary margin stays independent of vertex origin") {
	GodotWorldBoundaryShape3D boundary;
	boundary.set_data(Plane(Vector3(1.0, 0.0, 0.0), real_t(0.0)));
	GodotConvexPolygonShape3D convex;
	Vector<Vector3> vertices;
	for (int i = 0; i < 8; i++) {
		vertices.push_back(Vector3(
				(i & 1) ? real_t(4.0) : real_t(2.0),
				(i & 2) ? real_t(1.0) : real_t(-1.0),
				(i & 4) ? real_t(1.0) : real_t(-1.0)));
	}
	convex.set_data(vertices);
	const Transform3D transform(Basis(), Vector3(real_t(-1.5), 0.0, 0.0));

	CHECK_FALSE(GodotCollisionSolver3D::solve_static(&boundary, Transform3D(), &convex, transform, nullptr, nullptr));
	Contact contact;
	CHECK(GodotCollisionSolver3D::solve_static(&boundary, Transform3D(), &convex, transform,
			record_contact, &contact, nullptr, real_t(0.0), real_t(0.6)));
	CHECK(contact.count > 0);
	if (contact.count > 0) {
		CHECK(Math::abs(contact.plane_point.x) < real_t(0.001));
		CHECK(Math::abs(contact.shape_point.x + real_t(0.1)) < real_t(0.001));
	}
	CHECK_FALSE(GodotCollisionSolver3D::solve_static(&boundary, Transform3D(), &convex, transform,
			nullptr, nullptr, nullptr, real_t(0.0), real_t(0.4)));

	Contact swapped;
	CHECK(GodotCollisionSolver3D::solve_static(&convex, transform, &boundary, Transform3D(),
			record_contact, &swapped, nullptr, real_t(0.6), real_t(0.0)));
	CHECK(swapped.count > 0);
}

TEST_CASE("[GodotPhysics3D] Boundary margin measures world distance under scale") {
	GodotWorldBoundaryShape3D boundary;
	boundary.set_data(Plane(Vector3(1.0, 0.0, 0.0), real_t(0.0)));
	GodotBoxShape3D box;
	box.set_data(Vector3(real_t(1.0), real_t(1.0), real_t(1.0)));
	const Transform3D scaled(Basis::from_scale(Vector3(2.0, 1.0, 1.0)), Vector3(2.5, 0.0, 0.0));

	Contact contact;
	CHECK(GodotCollisionSolver3D::solve_static(&boundary, Transform3D(), &box, scaled,
			record_contact, &contact, nullptr, real_t(0.0), real_t(0.6)));
	CHECK(contact.count > 0);
	if (contact.count > 0) {
		CHECK(Math::abs(contact.shape_point.x + real_t(0.1)) < real_t(0.001));
	}
	CHECK_FALSE(GodotCollisionSolver3D::solve_static(&boundary, Transform3D(), &box, scaled,
			nullptr, nullptr, nullptr, real_t(0.0), real_t(0.4)));
}

} // namespace TestGodotPhysics3DWorldBoundaryMargin

#endif // MODULE_GODOT_PHYSICS_3D_ENABLED
