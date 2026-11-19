/**************************************************************************/
/*  terrain_3d.h                                                          */
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
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "scene/3d/mesh_instance_3d.h"

class Image;
class StandardMaterial3D;

// Initial built-in heightfield terrain: one grid, one surface, no LOD/streaming.
// Heights and vertex colors are the authoritative serialized data. The mesh is
// regenerated from those arrays, and must not be serialized independently.
class HeightmapTerrain3D : public MeshInstance3D {
	GDCLASS(HeightmapTerrain3D, MeshInstance3D);

	Vector2i grid_size = Vector2i(33, 33);
	real_t cell_size = 1.0;
	PackedFloat32Array height_data;
	PackedColorArray color_data;
	Ref<StandardMaterial3D> default_material;

	int _index(int p_x, int p_z) const { return p_z * grid_size.x + p_x; }
	float _height_clamped(int p_x, int p_z) const;
	void _rebuild_mesh();

protected:
	static void _bind_methods();
	void _validate_property(PropertyInfo &p_property) const;

public:
	void set_grid_size(const Vector2i &p_size);
	Vector2i get_grid_size() const { return grid_size; }

	void set_cell_size(real_t p_size);
	real_t get_cell_size() const { return cell_size; }

	void set_height_data(const PackedFloat32Array &p_data);
	PackedFloat32Array get_height_data() const { return height_data; }

	void set_color_data(const PackedColorArray &p_data);
	PackedColorArray get_color_data() const { return color_data; }

	void set_height_at(int p_x, int p_z, float p_height);
	float get_height_at(int p_x, int p_z) const;
	real_t sample_height(const Vector2 &p_grid_position) const;

	// Positions/radius are in grid cells, delta in height units.
	void sculpt(const Vector2 &p_grid_position, real_t p_radius, real_t p_delta);
	void smooth(const Vector2 &p_grid_position, real_t p_radius, real_t p_strength);
	void paint_color(const Vector2 &p_grid_position, real_t p_radius, const Color &p_color, real_t p_opacity);
	void import_heightmap(const Ref<Image> &p_image, real_t p_min_height, real_t p_max_height);

	HeightmapTerrain3D();
};
