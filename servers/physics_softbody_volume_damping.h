/**************************************************************************/
/*  physics_softbody_volume_damping.h                                    */
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
/**************************************************************************/

#pragma once

#include "core/math/math_funcs.h"
#include "core/math/vector3.h"

// Mass-weighted projection of the enclosed volume rate dV/dt.
// K = sum inverse_mass_i * |grad_i(V)|^2 is the effective inverse mass.
// An exponential damping fraction f = 1-exp(-rate*dt) in [0,1]
// gives lambda = -f*Vdot/K and Vdot_after = (1-f)*Vdot_before.
//
// Dissipated kinetic energy = f*(2-f)*Vdot^2/(2*K), never negative.
// On invalid or degenerate input, r_impulse is NOT modified.
_FORCE_INLINE_ static bool physics_softbody_bulk_viscosity_impulse(
		double p_volume_rate, double p_inverse_mass_gradient, double p_fraction,
		double &r_impulse) {
	if (!Math::is_finite(p_volume_rate) ||
			!Math::is_finite(p_inverse_mass_gradient) ||
			!Math::is_finite(p_fraction) ||
			!(p_inverse_mass_gradient > 0.0) ||
			!(p_fraction > 0.0 && p_fraction <= 1.0)) {
		return false;
	}
	const double impulse = -p_fraction * (p_volume_rate / p_inverse_mass_gradient);
	if (!Math::is_finite(impulse) || impulse == 0.0) {
		return false;
	}
	r_impulse = impulse;
	return true;
}

// Predict velocity in double precision before narrowing to Vector3.
// No mutation until all candidates for the body are validated atomically.
_FORCE_INLINE_ static bool physics_softbody_bulk_viscosity_velocity(
		const Vector3 &p_velocity, const Vector3 &p_volume_gradient,
		real_t p_inverse_mass, double p_impulse, Vector3 &r_velocity) {
	if (!p_velocity.is_finite() || !p_volume_gradient.is_finite() ||
			!Math::is_finite(p_inverse_mass) || !(p_inverse_mass > real_t(0.0)) ||
			!Math::is_finite(p_impulse)) {
		return false;
	}
	const double scale = double(p_inverse_mass) * p_impulse;
	const Vector3 candidate(
			real_t(double(p_velocity.x) + double(p_volume_gradient.x) * scale),
			real_t(double(p_velocity.y) + double(p_volume_gradient.y) * scale),
			real_t(double(p_velocity.z) + double(p_volume_gradient.z) * scale));
	if (!candidate.is_finite()) {
		return false;
	}
	r_velocity = candidate;
	return true;
}
