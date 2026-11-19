/**************************************************************************/
/*  test_godot_physics_2d_capsule_long_ray.cpp                             */
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

TEST_FORCE_LINK(test_godot_physics_2d_capsule_long_ray)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "modules/godot_physics_2d/godot_shape_2d.h"

namespace TestGodotPhysics2DCapsuleLongRay {

TEST_CASE("[GodotPhysics2D] Capsule rays keep entry positions for million-unit segments") {
	GodotCapsuleShape2D capsule;
	capsule.set_data(Vector2(1.0, 4.0));
	const real_t expected = real_t(0.8660254037844386);
	Vector2 point, normal;

	// This ray hits only the upper round cap (the central rectangle ends at y=1).
	// A float quadratic discriminant rounds to zero and incorrectly returns x=0.
	CHECK(capsule.intersect_segment(Vector2(real_t(-1000000.0), real_t(1.5)), Vector2(real_t(1000000.0), real_t(1.5)), point, normal));
	CHECK(Math::abs(point.x + expected) < real_t(0.01));
	CHECK(Math::abs(point.y - real_t(1.5)) < real_t(0.01));
	CHECK(normal.is_equal_approx(Vector2(-expected, real_t(0.5))));

	CHECK(capsule.intersect_segment(Vector2(real_t(1000000.0), real_t(1.5)), Vector2(real_t(-1000000.0), real_t(1.5)), point, normal));
	CHECK(Math::abs(point.x - expected) < real_t(0.01));
	CHECK(normal.is_equal_approx(Vector2(expected, real_t(0.5))));

	CHECK(capsule.intersect_segment(Vector2(-3.0, 1.5), Vector2(3.0, 1.5), point, normal));
	CHECK(Math::abs(point.x + expected) < real_t(0.01));
	CHECK(capsule.intersect_segment(Vector2(-3.0, 2.0), Vector2(3.0, 2.0), point, normal));
	CHECK(point.is_equal_approx(Vector2(0.0, 2.0)));

	CHECK_FALSE(capsule.intersect_segment(Vector2(-3.0, 2.1), Vector2(3.0, 2.1), point, normal));
	CHECK_FALSE(capsule.intersect_segment(Vector2(-3.0, 1.5), Vector2(-3.0, 1.5), point, normal));
	CHECK_FALSE(capsule.intersect_segment(Vector2(0.0, 1.5), Vector2(0.0, 5.0), point, normal));
}

} // namespace TestGodotPhysics2DCapsuleLongRay

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
