/**************************************************************************/
/*  heightmap_terrain_geometry.h                                             */
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

#include "core/math/aabb.h"
#include "core/math/vector2.h"
#include "core/math/vector3.h"
#include "core/variant/variant.h"

// Mesh and sampling math of ChunkedTerrain3D, free of any scene or rendering code so it can be
// unit tested. A height field is a row-major grid of `width` x `depth` samples (index = z * width + x).
namespace HeightmapTerrainGeometry {

struct HeightField {
	const real_t *heights = nullptr;
	int width = 0;
	int depth = 0;

	// Edge samples repeat outward, so lookups just past the border are safe.
	_FORCE_INLINE_ real_t get(int p_x, int p_z) const {
		p_x = CLAMP(p_x, 0, width - 1);
		p_z = CLAMP(p_z, 0, depth - 1);
		return heights[p_z * width + p_x];
	}
	bool is_valid() const { return heights != nullptr && width >= 2 && depth >= 2; }
};

struct Params {
	// World distance between two neighbouring samples on x and z.
	Vector2 spacing = Vector2(1, 1);
	real_t height_scale = 1.0;
	real_t height_offset = 0.0;
	// World position of sample (0, 0). Lets the terrain be centered on its node.
	Vector2 origin;
	// Depth of the vertical skirt that hides cracks between chunks of different detail.
	real_t skirt_depth = 1.0;
};

struct ChunkMesh {
	PackedVector3Array vertices;
	PackedVector3Array normals;
	PackedVector2Array uvs;
	PackedInt32Array indices;
	AABB bounds;
};

// Bilinear height at fractional sample coordinates (already in sample space, not meters).
real_t sample_height(const HeightField &p_field, real_t p_x, real_t p_z);
// Unit surface normal at an integer sample, by central differences.
Vector3 sample_normal(const HeightField &p_field, int p_x, int p_z, const Params &p_params);
// Unit surface normal at fractional sample coordinates (bilinear blend of the four neighbours).
Vector3 sample_normal_bilinear(const HeightField &p_field, real_t p_x, real_t p_z, const Params &p_params);

// Builds the mesh of the chunk whose first sample is (p_x0, p_z0) and which covers p_quads quads on
// each side, sampling every `p_stride` samples (stride 1 is full detail, 2 halves the resolution...).
// p_quads must be a multiple of p_stride. Vertices are in the terrain's local space, UVs span the
// whole terrain from 0 to 1. Returns false for invalid input.
bool build_chunk(const HeightField &p_field, int p_x0, int p_z0, int p_quads, int p_stride, const Params &p_params, ChunkMesh &r_mesh);

// Minimum and maximum raw sample value inside a chunk (inclusive of its far border samples).
void chunk_height_range(const HeightField &p_field, int p_x0, int p_z0, int p_quads, real_t &r_min, real_t &r_max);

// Detail level for a chunk at `p_distance` from the viewer. Level 0 is full detail, and every
// level doubles the distance. `p_current` (or -1) adds hysteresis: the current level is kept while
// the distance stays within 10% of its range, so chunks at a boundary do not flip every frame.
int select_lod(real_t p_distance, real_t p_base_distance, int p_lod_count, int p_current = -1);

// Largest stride that divides the chunk and does not exceed 2^(lod_count - 1).
int lod_stride(int p_lod, int p_quads);

} // namespace HeightmapTerrainGeometry
