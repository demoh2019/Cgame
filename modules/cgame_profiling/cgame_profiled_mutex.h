/**************************************************************************/
/*  cgame_profiled_mutex.h                                                */
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
#include "core/templates/hash_map.h"

#include <atomic>

// Recursive mutex that records acquisition count, contended acquisitions, wait time, hold time and
// the last owner thread. A global registry feeds report() (sorted by total wait). sync_point()
// times arbitrary blocking calls (for example RenderingServer force_sync or readbacks) and flags
// long CPU/GPU sync stalls. When CgameTrace is active, contended waits appear as "lock" scopes.
class CgameProfiledMutex : public RefCounted {
	GDCLASS(CgameProfiledMutex, RefCounted);

	struct SyncStat {
		String name;
		int64_t count = 0;
		double total_ms = 0.0;
		double max_ms = 0.0;
		int64_t long_count = 0;
	};

	Mutex mutex;
	String name;
	const char *wait_label = nullptr;

	// Written only while `mutex` is held; atomics make cross-thread report() reads well-defined.
	int depth = 0;
	uint64_t hold_start_us = 0;
	std::atomic<uint64_t> owner_thread_id{ 0 };
	std::atomic<uint64_t> acquisitions{ 0 };
	std::atomic<uint64_t> contended{ 0 };
	std::atomic<uint64_t> total_wait_us{ 0 };
	std::atomic<uint64_t> max_wait_us{ 0 };
	std::atomic<uint64_t> total_hold_us{ 0 };
	std::atomic<uint64_t> max_hold_us{ 0 };
	bool registered = false;

	static Mutex registry_mutex;
	static LocalVector<CgameProfiledMutex *> registry;
	static Mutex sync_mutex;
	static HashMap<String, SyncStat> syncs;
	static double long_sync_threshold;

	void _register();

protected:
	static void _bind_methods();

public:
	void set_name(const String &p_name) { name = p_name; }
	String get_name() const { return name; }

	void lock();
	bool try_lock();
	void unlock();
	Dictionary stats() const;
	void reset();

	static Ref<CgameProfiledMutex> create(const String &p_name);
	static void clear_registry();
	static Array report();
	static Variant sync_point(const String &p_name, const Callable &p_callable);
	static void record_sync(const String &p_name, uint64_t p_usec);
	static Array sync_report();
	static PackedStringArray long_syncs();
	static void set_long_sync_threshold_ms(double p_ms);
	static double get_long_sync_threshold_ms();

	CgameProfiledMutex();
	~CgameProfiledMutex();
};
