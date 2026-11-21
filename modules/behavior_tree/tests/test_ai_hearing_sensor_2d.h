/**************************************************************************/
/*  test_ai_hearing_sensor_2d.h                                                  */
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

#include "../ai_hearing_sensor_2d.h"
#include "tests/test_macros.h"

namespace TestAIHearingSensor2D {

TEST_CASE("[AIHearingSensor2D] Event detection depends on radius and loudness") {
	Ref<AIHearingSensor2D> sensor;
	sensor.instantiate();
	sensor->set_hearing_radius(100.0);
	CHECK(sensor->report_noise(Vector2(), Vector2(90, 0), 1.0));
	CHECK(sensor->get_last_heard_position() == Vector2(90, 0));
	CHECK_FALSE(sensor->report_noise(Vector2(), Vector2(120, 0), 1.0));
	CHECK(sensor->report_noise(Vector2(), Vector2(120, 0), 1.5));
	CHECK(sensor->get_last_heard_loudness() == real_t(1.5));
}

TEST_CASE("[AIHearingSensor2D] Silent events do not create memory") {
	Ref<AIHearingSensor2D> sensor;
	sensor.instantiate();
	CHECK_FALSE(sensor->report_noise(Vector2(), Vector2(10, 0), 0.0));
	CHECK_FALSE(sensor->has_sound_memory());
}

TEST_CASE("[AIHearingSensor2D] Occlusion is controlled by the game") {
	Ref<AIHearingSensor2D> sensor;
	sensor.instantiate();
	sensor->set_hearing_radius(100.0);
	CHECK_FALSE(sensor->report_noise(Vector2(), Vector2(70, 0), 1.0, 0.5));
	CHECK_FALSE(sensor->has_sound_memory());
	CHECK(sensor->report_noise(Vector2(), Vector2(70, 0), 1.0, 0.8));
	CHECK(sensor->has_sound_memory());
	CHECK_FALSE(sensor->report_noise(Vector2(), Vector2(1, 0), 10.0, 0.0));
	CHECK(sensor->get_last_heard_position() == Vector2(70, 0));
}

TEST_CASE("[AIHearingSensor2D] Sound memory expires in seconds") {
	Ref<AIHearingSensor2D> sensor;
	sensor.instantiate();
	sensor->set_memory_duration(2.0);
	REQUIRE(sensor->report_noise(Vector2(), Vector2(20, 0), 1.0));
	CHECK(sensor->has_sound_memory());
	sensor->advance_time(0.75);
	CHECK(sensor->has_sound_memory());
	CHECK(sensor->get_memory_remaining() == real_t(1.25));
	sensor->advance_time(1.25);
	CHECK_FALSE(sensor->has_sound_memory());
	CHECK(sensor->get_memory_remaining() == real_t(0.0));
}

TEST_CASE("[AIHearingSensor2D] Stronger event refreshes position and timer") {
	Ref<AIHearingSensor2D> sensor;
	sensor.instantiate();
	sensor->set_memory_duration(2.0);
	REQUIRE(sensor->report_noise(Vector2(), Vector2(20, 0), 1.0));
	sensor->advance_time(1.5);
	REQUIRE(sensor->report_noise(Vector2(), Vector2(40, 0), 2.0));
	CHECK(sensor->get_last_heard_position() == Vector2(40, 0));
	CHECK(sensor->get_memory_remaining() == real_t(2.0));
}

TEST_CASE("[AIHearingSensor2D] Invalid parameters cannot modify sensor state") {
	Ref<AIHearingSensor2D> sensor;
	sensor.instantiate();
	const real_t radius = sensor->get_hearing_radius();
	const real_t duration = sensor->get_memory_duration();
	ERR_PRINT_OFF;
	sensor->set_hearing_radius(0.0);
	sensor->set_memory_duration(-1.0);
	CHECK_FALSE(sensor->report_noise(Vector2(), Vector2(1, 0), -1.0));
	CHECK_FALSE(sensor->report_noise(Vector2(), Vector2(1, 0), 1.0, -0.1));
	CHECK_FALSE(sensor->report_noise(Vector2(), Vector2(1, 0), 1.0, 1.1));
	sensor->advance_time(-2.0);
	ERR_PRINT_ON;
	CHECK(sensor->get_hearing_radius() == radius);
	CHECK(sensor->get_memory_duration() == duration);
	CHECK_FALSE(sensor->has_sound_memory());
}

TEST_CASE("[AIHearingSensor2D] Sensors keep independent noise memory") {
	Ref<AIHearingSensor2D> one;
	one.instantiate();
	Ref<AIHearingSensor2D> two;
	two.instantiate();
	REQUIRE(one->report_noise(Vector2(), Vector2(50, 0), 1.0));
	CHECK(one->has_sound_memory());
	CHECK_FALSE(two->has_sound_memory());
	CHECK(two->get_last_heard_position() == Vector2());
}

TEST_CASE("[AIHearingSensor2D] Reset clears sound memory") {
	Ref<AIHearingSensor2D> sensor;
	sensor.instantiate();
	REQUIRE(sensor->report_noise(Vector2(), Vector2(60, 0), 1.0));
	sensor->reset();
	CHECK_FALSE(sensor->has_sound_memory());
	CHECK(sensor->get_last_heard_position() == Vector2());
	CHECK(sensor->get_last_heard_loudness() == real_t(0.0));
	CHECK(sensor->get_memory_remaining() == real_t(0.0));
}

TEST_CASE("[AIHearingSensor2D] Zero memory duration does not latch noise") {
	Ref<AIHearingSensor2D> sensor;
	sensor.instantiate();
	sensor->set_memory_duration(0.0);
	CHECK(sensor->report_noise(Vector2(), Vector2(20, 0), 1.0));
	CHECK_FALSE(sensor->has_sound_memory());
}

} // namespace TestAIHearingSensor2D
