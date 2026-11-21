/**************************************************************************/
/*  cgame_shader_stall_analyzer.h                                         */
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
#include "core/os/mutex.h"
#include "core/templates/local_vector.h"
#include "core/variant/dictionary.h"

// Shader compilation stall analyzer: correlates per-frame pipeline compilation counts with
// frame-time spikes and the materials first drawn in that frame. Frames can be fed manually, or
// the analyzer can sample RenderingServer pipeline compilation counters natively once per main
// loop iteration (start_auto_sampling()).
class CgameShaderStallAnalyzer : public RefCounted {
	GDCLASS(CgameShaderStallAnalyzer, RefCounted);

	struct FrameSample {
		int64_t index = 0;
		double ms = 0.0;
		int64_t compiles = 0;
		PackedStringArray materials;
	};

	LocalVector<FrameSample> samples;
	double spike_factor = 2.0;
	double min_extra_ms = 4.0;
	int64_t last_total = -1;

	bool auto_sampling = false;
	int max_samples = 4096;
	uint64_t last_tick_usec = 0;
	PackedStringArray pending_materials; // Guarded by registry_mutex.

	static Mutex registry_mutex;
	static LocalVector<CgameShaderStallAnalyzer *> auto_instances;

	void _auto_tick(uint64_t p_frame, uint64_t p_ticks_usec);

protected:
	static void _bind_methods();

public:
	void set_spike_factor(double p_factor) { spike_factor = MAX(p_factor, 1.0); }
	double get_spike_factor() const { return spike_factor; }
	void set_min_extra_ms(double p_ms) { min_extra_ms = MAX(p_ms, 0.0); }
	double get_min_extra_ms() const { return min_extra_ms; }
	void set_max_samples(int p_count) { max_samples = MAX(p_count, 1); }
	int get_max_samples() const { return max_samples; }

	void feed(int64_t p_index, double p_ms, int64_t p_compiles, const PackedStringArray &p_first_drawn_materials = PackedStringArray());
	void feed_cumulative(int64_t p_index, double p_ms, int64_t p_total_compiles, const PackedStringArray &p_first_drawn_materials = PackedStringArray());
	static int64_t live_compile_total();
	double baseline_ms() const;
	Dictionary analyze() const;
	int frame_count() const { return (int)samples.size(); }
	void clear();

	void start_auto_sampling();
	void stop_auto_sampling();
	bool is_auto_sampling() const { return auto_sampling; }
	// Records a material first drawn this frame; consumed by the next automatic sample. Thread-safe.
	void note_material(const String &p_material);

	// Main-thread engine frame hook entry point.
	static void tick_all(uint64_t p_frame, uint64_t p_ticks_usec);

	~CgameShaderStallAnalyzer();
};
