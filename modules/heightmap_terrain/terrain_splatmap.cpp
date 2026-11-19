/**************************************************************************/
/*  terrain_splatmap.cpp                                                  */
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
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "terrain_splatmap.h"

#include "core/io/image.h"
#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void TerrainSplatmap::set_dimensions(int p_width, int p_depth) {
    ERR_FAIL_COND_MSG(p_width < 2 || p_depth < 2 || p_width > 513 || p_depth > 513,
            "Splatmap dimensions must each be between 2 and 513.");
    if (p_width == width && p_depth == depth) {
        return;
    }
    PackedColorArray resized;
    resized.resize(p_width * p_depth);
    for (int z = 0; z < p_depth; ++z) {
        for (int x = 0; x < p_width; ++x) {
            resized.set(z * p_width + x,
                    x < width && z < depth ? weights[z * width + x] : Color(1, 0, 0, 0));
        }
    }
    width = p_width;
    depth = p_depth;
    weights = resized;
    emit_changed();
}

void TerrainSplatmap::set_width(int p_width) {
    set_dimensions(p_width, depth);
}

int TerrainSplatmap::get_width() const {
    return width;
}

void TerrainSplatmap::set_depth(int p_depth) {
    set_dimensions(width, p_depth);
}

int TerrainSplatmap::get_depth() const {
    return depth;
}

void TerrainSplatmap::set_weights(const PackedColorArray &p_weights) {
    ERR_FAIL_COND_MSG(p_weights.size() != width * depth, "Splatmap weight count must match dimensions.");
    for (int i = 0; i < p_weights.size(); ++i) {
        const Color value = p_weights[i];
        real_t sum = 0;
        for (int channel = 0; channel < 4; ++channel) {
            const real_t component = value[channel];
            ERR_FAIL_COND_MSG(!Math::is_finite(component) || component < 0 || component > 1,
                    "All splat weights must be finite and within the range 0..1.");
            sum += component;
        }
        ERR_FAIL_COND_MSG(!Math::is_equal_approx(sum, real_t(1)),
                "Splat weights must sum to one at each vertex.");
    }
    if (p_weights == weights) {
        return;
    }
    weights = p_weights;
    emit_changed();
}

PackedColorArray TerrainSplatmap::get_weights() const {
    return weights;
}

Color TerrainSplatmap::get_weights_at(int p_x, int p_z) const {
    ERR_FAIL_COND_V(p_x < 0 || p_z < 0 || p_x >= width || p_z >= depth, Color());
    return weights[p_z * width + p_x];
}

real_t TerrainSplatmap::get_layer_weight(int p_x, int p_z, int p_layer) const {
    ERR_FAIL_COND_V(p_layer < 0 || p_layer >= 4, 0.0);
    return get_weights_at(p_x, p_z)[p_layer];
}

void TerrainSplatmap::paint_layer(int p_layer, const Vector2 &p_center, real_t p_radius, real_t p_strength) {
    ERR_FAIL_COND_MSG(p_layer < 0 || p_layer >= 4, "Only layers 0, 1, 2 and 3 exist.");
    ERR_FAIL_COND(!p_center.is_finite() || !Math::is_finite(p_radius) || p_radius <= 0 || !Math::is_finite(p_strength));
    const real_t strength = CLAMP(p_strength, real_t(0), real_t(1));
    if (strength == 0 || p_center.x + p_radius < 0 || p_center.y + p_radius < 0 ||
            p_center.x - p_radius > width - 1 || p_center.y - p_radius > depth - 1) {
        return;
    }
    // Clamp *before* narrowing to int to avoid overflow for far-away brush positions.
    const int min_x = int(Math::floor(MAX(p_center.x - p_radius, real_t(0))));
    const int max_x = int(Math::ceil(MIN(p_center.x + p_radius, real_t(width - 1))));
    const int min_z = int(Math::floor(MAX(p_center.y - p_radius, real_t(0))));
    const int max_z = int(Math::ceil(MIN(p_center.y + p_radius, real_t(depth - 1))));

    bool changed = false;
    for (int z = min_z; z <= max_z; ++z) {
        for (int x = min_x; x <= max_x; ++x) {
            const real_t distance = Vector2(x, z).distance_to(p_center);
            if (distance >= p_radius) {
                continue;
            }
            const real_t alpha = strength * (1.0 - distance / p_radius);
            const int index = z * width + x;
            const Color prior = weights[index];
            Color result;
            for (int c = 0; c < 4; ++c) {
                result[c] = prior[c] * (1 - alpha) + (c == p_layer ? alpha : 0);
            }
            if (prior != result) {
                weights.set(index, result);
                changed = true;
            }
        }
    }
    if (changed) {
        emit_changed();
    }
}

Ref<Image> TerrainSplatmap::to_image() const {
    Ref<Image> result = Image::create_empty(width, depth, false, Image::FORMAT_RGBA8);
    for (int z = 0; z < depth; ++z) {
        for (int x = 0; x < width; ++x) {
            result->set_pixel(x, z, weights[z * width + x]);
        }
    }
    return result;
}

void TerrainSplatmap::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_dimensions", "width", "depth"), &TerrainSplatmap::set_dimensions);
    ClassDB::bind_method(D_METHOD("set_width", "width"), &TerrainSplatmap::set_width);
    ClassDB::bind_method(D_METHOD("get_width"), &TerrainSplatmap::get_width);
    ClassDB::bind_method(D_METHOD("set_depth", "depth"), &TerrainSplatmap::set_depth);
    ClassDB::bind_method(D_METHOD("get_depth"), &TerrainSplatmap::get_depth);
    ClassDB::bind_method(D_METHOD("set_weights", "weights"), &TerrainSplatmap::set_weights);
    ClassDB::bind_method(D_METHOD("get_weights"), &TerrainSplatmap::get_weights);
    ClassDB::bind_method(D_METHOD("get_weights_at", "x", "z"), &TerrainSplatmap::get_weights_at);
    ClassDB::bind_method(D_METHOD("get_layer_weight", "x", "z", "layer"), &TerrainSplatmap::get_layer_weight);
    ClassDB::bind_method(D_METHOD("paint_layer", "layer", "center", "radius", "strength"), &TerrainSplatmap::paint_layer);
    ClassDB::bind_method(D_METHOD("to_image"), &TerrainSplatmap::to_image);

    ADD_PROPERTY(PropertyInfo(Variant::INT, "width", PROPERTY_HINT_RANGE, "2,513,1"), "set_width", "get_width");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "depth", PROPERTY_HINT_RANGE, "2,513,1"), "set_depth", "get_depth");
    ADD_PROPERTY(PropertyInfo(Variant::PACKED_COLOR_ARRAY, "weights", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE), "set_weights", "get_weights");
}

TerrainSplatmap::TerrainSplatmap() {
    weights.resize(width * depth);
    for (int i = 0; i < weights.size(); ++i) {
        weights.set(i, Color(1, 0, 0, 0));
    }
}
