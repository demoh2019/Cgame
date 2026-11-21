/**************************************************************************/
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#include "gameplay_cue_queue.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

bool GameplayCueQueue::_valid_tag(const StringName &p_tag) {
	const String tag = p_tag;
	return tag.begins_with("GameplayCue.") && tag.length() <= 160 &&
			!tag.ends_with(".") && !tag.contains("..");
}

bool GameplayCueQueue::_valid_priority(int p_priority) {
	return p_priority >= 0 && p_priority <= MAX_PRIORITY;
}

int GameplayCueQueue::_find_active(const Vector<ActiveCue> &p_active, const StringName &p_tag) {
	for (int i = 0; i < p_active.size(); ++i) {
		if (p_active[i].tag == p_tag) {
			return i;
		}
	}
	return -1;
}

const char *GameplayCueQueue::_event_label(EventType p_type) {
	switch (p_type) {
		case EVENT_STARTED: return "started";
		case EVENT_UPDATED: return "updated";
		case EVENT_STOPPED: return "stopped";
		case EVENT_EXECUTED: return "executed";
	}
	return "unknown";
}

bool GameplayCueQueue::_enqueue(Vector<PendingCue> &r_queue, const StringName &p_tag, EventType p_type, int p_stacks, double p_magnitude, int p_priority) {
	for (int i = 0; i < r_queue.size(); ++i) {
		PendingCue &entry = r_queue.write[i];
		if (entry.tag == p_tag && entry.type == p_type) {
			entry.count = MIN(entry.count + 1, MAX_DUPLICATES);
			entry.stacks = p_stacks;
			entry.magnitude = MAX(entry.magnitude, p_magnitude);
			entry.priority = MAX(entry.priority, p_priority);
			return true;
		}
	}
	if (r_queue.size() >= MAX_PENDING) {
		return false;
	}
	PendingCue cue;
	cue.tag = p_tag;
	cue.type = p_type;
	cue.stacks = p_stacks;
	cue.priority = p_priority;
	cue.magnitude = p_magnitude;
	r_queue.push_back(cue);
	return true;
}

bool GameplayCueQueue::emit_cue(const StringName &p_tag, double p_magnitude, int p_priority) {
	if (!_valid_tag(p_tag) || !Math::is_finite(p_magnitude) ||
			p_magnitude < 0.0 || p_magnitude > 1000000.0 || !_valid_priority(p_priority)) {
		return false;
	}
	if (pending.size() < MAX_PENDING) {
		return _enqueue(pending, p_tag, EVENT_EXECUTED, 0, p_magnitude, p_priority);
	}
	// A repeated pulse must still coalesce even when all slots are occupied.
	for (const PendingCue &entry : pending) {
		if (entry.type == EVENT_EXECUTED && entry.tag == p_tag) {
			return _enqueue(pending, p_tag, EVENT_EXECUTED, 0, p_magnitude, p_priority);
		}
	}
	// Niagara-style significance admission. Evict only an expendable
	// transient with strictly lower priority. First matching entry wins
	// ties (oldest of the lowest-priority candidates). Never discard
	// persistent started/updated/stopped events: they drive visual cleanup.
	int victim = -1;
	for (int i = 0; i < pending.size(); ++i) {
		const PendingCue &entry = pending[i];
		if (entry.type == EVENT_EXECUTED && entry.priority < p_priority &&
				(victim < 0 || entry.priority < pending[victim].priority)) {
			victim = i;
		}
	}
	if (victim < 0) {
		if (rejected_transient_count < 2147483647) {
			++rejected_transient_count;
		}
		return false;
	}
	// Reuse the queue's usual validation/coalescing. Do not partially
	// discard a queued cue if admission unexpectedly fails.
	Vector<PendingCue> next_pending = pending;
	next_pending.remove_at(victim);
	if (!_enqueue(next_pending, p_tag, EVENT_EXECUTED, 0, p_magnitude, p_priority)) {
		return false;
	}
	pending = next_pending;
	if (evicted_transient_count < 2147483647) {
		++evicted_transient_count;
	}
	return true;
}

bool GameplayCueQueue::set_active(const StringName &p_tag, int p_stacks, int p_priority) {
	if (!_valid_tag(p_tag) || p_stacks < 0 || p_stacks > MAX_STACKS || !_valid_priority(p_priority)) {
		return false;
	}
	Dictionary snapshot = get_active_snapshot();
	if (p_stacks == 0) {
		snapshot.erase(p_tag);
	} else {
		snapshot[p_tag] = p_stacks;
	}
	return replace_active(snapshot, p_priority);
}

bool GameplayCueQueue::_enqueue_lifecycle(Vector<PendingCue> &r_queue, const StringName &p_tag,
		EventType p_type, int p_stacks, int p_priority, bool p_admit, int &r_evictions) {
	if (_enqueue(r_queue, p_tag, p_type, p_stacks, 1.0, p_priority)) {
		return true;
	}
	if (!p_admit) {
		return false;
	}
	// Full queue: evict only a strictly less-important expendable pulse.
	// Persistent stop/start/update cues must never be discarded, because
	// they are required to clean up already-visible local effects.
	int victim = -1;
	for (int i = 0; i < r_queue.size(); ++i) {
		const PendingCue &candidate = r_queue[i];
		if (candidate.type == EVENT_EXECUTED && candidate.priority < p_priority &&
				(victim < 0 || candidate.priority < r_queue[victim].priority)) {
			victim = i;
		}
	}
	if (victim < 0) {
		return false;
	}
	r_queue.remove_at(victim);
	if (!_enqueue(r_queue, p_tag, p_type, p_stacks, 1.0, p_priority)) {
		return false;
	}
	++r_evictions;
	return true;
}

bool GameplayCueQueue::_replace_active_internal(const Dictionary &p_snapshot, int p_priority, bool p_admit) {
	if (!_valid_priority(p_priority) || p_snapshot.size() > MAX_ACTIVE) {
		return false;
	}
	Vector<ActiveCue> validated;
	for (const Variant &key : p_snapshot) {
		if (key.get_type() != Variant::STRING && key.get_type() != Variant::STRING_NAME) {
			return false;
		}
		const StringName tag = key;
		if (!_valid_tag(tag) || _find_active(validated, tag) >= 0) {
			return false;
		}
		const Variant value = p_snapshot[key];
		if (value.get_type() != Variant::INT) {
			return false;
		}
		const int64_t stacks = int64_t(value);
		if (stacks < 0 || stacks > MAX_STACKS) {
			return false;
		}
		if (stacks > 0) {
			ActiveCue cue;
			cue.tag = tag;
			cue.stacks = int(stacks);
			validated.push_back(cue);
		}
	}
	Vector<PendingCue> next_pending = pending;
	int preemptions = 0;
	for (const ActiveCue &previous : active) {
		if (_find_active(validated, previous.tag) < 0) {
			if (!_enqueue_lifecycle(next_pending, previous.tag, EVENT_STOPPED, 0, p_priority, p_admit, preemptions)) {
				return false;
			}
		}
	}
	for (const ActiveCue &current : validated) {
		const int old_index = _find_active(active, current.tag);
		if (old_index < 0) {
			if (!_enqueue_lifecycle(next_pending, current.tag, EVENT_STARTED, current.stacks, p_priority, p_admit, preemptions)) {
				return false;
			}
		} else if (active[old_index].stacks != current.stacks) {
			if (!_enqueue_lifecycle(next_pending, current.tag, EVENT_UPDATED, current.stacks, p_priority, p_admit, preemptions)) {
				return false;
			}
		}
	}
	// Commit only after full validation AND pending-capacity preflight.
	active = validated;
	pending = next_pending;
	// A failed snapshot never mutates either the queue or its diagnostics.
	evicted_transient_count = preemptions > 2147483647 - evicted_transient_count ?
			2147483647 : evicted_transient_count + preemptions;
	return true;
}

bool GameplayCueQueue::replace_active(const Dictionary &p_snapshot, int p_priority) {
	return _replace_active_internal(p_snapshot, p_priority, false);
}

bool GameplayCueQueue::replace_active_resilient(const Dictionary &p_snapshot, int p_priority) {
	return _replace_active_internal(p_snapshot, p_priority, true);
}

Dictionary GameplayCueQueue::get_active_snapshot() const {
	Dictionary snapshot;
	for (const ActiveCue &cue : active) {
		snapshot[cue.tag] = cue.stacks;
	}
	return snapshot;
}

int GameplayCueQueue::get_active_stacks(const StringName &p_tag) const {
	const int index = _find_active(active, p_tag);
	return index < 0 ? 0 : active[index].stacks;
}

Array GameplayCueQueue::take_events(int p_max_events) {
	Array events;
	if (p_max_events <= 0) {
		return events;
	}
	const int limit = MIN(p_max_events, 32);
	while (!pending.is_empty() && events.size() < limit) {
		int best = 0;
		for (int i = 1; i < pending.size(); ++i) {
			if (pending[i].priority > pending[best].priority) {
				best = i;
			}
		}
		const PendingCue &item = pending[best];
		Dictionary event;
		event["tag"] = item.tag;
		event["event"] = _event_label(item.type);
		event["stacks"] = item.stacks;
		event["magnitude"] = item.magnitude;
		event["priority"] = item.priority;
		event["count"] = item.count;
		events.push_back(event);
		pending.remove_at(best);
	}
	return events;
}

void GameplayCueQueue::reset() {
	active.clear();
	pending.clear();
	evicted_transient_count = 0;
	rejected_transient_count = 0;
}

void GameplayCueQueue::_bind_methods() {
	ClassDB::bind_method(D_METHOD("emit_cue", "tag", "magnitude", "priority"), &GameplayCueQueue::emit_cue, DEFVAL(1.0), DEFVAL(0));
	ClassDB::bind_method(D_METHOD("set_active", "tag", "stacks", "priority"), &GameplayCueQueue::set_active, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("replace_active", "snapshot", "priority"), &GameplayCueQueue::replace_active, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("replace_active_resilient", "snapshot", "priority"), &GameplayCueQueue::replace_active_resilient, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("get_active_snapshot"), &GameplayCueQueue::get_active_snapshot);
	ClassDB::bind_method(D_METHOD("get_active_stacks", "tag"), &GameplayCueQueue::get_active_stacks);
	ClassDB::bind_method(D_METHOD("is_active", "tag"), &GameplayCueQueue::is_active);
	ClassDB::bind_method(D_METHOD("take_events", "max_events"), &GameplayCueQueue::take_events, DEFVAL(32));
	ClassDB::bind_method(D_METHOD("get_active_count"), &GameplayCueQueue::get_active_count);
	ClassDB::bind_method(D_METHOD("get_pending_count"), &GameplayCueQueue::get_pending_count);
	ClassDB::bind_method(D_METHOD("get_evicted_transient_count"), &GameplayCueQueue::get_evicted_transient_count);
	ClassDB::bind_method(D_METHOD("get_rejected_transient_count"), &GameplayCueQueue::get_rejected_transient_count);
	ClassDB::bind_method(D_METHOD("reset"), &GameplayCueQueue::reset);
}
