/**************************************************************************/
/*  ai_hearing_sensor_2d.cpp                                                 */
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

#include "ai_hearing_sensor_2d.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void AIHearingSensor2D::set_hearing_radius(real_t p_radius) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_radius) || p_radius <= 0.0, "Hearing radius must be positive and finite.");
	hearing_radius = p_radius;
}

real_t AIHearingSensor2D::get_hearing_radius() const {
	return hearing_radius;
}

void AIHearingSensor2D::set_memory_duration(real_t p_seconds) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_seconds) || p_seconds < 0.0, "Memory duration must be non-negative and finite.");
	memory_duration = p_seconds;
	memory_remaining = MIN(memory_remaining, memory_duration);
	if (memory_remaining == 0.0) {
		last_heard_strength = 0.0;
	}
}

real_t AIHearingSensor2D::get_memory_duration() const {
	return memory_duration;
}

bool AIHearingSensor2D::report_noise(const Vector2 &p_listener, const Vector2 &p_source, real_t p_loudness, real_t p_occlusion) {
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_loudness) || p_loudness < 0.0, false, "Noise loudness must be non-negative and finite.");
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_occlusion) || p_occlusion < 0.0 || p_occlusion > 1.0, false, "Occlusion must be in [0, 1].");

	if (p_loudness == 0.0 || p_occlusion == 0.0) {
		return false;
	}
	const real_t effective_radius = hearing_radius * p_loudness * p_occlusion;
	if (p_listener.distance_to(p_source) > effective_radius) {
		return false;
	}
	last_heard_position = p_source;
	last_heard_loudness = p_loudness;
	// Legacy mode always takes the latest accepted event, regardless of
	// any previously ranked signal.
	last_heard_strength = 0.0;
	memory_remaining = memory_duration;
	return true;
}

// Perceived relative clarity, not acoustic energy or decibels: a source
// at the listener scores 1 and one at the edge of its allowed range scores 0.
// Selection is deterministic, including equal-strength events in any order.
bool AIHearingSensor2D::report_noise_ranked(const Vector2 &p_listener, const Vector2 &p_source, real_t p_loudness, real_t p_occlusion) {
	ERR_FAIL_COND_V_MSG(!p_listener.is_finite() || !p_source.is_finite(), false, "Listener and noise source positions must be finite.");
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_loudness) || p_loudness < 0.0, false, "Noise loudness must be non-negative and finite.");
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_occlusion) || p_occlusion < 0.0 || p_occlusion > 1.0, false, "Occlusion must be in [0, 1].");
	if (p_loudness == 0.0 || p_occlusion == 0.0) {
		return false;
	}
	const real_t effective_radius = hearing_radius * p_loudness * p_occlusion;
	const real_t distance = p_listener.distance_to(p_source);
	if (!Math::is_finite(effective_radius) || effective_radius <= 0.0 || !Math::is_finite(distance) || distance > effective_radius) {
		return false;
	}
	const real_t strength = MAX(real_t(0.0), real_t(1.0) - distance / effective_radius);
	const bool same_source = p_source == last_heard_position;
	const bool lexicographically_before = p_source.x < last_heard_position.x ||
			(p_source.x == last_heard_position.x && p_source.y < last_heard_position.y);
	if (!has_sound_memory() || strength > last_heard_strength ||
			(strength == last_heard_strength && (same_source || lexicographically_before))) {
		last_heard_position = p_source;
		last_heard_loudness = p_loudness;
		// Zero-duration memories never have a current ranked stimulus.
		last_heard_strength = memory_duration > 0.0 ? strength : real_t(0.0);
		memory_remaining = memory_duration;
	}
	return true;
}

void AIHearingSensor2D::advance_time(real_t p_delta) {
	ERR_FAIL_COND_MSG(!Math::is_finite(p_delta) || p_delta < 0.0, "Hearing delta must be non-negative and finite.");
	memory_remaining = MAX(real_t(0.0), memory_remaining - p_delta);
	if (memory_remaining == 0.0) {
		last_heard_strength = 0.0;
	}
}

bool AIHearingSensor2D::has_sound_memory() const {
	return memory_remaining > 0.0;
}

Vector2 AIHearingSensor2D::get_last_heard_position() const {
	return last_heard_position;
}

real_t AIHearingSensor2D::get_last_heard_loudness() const {
	return last_heard_loudness;
}

real_t AIHearingSensor2D::get_last_heard_strength() const {
	return last_heard_strength;
}

real_t AIHearingSensor2D::get_memory_remaining() const {
	return memory_remaining;
}

void AIHearingSensor2D::reset() {
	memory_remaining = 0.0;
	last_heard_loudness = 0.0;
	last_heard_strength = 0.0;
	last_heard_position = Vector2();
}

void AIHearingSensor2D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_hearing_radius", "radius"), &AIHearingSensor2D::set_hearing_radius);
	ClassDB::bind_method(D_METHOD("get_hearing_radius"), &AIHearingSensor2D::get_hearing_radius);
	ClassDB::bind_method(D_METHOD("set_memory_duration", "seconds"), &AIHearingSensor2D::set_memory_duration);
	ClassDB::bind_method(D_METHOD("get_memory_duration"), &AIHearingSensor2D::get_memory_duration);
	ClassDB::bind_method(D_METHOD("report_noise", "listener_position", "source_position", "loudness", "occlusion"), &AIHearingSensor2D::report_noise, DEFVAL(1.0));
	ClassDB::bind_method(D_METHOD("report_noise_ranked", "listener_position", "source_position", "loudness", "occlusion"), &AIHearingSensor2D::report_noise_ranked, DEFVAL(1.0));
	ClassDB::bind_method(D_METHOD("advance_time", "delta"), &AIHearingSensor2D::advance_time);
	ClassDB::bind_method(D_METHOD("has_sound_memory"), &AIHearingSensor2D::has_sound_memory);
	ClassDB::bind_method(D_METHOD("get_last_heard_position"), &AIHearingSensor2D::get_last_heard_position);
	ClassDB::bind_method(D_METHOD("get_last_heard_loudness"), &AIHearingSensor2D::get_last_heard_loudness);
	ClassDB::bind_method(D_METHOD("get_last_heard_strength"), &AIHearingSensor2D::get_last_heard_strength);
	ClassDB::bind_method(D_METHOD("get_memory_remaining"), &AIHearingSensor2D::get_memory_remaining);
	ClassDB::bind_method(D_METHOD("reset"), &AIHearingSensor2D::reset);

	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "hearing_radius", PROPERTY_HINT_RANGE, "0.1,20000,0.1,or_greater"), "set_hearing_radius", "get_hearing_radius");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "memory_duration", PROPERTY_HINT_RANGE, "0,60,0.1,or_greater"), "set_memory_duration", "get_memory_duration");
}
