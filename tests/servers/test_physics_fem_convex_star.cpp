/**************************************************************************/
/*  test_physics_fem_convex_star.cpp                                      */
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
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "servers/physics_fem_convex_star.h"
#include "tests/test_macros.h"

#include <initializer_list>

TEST_FORCE_LINK(test_physics_fem_convex_star)

namespace TestPhysicsFEMConvexStar {

static void build_cube(LocalVector<Vector3> &r_points,
		LocalVector<PhysicsFEMConvexFace> &r_faces, real_t p_scale = 1.0) {
	r_points.reset();
	r_faces.reset();
	const Vector3 positions[] = {
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0),
		Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 1),
		Vector3(1, 1, 1), Vector3(0, 1, 1)
	};
	for (const Vector3 &p : positions) {
		r_points.push_back(p * p_scale);
	}
	const PhysicsFEMConvexFace triangles[] = {
		{ 0, 2, 1 }, { 0, 3, 2 }, // Bottom
		{ 4, 5, 6 }, { 4, 6, 7 }, // Top
		{ 0, 1, 5 }, { 0, 5, 4 }, // Front
		{ 3, 7, 6 }, { 3, 6, 2 }, // Back
		{ 0, 4, 7 }, { 0, 7, 3 }, // Left
		{ 1, 2, 6 }, { 1, 6, 5 }  // Right
	};
	for (const PhysicsFEMConvexFace &tri : triangles) {
		r_faces.push_back(tri);
	}
}

TEST_CASE("[PhysicsFEMConvex] A closed tetrahedron still cooks exactly one element") {
	LocalVector<Vector3> points;
	points.push_back(Vector3());
	points.push_back(Vector3(1, 0, 0));
	points.push_back(Vector3(0, 1, 0));
	points.push_back(Vector3(0, 0, 1));
	LocalVector<PhysicsFEMConvexFace> faces;
	faces.push_back({ 1, 2, 3 });
	faces.push_back({ 0, 3, 2 });
	faces.push_back({ 0, 1, 3 });
	faces.push_back({ 0, 2, 1 });
	LocalVector<PhysicsFEMConvexTetra> cooked;
	CHECK(physics_fem_build_convex_star_tetrahedra(points, faces, 1.0 / 6.0, cooked));
	REQUIRE(cooked.size() == 1);
	CHECK(cooked[0].a == 0);
	CHECK(cooked[0].rest.volume == doctest::Approx(1.0 / 6.0));
	CHECK(cooked[0].lambda == 0.0);
}

TEST_CASE("[PhysicsFEMConvex] Convex cube cooks six non-overlapping tetrahedra") {
	LocalVector<Vector3> points;
	LocalVector<PhysicsFEMConvexFace> faces;
	build_cube(points, faces);
	LocalVector<PhysicsFEMConvexTetra> cooked;
	CHECK(physics_fem_build_convex_star_tetrahedra(points, faces, 1.0, cooked));
	REQUIRE(cooked.size() == 6);
	double volume = 0.0;
	for (const PhysicsFEMConvexTetra &tetra : cooked) {
		CHECK(tetra.a == 0);
		CHECK(tetra.b < points.size());
		CHECK(tetra.c < points.size());
		CHECK(tetra.d < points.size());
		CHECK(tetra.rest.signed_det > 0.0);
		volume += tetra.rest.volume;
	}
	CHECK(volume == doctest::Approx(1.0));
}

TEST_CASE("[PhysicsFEMConvex] Reversed outward winding is also supported") {
	LocalVector<Vector3> points;
	LocalVector<PhysicsFEMConvexFace> faces;
	build_cube(points, faces);
	for (PhysicsFEMConvexFace &face : faces) {
		SWAP(face.b, face.c);
	}
	LocalVector<PhysicsFEMConvexTetra> cooked;
	CHECK(physics_fem_build_convex_star_tetrahedra(points, faces, -1.0, cooked));
	REQUIRE(cooked.size() == 6);
	for (const PhysicsFEMConvexTetra &tetra : cooked) {
		CHECK(tetra.rest.signed_det < 0.0);
	}
}

TEST_CASE("[PhysicsFEMConvex] Nonconvex star-shaped shell is rejected transactionally") {
	LocalVector<Vector3> points;
	LocalVector<PhysicsFEMConvexFace> faces;
	build_cube(points, faces);
	LocalVector<PhysicsFEMConvexTetra> cooked;
	REQUIRE(physics_fem_build_convex_star_tetrahedra(points, faces, 1.0, cooked));
	const uint32_t unchanged = cooked.size();
	// Push a corner inside the cube: surface triangle planes cease to be
	// supporting hull planes even though the shell can remain watertight.
	points[6] = Vector3(real_t(0.35), real_t(0.35), real_t(0.35));
	CHECK_FALSE(physics_fem_build_convex_star_tetrahedra(points, faces, 0.35, cooked));
	CHECK(cooked.size() == unchanged);
}

TEST_CASE("[PhysicsFEMConvex] Open, inconsistent and non-manifold edges are rejected") {
	LocalVector<Vector3> points;
	LocalVector<PhysicsFEMConvexFace> faces;
	build_cube(points, faces);
	LocalVector<PhysicsFEMConvexTetra> cooked;
	REQUIRE(physics_fem_build_convex_star_tetrahedra(points, faces, 1.0, cooked));
	const uint32_t original = cooked.size();

	LocalVector<PhysicsFEMConvexFace> open_faces;
	for (uint32_t i = 0; i + 1 < faces.size(); ++i) {
		open_faces.push_back(faces[i]);
	}
	CHECK_FALSE(physics_fem_build_convex_star_tetrahedra(points, open_faces, 1.0, cooked));
	CHECK(cooked.size() == original);

	// One face reversed creates edges with duplicated orientation.
	const uint32_t previous_b = faces[0].b;
	faces[0].b = faces[0].c;
	faces[0].c = previous_b;
	CHECK_FALSE(physics_fem_build_convex_star_tetrahedra(points, faces, 1.0, cooked));
	CHECK(cooked.size() == original);

	// A third face sharing any existing edge violates manifold topology.
	faces[0].c = faces[0].b;
	faces[0].b = previous_b;
	faces.push_back(faces[0]);
	CHECK_FALSE(physics_fem_build_convex_star_tetrahedra(points, faces, 1.0, cooked));
	CHECK(cooked.size() == original);
}

TEST_CASE("[PhysicsFEMConvex] Invalid indexing and false volume are rejected") {
	LocalVector<Vector3> points;
	LocalVector<PhysicsFEMConvexFace> faces;
	build_cube(points, faces);
	LocalVector<PhysicsFEMConvexTetra> cooked;
	CHECK_FALSE(physics_fem_build_convex_star_tetrahedra(points, faces, 0.5, cooked));
	CHECK(cooked.is_empty());
	faces[2].b = 123456;
	CHECK_FALSE(physics_fem_build_convex_star_tetrahedra(points, faces, 1.0, cooked));
	CHECK(cooked.is_empty());
}

TEST_CASE("[PhysicsFEMConvex] Small and huge geometry preserves normalized topology") {
	for (const real_t scale : { real_t(1e-8), real_t(1e20) }) {
		LocalVector<Vector3> points;
		LocalVector<PhysicsFEMConvexFace> faces;
		build_cube(points, faces, scale);
		LocalVector<PhysicsFEMConvexTetra> cooked;
		CHECK(physics_fem_build_convex_star_tetrahedra(
				points, faces, double(scale) * scale * scale, cooked));
		REQUIRE(cooked.size() == 6);
		double volume = 0.0;
		for (const PhysicsFEMConvexTetra &tetra : cooked) {
			volume += tetra.rest.volume;
		}
		CHECK(volume / (double(scale) * scale * scale) == doctest::Approx(1.0).epsilon(1e-5));
	}
}

TEST_CASE("[PhysicsFEMConvex] Multi-element constraints damp a deformed corner") {
	LocalVector<Vector3> points;
	LocalVector<PhysicsFEMConvexFace> faces;
	build_cube(points, faces);
	LocalVector<PhysicsFEMConvexTetra> cooked;
	REQUIRE(physics_fem_build_convex_star_tetrahedra(points, faces, 1.0, cooked));
	points[6].z = real_t(1.25);
	uint32_t active = 0;
	for (PhysicsFEMConvexTetra &tetra : cooked) {
		const real_t dynamic_b = tetra.b == 6 ? real_t(1) : real_t(0);
		const real_t dynamic_c = tetra.c == 6 ? real_t(1) : real_t(0);
		const real_t dynamic_d = tetra.d == 6 ? real_t(1) : real_t(0);
		if (dynamic_b + dynamic_c + dynamic_d > 0.0 &&
				physics_fem_tetra_solve(
						points[tetra.a], points[tetra.b], points[tetra.c], points[tetra.d],
						0.0, dynamic_b, dynamic_c, dynamic_d,
						tetra.rest, 0.3, 0.0, tetra.lambda)) {
			++active;
		}
	}
	CHECK(active >= 2);
	CHECK(points[6].z < real_t(1.25));
	CHECK(points[6].z > real_t(0.8));
	CHECK(points[6].is_finite());
}

} // namespace TestPhysicsFEMConvexStar
