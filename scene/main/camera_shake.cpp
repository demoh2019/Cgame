/**************************************************************************/
/*  camera_shake.cpp                                             */
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

#include "camera_shake.h"

// Integer hash (Murmur3 finalizer): well mixed, cheap, no state.
static _FORCE_INLINE_ uint32_t shake_hash(uint32_t p_value) {
	p_value ^= p_value >> 16;
	p_value *= 0x85ebca6bU;
	p_value ^= p_value >> 13;
	p_value *= 0xc2b2ae35U;
	p_value ^= p_value >> 16;
	return p_value;
}

static _FORCE_INLINE_ real_t shake_lattice(int32_t p_cell, uint32_t p_channel) {
	const uint32_t h = shake_hash(uint32_t(p_cell) * 0x9e3779b1U + p_channel * 0x85ebca77U + 0x165667b1U);
	return real_t(h) * (real_t(2.0) / real_t(4294967295.0)) - real_t(1.0);
}

real_t CameraShake::noise(double p_x, uint32_t p_channel) {
	const double floored = Math::floor(p_x);
	const real_t f = real_t(p_x - floored);
	const int32_t cell = int32_t(floored);
	// Quintic fade: zero first and second derivatives at the lattice points, so the motion has
	// no visible kinks.
	const real_t u = f * f * f * (f * (f * real_t(6.0) - real_t(15.0)) + real_t(10.0));
	return Math::lerp(shake_lattice(cell, p_channel), shake_lattice(cell + 1, p_channel), u);
}

bool CameraShake::advance(double p_delta, real_t p_decay, real_t p_frequency) {
	if (!(trauma > real_t(0.0))) {
		return false;
	}
	if (p_delta > 0.0) {
		phase += p_delta * double(MAX(p_frequency, real_t(0.0)));
		trauma = MAX(real_t(0.0), trauma - MAX(p_decay, real_t(0.0)) * real_t(p_delta));
	}
	return trauma > real_t(0.0);
}

real_t CameraShake::get_intensity(real_t p_exponent) const {
	if (!(trauma > real_t(0.0))) {
		return real_t(0.0);
	}
	return Math::pow(trauma, MAX(p_exponent, real_t(0.0)));
}

Vector3 CameraShake::get_translation_unit() const {
	return Vector3(noise(phase, 0), noise(phase, 1), noise(phase, 2));
}

Vector3 CameraShake::get_rotation_unit() const {
	return Vector3(noise(phase, 3), noise(phase, 4), noise(phase, 5));
}
