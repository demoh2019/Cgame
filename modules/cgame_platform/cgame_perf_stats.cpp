/**************************************************************************/
/*  cgame_perf_stats.cpp                                                  */
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

#include "cgame_perf_stats.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void CgamePerfStats::Ring::push(float p_value) {
	const int size = data.size();
	data.write[head] = p_value;
	head = (head + 1) % size;
	count = MIN(count + 1, size);
	total++;
}

Vector<float> CgamePerfStats::Ring::to_array(int p_n) const {
	const int size = data.size();
	const int take = p_n <= 0 ? count : MIN(p_n, count);
	Vector<float> out;
	out.resize(take);
	const int start = (head - take + size * 2) % size;
	for (int i = 0; i < take; i++) {
		out.write[i] = data[(start + i) % size];
	}
	return out;
}

void CgamePerfStats::set_capacity(int p_capacity) {
	capacity = MAX(p_capacity, 1);
}

void CgamePerfStats::push(const String &p_series, double p_value) {
	if (!Math::is_finite(p_value)) {
		return;
	}
	HashMap<String, Ring>::Iterator it = rings.find(p_series);
	if (it == rings.end()) {
		Ring ring;
		ring.init(capacity);
		it = rings.insert(p_series, ring);
	}
	it->value.push((float)p_value);
}

bool CgamePerfStats::has_series(const String &p_series) const {
	return rings.has(p_series);
}

TypedArray<String> CgamePerfStats::names() const {
	TypedArray<String> out;
	for (const KeyValue<String, Ring> &kv : rings) {
		out.push_back(kv.key);
	}
	return out;
}

PackedFloat32Array CgamePerfStats::series(const String &p_series, int p_window) const {
	PackedFloat32Array out;
	HashMap<String, Ring>::ConstIterator it = rings.find(p_series);
	if (it == rings.end()) {
		return out;
	}
	out.append_array(it->value.to_array(p_window));
	return out;
}

int CgamePerfStats::count(const String &p_series) const {
	HashMap<String, Ring>::ConstIterator it = rings.find(p_series);
	return it == rings.end() ? 0 : it->value.count;
}

int64_t CgamePerfStats::total_pushed(const String &p_series) const {
	HashMap<String, Ring>::ConstIterator it = rings.find(p_series);
	return it == rings.end() ? 0 : it->value.total;
}

double CgamePerfStats::last(const String &p_series) const {
	HashMap<String, Ring>::ConstIterator it = rings.find(p_series);
	if (it == rings.end()) {
		return 0.0;
	}
	const Vector<float> s = it->value.to_array(1);
	return s.is_empty() ? 0.0 : s[0];
}

double CgamePerfStats::percentile_sorted(const Vector<float> &p_sorted, double p_percent) {
	const int n = p_sorted.size();
	if (n == 0) {
		return 0.0;
	}
	const double rank = CLAMP(p_percent, 0.0, 100.0) / 100.0 * (double)(n - 1);
	const int lo = (int)Math::floor(rank);
	const int hi = MIN(lo + 1, n - 1);
	return Math::lerp((double)p_sorted[lo], (double)p_sorted[hi], rank - (double)lo);
}

double CgamePerfStats::percentile(const String &p_series, double p_percent, int p_window) const {
	HashMap<String, Ring>::ConstIterator it = rings.find(p_series);
	if (it == rings.end()) {
		return 0.0;
	}
	Vector<float> s = it->value.to_array(p_window);
	if (s.is_empty()) {
		return 0.0;
	}
	s.sort();
	return percentile_sorted(s, p_percent);
}

double CgamePerfStats::average(const String &p_series, int p_window) const {
	HashMap<String, Ring>::ConstIterator it = rings.find(p_series);
	if (it == rings.end()) {
		return 0.0;
	}
	const Vector<float> s = it->value.to_array(p_window);
	if (s.is_empty()) {
		return 0.0;
	}
	double sum = 0.0;
	for (int i = 0; i < s.size(); i++) {
		sum += s[i];
	}
	return sum / (double)s.size();
}

double CgamePerfStats::max_value(const String &p_series, int p_window) const {
	HashMap<String, Ring>::ConstIterator it = rings.find(p_series);
	if (it == rings.end()) {
		return 0.0;
	}
	const Vector<float> s = it->value.to_array(p_window);
	double m = 0.0;
	for (int i = 0; i < s.size(); i++) {
		m = MAX(m, (double)s[i]);
	}
	return m;
}

Dictionary CgamePerfStats::summary(const String &p_series, int p_window) const {
	Dictionary d;
	d["last"] = last(p_series);
	d["avg"] = average(p_series, p_window);
	d["p50"] = percentile(p_series, 50.0, p_window);
	d["p95"] = percentile(p_series, 95.0, p_window);
	d["p99"] = percentile(p_series, 99.0, p_window);
	d["max"] = max_value(p_series, p_window);
	d["samples"] = count(p_series);
	return d;
}

void CgamePerfStats::clear() {
	rings.clear();
}

void CgamePerfStats::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_capacity", "capacity"), &CgamePerfStats::set_capacity);
	ClassDB::bind_method(D_METHOD("get_capacity"), &CgamePerfStats::get_capacity);
	ClassDB::bind_method(D_METHOD("push", "series", "value"), &CgamePerfStats::push);
	ClassDB::bind_method(D_METHOD("has_series", "series"), &CgamePerfStats::has_series);
	ClassDB::bind_method(D_METHOD("names"), &CgamePerfStats::names);
	ClassDB::bind_method(D_METHOD("series", "series", "window"), &CgamePerfStats::series, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("count", "series"), &CgamePerfStats::count);
	ClassDB::bind_method(D_METHOD("total_pushed", "series"), &CgamePerfStats::total_pushed);
	ClassDB::bind_method(D_METHOD("last", "series"), &CgamePerfStats::last);
	ClassDB::bind_method(D_METHOD("percentile", "series", "percent", "window"), &CgamePerfStats::percentile, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("average", "series", "window"), &CgamePerfStats::average, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("max_value", "series", "window"), &CgamePerfStats::max_value, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("summary", "series", "window"), &CgamePerfStats::summary, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("clear"), &CgamePerfStats::clear);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "capacity", PROPERTY_HINT_RANGE, "1,100000,1,or_greater"), "set_capacity", "get_capacity");
}
