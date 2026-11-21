/**************************************************************************/
/*  pcg_density_selector.cpp                                               */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#include "pcg_density_selector.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void PCGDensitySelector::_bind_methods() {
	ClassDB::bind_method(D_METHOD("remap_densities", "densities", "input_min", "input_max",
					"output_min", "output_max", "clamp_input"),
			&PCGDensitySelector::remap_densities,
			DEFVAL(0.0), DEFVAL(1.0), DEFVAL(0.0), DEFVAL(1.0), DEFVAL(true));
	ClassDB::bind_method(D_METHOD("select_indices", "densities", "stable_ids", "seed", "max_selected"),
			&PCGDensitySelector::select_indices, DEFVAL(0), DEFVAL(4096));
}

PackedFloat32Array PCGDensitySelector::remap_densities(const PackedFloat32Array &p_densities,
		double p_input_min, double p_input_max,
		double p_output_min, double p_output_max, bool p_clamp_input) const {
	PackedFloat32Array result;
	const int count = p_densities.size();
	if (count > MAX_POINTS ||
			!Math::is_finite(p_input_min) || !Math::is_finite(p_input_max) ||
			!Math::is_finite(p_output_min) || !Math::is_finite(p_output_max) ||
			p_input_min < 0.0 || p_input_max > 1.0 || p_input_min >= p_input_max ||
			p_output_min < 0.0 || p_output_min > 1.0 ||
			p_output_max < 0.0 || p_output_max > 1.0) {
		return result;
	}
	// Validate all points before producing any output.
	for (int i = 0; i < count; ++i) {
		const float d = p_densities[i];
		if (!Math::is_finite(d) || d < 0.0f || d > 1.0f) {
			return result;
		}
	}
	result.resize(count);
	const double scale = (p_output_max - p_output_min) / (p_input_max - p_input_min);
	for (int i = 0; i < count; ++i) {
		const double input = p_clamp_input ?
				CLAMP(double(p_densities[i]), p_input_min, p_input_max) : double(p_densities[i]);
		const double mapped = p_output_min + (input - p_input_min) * scale;
		result.set(i, float(CLAMP(mapped, 0.0, 1.0)));
	}
	return result;
}

PackedInt32Array PCGDensitySelector::select_indices(const PackedFloat32Array &p_densities,
		const PackedInt64Array &p_stable_ids, int p_seed, int p_max_selected) const {
	PackedInt32Array selected;
	const int count = p_densities.size();
	if (count != p_stable_ids.size() || count > MAX_POINTS ||
			p_seed < 0 || p_max_selected < 1 || p_max_selected > MAX_SELECTED) {
		return selected;
	}
	// All-or-nothing validation. Invalid tail values must never cause a
	// partially accepted list that changes the contents of the scene.
	for (int i = 0; i < count; ++i) {
		const float d = p_densities[i];
		const int64_t id = p_stable_ids[i];
		if (!Math::is_finite(d) || d < 0.0f || d > 1.0f ||
				id < 0 || id > MAX_STABLE_ID) {
			return selected;
		}
	}

	for (int i = 0; i < count; ++i) {
		const float density = p_densities[i];
		if (density == 0.0f) {
			continue;
		}
		// Exact unsigned 32-bit avalanche mixer; nearby small grid IDs
		// must not yield nearly identical probabilities. No shared RNG.
		uint32_t hash = uint32_t(p_stable_ids[i]) ^ uint32_t(p_seed) ^ 0x9E3779B9u;
		hash = (hash ^ (hash >> 16)) * 0x045d9f3bu;
		hash = (hash ^ (hash >> 16)) * 0x045d9f3bu;
		hash ^= hash >> 16;
		if (density == 1.0f || double(hash) < double(density) * 4294967296.0) {
			selected.push_back(i);
			if (selected.size() == p_max_selected) {
				break;
			}
		}
	}
	return selected;
}
