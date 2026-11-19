/**************************************************************************/
/*  test_physics_fem_explicit_tetra.cpp                                   */
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

#include "servers/physics_fem_explicit_tetra.h"
#include "servers/physics_fem_lumped_mass.h"
#include "tests/test_macros.h"

#include <initializer_list>
#include <utility>

TEST_FORCE_LINK(test_physics_fem_explicit_tetra)

namespace TestPhysicsFEMExplicitTetra {

static void make_concave(LocalVector<Vector3> &r_positions,
		LocalVector<PhysicsFEMConvexFace> &r_faces,
		LocalVector<uint32_t> &r_indices) {
	r_positions.reset();
	r_faces.reset();
	r_indices.reset();
	// Two actual nonoverlapping tetrahedra share face (0,1,2).
	// Vertex 4 protrudes outside the upper tetra projection, making
	// the union nonconvex; a fan from vertex 0 must NOT be used.
	for (const Vector3 &p : {
			Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0),
			Vector3(0, 0, 1), Vector3(real_t(0.6), real_t(0.8), real_t(-0.25)) }) {
		r_positions.push_back(p);
	}
	for (const PhysicsFEMConvexFace &face : {
			PhysicsFEMConvexFace{ 1, 2, 3 }, PhysicsFEMConvexFace{ 0, 3, 2 },
			PhysicsFEMConvexFace{ 0, 1, 3 }, PhysicsFEMConvexFace{ 2, 1, 4 },
			PhysicsFEMConvexFace{ 0, 4, 1 }, PhysicsFEMConvexFace{ 0, 2, 4 } }) {
		r_faces.push_back(face);
	}
	for (uint32_t index : { 0u, 1u, 2u, 3u, 0u, 2u, 1u, 4u }) {
		r_indices.push_back(index);
	}
}

TEST_CASE("[PhysicsFEMExplicit] Concave five-vertex shell cooks two real tets") {
	LocalVector<Vector3> positions;
	LocalVector<PhysicsFEMConvexFace> faces;
	LocalVector<uint32_t> indices;
	make_concave(positions, faces, indices);
	LocalVector<PhysicsFEMConvexTetra> cooked;
	const double volume = 1.25 / 6.0;
	CHECK_FALSE(physics_fem_build_convex_star_tetrahedra(positions, faces, volume, cooked));
	CHECK(physics_fem_build_explicit_tetrahedra(positions, faces, indices, volume, cooked));
	REQUIRE(cooked.size() == 2);
	CHECK(cooked[0].rest.signed_det > 0.0);
	CHECK(cooked[1].rest.signed_det > 0.0);
	CHECK(cooked[0].rest.volume + cooked[1].rest.volume == doctest::Approx(volume));
}

TEST_CASE("[PhysicsFEMExplicit] Mixed input tetra winding is automatically normalized") {
	LocalVector<Vector3> positions;
	LocalVector<PhysicsFEMConvexFace> faces;
	LocalVector<uint32_t> indices;
	make_concave(positions, faces, indices);
	std::swap(indices[1], indices[2]);
	LocalVector<PhysicsFEMConvexTetra> cooked;
	REQUIRE(physics_fem_build_explicit_tetrahedra(positions, faces, indices, 1.25 / 6.0, cooked));
	REQUIRE(cooked.size() == 2);
	CHECK(cooked[0].rest.signed_det > 0.0);
	CHECK(cooked[1].rest.signed_det > 0.0);
}

TEST_CASE("[PhysicsFEMExplicit] Inward-oriented shell is also supported") {
	LocalVector<Vector3> positions;
	LocalVector<PhysicsFEMConvexFace> faces;
	LocalVector<uint32_t> indices;
	make_concave(positions, faces, indices);
	for (PhysicsFEMConvexFace &face : faces) {
		std::swap(face.b, face.c);
	}
	LocalVector<PhysicsFEMConvexTetra> cooked;
	CHECK(physics_fem_build_explicit_tetrahedra(positions, faces, indices, -1.25 / 6.0, cooked));
	CHECK(cooked.size() == 2);
}

TEST_CASE("[PhysicsFEMExplicit] Tet solver handles imported concave assembly") {
	LocalVector<Vector3> positions;
	LocalVector<PhysicsFEMConvexFace> faces;
	LocalVector<uint32_t> indices;
	make_concave(positions, faces, indices);
	LocalVector<PhysicsFEMConvexTetra> cooked;
	REQUIRE(physics_fem_build_explicit_tetrahedra(positions, faces, indices, 1.25 / 6.0, cooked));
	positions[4].z -= real_t(0.15);
	double energy = 0.0;
	Vector3 ga, gb, gc, gd;
	CHECK(physics_fem_tetra_energy_gradient(
			positions[0], positions[2], positions[1], positions[4],
			cooked[1].rest, 0.3, energy, ga, gb, gc, gd));
	CHECK(energy > 0.0);
	double lambda = 0.0;
	CHECK(physics_fem_tetra_solve(
			positions[cooked[1].a], positions[cooked[1].b],
			positions[cooked[1].c], positions[cooked[1].d],
			0.0, 0.0, 0.0, 1.0, cooked[1].rest, 0.3, 0.0, lambda));
	CHECK(positions[4].is_finite());
}

TEST_CASE("[PhysicsFEMExplicit] Missing boundary face preserves old output") {
	LocalVector<Vector3> positions;
	LocalVector<PhysicsFEMConvexFace> faces;
	LocalVector<uint32_t> indices;
	make_concave(positions, faces, indices);
	LocalVector<PhysicsFEMConvexTetra> cooked;
	REQUIRE(physics_fem_build_explicit_tetrahedra(positions, faces, indices, 1.25 / 6.0, cooked));
	faces.remove_at(0);
	CHECK_FALSE(physics_fem_build_explicit_tetrahedra(positions, faces, indices, 1.25 / 6.0, cooked));
	CHECK(cooked.size() == 2);
}

TEST_CASE("[PhysicsFEMExplicit] Reversed boundary triangle and wrong volume are rejected") {
	LocalVector<Vector3> positions;
	LocalVector<PhysicsFEMConvexFace> faces;
	LocalVector<uint32_t> indices;
	make_concave(positions, faces, indices);
	LocalVector<PhysicsFEMConvexTetra> cooked;
	std::swap(faces[0].b, faces[0].c);
	CHECK_FALSE(physics_fem_build_explicit_tetrahedra(positions, faces, indices, 1.25 / 6.0, cooked));
	std::swap(faces[0].b, faces[0].c);
	CHECK_FALSE(physics_fem_build_explicit_tetrahedra(positions, faces, indices, 0.5, cooked));
	CHECK(cooked.is_empty());
}

TEST_CASE("[PhysicsFEMExplicit] Invalid tetra topology rejects without touching result") {
	LocalVector<Vector3> positions;
	LocalVector<PhysicsFEMConvexFace> faces;
	LocalVector<uint32_t> indices;
	make_concave(positions, faces, indices);
	LocalVector<PhysicsFEMConvexTetra> cooked;
	REQUIRE(physics_fem_build_explicit_tetrahedra(positions, faces, indices, 1.25 / 6.0, cooked));
	indices[7] = 5000;
	CHECK_FALSE(physics_fem_build_explicit_tetrahedra(positions, faces, indices, 1.25 / 6.0, cooked));
	indices[7] = 4;
	indices[0] = indices[1];
	CHECK_FALSE(physics_fem_build_explicit_tetrahedra(positions, faces, indices, 1.25 / 6.0, cooked));
	CHECK(cooked.size() == 2);
}

TEST_CASE("[PhysicsFEMExplicit] Duplicate and non-manifold tet volume are rejected") {
	LocalVector<Vector3> positions;
	LocalVector<PhysicsFEMConvexFace> faces;
	LocalVector<uint32_t> indices;
	make_concave(positions, faces, indices);
	const uint32_t original_count = indices.size();
	for (uint32_t i = 0; i < original_count; ++i) {
		indices.push_back(indices[i]);
	}
	LocalVector<PhysicsFEMConvexTetra> cooked;
	CHECK_FALSE(physics_fem_build_explicit_tetrahedra(positions, faces, indices, 2.5 / 6.0, cooked));
}


static void make_interior_cube(LocalVector<Vector3> &r_positions,
		LocalVector<PhysicsFEMConvexFace> &r_faces,
		LocalVector<uint32_t> &r_indices) {
	r_positions.reset();
	r_faces.reset();
	r_indices.reset();
	const Vector3 points[] = {
		Vector3(-1, -1, -1), Vector3(1, -1, -1),
		Vector3(1, 1, -1), Vector3(-1, 1, -1),
		Vector3(-1, -1, 1), Vector3(1, -1, 1),
		Vector3(1, 1, 1), Vector3(-1, 1, 1),
		Vector3(0, 0, 0) // Internal simulation node, not a surface vertex.
	};
	const PhysicsFEMConvexFace triangles[] = {
		{ 0, 2, 1 }, { 0, 3, 2 }, { 4, 5, 6 }, { 4, 6, 7 },
		{ 0, 1, 5 }, { 0, 5, 4 }, { 3, 7, 6 }, { 3, 6, 2 },
		{ 0, 4, 7 }, { 0, 7, 3 }, { 1, 2, 6 }, { 1, 6, 5 }
	};
	for (const Vector3 &p : points) {
		r_positions.push_back(p);
	}
	for (const PhysicsFEMConvexFace &tri : triangles) {
		r_faces.push_back(tri);
		r_indices.push_back(8);
		r_indices.push_back(tri.a);
		r_indices.push_back(tri.b);
		r_indices.push_back(tri.c);
	}
}

TEST_CASE("[PhysicsFEMExplicit] Interior vertex creates 12 non-overlapping cube tetrahedra") {
	LocalVector<Vector3> points;
	LocalVector<PhysicsFEMConvexFace> faces;
	LocalVector<uint32_t> indices;
	make_interior_cube(points, faces, indices);
	LocalVector<PhysicsFEMConvexTetra> cooked;
	REQUIRE(physics_fem_build_explicit_tetrahedra(points, faces, indices, 8.0, cooked));
	REQUIRE(cooked.size() == 12);
	double volume = 0.0;
	for (const PhysicsFEMConvexTetra &tetra : cooked) {
		CHECK(tetra.a == 8);
		CHECK(tetra.rest.signed_det > 0.0);
		volume += tetra.rest.volume;
	}
	CHECK(volume == doctest::Approx(8.0).epsilon(1e-6));
}

TEST_CASE("[PhysicsFEMExplicit] Interior node receives exactly one-quarter of volume-lumped mass") {
	LocalVector<Vector3> points;
	LocalVector<PhysicsFEMConvexFace> faces;
	LocalVector<uint32_t> indices;
	make_interior_cube(points, faces, indices);
	LocalVector<PhysicsFEMConvexTetra> cooked;
	REQUIRE(physics_fem_build_explicit_tetrahedra(points, faces, indices, 8.0, cooked));
	LocalVector<double> fractions;
	LocalVector<real_t> inverse_masses;
	REQUIRE(physics_fem_build_lumped_masses(
			points.size(), cooked, real_t(12.0), fractions, inverse_masses));
	REQUIRE(fractions.size() == 9);
	CHECK(fractions[8] == doctest::Approx(0.25).epsilon(1e-6));
	CHECK(inverse_masses[8] == doctest::Approx(1.0 / 3.0).epsilon(1e-6));
	double total_mass = 0.0;
	for (uint32_t i = 0; i < fractions.size(); ++i) {
		total_mass += 1.0 / double(inverse_masses[i]);
	}
	CHECK(total_mass == doctest::Approx(12.0).epsilon(1e-6));
}

TEST_CASE("[PhysicsFEMExplicit] Interior node outside the volume rejects the FEM cook") {
	LocalVector<Vector3> points;
	LocalVector<PhysicsFEMConvexFace> faces;
	LocalVector<uint32_t> indices;
	make_interior_cube(points, faces, indices);
	LocalVector<PhysicsFEMConvexTetra> cooked;
	REQUIRE(physics_fem_build_explicit_tetrahedra(points, faces, indices, 8.0, cooked));
	points[8] = Vector3(3, 3, 3); // Produces overlapping/inverted tet volumes.
	CHECK_FALSE(physics_fem_build_explicit_tetrahedra(points, faces, indices, 8.0, cooked));
	CHECK(cooked.size() == 12);
}

TEST_CASE("[PhysicsFEMExplicit] Degenerate internal node on the surface rejects FEM") {
	LocalVector<Vector3> points;
	LocalVector<PhysicsFEMConvexFace> faces;
	LocalVector<uint32_t> indices;
	make_interior_cube(points, faces, indices);
	points[8] = Vector3(-1, -1, -1);
	LocalVector<PhysicsFEMConvexTetra> cooked;
	CHECK_FALSE(physics_fem_build_explicit_tetrahedra(points, faces, indices, 8.0, cooked));
	CHECK(cooked.is_empty());
}

} // namespace TestPhysicsFEMExplicitTetra
