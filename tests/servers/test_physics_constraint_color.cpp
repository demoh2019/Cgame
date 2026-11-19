/**************************************************************************/
/*  test_physics_constraint_color.cpp                                     */
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

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_physics_constraint_color)

#include "servers/physics_constraint_color.h"

namespace TestPhysicsConstraintColor {

TEST_CASE("[Physics] Bit-scan constraint color matches the existing greedy solver") {
	constexpr uint32_t COLOR_COUNT = 16;
	uint32_t mismatches = 0;
	uint32_t mismatches_high_bits = 0;

	// Enumerate ALL masks the 2D/3D 16-color solvers can construct, including
	// zero, a single missing color, alternating masks, and a saturated hub.
	for (uint32_t used = 0; used <= 0xFFFFu; ++used) {
		uint32_t expected = COLOR_COUNT;
		for (uint32_t color = 0; color < COLOR_COUNT; ++color) {
			if ((used & (uint32_t(1) << color)) == 0) {
				expected = color;
				break;
			}
		}
		const uint32_t actual = godot_physics_first_available_constraint_color<COLOR_COUNT>(used);
		if (actual != expected) {
			++mismatches;
		}
		// Upper bits are ignored, as in the original candidate loop.
		const uint32_t upper_bits_set = used | 0xFFFF0000u;
		if (godot_physics_first_available_constraint_color<COLOR_COUNT>(upper_bits_set) != expected) {
			++mismatches_high_bits;
		}
	}
	CHECK(mismatches == 0);
	CHECK(mismatches_high_bits == 0);
}

TEST_CASE("[Physics] Constraint-color overflow and non-16 bit widths") {
	CHECK(godot_physics_first_available_constraint_color<16>(0) == 0);
	CHECK(godot_physics_first_available_constraint_color<16>(0x00000001u) == 1);
	CHECK(godot_physics_first_available_constraint_color<16>(0x0000FFFEu) == 0);
	CHECK(godot_physics_first_available_constraint_color<16>(0x0000FFFFu) == 16);
	CHECK(godot_physics_first_available_constraint_color<16>(0xFFFFFFFFu) == 16);
	CHECK(godot_physics_first_available_constraint_color<1>(0) == 0);
	CHECK(godot_physics_first_available_constraint_color<1>(1) == 1);
	CHECK(godot_physics_first_available_constraint_color<8>(0x0000007Fu) == 7);
	CHECK(godot_physics_first_available_constraint_color<8>(0x000000FFu) == 8);
	CHECK(godot_physics_first_available_constraint_color<31>(0x3FFFFFFFu) == 30);
	CHECK(godot_physics_first_available_constraint_color<31>(0x7FFFFFFFu) == 31);
}

} // namespace TestPhysicsConstraintColor
