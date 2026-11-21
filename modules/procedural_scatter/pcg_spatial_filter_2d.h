/**************************************************************************/
/*  pcg_spatial_filter_2d.h                                                 */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

// Deterministic spatial thinning for client-only procedural decoration.
// Stable greedy input order, world-coordinate grid, no RNG or scene access.
class PCGSpatialFilter2D : public RefCounted {
	GDCLASS(PCGSpatialFilter2D, RefCounted);

protected:
	static void _bind_methods();

public:
	static constexpr int MAX_CANDIDATES = 16384;
	static constexpr int MAX_SELECTED = 4096;
	static constexpr double MAX_COORDINATE = 10000000.0;
	static constexpr double MIN_SPACING = 0.05;
	static constexpr double MAX_SPACING = 10000.0;

	// Returns original candidate indices in stable order. Adjacent accepted
	// points are at least min_spacing apart. A zero spacing preserves order.
	// Invalid/oversized inputs are rejected atomically (empty result).
	PackedInt32Array filter_indices(const PackedVector2Array &p_candidates,
			double p_min_spacing, int p_max_selected = MAX_SELECTED) const;
};
