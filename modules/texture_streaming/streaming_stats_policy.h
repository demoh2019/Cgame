/**************************************************************************/
/*  streaming_stats_policy.h                                              */
/*  Pure helpers for cheap Unreal STAT STREAMING-style mip telemetry.     */
/*  SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

#include <cstdint>

namespace TextureStreamingStatsPolicy {

// 255 is TextureStreaming's uninitialized mip sentinel, not a valid target.
constexpr bool needs_reload(uint8_t p_resident_mip, uint8_t p_target_mip) {
	return p_target_mip != UINT8_MAX && p_resident_mip != p_target_mip;
}

// Mip index increases when the budget fitter sacrifices detail. This counts
// precisely the number of quality reductions, never increases or unchanged
// states, and cannot underflow for a malformed input.
constexpr uint32_t budget_reduction_steps(uint8_t p_before, uint8_t p_after) {
	return (p_before != UINT8_MAX && p_after != UINT8_MAX && p_after > p_before) ?
			uint32_t(p_after - p_before) : 0u;
}

} // namespace TextureStreamingStatsPolicy
