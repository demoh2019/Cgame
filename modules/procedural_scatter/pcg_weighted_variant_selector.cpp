/**************************************************************************/
/*  pcg_weighted_variant_selector.cpp                                      */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#include "pcg_weighted_variant_selector.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void PCGWeightedVariantSelector::_bind_methods() {
	ClassDB::bind_method(D_METHOD("choose_variants", "stable_ids", "weights", "seed"),
			&PCGWeightedVariantSelector::choose_variants, DEFVAL(0));
}

PackedInt32Array PCGWeightedVariantSelector::choose_variants(
		const PackedInt64Array &p_stable_ids, const PackedFloat32Array &p_weights,
		int p_seed) const {
	PackedInt32Array result;
	const int count = p_stable_ids.size();
	const int variants = p_weights.size();
	if (count > MAX_POINTS || variants < 1 || variants > MAX_VARIANTS ||
			p_seed < 0 || int64_t(p_seed) > MAX_STABLE_ID) {
		return result;
	}
	double total_weight = 0.0;
	int last_positive = -1;
	for (int j = 0; j < variants; ++j) {
		const float weight = p_weights[j];
		if (!Math::is_finite(weight) || weight < 0.0f || weight > 1000000.0f) {
			return result;
		}
		total_weight += double(weight);
		if (weight > 0.0f) {
			last_positive = j;
		}
	}
	if (last_positive < 0) {
		return result;
	}
	// A bad tail ID must not produce partially chosen variants.
	for (int i = 0; i < count; ++i) {
		if (p_stable_ids[i] < 0 || p_stable_ids[i] > MAX_STABLE_ID) {
			return result;
		}
	}
	result.resize(count);
	for (int i = 0; i < count; ++i) {
		// 32-bit avalanche hash. Every point is independent of traversal order
		// and no shared Godot RNG state is advanced.
		uint32_t hash = uint32_t(p_stable_ids[i]) ^ uint32_t(p_seed) ^ 0x9e3779b9u;
		hash = (hash ^ (hash >> 16)) * 0x045d9f3bu;
		hash = (hash ^ (hash >> 16)) * 0x045d9f3bu;
		hash ^= hash >> 16;
		const double draw = (double(hash) + 0.5) * (total_weight / 4294967296.0);
		double cumulative = 0.0;
		int selected = last_positive;
		for (int j = 0; j < variants; ++j) {
			cumulative += double(p_weights[j]);
			if (draw < cumulative) {
				selected = j;
				break;
			}
		}
		result.set(i, selected);
	}
	return result;
}
