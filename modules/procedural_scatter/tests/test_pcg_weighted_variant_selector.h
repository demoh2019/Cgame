/**************************************************************************/
/*  test_pcg_weighted_variant_selector.h                                   */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

#include "../pcg_weighted_variant_selector.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestPCGWeightedVariantSelector {

TEST_CASE("[PCGWeightedVariantSelector] stable weighted indices and seeded repeatability") {
	Ref<PCGWeightedVariantSelector> selector;
	selector.instantiate();
	const PackedInt64Array ids = { 1, 200, 3, 56, 4, 800, 50, 27 };
	const PackedFloat32Array weights = { 6.0f, 3.0f, 1.0f };
	const PackedInt32Array first = selector->choose_variants(ids, weights, 27419);
	REQUIRE(first.size() == ids.size());
	CHECK(selector->choose_variants(ids, weights, 27419) == first);
	for (int i = 0; i < first.size(); ++i) {
		CHECK(first[i] >= 0);
		CHECK(first[i] < 3);
	}
	const PackedInt64Array permuted = { 50, 4, 800, 3, 200, 1, 27, 56, 1 };
	const PackedInt32Array other = selector->choose_variants(permuted, weights, 27419);
	REQUIRE(other.size() == permuted.size());
	for (int i = 0; i < other.size(); ++i) {
		bool found = false;
		for (int j = 0; j < ids.size(); ++j) {
			if (permuted[i] == ids[j]) {
				CHECK(other[i] == first[j]);
				found = true;
				break;
			}
		}
		CHECK(found);
	}
	const PackedFloat32Array forced = { 0.0f, 50.0f, 0.0f };
	const PackedInt32Array all_middle = selector->choose_variants(ids, forced, 1);
	REQUIRE(all_middle.size() == ids.size());
	for (int idx : all_middle) {
		CHECK(idx == 1);
	}
}

TEST_CASE("[PCGWeightedVariantSelector] weight proportions and zero-weight variants") {
	Ref<PCGWeightedVariantSelector> selector;
	selector.instantiate();
	PackedInt64Array ids;
	for (int i = 0; i < 4096; ++i) {
		ids.push_back(i);
	}
	const PackedInt32Array a = selector->choose_variants(ids, { 6.0f, 3.0f, 1.0f }, 2711);
	REQUIRE(a.size() == 4096);
	int counts[3] = { 0, 0, 0 };
	for (int idx : a) {
		REQUIRE(idx >= 0);
		REQUIRE(idx < 3);
		counts[idx]++;
	}
	CHECK(counts[0] > 2100);
	CHECK(counts[0] < 2850);
	CHECK(counts[1] > 850);
	CHECK(counts[1] < 1650);
	CHECK(counts[2] > 200);
	CHECK(counts[2] < 700);
	CHECK(selector->choose_variants(ids, { 0.0f, 0.0f, 1.0f }, 11).size() == 4096);
}

TEST_CASE("[PCGWeightedVariantSelector] invalid input rejected without partial output") {
	Ref<PCGWeightedVariantSelector> selector;
	selector.instantiate();
	CHECK(selector->choose_variants({ 4, -1 }, { 1.0f, 2.0f }).is_empty());
	CHECK(selector->choose_variants({ 4, 2147483648ll }, { 1.0f }).is_empty());
	CHECK(selector->choose_variants({ 4, 5 }, { 1.0f, static_cast<float>(Math::NaN) }).is_empty());
	CHECK(selector->choose_variants({ 4, 5 }, { 1.0f, static_cast<float>(Math::INF) }).is_empty());
	CHECK(selector->choose_variants({ 4, 5 }, { 1.0f, -1.0f }).is_empty());
	CHECK(selector->choose_variants({ 4, 5 }, { 0.0f, 0.0f }).is_empty());
	CHECK(selector->choose_variants({ 4, 5 }, { 1000001.0f }).is_empty());
	CHECK(selector->choose_variants({ 4, 5 }, { 1.0f }, -1).is_empty());
	CHECK(selector->choose_variants({ 4, 5 }, {}).is_empty());
	PackedFloat32Array too_many_weights;
	too_many_weights.resize(33);
	too_many_weights.set(0, 1.0f);
	CHECK(selector->choose_variants({ 4, 5 }, too_many_weights).is_empty());
	PackedInt64Array too_many_ids;
	too_many_ids.resize(16385);
	CHECK(selector->choose_variants(too_many_ids, { 1.0f }).is_empty());
	CHECK(selector->choose_variants({}, { 1.0f }).is_empty()); // Valid empty input.
}

TEST_CASE("[PCGWeightedVariantSelector] variant partition preserves every source index exactly once") {
	Ref<PCGWeightedVariantSelector> selector;
	selector.instantiate();
	const PackedInt32Array chosen = { 2, 0, 1, 2, 0, 2, 1, 2 };
	const PackedInt32Array input_copy = chosen;
	const Array batches = selector->partition_indices(chosen, 4);
	REQUIRE(batches.size() == 4);
	const PackedInt32Array b0 = batches[0];
	const PackedInt32Array b1 = batches[1];
	const PackedInt32Array b2 = batches[2];
	const PackedInt32Array b3 = batches[3];

	const PackedInt32Array expected0 = { 1, 4 };
	const PackedInt32Array expected1 = { 2, 6 };
	const PackedInt32Array expected2 = { 0, 3, 5, 7 };
	CHECK(b0 == expected0);
	CHECK(b1 == expected1);
	CHECK(b2 == expected2);
	CHECK(b3.is_empty()); // An unused mesh variant is an empty valid batch.
	CHECK(chosen == input_copy);
	CHECK(selector->partition_indices(chosen, 4) == batches);
	int visits[8] = { 0 };
	for (int variant = 0; variant < batches.size(); ++variant) {
		const PackedInt32Array indices = batches[variant];
		for (int index : indices) {
			REQUIRE(index >= 0);
			REQUIRE(index < 8);
			CHECK(chosen[index] == variant);
			visits[index]++;
		}
	}
	for (int visit : visits) {
		CHECK(visit == 1);
	}
}

TEST_CASE("[PCGWeightedVariantSelector] empty and fully occupied mesh variants") {
	Ref<PCGWeightedVariantSelector> selector;
	selector.instantiate();
	const Array empty_groups = selector->partition_indices(PackedInt32Array(), 3);
	REQUIRE(empty_groups.size() == 3);
	for (int i = 0; i < 3; ++i) {
		const PackedInt32Array empty = empty_groups[i];
		CHECK(empty.is_empty());
	}
	const PackedInt32Array all_single = { 0, 0, 0, 0 };
	const Array one_batch = selector->partition_indices(all_single, 1);
	REQUIRE(one_batch.size() == 1);

	const PackedInt32Array all_indices = one_batch[0];
	const PackedInt32Array expected = { 0, 1, 2, 3 };
	CHECK(all_indices == expected);
	const PackedInt32Array three = { 0, 1, 2 };
	CHECK(selector->partition_indices(three, 3).size() == 3);
	CHECK(selector->partition_indices(three, 32).size() == 32);
}

TEST_CASE("[PCGWeightedVariantSelector] invalid mesh attributes reject the full batch") {
	Ref<PCGWeightedVariantSelector> selector;
	selector.instantiate();
	CHECK(selector->partition_indices({ 0, 1, 2, 3 }, 3).is_empty());
	CHECK(selector->partition_indices({ 0, -1 }, 3).is_empty());
	CHECK(selector->partition_indices({ 0, 0, 99 }, 3).is_empty());
	CHECK(selector->partition_indices({ 0, 1 }, 0).is_empty());
	CHECK(selector->partition_indices({ 0, 1 }, 33).is_empty());
	PackedInt32Array many;
	many.resize(16385);
	CHECK(selector->partition_indices(many, 2).is_empty());
	many.resize(16384);
	const Array max_groups = selector->partition_indices(many, 2);
	REQUIRE(max_groups.size() == 2);

	const PackedInt32Array full = max_groups[0];
	const PackedInt32Array empty = max_groups[1];
	CHECK(full.size() == 16384);
	CHECK(empty.is_empty());
}

} // namespace TestPCGWeightedVariantSelector
