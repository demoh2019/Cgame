/**************************************************************************/
/*  stream_request_queue.cpp                                              */
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

#include "stream_request_queue.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/templates/hash_set.h"

void StreamRequestQueue::set_max_in_flight(int p_max) {
	max_in_flight = MAX(p_max, 0);
}

int StreamRequestQueue::get_max_in_flight() const {
	return max_in_flight;
}

int64_t StreamRequestQueue::get_newest_generation() const {
	return newest_generation;
}

bool StreamRequestQueue::request(const Vector2i &p_cell, double p_priority, int64_t p_generation) {
	// A non-finite priority is not a strict ordering key. Reject it before
	// updating the generation or allowing it to enter the scheduling heap.
	if (!Math::is_finite(p_priority)) {
		stat_rejected_invalid++;
		return false;
	}
	if (p_generation < newest_generation) {
		stat_rejected_stale++;
		return false;
	}
	newest_generation = p_generation;
	HashMap<Vector2i, Req>::Iterator it = reqs.find(p_cell);
	if (it) {
		Req &r = it->value;
		r.generation = MAX(r.generation, p_generation);
		if (r.state == STATE_CANCELLED) {
			r.state = STATE_IN_FLIGHT;
			stat_revived++;
		} else if (r.state == STATE_QUEUED) {
			r.priority = MAX(r.priority, p_priority);
		}
		return true;
	}
	Req n;
	n.priority = p_priority;
	n.generation = p_generation;
	n.seq = seq_counter++;
	reqs[p_cell] = n;
	stat_requested++;
	return true;
}

int StreamRequestQueue::cancel_stale(int64_t p_current_generation, const TypedArray<Vector2i> &p_keep_cells) {
	newest_generation = MAX(newest_generation, p_current_generation);
	HashSet<Vector2i> keep;
	for (int i = 0; i < p_keep_cells.size(); i++) {
		keep.insert(p_keep_cells[i]);
	}
	int cancelled = 0;
	LocalVector<Vector2i> keys;
	for (const KeyValue<Vector2i, Req> &kv : reqs) {
		keys.push_back(kv.key);
	}
	for (const Vector2i &cell : keys) {
		Req &r = reqs[cell];
		if (keep.has(cell)) {
			r.generation = MAX(r.generation, p_current_generation);
			if (r.state == STATE_CANCELLED) {
				r.state = STATE_IN_FLIGHT;
				stat_revived++;
			}
			continue;
		}
		if (r.generation >= p_current_generation || r.state == STATE_CANCELLED) {
			continue;
		}
		cancelled++;
		if (r.state == STATE_QUEUED) {
			reqs.erase(cell);
			stat_cancelled_queued++;
		} else {
			r.state = STATE_CANCELLED;
			stat_cancelled_inflight++;
		}
	}
	return cancelled;
}

namespace {
struct QueuedEntry {
	Vector2i cell;
	double priority;
	int64_t seq;
};

struct QueuedEntryBefore {
	bool operator()(const QueuedEntry &p_a, const QueuedEntry &p_b) const {
		if (p_a.priority != p_b.priority) {
			return p_a.priority > p_b.priority;
		}
		return p_a.seq < p_b.seq;
	}
};

// A heap with the weakest candidate at its root, matching the GDScript fallback.
void push_worst(LocalVector<QueuedEntry> &r_heap, const QueuedEntry &p_entry) {
	r_heap.push_back(p_entry);
	uint32_t child = r_heap.size() - 1;
	const QueuedEntryBefore before;
	while (child > 0) {
		const uint32_t parent = (child - 1) / 2;
		if (!before(r_heap[parent], r_heap[child])) {
			break;
		}
		SWAP(r_heap[parent], r_heap[child]);
		child = parent;
	}
}

void fix_worst_root(LocalVector<QueuedEntry> &r_heap) {
	uint32_t parent = 0;
	const QueuedEntryBefore before;
	while (true) {
		const uint32_t left = parent * 2 + 1;
		if (left >= r_heap.size()) {
			break;
		}
		uint32_t worst = left;
		const uint32_t right = left + 1;
		if (right < r_heap.size() && before(r_heap[left], r_heap[right])) {
			worst = right;
		}
		if (!before(r_heap[parent], r_heap[worst])) {
			break;
		}
		SWAP(r_heap[parent], r_heap[worst]);
		parent = worst;
	}
}
} //namespace

TypedArray<Vector2i> StreamRequestQueue::next_batch(int p_budget) {
	TypedArray<Vector2i> out;
	int allowed = p_budget;
	if (max_in_flight > 0) {
		allowed = MIN(allowed, max_in_flight - in_flight_count());
	}
	if (allowed <= 0) {
		return out;
	}
	LocalVector<QueuedEntry> queued;
	// Small frame budgets need only the best K entries, not a full queue sort.
	const bool use_heap = allowed <= 128;
	const QueuedEntryBefore before;
	for (const KeyValue<Vector2i, Req> &kv : reqs) {
		if (kv.value.state != STATE_QUEUED) {
			continue;
		}
		const QueuedEntry entry = { kv.key, kv.value.priority, kv.value.seq };
		if (!use_heap) {
			queued.push_back(entry);
		} else if (queued.size() < (uint32_t)allowed) {
			push_worst(queued, entry);
		} else if (before(entry, queued[0])) {
			queued[0] = entry;
			fix_worst_root(queued);
		}
	}
	queued.sort_custom<QueuedEntryBefore>();
	for (uint32_t i = 0; i < queued.size() && (int)i < allowed; i++) {
		reqs[queued[i].cell].state = STATE_IN_FLIGHT;
		active_workers++;
		out.push_back(queued[i].cell);
	}
	return out;
}

bool StreamRequestQueue::complete(const Vector2i &p_cell, const Variant &p_result) {
	HashMap<Vector2i, Req>::Iterator it = reqs.find(p_cell);
	if (!it) {
		stat_dropped_late++;
		return false;
	}
	Req &r = it->value;
	if (r.state == STATE_CANCELLED || r.state == STATE_QUEUED || r.generation < newest_generation) {
		if (r.state != STATE_QUEUED) {
			active_workers--;
			reqs.erase(p_cell);
		}
		stat_dropped_late++;
		return false;
	}
	Done d;
	d.cell = p_cell;
	d.result = p_result;
	d.generation = r.generation;
	active_workers--;
	reqs.erase(p_cell);
	stat_completed++;
	completed.push_back(d);
	return true;
}

TypedArray<Dictionary> StreamRequestQueue::take_completed() {
	TypedArray<Dictionary> out;
	for (const Done &d : completed) {
		Dictionary e;
		e["cell"] = d.cell;
		e["result"] = d.result;
		e["generation"] = d.generation;
		out.push_back(e);
	}
	completed.clear();
	return out;
}

bool StreamRequestQueue::has_request(const Vector2i &p_cell) const {
	return reqs.has(p_cell);
}

int StreamRequestQueue::state_of(const Vector2i &p_cell) const {
	HashMap<Vector2i, Req>::ConstIterator it = reqs.find(p_cell);
	if (!it) {
		return -1;
	}
	return it->value.state;
}

int StreamRequestQueue::queued_count() const {
	return reqs.size() - active_workers;
}

int StreamRequestQueue::in_flight_count() const {
	return active_workers;
}

Dictionary StreamRequestQueue::stats() const {
	Dictionary s;
	s["requested"] = stat_requested;
	s["completed"] = stat_completed;
	s["cancelled_queued"] = stat_cancelled_queued;
	s["cancelled_inflight"] = stat_cancelled_inflight;
	s["dropped_late"] = stat_dropped_late;
	s["rejected_stale"] = stat_rejected_stale;
	s["rejected_invalid"] = stat_rejected_invalid;
	s["revived"] = stat_revived;
	s["queued"] = queued_count();
	s["in_flight"] = in_flight_count();
	return s;
}

void StreamRequestQueue::clear() {
	reqs.clear();
	active_workers = 0;
	completed.clear();
	newest_generation = 0;
	seq_counter = 0;
	stat_requested = stat_completed = stat_cancelled_queued = stat_cancelled_inflight = 0;
	stat_dropped_late = stat_rejected_stale = stat_rejected_invalid = stat_revived = 0;
}

void StreamRequestQueue::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_max_in_flight", "max_in_flight"), &StreamRequestQueue::set_max_in_flight);
	ClassDB::bind_method(D_METHOD("get_max_in_flight"), &StreamRequestQueue::get_max_in_flight);
	ClassDB::bind_method(D_METHOD("get_newest_generation"), &StreamRequestQueue::get_newest_generation);

	ClassDB::bind_method(D_METHOD("request", "cell", "priority", "generation"), &StreamRequestQueue::request);
	ClassDB::bind_method(D_METHOD("cancel_stale", "current_generation", "keep_cells"), &StreamRequestQueue::cancel_stale);
	ClassDB::bind_method(D_METHOD("next_batch", "budget"), &StreamRequestQueue::next_batch);
	ClassDB::bind_method(D_METHOD("complete", "cell", "result"), &StreamRequestQueue::complete);
	ClassDB::bind_method(D_METHOD("take_completed"), &StreamRequestQueue::take_completed);
	ClassDB::bind_method(D_METHOD("has_request", "cell"), &StreamRequestQueue::has_request);
	ClassDB::bind_method(D_METHOD("state_of", "cell"), &StreamRequestQueue::state_of);
	ClassDB::bind_method(D_METHOD("queued_count"), &StreamRequestQueue::queued_count);
	ClassDB::bind_method(D_METHOD("in_flight_count"), &StreamRequestQueue::in_flight_count);
	ClassDB::bind_method(D_METHOD("stats"), &StreamRequestQueue::stats);
	ClassDB::bind_method(D_METHOD("clear"), &StreamRequestQueue::clear);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_in_flight", PROPERTY_HINT_RANGE, "0,1024,1,or_greater"), "set_max_in_flight", "get_max_in_flight");

	BIND_ENUM_CONSTANT(STATE_QUEUED);
	BIND_ENUM_CONSTANT(STATE_IN_FLIGHT);
	BIND_ENUM_CONSTANT(STATE_CANCELLED);
}
