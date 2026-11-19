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

// Plain C++ policy: keeping it independent of the renderer lets us run
// deterministic boundary tests without allocating GPU resources.
namespace TextureStreamingFeedbackPolicy {
constexpr uint32_t MIN_BUFFER_SIZE_BYTES = 4096;
constexpr uint32_t MAX_MATERIAL_COUNT = 1u << 29;

// Do not repeatedly recreate a valid 4 KiB buffer when no materials exist.
// Use 64-bit arithmetic so large material counts cannot wrap the comparison.
constexpr bool needs_resize(uint32_t p_allocated_bytes, bool p_buffer_valid, uint32_t p_material_count) {
	return !p_buffer_valid || p_allocated_bytes < MIN_BUFFER_SIZE_BYTES ||
			uint64_t(p_allocated_bytes) < uint64_t(p_material_count) * sizeof(uint32_t);
}
} // namespace TextureStreamingFeedbackPolicy

#endif // TEXTURE_STREAMING_FEEDBACK_BUFFER_POLICY_H
