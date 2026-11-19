/**************************************************************************/
/*  terrain_heightmap.h                                                   */
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
/**************************************************************************/

#pragma once

#include "core/io/resource.h"
#include "scene/resources/mesh.h"

// A serializable, CPU-side height field with four vertex-paint layers.
// Coordinates are measured in grid cells; build_mesh() applies the world scale.
class TerrainHeightmap : public Resource {
	GDCLASS(TerrainHeightmap, Resource);

	Size2i dimensions = Size2i(17, 17);
	PackedFloat32Array heights;
	PackedColorArray paint_weights;
	int edit_depth = 0;
	bool pending_change = false;

	bool _valid_cell(int p_x, int p_z) const;
	int _index(int p_x, int p_z) const;
	void _notify_changed();

protected:
	static void _bind_methods();

public:
	TerrainHeightmap();

	void begin_edit();
	void end_edit();

	void set_dimensions(const Size2i &p_dimensions);
	Size2i get_dimensions() const;

	void set_heights(const PackedFloat32Array &p_heights);
	PackedFloat32Array get_heights() const;

	void set_paint_weights(const PackedColorArray &p_weights);
	PackedColorArray get_paint_weights() const;

	void set_height_at(int p_x, int p_z, float p_height);
	float get_height_at(int p_x, int p_z) const;
	Color get_paint_at(int p_x, int p_z) const;

	float sample_height(const Vector2 &p_grid_position) const;
	void sculpt(const Vector2 &p_center, float p_radius, float p_delta);
	void smooth(const Vector2 &p_center, float p_radius, float p_strength);
	void erode_talus(int p_iterations, float p_talus, float p_rate);
	void paint_layer(const Vector2 &p_center, float p_radius, int p_layer, float p_strength);

	// Deterministic grid-jitter foliage candidates, optionally constrained by slope and elevation.
	PackedVector3Array scatter_points(int p_seed, float p_spacing, float p_jitter = 0.75f,
			float p_max_slope_degrees = 45.0f, float p_min_height = -100000.0f,
			float p_max_height = 100000.0f, float p_cell_size = 1.0f) const;

	Ref<ArrayMesh> build_mesh(float p_cell_size = 1.0f) const;
	Ref<ArrayMesh> build_chunk_mesh(const Vector2i &p_origin, const Vector2i &p_cell_count, int p_stride = 1, float p_cell_size = 1.0f) const;
};
