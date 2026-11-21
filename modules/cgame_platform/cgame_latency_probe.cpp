/**************************************************************************/
/*  cgame_latency_probe.cpp                                               */
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

#include "cgame_latency_probe.h"

#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/os/os.h"
#include "servers/display/display_server.h"

static double _resolve_refresh_hz(double p_refresh_hz) {
	double hz = p_refresh_hz;
	if (hz < 0.0) {
		DisplayServer *ds = DisplayServer::get_singleton();
		hz = ds ? (double)ds->screen_get_refresh_rate() : 0.0;
	}
	return hz;
}

int CgameLatencyProbe::mark_input(int64_t p_now_us) {
	const int64_t now = p_now_us >= 0 ? p_now_us : (int64_t)OS::get_singleton()->get_ticks_usec();
	if ((double)(now - last_input_us) < min_gap_ms * 1000.0) {
		return -1;
	}
	last_input_us = now;
	Dictionary s;
	s["mode"] = mode;
	s["input_us"] = now;
	s["draw_us"] = (int64_t)-1;
	s["photodiode_us"] = (int64_t)-1;
	samples.push_back(s);
	pending.push_back(samples.size() - 1);
	flash_left = flash_frames;
	return samples.size() - 1;
}

int CgameLatencyProbe::mark_draw(int64_t p_now_us) {
	const int64_t now = p_now_us >= 0 ? p_now_us : (int64_t)OS::get_singleton()->get_ticks_usec();
	const int completed = pending.size();
	for (int i = 0; i < pending.size(); i++) {
		Dictionary s = samples[pending[i]];
		s["draw_us"] = now;
		emit_signal(SNAME("sample_completed"), s);
	}
	pending.clear();
	if (flash_left > 0) {
		flash_left--;
	}
	return completed;
}

void CgameLatencyProbe::clear() {
	samples.clear();
	pending.clear();
	flash_left = 0;
	last_input_us = -1000000000;
}

int CgameLatencyProbe::import_photodiode_csv(const String &p_path, int64_t p_clock_offset_us) {
	if (!FileAccess::exists(p_path)) {
		return 0;
	}
	PackedInt64Array edges;
	const Vector<String> lines = FileAccess::get_file_as_string(p_path).split("\n", false);
	for (const String &line : lines) {
		const String s = line.strip_edges();
		if (s.is_valid_int()) {
			edges.push_back(s.to_int());
		}
	}
	return pair_photodiode(samples, edges, p_clock_offset_us);
}

double CgameLatencyProbe::estimate_display_ms(double p_refresh_hz) const {
	double hz = _resolve_refresh_hz(p_refresh_hz);
	if (hz <= 0.0) {
		hz = 60.0;
	}
	return 500.0 / hz + display_offset_ms;
}

Dictionary CgameLatencyProbe::report(double p_refresh_hz) const {
	Dictionary rep = summarize(samples, estimate_display_ms(p_refresh_hz));
	rep["refresh_hz"] = _resolve_refresh_hz(p_refresh_hz);
	rep["display_offset_ms"] = display_offset_ms;
	return rep;
}

bool CgameLatencyProbe::save_report(const String &p_path, double p_refresh_hz) const {
	Ref<FileAccess> f = FileAccess::open(p_path, FileAccess::WRITE);
	if (f.is_null()) {
		return false;
	}
	f->store_string(JSON::stringify(report(p_refresh_hz), "\t"));
	return true;
}

double CgameLatencyProbe::latency_ms(const Dictionary &p_sample, double p_display_ms) {
	const int64_t input_us = p_sample.get("input_us", (int64_t)-1);
	if (input_us < 0) {
		return -1.0;
	}
	const int64_t pd = p_sample.get("photodiode_us", (int64_t)-1);
	if (pd >= 0) {
		return (double)(pd - input_us) / 1000.0;
	}
	const int64_t draw = p_sample.get("draw_us", (int64_t)-1);
	if (draw < 0) {
		return -1.0;
	}
	return (double)(draw - input_us) / 1000.0 + p_display_ms;
}

double CgameLatencyProbe::percentile(const PackedFloat64Array &p_sorted, double p_percent) {
	const int n = p_sorted.size();
	if (n == 0) {
		return 0.0;
	}
	if (n == 1) {
		return p_sorted[0];
	}
	const double pos = CLAMP(p_percent, 0.0, 100.0) / 100.0 * (double)(n - 1);
	const int lo = (int)Math::floor(pos);
	const int hi = MIN(lo + 1, n - 1);
	return Math::lerp(p_sorted[lo], p_sorted[hi], pos - (double)lo);
}

Dictionary CgameLatencyProbe::summarize(const Array &p_samples, double p_display_ms) {
	HashMap<String, Vector<double>> by_mode;
	HashMap<String, int> pd_count;
	Vector<String> order;
	for (int i = 0; i < p_samples.size(); i++) {
		const Dictionary s = p_samples[i];
		const double ms = latency_ms(s, p_display_ms);
		if (ms < 0.0) {
			continue;
		}
		const String m = s.get("mode", "normal");
		if (!by_mode.has(m)) {
			by_mode.insert(m, Vector<double>());
			pd_count.insert(m, 0);
			order.push_back(m);
		}
		by_mode[m].push_back(ms);
		const int64_t pd = s.get("photodiode_us", (int64_t)-1);
		if (pd >= 0) {
			pd_count[m] += 1;
		}
	}
	Dictionary out;
	for (const String &m : order) {
		Vector<double> a = by_mode[m];
		a.sort();
		PackedFloat64Array sorted;
		sorted.append_array(a);
		double total = 0.0;
		for (int i = 0; i < a.size(); i++) {
			total += a[i];
		}
		const double avg = total / (double)a.size();
		double var_sum = 0.0;
		for (int i = 0; i < a.size(); i++) {
			var_sum += (a[i] - avg) * (a[i] - avg);
		}
		String src = "software";
		if (pd_count[m] == a.size()) {
			src = "photodiode";
		} else if (pd_count[m] > 0) {
			src = "mixed";
		}
		Dictionary st;
		st["count"] = a.size();
		st["min"] = a[0];
		st["avg"] = avg;
		st["p50"] = percentile(sorted, 50.0);
		st["p90"] = percentile(sorted, 90.0);
		st["p95"] = percentile(sorted, 95.0);
		st["p99"] = percentile(sorted, 99.0);
		st["max"] = a[a.size() - 1];
		st["jitter"] = Math::sqrt(var_sum / (double)a.size());
		st["source"] = src;
		out[m] = st;
	}
	return out;
}

int CgameLatencyProbe::pair_photodiode(const Array &p_samples, const PackedInt64Array &p_edges_us, int64_t p_clock_offset_us, int64_t p_max_gap_us) {
	int paired = 0;
	for (int e = 0; e < p_edges_us.size(); e++) {
		const int64_t t = p_edges_us[e] + p_clock_offset_us;
		int best = -1;
		int64_t best_input = 0;
		for (int i = 0; i < p_samples.size(); i++) {
			const Dictionary s = p_samples[i];
			if ((int64_t)s.get("photodiode_us", (int64_t)-1) >= 0) {
				continue;
			}
			const int64_t in_us = s.get("input_us", (int64_t)-1);
			if (in_us <= t && t - in_us <= p_max_gap_us) {
				if (best < 0 || in_us > best_input) {
					best = i;
					best_input = in_us;
				}
			}
		}
		if (best >= 0) {
			Dictionary s = p_samples[best];
			s["photodiode_us"] = t;
			paired++;
		}
	}
	return paired;
}

void CgameLatencyProbe::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_mode", "mode"), &CgameLatencyProbe::set_mode);
	ClassDB::bind_method(D_METHOD("get_mode"), &CgameLatencyProbe::get_mode);
	ClassDB::bind_method(D_METHOD("set_flash_frames", "frames"), &CgameLatencyProbe::set_flash_frames);
	ClassDB::bind_method(D_METHOD("get_flash_frames"), &CgameLatencyProbe::get_flash_frames);
	ClassDB::bind_method(D_METHOD("set_min_gap_ms", "ms"), &CgameLatencyProbe::set_min_gap_ms);
	ClassDB::bind_method(D_METHOD("get_min_gap_ms"), &CgameLatencyProbe::get_min_gap_ms);
	ClassDB::bind_method(D_METHOD("set_display_offset_ms", "ms"), &CgameLatencyProbe::set_display_offset_ms);
	ClassDB::bind_method(D_METHOD("get_display_offset_ms"), &CgameLatencyProbe::get_display_offset_ms);
	ClassDB::bind_method(D_METHOD("set_capture_enabled", "enabled"), &CgameLatencyProbe::set_capture_enabled);
	ClassDB::bind_method(D_METHOD("is_capture_enabled"), &CgameLatencyProbe::is_capture_enabled);
	ClassDB::bind_method(D_METHOD("get_samples"), &CgameLatencyProbe::get_samples);

	ClassDB::bind_method(D_METHOD("mark_input", "now_us"), &CgameLatencyProbe::mark_input, DEFVAL((int64_t)-1));
	ClassDB::bind_method(D_METHOD("mark_draw", "now_us"), &CgameLatencyProbe::mark_draw, DEFVAL((int64_t)-1));
	ClassDB::bind_method(D_METHOD("is_flash_on"), &CgameLatencyProbe::is_flash_on);
	ClassDB::bind_method(D_METHOD("get_pending_count"), &CgameLatencyProbe::get_pending_count);
	ClassDB::bind_method(D_METHOD("clear"), &CgameLatencyProbe::clear);
	ClassDB::bind_method(D_METHOD("import_photodiode_csv", "path", "clock_offset_us"), &CgameLatencyProbe::import_photodiode_csv, DEFVAL((int64_t)0));
	ClassDB::bind_method(D_METHOD("report", "refresh_hz"), &CgameLatencyProbe::report, DEFVAL(-1.0));
	ClassDB::bind_method(D_METHOD("estimate_display_ms", "refresh_hz"), &CgameLatencyProbe::estimate_display_ms, DEFVAL(-1.0));
	ClassDB::bind_method(D_METHOD("save_report", "path", "refresh_hz"), &CgameLatencyProbe::save_report, DEFVAL(-1.0));

	ClassDB::bind_static_method("CgameLatencyProbe", D_METHOD("latency_ms", "sample", "display_ms"), &CgameLatencyProbe::latency_ms);
	ClassDB::bind_static_method("CgameLatencyProbe", D_METHOD("percentile", "sorted_values", "percent"), &CgameLatencyProbe::percentile);
	ClassDB::bind_static_method("CgameLatencyProbe", D_METHOD("summarize", "samples", "display_ms"), &CgameLatencyProbe::summarize);
	ClassDB::bind_static_method("CgameLatencyProbe", D_METHOD("pair_photodiode", "samples", "edges_us", "clock_offset_us", "max_gap_us"), &CgameLatencyProbe::pair_photodiode, DEFVAL((int64_t)0), DEFVAL((int64_t)DEFAULT_MAX_GAP_US));

	ADD_PROPERTY(PropertyInfo(Variant::STRING, "mode"), "set_mode", "get_mode");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "flash_frames", PROPERTY_HINT_RANGE, "1,60,1"), "set_flash_frames", "get_flash_frames");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_gap_ms", PROPERTY_HINT_RANGE, "0,10000,0.1,or_greater,suffix:ms"), "set_min_gap_ms", "get_min_gap_ms");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "display_offset_ms", PROPERTY_HINT_RANGE, "0,200,0.1,or_greater,suffix:ms"), "set_display_offset_ms", "get_display_offset_ms");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "capture_enabled"), "set_capture_enabled", "is_capture_enabled");

	ADD_SIGNAL(MethodInfo("sample_completed", PropertyInfo(Variant::DICTIONARY, "sample")));
}
