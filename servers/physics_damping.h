/**************************************************************************/
/*  physics_damping.h                                                     */
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

// Box2D-style implicit (Pade) integration of dv/dt + damping*v = 0.
// For nonnegative damping, the result 1/(1 + step*damping) is strictly
// positive even when a large step would make explicit Euler clamp to zero.
// Legacy behavior remains bit-for-bit unchanged when the feature is off.
// Negative damping continues to use legacy amplification in either mode.
_FORCE_INLINE_ static real_t godot_physics_damping_factor(real_t p_step, real_t p_damping, bool p_implicit) {
	const real_t attenuation = p_step * p_damping;
	if (p_implicit && attenuation > real_t(0.0)) {
		return real_t(1.0) / (real_t(1.0) + attenuation);
	}
	const real_t legacy_factor = real_t(1.0) - attenuation;
	return legacy_factor < real_t(0.0) ? real_t(0.0) : legacy_factor;
}
