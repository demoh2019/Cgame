/**************************************************************************/
/*  cgame_trace.cpp                                                       */
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

#include "cgame_trace.h"

#include "core/config/engine.h"
#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/os/os.h"
#include "core/os/thread.h"
#include "core/templates/hash_set.h"
#include "core/templates/local_vector.h"

CgameTrace *CgameTrace::singleton = nullptr;
std::atomic<bool> CgameTrace::active{ false };

namespace {

constexpr uint32_t MAX_SCOPE_DEPTH = 64;

struct OpenScope {
	const char *name = nullptr;
	const char *cat = nullptr;
	uint64_t start = 0;
};

// Owned by exactly one writer thread; other threads only read `head`, `events` and `name` (under the state mutex).
struct ThreadBuffer {
	CgameTrace::Event *events = nullptr;
	uint64_t capacity = 0;
	uint64_t mask = 0;
	std::atomic<uint64_t> head{ 0 };
	std::atomic<uint64_t> clear_base{ 0 };
	uint64_t tid = 0;
	String name; // Guarded by state_mutex.
	uint64_t frame_cursor = 0; // Guarded by state_mutex.

	// Writer-thread private state.
	OpenScope stack[MAX_SCOPE_DEPTH];
	uint32_t depth = 0;
	uint32_t epoch_seen = 0;
	HashMap<String, const char *> intern_cache;

	ThreadBuffer(uint64_t p_tid, uint64_t p_capacity) {
		tid = p_tid;
		capacity = 16;
		while (capacity < p_capacity) {
			capacity <<= 1;
		}
		mask = capacity - 1;
		events = memnew_arr(CgameTrace::Event, capacity);
	}
	~ThreadBuffer() {
		memdelete_arr(events);
	}
};

Mutex state_mutex;
LocalVector<ThreadBuffer *> buffers;
Mutex intern_mutex;
HashMap<String, CharString> intern_table;
std::atomic<bool> shut_down{ false };
std::atomic<uint32_t> clear_epoch{ 0 };
std::atomic<int> buffer_capacity_setting{ 16384 };
thread_local ThreadBuffer *tl_buffer = nullptr;

ThreadBuffer *get_buffer() {
	if (likely(tl_buffer != nullptr)) {
		return tl_buffer;
	}
	if (shut_down.load(std::memory_order_relaxed)) {
		return nullptr;
	}
	ThreadBuffer *b = memnew(ThreadBuffer(Thread::get_caller_id(), (uint64_t)buffer_capacity_setting.load(std::memory_order_relaxed)));
	b->epoch_seen = clear_epoch.load(std::memory_order_relaxed);
	MutexLock lock(state_mutex);
	buffers.push_back(b);
	tl_buffer = b;
	return b;
}

_FORCE_INLINE_ uint64_t now_usec() {
	return OS::get_singleton()->get_ticks_usec();
}

_FORCE_INLINE_ void push_event(ThreadBuffer *p_buffer, const CgameTrace::Event &p_event) {
	const uint64_t h = p_buffer->head.load(std::memory_order_relaxed);
	p_buffer->events[h & p_buffer->mask] = p_event;
	p_buffer->head.store(h + 1, std::memory_order_release);
}

const char *intern_fast(ThreadBuffer *p_buffer, const String &p_string) {
	if (const char *const *cached = p_buffer->intern_cache.getptr(p_string)) {
		return *cached;
	}
	const char *ptr = CgameTrace::intern(p_string);
	p_buffer->intern_cache.insert(p_string, ptr);
	return ptr;
}

// Copies the events with index >= p_from that are provably intact. Optimistic: slots the writer may
// have overwritten while copying are dropped. Returns the head the copy is current to.
uint64_t snapshot_buffer(ThreadBuffer *p_buffer, uint64_t p_from, LocalVector<CgameTrace::Event> &r_out) {
	const uint64_t cap = p_buffer->capacity;
	const uint64_t h1 = p_buffer->head.load(std::memory_order_acquire);
	uint64_t start = h1 > cap ? h1 - cap : 0;
	start = MAX(start, p_buffer->clear_base.load(std::memory_order_relaxed));
	start = MAX(start, p_from);
	if (start >= h1) {
		return h1;
	}
	LocalVector<CgameTrace::Event> tmp;
	tmp.reserve(h1 - start);
	for (uint64_t i = start; i < h1; i++) {
		tmp.push_back(p_buffer->events[i & p_buffer->mask]);
	}
	const uint64_t h2 = p_buffer->head.load(std::memory_order_acquire);
	// The writer may be mid-way through writing index h2, which reuses the slot of index h2 - cap.
	const uint64_t safe = (h2 + 1 > cap) ? h2 + 1 - cap : 0;
	uint64_t first_valid = 0;
	if (safe > start) {
		first_valid = MIN(safe - start, (uint64_t)tmp.size());
	}
	for (uint64_t i = first_valid; i < tmp.size(); i++) {
		r_out.push_back(tmp[i]);
	}
	return h1;
}

struct ExportItem {
	CgameTrace::Event e;
	uint64_t tid = 0;
};

struct ExportOrder {
	_FORCE_INLINE_ bool operator()(const ExportItem &p_a, const ExportItem &p_b) const {
		if (p_a.e.ts != p_b.e.ts) {
			return p_a.e.ts < p_b.e.ts;
		}
		// At equal start a longer scope comes first so parents enclose their children.
		return p_a.e.dur > p_b.e.dur;
	}
};

struct PctDesc {
	_FORCE_INLINE_ bool operator()(const Dictionary &p_a, const Dictionary &p_b) const {
		return (double)p_a["pct"] > (double)p_b["pct"];
	}
};

} // namespace

const char *CgameTrace::intern(const String &p_string) {
	MutexLock lock(intern_mutex);
	if (const CharString *existing = intern_table.getptr(p_string)) {
		return existing->get_data();
	}
	HashMap<String, CharString>::Iterator it = intern_table.insert(p_string, p_string.utf8());
	return it->value.get_data();
}

void CgameTrace::scope_begin(const char *p_name, const char *p_category) {
	ThreadBuffer *b = get_buffer();
	if (unlikely(b == nullptr)) {
		return;
	}
	const uint32_t epoch = clear_epoch.load(std::memory_order_relaxed);
	if (unlikely(b->epoch_seen != epoch)) {
		b->depth = 0;
		b->epoch_seen = epoch;
	}
	if (b->depth < MAX_SCOPE_DEPTH) {
		OpenScope &s = b->stack[b->depth];
		s.name = p_name;
		s.cat = p_category;
		s.start = now_usec();
	}
	b->depth++;
}

void CgameTrace::scope_end() {
	ThreadBuffer *b = tl_buffer;
	if (unlikely(b == nullptr)) {
		return;
	}
	const uint32_t epoch = clear_epoch.load(std::memory_order_relaxed);
	if (unlikely(b->epoch_seen != epoch)) {
		b->depth = 0;
		b->epoch_seen = epoch;
	}
	if (b->depth == 0) {
		return;
	}
	b->depth--;
	if (b->depth >= MAX_SCOPE_DEPTH) {
		return;
	}
	const OpenScope &s = b->stack[b->depth];
	const uint64_t now = now_usec();
	Event e;
	e.phase = PHASE_COMPLETE;
	e.name = s.name;
	e.cat = s.cat;
	e.ts = s.start;
	e.dur = now > s.start ? now - s.start : 0;
	push_event(b, e);
}

void CgameTrace::emit_counter(const char *p_name, double p_value) {
	ThreadBuffer *b = get_buffer();
	if (unlikely(b == nullptr)) {
		return;
	}
	Event e;
	e.phase = PHASE_COUNTER;
	e.name = p_name;
	e.cat = "counter";
	e.ts = now_usec();
	e.value = p_value;
	push_event(b, e);
}

void CgameTrace::emit_instant(const char *p_name, const char *p_args_json) {
	ThreadBuffer *b = get_buffer();
	if (unlikely(b == nullptr)) {
		return;
	}
	Event e;
	e.phase = PHASE_INSTANT;
	e.name = p_name;
	e.cat = "instant";
	e.args = p_args_json;
	e.ts = now_usec();
	push_event(b, e);
}

void CgameTrace::emit_flow(bool p_start, int64_t p_id, const char *p_name) {
	if (!is_active()) {
		return;
	}
	ThreadBuffer *b = get_buffer();
	if (unlikely(b == nullptr)) {
		return;
	}
	Event e;
	e.phase = p_start ? PHASE_FLOW_START : PHASE_FLOW_END;
	e.name = p_name;
	e.cat = "flow";
	e.id = p_id;
	e.ts = now_usec();
	push_event(b, e);
}

void CgameTrace::shutdown_buffers() {
	shut_down.store(true);
	active.store(false);
	MutexLock lock(state_mutex);
	for (ThreadBuffer *b : buffers) {
		memdelete(b);
	}
	buffers.clear();
	tl_buffer = nullptr;
}

void CgameTrace::set_enabled(bool p_enabled) {
	active.store(p_enabled, std::memory_order_relaxed);
}

bool CgameTrace::is_enabled() const {
	return active.load(std::memory_order_relaxed);
}

void CgameTrace::set_max_events(int p_count) {
	max_events = CLAMP(p_count, 16, 1 << 24);
	buffer_capacity_setting.store(max_events);
}

void CgameTrace::set_max_frames(int p_count) {
	max_frames = MAX(p_count, 1);
	MutexLock lock(state_mutex);
	while (frame_list.size() > max_frames) {
		frame_list.pop_front();
	}
}

void CgameTrace::begin(const String &p_name, const String &p_category) {
	if (!is_active()) {
		return;
	}
	ThreadBuffer *b = get_buffer();
	if (unlikely(b == nullptr)) {
		return;
	}
	scope_begin(intern_fast(b, p_name), intern_fast(b, p_category));
}

void CgameTrace::end() {
	if (!is_active()) {
		return;
	}
	scope_end();
}

Variant CgameTrace::measure(const String &p_name, const Callable &p_callable, const String &p_category) {
	Variant ret;
	Callable::CallError ce;
	if (!is_active()) {
		p_callable.callp(nullptr, 0, ret, ce);
		return ret;
	}
	begin(p_name, p_category);
	p_callable.callp(nullptr, 0, ret, ce);
	end();
	return ret;
}

void CgameTrace::counter(const String &p_name, double p_value) {
	if (!is_active()) {
		return;
	}
	ThreadBuffer *b = get_buffer();
	if (unlikely(b == nullptr)) {
		return;
	}
	emit_counter(intern_fast(b, p_name), p_value);
}

void CgameTrace::instant(const String &p_name, const Dictionary &p_args) {
	if (!is_active()) {
		return;
	}
	ThreadBuffer *b = get_buffer();
	if (unlikely(b == nullptr)) {
		return;
	}
	const char *args = p_args.is_empty() ? nullptr : intern(JSON::stringify(p_args, "", false));
	emit_instant(intern_fast(b, p_name), args);
}

void CgameTrace::flow_start(int64_t p_id, const String &p_name) {
	if (!is_active()) {
		return;
	}
	emit_flow(true, p_id, intern(p_name));
}

void CgameTrace::flow_end(int64_t p_id, const String &p_name) {
	if (!is_active()) {
		return;
	}
	emit_flow(false, p_id, intern(p_name));
}

void CgameTrace::set_thread_name(const String &p_name) {
	ThreadBuffer *b = get_buffer();
	if (b == nullptr) {
		return;
	}
	MutexLock lock(state_mutex);
	b->name = p_name;
}

int CgameTrace::event_count() const {
	MutexLock lock(state_mutex);
	uint64_t total = 0;
	for (ThreadBuffer *b : buffers) {
		const uint64_t h = b->head.load(std::memory_order_acquire);
		uint64_t base = h > b->capacity ? h - b->capacity : 0;
		base = MAX(base, b->clear_base.load(std::memory_order_relaxed));
		total += h - base;
	}
	return (int)total;
}

int CgameTrace::thread_count() const {
	MutexLock lock(state_mutex);
	return (int)buffers.size();
}

void CgameTrace::clear() {
	MutexLock lock(state_mutex);
	clear_epoch.fetch_add(1);
	for (ThreadBuffer *b : buffers) {
		const uint64_t h = b->head.load(std::memory_order_acquire);
		b->clear_base.store(h);
		b->frame_cursor = h;
	}
	frame_list.clear();
	last_frame_usec = -1;
}

void CgameTrace::frame_marker(int64_t p_frame_index) {
	if (!is_active()) {
		return;
	}
	const int64_t now = (int64_t)now_usec();
	{
		MutexLock lock(state_mutex);
		if (last_frame_usec >= 0) {
			// Aggregate everything recorded since the previous marker, lock-free for the writers.
			HashMap<uint64_t, double> scope_totals;
			HashMap<uint64_t, double> counter_values;
			for (ThreadBuffer *b : buffers) {
				LocalVector<Event> tmp;
				b->frame_cursor = snapshot_buffer(b, b->frame_cursor, tmp);
				for (const Event &e : tmp) {
					if (e.phase == PHASE_COMPLETE) {
						scope_totals[(uint64_t)(uintptr_t)e.name] += (double)e.dur;
					} else if (e.phase == PHASE_COUNTER) {
						counter_values[(uint64_t)(uintptr_t)e.name] = e.value;
					}
				}
			}
			FrameRecord fr;
			fr.index = p_frame_index;
			fr.ms = double(now - last_frame_usec) / 1000.0;
			for (const KeyValue<uint64_t, double> &kv : scope_totals) {
				fr.scopes[String::utf8((const char *)(uintptr_t)kv.key)] += kv.value;
			}
			for (const KeyValue<uint64_t, double> &kv : counter_values) {
				fr.counters[String::utf8((const char *)(uintptr_t)kv.key)] = kv.value;
			}
			frame_list.push_back(fr);
			while (frame_list.size() > max_frames) {
				frame_list.pop_front();
			}
		} else {
			for (ThreadBuffer *b : buffers) {
				b->frame_cursor = b->head.load(std::memory_order_acquire);
			}
		}
		last_frame_usec = now;
	}
	ThreadBuffer *b = get_buffer();
	if (b == nullptr) {
		return;
	}
	Event e;
	e.phase = PHASE_FRAME;
	e.name = "frame";
	e.cat = "frame";
	e.value = (double)p_frame_index;
	e.ts = (uint64_t)now;
	push_event(b, e);
}

void CgameTrace::on_engine_frame(uint64_t p_process_frame) {
	if (auto_frame_markers && is_active()) {
		frame_marker((int64_t)p_process_frame);
	}
}

TypedArray<Dictionary> CgameTrace::frames() const {
	TypedArray<Dictionary> out;
	MutexLock lock(state_mutex);
	for (const FrameRecord &fr : frame_list) {
		Dictionary d;
		d["index"] = fr.index;
		d["ms"] = fr.ms;
		Dictionary scopes;
		for (const KeyValue<String, double> &kv : fr.scopes) {
			scopes[kv.key] = kv.value;
		}
		Dictionary counters;
		for (const KeyValue<String, double> &kv : fr.counters) {
			counters[kv.key] = kv.value;
		}
		d["scopes"] = scopes;
		d["counters"] = counters;
		out.push_back(d);
	}
	return out;
}

Dictionary CgameTrace::build_event_dict(const Event &p_event, uint64_t p_tid, int64_t p_pid) const {
	Dictionary rec;
	const String name = p_event.name ? String::utf8(p_event.name) : String();
	rec["name"] = name;
	rec["ts"] = (int64_t)p_event.ts;
	rec["pid"] = p_pid;
	rec["tid"] = (int64_t)p_tid;
	rec["cat"] = p_event.cat ? String::utf8(p_event.cat) : String("cpp");
	switch (p_event.phase) {
		case PHASE_COMPLETE: {
			rec["ph"] = "X";
			rec["dur"] = (int64_t)p_event.dur;
		} break;
		case PHASE_COUNTER: {
			rec["ph"] = "C";
			Dictionary args;
			args[name] = p_event.value;
			rec["args"] = args;
		} break;
		case PHASE_INSTANT: {
			rec["ph"] = "i";
			rec["s"] = "t";
			if (p_event.args) {
				Variant parsed = JSON::parse_string(String::utf8(p_event.args));
				if (parsed.get_type() == Variant::DICTIONARY) {
					rec["args"] = parsed;
				}
			}
		} break;
		case PHASE_FLOW_START: {
			rec["ph"] = "s";
			rec["id"] = p_event.id;
		} break;
		case PHASE_FLOW_END: {
			rec["ph"] = "f";
			rec["bp"] = "e";
			rec["id"] = p_event.id;
		} break;
		case PHASE_FRAME: {
			rec["ph"] = "i";
			rec["s"] = "t";
			Dictionary args;
			args["frame"] = (int64_t)p_event.value;
			rec["args"] = args;
		} break;
		default: {
		} break;
	}
	return rec;
}

String CgameTrace::export_chrome_json() const {
	LocalVector<ExportItem> items;
	HashMap<uint64_t, String> names;
	{
		MutexLock lock(state_mutex);
		for (ThreadBuffer *b : buffers) {
			LocalVector<Event> tmp;
			snapshot_buffer(b, 0, tmp);
			for (const Event &e : tmp) {
				ExportItem item;
				item.e = e;
				item.tid = b->tid;
				items.push_back(item);
			}
			if (!b->name.is_empty()) {
				names[b->tid] = b->name;
			}
		}
	}
	items.sort_custom<ExportOrder>();

	const int64_t pid = OS::get_singleton() ? (int64_t)OS::get_singleton()->get_process_id() : 0;
	const uint64_t main_tid = Thread::get_main_id();
	Array out;
	{
		Dictionary meta;
		meta["ph"] = "M";
		meta["name"] = "process_name";
		meta["pid"] = pid;
		meta["tid"] = (int64_t)main_tid;
		Dictionary args;
		args["name"] = "Cgame";
		meta["args"] = args;
		out.push_back(meta);
	}
	HashSet<uint64_t> seen;
	for (const ExportItem &item : items) {
		if (seen.has(item.tid)) {
			continue;
		}
		seen.insert(item.tid);
		Dictionary meta;
		meta["ph"] = "M";
		meta["name"] = "thread_name";
		meta["pid"] = pid;
		meta["tid"] = (int64_t)item.tid;
		Dictionary args;
		if (const String *n = names.getptr(item.tid)) {
			args["name"] = *n;
		} else {
			args["name"] = item.tid == main_tid ? String("main") : vformat("thread-%d", (int64_t)item.tid);
		}
		meta["args"] = args;
		out.push_back(meta);
	}
	for (const ExportItem &item : items) {
		out.push_back(build_event_dict(item.e, item.tid, pid));
	}
	Dictionary root;
	root["traceEvents"] = out;
	root["displayTimeUnit"] = "ms";
	return JSON::stringify(root, "", false);
}

bool CgameTrace::save(const String &p_path) const {
	Ref<FileAccess> f = FileAccess::open(p_path, FileAccess::WRITE);
	if (f.is_null()) {
		return false;
	}
	f->store_string(export_chrome_json());
	return true;
}

Dictionary CgameTrace::frame_stats() const {
	struct Acc {
		double total = 0.0;
		double max = 0.0;
	};
	HashMap<String, Acc> acc;
	int64_t n = 0;
	{
		MutexLock lock(state_mutex);
		n = frame_list.size();
		for (const FrameRecord &fr : frame_list) {
			for (const KeyValue<String, double> &kv : fr.scopes) {
				Acc &v = acc[kv.key];
				v.total += kv.value;
				v.max = MAX(v.max, kv.value);
			}
		}
	}
	Dictionary scopes;
	for (const KeyValue<String, Acc> &kv : acc) {
		Dictionary s;
		s["total"] = kv.value.total;
		s["avg"] = kv.value.total / (double)MAX<int64_t>(n, 1);
		s["max"] = kv.value.max;
		scopes[kv.key] = s;
	}
	Dictionary out;
	out["frames"] = n;
	out["scopes"] = scopes;
	return out;
}

bool CgameTrace::save_stats_json(const String &p_path) const {
	Ref<FileAccess> f = FileAccess::open(p_path, FileAccess::WRITE);
	if (f.is_null()) {
		return false;
	}
	f->store_string(JSON::stringify(frame_stats(), "\t"));
	return true;
}

Dictionary CgameTrace::load_stats_json(const String &p_path) const {
	if (!FileAccess::exists(p_path)) {
		return Dictionary();
	}
	Variant parsed = JSON::parse_string(FileAccess::get_file_as_string(p_path));
	if (parsed.get_type() == Variant::DICTIONARY) {
		return parsed;
	}
	return Dictionary();
}

Array CgameTrace::compare(const Dictionary &p_baseline, const Dictionary &p_current, double p_threshold_pct) {
	LocalVector<Dictionary> rows;
	const Dictionary base_scopes = p_baseline.get("scopes", Dictionary());
	const Dictionary cur_scopes = p_current.get("scopes", Dictionary());
	for (const Variant &key : cur_scopes.get_key_list()) {
		if (!base_scopes.has(key)) {
			continue;
		}
		const double base_avg = Dictionary(base_scopes[key]).get("avg", 0.0);
		const double cur_avg = Dictionary(cur_scopes[key]).get("avg", 0.0);
		if (base_avg <= 0.0) {
			continue;
		}
		const double pct = (cur_avg - base_avg) / base_avg * 100.0;
		if (pct > p_threshold_pct) {
			Dictionary row;
			row["scope"] = key;
			row["baseline_avg"] = base_avg;
			row["current_avg"] = cur_avg;
			row["pct"] = pct;
			rows.push_back(row);
		}
	}
	rows.sort_custom<PctDesc>();
	Array out;
	for (const Dictionary &row : rows) {
		out.push_back(row);
	}
	return out;
}

void CgameTrace::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_enabled", "enabled"), &CgameTrace::set_enabled);
	ClassDB::bind_method(D_METHOD("is_enabled"), &CgameTrace::is_enabled);
	ClassDB::bind_method(D_METHOD("set_auto_frame_markers", "enabled"), &CgameTrace::set_auto_frame_markers);
	ClassDB::bind_method(D_METHOD("is_auto_frame_markers"), &CgameTrace::is_auto_frame_markers);
	ClassDB::bind_method(D_METHOD("set_max_events", "count"), &CgameTrace::set_max_events);
	ClassDB::bind_method(D_METHOD("get_max_events"), &CgameTrace::get_max_events);
	ClassDB::bind_method(D_METHOD("set_max_frames", "count"), &CgameTrace::set_max_frames);
	ClassDB::bind_method(D_METHOD("get_max_frames"), &CgameTrace::get_max_frames);

	ClassDB::bind_method(D_METHOD("begin", "name", "category"), &CgameTrace::begin, DEFVAL("game"));
	ClassDB::bind_method(D_METHOD("end"), &CgameTrace::end);
	ClassDB::bind_method(D_METHOD("measure", "name", "callable", "category"), &CgameTrace::measure, DEFVAL("game"));
	ClassDB::bind_method(D_METHOD("counter", "name", "value"), &CgameTrace::counter);
	ClassDB::bind_method(D_METHOD("instant", "name", "args"), &CgameTrace::instant, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("frame_marker", "frame_index"), &CgameTrace::frame_marker);
	ClassDB::bind_method(D_METHOD("flow_start", "id", "name"), &CgameTrace::flow_start);
	ClassDB::bind_method(D_METHOD("flow_end", "id", "name"), &CgameTrace::flow_end);
	ClassDB::bind_method(D_METHOD("set_thread_name", "name"), &CgameTrace::set_thread_name);
	ClassDB::bind_method(D_METHOD("event_count"), &CgameTrace::event_count);
	ClassDB::bind_method(D_METHOD("thread_count"), &CgameTrace::thread_count);
	ClassDB::bind_method(D_METHOD("clear"), &CgameTrace::clear);
	ClassDB::bind_method(D_METHOD("frames"), &CgameTrace::frames);
	ClassDB::bind_method(D_METHOD("export_chrome_json"), &CgameTrace::export_chrome_json);
	ClassDB::bind_method(D_METHOD("save", "path"), &CgameTrace::save);
	ClassDB::bind_method(D_METHOD("frame_stats"), &CgameTrace::frame_stats);
	ClassDB::bind_method(D_METHOD("save_stats_json", "path"), &CgameTrace::save_stats_json);
	ClassDB::bind_method(D_METHOD("load_stats_json", "path"), &CgameTrace::load_stats_json);
	ClassDB::bind_static_method("CgameTrace", D_METHOD("compare", "baseline", "current", "threshold_pct"), &CgameTrace::compare, DEFVAL(10.0));

	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enabled"), "set_enabled", "is_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "auto_frame_markers"), "set_auto_frame_markers", "is_auto_frame_markers");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_events", PROPERTY_HINT_RANGE, "16,16777216,1"), "set_max_events", "get_max_events");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_frames", PROPERTY_HINT_RANGE, "1,1000000,1"), "set_max_frames", "get_max_frames");
}

CgameTrace::CgameTrace() {
	singleton = this;
}

CgameTrace::~CgameTrace() {
	if (singleton == this) {
		singleton = nullptr;
	}
}
