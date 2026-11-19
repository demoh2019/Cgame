/**************************************************************************/
/*  heightmap_foliage_3d.cpp                                              */
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

#include "heightmap_foliage_3d.h"

#include "core/math/math_funcs.h"
#include "core/math/random_number_generator.h"
#include "core/object/callable_mp.h"
#include "core/object/class_db.h"
#include "scene/resources/multimesh.h"

void HeightmapFoliage3D::_heightmap_changed() {
    regenerate();
}

void HeightmapFoliage3D::set_heightmap(const Ref<TerrainHeightmap> &p_data) {
    if (heightmap == p_data) {
        return;
    }
    if (heightmap.is_valid()) {
        heightmap->disconnect_changed(callable_mp(this, &HeightmapFoliage3D::_heightmap_changed));
    }
    heightmap = p_data;
    if (heightmap.is_valid()) {
        heightmap->connect_changed(callable_mp(this, &HeightmapFoliage3D::_heightmap_changed));
    }
    regenerate();
}

Ref<TerrainHeightmap> HeightmapFoliage3D::get_heightmap() const {
    return heightmap;
}

void HeightmapFoliage3D::set_foliage_mesh(const Ref<Mesh> &p_mesh) {
    if (foliage_mesh == p_mesh) {
        return;
    }
    foliage_mesh = p_mesh;
    regenerate();
}

Ref<Mesh> HeightmapFoliage3D::get_foliage_mesh() const {
    return foliage_mesh;
}

void HeightmapFoliage3D::set_instance_count(int p_count) {
    ERR_FAIL_COND_MSG(p_count < 0 || p_count > 100000, "Foliage count must be between 0 and 100000.");
    if (instance_count == p_count) {
        return;
    }
    instance_count = p_count;
    regenerate();
}

int HeightmapFoliage3D::get_instance_count() const {
    return instance_count;
}

void HeightmapFoliage3D::set_random_seed(uint32_t p_seed) {
    if (random_seed == p_seed) {
        return;
    }
    random_seed = p_seed;
    regenerate();
}

uint32_t HeightmapFoliage3D::get_random_seed() const {
    return random_seed;
}

void HeightmapFoliage3D::set_terrain_cell_size(real_t p_size) {
    ERR_FAIL_COND_MSG(!Math::is_finite(p_size) || p_size <= CMP_EPSILON, "Terrain cell size must be positive.");
    if (terrain_cell_size == p_size) {
        return;
    }
    terrain_cell_size = p_size;
    regenerate();
}

real_t HeightmapFoliage3D::get_terrain_cell_size() const {
    return terrain_cell_size;
}

void HeightmapFoliage3D::set_minimum_scale(real_t p_scale) {
    ERR_FAIL_COND_MSG(!Math::is_finite(p_scale) || p_scale <= 0, "Minimum foliage scale must be positive.");
    if (minimum_scale == p_scale) {
        return;
    }
    minimum_scale = p_scale;
    maximum_scale = MAX(maximum_scale, minimum_scale);
    regenerate();
}

real_t HeightmapFoliage3D::get_minimum_scale() const {
    return minimum_scale;
}

void HeightmapFoliage3D::set_maximum_scale(real_t p_scale) {
    ERR_FAIL_COND_MSG(!Math::is_finite(p_scale) || p_scale <= 0, "Maximum foliage scale must be positive.");
    if (maximum_scale == p_scale) {
        return;
    }
    maximum_scale = p_scale;
    minimum_scale = MIN(minimum_scale, maximum_scale);
    regenerate();
}

real_t HeightmapFoliage3D::get_maximum_scale() const {
    return maximum_scale;
}

void HeightmapFoliage3D::set_maximum_slope_degrees(real_t p_angle) {
    ERR_FAIL_COND_MSG(!Math::is_finite(p_angle) || p_angle < 0 || p_angle > 90, "Maximum foliage slope must be in the range 0 to 90 degrees.");
    if (maximum_slope_degrees == p_angle) {
        return;
    }
    maximum_slope_degrees = p_angle;
    regenerate();
}

real_t HeightmapFoliage3D::get_maximum_slope_degrees() const {
    return maximum_slope_degrees;
}

void HeightmapFoliage3D::regenerate() {
    if (heightmap.is_null() || foliage_mesh.is_null() || instance_count <= 0) {
        set_multimesh(Ref<MultiMesh>());
        return;
    }

    Ref<MultiMesh> generated;
    generated.instantiate();
    generated->set_mesh(foliage_mesh);
    generated->set_transform_format(MultiMesh::TRANSFORM_3D);
    generated->set_instance_count(instance_count);

    RandomNumberGenerator rng;
    rng.set_seed(random_seed);

    const real_t max_x = heightmap->get_width() - 1;
    const real_t max_z = heightmap->get_depth() - 1;
    const real_t cosine_limit = Math::cos(Math::deg_to_rad(maximum_slope_degrees));
    int placed = 0;
    const int attempts = instance_count * 12;
    for (int attempt = 0; attempt < attempts && placed < instance_count; ++attempt) {
        const real_t grid_x = rng.randf_range(0, max_x);
        const real_t grid_z = rng.randf_range(0, max_z);
        const real_t ground = heightmap->sample_height(grid_x, grid_z);

        const real_t left = MAX(grid_x - 0.5, real_t(0));
        const real_t right = MIN(grid_x + 0.5, max_x);
        const real_t up = MAX(grid_z - 0.5, real_t(0));
        const real_t down = MIN(grid_z + 0.5, max_z);
        const real_t derivative_x = (heightmap->sample_height(right, grid_z) -
                heightmap->sample_height(left, grid_z)) / ((right - left) * terrain_cell_size);
        const real_t derivative_z = (heightmap->sample_height(grid_x, down) -
                heightmap->sample_height(grid_x, up)) / ((down - up) * terrain_cell_size);
        const Vector3 normal = Vector3(-derivative_x, 1.0, -derivative_z).normalized();
        if (normal.y < cosine_limit) {
            continue;
        }

        const real_t yaw = rng.randf_range(0, Math::TAU);
        const real_t scale = rng.randf_range(minimum_scale, maximum_scale);
        Basis orientation(Vector3(0, 1, 0), yaw);
        orientation.scale(Vector3(scale, scale, scale));

        const Vector3 position(grid_x * terrain_cell_size, ground, grid_z * terrain_cell_size);
        generated->set_instance_transform(placed, Transform3D(orientation, position));
        ++placed;
    }
    generated->set_visible_instance_count(placed);
    set_multimesh(generated);
}

int HeightmapFoliage3D::get_generated_count() const {
    const Ref<MultiMesh> current = get_multimesh();
    return current.is_valid() ? current->get_visible_instance_count() : 0;
}

void HeightmapFoliage3D::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_heightmap", "heightmap"), &HeightmapFoliage3D::set_heightmap);
    ClassDB::bind_method(D_METHOD("get_heightmap"), &HeightmapFoliage3D::get_heightmap);
    ClassDB::bind_method(D_METHOD("set_foliage_mesh", "mesh"), &HeightmapFoliage3D::set_foliage_mesh);
    ClassDB::bind_method(D_METHOD("get_foliage_mesh"), &HeightmapFoliage3D::get_foliage_mesh);
    ClassDB::bind_method(D_METHOD("set_instance_count", "count"), &HeightmapFoliage3D::set_instance_count);
    ClassDB::bind_method(D_METHOD("get_instance_count"), &HeightmapFoliage3D::get_instance_count);
    ClassDB::bind_method(D_METHOD("set_random_seed", "seed"), &HeightmapFoliage3D::set_random_seed);
    ClassDB::bind_method(D_METHOD("get_random_seed"), &HeightmapFoliage3D::get_random_seed);
    ClassDB::bind_method(D_METHOD("set_terrain_cell_size", "size"), &HeightmapFoliage3D::set_terrain_cell_size);
    ClassDB::bind_method(D_METHOD("get_terrain_cell_size"), &HeightmapFoliage3D::get_terrain_cell_size);
    ClassDB::bind_method(D_METHOD("set_minimum_scale", "scale"), &HeightmapFoliage3D::set_minimum_scale);
    ClassDB::bind_method(D_METHOD("get_minimum_scale"), &HeightmapFoliage3D::get_minimum_scale);
    ClassDB::bind_method(D_METHOD("set_maximum_scale", "scale"), &HeightmapFoliage3D::set_maximum_scale);
    ClassDB::bind_method(D_METHOD("get_maximum_scale"), &HeightmapFoliage3D::get_maximum_scale);
    ClassDB::bind_method(D_METHOD("set_maximum_slope_degrees", "degrees"), &HeightmapFoliage3D::set_maximum_slope_degrees);
    ClassDB::bind_method(D_METHOD("get_maximum_slope_degrees"), &HeightmapFoliage3D::get_maximum_slope_degrees);
    ClassDB::bind_method(D_METHOD("regenerate"), &HeightmapFoliage3D::regenerate);
    ClassDB::bind_method(D_METHOD("get_generated_count"), &HeightmapFoliage3D::get_generated_count);

    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "heightmap", PROPERTY_HINT_RESOURCE_TYPE, "TerrainHeightmap",
                         PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_EDITOR_INSTANTIATE_OBJECT), "set_heightmap", "get_heightmap");
    ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "foliage_mesh", PROPERTY_HINT_RESOURCE_TYPE, "Mesh"), "set_foliage_mesh", "get_foliage_mesh");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "instance_count", PROPERTY_HINT_RANGE, "0,100000,1"), "set_instance_count", "get_instance_count");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "random_seed"), "set_random_seed", "get_random_seed");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "terrain_cell_size", PROPERTY_HINT_RANGE, "0.01,100,0.01"), "set_terrain_cell_size", "get_terrain_cell_size");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "minimum_scale", PROPERTY_HINT_RANGE, "0.01,10,0.01"), "set_minimum_scale", "get_minimum_scale");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "maximum_scale", PROPERTY_HINT_RANGE, "0.01,10,0.01"), "set_maximum_scale", "get_maximum_scale");
    ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "maximum_slope_degrees", PROPERTY_HINT_RANGE, "0,90,1,suffix:°"), "set_maximum_slope_degrees", "get_maximum_slope_degrees");
}

HeightmapFoliage3D::~HeightmapFoliage3D() {
    if (heightmap.is_valid()) {
        heightmap->disconnect_changed(callable_mp(this, &HeightmapFoliage3D::_heightmap_changed));
    }
}
