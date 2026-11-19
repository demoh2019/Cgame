/**************************************************************************/
/*  test_godot_physics_3d_affine_concave_cull.cpp                          */
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

TEST_FORCE_LINK(test_godot_physics_3d_affine_concave_cull)

#ifdef MODULE_GODOT_PHYSICS_3D_ENABLED

#include "modules/godot_physics_3d/godot_collision_solver_3d.h"
#include "modules/godot_physics_3d/godot_concave_query_3d.h"

namespace TestGodotPhysics3DAffineConcaveCull {

static Transform3D make_sheared_mesh_transform() {
	// Local (x,y,z) maps to world (x+2y,y,z). Its inverse rows, not
	// normalized forward columns, define the three mesh-local AABB axes.
	const Basis mesh_basis(Vector3(1, 0, 0), Vector3(2, 1, 0), Vector3(0, 0, 1));
	return Transform3D(mesh_basis, Vector3(100, -40, 7));
}

TEST_CASE("[GodotPhysics3D] Convex vs mesh affine-local culling bounds") {
	GodotBoxShape3D box;
	box.set_data(Vector3(1, 2, 3));
	const Transform3D mesh_transform = make_sheared_mesh_transform();
	Transform3D box_transform(Basis(Vector3(0, 0, 1), real_t(0.25)), mesh_transform.xform(Vector3(5, 1, 0)));

	AABB local_query;
	CHECK(godot_physics_3d_concave_query_aabb(&box, box_transform, mesh_transform, local_query));

	// The exact local AABB must contain every transformed box corner.
	// A slight test tolerance accommodates float rounding at the extrema.
	const Transform3D relative = mesh_transform.affine_inverse() * box_transform;
	const AABB padded = local_query.grow(real_t(0.0001));
	for (int i = 0; i < 8; i++) {
		const Vector3 corner = box.get_aabb().get_endpoint(i);
		CHECK(padded.has_point(relative.xform(corner)));
	}

	// Margins are specified in world space, not mesh-local space.
	AABB expanded;
	const real_t margin_a = real_t(0.2);
	const real_t margin_b = real_t(0.35);
	CHECK(godot_physics_3d_concave_query_aabb(&box, box_transform, mesh_transform, expanded, margin_a, margin_b));
	const Basis inverse_basis = mesh_transform.basis.inverse();
	for (int i = 0; i < 3; ++i) {
		const real_t expected = (margin_a + margin_b) * inverse_basis[i].length();
		CHECK(Math::is_equal_approx(expanded.position[i], local_query.position[i] - expected));
		CHECK(Math::is_equal_approx(expanded.size[i], local_query.size[i] + expected * 2.0));
	}
}

TEST_CASE("[GodotPhysics3D] Swept world-space hint respects nonorthogonal mesh axes") {
	const Transform3D mesh_transform = make_sheared_mesh_transform();
	GodotSphereShape3D sphere;
	sphere.set_data(real_t(0.25));
	const Transform3D sphere_transform(Basis(), mesh_transform.xform(Vector3(5, 0, 0)));
	const AABB world_hint(sphere_transform.origin - Vector3(0.5, 0.5, 0.5), Vector3(1, 1, 1));

	AABB query;
	CHECK(godot_physics_3d_concave_query_aabb(&sphere, sphere_transform, mesh_transform, query, 0.0, 0.0, &world_hint));
	const Transform3D inverse = mesh_transform.affine_inverse();
	const AABB padded = query.grow(real_t(0.0001));
	for (int i = 0; i < 8; ++i) {
		CHECK(padded.has_point(inverse.xform(world_hint.get_endpoint(i))));
	}
	CHECK(query.has_point(Vector3(5, 0, 0)));

	// The soft-body path supplies only world-space node bounds; it has no
	// convex support shape at this stage of the collision query.
	AABB soft_query;
	CHECK(godot_physics_3d_concave_query_aabb(nullptr, Transform3D(), mesh_transform, soft_query, 0.0, 0.0, &world_hint));
	CHECK(soft_query.is_equal_approx(query));
}

TEST_CASE("[GodotPhysics3D] Singular concave basis falls back to full mesh cull") {
	GodotSphereShape3D sphere;
	sphere.set_data(real_t(1.0));
	Transform3D invalid_mesh;
	invalid_mesh.basis.scale(Vector3(1, 0, 1));
	AABB result;
	CHECK_FALSE(godot_physics_3d_concave_query_aabb(&sphere, Transform3D(), invalid_mesh, result));
}

TEST_CASE("[GodotPhysics3D] Sheared triangle mesh finds the overlapping sphere") {
	// With the former column-projection approximation, a sphere at
	// mesh-local (5,0,0) was erroneously queried near y=2 and the
	// triangle at y=0 could be rejected before reaching SAT/GJK.
	GodotConcavePolygonShape3D mesh;
	PackedVector3Array faces;
	faces.push_back(Vector3(5, -0.4, -0.4));
	faces.push_back(Vector3(5, 0.4, -0.4));
	faces.push_back(Vector3(5, 0, 0.4));
	Dictionary data;
	data["faces"] = faces;
	data["backface_collision"] = true;
	mesh.set_data(data);

	GodotSphereShape3D sphere;
	sphere.set_data(real_t(0.5));
	const Transform3D mesh_transform = make_sheared_mesh_transform();
	const Transform3D sphere_transform(Basis(), mesh_transform.xform(Vector3(5, 0, 0)));
	CHECK(GodotCollisionSolver3D::solve_static(&sphere, sphere_transform, &mesh, mesh_transform, nullptr, nullptr));

	// Translation out of the face plane is disjoint: culling must not
	// turn the conservative AABB into a false positive collision result.
	const Transform3D separated_transform(Basis(), mesh_transform.xform(Vector3(8, 0, 0)));
	CHECK_FALSE(GodotCollisionSolver3D::solve_static(&sphere, separated_transform, &mesh, mesh_transform, nullptr, nullptr));
}

} // namespace TestGodotPhysics3DAffineConcaveCull

#endif // MODULE_GODOT_PHYSICS_3D_ENABLED
