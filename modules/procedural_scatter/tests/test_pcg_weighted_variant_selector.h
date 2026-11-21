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
	CHECK(selector->choose_variants({ 4, 5 }, { 1.0f, Math::NaN }).is_empty());
	CHECK(selector->choose_variants({ 4, 5 }, { 1.0f, Math::INF }).is_empty());
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

} // namespace TestPCGWeightedVariantSelector
