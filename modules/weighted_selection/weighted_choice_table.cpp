/**************************************************************************/
/*  weighted_choice_table.cpp                                              */
/**************************************************************************/
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#include "weighted_choice_table.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

bool WeightedChoiceTable::configure(const PackedFloat64Array &p_weights) {
	if (p_weights.is_empty() || p_weights.size() > MAX_OPTIONS) {
		return false;
	}

	Vector<double> next_cumulative;
	next_cumulative.resize(p_weights.size());
	double sum = 0.0;
	for (int i = 0; i < p_weights.size(); ++i) {
		const double weight = p_weights[i];
		if (!Math::is_finite(weight) || weight < 0.0 || weight > MAX_TOTAL_WEIGHT - sum) {
			return false;
		}
		sum += weight;
		next_cumulative.write[i] = sum;
	}
	if (sum <= 0.0) {
		return false;
	}

	// Avoid redundant Resource.changed emissions for repeated snapshots.
	if (weights == p_weights) {
		return true;
	}
	weights = p_weights;
	cumulative = next_cumulative;
	total_weight = sum;
	emit_changed();
	return true;
}

int WeightedChoiceTable::sample_unit(double p_unit) const {
	if (!is_configured() || !Math::is_finite(p_unit) || p_unit < 0.0 || p_unit >= 1.0) {
		return -1;
	}

	const double target = p_unit * total_weight;
	// Binary upper_bound skips zero-weight entries even at exact boundaries.
	int lo = 0;
	int hi = cumulative.size();
	while (lo < hi) {
		const int mid = lo + (hi - lo) / 2;
		if (target < cumulative[mid]) {
			hi = mid;
		} else {
			lo = mid + 1;
		}
	}
	if (lo < cumulative.size()) {
		return lo;
	}
	// Multiplication near 1.0 may round to the total. Since p_unit < 1,
	// the final nonzero outcome remains the mathematically correct choice.
	for (int i = weights.size() - 1; i >= 0; --i) {
		if (weights[i] > 0.0) {
			return i;
		}
	}
	return -1;
}

PackedInt32Array WeightedChoiceTable::sample_many(const PackedFloat64Array &p_units) const {
	PackedInt32Array result;
	if (!is_configured() || p_units.size() > MAX_BATCH) {
		return result;
	}
	// Prevalidate so a bad draw cannot leave a partially accepted batch.
	for (int i = 0; i < p_units.size(); ++i) {
		if (!Math::is_finite(p_units[i]) || p_units[i] < 0.0 || p_units[i] >= 1.0) {
			return result;
		}
	}
	result.resize(p_units.size());
	for (int i = 0; i < p_units.size(); ++i) {
		result.set(i, sample_unit(p_units[i]));
	}
	return result;
}

int WeightedChoiceTable::sample_excluding(double p_unit, const PackedInt32Array &p_excluded) const {
	if (!is_configured() || !Math::is_finite(p_unit) || p_unit < 0.0 || p_unit >= 1.0) {
		return -1;
	}
	// Fixed 4096-bit stack mask: no per-playback heap allocation.
	// Validate exclusions before considering any candidate.
	uint64_t excluded_words[(MAX_OPTIONS + 63) / 64] = {};
	for (int i = 0; i < p_excluded.size(); ++i) {
		const int index = p_excluded[i];
		if (index < 0 || index >= weights.size()) {
			return -1;
		}
		excluded_words[index >> 6] |= uint64_t(1) << (index & 63);
	}
	double remaining = 0.0;
	for (int i = 0; i < weights.size(); ++i) {
		if ((excluded_words[i >> 6] & (uint64_t(1) << (i & 63))) == 0) {
			remaining += weights[i];
		}
	}
	if (remaining <= 0.0) {
		return -1;
	}
	const double target = p_unit * remaining;
	double sum = 0.0;
	int last_valid = -1;
	for (int i = 0; i < weights.size(); ++i) {
		if ((excluded_words[i >> 6] & (uint64_t(1) << (i & 63))) != 0 || weights[i] <= 0.0) {
			continue;
		}
		last_valid = i;
		sum += weights[i];
		if (target < sum) {
			return i;
		}
	}
	// Preserve the last positive bucket when multiplication rounds to total.
	return last_valid;
}

double WeightedChoiceTable::get_probability(int p_index) const {
	if (!is_configured() || p_index < 0 || p_index >= weights.size()) {
		return 0.0;
	}
	return weights[p_index] / total_weight;
}

void WeightedChoiceTable::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "weights"), &WeightedChoiceTable::configure);
	ClassDB::bind_method(D_METHOD("set_weights", "weights"), &WeightedChoiceTable::set_weights);
	ClassDB::bind_method(D_METHOD("get_weights"), &WeightedChoiceTable::get_weights);
	ClassDB::bind_method(D_METHOD("sample_unit", "unit"), &WeightedChoiceTable::sample_unit);
	ClassDB::bind_method(D_METHOD("sample_many", "units"), &WeightedChoiceTable::sample_many);
	ClassDB::bind_method(D_METHOD("sample_excluding", "unit", "excluded"), &WeightedChoiceTable::sample_excluding);
	ClassDB::bind_method(D_METHOD("get_option_count"), &WeightedChoiceTable::get_option_count);
	ClassDB::bind_method(D_METHOD("get_total_weight"), &WeightedChoiceTable::get_total_weight);
	ClassDB::bind_method(D_METHOD("get_probability", "index"), &WeightedChoiceTable::get_probability);
	ClassDB::bind_method(D_METHOD("is_configured"), &WeightedChoiceTable::is_configured);

	ADD_PROPERTY(PropertyInfo(Variant::PACKED_FLOAT64_ARRAY, "weights"), "set_weights", "get_weights");
}
