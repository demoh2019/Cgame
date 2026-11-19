/**************************************************************************/
/*  physics_fem_tetra_cycle_fatigue.h                                            */
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

#include "servers/physics_fem_tetra_damage.h"
#include "servers/physics_fem_tetra_principal_limits.h"

#include <cmath>
#include <cstdint>

// Experimental cycle-dependent continuum fatigue for 3D tetrahedra.
//
// Samples an objective SIGNED scalar strain: the principal logarithmic
// stretch with the greatest absolute value, from singular values of
// F = Ds * inverse(Dm). Compression is negative and tension positive.
// The full 3D principal spectrum captures axial, volumetric and shear
// loading, unlike fatigue measured solely on shell edges.
//
// A bounded-memory extremum reversal detector counts a full excursion
// only on an alternating peak -> valley -> peak sequence. A half-range
// amplitude A=min(peak_previous, peak_new)-valley, divided by two,
// drives a simplified Woehler/Basquin + Palmgren-Miner damage increment:
//
//   A_eff = max(0, A - endurance) / (reference - endurance)
//   Delta D = A_eff^exponent / reference_cycles
//
// Cycles below the endurance amplitude do no damage. Repeated holds,
// monotonic loading and motion smaller than the noise deadband do not
// count cycles. This is intentionally O(1) memory per FEM element and
// is NOT ASTM rainflow counting, fracture topology, or a calibrated S-N
// model; multilevel variable-amplitude histories are approximate.
//
// Fatigue and instantaneous overload damage share the existing scalar
// D in [0, PhysicsFEMTetraDamage::MAX_DAMAGE], so elastic, fiber and
// SLS/Prony compliance all soften consistently. Persistent state resets
// only on FEM rest-mesh rebuild, never per XPBD iteration.
struct PhysicsFEMTetraCycleFatigueState {
	bool initialized = false;
	bool has_peak = false;
	bool has_valley = false;
	int direction = 0; // -1 descending, +1 ascending, 0 unknown.
	double sample = 0.0;
	double previous_peak = 0.0;
	double valley = 0.0;
	uint64_t cycles = 0;
};

struct PhysicsFEMTetraCycleFatigue {
	_FORCE_INLINE_ static bool measure_strain(
			const Vector3 p_positions[4], const PhysicsFEMTetraRest &p_rest,
			double &r_signed_strain) {
		if (!p_positions) {
			return false;
		}
		double sigmas[3], axes[3][3], f[3][3];
		if (!physics_fem_tetra_principal_spectrum(
					p_positions, p_rest, sigmas, axes, f)) {
			return false;
		}
		double result = 0.0;
		for (int i = 0; i < 3; ++i) {
			const double s = std::log(sigmas[i]);
			if (!Math::is_finite(s)) {
				return false;
			}
			if (Math::abs(s) > Math::abs(result)) {
				result = s;
			}
		}
		r_signed_strain = result;
		return true;
	}

	_FORCE_INLINE_ static bool evolve(
			double p_signed_strain, double p_endurance_amplitude,
			double p_reference_amplitude, double p_reference_cycles,
			double p_exponent, double p_noise_deadband,
			PhysicsFEMTetraCycleFatigueState &r_state, double &r_damage) {
		if (!Math::is_finite(p_signed_strain) ||
				!Math::is_finite(p_endurance_amplitude) || p_endurance_amplitude < 0.0 ||
				!Math::is_finite(p_reference_amplitude) ||
				!(p_reference_amplitude > p_endurance_amplitude) ||
				!Math::is_finite(p_reference_cycles) || !(p_reference_cycles > 0.0) ||
				!Math::is_finite(p_exponent) || p_exponent < 1.0 || p_exponent > 10.0 ||
				!Math::is_finite(p_noise_deadband) || p_noise_deadband < 0.0 ||
				!Math::is_finite(r_damage) || r_damage < 0.0 ||
				r_damage > PhysicsFEMTetraDamage::MAX_DAMAGE ||
				(r_state.direction < -1 || r_state.direction > 1) ||
				!Math::is_finite(r_state.sample) ||
				!Math::is_finite(r_state.previous_peak) ||
				!Math::is_finite(r_state.valley)) {
			return false;
		}
		PhysicsFEMTetraCycleFatigueState next = r_state;
		double damage = r_damage;
		if (!next.initialized) {
			next.sample = p_signed_strain;
			next.initialized = true;
			r_state = next;
			return true;
		}
		const double delta = p_signed_strain - next.sample;
		if (!Math::is_finite(delta)) {
			return false;
		}
		if (Math::abs(delta) <= p_noise_deadband) {
			// Leave the last significant sample in place so a succession
			// of small monotone increments can eventually cross the band.
			return true;
		}
		const int direction = delta > 0.0 ? 1 : -1;
		if (next.direction == 0 || direction == next.direction) {
			next.direction = direction;
			next.sample = p_signed_strain;
			r_state = next;
			return true;
		}
		// Reversal occurs at the PREVIOUS sample, which is an extremum.
		if (next.direction < 0 && direction > 0) {
			next.valley = next.sample;
			next.has_valley = next.has_peak;
		} else if (next.direction > 0 && direction < 0) {
			const double peak = next.sample;
			if (next.has_peak && next.has_valley) {
				const double full_range = MIN(next.previous_peak, peak) - next.valley;
				if (!Math::is_finite(full_range)) {
					return false;
				}
				if (full_range > 0.0) {
					const double amplitude = 0.5 * full_range;
					if (amplitude > p_endurance_amplitude &&
							damage < PhysicsFEMTetraDamage::MAX_DAMAGE) {
						const double normalized =
								(amplitude - p_endurance_amplitude) /
								(p_reference_amplitude - p_endurance_amplitude);
						const double increment = std::pow(normalized, p_exponent) /
								p_reference_cycles;
						// Positive overflow saturates at MAX_DAMAGE, never NaN.
						if (!(increment >= 0.0) || std::isnan(increment)) {
							return false;
						}
						damage = MIN(PhysicsFEMTetraDamage::MAX_DAMAGE, damage + increment);
						if (!Math::is_finite(damage)) {
							return false;
						}
					}
					if (next.cycles < UINT64_MAX) {
						++next.cycles;
					}
				}
			}
			next.previous_peak = peak;
			next.has_peak = true;
			next.has_valley = false;
		}
		next.sample = p_signed_strain;
		next.direction = direction;
		r_damage = damage;
		r_state = next;
		return true;
	}
};
