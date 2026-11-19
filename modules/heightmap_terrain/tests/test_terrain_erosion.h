/**************************************************************************/
/*  test_terrain_erosion.h                                                */
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
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "../terrain_heightmap.h"

#include "tests/test_macros.h"

namespace TestTerrainErosion {

static real_t sum_heights(const Ref<TerrainHeightmap> &p_data) {
    real_t sum = 0;
    for (const float height : p_data->get_heights()) {
        sum += height;
    }
    return sum;
}

TEST_CASE("[Erosion] Flat ground remains flat") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(7, 9);
    const PackedFloat32Array before = data->get_heights();
    data->erode_thermal(32, 0, 0.25);
    CHECK(data->get_heights() == before);
}

TEST_CASE("[Erosion] A single peak distributes to its four neighbors") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(3, 3);
    data->set_height(1, 1, 100);
    data->erode_thermal(1, 0, 0.25);
    CHECK(data->get_height(1, 1) == doctest::Approx(0));
    CHECK(data->get_height(0, 1) == doctest::Approx(25));
    CHECK(data->get_height(2, 1) == doctest::Approx(25));
    CHECK(data->get_height(1, 0) == doctest::Approx(25));
    CHECK(data->get_height(1, 2) == doctest::Approx(25));
    CHECK(data->get_height(0, 0) == doctest::Approx(0));
    CHECK(sum_heights(data) == doctest::Approx(100));
}

TEST_CASE("[Erosion] A single pit receives material from its neighbors") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(3, 3);
    data->set_height(1, 1, -100);
    data->erode_thermal(1, 0, 0.25);
    CHECK(data->get_height(1, 1) == doctest::Approx(0));
    CHECK(data->get_height(0, 1) == doctest::Approx(-25));
    CHECK(data->get_height(2, 1) == doctest::Approx(-25));
    CHECK(data->get_height(1, 0) == doctest::Approx(-25));
    CHECK(data->get_height(1, 2) == doctest::Approx(-25));
    CHECK(sum_heights(data) == doctest::Approx(-100));
}

TEST_CASE("[Erosion] Talus threshold leaves gentle slopes intact") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(3, 3);
    for (int z = 0; z < 3; ++z) {
        for (int x = 0; x < 3; ++x) {
            data->set_height(x, z, x * 2 + z);
        }
    }
    const PackedFloat32Array before = data->get_heights();
    data->erode_thermal(20, 2.0, 0.2);
    CHECK(data->get_heights() == before);
}

TEST_CASE("[Erosion] A finite talus threshold limits each transfer") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(2, 2);
    data->set_height(0, 0, 10);
    data->erode_thermal(1, 2, 0.25);
    CHECK(data->get_height(0, 0) == doctest::Approx(6));
    CHECK(data->get_height(1, 0) == doctest::Approx(2));
    CHECK(data->get_height(0, 1) == doctest::Approx(2));
    CHECK(data->get_height(1, 1) == doctest::Approx(0));
    CHECK(sum_heights(data) == doctest::Approx(10));
}

TEST_CASE("[Erosion] Zero strength and zero iterations are no-ops") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(3, 3);
    data->set_height(1, 1, 100);
    const PackedFloat32Array before = data->get_heights();
    data->erode_thermal(0, 0, 0.25);
    data->erode_thermal(100, 0, 0);
    CHECK(data->get_heights() == before);
}

TEST_CASE("[Erosion] Repeated erosion conserves approximate total height") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(7, 7);
    for (int z = 0; z < 7; ++z) {
        for (int x = 0; x < 7; ++x) {
            data->set_height(x, z, (x + 3 * z) % 5 * 10);
        }
    }
    const real_t total_before = sum_heights(data);
    data->erode_thermal(60, 0.1, 0.15);
    CHECK(sum_heights(data) == doctest::Approx(total_before).epsilon(0.0001));
}

TEST_CASE("[Erosion] Boundary cells do not leak mass from the grid") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(5, 5);
    data->set_height(0, 0, 40);
    data->erode_thermal(1, 0, 0.25);
    CHECK(data->get_height(0, 0) == doctest::Approx(20));
    CHECK(data->get_height(1, 0) == doctest::Approx(10));
    CHECK(data->get_height(0, 1) == doctest::Approx(10));
    CHECK(sum_heights(data) == doctest::Approx(40));
}

TEST_CASE("[Erosion] Identical inputs produce identical erosion results") {
    Ref<TerrainHeightmap> first;
    Ref<TerrainHeightmap> second;
    first.instantiate();
    second.instantiate();
    first->set_dimensions(5, 5);
    second->set_dimensions(5, 5);
    for (int z = 0; z < 5; ++z) {
        for (int x = 0; x < 5; ++x) {
            first->set_height(x, z, (x * x - z * z) * 3);
        }
    }
    second->set_heights(first->get_heights());
    first->erode_thermal(15, 0.5, 0.2);
    second->erode_thermal(15, 0.5, 0.2);
    CHECK(first->get_heights() == second->get_heights());
}

TEST_CASE("[Erosion] Long erosion run remains finite") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(9, 9);
    for (int z = 0; z < 9; ++z) {
        for (int x = 0; x < 9; ++x) {
            data->set_height(x, z, ((x * 7 + z * 3) % 11) * 1.25);
        }
    }
    data->erode_thermal(128, 0.001, 0.2);
    for (const float value : data->get_heights()) {
        CHECK(Math::is_finite(value));
    }
}

TEST_CASE("[Erosion] Reject invalid settings without corrupting heights") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(3, 3);
    data->set_height(1, 1, 10);
    const PackedFloat32Array snapshot = data->get_heights();
    ERR_PRINT_OFF;
    data->erode_thermal(-1, 0, 0.2);
    data->erode_thermal(129, 0, 0.2);
    data->erode_thermal(1, -1, 0.2);
    data->erode_thermal(1, Math::NaN, 0.2);
    data->erode_thermal(1, 0, -0.1);
    data->erode_thermal(1, 0, 0.5);
    data->erode_thermal(1, 0, Math::NaN);
    ERR_PRINT_ON;
    CHECK(data->get_heights() == snapshot);
}

TEST_CASE("[Erosion] Height array snapshots allow undo and redo") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(5, 5);
    data->set_height(2, 2, 10);
    const PackedFloat32Array before = data->get_heights();
    data->erode_thermal(8, 0.1, 0.15);
    const PackedFloat32Array after = data->get_heights();
    CHECK(before != after);
    data->set_heights(before);
    CHECK(data->get_heights() == before);
    data->set_heights(after);
    CHECK(data->get_heights() == after);
}

} // namespace TestTerrainErosion
