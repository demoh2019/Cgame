/**************************************************************************/
/*  test_godot_physics_2d_primitive_inertia.cpp                            */
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

TEST_FORCE_LINK(test_godot_physics_2d_primitive_inertia)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "modules/godot_physics_2d/godot_shape_2d.h"

namespace TestGodotPhysics2DPrimitiveInertia {

TEST_CASE("[GodotPhysics2D] Primitive inertia uses the entire affine basis") {
	const Transform2D identity;
	const Transform2D shear(Vector2(1.0, 0.0), Vector2(2.0, 1.0), Vector2(30.0, -45.0));
	const Transform2D reflection(Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2());

	GodotCircleShape2D circle;
	circle.set_data(real_t(1.0));
	CHECK(Math::is_equal_approx(circle.get_moment_of_inertia_transformed(real_t(12.0), identity), real_t(6.0)));
	CHECK(Math::is_equal_approx(circle.get_moment_of_inertia_transformed(real_t(12.0), shear), real_t(18.0)));
	CHECK(Math::is_equal_approx(circle.get_moment_of_inertia_transformed(real_t(12.0), reflection), real_t(6.0)));

	GodotRectangleShape2D rectangle;
	rectangle.set_data(Vector2(2.0, 1.0));
	CHECK(Math::is_equal_approx(rectangle.get_moment_of_inertia_transformed(real_t(12.0), identity), real_t(20.0)));
	CHECK(Math::is_equal_approx(rectangle.get_moment_of_inertia_transformed(real_t(12.0), shear), real_t(36.0)));
	CHECK(Math::is_equal_approx(rectangle.get_moment_of_inertia_transformed(real_t(12.0), reflection), real_t(20.0)));
}

TEST_CASE("[GodotPhysics2D] Capsule mass inertia integrates rectangle and semicircular ends") {
	GodotCapsuleShape2D capsule;
	capsule.set_data(Vector2(1.0, 4.0));

	const Transform2D identity;
	const Transform2D shear(Vector2(1.0, 0.0), Vector2(2.0, 1.0), Vector2());
	const Transform2D rotation(Vector2(0.0, 1.0), Vector2(-1.0, 0.0), Vector2());
	// Independent area integrals for a vertical capsule of radius 1, height 4:
	// E[x*x] = 0.2966749294592964 and E[y*y] = 1.1099752116221107.
	const real_t expected_identity = real_t(14.06650141081407);
	const real_t expected_shear = real_t(58.465509875698494);
	CHECK(Math::is_equal_approx(capsule.get_moment_of_inertia(real_t(10.0), Vector2(1.0, 1.0)), expected_identity));
	CHECK(Math::is_equal_approx(capsule.get_moment_of_inertia_transformed(real_t(10.0), identity), expected_identity));
	CHECK(Math::is_equal_approx(capsule.get_moment_of_inertia_transformed(real_t(10.0), rotation), expected_identity));
	CHECK(Math::is_equal_approx(capsule.get_moment_of_inertia_transformed(real_t(10.0), shear), expected_shear));

	// When the straight section is zero, the capsule is a disk.
	capsule.set_data(Vector2(1.0, 2.0));
	CHECK(Math::is_equal_approx(capsule.get_moment_of_inertia_transformed(real_t(10.0), identity), real_t(5.0)));
	CHECK(Math::is_equal_approx(capsule.get_moment_of_inertia_transformed(real_t(10.0), shear), real_t(15.0)));
}

} // namespace TestGodotPhysics2DPrimitiveInertia

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
