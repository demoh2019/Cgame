/**************************************************************************/
/*  test_heightmap_foliage.h                                              */
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

#include "../heightmap_foliage_3d.h"

#include "scene/resources/3d/primitive_meshes.h"
#include "scene/resources/multimesh.h"
#include "tests/test_macros.h"

namespace TestHeightmapFoliage {

TEST_CASE("[Foliage] No source data or mesh produces no instances") {
    HeightmapFoliage3D *node = memnew(HeightmapFoliage3D);
    CHECK(node->get_generated_count() == 0);
    Ref<TerrainHeightmap> terrain;
    terrain.instantiate();
    node->set_heightmap(terrain);
    CHECK(node->get_generated_count() == 0);
    Ref<BoxMesh> mesh;
    mesh.instantiate();
    node->set_foliage_mesh(mesh);
    CHECK(node->get_generated_count() == 128);
    node->set_heightmap(Ref<TerrainHeightmap>());
    CHECK(node->get_generated_count() == 0);
    memdelete(node);
}

TEST_CASE("[Foliage] Zero instance count generates no MultiMesh") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    Ref<BoxMesh> mesh;
    mesh.instantiate();
    HeightmapFoliage3D *node = memnew(HeightmapFoliage3D);
    node->set_heightmap(data);
    node->set_foliage_mesh(mesh);
    node->set_instance_count(0);
    CHECK(node->get_generated_count() == 0);
    CHECK(node->get_multimesh().is_null());
    memdelete(node);
}

TEST_CASE("[Foliage] Deterministic generation with the same seed") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(9, 9);
    Ref<BoxMesh> mesh;
    mesh.instantiate();
    HeightmapFoliage3D *a = memnew(HeightmapFoliage3D);
    HeightmapFoliage3D *b = memnew(HeightmapFoliage3D);
    a->set_heightmap(data);
    b->set_heightmap(data);
    a->set_foliage_mesh(mesh);
    b->set_foliage_mesh(mesh);
    a->set_instance_count(32);
    b->set_instance_count(32);
    a->set_random_seed(9001);
    b->set_random_seed(9001);
    REQUIRE(a->get_generated_count() == 32);
    REQUIRE(b->get_generated_count() == 32);
    for (int i = 0; i < 32; ++i) {
        CHECK(a->get_multimesh()->get_instance_transform(i) == b->get_multimesh()->get_instance_transform(i));
    }
    memdelete(a);
    memdelete(b);
}

TEST_CASE("[Foliage] Different seeds produce different placement") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    Ref<BoxMesh> mesh;
    mesh.instantiate();
    HeightmapFoliage3D *a = memnew(HeightmapFoliage3D);
    HeightmapFoliage3D *b = memnew(HeightmapFoliage3D);
    a->set_heightmap(data);
    b->set_heightmap(data);
    a->set_foliage_mesh(mesh);
    b->set_foliage_mesh(mesh);
    a->set_random_seed(1);
    b->set_random_seed(2);
    REQUIRE(a->get_generated_count() == 128);
    REQUIRE(b->get_generated_count() == 128);
    CHECK(a->get_multimesh()->get_instance_transform(0) != b->get_multimesh()->get_instance_transform(0));
    memdelete(a);
    memdelete(b);
}

TEST_CASE("[Foliage] All instances remain within map bounds") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(5, 7);
    Ref<BoxMesh> mesh;
    mesh.instantiate();
    HeightmapFoliage3D *node = memnew(HeightmapFoliage3D);
    node->set_heightmap(data);
    node->set_foliage_mesh(mesh);
    node->set_terrain_cell_size(3);
    node->set_instance_count(50);
    REQUIRE(node->get_generated_count() == 50);
    for (int i = 0; i < node->get_generated_count(); ++i) {
        const Vector3 origin = node->get_multimesh()->get_instance_transform(i).origin;
        CHECK(origin.x >= 0);
        CHECK(origin.x <= 12);
        CHECK(origin.z >= 0);
        CHECK(origin.z <= 18);
        CHECK(origin.y == doctest::Approx(0));
    }
    memdelete(node);
}

TEST_CASE("[Foliage] Sampled positions follow the heightmap") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(3, 3);
    for (int z = 0; z < 3; ++z) {
        for (int x = 0; x < 3; ++x) {
            data->set_height(x, z, x + z);
        }
    }
    Ref<BoxMesh> mesh;
    mesh.instantiate();
    HeightmapFoliage3D *node = memnew(HeightmapFoliage3D);
    node->set_heightmap(data);
    node->set_foliage_mesh(mesh);
    node->set_terrain_cell_size(2);
    node->set_maximum_slope_degrees(89);
    node->set_instance_count(24);
    REQUIRE(node->get_generated_count() == 24);
    for (int i = 0; i < node->get_generated_count(); ++i) {
        const Vector3 origin = node->get_multimesh()->get_instance_transform(i).origin;
        CHECK(origin.y == doctest::Approx(data->sample_height(origin.x / 2, origin.z / 2)));
    }
    memdelete(node);
}

TEST_CASE("[Foliage] Flat terrain passes the zero-degree slope filter") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    Ref<BoxMesh> mesh;
    mesh.instantiate();
    HeightmapFoliage3D *node = memnew(HeightmapFoliage3D);
    node->set_heightmap(data);
    node->set_foliage_mesh(mesh);
    node->set_maximum_slope_degrees(0);
    node->set_instance_count(20);
    CHECK(node->get_generated_count() == 20);
    memdelete(node);
}

TEST_CASE("[Foliage] Steep terrain fails the zero-degree slope filter") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(3, 3);
    for (int z = 0; z < 3; ++z) {
        for (int x = 0; x < 3; ++x) {
            data->set_height(x, z, 100 * x);
        }
    }
    Ref<BoxMesh> mesh;
    mesh.instantiate();
    HeightmapFoliage3D *node = memnew(HeightmapFoliage3D);
    node->set_heightmap(data);
    node->set_foliage_mesh(mesh);
    node->set_maximum_slope_degrees(0);
    node->set_instance_count(20);
    CHECK(node->get_generated_count() == 0);
    memdelete(node);
}

TEST_CASE("[Foliage] Uniform random scale stays within configured bounds") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    Ref<BoxMesh> mesh;
    mesh.instantiate();
    HeightmapFoliage3D *node = memnew(HeightmapFoliage3D);
    node->set_heightmap(data);
    node->set_foliage_mesh(mesh);
    node->set_minimum_scale(0.7);
    node->set_maximum_scale(1.5);
    node->set_instance_count(24);
    REQUIRE(node->get_generated_count() == 24);
    for (int i = 0; i < 24; ++i) {
        const Vector3 scale = node->get_multimesh()->get_instance_transform(i).basis.get_scale();
        CHECK(scale.x >= 0.7);
        CHECK(scale.x <= 1.5);
        CHECK(scale.x == doctest::Approx(scale.y));
        CHECK(scale.x == doctest::Approx(scale.z));
    }
    memdelete(node);
}

TEST_CASE("[Foliage] Regenerates at the same horizontal positions after terrain height edit") {
    Ref<TerrainHeightmap> data;
    data.instantiate();
    data->set_dimensions(2, 2);
    Ref<BoxMesh> mesh;
    mesh.instantiate();
    HeightmapFoliage3D *node = memnew(HeightmapFoliage3D);
    node->set_heightmap(data);
    node->set_foliage_mesh(mesh);
    node->set_instance_count(10);
    node->set_maximum_slope_degrees(90);
    REQUIRE(node->get_generated_count() == 10);
    const Transform3D before = node->get_multimesh()->get_instance_transform(0);
    for (int z = 0; z < 2; ++z) {
        for (int x = 0; x < 2; ++x) {
            data->set_height(x, z, 5);
        }
    }
    REQUIRE(node->get_generated_count() == 10);
    const Transform3D after = node->get_multimesh()->get_instance_transform(0);
    CHECK(before.origin.x == doctest::Approx(after.origin.x));
    CHECK(before.origin.z == doctest::Approx(after.origin.z));
    CHECK(after.origin.y == doctest::Approx(5));
    memdelete(node);
}

TEST_CASE("[Foliage] Scale setters preserve valid ordering for serialization") {
    HeightmapFoliage3D *node = memnew(HeightmapFoliage3D);
    node->set_minimum_scale(2);
    CHECK(node->get_minimum_scale() == 2);
    CHECK(node->get_maximum_scale() == 2);
    node->set_maximum_scale(3);
    CHECK(node->get_minimum_scale() == 2);
    CHECK(node->get_maximum_scale() == 3);
    node->set_maximum_scale(0.5);
    CHECK(node->get_minimum_scale() == 0.5);
    CHECK(node->get_maximum_scale() == 0.5);
    memdelete(node);
}

TEST_CASE("[Foliage] Invalid count and cell size do not mutate properties") {
    HeightmapFoliage3D *node = memnew(HeightmapFoliage3D);
    node->set_instance_count(9);
    node->set_terrain_cell_size(4);
    ERR_PRINT_OFF;
    node->set_instance_count(-1);
    node->set_instance_count(100001);
    node->set_terrain_cell_size(0);
    node->set_terrain_cell_size(-5);
    ERR_PRINT_ON;
    CHECK(node->get_instance_count() == 9);
    CHECK(node->get_terrain_cell_size() == 4);
    memdelete(node);
}

} // namespace TestHeightmapFoliage
