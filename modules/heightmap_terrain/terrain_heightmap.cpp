/**************************************************************************/
/*  terrain_heightmap.cpp                                                 */
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

#include "terrain_heightmap.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "scene/resources/texture.h"

void TerrainHeightmap::set_dimensions(int p_width, int p_depth) {
    ERR_FAIL_COND_MSG(p_width < 2 || p_depth < 2 || p_width > MAX_RESOLUTION || p_depth > MAX_RESOLUTION,
            "Terrain resolution must be between 2 and 513 samples on each axis.");
    if (width == p_width && depth == p_depth) {
        return;
    }

    PackedFloat32Array new_heights;
    PackedColorArray new_colors;
    new_heights.resize(p_width * p_depth);
    new_colors.resize(p_width * p_depth);
    for (int z = 0; z < p_depth; ++z) {
        for (int x = 0; x < p_width; ++x) {
            const int new_i = z * p_width + x;
            new_heights.set(new_i, (x < width && z < depth) ? heights[z * width + x] : 0.0f);
            new_colors.set(new_i, (x < width && z < depth) ? colors[z * width + x] : Color(1, 1, 1));
        }
    }

    width = p_width;
    depth = p_depth;
    heights = new_heights;
    colors = new_colors;
    emit_changed();
}

void TerrainHeightmap::set_width(int p_width) {
    set_dimensions(p_width, depth);
}

int TerrainHeightmap::get_width() const {
    return width;
}

void TerrainHeightmap::set_depth(int p_depth) {
    set_dimensions(width, p_depth);
}

int TerrainHeightmap::get_depth() const {
    return depth;
}

void TerrainHeightmap::set_heights(const PackedFloat32Array &p_heights) {
    ERR_FAIL_COND_MSG(p_heights.size() != width * depth, "The sample count must equal width * depth.");
    for (int i = 0; i < p_heights.size(); ++i) {
        ERR_FAIL_COND_MSG(!Math::is_finite(p_heights[i]), "Terrain heights must be finite.");
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

void TerrainHeightmap::set_colors(const PackedColorArray &p_colors) {
    ERR_FAIL_COND_MSG(p_colors.size() != width * depth, "The color count must equal width * depth.");
    for (int i = 0; i < p_colors.size(); ++i) {
        ERR_FAIL_COND_MSG(!Math::is_finite(p_colors[i].r) || !Math::is_finite(p_colors[i].g) || !Math::is_finite(p_colors[i].b) || !Math::is_finite(p_colors[i].a), "Terrain vertex colors must be finite.");
    }
    if (colors == p_colors) {
        return;
    }
    colors = p_colors;
    emit_changed();
}

PackedColorArray TerrainHeightmap::get_colors() const {
    return colors;
}

void TerrainHeightmap::set_height(int p_x, int p_z, real_t p_height) {
    ERR_FAIL_COND(p_x < 0 || p_x >= width || p_z < 0 || p_z >= depth);
    ERR_FAIL_COND(!Math::is_finite(p_height));
    const int index = p_z * width + p_x;
    if (heights[index] == p_height) {
        return;
    }
    heights.set(index, p_height);
    emit_changed();
}

real_t TerrainHeightmap::get_height(int p_x, int p_z) const {
    ERR_FAIL_COND_V(p_x < 0 || p_x >= width || p_z < 0 || p_z >= depth, 0.0);
    return heights[p_z * width + p_x];
}

Color TerrainHeightmap::get_color(int p_x, int p_z) const {
    ERR_FAIL_COND_V(p_x < 0 || p_x >= width || p_z < 0 || p_z >= depth, Color());
    return colors[p_z * width + p_x];
}

real_t TerrainHeightmap::sample_height(real_t p_x, real_t p_z) const {
    ERR_FAIL_COND_V(!Math::is_finite(p_x) || !Math::is_finite(p_z), 0.0);
    const real_t x = CLAMP(p_x, 0.0, real_t(width - 1));
    const real_t z = CLAMP(p_z, 0.0, real_t(depth - 1));
    const int x0 = int(Math::floor(x));
    const int z0 = int(Math::floor(z));
    const int x1 = MIN(x0 + 1, width - 1);
    const int z1 = MIN(z0 + 1, depth - 1);
    const real_t fx = x - x0;
    const real_t fz = z - z0;
    return Math::lerp(
            Math::lerp(real_t(heights[z0 * width + x0]), real_t(heights[z0 * width + x1]), fx),
            Math::lerp(real_t(heights[z1 * width + x0]), real_t(heights[z1 * width + x1]), fx),
            fz);
}

void TerrainHeightmap::apply_height_brush(const Vector2 &p_center, real_t p_radius, real_t p_amount) {
    ERR_FAIL_COND(!p_center.is_finite() || !Math::is_finite(p_radius) || !Math::is_finite(p_amount));
    ERR_FAIL_COND(p_radius <= 0);
    if (Math::is_zero_approx(p_amount)) {
        return;
    }
    // Clip in floating point before narrowing to int, even for huge brush coordinates.
    if (p_center.x + p_radius < 0 || p_center.y + p_radius < 0 ||
            p_center.x - p_radius > width - 1 || p_center.y - p_radius > depth - 1) {
        return;
    }
    const int from_x = int(Math::floor(MAX(p_center.x - p_radius, real_t(0))));
    const int to_x = int(Math::ceil(MIN(p_center.x + p_radius, real_t(width - 1))));
    const int from_z = int(Math::floor(MAX(p_center.y - p_radius, real_t(0))));
    const int to_z = int(Math::ceil(MIN(p_center.y + p_radius, real_t(depth - 1))));
    bool modified = false;
    for (int z = from_z; z <= to_z; ++z) {
        for (int x = from_x; x <= to_x; ++x) {
            const real_t distance = Vector2(x, z).distance_to(p_center);
            if (distance >= p_radius) {
                continue;
            }
            const int index = z * width + x;
            const real_t next = real_t(heights[index]) + p_amount * (1.0 - distance / p_radius);
            if (!Math::is_finite(next) || real_t(heights[index]) == next) {
                continue;
            }
            heights.set(index, next);
            modified = true;
        }
    }
    if (modified) {
        emit_changed();
    }
}

void TerrainHeightmap::apply_color_brush(const Vector2 &p_center, real_t p_radius, const Color &p_color, real_t p_strength) {
    ERR_FAIL_COND(!p_center.is_finite() || !Math::is_finite(p_color.r) || !Math::is_finite(p_color.g) || !Math::is_finite(p_color.b) || !Math::is_finite(p_color.a) || !Math::is_finite(p_radius) || !Math::is_finite(p_strength));
    ERR_FAIL_COND(p_radius <= 0);
    p_strength = CLAMP(p_strength, 0.0, 1.0);
    if (p_strength == 0) {
        return;
    }
    if (p_center.x + p_radius < 0 || p_center.y + p_radius < 0 ||
            p_center.x - p_radius > width - 1 || p_center.y - p_radius > depth - 1) {
        return;
    }
    const int from_x = int(Math::floor(MAX(p_center.x - p_radius, real_t(0))));
    const int to_x = int(Math::ceil(MIN(p_center.x + p_radius, real_t(width - 1))));
    const int from_z = int(Math::floor(MAX(p_center.y - p_radius, real_t(0))));
    const int to_z = int(Math::ceil(MIN(p_center.y + p_radius, real_t(depth - 1))));
    bool modified = false;
    for (int z = from_z; z <= to_z; ++z) {
        for (int x = from_x; x <= to_x; ++x) {
            const real_t distance = Vector2(x, z).distance_to(p_center);
            if (distance >= p_radius) {
                continue;
            }
            const int index = z * width + x;
            const Color next = colors[index].lerp(p_color, p_strength * (1.0 - distance / p_radius));
            if (colors[index] == next) {
                continue;
            }
            colors.set(index, next);
            modified = true;
        }
    }
    if (modified) {
        emit_changed();
    }
}

void TerrainHeightmap::import_height_image(const Ref<Image> &p_image, real_t p_min_height, real_t p_max_height) {
    ERR_FAIL_COND(p_image.is_null());
    ERR_FAIL_COND_MSG(p_image->is_compressed(), "Decompress the heightmap image before importing.");
    const int iw = p_image->get_width();
    const int ih = p_image->get_height();
    ERR_FAIL_COND_MSG(iw < 2 || ih < 2 || iw > MAX_RESOLUTION || ih > MAX_RESOLUTION,
            "Image heightmaps must have dimensions between 2 and 513.");
    ERR_FAIL_COND(!Math::is_finite(p_min_height) || !Math::is_finite(p_max_height));
    ERR_FAIL_COND(p_max_height < p_min_height);

    const Image::Format format = p_image->get_format();
    // R-only formats return Color(r, 0, 0, 1). Applying RGB luminance
    // would incorrectly scale a height of 1.0 to roughly 0.21.
    const bool single_channel = format == Image::FORMAT_L8 || format == Image::FORMAT_LA8 ||
            format == Image::FORMAT_R8 || format == Image::FORMAT_RF ||
            format == Image::FORMAT_RH || format == Image::FORMAT_R16 ||
            format == Image::FORMAT_R16I;
    PackedFloat32Array samples;
    samples.resize(iw * ih);
    for (int z = 0; z < ih; ++z) {
        for (int x = 0; x < iw; ++x) {
            const Color pixel = p_image->get_pixel(x, z);
            const real_t intensity = single_channel ? pixel.r : pixel.get_luminance();
            samples.set(z * iw + x, Math::lerp(p_min_height, p_max_height, CLAMP(intensity, real_t(0), real_t(1))));
        }
    }
    set_dimensions(iw, ih);
    set_heights(samples);
}

void TerrainHeightmap::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_dimensions", "width", "depth"), &TerrainHeightmap::set_dimensions);
    ClassDB::bind_method(D_METHOD("set_width", "width"), &TerrainHeightmap::set_width);
    ClassDB::bind_method(D_METHOD("get_width"), &TerrainHeightmap::get_width);
    ClassDB::bind_method(D_METHOD("set_depth", "depth"), &TerrainHeightmap::set_depth);
    ClassDB::bind_method(D_METHOD("get_depth"), &TerrainHeightmap::get_depth);
    ClassDB::bind_method(D_METHOD("set_heights", "heights"), &TerrainHeightmap::set_heights);
    ClassDB::bind_method(D_METHOD("get_heights"), &TerrainHeightmap::get_heights);
    ClassDB::bind_method(D_METHOD("set_colors", "colors"), &TerrainHeightmap::set_colors);
    ClassDB::bind_method(D_METHOD("get_colors"), &TerrainHeightmap::get_colors);
    ClassDB::bind_method(D_METHOD("set_height", "x", "z", "height"), &TerrainHeightmap::set_height);
    ClassDB::bind_method(D_METHOD("get_height", "x", "z"), &TerrainHeightmap::get_height);
    ClassDB::bind_method(D_METHOD("get_color", "x", "z"), &TerrainHeightmap::get_color);
    ClassDB::bind_method(D_METHOD("sample_height", "x", "z"), &TerrainHeightmap::sample_height);
    ClassDB::bind_method(D_METHOD("apply_height_brush", "center", "radius", "amount"), &TerrainHeightmap::apply_height_brush);
    ClassDB::bind_method(D_METHOD("apply_color_brush", "center", "radius", "color", "strength"), &TerrainHeightmap::apply_color_brush);
    ClassDB::bind_method(D_METHOD("import_height_image", "image", "min_height", "max_height"), &TerrainHeightmap::import_height_image);

    ADD_PROPERTY(PropertyInfo(Variant::INT, "width", PROPERTY_HINT_RANGE, "2,513,1"), "set_width", "get_width");
    ADD_PROPERTY(PropertyInfo(Variant::INT, "depth", PROPERTY_HINT_RANGE, "2,513,1"), "set_depth", "get_depth");
    ADD_PROPERTY(PropertyInfo(Variant::PACKED_FLOAT32_ARRAY, "heights", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE), "set_heights", "get_heights");
    ADD_PROPERTY(PropertyInfo(Variant::PACKED_COLOR_ARRAY, "colors", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE), "set_colors", "get_colors");
}

TerrainHeightmap::TerrainHeightmap() {
    heights.resize(width * depth);
    colors.resize(width * depth);
    for (int i = 0; i < colors.size(); ++i) {
        colors.set(i, Color(1, 1, 1));
    }
}
