/**************************************************************************/
/*  cgame_thermal_governor.cpp                                            */
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

#include "cgame_thermal_governor.h"

#include "core/object/class_db.h"
#include "core/variant/dictionary.h"

void CgameThermalGovernor::configure(int p_target_fps) {
	target_fps = MAX(p_target_fps, 1);
}

Dictionary CgameThermalGovernor::read_system_battery() {
	// The engine exposes no battery API, so battery percent is an input (see record_battery()).
	Dictionary d;
	d["available"] = false;
	d["percent"] = -1.0;
	d["charging"] = false;
	return d;
}

double CgameThermalGovernor::budget_ms() const {
	return 1000.0 / (double)target_fps;
}

double CgameThermalGovernor::_mean(const Vector<float> &p_values, int p_from, int p_to) {
	if (p_to <= p_from) {
		return 0.0;
	}
	double s = 0.0;
	for (int i = p_from; i < p_to; i++) {
		s += p_values[i];
	}
	return s / (double)(p_to - p_from);
}

bool CgameThermalGovernor::_battery_is_low() const {
	return on_battery && battery_pct >= 0.0 && battery_pct < LOW_BATTERY_PCT;
}

bool CgameThermalGovernor::sample_frame(double p_frame_ms, double p_now_s) {
	frames.push_back((float)p_frame_ms);
	if (frames.size() > WINDOW_FRAMES) {
		frames.remove_at(0);
	}
	if (last_eval_s < 0.0) {
		last_eval_s = p_now_s;
		return false;
	}
	const double elapsed = p_now_s - last_eval_s;
	if (elapsed < EVAL_INTERVAL_S) {
		return false;
	}
	last_eval_s = p_now_s;
	return _evaluate(elapsed);
}

bool CgameThermalGovernor::_evaluate(double p_elapsed) {
	const double avg = _mean(frames, 0, frames.size());
	const int half = frames.size() / 2;
	bool rising = false;
	if (half >= 8) {
		const double first = _mean(frames, 0, half);
		const double second = _mean(frames, half, frames.size());
		rising = second > first * 1.2;
	}
	const double budget = budget_ms();
	const double slow_limit = budget * (SLOW_RATIO - (rising ? 0.08 : 0.0));
	const int before = step;
	if (avg > slow_limit) {
		slow_s += p_elapsed;
		fast_s = 0.0;
		if (slow_s >= STEP_DOWN_AFTER_S && step < MAX_STEPS) {
			step++;
			slow_s = 0.0;
		}
	} else if (avg < budget * FAST_RATIO) {
		fast_s += p_elapsed;
		slow_s = 0.0;
		if (fast_s >= STEP_UP_AFTER_S && step > 0) {
			step--;
			fast_s = 0.0;
		}
	} else {
		// Dead band: neither slow nor clearly fast, hold the current step.
		slow_s = MAX(slow_s - p_elapsed, 0.0);
		fast_s = MAX(fast_s - p_elapsed, 0.0);
	}
	return step != before;
}

void CgameThermalGovernor::record_battery(double p_now_s, double p_percent, bool p_charging) {
	battery_pct = p_percent;
	on_battery = !p_charging;
	if (p_charging) {
		battery_samples.clear();
		return;
	}
	battery_samples.push_back(Vector2((real_t)p_now_s, (real_t)p_percent));
	if (battery_samples.size() > 600) {
		battery_samples.remove_at(0);
	}
}

double CgameThermalGovernor::drain_per_hour() const {
	const int n = battery_samples.size();
	if (n < 2) {
		return -1.0;
	}
	const double span = battery_samples[n - 1].x - battery_samples[0].x;
	if (span < 1.0) {
		return -1.0;
	}
	double mx = 0.0;
	double my = 0.0;
	for (int i = 0; i < n; i++) {
		mx += battery_samples[i].x;
		my += battery_samples[i].y;
	}
	mx /= (double)n;
	my /= (double)n;
	double num = 0.0;
	double den = 0.0;
	for (int i = 0; i < n; i++) {
		const double dx = battery_samples[i].x - mx;
		num += dx * (battery_samples[i].y - my);
		den += dx * dx;
	}
	if (den <= 0.0) {
		return -1.0;
	}
	return MAX(-num / den * 3600.0, 0.0);
}

double CgameThermalGovernor::hours_remaining() const {
	const double drain = drain_per_hour();
	if (drain <= 0.0 || battery_pct < 0.0) {
		return -1.0;
	}
	return battery_pct / drain;
}

int CgameThermalGovernor::fps_cap() const {
	int cap = target_fps;
	if (step >= MAX_STEPS) {
		cap = MIN(cap, 30);
	}
	if (_battery_is_low()) {
		cap = MIN(cap, 30);
	}
	return cap;
}

int CgameThermalGovernor::apply_to(int p_base_level) const {
	int lv = p_base_level - step;
	if (_battery_is_low()) {
		lv -= 1;
	}
	return CLAMP(lv, 0, 3);
}

void CgameThermalGovernor::reset() {
	step = 0;
	frames.clear();
	last_eval_s = -1.0;
	slow_s = 0.0;
	fast_s = 0.0;
	battery_samples.clear();
	on_battery = false;
	battery_pct = -1.0;
}

void CgameThermalGovernor::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "target_fps"), &CgameThermalGovernor::configure);
	ClassDB::bind_method(D_METHOD("get_target_fps"), &CgameThermalGovernor::get_target_fps);
	ClassDB::bind_static_method("CgameThermalGovernor", D_METHOD("read_system_battery"), &CgameThermalGovernor::read_system_battery);
	ClassDB::bind_method(D_METHOD("budget_ms"), &CgameThermalGovernor::budget_ms);
	ClassDB::bind_method(D_METHOD("sample_frame", "frame_ms", "now_s"), &CgameThermalGovernor::sample_frame);
	ClassDB::bind_method(D_METHOD("record_battery", "now_s", "percent", "charging"), &CgameThermalGovernor::record_battery);
	ClassDB::bind_method(D_METHOD("drain_per_hour"), &CgameThermalGovernor::drain_per_hour);
	ClassDB::bind_method(D_METHOD("hours_remaining"), &CgameThermalGovernor::hours_remaining);
	ClassDB::bind_method(D_METHOD("fps_cap"), &CgameThermalGovernor::fps_cap);
	ClassDB::bind_method(D_METHOD("quality_step"), &CgameThermalGovernor::quality_step);
	ClassDB::bind_method(D_METHOD("apply_to", "base_level"), &CgameThermalGovernor::apply_to);
	ClassDB::bind_method(D_METHOD("reset"), &CgameThermalGovernor::reset);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "target_fps", PROPERTY_HINT_RANGE, "1,1000,1"), "configure", "get_target_fps");

	BIND_CONSTANT(MAX_STEPS);
	BIND_CONSTANT(WINDOW_FRAMES);
}
