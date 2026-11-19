/**************************************************************************/
/*  physics_softbody_adiabatic_gas.h                                      */
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
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE       */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "core/math/vector3.h"

// Optional pressure-volume response for a sealed, oriented soft-body mesh.
// p(V) = p_rest * (|V_rest| / |V|)^gamma, gamma = 1 (isothermal),
// gamma > 1 (adiabatic compression). For extreme compression, pressure
// is evaluated at >= 5% rest volume to avoid singular/infinite forces.
// A reversed or degenerate signed volume disables the gas for this step.
// The solver determines mesh manifold closedness separately, at setup.
_FORCE_INLINE_ bool physics_softbody_adiabatic_pressure(
		double p_rest_signed_volume, double p_current_signed_volume,
		double p_pressure_at_rest, double p_gamma, double &r_pressure) {
	if (!Math::is_finite(p_rest_signed_volume) ||
			!Math::is_finite(p_current_signed_volume) ||
			!Math::is_finite(p_pressure_at_rest) || !Math::is_finite(p_gamma) ||
			p_rest_signed_volume == 0.0 || p_current_signed_volume == 0.0 ||
			!(p_pressure_at_rest > 0.0) || !(p_gamma > 0.0) || p_gamma > 5.0 ||
			((p_rest_signed_volume < 0.0) != (p_current_signed_volume < 0.0))) {
		return false;
	}
	const double rest = Math::abs(p_rest_signed_volume);
	const double current = Math::abs(p_current_signed_volume);
	const double relative_volume = current / rest;
	if (!(relative_volume > 0.0) || !Math::is_finite(relative_volume)) {
		return false;
	}
	// Divide volume by rest first; avoid multiplying large cubic scales.
	const double ratio = 1.0 / MAX(relative_volume, 0.05);
	const double pressure = p_pressure_at_rest * Math::pow(ratio, p_gamma);
	if (!(pressure > 0.0) || !Math::is_finite(pressure)) {
		return false;
	}
	r_pressure = pressure;
	return true;
}

// Return the pressure force applied to EACH of the three face vertices.
// F_vertex = (pressure/3) * oriented_area_vector
//          = pressure * sign(V_rest) * cross(b-a, c-a) / 6.
// Using a double-precision geometric cross prevents float intermediate
// overflow on large triangles; winding reversal flips sign(V_rest) too.
// No allocations, unchanged output for bad inputs, and pins can be skipped
// when applying the result in the soft-body solver.
_FORCE_INLINE_ bool physics_softbody_adiabatic_face_force(
		const Vector3 &p_a, const Vector3 &p_b, const Vector3 &p_c,
		double p_pressure, int p_rest_orientation, Vector3 &r_force_per_vertex) {
	if (!p_a.is_finite() || !p_b.is_finite() || !p_c.is_finite() ||
			!Math::is_finite(p_pressure) || !(p_pressure > 0.0) ||
			(p_rest_orientation != 1 && p_rest_orientation != -1)) {
		return false;
	}
	const double abx = double(p_b.x) - double(p_a.x);
	const double aby = double(p_b.y) - double(p_a.y);
	const double abz = double(p_b.z) - double(p_a.z);
	const double acx = double(p_c.x) - double(p_a.x);
	const double acy = double(p_c.y) - double(p_a.y);
	const double acz = double(p_c.z) - double(p_a.z);
	const double cx = aby * acz - abz * acy;
	const double cy = abz * acx - abx * acz;
	const double cz = abx * acy - aby * acx;
	const double sq = cx * cx + cy * cy + cz * cz;
	if (!(sq > 0.0) || !Math::is_finite(sq)) {
		return false;
	}
	const double scale = p_pressure * double(p_rest_orientation) / 6.0;
	const Vector3 candidate(real_t(cx * scale), real_t(cy * scale), real_t(cz * scale));
	if (!candidate.is_finite()) {
		return false;
	}
	r_force_per_vertex = candidate;
	return true;
}
