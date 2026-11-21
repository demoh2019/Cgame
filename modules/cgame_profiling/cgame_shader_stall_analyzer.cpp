/**************************************************************************/
/*  cgame_shader_stall_analyzer.cpp                                       */
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

#include "cgame_shader_stall_analyzer.h"

#include "core/object/class_db.h"
#include "servers/rendering/rendering_server.h"

Mutex CgameShaderStallAnalyzer::registry_mutex;
LocalVector<CgameShaderStallAnalyzer *> CgameShaderStallAnalyzer::auto_instances;

namespace {
struct ExtraDesc {
	_FORCE_INLINE_ bool operator()(const Dictionary &p_a, const Dictionary &p_b) const {
		return (double)p_a["total_extra_ms"] > (double)p_b["total_extra_ms"];
	}
};
} // namespace

CgameShaderStallAnalyzer::~CgameShaderStallAnalyzer() {
	stop_auto_sampling();
}

// compiles = pipelines compiled during this frame; materials = first drawn this frame.
void CgameShaderStallAnalyzer::feed(int64_t p_index, double p_ms, int64_t p_compiles, const PackedStringArray &p_first_drawn_materials) {
	FrameSample s;
	s.index = p_index;
	s.ms = p_ms;
	s.compiles = p_compiles;
	s.materials = p_first_drawn_materials;
	samples.push_back(s);
}

// Same, but from a cumulative compile counter (delta computed internally).
void CgameShaderStallAnalyzer::feed_cumulative(int64_t p_index, double p_ms, int64_t p_total_compiles, const PackedStringArray &p_first_drawn_materials) {
	const int64_t delta = last_total < 0 ? 0 : MAX<int64_t>(0, p_total_compiles - last_total);
	last_total = p_total_compiles;
	feed(p_index, p_ms, delta, p_first_drawn_materials);
}

// Sum of the RenderingServer pipeline compilation counters (0 when no server exists).
int64_t CgameShaderStallAnalyzer::live_compile_total() {
	RenderingServer *rs = RenderingServer::get_singleton();
	if (rs == nullptr) {
		return 0;
	}
	int64_t total = 0;
	total += (int64_t)rs->get_rendering_info(RSE::RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS);
	total += (int64_t)rs->get_rendering_info(RSE::RENDERING_INFO_PIPELINE_COMPILATIONS_MESH);
	total += (int64_t)rs->get_rendering_info(RSE::RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE);
	total += (int64_t)rs->get_rendering_info(RSE::RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW);
	total += (int64_t)rs->get_rendering_info(RSE::RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION);
	return total;
}

double CgameShaderStallAnalyzer::baseline_ms() const {
	if (samples.is_empty()) {
		return 0.0;
	}
	LocalVector<double> arr;
	for (const FrameSample &s : samples) {
		arr.push_back(s.ms);
	}
	arr.sort();
	return arr[arr.size() >> 1];
}

// {"baseline_ms", "stalls": [{index, ms, extra_ms, compiles, culprits}],
//  "unrelated_spikes": [index], "culprits": [{material, stalls, total_extra_ms}]}
Dictionary CgameShaderStallAnalyzer::analyze() const {
	const double base = baseline_ms();
	const double limit = MAX(base * spike_factor, base + min_extra_ms);
	Array stalls;
	Array unrelated;
	HashMap<String, Dictionary> by_mat;
	LocalVector<String> mat_order;
	for (const FrameSample &f : samples) {
		if (f.ms <= limit) {
			continue;
		}
		if (f.compiles <= 0) {
			unrelated.push_back(f.index);
			continue;
		}
		const double extra = f.ms - base;
		Dictionary stall;
		stall["index"] = f.index;
		stall["ms"] = f.ms;
		stall["extra_ms"] = extra;
		stall["compiles"] = f.compiles;
		stall["culprits"] = f.materials.duplicate();
		stalls.push_back(stall);
		const double share = extra / (double)MAX(1, (int)f.materials.size());
		for (const String &m : f.materials) {
			if (!by_mat.has(m)) {
				Dictionary e;
				e["material"] = m;
				e["stalls"] = 0;
				e["total_extra_ms"] = 0.0;
				by_mat[m] = e;
				mat_order.push_back(m);
			}
			Dictionary &e = by_mat[m];
			e["stalls"] = (int64_t)e["stalls"] + 1;
			e["total_extra_ms"] = (double)e["total_extra_ms"] + share;
		}
	}
	LocalVector<Dictionary> ranked;
	for (const String &m : mat_order) {
		ranked.push_back(by_mat[m]);
	}
	ranked.sort_custom<ExtraDesc>();
	Array culprits;
	for (const Dictionary &d : ranked) {
		culprits.push_back(d);
	}
	Dictionary out;
	out["baseline_ms"] = base;
	out["stalls"] = stalls;
	out["unrelated_spikes"] = unrelated;
	out["culprits"] = culprits;
	return out;
}

void CgameShaderStallAnalyzer::clear() {
	samples.clear();
	last_total = -1;
	MutexLock lock(registry_mutex);
	pending_materials.clear();
}

void CgameShaderStallAnalyzer::start_auto_sampling() {
	MutexLock lock(registry_mutex);
	if (auto_sampling) {
		return;
	}
	auto_sampling = true;
	last_tick_usec = 0;
	auto_instances.push_back(this);
}

void CgameShaderStallAnalyzer::stop_auto_sampling() {
	MutexLock lock(registry_mutex);
	if (!auto_sampling) {
		return;
	}
	auto_sampling = false;
	auto_instances.erase(this);
}

void CgameShaderStallAnalyzer::note_material(const String &p_material) {
	MutexLock lock(registry_mutex);
	pending_materials.push_back(p_material);
}

// Caller holds registry_mutex.
void CgameShaderStallAnalyzer::_auto_tick(uint64_t p_frame, uint64_t p_ticks_usec) {
	if (last_tick_usec != 0) {
		const double ms = double(p_ticks_usec - last_tick_usec) / 1000.0;
		feed_cumulative((int64_t)p_frame, ms, live_compile_total(), pending_materials);
		while (samples.size() > (uint32_t)max_samples) {
			samples.remove_at(0);
		}
	} else {
		// First tick only establishes the counter and time baselines.
		last_total = live_compile_total();
	}
	pending_materials.clear();
	last_tick_usec = p_ticks_usec;
}

void CgameShaderStallAnalyzer::tick_all(uint64_t p_frame, uint64_t p_ticks_usec) {
	MutexLock lock(registry_mutex);
	for (CgameShaderStallAnalyzer *a : auto_instances) {
		a->_auto_tick(p_frame, p_ticks_usec);
	}
}

void CgameShaderStallAnalyzer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_spike_factor", "factor"), &CgameShaderStallAnalyzer::set_spike_factor);
	ClassDB::bind_method(D_METHOD("get_spike_factor"), &CgameShaderStallAnalyzer::get_spike_factor);
	ClassDB::bind_method(D_METHOD("set_min_extra_ms", "ms"), &CgameShaderStallAnalyzer::set_min_extra_ms);
	ClassDB::bind_method(D_METHOD("get_min_extra_ms"), &CgameShaderStallAnalyzer::get_min_extra_ms);
	ClassDB::bind_method(D_METHOD("set_max_samples", "count"), &CgameShaderStallAnalyzer::set_max_samples);
	ClassDB::bind_method(D_METHOD("get_max_samples"), &CgameShaderStallAnalyzer::get_max_samples);
	ClassDB::bind_method(D_METHOD("feed", "index", "ms", "compiles", "first_drawn_materials"), &CgameShaderStallAnalyzer::feed, DEFVAL(PackedStringArray()));
	ClassDB::bind_method(D_METHOD("feed_cumulative", "index", "ms", "total_compiles", "first_drawn_materials"), &CgameShaderStallAnalyzer::feed_cumulative, DEFVAL(PackedStringArray()));
	ClassDB::bind_static_method("CgameShaderStallAnalyzer", D_METHOD("live_compile_total"), &CgameShaderStallAnalyzer::live_compile_total);
	ClassDB::bind_method(D_METHOD("baseline_ms"), &CgameShaderStallAnalyzer::baseline_ms);
	ClassDB::bind_method(D_METHOD("analyze"), &CgameShaderStallAnalyzer::analyze);
	ClassDB::bind_method(D_METHOD("frame_count"), &CgameShaderStallAnalyzer::frame_count);
	ClassDB::bind_method(D_METHOD("clear"), &CgameShaderStallAnalyzer::clear);
	ClassDB::bind_method(D_METHOD("start_auto_sampling"), &CgameShaderStallAnalyzer::start_auto_sampling);
	ClassDB::bind_method(D_METHOD("stop_auto_sampling"), &CgameShaderStallAnalyzer::stop_auto_sampling);
	ClassDB::bind_method(D_METHOD("is_auto_sampling"), &CgameShaderStallAnalyzer::is_auto_sampling);
	ClassDB::bind_method(D_METHOD("note_material", "material"), &CgameShaderStallAnalyzer::note_material);

	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "spike_factor", PROPERTY_HINT_RANGE, "1,100,0.01,or_greater"), "set_spike_factor", "get_spike_factor");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_extra_ms", PROPERTY_HINT_RANGE, "0,1000,0.01,or_greater"), "set_min_extra_ms", "get_min_extra_ms");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_samples", PROPERTY_HINT_RANGE, "1,1000000,1"), "set_max_samples", "get_max_samples");
}
