/**************************************************************************/
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

#include "core/object/ref_counted.h"
#include "core/string/string_name.h"
#include "core/templates/vector.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// A bounded, deterministic GameplayCue event bridge inspired by Unreal GAS.
// Rendering and sound playback remain the application's responsibility.
// Snapshot updates are atomic, and event delivery never executes gameplay.
class GameplayCueQueue : public RefCounted {
	GDCLASS(GameplayCueQueue, RefCounted);

public:
	static constexpr int MAX_ACTIVE = 128;
	static constexpr int MAX_PENDING = 128;
	static constexpr int MAX_DUPLICATES = 32;
	static constexpr int MAX_STACKS = 65535;
	static constexpr int MAX_PRIORITY = 7;

private:
	enum EventType {
		EVENT_STARTED,
		EVENT_UPDATED,
		EVENT_STOPPED,
		EVENT_EXECUTED,
	};
	struct ActiveCue {
		StringName tag;
		int stacks = 1;
	};
	struct PendingCue {
		StringName tag;
		EventType type = EVENT_EXECUTED;
		int stacks = 0;
		int count = 1;
		int priority = 0;
		double magnitude = 1.0;
	};

	Vector<ActiveCue> active;
	Vector<PendingCue> pending;
	int evicted_transient_count = 0;
	int rejected_transient_count = 0;

	static bool _valid_tag(const StringName &p_tag);
	static bool _valid_priority(int p_priority);
	static int _find_active(const Vector<ActiveCue> &p_active, const StringName &p_tag);
	static bool _enqueue(Vector<PendingCue> &r_queue, const StringName &p_tag, EventType p_type, int p_stacks, double p_magnitude, int p_priority);
	static bool _enqueue_lifecycle(Vector<PendingCue> &r_queue, const StringName &p_tag,
			EventType p_type, int p_stacks, int p_priority, bool p_admit, int &r_evictions);
	bool _replace_active_internal(const Dictionary &p_snapshot, int p_priority, bool p_admit);
	static const char *_event_label(EventType p_type);

protected:
	static void _bind_methods();

public:
	// Immediate, nonpersistent cue (particles, sound, HUD, etc.). Repeats
	// coalesce by tag, capped at MAX_DUPLICATES per undrained cue.
	// On a full queue, a higher-priority transient may evict the oldest
	// lowest-priority transient; persistent status lifecycle events are safe.
	bool emit_cue(const StringName &p_tag, double p_magnitude = 1.0, int p_priority = 0);
	// Batched transient dispatch: prevalidate all entries and commit only
	// when every one can be admitted. Existing lifecycle events are never
	// evicted; a failure leaves the queue and diagnostics unchanged.
	// Each dictionary requires tag, magnitude and priority; max 32 entries.
	bool emit_cues_batch(const Array &p_events);
	// 0 stacks stops an active cue; an unchanged value never emits another event.
	bool set_active(const StringName &p_tag, int p_stacks, int p_priority = 0);
	// Replace the active set transactionally, emitting started/updated/stopped
	// events only for changed tags. Invalid input preserves state and events.
	bool replace_active(const Dictionary &p_snapshot, int p_priority = 0);
	// Important status start/stop/stack changes can atomically make room by
	// evicting lower-priority transient cues. Existing lifecycle cues and
	// equal/higher-priority transients are never evicted; all-or-nothing.
	bool replace_active_resilient(const Dictionary &p_snapshot, int p_priority = 0);
	// Update only exact/dotted descendants of a replicated cue namespace.
	// Preserve active local/FX cues and their pending lifecycle. Validate first,
	// skip identical snapshots, and roll back if event capacity is exhausted.
	bool replace_active_branch(const StringName &p_branch, const Dictionary &p_snapshot, int p_priority = 0);
	Dictionary get_active_snapshot() const;
	int get_active_stacks(const StringName &p_tag) const;
	bool is_active(const StringName &p_tag) const { return get_active_stacks(p_tag) > 0; }
	// Highest priority first, stable insertion order on equal priority.
	// Event fields: tag, event, stacks, magnitude, priority, count.
	Array take_events(int p_max_events = 32);
	int get_active_count() const { return active.size(); }
	int get_pending_count() const { return pending.size(); }
	// Diagnostic counters since the last reset. Lifecycle cues are never evicted.
	int get_evicted_transient_count() const { return evicted_transient_count; }
	int get_rejected_transient_count() const { return rejected_transient_count; }
	void reset();
};
