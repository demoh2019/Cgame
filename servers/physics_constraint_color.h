/**************************************************************************/
/*  physics_constraint_color.h                                            */
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

#pragma once

#include <cstdint>

#ifdef _MSC_VER
#include <intrin.h>
#endif

// Greedy graph coloring for the GodotPhysics2D/3D large-island solver.
//
// Used colors are packed into a word, one bit per independent color. Return
// the lowest unused color, or COLOR_COUNT for the sequential overflow group.
// A bit scan replaces a possible 16-iteration branch loop in the coloring
// hot path. Masking first preserves the previous result even if higher bits
// are set (e.g. when color flags are reused for another purpose).
template <uint32_t COLOR_COUNT>
static inline uint32_t godot_physics_first_available_constraint_color(uint32_t p_used_colors) {
	static_assert(COLOR_COUNT > 0 && COLOR_COUNT < 32, "Color count must fit in the 32-bit mask with an overflow sentinel.");
	constexpr uint32_t valid_mask = (uint32_t(1) << COLOR_COUNT) - 1;
	const uint32_t available = ~p_used_colors & valid_mask;
	if (available == 0) {
		return COLOR_COUNT;
	}
#ifdef _MSC_VER
	unsigned long first_color = 0;
	_BitScanForward(&first_color, available);
	return uint32_t(first_color);
#elif defined(__GNUC__) || defined(__clang__)
	return uint32_t(__builtin_ctz(available));
#else
	// Support any additional C++ compiler without architecture-specific code.
	uint32_t first_color = 0;
	while ((available & (uint32_t(1) << first_color)) == 0) {
		++first_color;
	}
	return first_color;
#endif
}
