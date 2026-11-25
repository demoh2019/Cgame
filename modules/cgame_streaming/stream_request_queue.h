/**************************************************************************/
/*  stream_request_queue.h                                                */
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

#include "core/math/vector2i.h"
#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "core/templates/local_vector.h"
#include "core/variant/typed_array.h"

// Prioritised streaming request queue with generations.
class StreamRequestQueue : public RefCounted {
	GDCLASS(StreamRequestQueue, RefCounted);

public:
	enum State {
		STATE_QUEUED,
		STATE_IN_FLIGHT,
		STATE_CANCELLED,
	};

private:
	struct Req {
		double priority = 0.0;
		int64_t generation = 0;
		State state = STATE_QUEUED;
		int64_t seq = 0;
	};

	struct Done {
		Vector2i cell;
		Variant result;
		int64_t generation = 0;
	};

	int max_in_flight = 0;
	int64_t newest_generation = 0;
	HashMap<Vector2i, Req> reqs;
	int64_t seq_counter = 0;
	LocalVector<Done> completed;

	int64_t stat_requested = 0;
	int64_t stat_completed = 0;
	int64_t stat_cancelled_queued = 0;
	int64_t stat_cancelled_inflight = 0;
	int64_t stat_dropped_late = 0;
	int64_t stat_rejected_stale = 0;
	int64_t stat_rejected_invalid = 0;
	int64_t stat_revived = 0;

	int _count(State p_state) const;

protected:
	static void _bind_methods();

public:
	void set_max_in_flight(int p_max);
	int get_max_in_flight() const;
	int64_t get_newest_generation() const;

	bool request(const Vector2i &p_cell, double p_priority, int64_t p_generation);
	int cancel_stale(int64_t p_current_generation, const TypedArray<Vector2i> &p_keep_cells);
	TypedArray<Vector2i> next_batch(int p_budget);
	bool complete(const Vector2i &p_cell, const Variant &p_result);
	TypedArray<Dictionary> take_completed();
	bool has_request(const Vector2i &p_cell) const;
	int state_of(const Vector2i &p_cell) const;
	int queued_count() const;
	int in_flight_count() const;
	Dictionary stats() const;
	void clear();
};

VARIANT_ENUM_CAST(StreamRequestQueue::State);
