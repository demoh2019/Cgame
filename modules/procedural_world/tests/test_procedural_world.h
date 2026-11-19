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
	CHECK(world->generate_heightmap(2, 2, 1, 20.0f, 0.0f) == PackedFloat32Array::make(0.0f, 0.0f, 0.0f, 0.0f));
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
	CHECK(Vector2i(cells[0]) == Vector2i(-1, -1));
	CHECK(Vector2i(cells[1]) == Vector2i(0, -1));
	CHECK(Vector2i(cells[2]) == Vector2i(-1, 0));
	CHECK(Vector2i(cells[3]) == Vector2i(0, 0));
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

} // namespace TestProceduralWorld
