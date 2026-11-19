/**************************************************************************/
/*  test_heightmap_terrain.h                                              */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
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

#include "../heightmap_terrain_3d.h"
#include "../terrain_heightmap.h"

#include "core/io/image.h"
#include "tests/test_macros.h"

namespace TestHeightmapTerrain {

TEST_CASE("[Terrain] Default grid dimensions and storage") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    CHECK(data->get_width() == 17);
    CHECK(data->get_depth() == 17);
    CHECK(data->get_heights().size() == 17 * 17);
    CHECK(data->get_colors().size() == 17 * 17);
    for (int z = 0; z < data->get_depth(); ++z) {
        for (int x = 0; x < data->get_width(); ++x) {
            CHECK(data->get_height(x, z) == 0.0);
            CHECK(data->get_color(x, z) == Color(1, 1, 1));
        }
    }
}

TEST_CASE("[Terrain] Resize keeps intersecting samples and initializes new samples") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(3, 3);
    data->set_height(1, 1, 12);
    data->set_height(2, 2, -4);
    data->set_dimensions(5, 4);
    CHECK(data->get_width() == 5);
    CHECK(data->get_depth() == 4);
    CHECK(data->get_height(1, 1) == 12);
    CHECK(data->get_height(2, 2) == -4);
    CHECK(data->get_height(4, 3) == 0);
    CHECK(data->get_color(4, 3) == Color(1, 1, 1));
    data->set_dimensions(2, 2);
    CHECK(data->get_height(1, 1) == 12);
    data->set_dimensions(3, 3);
    CHECK(data->get_height(2, 2) == 0);
}

TEST_CASE("[Terrain] Individual height writes preserve other samples") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(3, 3);
    data->set_height(0, 0, -2);
    data->set_height(2, 2, 5);
    CHECK(data->get_height(0, 0) == -2);
    CHECK(data->get_height(2, 2) == 5);
    CHECK(data->get_height(1, 1) == 0);
    CHECK(data->get_heights().size() == 9);
}

TEST_CASE("[Terrain] Bilinear sampling and clamped edges") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(2, 2);
    data->set_height(0, 0, 0);
    data->set_height(1, 0, 10);
    data->set_height(0, 1, 20);
    data->set_height(1, 1, 30);
    CHECK(data->sample_height(0, 0) == doctest::Approx(0));
    CHECK(data->sample_height(1, 1) == doctest::Approx(30));
    CHECK(data->sample_height(0.5, 0.5) == doctest::Approx(15));
    CHECK(data->sample_height(0.25, 0.75) == doctest::Approx(17.5));
    CHECK(data->sample_height(-4, -4) == doctest::Approx(0));
    CHECK(data->sample_height(4, 4) == doctest::Approx(30));
}

TEST_CASE("[Terrain] Height brush raises center and has linear falloff") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(7, 7);
    data->apply_height_brush(Vector2(3, 3), 3, 6);
    CHECK(data->get_height(3, 3) == doctest::Approx(6));
    CHECK(data->get_height(4, 3) == doctest::Approx(4));
    CHECK(data->get_height(5, 3) == doctest::Approx(2));
    CHECK(data->get_height(6, 3) == doctest::Approx(0));
    CHECK(data->get_height(0, 0) == doctest::Approx(0));
    data->apply_height_brush(Vector2(3, 3), 3, -6);
    CHECK(data->get_height(3, 3) == doctest::Approx(0));
    CHECK(data->get_height(4, 3) == doctest::Approx(0));
}

TEST_CASE("[Terrain] Height brush clamps to borders and ignores distant locations") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(3, 4);
    data->apply_height_brush(Vector2(0, 0), 1.5, 3);
    CHECK(data->get_height(0, 0) == doctest::Approx(3));
    CHECK(data->get_height(1, 0) > 0);
    CHECK(data->get_height(2, 3) == 0);
    const PackedFloat32Array snapshot = data->get_heights();
    data->apply_height_brush(Vector2(1000, 1000), 3, 7);
    CHECK(snapshot == data->get_heights());
    data->apply_height_brush(Vector2(0, 0), 1, 0);
    CHECK(snapshot == data->get_heights());
}

TEST_CASE("[Terrain] Color brush only modifies nearby vertices") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(5, 5);
    data->apply_color_brush(Vector2(2, 2), 2, Color(1, 0, 0), 1);
    CHECK(data->get_color(2, 2) == Color(1, 0, 0));
    CHECK(data->get_color(4, 2) == Color(1, 1, 1));
    CHECK(data->get_color(0, 0) == Color(1, 1, 1));
    const Color near = data->get_color(3, 2);
    CHECK(near.g == doctest::Approx(0.5));
    CHECK(near.b == doctest::Approx(0.5));
}

TEST_CASE("[Terrain] Color brush strength is clamped and zero is a no-op") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(3, 3);
    const PackedColorArray before = data->get_colors();
    data->apply_color_brush(Vector2(1, 1), 2, Color(0, 0, 0), 0);
    CHECK(data->get_colors() == before);
    data->apply_color_brush(Vector2(1, 1), 2, Color(0, 0, 0), 999);
    CHECK(data->get_color(1, 1) == Color(0, 0, 0));
    data->apply_color_brush(Vector2(1, 1), 2, Color(1, 0, 0), -5);
    CHECK(data->get_color(1, 1) == Color(0, 0, 0));
}

TEST_CASE("[Terrain] Packed arrays can be restored for Undo/Redo") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(4, 4);
    const PackedFloat32Array before = data->get_heights();
    const PackedColorArray before_color = data->get_colors();
    data->apply_height_brush(Vector2(1, 1), 2, 10);
    data->apply_color_brush(Vector2(1, 1), 2, Color(0, 0, 1), 1);
    const PackedFloat32Array after = data->get_heights();
    const PackedColorArray after_color = data->get_colors();
    CHECK(before != after);
    CHECK(before_color != after_color);
    data->set_heights(before);
    data->set_colors(before_color);
    CHECK(data->get_heights() == before);
    CHECK(data->get_colors() == before_color);
    data->set_heights(after);
    data->set_colors(after_color);
    CHECK(data->get_heights() == after);
    CHECK(data->get_colors() == after_color);
}

TEST_CASE("[Terrain] Import grayscale Image with height range") {
    Ref<Image> image = Image::create_empty(2, 2, false, Image::FORMAT_RF);
    image->set_pixel(0, 0, Color(0, 0, 0));
    image->set_pixel(1, 0, Color(1, 1, 1));
    image->set_pixel(0, 1, Color(0.25, 0.25, 0.25));
    image->set_pixel(1, 1, Color(0.5, 0.5, 0.5));
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->import_height_image(image, -10, 30);
    CHECK(data->get_width() == 2);
    CHECK(data->get_depth() == 2);
    CHECK(data->get_height(0, 0) == doctest::Approx(-10));
    CHECK(data->get_height(1, 0) == doctest::Approx(30));
    CHECK(data->get_height(0, 1) == doctest::Approx(0));
    CHECK(data->get_height(1, 1) == doctest::Approx(10));
}

TEST_CASE("[Terrain] Generated mesh has valid upward winding and UVs") {
    HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
    terrain->get_heightmap()->set_dimensions(3, 2);
    Ref<ArrayMesh> mesh = terrain->build_mesh();
    REQUIRE(mesh.is_valid());
    REQUIRE(mesh->get_surface_count() == 1);
    const Array arrays = mesh->surface_get_arrays(0);
    const PackedVector3Array verts = arrays[Mesh::ARRAY_VERTEX];
    const PackedVector3Array normals = arrays[Mesh::ARRAY_NORMAL];
    const PackedVector2Array uv = arrays[Mesh::ARRAY_TEX_UV];
    const PackedInt32Array index = arrays[Mesh::ARRAY_INDEX];
    CHECK(verts.size() == 6);
    CHECK(normals.size() == 6);
    CHECK(uv.size() == 6);
    CHECK(index.size() == 12);
    for (int i = 0; i < normals.size(); ++i) {
        CHECK(normals[i].is_equal_approx(Vector3(0, 1, 0)));
    }
    for (int i = 0; i < index.size(); i += 3) {
        const Vector3 edge0 = verts[index[i + 1]] - verts[index[i]];
        const Vector3 edge1 = verts[index[i + 2]] - verts[index[i]];
        CHECK(edge0.cross(edge1).y > 0);
    }
    CHECK(uv[0] == Vector2(0, 0));
    CHECK(uv[5] == Vector2(1, 1));
    memdelete(terrain);
}

TEST_CASE("[Terrain] Mesh geometry updates when heightmap changes") {
    HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
    terrain->get_heightmap()->set_dimensions(3, 3);
    terrain->get_heightmap()->set_height(1, 1, 8);
    Ref<Mesh> mesh = terrain->get_mesh();
    REQUIRE(mesh.is_valid());
    const Array arrays = mesh->surface_get_arrays(0);
    const PackedVector3Array verts = arrays[Mesh::ARRAY_VERTEX];
    CHECK(verts[4].y == doctest::Approx(8));
    CHECK(terrain->sample_height_local(1, 1) == doctest::Approx(8));
    memdelete(terrain);
}

TEST_CASE("[Terrain] Mesh cell size changes vertex coordinates and sampling") {
    HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
    terrain->get_heightmap()->set_dimensions(2, 2);
    terrain->get_heightmap()->set_height(1, 1, 6);
    terrain->set_cell_size(2);
    const Array arrays = terrain->build_mesh()->surface_get_arrays(0);
    const PackedVector3Array verts = arrays[Mesh::ARRAY_VERTEX];
    CHECK(verts[3] == Vector3(2, 6, 2));
    CHECK(terrain->sample_height_local(2, 2) == doctest::Approx(6));
    CHECK(terrain->sample_height_local(1, 1) == doctest::Approx(1.5));
    memdelete(terrain);
}

TEST_CASE("[Terrain] Generated mesh passes painted vertex colors") {
    HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
    terrain->get_heightmap()->set_dimensions(2, 2);
    terrain->get_heightmap()->apply_color_brush(Vector2(0, 0), 0.5, Color(0, 1, 0), 1);
    const Array arrays = terrain->build_mesh()->surface_get_arrays(0);
    const PackedColorArray colors = arrays[Mesh::ARRAY_COLOR];
    CHECK(colors.size() == 4);
    CHECK(colors[0] == Color(0, 1, 0));
    CHECK(colors[3] == Color(1, 1, 1));
    memdelete(terrain);
}

TEST_CASE("[Terrain] Brush accepts very large off-map coordinates without mutation") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(3, 3);
    const PackedFloat32Array before_height = data->get_heights();
    const PackedColorArray before_color = data->get_colors();
    data->apply_height_brush(Vector2(1e20, 1e20), 3, 7);
    data->apply_height_brush(Vector2(-1e20, -1e20), 3, 7);
    data->apply_color_brush(Vector2(1e20, 1e20), 3, Color(0, 1, 0), 1);
    data->apply_color_brush(Vector2(-1e20, -1e20), 3, Color(0, 1, 0), 1);
    CHECK(data->get_heights() == before_height);
    CHECK(data->get_colors() == before_color);
}

TEST_CASE("[Terrain] Invalid resolution never corrupts the grid") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(3, 3);
    data->set_height(1, 1, 4);
    ERR_PRINT_OFF;
    data->set_dimensions(0, 3);
    data->set_dimensions(3, 1);
    data->set_dimensions(TerrainHeightmap::MAX_RESOLUTION + 1, 3);
    ERR_PRINT_ON;
    CHECK(data->get_width() == 3);
    CHECK(data->get_depth() == 3);
    CHECK(data->get_heights().size() == 9);
    CHECK(data->get_height(1, 1) == 4);
}

TEST_CASE("[Terrain] Invalid height arrays cannot overwrite valid samples") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(2, 2);
    data->set_height(1, 1, 7);
    PackedFloat32Array short_array;
    short_array.resize(3);
    PackedFloat32Array nan_array;
    nan_array.resize(4);
    nan_array.set(2, Math::NaN);
    ERR_PRINT_OFF;
    data->set_heights(short_array);
    data->set_heights(nan_array);
    ERR_PRINT_ON;
    CHECK(data->get_height(1, 1) == 7);
    CHECK(data->get_heights().size() == 4);
}

TEST_CASE("[Terrain] Invalid color arrays cannot overwrite valid colors") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(2, 2);
    data->apply_color_brush(Vector2(0, 0), 0.5, Color(0, 0, 1), 1);
    PackedColorArray short_array;
    short_array.resize(3);
    PackedColorArray nan_array;
    nan_array.resize(4);
    nan_array.set(2, Color(Math::NaN, 0, 0));
    ERR_PRINT_OFF;
    data->set_colors(short_array);
    data->set_colors(nan_array);
    ERR_PRINT_ON;
    CHECK(data->get_color(0, 0) == Color(0, 0, 1));
    CHECK(data->get_colors().size() == 4);
}

TEST_CASE("[Terrain] Heightmap can be shared between multiple terrain nodes") {
    Ref<TerrainHeightmap> shared;
    shared.instantiate();
    shared->set_dimensions(2, 2);
    HeightmapTerrain3D *a = memnew(HeightmapTerrain3D);
    HeightmapTerrain3D *b = memnew(HeightmapTerrain3D);
    a->set_heightmap(shared);
    b->set_heightmap(shared);
    shared->set_height(1, 1, 4);
    const Array a_arrays = a->get_mesh()->surface_get_arrays(0);
    const Array b_arrays = b->get_mesh()->surface_get_arrays(0);
    const PackedVector3Array a_vertices = a_arrays[Mesh::ARRAY_VERTEX];
    const PackedVector3Array b_vertices = b_arrays[Mesh::ARRAY_VERTEX];
    CHECK(a_vertices[3].y == doctest::Approx(4));
    CHECK(b_vertices[3].y == doctest::Approx(4));
    memdelete(a);
    memdelete(b);
}

TEST_CASE("[Terrain] Switching heightmap disconnects old resource updates") {
    Ref<TerrainHeightmap> first;
    Ref<TerrainHeightmap> second;
    first.instantiate();
    second.instantiate();
    first->set_dimensions(2, 2);
    second->set_dimensions(2, 2);
    HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
    terrain->set_heightmap(first);
    terrain->set_heightmap(second);
    first->set_height(1, 1, 100);
    const Array old_arrays = terrain->get_mesh()->surface_get_arrays(0);
    const PackedVector3Array old_vertices = old_arrays[Mesh::ARRAY_VERTEX];
    CHECK(old_vertices[3].y == doctest::Approx(0));
    second->set_height(1, 1, 9);
    const Array new_arrays = terrain->get_mesh()->surface_get_arrays(0);
    const PackedVector3Array new_vertices = new_arrays[Mesh::ARRAY_VERTEX];
    CHECK(new_vertices[3].y == doctest::Approx(9));
    memdelete(terrain);
}

TEST_CASE("[Terrain] Sloped mesh produces finite unit normals") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(3, 3);
    for (int z = 0; z < 3; ++z) {
        for (int x = 0; x < 3; ++x) {
            data->set_height(x, z, x + z);
        }
    }
    HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
    terrain->set_heightmap(data);
    const Array arrays = terrain->build_mesh()->surface_get_arrays(0);
    const PackedVector3Array normals = arrays[Mesh::ARRAY_NORMAL];
    REQUIRE(normals.size() == 9);
    for (int i = 0; i < normals.size(); ++i) {
        CHECK(normals[i].is_finite());
        CHECK(normals[i].length() == doctest::Approx(1.0));
        CHECK(normals[i].y > 0);
    }
    CHECK(normals[4].is_equal_approx(Vector3(-1, 1, -1).normalized()));
    memdelete(terrain);
}

TEST_CASE("[Terrain] Invalid cell size keeps the last valid mesh scaling") {
    HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
    terrain->set_cell_size(5);
    ERR_PRINT_OFF;
    terrain->set_cell_size(0);
    terrain->set_cell_size(-1);
    terrain->set_cell_size(Math::NaN);
    ERR_PRINT_ON;
    CHECK(terrain->get_cell_size() == 5);
    const Array arrays = terrain->build_mesh()->surface_get_arrays(0);
    const PackedVector3Array verts = arrays[Mesh::ARRAY_VERTEX];
    CHECK(verts[1].x == doctest::Approx(5));
    memdelete(terrain);
}

TEST_CASE("[Terrain] Import R8 grayscale Image uses the red channel") {
    Ref<Image> image = Image::create_empty(2, 2, false, Image::FORMAT_R8);
    image->set_pixel(0, 0, Color(0, 0, 0));
    image->set_pixel(1, 0, Color(1, 0, 0));
    image->set_pixel(0, 1, Color(0.5, 0, 0));
    image->set_pixel(1, 1, Color(0.75, 0, 0));
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->import_height_image(image, 0, 100);
    CHECK(data->get_height(0, 0) == doctest::Approx(0));
    CHECK(data->get_height(1, 0) == doctest::Approx(100));
    CHECK(data->get_height(0, 1) == doctest::Approx(50).epsilon(0.02));
    CHECK(data->get_height(1, 1) == doctest::Approx(75).epsilon(0.02));
}

TEST_CASE("[Terrain] Import RGB Image uses luminance for colored pixels") {
    Ref<Image> image = Image::create_empty(2, 2, false, Image::FORMAT_RGBF);
    image->set_pixel(0, 0, Color(1, 0, 0));
    image->set_pixel(1, 0, Color(0, 1, 0));
    image->set_pixel(0, 1, Color(0, 0, 1));
    image->set_pixel(1, 1, Color(1, 1, 1));
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->import_height_image(image, 0, 1);
    CHECK(data->get_height(0, 0) == doctest::Approx(Color(1, 0, 0).get_luminance()));
    CHECK(data->get_height(1, 0) == doctest::Approx(Color(0, 1, 0).get_luminance()));
    CHECK(data->get_height(0, 1) == doctest::Approx(Color(0, 0, 1).get_luminance()));
    CHECK(data->get_height(1, 1) == doctest::Approx(1));
}

TEST_CASE("[Terrain] Import clamps out-of-range float samples") {
    Ref<Image> image = Image::create_empty(2, 2, false, Image::FORMAT_RF);
    image->set_pixel(0, 0, Color(-2, 0, 0));
    image->set_pixel(1, 0, Color(2, 0, 0));
    image->set_pixel(0, 1, Color(0.5, 0, 0));
    image->set_pixel(1, 1, Color(1, 0, 0));
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->import_height_image(image, 10, 20);
    CHECK(data->get_height(0, 0) == doctest::Approx(10));
    CHECK(data->get_height(1, 0) == doctest::Approx(20));
    CHECK(data->get_height(0, 1) == doctest::Approx(15));
    CHECK(data->get_height(1, 1) == doctest::Approx(20));
}

TEST_CASE("[Terrain] Import accepts constant height range") {
    Ref<Image> image = Image::create_empty(2, 2, false, Image::FORMAT_RF);
    image->set_pixel(0, 0, Color(0, 0, 0));
    image->set_pixel(1, 1, Color(1, 0, 0));
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->import_height_image(image, 7, 7);
    CHECK(data->get_height(0, 0) == doctest::Approx(7));
    CHECK(data->get_height(1, 0) == doctest::Approx(7));
    CHECK(data->get_height(0, 1) == doctest::Approx(7));
    CHECK(data->get_height(1, 1) == doctest::Approx(7));
}

} // namespace TestHeightmapTerrain
