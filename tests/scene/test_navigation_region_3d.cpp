/**************************************************************************/
/*  test_navigation_region_3d.cpp                                         */
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

TEST_FORCE_LINK(test_navigation_region_3d)

#include "modules/modules_enabled.gen.h" // For navigation 3D.

#ifdef MODULE_NAVIGATION_3D_ENABLED

#include "scene/3d/mesh_instance_3d.h"
#include "scene/3d/navigation/navigation_region_3d.h"
#include "scene/main/scene_tree.h"
#include "scene/main/window.h"
#include "scene/resources/3d/primitive_meshes.h"
#include "servers/navigation_3d/navigation_server_3d.h"

namespace TestNavigationRegion3D {

TEST_SUITE("[Navigation3D]") {
	TEST_CASE("[SceneTree][NavigationRegion3D] New region should have valid RID") {
		NavigationRegion3D *region_node = memnew(NavigationRegion3D);
		CHECK(region_node->get_rid().is_valid());
		memdelete(region_node);
	}

	TEST_CASE("[SceneTree][NavigationRegion3D] Region should bake successfully from valid geometry") {
		Node3D *node_3d = memnew(Node3D);
		SceneTree::get_singleton()->get_root()->add_child(node_3d);
		Ref<NavigationMesh> navigation_mesh = memnew(NavigationMesh);
		NavigationRegion3D *navigation_region = memnew(NavigationRegion3D);
		navigation_region->set_navigation_mesh(navigation_mesh);
		node_3d->add_child(navigation_region);
		Ref<PlaneMesh> plane_mesh = memnew(PlaneMesh);
		plane_mesh->set_size(Size2(10.0, 10.0));
		MeshInstance3D *mesh_instance = memnew(MeshInstance3D);
		mesh_instance->set_mesh(plane_mesh);
		navigation_region->add_child(mesh_instance);

		CHECK_FALSE(navigation_region->is_baking());
		CHECK_EQ(navigation_mesh->get_polygon_count(), 0);
		CHECK_EQ(navigation_mesh->get_vertices().size(), 0);

		SUBCASE("Synchronous bake should have immediate effects") {
			ERR_PRINT_OFF; // Suppress warning about baking from visual meshes as source geometry.
			navigation_region->bake_navigation_mesh(false);
			ERR_PRINT_ON;
			CHECK_FALSE(navigation_region->is_baking());
			CHECK_NE(navigation_mesh->get_polygon_count(), 0);
			CHECK_NE(navigation_mesh->get_vertices().size(), 0);
		}

		memdelete(mesh_instance);
		memdelete(navigation_region);
		memdelete(node_3d);
	}
}


#ifdef DEBUG_ENABLED
TEST_CASE("[NavigationDebugFastPath] empty navigation mesh has no debug surfaces") {
	Ref<NavigationMesh> navmesh;
	navmesh.instantiate();
	Ref<ArrayMesh> debug = navmesh->get_debug_mesh();
	REQUIRE(debug.is_valid());
	CHECK_EQ(debug->get_surface_count(), 0);
}

TEST_CASE("[NavigationDebugFastPath] a triangle produces exactly three face vertices") {
	Ref<NavigationMesh> navmesh;
	navmesh.instantiate();
	const Vector<Vector3> vertices = {
		Vector3(1, 2, 3),
		Vector3(4, 5, 6),
		Vector3(7, 8, 9)
	};
	navmesh->set_vertices(vertices);
	navmesh->add_polygon({ 0, 1, 2 });

	Ref<ArrayMesh> debug = navmesh->get_debug_mesh();
	REQUIRE(debug.is_valid());
	REQUIRE(debug->get_surface_count() >= 1);
	const Array arrays = debug->surface_get_arrays(0);
	const PackedVector3Array faces = arrays[Mesh::ARRAY_VERTEX];
	REQUIRE_EQ(faces.size(), 3);
	for (int i = 0; i < 3; ++i) {
		CHECK_EQ(faces[i], vertices[i]);
	}
	Ref<ArrayMesh> cached = navmesh->get_debug_mesh();
	CHECK_EQ(cached.ptr(), debug.ptr());
}

TEST_CASE("[NavigationDebugFastPath] multiple triangles contain no zero-filled prefix") {
	Ref<NavigationMesh> navmesh;
	navmesh.instantiate();
	const Vector<Vector3> vertices = {
		Vector3(1, 0, 0),
		Vector3(2, 0, 0),
		Vector3(1, 1, 0),
		Vector3(3, 0, 0),
		Vector3(3, 1, 0)
	};
	navmesh->set_vertices(vertices);
	navmesh->add_polygon({ 0, 1, 2 });
	navmesh->add_polygon({ 1, 3, 4 });

	Ref<ArrayMesh> debug = navmesh->get_debug_mesh();
	REQUIRE(debug.is_valid());
	REQUIRE(debug->get_surface_count() >= 1);
	const Array arrays = debug->surface_get_arrays(0);
	const PackedVector3Array faces = arrays[Mesh::ARRAY_VERTEX];
	REQUIRE_EQ(faces.size(), 6);
	const int indices[] = { 0, 1, 2, 1, 3, 4 };
	for (int i = 0; i < 6; ++i) {
		CHECK_EQ(faces[i], vertices[indices[i]]);
	}
	if (NavigationServer3D::get_singleton()->get_debug_navigation_enable_edge_lines()) {
		REQUIRE_EQ(debug->get_surface_count(), 2);
		const Array lines = debug->surface_get_arrays(1);
		const PackedVector3Array edges = lines[Mesh::ARRAY_VERTEX];
		REQUIRE_EQ(edges.size(), 12);
		CHECK_EQ(edges[0], vertices[0]);
		CHECK_EQ(edges[1], vertices[1]);
		CHECK_EQ(edges[2], vertices[1]);
		CHECK_EQ(edges[3], vertices[2]);
		CHECK_EQ(edges[4], vertices[2]);
		CHECK_EQ(edges[5], vertices[0]);
	}
	if (NavigationServer3D::get_singleton()->get_debug_navigation_enable_geometry_face_random_color()) {
		const PackedColorArray colors = arrays[Mesh::ARRAY_COLOR];
		REQUIRE_EQ(colors.size(), 6);
		CHECK_EQ(colors[0], colors[1]);
		CHECK_EQ(colors[1], colors[2]);
		CHECK_EQ(colors[3], colors[4]);
		CHECK_EQ(colors[4], colors[5]);
	}
}
#endif // DEBUG_ENABLED

} // namespace TestNavigationRegion3D

#endif // MODULE_NAVIGATION_3D_ENABLED
