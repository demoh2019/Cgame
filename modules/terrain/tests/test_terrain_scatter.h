/**************************************************************************/
/*  test_terrain_scatter.h                                                */
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
/* permit persons to whom the Software is furnished to so, subject to the */
/* following conditions:                                                  */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/**************************************************************************/

#pragma once

#include "../terrain_heightmap.h"
#include "tests/test_macros.h"

#include <limits>

namespace TestTerrainScatter {

TEST_CASE("[TerrainScatter] Flat terrain creates one candidate per spacing grid cell") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(Size2i(5, 5));
    const PackedVector3Array positions = data->scatter_points(1, 2.0f, 0.0f);
    REQUIRE(positions.size() == 4);
    CHECK(positions[0] == Vector3(1, 0, 1));
    CHECK(positions[1] == Vector3(3, 0, 1));
    CHECK(positions[2] == Vector3(1, 0, 3));
    CHECK(positions[3] == Vector3(3, 0, 3));
}

TEST_CASE("[TerrainScatter] Identical seeds and parameters are deterministic") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(Size2i(17, 17));
    const PackedVector3Array first = data->scatter_points(42, 2.0f, 1.0f);
    const PackedVector3Array second = data->scatter_points(42, 2.0f, 1.0f);
    CHECK(first.size() == 64);
    CHECK(first == second);
}

TEST_CASE("[TerrainScatter] Different seeds vary jittered candidate positions") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(Size2i(17, 17));
    const PackedVector3Array a = data->scatter_points(1, 2.0f, 0.9f);
    const PackedVector3Array b = data->scatter_points(2, 2.0f, 0.9f);
    CHECK(a.size() == b.size());
    CHECK(a != b);
}

TEST_CASE("[TerrainScatter] Zero jitter produces stable grid independent of seed") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(Size2i(5, 5));
    const PackedVector3Array a = data->scatter_points(1, 1.0f, 0);
    const PackedVector3Array b = data->scatter_points(500, 1.0f, 0);
    CHECK(a == b);
}

TEST_CASE("[TerrainScatter] Elevation matches heightmap samples at generated positions") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(Size2i(5, 5));
    for (int z = 0; z < 5; z++) {
        for (int x = 0; x < 5; x++) {
            data->set_height_at(x, z, float(x));
        }
    }
    const PackedVector3Array points = data->scatter_points(1, 2.0f, 0, 89.0f);
    REQUIRE(points.size() == 4);
    for (const Vector3 &p : points) {
        CHECK(p.y == doctest::Approx(p.x));
    }
}

TEST_CASE("[TerrainScatter] Reject steep slopes when maximum angle is low") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(Size2i(9, 9));
    for (int z = 0; z < 9; z++) {
        for (int x = 0; x < 9; x++) {
            data->set_height_at(x, z, float(x * 10));
        }
    }
    const PackedVector3Array flat_only = data->scatter_points(1, 2, 0, 5.0f);
    const PackedVector3Array all = data->scatter_points(1, 2, 0, 90.0f);
    CHECK(flat_only.is_empty());
    CHECK(all.size() == 16);
}

TEST_CASE("[TerrainScatter] Height window excludes inaccessible elevations") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(Size2i(5, 5));
    data->set_heights(PackedFloat32Array());
    // The invalid bulk setter does not mutate the resource.
    for (int z = 0; z < 5; z++) {
        for (int x = 0; x < 5; x++) {
            data->set_height_at(x, z, float(z));
        }
    }
    const PackedVector3Array on_high = data->scatter_points(1, 1, 0, 90, 2.5f, 3.5f);
    CHECK(on_high.size() == 4);
    for (const Vector3 &p : on_high) {
        CHECK(p.y >= 2.5f);
        CHECK(p.y <= 3.5f);
    }
}

TEST_CASE("[TerrainScatter] World cell size scales positions without changing height") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(Size2i(5, 5));
    data->set_height_at(1, 1, 4);
    const PackedVector3Array points = data->scatter_points(3, 4, 0, 90, -100, 100, 2);
    REQUIRE(points.size() == 4);
    CHECK(points[0] == Vector3(2, 4, 2));
    CHECK(points[1].x == 6.0f);
    CHECK(points[2].z == 6.0f);
}

TEST_CASE("[TerrainScatter] Spacing larger than terrain produces one candidate") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(Size2i(3, 3));
    const PackedVector3Array points = data->scatter_points(7, 100, 1);
    REQUIRE(points.size() == 1);
    CHECK(points[0].x >= 0);
    CHECK(points[0].x <= 2);
    CHECK(points[0].z >= 0);
    CHECK(points[0].z <= 2);
}

TEST_CASE("[TerrainScatter] All candidates remain inside terrain bounds") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(Size2i(9, 7));
    const PackedVector3Array points = data->scatter_points(-123, 0.85f, 1.0f);
    REQUIRE(points.size() > 0);
    for (const Vector3 &p : points) {
        CHECK(p.x >= 0);
        CHECK(p.x <= 8);
        CHECK(p.z >= 0);
        CHECK(p.z <= 6);
    }
}

TEST_CASE("[TerrainScatter] Invalid brush style parameters return no points") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    ERR_PRINT_OFF
    const PackedVector3Array invalid_spacing = data->scatter_points(0, 0);
    const PackedVector3Array invalid_jitter = data->scatter_points(0, 1, 2);
    const PackedVector3Array invalid_slope = data->scatter_points(0, 1, 0, 91);
    const PackedVector3Array invalid_heights = data->scatter_points(0, 1, 0, 90, 10, -10);
    const PackedVector3Array invalid_cell_size = data->scatter_points(0, 1, 0, 90, -10, 10, -1);
    ERR_PRINT_ON
    CHECK(invalid_spacing.is_empty());
    CHECK(invalid_jitter.is_empty());
    CHECK(invalid_slope.is_empty());
    CHECK(invalid_heights.is_empty());
    CHECK(invalid_cell_size.is_empty());
}

TEST_CASE("[TerrainScatter] Excessively dense candidate grids are rejected") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(Size2i(1025, 1025));
    ERR_PRINT_OFF
    const PackedVector3Array too_many = data->scatter_points(1, 1.0f, 0.8f);
    ERR_PRINT_ON
    CHECK(too_many.is_empty());
}

TEST_CASE("[TerrainScatter] Nonfinite numeric inputs cannot produce invalid points") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    ERR_PRINT_OFF
    const PackedVector3Array nan_spacing = data->scatter_points(0, std::numeric_limits<float>::quiet_NaN());
    const PackedVector3Array inf_scale = data->scatter_points(0, 1, 0, 90, -100, 100, std::numeric_limits<float>::infinity());
    ERR_PRINT_ON
    CHECK(nan_spacing.is_empty());
    CHECK(inf_scale.is_empty());
}

} // namespace TestTerrainScatter
