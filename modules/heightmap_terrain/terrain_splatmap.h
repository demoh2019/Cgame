/**************************************************************************/
/*  terrain_splatmap.h                                                    */
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

#pragma once

#include "core/io/resource.h"
#include "core/math/vector2.h"

class Image;

/**
 * Four mutually normalized terrain material weights per vertex.
 * Serialized as a PackedColorArray; never stores texture image bytes in scenes.
 */
class TerrainSplatmap : public Resource {
    GDCLASS(TerrainSplatmap, Resource);

    int width = 17;
    int depth = 17;
    PackedColorArray weights;

protected:
    static void _bind_methods();

public:
    void set_dimensions(int p_width, int p_depth);
    void set_width(int p_width);
    int get_width() const;
    void set_depth(int p_depth);
    int get_depth() const;

    void set_weights(const PackedColorArray &p_weights);
    PackedColorArray get_weights() const;
    Color get_weights_at(int p_x, int p_z) const;
    real_t get_layer_weight(int p_x, int p_z, int p_layer) const;
    void paint_layer(int p_layer, const Vector2 &p_center, real_t p_radius, real_t p_strength);
    Ref<Image> to_image() const;

    TerrainSplatmap();
};
