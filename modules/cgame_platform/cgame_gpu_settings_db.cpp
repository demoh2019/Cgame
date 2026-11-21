/**************************************************************************/
/*  cgame_gpu_settings_db.cpp                                             */
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

#include "cgame_gpu_settings_db.h"

#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/object/class_db.h"
#include "core/string/regex.h"
#include "servers/rendering/rendering_server.h"

namespace {

struct Rule {
	const char *pattern;
	const char *family;
	int level;
	double scale;
};

// Ordered rules, first match wins.
const Rule RULES[] = {
	// Apple silicon.
	{ "apple m[1-4] (max|ultra)", "apple_m_pro_max", 3, 1.0 },
	{ "apple m[2-4] pro", "apple_m_pro_max", 3, 1.0 },
	{ "apple m1 pro", "apple_m1_pro", 2, 1.0 },
	{ "apple m[34]\\b", "apple_m3_m4", 3, 1.0 },
	{ "apple m2\\b", "apple_m2", 2, 1.0 },
	{ "apple m1\\b", "apple_m1", 2, 0.9 },
	{ "apple a(1[5-9]|[2-9]\\d)", "apple_a_new", 1, 0.8 },
	{ "apple a\\d+", "apple_a_old", 0, 0.7 },
	// NVIDIA.
	{ "rtx\\s*[2-5]0(90|80|70)", "nvidia_rtx_high", 3, 1.0 },
	{ "rtx\\s*[3-5]0(60|50)", "nvidia_rtx_mid", 2, 1.0 },
	{ "rtx\\s*20(60|50)", "nvidia_rtx20_mid", 2, 1.0 },
	{ "gtx\\s*16\\d\\d", "nvidia_gtx16", 2, 1.0 },
	{ "gtx\\s*10(80|70|60)", "nvidia_gtx10_high", 2, 1.0 },
	{ "gtx\\s*10\\d\\d", "nvidia_gtx10_low", 1, 1.0 },
	{ "gtx\\s*9\\d\\d", "nvidia_gtx9", 1, 0.9 },
	{ "(gt|gtx)\\s*\\d{3,4}", "nvidia_legacy", 0, 0.8 },
	// AMD.
	{ "rx\\s*(7[6-9]00|6[7-9]00|9[0-9]00)", "amd_rx_high", 3, 1.0 },
	{ "rx\\s*(7[0-5]00|6[0-6]00)", "amd_rx_mid", 2, 1.0 },
	{ "rx\\s*5[0-9]00", "amd_rx5000", 2, 1.0 },
	{ "(rx\\s*[45]\\d\\d\\b|vega)", "amd_polaris_vega", 1, 0.9 },
	{ "radeon.*graphics", "amd_igpu", 1, 0.8 },
	// Intel.
	{ "intel.*arc", "intel_arc", 2, 1.0 },
	{ "iris.*(xe|plus)", "intel_iris_xe", 1, 0.85 },
	{ "intel.*(uhd|hd graphics)", "intel_uhd", 0, 0.75 },
	// Mobile.
	{ "immortalis", "mali_immortalis", 2, 0.85 },
	{ "mali-g7[1-9]\\d", "mali_g7", 1, 0.8 },
	{ "mali", "mali_low", 0, 0.7 },
	{ "adreno.*\\(?(7\\d\\d)", "adreno_7xx", 2, 0.85 },
	{ "adreno.*\\(?6[4-9]\\d", "adreno_64x", 1, 0.8 },
	{ "adreno", "adreno_low", 0, 0.7 },
};

struct VendorHint {
	const char *key;
	int level;
};

const VendorHint VENDOR_FALLBACK[] = {
	{ "apple", 2 }, { "nvidia", 2 }, { "amd", 1 }, { "ati", 1 }, { "intel", 0 }, { "qualcomm", 0 }, { "arm", 0 },
};

} // namespace

int CgameGPUSettingsDB::get_rule_count() {
	return (int)(sizeof(RULES) / sizeof(RULES[0]));
}

Dictionary CgameGPUSettingsDB::match_adapter(const String &p_adapter, const String &p_vendor) {
	const String name = p_adapter.to_lower();
	for (const Rule &rule : RULES) {
		Ref<RegEx> re;
		re.instantiate();
		if (re->compile(rule.pattern, false) != OK) {
			continue;
		}
		if (re->search(name).is_valid()) {
			Dictionary d;
			d["level"] = rule.level;
			d["scale"] = rule.scale;
			d["family"] = String(rule.family);
			d["source"] = "database";
			d["features"] = features_for(rule.level);
			return d;
		}
	}
	return _fallback(name, p_vendor.to_lower());
}

Dictionary CgameGPUSettingsDB::_fallback(const String &p_name, const String &p_vendor) {
	int level = 1;
	double scale = 0.9;
	const String hay = p_name + " " + p_vendor;
	for (const VendorHint &hint : VENDOR_FALLBACK) {
		if (hay.contains(hint.key)) {
			level = hint.level;
			break;
		}
	}
	if (hay.contains("software") || hay.contains("llvmpipe") || hay.contains("swiftshader")) {
		level = 0;
		scale = 0.5;
	}
	Dictionary d;
	d["level"] = level;
	d["scale"] = scale;
	d["family"] = "unknown";
	d["source"] = "fallback";
	d["features"] = features_for(level);
	return d;
}

Dictionary CgameGPUSettingsDB::features_for(int p_level) {
	const int lv = CLAMP(p_level, 0, MAX_LEVEL);
	Dictionary d;
	d["ssao"] = lv >= 2;
	d["ssr"] = lv >= 3;
	d["volumetric_fog"] = lv >= 2;
	d["sdfgi"] = lv >= 3;
	d["glow"] = lv >= 1;
	d["shadow_quality"] = lv;
	d["msaa"] = lv < 2 ? 0 : (lv == 2 ? 2 : 4);
	return d;
}

Dictionary CgameGPUSettingsDB::_load(const String &p_path) {
	if (!FileAccess::exists(p_path)) {
		return Dictionary();
	}
	const Variant parsed = JSON::parse_string(FileAccess::get_file_as_string(p_path));
	if (parsed.get_type() == Variant::DICTIONARY) {
		return parsed;
	}
	return Dictionary();
}

Dictionary CgameGPUSettingsDB::_medians(const String &p_adapter, const String &p_path) {
	Dictionary out;
	const Dictionary data = _load(p_path);
	const Dictionary entry = data.get(p_adapter.strip_edges().to_lower(), Dictionary());
	for (const Variant &k : entry.keys()) {
		const Array samples = entry[k];
		if (samples.is_empty()) {
			continue;
		}
		Vector<double> vals;
		for (int i = 0; i < samples.size(); i++) {
			vals.push_back((double)samples[i]);
		}
		vals.sort();
		const int n = vals.size();
		const double med = (n % 2 == 1) ? vals[n / 2] : (vals[n / 2 - 1] + vals[n / 2]) * 0.5;
		out[String(k).to_int()] = med;
	}
	return out;
}

Dictionary CgameGPUSettingsDB::recommend(const String &p_adapter, const String &p_vendor, double p_target_ms, const String &p_path) {
	Dictionary base = match_adapter(p_adapter, p_vendor);
	const Dictionary per_level = _medians(p_adapter, p_path);
	if (per_level.is_empty()) {
		return base;
	}
	int best = -1;
	int lowest_measured = MAX_LEVEL + 1;
	for (const Variant &k : per_level.keys()) {
		const int lv = k;
		lowest_measured = MIN(lowest_measured, lv);
		if ((double)per_level[k] <= p_target_ms && lv > best) {
			best = lv;
		}
	}
	int chosen;
	if (best >= 0) {
		chosen = best;
		if ((double)per_level[best] < p_target_ms * 0.7 && !per_level.has(best + 1)) {
			chosen = MIN(best + 1, MAX_LEVEL);
		}
	} else {
		chosen = MAX(lowest_measured - 1, 0);
	}
	base["level"] = chosen;
	base["source"] = "learned";
	base["features"] = features_for(chosen);
	return base;
}

bool CgameGPUSettingsDB::learn(const String &p_adapter, double p_measured_frame_ms, int p_level, const String &p_path) {
	if (p_measured_frame_ms <= 0.0) {
		return false;
	}
	Dictionary data = _load(p_path);
	const String key = p_adapter.strip_edges().to_lower();
	Dictionary entry = data.get(key, Dictionary());
	const String lk = itos(CLAMP(p_level, 0, MAX_LEVEL));
	Array samples = entry.get(lk, Array());
	samples.push_back(p_measured_frame_ms);
	while (samples.size() > MAX_SAMPLES_PER_LEVEL) {
		samples.pop_front();
	}
	entry[lk] = samples;
	data[key] = entry;
	Ref<FileAccess> f = FileAccess::open(p_path, FileAccess::WRITE);
	if (f.is_null()) {
		return false;
	}
	f->store_string(JSON::stringify(data));
	return true;
}

Dictionary CgameGPUSettingsDB::recommend_current() {
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs == nullptr) {
		return match_adapter("", "");
	}
	return recommend(rs->get_video_adapter_name(), rs->get_video_adapter_vendor());
}

void CgameGPUSettingsDB::_bind_methods() {
	ClassDB::bind_static_method("CgameGPUSettingsDB", D_METHOD("match_adapter", "adapter", "vendor"), &CgameGPUSettingsDB::match_adapter, DEFVAL(""));
	ClassDB::bind_static_method("CgameGPUSettingsDB", D_METHOD("features_for", "level"), &CgameGPUSettingsDB::features_for);
	ClassDB::bind_static_method("CgameGPUSettingsDB", D_METHOD("recommend", "adapter", "vendor", "target_ms", "path"), &CgameGPUSettingsDB::recommend, DEFVAL(""), DEFVAL(TARGET_FRAME_MS), DEFVAL("user://gpu_learned.json"));
	ClassDB::bind_static_method("CgameGPUSettingsDB", D_METHOD("learn", "adapter", "measured_frame_ms", "level", "path"), &CgameGPUSettingsDB::learn, DEFVAL("user://gpu_learned.json"));
	ClassDB::bind_static_method("CgameGPUSettingsDB", D_METHOD("recommend_current"), &CgameGPUSettingsDB::recommend_current);
	ClassDB::bind_static_method("CgameGPUSettingsDB", D_METHOD("get_default_path"), &CgameGPUSettingsDB::get_default_path);
	ClassDB::bind_static_method("CgameGPUSettingsDB", D_METHOD("get_rule_count"), &CgameGPUSettingsDB::get_rule_count);

	BIND_CONSTANT(MAX_LEVEL);
	BIND_CONSTANT(MAX_SAMPLES_PER_LEVEL);
}
