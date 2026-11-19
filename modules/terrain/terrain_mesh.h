/**************************************************************************/
/*  terrain_mesh.h                                                        */
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

#include "scene/resources/3d/primitive_meshes.h"

class TerrainMesh : public PrimitiveMesh {
	GDCLASS(TerrainMesh, PrimitiveMesh);

	Vector2i grid_size = Vector2i(16, 16);
	float cell_size = 1.0f;
	float height_scale = 1.0f;
	PackedFloat32Array heights;

	int _index(int p_x, int p_z) const { return p_z * grid_size.x + p_x; }
	float _height_clamped(int p_x, int p_z) const;

protected:
	static void _bind_methods();
	void _create_mesh_array(Array &p_arr) const override;

public:
	void set_grid_size(const Vector2i &p_grid_size);
	Vector2i get_grid_size() const { return grid_size; }

	void set_cell_size(float p_cell_size);
	float get_cell_size() const { return cell_size; }

	void set_height_scale(float p_height_scale);
	float get_height_scale() const { return height_scale; }

	void set_heights(const PackedFloat32Array &p_heights);
	PackedFloat32Array get_heights() const { return heights; }

	void set_height(int p_x, int p_z, float p_height);
	float get_height(int p_x, int p_z) const;
	float sample_height(const Vector2 &p_grid_position) const;
	bool intersect_segment(const Vector3 &p_from, const Vector3 &p_to, Vector3 &r_hit) const;

	void sculpt(const Vector2 &p_grid_position, float p_radius, float p_amount);
	void smooth(const Vector2 &p_grid_position, float p_radius, float p_strength);
	void erode(int p_iterations, float p_talus = 0.0f, float p_strength = 0.5f);

	TerrainMesh();
};
