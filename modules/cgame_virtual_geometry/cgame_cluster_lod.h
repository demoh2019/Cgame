/**************************************************************************/
/*  cgame_cluster_lod.h                                                   */
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

#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

// Nanite-style cluster DAG LOD hierarchy built with meshoptimizer.
//
// Level 0 holds the meshlets of the source mesh. Every following level groups up to
// GROUP_SIZE neighbouring clusters, simplifies the merged triangles to half with the
// group border locked (meshopt_SimplifyLockBorder) and re-splits the result into new
// meshlets. All clusters of a group share one LOD sphere and one error value, so a cut
// selected by select_cut() is crack free.
//
// Hierarchy dictionary (same layout as scripts/shared/cluster_lod.gd):
// vertices, clusters (Array of Dictionary), levels, roots.
// Cluster dictionary: indices, vertex_ids, center, radius, cone_axis, cone_cutoff, level,
// error, lod_center, lod_radius, parent_error, parent_center, parent_radius, children.
class CgameClusterLOD : public RefCounted {
	GDCLASS(CgameClusterLOD, RefCounted);

public:
	static constexpr int GROUP_SIZE = 4;
	static constexpr int MAX_LEVELS = 16;

protected:
	static void _bind_methods();

public:
	static Dictionary build_hierarchy(const PackedVector3Array &p_vertices, const PackedInt32Array &p_indices, int p_levels = 4);
	static PackedInt32Array select_cut(const Dictionary &p_hierarchy, const Vector3 &p_camera_pos, real_t p_fov_y, real_t p_screen_height, real_t p_error_pixels = 1.0);
	static int triangle_count(const Dictionary &p_hierarchy, const PackedInt32Array &p_cut);
	// Attribute-aware meshoptimizer path for static imported triangle surfaces.
	// Returns Mesh::ARRAY_MAX source arrays with ONLY the index buffer replaced.
	// Source normals/UV guide simplification; colors, tangents, skinning,
	// secondary UV and custom channels are left bit-for-bit intact.
	// Empty array means invalid input or no safe reduction.
	static Array simplify_surface_arrays(const Array &p_surface_arrays, int p_target_triangles,
			float p_normal_weight = 0.6f, float p_uv_weight = 0.6f);
};
