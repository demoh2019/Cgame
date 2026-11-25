/**************************************************************************/
/*  cgame_cpu_budget.cpp                                                  */
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

#include "cgame_cpu_budget.h"

#include "core/object/class_db.h"
#include "core/variant/dictionary.h"

int CgameCPUBudget::_find(const String &p_name) const {
	for (uint32_t i = 0; i < systems.size(); i++) {
		if (systems[i].name == p_name) {
			return (int)i;
		}
	}
	return -1;
}

double CgameCPUBudget::_demand(const System &p_system) const {
	if (p_system.ema < 0.0) {
		return p_system.desired_ms;
	}
	return CLAMP(p_system.ema * headroom, p_system.min_ms, p_system.desired_ms);
}

void CgameCPUBudget::register_system(const String &p_name, double p_priority, double p_min_ms, double p_desired_ms) {
	if (p_name.is_empty()) {
		return;
	}
	System s;
	s.name = p_name;
	s.priority = Math::is_finite(p_priority) ? MAX(p_priority, 0.0001) : 0.0001;
	s.min_ms = Math::is_finite(p_min_ms) ? MAX(p_min_ms, 0.0) : 0.0;
	s.desired_ms = Math::is_finite(p_desired_ms) ? MAX(p_desired_ms, s.min_ms) : s.min_ms;
	allocation.erase(p_name);
	const int idx = _find(p_name);
	if (idx >= 0) {
		systems[idx] = s;
	} else {
		systems.push_back(s);
	}
}

void CgameCPUBudget::unregister_system(const String &p_name) {
	const int idx = _find(p_name);
	if (idx >= 0) {
		systems.remove_at(idx);
	}
	allocation.erase(p_name);
}

double CgameCPUBudget::demand_ms(const String &p_name) const {
	const int idx = _find(p_name);
	return idx >= 0 ? _demand(systems[idx]) : 0.0;
}

Dictionary CgameCPUBudget::allocate(double p_frame_budget_ms) {
	p_frame_budget_ms = Math::is_finite(p_frame_budget_ms) ? MAX(p_frame_budget_ms, 0.0) : 0.0;
	Dictionary out;
	allocation.clear();
	double min_sum = 0.0;
	for (const System &s : systems) {
		min_sum += s.min_ms;
	}
	if (min_sum >= p_frame_budget_ms) {
		const double scale = min_sum > 0.0 ? p_frame_budget_ms / min_sum : 0.0;
		for (const System &s : systems) {
			out[s.name] = s.min_ms * scale;
			allocation[s.name] = s.min_ms * scale;
		}
		return out;
	}
	LocalVector<double> given;
	given.resize(systems.size());
	LocalVector<int> open;
	double remaining = p_frame_budget_ms;
	for (uint32_t i = 0; i < systems.size(); i++) {
		given[i] = systems[i].min_ms;
		remaining -= systems[i].min_ms;
		open.push_back((int)i);
	}
	// Water-filling: share what is left by priority; clamp at demand and redistribute.
	while (remaining > 0.000001 && !open.is_empty()) {
		double wsum = 0.0;
		for (int i : open) {
			wsum += systems[i].priority;
		}
		LocalVector<int> next_open;
		double spent = 0.0;
		bool capped = false;
		for (int i : open) {
			const double share = remaining * systems[i].priority / wsum;
			const double room = _demand(systems[i]) - given[i];
			if (share >= room) {
				const double add = MAX(room, 0.0);
				given[i] += add;
				spent += add;
				capped = true;
			} else {
				next_open.push_back(i);
			}
		}
		if (!capped) {
			for (int i : open) {
				given[i] += remaining * systems[i].priority / wsum;
			}
			remaining = 0.0;
			break;
		}
		remaining -= spent;
		open = next_open;
	}
	for (uint32_t i = 0; i < systems.size(); i++) {
		out[systems[i].name] = given[i];
		allocation[systems[i].name] = given[i];
	}
	return out;
}

double CgameCPUBudget::allocation_ms(const String &p_name) const {
	const double *v = allocation.getptr(p_name);
	return v ? *v : 0.0;
}

void CgameCPUBudget::report_usage(const String &p_name, double p_ms) {
	const int idx = _find(p_name);
	if (idx < 0 || !Math::is_finite(p_ms) || p_ms < 0.0) {
		return;
	}
	System &s = systems[idx];
	s.ema = s.ema < 0.0 ? p_ms : Math::lerp(s.ema, p_ms, smoothing);
	s.last = p_ms;
}

double CgameCPUBudget::smoothed_usage_ms(const String &p_name) const {
	const int idx = _find(p_name);
	return idx >= 0 ? MAX(systems[idx].ema, 0.0) : 0.0;
}

// Systems whose smoothed usage exceeds their last allocation, worst overshoot first.
PackedStringArray CgameCPUBudget::over_budget() const {
	struct Row {
		double over;
		String name;
	};
	LocalVector<Row> rows;
	for (const System &s : systems) {
		const double *a = allocation.getptr(s.name);
		if (s.ema < 0.0 || a == nullptr) {
			continue;
		}
		const double over = s.ema - *a;
		if (over > 0.0001) {
			rows.push_back({ over, s.name });
		}
	}
	// Insertion sort keeps equal overshoots in registration order.
	for (uint32_t i = 1; i < rows.size(); i++) {
		Row key = rows[i];
		int j = (int)i - 1;
		while (j >= 0 && rows[j].over < key.over) {
			rows[j + 1] = rows[j];
			j--;
		}
		rows[j + 1] = key;
	}
	PackedStringArray out;
	for (const Row &r : rows) {
		out.push_back(r.name);
	}
	return out;
}

void CgameCPUBudget::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_smoothing", "smoothing"), &CgameCPUBudget::set_smoothing);
	ClassDB::bind_method(D_METHOD("get_smoothing"), &CgameCPUBudget::get_smoothing);
	ClassDB::bind_method(D_METHOD("set_headroom", "headroom"), &CgameCPUBudget::set_headroom);
	ClassDB::bind_method(D_METHOD("get_headroom"), &CgameCPUBudget::get_headroom);
	ClassDB::bind_method(D_METHOD("register_system", "name", "priority", "min_ms", "desired_ms"), &CgameCPUBudget::register_system);
	ClassDB::bind_method(D_METHOD("unregister_system", "name"), &CgameCPUBudget::unregister_system);
	ClassDB::bind_method(D_METHOD("system_count"), &CgameCPUBudget::system_count);
	ClassDB::bind_method(D_METHOD("demand_ms", "name"), &CgameCPUBudget::demand_ms);
	ClassDB::bind_method(D_METHOD("allocate", "frame_budget_ms"), &CgameCPUBudget::allocate);
	ClassDB::bind_method(D_METHOD("allocation_ms", "name"), &CgameCPUBudget::allocation_ms);
	ClassDB::bind_method(D_METHOD("report_usage", "name", "ms"), &CgameCPUBudget::report_usage);
	ClassDB::bind_method(D_METHOD("smoothed_usage_ms", "name"), &CgameCPUBudget::smoothed_usage_ms);
	ClassDB::bind_method(D_METHOD("over_budget"), &CgameCPUBudget::over_budget);

	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "smoothing", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_smoothing", "get_smoothing");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "headroom", PROPERTY_HINT_RANGE, "0,10,0.01,or_greater"), "set_headroom", "get_headroom");
}
