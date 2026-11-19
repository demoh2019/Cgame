/**************************************************************************/
/*  test_godot_physics_2d_world_boundary_affine.cpp                       */
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

TEST_FORCE_LINK(test_godot_physics_2d_world_boundary_affine)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "modules/godot_physics_2d/godot_collision_solver_2d.h"

namespace TestGodotPhysics2DWorldBoundaryAffine {

struct Contact {
	int count = 0;
	Vector2 boundary_point;
	Vector2 shape_point;
};

static void record_contact(const Vector2 &p_a, const Vector2 &p_b, void *p_userdata) {
	Contact *c = static_cast<Contact *>(p_userdata);
	c->count++;
	c->boundary_point = p_a;
	c->shape_point = p_b;
}

static void configure_boundary(GodotWorldBoundaryShape2D &r_boundary, const Vector2 &p_normal, real_t p_distance) {
	Array data;
	data.push_back(p_normal);
	data.push_back(p_distance);
	r_boundary.set_data(data);
}

TEST_CASE("[GodotPhysics2D] World boundary planes transform with inverse transpose") {
	GodotWorldBoundaryShape2D boundary;
	configure_boundary(boundary, Vector2(1.0, 0.0), real_t(0.0));
	GodotCircleShape2D circle;
	circle.set_data(real_t(0.25));

	// A local x=0 half-plane becomes world x=2*y under this shear.
	const Transform2D shear(Vector2(1.0, 0.0), Vector2(2.0, 1.0), Vector2());
	const Transform2D near_circle(real_t(0.0), Vector2(1.65, 0.9));
	const Transform2D far_circle(real_t(0.0), Vector2(2.8, 0.9));
	Contact contact;
	CHECK(GodotCollisionSolver2D::solve(&boundary, shear, Vector2(),
			&circle, near_circle, Vector2(), record_contact, &contact));
	CHECK(contact.count > 0);
	if (contact.count > 0) {
		CHECK(Math::abs(contact.boundary_point.x - real_t(2.0) * contact.boundary_point.y) < real_t(0.001));
	}
	CHECK_FALSE(GodotCollisionSolver2D::solve(&boundary, shear, Vector2(),
			&circle, far_circle, Vector2(), nullptr, nullptr));

	// n=(2,0), d=2 defines local x=1. Scaling by two and translating
	// by three must put the boundary at world x=5 (not x=11).
	configure_boundary(boundary, Vector2(2.0, 0.0), real_t(2.0));
	const Transform2D scaled(Vector2(2.0, 0.0), Vector2(0.0, 0.5), Vector2(3.0, 0.0));
	const Transform2D touching(real_t(0.0), Vector2(5.1, 0.0));
	const Transform2D separated(real_t(0.0), Vector2(5.6, 0.0));
	contact = Contact();
	CHECK(GodotCollisionSolver2D::solve(&boundary, scaled, Vector2(),
			&circle, touching, Vector2(), record_contact, &contact));
	CHECK(contact.count > 0);
	if (contact.count > 0) {
		CHECK(Math::abs(contact.boundary_point.x - real_t(5.0)) < real_t(0.001));
	}
	CHECK_FALSE(GodotCollisionSolver2D::solve(&boundary, scaled, Vector2(),
			&circle, separated, Vector2(), nullptr, nullptr));
}

TEST_CASE("[GodotPhysics2D] Boundary support direction uses shape basis transpose") {
	GodotWorldBoundaryShape2D boundary;
	configure_boundary(boundary, Vector2(1.0, 0.0), real_t(0.0));
	GodotCircleShape2D circle;
	circle.set_data(real_t(1.0));

	// A sheared circle has support extent sqrt(1+3*3) along world X.
	// The old inverse-basis query only saw an extent of one.
	const Transform2D sheared_circle(Vector2(1.0, 0.0), Vector2(3.0, 1.0), Vector2(2.0, 0.0));
	Contact contact;
	CHECK(GodotCollisionSolver2D::solve(&boundary, Transform2D(), Vector2(),
			&circle, sheared_circle, Vector2(), record_contact, &contact));
	CHECK(contact.count > 0);
	if (contact.count > 0) {
		CHECK(contact.shape_point.x < real_t(-1.0));
		CHECK(Math::abs(contact.boundary_point.x) < real_t(0.001));
	}

	// The result callback must swap point order when the world boundary is B.
	Contact swapped;
	CHECK(GodotCollisionSolver2D::solve(&circle, sheared_circle, Vector2(),
			&boundary, Transform2D(), Vector2(), record_contact, &swapped));
	CHECK(swapped.count > 0);
	if (swapped.count > 0) {
		CHECK(swapped.boundary_point.x < real_t(-1.0));
		CHECK(Math::abs(swapped.shape_point.x) < real_t(0.001));
	}
}

TEST_CASE("[GodotPhysics2D] Boundary collision margin is world-space and origin independent") {
	GodotWorldBoundaryShape2D boundary;
	configure_boundary(boundary, Vector2(1.0, 0.0), real_t(0.0));
	GodotConvexPolygonShape2D polygon;
	PackedVector2Array vertices;
	vertices.push_back(Vector2(2.0, -1.0));
	vertices.push_back(Vector2(4.0, -1.0));
	vertices.push_back(Vector2(4.0, 1.0));
	vertices.push_back(Vector2(2.0, 1.0));
	polygon.set_data(vertices);
	const Transform2D offset_polygon(real_t(0.0), Vector2(-1.5, 0.0));

	CHECK_FALSE(GodotCollisionSolver2D::solve(&boundary, Transform2D(), Vector2(),
			&polygon, offset_polygon, Vector2(), nullptr, nullptr));
	Contact contact;
	CHECK(GodotCollisionSolver2D::solve(&boundary, Transform2D(), Vector2(),
			&polygon, offset_polygon, Vector2(), record_contact, &contact, nullptr, real_t(0.0), real_t(0.6)));
	CHECK(contact.count > 0);
	if (contact.count > 0) {
		CHECK(Math::abs(contact.boundary_point.x) < real_t(0.001));
		CHECK(Math::abs(contact.shape_point.x + real_t(0.1)) < real_t(0.001));
	}
	CHECK_FALSE(GodotCollisionSolver2D::solve(&boundary, Transform2D(), Vector2(),
			&polygon, offset_polygon, Vector2(), nullptr, nullptr, nullptr, real_t(0.0), real_t(0.4)));
}

} // namespace TestGodotPhysics2DWorldBoundaryAffine

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
