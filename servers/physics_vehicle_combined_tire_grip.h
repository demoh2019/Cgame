/**************************************************************************/
/*  physics_vehicle_combined_tire_grip.h                                 */
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

#include <algorithm>
#include <cmath>

// Coupled longitudinal / lateral raycast-wheel tire impulse projection.
//
// Existing VehicleBody3D uses half-weighted forward impulse for the
// limit, so baseline capacities are:
//    forward_limit = 2 * suspension_normal_impulse * wheel_friction_slip
//    lateral_limit =     suspension_normal_impulse * wheel_friction_slip
// Preserve this weighting for 1.0 longitudinal/lateral grip multipliers,
// and introduce optional independent tire grip in [0,4] per direction.
//
// Project the requested tire impulse pair onto the elliptical budget:
//    (Jforward/forward_limit)^2 + (Jside/lateral_limit)^2 <= 1.
//
// Unlike the legacy skid correction, projection applies even when either
// one of the demanded impulses is exactly zero. A zero directional grip
// disables ONLY that axis, not the other. All results are candidate-only
// and written after validation; invalid input resets output impulses to
// zero so the solver never applies NaN or Inf impulses.
//
// This is a simplified combined-slip constraint, NOT a Pacejka/Magic
// Formula tire with dynamic longitudinal slip ratio, camber or relaxation.
//
// Returns true on numerically valid inputs, and r_skid is the *smallest*
// realized/requested impulse fraction in [0,1]. No heap allocation.
inline static bool physics_vehicle_project_combined_tire_impulses(
		double p_forward_impulse, double p_side_impulse,
		double p_normal_impulse, double p_friction_slip,
		double p_longitudinal_grip, double p_lateral_grip,
		double &r_forward, double &r_side, double &r_skid) {
	if (!std::isfinite(p_forward_impulse) || !std::isfinite(p_side_impulse) ||
			!std::isfinite(p_normal_impulse) || p_normal_impulse < 0.0 ||
			!std::isfinite(p_friction_slip) || p_friction_slip < 0.0 ||
			!std::isfinite(p_longitudinal_grip) ||
			p_longitudinal_grip < 0.0 || p_longitudinal_grip > 4.0 ||
			!std::isfinite(p_lateral_grip) ||
			p_lateral_grip < 0.0 || p_lateral_grip > 4.0) {
		r_forward = 0.0;
		r_side = 0.0;
		r_skid = 0.0;
		return false;
	}
	const double friction_budget = p_normal_impulse * p_friction_slip;
	const double forward_limit = 2.0 * friction_budget * p_longitudinal_grip;
	const double side_limit = friction_budget * p_lateral_grip;
	if (!std::isfinite(forward_limit) || !std::isfinite(side_limit)) {
		r_forward = 0.0;
		r_side = 0.0;
		r_skid = 0.0;
		return false;
	}

	double forward = forward_limit > 0.0 ? p_forward_impulse : 0.0;
	double side = side_limit > 0.0 ? p_side_impulse : 0.0;
	const double normalized_forward = forward_limit > 0.0 ? forward / forward_limit : 0.0;
	const double normalized_side = side_limit > 0.0 ? side / side_limit : 0.0;
	const double norm = std::hypot(normalized_forward, normalized_side);
	if (!(norm >= 0.0)) {
		r_forward = 0.0;
		r_side = 0.0;
		r_skid = 0.0;
		return false;
	}
	// A finite norm is not required; hypot(Infinity, finite) is defined,
	// and a zero projection factor remains safe for finite impulses.
	if (norm > 1.0) {
		const double scale = 1.0 / norm;
		forward *= scale;
		side *= scale;
	}
	const double forward_fraction = p_forward_impulse != 0.0 ?
			std::min(1.0, std::abs(forward / p_forward_impulse)) : 1.0;
	const double side_fraction = p_side_impulse != 0.0 ?
			std::min(1.0, std::abs(side / p_side_impulse)) : 1.0;
	const double skid = std::min(forward_fraction, side_fraction);
	if (!std::isfinite(forward) || !std::isfinite(side) ||
			!std::isfinite(skid)) {
		r_forward = 0.0;
		r_side = 0.0;
		r_skid = 0.0;
		return false;
	}
	r_forward = forward;
	r_side = side;
	r_skid = skid;
	return true;
}
