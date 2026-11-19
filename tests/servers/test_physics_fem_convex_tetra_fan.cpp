/**************************************************************************/
/*  test_physics_fem_convex_tetra_fan.cpp                                 */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
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

#include "servers/physics_fem_convex_tetra_fan.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_fem_convex_tetra_fan)

namespace TestPhysicsFEMConvexTetraFan {

static const PhysicsFEMSurfaceTriangle cube_faces[12] = {
	{ 0, 2, 1 }, { 0, 3, 2 },
	{ 4, 5, 6 }, { 4, 6, 7 },
	{ 0, 1, 5 }, { 0, 5, 4 },
	{ 3, 7, 6 }, { 3, 6, 2 },
	{ 0, 4, 7 }, { 0, 7, 3 },
	{ 1, 2, 6 }, { 1, 6, 5 }
};

static void set_cube(Vector3 (&r_points)[8]) {
	r_points[0] = Vector3(0, 0, 0);
	r_points[1] = Vector3(1, 0, 0);
	r_points[2] = Vector3(1, 1, 0);
	r_points[3] = Vector3(0, 1, 0);
	r_points[4] = Vector3(0, 0, 1);
	r_points[5] = Vector3(1, 0, 1);
	r_points[6] = Vector3(1, 1, 1);
	r_points[7] = Vector3(0, 1, 1);
}

TEST_CASE("[PhysicsFEM] Closed convex cube creates multiple volume tets") {
	Vector3 p[8];
	set_cube(p);
	PhysicsFEMConvexTetra elements[12];
	uint32_t count = 42;
	CHECK(physics_fem_build_convex_tetra_fan(p, 8, cube_faces, 12, elements, 12, count));
	CHECK(count == 6);
	double total = 0.0;
	for (uint32_t i = 0; i < count; ++i) {
		total += elements[i].rest.volume;
		CHECK(elements[i].rest.volume > 0.0);
		CHECK(elements[i].nodes[0] == 0);
	}
	CHECK(total == doctest::Approx(1.0));
}

TEST_CASE("[PhysicsFEM] Uniform translation retains volume and connectivity") {
	Vector3 p[8];
	set_cube(p);
	for (Vector3 &v : p) {
		v += Vector3(1000, -100, 250);
	}
	PhysicsFEMConvexTetra elements[12];
	uint32_t count = 0;
	CHECK(physics_fem_build_convex_tetra_fan(p, 8, cube_faces, 12, elements, 12, count));
	CHECK(count == 6);
	for (uint32_t i = 0; i < count; ++i) {
		CHECK(elements[i].rest.volume == doctest::Approx(1.0 / 6.0));
	}
}

TEST_CASE("[PhysicsFEM] Reversed boundary winding still builds tets") {
	Vector3 p[8];
	set_cube(p);
	PhysicsFEMSurfaceTriangle flipped[12];
	for (int i = 0; i < 12; ++i) {
		flipped[i] = { cube_faces[i].a, cube_faces[i].c, cube_faces[i].b };
	}
	PhysicsFEMConvexTetra elements[12];
	uint32_t count = 0;
	CHECK(physics_fem_build_convex_tetra_fan(p, 8, flipped, 12, elements, 12, count));
	CHECK(count == 6);
	for (uint32_t i = 0; i < count; ++i) {
		CHECK(elements[i].rest.signed_det < 0.0);
	}
}

TEST_CASE("[PhysicsFEM] A four-vertex shell still creates exactly one FEM element") {
	const Vector3 p[4] = {
		Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)
	};
	const PhysicsFEMSurfaceTriangle faces[4] = {
		{ 0, 2, 1 }, { 0, 1, 3 }, { 0, 3, 2 }, { 1, 2, 3 }
	};
	PhysicsFEMConvexTetra elements[4];
	uint32_t count = 0;
	CHECK(physics_fem_build_convex_tetra_fan(p, 4, faces, 4, elements, 4, count));
	CHECK(count == 1);
	CHECK(elements[0].rest.volume == doctest::Approx(1.0 / 6.0));
}

TEST_CASE("[PhysicsFEM] Double-tetra bipyramid generates two connected tets") {
	const Vector3 p[5] = {
		Vector3(), Vector3(1, 0, 0), Vector3(0, 1, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1)
	};
	const PhysicsFEMSurfaceTriangle faces[6] = {
		{ 0, 3, 2 }, { 0, 1, 3 }, { 1, 2, 3 },
		{ 0, 2, 4 }, { 0, 4, 1 }, { 1, 4, 2 }
	};
	PhysicsFEMConvexTetra elements[6];
	uint32_t count = 0;
	CHECK(physics_fem_build_convex_tetra_fan(p, 5, faces, 6, elements, 6, count));
	CHECK(count == 2);
	CHECK(elements[0].nodes[0] == elements[1].nodes[0]);
	CHECK(elements[0].rest.volume + elements[1].rest.volume == doctest::Approx(1.0 / 3.0));
}

TEST_CASE("[PhysicsFEM] Concave surfaces are rejected without publishing output") {
	Vector3 p[8];
	set_cube(p);
	p[6] = Vector3(real_t(0.2), real_t(0.2), real_t(0.2));
	PhysicsFEMConvexTetra elements[12];
	uint32_t count = 71;
	CHECK_FALSE(physics_fem_build_convex_tetra_fan(p, 8, cube_faces, 12, elements, 12, count));
	CHECK(count == 71);
}

TEST_CASE("[PhysicsFEM] Invalid indices and duplicate vertices are rejected") {
	Vector3 p[8];
	set_cube(p);
	PhysicsFEMSurfaceTriangle bad[12];
	for (int i = 0; i < 12; ++i) {
		bad[i] = cube_faces[i];
	}
	bad[2].a = 12;
	PhysicsFEMConvexTetra elements[12];
	uint32_t count = 9;
	CHECK_FALSE(physics_fem_build_convex_tetra_fan(p, 8, bad, 12, elements, 12, count));
	bad[2] = { 4, 4, 6 };
	CHECK_FALSE(physics_fem_build_convex_tetra_fan(p, 8, bad, 12, elements, 12, count));
	CHECK(count == 9);
}

TEST_CASE("[PhysicsFEM] Nonfinite coordinates are rejected") {
	Vector3 p[8];
	set_cube(p);
	p[7].z = std::numeric_limits<real_t>::infinity();
	PhysicsFEMConvexTetra elements[12];
	uint32_t count = 55;
	CHECK_FALSE(physics_fem_build_convex_tetra_fan(p, 8, cube_faces, 12, elements, 12, count));
	CHECK(count == 55);
}

TEST_CASE("[PhysicsFEM] Out of capacity is rejected before writing elements") {
	Vector3 p[8];
	set_cube(p);
	PhysicsFEMConvexTetra elements[2];
	uint32_t count = 31;
	CHECK_FALSE(physics_fem_build_convex_tetra_fan(p, 8, cube_faces, 12, elements, 2, count));
	CHECK(count == 31);
}

TEST_CASE("[PhysicsFEM] Uniform scaling preserves relative volumetric coverage") {
	Vector3 p[8];
	set_cube(p);
	for (Vector3 &v : p) {
		v *= real_t(0.01);
	}
	PhysicsFEMConvexTetra elements[12];
	uint32_t count = 0;
	CHECK(physics_fem_build_convex_tetra_fan(p, 8, cube_faces, 12, elements, 12, count));
	CHECK(count == 6);
	double total = 0.0;
	for (uint32_t i = 0; i < count; ++i) {
		total += elements[i].rest.volume;
	}
	CHECK(total == doctest::Approx(1e-6));
}

TEST_CASE("[PhysicsFEM] A shared vertex deforms several neighboring tets") {
	Vector3 p[8];
	set_cube(p);
	PhysicsFEMConvexTetra elements[12];
	uint32_t count = 0;
	CHECK(physics_fem_build_convex_tetra_fan(p, 8, cube_faces, 12, elements, 12, count));
	p[0] = Vector3(real_t(0.05), real_t(0.05), real_t(0.05));
	uint32_t affected = 0;
	for (uint32_t i = 0; i < count; ++i) {
		const PhysicsFEMConvexTetra &tet = elements[i];
		double energy = 0.0;
		Vector3 ga, gb, gc, gd;
		if (physics_fem_tetra_energy_gradient(
				p[tet.nodes[0]], p[tet.nodes[1]], p[tet.nodes[2]], p[tet.nodes[3]],
				tet.rest, 0.3, energy, ga, gb, gc, gd)) {
			if (energy > 0.0) {
				++affected;
			}
		}
	}
	CHECK(affected >= 2);
}

} // namespace TestPhysicsFEMConvexTetraFan
