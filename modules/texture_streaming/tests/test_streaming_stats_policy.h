/**************************************************************************/
/*  test_streaming_stats_policy.h                                         */
/*  This file is part of: GODOT ENGINE                                    */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

#include "../streaming_stats_policy.h"
#include "tests/test_macros.h"

namespace TestStreamingStatsPolicy {

using TextureStreamingStatsPolicy::needs_reload;
using TextureStreamingStatsPolicy::budget_reduction_steps;

TEST_CASE("[TextureStreaming] wanted versus resident mip backlog semantics") {
	CHECK_FALSE(needs_reload(0, 0));
	CHECK_FALSE(needs_reload(13, 13));
	CHECK(needs_reload(9, 3)); // High-resolution mips not yet present.
	CHECK(needs_reload(2, 5)); // Budget eviction still waiting on coarser mip.
	CHECK(needs_reload(255, 8)); // Uninitialized texture is missing its target.
	CHECK_FALSE(needs_reload(255, 255)); // No valid fitted target.
	CHECK_FALSE(needs_reload(0, 255)); // Missing target cannot create bogus I/O work.
	for (uint8_t target = 0; target <= 13; ++target) {
		for (uint8_t current = 0; current <= 13; ++current) {
			CHECK(needs_reload(current, target) == (current != target));
		}
	}
}

TEST_CASE("[TextureStreaming] reduction steps only count budget-driven loss of mip detail") {
	CHECK(budget_reduction_steps(0, 0) == 0);
	CHECK(budget_reduction_steps(3, 4) == 1);
	CHECK(budget_reduction_steps(0, 13) == 13);
	CHECK(budget_reduction_steps(8, 3) == 0); // Detail recovery is not a cut.
	CHECK(budget_reduction_steps(255, 3) == 0);
	CHECK(budget_reduction_steps(3, 255) == 0);
	CHECK(budget_reduction_steps(255, 255) == 0);
	for (uint8_t before = 0; before <= 13; ++before) {
		for (uint8_t after = 0; after <= 13; ++after) {
			CHECK(budget_reduction_steps(before, after) ==
					(after > before ? uint32_t(after - before) : 0u));
		}
	}
}

} // namespace TestStreamingStatsPolicy
