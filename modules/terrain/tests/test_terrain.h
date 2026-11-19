/**************************************************************************/
/*  test_terrain.h                                                        */
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

#pragma once

#include "../terrain_3d.h"

#include "core/io/image.h"
#include "scene/resources/mesh.h"
#include "scene/resources/multimesh.h"
#include "scene/resources/3d/primitive_meshes.h"
#include "tests/test_macros.h"

namespace TestTerrain3D {

TEST_CASE("[Terrain3D] Flat default terrain produces a 33x33 render mesh") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	CHECK(terrain->get_grid_size() == Vector2i(33, 33));
	CHECK(terrain->get_cell_size() == 1.0);
	CHECK(terrain->get_height_data().size() == 1089);
	CHECK(terrain->get_color_data().size() == 1089);
	REQUIRE(terrain->get_mesh().is_valid());
	CHECK(terrain->get_mesh()->get_surface_count() == 1);
	Array arrays = terrain->get_mesh()->surface_get_arrays(0);
	PackedVector3Array vertices = arrays[Mesh::ARRAY_VERTEX];
	PackedVector3Array normals = arrays[Mesh::ARRAY_NORMAL];
	PackedInt32Array indices = arrays[Mesh::ARRAY_INDEX];
	CHECK(vertices.size() == 1089);
	CHECK(normals.size() == 1089);
	CHECK(indices.size() == 32 * 32 * 6);
	CHECK(vertices[0] == Vector3());
	CHECK(vertices[1088] == Vector3(32, 0, 32));
	CHECK(normals[0].is_equal_approx(Vector3(0, 1, 0)));
	memdelete(terrain);
}

TEST_CASE("[Terrain3D] Supports rectangular grids and upward triangle winding") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	terrain->set_grid_size(Vector2i(3, 5));
	CHECK(terrain->get_height_data().size() == 15);
	Ref<Mesh> mesh = terrain->get_mesh();
	REQUIRE(mesh.is_valid());
	Array arrays = mesh->surface_get_arrays(0);
	PackedVector3Array vertices = arrays[Mesh::ARRAY_VERTEX];
	PackedInt32Array indices = arrays[Mesh::ARRAY_INDEX];
	CHECK(vertices.size() == 15);
	CHECK(indices.size() == 2 * 4 * 6);
	CHECK(vertices[14] == Vector3(2, 0, 4));
	const Vector3 face_normal = (vertices[indices[1]] - vertices[indices[0]]).cross(vertices[indices[2]] - vertices[indices[0]]);
	CHECK(face_normal.y > 0);
	memdelete(terrain);
}

TEST_CASE("[Terrain3D] Grid resize resets data rather than mismatching dimensions") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	terrain->set_height_at(0, 0, 50);
	terrain->set_grid_size(Vector2i(4, 2));
	CHECK(terrain->get_grid_size() == Vector2i(4, 2));
	CHECK(terrain->get_height_data().size() == 8);
	CHECK(terrain->get_color_data().size() == 8);
	for (float height : terrain->get_height_data()) {
		CHECK(height == 0);
	}
	for (Color color : terrain->get_color_data()) {
		CHECK(color == Color(1, 1, 1));
	}
	memdelete(terrain);
}

TEST_CASE("[Terrain3D] Grid bounds and invalid size are rejected without mutation") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	const Vector2i invalid[] = { Vector2i(0, 2), Vector2i(1, 3), Vector2i(2, 1), Vector2i(258, 2), Vector2i(2, 258) };
	ERR_PRINT_OFF
	for (Vector2i size : invalid) {
		terrain->set_grid_size(size);
		CHECK(terrain->get_grid_size() == Vector2i(33, 33));
	}
	ERR_PRINT_ON
	memdelete(terrain);
}

TEST_CASE("[Terrain3D] Cell size scales vertices without modifying heights") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	terrain->set_grid_size(Vector2i(2, 2));
	terrain->set_height_at(1, 1, 9);
	terrain->set_cell_size(2.5);
	CHECK(terrain->get_cell_size() == 2.5);
	CHECK(terrain->get_height_at(1, 1) == 9);
	Array arrays = terrain->get_mesh()->surface_get_arrays(0);
	PackedVector3Array vertices = arrays[Mesh::ARRAY_VERTEX];
	CHECK(vertices[3].is_equal_approx(Vector3(2.5, 9, 2.5)));
	memdelete(terrain);
}

TEST_CASE("[Terrain3D] Invalid cell size and height data do not corrupt terrain") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	const PackedFloat32Array initial_heights = terrain->get_height_data();
	const float invalid_sizes[] = { 0.0f, -1.0f, Math::INF, -Math::INF };
	ERR_PRINT_OFF
	for (float size : invalid_sizes) {
		terrain->set_cell_size(size);
		CHECK(terrain->get_cell_size() == 1);
	}
	PackedFloat32Array wrong_size;
	wrong_size.resize(5);
	terrain->set_height_data(wrong_size);
	CHECK(terrain->get_height_data() == initial_heights);
	PackedFloat32Array invalid_heights = initial_heights;
	invalid_heights.set(0, Math::INF);
	terrain->set_height_data(invalid_heights);
	CHECK(terrain->get_height_data() == initial_heights);
	ERR_PRINT_ON
	memdelete(terrain);
}

TEST_CASE("[Terrain3D] Get, set and bilinearly interpolate heights") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	terrain->set_grid_size(Vector2i(2, 2));
	terrain->set_height_at(0, 0, 0);
	terrain->set_height_at(1, 0, 10);
	terrain->set_height_at(0, 1, 20);
	terrain->set_height_at(1, 1, 30);
	CHECK(terrain->get_height_at(1, 1) == 30);
	CHECK(Math::is_equal_approx(terrain->sample_height(Vector2(0.5, 0.5)), (real_t)15.0));
	CHECK(Math::is_equal_approx(terrain->sample_height(Vector2(0.5, 0)), (real_t)5.0));
	CHECK(Math::is_equal_approx(terrain->sample_height(Vector2(0, 0.5)), (real_t)10.0));
	CHECK(terrain->sample_height(Vector2(1, 1)) == 30);
	memdelete(terrain);
}

TEST_CASE("[Terrain3D] Height edits update mesh vertices and surface normals") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	terrain->set_grid_size(Vector2i(3, 3));
	terrain->set_height_at(2, 1, 3);
	Array arrays = terrain->get_mesh()->surface_get_arrays(0);
	PackedVector3Array positions = arrays[Mesh::ARRAY_VERTEX];
	PackedVector3Array normals = arrays[Mesh::ARRAY_NORMAL];
	CHECK(positions[5] == Vector3(2, 3, 1));
	CHECK(normals[4].x < 0);
	CHECK(normals[4].y > 0);
	memdelete(terrain);
}

TEST_CASE("[Terrain3D] Sculpt has spatial falloff and leaves distant points unchanged") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	terrain->set_grid_size(Vector2i(7, 7));
	terrain->sculpt(Vector2(3, 3), 2.5, 4);
	CHECK(Math::is_equal_approx((real_t)terrain->get_height_at(3, 3), (real_t)4));
	CHECK(terrain->get_height_at(4, 3) > 0);
	CHECK(terrain->get_height_at(4, 3) < 4);
	CHECK(terrain->get_height_at(0, 0) == 0);
	terrain->sculpt(Vector2(3, 3), 0.5, -2);
	CHECK(terrain->get_height_at(3, 3) == 2);
	CHECK(terrain->get_height_at(0, 0) == 0);
	memdelete(terrain);
}

TEST_CASE("[Terrain3D] Sculpt supports brushes at edges and outside the grid") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	terrain->set_grid_size(Vector2i(4, 4));
	terrain->sculpt(Vector2(0, 0), 2, 2);
	CHECK(terrain->get_height_at(0, 0) == 2);
	CHECK(terrain->get_height_at(3, 3) == 0);
	const PackedFloat32Array before = terrain->get_height_data();
	terrain->sculpt(Vector2(-10, -10), 1, 5);
	CHECK(terrain->get_height_data() == before);
	memdelete(terrain);
}

TEST_CASE("[Terrain3D] Invalid brush radius does not mutate heights") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	const PackedFloat32Array before = terrain->get_height_data();
	ERR_PRINT_OFF
	terrain->sculpt(Vector2(3, 3), 0, 5);
	terrain->sculpt(Vector2(3, 3), -2, 5);
	terrain->smooth(Vector2(3, 3), 0, 1);
	ERR_PRINT_ON
	CHECK(terrain->get_height_data() == before);
	memdelete(terrain);
}

TEST_CASE("[Terrain3D] Smoothing reduces spikes while preserving flat areas") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	terrain->set_grid_size(Vector2i(5, 5));
	terrain->set_height_at(2, 2, 9);
	terrain->smooth(Vector2(2, 2), 2, 1);
	CHECK(terrain->get_height_at(2, 2) < 9);
	CHECK(terrain->get_height_at(2, 2) > 0);
	CHECK(terrain->get_height_at(1, 2) > 0);
	CHECK(terrain->get_height_at(0, 0) == 0);
	memdelete(terrain);
}

TEST_CASE("[Terrain3D] Constant heightfield is invariant under smoothing") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	terrain->set_grid_size(Vector2i(5, 5));
	PackedFloat32Array heights = terrain->get_height_data();
	heights.fill(3.0f);
	terrain->set_height_data(heights);
	terrain->smooth(Vector2(2, 2), 3, 1);
	CHECK(terrain->get_height_data() == heights);
	memdelete(terrain);
}

TEST_CASE("[Terrain3D] Vertex painting interpolates colors and changes mesh color array") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	terrain->set_grid_size(Vector2i(5, 5));
	terrain->paint_color(Vector2(2, 2), 2, Color(1, 0, 0), 0.5);
	CHECK(terrain->get_color_data()[12].is_equal_approx(Color(1, 0.5, 0.5)));
	CHECK(terrain->get_color_data()[0] == Color(1, 1, 1));
	Array arrays = terrain->get_mesh()->surface_get_arrays(0);
	PackedColorArray colors = arrays[Mesh::ARRAY_COLOR];
	CHECK(colors.size() == 25);
	CHECK(colors[12].is_equal_approx(terrain->get_color_data()[12]));
	memdelete(terrain);
}

TEST_CASE("[Terrain3D] Invalid vertex color array is rejected without data loss") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	PackedColorArray original = terrain->get_color_data();
	PackedColorArray invalid;
	invalid.resize(3);
	ERR_PRINT_OFF
	terrain->set_color_data(invalid);
	ERR_PRINT_ON
	CHECK(terrain->get_color_data() == original);
	memdelete(terrain);
}

TEST_CASE("[Terrain3D] Imports grayscale height maps in row-major order") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	Ref<Image> image = Image::create_empty(2, 2, false, Image::FORMAT_RGBA8);
	REQUIRE(image.is_valid());
	image->set_pixel(0, 0, Color(0, 0, 0));
	image->set_pixel(1, 0, Color(1, 1, 1));
	image->set_pixel(0, 1, Color(0.5, 0.5, 0.5));
	image->set_pixel(1, 1, Color(0.25, 0.25, 0.25));
	terrain->import_heightmap(image, -10, 10);
	CHECK(terrain->get_grid_size() == Vector2i(2, 2));
	CHECK(Math::is_equal_approx((real_t)terrain->get_height_at(0, 0), (real_t)-10));
	CHECK(Math::is_equal_approx((real_t)terrain->get_height_at(1, 0), (real_t)10));
	CHECK(Math::abs(terrain->get_height_at(0, 1)) < 0.2);
	CHECK(Math::abs(terrain->get_height_at(1, 1) - (-5)) < 0.2);
	memdelete(terrain);
}

TEST_CASE("[Terrain3D] Importing an invalid image leaves existing geometry intact") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	const PackedFloat32Array before = terrain->get_height_data();
	const Vector2i before_size = terrain->get_grid_size();
	ERR_PRINT_OFF
	terrain->import_heightmap(Ref<Image>(), -1, 1);
	ERR_PRINT_ON
	CHECK(terrain->get_height_data() == before);
	CHECK(terrain->get_grid_size() == before_size);
	memdelete(terrain);
}


TEST_CASE("[Terrain3D] Thermal erosion conserves height and spreads a peak") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	terrain->set_grid_size(Vector2i(5, 5));
	terrain->set_height_at(2, 2, 16);
	terrain->erode_thermal(1, 0, 1);
	CHECK(terrain->get_height_at(2, 2) < 16);
	CHECK(terrain->get_height_at(1, 2) > 0);
	CHECK(terrain->get_height_at(3, 2) > 0);
	CHECK(terrain->get_height_at(2, 1) > 0);
	CHECK(terrain->get_height_at(2, 3) > 0);
	real_t total = 0;
	for (float height : terrain->get_height_data()) {
		total += height;
	}
	CHECK(Math::abs(total - 16.0) < 0.0001);
	memdelete(terrain);
}

TEST_CASE("[Terrain3D] Thermal erosion preserves constant fields") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	terrain->set_grid_size(Vector2i(8, 4));
	PackedFloat32Array original = terrain->get_height_data();
	original.fill(4);
	terrain->set_height_data(original);
	terrain->erode_thermal(20, 0, 1);
	CHECK(terrain->get_height_data() == original);
	memdelete(terrain);
}

TEST_CASE("[Terrain3D] Thermal erosion respects talus and zero strength") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	terrain->set_grid_size(Vector2i(3, 3));
	terrain->set_height_at(1, 1, 1);
	const PackedFloat32Array original = terrain->get_height_data();
	terrain->erode_thermal(10, 2, 1);
	terrain->erode_thermal(0, 0, 1);
	terrain->erode_thermal(10, 0, 0);
	CHECK(terrain->get_height_data() == original);
	memdelete(terrain);
}

TEST_CASE("[Terrain3D] Erosion at the grid edge never wraps") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	terrain->set_grid_size(Vector2i(4, 4));
	terrain->set_height_at(0, 0, 8);
	terrain->erode_thermal(1, 0, 1);
	CHECK(terrain->get_height_at(0, 0) < 8);
	CHECK(terrain->get_height_at(1, 0) > 0);
	CHECK(terrain->get_height_at(0, 1) > 0);
	CHECK(terrain->get_height_at(3, 3) == 0);
	memdelete(terrain);
}

TEST_CASE("[Terrain3D] Invalid erosion parameters never alter the heightfield") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	terrain->set_height_at(3, 3, 5);
	const PackedFloat32Array original = terrain->get_height_data();
	ERR_PRINT_OFF
	terrain->erode_thermal(-1, 0, 1);
	terrain->erode_thermal(129, 0, 1);
	terrain->erode_thermal(1, -1, 1);
	terrain->erode_thermal(1, 0, -1);
	terrain->erode_thermal(1, 0, 2);
	terrain->erode_thermal(1, Math::INF, 1);
	ERR_PRINT_ON
	CHECK(terrain->get_height_data() == original);
	memdelete(terrain);
}

TEST_CASE("[Terrain3D][Foliage] Flat terrain returns the requested instance count") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	Ref<BoxMesh> mesh;
	mesh.instantiate();
	Ref<MultiMesh> foliage = terrain->create_foliage_multimesh(mesh, 64, 7, 0.9);
	REQUIRE(foliage.is_valid());
	CHECK(foliage->get_transform_format() == MultiMesh::TRANSFORM_3D);
	CHECK(foliage->get_mesh() == mesh);
	CHECK(foliage->get_instance_count() == 64);
	for (int i = 0; i < foliage->get_instance_count(); i++) {
		const Vector3 origin = foliage->get_instance_transform(i).origin;
		CHECK(origin.x >= 0.0);
		CHECK(origin.x <= 32.0);
		CHECK(origin.z >= 0.0);
		CHECK(origin.z <= 32.0);
		CHECK(Math::is_zero_approx(origin.y));
	}
	memdelete(terrain);
}

TEST_CASE("[Terrain3D][Foliage] Identical seeds produce identical instance transforms") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	Ref<BoxMesh> mesh;
	mesh.instantiate();
	Ref<MultiMesh> first = terrain->create_foliage_multimesh(mesh, 100, 1234, 0.0);
	Ref<MultiMesh> second = terrain->create_foliage_multimesh(mesh, 100, 1234, 0.0);
	REQUIRE(first.is_valid());
	REQUIRE(second.is_valid());
	REQUIRE(first->get_instance_count() == 100);
	REQUIRE(second->get_instance_count() == 100);
	for (int i = 0; i < 100; i++) {
		CHECK(first->get_instance_transform(i).is_equal_approx(second->get_instance_transform(i)));
	}
	Ref<MultiMesh> different = terrain->create_foliage_multimesh(mesh, 100, 1235, 0.0);
	REQUIRE(different.is_valid());
	CHECK_FALSE(first->get_instance_transform(0).origin.is_equal_approx(different->get_instance_transform(0).origin));
	memdelete(terrain);
}

TEST_CASE("[Terrain3D][Foliage] Zero instances return an empty valid MultiMesh") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	Ref<BoxMesh> mesh;
	mesh.instantiate();
	Ref<MultiMesh> result = terrain->create_foliage_multimesh(mesh, 0, 0);
	REQUIRE(result.is_valid());
	CHECK(result->get_instance_count() == 0);
	CHECK(result->get_mesh() == mesh);
	memdelete(terrain);
}

TEST_CASE("[Terrain3D][Foliage] Foliage conforms to interpolated terrain heights") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	terrain->set_grid_size(Vector2i(5, 7));
	terrain->set_cell_size(2.0);
	PackedFloat32Array heights = terrain->get_height_data();
	for (int z = 0; z < 7; z++) {
		for (int x = 0; x < 5; x++) {
			heights.set(z * 5 + x, float(x + z * 2));
		}
	}
	terrain->set_height_data(heights);
	Ref<BoxMesh> mesh;
	mesh.instantiate();
	Ref<MultiMesh> instances = terrain->create_foliage_multimesh(mesh, 75, 42, 0.0);
	REQUIRE(instances.is_valid());
	REQUIRE(instances->get_instance_count() == 75);
	for (int i = 0; i < instances->get_instance_count(); i++) {
		const Transform3D xform = instances->get_instance_transform(i);
		CHECK(xform.origin.x >= 0.0);
		CHECK(xform.origin.x <= 8.0);
		CHECK(xform.origin.z >= 0.0);
		CHECK(xform.origin.z <= 12.0);
		const Vector2 grid_point(xform.origin.x / 2.0, xform.origin.z / 2.0);
		CHECK(Math::is_equal_approx(xform.origin.y, terrain->sample_height(grid_point)));
	}
	memdelete(terrain);
}

TEST_CASE("[Terrain3D][Foliage] Generated uniform scales stay within the requested range") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	Ref<BoxMesh> mesh;
	mesh.instantiate();
	Ref<MultiMesh> instances = terrain->create_foliage_multimesh(mesh, 48, 314, 0.0, 0.5, 1.5);
	REQUIRE(instances.is_valid());
	REQUIRE(instances->get_instance_count() == 48);
	for (int i = 0; i < 48; i++) {
		const Vector3 scale = instances->get_instance_transform(i).basis.get_scale();
		CHECK(scale.x >= 0.5 - CMP_EPSILON);
		CHECK(scale.x <= 1.5 + CMP_EPSILON);
		CHECK(Math::is_equal_approx(scale.x, scale.y));
		CHECK(Math::is_equal_approx(scale.y, scale.z));
	}
	memdelete(terrain);
}

TEST_CASE("[Terrain3D][Foliage] Flat terrain accepts the steepness threshold of one") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	Ref<BoxMesh> mesh;
	mesh.instantiate();
	Ref<MultiMesh> result = terrain->create_foliage_multimesh(mesh, 32, 10, 1.0);
	REQUIRE(result.is_valid());
	CHECK(result->get_instance_count() == 32);
	memdelete(terrain);
}

TEST_CASE("[Terrain3D][Foliage] Rejects slopes steeper than the specified normal threshold") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	terrain->set_grid_size(Vector2i(4, 4));
	PackedFloat32Array heights = terrain->get_height_data();
	for (int z = 0; z < 4; z++) {
		for (int x = 0; x < 4; x++) {
			heights.set(z * 4 + x, x * 20.0);
		}
	}
	terrain->set_height_data(heights);
	Ref<BoxMesh> mesh;
	mesh.instantiate();
	Ref<MultiMesh> reject = terrain->create_foliage_multimesh(mesh, 64, 5, 0.5);
	REQUIRE(reject.is_valid());
	CHECK(reject->get_instance_count() == 0);
	Ref<MultiMesh> accept = terrain->create_foliage_multimesh(mesh, 64, 5, 0.0);
	REQUIRE(accept.is_valid());
	CHECK(accept->get_instance_count() == 64);
	memdelete(terrain);
}

TEST_CASE("[Terrain3D][Foliage] Scatter never mutates the source terrain data") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	terrain->set_height_at(2, 2, 8);
	const PackedFloat32Array heights_before = terrain->get_height_data();
	const PackedColorArray colors_before = terrain->get_color_data();
	Ref<BoxMesh> mesh;
	mesh.instantiate();
	Ref<MultiMesh> result = terrain->create_foliage_multimesh(mesh, 100, -11, 0.0);
	REQUIRE(result.is_valid());
	CHECK(terrain->get_height_data() == heights_before);
	CHECK(terrain->get_color_data() == colors_before);
	memdelete(terrain);
}

TEST_CASE("[Terrain3D][Foliage] Generated visibility bounds enclose all mesh instances") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	terrain->set_grid_size(Vector2i(2, 3));
	terrain->set_height_at(0, 0, -5);
	terrain->set_height_at(1, 2, 10);
	Ref<BoxMesh> mesh;
	mesh.instantiate();
	Ref<MultiMesh> result = terrain->create_foliage_multimesh(mesh, 50, 123, 0.0, 0.8, 2.0);
	REQUIRE(result.is_valid());
	REQUIRE(result->get_instance_count() == 50);
	const AABB bounds = result->get_custom_aabb();
	for (int i = 0; i < result->get_instance_count(); i++) {
		CHECK(bounds.has_point(result->get_instance_transform(i).origin));
	}
	memdelete(terrain);
}

TEST_CASE("[Terrain3D][Foliage] Invalid arguments fail without touching terrain heights") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	Ref<BoxMesh> mesh;
	mesh.instantiate();
	const PackedFloat32Array before = terrain->get_height_data();
	ERR_PRINT_OFF
	CHECK(terrain->create_foliage_multimesh(Ref<Mesh>(), 1, 0).is_null());
	CHECK(terrain->create_foliage_multimesh(mesh, -1, 0).is_null());
	CHECK(terrain->create_foliage_multimesh(mesh, 100001, 0).is_null());
	CHECK(terrain->create_foliage_multimesh(mesh, 1, 0, -0.1).is_null());
	CHECK(terrain->create_foliage_multimesh(mesh, 1, 0, 1.1).is_null());
	CHECK(terrain->create_foliage_multimesh(mesh, 1, 0, Math::NaN).is_null());
	CHECK(terrain->create_foliage_multimesh(mesh, 1, 0, 0.0, 0.0).is_null());
	CHECK(terrain->create_foliage_multimesh(mesh, 1, 0, 0.0, 1.3, 1.2).is_null());
	CHECK(terrain->create_foliage_multimesh(mesh, 1, 0, 0.0, 0.8, Math::INF).is_null());
	ERR_PRINT_ON
	CHECK(terrain->get_height_data() == before);
	memdelete(terrain);
}


TEST_CASE("[Terrain3D][Foliage] Cell size changes footprint without changing sampled height") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	terrain->set_grid_size(Vector2i(4, 4));
	terrain->set_height_at(1, 1, 2);
	Ref<BoxMesh> mesh;
	mesh.instantiate();
	Ref<MultiMesh> before = terrain->create_foliage_multimesh(mesh, 16, 3, 0.0, 1.0, 1.0);
	REQUIRE(before.is_valid());
	terrain->set_cell_size(3.0);
	Ref<MultiMesh> after = terrain->create_foliage_multimesh(mesh, 16, 3, 0.0, 1.0, 1.0);
	REQUIRE(after.is_valid());
	REQUIRE(before->get_instance_count() == 16);
	REQUIRE(after->get_instance_count() == 16);
	for (int i = 0; i < 16; i++) {
		const Transform3D a = before->get_instance_transform(i);
		const Transform3D b = after->get_instance_transform(i);
		CHECK(Math::is_equal_approx(b.origin.x, a.origin.x * 3.0));
		CHECK(Math::is_equal_approx(b.origin.z, a.origin.z * 3.0));
		CHECK(Math::is_equal_approx(b.origin.y, a.origin.y));
	}
	memdelete(terrain);
}

TEST_CASE("[Terrain3D][Foliage] New scatter output follows edited heights without modifying old output") {
	HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
	terrain->set_grid_size(Vector2i(3, 3));
	Ref<BoxMesh> mesh;
	mesh.instantiate();
	Ref<MultiMesh> old = terrain->create_foliage_multimesh(mesh, 24, 18, 0.0, 1.0, 1.0);
	REQUIRE(old.is_valid());
	PackedFloat32Array heights = terrain->get_height_data();
	heights.fill(6.0);
	terrain->set_height_data(heights);
	Ref<MultiMesh> updated = terrain->create_foliage_multimesh(mesh, 24, 18, 0.0, 1.0, 1.0);
	REQUIRE(updated.is_valid());
	REQUIRE(old->get_instance_count() == 24);
	REQUIRE(updated->get_instance_count() == 24);
	for (int i = 0; i < 24; i++) {
		CHECK(Math::is_zero_approx(old->get_instance_transform(i).origin.y));
		CHECK(Math::is_equal_approx(updated->get_instance_transform(i).origin.y, (real_t)6.0));
		CHECK(Math::is_equal_approx(updated->get_instance_transform(i).origin.x, old->get_instance_transform(i).origin.x));
		CHECK(Math::is_equal_approx(updated->get_instance_transform(i).origin.z, old->get_instance_transform(i).origin.z));
	}
	memdelete(terrain);
}

} // namespace TestTerrain3D
