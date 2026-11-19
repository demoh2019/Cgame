/**************************************************************************/
/*  terrain_heightmap.h                                                   */
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

#include "core/io/resource.h"
#include "core/math/vector2.h"
#include "core/variant/variant.h"

class Image;

// Shared, serializable height and vertex-color samples. Coordinates are in grid units.
class TerrainHeightmap : public Resource {
    GDCLASS(TerrainHeightmap, Resource);

public:
    static constexpr int MAX_RESOLUTION = 513;

private:
    int width = 17;
    int depth = 17;
    PackedFloat32Array heights;
    PackedColorArray colors;

protected:
    static void _bind_methods();

public:
    void set_dimensions(int p_width, int p_depth);
    void set_width(int p_width);
    int get_width() const;
    void set_depth(int p_depth);
    int get_depth() const;

    void set_heights(const PackedFloat32Array &p_heights);
    PackedFloat32Array get_heights() const;
    void set_colors(const PackedColorArray &p_colors);
    PackedColorArray get_colors() const;

    void set_height(int p_x, int p_z, real_t p_height);
    real_t get_height(int p_x, int p_z) const;
    Color get_color(int p_x, int p_z) const;
    real_t sample_height(real_t p_x, real_t p_z) const;

    void apply_height_brush(const Vector2 &p_center, real_t p_radius, real_t p_amount);
    void apply_color_brush(const Vector2 &p_center, real_t p_radius, const Color &p_color, real_t p_strength);
    void import_height_image(const Ref<Image> &p_image, real_t p_min_height, real_t p_max_height);

    TerrainHeightmap();
};
