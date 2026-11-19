/**************************************************************************/
/*  physics_rolling_resistance.h                                          */
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

// One accumulated torque impulse per body pair, not per contact point.
// Input normal impulse has units force*time and radius_coeff has units
// length, giving torque impulse. The caller applies only next-previous.
_FORCE_INLINE_ static real_t godot_physics_accumulate_rolling_impulse(
		real_t p_previous, real_t p_relative_angular_velocity,
		real_t p_inv_angular_mass, real_t p_normal_impulse,
		real_t p_coefficient_times_radius) {
	if (p_inv_angular_mass <= 0.0 || p_coefficient_times_radius <= 0.0) {
		return p_previous;
	}
	const real_t max_impulse = MAX(p_normal_impulse, real_t(0.0)) * p_coefficient_times_radius;
	return CLAMP(p_previous - p_relative_angular_velocity / p_inv_angular_mass, -max_impulse, max_impulse);
}
