/**************************************************************************/
/*  physics_softbody_gas_leak.h                                           */
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
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

#include "servers/physics_softbody_adiabatic_gas.h"

// Optional bounded mass-loss model for the closed SoftBody3D pressure shell.
// m is the remaining gas mass as a fraction of its original mass. For the
// same reference entropy, P = P_rest * (m * V_rest / V)^gamma.
//
// A simplified gas vent follows dm/dt = -k*m*sqrt(P / P_rest).
// The square-root pressure dependence approximates faster discharge of a
// compressed shell; k is a user-controlled rate in 1/s at reference pressure.
// This is NOT a calibrated compressible-nozzle/choked-flow model: ambient
// pressure, temperature exchange and actual vent area are not simulated.
//
// The exponential step is unconditionally nonnegative and bounded by the
// previous mass (unlike explicit Euler for large k*dt). A zero leak rate
// preserves the existing adiabatic pressure model exactly at m=1.
// No allocations; both outputs are committed together only after validation.
_FORCE_INLINE_ bool physics_softbody_gas_leak_step(
		double p_rest_signed_volume, double p_current_signed_volume,
		double p_pressure_at_rest, double p_gamma, double p_rate,
		double p_step, double &r_mass_fraction, double &r_pressure) {
	if (!Math::is_finite(p_rate) || p_rate < 0.0 ||
			!Math::is_finite(p_step) || p_step < 0.0 ||
			!Math::is_finite(r_mass_fraction) ||
			r_mass_fraction < 0.0 || r_mass_fraction > 1.0) {
		return false;
	}

	double sealed_pressure = 0.0;
	if (!physics_softbody_adiabatic_pressure(p_rest_signed_volume,
				p_current_signed_volume, p_pressure_at_rest, p_gamma,
				sealed_pressure)) {
		return false;
	}

	const double previous_pressure = sealed_pressure * Math::pow(r_mass_fraction, p_gamma);
	if (!Math::is_finite(previous_pressure) || previous_pressure < 0.0) {
		return false;
	}

	double next_mass = r_mass_fraction;
	if (p_rate > 0.0 && p_step > 0.0 && r_mass_fraction > 0.0 && previous_pressure > 0.0) {
		const double pressure_ratio = previous_pressure / p_pressure_at_rest;
		if (!(pressure_ratio >= 0.0) || !Math::is_finite(pressure_ratio)) {
			return false;
		}
		// Pressure cannot increase the per-step flow factor without bound
		// after extreme mesh compression. The EOS itself already clamps
		// geometric compression to 5% of its rest volume.
		const double discharge_speed = Math::sqrt(MIN(pressure_ratio, 1e12));
		const double raw_exponent = p_rate * p_step * discharge_speed;
		const double exponent = Math::is_finite(raw_exponent) ? MIN(raw_exponent, 750.0) : 750.0;
		next_mass *= Math::exp(-exponent);
	}
	const double next_pressure = sealed_pressure * Math::pow(next_mass, p_gamma);
	if (!Math::is_finite(next_mass) || next_mass < 0.0 || next_mass > r_mass_fraction ||
			!Math::is_finite(next_pressure) || next_pressure < 0.0) {
		return false;
	}
	r_mass_fraction = next_mass;
	r_pressure = next_pressure;
	return true;
}
