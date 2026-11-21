/**************************************************************************/
/*  test_adaptive_prefetch_policy.h                                         */
/*                         This file is part of: GODOT ENGINE              */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "../feedback_buffer_policy.h"
#include "tests/test_macros.h"

namespace TestAdaptiveTexturePrefetch {

using TextureStreamingFeedbackPolicy::adaptive_prefetch_mips;

TEST_CASE("[TextureStreaming] disabled and unconstrained adaptive prefetch") {
	constexpr uint64_t MB = 1024ull * 1024ull;
	CHECK(adaptive_prefetch_mips(2, 0, 499 * MB, 500 * MB, false) == 2);
	CHECK(adaptive_prefetch_mips(2, 0, 499 * MB, 0, true) == 2);
	CHECK(adaptive_prefetch_mips(1, 2, 0, 100 * MB, true) == 1);
	CHECK(adaptive_prefetch_mips(0, 2, 0, 100 * MB, true) == 0);
	CHECK(adaptive_prefetch_mips(255, 0, 0, 100 * MB, false) == 2);
	CHECK(adaptive_prefetch_mips(2, 0, 0, 100 * MB, true) == 2);
}

TEST_CASE("[TextureStreaming] VRAM pressure suppresses only speculative mip prefetch") {
	constexpr uint64_t MB = 1024ull * 1024ull;
	// 100 MiB pool: 95% hard stop, 85% one speculative mip maximum.
	CHECK(adaptive_prefetch_mips(2, 2, 94 * MB, 100 * MB, true) == 1);
	CHECK(adaptive_prefetch_mips(2, 2, 95 * MB, 100 * MB, true) == 0);
	CHECK(adaptive_prefetch_mips(2, 1, 86 * MB, 100 * MB, true) == 1);
	CHECK(adaptive_prefetch_mips(2, 0, 90 * MB, 100 * MB, true) == 0);
	CHECK(adaptive_prefetch_mips(2, 2, 84 * MB, 100 * MB, true) == 2);
	CHECK(adaptive_prefetch_mips(2, 0, 84 * MB, 100 * MB, true) == 0);
	CHECK(adaptive_prefetch_mips(2, 0, 78 * MB, 100 * MB, true) == 1);
	CHECK(adaptive_prefetch_mips(2, 0, 70 * MB, 100 * MB, true) == 2);
	CHECK(adaptive_prefetch_mips(1, 0, 78 * MB, 100 * MB, true) == 1);
	CHECK(adaptive_prefetch_mips(2, 0, 1000 * MB, 100 * MB, true) == 0);
}

TEST_CASE("[TextureStreaming] integer budget thresholds are overflow-safe") {
	constexpr uint64_t HUGE = UINT64_MAX;
	CHECK(adaptive_prefetch_mips(2, 2, HUGE, HUGE, true) == 0);
	CHECK(adaptive_prefetch_mips(2, 0, 0, HUGE, true) == 2);
	CHECK(adaptive_prefetch_mips(2, 0, HUGE / 2, HUGE, true) == 2);
	CHECK(adaptive_prefetch_mips(2, 1, 0, 1, true) == 2);
	CHECK(adaptive_prefetch_mips(2, 0, 1, 1, true) == 0);
}

} // namespace TestAdaptiveTexturePrefetch
