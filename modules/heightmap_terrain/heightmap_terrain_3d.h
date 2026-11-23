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
#ifndef PHYSICS_3D_DISABLED
#include "scene/resources/3d/shape_3d.h"
class CollisionShape3D;
class StaticBody3D;
#endif

class HeightmapTerrain3D : public MeshInstance3D {
    GDCLASS(HeightmapTerrain3D, MeshInstance3D);

    Ref<TerrainHeightmap> heightmap;
    Ref<Material> terrain_material;
    Ref<Material> default_material;
    real_t cell_size = 1.0;

#ifndef PHYSICS_3D_DISABLED
    bool automatic_collision = false;
    bool collision_rebuild_pending = false;
    int collision_step = 1;
    int generated_collision_triangles = 0;
    int last_collision_width = -1;
    int last_collision_depth = -1;
    int last_collision_step = -1;
    real_t last_collision_cell_size = -1.0;
    PackedFloat32Array last_collision_heights;
    StaticBody3D *collision_body = nullptr;
    CollisionShape3D *collision_shape = nullptr;
    void _queue_collision_rebuild();
    void _update_auto_collision();
#endif

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

#ifndef PHYSICS_3D_DISABLED
    void set_auto_collision_enabled(bool p_enabled);
    bool is_auto_collision_enabled() const;
    void set_auto_collision_step(int p_step);
    int get_auto_collision_step() const;
    int get_auto_collision_triangle_count() const;
    Ref<Shape3D> get_auto_collision_shape() const;
#endif

    HeightmapTerrain3D();
    ~HeightmapTerrain3D();
};
