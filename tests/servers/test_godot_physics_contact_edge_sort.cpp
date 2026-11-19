/**************************************************************************/
/*  test_godot_physics_contact_edge_sort.cpp                               */
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

TEST_FORCE_LINK(test_godot_physics_contact_edge_sort)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED
#include "modules/godot_physics_2d/godot_collision_solver_2d_sat.h"

namespace TestGodotPhysics2DEdgeSort {

struct Contacts {
	int count = 0;
	bool finite = true;

	static void record(const Vector2 &p_a, const Vector2 &p_b, void *p_userdata) {
		Contacts *self = static_cast<Contacts *>(p_userdata);
		self->count++;
		self->finite &= p_a.is_finite() && p_b.is_finite();
	}
};

TEST_CASE("[GodotPhysics2D] Rectangle edge manifolds retain finite contacts") {
	GodotRectangleShape2D box;
	box.set_data(Vector2(1, 1));
	const Transform2D identity;
	Transform2D moved;

	for (int i = -8; i <= 8; i++) {
		moved.set_origin(Vector2(i * real_t(0.13), real_t(1.5)));
		Contacts contacts;
		CHECK(sat_2d_calculate_penetration(&box, identity, Vector2(), &box, moved, Vector2(),
				Contacts::record, &contacts));
		CHECK(contacts.count > 0);
		CHECK(contacts.count <= 2);
		CHECK(contacts.finite);
	}

	moved.set_origin(Vector2(0, 3));
	Contacts separated;
	CHECK_FALSE(sat_2d_calculate_penetration(&box, identity, Vector2(), &box, moved, Vector2(),
				Contacts::record, &separated));
	CHECK(separated.count == 0);
}

} // namespace TestGodotPhysics2DEdgeSort
#endif // MODULE_GODOT_PHYSICS_2D_ENABLED

#ifdef MODULE_GODOT_PHYSICS_3D_ENABLED
#include "modules/godot_physics_3d/godot_collision_solver_3d_sat.h"

namespace TestGodotPhysics3DEdgeSort {

struct Contacts {
	int count = 0;
	bool finite = true;

	static void record(const Vector3 &p_a, int, const Vector3 &p_b, int, const Vector3 &p_normal, void *p_userdata) {
		Contacts *self = static_cast<Contacts *>(p_userdata);
		self->count++;
		self->finite &= p_a.is_finite() && p_b.is_finite() && p_normal.is_finite();
	}
};

TEST_CASE("[GodotPhysics3D] Box edge and face manifolds remain finite") {
	GodotBoxShape3D box;
	box.set_data(Vector3(1, 1, 1));
	const Transform3D identity;

	for (int angle_step = 0; angle_step < 5; angle_step++) {
		const Basis rotated(Vector3(0, 0, 1), angle_step * real_t(0.15));
		for (int offset_step = -5; offset_step <= 5; offset_step++) {
			const Transform3D moved(rotated, Vector3(offset_step * real_t(0.05), real_t(1.5), 0));
			Contacts contacts;
			CHECK(sat_calculate_penetration(&box, identity, &box, moved, Contacts::record, &contacts));
			CHECK(contacts.count > 0);
			CHECK(contacts.finite);
		}
	}

	const Transform3D separated(Basis(), Vector3(0, 4, 0));
	Contacts contacts;
	CHECK_FALSE(sat_calculate_penetration(&box, identity, &box, separated, Contacts::record, &contacts));
	CHECK(contacts.count == 0);
}

} // namespace TestGodotPhysics3DEdgeSort
#endif // MODULE_GODOT_PHYSICS_3D_ENABLED
