/**************************************************************************/
/*  ai_execution_profiler.cpp                                                 */
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

#include "ai_execution_profiler.h"

#include "core/object/class_db.h"
#include "core/os/time.h"

void AIExecutionProfiler::set_enabled(bool p_enabled) {
	enabled = p_enabled;
	if (!enabled) {
		active_starts.clear();
	}
}

bool AIExecutionProfiler::is_enabled() const {
	return enabled;
}

void AIExecutionProfiler::set_budget_usec(int64_t p_budget_usec) {
	ERR_FAIL_COND_MSG(p_budget_usec <= 0 || p_budget_usec > MAX_SAMPLE_USEC, "AI profiling budget must be positive and at most one trillion microseconds.");
	budget_usec = p_budget_usec;
}

int64_t AIExecutionProfiler::get_budget_usec() const {
	return budget_usec;
}

bool AIExecutionProfiler::record_sample(const StringName &p_category, int64_t p_duration_usec) {
	if (!enabled || p_category.is_empty()) {
		return false;
	}
	ERR_FAIL_COND_V_MSG(p_duration_usec < 0 || p_duration_usec > MAX_SAMPLE_USEC, false, "AI profiling sample duration is outside the valid range.");
	ERR_FAIL_COND_V_MSG(!samples.has(p_category) && samples.size() >= MAX_CATEGORIES, false, "Too many named AI profiling categories.");

	Dictionary entry = samples.get(p_category, Dictionary());
	const int64_t count = entry.get("count", int64_t(0));
	const int64_t total = entry.get("total_usec", int64_t(0));
	const int64_t over_budget = entry.get("over_budget", int64_t(0));
	entry["count"] = count + 1;
	entry["total_usec"] = total + p_duration_usec;
	entry["last_usec"] = p_duration_usec;
	entry["min_usec"] = count == 0 ? p_duration_usec : MIN(int64_t(entry["min_usec"]), p_duration_usec);
	entry["max_usec"] = count == 0 ? p_duration_usec : MAX(int64_t(entry["max_usec"]), p_duration_usec);
	entry["mean_usec"] = double(total + p_duration_usec) / double(count + 1);
	entry["over_budget"] = over_budget + (p_duration_usec > budget_usec ? 1 : 0);
	samples[p_category] = entry;
	total_samples++;
	return true;
}

bool AIExecutionProfiler::begin_sample(const StringName &p_category) {
	if (!enabled || p_category.is_empty()) {
		return false;
	}
	ERR_FAIL_COND_V_MSG(active_starts.has(p_category), false, "The same AI profiling category is already active.");
	ERR_FAIL_COND_V_MSG(!samples.has(p_category) && !active_starts.has(p_category) && samples.size() + active_starts.size() >= MAX_CATEGORIES, false, "Too many simultaneous AI profiling categories.");
	active_starts[p_category] = int64_t(Time::get_singleton()->get_ticks_usec());
	return true;
}

int64_t AIExecutionProfiler::end_sample(const StringName &p_category) {
	if (!enabled || !active_starts.has(p_category)) {
		return -1;
	}
	const int64_t start = active_starts[p_category];
	active_starts.erase(p_category);
	const int64_t now = int64_t(Time::get_singleton()->get_ticks_usec());
	const int64_t elapsed = MAX(int64_t(0), now - start);
	return record_sample(p_category, elapsed) ? elapsed : -1;
}

Dictionary AIExecutionProfiler::get_snapshot() const {
	Dictionary snapshot;
	snapshot["enabled"] = enabled;
	snapshot["budget_usec"] = budget_usec;
	snapshot["total_samples"] = total_samples;
	snapshot["categories"] = samples.duplicate(true);
	return snapshot;
}

void AIExecutionProfiler::reset() {
	total_samples = 0;
	samples.clear();
	active_starts.clear();
}

void AIExecutionProfiler::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_enabled", "enabled"), &AIExecutionProfiler::set_enabled);
	ClassDB::bind_method(D_METHOD("is_enabled"), &AIExecutionProfiler::is_enabled);
	ClassDB::bind_method(D_METHOD("set_budget_usec", "budget_usec"), &AIExecutionProfiler::set_budget_usec);
	ClassDB::bind_method(D_METHOD("get_budget_usec"), &AIExecutionProfiler::get_budget_usec);
	ClassDB::bind_method(D_METHOD("record_sample", "category", "duration_usec"), &AIExecutionProfiler::record_sample);
	ClassDB::bind_method(D_METHOD("begin_sample", "category"), &AIExecutionProfiler::begin_sample);
	ClassDB::bind_method(D_METHOD("end_sample", "category"), &AIExecutionProfiler::end_sample);
	ClassDB::bind_method(D_METHOD("get_snapshot"), &AIExecutionProfiler::get_snapshot);
	ClassDB::bind_method(D_METHOD("reset"), &AIExecutionProfiler::reset);

	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enabled"), "set_enabled", "is_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "budget_usec", PROPERTY_HINT_RANGE, "1,1000000,1,or_greater,suffix:us"), "set_budget_usec", "get_budget_usec");
}
