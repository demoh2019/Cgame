/**************************************************************************/
/*  test_godot_physics_3d_mesh_projection.cpp                              */
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

TEST_FORCE_LINK(test_godot_physics_3d_mesh_projection)

#ifdef MODULE_GODOT_PHYSICS_3D_ENABLED

#include "modules/godot_physics_3d/godot_shape_3d.h"

namespace TestGodotPhysics3DMeshProjection {

static void check_mesh_projection(const GodotShape3D &p_shape, const Vector<Vector3> &p_vertices) {
	const Transform3D transforms[] = {
		Transform3D(),
		Transform3D(Basis(Vector3(1.0, 0.0, 0.0), real_t(0.7)), Vector3(3.0, -4.0, 2.0)),
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

	for (const Transform3D &transform : transforms) {
		for (const Vector3 &axis : axes) {
			real_t expected_min = 0.0;
			real_t expected_max = 0.0;
			for (int i = 0; i < p_vertices.size(); ++i) {
				const real_t value = axis.dot(transform.xform(p_vertices[i]));
				if (i == 0) {
					expected_min = value;
					expected_max = value;
				} else {
					expected_min = MIN(expected_min, value);
					expected_max = MAX(expected_max, value);
				}
			}

			real_t actual_min = 0.0;
			real_t actual_max = 0.0;
			p_shape.project_range(axis, transform, actual_min, actual_max);
			CHECK(Math::is_equal_approx(actual_min, expected_min, real_t(0.0001)));
			CHECK(Math::is_equal_approx(actual_max, expected_max, real_t(0.0001)));
		}
	}
}

TEST_CASE("[GodotPhysics3D] Triangle SAT projection matches transformed vertices") {
	GodotFaceShape3D face;
	face.vertex[0] = Vector3(-2.0, 1.0, 0.5);
	face.vertex[1] = Vector3(2.0, -1.0, -0.5);
	face.vertex[2] = Vector3(0.0, 3.0, 2.0);
	Vector<Vector3> points;
	for (int i = 0; i < 3; ++i) {
		points.push_back(face.vertex[i]);
	}
	check_mesh_projection(face, points);
}

TEST_CASE("[GodotPhysics3D] Concave triangle mesh SAT projection matches transformed vertices") {
	Vector<Vector3> triangles;
	for (int x = 0; x < 6; ++x) {
		for (int z = 0; z < 6; ++z) {
			const Vector3 a(x, real_t(x * x + z) * real_t(0.05), z);
			const Vector3 b(x + 1, real_t((x + 1) * (x + 1) + z) * real_t(0.05), z);
			const Vector3 c(x, real_t(x * x + z + 1) * real_t(0.05), z + 1);
			const Vector3 d(x + 1, real_t((x + 1) * (x + 1) + z + 1) * real_t(0.05), z + 1);
			triangles.push_back(a);
			triangles.push_back(b);
			triangles.push_back(c);
			triangles.push_back(b);
			triangles.push_back(d);
			triangles.push_back(c);
		}
	}

	GodotConcavePolygonShape3D mesh;
	Dictionary data;
	data["faces"] = triangles;
	data["backface_collision"] = false;
	mesh.set_data(data);
	check_mesh_projection(mesh, triangles);
}

TEST_CASE("[GodotPhysics3D] Empty concave mesh retains zero projection") {
	GodotConcavePolygonShape3D empty;
	real_t range_min = -1.0;
	real_t range_max = 2.0;
	empty.project_range(Vector3(1.0, 0.0, 0.0), Transform3D(), range_min, range_max);
	CHECK(range_min == real_t(0.0));
	CHECK(range_max == real_t(0.0));
}

} // namespace TestGodotPhysics3DMeshProjection

#endif // MODULE_GODOT_PHYSICS_3D_ENABLED
