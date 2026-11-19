/**************************************************************************/
/*  test_physics_rigid_convex_aero_facets_3d.cpp                           */
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

#include "servers/physics_rigid_convex_aero_facets_3d.h"
#include "tests/test_macros.h"

#include <limits>

TEST_FORCE_LINK(test_physics_rigid_convex_aero_facets_3d)

namespace TestPhysicsRigidConvexAeroFacets3D {

// Reuse the explicit hull layout expected by the built-in fluid convex
// tests. Construct in place; no mesh builder assumptions or shape server.
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
	for (int i = 0; i < 8; ++i) {
		r_mesh.vertices[i] = vertices[i];
	}
	for (int i = 0; i < 6; ++i) {
		for (int j = 0; j < 4; ++j) {
			r_mesh.faces[i].indices.push_back(faces[i][j]);
		}
	}
}

static void make_tetra_mesh(Geometry3D::MeshData &r_mesh) {
	const Vector3 vertices[4] = {
		Vector3(-1, -1, -1), Vector3(1, -1, -1),
		Vector3(-1, 1, -1), Vector3(-1, -1, 1)
	};
	const int faces[4][3] = {
		{ 0, 1, 2 }, { 0, 3, 1 }, { 0, 2, 3 }, { 1, 3, 2 }
	};
	r_mesh.vertices.resize(4);
	r_mesh.faces.resize(4);
	for (int i = 0; i < 4; ++i) {
		r_mesh.vertices[i] = vertices[i];
	}
	for (int i = 0; i < 4; ++i) {
		for (int j = 0; j < 3; ++j) {
			r_mesh.faces[i].indices.push_back(faces[i][j]);
		}
	}
}

static bool apply(Vector3 &r_linear, Vector3 &r_angular,
		const Geometry3D::MeshData &p_mesh,
		real_t p_pressure = 1.0, real_t p_skin = 0.0,
		real_t p_density = 1.0, real_t p_dt = real_t(0.01),
		const Transform3D &p_transform = Transform3D(),
		const Vector3 &p_com = Vector3(), const Vector3 &p_wind = Vector3(),
		const Basis &p_inverse_inertia = Basis()) {
	return godot_physics_rigid_convex_aero_step_3d(r_linear, r_angular,
			p_mesh, p_transform, p_com, p_wind, p_density, p_pressure,
			p_skin, real_t(1.0), p_inverse_inertia, p_dt);
}

static real_t energy(const Vector3 &p_v, const Vector3 &p_w) {
	return real_t(0.5) * (p_v.length_squared() + p_w.length_squared());
}

TEST_CASE("[PhysicsConvexAero] Four-point box face has true area centroid and outward normal") {
	Geometry3D::MeshData mesh;
	make_box_mesh(mesh);
	GodotPhysicsConvexAeroFacet3D facet;
	CHECK(godot_physics_convex_aero_facet_3d(mesh, mesh.faces[5], Transform3D(), Vector3(), facet));
	CHECK(facet.area == doctest::Approx(4.0));
	CHECK(facet.center.distance_to(Vector3(1, 0, 0)) < real_t(1e-5));
	CHECK(facet.outward_normal.distance_to(Vector3(1, 0, 0)) < real_t(1e-5));
}

TEST_CASE("[PhysicsConvexAero] Reversing polygon winding keeps outward normal and centroid") {
	Geometry3D::MeshData mesh;
	make_box_mesh(mesh);
	GodotPhysicsConvexAeroFacet3D expected, reversed;
	CHECK(godot_physics_convex_aero_facet_3d(mesh, mesh.faces[5], Transform3D(), Vector3(), expected));
	const int temp = mesh.faces[5].indices[1];
	mesh.faces[5].indices[1] = mesh.faces[5].indices[3];
	mesh.faces[5].indices[3] = temp;
	CHECK(godot_physics_convex_aero_facet_3d(mesh, mesh.faces[5], Transform3D(), Vector3(), reversed));
	CHECK(reversed.area == doctest::Approx(expected.area));
	CHECK(reversed.center.distance_to(expected.center) < real_t(1e-5));
	CHECK(reversed.outward_normal.distance_to(expected.outward_normal) < real_t(1e-5));
}

TEST_CASE("[PhysicsConvexAero] Nonuniform scale changes area and centroid exactly") {
	Geometry3D::MeshData mesh;
	make_box_mesh(mesh);
	GodotPhysicsConvexAeroFacet3D facet;
	const Transform3D world(Basis::from_scale(Vector3(2, 3, 4)), Vector3(10, 20, 30));
	CHECK(godot_physics_convex_aero_facet_3d(mesh, mesh.faces[5], world, Vector3(10, 20, 30), facet));
	CHECK(facet.area == doctest::Approx(48.0));
	CHECK(facet.center.distance_to(Vector3(12, 20, 30)) < real_t(1e-5));
	CHECK(facet.outward_normal.distance_to(Vector3(1, 0, 0)) < real_t(1e-5));
}

TEST_CASE("[PhysicsConvexAero] Mirrored affine hull preserves outward face orientation") {
	Geometry3D::MeshData mesh;
	make_box_mesh(mesh);
	GodotPhysicsConvexAeroFacet3D facet;
	const Transform3D world(Basis::from_scale(Vector3(-2, 3, 4)), Vector3());
	CHECK(godot_physics_convex_aero_facet_3d(mesh, mesh.faces[5], world, Vector3(), facet));
	CHECK(facet.area == doctest::Approx(48.0));
	CHECK(facet.center.distance_to(Vector3(-2, 0, 0)) < real_t(1e-5));
	CHECK(facet.outward_normal.distance_to(Vector3(-1, 0, 0)) < real_t(1e-5));
}

TEST_CASE("[PhysicsConvexAero] Default zero coefficients leave velocities unchanged") {
	Geometry3D::MeshData mesh;
	make_box_mesh(mesh);
	Vector3 v(10, 0, 0), w(0, 0, 2);
	CHECK(apply(v, w, mesh, 0, 0));
	CHECK(v == Vector3(10, 0, 0));
	CHECK(w == Vector3(0, 0, 2));
}

TEST_CASE("[PhysicsConvexAero] Axial pressure reduces speed analytically") {
	Geometry3D::MeshData mesh;
	make_box_mesh(mesh);
	Vector3 v(10, 0, 0), w;
	// Only +X panel receives F=-0.5 * rho * Cp * area * v² = -200N.
	CHECK(apply(v, w, mesh));
	CHECK(v.x == doctest::Approx(8.0).epsilon(1e-5));
	CHECK(v.y == doctest::Approx(0.0));
	CHECK(w.length() < real_t(1e-5));
}

TEST_CASE("[PhysicsConvexAero] Reverse motion activates the opposite polygon") {
	Geometry3D::MeshData mesh;
	make_box_mesh(mesh);
	Vector3 v(-10, 0, 0), w;
	CHECK(apply(v, w, mesh));
	CHECK(v.x == doctest::Approx(-8.0).epsilon(1e-5));
	CHECK(w.length() < real_t(1e-5));
}

TEST_CASE("[PhysicsConvexAero] Density doubles uncapped windward pressure") {
	Geometry3D::MeshData mesh;
	make_box_mesh(mesh);
	Vector3 v1(10, 0, 0), v2 = v1, w1, w2;
	CHECK(apply(v1, w1, mesh));
	CHECK(apply(v2, w2, mesh, 1, 0, 2));
	CHECK(v1.x == doctest::Approx(8.0));
	CHECK(v2.x == doctest::Approx(6.0));
}

TEST_CASE("[PhysicsConvexAero] A large timestep clamps impulse before reversal") {
	Geometry3D::MeshData mesh;
	make_box_mesh(mesh);
	Vector3 v(10, 0, 0), w;
	CHECK(apply(v, w, mesh, 1, 0, 1, 10));
	CHECK(v.x >= real_t(-0.00001));
	CHECK(v.x == doctest::Approx(0.0).epsilon(1e-5));
}

TEST_CASE("[PhysicsConvexAero] Matching world wind causes no aerodynamic force") {
	Geometry3D::MeshData mesh;
	make_box_mesh(mesh);
	Vector3 v(4, 2, -5), w;
	CHECK(apply(v, w, mesh, 1, 1, 1, real_t(.1), Transform3D(), Vector3(), v));
	CHECK(v == Vector3(4, 2, -5));
	CHECK(w == Vector3());
}

TEST_CASE("[PhysicsConvexAero] Wind and body translation have Galilean invariance") {
	Geometry3D::MeshData mesh;
	make_box_mesh(mesh);
	Vector3 v(10, 0, 0), moved(13, 2, 5), w, moved_w;
	CHECK(apply(v, w, mesh));
	CHECK(apply(moved, moved_w, mesh, 1, 0, 1, real_t(.01),
			Transform3D(), Vector3(), Vector3(3, 2, 5)));
	CHECK(moved.distance_to(v + Vector3(3, 2, 5)) < real_t(1e-5));
	CHECK(w.distance_to(moved_w) < real_t(1e-5));
}

TEST_CASE("[PhysicsConvexAero] Offset hull center generates rotation") {
	Geometry3D::MeshData mesh;
	make_box_mesh(mesh);
	Vector3 v(10, 0, 0), w;
	const Transform3D world(Basis(), Vector3(0, 1, 0));
	CHECK(apply(v, w, mesh, 1, 0, 1, real_t(.01), world));
	CHECK(v.x < real_t(10.0));
	CHECK(w.z > 0.0);
}

TEST_CASE("[PhysicsConvexAero] Skin drag dissipates spinning convex hull energy") {
	Geometry3D::MeshData mesh;
	make_box_mesh(mesh);
	Vector3 v, w(0, 0, 10);
	const real_t before = energy(v, w);
	CHECK(apply(v, w, mesh, 0, real_t(.1)));
	CHECK(energy(v, w) < before);
	CHECK(Math::abs(w.z) < real_t(10.0));
}

TEST_CASE("[PhysicsConvexAero] Repeated pressure and shear dissipate total rigid energy") {
	Geometry3D::MeshData mesh;
	make_box_mesh(mesh);
	Vector3 v(10, -3, 4), w(1, -2, 5);
	const real_t original = energy(v, w);
	for (int i = 0; i < 30; ++i) {
		const real_t previous = energy(v, w);
		CHECK(apply(v, w, mesh, real_t(.5), real_t(.05)));
		CHECK(energy(v, w) <= previous + real_t(1e-4));
	}
	CHECK(energy(v, w) < original);
}

TEST_CASE("[PhysicsConvexAero] Tetrahedral shape gives finite physically resisting drag") {
	Geometry3D::MeshData mesh;
	make_tetra_mesh(mesh);
	Vector3 v(10, 0, 0), w;
	const real_t before = energy(v, w);
	CHECK(apply(v, w, mesh, real_t(.5), real_t(.05)));
	CHECK(v.is_finite());
	CHECK(w.is_finite());
	CHECK(energy(v, w) < before);
}

TEST_CASE("[PhysicsConvexAero] Invalid late face rejects entire box update transactionally") {
	Geometry3D::MeshData mesh;
	make_box_mesh(mesh);
	mesh.faces[5].indices[0] = 9999;
	Vector3 v(10, 0, 0), w;
	CHECK_FALSE(apply(v, w, mesh));
	CHECK(v == Vector3(10, 0, 0));
	CHECK(w == Vector3());
}

TEST_CASE("[PhysicsConvexAero] Degenerate face rejects without corrupting velocity") {
	Geometry3D::MeshData mesh;
	make_box_mesh(mesh);
	for (int i = 0; i < 4; ++i) {
		mesh.faces[1].indices[i] = 0;
	}
	Vector3 v(10, 0, 0), w;
	CHECK_FALSE(apply(v, w, mesh));
	CHECK(v == Vector3(10, 0, 0));
}

TEST_CASE("[PhysicsConvexAero] Mesh facet count is bounded for adversarial geometry") {
	Geometry3D::MeshData mesh;
	make_box_mesh(mesh);
	mesh.faces.resize(257);
	Vector3 v(10, 0, 0), w;
	CHECK_FALSE(apply(v, w, mesh));
	CHECK(v == Vector3(10, 0, 0));
}

TEST_CASE("[PhysicsConvexAero] Invalid settings and nonfinite wind are atomic") {
	Geometry3D::MeshData mesh;
	make_box_mesh(mesh);
	Vector3 v(10, 0, 0), w;
	const real_t nan = std::numeric_limits<real_t>::quiet_NaN();
	CHECK_FALSE(apply(v, w, mesh, -1));
	CHECK_FALSE(apply(v, w, mesh, 1, -1));
	CHECK_FALSE(apply(v, w, mesh, 1, 0, -1));
	CHECK_FALSE(apply(v, w, mesh, 1, 0, 1, real_t(-.01)));
	CHECK_FALSE(apply(v, w, mesh, 1, 0, 1, real_t(.01),
			Transform3D(), Vector3(), Vector3(nan, 0, 0)));
	CHECK(v == Vector3(10, 0, 0));
	CHECK(w == Vector3());
}

TEST_CASE("[PhysicsConvexAero] Nonuniform stretch computes real 48-square-meter face pressure") {
	Geometry3D::MeshData mesh;
	make_box_mesh(mesh);
	Vector3 v(10, 0, 0), w;
	const Transform3D world(Basis::from_scale(Vector3(2, 3, 4)), Vector3());
	CHECK(apply(v, w, mesh, 1, 0, 1, real_t(.001), world));
	// Area 48 m², F=-2400N; dt=0.001, m=1kg -> v=7.6m/s.
	CHECK(v.x == doctest::Approx(7.6).epsilon(1e-5));
	CHECK(w.length() < real_t(1e-5));
}

TEST_CASE("[PhysicsConvexAero] Center and orientation are invariant to world translation") {
	Geometry3D::MeshData mesh;
	make_box_mesh(mesh);
	GodotPhysicsConvexAeroFacet3D a, b;
	CHECK(godot_physics_convex_aero_facet_3d(mesh, mesh.faces[5], Transform3D(), Vector3(), a));
	const Vector3 shift(100, 200, -300);
	CHECK(godot_physics_convex_aero_facet_3d(mesh, mesh.faces[5],
			Transform3D(Basis(), shift), shift, b));
	CHECK(a.outward_normal.distance_to(b.outward_normal) < real_t(1e-5));
	CHECK(a.area == doctest::Approx(b.area));
	CHECK((a.center + shift).distance_to(b.center) < real_t(1e-5));
}

} // namespace TestPhysicsRigidConvexAeroFacets3D
