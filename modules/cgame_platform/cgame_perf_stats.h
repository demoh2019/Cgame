/**************************************************************************/
/*  cgame_perf_stats.h                                                    */
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
#include "core/templates/hash_map.h"
#include "core/templates/vector.h"
#include "core/variant/typed_array.h"

// Rolling statistics keyed by series name. Every series is a fixed-capacity ring buffer of floats, so pushing a
// sample never allocates after the series was created.
class CgamePerfStats : public RefCounted {
	GDCLASS(CgamePerfStats, RefCounted);

	struct Ring {
		Vector<float> data;
		int head = 0;
		int count = 0;
		int64_t total = 0;

		void init(int p_capacity) {
			data.resize(MAX(p_capacity, 1));
			data.fill(0.0f);
		}
		void push(float p_value);
		Vector<float> to_array(int p_n) const;
	};

	int capacity = 300;
	HashMap<String, Ring> rings;

protected:
	static void _bind_methods();

public:
	void set_capacity(int p_capacity);
	int get_capacity() const { return capacity; }

	void push(const String &p_series, double p_value);
	bool has_series(const String &p_series) const;
	TypedArray<String> names() const;
	PackedFloat32Array series(const String &p_series, int p_window = 0) const;
	int count(const String &p_series) const;
	int64_t total_pushed(const String &p_series) const;
	double last(const String &p_series) const;
	double percentile(const String &p_series, double p_percent, int p_window = 0) const;
	double average(const String &p_series, int p_window = 0) const;
	double max_value(const String &p_series, int p_window = 0) const;
	Dictionary summary(const String &p_series, int p_window = 0) const;
	void clear();

	// Pure helper: linear-interpolated percentile (0..100) of an ascending-sorted array.
	static double percentile_sorted(const Vector<float> &p_sorted, double p_percent);

	CgamePerfStats() {}
	explicit CgamePerfStats(int p_capacity) { capacity = MAX(p_capacity, 1); }
};
