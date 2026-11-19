/**************************************************************************/
/*  physics_softbody_plasticity.h                                         */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
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
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/math/math_funcs.h"

#include <limits>

// Simple isotropic viscoplastic link model for deformable SoftBody3D meshes.
// Once |current/rest - 1| exceeds the elastic yield strain, relax the rest
// length exponentially toward the nearest allowed elastic boundary.
// This models permanent stretching/compression without mesh topology changes.
// p_creep_fraction is computed once per step: 1 - exp(-creep_rate * dt).
// The caller updates the squared rest length used by legacy PBD after success.
_FORCE_INLINE_ static bool physics_softbody_creep_rest_length(
		real_t p_current_length, real_t p_yield_strain,
		double p_creep_fraction, real_t &r_rest_length) {
	if (!(p_current_length > real_t(0.0) && r_rest_length > real_t(0.0) &&
			p_yield_strain >= real_t(0.0) && p_yield_strain <= real_t(1.0) &&
			p_creep_fraction > 0.0 && p_creep_fraction <= 1.0) ||
			!Math::is_finite(p_current_length) || !Math::is_finite(r_rest_length) ||
			!Math::is_finite(p_yield_strain) || !Math::is_finite(p_creep_fraction)) {
		return false;
	}

	const double rest = double(r_rest_length);
	const double length = double(p_current_length);
	const double yield = double(p_yield_strain);
	double target = rest;

	if (length > rest * (1.0 + yield)) {
		// An over-stretched spring settles at +yield elastic strain.
		target = length / (1.0 + yield);
	} else if (yield < 1.0 && length < rest * (1.0 - yield)) {
		// An over-compressed spring settles at -yield elastic strain.
		target = length / (1.0 - yield);
	} else {
		return false; // Elastic range: no permanent deformation.
	}

	const double next = rest + (target - rest) * p_creep_fraction;
	if (!(next > 0.0) || !Math::is_finite(next)) {
		return false;
	}
	const real_t next_rest_length = real_t(next);
	if (!(next_rest_length > real_t(0.0)) || !Math::is_finite(next_rest_length) ||
			!Math::is_finite(next_rest_length * next_rest_length) ||
			next_rest_length == r_rest_length) {
		return false;
	}
	r_rest_length = next_rest_length;
	return true;
}
