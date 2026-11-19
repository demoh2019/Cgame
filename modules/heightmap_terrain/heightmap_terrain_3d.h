/**************************************************************************/
/*  heightmap_terrain_3d.h                                                */
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

#include "scene/3d/mesh_instance_3d.h"
#include "terrain_heightmap.h"

class HeightmapTerrain3D : public MeshInstance3D {
    GDCLASS(HeightmapTerrain3D, MeshInstance3D);

    Ref<TerrainHeightmap> heightmap;
    Ref<Material> terrain_material;
    Ref<Material> default_material;
    real_t cell_size = 1.0;

    void _heightmap_changed();
    void _rebuild_mesh();

protected:
    static void _bind_methods();

public:
    void set_heightmap(const Ref<TerrainHeightmap> &p_heightmap);
    Ref<TerrainHeightmap> get_heightmap() const;

    void set_cell_size(real_t p_size);
    real_t get_cell_size() const;

    void set_terrain_material(const Ref<Material> &p_material);
    Ref<Material> get_terrain_material() const;

    real_t sample_height_local(real_t p_x, real_t p_z) const;
    Ref<ArrayMesh> build_mesh() const;

    HeightmapTerrain3D();
    ~HeightmapTerrain3D();
};
