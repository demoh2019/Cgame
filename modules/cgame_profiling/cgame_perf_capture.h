/**************************************************************************/
/*  cgame_perf_capture.h                                                  */
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
#include "core/variant/dictionary.h"
#include "core/variant/typed_array.h"

// Versioned performance capture (".cgperf"): one dictionary bundling frame timings, trace events,
// counters, memory samples, streaming events, network packets and environment info, stored as
// binary variant (default) or JSON. Also provides noise-aware run comparison, per-subsystem
// regression comparison and a soak-test leak detector. All methods are static.
class CgamePerfCapture : public RefCounted {
	GDCLASS(CgamePerfCapture, RefCounted);

public:
	static constexpr int VERSION = 1;
	static constexpr double DEFAULT_THRESHOLD_PCT = 10.0;

private:
	static Dictionary _frame_stats_from_capture(const Dictionary &p_capture);
	static PackedFloat64Array _metric_values(const Dictionary &p_run, const String &p_metric);

protected:
	static void _bind_methods();

public:
	static Dictionary new_capture(const String &p_label = "");
	static Dictionary capture_environment();
	static Dictionary capture_from_trace(const String &p_label = "");
	static void add_frame(Dictionary p_capture, int64_t p_index, double p_ms, const Dictionary &p_scopes = Dictionary(), const Dictionary &p_counters = Dictionary());
	static void add_event(Dictionary p_capture, const String &p_section, const Dictionary &p_event);
	static PackedStringArray validate(const Dictionary &p_capture);
	static bool write(const String &p_path, const Dictionary &p_capture, bool p_as_json = false);
	static Dictionary read(const String &p_path);
	static Dictionary merge(const Dictionary &p_base, const Dictionary &p_extra);
	static PackedFloat32Array frame_times(const Dictionary &p_capture);

	static Dictionary compare_runs(const Dictionary &p_baseline, const Dictionary &p_current, const Dictionary &p_thresholds = Dictionary());
	static Array compare_subsystems(const Dictionary &p_baseline_capture, const Dictionary &p_current_capture, double p_threshold_pct = 10.0);
	static Dictionary memory_leak_trend(const PackedFloat32Array &p_samples, double p_min_growth_pct = 5.0, double p_min_r2 = 0.8);
	static Dictionary load_json(const String &p_path);
	static bool save_json(const String &p_path, const Dictionary &p_data);
};
