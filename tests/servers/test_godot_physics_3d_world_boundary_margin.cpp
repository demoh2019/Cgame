/**************************************************************************/
/*  test_godot_physics_3d_world_boundary_margin.cpp                       */
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

TEST_FORCE_LINK(test_godot_physics_3d_world_boundary_margin)

#ifdef MODULE_GODOT_PHYSICS_3D_ENABLED

#include "modules/godot_physics_3d/godot_collision_solver_3d.h"

namespace TestGodotPhysics3DWorldBoundaryMargin {

struct ContactResult {
	int count = 0;
	Vector3 normal;
};

static void capture_contact(const Vector3 &p_point_a, int p_index_a, const Vector3 &p_point_b, int p_index_b, const Vector3 &p_normal, void *p_userdata) {
	ContactResult *result = static_cast<ContactResult *>(p_userdata);
	result->count++;
	result->normal = p_normal;
}

TEST_CASE("[GodotPhysics3D] World boundary margin is measured along plane normal") {
	GodotWorldBoundaryShape3D boundary;
	boundary.set_data(Plane(Vector3(0.0, 1.0, 0.0), 0.0));
	GodotBoxShape3D box;
	box.set_data(Vector3(10.0, 0.5, 0.5));

	const Transform3D plane_transform;
	const Transform3D box_transform(Basis(), Vector3(0.0, 0.6, 0.0));

	SUBCASE("Wide box enters contact only when the physical margin reaches it") {
		CHECK_FALSE(GodotCollisionSolver3D::solve_static(&boundary, plane_transform, &box, box_transform, nullptr, nullptr, nullptr, 0.0, 0.0));
		CHECK_FALSE(GodotCollisionSolver3D::solve_static(&boundary, plane_transform, &box, box_transform, nullptr, nullptr, nullptr, 0.0, 0.05));
		CHECK(GodotCollisionSolver3D::solve_static(&boundary, plane_transform, &box, box_transform, nullptr, nullptr, nullptr, 0.0, 0.2));
	}

	SUBCASE("Both collision orders have correctly oriented unit normals") {
		ContactResult original;
		CHECK(GodotCollisionSolver3D::solve_static(&boundary, plane_transform, &box, box_transform, capture_contact, &original, nullptr, 0.0, 0.2));
		CHECK(original.count > 0);
		CHECK(original.normal.is_equal_approx(Vector3(0.0, -1.0, 0.0)));

		ContactResult reversed;
		CHECK(GodotCollisionSolver3D::solve_static(&box, box_transform, &boundary, plane_transform, capture_contact, &reversed, nullptr, 0.2, 0.0));
		CHECK(reversed.count > 0);
		CHECK(reversed.normal.is_equal_approx(Vector3(0.0, 1.0, 0.0)));
	}
}

} // namespace TestGodotPhysics3DWorldBoundaryMargin

#endif // MODULE_GODOT_PHYSICS_3D_ENABLED
