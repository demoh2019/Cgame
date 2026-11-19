/**************************************************************************/
/*  smooth_damp.h                                             */
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

#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

// Critically damped spring toward a moving target (Unity's Mathf.SmoothDamp family).
// The object owns the velocity, so callers only feed it the current value and the target:
//     position = damper.step(position, target, delta)
class SmoothDamp : public RefCounted {
	GDCLASS(SmoothDamp, RefCounted);

	real_t smooth_time = 0.3;
	real_t max_speed = 0.0; // 0 or less: unlimited.
	Variant velocity;

	template <typename T>
	static T _damp(const T &p_current, const T &p_target, T &r_velocity, real_t p_smooth_time, real_t p_max_speed, real_t p_delta);

protected:
	static void _bind_methods();

public:
	void set_smooth_time(real_t p_time) { smooth_time = MAX(p_time, real_t(0.0001)); }
	real_t get_smooth_time() const { return smooth_time; }

	void set_max_speed(real_t p_speed) { max_speed = p_speed; }
	real_t get_max_speed() const { return max_speed; }

	void set_velocity(const Variant &p_velocity) { velocity = p_velocity; }
	Variant get_velocity() const { return velocity; }

	Variant step(const Variant &p_current, const Variant &p_target, real_t p_delta);
	real_t step_angle(real_t p_current, real_t p_target, real_t p_delta);
	void reset();

	// Pure function used by `step` and by tests: returns the new value, updates the velocity.
	static real_t damp_scalar(real_t p_current, real_t p_target, real_t &r_velocity, real_t p_smooth_time, real_t p_max_speed, real_t p_delta);
	static Vector3 damp_vector3(const Vector3 &p_current, const Vector3 &p_target, Vector3 &r_velocity, real_t p_smooth_time, real_t p_max_speed, real_t p_delta);

	SmoothDamp() {}
};
