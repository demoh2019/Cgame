/**************************************************************************/
/*  camera_shake.h                                             */
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

#include "core/math/vector3.h"

// Trauma based camera shake (the model from Squirrel Eiserloh's GDC 2016 talk "Math for Game
// Programmers: Juicing Your Cameras With Math"): events add *trauma* in [0, 1] that decays
// linearly, and the visible shake is trauma^exponent times smooth noise. Squaring the trauma
// makes small hits subtle and big hits violent without extra tuning.
//
// This type only holds the state and samples the noise; Camera2D and Camera3D own an instance
// and turn the unit values into offsets and rotations.
struct CameraShake {
	real_t trauma = 0.0;
	double phase = 0.0; // Noise time, advanced at `frequency` per second.

	void add_trauma(real_t p_amount) { set_trauma(trauma + p_amount); }
	void set_trauma(real_t p_trauma) { trauma = Math::is_finite(p_trauma) ? CLAMP(p_trauma, real_t(0.0), real_t(1.0)) : real_t(0.0); }

	// Advances time and decays trauma. Returns true while the shake is still active.
	bool advance(double p_delta, real_t p_decay, real_t p_frequency);

	real_t get_intensity(real_t p_exponent) const;

	// Smooth noise in [-1, 1] on three independent channels.
	Vector3 get_translation_unit() const;
	Vector3 get_rotation_unit() const;

	// Smooth (C2) 1D value noise in [-1, 1]; `p_channel` selects an independent noise stream.
	static real_t noise(double p_x, uint32_t p_channel);
};
