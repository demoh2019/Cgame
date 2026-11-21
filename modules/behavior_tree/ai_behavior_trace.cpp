/**************************************************************************/
/*  ai_behavior_trace.h                                                 */
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

#include "ai_behavior_trace.h"

#include "core/object/class_db.h"
#include "core/os/time.h"

void AIBehaviorTrace::set_max_steps(int p_max_steps) {
	ERR_FAIL_COND_MSG(p_max_steps < 1 || p_max_steps > 256, "AI execution trace capacity must be in [1, 256].");
	max_steps = p_max_steps;
	// Changing limits clears a partially recorded tick, not external state.
	reset();
}

void AIBehaviorTrace::begin_tick() {
	steps.clear();
	started_usec.clear();
	completed.clear();
	truncated = 0;
	tick_index++;
}

int AIBehaviorTrace::begin_step(const String &p_path, const String &p_task_class) {
	ERR_FAIL_COND_V_MSG(p_path.is_empty() || p_path.length() > 256 || p_task_class.is_empty() || p_task_class.length() > 128, -1, "AI trace path and task class must be nonempty and bounded.");
	if (steps.size() >= max_steps) {
		truncated++;
		return -1;
	}
	Dictionary event;
	event["path"] = p_path;
	event["task_class"] = p_task_class;
	event["depth"] = p_path.count("/");
	event["status"] = -1; // Active until matching end_step().
	event["duration_usec"] = int64_t(0);
	steps.push_back(event);
	started_usec.push_back(int64_t(Time::get_singleton()->get_ticks_usec()));
	completed.push_back(0);
	return steps.size() - 1;
}

bool AIBehaviorTrace::end_step(int p_token, int p_status) {
	ERR_FAIL_COND_V_MSG(p_status < 0 || p_status > 2, false, "AI trace task status must be SUCCESS, FAILURE or RUNNING.");
	if (p_token < 0 || p_token >= steps.size() || completed[p_token]) {
		return false;
	}
	const int64_t elapsed = MAX(int64_t(0), int64_t(Time::get_singleton()->get_ticks_usec()) - started_usec[p_token]);
	Dictionary event = steps[p_token];
	event["status"] = p_status;
	event["duration_usec"] = elapsed;
	steps[p_token] = event;
	completed.write[p_token] = 1;
	return true;
}

Dictionary AIBehaviorTrace::get_snapshot() const {
	Dictionary out;
	out["tick_index"] = tick_index;
	out["max_steps"] = max_steps;
	out["truncated"] = truncated;
	out["steps"] = steps.duplicate(true);
	return out;
}

void AIBehaviorTrace::reset() {
	steps.clear();
	started_usec.clear();
	completed.clear();
	truncated = 0;
	tick_index = 0;
}

void AIBehaviorTrace::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_max_steps", "max_steps"), &AIBehaviorTrace::set_max_steps);
	ClassDB::bind_method(D_METHOD("get_max_steps"), &AIBehaviorTrace::get_max_steps);
	ClassDB::bind_method(D_METHOD("begin_tick"), &AIBehaviorTrace::begin_tick);
	ClassDB::bind_method(D_METHOD("begin_step", "path", "task_class"), &AIBehaviorTrace::begin_step);
	ClassDB::bind_method(D_METHOD("end_step", "token", "status"), &AIBehaviorTrace::end_step);
	ClassDB::bind_method(D_METHOD("get_snapshot"), &AIBehaviorTrace::get_snapshot);
	ClassDB::bind_method(D_METHOD("reset"), &AIBehaviorTrace::reset);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_steps", PROPERTY_HINT_RANGE, "1,256,1"), "set_max_steps", "get_max_steps");
}
