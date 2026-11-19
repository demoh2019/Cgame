/**************************************************************************/
/*  physics_restitution_combine.h                                         */
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
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/**************************************************************************/

#pragma once

#include "core/math/math_funcs.h"

// Shared by GodotPhysics2D/3D. Mode 0 must keep the historical GodotPhysics
// behavior exactly; newer modes clamp each material to its physical [0, 1]
// coefficient range before mixing. This is called once per body pair per step.
_FORCE_INLINE_ static real_t godot_physics_combine_restitution(real_t p_a, real_t p_b, int p_mode) {
	if (p_mode == 0) {
		return CLAMP(p_a + p_b, real_t(0.0), real_t(1.0));
	}

	const real_t a = CLAMP(p_a, real_t(0.0), real_t(1.0));
	const real_t b = CLAMP(p_b, real_t(0.0), real_t(1.0));
	switch (p_mode) {
		case 1: // Maximum (Box2D default).
			return MAX(a, b);
		case 2: // Average (Rapier default).
			return (a + b) * real_t(0.5);
		case 3: // Minimum.
			return MIN(a, b);
		case 4: // Multiply.
			return a * b;
		case 5: // Geometric mean.
			return Math::sqrt(a * b);
		default:
			return CLAMP(p_a + p_b, real_t(0.0), real_t(1.0));
	}
}
