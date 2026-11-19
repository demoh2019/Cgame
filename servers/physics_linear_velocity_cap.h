/**************************************************************************/
/*  physics_linear_velocity_cap.h                                         */
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

// Common fast path for 2D and 3D dynamic bodies. Avoid sqrt below the cap;
// default 0 disables this feature, preserving the former engine behavior.
template <typename TVector>
_FORCE_INLINE_ static TVector godot_physics_clamp_linear_velocity(const TVector &p_velocity, real_t p_max_speed) {
	if (!(p_max_speed > 0.0)) {
		return p_velocity;
	}
	const real_t speed_squared = p_velocity.length_squared();
	const real_t max_squared = p_max_speed * p_max_speed;
	if (speed_squared <= max_squared) {
		return p_velocity;
	}
	// Preserve invalid input without generating new NaN values during scaling.
	if (!p_velocity.is_finite() || !Math::is_finite(speed_squared)) {
		return p_velocity;
	}
	return p_velocity * (p_max_speed / Math::sqrt(speed_squared));
}
