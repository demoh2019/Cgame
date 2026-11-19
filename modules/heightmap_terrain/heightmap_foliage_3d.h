/**************************************************************************/
/*  heightmap_foliage_3d.h                                                */
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

#include "scene/3d/multimesh_instance_3d.h"
#include "terrain_heightmap.h"

class HeightmapFoliage3D : public MultiMeshInstance3D {
    GDCLASS(HeightmapFoliage3D, MultiMeshInstance3D);

    Ref<TerrainHeightmap> heightmap;
    Ref<Mesh> foliage_mesh;
    int instance_count = 128;
    uint32_t random_seed = 1;
    real_t terrain_cell_size = 1.0;
    real_t minimum_scale = 0.8;
    real_t maximum_scale = 1.2;
    real_t maximum_slope_degrees = 60.0;

    void _heightmap_changed();

protected:
    static void _bind_methods();

public:
    void set_heightmap(const Ref<TerrainHeightmap> &p_data);
    Ref<TerrainHeightmap> get_heightmap() const;
    void set_foliage_mesh(const Ref<Mesh> &p_mesh);
    Ref<Mesh> get_foliage_mesh() const;
    void set_instance_count(int p_count);
    int get_instance_count() const;
    void set_random_seed(uint32_t p_seed);
    uint32_t get_random_seed() const;
    void set_terrain_cell_size(real_t p_size);
    real_t get_terrain_cell_size() const;
    void set_minimum_scale(real_t p_scale);
    real_t get_minimum_scale() const;
    void set_maximum_scale(real_t p_scale);
    real_t get_maximum_scale() const;
    void set_maximum_slope_degrees(real_t p_angle);
    real_t get_maximum_slope_degrees() const;

    void regenerate();
    int get_generated_count() const;

    ~HeightmapFoliage3D();
};
