/**************************************************************************/
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/* SPDX-License-Identifier: MIT                                              */
/**************************************************************************/
#include "gameplay_effect_timeline.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

int GameplayEffectTimeline::_find(const StringName &p_tag) const {
	for (int i = 0; i < effects.size(); ++i) {
		if (effects[i].tag == p_tag) {
			return i;
		}
	}
	return -1;
}

bool GameplayEffectTimeline::_valid_tag(const StringName &p_tag) {
	const String text = p_tag;
	return !text.is_empty() && !text.begins_with(".") && !text.ends_with(".") && !text.contains("..");
}

bool GameplayEffectTimeline::_valid_duration(double p_seconds) {
	return Math::is_finite(p_seconds) && p_seconds >= 0.0 && p_seconds <= MAX_DURATION;
}

bool GameplayEffectTimeline::_valid_stacks(int p_stacks) {
	return p_stacks > 0 && p_stacks <= MAX_STACKS;
}

bool GameplayEffectTimeline::set_effect(const StringName &p_tag, double p_seconds, int p_stacks) {
	if (!_valid_tag(p_tag) || !_valid_duration(p_seconds) || !_valid_stacks(p_stacks)) {
		return false;
	}
	if (p_seconds == 0.0) {
		remove_effect(p_tag);
		return true;
	}
	const int index = _find(p_tag);
	if (index < 0) {
		if (effects.size() >= MAX_EFFECTS) {
			return false;
		}
		Effect effect;
		effect.tag = p_tag;
		effect.remaining = p_seconds;
		effect.stacks = p_stacks;
		effects.push_back(effect);
	} else {
		effects.write[index].remaining = p_seconds;
		effects.write[index].stacks = p_stacks;
	}
	return true;
}

bool GameplayEffectTimeline::apply_effect(const StringName &p_tag, double p_seconds, int p_stacks, int p_stack_limit, ReapplyPolicy p_policy) {
	if (!_valid_tag(p_tag) || !_valid_duration(p_seconds) || p_seconds <= 0.0 || !_valid_stacks(p_stacks) ||
			!_valid_stacks(p_stack_limit) || p_policy < REAPPLY_REFRESH || p_policy > REAPPLY_KEEP) {
		return false;
	}
	const int index = _find(p_tag);
	if (index < 0) {
		return set_effect(p_tag, p_seconds, MIN(p_stacks, p_stack_limit));
	}
	Effect &effect = effects.write[index];
	if (effect.stacks > p_stack_limit) {
		return false; // A smaller limit must never silently remove established stacks.
	}
	effect.stacks = int(MIN(int64_t(effect.stacks) + p_stacks, int64_t(p_stack_limit)));
	switch (p_policy) {
		case REAPPLY_REFRESH: {
			effect.remaining = p_seconds;
		} break;
		case REAPPLY_EXTEND: {
			effect.remaining = MIN(MAX_DURATION, effect.remaining + p_seconds);
		} break;
		case REAPPLY_KEEP: {
		} break;
	}
	return true;
}

bool GameplayEffectTimeline::remove_effect(const StringName &p_tag) {
	const int index = _find(p_tag);
	if (index < 0) {
		return false;
	}
	effects.remove_at(index);
	return true;
}

void GameplayEffectTimeline::clear() {
	effects.clear();
}

bool GameplayEffectTimeline::replace_snapshot(const Dictionary &p_effects) {
	if (p_effects.size() > MAX_EFFECTS) {
		return false;
	}
	Vector<Effect> validated;
	for (const Variant &key : p_effects) {
		if (key.get_type() != Variant::STRING && key.get_type() != Variant::STRING_NAME) {
			return false;
		}
		const StringName tag = key;
		if (!_valid_tag(tag)) {
			return false;
		}
		for (const Effect &prior : validated) {
			if (prior.tag == tag) {
				return false; // String and StringName keys may alias.
			}
		}
		const Variant value = p_effects[key];
		if (value.get_type() != Variant::DICTIONARY) {
			return false;
		}
		const Dictionary state = value;
		if (!state.has("remaining") || !state.has("stacks")) {
			return false;
		}
		const Variant raw_remaining = state["remaining"];
		const Variant raw_stacks = state["stacks"];
		if ((raw_remaining.get_type() != Variant::FLOAT && raw_remaining.get_type() != Variant::INT) ||
				raw_stacks.get_type() != Variant::INT) {
			return false;
		}
		const double remaining = double(raw_remaining);
		const int64_t stacks = int64_t(raw_stacks);
		if (!_valid_duration(remaining) || stacks < 1 || stacks > MAX_STACKS) {
			return false;
		}
		if (remaining > 0.0) {
			Effect effect;
			effect.tag = tag;
			effect.remaining = remaining;
			effect.stacks = int(stacks);
			validated.push_back(effect);
		}
	}
	// Transaction commit: invalid entries never partially remove prior effects.
	effects = validated;
	return true;
}

// Exact or descendant match only; a Runtime branch must not capture RuntimeExtra.
static bool _effect_tag_in_branch(const StringName &p_tag, const StringName &p_branch) {
	const String tag = p_tag;
	const String branch = p_branch;
	return tag == branch || (tag.length() > branch.length() && tag.begins_with(branch) && tag[branch.length()] == '.');
}

bool GameplayEffectTimeline::replace_effect_branch(const StringName &p_branch, const Dictionary &p_effects) {
	if (!_valid_tag(p_branch) || p_effects.size() > MAX_EFFECTS) {
		return false;
	}

	// Validate all entries and normalized keys before touching the live timeline.
	// Zero-duration entries count as seen to reject mixed String/StringName aliases.
	Vector<Effect> validated;
	Vector<StringName> seen;
	for (const Variant &key : p_effects) {
		if (key.get_type() != Variant::STRING && key.get_type() != Variant::STRING_NAME) {
			return false;
		}
		const StringName tag = key;
		if (!_valid_tag(tag) || !_effect_tag_in_branch(tag, p_branch) || seen.has(tag)) {
			return false;
		}
		seen.push_back(tag);
		const Variant value = p_effects[key];
		if (value.get_type() != Variant::DICTIONARY) {
			return false;
		}
		const Dictionary state = value;
		if (!state.has("remaining") || !state.has("stacks")) {
			return false;
		}
		const Variant raw_remaining = state["remaining"];
		const Variant raw_stacks = state["stacks"];
		if ((raw_remaining.get_type() != Variant::FLOAT && raw_remaining.get_type() != Variant::INT) ||
				raw_stacks.get_type() != Variant::INT) {
			return false;
		}
		const double remaining = double(raw_remaining);
		const int64_t stacks = int64_t(raw_stacks);
		if (!_valid_duration(remaining) || stacks < 1 || stacks > MAX_STACKS) {
			return false;
		}
		if (remaining > 0.0) {
			Effect effect;
			effect.tag = tag;
			effect.remaining = remaining;
			effect.stacks = int(stacks);
			validated.push_back(effect);
		}
	}

	Vector<Effect> next;
	for (const Effect &effect : effects) {
		if (!_effect_tag_in_branch(effect.tag, p_branch)) {
			next.push_back(effect);
		}
	}
	if (next.size() + validated.size() > MAX_EFFECTS) {
		return false;
	}
	for (const Effect &effect : validated) {
		next.push_back(effect);
	}

	// Idempotent repeated snapshots do not rebuild the timeline.
	bool unchanged = effects.size() == next.size();
	if (unchanged) {
		for (int i = 0; i < next.size(); i++) {
			if (effects[i].tag != next[i].tag || effects[i].stacks != next[i].stacks ||
					effects[i].remaining != next[i].remaining) {
				unchanged = false;
				break;
			}
		}
	}
	if (!unchanged) {
		effects = next;
	}
	return true;
}

Dictionary GameplayEffectTimeline::get_snapshot() const {
	Dictionary result;
	for (const Effect &effect : effects) {
		Dictionary state;
		state["remaining"] = effect.remaining;
		state["stacks"] = effect.stacks;
		result[effect.tag] = state;
	}
	return result;
}

PackedStringArray GameplayEffectTimeline::tick(double p_delta) {
	PackedStringArray expired;
	if (!Math::is_finite(p_delta) || p_delta <= 0.0) {
		return expired;
	}
	int i = 0;
	while (i < effects.size()) {
		Effect &effect = effects.write[i];
		if (p_delta >= effect.remaining) {
			expired.push_back(String(effect.tag));
			effects.remove_at(i);
		} else {
			effect.remaining -= p_delta;
			i++;
		}
	}
	return expired;
}

double GameplayEffectTimeline::get_remaining(const StringName &p_tag) const {
	const int index = _find(p_tag);
	return index < 0 ? 0.0 : effects[index].remaining;
}

int GameplayEffectTimeline::get_stacks(const StringName &p_tag) const {
	const int index = _find(p_tag);
	return index < 0 ? 0 : effects[index].stacks;
}

bool GameplayEffectTimeline::has_effect(const StringName &p_tag) const {
	return _find(p_tag) >= 0;
}

void GameplayEffectTimeline::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_effect", "tag", "seconds", "stacks"), &GameplayEffectTimeline::set_effect, DEFVAL(1));
	ClassDB::bind_method(D_METHOD("apply_effect", "tag", "seconds", "stacks", "stack_limit", "policy"), &GameplayEffectTimeline::apply_effect, DEFVAL(1), DEFVAL(MAX_STACKS), DEFVAL(REAPPLY_REFRESH));
	ClassDB::bind_method(D_METHOD("remove_effect", "tag"), &GameplayEffectTimeline::remove_effect);
	ClassDB::bind_method(D_METHOD("clear"), &GameplayEffectTimeline::clear);
	ClassDB::bind_method(D_METHOD("replace_snapshot", "effects"), &GameplayEffectTimeline::replace_snapshot);
	ClassDB::bind_method(D_METHOD("replace_effect_branch", "branch", "effects"), &GameplayEffectTimeline::replace_effect_branch);
	ClassDB::bind_method(D_METHOD("get_snapshot"), &GameplayEffectTimeline::get_snapshot);
	ClassDB::bind_method(D_METHOD("tick", "delta"), &GameplayEffectTimeline::tick);
	ClassDB::bind_method(D_METHOD("get_remaining", "tag"), &GameplayEffectTimeline::get_remaining);
	ClassDB::bind_method(D_METHOD("get_stacks", "tag"), &GameplayEffectTimeline::get_stacks);
	ClassDB::bind_method(D_METHOD("has_effect", "tag"), &GameplayEffectTimeline::has_effect);
	ClassDB::bind_method(D_METHOD("get_effect_count"), &GameplayEffectTimeline::get_effect_count);
	ClassDB::bind_method(D_METHOD("is_empty"), &GameplayEffectTimeline::is_empty);
	BIND_ENUM_CONSTANT(REAPPLY_REFRESH);
	BIND_ENUM_CONSTANT(REAPPLY_EXTEND);
	BIND_ENUM_CONSTANT(REAPPLY_KEEP);
}
