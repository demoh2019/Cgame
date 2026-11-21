/**************************************************************************/
/*  weighted_choice_table.h                                                */
/**************************************************************************/
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#pragma once

#include "core/io/resource.h"
#include "core/templates/vector.h"
#include "core/variant/variant.h"

// Reusable, immutable-between-configurations discrete sampling table.
// Selection uses one externally provided [0, 1) uniform draw and never
// mutates global or per-agent RNG state. Safe for deterministic game replay.
class WeightedChoiceTable : public Resource {
	GDCLASS(WeightedChoiceTable, Resource);

	static constexpr int MAX_OPTIONS = 4096;
	static constexpr int MAX_BATCH = 65536;
	static constexpr double MAX_TOTAL_WEIGHT = 1000000000000.0;

	PackedFloat64Array weights;
	Vector<double> cumulative;
	double total_weight = 0.0;

protected:
	static void _bind_methods();

public:
	// All-or-nothing validation. Negative, nonfinite, zero-total, oversized
	// and overflowing input leaves the previous distribution intact.
	bool configure(const PackedFloat64Array &p_weights);
	void set_weights(const PackedFloat64Array &p_weights) { configure(p_weights); }
	PackedFloat64Array get_weights() const { return weights; }

	// Selects the first positive cumulative weight strictly above unit*total.
	// Returns -1 for missing table or any nonfinite/out-of-range draw.
	int sample_unit(double p_unit) const;
	// Valid inputs return one index per draw. A malformed batch is rejected
	// without partial results (empty array); no random draws are consumed.
	PackedInt32Array sample_many(const PackedFloat64Array &p_units) const;

	int get_option_count() const { return weights.size(); }
	double get_total_weight() const { return total_weight; }
	double get_probability(int p_index) const;
	bool is_configured() const { return total_weight > 0.0; }
};
