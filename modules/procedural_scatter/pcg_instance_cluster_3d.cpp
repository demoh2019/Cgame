/**************************************************************************/
/*  pcg_instance_cluster_3d.cpp                                             */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#include "pcg_instance_cluster_3d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/templates/hash_map.h"
#include "core/templates/vector.h"

namespace {
// Preserve every instance if splitting would exceed the draw-call budget.
Array single_cluster(int p_count) {
	Array result;
	if (p_count == 0) {
		return result;
	}
	PackedInt32Array indices;
	indices.resize(p_count);
	for (int i = 0; i < p_count; ++i) {
		indices.set(i, i);
	}
	result.push_back(indices);
	return result;
}
} // namespace

void PCGInstanceCluster3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("partition_indices", "positions", "cell_size", "min_split_count", "max_clusters"),
			&PCGInstanceCluster3D::partition_indices, DEFVAL(32.0), DEFVAL(48), DEFVAL(MAX_CLUSTERS));
}

Array PCGInstanceCluster3D::partition_indices(const PackedVector3Array &p_positions,
		double p_cell_size, int p_min_split_count, int p_max_clusters) const {
	Array result;
	const int count = p_positions.size();
	if (count > MAX_INSTANCES || p_min_split_count < 1 || p_min_split_count > MAX_INSTANCES ||
			p_max_clusters < 1 || p_max_clusters > MAX_CLUSTERS ||
			!Math::is_finite(p_cell_size) || p_cell_size < MIN_CELL_SIZE ||
			p_cell_size > MAX_CELL_SIZE) {
		return result;
	}
	// Preflight all points before allocation: invalid late input never
	// produces partly instantiated scenery.
	for (const Vector3 &point : p_positions) {
		if (!point.is_finite() || Math::abs(double(point.x)) > MAX_COORDINATE ||
				Math::abs(double(point.y)) > MAX_COORDINATE ||
				Math::abs(double(point.z)) > MAX_COORDINATE) {
			return result;
		}
	}
	if (count == 0) {
		return result;
	}
	if (count < p_min_split_count || p_max_clusters == 1) {
		return single_cluster(count);
	}

	HashMap<Vector3i, int> lookup;
	Vector<Vector<int>> groups;
	for (int i = 0; i < count; ++i) {
		const Vector3 point = p_positions[i];
		// Bounded coordinates and a >=0.5 cell keep keys inside int32.
		const Vector3i cell(int32_t(Math::floor(double(point.x) / p_cell_size)),
				int32_t(Math::floor(double(point.y) / p_cell_size)),
				int32_t(Math::floor(double(point.z) / p_cell_size)));
		int *group_index = lookup.getptr(cell);
		if (group_index == nullptr) {
			if (groups.size() >= p_max_clusters) {
				// No silent dropped instances, no unbounded tiny draw calls.
				return single_cluster(count);
			}
			const int new_index = groups.size();
			groups.push_back(Vector<int>());
			lookup.insert(cell, new_index);
			group_index = lookup.getptr(cell);
		}
		groups.write[*group_index].push_back(i);
	}

	for (const Vector<int> &group : groups) {
		PackedInt32Array indices;
		indices.resize(group.size());
		for (int i = 0; i < group.size(); ++i) {
			indices.set(i, group[i]);
		}
		result.push_back(indices);
	}
	return result;
}
