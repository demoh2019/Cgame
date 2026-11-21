/**************************************************************************/
/*  pcg_instance_cluster_3d.h                                               */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

// Deterministic, budget-capped 3D grid clusters for instanced scenery.
// Results are ordered indices, never reordered or discarded transforms.
class PCGInstanceCluster3D : public RefCounted {
	GDCLASS(PCGInstanceCluster3D, RefCounted);

protected:
	static void _bind_methods();

public:
	static constexpr int MAX_INSTANCES = 65536;
	static constexpr int MAX_CLUSTERS = 256;
	static constexpr double MAX_COORDINATE = 10000000.0;
	static constexpr double MIN_CELL_SIZE = 0.5;
	static constexpr double MAX_CELL_SIZE = 10000.0;

	Array partition_indices(const PackedVector3Array &p_positions, double p_cell_size = 32.0,
			int p_min_split_count = 48, int p_max_clusters = MAX_CLUSTERS) const;
};
