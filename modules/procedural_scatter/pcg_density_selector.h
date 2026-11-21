/**************************************************************************/
/*  pcg_density_selector.h                                                 */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

/**
 * Bounded and deterministic Unreal PCG-inspired density remap/filter.
 *
 * Pure CPU operations: no random generator, material/scene mutation or I/O.
 * Stable point IDs make decisions independent of candidate order, until the
 * optional output budget is reached (then first accepted points win).
 */
class PCGDensitySelector : public RefCounted {
	GDCLASS(PCGDensitySelector, RefCounted);

protected:
	static void _bind_methods();

public:
	static constexpr int MAX_POINTS = 16384;
	static constexpr int MAX_SELECTED = 4096;
	static constexpr int MAX_STABLE_ID = 2147483647;

	PackedFloat32Array remap_densities(const PackedFloat32Array &p_densities,
			double p_input_min = 0.0, double p_input_max = 1.0,
			double p_output_min = 0.0, double p_output_max = 1.0,
			bool p_clamp_input = true) const;

	PackedInt32Array select_indices(const PackedFloat32Array &p_densities,
			const PackedInt64Array &p_stable_ids,
			int p_seed = 0, int p_max_selected = 4096) const;
};
