/**************************************************************************/
/*  test_triangle_mesh.cpp                                                */
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

TEST_FORCE_LINK(test_triangle_mesh)

#ifndef _3D_DISABLED

#include "core/math/triangle_mesh.h"
#include "scene/resources/3d/primitive_meshes.h"

namespace TestTriangleMesh {

TEST_CASE("[SceneTree][TriangleMesh] BVH creation and intersection") {
	Ref<BoxMesh> box_mesh;
	box_mesh.instantiate();

	const Vector<Face3> faces = box_mesh->get_faces();

	Ref<TriangleMesh> triangle_mesh;
	triangle_mesh.instantiate();
	CHECK(triangle_mesh->create_from_faces(Variant(faces)));

	const Vector3 begin = Vector3(0.0, 2.0, 0.0);
	const Vector3 end = Vector3(0.0, -2.0, 0.0);

	{
		Vector3 point;
		Vector3 normal;
		int32_t *surf_index = nullptr;
		int32_t face_index = -1;
		const bool has_result = triangle_mesh->intersect_segment(begin, end, point, normal, surf_index, &face_index);
		CHECK(has_result);
		CHECK(point.is_equal_approx(Vector3(0.0, 0.5, 0.0)));
		CHECK(normal.is_equal_approx(Vector3(0.0, 1.0, 0.0)));
		CHECK(surf_index == nullptr);
		REQUIRE(face_index != -1);
		CHECK(face_index == 8);
	}

	{
		Vector3 dir = begin.direction_to(end);
		Vector3 point;
		Vector3 normal;
		int32_t *surf_index = nullptr;
		int32_t face_index = -1;
		const bool has_result = triangle_mesh->intersect_ray(begin, dir, point, normal, surf_index, &face_index);
		CHECK(has_result);
		CHECK(point.is_equal_approx(Vector3(0.0, 0.5, 0.0)));
		CHECK(normal.is_equal_approx(Vector3(0.0, 1.0, 0.0)));
		CHECK(surf_index == nullptr);
		REQUIRE(face_index != -1);
		CHECK(face_index == 8);
	}
}


TEST_CASE("[TriangleMesh][Performance] Compact BVH allocation and topology") {
	// Exercise odd, even, singleton, and multi-level BVH trees. Every face is
	// a disjoint triangle in the XY plane, so ray hits identify their leaf.
	const int face_counts[] = { 1, 2, 3, 4, 5, 16, 31, 64, 128, 257 };
	for (int face_count : face_counts) {
		Vector<Vector3> faces;
		faces.resize(face_count * 3);
		Vector3 *vertices = faces.ptrw();
		Vector<int32_t> surfaces;
		surfaces.resize(face_count * 3);
		int32_t *surface_ids = surfaces.ptrw();
		for (int i = 0; i < face_count; i++) {
			const real_t x = real_t(i * 2);
			vertices[3 * i] = Vector3(x, 0, 0);
			vertices[3 * i + 1] = Vector3(x + 1, 0, 0);
			vertices[3 * i + 2] = Vector3(x, 1, 0);
			for (int j = 0; j < 3; j++) {
				surface_ids[3 * i + j] = i % 7;
			}
		}

		Ref<TriangleMesh> mesh;
		mesh.instantiate();
		mesh->create(faces, surfaces);
		REQUIRE(mesh->is_valid());
		REQUIRE(mesh->get_triangles().size() == face_count);
		const Vector<TriangleMesh::BVH> &nodes = mesh->get_bvh();
		REQUIRE(nodes.size() == 2 * face_count - 1);

		Vector<int> face_visits;
		face_visits.resize(face_count);
		for (int i = 0; i < face_count; i++) {
			face_visits.write[i] = 0;
		}
		int leaf_count = 0;
		int inner_count = 0;
		for (int node_index = 0; node_index < nodes.size(); node_index++) {
			const TriangleMesh::BVH &node = nodes[node_index];
			if (node.face_index >= 0) {
				CHECK(node.face_index < face_count);
				REQUIRE(node.face_index < face_count);
				face_visits.write[node.face_index]++;
				leaf_count++;
			} else {
				CHECK(node.left >= 0);
				CHECK(node.right >= 0);
				CHECK(node.left < node_index);
				CHECK(node.right < node_index);
				inner_count++;
			}
		}
		CHECK(leaf_count == face_count);
		CHECK(inner_count == face_count - 1);
		for (int i = 0; i < face_count; i++) {
			CHECK(face_visits[i] == 1);
		}

		// Each ray intersects exactly one triangle, including near the
		// partition boundaries for highly unbalanced face counts.
		for (int i = 0; i < face_count; i++) {
			const Vector3 origin(real_t(i * 2) + real_t(0.25), real_t(0.25), 2);
			const Vector3 hit(real_t(i * 2) + real_t(0.25), real_t(0.25), 0);
			Vector3 point;
			Vector3 normal;
			int32_t surface_index = -1;
			int32_t face_index = -1;
			CHECK(mesh->intersect_ray(origin, Vector3(0, 0, -1), point, normal, &surface_index, &face_index));
			CHECK(point.is_equal_approx(hit));
			CHECK(face_index == i);
			CHECK(surface_index == i % 7);
		}
	}
}


TEST_CASE("[SceneTree][TriangleMesh][Performance] Convex containment reuses transformed BVH bounds") {
	Ref<BoxMesh> box_mesh;
	box_mesh.instantiate();
	const Vector<Face3> faces = box_mesh->get_faces();
	Ref<TriangleMesh> mesh;
	mesh.instantiate();
	REQUIRE(mesh->create_from_faces(Variant(faces)));
	REQUIRE(mesh->get_bvh().size() > 1);

	// The planes enclose a 2x2x2 axis-aligned box with outward normals.
	// All eight points are supplied because the convex-intersection test
	// also uses the actual hull vertices.
	const Plane planes[] = {
		Plane(Vector3(1, 0, 0), 1),
		Plane(Vector3(-1, 0, 0), 1),
		Plane(Vector3(0, 1, 0), 1),
		Plane(Vector3(0, -1, 0), 1),
		Plane(Vector3(0, 0, 1), 1),
		Plane(Vector3(0, 0, -1), 1),
	};
	Vector3 hull[8];
	for (int i = 0; i < 8; i++) {
		hull[i] = Vector3((i & 1) ? 1 : -1, (i & 2) ? 1 : -1, (i & 4) ? 1 : -1);
	}

	const Vector3 inside_scales[] = {
		Vector3(1, 1, 1),
		Vector3(0.5, 0.5, 0.5),
		Vector3(0.1, 0.5, 1.5),
		Vector3(-1, 1, 1),
		Vector3(-0.3, -0.5, -1.5),
	};
	for (const Vector3 &scale : inside_scales) {
		CHECK(mesh->inside_convex_shape(planes, 6, hull, 8, scale));
	}

	const Vector3 outside_scales[] = {
		Vector3(3, 3, 3),
		Vector3(1, 3, 1),
		Vector3(-3, 1, 1),
		Vector3(1, 1, -3),
	};
	for (const Vector3 &scale : outside_scales) {
		CHECK_FALSE(mesh->inside_convex_shape(planes, 6, hull, 8, scale));
	}

	// Test a one-face mesh as well: this visits only the BVH root and
	// should behave identically to a full multi-level tree.
	Vector<Vector3> triangle = {
		Vector3(-0.2, -0.2, 0),
		Vector3(0.2, -0.2, 0),
		Vector3(0, 0.2, 0),
	};
	Ref<TriangleMesh> single;
	single.instantiate();
	single->create(triangle);
	REQUIRE(single->is_valid());
	CHECK(single->inside_convex_shape(planes, 6, hull, 8));
	CHECK_FALSE(single->inside_convex_shape(planes, 6, hull, 8, Vector3(10, 10, 10)));
}


TEST_CASE("[TriangleMesh][Regression] Compact BVH references nodes by index and preserves surface IDs") {
	// Each face stores the same surface ID for all three of its vertices.
	// Verify that the ID is read at face * 3, not face, while the BVH's
	// leaves and internal nodes reference actual compact node indices.
	const int face_count = 37;
	Vector<Vector3> faces;
	Vector<int32_t> metadata;
	REQUIRE(faces.resize_uninitialized(face_count * 3) == OK);
	REQUIRE(metadata.resize_uninitialized(face_count * 3) == OK);
	Vector3 *const points = faces.ptrw();
	int32_t *const surface = metadata.ptrw();
	for (int i = 0; i < face_count; i++) {
		const real_t x = real_t(i * 3);
		points[i * 3] = Vector3(x, 0, 0);
		points[i * 3 + 1] = Vector3(x + 1, 0, 0);
		points[i * 3 + 2] = Vector3(x, 1, 0);
		for (int vertex = 0; vertex < 3; vertex++) {
			surface[i * 3 + vertex] = (i * 5 + 3) % 11;
		}
	}
	Ref<TriangleMesh> mesh;
	mesh.instantiate();
	mesh->create(faces, metadata);
	REQUIRE(mesh->is_valid());
	REQUIRE(mesh->get_triangles().size() == face_count);
	REQUIRE(mesh->get_bvh().size() == 2 * face_count - 1);
	for (int i = 0; i < face_count; i++) {
		CHECK(mesh->get_triangles()[i].surface_index == (i * 5 + 3) % 11);
		Vector3 hit_position;
		Vector3 hit_normal;
		int32_t hit_surface = -1;
		int32_t hit_face = -1;
		const Vector3 origin(real_t(i * 3) + real_t(0.25), real_t(0.25), 10);
		REQUIRE(mesh->intersect_ray(origin, Vector3(0, 0, -1), hit_position, hit_normal, &hit_surface, &hit_face));
		CHECK(hit_face == i);
		CHECK(hit_surface == (i * 5 + 3) % 11);
		CHECK(hit_position.is_equal_approx(Vector3(origin.x, origin.y, 0)));
	}
}

} // namespace TestTriangleMesh

#endif // _3D_DISABLED
