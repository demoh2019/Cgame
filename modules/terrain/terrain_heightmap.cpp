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
#include <limits>

bool TerrainHeightmap::_valid_cell(int p_x, int p_z) const {
    return p_x >= 0 && p_z >= 0 && p_x < dimensions.x && p_z < dimensions.y;
}

int TerrainHeightmap::_index(int p_x, int p_z) const {
    return p_z * dimensions.x + p_x;
}

void TerrainHeightmap::_notify_changed() {
    if (edit_depth > 0) {
        pending_change = true;
    } else {
        emit_changed();
    }
}

void TerrainHeightmap::begin_edit() {
    edit_depth++;
}

void TerrainHeightmap::end_edit() {
    ERR_FAIL_COND_MSG(edit_depth == 0, "end_edit() called without begin_edit().");
    edit_depth--;
    if (edit_depth == 0 && pending_change) {
        pending_change = false;
        emit_changed();
    }
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
    _notify_changed();
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
    _notify_changed();
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
    _notify_changed();
}

PackedColorArray TerrainHeightmap::get_paint_weights() const {
    return paint_weights;
}

void TerrainHeightmap::set_height_at(int p_x, int p_z, float p_height) {
    ERR_FAIL_COND_MSG(!_valid_cell(p_x, p_z) || !std::isfinite(p_height), "Invalid terrain cell or non-finite height.");
    const int index = _index(p_x, p_z);
    if (heights[index] != p_height) {
        heights.set(index, p_height);
        _notify_changed();
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
    // Visit only the brush's clamped bounding box, rather than the whole terrain.
    const int min_x = int(CLAMP(Math::floor(p_center.x - p_radius), 0.0f, float(dimensions.x - 1)));
    const int max_x = int(CLAMP(Math::ceil(p_center.x + p_radius), 0.0f, float(dimensions.x - 1)));
    const int min_z = int(CLAMP(Math::floor(p_center.y - p_radius), 0.0f, float(dimensions.y - 1)));
    const int max_z = int(CLAMP(Math::ceil(p_center.y + p_radius), 0.0f, float(dimensions.y - 1)));
    for (int z = min_z; z <= max_z; z++) {
        for (int x = min_x; x <= max_x; x++) {
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
        _notify_changed();
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
    // Visit only the brush's clamped bounding box, rather than the whole terrain.
    const int min_x = int(CLAMP(Math::floor(p_center.x - p_radius), 0.0f, float(dimensions.x - 1)));
    const int max_x = int(CLAMP(Math::ceil(p_center.x + p_radius), 0.0f, float(dimensions.x - 1)));
    const int min_z = int(CLAMP(Math::floor(p_center.y - p_radius), 0.0f, float(dimensions.y - 1)));
    const int max_z = int(CLAMP(Math::ceil(p_center.y + p_radius), 0.0f, float(dimensions.y - 1)));
    for (int z = min_z; z <= max_z; z++) {
        for (int x = min_x; x <= max_x; x++) {
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
        _notify_changed();
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
        _notify_changed();
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
    // Visit only the brush's clamped bounding box, rather than the whole terrain.
    const int min_x = int(CLAMP(Math::floor(p_center.x - p_radius), 0.0f, float(dimensions.x - 1)));
    const int max_x = int(CLAMP(Math::ceil(p_center.x + p_radius), 0.0f, float(dimensions.x - 1)));
    const int min_z = int(CLAMP(Math::floor(p_center.y - p_radius), 0.0f, float(dimensions.y - 1)));
    const int max_z = int(CLAMP(Math::ceil(p_center.y + p_radius), 0.0f, float(dimensions.y - 1)));
    for (int z = min_z; z <= max_z; z++) {
        for (int x = min_x; x <= max_x; x++) {
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
        _notify_changed();
    }
}

namespace {
uint32_t terrain_hash(uint32_t p_value) {
    p_value ^= p_value >> 16;
    p_value *= 0x7feb352dU;
    p_value ^= p_value >> 15;
    p_value *= 0x846ca68bU;
    p_value ^= p_value >> 16;
    return p_value;
}

float terrain_random01(uint32_t p_seed, uint32_t p_x, uint32_t p_z, uint32_t p_channel) {
    const uint32_t value = terrain_hash(p_seed ^ (p_x * 0x9e3779b9U) ^
            (p_z * 0x85ebca6bU) ^ (p_channel * 0xc2b2ae35U));
    return float(value & 0xFFFFFFU) / 16777216.0f;
}
} // namespace

PackedVector3Array TerrainHeightmap::scatter_points(int p_seed, float p_spacing, float p_jitter,
        float p_max_slope_degrees, float p_min_height, float p_max_height, float p_cell_size) const {
    PackedVector3Array points;
    ERR_FAIL_COND_V_MSG(!std::isfinite(p_spacing) || p_spacing <= 0 ||
                    !std::isfinite(p_cell_size) || p_cell_size <= 0 ||
                    !std::isfinite(p_jitter) || p_jitter < 0 || p_jitter > 1 ||
                    !std::isfinite(p_max_slope_degrees) || p_max_slope_degrees < 0 || p_max_slope_degrees > 90 ||
                    !std::isfinite(p_min_height) || !std::isfinite(p_max_height) || p_min_height > p_max_height,
            points, "Invalid terrain scatter parameters.");

    const double extent_x = double(dimensions.x - 1) * p_cell_size;
    const double extent_z = double(dimensions.y - 1) * p_cell_size;
    ERR_FAIL_COND_V_MSG(extent_x > std::numeric_limits<float>::max() ||
                    extent_z > std::numeric_limits<float>::max(),
            points, "Terrain extent exceeds representable world coordinates.");
    const double cols_d = Math::ceil(extent_x / p_spacing);
    const double rows_d = Math::ceil(extent_z / p_spacing);
    // Cap the candidate grid before casting to integers to avoid overflow and
    // unbounded allocations when processing large world coordinates.
    ERR_FAIL_COND_V_MSG(!std::isfinite(cols_d) || !std::isfinite(rows_d) ||
                    cols_d < 1 || rows_d < 1 || cols_d > 65536 || rows_d > 65536 ||
                    cols_d * rows_d > 65536,
            points, "Terrain scatter supports at most 65,536 candidate positions.");
    const int cols = int(cols_d);
    const int rows = int(rows_d);
    const float max_slope_tangent = p_max_slope_degrees == 90.0f ?
            std::numeric_limits<float>::infinity() : Math::tan(p_max_slope_degrees * float(Math::PI) / 180.0f);

    const uint32_t seed = uint32_t(p_seed);
    for (int z = 0; z < rows; z++) {
        for (int x = 0; x < cols; x++) {
            const float random_x = terrain_random01(seed, x, z, 1);
            const float random_z = terrain_random01(seed, x, z, 2);
            const float world_x = float(CLAMP((double(x) + 0.5 + (double(random_x) - 0.5) * p_jitter) *
                            double(p_spacing), 0.0, extent_x));
            const float world_z = float(CLAMP((double(z) + 0.5 + (double(random_z) - 0.5) * p_jitter) *
                            double(p_spacing), 0.0, extent_z));
            const Vector2 grid_pos(world_x / p_cell_size, world_z / p_cell_size);
            const float world_y = sample_height(grid_pos);
            if (world_y < p_min_height || world_y > p_max_height) {
                continue;
            }
            const float left = sample_height(grid_pos - Vector2(1, 0));
            const float right = sample_height(grid_pos + Vector2(1, 0));
            const float back = sample_height(grid_pos - Vector2(0, 1));
            const float forward = sample_height(grid_pos + Vector2(0, 1));
            const float grad_x = (right - left) / (2.0f * p_cell_size);
            const float grad_z = (forward - back) / (2.0f * p_cell_size);
            const float gradient_squared = grad_x * grad_x + grad_z * grad_z;
            if (gradient_squared > max_slope_tangent * max_slope_tangent) {
                continue;
            }
            points.push_back(Vector3(world_x, world_y, world_z));
        }
    }
    return points;
}

Ref<ArrayMesh> TerrainHeightmap::build_mesh(float p_cell_size) const {
    return build_chunk_mesh(Vector2i(0, 0), dimensions - Vector2i(1, 1), 1, p_cell_size);
}

Ref<ArrayMesh> TerrainHeightmap::build_chunk_mesh(const Vector2i &p_origin, const Vector2i &p_cell_count, int p_stride, float p_cell_size) const {
    ERR_FAIL_COND_V_MSG(!std::isfinite(p_cell_size) || p_cell_size <= 0, Ref<ArrayMesh>(),
            "Terrain mesh cell size must be finite and positive.");
    ERR_FAIL_COND_V_MSG(p_stride < 1 || p_stride > 128, Ref<ArrayMesh>(),
            "Terrain chunk stride must be between 1 and 128.");
    ERR_FAIL_COND_V_MSG(p_origin.x < 0 || p_origin.y < 0 ||
                    p_cell_count.x < 1 || p_cell_count.y < 1 ||
                    p_cell_count.x > dimensions.x - 1 || p_cell_count.y > dimensions.y - 1 ||
                    p_origin.x > dimensions.x - 1 - p_cell_count.x ||
                    p_origin.y > dimensions.y - 1 - p_cell_count.y,
            Ref<ArrayMesh>(), "Terrain chunk must fit within the heightmap's cells.");
    ERR_FAIL_COND_V_MSG(p_cell_count.x % p_stride != 0 || p_cell_count.y % p_stride != 0,
            Ref<ArrayMesh>(), "The chunk cell counts must be divisible by the LOD stride.");

    const int w = p_cell_count.x / p_stride + 1;
    const int h = p_cell_count.y / p_stride + 1;
    const int vertex_count = w * h;

    PackedVector3Array vertices;
    PackedVector3Array normals;
    PackedVector2Array uvs;
    PackedColorArray colors;
    PackedInt32Array indices;
    vertices.resize(vertex_count);
    normals.resize(vertex_count);
    uvs.resize(vertex_count);
    colors.resize(vertex_count);
    indices.resize((w - 1) * (h - 1) * 6);

    for (int z = 0; z < h; z++) {
        const int gz = p_origin.y + z * p_stride;
        for (int x = 0; x < w; x++) {
            const int gx = p_origin.x + x * p_stride;
            const int src_index = _index(gx, gz);
            const int dst_index = z * w + x;
            vertices.set(dst_index, Vector3(x * p_stride * p_cell_size, heights[src_index], z * p_stride * p_cell_size));
            uvs.set(dst_index, Vector2(float(gx) / (dimensions.x - 1), float(gz) / (dimensions.y - 1)));
            colors.set(dst_index, paint_weights[src_index]);

            // Derivatives come from the full-resolution heightmap so that
            // adjacent equal-LOD chunks share compatible boundary normals.
            const int xl = MAX(0, gx - 1);
            const int xr = MIN(dimensions.x - 1, gx + 1);
            const int zu = MAX(0, gz - 1);
            const int zd = MIN(dimensions.y - 1, gz + 1);
            const float dx = (heights[_index(xl, gz)] - heights[_index(xr, gz)]) /
                    ((xr - xl) * p_cell_size);
            const float dz = (heights[_index(gx, zu)] - heights[_index(gx, zd)]) /
                    ((zd - zu) * p_cell_size);
            normals.set(dst_index, Vector3(dx, 1.0f, dz).normalized());
        }
    }

    int cursor = 0;
    for (int z = 0; z < h - 1; z++) {
        for (int x = 0; x < w - 1; x++) {
            const int a = z * w + x;
            const int b = a + 1;
            const int c = a + w;
            const int d = c + 1;
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
    arrays[Mesh::ARRAY_COLOR] = colors;
    arrays[Mesh::ARRAY_INDEX] = indices;

    Ref<ArrayMesh> mesh;
    mesh.instantiate();
    mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
    return mesh;
}

void TerrainHeightmap::_bind_methods() {
    ClassDB::bind_method(D_METHOD("begin_edit"), &TerrainHeightmap::begin_edit);
    ClassDB::bind_method(D_METHOD("end_edit"), &TerrainHeightmap::end_edit);
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
    ClassDB::bind_method(D_METHOD("scatter_points", "seed", "spacing", "jitter", "max_slope_degrees", "min_height", "max_height", "cell_size"), &TerrainHeightmap::scatter_points,
            DEFVAL(0.75f), DEFVAL(45.0f), DEFVAL(-100000.0f), DEFVAL(100000.0f), DEFVAL(1.0f));
    ClassDB::bind_method(D_METHOD("build_mesh", "cell_size"), &TerrainHeightmap::build_mesh, DEFVAL(1.0f));
    ClassDB::bind_method(D_METHOD("build_chunk_mesh", "cell_origin", "cell_count", "lod_stride", "cell_size"), &TerrainHeightmap::build_chunk_mesh, DEFVAL(1), DEFVAL(1.0f));

    ADD_PROPERTY(PropertyInfo(Variant::VECTOR2I, "dimensions"), "set_dimensions", "get_dimensions");
    ADD_PROPERTY(PropertyInfo(Variant::PACKED_FLOAT32_ARRAY, "heights", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE), "set_heights", "get_heights");
    ADD_PROPERTY(PropertyInfo(Variant::PACKED_COLOR_ARRAY, "paint_weights", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE), "set_paint_weights", "get_paint_weights");
}
