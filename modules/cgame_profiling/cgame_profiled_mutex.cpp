/**************************************************************************/
/*  cgame_profiled_mutex.cpp                                              */
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

#include "cgame_profiled_mutex.h"

#include "cgame_trace.h"

#include "core/object/class_db.h"
#include "core/os/os.h"
#include "core/os/thread.h"
#include "core/templates/local_vector.h"

Mutex CgameProfiledMutex::registry_mutex;
LocalVector<CgameProfiledMutex *> CgameProfiledMutex::registry;
Mutex CgameProfiledMutex::sync_mutex;
HashMap<String, CgameProfiledMutex::SyncStat> CgameProfiledMutex::syncs;
double CgameProfiledMutex::long_sync_threshold = 2.0;

namespace {
_FORCE_INLINE_ uint64_t now_usec() {
	return OS::get_singleton()->get_ticks_usec();
}
_FORCE_INLINE_ void add_relaxed(std::atomic<uint64_t> &r_value, uint64_t p_add) {
	r_value.store(r_value.load(std::memory_order_relaxed) + p_add, std::memory_order_relaxed);
}
_FORCE_INLINE_ void max_relaxed(std::atomic<uint64_t> &r_value, uint64_t p_candidate) {
	if (p_candidate > r_value.load(std::memory_order_relaxed)) {
		r_value.store(p_candidate, std::memory_order_relaxed);
	}
}
} // namespace

CgameProfiledMutex::CgameProfiledMutex() {
}

CgameProfiledMutex::~CgameProfiledMutex() {
	if (registered) {
		MutexLock lock(registry_mutex);
		registry.erase(this);
	}
}

void CgameProfiledMutex::_register() {
	MutexLock lock(registry_mutex);
	if (!registered) {
		registry.push_back(this);
		registered = true;
	}
}

void CgameProfiledMutex::lock() {
	const uint64_t t0 = now_usec();
	bool was_contended = false;
	if (!mutex.try_lock()) {
		was_contended = true;
		const bool tracing = CgameTrace::is_active();
		if (tracing) {
			if (wait_label == nullptr) {
				wait_label = CgameTrace::intern("wait:" + name);
			}
			CgameTrace::scope_begin(wait_label, "lock");
		}
		mutex.lock();
		if (tracing) {
			CgameTrace::scope_end();
		}
	}
	const uint64_t waited = now_usec() - t0;
	// Statistics are only touched while the mutex is held.
	if (depth == 0) {
		hold_start_us = now_usec();
		owner_thread_id.store(Thread::get_caller_id(), std::memory_order_relaxed);
		add_relaxed(acquisitions, 1);
		if (was_contended) {
			add_relaxed(contended, 1);
			add_relaxed(total_wait_us, waited);
			max_relaxed(max_wait_us, waited);
		}
	}
	depth++;
}

bool CgameProfiledMutex::try_lock() {
	if (!mutex.try_lock()) {
		return false;
	}
	if (depth == 0) {
		hold_start_us = now_usec();
		owner_thread_id.store(Thread::get_caller_id(), std::memory_order_relaxed);
		add_relaxed(acquisitions, 1);
	}
	depth++;
	return true;
}

void CgameProfiledMutex::unlock() {
	ERR_FAIL_COND_MSG(depth <= 0, "CgameProfiledMutex: unlock() without a matching lock().");
	depth--;
	if (depth == 0) {
		const uint64_t held = now_usec() - hold_start_us;
		add_relaxed(total_hold_us, held);
		max_relaxed(max_hold_us, held);
	}
	mutex.unlock();
}

Dictionary CgameProfiledMutex::stats() const {
	Dictionary d;
	d["name"] = name;
	d["acquisitions"] = (int64_t)acquisitions.load(std::memory_order_relaxed);
	d["contended"] = (int64_t)contended.load(std::memory_order_relaxed);
	d["total_wait_ms"] = double(total_wait_us.load(std::memory_order_relaxed)) / 1000.0;
	d["max_wait_ms"] = double(max_wait_us.load(std::memory_order_relaxed)) / 1000.0;
	d["total_hold_ms"] = double(total_hold_us.load(std::memory_order_relaxed)) / 1000.0;
	d["max_hold_ms"] = double(max_hold_us.load(std::memory_order_relaxed)) / 1000.0;
	d["owner_thread_id"] = (int64_t)owner_thread_id.load(std::memory_order_relaxed);
	return d;
}

void CgameProfiledMutex::reset() {
	acquisitions.store(0);
	contended.store(0);
	total_wait_us.store(0);
	max_wait_us.store(0);
	total_hold_us.store(0);
	max_hold_us.store(0);
}

Ref<CgameProfiledMutex> CgameProfiledMutex::create(const String &p_name) {
	Ref<CgameProfiledMutex> m;
	m.instantiate();
	m->name = p_name;
	m->_register();
	return m;
}

void CgameProfiledMutex::clear_registry() {
	{
		MutexLock lock(registry_mutex);
		for (CgameProfiledMutex *m : registry) {
			m->registered = false;
		}
		registry.clear();
	}
	MutexLock lock(sync_mutex);
	syncs.clear();
}

namespace {
struct MutexRowOrder {
	_FORCE_INLINE_ bool operator()(const Dictionary &p_a, const Dictionary &p_b) const {
		if ((double)p_a["total_wait_ms"] == (double)p_b["total_wait_ms"]) {
			return (double)p_a["total_hold_ms"] > (double)p_b["total_hold_ms"];
		}
		return (double)p_a["total_wait_ms"] > (double)p_b["total_wait_ms"];
	}
};
struct SyncRowOrder {
	_FORCE_INLINE_ bool operator()(const Dictionary &p_a, const Dictionary &p_b) const {
		return (double)p_a["total_ms"] > (double)p_b["total_ms"];
	}
};
} // namespace

// Mutex stats sorted by total wait time (most contended first).
Array CgameProfiledMutex::report() {
	LocalVector<Dictionary> rows;
	{
		MutexLock lock(registry_mutex);
		for (const CgameProfiledMutex *m : registry) {
			rows.push_back(m->stats());
		}
	}
	rows.sort_custom<MutexRowOrder>();
	Array out;
	for (const Dictionary &r : rows) {
		out.push_back(r);
	}
	return out;
}

void CgameProfiledMutex::record_sync(const String &p_name, uint64_t p_usec) {
	const double ms = double(p_usec) / 1000.0;
	MutexLock lock(sync_mutex);
	SyncStat &s = syncs[p_name];
	s.name = p_name;
	s.count++;
	s.total_ms += ms;
	s.max_ms = MAX(s.max_ms, ms);
	if (ms >= long_sync_threshold) {
		s.long_count++;
	}
}

// Runs `p_callable`, timing it as a CPU/GPU sync point. Returns the callable's result.
Variant CgameProfiledMutex::sync_point(const String &p_name, const Callable &p_callable) {
	const uint64_t t0 = now_usec();
	Variant ret;
	Callable::CallError ce;
	p_callable.callp(nullptr, 0, ret, ce);
	record_sync(p_name, now_usec() - t0);
	return ret;
}

Array CgameProfiledMutex::sync_report() {
	LocalVector<Dictionary> rows;
	{
		MutexLock lock(sync_mutex);
		for (const KeyValue<String, SyncStat> &kv : syncs) {
			Dictionary d;
			d["name"] = kv.value.name;
			d["count"] = kv.value.count;
			d["total_ms"] = kv.value.total_ms;
			d["max_ms"] = kv.value.max_ms;
			d["long_count"] = kv.value.long_count;
			rows.push_back(d);
		}
	}
	rows.sort_custom<SyncRowOrder>();
	Array out;
	for (const Dictionary &r : rows) {
		out.push_back(r);
	}
	return out;
}

// Names of sync points that exceeded the long-sync threshold at least once.
PackedStringArray CgameProfiledMutex::long_syncs() {
	PackedStringArray out;
	const Array rows = sync_report();
	for (int i = 0; i < rows.size(); i++) {
		const Dictionary r = rows[i];
		if ((int64_t)r["long_count"] > 0) {
			out.push_back(r["name"]);
		}
	}
	return out;
}

void CgameProfiledMutex::set_long_sync_threshold_ms(double p_ms) {
	MutexLock lock(sync_mutex);
	long_sync_threshold = MAX(p_ms, 0.0);
}

double CgameProfiledMutex::get_long_sync_threshold_ms() {
	MutexLock lock(sync_mutex);
	return long_sync_threshold;
}

void CgameProfiledMutex::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_name", "name"), &CgameProfiledMutex::set_name);
	ClassDB::bind_method(D_METHOD("get_name"), &CgameProfiledMutex::get_name);
	ClassDB::bind_method(D_METHOD("lock"), &CgameProfiledMutex::lock);
	ClassDB::bind_method(D_METHOD("try_lock"), &CgameProfiledMutex::try_lock);
	ClassDB::bind_method(D_METHOD("unlock"), &CgameProfiledMutex::unlock);
	ClassDB::bind_method(D_METHOD("stats"), &CgameProfiledMutex::stats);
	ClassDB::bind_method(D_METHOD("reset"), &CgameProfiledMutex::reset);
	ClassDB::bind_static_method("CgameProfiledMutex", D_METHOD("create", "name"), &CgameProfiledMutex::create);
	ClassDB::bind_static_method("CgameProfiledMutex", D_METHOD("clear_registry"), &CgameProfiledMutex::clear_registry);
	ClassDB::bind_static_method("CgameProfiledMutex", D_METHOD("report"), &CgameProfiledMutex::report);
	ClassDB::bind_static_method("CgameProfiledMutex", D_METHOD("sync_point", "name", "callable"), &CgameProfiledMutex::sync_point);
	ClassDB::bind_static_method("CgameProfiledMutex", D_METHOD("sync_report"), &CgameProfiledMutex::sync_report);
	ClassDB::bind_static_method("CgameProfiledMutex", D_METHOD("long_syncs"), &CgameProfiledMutex::long_syncs);
	ClassDB::bind_static_method("CgameProfiledMutex", D_METHOD("set_long_sync_threshold_ms", "ms"), &CgameProfiledMutex::set_long_sync_threshold_ms);
	ClassDB::bind_static_method("CgameProfiledMutex", D_METHOD("get_long_sync_threshold_ms"), &CgameProfiledMutex::get_long_sync_threshold_ms);

	ADD_PROPERTY(PropertyInfo(Variant::STRING, "name"), "set_name", "get_name");
}
