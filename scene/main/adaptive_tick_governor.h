/**************************************************************************/
/*  adaptive_tick_governor.h                                              */
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

#include "core/object/ref_counted.h"
#include "core/templates/vector.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// Bounded CPU-tick telemetry and hysteretic backpressure for optional work.
// Uses measured tick durations, never skips mandatory simulation work.
// No server/gameplay/scene dependencies: budget_units is a caller-owned hint.
class AdaptiveTickGovernor : public RefCounted {
	GDCLASS(AdaptiveTickGovernor, RefCounted);

	static constexpr int HISTORY_CAP = 200;
	static constexpr int WINDOW_TICKS = 20;
	static constexpr double HIGH_RATIO = 0.90;
	static constexpr double LOW_RATIO = 0.60;
	static constexpr int HIGH_WINDOWS = 3;
	static constexpr int LOW_WINDOWS = 5;

	Vector<double> history;
	Vector<double> window;
	int next_history_slot = 0;
	int high_streak = 0;
	int low_streak = 0;
	int min_budget_units = 2;
	int max_budget_units = 10;
	int budget_units = 10;
	double target_tick_ms = 50.0;
	double last_window_p95_ms = 0.0;
	int64_t total_ticks = 0;
	bool enabled = true;

	static double _nearest_rank(const Vector<double> &p_values, double p_percentile);
	void _reset_evidence();

protected:
	static void _bind_methods();

public:
	void observe_tick(int64_t p_elapsed_usec, int p_active_users);
	void set_enabled(bool p_enabled);
	bool is_enabled() const { return enabled; }
	int get_budget_units() const { return budget_units; }
	int get_history_count() const { return history.size(); }
	int64_t get_total_ticks() const { return total_ticks; }
	double get_last_window_p95_ms() const { return last_window_p95_ms; }
	void set_target_tick_ms(double p_target_ms);
	double get_target_tick_ms() const { return target_tick_ms; }
	void set_budget_range(int p_min_units, int p_max_units);
	int get_min_budget_units() const { return min_budget_units; }
	int get_max_budget_units() const { return max_budget_units; }
	PackedFloat64Array samples_oldest_first() const;
	Dictionary snapshot() const;
	void reset();
};
