/**************************************************************************/
/*  test_terrain_heightmap.h                                              */
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
/**************************************************************************/

#pragma once

#include "../terrain_heightmap.h"
#include "tests/test_macros.h"

#include <limits>

namespace TestTerrainHeightmap {

TEST_CASE("[TerrainHeightmap] Default data is flat and painted with layer zero") {
	Ref<TerrainHeightmap> terrain;
	terrain.instantiate();
	CHECK(terrain->get_dimensions() == Size2i(17, 17));
	CHECK(terrain->get_heights().size() == 289);
	CHECK(terrain->get_paint_weights().size() == 289);
	CHECK(terrain->get_height_at(0, 0) == 0.0f);
	CHECK(terrain->get_height_at(16, 16) == 0.0f);
	CHECK(terrain->get_paint_at(8, 8) == Color(1, 0, 0, 0));
}

TEST_CASE("[TerrainHeightmap] Resizing preserves overlapping heights and paint") {
	Ref<TerrainHeightmap> terrain;
	terrain.instantiate();
	terrain->set_dimensions(Size2i(3, 3));
	terrain->set_height_at(1, 1, 12.5f);
	terrain->paint_layer(Vector2(1, 1), 0.5f, 2, 1.0f);
	terrain->set_dimensions(Size2i(5, 4));
	CHECK(terrain->get_height_at(1, 1) == doctest::Approx(12.5f));
	CHECK(terrain->get_paint_at(1, 1) == Color(0, 0, 1, 0));
	CHECK(terrain->get_height_at(4, 3) == 0.0f);
	CHECK(terrain->get_paint_at(4, 3) == Color(1, 0, 0, 0));
	terrain->set_dimensions(Size2i(2, 2));
	CHECK(terrain->get_heights().size() == 4);
	CHECK(terrain->get_height_at(1, 1) == doctest::Approx(12.5f));
}

TEST_CASE("[TerrainHeightmap] Invalid dimensions are rejected without mutation") {
	Ref<TerrainHeightmap> terrain;
	terrain.instantiate();
	const Size2i before = terrain->get_dimensions();
	ERR_PRINT_OFF
	terrain->set_dimensions(Size2i(1, 1));
	terrain->set_dimensions(Size2i(2048, 2048));
	terrain->set_dimensions(Size2i(-1, 5));
	ERR_PRINT_ON
	CHECK(terrain->get_dimensions() == before);
}

TEST_CASE("[TerrainHeightmap] Bulk heights roundtrip and invalid array length is rejected") {
	Ref<TerrainHeightmap> terrain;
	terrain.instantiate();
	terrain->set_dimensions(Size2i(2, 2));
	PackedFloat32Array values;
	values.resize(4);
	values.set(0, -3.0f);
	values.set(1, 1.0f);
	values.set(2, 5.0f);
	values.set(3, 9.0f);
	terrain->set_heights(values);
	CHECK(terrain->get_heights() == values);
	values.resize(3);
	ERR_PRINT_OFF
	terrain->set_heights(values);
	ERR_PRINT_ON
	CHECK(terrain->get_height_at(1, 1) == 9.0f);
}

TEST_CASE("[TerrainHeightmap] Nonfinite heights are rejected") {
	Ref<TerrainHeightmap> terrain;
	terrain.instantiate();
	PackedFloat32Array invalid = terrain->get_heights();
	invalid.set(3, std::numeric_limits<float>::infinity());
	ERR_PRINT_OFF
	terrain->set_heights(invalid);
	terrain->set_height_at(0, 0, std::numeric_limits<float>::quiet_NaN());
	ERR_PRINT_ON
	CHECK(terrain->get_height_at(0, 0) == 0.0f);
	CHECK(terrain->get_height_at(3, 0) == 0.0f);
}

TEST_CASE("[TerrainHeightmap] Bilinear interpolation at corners, center and clamped bounds") {
	Ref<TerrainHeightmap> terrain;
	terrain.instantiate();
	terrain->set_dimensions(Size2i(2, 2));
	terrain->set_height_at(0, 0, 0);
	terrain->set_height_at(1, 0, 10);
	terrain->set_height_at(0, 1, 20);
	terrain->set_height_at(1, 1, 30);
	CHECK(terrain->sample_height(Vector2(0.5f, 0.5f)) == doctest::Approx(15.0f));
	CHECK(terrain->sample_height(Vector2(0.25f, 0.75f)) == doctest::Approx(17.5f));
	CHECK(terrain->sample_height(Vector2(-100, -100)) == 0.0f);
	CHECK(terrain->sample_height(Vector2(100, 100)) == 30.0f);
}

TEST_CASE("[TerrainHeightmap] Sculpt brush changes center and attenuates with distance") {
	Ref<TerrainHeightmap> terrain;
	terrain.instantiate();
	terrain->set_dimensions(Size2i(7, 7));
	terrain->sculpt(Vector2(3, 3), 2.0f, 8.0f);
	CHECK(terrain->get_height_at(3, 3) == doctest::Approx(8.0f));
	CHECK(terrain->get_height_at(4, 3) == doctest::Approx(4.0f));
	CHECK(terrain->get_height_at(5, 3) == 0.0f);
	CHECK(terrain->get_height_at(0, 0) == 0.0f);
	terrain->sculpt(Vector2(3, 3), 1.0f, -3.0f);
	CHECK(terrain->get_height_at(3, 3) == doctest::Approx(5.0f));
}

TEST_CASE("[TerrainHeightmap] Sculpt brush outside terrain has no effect") {
	Ref<TerrainHeightmap> terrain;
	terrain.instantiate();
	PackedFloat32Array before = terrain->get_heights();
	terrain->sculpt(Vector2(-100, -100), 1.0f, 100.0f);
	CHECK(terrain->get_heights() == before);
}

TEST_CASE("[TerrainHeightmap] Smoothing lowers a spike without changing distant cells") {
	Ref<TerrainHeightmap> terrain;
	terrain.instantiate();
	terrain->set_dimensions(Size2i(7, 7));
	terrain->set_height_at(3, 3, 9.0f);
	terrain->smooth(Vector2(3, 3), 1.0f, 1.0f);
	CHECK(terrain->get_height_at(3, 3) == doctest::Approx(1.0f));
	CHECK(terrain->get_height_at(0, 0) == 0.0f);
}

TEST_CASE("[TerrainHeightmap] Smoothing uses a snapshot and is symmetric") {
	Ref<TerrainHeightmap> terrain;
	terrain.instantiate();
	terrain->set_dimensions(Size2i(5, 5));
	terrain->set_height_at(2, 2, 9.0f);
	terrain->smooth(Vector2(2, 2), 2.0f, 1.0f);
	CHECK(terrain->get_height_at(1, 2) == doctest::Approx(0.5f));
	CHECK(terrain->get_height_at(3, 2) == doctest::Approx(0.5f));
	CHECK(terrain->get_height_at(2, 1) == doctest::Approx(0.5f));
	CHECK(terrain->get_height_at(2, 3) == doctest::Approx(0.5f));
}

TEST_CASE("[TerrainHeightmap] Zero strength brushing does not alter data") {
	Ref<TerrainHeightmap> terrain;
	terrain.instantiate();
	const PackedFloat32Array before_heights = terrain->get_heights();
	const PackedColorArray before_paint = terrain->get_paint_weights();
	terrain->sculpt(Vector2(1, 1), 3, 0);
	terrain->smooth(Vector2(1, 1), 3, 0);
	terrain->paint_layer(Vector2(1, 1), 3, 1, 0);
	terrain->erode_talus(0, 0, 0.5f);
	CHECK(terrain->get_heights() == before_heights);
	CHECK(terrain->get_paint_weights() == before_paint);
}

TEST_CASE("[TerrainHeightmap] Flat terrain remains unchanged by thermal erosion") {
	Ref<TerrainHeightmap> terrain;
	terrain.instantiate();
	terrain->erode_talus(10, 0.1f, 0.5f);
	CHECK(terrain->get_height_at(0, 0) == 0.0f);
	CHECK(terrain->get_height_at(8, 8) == 0.0f);
}

TEST_CASE("[TerrainHeightmap] Erosion transports height and conserves total") {
	Ref<TerrainHeightmap> terrain;
	terrain.instantiate();
	terrain->set_dimensions(Size2i(5, 5));
	terrain->set_height_at(2, 2, 10.0f);
	terrain->erode_talus(5, 0.0f, 0.2f);
	const PackedFloat32Array result = terrain->get_heights();
	double total = 0;
	for (int i = 0; i < result.size(); i++) {
		total += result[i];
	}
	CHECK(total == doctest::Approx(10.0).epsilon(0.00001));
	CHECK(terrain->get_height_at(2, 2) < 10.0f);
	CHECK(terrain->get_height_at(1, 2) > 0.0f);
}

TEST_CASE("[TerrainHeightmap] Talus threshold prevents shallow erosion") {
	Ref<TerrainHeightmap> terrain;
	terrain.instantiate();
	terrain->set_dimensions(Size2i(3, 3));
	terrain->set_height_at(1, 1, 1.0f);
	terrain->erode_talus(10, 2.0f, 0.5f);
	CHECK(terrain->get_height_at(1, 1) == 1.0f);
}

TEST_CASE("[TerrainHeightmap] Layer painting is normalized and supports all four channels") {
	Ref<TerrainHeightmap> terrain;
	terrain.instantiate();
	terrain->set_dimensions(Size2i(5, 5));
	for (int layer = 1; layer < 4; layer++) {
		terrain->paint_layer(Vector2(2, 2), 0.5f, layer, 1.0f);
		const Color c = terrain->get_paint_at(2, 2);
		CHECK(c[layer] == doctest::Approx(1.0f));
		CHECK(c.r + c.g + c.b + c.a == doctest::Approx(1.0f));
	}
	CHECK(terrain->get_paint_at(0, 0) == Color(1, 0, 0, 0));
}

TEST_CASE("[TerrainHeightmap] Partial layer brush preserves weight sum") {
	Ref<TerrainHeightmap> terrain;
	terrain.instantiate();
	terrain->set_dimensions(Size2i(5, 5));
	terrain->paint_layer(Vector2(2, 2), 2.0f, 1, 0.5f);
	const Color center = terrain->get_paint_at(2, 2);
	const Color neighbor = terrain->get_paint_at(3, 2);
	CHECK(center.r == doctest::Approx(0.5f));
	CHECK(center.g == doctest::Approx(0.5f));
	CHECK(neighbor.r == doctest::Approx(0.75f));
	CHECK(neighbor.g == doctest::Approx(0.25f));
	CHECK(neighbor.r + neighbor.g + neighbor.b + neighbor.a == doctest::Approx(1.0f));
}

TEST_CASE("[TerrainHeightmap] Invalid paint weight arrays cannot corrupt resource") {
	Ref<TerrainHeightmap> terrain;
	terrain.instantiate();
	terrain->set_dimensions(Size2i(2, 2));
	PackedColorArray bad;
	bad.resize(4);
	bad.fill(Color(0.5f, 0.5f, 0.5f, 0));
	ERR_PRINT_OFF
	terrain->set_paint_weights(bad);
	bad.resize(3);
	terrain->set_paint_weights(bad);
	ERR_PRINT_ON
	CHECK(terrain->get_paint_at(0, 0) == Color(1, 0, 0, 0));
}

TEST_CASE("[TerrainHeightmap] Invalid brush parameters are rejected") {
	Ref<TerrainHeightmap> terrain;
	terrain.instantiate();
	const PackedFloat32Array before_heights = terrain->get_heights();
	const PackedColorArray before_paint = terrain->get_paint_weights();
	ERR_PRINT_OFF
	terrain->sculpt(Vector2(1, 1), -2, 3);
	terrain->smooth(Vector2(1, 1), 1, 1.1f);
	terrain->paint_layer(Vector2(1, 1), 1, 4, 1);
	terrain->paint_layer(Vector2(1, 1), 1, 1, -1);
	terrain->erode_talus(1, -1, 0.5f);
	ERR_PRINT_ON
	CHECK(terrain->get_heights() == before_heights);
	CHECK(terrain->get_paint_weights() == before_paint);
}

TEST_CASE("[TerrainHeightmap] Mesh contains vertex paint, UVs and upward winding") {
	Ref<TerrainHeightmap> terrain;
	terrain.instantiate();
	terrain->set_dimensions(Size2i(3, 2));
	terrain->paint_layer(Vector2(1, 0), 0.5f, 2, 1);
	const Ref<ArrayMesh> mesh = terrain->build_mesh(2.0f);
	REQUIRE(mesh.is_valid());
	REQUIRE(mesh->get_surface_count() == 1);
	const Array arrays = mesh->surface_get_arrays(0);
	const PackedVector3Array vertices = arrays[Mesh::ARRAY_VERTEX];
	const PackedVector3Array normals = arrays[Mesh::ARRAY_NORMAL];
	const PackedVector2Array uvs = arrays[Mesh::ARRAY_TEX_UV];
	const PackedColorArray colors = arrays[Mesh::ARRAY_COLOR];
	const PackedInt32Array indices = arrays[Mesh::ARRAY_INDEX];
	REQUIRE(vertices.size() == 6);
	REQUIRE(indices.size() == 12);
	CHECK(normals.size() == 6);
	CHECK(uvs.size() == 6);
	CHECK(colors.size() == 6);
	CHECK(vertices[5] == Vector3(4, 0, 2));
	CHECK(uvs[5] == Vector2(1, 1));
	CHECK(colors[1] == Color(0, 0, 1, 0));
	const Vector3 a = vertices[indices[0]];
	const Vector3 b = vertices[indices[1]];
	const Vector3 c = vertices[indices[2]];
	CHECK((b - a).cross(c - a).y > 0);
	CHECK(normals[0] == Vector3(0, 1, 0));
}

TEST_CASE("[TerrainHeightmap] Sloped mesh normals point uphill and remain normalized") {
	Ref<TerrainHeightmap> terrain;
	terrain.instantiate();
	terrain->set_dimensions(Size2i(2, 2));
	terrain->set_height_at(1, 0, 2.0f);
	terrain->set_height_at(1, 1, 2.0f);
	const Ref<ArrayMesh> mesh = terrain->build_mesh();
	REQUIRE(mesh.is_valid());
	const Array arrays = mesh->surface_get_arrays(0);
	const PackedVector3Array normals = arrays[Mesh::ARRAY_NORMAL];
	CHECK(normals[0].x < 0);
	CHECK(normals[0].y > 0);
	CHECK(normals[0].length() == doctest::Approx(1.0f));
}

TEST_CASE("[TerrainHeightmap] Invalid mesh scale yields no mesh") {
	Ref<TerrainHeightmap> terrain;
	terrain.instantiate();
	ERR_PRINT_OFF
	Ref<ArrayMesh> invalid = terrain->build_mesh(0.0f);
	ERR_PRINT_ON
	CHECK(invalid.is_null());
}

} // namespace TestTerrainHeightmap
