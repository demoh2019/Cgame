/**************************************************************************/
/*  physics_friction_combine.h                                            */
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

#include "core/math/math_funcs.h"

// Shared by GodotPhysics2D, GodotPhysics3D and Cgame's Jolt backend.
// 0 = legacy minimum, 1 = Box2D geometric mean, 2 = average, 3 = maximum.
// Preserve the historical absolute-minimum rule for default and invalid modes.
_FORCE_INLINE_ static real_t godot_physics_combine_friction(real_t p_a, real_t p_b, int p_mode) {
	if (p_mode == 0) {
		return Math::abs(MIN(p_a, p_b));
	}

	const real_t a = Math::abs(p_a);
	const real_t b = Math::abs(p_b);
	switch (p_mode) {
		case 1:
			return Math::sqrt(a * b);
		case 2:
			return (a + b) * real_t(0.5);
		case 3:
			return MAX(a, b);
		default:
			return Math::abs(MIN(p_a, p_b));
	}
}
