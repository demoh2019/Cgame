/**************************************************************************/
/*  test_physics_material_combine.cpp                                     */
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

TEST_FORCE_LINK(test_physics_material_combine)

#include "servers/physics_friction_combine.h"
#include "servers/physics_restitution_combine.h"

namespace TestPhysicsMaterialCombine {

TEST_CASE("[Physics] Friction combine modes match across 2D 3D and Jolt") {
	SUBCASE("Legacy minimum remains the default") {
		CHECK(godot_physics_combine_friction(1.0, 0.25, 0) == real_t(0.25));
		CHECK(godot_physics_combine_friction(1.0, 0.25, -1) == real_t(0.25));
		CHECK(godot_physics_combine_friction(-0.25, 1.0, 0) == real_t(0.25));
		CHECK(godot_physics_combine_friction(1.0, -0.25, 0) == real_t(0.25));
	}
	SUBCASE("Geometric mean is zero if either surface has no friction") {
		CHECK(godot_physics_combine_friction(1.0, 0.25, 1) == real_t(0.5));
		CHECK(godot_physics_combine_friction(0.0, 0.8, 1) == real_t(0.0));
		CHECK(godot_physics_combine_friction(-1.0, 0.25, 1) == real_t(0.5));
	}
	SUBCASE("Average and maximum") {
		CHECK(godot_physics_combine_friction(1.0, 0.25, 2) == real_t(0.625));
		CHECK(godot_physics_combine_friction(1.0, 0.25, 3) == real_t(1.0));
		CHECK(godot_physics_combine_friction(1.0, 0.25, 20) == real_t(0.25));
	}
}

TEST_CASE("[Physics] Restitution combine modes support legacy and Rapier rules") {
	const real_t a = real_t(0.25);
	const real_t b = real_t(0.5);
	CHECK(godot_physics_combine_restitution(a, b, 0) == real_t(0.75));
	CHECK(godot_physics_combine_restitution(a, b, 1) == real_t(0.5));
	CHECK(godot_physics_combine_restitution(a, b, 2) == real_t(0.375));
	CHECK(godot_physics_combine_restitution(a, b, 3) == real_t(0.25));
	CHECK(godot_physics_combine_restitution(a, b, 4) == real_t(0.125));
	CHECK(Math::is_equal_approx(godot_physics_combine_restitution(a, b, 5), Math::sqrt(real_t(0.125))));
	CHECK(godot_physics_combine_restitution(real_t(0.8), real_t(0.6), 0) == real_t(1.0));
	CHECK(godot_physics_combine_restitution(real_t(-1.0), real_t(0.6), 3) == real_t(0.0));
}

} // namespace TestPhysicsMaterialCombine
