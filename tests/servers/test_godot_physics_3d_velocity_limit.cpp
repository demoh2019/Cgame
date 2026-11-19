/**************************************************************************/
/*  test_godot_physics_3d_velocity_limit.cpp                             */
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

TEST_FORCE_LINK(test_godot_physics_3d_velocity_limit)

#ifdef MODULE_GODOT_PHYSICS_3D_ENABLED

#include "modules/godot_physics_3d/godot_velocity_limit_3d.h"

namespace TestGodotPhysics3DVelocityLimit {

TEST_CASE("[GodotPhysics3D] Opt-in linear velocity limit") {
	SUBCASE("Default zero or negative limits preserve legacy behavior") {
		const Vector3 v(2.0, 3.0, 6.0);
		CHECK(godot_physics_3d_limit_linear_velocity(v, 0.0) == v);
		CHECK(godot_physics_3d_limit_linear_velocity(v, -1.0) == v);
	}
	SUBCASE("Speed below and exactly at cap is unchanged") {
		CHECK(godot_physics_3d_limit_linear_velocity(Vector3(1.0, 2.0, 2.0), 3.0) == Vector3(1.0, 2.0, 2.0));
		CHECK(godot_physics_3d_limit_linear_velocity(Vector3(0.0, 0.0, 0.0), 100.0) == Vector3());
	}
	SUBCASE("Magnitude is capped without changing the direction") {
		const Vector3 result = godot_physics_3d_limit_linear_velocity(Vector3(2.0, -3.0, 6.0), 3.5);
		CHECK(result.is_equal_approx(Vector3(1.0, -1.5, 3.0)));
		CHECK(Math::is_equal_approx(result.length(), real_t(3.5)));
	}
	SUBCASE("Extremely large finite components remain finite") {
		const Vector3 result = godot_physics_3d_limit_linear_velocity(Vector3(real_t(1e25), real_t(-1e25), real_t(1e25)), 100.0);
		CHECK(result.is_finite());
		CHECK(Math::is_equal_approx(result.length(), real_t(100.0)));
	}
}

} // namespace TestGodotPhysics3DVelocityLimit

#endif // MODULE_GODOT_PHYSICS_3D_ENABLED
