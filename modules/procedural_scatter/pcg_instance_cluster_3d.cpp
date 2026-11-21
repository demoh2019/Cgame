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

bool valid_input(const PackedVector3Array &p_positions, double p_cell_size,
		int p_min_split_count, int p_max_clusters) {
	if (p_positions.size() > PCGInstanceCluster3D::MAX_INSTANCES ||
			p_min_split_count < 1 || p_min_split_count > PCGInstanceCluster3D::MAX_INSTANCES ||
			p_max_clusters < 1 || p_max_clusters > PCGInstanceCluster3D::MAX_CLUSTERS ||
			!Math::is_finite(p_cell_size) ||
			p_cell_size < PCGInstanceCluster3D::MIN_CELL_SIZE ||
			p_cell_size > PCGInstanceCluster3D::MAX_CELL_SIZE) {
		return false;
	}
	// Preflight all points so an invalid late point cannot create partial groups.
	for (const Vector3 &point : p_positions) {
		if (!point.is_finite() ||
				Math::abs(double(point.x)) > PCGInstanceCluster3D::MAX_COORDINATE ||
				Math::abs(double(point.y)) > PCGInstanceCluster3D::MAX_COORDINATE ||
				Math::abs(double(point.z)) > PCGInstanceCluster3D::MAX_COORDINATE) {
			return false;
		}
	}
	return true;
}

// Empty means the proposed grid would exceed the cluster cap.
// Callers choose whether to retain one batch or retry with coarser cells.
Array build_bounded_clusters(const PackedVector3Array &p_positions,
		double p_cell_size, int p_max_clusters) {
	Array result;
	HashMap<Vector3i, int> lookup;
	Vector<Vector<int>> groups;
	for (int i = 0; i < p_positions.size(); ++i) {
		const Vector3 point = p_positions[i];
		// Bounds and minimum cell size keep all keys in int32 range.
		const Vector3i cell(int32_t(Math::floor(double(point.x) / p_cell_size)),
				int32_t(Math::floor(double(point.y) / p_cell_size)),
				int32_t(Math::floor(double(point.z) / p_cell_size)));
		int *group_index = lookup.getptr(cell);
		if (group_index == nullptr) {
			if (groups.size() >= p_max_clusters) {
				return result;
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
} // namespace

void PCGInstanceCluster3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("partition_indices", "positions", "cell_size", "min_split_count", "max_clusters"),
			&PCGInstanceCluster3D::partition_indices, DEFVAL(32.0), DEFVAL(48), DEFVAL(MAX_CLUSTERS));
	ClassDB::bind_method(D_METHOD("partition_indices_adaptive", "positions", "cell_size", "min_split_count", "max_clusters", "max_coarsen_passes"),
			&PCGInstanceCluster3D::partition_indices_adaptive, DEFVAL(32.0), DEFVAL(48), DEFVAL(MAX_CLUSTERS), DEFVAL(MAX_COARSEN_PASSES));
}

Array PCGInstanceCluster3D::partition_indices(const PackedVector3Array &p_positions,
		double p_cell_size, int p_min_split_count, int p_max_clusters) const {
	Array result;
	if (!valid_input(p_positions, p_cell_size, p_min_split_count, p_max_clusters)) {
		return result;
	}
	const int count = p_positions.size();
	if (count == 0) {
		return result;
	}
	if (count < p_min_split_count || p_max_clusters == 1) {
		return single_cluster(count);
	}
	result = build_bounded_clusters(p_positions, p_cell_size, p_max_clusters);
	return result.is_empty() ? single_cluster(count) : result;
}

Array PCGInstanceCluster3D::partition_indices_adaptive(const PackedVector3Array &p_positions,
		double p_cell_size, int p_min_split_count, int p_max_clusters,
		int p_max_coarsen_passes) const {
	Array result;
	if (!valid_input(p_positions, p_cell_size, p_min_split_count, p_max_clusters) ||
			p_max_coarsen_passes < 0 || p_max_coarsen_passes > MAX_COARSEN_PASSES) {
		return result;
	}
	const int count = p_positions.size();
	if (count == 0) {
		return result;
	}
	if (count < p_min_split_count || p_max_clusters == 1) {
		return single_cluster(count);
	}
	// Fast path: if the initial grid fits, this is precisely the legacy result.
	// Retries happen only for pathological numbers of occupied cells.
	double cell_size = p_cell_size;
	for (int pass = 0; pass <= p_max_coarsen_passes; ++pass) {
		result = build_bounded_clusters(p_positions, cell_size, p_max_clusters);
		if (!result.is_empty()) {
			return result;
		}
		if (cell_size >= MAX_CELL_SIZE) {
			break;
		}
		cell_size = MIN(cell_size * 2.0, MAX_CELL_SIZE);
	}
	// Preserve all instances when even the largest permitted grid overflows.
	return single_cluster(count);
}
