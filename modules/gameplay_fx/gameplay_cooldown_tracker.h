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
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// Explicit-clock, bounded tag cooldowns inspired by Unreal GAS. Does not
// execute gameplay or access wall time; an authoritative owner must call tick.
class GameplayCooldownTracker : public RefCounted {
	GDCLASS(GameplayCooldownTracker, RefCounted);

public:
	static constexpr int MAX_COOLDOWNS = 256;
	static constexpr double MAX_DURATION = 604800.0; // Seven days.

private:
	struct Cooldown {
		StringName tag;
		double remaining = 0.0;
	};
	Vector<Cooldown> cooldowns;
	int _find(const StringName &p_tag) const;
	static bool _valid_tag(const StringName &p_tag);
	static bool _valid_duration(double p_seconds);

protected:
	static void _bind_methods();

public:
	// Zero removes a tag; positive values replace its remaining duration.
	bool set_remaining(const StringName &p_tag, double p_seconds);
	// Atomically checks ability and optional group lock, then starts the timers.
	// A group duration of zero only checks the shared lock; it does not start one.
	bool try_start(const StringName &p_tag, double p_seconds, const StringName &p_group_tag = StringName(), double p_group_seconds = 0.0);
	// Decrease one cooldown, optionally expiring it. Rejects negative/nonfinite.
	bool reduce_remaining(const StringName &p_tag, double p_seconds);
	bool remove_cooldown(const StringName &p_tag);
	void clear();
	// Snapshot maps exact tag keys to nonnegative remaining seconds.
	// Validation commits transactionally; duplicates after normalization fail.
	bool replace_snapshot(const Dictionary &p_snapshot);
	// Replace only a dotted tag branch (e.g. Ability), preserving local UI
	// timers and unrelated groups. Invalid snapshots leave all tags unchanged.
	bool replace_cooldown_branch(const StringName &p_branch, const Dictionary &p_snapshot);
	Dictionary get_snapshot() const;
	// Deterministic in caller-provided delta. Returns expired exact tags.
	PackedStringArray tick(double p_delta);
	double get_remaining(const StringName &p_tag) const;
	double get_effective_remaining(const StringName &p_tag, const StringName &p_group_tag = StringName()) const;
	bool is_ready(const StringName &p_tag, const StringName &p_group_tag = StringName()) const;
	int get_cooldown_count() const { return cooldowns.size(); }
};
