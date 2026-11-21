/**************************************************************************/
/*  pcg_foliage_scalability_3d.h                                            */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

// Unreal-style foliage density scalability without mesh/scene/RNG mutation.
// Returns stable bit-reversed ordering and quality/distance visibility budgets.
class PCGFoliageScalability3D : public RefCounted {
	GDCLASS(PCGFoliageScalability3D, RefCounted);

protected:
	static void _bind_methods();

public:
	static constexpr int MAX_INSTANCES_PER_CLUSTER = 65536;
	static constexpr int MAX_CLUSTERS = 4096;
	static constexpr int MAX_LOD_INSTANCES = 16384;
	static constexpr int MAX_MESH_VARIANTS = 32;
	static constexpr double MAX_LOD_COORDINATE = 10000000.0;
	static constexpr double MAX_DISTANCE = 10000000.0;
	static constexpr double MAX_LOD_DISTANCE = 1000000.0;

	PackedInt32Array spread_indices(int p_count) const;
	PackedInt32Array plan_visible_counts(const PackedInt32Array &p_counts,
			const PackedFloat32Array &p_distances, int p_quality,
			double p_near_distance = 18.0, double p_far_distance = 125.0) const;

	// Reversible, bounded temporal density stabilization. Previous visible
	// counts use -1 as "uninitialized or changed quality tier". Only same-tier
	// visual counts within p_deadband instances are retained. No instance
	// transforms, GPU buffer, scene nodes, RNG or persistent engine state.
	PackedInt32Array plan_visible_counts_stable(const PackedInt32Array &p_counts,
			const PackedFloat32Array &p_distances, const PackedInt32Array &p_previous_counts,
			int p_quality, int p_deadband = 2,
			double p_near_distance = 18.0, double p_far_distance = 125.0) const;

	// Unreal ISM-inspired per-instance geometry LOD with two-band hysteresis.
	// Previous tiers may be empty for the first evaluation, otherwise must
	// match the full point set. Each tier is 0 (detail) or 1 (proxy).
	PackedInt32Array plan_instance_lods(const PackedVector3Array &p_positions,
			const Vector3 &p_viewer, const PackedInt32Array &p_previous_tiers,
			double p_switch_distance = 24.0, double p_hysteresis = 3.0) const;

	// Return two source-index arrays per mesh variant, ordered [near, far].
	// Every valid input point is represented exactly once, even if no point
	// requires a particular combination of mesh and LOD tier.
	Array partition_variant_lods(const PackedInt32Array &p_variants,
			const PackedInt32Array &p_lod_tiers, int p_variant_count) const;
};
