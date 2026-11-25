/**************************************************************************/
/*  cgame_cpu_budget.h                                                    */
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

#include "core/math/math_funcs.h"
#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "core/templates/local_vector.h"

// Unified per-frame CPU budget allocator. Systems register {priority, min_ms, desired_ms};
// allocate() splits the frame budget: minima are guaranteed first (scaled down proportionally if
// they alone exceed the budget), the remainder is shared priority-weighted by water-filling, each
// system capped by its demand. Demand adapts to smoothed measured usage via report_usage().
class CgameCPUBudget : public RefCounted {
	GDCLASS(CgameCPUBudget, RefCounted);

	struct System {
		String name;
		double priority = 1.0;
		double min_ms = 0.0;
		double desired_ms = 0.0;
		double ema = -1.0;
		double last = 0.0;
	};

	LocalVector<System> systems;
	HashMap<String, double> allocation;
	double smoothing = 0.2;
	double headroom = 1.25;

	int _find(const String &p_name) const;
	double _demand(const System &p_system) const;

protected:
	static void _bind_methods();

public:
	void set_smoothing(double p_smoothing) { smoothing = Math::is_finite(p_smoothing) ? CLAMP(p_smoothing, 0.0, 1.0) : 0.2; }
	double get_smoothing() const { return smoothing; }
	void set_headroom(double p_headroom) { headroom = Math::is_finite(p_headroom) ? MAX(p_headroom, 0.0) : 1.0; }
	double get_headroom() const { return headroom; }

	void register_system(const String &p_name, double p_priority, double p_min_ms, double p_desired_ms);
	void unregister_system(const String &p_name);
	int system_count() const { return (int)systems.size(); }
	double demand_ms(const String &p_name) const;
	Dictionary allocate(double p_frame_budget_ms);
	double allocation_ms(const String &p_name) const;
	void report_usage(const String &p_name, double p_ms);
	double smoothed_usage_ms(const String &p_name) const;
	PackedStringArray over_budget() const;
};
