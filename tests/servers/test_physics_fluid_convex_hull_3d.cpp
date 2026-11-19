/**************************************************************************/
/*  test_physics_fluid_convex_hull_3d.cpp                                 */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_physics_fluid_convex_hull_3d)

#include "servers/physics_fluid_convex_hull_3d.h"

namespace TestPhysicsFluidConvexHull3D {

static void make_box_mesh(Geometry3D::MeshData &r_mesh) {
	const Vector3 vertices[8] = {
		Vector3(-1, -1, -1), Vector3(1, -1, -1),
		Vector3(1, 1, -1), Vector3(-1, 1, -1),
		Vector3(-1, -1, 1), Vector3(1, -1, 1),
		Vector3(1, 1, 1), Vector3(-1, 1, 1)
	};
	const int faces[6][4] = {
		{ 0, 1, 2, 3 }, { 4, 7, 6, 5 },
		{ 0, 4, 5, 1 }, { 3, 2, 6, 7 },
		{ 0, 3, 7, 4 }, { 1, 5, 6, 2 }
	};
	r_mesh.vertices.resize(8);
	r_mesh.faces.resize(6);
	for (int i = 0; i < 8; i++) {
		r_mesh.vertices[i] = vertices[i];
	}
	for (int i = 0; i < 6; i++) {
		for (int j = 0; j < 4; j++) {
			r_mesh.faces[i].indices.push_back(faces[i][j]);
		}
	}
}

static void make_tetra_mesh(Geometry3D::MeshData &r_mesh, const Vector3 &p_a,
		const Vector3 &p_b, const Vector3 &p_c, const Vector3 &p_d) {
	const Vector3 vertices[4] = { p_a, p_b, p_c, p_d };
	const int faces[4][3] = {
		{ 0, 1, 2 }, { 0, 3, 1 },
		{ 0, 2, 3 }, { 1, 3, 2 }
	};
	r_mesh.vertices.resize(4);
	r_mesh.faces.resize(4);
	for (int i = 0; i < 4; i++) {
		r_mesh.vertices[i] = vertices[i];
	}
	for (int i = 0; i < 4; i++) {
		for (int j = 0; j < 3; j++) {
			r_mesh.faces[i].indices.push_back(faces[i][j]);
		}
	}
}

TEST_CASE("[Physics] Convex water halfspace clips unrotated and rotated boxes exactly") {
	Geometry3D::MeshData mesh;
	make_box_mesh(mesh);
	GodotPhysicsFluidSample3D sample;
	real_t total_volume;

	CHECK(godot_physics_fluid_convex_hull_sample_3d(mesh, Transform3D(), 0.0, sample, total_volume));
	CHECK(Math::is_equal_approx(total_volume, real_t(8.0)));
	CHECK(Math::is_equal_approx(sample.submerged_volume, real_t(4.0)));
	CHECK(Math::is_equal_approx(sample.submerged_fraction, real_t(0.5)));
	CHECK(sample.center_of_buoyancy.distance_to(Vector3(0.0, -0.5, 0.0)) < real_t(0.0001));

	CHECK(godot_physics_fluid_convex_hull_sample_3d(mesh,
			Transform3D(Basis(Vector3(0, 0, 1), Math::PI / 4.0), Vector3()), 0.0, sample, total_volume));
	CHECK(Math::is_equal_approx(total_volume, real_t(8.0)));
	CHECK(Math::is_equal_approx(sample.submerged_volume, real_t(4.0)));
	CHECK(Math::is_equal_approx(sample.center_of_buoyancy.x, real_t(0.0)));
	CHECK(Math::is_equal_approx(sample.center_of_buoyancy.z, real_t(0.0)));
	CHECK(Math::abs(sample.center_of_buoyancy.y + Math::sqrt(real_t(2.0)) / real_t(3.0)) < real_t(0.0001));

	// Nonuniform scale and translation must preserve exact displacement,
	// with world volume multiplied by the absolute basis determinant.
	const Transform3D stretched(Basis::from_scale(Vector3(2.0, 3.0, 4.0)), Vector3(100, 20, -100));
	CHECK(godot_physics_fluid_convex_hull_sample_3d(mesh, stretched, 20.0, sample, total_volume));
	CHECK(Math::is_equal_approx(total_volume, real_t(192.0)));
	CHECK(Math::is_equal_approx(sample.submerged_volume, real_t(96.0)));
	CHECK(sample.center_of_buoyancy.distance_to(Vector3(100, 18.5, -100)) < real_t(0.0001));

	const Transform3D mirrored(Basis::from_scale(Vector3(-2.0, 3.0, 4.0)), Vector3(0, 0, 0));
	CHECK(godot_physics_fluid_convex_hull_sample_3d(mesh, mirrored, 0.0, sample, total_volume));
	CHECK(Math::is_equal_approx(total_volume, real_t(192.0)));
	CHECK(Math::is_equal_approx(sample.submerged_volume, real_t(96.0)));
}

TEST_CASE("[Physics] Convex tetra clipping handles one, two, three and four wet vertices") {
	GodotPhysicsFluidSample3D sample;
	real_t total_volume;

	{
		Geometry3D::MeshData mesh;
		make_tetra_mesh(mesh, Vector3(0, -1, 0), Vector3(1, 1, 0),
				Vector3(0, 1, 1), Vector3(0, 1, -1));
		CHECK(godot_physics_fluid_convex_hull_sample_3d(mesh, Transform3D(), 0.0, sample, total_volume));
		CHECK(Math::is_equal_approx(sample.submerged_fraction, real_t(0.125)));
		CHECK(Math::is_equal_approx(sample.center_of_buoyancy.y, real_t(-0.25)));
	}
	{
		Geometry3D::MeshData mesh;
		make_tetra_mesh(mesh, Vector3(0, -1, 0), Vector3(1, -1, 0),
				Vector3(0, 1, 0), Vector3(0, 1, 1));
		CHECK(godot_physics_fluid_convex_hull_sample_3d(mesh, Transform3D(), 0.0, sample, total_volume));
		CHECK(Math::is_equal_approx(sample.submerged_fraction, real_t(0.5)));
		CHECK(Math::is_equal_approx(sample.center_of_buoyancy.y, real_t(-0.375)));
	}
	{
		Geometry3D::MeshData mesh;
		make_tetra_mesh(mesh, Vector3(0, 1, 0), Vector3(1, -1, 0),
				Vector3(0, -1, 1), Vector3(0, -1, -1));
		CHECK(godot_physics_fluid_convex_hull_sample_3d(mesh, Transform3D(), 0.0, sample, total_volume));
		CHECK(Math::is_equal_approx(sample.submerged_fraction, real_t(0.875)));
		CHECK(Math::abs(sample.center_of_buoyancy.y + real_t(17.0 / 28.0)) < real_t(0.0001));
		CHECK(godot_physics_fluid_convex_hull_sample_3d(mesh, Transform3D(), -10.0, sample, total_volume));
		CHECK(sample.submerged_volume == 0.0);
		CHECK(godot_physics_fluid_convex_hull_sample_3d(mesh, Transform3D(), 10.0, sample, total_volume));
		CHECK(Math::is_equal_approx(sample.submerged_fraction, real_t(1.0)));
	}
}

TEST_CASE("[Physics] Invalid and overbudget convex hulls fail without returning fictitious displacement") {
	Geometry3D::MeshData mesh;
	make_box_mesh(mesh);
	GodotPhysicsFluidSample3D sample;
	real_t total_volume;
	CHECK(godot_physics_fluid_convex_hull_sample_3d(mesh, Transform3D(), 0.0, sample, total_volume));
	mesh.faces[0].indices[0] = 500;
	CHECK(!godot_physics_fluid_convex_hull_sample_3d(mesh, Transform3D(), 0.0, sample, total_volume));
	CHECK(total_volume == 0.0);
	mesh.faces[0].indices[0] = 0;
	mesh.faces.resize(257);
	CHECK(!godot_physics_fluid_convex_hull_sample_3d(mesh, Transform3D(), 0.0, sample, total_volume));
}

} // namespace TestPhysicsFluidConvexHull3D
