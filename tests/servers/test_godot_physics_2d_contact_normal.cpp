/**************************************************************************/
/*  test_godot_physics_2d_contact_normal.cpp                              */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "modules/modules_enabled.gen.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_2d_contact_normal)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "modules/godot_physics_2d/godot_contact_normal_2d.h"

namespace TestGodotPhysics2DContactNormal {

TEST_CASE("[GodotPhysics2D] Degenerate contact normal fallback") {
	SUBCASE("Penetrating contacts retain point-derived normal") {
		const Vector2 normal = godot_physics_2d_contact_normal(Vector2(0.0, -2.0), Vector2(), Vector2(1.0, 0.0));
		CHECK(normal.is_equal_approx(Vector2(0.0, -1.0)));
	}
	SUBCASE("Exact tangency uses body center direction") {
		const Vector2 normal = godot_physics_2d_contact_normal(Vector2(2.0, 0.0), Vector2(2.0, 0.0), Vector2(3.0, 4.0));
		CHECK(normal.is_equal_approx(Vector2(0.6, 0.8)));
	}
	SUBCASE("Almost coincident points prefer center direction") {
		const real_t tiny = real_t(CMP_EPSILON) * real_t(0.01);
		const Vector2 normal = godot_physics_2d_contact_normal(Vector2(tiny, 0.0), Vector2(), Vector2(-3.0, 0.0));
		CHECK(normal.is_equal_approx(Vector2(-1.0, 0.0)));
	}
	SUBCASE("Coincident centers use deterministic unit axis") {
		const Vector2 normal = godot_physics_2d_contact_normal(Vector2(), Vector2(), Vector2());
		CHECK(normal.is_equal_approx(Vector2(0.0, 1.0)));
	}
	SUBCASE("Reversed point order flips nondegenerate normal") {
		const Vector2 normal = godot_physics_2d_contact_normal(Vector2(1.0, 0.0), Vector2(3.0, 0.0), Vector2(0.0, 1.0));
		CHECK(normal.is_equal_approx(Vector2(-1.0, 0.0)));
	}
}

} // namespace TestGodotPhysics2DContactNormal

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
