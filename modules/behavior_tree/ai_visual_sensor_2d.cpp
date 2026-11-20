/**************************************************************************/
/*  ai_visual_sensor_2d.cpp                                               */
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

#include "ai_visual_sensor_2d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void AIVisualSensor2D::set_sight_radius(real_t p_radius) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_radius) || p_radius <= 0.0, "Sight radius must be positive and finite.");
	sight_radius = p_radius;
	lose_sight_radius = MAX(lose_sight_radius, sight_radius);
}

real_t AIVisualSensor2D::get_sight_radius() const {
	return sight_radius;
}

void AIVisualSensor2D::set_lose_sight_radius(real_t p_radius) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_radius) || p_radius < sight_radius, "Lose-sight radius cannot be smaller than sight radius.");
	lose_sight_radius = p_radius;
}

real_t AIVisualSensor2D::get_lose_sight_radius() const {
	return lose_sight_radius;
}

void AIVisualSensor2D::set_field_of_view_degrees(real_t p_degrees) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_degrees) || p_degrees <= 0.0 || p_degrees > 360.0, "Field of view must be in (0, 360] degrees.");
	field_of_view_degrees = p_degrees;
}

real_t AIVisualSensor2D::get_field_of_view_degrees() const {
	return field_of_view_degrees;
}

void AIVisualSensor2D::set_memory_duration(real_t p_seconds) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_seconds) || p_seconds < 0.0, "Memory duration cannot be negative or non-finite.");
	memory_duration = p_seconds;
	memory_remaining = MIN(memory_remaining, memory_duration);
}

real_t AIVisualSensor2D::get_memory_duration() const {
	return memory_duration;
}

void AIVisualSensor2D::observe(const Vector2 &p_observer, const Vector2 &p_forward, const Vector2 &p_target, bool p_has_line_of_sight, real_t p_delta) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_delta) || p_delta < 0.0, "Perception delta must be nonnegative and finite.");

	const Vector2 to_target = p_target - p_observer;
	const real_t max_radius = target_visible ? lose_sight_radius : sight_radius;
	const bool in_range = to_target.length() <= max_radius;

	bool in_view = field_of_view_degrees >= 360.0;
	if (!in_view) {
		if (to_target.is_zero_approx()) {
			in_view = true;
		} else if (!p_forward.is_zero_approx()) {
			const real_t dot = p_forward.normalized().dot(to_target.normalized());
			in_view = dot >= Math::cos(Math::deg_to_rad(field_of_view_degrees * 0.5));
		}
	}

	target_visible = p_has_line_of_sight && in_range && in_view;
	if (target_visible) {
		last_known_position = p_target;
		memory_remaining = memory_duration;
	} else {
		memory_remaining = MAX(real_t(0.0), memory_remaining - p_delta);
	}
}

bool AIVisualSensor2D::is_target_visible() const {
	return target_visible;
}

bool AIVisualSensor2D::has_target_memory() const {
	return target_visible || memory_remaining > 0.0;
}

Vector2 AIVisualSensor2D::get_last_known_position() const {
	return last_known_position;
}

real_t AIVisualSensor2D::get_memory_remaining() const {
	return memory_remaining;
}

void AIVisualSensor2D::reset() {
	target_visible = false;
	memory_remaining = 0.0;
	last_known_position = Vector2();
}

void AIVisualSensor2D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_sight_radius", "radius"), &AIVisualSensor2D::set_sight_radius);
	ClassDB::bind_method(D_METHOD("get_sight_radius"), &AIVisualSensor2D::get_sight_radius);
	ClassDB::bind_method(D_METHOD("set_lose_sight_radius", "radius"), &AIVisualSensor2D::set_lose_sight_radius);
	ClassDB::bind_method(D_METHOD("get_lose_sight_radius"), &AIVisualSensor2D::get_lose_sight_radius);
	ClassDB::bind_method(D_METHOD("set_field_of_view_degrees", "degrees"), &AIVisualSensor2D::set_field_of_view_degrees);
	ClassDB::bind_method(D_METHOD("get_field_of_view_degrees"), &AIVisualSensor2D::get_field_of_view_degrees);
	ClassDB::bind_method(D_METHOD("set_memory_duration", "seconds"), &AIVisualSensor2D::set_memory_duration);
	ClassDB::bind_method(D_METHOD("get_memory_duration"), &AIVisualSensor2D::get_memory_duration);
	ClassDB::bind_method(D_METHOD("observe", "observer_position", "forward", "target_position", "has_line_of_sight", "delta"), &AIVisualSensor2D::observe);
	ClassDB::bind_method(D_METHOD("is_target_visible"), &AIVisualSensor2D::is_target_visible);
	ClassDB::bind_method(D_METHOD("has_target_memory"), &AIVisualSensor2D::has_target_memory);
	ClassDB::bind_method(D_METHOD("get_last_known_position"), &AIVisualSensor2D::get_last_known_position);
	ClassDB::bind_method(D_METHOD("get_memory_remaining"), &AIVisualSensor2D::get_memory_remaining);
	ClassDB::bind_method(D_METHOD("reset"), &AIVisualSensor2D::reset);

	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "sight_radius", PROPERTY_HINT_RANGE, "0.1,20000,0.1,or_greater"), "set_sight_radius", "get_sight_radius");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "lose_sight_radius", PROPERTY_HINT_RANGE, "0.1,20000,0.1,or_greater"), "set_lose_sight_radius", "get_lose_sight_radius");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "field_of_view_degrees", PROPERTY_HINT_RANGE, "1,360,1"), "set_field_of_view_degrees", "get_field_of_view_degrees");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "memory_duration", PROPERTY_HINT_RANGE, "0,60,0.1,or_greater"), "set_memory_duration", "get_memory_duration");
}
