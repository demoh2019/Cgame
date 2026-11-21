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
	static constexpr double MAX_DISTANCE = 10000000.0;
	static constexpr double MAX_LOD_DISTANCE = 1000000.0;

	PackedInt32Array spread_indices(int p_count) const;
	PackedInt32Array plan_visible_counts(const PackedInt32Array &p_counts,
			const PackedFloat32Array &p_distances, int p_quality,
			double p_near_distance = 18.0, double p_far_distance = 125.0) const;

	// Screen-space foliage density: approximate per-instance pixel diameter
	// from camera depth and nominal world mesh size. Groups are selected in one
	// native call, independent of viewport resolution, zoom, and scene traversal.
	// For orthographic projection, focal_pixels is pixels per world unit.
	PackedInt32Array plan_projected_visible_counts(const PackedInt32Array &p_counts,
			const PackedVector3Array &p_centers,
			const PackedFloat32Array &p_mesh_diameters,
			const Vector3 &p_camera_position, const Vector3 &p_camera_forward,
			double p_focal_pixels, bool p_orthographic, int p_quality,
			double p_near_pixels = 20.0, double p_far_pixels = 2.0) const;
};
