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
	const PackedInt32Array one = { 0 };
	CHECK(budget->spread_indices(1) == one);
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
	const PackedInt32Array performance = { 42, 31, 20, 0, 1 };
	CHECK(budget->plan_visible_counts(counts, distances, 0) == performance);
	const PackedInt32Array balanced = { 68, 55, 42, 0, 1 };
	CHECK(budget->plan_visible_counts(counts, distances, 1) == balanced);
	const PackedInt32Array high = { 88, 79, 70, 0, 1 };
	CHECK(budget->plan_visible_counts(counts, distances, 2) == high);
	CHECK(budget->plan_visible_counts(counts, distances, 3) == counts);
	CHECK(budget->plan_visible_counts(counts, distances, 1) ==
			budget->plan_visible_counts(counts, distances, 1));
	const PackedInt32Array near_and_far = { 42, 20 };
	CHECK(budget->plan_visible_counts({ 100, 100 }, { 0, 1000 }, 0) == near_and_far);
	CHECK(budget->plan_visible_counts({ 100, 100 }, { 10, 30 }, 0, 10, 30) == near_and_far);
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

TEST_CASE("[PCGFoliageScalability3D] temporal count deadband prevents tiny density oscillation") {
	Ref<PCGFoliageScalability3D> planner;
	planner.instantiate();
	const PackedInt32Array counts = { 100, 100, 0, 10 };
	const PackedFloat32Array distances = { 18, 30, 50, 18 };
	const PackedInt32Array history = { 68, 68, 0, -1 };
	const PackedInt32Array expected = { 68, 68, 0, 7 };
	CHECK(planner->plan_visible_counts_stable(counts, distances, history, 1) == expected);
	// Suppressed one-count changes are released once the actual requested
	// count differs by more than the two-instance threshold.
	CHECK(planner->plan_visible_counts_stable({ 100 }, { 125 }, { 68 }, 1)[0] == 42);
	CHECK(planner->plan_visible_counts_stable({ 100 }, { 125 }, { 42 }, 1)[0] == 42);
	CHECK(planner->plan_visible_counts_stable({ 100 }, { 30 }, { -1 }, 1)[0] == 67);
	CHECK(planner->plan_visible_counts_stable({ 100 }, { 30 }, { 68 }, 1, 0)[0] == 67);
	// Tier switch with -1 bypasses the deadband and restores full Ultra.
	CHECK(planner->plan_visible_counts_stable({ 10 }, { 125 }, { -1 }, 3)[0] == 10);
	CHECK(planner->plan_visible_counts_stable({ 10 }, { 125 }, { -1 }, 0)[0] == 2);
	// Nonempty foliage cannot stick at a previously hidden 0 count.
	CHECK(planner->plan_visible_counts_stable({ 1 }, { 18 }, { 0 }, 0)[0] == 1);
	CHECK(planner->plan_visible_counts_stable({ 0 }, { 18 }, { 0 }, 0)[0] == 0);
}

TEST_CASE("[PCGFoliageScalability3D] stable planner validates all prior rows atomically") {
	Ref<PCGFoliageScalability3D> planner;
	planner.instantiate();
	CHECK(planner->plan_visible_counts_stable({ 10, 20 }, { 18, 19 }, { -1 }, 1).is_empty());
	CHECK(planner->plan_visible_counts_stable({ 10, 20 }, { 18 }, { -1, -1 }, 1).is_empty());
	CHECK(planner->plan_visible_counts_stable({ 10, 20 }, { 18, 19 }, { -1, 21 }, 1).is_empty());
	CHECK(planner->plan_visible_counts_stable({ 10, 20 }, { 18, 19 }, { -1, -2 }, 1).is_empty());
	CHECK(planner->plan_visible_counts_stable({ 10 }, { 18 }, { -1 }, 1, -1).is_empty());
	CHECK(planner->plan_visible_counts_stable({ 10 }, { 18 }, { -1 }, 1, 9).is_empty());
	CHECK(planner->plan_visible_counts_stable({ 10 }, { Math::NaN }, { -1 }, 1).is_empty());
	CHECK(planner->plan_visible_counts_stable({ 10 }, { 18 }, { -1 }, 4).is_empty());
	CHECK(planner->plan_visible_counts_stable({ 10 }, { 18 }, { -1 }, 1, 2, 20, 20).is_empty());
	CHECK(planner->plan_visible_counts_stable({}, {}, {}, 1).is_empty());
	PackedInt32Array counts;
	PackedFloat32Array distances;
	PackedInt32Array history;
	for (int i = 0; i < 4096; ++i) {
		counts.push_back(100);
		distances.push_back(30.0f);
		history.push_back(68);
	}
	const PackedInt32Array planned = planner->plan_visible_counts_stable(counts, distances, history, 1);
	REQUIRE(planned.size() == 4096);
	CHECK(planned[0] == 68);
	CHECK(planned[4095] == 68);
	counts.push_back(100);
	distances.push_back(30.0f);
	history.push_back(68);
	CHECK(planner->plan_visible_counts_stable(counts, distances, history, 1).is_empty());
}

} // namespace TestPCGFoliageScalability3D
