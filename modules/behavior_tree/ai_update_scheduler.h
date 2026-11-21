/**************************************************************************/
/*  ai_update_scheduler.h                                                 */
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

#include <cstdint>

// Stateless, deterministic time-slot scheduler for heavy AI decisions.
// A stable hashed slot spreads NPC decisions over an N-tick cycle without
// per-agent dictionaries, wall-clock dependencies, or frame-order bias.
// It does not pause gameplay movement, damage, physics, or mandatory checks.
class AIUpdateScheduler : public RefCounted {
	GDCLASS(AIUpdateScheduler, RefCounted);

	int slots_per_cycle = 4;

	static uint64_t hash_agent_id(int64_t p_agent_id);

protected:
	static void _bind_methods();

public:
	void set_slots_per_cycle(int p_slots);
	int get_slots_per_cycle() const { return slots_per_cycle; }

	// Each stable ID is assigned one slot in [0, slots_per_cycle).
	int get_agent_slot(int64_t p_agent_id) const;

	// True exactly once per slots_per_cycle simulation ticks for each ID.
	// Urgent decisions bypass staggering. Negative ticks are invalid.
	bool is_due(int64_t p_agent_id, int64_t p_tick_index, bool p_urgent = false) const;

	// Number of simulation ticks until the next eligible slot (0 = now).
	// -1 for a negative tick index.
	int ticks_until_due(int64_t p_agent_id, int64_t p_tick_index) const;
};
