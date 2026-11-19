/**************************************************************************/
/*  physics_ccd_rotational_bounds.h                                       */
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

#include "core/math/aabb.h"
#include "core/math/rect2.h"

// A rotating point at radius r travels no more than
// 2*r*sin(min(abs(angle), PI)/2) from its initial position during a step.
// For turns >= PI, the maximum possible chord is the diameter.
// Return zero for inactive/invalid angular sweeps, to keep legacy behavior.
_FORCE_INLINE_ static real_t godot_physics_ccd_rotational_factor(real_t p_angle) {
	if (!(Math::abs(p_angle) > real_t(0.0)) || !Math::is_finite(p_angle)) {
		return real_t(0.0);
	}
	return real_t(2.0) * Math::sin(MIN(Math::abs(p_angle), real_t(Math_PI)) * real_t(0.5));
}

// All corners of an axis-aligned box are bounded by the farthest absolute
// coordinate on each axis relative to the body's current world-space COM.
// The resulting sphere/circle contains the original world-space AABB and
// therefore all of the actual collider geometry, including compound offsets.
_FORCE_INLINE_ static real_t godot_physics_ccd_rotational_padding(const Rect2 &p_bounds, const Vector2 &p_pivot, real_t p_factor) {
	if (!(p_factor > real_t(0.0))) {
		return real_t(0.0);
	}
	const Vector2 a = (p_bounds.position - p_pivot).abs();
	const Vector2 b = (p_bounds.position + p_bounds.size - p_pivot).abs();
	const Vector2 extent(MAX(a.x, b.x), MAX(a.y, b.y));
	return extent.length() * p_factor;
}

_FORCE_INLINE_ static real_t godot_physics_ccd_rotational_padding(const AABB &p_bounds, const Vector3 &p_pivot, real_t p_factor) {
	if (!(p_factor > real_t(0.0))) {
		return real_t(0.0);
	}
	const Vector3 a = (p_bounds.position - p_pivot).abs();
	const Vector3 b = (p_bounds.position + p_bounds.size - p_pivot).abs();
	const Vector3 extent(MAX(a.x, b.x), MAX(a.y, b.y), MAX(a.z, b.z));
	return extent.length() * p_factor;
}
