/**************************************************************************/
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#pragma once

#include "../weighted_choice_table.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestWeightedChoiceTable {

TEST_CASE("[WeightedChoiceTable] deterministic bucket boundaries and zero weights") {
	Ref<WeightedChoiceTable> table;
	table.instantiate();
	CHECK_FALSE(table->is_configured());
	CHECK(table->sample_unit(0.0) == -1);

	PackedFloat64Array values;
	values.push_back(24.0);
	values.push_back(20.0);
	values.push_back(16.0);
	values.push_back(16.0);
	values.push_back(10.0);
	values.push_back(9.0);
	values.push_back(5.0);
	CHECK(table->configure(values));
	CHECK(table->get_option_count() == 7);
	CHECK(table->get_total_weight() == 100.0);
	CHECK(table->sample_unit(0.0) == 0);
	CHECK(table->sample_unit(0.23999) == 0);
	CHECK(table->sample_unit(0.24) == 1);
	CHECK(table->sample_unit(0.44) == 2);
	CHECK(table->sample_unit(0.60) == 3);
	CHECK(table->sample_unit(0.76) == 4);
	CHECK(table->sample_unit(0.86) == 5);
	CHECK(table->sample_unit(0.95) == 6);
	CHECK(table->sample_unit(0.999999999) == 6);
	CHECK(Math::is_equal_approx(table->get_probability(0), 0.24));
	CHECK(table->get_probability(-1) == 0.0);
	CHECK(table->get_probability(7) == 0.0);

	values.clear();
	values.push_back(0.0);
	values.push_back(3.0);
	values.push_back(0.0);
	values.push_back(2.0);
	CHECK(table->configure(values));
	CHECK(table->sample_unit(0.0) == 1);
	CHECK(table->sample_unit(0.59) == 1);
	CHECK(table->sample_unit(0.6) == 3);
	CHECK(table->sample_unit(0.9999999) == 3);

	PackedFloat64Array snapshot = table->get_weights();
	snapshot.set(1, 1000.0);
	CHECK(table->get_weights()[1] == 3.0);
}

TEST_CASE("[WeightedChoiceTable] atomic validation, bounded draw and deterministic batches") {
	Ref<WeightedChoiceTable> table;
	table.instantiate();
	PackedFloat64Array good;
	good.push_back(1.0);
	good.push_back(4.0);
	CHECK(table->configure(good));

	PackedFloat64Array invalid;
	CHECK_FALSE(table->configure(invalid));
	invalid.push_back(0.0);
	CHECK_FALSE(table->configure(invalid));
	invalid.push_back(-1.0);
	CHECK_FALSE(table->configure(invalid));
	invalid.set(1, Math::INF);
	CHECK_FALSE(table->configure(invalid));
	invalid.set(1, Math::NaN);
	CHECK_FALSE(table->configure(invalid));
	invalid.set(1, 1000000000001.0);
	CHECK_FALSE(table->configure(invalid));
	CHECK(table->get_weights() == good);
	CHECK(table->sample_unit(0.0) == 0);
	CHECK(table->sample_unit(0.2) == 1);
	CHECK(table->sample_unit(-0.001) == -1);
	CHECK(table->sample_unit(1.0) == -1);
	CHECK(table->sample_unit(Math::INF) == -1);
	CHECK(table->sample_unit(Math::NaN) == -1);

	PackedFloat64Array units;
	units.push_back(0.0);
	units.push_back(0.1999);
	units.push_back(0.2);
	units.push_back(0.99);
	PackedInt32Array choices = table->sample_many(units);
	REQUIRE(choices.size() == 4);
	CHECK(choices[0] == 0);
	CHECK(choices[1] == 0);
	CHECK(choices[2] == 1);
	CHECK(choices[3] == 1);
	units.push_back(-0.1);
	CHECK(table->sample_many(units).is_empty()); // Atomic reject.
	units.resize(65537);
	CHECK(table->sample_many(units).is_empty()); // Bound memory.

	PackedFloat64Array max_size;
	max_size.resize(4097);
	max_size.set(0, 1.0);
	CHECK_FALSE(table->configure(max_size));
	CHECK(table->get_option_count() == 2); // Previous table is still alive.
}

TEST_CASE("[WeightedChoiceTable] weighted selection without replacement") {
	Ref<WeightedChoiceTable> table;
	table.instantiate();
	PackedFloat64Array weights;
	weights.push_back(0.0);
	weights.push_back(2.0);
	weights.push_back(3.0);
	weights.push_back(5.0);
	REQUIRE(table->configure(weights));
	PackedInt32Array excluded;
	CHECK(table->sample_excluding(0.0, excluded) == table->sample_unit(0.0));
	CHECK(table->sample_excluding(0.5, excluded) == table->sample_unit(0.5));
	excluded.push_back(1); // Remaining weights: 3 at index 2, 5 at 3.
	CHECK(table->sample_excluding(0.0, excluded) == 2);
	CHECK(table->sample_excluding(0.3749, excluded) == 2);
	CHECK(table->sample_excluding(0.375, excluded) == 3);
	excluded.push_back(3);
	CHECK(table->sample_excluding(0.999999, excluded) == 2);
	excluded.push_back(3); // Repeated exclusions are harmless.
	CHECK(table->sample_excluding(0.0, excluded) == 2);
	excluded.push_back(2); // No positive weights remain.
	CHECK(table->sample_excluding(0.0, excluded) == -1);
	excluded.clear();
	excluded.push_back(4);
	CHECK(table->sample_excluding(0.4, excluded) == -1);
	excluded.set(0, -1);
	CHECK(table->sample_excluding(0.4, excluded) == -1);
	excluded.clear();
	CHECK(table->sample_excluding(-0.01, excluded) == -1);
	CHECK(table->sample_excluding(1.0, excluded) == -1);
	CHECK(table->sample_excluding(Math::NaN, excluded) == -1);
	CHECK(table->sample_excluding(Math::INF, excluded) == -1);
	CHECK(table->get_weights() == weights); // No mutation of configuration.
	// Highest possible valid index exercises the last 64-bit mask word.
	PackedFloat64Array large;
	large.resize(4096);
	large.set(0, 1.0);
	large.set(4095, 1.0);
	REQUIRE(table->configure(large));
	excluded.push_back(4095);
	CHECK(table->sample_excluding(0.999, excluded) == 0);
	excluded.push_back(0);
	CHECK(table->sample_excluding(0.0, excluded) == -1);
	CHECK(table->get_weights() == large);
}

} // namespace TestWeightedChoiceTable
