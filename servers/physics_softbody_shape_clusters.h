/**************************************************************************/
/*  physics_softbody_shape_clusters.h                                     */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/math/quaternion.h"
#include "core/math/vector3.h"
#include "core/templates/local_vector.h"

#include <cstdint>
#include <limits>

// Optional overlapping graph-local shape matching. Build BFS cores with at
// most core_size vertices, then expand each core by one original-mesh edge.
// Per-cluster best-fit rotations give elastic bending between groups; Jacobi
// averaging at shared nodes avoids correction order dependence. Unlike a
// tetrahedral FEM mesh this requires only the existing triangle graph.
struct PhysicsSoftBodyShapeEdge {
	uint32_t a = 0;
	uint32_t b = 0;
};

struct PhysicsSoftBodyShapeCluster {
	uint32_t first = 0;
	uint32_t count = 0;
};

_FORCE_INLINE_ bool physics_softbody_build_shape_clusters(
		uint32_t p_vertex_count, const LocalVector<PhysicsSoftBodyShapeEdge> &p_edges,
		uint32_t p_core_size, LocalVector<PhysicsSoftBodyShapeCluster> &r_clusters,
		LocalVector<uint32_t> &r_members) {
	if (p_vertex_count < 3 || p_vertex_count == UINT32_MAX ||
			p_core_size < 3 || p_core_size > 64 ||
			p_edges.size() > UINT32_MAX / 2) {
		return false;
	}
	// Validate all edges before touching either output.
	for (const PhysicsSoftBodyShapeEdge &edge : p_edges) {
		if (edge.a >= p_vertex_count || edge.b >= p_vertex_count || edge.a == edge.b) {
			return false;
		}
	}

	// Compressed sparse row adjacency avoids O(vertex_count) allocations for
	// a large triangle soup. Duplicated edges are safe: visited markers remove
	// repeated vertices from both core and overlap.
	LocalVector<uint32_t> degree;
	degree.resize(p_vertex_count);
	for (uint32_t i = 0; i < p_vertex_count; ++i) {
		degree[i] = 0;
	}
	for (const PhysicsSoftBodyShapeEdge &edge : p_edges) {
		++degree[edge.a];
		++degree[edge.b];
	}
	LocalVector<uint32_t> offsets;
	offsets.resize(p_vertex_count + 1);
	offsets[0] = 0;
	for (uint32_t i = 0; i < p_vertex_count; ++i) {
		offsets[i + 1] = offsets[i] + degree[i];
	}
	LocalVector<uint32_t> cursor;
	cursor.resize(p_vertex_count);
	for (uint32_t i = 0; i < p_vertex_count; ++i) {
		cursor[i] = offsets[i];
	}
	LocalVector<uint32_t> neighbors;
	neighbors.resize(offsets[p_vertex_count]);
	for (const PhysicsSoftBodyShapeEdge &edge : p_edges) {
		neighbors[cursor[edge.a]++] = edge.b;
		neighbors[cursor[edge.b]++] = edge.a;
	}

	LocalVector<uint8_t> assigned;
	assigned.resize(p_vertex_count);
	LocalVector<uint32_t> stamped;
	stamped.resize(p_vertex_count);
	for (uint32_t i = 0; i < p_vertex_count; ++i) {
		assigned[i] = 0;
		stamped[i] = 0;
	}
	LocalVector<uint32_t> core;
	r_clusters.reset();
	r_members.reset();
	for (uint32_t seed = 0; seed < p_vertex_count; ++seed) {
		if (assigned[seed]) {
			continue;
		}
		core.clear();
		core.push_back(seed);
		assigned[seed] = 1;
		for (uint32_t read = 0; read < core.size() && core.size() < p_core_size; ++read) {
			const uint32_t node = core[read];
			for (uint32_t k = offsets[node]; k < offsets[node + 1] && core.size() < p_core_size; ++k) {
				const uint32_t adjacent = neighbors[k];
				if (!assigned[adjacent]) {
					assigned[adjacent] = 1;
					core.push_back(adjacent);
				}
			}
		}

		// Each core has one-ring overlap with adjacent cores, ensuring their
		// deformation fields are connected rather than split at hard seams.
		const uint32_t mark = seed + 1;
		const uint32_t first = r_members.size();
		for (uint32_t node : core) {
			stamped[node] = mark;
			r_members.push_back(node);
		}
		for (uint32_t node : core) {
			for (uint32_t k = offsets[node]; k < offsets[node + 1]; ++k) {
				const uint32_t adjacent = neighbors[k];
				if (stamped[adjacent] != mark) {
					stamped[adjacent] = mark;
					r_members.push_back(adjacent);
				}
			}
		}
		if (r_members.size() - first < 3) {
			// Isolated vertices and 2-node lines lack enough shape geometry.
			r_members.resize(first);
		} else {
			PhysicsSoftBodyShapeCluster cluster;
			cluster.first = first;
			cluster.count = r_members.size() - first;
			r_clusters.push_back(cluster);
		}
	}
	return !r_clusters.is_empty();
}

// Collect one cluster goal without changing any mesh position. The caller
// computes a single weighted average for each movable particle after all
// clusters have been processed, making the solver independent of cluster order.
_FORCE_INLINE_ bool physics_softbody_shape_cluster_accumulate(
		const Vector3 &p_position, const Vector3 &p_rest_offset,
		const Vector3 &p_center, const Quaternion &p_rotation,
		Vector3 &r_displacement_sum, uint32_t &r_sample_count) {
	if (!p_position.is_finite() || !p_rest_offset.is_finite() ||
			!p_center.is_finite() || r_sample_count == UINT32_MAX) {
		return false;
	}
	const Vector3 goal = p_center + p_rotation.xform(p_rest_offset);
	const Vector3 increment = goal - p_position;
	if (!goal.is_finite() || !increment.is_finite()) {
		return false;
	}
	const Vector3 next = r_displacement_sum + increment;
	if (!next.is_finite()) {
		return false;
	}
	r_displacement_sum = next;
	++r_sample_count;
	return true;
}
