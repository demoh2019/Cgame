/**************************************************************************/
/*  feedback_buffer_policy.h                                              */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#ifndef TEXTURE_STREAMING_FEEDBACK_BUFFER_POLICY_H
#define TEXTURE_STREAMING_FEEDBACK_BUFFER_POLICY_H

#include <cstdint>
#include <cstring>
#include <limits>

// Plain C++ policy: keeping it independent of the renderer lets us run
// deterministic boundary tests without allocating GPU resources.
namespace TextureStreamingFeedbackPolicy {
constexpr uint32_t MIN_BUFFER_SIZE_BYTES = 4096;
constexpr uint32_t MAX_MATERIAL_COUNT = 1u << 29;

// Cache on texture creation/update instead of repeating float log2 in the feedback loop.
constexpr uint8_t mip_level_count(uint16_t p_width, uint16_t p_height) {
	uint32_t max_dim = p_width > p_height ? p_width : p_height;
	uint8_t levels = 1;
	while (max_dim > 1) {
		max_dim >>= 1;
		++levels;
	}
	return levels;
}

// Convert a positive texel footprint to its required mip without float log2.
// For IEEE-754 binary32 values >= 1, exponent - 127 is exactly floor(log2).
// Values below 1 (including zero, negatives and NaNs) request mip 0.
// Positive infinity saturates at the coarsest allowed mip.
inline uint8_t mip_from_coverage(float p_coverage, uint8_t p_mip_count) {
	static_assert(sizeof(float) == sizeof(uint32_t) && std::numeric_limits<float>::is_iec559,
			"Fast mip selection requires IEEE 754 binary32 floats.");
	if (p_mip_count == 0 || !(p_coverage >= 1.0f)) {
		return 0;
	}
	uint32_t bits;
	memcpy(&bits, &p_coverage, sizeof(bits));
	const uint32_t exponent = ((bits >> 23) & 0xffu) - 127u;
	const uint32_t max_mip = uint32_t(p_mip_count - 1);
	return uint8_t(exponent < max_mip ? exponent : max_mip);
}

// Predictive high-resolution mip residency: lower mip numbers are sharper.
// This operates on the GPU feedback result before the existing memory budget
// fitter. Saturating arithmetic prevents underflow for mip 0 and tiny textures.
constexpr uint8_t prefetch_mip(uint8_t p_requested, uint8_t p_detail_prefetch_mips) {
	return p_detail_prefetch_mips >= p_requested ? 0 : uint8_t(p_requested - p_detail_prefetch_mips);
}

// Opt-in prefetch control driven by actual resident streamed-texture memory.
// Recovery has a lower threshold than restriction: 95% -> 0, 85% -> at most 1;
// below 78% recover one mip, below 70% recover the full user-requested tier.
// Integer threshold arithmetic avoids overflow at uint64_t budget extremes.
// Zero budget or disabled adaptive mode leaves legacy behavior unchanged.
constexpr uint8_t adaptive_prefetch_mips(uint8_t p_requested, uint8_t p_previous,
		uint64_t p_used_bytes, uint64_t p_budget_bytes, bool p_enabled) {
	const uint8_t requested = p_requested > 2 ? 2 : p_requested;
	if (!p_enabled || p_budget_bytes == 0) {
		return requested;
	}
	uint8_t current = p_previous > requested ? requested : p_previous;
	const uint64_t hard = p_budget_bytes - p_budget_bytes / 20; // 95%.
	const uint64_t soft = p_budget_bytes - p_budget_bytes / 10 - p_budget_bytes / 20; // 85%.
	const uint64_t recover_one = p_budget_bytes - p_budget_bytes / 5 - p_budget_bytes / 50; // 78%.
	const uint64_t recover_all = p_budget_bytes - p_budget_bytes / 5 - p_budget_bytes / 10; // 70%.
	if (p_used_bytes >= hard) {
		return 0;
	}
	if (p_used_bytes >= soft) {
		return current > 1 ? 1 : current;
	}
	if (p_used_bytes <= recover_all) {
		return requested;
	}
	if (p_used_bytes <= recover_one) {
		if (current == 0 && requested > 0) {
			return 1;
		}
		return current;
	}
	return current;
}

// Pick the next physical texture reload toward the memory-fitted target.
// High/Ultra skip one intermediate blurry upload on detail recovery, but
// under VRAM pressure sharpness still decays conservatively one mip at a time.
// Uninitialized textures can directly upload the approved target level.
constexpr uint8_t next_reload_mip(uint8_t p_current, uint8_t p_target, uint8_t p_detail_prefetch_mips) {
	if (p_current == 255 || p_current == p_target) {
		return p_target;
	}
	if (p_target > p_current) {
		return uint8_t(p_current + 1);
	}
	const uint8_t step = p_detail_prefetch_mips > 0 ? 2 : 1;
	const uint8_t distance = uint8_t(p_current - p_target);
	return uint8_t(p_current - (distance < step ? distance : step));
}

// Do not repeatedly recreate a valid 4 KiB buffer when no materials exist.
// Use 64-bit arithmetic so large material counts cannot wrap the comparison.
constexpr bool needs_resize(uint32_t p_allocated_bytes, bool p_buffer_valid, uint32_t p_material_count) {
	return !p_buffer_valid || p_allocated_bytes < MIN_BUFFER_SIZE_BYTES ||
			uint64_t(p_allocated_bytes) < uint64_t(p_material_count) * sizeof(uint32_t);
}
} // namespace TextureStreamingFeedbackPolicy

#endif // TEXTURE_STREAMING_FEEDBACK_BUFFER_POLICY_H
