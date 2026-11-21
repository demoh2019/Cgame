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
	return _enqueue(pending, p_tag, EVENT_EXECUTED, 0, p_magnitude, p_priority);
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

bool GameplayCueQueue::replace_active(const Dictionary &p_snapshot, int p_priority) {
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
	for (const ActiveCue &previous : active) {
		if (_find_active(validated, previous.tag) < 0) {
			if (!_enqueue(next_pending, previous.tag, EVENT_STOPPED, 0, 0.0, p_priority)) {
				return false;
			}
		}
	}
	for (const ActiveCue &current : validated) {
		const int old_index = _find_active(active, current.tag);
		if (old_index < 0) {
			if (!_enqueue(next_pending, current.tag, EVENT_STARTED, current.stacks, 1.0, p_priority)) {
				return false;
			}
		} else if (active[old_index].stacks != current.stacks) {
			if (!_enqueue(next_pending, current.tag, EVENT_UPDATED, current.stacks, 1.0, p_priority)) {
				return false;
			}
		}
	}
	// Commit only after full validation AND pending-capacity preflight.
	active = validated;
	pending = next_pending;
	return true;
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
}

void GameplayCueQueue::_bind_methods() {
	ClassDB::bind_method(D_METHOD("emit_cue", "tag", "magnitude", "priority"), &GameplayCueQueue::emit_cue, DEFVAL(1.0), DEFVAL(0));
	ClassDB::bind_method(D_METHOD("set_active", "tag", "stacks", "priority"), &GameplayCueQueue::set_active, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("replace_active", "snapshot", "priority"), &GameplayCueQueue::replace_active, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("get_active_snapshot"), &GameplayCueQueue::get_active_snapshot);
	ClassDB::bind_method(D_METHOD("get_active_stacks", "tag"), &GameplayCueQueue::get_active_stacks);
	ClassDB::bind_method(D_METHOD("is_active", "tag"), &GameplayCueQueue::is_active);
	ClassDB::bind_method(D_METHOD("take_events", "max_events"), &GameplayCueQueue::take_events, DEFVAL(32));
	ClassDB::bind_method(D_METHOD("get_active_count"), &GameplayCueQueue::get_active_count);
	ClassDB::bind_method(D_METHOD("get_pending_count"), &GameplayCueQueue::get_pending_count);
	ClassDB::bind_method(D_METHOD("reset"), &GameplayCueQueue::reset);
}
