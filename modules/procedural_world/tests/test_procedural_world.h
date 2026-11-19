/**************************************************************************/
/*  test_procedural_world.h                                               */
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

#include "../procedural_world.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestProceduralWorld {

TEST_CASE("[ProceduralWorld] Seeded heightmaps are deterministic") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	PackedFloat32Array a = world->generate_heightmap(16, 12, 1234);
	PackedFloat32Array b = world->generate_heightmap(16, 12, 1234);
	PackedFloat32Array c = world->generate_heightmap(16, 12, 4321);
	REQUIRE(a.size() == 192);
	CHECK(a == b);
	CHECK(a != c);
	for (float height : a) {
		CHECK(Math::is_finite(height));
		CHECK(height >= -32.0f);
		CHECK(height <= 32.0f);
	}
	const PackedFloat32Array flat = world->generate_heightmap(2, 2, 1, 20.0f, 0.0f);
	REQUIRE(flat.size() == 4);
	for (float h : flat) {
		CHECK(h == 0.0f);
	}
}

TEST_CASE("[ProceduralWorld] Tiled heightmaps share identical overlapping samples") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	const PackedFloat32Array left = world->generate_heightmap(8, 6, 1024, 32.0f, 8.0f, 4, Vector2i(-7, -3));
	const PackedFloat32Array right = world->generate_heightmap(8, 6, 1024, 32.0f, 8.0f, 4, Vector2i(0, -3));
	REQUIRE(left.size() == 48);
	REQUIRE(right.size() == 48);
	for (int y = 0; y < 6; y++) {
		CHECK(left[y * 8 + 7] == right[y * 8]);
	}
	CHECK(left != right);
	const PackedFloat32Array extreme = world->generate_heightmap(2, 2, 1024, 0.001f, 1.0f, 8, Vector2i(1000000, -1000000));
	REQUIRE(extreme.size() == 4);
	for (float h : extreme) {
		CHECK(Math::is_finite(h));
	}
}

TEST_CASE("[ProceduralWorld] Heightmap inputs are bounded") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	ERR_PRINT_OFF;
	CHECK(world->generate_heightmap(0, 5, 1).is_empty());
	CHECK(world->generate_heightmap(2049, 1, 1).is_empty());
	CHECK(world->generate_heightmap(8, 8, 1, 0.0f).is_empty());
	CHECK(world->generate_heightmap(8, 8, 1, 1.0f, -1.0f).is_empty());
	CHECK(world->generate_heightmap(8, 8, 1, 1.0f, 1.0f, 0).is_empty());
	CHECK(world->generate_heightmap(8, 8, 1, 1.0f, 1.0f, 4, Vector2i(1000001, 0)).is_empty());
	ERR_PRINT_ON;
}

TEST_CASE("[ProceduralWorld] Sculpting brush changes only samples within radius") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	PackedFloat32Array flat;
	flat.resize(25);
	PackedFloat32Array raised = world->paint_heightmap(flat, 5, 5, Vector2(2, 2), 1.1f, 4.0f);
	REQUIRE(raised.size() == 25);
	CHECK(raised[2 + 2 * 5] == doctest::Approx(4.0f));
	CHECK(raised[1 + 2 * 5] > 0);
	CHECK(raised[2 + 1 * 5] > 0);
	CHECK(raised[1 + 1 * 5] == 0.0f); // Diagonal outside radius.
	CHECK(raised[0] == 0.0f);
	CHECK(flat[12] == 0.0f); // Brush never edits original data.
	const PackedFloat32Array lowered = world->paint_heightmap(raised, 5, 5, Vector2(2, 2), 1.1f, -4.0f);
	CHECK(Math::is_zero_approx(lowered[12]));
}

TEST_CASE("[ProceduralWorld] Sculpting brush validates dimensions and radius") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	PackedFloat32Array heights;
	heights.resize(4);
	ERR_PRINT_OFF;
	CHECK(world->paint_heightmap(heights, 3, 3, Vector2(1, 1), 1.0f, 1.0f).is_empty());
	CHECK(world->paint_heightmap(heights, 2, 2, Vector2(0, 0), 0.0f, 1.0f).is_empty());
	ERR_PRINT_ON;
}

TEST_CASE("[ProceduralWorld] Terrain mesh has correct geometry, UV and orientation") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	PackedFloat32Array heights;
	heights.resize(9);
	heights.set(4, 2.0f);
	Ref<ArrayMesh> mesh = world->create_terrain_mesh(heights, 3, 3, 2.0f, 2.0f);
	REQUIRE(mesh.is_valid());
	REQUIRE(mesh->get_surface_count() == 1);
	Array surface = mesh->surface_get_arrays(0);
	const PackedVector3Array vertices = surface[Mesh::ARRAY_VERTEX];
	const PackedVector3Array normals = surface[Mesh::ARRAY_NORMAL];
	const PackedVector2Array uvs = surface[Mesh::ARRAY_TEX_UV];
	const PackedInt32Array indices = surface[Mesh::ARRAY_INDEX];
	REQUIRE(vertices.size() == 9);
	REQUIRE(normals.size() == 9);
	REQUIRE(uvs.size() == 9);
	REQUIRE(indices.size() == 24);
	CHECK(vertices[0] == Vector3(0, 0, 0));
	CHECK(vertices[4] == Vector3(2, 4, 2));
	CHECK(vertices[8] == Vector3(4, 0, 4));
	CHECK(uvs[0] == Vector2(0, 0));
	CHECK(uvs[8] == Vector2(1, 1));
	CHECK(normals[4].y == doctest::Approx(1.0f));
	const Vector3 front = (vertices[indices[1]] - vertices[indices[0]]).cross(vertices[indices[2]] - vertices[indices[0]]);
	CHECK(front.y > 0.0f);
}

TEST_CASE("[ProceduralWorld] Terrain mesh input validation") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	PackedFloat32Array wrong;
	wrong.resize(3);
	ERR_PRINT_OFF;
	CHECK(world->create_terrain_mesh(wrong, 2, 2).is_null());
	CHECK(world->create_terrain_mesh(wrong, 1, 3).is_null());
	CHECK(world->create_terrain_mesh(wrong, 2, 2, 0.0f).is_null());
	ERR_PRINT_ON;
}

TEST_CASE("[ProceduralWorld] Thermal erosion conserves material") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	PackedFloat32Array heights;
	heights.resize(9);
	for (int i = 0; i < 9; i++) {
		heights.set(i, i == 4 ? 8.0f : 0.0f);
	}
	const PackedFloat32Array untouched = world->erode_heightmap(heights, 3, 3, 0, 0.0f, 1.0f);
	CHECK(untouched == heights);
	const PackedFloat32Array eroded = world->erode_heightmap(heights, 3, 3, 10, 0.0f, 0.5f);
	REQUIRE(eroded.size() == 9);
	CHECK(eroded[4] < 8.0f);
	CHECK(eroded[1] > 0.0f);
	float sum = 0.0f;
	for (float height : eroded) {
		CHECK(Math::is_finite(height));
		sum += height;
	}
	CHECK(sum == doctest::Approx(8.0f).epsilon(0.0001f));
	CHECK(heights[4] == 8.0f); // Input remains unmodified.
}

TEST_CASE("[ProceduralWorld] Thermal erosion rejects wrong sample counts") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	PackedFloat32Array values;
	values.resize(3);
	ERR_PRINT_OFF;
	CHECK(world->erode_heightmap(values, 2, 2).is_empty());
	CHECK(world->erode_heightmap(values, 3, 1, -1).is_empty());
	CHECK(world->erode_heightmap(values, 3, 1, 1, 1, 2).is_empty());
	values.set(0, Math::NaN);
	CHECK(world->erode_heightmap(values, 3, 1, 1).is_empty());
	ERR_PRINT_ON;
}

TEST_CASE("[ProceduralWorld] Scatter respects min distance and seed") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	const Rect2 area(Vector2(-20, 10), Vector2(100, 80));
	const PackedVector2Array a = world->scatter_points(area, 9.0f, 5, 80);
	const PackedVector2Array b = world->scatter_points(area, 9.0f, 5, 80);
	REQUIRE(a.size() > 2);
	CHECK(a.size() <= 80);
	CHECK(a == b);
	for (int i = 0; i < a.size(); i++) {
		CHECK(area.has_point(a[i]));
		for (int j = 0; j < i; j++) {
			CHECK(a[i].distance_squared_to(a[j]) >= 81.0f - 0.001f);
		}
	}
	CHECK(world->scatter_points(area, 9.0f, 6, 80) != a);
	CHECK(world->scatter_points(area, 9.0f, 5, 0).is_empty());
}

TEST_CASE("[ProceduralWorld] Scatter validates bounds") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	ERR_PRINT_OFF;
	CHECK(world->scatter_points(Rect2(), 1.0f, 1).is_empty());
	CHECK(world->scatter_points(Rect2(0, 0, 10, 10), 0.0f, 1).is_empty());
	CHECK(world->scatter_points(Rect2(0, 0, 10, 10), 1.0f, 1, 5000).is_empty());
	ERR_PRINT_ON;
}

TEST_CASE("[ProceduralWorld] Chunk coordinates handle negative and half-open bounds") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	Array cells = world->get_chunk_coordinates(Rect2(-32, -32, 64, 64), 32);
	REQUIRE(cells.size() == 4);
	const Vector2i cell0 = cells[0];
	const Vector2i cell1 = cells[1];
	const Vector2i cell2 = cells[2];
	const Vector2i cell3 = cells[3];
	CHECK(cell0 == Vector2i(-1, -1));
	CHECK(cell1 == Vector2i(0, -1));
	CHECK(cell2 == Vector2i(-1, 0));
	CHECK(cell3 == Vector2i(0, 0));
	CHECK(world->get_chunk_coordinates(Rect2(0, 0, 64, 32), 32).size() == 2);
	CHECK(world->get_chunk_coordinates(Rect2(0, 0, 0, 32), 32).is_empty());
}

TEST_CASE("[ProceduralWorld] Chunk coordinate validation") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	ERR_PRINT_OFF;
	CHECK(world->get_chunk_coordinates(Rect2(0, 0, 10, 10), 0).is_empty());
	CHECK(world->get_chunk_coordinates(Rect2(0, 0, -10, 10), 16).is_empty());
	CHECK(world->get_chunk_coordinates(Rect2(0, 0, 100000, 100000), 1).is_empty());
	ERR_PRINT_ON;
}

TEST_CASE("[ProceduralWorld] Small rectangular heightmaps and octaves") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	for (int octaves = 1; octaves <= 8; octaves++) {
		const PackedFloat32Array heights = world->generate_heightmap(1, 7, 75, 12.0f, 4.0f, octaves);
		REQUIRE(heights.size() == 7);
		for (float height : heights) {
			CHECK(Math::is_finite(height));
			CHECK(Math::abs(height) <= 4.0f);
		}
	}
	CHECK(world->generate_heightmap(7, 1, 3).size() == 7);
	CHECK(world->generate_heightmap(1, 1, 3).size() == 1);
}

TEST_CASE("[ProceduralWorld] Adjacent tiles match vertically in world coordinates") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	const PackedFloat32Array north = world->generate_heightmap(7, 5, -50, 50.0f, 12.0f, 5, Vector2i(-4, -6));
	const PackedFloat32Array south = world->generate_heightmap(7, 5, -50, 50.0f, 12.0f, 5, Vector2i(-4, -2));
	REQUIRE(north.size() == 35);
	REQUIRE(south.size() == 35);
	for (int x = 0; x < 7; x++) {
		CHECK(north[4 * 7 + x] == south[x]);
	}
}

TEST_CASE("[ProceduralWorld] Heightmaps are stable across sample layouts") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	const PackedFloat32Array large = world->generate_heightmap(10, 10, 99, 7.0f, 8.0f, 3, Vector2i(100, -100));
	const PackedFloat32Array slice = world->generate_heightmap(3, 3, 99, 7.0f, 8.0f, 3, Vector2i(104, -96));
	REQUIRE(large.size() == 100);
	REQUIRE(slice.size() == 9);
	for (int y = 0; y < 3; y++) {
		for (int x = 0; x < 3; x++) {
			CHECK(slice[y * 3 + x] == large[(y + 4) * 10 + (x + 4)]);
		}
	}
}

TEST_CASE("[ProceduralWorld] Heightmap parameters change actual samples") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	const PackedFloat32Array base = world->generate_heightmap(12, 12, 5, 7.0f, 8.0f, 1);
	REQUIRE(base.size() == 144);
	CHECK(world->generate_heightmap(12, 12, 6, 7.0f, 8.0f, 1) != base);
	CHECK(world->generate_heightmap(12, 12, 5, 2.0f, 8.0f, 1) != base);
	CHECK(world->generate_heightmap(12, 12, 5, 7.0f, 16.0f, 1) != base);
	CHECK(world->generate_heightmap(12, 12, 5, 7.0f, 8.0f, 4) != base);
}

TEST_CASE("[ProceduralWorld] Height painting leaves non-intersecting samples alone") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	PackedFloat32Array heights;
	heights.resize(16);
	heights.set(0, 7.0f);
	const PackedFloat32Array unchanged = world->paint_heightmap(heights, 4, 4, Vector2(-20, -20), 3.0f, 15.0f);
	CHECK(unchanged == heights);
	const PackedFloat32Array zero_delta = world->paint_heightmap(heights, 4, 4, Vector2(1, 1), 4.0f, 0.0f);
	CHECK(zero_delta == heights);
	const PackedFloat32Array corner = world->paint_heightmap(heights, 4, 4, Vector2(0, 0), 0.5f, 3.0f);
	REQUIRE(corner.size() == 16);
	CHECK(corner[0] == 10.0f);
	CHECK(corner[1] == 0.0f);
	CHECK(corner[4] == 0.0f);
}

TEST_CASE("[ProceduralWorld] Sculpt brush supports constant and graded falloff") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	PackedFloat32Array heights;
	heights.resize(25);
	const PackedFloat32Array flat = world->paint_heightmap(heights, 5, 5, Vector2(2, 2), 2.5f, 2.0f, 0.0f);
	const PackedFloat32Array smooth = world->paint_heightmap(heights, 5, 5, Vector2(2, 2), 2.5f, 2.0f, 2.0f);
	REQUIRE(flat.size() == 25);
	REQUIRE(smooth.size() == 25);
	CHECK(flat[12] == 2.0f);
	CHECK(smooth[12] == 2.0f);
	CHECK(flat[11] == 2.0f);
	CHECK(smooth[11] > 0.0f);
	CHECK(smooth[11] < flat[11]);
	CHECK(flat[0] == 0.0f);
	CHECK(smooth[0] == 0.0f);
}

TEST_CASE("[ProceduralWorld] Sculpt brush rejects nonfinite heights and strengths") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	PackedFloat32Array heights;
	heights.resize(4);
	ERR_PRINT_OFF;
	CHECK(world->paint_heightmap(heights, 2, 2, Vector2(0, 0), 1.0f, float(Math::NaN)).is_empty());
	CHECK(world->paint_heightmap(heights, 2, 2, Vector2(0, 0), 1.0f, 1.0f, -1.0f).is_empty());
	CHECK(world->paint_heightmap(heights, 2, 2, Vector2(0, 0), 1.0f, 1.0f, 9.0f).is_empty());
	heights.set(0, float(Math::NaN));
	CHECK(world->paint_heightmap(heights, 2, 2, Vector2(0, 0), 1.0f, 1.0f).is_empty());
	ERR_PRINT_ON;
}

TEST_CASE("[ProceduralWorld] Erosion leaves uniform planes unchanged") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	PackedFloat32Array plane;
	plane.resize(35);
	for (int i = 0; i < plane.size(); i++) {
		plane.set(i, -3.0f);
	}
	CHECK(world->erode_heightmap(plane, 7, 5, 64, 0.0f, 1.0f) == plane);
	CHECK(world->erode_heightmap(plane, 7, 5, 3, 2.0f, 0.0f) == plane);
	CHECK(world->erode_heightmap(plane, 7, 5, 0) == plane);
}

TEST_CASE("[ProceduralWorld] Erosion respects talus and conserves material on boundaries") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	PackedFloat32Array heights;
	heights.resize(6);
	heights.set(0, 3.0f);
	CHECK(world->erode_heightmap(heights, 3, 2, 4, 10.0f, 1.0f) == heights);
	const PackedFloat32Array eroded = world->erode_heightmap(heights, 3, 2, 24, 0.0f, 1.0f);
	REQUIRE(eroded.size() == 6);
	float total = 0.0f;
	for (float value : eroded) {
		CHECK(Math::is_finite(value));
		total += value;
	}
	CHECK(total == doctest::Approx(3.0f).epsilon(0.0002f));
	CHECK(heights[0] == 3.0f);
}

TEST_CASE("[ProceduralWorld] Erosion validates iterations and finite parameters") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	PackedFloat32Array heights;
	heights.resize(4);
	ERR_PRINT_OFF;
	CHECK(world->erode_heightmap(heights, 2, 2, 257).is_empty());
	CHECK(world->erode_heightmap(heights, 2, 2, 4, -1.0f).is_empty());
	CHECK(world->erode_heightmap(heights, 2, 2, 4, 1.0f, -0.1f).is_empty());
	CHECK(world->erode_heightmap(heights, 2, 2, 4, 1.0f, 1.1f).is_empty());
	CHECK(world->erode_heightmap(heights, 2, 2, 4, float(Math::NaN)).is_empty());
	ERR_PRINT_ON;
}

TEST_CASE("[ProceduralWorld] A flat terrain mesh has up normals and expected triangles") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	PackedFloat32Array plane;
	plane.resize(4);
	const Ref<ArrayMesh> mesh = world->create_terrain_mesh(plane, 2, 2, 3.0f);
	REQUIRE(mesh.is_valid());
	const Array surface = mesh->surface_get_arrays(0);
	const PackedVector3Array vertices = surface[Mesh::ARRAY_VERTEX];
	const PackedVector3Array normals = surface[Mesh::ARRAY_NORMAL];
	const PackedInt32Array indices = surface[Mesh::ARRAY_INDEX];
	REQUIRE(vertices.size() == 4);
	REQUIRE(normals.size() == 4);
	REQUIRE(indices.size() == 6);
	CHECK(vertices[1] == Vector3(3, 0, 0));
	CHECK(vertices[2] == Vector3(0, 0, 3));
	for (const Vector3 &normal : normals) {
		CHECK(normal == Vector3(0, 1, 0));
	}
	for (int index : indices) {
		CHECK(index >= 0);
		CHECK(index < 4);
	}
}

TEST_CASE("[ProceduralWorld] Terrain mesh slopes and height scaling") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	PackedFloat32Array ramp;
	ramp.resize(4);
	ramp.set(1, 1.0f);
	ramp.set(3, 1.0f);
	const Ref<ArrayMesh> mesh = world->create_terrain_mesh(ramp, 2, 2, 1.0f, 3.0f);
	REQUIRE(mesh.is_valid());
	const Array arrays = mesh->surface_get_arrays(0);
	const PackedVector3Array vertices = arrays[Mesh::ARRAY_VERTEX];
	const PackedVector3Array normals = arrays[Mesh::ARRAY_NORMAL];
	REQUIRE(vertices.size() == 4);
	CHECK(vertices[1].y == 3.0f);
	for (const Vector3 &normal : normals) {
		CHECK(normal.x < 0.0f);
		CHECK(normal.y > 0.0f);
		CHECK(Math::is_equal_approx(normal.length(), 1.0f));
	}
}

TEST_CASE("[ProceduralWorld] Scatter respects maximum count in tiny spaces") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	const Rect2 area(-2, -3, 4, 4);
	const PackedVector2Array points = world->scatter_points(area, 100.0f, 234, 100);
	REQUIRE(points.size() == 1);
	CHECK(area.has_point(points[0]));
	const PackedVector2Array few = world->scatter_points(Rect2(-20, -10, 30, 30), 2.0f, 234, 3);
	CHECK(few.size() <= 3);
	CHECK(few.size() >= 1);
}

TEST_CASE("[ProceduralWorld] Scatter handles negative coordinates and crowding") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	const Rect2 area(-100, -120, 48, 65);
	const PackedVector2Array points = world->scatter_points(area, 7.0f, 44, 100);
	REQUIRE(points.size() > 1);
	for (int i = 0; i < points.size(); i++) {
		CHECK(area.has_point(points[i]));
		for (int j = 0; j < i; j++) {
			CHECK(points[i].distance_squared_to(points[j]) >= 49.0f - 0.001f);
		}
	}
}

TEST_CASE("[ProceduralWorld] Scatter rejects oversized grids") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	ERR_PRINT_OFF;
	CHECK(world->scatter_points(Rect2(0, 0, 100000, 100000), 0.01f, 12, 50).is_empty());
	CHECK(world->scatter_points(Rect2(0, 0, 5, 5), 1.0f, 12, 50, 0).is_empty());
	CHECK(world->scatter_points(Rect2(0, 0, 5, 5), 1.0f, 12, 50, 101).is_empty());
	ERR_PRINT_ON;
}

TEST_CASE("[ProceduralWorld] Chunk boundaries are half-open for positive and negative positions") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	CHECK(world->get_chunk_coordinates(Rect2(0, 0, 32, 32), 32).size() == 1);
	CHECK(world->get_chunk_coordinates(Rect2(32, 0, 32, 32), 32).size() == 1);
	CHECK(world->get_chunk_coordinates(Rect2(-64, -64, 32, 32), 32).size() == 1);
	const Array one = world->get_chunk_coordinates(Rect2(-64, -64, 32, 32), 32);
	REQUIRE(one.size() == 1);
	const Vector2i coordinate = one[0];
	CHECK(coordinate == Vector2i(-2, -2));
}

TEST_CASE("[ProceduralWorld] Chunks support fractional world positions") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	const Array cells = world->get_chunk_coordinates(Rect2(0.25f, 0.25f, 32.0f, 32.0f), 32);
	REQUIRE(cells.size() == 4);
	const Vector2i top_left = cells[0];
	const Vector2i bottom_right = cells[3];
	CHECK(top_left == Vector2i(0, 0));
	CHECK(bottom_right == Vector2i(1, 1));
	CHECK(world->get_chunk_coordinates(Rect2(-0.1f, -0.1f, 0.2f, 0.2f), 32).size() == 4);
}

TEST_CASE("[ProceduralWorld] Chunks reject world coordinates outside supported range") {
	Ref<ProceduralWorld> world;
	world.instantiate();
	ERR_PRINT_OFF;
	CHECK(world->get_chunk_coordinates(Rect2(1000000001.0f, 0.0f, 1.0f, 1.0f), 32).is_empty());
	CHECK(world->get_chunk_coordinates(Rect2(0, 0, 1000000, 1000000), 1).is_empty());
	ERR_PRINT_ON;
}

} // namespace TestProceduralWorld
