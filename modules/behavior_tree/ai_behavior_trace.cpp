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
	// Save the previous complete tick only when replay was requested. Keep
	// capacity-1 older frames because the current tick occupies one slot.
	if (history_capacity > 1 && tick_index > 0) {
		history_frames.push_back(get_snapshot());
		while (history_frames.size() >= history_capacity) {
			history_frames.remove_at(0);
		}
	}
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

void AIBehaviorTrace::set_history_capacity(int p_capacity) {
	ERR_FAIL_COND_MSG(p_capacity < 0 || p_capacity > 32, "AI trace history capacity must be in [0,32].");
	history_capacity = p_capacity;
	if (history_capacity == 0) {
		history_frames.clear();
	} else {
		while (history_frames.size() >= history_capacity) {
			history_frames.remove_at(0);
		}
	}
}

// A duration change alone does not count as a behavior change. This lets
// tools jump between meaningful decisions instead of CPU timing jitter.
static bool _ai_trace_same_behavior(const Dictionary &p_first, const Dictionary &p_second) {
	if (int(p_first.get("truncated", 0)) != int(p_second.get("truncated", 0))) {
		return false;
	}
	const Array a = p_first.get("steps", Array());
	const Array b = p_second.get("steps", Array());
	if (a.size() != b.size()) {
		return false;
	}
	for (int i = 0; i < a.size(); ++i) {
		const Dictionary first = a[i];
		const Dictionary second = b[i];
		if (first.get("path", String()) != second.get("path", String()) ||
				first.get("task_class", String()) != second.get("task_class", String()) ||
				int(first.get("status", -1)) != int(second.get("status", -1))) {
			return false;
		}
	}
	return true;
}

Array AIBehaviorTrace::get_history_frames(bool p_changes_only) const {
	Array result;
	if (history_capacity == 0) {
		return result;
	}
	Dictionary previous;
	bool have_previous = false;
	// Include up to capacity-1 retained ticks plus the latest in progress.
	for (int i = 0; i < history_frames.size() + (tick_index > 0 ? 1 : 0); ++i) {
		Dictionary frame;
		if (i < history_frames.size()) {
			frame = history_frames[i];
		} else {
			frame = get_snapshot();
		}
		const bool changed = !have_previous || !_ai_trace_same_behavior(previous, frame);
		if (!p_changes_only || changed) {
			Dictionary copy = frame.duplicate(true);
			copy["changed"] = changed;
			result.push_back(copy);
		}
		previous = frame;
		have_previous = true;
	}
	return result;
}

Array AIBehaviorTrace::get_slowest_nodes(int p_limit) const {
	ERR_FAIL_COND_V_MSG(p_limit < 0 || p_limit > 32, Array(), "AI trace slowest-node limit must be in [0,32].");
	Array top;
	for (int i = 0; i < steps.size() && p_limit > 0; ++i) {
		const Dictionary candidate = steps[i];
		if (int(candidate.get("status", -1)) < 0) {
			continue;
		}
		const int64_t inclusive_usec = candidate.get("duration_usec", int64_t(0));
		const String path = candidate.get("path", String());
		const int depth = candidate.get("depth", 0);
		// Inclusive timings are correct for the trace, but tend to show
		// the root as the slowest node. Subtract immediate child spans to
		// approximate the own work of a task and expose actual hot leaves.
		int64_t children_usec = 0;
		for (int j = 0; j < steps.size(); ++j) {
			if (i == j) {
				continue;
			}
			const Dictionary other = steps[j];
			const String other_path = other.get("path", String());
			if (int(other.get("status", -1)) >= 0 &&
					int(other.get("depth", -1)) == depth + 1 &&
					other_path.begins_with(path + "/")) {
				children_usec += int64_t(other.get("duration_usec", int64_t(0)));
			}
		}
		const int64_t self_usec = MAX(int64_t(0), inclusive_usec - children_usec);
		Dictionary record = candidate.duplicate(true);
		record["self_usec"] = self_usec;
		int index = 0;
		for (; index < top.size(); ++index) {
			const Dictionary other = top[index];
			const int64_t other_usec = other.get("self_usec", int64_t(0));
			if (self_usec > other_usec || (self_usec == other_usec && path < String(other.get("path", String())))) {
				break;
			}
		}
		if (index >= p_limit) {
			continue;
		}
		top.insert(index, record);
		if (top.size() > p_limit) {
			top.remove_at(top.size() - 1);
		}
	}
	return top;
}

void AIBehaviorTrace::reset() {
	history_frames.clear();
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
	ClassDB::bind_method(D_METHOD("set_history_capacity", "capacity"), &AIBehaviorTrace::set_history_capacity);
	ClassDB::bind_method(D_METHOD("get_history_capacity"), &AIBehaviorTrace::get_history_capacity);
	ClassDB::bind_method(D_METHOD("get_history_frames", "changes_only"), &AIBehaviorTrace::get_history_frames, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("get_slowest_nodes", "limit"), &AIBehaviorTrace::get_slowest_nodes, DEFVAL(8));
	ClassDB::bind_method(D_METHOD("reset"), &AIBehaviorTrace::reset);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_steps", PROPERTY_HINT_RANGE, "1,256,1"), "set_max_steps", "get_max_steps");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "history_capacity", PROPERTY_HINT_RANGE, "0,32,1"), "set_history_capacity", "get_history_capacity");
}
