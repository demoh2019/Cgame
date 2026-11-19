/**************************************************************************/
/*  test_terrain_splatmap.h                                               */
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
/* SOFTWARE OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE   */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "../heightmap_terrain_3d.h"
#include "../terrain_splatmap.h"

#include "core/io/image.h"
#include "scene/resources/image_texture.h"
#include "scene/resources/material.h"
#include "tests/test_macros.h"

namespace TestTerrainSplatmap {

TEST_CASE("[Splatmap] Default RGBA weights choose base layer") {
    Ref<TerrainSplatmap> data;
    data.instantiate();
    CHECK(data->get_width() == 17);
    CHECK(data->get_depth() == 17);
    CHECK(data->get_weights().size() == 289);
    for (int z = 0; z < 17; ++z) {
        for (int x = 0; x < 17; ++x) {
            CHECK(data->get_weights_at(x, z) == Color(1, 0, 0, 0));
            CHECK(data->get_layer_weight(x, z, 0) == 1);
            CHECK(data->get_layer_weight(x, z, 1) == 0);
        }
    }
}

TEST_CASE("[Splatmap] Resize preserves overlap and initializes new vertices") {
    Ref<TerrainSplatmap> data;
    data.instantiate();
    data->set_dimensions(3, 3);
    data->paint_layer(2, Vector2(1, 1), 0.8, 1);
    CHECK(data->get_weights_at(1, 1) == Color(0, 0, 1, 0));
    data->set_dimensions(5, 4);
    CHECK(data->get_width() == 5);
    CHECK(data->get_depth() == 4);
    CHECK(data->get_weights_at(1, 1) == Color(0, 0, 1, 0));
    CHECK(data->get_weights_at(4, 3) == Color(1, 0, 0, 0));
    data->set_dimensions(2, 2);
    data->set_dimensions(3, 3);
    CHECK(data->get_weights_at(2, 2) == Color(1, 0, 0, 0));
}

TEST_CASE("[Splatmap] Full-strength brush switches target layer") {
    Ref<TerrainSplatmap> data;
    data.instantiate();
    data->set_dimensions(5, 5);
    for (int i = 0; i < 4; ++i) {
        data->paint_layer(i, Vector2(2, 2), 0.9, 1);
        const Color mask = data->get_weights_at(2, 2);
        for (int layer = 0; layer < 4; ++layer) {
            CHECK(mask[layer] == doctest::Approx(layer == i ? 1 : 0));
        }
    }
}

TEST_CASE("[Splatmap] Brush falloff preserves normalized weights") {
    Ref<TerrainSplatmap> data;
    data.instantiate();
    data->set_dimensions(7, 7);
    data->paint_layer(1, Vector2(3, 3), 3, 1);
    CHECK(data->get_weights_at(3, 3) == Color(0, 1, 0, 0));
    CHECK(data->get_weights_at(4, 3).r == doctest::Approx(1.0 / 3).epsilon(1e-5));
    CHECK(data->get_weights_at(4, 3).g == doctest::Approx(2.0 / 3).epsilon(1e-5));
    CHECK(data->get_weights_at(5, 3).r == doctest::Approx(2.0 / 3).epsilon(1e-5));
    CHECK(data->get_weights_at(6, 3) == Color(1, 0, 0, 0));
    for (int z = 0; z < 7; ++z) {
        for (int x = 0; x < 7; ++x) {
            const Color w = data->get_weights_at(x, z);
            CHECK(w.r + w.g + w.b + w.a == doctest::Approx(1.0).epsilon(1e-5));
            CHECK(w.r >= 0);
            CHECK(w.g >= 0);
            CHECK(w.b >= 0);
            CHECK(w.a >= 0);
        }
    }
}

TEST_CASE("[Splatmap] Repeated mixing preserves sum and nonnegative channels") {
    Ref<TerrainSplatmap> data;
    data.instantiate();
    data->set_dimensions(5, 5);
    for (int i = 0; i < 150; ++i) {
        data->paint_layer(i % 4, Vector2(2, 2), 2.5, 0.25);
    }
    for (int z = 0; z < 5; ++z) {
        for (int x = 0; x < 5; ++x) {
            const Color w = data->get_weights_at(x, z);
            CHECK(w.r + w.g + w.b + w.a == doctest::Approx(1.0).epsilon(1e-5));
            for (int layer = 0; layer < 4; ++layer) {
                CHECK(w[layer] >= 0);
                CHECK(w[layer] <= 1);
            }
        }
    }
}

TEST_CASE("[Splatmap] Zero and negative strength do not modify anything") {
    Ref<TerrainSplatmap> data;
    data.instantiate();
    data->set_dimensions(3, 3);
    const PackedColorArray previous = data->get_weights();
    data->paint_layer(3, Vector2(1, 1), 3, 0);
    data->paint_layer(3, Vector2(1, 1), 3, -10);
    CHECK(data->get_weights() == previous);
}

TEST_CASE("[Splatmap] Strength above one gets clamped") {
    Ref<TerrainSplatmap> data;
    data.instantiate();
    data->set_dimensions(3, 3);
    data->paint_layer(3, Vector2(1, 1), 3, 999);
    CHECK(data->get_weights_at(1, 1) == Color(0, 0, 0, 1));
}

TEST_CASE("[Splatmap] Out-of-range far-away brush cannot overflow indices") {
    Ref<TerrainSplatmap> data;
    data.instantiate();
    data->set_dimensions(3, 3);
    const PackedColorArray previous = data->get_weights();
    for (int layer = 0; layer < 4; ++layer) {
        data->paint_layer(layer, Vector2(1e20, 1e20), 10, 1);
        data->paint_layer(layer, Vector2(-1e20, -1e20), 10, 1);
    }
    CHECK(data->get_weights() == previous);
}

TEST_CASE("[Splatmap] Invalid brush parameters cannot mutate resource") {
    Ref<TerrainSplatmap> data;
    data.instantiate();
    const PackedColorArray before = data->get_weights();
    ERR_PRINT_OFF;
    data->paint_layer(-1, Vector2(1, 1), 2, 1);
    data->paint_layer(4, Vector2(1, 1), 2, 1);
    data->paint_layer(1, Vector2(1, 1), 0, 1);
    data->paint_layer(1, Vector2(1, 1), -1, 1);
    data->paint_layer(1, Vector2(Math::NaN, 0), 1, 1);
    data->paint_layer(1, Vector2(1, 1), 2, Math::NaN);
    ERR_PRINT_ON;
    CHECK(data->get_weights() == before);
}

TEST_CASE("[Splatmap] Reject invalid and non-normalized weight arrays") {
    Ref<TerrainSplatmap> data;
    data.instantiate();
    data->set_dimensions(2, 2);
    const PackedColorArray before = data->get_weights();
    PackedColorArray invalid;
    invalid.resize(4);
    invalid.set(0, Color(0, 0, 0, 0));
    invalid.set(1, Color(-0.1, 1.1, 0, 0));
    invalid.set(2, Color(Math::NaN, 0, 0, 1));
    ERR_PRINT_OFF;
    data->set_weights(invalid);
    invalid.set(0, Color(1, 0, 0, 0));
    data->set_weights(invalid);
    invalid.set(1, Color(0, 1, 0, 0));
    data->set_weights(invalid);
    invalid.set(2, Color(0, 0, 1, 0));
    invalid.set(3, Color(0, 0, 0, 0));
    data->set_weights(invalid);
    ERR_PRINT_ON;
    CHECK(data->get_weights() == before);
}

TEST_CASE("[Splatmap] Reject dimensions outside safe range") {
    Ref<TerrainSplatmap> data;
    data.instantiate();
    data->set_dimensions(3, 2);
    ERR_PRINT_OFF;
    data->set_dimensions(0, 2);
    data->set_dimensions(2, 1);
    data->set_dimensions(514, 2);
    ERR_PRINT_ON;
    CHECK(data->get_width() == 3);
    CHECK(data->get_depth() == 2);
    CHECK(data->get_weights().size() == 6);
}

TEST_CASE("[Splatmap] Exact mask arrays can be restored for Undo/Redo") {
    Ref<TerrainSplatmap> data;
    data.instantiate();
    const PackedColorArray before = data->get_weights();
    data->paint_layer(1, Vector2(8, 8), 3, 1);
    const PackedColorArray after = data->get_weights();
    CHECK(after != before);
    data->set_weights(before);
    CHECK(data->get_weights() == before);
    data->set_weights(after);
    CHECK(data->get_weights() == after);
}

TEST_CASE("[Splatmap] RGBA image export maps weights into correct pixels") {
    Ref<TerrainSplatmap> data;
    data.instantiate();
    data->set_dimensions(3, 2);
    data->paint_layer(2, Vector2(1, 0), 0.5, 1);
    const Ref<Image> image = data->to_image();
    REQUIRE(image.is_valid());
    CHECK(image->get_width() == 3);
    CHECK(image->get_height() == 2);
    CHECK(image->get_format() == Image::FORMAT_RGBA8);
    CHECK(image->get_pixel(1, 0) == Color(0, 0, 1, 0));
    CHECK(image->get_pixel(2, 1) == Color(1, 0, 0, 0));
}

TEST_CASE("[Splatmap] Layer 0 can be restored after painting layer 3") {
    Ref<TerrainSplatmap> data;
    data.instantiate();
    data->set_dimensions(3, 3);
    data->paint_layer(3, Vector2(1, 1), 1, 1);
    data->paint_layer(0, Vector2(1, 1), 1, 1);
    CHECK(data->get_weights_at(1, 1) == Color(1, 0, 0, 0));
}

TEST_CASE("[Splatmap] Heightmap resizing synchronizes splatmap dimensions") {
    HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
    REQUIRE(terrain->get_splatmap().is_valid());
    terrain->get_heightmap()->set_dimensions(9, 13);
    CHECK(terrain->get_splatmap()->get_width() == 9);
    CHECK(terrain->get_splatmap()->get_depth() == 13);
    CHECK(terrain->get_splatmap()->get_weights().size() == 117);
    memdelete(terrain);
}

TEST_CASE("[Splatmap] Node exposes four texture layers") {
    HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
    Ref<Image> image = Image::create_empty(2, 2, false, Image::FORMAT_RGBA8);
    image->fill(Color(0, 1, 0));
    Ref<ImageTexture> green = ImageTexture::create_from_image(image);
    terrain->set_layer_1(green);
    CHECK(terrain->get_layer_0().is_null());
    CHECK(terrain->get_layer_1() == green);
    CHECK(terrain->get_layer_2().is_null());
    CHECK(terrain->get_layer_3().is_null());
    Ref<Mesh> mesh = terrain->get_mesh();
    REQUIRE(mesh.is_valid());
    CHECK(mesh->get_surface_count() == 1);
    CHECK(Object::cast_to<ShaderMaterial>(mesh->surface_get_material(0).ptr()) != nullptr);
    terrain->set_layer_1(Ref<Texture2D>());
    CHECK(Object::cast_to<ShaderMaterial>(terrain->get_mesh()->surface_get_material(0).ptr()) == nullptr);
    memdelete(terrain);
}

TEST_CASE("[Splatmap] Painting mask does not rebuild geometry") {
    HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
    Ref<Image> image = Image::create_empty(2, 2, false, Image::FORMAT_RGBA8);
    image->fill(Color(1, 1, 1));
    terrain->set_layer_0(ImageTexture::create_from_image(image));
    Ref<Mesh> existing = terrain->get_mesh();
    terrain->get_splatmap()->paint_layer(2, Vector2(8, 8), 3, 1);
    CHECK(terrain->get_mesh() == existing);
    CHECK(terrain->get_splatmap()->get_weights_at(8, 8) == Color(0, 0, 1, 0));
    memdelete(terrain);
}

TEST_CASE("[Splatmap] Texture tiling validates input") {
    HeightmapTerrain3D *terrain = memnew(HeightmapTerrain3D);
    terrain->set_texture_tiling(12);
    ERR_PRINT_OFF;
    terrain->set_texture_tiling(-2);
    terrain->set_texture_tiling(0);
    terrain->set_texture_tiling(257);
    terrain->set_texture_tiling(Math::NaN);
    ERR_PRINT_ON;
    CHECK(terrain->get_texture_tiling() == doctest::Approx(12));
    memdelete(terrain);
}

} // namespace TestTerrainSplatmap
