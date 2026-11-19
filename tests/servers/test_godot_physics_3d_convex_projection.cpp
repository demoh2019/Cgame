/**************************************************************************/
/*  test_godot_physics_3d_convex_projection.cpp                            */
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

TEST_FORCE_LINK(test_godot_physics_3d_convex_projection)

#ifdef MODULE_GODOT_PHYSICS_3D_ENABLED

#include "modules/godot_physics_3d/godot_shape_3d.h"

namespace TestGodotPhysics3DConvexProjection {

TEST_CASE("[GodotPhysics3D] Convex SAT projection matches transformed vertex enumeration") {
	const Transform3D transforms[] = {
		Transform3D(),
		Transform3D(Basis(Vector3(0.0, 1.0, 0.0), real_t(0.65)), Vector3(3.0, -4.0, 5.0)),
		Transform3D(Basis::from_scale(Vector3(2.0, 3.0, 0.5)), Vector3(1.0, 2.0, -2.0)),
		Transform3D(Basis(Vector3(1.8, 0.2, 0.0), Vector3(0.3, 0.9, -0.4), Vector3(-0.2, 0.1, 1.4)), Vector3(-7.0, 4.0, 3.0)),
		Transform3D(Basis::from_scale(Vector3(-1.0, 0.5, -2.0)), Vector3(2.0, -3.0, 1.0)),
		Transform3D(Basis::from_scale(Vector3(0.0, 2.0, 0.5)), Vector3(-2.0, 5.0, 1.0))
	};
	const Vector3 axes[] = {
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(1.0, -2.0, 3.0).normalized(),
		Vector3(-2.0, 3.0, -4.0),
		Vector3(0.001, 0.002, -0.003),
		Vector3()
	};

	for (int mesh_kind = 0; mesh_kind < 2; ++mesh_kind) {
		Vector<Vector3> points;
		if (mesh_kind == 0) {
			// Small mesh: exercises the direct projection loop.
			for (int i = 0; i < 8; ++i) {
				points.push_back(Vector3((i & 1) ? 2.0 : -2.0,
						(i & 2) ? 1.0 : -1.0, (i & 4) ? 3.0 : -3.0));
			}
		} else {
			// Many hull vertices: exercises the hill-climbing support path.
			constexpr int VERTICES = 128;
			for (int i = 0; i < VERTICES; ++i) {
				const real_t y = real_t(1.0) - (real_t(i) + real_t(0.5)) * (real_t(2.0) / VERTICES);
				const real_t radial = Math::sqrt(real_t(1.0) - y * y);
				const real_t angle = real_t(i) * real_t(2.399963229728653);
				points.push_back(Vector3(radial * Math::cos(angle), y, radial * Math::sin(angle)));
			}
		}

		GodotConvexPolygonShape3D convex;
		convex.set_data(points);
		for (const Transform3D &transform : transforms) {
			for (const Vector3 &axis : axes) {
				real_t expected_min = 0.0;
				real_t expected_max = 0.0;
				for (int i = 0; i < points.size(); ++i) {
					const real_t projected = axis.dot(transform.xform(points[i]));
					if (i == 0) {
						expected_min = projected;
						expected_max = projected;
					} else {
						expected_min = MIN(expected_min, projected);
						expected_max = MAX(expected_max, projected);
					}
				}

				real_t actual_min = 0.0;
				real_t actual_max = 0.0;
				convex.project_range(axis, transform, actual_min, actual_max);
				CHECK(Math::is_equal_approx(actual_min, expected_min, real_t(0.0001)));
				CHECK(Math::is_equal_approx(actual_max, expected_max, real_t(0.0001)));
			}
		}
	}
}

} // namespace TestGodotPhysics3DConvexProjection

#endif // MODULE_GODOT_PHYSICS_3D_ENABLED
