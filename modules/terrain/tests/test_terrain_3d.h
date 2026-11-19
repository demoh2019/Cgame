/**************************************************************************/
/*  test_terrain_3d.h                                                     */
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

#include "../terrain_3d.h"
#include "tests/test_macros.h"

namespace TestHeightmapTerrain3D {

TEST_CASE("[HeightmapTerrain3D] New node owns a default terrain mesh") {
    HeightmapTerrain3D terrain;
    CHECK(terrain.get_terrain_data().is_valid());
    CHECK(terrain.get_cell_size() == 1.0f);
    Ref<Mesh> mesh = terrain.get_mesh();
    REQUIRE(mesh.is_valid());
    CHECK(mesh->get_surface_count() == 1);
}

TEST_CASE("[HeightmapTerrain3D] Mesh is regenerated on height changes") {
    HeightmapTerrain3D terrain;
    Ref<TerrainHeightmap> data = terrain.get_terrain_data();
    data->set_dimensions(Size2i(2, 2));
    Ref<Mesh> first = terrain.get_mesh();
    REQUIRE(first.is_valid());
    data->set_height_at(1, 1, 5.0f);
    Ref<Mesh> second = terrain.get_mesh();
    REQUIRE(second.is_valid());
    CHECK(first != second);
    const Array arrays = second->surface_get_arrays(0);
    const PackedVector3Array vertices = arrays[Mesh::ARRAY_VERTEX];
    REQUIRE(vertices.size() == 4);
    CHECK(vertices[3] == Vector3(1, 5, 1));
}

TEST_CASE("[HeightmapTerrain3D] Cell size updates the mesh coordinates") {
    HeightmapTerrain3D terrain;
    Ref<TerrainHeightmap> data = terrain.get_terrain_data();
    data->set_dimensions(Size2i(2, 2));
    terrain.set_cell_size(3.0f);
    CHECK(terrain.get_cell_size() == 3.0f);
    const Array arrays = terrain.get_mesh()->surface_get_arrays(0);
    const PackedVector3Array vertices = arrays[Mesh::ARRAY_VERTEX];
    CHECK(vertices[3] == Vector3(3, 0, 3));
}

TEST_CASE("[HeightmapTerrain3D] Invalid cell size leaves previous geometry intact") {
    HeightmapTerrain3D terrain;
    Ref<Mesh> original = terrain.get_mesh();
    ERR_PRINT_OFF
    terrain.set_cell_size(-1);
    ERR_PRINT_ON
    CHECK(terrain.get_mesh() == original);
    CHECK(terrain.get_cell_size() == 1.0f);
}

TEST_CASE("[HeightmapTerrain3D] Replacing terrain data disconnects previous resource") {
    HeightmapTerrain3D terrain;
    Ref<TerrainHeightmap> old_data = terrain.get_terrain_data();
    Ref<TerrainHeightmap> new_data;
    new_data.instantiate();
    new_data->set_dimensions(Size2i(3, 3));
    terrain.set_terrain_data(new_data);
    Ref<Mesh> replacement = terrain.get_mesh();
    old_data->set_height_at(0, 0, 10.0f);
    CHECK(terrain.get_mesh() == replacement);
    new_data->set_height_at(0, 0, 10.0f);
    CHECK(terrain.get_mesh() != replacement);
}

TEST_CASE("[HeightmapTerrain3D] Null terrain resource clears the generated mesh") {
    HeightmapTerrain3D terrain;
    terrain.set_terrain_data(Ref<TerrainHeightmap>());
    CHECK(terrain.get_terrain_data().is_null());
    CHECK(terrain.get_mesh().is_null());
}

} // namespace TestHeightmapTerrain3D
