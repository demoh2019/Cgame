/**************************************************************************/
/*  test_geometry_3d.cpp                                                  */
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

TEST_FORCE_LINK(test_geometry_3d)

#include "core/math/geometry_3d.h"

namespace TestGeometry3D {

TEST_CASE("[Geometry3D] Closest Points Between Segments") {
	Vector3 ps, qt;
	Geometry3D::get_closest_points_between_segments(Vector3(1, -1, 1), Vector3(1, 1, -1), Vector3(-1, -2, -1), Vector3(-1, 1, 1), ps, qt);
	CHECK(ps.is_equal_approx(Vector3(1, -0.2, 0.2)));
	CHECK(qt.is_equal_approx(Vector3(-1, -0.2, 0.2)));
}

TEST_CASE("[Geometry3D] Closest Distance Between Segments") {
	CHECK(Geometry3D::get_closest_distance_between_segments(Vector3(1, -2, 0), Vector3(1, 2, 0), Vector3(-1, 2, 0), Vector3(-1, -2, 0)) == 2.0f);
}

TEST_CASE("[Geometry3D] Build Box Planes") {
	constexpr Vector3 extents = Vector3(5, 5, 20);
	Vector<Plane> box = Geometry3D::build_box_planes(extents);
	CHECK(box.size() == 6);
	CHECK(extents.x == box[0].d);
	CHECK(box[0].normal == Vector3(1, 0, 0));
	CHECK(extents.x == box[1].d);
	CHECK(box[1].normal == Vector3(-1, 0, 0));
	CHECK(extents.y == box[2].d);
	CHECK(box[2].normal == Vector3(0, 1, 0));
	CHECK(extents.y == box[3].d);
	CHECK(box[3].normal == Vector3(0, -1, 0));
	CHECK(extents.z == box[4].d);
	CHECK(box[4].normal == Vector3(0, 0, 1));
	CHECK(extents.z == box[5].d);
	CHECK(box[5].normal == Vector3(0, 0, -1));
}

TEST_CASE("[Geometry3D] Build Capsule Planes") {
	Vector<Plane> capsule = Geometry3D::build_capsule_planes(10, 20, 6, 10);
	CHECK(capsule.size() == 126);
}

TEST_CASE("[Geometry3D] Build Cylinder Planes") {
	Vector<Plane> planes = Geometry3D::build_cylinder_planes(3.0f, 10.0f, 10);
	CHECK(planes.size() == 12);
}

TEST_CASE("[Geometry3D] Build Sphere Planes") {
	Vector<Plane> planes = Geometry3D::build_sphere_planes(10.0f, 10, 3);
	CHECK(planes.size() == 63);
}

#if false
// This test has been temporarily disabled because it's really fragile and
// breaks if calculations change very slightly. For example, it breaks when
// using doubles, and it breaks when making Plane calculations more accurate.
TEST_CASE("[Geometry3D] Build Convex Mesh") {
	struct Case {
		Vector<Plane> object;
		int want_faces, want_edges, want_vertices;
		Case(){};
		Case(Vector<Plane> p_object, int p_want_faces, int p_want_edges, int p_want_vertices) :
				object(p_object), want_faces(p_want_faces), want_edges(p_want_edges), want_vertices(p_want_vertices){};
	};
	Vector<Case> tt;
	tt.push_back(Case(Geometry3D::build_box_planes(Vector3(5, 10, 5)), 6, 12, 8));
	tt.push_back(Case(Geometry3D::build_capsule_planes(5, 5, 20, 20, Vector3::Axis()), 820, 7603, 6243));
	tt.push_back(Case(Geometry3D::build_cylinder_planes(5, 5, 20, Vector3::Axis()), 22, 100, 80));
	tt.push_back(Case(Geometry3D::build_sphere_planes(5, 5, 20), 220, 1011, 522));
	for (int i = 0; i < tt.size(); ++i) {
		Case current_case = tt[i];
		Geometry3D::MeshData mesh = Geometry3D::build_convex_mesh(current_case.object);
		CHECK(mesh.faces.size() == current_case.want_faces);
		CHECK(mesh.edges.size() == current_case.want_edges);
		CHECK(mesh.vertices.size() == current_case.want_vertices);
	}
}
#endif

TEST_CASE("[Geometry3D] Clip Polygon") {
	Vector<Plane> box_planes = Geometry3D::build_box_planes(Vector3(5, 10, 5));
	Vector<Vector3> box = Geometry3D::compute_convex_mesh_points(&box_planes[0], box_planes.size());
	Vector<Vector3> output = Geometry3D::clip_polygon(box, Plane());
	CHECK(output == box);
	output = Geometry3D::clip_polygon(box, Plane(Vector3(0, 1, 0), Vector3(0, 3, 0)));
	CHECK(output != box);
}

TEST_CASE("[Geometry3D] Compute Convex Mesh Points") {
	Vector<Vector3> cube;
	cube.push_back(Vector3(-5, -5, -5));
	cube.push_back(Vector3(5, -5, -5));
	cube.push_back(Vector3(-5, 5, -5));
	cube.push_back(Vector3(5, 5, -5));
	cube.push_back(Vector3(-5, -5, 5));
	cube.push_back(Vector3(5, -5, 5));
	cube.push_back(Vector3(-5, 5, 5));
	cube.push_back(Vector3(5, 5, 5));
	Vector<Plane> box_planes = Geometry3D::build_box_planes(Vector3(5, 5, 5));
	CHECK(Geometry3D::compute_convex_mesh_points(&box_planes[0], box_planes.size()) == cube);
}

TEST_CASE("[Geometry3D] Get Closest Point To Segment") {
	constexpr Vector3 a = Vector3(1, 1, 1);
	constexpr Vector3 b = Vector3(5, 5, 5);
	Vector3 output = Geometry3D::get_closest_point_to_segment(Vector3(2, 1, 4), a, b);
	CHECK(output.is_equal_approx(Vector3(2.33333, 2.33333, 2.33333)));
}

TEST_CASE("[Geometry3D] Plane and Box Overlap") {
	CHECK(Geometry3D::planeBoxOverlap(Vector3(3, 4, 2), 5.0f, Vector3(5, 5, 5)) == true);
	CHECK(Geometry3D::planeBoxOverlap(Vector3(0, 1, 0), -10.0f, Vector3(5, 5, 5)) == false);
	CHECK(Geometry3D::planeBoxOverlap(Vector3(1, 0, 0), -6.0f, Vector3(5, 5, 5)) == false);
}

TEST_CASE("[Geometry3D] Is Point in Projected Triangle") {
	CHECK(Geometry3D::point_in_projected_triangle(Vector3(1, 1, 0), Vector3(3, 0, 0), Vector3(0, 3, 0), Vector3(-3, 0, 0)) == true);
	CHECK(Geometry3D::point_in_projected_triangle(Vector3(5, 1, 0), Vector3(3, 0, 0), Vector3(0, 3, 0), Vector3(-3, 0, 0)) == false);
	CHECK(Geometry3D::point_in_projected_triangle(Vector3(3, 0, 0), Vector3(3, 0, 0), Vector3(0, 3, 0), Vector3(-3, 0, 0)) == true);
}

TEST_CASE("[Geometry3D] Does Ray Intersect Triangle") {
	Vector3 result;
	CHECK(Geometry3D::ray_intersects_triangle(Vector3(0, 1, 1), Vector3(0, 0, -10), Vector3(0, 3, 0), Vector3(-3, 0, 0), Vector3(3, 0, 0), &result) == true);
	CHECK(Geometry3D::ray_intersects_triangle(Vector3(5, 10, 1), Vector3(0, 0, -10), Vector3(0, 3, 0), Vector3(-3, 0, 0), Vector3(3, 0, 0), &result) == false);
	CHECK(Geometry3D::ray_intersects_triangle(Vector3(0, 1, 1), Vector3(0, 0, 10), Vector3(0, 3, 0), Vector3(-3, 0, 0), Vector3(3, 0, 0), &result) == false);
}

TEST_CASE("[Geometry3D] Does Segment Intersect Convex") {
	Vector<Plane> box_planes = Geometry3D::build_box_planes(Vector3(5, 5, 5));
	Vector3 result, normal;
	CHECK(Geometry3D::segment_intersects_convex(Vector3(10, 10, 10), Vector3(0, 0, 0), &box_planes[0], box_planes.size(), &result, &normal) == true);
	CHECK(Geometry3D::segment_intersects_convex(Vector3(10, 10, 10), Vector3(5, 5, 5), &box_planes[0], box_planes.size(), &result, &normal) == true);
	CHECK(Geometry3D::segment_intersects_convex(Vector3(10, 10, 10), Vector3(6, 5, 5), &box_planes[0], box_planes.size(), &result, &normal) == false);
	CHECK(Geometry3D::segment_intersects_convex(Vector3(10, 10, 0), Vector3(10, 0, 0), &box_planes[0], box_planes.size(), &result, &normal) == false);
}

TEST_CASE("[Geometry3D] Segment Intersects Cylinder") {
	Vector3 result, normal;
	CHECK(Geometry3D::segment_intersects_cylinder(Vector3(10, 10, 10), Vector3(0, 0, 0), 5, 5, &result, &normal) == true);
	CHECK(Geometry3D::segment_intersects_cylinder(Vector3(10, 10, 10), Vector3(6, 6, 6), 5, 5, &result, &normal) == false);
}

TEST_CASE("[Geometry3D] Segment Intersects Cylinder") {
	Vector3 result, normal;
	CHECK(Geometry3D::segment_intersects_sphere(Vector3(10, 10, 10), Vector3(0, 0, 0), Vector3(0, 0, 0), 5, &result, &normal) == true);
	CHECK(Geometry3D::segment_intersects_sphere(Vector3(10, 10, 10), Vector3(0, 0, 2.5), Vector3(0, 0, 0), 5, &result, &normal) == true);
	CHECK(Geometry3D::segment_intersects_sphere(Vector3(10, 10, 10), Vector3(5, 5, 5), Vector3(0, 0, 0), 5, &result, &normal) == false);
}

TEST_CASE("[Geometry3D] Segment Intersects Triangle") {
	Vector3 result;
	CHECK(Geometry3D::segment_intersects_triangle(Vector3(1, 1, 1), Vector3(-1, -1, -1), Vector3(-3, 0, 0), Vector3(0, 3, 0), Vector3(3, 0, 0), &result) == true);
	CHECK(Geometry3D::segment_intersects_triangle(Vector3(1, 1, 1), Vector3(3, 0, 0), Vector3(-3, 0, 0), Vector3(0, 3, 0), Vector3(3, 0, 0), &result) == true);
	CHECK(Geometry3D::segment_intersects_triangle(Vector3(1, 1, 1), Vector3(10, -1, -1), Vector3(-3, 0, 0), Vector3(0, 3, 0), Vector3(3, 0, 0), &result) == false);
}

TEST_CASE("[Geometry3D] Triangle and Box Overlap") {
	constexpr Vector3 good_triangle[3] = { Vector3(3, 2, 3), Vector3(2, 2, 1), Vector3(2, 1, 1) };
	CHECK(Geometry3D::triangle_box_overlap(Vector3(0, 0, 0), Vector3(5, 5, 5), good_triangle) == true);
	constexpr Vector3 bad_triangle[3] = { Vector3(100, 100, 100), Vector3(-100, -100, -100), Vector3(10, 10, 10) };
	CHECK(Geometry3D::triangle_box_overlap(Vector3(1000, 1000, 1000), Vector3(1, 1, 1), bad_triangle) == false);
}

TEST_CASE("[Geometry3D] Triangle and Sphere Intersect") {
	constexpr Vector3 triangle_a = Vector3(3, 0, 0);
	constexpr Vector3 triangle_b = Vector3(-3, 0, 0);
	constexpr Vector3 triangle_c = Vector3(0, 3, 0);
	Vector3 triangle_contact, sphere_contact;
	CHECK(Geometry3D::triangle_sphere_intersection_test(triangle_a, triangle_b, triangle_c, Vector3(0, -1, 0), Vector3(0, 0, 0), 5, triangle_contact, sphere_contact) == true);
	CHECK(Geometry3D::triangle_sphere_intersection_test(triangle_a, triangle_b, triangle_c, Vector3(0, 1, 0), Vector3(0, 0, 0), 5, triangle_contact, sphere_contact) == true);
	CHECK(Geometry3D::triangle_sphere_intersection_test(triangle_a, triangle_b, triangle_c, Vector3(0, 1, 0), Vector3(20, 0, 0), 5, triangle_contact, sphere_contact) == false);
}

TEST_CASE("[Geometry3D] Preallocated plane arrays preserve reference formulas and ordering") {
	const int segment_counts[] = { 1, 3, 8, 32, 256 };
	const int latitude_counts[] = { 0, 1, 3, 9 };
	for (int axis_index = 0; axis_index < 3; axis_index++) {
		const Vector3::Axis axis_index_3d = static_cast<Vector3::Axis>(axis_index);
		Vector3 axis;
		axis[axis_index_3d] = 1.0;
		Vector3 axis_neg;
		axis_neg[(axis_index_3d + 1) % 3] = 1.0;
		axis_neg[(axis_index_3d + 2) % 3] = 1.0;
		axis_neg[axis_index_3d] = -1.0;

		for (int segments : segment_counts) {
			const real_t radius = 2.75;
			const real_t height = 9.25;
			const double step = Math::TAU / segments;

			Vector<Plane> cylinder_expected;
			for (int i = 0; i < segments; i++) {
				Vector3 normal;
				normal[(axis_index_3d + 1) % 3] = Math::cos(i * step);
				normal[(axis_index_3d + 2) % 3] = Math::sin(i * step);
				cylinder_expected.push_back(Plane(normal, radius));
			}
			cylinder_expected.push_back(Plane(axis, height * 0.5f));
			cylinder_expected.push_back(Plane(-axis, height * 0.5f));

			const Vector<Plane> cylinder_actual = Geometry3D::build_cylinder_planes(radius, height, segments, axis_index_3d);
			REQUIRE_EQ(cylinder_actual.size(), cylinder_expected.size());
			for (int j = 0; j < cylinder_actual.size(); j++) {
				CHECK(cylinder_actual[j].is_equal_approx(cylinder_expected[j]));
			}

			for (int lats : latitude_counts) {
				Vector<Plane> sphere_expected;
				Vector<Plane> capsule_expected;
				for (int i = 0; i < segments; i++) {
					Vector3 normal;
					normal[(axis_index_3d + 1) % 3] = Math::cos(i * step);
					normal[(axis_index_3d + 2) % 3] = Math::sin(i * step);
					sphere_expected.push_back(Plane(normal, radius));
					capsule_expected.push_back(Plane(normal, radius));
					for (int j = 1; j <= lats; j++) {
						Vector3 plane_normal = normal.lerp(axis, j / (real_t)lats).normalized();
						sphere_expected.push_back(Plane(plane_normal, radius));
						sphere_expected.push_back(Plane(plane_normal * axis_neg, radius));
						Vector3 position = axis * height * 0.5f + plane_normal * radius;
						capsule_expected.push_back(Plane(plane_normal, position));
						capsule_expected.push_back(Plane(plane_normal * axis_neg, position * axis_neg));
					}
				}

				const Vector<Plane> sphere_actual = Geometry3D::build_sphere_planes(radius, lats, segments, axis_index_3d);
				const Vector<Plane> capsule_actual = Geometry3D::build_capsule_planes(radius, height, segments, lats, axis_index_3d);
				REQUIRE_EQ(sphere_actual.size(), sphere_expected.size());
				REQUIRE_EQ(capsule_actual.size(), capsule_expected.size());
				for (int j = 0; j < sphere_actual.size(); j++) {
					CHECK(sphere_actual[j].is_equal_approx(sphere_expected[j]));
				}
				for (int j = 0; j < capsule_actual.size(); j++) {
					CHECK(capsule_actual[j].is_equal_approx(capsule_expected[j]));
				}
			}
		}
	}
}

TEST_CASE("[Geometry3D] Known-size builders handle zero and negative dimensions") {
	const Vector<Plane> cylinder = Geometry3D::build_cylinder_planes(1.0, 2.0, -1);
	REQUIRE_EQ(cylinder.size(), 2);
	CHECK(cylinder[0].is_equal_approx(Plane(Vector3(0, 0, 1), 1.0)));
	CHECK(cylinder[1].is_equal_approx(Plane(Vector3(0, 0, -1), 1.0)));

	const Vector<Plane> sphere_empty = Geometry3D::build_sphere_planes(1.0, 2, -1);
	CHECK_EQ(sphere_empty.size(), 0);
	const Vector<Plane> sphere_flat = Geometry3D::build_sphere_planes(1.0, -1, 3);
	CHECK_EQ(sphere_flat.size(), 3);
	const Vector<Plane> capsule_empty = Geometry3D::build_capsule_planes(1.0, 2.0, -1, 3);
	CHECK_EQ(capsule_empty.size(), 0);
	const Vector<Plane> capsule_flat = Geometry3D::build_capsule_planes(1.0, 2.0, 3, -1);
	CHECK_EQ(capsule_flat.size(), 3);
}


TEST_CASE("[Geometry3D][Performance] MeshData dense remapping preserves first-use order") {
	Geometry3D::MeshData mesh;
	mesh.vertices.resize(12);
	for (uint32_t i = 0; i < mesh.vertices.size(); i++) {
		mesh.vertices[i] = Vector3(real_t(i), real_t(i * 3), real_t(-int(i)));
	}
	Geometry3D::MeshData::Face first;
	first.indices.push_back(7);
	first.indices.push_back(3);
	first.indices.push_back(7);
	mesh.faces.push_back(std::move(first));

	Geometry3D::MeshData::Face second;
	second.indices.push_back(3);
	second.indices.push_back(0);
	second.indices.push_back(7);
	mesh.faces.push_back(std::move(second));

	Geometry3D::MeshData::Edge edge;
	edge.vertex_a = 11;
	edge.vertex_b = 0;
	edge.face_a = 0;
	edge.face_b = 1;
	mesh.edges.push_back(edge);
	edge.vertex_a = 11;
	edge.vertex_b = 3;
	mesh.edges.push_back(edge);

	mesh.optimize_vertices();

	REQUIRE(mesh.vertices.size() == 5);
	CHECK(mesh.vertices[0] == Vector3(7, 21, -7));
	CHECK(mesh.vertices[1] == Vector3(3, 9, -3));
	CHECK(mesh.vertices[2] == Vector3(0, 0, 0));
	CHECK(mesh.vertices[3] == Vector3(11, 33, -11));
	CHECK(mesh.faces[0].indices[0] == 0);
	CHECK(mesh.faces[0].indices[1] == 1);
	CHECK(mesh.faces[0].indices[2] == 0);
	CHECK(mesh.faces[1].indices[0] == 1);
	CHECK(mesh.faces[1].indices[1] == 2);
	CHECK(mesh.faces[1].indices[2] == 0);
	CHECK(mesh.edges[0].vertex_a == 3);
	CHECK(mesh.edges[0].vertex_b == 2);
	CHECK(mesh.edges[1].vertex_a == 3);
	CHECK(mesh.edges[1].vertex_b == 1);
	CHECK(mesh.edges[0].face_a == 0);
	CHECK(mesh.edges[0].face_b == 1);

	// Applying the pass to an already-compacted mesh must be idempotent.
	mesh.optimize_vertices();
	CHECK(mesh.vertices.size() == 5);
	CHECK(mesh.vertices[3] == Vector3(11, 33, -11));
	CHECK(mesh.faces[0].indices[0] == 0);
	CHECK(mesh.edges[1].vertex_a == 3);
}

TEST_CASE("[Geometry3D][Performance] MeshData remapping preserves large shared meshes") {
	const int vertex_count = 4096;
	const int face_count = 2400;
	Geometry3D::MeshData mesh;
	mesh.vertices.resize(vertex_count);
	for (int i = 0; i < vertex_count; i++) {
		mesh.vertices[i] = Vector3(real_t(i), real_t(i % 13), real_t(i % 29));
	}
	LocalVector<int> originals;
	originals.resize_uninitialized(face_count * 3);

	for (int i = 0; i < face_count; i++) {
		Geometry3D::MeshData::Face face;
		for (int j = 0; j < 3; j++) {
			const int index = (i * 37 + j * 251) % vertex_count;
			face.indices.push_back(index);
			originals[i * 3 + j] = index;
		}
		mesh.faces.push_back(std::move(face));
	}
	mesh.optimize_vertices();
	CHECK(mesh.vertices.size() <= uint32_t(vertex_count));
	CHECK(mesh.vertices.size() > 100);

	for (int i = 0; i < face_count; i++) {
		for (int j = 0; j < 3; j++) {
			const int mapped = mesh.faces[i].indices[j];
			REQUIRE(mapped >= 0);
			REQUIRE(mapped < int(mesh.vertices.size()));
			const int original = originals[i * 3 + j];
			CHECK(mesh.vertices[mapped] == Vector3(real_t(original), real_t(original % 13), real_t(original % 29)));
		}
	}
}

TEST_CASE("[Geometry3D][Performance] MeshData drops vertices without references") {
	Geometry3D::MeshData mesh;
	mesh.vertices.resize(32);
	mesh.optimize_vertices();
	CHECK(mesh.vertices.size() == 0);

	mesh.vertices.resize(32);
	for (int i = 0; i < 32; i++) {
		mesh.vertices[i] = Vector3(i, i + 1, i + 2);
	}
	Geometry3D::MeshData::Edge edge;
	edge.vertex_a = 31;
	edge.vertex_b = 31;
	edge.face_a = -1;
	edge.face_b = -1;
	mesh.edges.push_back(edge);
	mesh.optimize_vertices();
	REQUIRE(mesh.vertices.size() == 1);
	CHECK(mesh.vertices[0] == Vector3(31, 32, 33));
	CHECK(mesh.edges[0].vertex_a == 0);
	CHECK(mesh.edges[0].vertex_b == 0);
}

} // namespace TestGeometry3D
