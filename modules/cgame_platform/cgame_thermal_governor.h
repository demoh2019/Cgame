/**************************************************************************/
/*  cgame_thermal_governor.h                                              */
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

// Thermal / battery governor for phones and laptops. Feed it frame times (and optionally battery readings); it
// outputs an FPS cap and how many quality levels to step down. Hysteresis: stepping down needs sustained slow
// frames, stepping back up needs a longer run of headroom.
class CgameThermalGovernor : public RefCounted {
	GDCLASS(CgameThermalGovernor, RefCounted);

public:
	static constexpr double EVAL_INTERVAL_S = 1.0;
	static constexpr int WINDOW_FRAMES = 180;
	static constexpr double SLOW_RATIO = 1.15;
	static constexpr double FAST_RATIO = 0.70;
	static constexpr double STEP_DOWN_AFTER_S = 3.0;
	static constexpr double STEP_UP_AFTER_S = 12.0;
	static constexpr int MAX_STEPS = 3;
	static constexpr double LOW_BATTERY_PCT = 20.0;

private:
	int target_fps = 60;
	int step = 0;
	Vector<float> frames;
	double last_eval_s = -1.0;
	double slow_s = 0.0;
	double fast_s = 0.0;
	Vector<Vector2> battery_samples; // (time_s, percent) while discharging.
	bool on_battery = false;
	double battery_pct = -1.0;

	static double _mean(const Vector<float> &p_values, int p_from, int p_to);
	bool _evaluate(double p_elapsed);
	bool _battery_is_low() const;

protected:
	static void _bind_methods();

public:
	void configure(int p_target_fps);
	int get_target_fps() const { return target_fps; }
	static Dictionary read_system_battery();
	double budget_ms() const;

	bool sample_frame(double p_frame_ms, double p_now_s);
	void record_battery(double p_now_s, double p_percent, bool p_charging);
	double drain_per_hour() const;
	double hours_remaining() const;
	int fps_cap() const;
	int quality_step() const { return step; }
	int apply_to(int p_base_level) const;
	void reset();
};
