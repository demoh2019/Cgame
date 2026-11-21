/**************************************************************************/
/*  test_pcg_foliage_scalability_3d.h                                       */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "../pcg_foliage_scalability_3d.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestPCGFoliageScalability3D {

TEST_CASE("[PCGFoliageScalability3D] stable bit-reversed distributed prefixes") {
	Ref<PCGFoliageScalability3D> budget;
	budget.instantiate();
	const PackedInt32Array expected = { 0, 8, 4, 2, 6, 1, 9, 5, 3, 7 };
	CHECK(budget->spread_indices(10) == expected);
	CHECK(budget->spread_indices(10) == expected); // Idempotent; no RNG.
	CHECK(budget->spread_indices(0).is_empty());
	CHECK(budget->spread_indices(1) == PackedInt32Array({ 0 }));
	CHECK(budget->spread_indices(-1).is_empty());
	CHECK(budget->spread_indices(65537).is_empty());
	const PackedInt32Array max_order = budget->spread_indices(65536);
	REQUIRE(max_order.size() == 65536);
	CHECK(max_order[0] == 0);
	CHECK(max_order[1] == 32768);
	CHECK(max_order[2] == 16384);
	CHECK(max_order[65535] == 65535);
	// Every original index occurs once, including non-power-of-two sizes.
	bool seen[10] = {};
	for (int i = 0; i < expected.size(); ++i) {
		const int source = expected[i];
		REQUIRE(source >= 0);
		REQUIRE(source < 10);
		CHECK(!seen[source]);
		seen[source] = true;
	}
}

TEST_CASE("[PCGFoliageScalability3D] reversible density tiers and smooth distance") {
	Ref<PCGFoliageScalability3D> budget;
	budget.instantiate();
	const PackedInt32Array counts = { 100, 100, 100, 0, 1 };
	const PackedFloat32Array distances = { 18, 71.5f, 125, 70, 125 };
	CHECK(budget->plan_visible_counts(counts, distances, 0) ==
			PackedInt32Array({ 42, 31, 20, 0, 1 }));
	CHECK(budget->plan_visible_counts(counts, distances, 1) ==
			PackedInt32Array({ 68, 55, 42, 0, 1 }));
	CHECK(budget->plan_visible_counts(counts, distances, 2) ==
			PackedInt32Array({ 88, 79, 70, 0, 1 }));
	CHECK(budget->plan_visible_counts(counts, distances, 3) == counts);
	CHECK(budget->plan_visible_counts(counts, distances, 1) ==
			budget->plan_visible_counts(counts, distances, 1));
	CHECK(budget->plan_visible_counts({ 100, 100 }, { 0, 1000 }, 0) ==
			PackedInt32Array({ 42, 20 }));
	CHECK(budget->plan_visible_counts({ 100, 100 }, { 10, 30 }, 0, 10, 30) ==
			PackedInt32Array({ 42, 20 }));
}

TEST_CASE("[PCGFoliageScalability3D] atomic validation and bounded cluster counts") {
	Ref<PCGFoliageScalability3D> budget;
	budget.instantiate();
	CHECK(budget->plan_visible_counts({ 1, 1 }, { 1 }, 0).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { 1 }, -1).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { 1 }, 4).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { Math::NaN }, 1).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { Math::INF }, 1).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { -1 }, 1).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { 10000001 }, 1).is_empty());
	CHECK(budget->plan_visible_counts({ -1 }, { 1 }, 1).is_empty());
	CHECK(budget->plan_visible_counts({ 65537 }, { 1 }, 1).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { 1 }, 1, -1, 125).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { 1 }, 1, 125, 125).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { 1 }, 1, 20, 10).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { 1 }, 1, Math::NaN, 125).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { 1 }, 1, 18, Math::INF).is_empty());
	CHECK(budget->plan_visible_counts({ 1 }, { 1 }, 1, 18, 1000001).is_empty());
	CHECK(budget->plan_visible_counts({ 100, 20, -1 }, { 10, 20, 30 }, 0).is_empty());
	CHECK(budget->plan_visible_counts({}, {}, 0).is_empty());
	PackedInt32Array many_counts;
	PackedFloat32Array many_distances;
	for (int i = 0; i < 4097; ++i) {
		many_counts.push_back(10);
		many_distances.push_back(100.0f);
	}
	CHECK(budget->plan_visible_counts(many_counts, many_distances, 1).is_empty());
	many_counts.resize(4096);
	many_distances.resize(4096);
	const PackedInt32Array planned = budget->plan_visible_counts(many_counts, many_distances, 1);
	REQUIRE(planned.size() == 4096);
	CHECK(planned[0] >= 1);
	CHECK(planned[4095] >= 1);
}

} // namespace TestPCGFoliageScalability3D
