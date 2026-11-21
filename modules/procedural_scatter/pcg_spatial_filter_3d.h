/**************************************************************************/
/*  pcg_spatial_filter_3d.h                                                 */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

// Stable bounded 3D thinning for procedural points. No RNG or scene access.
class PCGSpatialFilter3D : public RefCounted {
	GDCLASS(PCGSpatialFilter3D, RefCounted);

protected:
	static void _bind_methods();

public:
	static constexpr int MAX_CANDIDATES = 16384;
	static constexpr int MAX_SELECTED = 4096;
	static constexpr double MAX_COORDINATE = 10000000.0;
	static constexpr double MIN_SPACING = 0.05;
	static constexpr double MAX_SPACING = 10000.0;

	PackedInt32Array filter_indices(const PackedVector3Array &p_candidates,
			double p_min_spacing, int p_max_selected = MAX_SELECTED) const;
};
