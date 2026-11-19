/**************************************************************************/
/*  test_godot_physics_3d_contact_warmstart.cpp                            */
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

TEST_FORCE_LINK(test_godot_physics_3d_contact_warmstart)

#ifdef MODULE_GODOT_PHYSICS_3D_ENABLED

#include "modules/godot_physics_3d/godot_contact_warmstart_3d.h"

namespace TestGodotPhysics3DContactWarmstart {

TEST_CASE("[GodotPhysics3D] Contact impulse recycling rejects folded or reversed normals") {
	const Vector3 up(0, 1, 0);

	SUBCASE("Identical normals preserve impulses") {
		CHECK(godot_physics_3d_can_reuse_contact_impulses(up, up));
	}

	SUBCASE("Small rotation preserves impulses") {
		const Vector3 rotated = Vector3(real_t(0.1), 1, 0).normalized();
		CHECK(godot_physics_3d_can_reuse_contact_impulses(up, rotated));
	}

	SUBCASE("Large rotation discards old impulses") {
		const Vector3 tilted = Vector3(1, 1, 0).normalized();
		CHECK_FALSE(godot_physics_3d_can_reuse_contact_impulses(up, tilted));
	}

	SUBCASE("Folded soft-body surface discards impulses") {
		CHECK_FALSE(godot_physics_3d_can_reuse_contact_impulses(up, -up));
		CHECK_FALSE(godot_physics_3d_can_reuse_contact_impulses(up, Vector3(1, 0, 0)));
	}

	SUBCASE("Degenerate normals cannot be warm started") {
		CHECK_FALSE(godot_physics_3d_can_reuse_contact_impulses(Vector3(), up));
		CHECK_FALSE(godot_physics_3d_can_reuse_contact_impulses(up, Vector3()));
	}

	SUBCASE("Magnitude of the normal does not affect angular compatibility") {
		const Vector3 rotated = Vector3(real_t(0.1), 1, 0);
		CHECK(godot_physics_3d_can_reuse_contact_impulses(up * 7, rotated * 3));
		CHECK_FALSE(godot_physics_3d_can_reuse_contact_impulses(up * 7, Vector3(1, 1, 0) * 3));
	}
}

TEST_CASE("[GodotPhysics3D] Contact friction cache stays in new tangent plane") {
	SUBCASE("A scaled normal removes only the perpendicular component") {
		const Vector3 impulse(1, 2, 3);
		const Vector3 normal(0, 4, 0);
		const Vector3 projected = godot_physics_3d_reproject_contact_friction(impulse, normal);
		CHECK(projected.is_equal_approx(Vector3(1, 0, 3)));
		CHECK(Math::is_zero_approx(projected.dot(normal)));
	}

	SUBCASE("Tilted normal does not remove in-plane friction") {
		const Vector3 impulse(2, 0, 1);
		const Vector3 normal(1, 1, 0);
		const Vector3 projected = godot_physics_3d_reproject_contact_friction(impulse, normal);
		CHECK(projected.is_equal_approx(Vector3(1, -1, 1)));
		CHECK(Math::is_zero_approx(projected.dot(normal)));
	}

	SUBCASE("Already tangential impulse is unchanged") {
		const Vector3 impulse(2, 0, 1);
		const Vector3 normal(0, 1, 0);
		CHECK(godot_physics_3d_reproject_contact_friction(impulse, normal).is_equal_approx(impulse));
	}

	SUBCASE("Degenerate normal cannot project a tangential force") {
		CHECK(godot_physics_3d_reproject_contact_friction(Vector3(1, 2, 3), Vector3()) == Vector3());
	}

	SUBCASE("Idempotence keeps repeated warm starts from drifting") {
		const Vector3 normal = Vector3(1, 2, 3).normalized();
		Vector3 projected = godot_physics_3d_reproject_contact_friction(Vector3(5, -2, 1), normal);
		for (int i = 0; i < 20; ++i) {
			projected = godot_physics_3d_reproject_contact_friction(projected, normal);
		}
		CHECK(Math::abs(projected.dot(normal)) <= real_t(0.00001));
	}
}

} // namespace TestGodotPhysics3DContactWarmstart

#endif // MODULE_GODOT_PHYSICS_3D_ENABLED
