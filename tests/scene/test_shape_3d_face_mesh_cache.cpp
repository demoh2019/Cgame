/**************************************************************************/
/*  test_shape_3d_face_mesh_cache.cpp                                     */
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

TEST_FORCE_LINK(test_shape_3d_face_mesh_cache)

#ifndef PHYSICS_3D_DISABLED

#include "scene/resources/3d/box_shape_3d.h"
#include "scene/resources/3d/sphere_shape_3d.h"
#include "scene/resources/mesh.h"
#include "servers/rendering/rendering_server.h"

namespace TestShape3DFaceMeshCache {

static void check_surface_colors(const Ref<ArrayMesh> &p_mesh, const Color &p_color) {
	REQUIRE(p_mesh.is_valid());
	REQUIRE_EQ(p_mesh->get_surface_count(), 1);
	const Array arrays = p_mesh->surface_get_arrays(0);
	const PackedColorArray colors = arrays[Mesh::ARRAY_COLOR];
	REQUIRE(colors.size() > 0);
	for (int i = 0; i < colors.size(); i++) {
		CHECK_EQ(colors[i], p_color);
	}
}

TEST_CASE("[SceneTree][Shape3D] Box debug face mesh cache preserves color and invalidates geometry") {
	Ref<BoxShape3D> box;
	box.instantiate();
	const Color red(1.0, 0.25, 0.0, 0.8);
	const Color green(0.0, 0.8, 0.5, 1.0);

	const Ref<ArrayMesh> first = box->get_debug_arraymesh_faces(red);
	REQUIRE(first.is_valid());
	CHECK(box->get_debug_arraymesh_faces(red).ptr() == first.ptr());
	check_surface_colors(first, red);

	const Ref<ArrayMesh> changed_color = box->get_debug_arraymesh_faces(green);
	REQUIRE(changed_color.is_valid());
	CHECK(changed_color.ptr() != first.ptr());
	CHECK(box->get_debug_arraymesh_faces(green).ptr() == changed_color.ptr());
	check_surface_colors(changed_color, green);

	box->set_size(Vector3(3.0, 2.0, 5.0));
	const Ref<ArrayMesh> changed_size = box->get_debug_arraymesh_faces(green);
	REQUIRE(changed_size.is_valid());
	CHECK(changed_size.ptr() != changed_color.ptr());
	CHECK(box->get_debug_arraymesh_faces(green).ptr() == changed_size.ptr());
	check_surface_colors(changed_size, green);
}

TEST_CASE("[SceneTree][Shape3D] Sphere debug mesh cache reuses unchanged shape and invalidates radius") {
	Ref<SphereShape3D> sphere;
	sphere.instantiate();
	const Color blue(0.2, 0.4, 1.0, 1.0);
	const Color gray(0.4, 0.4, 0.4, 0.4);

	const Ref<ArrayMesh> first = sphere->get_debug_arraymesh_faces(blue);
	REQUIRE(first.is_valid());
	CHECK(sphere->get_debug_arraymesh_faces(blue).ptr() == first.ptr());
	check_surface_colors(first, blue);

	sphere->set_radius(2.0f);
	const Ref<ArrayMesh> new_radius = sphere->get_debug_arraymesh_faces(blue);
	REQUIRE(new_radius.is_valid());
	CHECK(new_radius.ptr() != first.ptr());
	CHECK(sphere->get_debug_arraymesh_faces(blue).ptr() == new_radius.ptr());
	check_surface_colors(new_radius, blue);

	const Ref<ArrayMesh> new_color = sphere->get_debug_arraymesh_faces(gray);
	REQUIRE(new_color.is_valid());
	CHECK(new_color.ptr() != new_radius.ptr());
	check_surface_colors(new_color, gray);
}

TEST_CASE("[SceneTree][Shape3D] Sphere outline fast path equals trigonometric reference") {
	Ref<SphereShape3D> sphere;
	sphere.instantiate();
	const float radii[] = { 0.0f, 0.5f, 1.75f, 12.0f };
	for (float radius : radii) {
		sphere->set_radius(radius);
		const Vector<Vector3> actual = sphere->get_debug_mesh_lines();
		REQUIRE_EQ(actual.size(), 361 * 6);

		int idx = 0;
		for (int i = 0; i <= 360; i++) {
			const float ra = Math::deg_to_rad((float)i);
			const float rb = Math::deg_to_rad((float)i + 1);
			const Vector2 a = Vector2(Math::sin(ra), Math::cos(ra)) * radius;
			const Vector2 b = Vector2(Math::sin(rb), Math::cos(rb)) * radius;

			CHECK(actual[idx++].is_equal_approx(Vector3(a.x, 0, a.y)));
			CHECK(actual[idx++].is_equal_approx(Vector3(b.x, 0, b.y)));
			CHECK(actual[idx++].is_equal_approx(Vector3(0, a.x, a.y)));
			CHECK(actual[idx++].is_equal_approx(Vector3(0, b.x, b.y)));
			CHECK(actual[idx++].is_equal_approx(Vector3(a.x, a.y, 0)));
			CHECK(actual[idx++].is_equal_approx(Vector3(b.x, b.y, 0)));
		}
		REQUIRE_EQ(idx, actual.size());
	}
}

TEST_CASE("[SceneTree][Shape3D] Box outline fixed buffer preserves all 12 edges") {
	Ref<BoxShape3D> box;
	box.instantiate();
	box->set_size(Vector3(3.0f, 5.0f, 7.0f));
	const Vector<Vector3> actual = box->get_debug_mesh_lines();
	REQUIRE_EQ(actual.size(), 24);

	AABB reference;
	reference.size = box->get_size();
	reference.position = -reference.size / 2;
	for (int edge = 0; edge < 12; edge++) {
		Vector3 a;
		Vector3 b;
		reference.get_edge(edge, a, b);
		CHECK_EQ(actual[edge * 2], a);
		CHECK_EQ(actual[edge * 2 + 1], b);
	}
}

} // namespace TestShape3DFaceMeshCache

#endif // PHYSICS_3D_DISABLED
