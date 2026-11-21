/**************************************************************************/
/*  pcg_surface_filter_3d.h                                                 */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

// Unreal PCG-style normal/slope and elevation selection for sampled points.
// Pure data, stable original indices; the caller handles placement and RNG.
class PCGSurfaceFilter3D : public RefCounted {
	GDCLASS(PCGSurfaceFilter3D, RefCounted);

protected:
	static void _bind_methods();

public:
	static constexpr int MAX_CANDIDATES = 16384;
	static constexpr int MAX_SELECTED = 4096;
	static constexpr double MAX_COORDINATE = 10000000.0;

	PackedInt32Array filter_indices(const PackedVector3Array &p_positions,
			const PackedVector3Array &p_normals, double p_min_slope_degrees = 0.0,
			double p_max_slope_degrees = 90.0, double p_min_height = -MAX_COORDINATE,
			double p_max_height = MAX_COORDINATE, int p_max_selected = MAX_SELECTED) const;

	// Batch-rotate authored/yaw-scaled transforms toward terrain normals. Retains
	// translation, authored yaw, scale, and stable order. Limits tilt to prevent
	// visual props tipping over on cliffs; no RNG, physics or scene mutation.
	Array align_transforms(const Array &p_transforms, const PackedVector3Array &p_normals,
			double p_max_tilt_degrees = 35.0) const;
};
