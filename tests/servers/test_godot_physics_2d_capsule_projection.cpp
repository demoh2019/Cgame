/**************************************************************************/
/*  test_godot_physics_2d_capsule_projection.cpp                           */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "modules/modules_enabled.gen.h"
#include "tests/test_macros.h"

TEST_FORCE_LINK(test_godot_physics_2d_capsule_projection)

#ifdef MODULE_GODOT_PHYSICS_2D_ENABLED

#include "modules/godot_physics_2d/godot_shape_2d.h"

namespace TestGodotPhysics2DCapsuleProjection {

// Reference implementation kept in the test to detect projection regressions.
static void reference_project_range(const GodotCapsuleShape2D &p_capsule, const Vector2 &p_axis, const Transform2D &p_transform, real_t &r_min, real_t &r_max) {
	Vector2 support = p_transform.basis_xform_inv(p_axis).normalized();
	const real_t half_segment = p_capsule.get_height() * real_t(0.5) - p_capsule.get_radius();
	support *= p_capsule.get_radius();
	support.y += (support.y > 0.0) ? half_segment : -half_segment;
	r_max = p_axis.dot(p_transform.xform(support));
	r_min = p_axis.dot(p_transform.xform(-support));
	if (r_max < r_min) {
		SWAP(r_max, r_min);
	}
}

TEST_CASE("[GodotPhysics2D] Capsule SAT support projections match reference") {
	const Vector2 capsule_dimensions[] = {
		Vector2(1.0, 6.0),
		Vector2(0.25, 0.5),
		Vector2(0.0, 4.0)
	};
	const Transform2D transforms[] = {
		Transform2D(),
		Transform2D(real_t(0.6), Vector2(3.0, -4.0)),
		Transform2D(Vector2(2.0, 0.3), Vector2(0.4, 0.8), Vector2(-5.0, 6.0)),
		Transform2D(Vector2(-1.0, 0.0), Vector2(0.0, 2.0), Vector2(12.0, -4.0)),
		Transform2D(Vector2(0.0, 0.0), Vector2(0.0, 3.0), Vector2())
	};
	const Vector2 axes[] = {
		Vector2(1.0, 0.0),
		Vector2(0.0, 1.0),
		Vector2(1.0, 1.0).normalized(),
		Vector2(-2.0, 3.0),
		Vector2(0.001, 0.002),
		Vector2()
	};
	const Vector2 motion(1.7, -2.3);

	for (const Vector2 &dimensions : capsule_dimensions) {
		GodotCapsuleShape2D capsule;
		capsule.set_data(dimensions);
		for (const Transform2D &transform : transforms) {
			for (const Vector2 &axis : axes) {
				real_t expected_min = 0.0;
				real_t expected_max = 0.0;
				reference_project_range(capsule, axis, transform, expected_min, expected_max);

				real_t actual_min = 0.0;
				real_t actual_max = 0.0;
				capsule.project_range(axis, transform, actual_min, actual_max);
				CHECK(Math::is_equal_approx(actual_min, expected_min, real_t(0.0001)));
				CHECK(Math::is_equal_approx(actual_max, expected_max, real_t(0.0001)));

				const real_t shift = axis.dot(motion);
				const real_t expected_cast_min = MIN(expected_min, expected_min + shift);
				const real_t expected_cast_max = MAX(expected_max, expected_max + shift);
				capsule.project_range_cast(motion, axis, transform, actual_min, actual_max);
				CHECK(Math::is_equal_approx(actual_min, expected_cast_min, real_t(0.0001)));
				CHECK(Math::is_equal_approx(actual_max, expected_cast_max, real_t(0.0001)));
			}
		}
	}
}

} // namespace TestGodotPhysics2DCapsuleProjection

#endif // MODULE_GODOT_PHYSICS_2D_ENABLED
