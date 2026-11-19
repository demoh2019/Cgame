/**************************************************************************/
/*  procedural_world.h                                                    */
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

#include "core/math/rect2.h"
#include "core/object/ref_counted.h"
#include "core/variant/variant.h"
#include "scene/resources/mesh.h"

class ProceduralWorld : public RefCounted {
	GDCLASS(ProceduralWorld, RefCounted);

	static uint32_t _hash(int64_t p_x, int64_t p_y, uint32_t p_seed);
	static float _noise(double p_x, double p_y, uint32_t p_seed);

protected:
	static void _bind_methods();

public:
	// Row-major height map: index = y * width + x.
	PackedFloat32Array generate_heightmap(int p_width, int p_height, int p_seed, float p_scale = 64.0f, float p_amplitude = 32.0f, int p_octaves = 4, const Vector2i &p_origin = Vector2i()) const;
	PackedFloat32Array paint_heightmap(const PackedFloat32Array &p_heights, int p_width, int p_height, const Vector2 &p_center, float p_radius, float p_delta, float p_falloff = 1.0f) const;
	Ref<ArrayMesh> create_terrain_mesh(const PackedFloat32Array &p_heights, int p_width, int p_height, float p_cell_size = 1.0f, float p_height_scale = 1.0f) const;
	PackedFloat32Array erode_heightmap(const PackedFloat32Array &p_heights, int p_width, int p_height, int p_iterations = 8, float p_talus = 1.0f, float p_strength = 0.5f) const;

	// Rejection-based blue-noise-inspired scatter; never returns points closer than min_distance.
	PackedVector2Array scatter_points(const Rect2 &p_area, float p_min_distance, int p_seed, int p_max_points = 1024, int p_attempts_per_point = 30) const;

	// Returns every chunk (Vector2i coordinates) intersecting the half-open rectangle.
	Array get_chunk_coordinates(const Rect2 &p_world_area, int p_chunk_size = 64) const;
};
