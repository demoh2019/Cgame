/**************************************************************************/
/*  adaptive_tick_governor.cpp                                              */
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

#include "adaptive_tick_governor.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void AdaptiveTickGovernor::_bind_methods() {
	ClassDB::bind_method(D_METHOD("observe_tick", "elapsed_usec", "active_users"), &AdaptiveTickGovernor::observe_tick);
	ClassDB::bind_method(D_METHOD("set_enabled", "enabled"), &AdaptiveTickGovernor::set_enabled);
	ClassDB::bind_method(D_METHOD("is_enabled"), &AdaptiveTickGovernor::is_enabled);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enabled"), "set_enabled", "is_enabled");
	ClassDB::bind_method(D_METHOD("get_budget_units"), &AdaptiveTickGovernor::get_budget_units);
	ClassDB::bind_method(D_METHOD("get_history_count"), &AdaptiveTickGovernor::get_history_count);
	ClassDB::bind_method(D_METHOD("get_total_ticks"), &AdaptiveTickGovernor::get_total_ticks);
	ClassDB::bind_method(D_METHOD("get_last_window_p95_ms"), &AdaptiveTickGovernor::get_last_window_p95_ms);
	ClassDB::bind_method(D_METHOD("set_target_tick_ms", "milliseconds"), &AdaptiveTickGovernor::set_target_tick_ms);
	ClassDB::bind_method(D_METHOD("get_target_tick_ms"), &AdaptiveTickGovernor::get_target_tick_ms);
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "target_tick_ms", PROPERTY_HINT_RANGE, "1,1000,0.1"), "set_target_tick_ms", "get_target_tick_ms");
	ClassDB::bind_method(D_METHOD("set_budget_range", "minimum", "maximum"), &AdaptiveTickGovernor::set_budget_range);
	ClassDB::bind_method(D_METHOD("get_min_budget_units"), &AdaptiveTickGovernor::get_min_budget_units);
	ClassDB::bind_method(D_METHOD("get_max_budget_units"), &AdaptiveTickGovernor::get_max_budget_units);
	ClassDB::bind_method(D_METHOD("samples_oldest_first"), &AdaptiveTickGovernor::samples_oldest_first);
	ClassDB::bind_method(D_METHOD("snapshot"), &AdaptiveTickGovernor::snapshot);
	ClassDB::bind_method(D_METHOD("reset"), &AdaptiveTickGovernor::reset);
}

double AdaptiveTickGovernor::_nearest_rank(const Vector<double> &p_values, double p_percentile) {
	if (p_values.is_empty() || !Math::is_finite(p_percentile)) {
		return 0.0;
	}
	Vector<double> sorted = p_values;
	sorted.sort();
	const int rank = CLAMP(int(Math::ceil(CLAMP(p_percentile, 0.0, 1.0) * double(sorted.size()))) - 1, 0, int(sorted.size()) - 1);
	return sorted[rank];
}

void AdaptiveTickGovernor::_reset_evidence() {
	window.clear();
	high_streak = 0;
	low_streak = 0;
}

void AdaptiveTickGovernor::observe_tick(int64_t p_elapsed_usec, int p_active_users) {
	// Limit to one minute so accidental time-base or clock problems do not
	// corrupt CPU telemetry or make the optional-work budget collapse.
	if (p_elapsed_usec < 0 || p_elapsed_usec > 60000000 || p_active_users < 0) {
		return;
	}
	const double tick_ms = double(p_elapsed_usec) / 1000.0;
	total_ticks++;
	if (history.size() < HISTORY_CAP) {
		history.push_back(tick_ms);
	} else {
		history.set(next_history_slot, tick_ms);
	}
	next_history_slot = (next_history_slot + 1) % HISTORY_CAP;

	if (p_active_users == 0) {
		_reset_evidence();
		return;
	}
	window.push_back(tick_ms);
	if (window.size() < WINDOW_TICKS) {
		return;
	}
	last_window_p95_ms = _nearest_rank(window, 0.95);
	window.clear();
	if (!enabled) {
		return;
	}
	if (last_window_p95_ms > target_tick_ms * HIGH_RATIO) {
		high_streak++;
		low_streak = 0;
	} else if (last_window_p95_ms < target_tick_ms * LOW_RATIO) {
		low_streak++;
		high_streak = 0;
	} else {
		high_streak = 0;
		low_streak = 0;
	}
	if (high_streak >= HIGH_WINDOWS) {
		budget_units = MAX(min_budget_units, budget_units - 2);
		high_streak = 0;
	} else if (low_streak >= LOW_WINDOWS) {
		budget_units = MIN(max_budget_units, budget_units + 1);
		low_streak = 0;
	}
}

void AdaptiveTickGovernor::set_enabled(bool p_enabled) {
	enabled = p_enabled;
	_reset_evidence();
	if (!enabled) {
		budget_units = max_budget_units;
	}
}

void AdaptiveTickGovernor::set_target_tick_ms(double p_target_ms) {
	ERR_FAIL_COND(!Math::is_finite(p_target_ms) || p_target_ms < 1.0 || p_target_ms > 1000.0);
	if (target_tick_ms == p_target_ms) {
		return;
	}
	target_tick_ms = p_target_ms;
	_reset_evidence(); // Do not mix evidence from different tick rates.
}

void AdaptiveTickGovernor::set_budget_range(int p_min_units, int p_max_units) {
	ERR_FAIL_COND(p_min_units < 0 || p_max_units < p_min_units || p_max_units > 1000000);
	min_budget_units = p_min_units;
	max_budget_units = p_max_units;
	budget_units = CLAMP(budget_units, min_budget_units, max_budget_units);
	_reset_evidence();
}

PackedFloat64Array AdaptiveTickGovernor::samples_oldest_first() const {
	PackedFloat64Array ordered;
	const int count = history.size();
	ordered.resize(count);
	const int first = count == HISTORY_CAP ? next_history_slot : 0;
	for (int i = 0; i < count; i++) {
		ordered.set(i, history[(first + i) % count]);
	}
	return ordered;
}

Dictionary AdaptiveTickGovernor::snapshot() const {
	double highest = 0.0;
	for (const double sample : history) {
		highest = MAX(highest, sample);
	}
	Dictionary result;
	result["sample_count"] = history.size();
	result["total_ticks"] = total_ticks;
	result["tick_p95_ms"] = _nearest_rank(history, 0.95);
	result["last_window_p95_ms"] = last_window_p95_ms;
	result["tick_max_ms"] = highest;
	result["incident_spawn_cap"] = budget_units; // Compatibility with Albion After logs.
	result["adaptive_enabled"] = enabled;
	result["native_backend"] = true;
	return result;
}

void AdaptiveTickGovernor::reset() {
	history.clear();
	window.clear();
	next_history_slot = 0;
	high_streak = 0;
	low_streak = 0;
	last_window_p95_ms = 0.0;
	total_ticks = 0;
	budget_units = max_budget_units;
}
