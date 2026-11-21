/**************************************************************************/
/*  ai_update_scheduler.cpp                                                 */
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

#include "ai_update_scheduler.h"

#include "core/object/class_db.h"

uint64_t AIUpdateScheduler::hash_agent_id(int64_t p_agent_id) {
	// SplitMix64 finalizer: reproducible across machines and runs, without
	// signed integer overflow. Stable ID -> stable slot, independent of
	// iteration order and random-number-generator state.
	uint64_t x = uint64_t(p_agent_id) + 0x9e3779b97f4a7c15ULL;
	x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ULL;
	x = (x ^ (x >> 27)) * 0x94d049bb133111ebULL;
	return x ^ (x >> 31);
}

void AIUpdateScheduler::set_slots_per_cycle(int p_slots) {
	ERR_FAIL_COND_MSG(p_slots < 1 || p_slots > 64, "AI update scheduler must use between 1 and 64 slots.");
	slots_per_cycle = p_slots;
}

int AIUpdateScheduler::get_agent_slot(int64_t p_agent_id) const {
	return int(hash_agent_id(p_agent_id) % uint64_t(slots_per_cycle));
}

bool AIUpdateScheduler::is_due(int64_t p_agent_id, int64_t p_tick_index, bool p_urgent) const {
	if (p_tick_index < 0) {
		return false;
	}
	if (p_urgent) {
		return true;
	}
	return p_tick_index % slots_per_cycle == get_agent_slot(p_agent_id);
}

PackedByteArray AIUpdateScheduler::get_due_mask(const PackedInt64Array &p_agent_ids, int64_t p_tick_index) const {
	PackedByteArray result;
	// A malformed or unexpectedly huge cohort must never allocate unbounded
	// memory. Callers can use the established per-agent API as a fallback.
	if (p_tick_index < 0 || p_agent_ids.size() > 4096) {
		return result;
	}
	result.resize(p_agent_ids.size());
	const int slot = int(p_tick_index % slots_per_cycle);
	uint8_t *flags = result.ptrw();
	for (int i = 0; i < p_agent_ids.size(); i++) {
		flags[i] = int(hash_agent_id(p_agent_ids[i]) % uint64_t(slots_per_cycle)) == slot ? 1 : 0;
	}
	return result;
}

int AIUpdateScheduler::ticks_until_due(int64_t p_agent_id, int64_t p_tick_index) const {
	if (p_tick_index < 0) {
		return -1;
	}
	const int current_slot = int(p_tick_index % slots_per_cycle);
	const int agent_slot = get_agent_slot(p_agent_id);
	return (agent_slot + slots_per_cycle - current_slot) % slots_per_cycle;
}

void AIUpdateScheduler::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_slots_per_cycle", "slots"), &AIUpdateScheduler::set_slots_per_cycle);
	ClassDB::bind_method(D_METHOD("get_slots_per_cycle"), &AIUpdateScheduler::get_slots_per_cycle);
	ClassDB::bind_method(D_METHOD("get_agent_slot", "agent_id"), &AIUpdateScheduler::get_agent_slot);
	ClassDB::bind_method(D_METHOD("is_due", "agent_id", "tick_index", "urgent"), &AIUpdateScheduler::is_due, DEFVAL(false));
	ClassDB::bind_method(D_METHOD("get_due_mask", "agent_ids", "tick_index"), &AIUpdateScheduler::get_due_mask);
	ClassDB::bind_method(D_METHOD("ticks_until_due", "agent_id", "tick_index"), &AIUpdateScheduler::ticks_until_due);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "slots_per_cycle", PROPERTY_HINT_RANGE, "1,64,1"), "set_slots_per_cycle", "get_slots_per_cycle");
}
