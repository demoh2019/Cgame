/**************************************************************************/
/*  test_godot_physics_3d_contact_normal.cpp                              */
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

TEST_FORCE_LINK(test_godot_physics_3d_contact_normal)

#ifdef MODULE_GODOT_PHYSICS_3D_ENABLED

#include "modules/godot_physics_3d/godot_contact_normal_3d.h"

namespace TestGodotPhysics3DContactNormal {

TEST_CASE("[GodotPhysics3D] Degenerate contact normal fallback") {
	SUBCASE("Penetrating contacts retain point-derived normal") {
		const Vector3 result = godot_physics_3d_contact_normal(Vector3(0.0, -2.0, 0.0), Vector3(), Vector3(1.0, 0.0, 0.0));
		CHECK(result.is_equal_approx(Vector3(0.0, -1.0, 0.0)));
	}

	SUBCASE("Exact tangency uses supplied narrowphase normal") {
		const Vector3 result = godot_physics_3d_contact_normal(Vector3(2.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0));
		CHECK(result.is_equal_approx(Vector3(1.0, 0.0, 0.0)));
	}

	SUBCASE("Near-coincident points use stable normal") {
		const real_t tiny = real_t(CMP_EPSILON) * real_t(0.01);
		const Vector3 result = godot_physics_3d_contact_normal(Vector3(tiny, 0.0, 0.0), Vector3(), Vector3(0.0, 0.0, 2.0));
		CHECK(result.is_equal_approx(Vector3(0.0, 0.0, -1.0)));
	}

	SUBCASE("Degenerate narrowphase normal has a deterministic fallback") {
		const Vector3 result = godot_physics_3d_contact_normal(Vector3(), Vector3(), Vector3());
		CHECK(result.is_equal_approx(Vector3(0.0, 1.0, 0.0)));
	}

	SUBCASE("Reversed point ordering flips nondegenerate contact") {
		const Vector3 result = godot_physics_3d_contact_normal(Vector3(1.0, 0.0, 0.0), Vector3(3.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0));
		CHECK(result.is_equal_approx(Vector3(-1.0, 0.0, 0.0)));
	}
}


TEST_CASE("[GodotPhysics3D] Soft body contacts use robust unit normals") {
	SUBCASE("Unit narrowphase normal preserves direction") {
		const Vector3 result = godot_physics_3d_soft_contact_normal(Vector3(0.0, -2.0, 0.0), Vector3(), Vector3(0.0, -1.0, 0.0));
		CHECK(result.is_equal_approx(Vector3(0.0, -1.0, 0.0)));
	}
	SUBCASE("Opposite narrowphase normal is reoriented") {
		const Vector3 result = godot_physics_3d_soft_contact_normal(Vector3(0.0, -2.0, 0.0), Vector3(), Vector3(0.0, 2.0, 0.0));
		CHECK(result.is_equal_approx(Vector3(0.0, -1.0, 0.0)));
	}
	SUBCASE("Non-unit normal is normalized") {
		const Vector3 result = godot_physics_3d_soft_contact_normal(Vector3(2.0, 0.0, 0.0), Vector3(), Vector3(5.0, 0.0, 0.0));
		CHECK(result.is_equal_approx(Vector3(1.0, 0.0, 0.0)));
	}
	SUBCASE("Zero narrowphase normal falls back to separation axis") {
		const Vector3 result = godot_physics_3d_soft_contact_normal(Vector3(0.0, 3.0, 0.0), Vector3(), Vector3());
		CHECK(result.is_equal_approx(Vector3(0.0, 1.0, 0.0)));
	}
	SUBCASE("Coincident points with zero normal give deterministic direction") {
		const Vector3 result = godot_physics_3d_soft_contact_normal(Vector3(), Vector3(), Vector3());
		CHECK(result.is_equal_approx(Vector3(0.0, 1.0, 0.0)));
	}
	SUBCASE("Coincident points preserve valid narrowphase normal") {
		const Vector3 result = godot_physics_3d_soft_contact_normal(Vector3(), Vector3(), Vector3(0.0, 0.0, 1.0));
		CHECK(result.is_equal_approx(Vector3(0.0, 0.0, 1.0)));
	}
}

} // namespace TestGodotPhysics3DContactNormal

#endif // MODULE_GODOT_PHYSICS_3D_ENABLED
