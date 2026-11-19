/**************************************************************************/
/*  smooth_damp.cpp                                             */
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

#include "smooth_damp.h"

#include "core/object/class_db.h"

// Magnitude helpers so scalars and vectors share one implementation.
static _FORCE_INLINE_ real_t sd_length(real_t p_v) { return Math::abs(p_v); }
static _FORCE_INLINE_ real_t sd_length(const Vector2 &p_v) { return p_v.length(); }
static _FORCE_INLINE_ real_t sd_length(const Vector3 &p_v) { return p_v.length(); }
static _FORCE_INLINE_ real_t sd_length(const Vector4 &p_v) { return p_v.length(); }
static _FORCE_INLINE_ real_t sd_dot(real_t p_a, real_t p_b) { return p_a * p_b; }
static _FORCE_INLINE_ real_t sd_dot(const Vector2 &p_a, const Vector2 &p_b) { return p_a.dot(p_b); }
static _FORCE_INLINE_ real_t sd_dot(const Vector3 &p_a, const Vector3 &p_b) { return p_a.dot(p_b); }
static _FORCE_INLINE_ real_t sd_dot(const Vector4 &p_a, const Vector4 &p_b) { return p_a.dot(p_b); }

// Game Programming Gems 4, chapter 1.10 ("Critically damped ease-in/ease-out smoothing").
// Stable for any delta, unlike a naive spring, and never overshoots the target.
template <typename T>
T SmoothDamp::_damp(const T &p_current, const T &p_target, T &r_velocity, real_t p_smooth_time, real_t p_max_speed, real_t p_delta) {
	if (!(p_delta > real_t(0.0))) {
		return p_current;
	}
	const real_t smooth = MAX(p_smooth_time, real_t(0.0001));
	const real_t omega = real_t(2.0) / smooth;
	const real_t x = omega * p_delta;
	const real_t decay = real_t(1.0) / (real_t(1.0) + x + real_t(0.48) * x * x + real_t(0.235) * x * x * x);

	T change = p_current - p_target;
	if (p_max_speed > real_t(0.0)) {
		const real_t max_change = p_max_speed * smooth;
		const real_t magnitude = sd_length(change);
		if (magnitude > max_change) {
			change = change * (max_change / magnitude);
		}
	}
	const T clamped_target = p_current - change;

	const T temp = (r_velocity + change * omega) * p_delta;
	r_velocity = (r_velocity - temp * omega) * decay;
	T output = clamped_target + (change + temp) * decay;

	// Prevent overshooting the (unclamped) target.
	if (sd_dot(p_target - p_current, output - p_target) > real_t(0.0)) {
		output = p_target;
		r_velocity = (output - p_target) / p_delta;
	}
	return output;
}

real_t SmoothDamp::damp_scalar(real_t p_current, real_t p_target, real_t &r_velocity, real_t p_smooth_time, real_t p_max_speed, real_t p_delta) {
	return _damp<real_t>(p_current, p_target, r_velocity, p_smooth_time, p_max_speed, p_delta);
}

Vector3 SmoothDamp::damp_vector3(const Vector3 &p_current, const Vector3 &p_target, Vector3 &r_velocity, real_t p_smooth_time, real_t p_max_speed, real_t p_delta) {
	return _damp<Vector3>(p_current, p_target, r_velocity, p_smooth_time, p_max_speed, p_delta);
}

Variant SmoothDamp::step(const Variant &p_current, const Variant &p_target, real_t p_delta) {
	const Variant::Type type = p_current.get_type();
	if (type == Variant::INT) {
		// Integers cannot hold fractional motion; treat them as floats.
		return step(real_t(p_current), p_target, p_delta);
	}
	ERR_FAIL_COND_V_MSG(p_target.get_type() != type && !(type == Variant::FLOAT && p_target.get_type() == Variant::INT), p_current, "SmoothDamp: current and target must have the same type.");

	// A velocity left over from another type (or never set) starts at rest.
	if (velocity.get_type() != type) {
		switch (type) {
			case Variant::FLOAT:
				velocity = real_t(0.0);
				break;
			case Variant::VECTOR2:
				velocity = Vector2();
				break;
			case Variant::VECTOR3:
				velocity = Vector3();
				break;
			case Variant::VECTOR4:
				velocity = Vector4();
				break;
			default:
				break;
		}
	}

	switch (type) {
		case Variant::FLOAT: {
			real_t v = velocity;
			const real_t out = _damp<real_t>(p_current, p_target, v, smooth_time, max_speed, p_delta);
			velocity = v;
			return out;
		}
		case Variant::VECTOR2: {
			Vector2 v = velocity;
			const Vector2 out = _damp<Vector2>(p_current, p_target, v, smooth_time, max_speed, p_delta);
			velocity = v;
			return out;
		}
		case Variant::VECTOR3: {
			Vector3 v = velocity;
			const Vector3 out = _damp<Vector3>(p_current, p_target, v, smooth_time, max_speed, p_delta);
			velocity = v;
			return out;
		}
		case Variant::VECTOR4: {
			Vector4 v = velocity;
			const Vector4 out = _damp<Vector4>(p_current, p_target, v, smooth_time, max_speed, p_delta);
			velocity = v;
			return out;
		}
		default: {
			ERR_FAIL_V_MSG(p_current, "SmoothDamp supports float, Vector2, Vector3 and Vector4.");
		}
	}
}

// Angles take the shortest way around the circle.
real_t SmoothDamp::step_angle(real_t p_current, real_t p_target, real_t p_delta) {
	const real_t shortest_target = p_current + real_t(Math::angle_difference(double(p_current), double(p_target)));
	return real_t(step(p_current, shortest_target, p_delta));
}

void SmoothDamp::reset() {
	velocity = Variant();
}

void SmoothDamp::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_smooth_time", "smooth_time"), &SmoothDamp::set_smooth_time);
	ClassDB::bind_method(D_METHOD("get_smooth_time"), &SmoothDamp::get_smooth_time);
	ClassDB::bind_method(D_METHOD("set_max_speed", "max_speed"), &SmoothDamp::set_max_speed);
	ClassDB::bind_method(D_METHOD("get_max_speed"), &SmoothDamp::get_max_speed);
	ClassDB::bind_method(D_METHOD("set_velocity", "velocity"), &SmoothDamp::set_velocity);
	ClassDB::bind_method(D_METHOD("get_velocity"), &SmoothDamp::get_velocity);

	ClassDB::bind_method(D_METHOD("step", "current", "target", "delta"), &SmoothDamp::step);
	ClassDB::bind_method(D_METHOD("step_angle", "current", "target", "delta"), &SmoothDamp::step_angle);
	ClassDB::bind_method(D_METHOD("reset"), &SmoothDamp::reset);

	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "smooth_time", PROPERTY_HINT_RANGE, "0.0001,10,0.001,or_greater,suffix:s"), "set_smooth_time", "get_smooth_time");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_speed", PROPERTY_HINT_RANGE, "0,1000,0.01,or_greater"), "set_max_speed", "get_max_speed");
	ADD_PROPERTY(PropertyInfo(Variant::NIL, "velocity", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NIL_IS_VARIANT | PROPERTY_USAGE_EDITOR), "set_velocity", "get_velocity");
}
