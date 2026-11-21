/**************************************************************************/
/*  test_ai_visual_sensor_2d.h                                                  */
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

#include "../ai_visual_sensor_2d.h"
#include "../behavior_tree.h"
#include "tests/test_macros.h"

namespace TestAIVisualSensor2D {

TEST_CASE("[AIVisualSensor2D] Sight range has hysteresis") {
	Ref<AIVisualSensor2D> sensor;
	sensor.instantiate();
	sensor->set_sight_radius(10.0);
	sensor->set_lose_sight_radius(12.0);
	sensor->set_field_of_view_degrees(360.0);

	sensor->observe(Vector2(), Vector2(1, 0), Vector2(11, 0), true, 0.1);
	CHECK_FALSE(sensor->is_target_visible()); // Acquisition radius is 10.

	sensor->observe(Vector2(), Vector2(1, 0), Vector2(9, 0), true, 0.1);
	CHECK(sensor->is_target_visible());
	sensor->observe(Vector2(), Vector2(1, 0), Vector2(11, 0), true, 0.1);
	CHECK(sensor->is_target_visible()); // Retention radius is 12.

	sensor->observe(Vector2(), Vector2(1, 0), Vector2(13, 0), true, 0.1);
	CHECK_FALSE(sensor->is_target_visible());
	sensor->observe(Vector2(), Vector2(1, 0), Vector2(11, 0), true, 0.1);
	CHECK_FALSE(sensor->is_target_visible()); // Must enter the smaller radius.
}

TEST_CASE("[AIVisualSensor2D] Facing direction and field of view gate detection") {
	Ref<AIVisualSensor2D> sensor;
	sensor.instantiate();
	sensor->set_field_of_view_degrees(90.0);
	sensor->observe(Vector2(), Vector2(1, 0), Vector2(0, 5), true, 0.1);
	CHECK_FALSE(sensor->is_target_visible());
	sensor->observe(Vector2(), Vector2(1, 0), Vector2(5, 0), true, 0.1);
	CHECK(sensor->is_target_visible());
	sensor->observe(Vector2(), Vector2(1, 0), Vector2(-5, 0), true, 0.1);
	CHECK_FALSE(sensor->is_target_visible());
	sensor->reset();
	sensor->observe(Vector2(), Vector2(), Vector2(5, 0), true, 0.1);
	CHECK_FALSE(sensor->is_target_visible()); // Zero facing is not omnidirectional.
	sensor->set_field_of_view_degrees(360.0);
	sensor->observe(Vector2(), Vector2(), Vector2(5, 0), true, 0.1);
	CHECK(sensor->is_target_visible());
}

TEST_CASE("[AIVisualSensor2D] Occlusion removes sight immediately but preserves memory") {
	Ref<AIVisualSensor2D> sensor;
	sensor.instantiate();
	sensor->set_memory_duration(2.0);
	sensor->observe(Vector2(), Vector2(1, 0), Vector2(40, 0), true, 0.5);
	CHECK(sensor->is_target_visible());
	CHECK(sensor->has_target_memory());
	CHECK(sensor->get_last_known_position() == Vector2(40, 0));

	sensor->observe(Vector2(), Vector2(1, 0), Vector2(80, 0), false, 0.5);
	CHECK_FALSE(sensor->is_target_visible());
	CHECK(sensor->has_target_memory());
	CHECK(sensor->get_last_known_position() == Vector2(40, 0));
	CHECK(sensor->get_memory_remaining() == real_t(1.5));
	sensor->observe(Vector2(), Vector2(1, 0), Vector2(100, 0), false, 1.5);
	CHECK_FALSE(sensor->has_target_memory());
	CHECK(sensor->get_memory_remaining() == real_t(0.0));
}

TEST_CASE("[AIVisualSensor2D] Last known position updates only when target is visible") {
	Ref<AIVisualSensor2D> sensor;
	sensor.instantiate();
	CHECK_FALSE(sensor->has_target_memory());
	sensor->observe(Vector2(), Vector2(1, 0), Vector2(20, 0), false, 0.1);
	CHECK_FALSE(sensor->has_target_memory());
	sensor->observe(Vector2(), Vector2(1, 0), Vector2(20, 0), true, 0.1);
	CHECK(sensor->get_last_known_position() == Vector2(20, 0));
	sensor->observe(Vector2(), Vector2(1, 0), Vector2(30, 0), true, 0.1);
	CHECK(sensor->get_last_known_position() == Vector2(30, 0));
	sensor->observe(Vector2(), Vector2(1, 0), Vector2(50, 0), false, 0.1);
	CHECK(sensor->get_last_known_position() == Vector2(30, 0));
}

TEST_CASE("[AIVisualSensor2D] Zero memory duration still reports current visibility") {
	Ref<AIVisualSensor2D> sensor;
	sensor.instantiate();
	sensor->set_memory_duration(0.0);
	sensor->observe(Vector2(), Vector2(1, 0), Vector2(20, 0), true, 0.1);
	CHECK(sensor->is_target_visible());
	CHECK(sensor->has_target_memory());
	sensor->observe(Vector2(), Vector2(1, 0), Vector2(20, 0), false, 0.1);
	CHECK_FALSE(sensor->is_target_visible());
	CHECK_FALSE(sensor->has_target_memory());
}

TEST_CASE("[AIVisualSensor2D] Reset discards visibility and last known position") {
	Ref<AIVisualSensor2D> sensor;
	sensor.instantiate();
	sensor->observe(Vector2(), Vector2(1, 0), Vector2(20, 0), true, 0.1);
	sensor->reset();
	CHECK_FALSE(sensor->is_target_visible());
	CHECK_FALSE(sensor->has_target_memory());
	CHECK(sensor->get_last_known_position() == Vector2());
	CHECK(sensor->get_memory_remaining() == real_t(0.0));
}

TEST_CASE("[AIVisualSensor2D] Invalid configuration leaves previous values intact") {
	Ref<AIVisualSensor2D> sensor;
	sensor.instantiate();
	const real_t sight = sensor->get_sight_radius();
	const real_t lose = sensor->get_lose_sight_radius();
	const real_t fov = sensor->get_field_of_view_degrees();
	const real_t memory = sensor->get_memory_duration();
	ERR_PRINT_OFF;
	sensor->set_sight_radius(-1.0);
	sensor->set_lose_sight_radius(1.0);
	sensor->set_field_of_view_degrees(361.0);
	sensor->set_memory_duration(-0.1);
	sensor->observe(Vector2(), Vector2(1, 0), Vector2(1, 0), true, -1.0);
	ERR_PRINT_ON;
	CHECK(sensor->get_sight_radius() == sight);
	CHECK(sensor->get_lose_sight_radius() == lose);
	CHECK(sensor->get_field_of_view_degrees() == fov);
	CHECK(sensor->get_memory_duration() == memory);
	CHECK_FALSE(sensor->is_target_visible());
}

TEST_CASE("[AIVisualSensor2D] Sensors do not share target memory") {
	Ref<AIVisualSensor2D> a;
	a.instantiate();
	Ref<AIVisualSensor2D> b;
	b.instantiate();
	a->observe(Vector2(), Vector2(1, 0), Vector2(40, 0), true, 0.1);
	CHECK(a->is_target_visible());
	CHECK_FALSE(b->is_target_visible());
	CHECK_FALSE(b->has_target_memory());
}

TEST_CASE("[AIVisualSensor2D] Perception can drive a native reactive behavior tree") {
	Ref<AIVisualSensor2D> sensor;
	sensor.instantiate();
	sensor->set_memory_duration(0.5);
	Ref<BehaviorTree> brain;
	brain.instantiate();

	Dictionary visible;
	visible["type"] = "condition";
	visible["key"] = "visible";
	visible["equals"] = true;
	Dictionary action;
	action["type"] = "set";
	action["key"] = "action";
	action["value"] = "chase";
	Array guarded;
	guarded.push_back(visible);
	guarded.push_back(action);
	Dictionary chase;
	chase["type"] = "reactive_sequence";
	chase["children"] = guarded;

	Dictionary patrol;
	patrol["type"] = "set";
	patrol["key"] = "action";
	patrol["value"] = "patrol";
	Array choices;
	choices.push_back(chase);
	choices.push_back(patrol);
	Dictionary priorities;
	priorities["type"] = "reactive_selector";
	priorities["children"] = choices;
	REQUIRE(brain->set_tree(priorities));

	sensor->observe(Vector2(), Vector2(1, 0), Vector2(20, 0), true, 0.1);
	brain->set_blackboard_value("visible", sensor->is_target_visible());
	CHECK(brain->tick() == BehaviorTree::SUCCESS);
	CHECK(brain->get_blackboard_value("action") == "chase");

	sensor->observe(Vector2(), Vector2(1, 0), Vector2(20, 0), false, 0.1);
	CHECK(sensor->has_target_memory());
	brain->set_blackboard_value("visible", sensor->is_target_visible());
	CHECK(brain->tick() == BehaviorTree::SUCCESS);
	CHECK(brain->get_blackboard_value("action") == "patrol");
}

} // namespace TestAIVisualSensor2D
