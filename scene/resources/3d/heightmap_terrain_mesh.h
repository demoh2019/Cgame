/**************************************************************************/
/*  heightmap_terrain_mesh.h                                               */
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
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER OF CONTRACT, TORT OR        */
/* OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR   */
/* THE USE OR OTHER DEALINGS IN THE SOFTWARE.                             */
/**************************************************************************/

#pragma once

#include "scene/resources/3d/primitive_meshes.h"

// Editable CPU heightfield mesh. Intended as a foundation for terrain tools;
// it does not implement clipmaps or GPU-driven terrain rendering.
class HeightmapTerrainMesh : public PrimitiveMesh {
	GDCLASS(HeightmapTerrainMesh, PrimitiveMesh);

	Vector2i grid_size = Vector2i(17, 17);
	Vector2 terrain_size = Vector2(16.0, 16.0);
	PackedFloat32Array height_data;
	PackedColorArray layer_weights;

	int _index(int p_x, int p_z) const;
	float _height_clamped(int p_x, int p_z) const;
	Vector2 _grid_to_local(int p_x, int p_z) const;
	float _brush_falloff(const Vector2 &p_center, float p_radius, int p_x, int p_z) const;
	void _reset_grid();

protected:
	static void _bind_methods();
	void _create_mesh_array(Array &r_arrays) const override;

public:
	void set_grid_size(const Vector2i &p_size);
	Vector2i get_grid_size() const;
	void set_terrain_size(const Vector2 &p_size);
	Vector2 get_terrain_size() const;

	void set_height_data(const PackedFloat32Array &p_heights);
	PackedFloat32Array get_height_data() const;
	void set_layer_weights(const PackedColorArray &p_weights);
	PackedColorArray get_layer_weights() const;

	void set_grid_height(int p_x, int p_z, float p_height);
	float get_grid_height(int p_x, int p_z) const;
	float get_local_height(const Vector2 &p_local_xz) const;

	void raise_brush(const Vector2 &p_local_xz, float p_radius, float p_delta);
	void flatten_brush(const Vector2 &p_local_xz, float p_radius, float p_height, float p_strength);
	void smooth_brush(const Vector2 &p_local_xz, float p_radius, float p_strength);
	void paint_layer(const Vector2 &p_local_xz, float p_radius, int p_layer, float p_strength);

	HeightmapTerrainMesh();
};
