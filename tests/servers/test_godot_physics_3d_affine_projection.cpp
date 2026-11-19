/**************************************************************************/
/*  test_godot_physics_3d_affine_projection.cpp                            */
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

TEST_FORCE_LINK(test_godot_physics_3d_affine_projection)

#ifdef MODULE_GODOT_PHYSICS_3D_ENABLED

#include "modules/godot_physics_3d/godot_shape_3d.h"

namespace TestGodotPhysics3DAffineProjection {

// Independent support-point reference for the capsule: a line segment
// Minkowski-summed with a sphere, evaluated in the transformed direction.
static void reference_capsule_projection(const Vector3 &p_axis, const Transform3D &p_transform, real_t p_radius, real_t p_height, real_t &r_min, real_t &r_max) {
	const Vector3 direction = p_transform.basis.xform_inv(p_axis);
	const real_t half_segment = p_height * real_t(0.5) - p_radius;
	Vector3 support = direction.normalized() * p_radius;
	support.y += direction.y >= 0.0 ? half_segment : -half_segment;

	r_max = p_axis.dot(p_transform.xform(support));
	r_min = p_axis.dot(p_transform.xform(-support));
}

// Independent support-point reference for a cylinder: the farthest disk
// point and the appropriate axial end cap, without using the new formula.
static void reference_cylinder_projection(const Vector3 &p_axis, const Transform3D &p_transform, real_t p_radius, real_t p_height, real_t &r_min, real_t &r_max) {
	const Vector3 direction = p_transform.basis.xform_inv(p_axis);
	const real_t disk_length = Math::sqrt(direction.x * direction.x + direction.z * direction.z);
	Vector3 support;
	if (disk_length > 0.0) {
		support.x = p_radius * direction.x / disk_length;
		support.z = p_radius * direction.z / disk_length;
	}
	support.y = direction.y >= 0.0 ? p_height * real_t(0.5) : -p_height * real_t(0.5);

	r_max = p_axis.dot(p_transform.xform(support));
	r_min = p_axis.dot(p_transform.xform(-support));
}

TEST_CASE("[GodotPhysics3D] Affine capsule SAT projections match support points") {
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
	const Vector2 dimensions[] = {
		Vector2(1.0, 6.0),
		Vector2(0.25, 0.5),
		Vector2(0.0, 4.0)
	};

	for (const Vector2 &dimensions_entry : dimensions) {
		GodotCapsuleShape3D capsule;
		Dictionary data;
		data["radius"] = dimensions_entry.x;
		data["height"] = dimensions_entry.y;
		capsule.set_data(data);

		for (const Transform3D &transform : transforms) {
			for (const Vector3 &axis : axes) {
				real_t expected_min;
				real_t expected_max;
				reference_capsule_projection(axis, transform, dimensions_entry.x, dimensions_entry.y, expected_min, expected_max);

				real_t actual_min;
				real_t actual_max;
				capsule.project_range(axis, transform, actual_min, actual_max);
				CHECK(Math::is_equal_approx(actual_min, expected_min, real_t(0.0001)));
				CHECK(Math::is_equal_approx(actual_max, expected_max, real_t(0.0001)));
			}
		}
	}
}

TEST_CASE("[GodotPhysics3D] Affine cylinder SAT projections match support points") {
	const Transform3D transforms[] = {
		Transform3D(),
		Transform3D(Basis(Vector3(0.0, 0.0, 1.0), real_t(0.8)), Vector3(-3.0, 2.0, 1.0)),
		Transform3D(Basis::from_scale(Vector3(2.0, 3.0, 0.5)), Vector3(2.0, -1.0, 5.0)),
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
	const Vector2 dimensions[] = {
		Vector2(1.0, 4.0),
		Vector2(0.25, 0.5),
		Vector2(0.0, 4.0)
	};

	for (const Vector2 &dimensions_entry : dimensions) {
		GodotCylinderShape3D cylinder;
		Dictionary data;
		data["radius"] = dimensions_entry.x;
		data["height"] = dimensions_entry.y;
		cylinder.set_data(data);

		for (const Transform3D &transform : transforms) {
			for (const Vector3 &axis : axes) {
				real_t expected_min;
				real_t expected_max;
				reference_cylinder_projection(axis, transform, dimensions_entry.x, dimensions_entry.y, expected_min, expected_max);

				real_t actual_min;
				real_t actual_max;
				cylinder.project_range(axis, transform, actual_min, actual_max);
				CHECK(Math::is_equal_approx(actual_min, expected_min, real_t(0.0001)));
				CHECK(Math::is_equal_approx(actual_max, expected_max, real_t(0.0001)));
			}
		}
	}

	SUBCASE("Nonuniform scale has exact known bounds") {
		GodotCylinderShape3D cylinder;
		Dictionary data;
		data["radius"] = 1.0;
		data["height"] = 4.0;
		cylinder.set_data(data);

		const Transform3D scaled(Basis::from_scale(Vector3(2.0, 3.0, 0.5)), Vector3());
		real_t min_projection;
		real_t max_projection;
		cylinder.project_range(Vector3(1.0, 1.0, 0.0), scaled, min_projection, max_projection);
		CHECK(Math::is_equal_approx(min_projection, real_t(-8.0)));
		CHECK(Math::is_equal_approx(max_projection, real_t(8.0)));
	}
}


TEST_CASE("[GodotPhysics3D] Solid capsule and cylinder moments of inertia") {
	GodotCylinderShape3D cylinder;
	Dictionary cylinder_data;
	cylinder_data["radius"] = 1.0;
	cylinder_data["height"] = 4.0;
	cylinder.set_data(cylinder_data);

	const Vector3 cylinder_inertia = cylinder.get_moment_of_inertia(real_t(2.0));
	CHECK(cylinder_inertia.is_equal_approx(Vector3(real_t(19.0 / 6.0), 1.0, real_t(19.0 / 6.0))));

	GodotCapsuleShape3D capsule;
	Dictionary capsule_data;
	capsule_data["radius"] = 1.0;
	capsule_data["height"] = 6.0;
	capsule.set_data(capsule_data);

	// Total mass 2 splits into cylinder mass 1.5 and hemisphere mass 0.5.
	const Vector3 capsule_inertia = capsule.get_moment_of_inertia(real_t(2.0));
	CHECK(capsule_inertia.is_equal_approx(Vector3(real_t(213.0 / 40.0), real_t(19.0 / 20.0), real_t(213.0 / 40.0))));

	// Zero-length center segment is exactly a solid sphere.
	capsule_data["height"] = 2.0;
	capsule.set_data(capsule_data);
	const Vector3 sphere_inertia = capsule.get_moment_of_inertia(real_t(5.0));
	CHECK(sphere_inertia.is_equal_approx(Vector3(2.0, 2.0, 2.0)));

	// The vanishing-radius limit is a rod (I_y = 0, I_x = I_z = m h^2 / 12).
	capsule_data["radius"] = 0.0;
	capsule_data["height"] = 4.0;
	capsule.set_data(capsule_data);
	CHECK(capsule.get_moment_of_inertia(real_t(2.0)).is_equal_approx(
			Vector3(real_t(8.0 / 3.0), 0.0, real_t(8.0 / 3.0))));

	cylinder_data["radius"] = 0.0;
	cylinder.set_data(cylinder_data);
	CHECK(cylinder.get_moment_of_inertia(real_t(2.0)).is_equal_approx(
			Vector3(real_t(8.0 / 3.0), 0.0, real_t(8.0 / 3.0))));
}

} // namespace TestGodotPhysics3DAffineProjection

#endif // MODULE_GODOT_PHYSICS_3D_ENABLED
