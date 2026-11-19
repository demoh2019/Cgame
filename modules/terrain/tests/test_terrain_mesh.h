/**************************************************************************/
/*  test_terrain_mesh.h                                                   */
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

#include "../terrain_mesh.h"

#ifndef PHYSICS_3D_DISABLED
#include "../terrain_collision_3d.h"
#endif

#include "core/io/resource_loader.h"
#include "core/io/resource_saver.h"
#include "tests/test_utils.h"

#include "tests/test_macros.h"

namespace TestTerrainMesh {

static Ref<TerrainMesh> make_terrain(const Vector2i &p_size = Vector2i(3, 3)) {
	Ref<TerrainMesh> terrain;
	terrain.instantiate();
	terrain->set_grid_size(p_size);
	return terrain;
}

static float total_height(const Ref<TerrainMesh> &p_terrain) {
	float sum = 0.0f;
	for (float value : p_terrain->get_heights()) {
		sum += value;
	}
	return sum;
}

TEST_CASE("[TerrainMesh] Default resource initializes a valid flat heightmap") {
	Ref<TerrainMesh> terrain;
	terrain.instantiate();
	CHECK(terrain->get_grid_size() == Vector2i(16, 16));
	CHECK(terrain->get_heights().size() == 256);
	CHECK(terrain->get_cell_size() == doctest::Approx(1.0f));
	CHECK(terrain->get_height_scale() == doctest::Approx(1.0f));
	for (float value : terrain->get_heights()) {
		CHECK(value == doctest::Approx(0.0f));
	}
}

TEST_CASE("[TerrainMesh] Grid resize preserves overlapping samples") {
	Ref<TerrainMesh> terrain = make_terrain(Vector2i(2, 2));
	terrain->set_height(0, 0, 2.0f);
	terrain->set_height(1, 1, 4.0f);
	terrain->set_grid_size(Vector2i(4, 3));
	CHECK(terrain->get_heights().size() == 12);
	CHECK(terrain->get_height(0, 0) == doctest::Approx(2.0f));
	CHECK(terrain->get_height(1, 1) == doctest::Approx(4.0f));
	CHECK(terrain->get_height(3, 2) == doctest::Approx(0.0f));
	terrain->set_grid_size(Vector2i(2, 2));
	CHECK(terrain->get_height(1, 1) == doctest::Approx(4.0f));
}

TEST_CASE("[TerrainMesh] Height values use row-major X/Z coordinates") {
	Ref<TerrainMesh> terrain = make_terrain(Vector2i(3, 2));
	PackedFloat32Array data;
	for (int i = 0; i < 6; i++) {
		data.push_back(float(i));
	}
	terrain->set_heights(data);
	CHECK(terrain->get_height(2, 0) == doctest::Approx(2.0f));
	CHECK(terrain->get_height(0, 1) == doctest::Approx(3.0f));
	CHECK(terrain->get_height(2, 1) == doctest::Approx(5.0f));
	CHECK(terrain->get_heights() == data);
}

TEST_CASE("[TerrainMesh] Editing heights detaches existing packed array snapshots") {
	Ref<TerrainMesh> terrain = make_terrain();
	PackedFloat32Array previous = terrain->get_heights();
	terrain->set_height(1, 1, 7.0f);
	CHECK(previous[4] == doctest::Approx(0.0f));
	CHECK(terrain->get_height(1, 1) == doctest::Approx(7.0f));
}

TEST_CASE("[TerrainMesh] Bilinear interpolation returns four corners and center") {
	Ref<TerrainMesh> terrain = make_terrain(Vector2i(2, 2));
	terrain->set_height(0, 0, 0.0f);
	terrain->set_height(1, 0, 2.0f);
	terrain->set_height(0, 1, 4.0f);
	terrain->set_height(1, 1, 6.0f);
	CHECK(terrain->sample_height(Vector2(0.0f, 0.0f)) == doctest::Approx(0.0f));
	CHECK(terrain->sample_height(Vector2(1.0f, 1.0f)) == doctest::Approx(6.0f));
	CHECK(terrain->sample_height(Vector2(0.5f, 0.5f)) == doctest::Approx(3.0f));
	CHECK(terrain->sample_height(Vector2(0.25f, 0.75f)) == doctest::Approx(3.5f));
}

TEST_CASE("[TerrainMesh] Sampling outside the grid clamps to its edges") {
	Ref<TerrainMesh> terrain = make_terrain(Vector2i(2, 2));
	terrain->set_height(0, 0, 3.0f);
	terrain->set_height(1, 1, -2.0f);
	CHECK(terrain->sample_height(Vector2(-10, -20)) == doctest::Approx(3.0f));
	CHECK(terrain->sample_height(Vector2(10, 10)) == doctest::Approx(-2.0f));
}

TEST_CASE("[TerrainMesh] Sculpt brush raises and lowers with linear falloff") {
	Ref<TerrainMesh> terrain = make_terrain(Vector2i(5, 5));
	terrain->sculpt(Vector2(2, 2), 2.0f, 4.0f);
	CHECK(terrain->get_height(2, 2) == doctest::Approx(4.0f));
	CHECK(terrain->get_height(1, 2) == doctest::Approx(2.0f));
	CHECK(terrain->get_height(2, 0) == doctest::Approx(0.0f));
	CHECK(terrain->get_height(0, 0) == doctest::Approx(0.0f));
	terrain->sculpt(Vector2(2, 2), 1.0f, -1.0f);
	CHECK(terrain->get_height(2, 2) == doctest::Approx(3.0f));
	CHECK(terrain->get_height(1, 2) == doctest::Approx(2.0f));
}

TEST_CASE("[TerrainMesh] Sculpt brush clips safely at the terrain boundary") {
	Ref<TerrainMesh> terrain = make_terrain();
	terrain->sculpt(Vector2(0, 0), 2.0f, 2.0f);
	CHECK(terrain->get_height(0, 0) == doctest::Approx(2.0f));
	CHECK(terrain->get_height(1, 0) == doctest::Approx(1.0f));
	CHECK(terrain->get_height(2, 2) == doctest::Approx(0.0f));
}

TEST_CASE("[TerrainMesh] Off-grid and zero-amount brushes do not change the data") {
	Ref<TerrainMesh> terrain = make_terrain();
	PackedFloat32Array baseline = terrain->get_heights();
	terrain->sculpt(Vector2(-100, -100), 1.0f, 4.0f);
	terrain->sculpt(Vector2(1, 1), 2.0f, 0.0f);
	terrain->smooth(Vector2(1, 1), 1.0f, 0.0f);
	CHECK(terrain->get_heights() == baseline);
}

TEST_CASE("[TerrainMesh] Smooth brush averages the original neighborhood") {
	Ref<TerrainMesh> terrain = make_terrain();
	terrain->set_height(1, 1, 9.0f);
	terrain->smooth(Vector2(1, 1), 1.0f, 1.0f);
	CHECK(terrain->get_height(1, 1) == doctest::Approx(1.0f));
	CHECK(terrain->get_height(0, 0) == doctest::Approx(0.0f));
}

TEST_CASE("[TerrainMesh] Smooth brush supports partial strength") {
	Ref<TerrainMesh> terrain = make_terrain();
	terrain->set_height(1, 1, 9.0f);
	terrain->smooth(Vector2(1, 1), 1.0f, 0.5f);
	CHECK(terrain->get_height(1, 1) == doctest::Approx(5.0f));
}

TEST_CASE("[TerrainMesh] Thermal erosion leaves flat terrain unchanged") {
	Ref<TerrainMesh> terrain = make_terrain(Vector2i(5, 4));
	PackedFloat32Array values;
	values.resize(20);
	for (int i = 0; i < 20; i++) {
		values.set(i, 3.0f);
	}
	terrain->set_heights(values);
	terrain->erode(10, 0.0f, 0.7f);
	CHECK(terrain->get_heights() == values);
}

TEST_CASE("[TerrainMesh] Thermal erosion conserves height sum and reduces a peak") {
	Ref<TerrainMesh> terrain = make_terrain(Vector2i(5, 5));
	terrain->set_height(2, 2, 8.0f);
	const float before = total_height(terrain);
	terrain->erode(8, 0.0f, 0.5f);
	CHECK(terrain->get_height(2, 2) < 8.0f);
	CHECK(terrain->get_height(2, 1) > 0.0f);
	CHECK(total_height(terrain) == doctest::Approx(before).epsilon(0.0001));
}

TEST_CASE("[TerrainMesh] Thermal erosion respects the talus threshold") {
	Ref<TerrainMesh> terrain = make_terrain();
	terrain->set_height(1, 1, 1.0f);
	PackedFloat32Array before = terrain->get_heights();
	terrain->erode(10, 2.0f, 1.0f);
	CHECK(terrain->get_heights() == before);
}

TEST_CASE("[TerrainMesh] Thermal erosion is deterministic") {
	Ref<TerrainMesh> a = make_terrain();
	Ref<TerrainMesh> b = make_terrain();
	a->set_height(1, 1, 5.0f);
	b->set_height(1, 1, 5.0f);
	a->erode(5, 0.1f, 0.7f);
	b->erode(5, 0.1f, 0.7f);
	CHECK(a->get_heights() == b->get_heights());
}

TEST_CASE("[TerrainMesh] Mesh uses consistent vertex count, winding and UVs") {
	Ref<TerrainMesh> terrain = make_terrain(Vector2i(2, 2));
	terrain->set_cell_size(2.0f);
	terrain->set_height_scale(3.0f);
	terrain->set_height(1, 0, 2.0f);
	Array arrays = terrain->get_mesh_arrays();
	PackedVector3Array vertices = arrays[Mesh::ARRAY_VERTEX];
	PackedVector3Array normals = arrays[Mesh::ARRAY_NORMAL];
	PackedVector2Array uvs = arrays[Mesh::ARRAY_TEX_UV];
	PackedInt32Array indices = arrays[Mesh::ARRAY_INDEX];
	REQUIRE(vertices.size() == 4);
	REQUIRE(normals.size() == 4);
	REQUIRE(uvs.size() == 4);
	REQUIRE(indices.size() == 6);
	CHECK(vertices[0].is_equal_approx(Vector3(0, 0, 0)));
	CHECK(vertices[1].is_equal_approx(Vector3(2, 6, 0)));
	CHECK(vertices[2].is_equal_approx(Vector3(0, 0, 2)));
	CHECK(uvs[0].is_equal_approx(Vector2(0, 0)));
	CHECK(uvs[3].is_equal_approx(Vector2(1, 1)));
	CHECK(indices[0] == 0);
	CHECK(indices[1] == 2);
	CHECK(indices[2] == 1);
	CHECK(normals[0].y > 0.0f);
	CHECK(normals[0].length() == doctest::Approx(1.0f));
}

TEST_CASE("[TerrainMesh] Invalid dimensions, arrays and brush parameters leave data intact") {
	Ref<TerrainMesh> terrain = make_terrain();
	PackedFloat32Array original = terrain->get_heights();
	PackedFloat32Array wrong;
	wrong.resize(5);
	ERR_PRINT_OFF;
	terrain->set_grid_size(Vector2i(1, 2));
	terrain->set_grid_size(Vector2i(2048, 2));
	terrain->set_heights(wrong);
	terrain->set_cell_size(-1.0f);
	terrain->set_height_scale(0.0f);
	terrain->sculpt(Vector2(1, 1), -1.0f, 10.0f);
	terrain->smooth(Vector2(1, 1), 1.0f, 2.0f);
	terrain->erode(-1);
	terrain->erode(1, -1.0f);
	ERR_PRINT_ON;
	CHECK(terrain->get_grid_size() == Vector2i(3, 3));
	CHECK(terrain->get_heights() == original);
	CHECK(terrain->get_cell_size() == doctest::Approx(1.0f));
	CHECK(terrain->get_height_scale() == doctest::Approx(1.0f));
}

TEST_CASE("[TerrainMesh] Segment picking intersects flat terrain at correct position") {
	Ref<TerrainMesh> terrain = make_terrain(Vector2i(4, 4));
	Vector3 hit;
	REQUIRE(terrain->intersect_segment(Vector3(1.5f, 5.0f, 1.5f), Vector3(1.5f, -5.0f, 1.5f), hit));
	CHECK(hit.is_equal_approx(Vector3(1.5f, 0.0f, 1.5f)));
}

TEST_CASE("[TerrainMesh] Segment picking follows the rendered triangle surface") {
	Ref<TerrainMesh> terrain = make_terrain(Vector2i(2, 2));
	terrain->set_height(1, 1, 4.0f);
	Vector3 hit;
	REQUIRE(terrain->intersect_segment(Vector3(0.75f, 8.0f, 0.75f), Vector3(0.75f, -8.0f, 0.75f), hit));
	CHECK(hit.y == doctest::Approx(2.0f));
}

TEST_CASE("[TerrainMesh] Segment picking respects world-spacing and vertical scaling") {
	Ref<TerrainMesh> terrain = make_terrain(Vector2i(2, 2));
	terrain->set_cell_size(3.0f);
	terrain->set_height_scale(2.0f);
	terrain->set_height(0, 0, 3.0f);
	terrain->set_height(1, 0, 3.0f);
	terrain->set_height(0, 1, 3.0f);
	terrain->set_height(1, 1, 3.0f);
	Vector3 hit;
	REQUIRE(terrain->intersect_segment(Vector3(1.5f, 10, 1.5f), Vector3(1.5f, 0, 1.5f), hit));
	CHECK(hit.y == doctest::Approx(6.0f));
}

TEST_CASE("[TerrainMesh] Segment picking rejects rays outside or away from terrain") {
	Ref<TerrainMesh> terrain = make_terrain();
	Vector3 hit(99, 99, 99);
	CHECK_FALSE(terrain->intersect_segment(Vector3(-4, 10, -4), Vector3(-4, -10, -4), hit));
	CHECK_FALSE(terrain->intersect_segment(Vector3(1, 10, 1), Vector3(1, 1, 1), hit));
	CHECK_FALSE(terrain->intersect_segment(Vector3(1, 0, 1), Vector3(1, 0, 1), hit));
	CHECK(hit == Vector3(99, 99, 99));
}

TEST_CASE("[TerrainMesh] Resource save and reload preserves a non-square edited heightfield") {
	Ref<TerrainMesh> terrain = make_terrain(Vector2i(5, 3));
	terrain->set_cell_size(2.5f);
	terrain->set_height_scale(4.0f);
	terrain->set_height(0, 0, -3.0f);
	terrain->set_height(4, 2, 7.0f);
	const String path = TestUtils::get_temp_path("terrain_round_trip.tres");
	REQUIRE(ResourceSaver::save(terrain, path) == OK);

	Ref<Resource> resource = ResourceLoader::load(path, "", ResourceLoader::CACHE_MODE_IGNORE);
	Ref<TerrainMesh> restored = resource;
	REQUIRE(restored.is_valid());
	CHECK(restored->get_grid_size() == Vector2i(5, 3));
	CHECK(restored->get_cell_size() == doctest::Approx(2.5f));
	CHECK(restored->get_height_scale() == doctest::Approx(4.0f));
	CHECK(restored->get_heights() == terrain->get_heights());
	CHECK(restored->get_height(4, 2) == doctest::Approx(7.0f));
}

TEST_CASE("[TerrainMesh] Picking at cell seams and corners is stable") {
	Ref<TerrainMesh> terrain = make_terrain(Vector2i(4, 4));
	Vector3 hit;
	REQUIRE(terrain->intersect_segment(Vector3(1, 5, 1), Vector3(1, -5, 1), hit));
	CHECK(hit.is_equal_approx(Vector3(1, 0, 1)));
	REQUIRE(terrain->intersect_segment(Vector3(3, 5, 3), Vector3(3, -5, 3), hit));
	CHECK(hit.is_equal_approx(Vector3(3, 0, 3)));
}

TEST_CASE("[TerrainMesh] Terrain samples do not change when merely ray-picking") {
	Ref<TerrainMesh> terrain = make_terrain();
	terrain->set_height(1, 1, 5.0f);
	const PackedFloat32Array before = terrain->get_heights();
	Vector3 hit;
	terrain->intersect_segment(Vector3(1, 10, 1), Vector3(1, -10, 1), hit);
	CHECK(terrain->get_heights() == before);
}

#ifndef PHYSICS_3D_DISABLED

TEST_CASE("[TerrainCollision3D] Empty collision node has no terrain or shape") {
	TerrainCollision3D *node = memnew(TerrainCollision3D);
	CHECK(node->get_terrain().is_null());
	CHECK(node->get_shape().is_null());
	memdelete(node);
}

TEST_CASE("[TerrainCollision3D] Linking a terrain generates two collision triangles per cell") {
	TerrainCollision3D *node = memnew(TerrainCollision3D);
	Ref<TerrainMesh> terrain = make_terrain(Vector2i(4, 3));
	node->set_terrain(terrain);
	Ref<ConcavePolygonShape3D> shape = node->get_shape();
	REQUIRE(shape.is_valid());
	CHECK(node->get_terrain() == terrain);
	CHECK(shape->get_faces().size() == 36);
	memdelete(node);
}

TEST_CASE("[TerrainCollision3D] Collision vertices use terrain X Z spacing and Y scaling") {
	TerrainCollision3D *node = memnew(TerrainCollision3D);
	Ref<TerrainMesh> terrain = make_terrain(Vector2i(2, 2));
	terrain->set_cell_size(2.0f);
	terrain->set_height_scale(3.0f);
	terrain->set_height(1, 1, 4.0f);
	node->set_terrain(terrain);
	Ref<ConcavePolygonShape3D> shape = node->get_shape();
	REQUIRE(shape.is_valid());
	bool found_far_corner = false;
	bool found_origin = false;
	for (const Vector3 &point : shape->get_faces()) {
		found_far_corner |= point.is_equal_approx(Vector3(2, 12, 2));
		found_origin |= point.is_equal_approx(Vector3(0, 0, 0));
	}
	CHECK(found_far_corner);
	CHECK(found_origin);
	CHECK(node->get_scale().is_equal_approx(Vector3(1, 1, 1)));
	memdelete(node);
}

TEST_CASE("[TerrainCollision3D] Editing heights updates the same collision shape") {
	TerrainCollision3D *node = memnew(TerrainCollision3D);
	Ref<TerrainMesh> terrain = make_terrain();
	node->set_terrain(terrain);
	Ref<Shape3D> original = node->get_shape();
	terrain->set_height(1, 1, 7.0f);
	CHECK(node->get_shape() == original);
	Ref<ConcavePolygonShape3D> shape = node->get_shape();
	bool found_peak = false;
	for (const Vector3 &point : shape->get_faces()) {
		found_peak |= point.is_equal_approx(Vector3(1, 7, 1));
	}
	CHECK(found_peak);
	memdelete(node);
}

TEST_CASE("[TerrainCollision3D] Sculpt and erosion refresh the collision geometry") {
	TerrainCollision3D *node = memnew(TerrainCollision3D);
	Ref<TerrainMesh> terrain = make_terrain(Vector2i(5, 5));
	node->set_terrain(terrain);
	terrain->sculpt(Vector2(2, 2), 1.0f, 8.0f);
	Ref<ConcavePolygonShape3D> shape = node->get_shape();
	bool peak = false;
	for (const Vector3 &v : shape->get_faces()) {
		peak |= Math::is_equal_approx(v.y, 8.0f);
	}
	CHECK(peak);
	terrain->erode(5, 0.0f, 0.5f);
	peak = false;
	for (const Vector3 &v : shape->get_faces()) {
		peak |= Math::is_equal_approx(v.y, 8.0f);
	}
	CHECK_FALSE(peak);
	memdelete(node);
}

TEST_CASE("[TerrainCollision3D] Grid resize changes triangle count without changing shape identity") {
	TerrainCollision3D *node = memnew(TerrainCollision3D);
	Ref<TerrainMesh> terrain = make_terrain(Vector2i(2, 2));
	node->set_terrain(terrain);
	Ref<ConcavePolygonShape3D> shape = node->get_shape();
	REQUIRE(shape.is_valid());
	CHECK(shape->get_faces().size() == 6);
	terrain->set_grid_size(Vector2i(3, 4));
	CHECK(node->get_shape().ptr() == shape.ptr());
	CHECK(shape->get_faces().size() == 36);
	terrain->set_grid_size(Vector2i(2, 2));
	CHECK(shape->get_faces().size() == 6);
	memdelete(node);
}

TEST_CASE("[TerrainCollision3D] Changing cell size updates collision position without nonuniform node scaling") {
	TerrainCollision3D *node = memnew(TerrainCollision3D);
	Ref<TerrainMesh> terrain = make_terrain(Vector2i(2, 2));
	node->set_terrain(terrain);
	terrain->set_cell_size(5.0f);
	Ref<ConcavePolygonShape3D> shape = node->get_shape();
	bool found = false;
	for (const Vector3 &point : shape->get_faces()) {
		found |= point.is_equal_approx(Vector3(5, 0, 5));
	}
	CHECK(found);
	CHECK(node->get_scale().is_equal_approx(Vector3(1, 1, 1)));
	memdelete(node);
}

TEST_CASE("[TerrainCollision3D] Changing the reference disconnects the previous resource") {
	TerrainCollision3D *node = memnew(TerrainCollision3D);
	Ref<TerrainMesh> old_terrain = make_terrain(Vector2i(2, 2));
	Ref<TerrainMesh> new_terrain = make_terrain(Vector2i(4, 3));
	node->set_terrain(old_terrain);
	node->set_terrain(new_terrain);
	Ref<ConcavePolygonShape3D> shape = node->get_shape();
	CHECK(shape->get_faces().size() == 36);
	old_terrain->set_height(0, 0, 100.0f);
	CHECK(shape->get_faces().size() == 36);
	new_terrain->set_height(1, 1, 10.0f);
	bool found = false;
	for (const Vector3 &point : shape->get_faces()) {
		found |= Math::is_equal_approx(point.y, 10.0f);
	}
	CHECK(found);
	memdelete(node);
}

TEST_CASE("[TerrainCollision3D] Clearing a terrain removes the generated collision shape") {
	TerrainCollision3D *node = memnew(TerrainCollision3D);
	Ref<TerrainMesh> terrain = make_terrain();
	node->set_terrain(terrain);
	CHECK(node->get_shape().is_valid());
	node->set_terrain(Ref<TerrainMesh>());
	CHECK(node->get_terrain().is_null());
	CHECK(node->get_shape().is_null());
	terrain->set_height(0, 0, 3.0f);
	CHECK(node->get_shape().is_null());
	memdelete(node);
}

TEST_CASE("[TerrainCollision3D] Two colliders share source data but do not share their shapes") {
	TerrainCollision3D *a = memnew(TerrainCollision3D);
	TerrainCollision3D *b = memnew(TerrainCollision3D);
	Ref<TerrainMesh> terrain = make_terrain();
	a->set_terrain(terrain);
	b->set_terrain(terrain);
	CHECK(a->get_shape().ptr() != b->get_shape().ptr());
	terrain->set_height(1, 1, 9.0f);
	Ref<ConcavePolygonShape3D> shape_a = a->get_shape();
	Ref<ConcavePolygonShape3D> shape_b = b->get_shape();
	CHECK(shape_a->get_faces() == shape_b->get_faces());
	memdelete(a);
	terrain->set_height(1, 1, 4.0f);
	CHECK(shape_a->get_faces() != shape_b->get_faces());
	memdelete(b);
}

TEST_CASE("[TerrainCollision3D] Reassigning the same terrain is idempotent") {
	TerrainCollision3D *node = memnew(TerrainCollision3D);
	Ref<TerrainMesh> terrain = make_terrain();
	node->set_terrain(terrain);
	Ref<Shape3D> shape = node->get_shape();
	node->set_terrain(terrain);
	CHECK(node->get_shape() == shape);
	memdelete(node);
}

#endif // PHYSICS_3D_DISABLED

} // namespace TestTerrainMesh
