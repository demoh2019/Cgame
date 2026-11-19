/**************************************************************************/
/*  test_heightmap_terrain_mesh.cpp                                        */
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
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_heightmap_terrain_mesh)

#ifndef _3D_DISABLED

#include "core/math/math_funcs.h"
#include "scene/resources/3d/heightmap_terrain_mesh.h"

namespace TestHeightmapTerrainMesh {

TEST_CASE("[SceneTree][HeightmapTerrainMesh] Defaults and sizes") {
	Ref<HeightmapTerrainMesh> mesh;
	mesh.instantiate();
	CHECK_EQ(mesh->get_grid_size(), Vector2i(17, 17));
	CHECK_EQ(mesh->get_terrain_size(), Vector2(16, 16));
	CHECK_EQ(mesh->get_height_data().size(), 289);
	CHECK_EQ(mesh->get_layer_weights().size(), 289);
	CHECK_EQ(mesh->get_grid_height(8, 8), 0.0f);
	CHECK_EQ(mesh->get_layer_weights()[0], Color(1, 0, 0, 0));
}

TEST_CASE("[SceneTree][HeightmapTerrainMesh] Mesh geometry and winding") {
	Ref<HeightmapTerrainMesh> mesh;
	mesh.instantiate();
	mesh->set_grid_size(Vector2i(3, 2));
	mesh->set_terrain_size(Vector2(4, 2));
	Array arrays = mesh->get_mesh_arrays();
	PackedVector3Array vertices = arrays[Mesh::ARRAY_VERTEX];
	PackedVector3Array normals = arrays[Mesh::ARRAY_NORMAL];
	PackedVector2Array uvs = arrays[Mesh::ARRAY_TEX_UV];
	PackedColorArray colors = arrays[Mesh::ARRAY_COLOR];
	PackedInt32Array indices = arrays[Mesh::ARRAY_INDEX];
	REQUIRE_EQ(vertices.size(), 6);
	REQUIRE_EQ(indices.size(), 12);
	CHECK_EQ(normals.size(), 6);
	CHECK_EQ(uvs.size(), 6);
	CHECK_EQ(colors.size(), 6);
	CHECK_EQ(vertices[0], Vector3(-2, 0, -1));
	CHECK_EQ(vertices[5], Vector3(2, 0, 1));
	CHECK_EQ(uvs[0], Vector2(0, 0));
	CHECK_EQ(uvs[5], Vector2(1, 1));
	CHECK_EQ(normals[0], Vector3(0, 1, 0));
	CHECK((vertices[indices[1]] - vertices[indices[0]]).cross(vertices[indices[2]] - vertices[indices[0]]).y > 0);
}

TEST_CASE("[SceneTree][HeightmapTerrainMesh] Height interpolation and bounds") {
	Ref<HeightmapTerrainMesh> mesh;
	mesh.instantiate();
	mesh->set_grid_size(Vector2i(2, 2));
	mesh->set_terrain_size(Vector2(2, 2));
	mesh->set_grid_height(0, 0, 0);
	mesh->set_grid_height(1, 0, 2);
	mesh->set_grid_height(0, 1, 4);
	mesh->set_grid_height(1, 1, 6);
	CHECK_EQ(mesh->get_local_height(Vector2(-1, -1)), 0);
	CHECK_EQ(mesh->get_local_height(Vector2(1, -1)), 2);
	CHECK_EQ(mesh->get_local_height(Vector2(-1, 1)), 4);
	CHECK_EQ(mesh->get_local_height(Vector2(1, 1)), 6);
	CHECK_EQ(mesh->get_local_height(Vector2(0, 0)), 3);
	CHECK_EQ(mesh->get_local_height(Vector2(-100, -100)), 0);
	CHECK_EQ(mesh->get_local_height(Vector2(100, 100)), 6);
}

TEST_CASE("[SceneTree][HeightmapTerrainMesh] Raise lower and flatten brushes") {
	Ref<HeightmapTerrainMesh> mesh;
	mesh.instantiate();
	mesh->set_grid_size(Vector2i(3, 3));
	mesh->set_terrain_size(Vector2(2, 2));
	mesh->raise_brush(Vector2(), 0.5f, 4.0f);
	CHECK_EQ(mesh->get_grid_height(1, 1), 4.0f);
	CHECK_EQ(mesh->get_grid_height(1, 0), 0.0f);
	mesh->raise_brush(Vector2(), 0.5f, -1.0f);
	CHECK_EQ(mesh->get_grid_height(1, 1), 3.0f);
	mesh->flatten_brush(Vector2(), 0.5f, 10.0f, 0.5f);
	CHECK(Math::is_equal_approx(mesh->get_grid_height(1, 1), 6.5f));
	mesh->flatten_brush(Vector2(), 0.5f, -2.0f, 1.0f);
	CHECK_EQ(mesh->get_grid_height(1, 1), -2.0f);
}

TEST_CASE("[SceneTree][HeightmapTerrainMesh] Smooth brush samples old heights") {
	Ref<HeightmapTerrainMesh> mesh;
	mesh.instantiate();
	mesh->set_grid_size(Vector2i(3, 3));
	mesh->set_terrain_size(Vector2(2, 2));
	mesh->set_grid_height(1, 1, 10.0f);
	mesh->smooth_brush(Vector2(), 0.5f, 1.0f);
	CHECK_EQ(mesh->get_grid_height(1, 1), 2.0f);
	CHECK_EQ(mesh->get_grid_height(1, 0), 0.0f);
	mesh->smooth_brush(Vector2(), 1.1f, 0.0f);
	CHECK_EQ(mesh->get_grid_height(1, 1), 2.0f);
}

TEST_CASE("[SceneTree][HeightmapTerrainMesh] Paint blends four normalized layers") {
	Ref<HeightmapTerrainMesh> mesh;
	mesh.instantiate();
	mesh->set_grid_size(Vector2i(3, 3));
	mesh->set_terrain_size(Vector2(2, 2));
	mesh->paint_layer(Vector2(), 0.5f, 2, 1.0f);
	CHECK_EQ(mesh->get_layer_weights()[4], Color(0, 0, 1, 0));
	CHECK_EQ(mesh->get_layer_weights()[0], Color(1, 0, 0, 0));
	mesh->paint_layer(Vector2(), 0.5f, 1, 0.25f);
	Color c = mesh->get_layer_weights()[4];
	CHECK(Math::is_equal_approx(c.r + c.g + c.b + c.a, 1.0f));
	CHECK(Math::is_equal_approx(c.g, 0.25f));
	CHECK(Math::is_equal_approx(c.b, 0.75f));
	Array arrays = mesh->get_mesh_arrays();
	PackedColorArray colors = arrays[Mesh::ARRAY_COLOR];
	CHECK(Math::abs(colors[4].g - c.g) < 0.01f);
	CHECK(Math::abs(colors[4].b - c.b) < 0.01f);
}

TEST_CASE("[SceneTree][HeightmapTerrainMesh] Array setters and defensive copies") {
	Ref<HeightmapTerrainMesh> mesh;
	mesh.instantiate();
	mesh->set_grid_size(Vector2i(2, 2));
	PackedFloat32Array heights;
	heights.resize(4);
	for (int i = 0; i < 4; i++) {
		heights.set(i, i + 1);
	}
	mesh->set_height_data(heights);
	heights.set(0, 100);
	CHECK_EQ(mesh->get_grid_height(0, 0), 1);
	PackedFloat32Array returned = mesh->get_height_data();
	returned.set(1, 100);
	CHECK_EQ(mesh->get_grid_height(1, 0), 2);

	PackedColorArray weights;
	weights.resize(4);
	for (int i = 0; i < 4; i++) {
		weights.set(i, Color(2, 2, 0, 0));
	}
	mesh->set_layer_weights(weights);
	CHECK_EQ(mesh->get_layer_weights()[2], Color(0.5f, 0.5f, 0, 0));
	weights.set(2, Color(1, 0, 0, 0));
	CHECK_EQ(mesh->get_layer_weights()[2], Color(0.5f, 0.5f, 0, 0));
}

TEST_CASE("[SceneTree][HeightmapTerrainMesh] Rejects invalid input and resets after resize") {
	Ref<HeightmapTerrainMesh> mesh;
	mesh.instantiate();
	PackedFloat32Array bad_heights;
	bad_heights.resize(289);
	bad_heights.set(0, Math::NaN);
	PackedColorArray bad_layers;
	bad_layers.resize(289);
	for (int i = 0; i < bad_layers.size(); i++) {
		bad_layers.set(i, Color(0, 0, 0, 0));
	}
	ERR_PRINT_OFF;
	mesh->set_grid_size(Vector2i(1, 2));
	mesh->set_grid_size(Vector2i(513, 2));
	mesh->set_terrain_size(Vector2(-1, 1));
	mesh->set_height_data(bad_heights);
	mesh->set_layer_weights(bad_layers);
	mesh->set_grid_height(-1, 0, 10);
	mesh->paint_layer(Vector2(), 1.0f, 4, 1.0f);
	mesh->raise_brush(Vector2(), 0.0f, 10.0f);
	mesh->flatten_brush(Vector2(), 1.0f, 100.0f, 2.0f);
	ERR_PRINT_ON;
	CHECK_EQ(mesh->get_grid_size(), Vector2i(17, 17));
	CHECK_EQ(mesh->get_terrain_size(), Vector2(16, 16));
	CHECK_EQ(mesh->get_height_data().size(), 289);
	CHECK_EQ(mesh->get_grid_height(0, 0), 0);
	CHECK_EQ(mesh->get_layer_weights()[0], Color(1, 0, 0, 0));

	mesh->set_grid_height(1, 1, 10.0f);
	mesh->set_grid_size(Vector2i(4, 5));
	CHECK_EQ(mesh->get_height_data().size(), 20);
	CHECK_EQ(mesh->get_layer_weights().size(), 20);
	CHECK_EQ(mesh->get_grid_height(1, 1), 0.0f);
	Array arrays = mesh->get_mesh_arrays();
	PackedInt32Array indices = arrays[Mesh::ARRAY_INDEX];
	CHECK_EQ(indices.size(), 72);
}

} // namespace TestHeightmapTerrainMesh

#endif // _3D_DISABLED
