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
#include "terrain_splatmap.h"

class ImageTexture;
class ShaderMaterial;
class Texture2D;

class HeightmapTerrain3D : public MeshInstance3D {
    GDCLASS(HeightmapTerrain3D, MeshInstance3D);

    Ref<TerrainHeightmap> heightmap;
    Ref<TerrainSplatmap> splatmap;
    Ref<Texture2D> texture_layers[4];
    Ref<ImageTexture> splat_texture;
    Ref<ImageTexture> white_texture;
    Ref<ShaderMaterial> blend_material;
    Ref<Material> terrain_material;
    Ref<Material> default_material;
    real_t cell_size = 1.0;
    real_t texture_tiling = 8.0;

    void _heightmap_changed();
    void _splatmap_changed();
    void _refresh_splat_texture();
    void _refresh_layer_material();
    Ref<Material> _get_active_material() const;
    void _rebuild_mesh();

protected:
    static void _bind_methods();

public:
    void set_heightmap(const Ref<TerrainHeightmap> &p_heightmap);
    Ref<TerrainHeightmap> get_heightmap() const;

    void set_splatmap(const Ref<TerrainSplatmap> &p_splatmap);
    Ref<TerrainSplatmap> get_splatmap() const;

    void set_texture_layer(int p_layer, const Ref<Texture2D> &p_texture);
    Ref<Texture2D> get_texture_layer(int p_layer) const;
    void set_layer_0(const Ref<Texture2D> &p_texture);
    Ref<Texture2D> get_layer_0() const;
    void set_layer_1(const Ref<Texture2D> &p_texture);
    Ref<Texture2D> get_layer_1() const;
    void set_layer_2(const Ref<Texture2D> &p_texture);
    Ref<Texture2D> get_layer_2() const;
    void set_layer_3(const Ref<Texture2D> &p_texture);
    Ref<Texture2D> get_layer_3() const;

    void set_texture_tiling(real_t p_tiling);
    real_t get_texture_tiling() const;

    void set_cell_size(real_t p_size);
    real_t get_cell_size() const;

    void set_terrain_material(const Ref<Material> &p_material);
    Ref<Material> get_terrain_material() const;

    real_t sample_height_local(real_t p_x, real_t p_z) const;
    Ref<ArrayMesh> build_mesh() const;

    HeightmapTerrain3D();
    ~HeightmapTerrain3D();
};
