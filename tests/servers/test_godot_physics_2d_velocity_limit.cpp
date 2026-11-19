/**************************************************************************/
/*  test_godot_physics_2d_velocity_limit.cpp                               */
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

TEST_FORCE_LINK(test_godot_physics_2d_velocity_limit)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "modules/godot_physics_2d/godot_velocity_limit_2d.h"

namespace TestGodotPhysics2DVelocityLimit {

TEST_CASE("[GodotPhysics2D] Opt-in linear velocity limit") {
	const Vector2 diagonal(300.0, 400.0);

	SUBCASE("Zero and negative limits preserve legacy motion") {
		CHECK(godot_physics_2d_limit_linear_velocity(diagonal, 0.0) == diagonal);
		CHECK(godot_physics_2d_limit_linear_velocity(diagonal, -100.0) == diagonal);
	}
	SUBCASE("Only velocities over the limit are reduced") {
		CHECK(godot_physics_2d_limit_linear_velocity(Vector2(3.0, 4.0), 5.0) == Vector2(3.0, 4.0));
		CHECK(godot_physics_2d_limit_linear_velocity(Vector2(1.0, 0.0), 100.0) == Vector2(1.0, 0.0));
		CHECK(godot_physics_2d_limit_linear_velocity(diagonal, 100.0).is_equal_approx(Vector2(60.0, 80.0)));
	}
	SUBCASE("Clamp is direction preserving and does not increase speed") {
		const Vector2 result = godot_physics_2d_limit_linear_velocity(Vector2(-300.0, 400.0), 100.0);
		CHECK(result.is_equal_approx(Vector2(-60.0, 80.0)));
		CHECK(Math::is_equal_approx(result.length(), real_t(100.0)));
	}
	SUBCASE("Huge finite speeds do not overflow when squared") {
		const Vector2 result = godot_physics_2d_limit_linear_velocity(Vector2(real_t(1e25), real_t(-1e25)), 100.0);
		CHECK(result.is_finite());
		CHECK(Math::is_equal_approx(result.length(), real_t(100.0)));
	}
	SUBCASE("Subnormal positive limit remains finite") {
		const Vector2 result = godot_physics_2d_limit_linear_velocity(diagonal, real_t(0.00001));
		CHECK(result.is_finite());
		CHECK(result.length() <= real_t(0.0000101));
	}
}

} // namespace TestGodotPhysics2DVelocityLimit

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
