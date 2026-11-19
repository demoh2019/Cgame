/**************************************************************************/
/*  physics_angular_velocity_cap.h                                        */
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

#include "core/math/vector3.h"
#include "servers/physics_linear_velocity_cap.h"

// Both overloads limit dynamic-body rotation, not positional correction bias.
// Nonpositive maximum means unlimited, preserving legacy scene trajectories.
// For 3D, reuse the overflow-safe vector magnitude limiter already used for
// linear velocity instead of adding another normalization implementation.
_FORCE_INLINE_ static real_t godot_physics_clamp_angular_velocity(real_t p_angular_velocity, real_t p_max_speed) {
	if (!(p_max_speed > real_t(0.0)) || !Math::is_finite(p_angular_velocity)) {
		return p_angular_velocity;
	}
	return CLAMP(p_angular_velocity, -p_max_speed, p_max_speed);
}

_FORCE_INLINE_ static Vector3 godot_physics_clamp_angular_velocity(const Vector3 &p_angular_velocity, real_t p_max_speed) {
	return godot_physics_clamp_linear_velocity(p_angular_velocity, p_max_speed);
}


// Rapier-style CCD rotation safety limit. Unlike the ordinary maximum
// angular velocity (rad/s), this is a maximum *angle per physics step*
// (radians). The caller enables it only for dynamic CCD bodies.
// Zero disables the feature, and invalid/nonpositive dt never divides.
_FORCE_INLINE_ static real_t godot_physics_clamp_ccd_angular_velocity(real_t p_angular_velocity, real_t p_max_angle, real_t p_step) {
	if (!(p_max_angle > real_t(0.0)) || !Math::is_finite(p_max_angle) ||
			!(p_step > real_t(0.0)) || !Math::is_finite(p_step)) {
		return p_angular_velocity;
	}
	const real_t speed_limit = p_max_angle / p_step;
	if (!Math::is_finite(speed_limit)) {
		return p_angular_velocity;
	}
	return godot_physics_clamp_angular_velocity(p_angular_velocity, speed_limit);
}

_FORCE_INLINE_ static Vector3 godot_physics_clamp_ccd_angular_velocity(const Vector3 &p_angular_velocity, real_t p_max_angle, real_t p_step) {
	if (!(p_max_angle > real_t(0.0)) || !Math::is_finite(p_max_angle) ||
			!(p_step > real_t(0.0)) || !Math::is_finite(p_step)) {
		return p_angular_velocity;
	}
	const real_t speed_limit = p_max_angle / p_step;
	if (!Math::is_finite(speed_limit)) {
		return p_angular_velocity;
	}
	return godot_physics_clamp_angular_velocity(p_angular_velocity, speed_limit);
}
