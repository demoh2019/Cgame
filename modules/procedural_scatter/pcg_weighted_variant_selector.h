/**************************************************************************/
/*  pcg_weighted_variant_selector.h                                        */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

// Deterministic Unreal-PCG-inspired weighted point attribute selection.
// Inputs: packed stable point IDs, shared positive finite weights and a seed.
// Output: one 0-based variant index per input point in original order.
class PCGWeightedVariantSelector : public RefCounted {
	GDCLASS(PCGWeightedVariantSelector, RefCounted);

protected:
	static void _bind_methods();

public:
	static constexpr int MAX_POINTS = 16384;
	static constexpr int MAX_VARIANTS = 32;
	static constexpr int64_t MAX_STABLE_ID = 2147483647;

	PackedInt32Array choose_variants(const PackedInt64Array &p_stable_ids,
			const PackedFloat32Array &p_weights, int p_seed = 0) const;

	// Partition the selected variant attributes into contiguous instancing
	// batches, retaining each source index exactly once. The result has
	// p_variant_count packed index arrays, including empty variants.
	// The operation is O(points + variants) and never mutates input.
	Array partition_indices(const PackedInt32Array &p_variants,
			int p_variant_count) const;
};
