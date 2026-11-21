/**************************************************************************/
/*  cgame_hitch_correlator.cpp                                            */
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

#include "cgame_hitch_correlator.h"

#include "core/object/class_db.h"
#include "core/templates/local_vector.h"
#include "servers/rendering/rendering_server.h"

namespace {

double median_of(const LocalVector<double> &p_input) {
	LocalVector<double> p_values;
	for (double v : p_input) {
		p_values.push_back(v);
	}
	if (p_values.is_empty()) {
		return 0.0;
	}
	p_values.sort();
	const uint32_t n = p_values.size();
	const uint32_t mid = n >> 1;
	if (n % 2 == 1) {
		return p_values[mid];
	}
	return (p_values[mid - 1] + p_values[mid]) * 0.5;
}

// Values of frames[from, to).`key` is "scopes" or "counters".
LocalVector<double> series(const Array &p_frames, int p_from, int p_to, const String &p_key, const Variant &p_name) {
	LocalVector<double> values;
	for (int i = p_from; i < p_to; i++) {
		const Dictionary frame = p_frames[i];
		const Dictionary d = frame.get(p_key, Dictionary());
		values.push_back(d.get(p_name, 0.0));
	}
	return values;
}

struct CulpritOrder {
	_FORCE_INLINE_ bool operator()(const Dictionary &p_a, const Dictionary &p_b) const {
		return (double)p_a["growth_usec"] > (double)p_b["growth_usec"];
	}
};

} // namespace

// frames: [{"ms": float, "scopes": {name: usec}, "counters": {name: value}}]
Array CgameHitchCorrelator::correlate(const Array &p_frames, double p_threshold_ms) {
	Array result;
	for (int i = 0; i < p_frames.size(); i++) {
		const Dictionary frame = p_frames[i];
		const double ms = frame.get("ms", 0.0);
		if (ms <= p_threshold_ms) {
			continue;
		}
		const int from = MAX(0, i - WINDOW);
		double baseline_ms = ms;
		if (i > from) {
			// "ms" lives at the frame root rather than in a sub-dictionary.
			LocalVector<double> ms_values;
			for (int k = from; k < i; k++) {
				const Dictionary w = p_frames[k];
				ms_values.push_back(w.get("ms", 0.0));
			}
			baseline_ms = median_of(ms_values);
		}

		LocalVector<Dictionary> culprits;
		const Dictionary scopes = frame.get("scopes", Dictionary());
		for (const Variant &scope_name : scopes.get_key_list()) {
			const double usec = scopes[scope_name];
			const double med = median_of(series(p_frames, from, i, "scopes", scope_name));
			if (usec - med > 0.0) {
				Dictionary c;
				c["scope"] = scope_name;
				c["usec"] = usec;
				c["median_usec"] = med;
				c["growth_usec"] = usec - med;
				culprits.push_back(c);
			}
		}
		culprits.sort_custom<CulpritOrder>();
		Array top;
		for (uint32_t k = 0; k < culprits.size() && (int)k < TOP_SCOPES; k++) {
			top.push_back(culprits[k]);
		}

		Array jumped;
		const Dictionary counters = frame.get("counters", Dictionary());
		for (const Variant &counter_name : counters.get_key_list()) {
			const double value = counters[counter_name];
			const double med = median_of(series(p_frames, from, i, "counters", counter_name));
			if (Math::abs(value - med) > MAX(Math::abs(med) * 0.5, 1.0)) {
				Dictionary j;
				j["name"] = counter_name;
				j["value"] = value;
				j["median"] = med;
				jumped.push_back(j);
			}
		}
		Dictionary rec;
		rec["index"] = i;
		rec["ms"] = ms;
		rec["baseline_ms"] = baseline_ms;
		rec["culprits"] = top;
		rec["counters"] = jumped;
		result.push_back(rec);
	}
	return result;
}

// Cheap per-frame engine counters: {"compiles", "cells", "vram"}.
Dictionary CgameHitchCorrelator::read_counters(int p_loaded_cells) {
	int64_t compiles = 0;
	double vram = 0.0;
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs) {
		compiles += (int64_t)rs->get_rendering_info(RSE::RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS);
		compiles += (int64_t)rs->get_rendering_info(RSE::RENDERING_INFO_PIPELINE_COMPILATIONS_MESH);
		compiles += (int64_t)rs->get_rendering_info(RSE::RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE);
		compiles += (int64_t)rs->get_rendering_info(RSE::RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW);
		compiles += (int64_t)rs->get_rendering_info(RSE::RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION);
		vram = (double)rs->get_rendering_info(RSE::RENDERING_INFO_VIDEO_MEM_USED);
	}
	Dictionary d;
	d["compiles"] = compiles;
	d["cells"] = p_loaded_cells;
	d["vram"] = vram;
	return d;
}

String CgameHitchCorrelator::cause(const Dictionary &p_before, const Dictionary &p_after) {
	if ((int64_t)p_after.get("compiles", 0) > (int64_t)p_before.get("compiles", 0)) {
		return "shader_compile";
	}
	if ((int64_t)p_after.get("cells", 0) != (int64_t)p_before.get("cells", 0)) {
		return "streaming";
	}
	if ((double)p_after.get("vram", 0.0) - (double)p_before.get("vram", 0.0) > VRAM_JUMP) {
		return "vram";
	}
	return "cpu";
}

double CgameHitchCorrelator::median() const {
	if (sampled_frames.is_empty()) {
		return 0.0;
	}
	LocalVector<double> sorted;
	for (double v : sampled_frames) {
		sorted.push_back(v);
	}
	sorted.sort();
	return sorted[sorted.size() / 2];
}

// Returns the hitch record when this frame was a hitch, else an empty dictionary.
Dictionary CgameHitchCorrelator::sample(double p_delta, const Dictionary &p_counters, double p_now) {
	Dictionary result;
	if (!Math::is_finite(p_delta) || p_delta <= 0.0) {
		return result;
	}
	const double typical = median();
	if (sampled_frames.size() >= 30 && p_delta >= MAX(MIN_HITCH_SEC, typical * HITCH_FACTOR) && !last_counters.is_empty()) {
		const String reason = cause(last_counters, p_counters);
		result["time"] = p_now;
		result["ms"] = p_delta * 1000.0;
		result["median_ms"] = typical * 1000.0;
		result["cause"] = reason;
		counts[reason] = (int64_t)counts.get(reason, 0) + 1;
		hitches.push_back(result);
		while (hitches.size() > SAMPLE_KEEP) {
			hitches.remove_at(0);
		}
	} else {
		// Hitches never pollute the baseline.
		sampled_frames.push_back(p_delta);
		if (sampled_frames.size() > (uint32_t)SAMPLE_WINDOW) {
			sampled_frames.remove_at(0);
		}
	}
	last_counters = p_counters;
	return result;
}

String CgameHitchCorrelator::describe() const {
	return vformat("hitches: shaders %d, streaming %d, vram %d, cpu %d",
			(int64_t)counts.get("shader_compile", 0), (int64_t)counts.get("streaming", 0),
			(int64_t)counts.get("vram", 0), (int64_t)counts.get("cpu", 0));
}

void CgameHitchCorrelator::reset() {
	hitches.clear();
	sampled_frames.clear();
	last_counters = Dictionary();
	counts["shader_compile"] = 0;
	counts["streaming"] = 0;
	counts["vram"] = 0;
	counts["cpu"] = 0;
}

void CgameHitchCorrelator::_bind_methods() {
	ClassDB::bind_static_method("CgameHitchCorrelator", D_METHOD("correlate", "frames", "threshold_ms"), &CgameHitchCorrelator::correlate);
	ClassDB::bind_static_method("CgameHitchCorrelator", D_METHOD("read_counters", "loaded_cells"), &CgameHitchCorrelator::read_counters, DEFVAL(0));
	ClassDB::bind_static_method("CgameHitchCorrelator", D_METHOD("cause", "before", "after"), &CgameHitchCorrelator::cause);
	ClassDB::bind_method(D_METHOD("sample", "delta", "counters", "now"), &CgameHitchCorrelator::sample, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("median"), &CgameHitchCorrelator::median);
	ClassDB::bind_method(D_METHOD("describe"), &CgameHitchCorrelator::describe);
	ClassDB::bind_method(D_METHOD("get_hitches"), &CgameHitchCorrelator::get_hitches);
	ClassDB::bind_method(D_METHOD("get_counts"), &CgameHitchCorrelator::get_counts);
	ClassDB::bind_method(D_METHOD("reset"), &CgameHitchCorrelator::reset);

	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "hitches", PROPERTY_HINT_ARRAY_TYPE, "Dictionary", PROPERTY_USAGE_NONE), "", "get_hitches");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "counts", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "", "get_counts");
}

CgameHitchCorrelator::CgameHitchCorrelator() {
	counts["shader_compile"] = 0;
	counts["streaming"] = 0;
	counts["vram"] = 0;
	counts["cpu"] = 0;
}
