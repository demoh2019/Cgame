/**************************************************************************/
/*  test_terrain_chunks.h                                                 */
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
/* distribute, sublicense, and/or sell copies of the Software.            */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/**************************************************************************/

#pragma once

#include "../terrain_3d.h"
#include "tests/test_macros.h"

namespace TestTerrainChunks {

TEST_CASE("[TerrainChunks] Chunk mesh at origin equals full mesh") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(Size2i(5, 4));
    data->set_height_at(2, 1, 8);
    data->paint_layer(Vector2(2, 1), 1, 2, 0.7f);
    const Ref<ArrayMesh> full = data->build_mesh(2.0f);
    const Ref<ArrayMesh> chunk = data->build_chunk_mesh(Vector2i(), Vector2i(4, 3), 1, 2.0f);
    REQUIRE(full.is_valid());
    REQUIRE(chunk.is_valid());
    const Array fa = full->surface_get_arrays(0);
    const Array ca = chunk->surface_get_arrays(0);
    CHECK(PackedVector3Array(fa[Mesh::ARRAY_VERTEX]) == PackedVector3Array(ca[Mesh::ARRAY_VERTEX]));
    CHECK(PackedVector3Array(fa[Mesh::ARRAY_NORMAL]) == PackedVector3Array(ca[Mesh::ARRAY_NORMAL]));
    CHECK(PackedVector2Array(fa[Mesh::ARRAY_TEX_UV]) == PackedVector2Array(ca[Mesh::ARRAY_TEX_UV]));
    CHECK(PackedColorArray(fa[Mesh::ARRAY_COLOR]) == PackedColorArray(ca[Mesh::ARRAY_COLOR]));
    CHECK(PackedInt32Array(fa[Mesh::ARRAY_INDEX]) == PackedInt32Array(ca[Mesh::ARRAY_INDEX]));
}

TEST_CASE("[TerrainChunks] Chunk vertices use local coordinates and global UVs") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(Size2i(9, 9));
    data->set_height_at(6, 4, 3);
    const Ref<ArrayMesh> chunk = data->build_chunk_mesh(Vector2i(4, 2), Vector2i(4, 4), 2, 3.0f);
    REQUIRE(chunk.is_valid());
    const Array arrays = chunk->surface_get_arrays(0);
    const PackedVector3Array vertices = arrays[Mesh::ARRAY_VERTEX];
    const PackedVector2Array uvs = arrays[Mesh::ARRAY_TEX_UV];
    REQUIRE(vertices.size() == 9);
    CHECK(vertices[0] == Vector3(0, 0, 0));
    CHECK(vertices[4] == Vector3(6, 3, 6));
    CHECK(vertices[8] == Vector3(12, 0, 12));
    CHECK(uvs[0] == Vector2(0.5f, 0.25f));
    CHECK(uvs[8] == Vector2(1.0f, 0.75f));
}

TEST_CASE("[TerrainChunks] Coarser strides reduce the mesh triangle budget") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(Size2i(17, 17));
    const Ref<ArrayMesh> a = data->build_chunk_mesh(Vector2i(), Vector2i(16, 16), 1);
    const Ref<ArrayMesh> b = data->build_chunk_mesh(Vector2i(), Vector2i(16, 16), 2);
    const Ref<ArrayMesh> c = data->build_chunk_mesh(Vector2i(), Vector2i(16, 16), 4);
    REQUIRE(a.is_valid());
    REQUIRE(b.is_valid());
    REQUIRE(c.is_valid());
    CHECK(PackedInt32Array(a->surface_get_arrays(0)[Mesh::ARRAY_INDEX]).size() == 16 * 16 * 6);
    CHECK(PackedInt32Array(b->surface_get_arrays(0)[Mesh::ARRAY_INDEX]).size() == 8 * 8 * 6);
    CHECK(PackedInt32Array(c->surface_get_arrays(0)[Mesh::ARRAY_INDEX]).size() == 4 * 4 * 6);
}

TEST_CASE("[TerrainChunks] Chunks share edge positions at identical LOD") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(Size2i(9, 5));
    for (int z = 0; z < 5; z++) {
        data->set_height_at(4, z, float(z * 3));
    }
    const Ref<ArrayMesh> left = data->build_chunk_mesh(Vector2i(0, 0), Vector2i(4, 4), 2, 1.5f);
    const Ref<ArrayMesh> right = data->build_chunk_mesh(Vector2i(4, 0), Vector2i(4, 4), 2, 1.5f);
    REQUIRE(left.is_valid());
    REQUIRE(right.is_valid());
    const Array la = left->surface_get_arrays(0);
    const Array ra = right->surface_get_arrays(0);
    const PackedVector3Array lv = la[Mesh::ARRAY_VERTEX];
    const PackedVector3Array rv = ra[Mesh::ARRAY_VERTEX];
    const PackedVector3Array ln = la[Mesh::ARRAY_NORMAL];
    const PackedVector3Array rn = ra[Mesh::ARRAY_NORMAL];
    for (int z = 0; z < 3; z++) {
        const int left_idx = z * 3 + 2;
        const int right_idx = z * 3;
        CHECK(lv[left_idx] + Vector3(0, 0, 0) == rv[right_idx] + Vector3(6, 0, 0));
        CHECK(ln[left_idx] == rn[right_idx]);
    }
}

TEST_CASE("[TerrainChunks] Vertex paint weights sample the correct source cells") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(Size2i(9, 9));
    data->paint_layer(Vector2(6, 6), 0.75f, 3, 1.0f);
    const Ref<ArrayMesh> chunk = data->build_chunk_mesh(Vector2i(4, 4), Vector2i(4, 4), 2);
    REQUIRE(chunk.is_valid());
    const PackedColorArray colors = chunk->surface_get_arrays(0)[Mesh::ARRAY_COLOR];
    REQUIRE(colors.size() == 9);
    CHECK(colors[4] == Color(0, 0, 0, 1));
    CHECK(colors[0] == Color(1, 0, 0, 0));
}

TEST_CASE("[TerrainChunks] Minimal 1x1 chunk has two triangles") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(Size2i(2, 2));
    const Ref<ArrayMesh> chunk = data->build_chunk_mesh(Vector2i(), Vector2i(1, 1));
    REQUIRE(chunk.is_valid());
    const Array arrays = chunk->surface_get_arrays(0);
    CHECK(PackedInt32Array(arrays[Mesh::ARRAY_INDEX]).size() == 6);
    CHECK(PackedVector3Array(arrays[Mesh::ARRAY_VERTEX]).size() == 4);
}

TEST_CASE("[TerrainChunks] Reject chunks extending beyond the heightmap") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(Size2i(9, 9));
    ERR_PRINT_OFF
    const Ref<ArrayMesh> negative = data->build_chunk_mesh(Vector2i(-1, 0), Vector2i(4, 4));
    const Ref<ArrayMesh> exceed = data->build_chunk_mesh(Vector2i(6, 0), Vector2i(4, 4));
    const Ref<ArrayMesh> zero = data->build_chunk_mesh(Vector2i(), Vector2i(0, 1));
    const Ref<ArrayMesh> huge = data->build_chunk_mesh(Vector2i(), Vector2i(100, 4));
    ERR_PRINT_ON
    CHECK(negative.is_null());
    CHECK(exceed.is_null());
    CHECK(zero.is_null());
    CHECK(huge.is_null());
}

TEST_CASE("[TerrainChunks] Reject invalid LOD stride and chunk alignment") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(Size2i(9, 9));
    ERR_PRINT_OFF
    const Ref<ArrayMesh> zero = data->build_chunk_mesh(Vector2i(), Vector2i(4, 4), 0);
    const Ref<ArrayMesh> too_big = data->build_chunk_mesh(Vector2i(), Vector2i(4, 4), 129);
    const Ref<ArrayMesh> uneven = data->build_chunk_mesh(Vector2i(), Vector2i(5, 4), 2);
    ERR_PRINT_ON
    CHECK(zero.is_null());
    CHECK(too_big.is_null());
    CHECK(uneven.is_null());
}

TEST_CASE("[TerrainChunks] Reject nonfinite chunk scale") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    ERR_PRINT_OFF
    const Ref<ArrayMesh> invalid = data->build_chunk_mesh(Vector2i(), Vector2i(4, 4), 1,
            std::numeric_limits<float>::infinity());
    ERR_PRINT_ON
    CHECK(invalid.is_null());
}

TEST_CASE("[TerrainChunks] Triangle winding faces upward for every LOD") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(Size2i(9, 9));
    for (int stride = 1; stride <= 4; stride *= 2) {
        const Ref<ArrayMesh> mesh = data->build_chunk_mesh(Vector2i(0, 0), Vector2i(8, 8), stride);
        REQUIRE(mesh.is_valid());
        const Array arrays = mesh->surface_get_arrays(0);
        const PackedInt32Array indices = arrays[Mesh::ARRAY_INDEX];
        const PackedVector3Array verts = arrays[Mesh::ARRAY_VERTEX];
        const Vector3 a = verts[indices[0]];
        const Vector3 b = verts[indices[1]];
        const Vector3 c = verts[indices[2]];
        CHECK((b - a).cross(c - a).y > 0);
    }
}

TEST_CASE("[TerrainChunks] Batched editing defers automatic mesh rebuild until edit end") {
    HeightmapTerrain3D node;
    Ref<TerrainHeightmap> data = node.get_terrain_data();
    Ref<Mesh> before = node.get_mesh();
    data->begin_edit();
    data->set_height_at(0, 0, 5.0f);
    data->paint_layer(Vector2(1, 1), 1.0f, 1, 0.5f);
    CHECK(node.get_mesh() == before);
    data->end_edit();
    CHECK(node.get_mesh() != before);
    CHECK(data->get_height_at(0, 0) == 5.0f);
}

TEST_CASE("[TerrainChunks] Nested batches flush only once at the outer end") {
    HeightmapTerrain3D node;
    Ref<TerrainHeightmap> data = node.get_terrain_data();
    Ref<Mesh> before = node.get_mesh();
    data->begin_edit();
    data->begin_edit();
    data->sculpt(Vector2(0, 0), 1, 4);
    data->end_edit();
    CHECK(node.get_mesh() == before);
    data->end_edit();
    CHECK(node.get_mesh() != before);
}

TEST_CASE("[TerrainChunks] No-op batch does not rebuild mesh") {
    HeightmapTerrain3D node;
    Ref<TerrainHeightmap> data = node.get_terrain_data();
    Ref<Mesh> before = node.get_mesh();
    data->begin_edit();
    data->sculpt(Vector2(0, 0), 1, 0);
    data->end_edit();
    CHECK(node.get_mesh() == before);
}

TEST_CASE("[TerrainChunks] Unpaired end_edit does not emit a change or corrupt state") {
    HeightmapTerrain3D node;
    Ref<TerrainHeightmap> data = node.get_terrain_data();
    Ref<Mesh> before = node.get_mesh();
    ERR_PRINT_OFF
    data->end_edit();
    ERR_PRINT_ON
    CHECK(node.get_mesh() == before);
    data->begin_edit();
    data->set_height_at(2, 2, 1);
    data->end_edit();
    CHECK(node.get_mesh() != before);
}

} // namespace TestTerrainChunks
