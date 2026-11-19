/**************************************************************************/
/*  terrain_heightmap.cpp                                                 */
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

#include "terrain_heightmap.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

#include <cmath>

bool TerrainHeightmap::_valid_cell(int p_x, int p_z) const {
    return p_x >= 0 && p_z >= 0 && p_x < dimensions.x && p_z < dimensions.y;
}

int TerrainHeightmap::_index(int p_x, int p_z) const {
    return p_z * dimensions.x + p_x;
}

TerrainHeightmap::TerrainHeightmap() {
    heights.resize(dimensions.x * dimensions.y);
    heights.fill(0.0f);
    paint_weights.resize(dimensions.x * dimensions.y);
    paint_weights.fill(Color(1, 0, 0, 0));
}

void TerrainHeightmap::set_dimensions(const Size2i &p_dimensions) {
    // Keep rebuilds bounded, including when loading untrusted resource files.
    ERR_FAIL_COND_MSG(p_dimensions.x < 2 || p_dimensions.y < 2 ||
                    p_dimensions.x > 2048 || p_dimensions.y > 2048 ||
                    int64_t(p_dimensions.x) * p_dimensions.y > 1048576,
            "Terrain heightmaps must be at least 2x2 and contain at most 1,048,576 cells.");
    if (dimensions == p_dimensions) {
        return;
    }

    PackedFloat32Array new_heights;
    PackedColorArray new_weights;
    new_heights.resize(p_dimensions.x * p_dimensions.y);
    new_heights.fill(0.0f);
    new_weights.resize(p_dimensions.x * p_dimensions.y);
    new_weights.fill(Color(1, 0, 0, 0));

    const int copy_x = MIN(dimensions.x, p_dimensions.x);
    const int copy_z = MIN(dimensions.y, p_dimensions.y);
    for (int z = 0; z < copy_z; z++) {
        for (int x = 0; x < copy_x; x++) {
            const int old_index = _index(x, z);
            const int new_index = z * p_dimensions.x + x;
            new_heights.set(new_index, heights[old_index]);
            new_weights.set(new_index, paint_weights[old_index]);
        }
    }
    dimensions = p_dimensions;
    heights = new_heights;
    paint_weights = new_weights;
    emit_changed();
}

Size2i TerrainHeightmap::get_dimensions() const {
    return dimensions;
}

void TerrainHeightmap::set_heights(const PackedFloat32Array &p_heights) {
    ERR_FAIL_COND_MSG(p_heights.size() != dimensions.x * dimensions.y, "Height array size must match the terrain dimensions.");
    for (int i = 0; i < p_heights.size(); i++) {
        ERR_FAIL_COND_MSG(!std::isfinite(p_heights[i]), "Terrain heights must be finite.");
    }
    if (heights == p_heights) {
        return;
    }
    heights = p_heights;
    emit_changed();
}

PackedFloat32Array TerrainHeightmap::get_heights() const {
    return heights;
}

void TerrainHeightmap::set_paint_weights(const PackedColorArray &p_weights) {
    ERR_FAIL_COND_MSG(p_weights.size() != dimensions.x * dimensions.y, "Paint array size must match the terrain dimensions.");
    for (int i = 0; i < p_weights.size(); i++) {
        const Color c = p_weights[i];
        const float sum = c.r + c.g + c.b + c.a;
        ERR_FAIL_COND_MSG(!std::isfinite(sum) || c.r < 0 || c.g < 0 || c.b < 0 || c.a < 0 ||
                        c.r > 1 || c.g > 1 || c.b > 1 || c.a > 1 || !Math::is_equal_approx(sum, 1.0f),
                "Terrain layer weights must be non-negative and sum to one.");
    }
    if (paint_weights == p_weights) {
        return;
    }
    paint_weights = p_weights;
    emit_changed();
}

PackedColorArray TerrainHeightmap::get_paint_weights() const {
    return paint_weights;
}

void TerrainHeightmap::set_height_at(int p_x, int p_z, float p_height) {
    ERR_FAIL_COND_MSG(!_valid_cell(p_x, p_z) || !std::isfinite(p_height), "Invalid terrain cell or non-finite height.");
    const int index = _index(p_x, p_z);
    if (heights[index] != p_height) {
        heights.set(index, p_height);
        emit_changed();
    }
}

float TerrainHeightmap::get_height_at(int p_x, int p_z) const {
    ERR_FAIL_COND_V_MSG(!_valid_cell(p_x, p_z), 0.0f, "Terrain cell is outside the heightmap.");
    return heights[_index(p_x, p_z)];
}

Color TerrainHeightmap::get_paint_at(int p_x, int p_z) const {
    ERR_FAIL_COND_V_MSG(!_valid_cell(p_x, p_z), Color(), "Terrain cell is outside the heightmap.");
    return paint_weights[_index(p_x, p_z)];
}

float TerrainHeightmap::sample_height(const Vector2 &p_grid_position) const {
    ERR_FAIL_COND_V_MSG(!std::isfinite(p_grid_position.x) || !std::isfinite(p_grid_position.y),
            0.0f, "Height sample coordinates must be finite.");
    const float px = CLAMP(p_grid_position.x, 0.0f, float(dimensions.x - 1));
    const float pz = CLAMP(p_grid_position.y, 0.0f, float(dimensions.y - 1));
    const int x0 = int(Math::floor(px));
    const int z0 = int(Math::floor(pz));
    const int x1 = MIN(x0 + 1, dimensions.x - 1);
    const int z1 = MIN(z0 + 1, dimensions.y - 1);
    const float tx = px - x0;
    const float tz = pz - z0;
    const float top = Math::lerp(heights[_index(x0, z0)], heights[_index(x1, z0)], tx);
    const float bottom = Math::lerp(heights[_index(x0, z1)], heights[_index(x1, z1)], tx);
    return Math::lerp(top, bottom, tz);
}

void TerrainHeightmap::sculpt(const Vector2 &p_center, float p_radius, float p_delta) {
    ERR_FAIL_COND_MSG(!std::isfinite(p_center.x) || !std::isfinite(p_center.y) ||
                    !std::isfinite(p_radius) || !std::isfinite(p_delta) || p_radius <= 0,
            "Invalid sculpt brush arguments.");
    if (p_delta == 0) {
        return;
    }
    bool modified = false;
    for (int z = 0; z < dimensions.y; z++) {
        for (int x = 0; x < dimensions.x; x++) {
            const float dist = Vector2(x, z).distance_to(p_center);
            if (dist >= p_radius) {
                continue;
            }
            const int i = _index(x, z);
            const float amount = p_delta * (1.0f - dist / p_radius);
            const float value = heights[i] + amount;
            if (std::isfinite(value) && heights[i] != value) {
                heights.set(i, value);
                modified = true;
            }
        }
    }
    if (modified) {
        emit_changed();
    }
}

void TerrainHeightmap::smooth(const Vector2 &p_center, float p_radius, float p_strength) {
    ERR_FAIL_COND_MSG(!std::isfinite(p_center.x) || !std::isfinite(p_center.y) ||
                    !std::isfinite(p_radius) || !std::isfinite(p_strength) ||
                    p_radius <= 0 || p_strength < 0 || p_strength > 1,
            "Invalid smooth brush arguments.");
    if (p_strength == 0) {
        return;
    }
    const PackedFloat32Array original = heights.duplicate();
    bool modified = false;
    for (int z = 0; z < dimensions.y; z++) {
        for (int x = 0; x < dimensions.x; x++) {
            const float dist = Vector2(x, z).distance_to(p_center);
            if (dist >= p_radius) {
                continue;
            }
            float total = 0.0f;
            int count = 0;
            for (int nz = MAX(0, z - 1); nz <= MIN(dimensions.y - 1, z + 1); nz++) {
                for (int nx = MAX(0, x - 1); nx <= MIN(dimensions.x - 1, x + 1); nx++) {
                    total += original[_index(nx, nz)];
                    count++;
                }
            }
            const int i = _index(x, z);
            const float weight = p_strength * (1.0f - dist / p_radius);
            const float value = Math::lerp(original[i], total / count, weight);
            if (std::isfinite(value) && value != original[i]) {
                heights.set(i, value);
                modified = true;
            }
        }
    }
    if (modified) {
        emit_changed();
    }
}

void TerrainHeightmap::erode_talus(int p_iterations, float p_talus, float p_rate) {
    ERR_FAIL_COND_MSG(p_iterations < 0 || p_iterations > 1000 ||
                    !std::isfinite(p_talus) || !std::isfinite(p_rate) ||
                    p_talus < 0 || p_rate < 0 || p_rate > 1,
            "Invalid erosion parameters.");
    if (p_iterations == 0 || p_rate == 0) {
        return;
    }
    bool modified = false;
    for (int iteration = 0; iteration < p_iterations; iteration++) {
        PackedFloat32Array delta;
        delta.resize(heights.size());
        delta.fill(0.0f);
        bool moved = false;
        for (int z = 0; z < dimensions.y; z++) {
            for (int x = 0; x < dimensions.x; x++) {
                const int from = _index(x, z);
                int to = -1;
                float max_drop = p_talus;
                const int nx[4] = { x - 1, x + 1, x, x };
                const int nz[4] = { z, z, z - 1, z + 1 };
                for (int n = 0; n < 4; n++) {
                    if (!_valid_cell(nx[n], nz[n])) {
                        continue;
                    }
                    const int candidate = _index(nx[n], nz[n]);
                    const float drop = heights[from] - heights[candidate];
                    if (drop > max_drop) {
                        max_drop = drop;
                        to = candidate;
                    }
                }
                if (to >= 0) {
                    const float amount = (max_drop - p_talus) * p_rate * 0.5f;
                    if (amount > 0 && std::isfinite(amount)) {
                        delta.set(from, delta[from] - amount);
                        delta.set(to, delta[to] + amount);
                        moved = true;
                    }
                }
            }
        }
        if (!moved) {
            break;
        }
        for (int i = 0; i < heights.size(); i++) {
            heights.set(i, heights[i] + delta[i]);
        }
        modified = true;
    }
    if (modified) {
        emit_changed();
    }
}

void TerrainHeightmap::paint_layer(const Vector2 &p_center, float p_radius, int p_layer, float p_strength) {
    ERR_FAIL_COND_MSG(!std::isfinite(p_center.x) || !std::isfinite(p_center.y) ||
                    !std::isfinite(p_radius) || !std::isfinite(p_strength) ||
                    p_radius <= 0 || p_layer < 0 || p_layer > 3 ||
                    p_strength < 0 || p_strength > 1,
            "Invalid terrain paint brush arguments.");
    if (p_strength == 0) {
        return;
    }
    const Color target(p_layer == 0 ? 1.0f : 0.0f,
            p_layer == 1 ? 1.0f : 0.0f,
            p_layer == 2 ? 1.0f : 0.0f,
            p_layer == 3 ? 1.0f : 0.0f);
    bool modified = false;
    for (int z = 0; z < dimensions.y; z++) {
        for (int x = 0; x < dimensions.x; x++) {
            const float dist = Vector2(x, z).distance_to(p_center);
            if (dist >= p_radius) {
                continue;
            }
            const int i = _index(x, z);
            const Color prev = paint_weights[i];
            const float amount = p_strength * (1.0f - dist / p_radius);
            const Color next = prev.lerp(target, amount);
            if (next != prev) {
                paint_weights.set(i, next);
                modified = true;
            }
        }
    }
    if (modified) {
        emit_changed();
    }
}

Ref<ArrayMesh> TerrainHeightmap::build_mesh(float p_cell_size) const {
    ERR_FAIL_COND_V_MSG(!std::isfinite(p_cell_size) || p_cell_size <= 0, Ref<ArrayMesh>(),
            "Terrain mesh cell size must be finite and positive.");
    const int w = dimensions.x;
    const int h = dimensions.y;
    const int cell_count = w * h;
    PackedVector3Array vertices;
    PackedVector3Array normals;
    PackedVector2Array uvs;
    PackedInt32Array indices;
    vertices.resize(cell_count);
    normals.resize(cell_count);
    uvs.resize(cell_count);
    indices.resize((w - 1) * (h - 1) * 6);

    for (int z = 0; z < h; z++) {
        for (int x = 0; x < w; x++) {
            const int i = _index(x, z);
            vertices.set(i, Vector3(x * p_cell_size, heights[i], z * p_cell_size));
            uvs.set(i, Vector2(float(x) / (w - 1), float(z) / (h - 1)));

            const int xl = MAX(0, x - 1);
            const int xr = MIN(w - 1, x + 1);
            const int zu = MAX(0, z - 1);
            const int zd = MIN(h - 1, z + 1);
            const float dx = (heights[_index(xl, z)] - heights[_index(xr, z)]) /
                    ((xr - xl) * p_cell_size);
            const float dz = (heights[_index(x, zu)] - heights[_index(x, zd)]) /
                    ((zd - zu) * p_cell_size);
            normals.set(i, Vector3(dx, 1.0f, dz).normalized());
        }
    }
    int cursor = 0;
    for (int z = 0; z < h - 1; z++) {
        for (int x = 0; x < w - 1; x++) {
            const int a = _index(x, z);
            const int b = _index(x + 1, z);
            const int c = _index(x, z + 1);
            const int d = _index(x + 1, z + 1);
            indices.set(cursor++, a);
            indices.set(cursor++, c);
            indices.set(cursor++, b);
            indices.set(cursor++, b);
            indices.set(cursor++, c);
            indices.set(cursor++, d);
        }
    }

    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = vertices;
    arrays[Mesh::ARRAY_NORMAL] = normals;
    arrays[Mesh::ARRAY_TEX_UV] = uvs;
    arrays[Mesh::ARRAY_COLOR] = paint_weights;
    arrays[Mesh::ARRAY_INDEX] = indices;

    Ref<ArrayMesh> mesh;
    mesh.instantiate();
    mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
    return mesh;
}

void TerrainHeightmap::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_dimensions", "dimensions"), &TerrainHeightmap::set_dimensions);
    ClassDB::bind_method(D_METHOD("get_dimensions"), &TerrainHeightmap::get_dimensions);
    ClassDB::bind_method(D_METHOD("set_heights", "heights"), &TerrainHeightmap::set_heights);
    ClassDB::bind_method(D_METHOD("get_heights"), &TerrainHeightmap::get_heights);
    ClassDB::bind_method(D_METHOD("set_paint_weights", "weights"), &TerrainHeightmap::set_paint_weights);
    ClassDB::bind_method(D_METHOD("get_paint_weights"), &TerrainHeightmap::get_paint_weights);
    ClassDB::bind_method(D_METHOD("set_height_at", "x", "z", "height"), &TerrainHeightmap::set_height_at);
    ClassDB::bind_method(D_METHOD("get_height_at", "x", "z"), &TerrainHeightmap::get_height_at);
    ClassDB::bind_method(D_METHOD("get_paint_at", "x", "z"), &TerrainHeightmap::get_paint_at);
    ClassDB::bind_method(D_METHOD("sample_height", "grid_position"), &TerrainHeightmap::sample_height);
    ClassDB::bind_method(D_METHOD("sculpt", "center", "radius", "delta"), &TerrainHeightmap::sculpt);
    ClassDB::bind_method(D_METHOD("smooth", "center", "radius", "strength"), &TerrainHeightmap::smooth);
    ClassDB::bind_method(D_METHOD("erode_talus", "iterations", "talus", "rate"), &TerrainHeightmap::erode_talus);
    ClassDB::bind_method(D_METHOD("paint_layer", "center", "radius", "layer", "strength"), &TerrainHeightmap::paint_layer);
    ClassDB::bind_method(D_METHOD("build_mesh", "cell_size"), &TerrainHeightmap::build_mesh, DEFVAL(1.0f));

    ADD_PROPERTY(PropertyInfo(Variant::VECTOR2I, "dimensions"), "set_dimensions", "get_dimensions");
    ADD_PROPERTY(PropertyInfo(Variant::PACKED_FLOAT32_ARRAY, "heights", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE), "set_heights", "get_heights");
    ADD_PROPERTY(PropertyInfo(Variant::PACKED_COLOR_ARRAY, "paint_weights", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE), "set_paint_weights", "get_paint_weights");
}
