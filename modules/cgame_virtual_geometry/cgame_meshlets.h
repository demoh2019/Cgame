/**************************************************************************/
/*  cgame_meshlets.h                                                      */
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

#include "core/math/vector3.h"
#include "core/object/ref_counted.h"
#include "core/templates/local_vector.h"
#include "core/variant/typed_array.h"
#include "core/variant/variant.h"

// Native meshlet (cluster) builder and per-cluster culling, backed by meshoptimizer.
//
// Dictionary keys match the GDScript reference (scripts/shared/meshlets.gd):
// indices, vertex_ids, bounds_center, bounds_radius, cone_axis, cone_cutoff.
// Triangle winding is Godot's (front faces are clockwise), so the cone axis
// points along the outward geometric normal.
class CgameMeshlets : public RefCounted {
	GDCLASS(CgameMeshlets, RefCounted);

public:
	static constexpr int DEFAULT_MAX_VERTICES = 64;
	static constexpr int DEFAULT_MAX_TRIANGLES = 124;
	static constexpr int LIMIT_MAX_VERTICES = 255;
	static constexpr int LIMIT_MAX_TRIANGLES = 512;

	// Plain C++ meshlet used internally and by CgameClusterLOD.
	struct Meshlet {
		LocalVector<int> indices; // Triangle list, local indices into vertex_ids.
		LocalVector<int> vertex_ids; // Indices into the source vertex array.
		Vector3 bounds_center;
		float bounds_radius = 0.0f;
		Vector3 cone_axis;
		float cone_cutoff = 1.0f;
	};

	// Builds meshlets from tightly packed float3 positions. Returns false (and prints an error) when an index is out of range.
	static bool build_native(const float *p_positions, uint32_t p_vertex_count, const uint32_t *p_indices, size_t p_index_count, int p_max_vertices, int p_max_triangles, LocalVector<Meshlet> &r_meshlets);

protected:
	static void _bind_methods();

public:
	static Array build_meshlets(const PackedVector3Array &p_vertices, const PackedInt32Array &p_indices, int p_max_vertices = DEFAULT_MAX_VERTICES, int p_max_triangles = DEFAULT_MAX_TRIANGLES);
	static bool cone_cull(const Dictionary &p_meshlet, const Vector3 &p_camera_pos);
	static bool frustum_cull(const Dictionary &p_meshlet, const TypedArray<Plane> &p_planes);

	static Dictionary meshlet_to_dictionary(const Meshlet &p_meshlet);
};
