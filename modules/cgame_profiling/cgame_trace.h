/**************************************************************************/
/*  cgame_trace.h                                                         */
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

#include "core/object/class_db.h"
#include "core/object/object.h"
#include "core/os/mutex.h"
#include "core/templates/hash_map.h"
#include "core/templates/list.h"
#include "core/variant/dictionary.h"
#include "core/variant/typed_array.h"

#include <atomic>

// Low-overhead trace capture with Chrome / Perfetto JSON export.
//
// Recording model: every thread owns a fixed-size ring buffer that only that thread writes
// (single producer, no locks, no allocation on the hot path). Readers (export, frame markers)
// snapshot buffers optimistically and discard slots that may have been overwritten meanwhile.
// While tracing is disabled every recording entry point costs one relaxed atomic load.
//
// Names passed to the C++ entry points must have static storage duration (string literals);
// script-facing methods intern their strings first.
class CgameTrace : public Object {
	GDCLASS(CgameTrace, Object);

public:
	enum Phase : uint8_t {
		PHASE_COMPLETE, // Chrome "X".
		PHASE_COUNTER, // "C".
		PHASE_INSTANT, // "i".
		PHASE_FLOW_START, // "s".
		PHASE_FLOW_END, // "f".
		PHASE_FRAME, // "i" with category "frame".
	};

	struct Event {
		uint64_t ts = 0;
		uint64_t dur = 0;
		const char *name = nullptr;
		const char *cat = nullptr;
		const char *args = nullptr; // JSON object text or nullptr.
		double value = 0.0;
		int64_t id = 0;
		uint8_t phase = PHASE_INSTANT;
	};

	struct FrameRecord {
		int64_t index = 0;
		double ms = 0.0;
		HashMap<String, double> scopes; // Microseconds per scope name.
		HashMap<String, double> counters;
	};

private:
	static CgameTrace *singleton;
	static std::atomic<bool> active;

	bool auto_frame_markers = true;
	int max_events = 16384;
	int max_frames = 4096;
	int64_t last_frame_usec = -1;
	List<FrameRecord> frame_list;

	Dictionary build_event_dict(const Event &p_event, uint64_t p_tid, int64_t p_pid) const;

protected:
	static void _bind_methods();

public:
	static CgameTrace *get_singleton() { return singleton; }

	// Hot path (usable from any C++ code, no singleton instance required).
	static _FORCE_INLINE_ bool is_active() { return active.load(std::memory_order_relaxed); }
	static void scope_begin(const char *p_name, const char *p_category = "cpp");
	static void scope_end();
	static void emit_counter(const char *p_name, double p_value);
	static void emit_instant(const char *p_name, const char *p_args_json = nullptr);
	static void emit_flow(bool p_start, int64_t p_id, const char *p_name);
	// Interns a runtime string; the returned pointer stays valid until engine shutdown.
	static const char *intern(const String &p_string);
	static void shutdown_buffers();

	// Script-facing API.
	void set_enabled(bool p_enabled);
	bool is_enabled() const;
	void set_auto_frame_markers(bool p_enabled) { auto_frame_markers = p_enabled; }
	bool is_auto_frame_markers() const { return auto_frame_markers; }
	void set_max_events(int p_count);
	int get_max_events() const { return max_events; }
	void set_max_frames(int p_count);
	int get_max_frames() const { return max_frames; }

	void begin(const String &p_name, const String &p_category = "game");
	void end();
	Variant measure(const String &p_name, const Callable &p_callable, const String &p_category = "game");
	void counter(const String &p_name, double p_value);
	void instant(const String &p_name, const Dictionary &p_args = Dictionary());
	void frame_marker(int64_t p_frame_index);
	void flow_start(int64_t p_id, const String &p_name);
	void flow_end(int64_t p_id, const String &p_name);
	void set_thread_name(const String &p_name);
	int event_count() const;
	int thread_count() const;
	void clear();

	TypedArray<Dictionary> frames() const;
	String export_chrome_json() const;
	bool save(const String &p_path) const;
	Dictionary frame_stats() const;
	bool save_stats_json(const String &p_path) const;
	Dictionary load_stats_json(const String &p_path) const;
	static Array compare(const Dictionary &p_baseline, const Dictionary &p_current, double p_threshold_pct = 10.0);

	// Called once per main loop iteration by the engine frame hook.
	void on_engine_frame(uint64_t p_process_frame);

	CgameTrace();
	~CgameTrace();
};

// RAII scope; costs one relaxed atomic load when tracing is disabled.
struct CgameTraceScope {
	bool on = false;
	_FORCE_INLINE_ explicit CgameTraceScope(const char *p_name, const char *p_category = "cpp") {
		on = CgameTrace::is_active();
		if (on) {
			CgameTrace::scope_begin(p_name, p_category);
		}
	}
	_FORCE_INLINE_ ~CgameTraceScope() {
		if (on) {
			CgameTrace::scope_end();
		}
	}
};

#define CGAME_TRACE_SCOPE(m_name) ::CgameTraceScope GD_UNIQUE_NAME(_cgame_trace_scope_)(m_name)
#define CGAME_TRACE_SCOPE_CAT(m_name, m_category) ::CgameTraceScope GD_UNIQUE_NAME(_cgame_trace_scope_)(m_name, m_category)
#define CGAME_TRACE_COUNTER(m_name, m_value) \
	do { \
		if (::CgameTrace::is_active()) { \
			::CgameTrace::emit_counter(m_name, (double)(m_value)); \
		} \
	} while (0)
#define CGAME_TRACE_INSTANT(m_name) \
	do { \
		if (::CgameTrace::is_active()) { \
			::CgameTrace::emit_instant(m_name); \
		} \
	} while (0)
