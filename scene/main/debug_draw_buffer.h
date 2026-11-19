/**************************************************************************/
/*  debug_draw_buffer.h                                             */
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

#include "core/templates/local_vector.h"

// Time-to-live bookkeeping for debug shapes, independent of rendering.
//
// A shape with a duration of zero lives for exactly one *drawn* frame. Shapes can be added from
// physics callbacks that run several times, or not at all, between two rendered frames, so a
// shape is only dropped after a frame was actually presented with it (or after it grew old
// enough that no frame can be coming, e.g. headless runs).
template <typename Segment>
class DebugDrawBuffer {
public:
	struct Entry {
		Segment segment;
		double expire_time = 0.0; // Seconds; only used when `timed`.
		uint64_t added_frame = 0;
		bool timed = false;
		bool drawn = false;
	};

private:
	LocalVector<Entry> entries;
	uint32_t max_entries = 200000;
	uint32_t dropped = 0;

public:
	void set_max_entries(uint32_t p_max) { max_entries = p_max; }
	uint32_t get_dropped_count() const { return dropped; }
	uint32_t size() const { return entries.size(); }
	bool is_empty() const { return entries.is_empty(); }
	const LocalVector<Entry> &get_entries() const { return entries; }
	void clear() { entries.clear(); }

	// Returns false if the buffer is full and the segment was discarded.
	bool add(const Segment &p_segment, double p_now, double p_duration, uint64_t p_frame) {
		if (entries.size() >= max_entries) {
			dropped++;
			return false;
		}
		Entry entry;
		entry.segment = p_segment;
		entry.timed = p_duration > 0.0;
		entry.expire_time = p_now + p_duration;
		entry.added_frame = p_frame;
		entries.push_back(entry);
		return true;
	}

	// Called once at the start of every frame: drops what has been shown long enough.
	void begin_frame(double p_now, uint64_t p_frame) {
		uint32_t kept = 0;
		for (uint32_t i = 0; i < entries.size(); i++) {
			const Entry &entry = entries[i];
			// With no renderer (headless) nothing ever reports "drawn"; two frames is enough age.
			const bool shown = entry.drawn || p_frame >= entry.added_frame + 2;
			const bool expired = entry.timed ? p_now >= entry.expire_time : true;
			if (shown && expired) {
				continue;
			}
			if (kept != i) {
				entries[kept] = entry;
			}
			kept++;
		}
		entries.resize(kept);
	}

	// Called right before a frame is rendered.
	void mark_drawn() {
		for (Entry &entry : entries) {
			entry.drawn = true;
		}
	}
};
