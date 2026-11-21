/**************************************************************************/
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#include "gameplay_cooldown_tracker.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

int GameplayCooldownTracker::_find(const StringName &p_tag) const {
	for (int i = 0; i < cooldowns.size(); ++i) {
		if (cooldowns[i].tag == p_tag) {
			return i;
		}
	}
	return -1;
}

bool GameplayCooldownTracker::_valid_tag(const StringName &p_tag) {
	const String text = p_tag;
	return !text.is_empty() && !text.begins_with(".") && !text.ends_with(".") && !text.contains("..");
}

bool GameplayCooldownTracker::_valid_duration(double p_seconds) {
	return Math::is_finite(p_seconds) && p_seconds >= 0.0 && p_seconds <= MAX_DURATION;
}

bool GameplayCooldownTracker::set_remaining(const StringName &p_tag, double p_seconds) {
	if (!_valid_tag(p_tag) || !_valid_duration(p_seconds)) {
		return false;
	}
	const int index = _find(p_tag);
	if (p_seconds == 0.0) {
		if (index >= 0) {
			cooldowns.remove_at(index);
		}
		return true;
	}
	if (index >= 0) {
		cooldowns.write[index].remaining = p_seconds;
		return true;
	}
	if (cooldowns.size() >= MAX_COOLDOWNS) {
		return false;
	}
	Cooldown next;
	next.tag = p_tag;
	next.remaining = p_seconds;
	cooldowns.push_back(next);
	return true;
}

bool GameplayCooldownTracker::try_start(const StringName &p_tag, double p_seconds, const StringName &p_group_tag, double p_group_seconds) {
	const bool has_group = !String(p_group_tag).is_empty();
	if (!_valid_tag(p_tag) || !_valid_duration(p_seconds) || p_seconds == 0.0 ||
			!_valid_duration(p_group_seconds) ||
			(has_group && (!_valid_tag(p_group_tag) || p_group_tag == p_tag)) ||
			(!has_group && p_group_seconds != 0.0)) {
		return false;
	}
	if (!is_ready(p_tag, p_group_tag)) {
		return false;
	}
	// Preflight capacity so an ability cannot start without its shared lock.
	const int needed = 1 + ((has_group && p_group_seconds > 0.0) ? 1 : 0);
	if (cooldowns.size() + needed > MAX_COOLDOWNS) {
		return false;
	}
	set_remaining(p_tag, p_seconds);
	if (has_group && p_group_seconds > 0.0) {
		set_remaining(p_group_tag, p_group_seconds);
	}
	return true;
}

bool GameplayCooldownTracker::reduce_remaining(const StringName &p_tag, double p_seconds) {
	if (!_valid_tag(p_tag) || !_valid_duration(p_seconds)) {
		return false;
	}
	const int index = _find(p_tag);
	if (index < 0) {
		return false;
	}
	return set_remaining(p_tag, MAX(0.0, cooldowns[index].remaining - p_seconds));
}

bool GameplayCooldownTracker::remove_cooldown(const StringName &p_tag) {
	const int index = _find(p_tag);
	if (index < 0) {
		return false;
	}
	cooldowns.remove_at(index);
	return true;
}

void GameplayCooldownTracker::clear() {
	cooldowns.clear();
}

bool GameplayCooldownTracker::replace_snapshot(const Dictionary &p_snapshot) {
	if (p_snapshot.size() > MAX_COOLDOWNS) {
		return false;
	}
	Vector<Cooldown> validated;
	for (const Variant &key : p_snapshot) {
		if (key.get_type() != Variant::STRING && key.get_type() != Variant::STRING_NAME) {
			return false;
		}
		const StringName tag = key;
		if (!_valid_tag(tag)) {
			return false;
		}
		for (const Cooldown &prior : validated) {
			if (prior.tag == tag) {
				return false; // A String and StringName must not alias.
			}
		}
		const Variant raw_time = p_snapshot[key];
		if (raw_time.get_type() != Variant::FLOAT && raw_time.get_type() != Variant::INT) {
			return false;
		}
		const double seconds = double(raw_time);
		if (!_valid_duration(seconds)) {
			return false;
		}
		if (seconds > 0.0) {
			Cooldown item;
			item.tag = tag;
			item.remaining = seconds;
			validated.push_back(item);
		}
	}
	cooldowns = validated;
	return true;
}


bool GameplayCooldownTracker::replace_cooldown_branch(const StringName &p_branch, const Dictionary &p_snapshot) {
	if (!_valid_tag(p_branch) || p_snapshot.size() > MAX_COOLDOWNS) {
		return false;
	}
	const String branch = p_branch;
	const String prefix = branch + ".";

	// Validate the *entire* incoming branch before touching live cooldowns.
	// Both String and StringName keys are accepted, but may not alias.
	Vector<StringName> seen;
	Vector<Cooldown> replacement;
	for (const Variant &key : p_snapshot) {
		if (key.get_type() != Variant::STRING && key.get_type() != Variant::STRING_NAME) {
			return false;
		}
		const StringName tag = key;
		const String name = tag;
		if (!_valid_tag(tag) || (name != branch && !name.begins_with(prefix)) || seen.has(tag)) {
			return false; // No parent/sibling subtree pollution or alias keys.
		}
		seen.push_back(tag);
		const Variant raw = p_snapshot[key];
		if (raw.get_type() != Variant::FLOAT && raw.get_type() != Variant::INT) {
			return false;
		}
		const double seconds = double(raw);
		if (!_valid_duration(seconds)) {
			return false;
		}
		if (seconds > 0.0) {
			Cooldown item;
			item.tag = tag;
			item.remaining = seconds;
			replacement.push_back(item);
		}
	}

	Vector<Cooldown> keep;
	for (const Cooldown &existing : cooldowns) {
		const String name = existing.tag;
		if (name != branch && !name.begins_with(prefix)) {
			keep.push_back(existing);
		}
	}
	if (keep.size() + replacement.size() > MAX_COOLDOWNS) {
		return false; // Capacity failure is a transaction rollback too.
	}
	for (const Cooldown &incoming : replacement) {
		keep.push_back(incoming);
	}
	cooldowns = keep;
	return true;
}

Dictionary GameplayCooldownTracker::get_snapshot() const {
	Dictionary snapshot;
	for (const Cooldown &entry : cooldowns) {
		snapshot[entry.tag] = entry.remaining;
	}
	return snapshot;
}

PackedStringArray GameplayCooldownTracker::tick(double p_delta) {
	PackedStringArray expired;
	if (!Math::is_finite(p_delta) || p_delta <= 0.0) {
		return expired;
	}
	int index = 0;
	while (index < cooldowns.size()) {
		Cooldown &entry = cooldowns.write[index];
		if (p_delta >= entry.remaining) {
			expired.push_back(String(entry.tag));
			cooldowns.remove_at(index);
		} else {
			entry.remaining -= p_delta;
			index++;
		}
	}
	return expired;
}

double GameplayCooldownTracker::get_remaining(const StringName &p_tag) const {
	const int index = _find(p_tag);
	return index < 0 ? 0.0 : cooldowns[index].remaining;
}

double GameplayCooldownTracker::get_effective_remaining(const StringName &p_tag, const StringName &p_group_tag) const {
	double remaining = get_remaining(p_tag);
	if (!String(p_group_tag).is_empty()) {
		remaining = MAX(remaining, get_remaining(p_group_tag));
	}
	return remaining;
}

bool GameplayCooldownTracker::is_ready(const StringName &p_tag, const StringName &p_group_tag) const {
	return _valid_tag(p_tag) && (String(p_group_tag).is_empty() || _valid_tag(p_group_tag)) &&
			get_effective_remaining(p_tag, p_group_tag) <= 0.0;
}

void GameplayCooldownTracker::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_remaining", "tag", "seconds"), &GameplayCooldownTracker::set_remaining);
	ClassDB::bind_method(D_METHOD("try_start", "tag", "seconds", "group_tag", "group_seconds"), &GameplayCooldownTracker::try_start, DEFVAL(StringName()), DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("reduce_remaining", "tag", "seconds"), &GameplayCooldownTracker::reduce_remaining);
	ClassDB::bind_method(D_METHOD("remove_cooldown", "tag"), &GameplayCooldownTracker::remove_cooldown);
	ClassDB::bind_method(D_METHOD("clear"), &GameplayCooldownTracker::clear);
	ClassDB::bind_method(D_METHOD("replace_snapshot", "snapshot"), &GameplayCooldownTracker::replace_snapshot);
	ClassDB::bind_method(D_METHOD("replace_cooldown_branch", "branch", "snapshot"), &GameplayCooldownTracker::replace_cooldown_branch);
	ClassDB::bind_method(D_METHOD("get_snapshot"), &GameplayCooldownTracker::get_snapshot);
	ClassDB::bind_method(D_METHOD("tick", "delta"), &GameplayCooldownTracker::tick);
	ClassDB::bind_method(D_METHOD("get_remaining", "tag"), &GameplayCooldownTracker::get_remaining);
	ClassDB::bind_method(D_METHOD("get_effective_remaining", "tag", "group_tag"), &GameplayCooldownTracker::get_effective_remaining, DEFVAL(StringName()));
	ClassDB::bind_method(D_METHOD("is_ready", "tag", "group_tag"), &GameplayCooldownTracker::is_ready, DEFVAL(StringName()));
	ClassDB::bind_method(D_METHOD("get_cooldown_count"), &GameplayCooldownTracker::get_cooldown_count);
}
