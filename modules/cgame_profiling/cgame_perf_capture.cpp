/**************************************************************************/
/*  cgame_perf_capture.cpp                                                */
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

#include "cgame_perf_capture.h"

#include "cgame_trace.h"

#include "core/config/engine.h"
#include "core/config/project_settings.h"
#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/io/marshalls.h"
#include "core/object/class_db.h"
#include "core/os/os.h"
#include "core/templates/local_vector.h"
#include "servers/rendering/rendering_server.h"

namespace {

const char *const MAGIC = "cgperf";
const char *const ARRAY_SECTIONS[] = {
	"frames", "trace_events", "counters", "memory_samples", "streaming_events", "network_packets"
};
constexpr int ARRAY_SECTION_COUNT = 6;
const char *const METRICS[] = {
	"frame_time_p50", "frame_time_p95", "frame_time_p99", "memory_peak", "draw_calls", "shader_compiles"
};
constexpr int METRIC_COUNT = 6;

bool is_number(const Variant &p_value) {
	return p_value.get_type() == Variant::INT || p_value.get_type() == Variant::FLOAT;
}

double median_of(const PackedFloat64Array &p_values) {
	PackedFloat64Array s = p_values;
	s.sort();
	const int n = s.size();
	if (n == 0) {
		return 0.0;
	}
	if (n % 2 == 1) {
		return s[n >> 1];
	}
	return (s[(n >> 1) - 1] + s[n >> 1]) * 0.5;
}

double spread_of(const PackedFloat64Array &p_values) {
	if (p_values.size() < 2) {
		return 0.0;
	}
	double lo = p_values[0];
	double hi = p_values[0];
	for (double x : p_values) {
		lo = MIN(lo, x);
		hi = MAX(hi, x);
	}
	return hi - lo;
}

struct FrameIndexOrder {
	_FORCE_INLINE_ bool operator()(const Variant &p_a, const Variant &p_b) const {
		const Dictionary a = p_a;
		const Dictionary b = p_b;
		return (int64_t)a.get("index", 0) < (int64_t)b.get("index", 0);
	}
};

} // namespace

Dictionary CgamePerfCapture::capture_environment() {
	Dictionary env;
	env["engine"] = Engine::get_singleton()->get_version_info().get("string", "unknown");
	env["os"] = OS::get_singleton()->get_name();
	env["processor"] = OS::get_singleton()->get_processor_name();
	env["cores"] = OS::get_singleton()->get_processor_count();
	RenderingServer *rs = RenderingServer::get_singleton();
	env["video_adapter"] = rs ? rs->get_video_adapter_name() : String();
	env["rendering_method"] = ProjectSettings::get_singleton() ? String(GLOBAL_GET("rendering/renderer/rendering_method")) : String("unknown");
#ifdef DEBUG_ENABLED
	env["debug_build"] = true;
#else
	env["debug_build"] = false;
#endif
	return env;
}

Dictionary CgamePerfCapture::new_capture(const String &p_label) {
	Dictionary cap;
	cap["magic"] = MAGIC;
	cap["version"] = VERSION;
	cap["label"] = p_label;
	cap["created_unix"] = (double)OS::get_singleton()->get_unix_time();
	cap["environment"] = capture_environment();
	cap["scenario"] = Dictionary();
	for (int i = 0; i < ARRAY_SECTION_COUNT; i++) {
		cap[ARRAY_SECTIONS[i]] = Array();
	}
	return cap;
}

// Builds a capture whose frames come from the live CgameTrace singleton.
Dictionary CgamePerfCapture::capture_from_trace(const String &p_label) {
	Dictionary cap = new_capture(p_label);
	CgameTrace *trace = CgameTrace::get_singleton();
	if (trace) {
		const TypedArray<Dictionary> frames = trace->frames();
		Array out;
		for (int i = 0; i < frames.size(); i++) {
			out.push_back(frames[i]);
		}
		cap["frames"] = out;
	}
	return cap;
}

void CgamePerfCapture::add_frame(Dictionary p_capture, int64_t p_index, double p_ms, const Dictionary &p_scopes, const Dictionary &p_counters) {
	Array frames = p_capture.get("frames", Array());
	Dictionary f;
	f["index"] = p_index;
	f["ms"] = p_ms;
	f["scopes"] = p_scopes;
	f["counters"] = p_counters;
	frames.push_back(f);
	p_capture["frames"] = frames;
}

void CgamePerfCapture::add_event(Dictionary p_capture, const String &p_section, const Dictionary &p_event) {
	bool known = false;
	for (int i = 0; i < ARRAY_SECTION_COUNT; i++) {
		if (p_section == ARRAY_SECTIONS[i]) {
			known = true;
		}
	}
	if (!known) {
		return;
	}
	Array arr = p_capture.get(p_section, Array());
	arr.push_back(p_event);
	p_capture[p_section] = arr;
}

// Returns a list of human-readable problems; empty means valid.
PackedStringArray CgamePerfCapture::validate(const Dictionary &p_capture) {
	PackedStringArray errs;
	if (String(p_capture.get("magic", "")) != MAGIC) {
		errs.push_back("bad magic");
	}
	if (!p_capture.has("version") || !is_number(p_capture["version"])) {
		errs.push_back("missing version");
	} else if ((int)p_capture["version"] > VERSION) {
		errs.push_back(vformat("version %d is newer than supported %d", (int)p_capture["version"], VERSION));
	} else if ((int)p_capture["version"] < 1) {
		errs.push_back("invalid version");
	}
	for (int i = 0; i < ARRAY_SECTION_COUNT; i++) {
		const String s = ARRAY_SECTIONS[i];
		if (!p_capture.has(s)) {
			errs.push_back("missing section " + s);
		} else if (p_capture[s].get_type() != Variant::ARRAY) {
			errs.push_back(vformat("section %s is not an array", s));
		}
	}
	if (!p_capture.has("environment") || p_capture["environment"].get_type() != Variant::DICTIONARY) {
		errs.push_back("missing environment");
	}
	if (p_capture.has("frames") && p_capture["frames"].get_type() == Variant::ARRAY) {
		const Array frames = p_capture["frames"];
		for (int i = 0; i < frames.size(); i++) {
			if (frames[i].get_type() != Variant::DICTIONARY) {
				errs.push_back(vformat("frame %d is not a dictionary", i));
				break;
			}
			const Dictionary fd = frames[i];
			if (!fd.has("ms") || !is_number(fd["ms"])) {
				errs.push_back(vformat("frame %d has no numeric ms", i));
				break;
			}
			if (fd.has("scopes") && fd["scopes"].get_type() != Variant::DICTIONARY) {
				errs.push_back(vformat("frame %d scopes is not a dictionary", i));
				break;
			}
		}
	}
	return errs;
}

bool CgamePerfCapture::write(const String &p_path, const Dictionary &p_capture, bool p_as_json) {
	Ref<FileAccess> f = FileAccess::open(p_path, FileAccess::WRITE);
	if (f.is_null()) {
		return false;
	}
	if (p_as_json || p_path.ends_with(".json")) {
		f->store_string(JSON::stringify(p_capture, "", false));
	} else {
		int len = 0;
		if (encode_variant(p_capture, nullptr, len, false) != OK) {
			return false;
		}
		Vector<uint8_t> buf;
		buf.resize(len);
		if (encode_variant(p_capture, buf.ptrw(), len, false) != OK) {
			return false;
		}
		f->store_buffer(buf.ptr(), len);
	}
	return true;
}

// Returns an empty dictionary when the file is missing, unreadable or not a capture.
Dictionary CgamePerfCapture::read(const String &p_path) {
	Vector<uint8_t> bytes = FileAccess::get_file_as_bytes(p_path);
	if (bytes.is_empty()) {
		return Dictionary();
	}
	Variant parsed;
	if (bytes[0] == 0x7B) { // '{'
		parsed = JSON::parse_string(String::utf8((const char *)bytes.ptr(), bytes.size()));
	} else {
		if (decode_variant(parsed, bytes.ptr(), bytes.size(), nullptr, false) != OK) {
			return Dictionary();
		}
	}
	if (parsed.get_type() != Variant::DICTIONARY) {
		return Dictionary();
	}
	const Dictionary cap = parsed;
	if (String(cap.get("magic", "")) != MAGIC) {
		return Dictionary();
	}
	return cap;
}

// Array sections are concatenated; frames are re-sorted by index; environment keys of `base` win;
// the scenario of `base` wins unless empty.
Dictionary CgamePerfCapture::merge(const Dictionary &p_base, const Dictionary &p_extra) {
	Dictionary out = p_base.duplicate(true);
	for (int i = 0; i < ARRAY_SECTION_COUNT; i++) {
		const String s = ARRAY_SECTIONS[i];
		Array a = out.get(s, Array());
		const Array b = p_extra.get(s, Array());
		a.append_array(b.duplicate(true));
		out[s] = a;
	}
	Array frames = out["frames"];
	LocalVector<Variant> sortable;
	for (const Variant &v : frames) {
		sortable.push_back(v);
	}
	sortable.sort_custom<FrameIndexOrder>();
	Array sorted;
	for (const Variant &v : sortable) {
		sorted.push_back(v);
	}
	out["frames"] = sorted;

	Dictionary env = out.get("environment", Dictionary());
	const Dictionary env_extra = p_extra.get("environment", Dictionary());
	for (const Variant &k : env_extra.get_key_list()) {
		if (!env.has(k)) {
			env[k] = env_extra[k];
		}
	}
	out["environment"] = env;
	const Dictionary sc = out.get("scenario", Dictionary());
	if (sc.is_empty()) {
		out["scenario"] = Dictionary(p_extra.get("scenario", Dictionary())).duplicate(true);
	}
	return out;
}

PackedFloat32Array CgamePerfCapture::frame_times(const Dictionary &p_capture) {
	PackedFloat32Array out;
	const Array frames = p_capture.get("frames", Array());
	for (const Variant &f : frames) {
		const Dictionary fd = f;
		out.push_back((float)(double)fd.get("ms", 0.0));
	}
	return out;
}

PackedFloat64Array CgamePerfCapture::_metric_values(const Dictionary &p_run, const String &p_metric) {
	PackedFloat64Array vals;
	if (p_run.has("runs")) {
		const Array runs = p_run["runs"];
		for (const Variant &r : runs) {
			const Dictionary rd = r;
			if (rd.has(p_metric)) {
				vals.push_back((double)rd[p_metric]);
			}
		}
	} else if (p_run.has(p_metric)) {
		vals.push_back((double)p_run[p_metric]);
	}
	return vals;
}

// baseline/current: either a flat {metric: value} dict or {"runs": [flat dicts]}.
// thresholds: {metric_or_"default": max allowed % increase}; optional key "noise_factor"
// (default 0.5) widens the limit by that share of the run spread.
Dictionary CgamePerfCapture::compare_runs(const Dictionary &p_baseline, const Dictionary &p_current, const Dictionary &p_thresholds) {
	Dictionary metrics;
	PackedStringArray regressions;
	const double noise_factor = p_thresholds.get("noise_factor", 0.5);
	const double default_pct = p_thresholds.get("default", DEFAULT_THRESHOLD_PCT);
	for (int mi = 0; mi < METRIC_COUNT; mi++) {
		const String m = METRICS[mi];
		const PackedFloat64Array b_vals = _metric_values(p_baseline, m);
		const PackedFloat64Array c_vals = _metric_values(p_current, m);
		if (b_vals.is_empty() || c_vals.is_empty()) {
			continue;
		}
		const double b = median_of(b_vals);
		const double c = median_of(c_vals);
		double pct = 0.0;
		if (Math::abs(b) > 0.000001) {
			pct = (c - b) / Math::abs(b) * 100.0;
		} else if (c > 0.0) {
			pct = c * 100.0;
		}
		double noise = 0.0;
		if (Math::abs(b) > 0.000001) {
			noise = MAX(spread_of(b_vals), spread_of(c_vals)) / Math::abs(b) * 100.0;
		}
		const double limit = (double)p_thresholds.get(m, default_pct) + noise * noise_factor;
		const bool regressed = pct > limit;
		Dictionary row;
		row["baseline"] = b;
		row["current"] = c;
		row["pct"] = pct;
		row["limit"] = limit;
		row["noise_pct"] = noise;
		row["regressed"] = regressed;
		row["improved"] = pct < -limit;
		metrics[m] = row;
		if (regressed) {
			regressions.push_back(m);
		}
	}
	Dictionary out;
	out["metrics"] = metrics;
	out["regressions"] = regressions;
	out["ok"] = regressions.is_empty();
	return out;
}

// Per-scope average usec/frame of a capture: {"frames": n, "scopes": {name: {"total","avg","max"}}}.
Dictionary CgamePerfCapture::_frame_stats_from_capture(const Dictionary &p_capture) {
	struct Acc {
		double total = 0.0;
		double max = 0.0;
	};
	HashMap<String, Acc> acc;
	const Array frames = p_capture.get("frames", Array());
	int64_t n = 0;
	for (const Variant &f : frames) {
		if (f.get_type() != Variant::DICTIONARY) {
			continue;
		}
		n++;
		const Dictionary fd = f;
		const Dictionary scopes = fd.get("scopes", Dictionary());
		for (const Variant &k : scopes.get_key_list()) {
			const double usec = scopes[k];
			Acc &a = acc[String(k)];
			a.total += usec;
			a.max = MAX(a.max, usec);
		}
	}
	Dictionary scopes_out;
	for (const KeyValue<String, Acc> &kv : acc) {
		Dictionary s;
		s["total"] = kv.value.total;
		s["avg"] = kv.value.total / (double)MAX<int64_t>(n, 1);
		s["max"] = kv.value.max;
		scopes_out[kv.key] = s;
	}
	Dictionary out;
	out["frames"] = n;
	out["scopes"] = scopes_out;
	return out;
}

// Scopes (subsystems) whose average per-frame cost grew by more than threshold_pct between two
// captures, worst first: [{"scope", "baseline_avg", "current_avg", "pct"}].
Array CgamePerfCapture::compare_subsystems(const Dictionary &p_baseline_capture, const Dictionary &p_current_capture, double p_threshold_pct) {
	return CgameTrace::compare(_frame_stats_from_capture(p_baseline_capture), _frame_stats_from_capture(p_current_capture), p_threshold_pct);
}

// Least-squares slope of memory samples over a soak run. Flags a leak when the fit is strong (r2)
// and total growth exceeds min_growth_pct of the mean.
Dictionary CgamePerfCapture::memory_leak_trend(const PackedFloat32Array &p_samples, double p_min_growth_pct, double p_min_r2) {
	Dictionary out;
	const int n = p_samples.size();
	if (n < 3) {
		out["slope"] = 0.0;
		out["r2"] = 0.0;
		out["growth_pct"] = 0.0;
		out["leak"] = false;
		out["samples"] = n;
		return out;
	}
	const double mx = double(n - 1) * 0.5;
	double my = 0.0;
	for (float y : p_samples) {
		my += y;
	}
	my /= double(n);
	double sxx = 0.0;
	double sxy = 0.0;
	double syy = 0.0;
	for (int i = 0; i < n; i++) {
		const double dx = double(i) - mx;
		const double dy = (double)p_samples[i] - my;
		sxx += dx * dx;
		sxy += dx * dy;
		syy += dy * dy;
	}
	const double slope = sxy / sxx;
	double r2 = 0.0;
	if (syy > 0.0000001) {
		r2 = (sxy * sxy) / (sxx * syy);
	}
	double growth_pct = 0.0;
	if (Math::abs(my) > 0.000001) {
		growth_pct = slope * double(n - 1) / Math::abs(my) * 100.0;
	}
	out["slope"] = slope;
	out["r2"] = r2;
	out["growth_pct"] = growth_pct;
	out["samples"] = n;
	out["leak"] = slope > 0.0 && r2 >= p_min_r2 && growth_pct >= p_min_growth_pct;
	return out;
}

Dictionary CgamePerfCapture::load_json(const String &p_path) {
	if (!FileAccess::exists(p_path)) {
		return Dictionary();
	}
	Variant parsed = JSON::parse_string(FileAccess::get_file_as_string(p_path));
	return parsed.get_type() == Variant::DICTIONARY ? Dictionary(parsed) : Dictionary();
}

bool CgamePerfCapture::save_json(const String &p_path, const Dictionary &p_data) {
	Ref<FileAccess> f = FileAccess::open(p_path, FileAccess::WRITE);
	if (f.is_null()) {
		return false;
	}
	f->store_string(JSON::stringify(p_data, "\t"));
	return true;
}

void CgamePerfCapture::_bind_methods() {
	ClassDB::bind_static_method("CgamePerfCapture", D_METHOD("new_capture", "label"), &CgamePerfCapture::new_capture, DEFVAL(""));
	ClassDB::bind_static_method("CgamePerfCapture", D_METHOD("capture_environment"), &CgamePerfCapture::capture_environment);
	ClassDB::bind_static_method("CgamePerfCapture", D_METHOD("capture_from_trace", "label"), &CgamePerfCapture::capture_from_trace, DEFVAL(""));
	ClassDB::bind_static_method("CgamePerfCapture", D_METHOD("add_frame", "capture", "index", "ms", "scopes", "counters"), &CgamePerfCapture::add_frame, DEFVAL(Dictionary()), DEFVAL(Dictionary()));
	ClassDB::bind_static_method("CgamePerfCapture", D_METHOD("add_event", "capture", "section", "event"), &CgamePerfCapture::add_event);
	ClassDB::bind_static_method("CgamePerfCapture", D_METHOD("validate", "capture"), &CgamePerfCapture::validate);
	ClassDB::bind_static_method("CgamePerfCapture", D_METHOD("write", "path", "capture", "as_json"), &CgamePerfCapture::write, DEFVAL(false));
	ClassDB::bind_static_method("CgamePerfCapture", D_METHOD("read", "path"), &CgamePerfCapture::read);
	ClassDB::bind_static_method("CgamePerfCapture", D_METHOD("merge", "base", "extra"), &CgamePerfCapture::merge);
	ClassDB::bind_static_method("CgamePerfCapture", D_METHOD("frame_times", "capture"), &CgamePerfCapture::frame_times);
	ClassDB::bind_static_method("CgamePerfCapture", D_METHOD("compare_runs", "baseline", "current", "thresholds"), &CgamePerfCapture::compare_runs, DEFVAL(Dictionary()));
	ClassDB::bind_static_method("CgamePerfCapture", D_METHOD("compare_subsystems", "baseline_capture", "current_capture", "threshold_pct"), &CgamePerfCapture::compare_subsystems, DEFVAL(10.0));
	ClassDB::bind_static_method("CgamePerfCapture", D_METHOD("memory_leak_trend", "samples", "min_growth_pct", "min_r2"), &CgamePerfCapture::memory_leak_trend, DEFVAL(5.0), DEFVAL(0.8));
	ClassDB::bind_static_method("CgamePerfCapture", D_METHOD("load_json", "path"), &CgamePerfCapture::load_json);
	ClassDB::bind_static_method("CgamePerfCapture", D_METHOD("save_json", "path", "data"), &CgamePerfCapture::save_json);

	BIND_CONSTANT(VERSION);
}
