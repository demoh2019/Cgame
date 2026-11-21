/**************************************************************************/
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/* SPDX-License-Identifier: MIT                                              */
/**************************************************************************/
#include "gameplay_effect_timeline.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

#include <cmath>

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

bool GameplayEffectTimeline::_tag_matches(const String &p_active, const String &p_requirement) {
	// Match exact or a dot-delimited child, never a lookalike string prefix.
	return p_active == p_requirement ||
			(p_active.length() > p_requirement.length() && p_active.begins_with(p_requirement) &&
					p_active[p_requirement.length()] == '.');
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
	if (effect.period > 0.0 && effect.reset_on_reapply) {
		effect.next_period = effect.period;
	}
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

bool GameplayEffectTimeline::apply_effect_with_tag_requirements(const StringName &p_tag, double p_seconds,
		const PackedStringArray &p_active_tags, const PackedStringArray &p_required_tags,
		const PackedStringArray &p_blocked_tags, int p_stacks, int p_stack_limit, ReapplyPolicy p_policy) {
	// All checks occur before any modification (including periodic pulse phase).
	// Bounded cardinalities guard against untrusted giant query inputs.
	if (p_active_tags.size() > MAX_ACTIVE_TAG_CONTEXTS ||
			p_required_tags.size() > MAX_TAG_REQUIREMENTS || p_blocked_tags.size() > MAX_TAG_REQUIREMENTS) {
		return false;
	}
	for (const String &active : p_active_tags) {
		if (!_valid_tag(StringName(active))) {
			return false;
		}
	}
	for (const String &required : p_required_tags) {
		if (!_valid_tag(StringName(required))) {
			return false;
		}
		bool found = false;
		for (const String &active : p_active_tags) {
			if (_tag_matches(active, required)) {
				found = true;
				break;
			}
		}
		if (!found) {
			return false; // All required tags must be present.
		}
	}
	for (const String &blocked : p_blocked_tags) {
		if (!_valid_tag(StringName(blocked))) {
			return false;
		}
		for (const String &active : p_active_tags) {
			if (_tag_matches(active, blocked)) {
				return false; // Any blocked tag prevents application.
			}
		}
	}
	return apply_effect(p_tag, p_seconds, p_stacks, p_stack_limit, p_policy);
}

bool GameplayEffectTimeline::set_periodic(const StringName &p_tag, double p_period, bool p_reset_on_reapply) {
	const int index = _find(p_tag);
	if (index < 0 || !Math::is_finite(p_period) || p_period < 0.0 ||
			(p_period != 0.0 && p_period < MIN_PERIOD) || p_period > MAX_DURATION) {
		return false;
	}
	Effect &effect = effects.write[index];
	if (effect.period != p_period) {
		effect.next_period = p_period;
	}
	effect.period = p_period;
	effect.reset_on_reapply = p_reset_on_reapply;
	return true;
}

double GameplayEffectTimeline::get_periodic(const StringName &p_tag) const {
	const int index = _find(p_tag);
	return index < 0 ? 0.0 : effects[index].period;
}

Dictionary GameplayEffectTimeline::take_periodic_pulses() {
	Dictionary result = pending_pulses;
	pending_pulses = Dictionary();
	return result;
}

bool GameplayEffectTimeline::remove_effect(const StringName &p_tag) {
	const int index = _find(p_tag);
	if (index < 0) {
		return false;
	}
	effects.remove_at(index);
	pending_pulses.erase(p_tag);
	return true;
}

void GameplayEffectTimeline::clear() {
	effects.clear();
	pending_pulses.clear();
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
			// A bare authoritative timer update preserves local periodic phase.
			// Explicit periodic fields allow complete snapshot round-tripping.
			const int prior = _find(tag);
			if (prior >= 0) {
				effect.period = effects[prior].period;
				effect.next_period = effects[prior].next_period;
				effect.reset_on_reapply = effects[prior].reset_on_reapply;
			}
			if (state.has("period")) {
				const Variant raw_period = state["period"];
				if (raw_period.get_type() != Variant::INT && raw_period.get_type() != Variant::FLOAT) {
					return false;
				}
				const double period = double(raw_period);
				if (!Math::is_finite(period) || period < 0.0 ||
						(period != 0.0 && period < MIN_PERIOD) || period > MAX_DURATION) {
					return false;
				}
				if (period != effect.period) {
					effect.next_period = period;
				}
				effect.period = period;
				if (state.has("reset_on_reapply")) {
					const Variant raw_reset = state["reset_on_reapply"];
					if (raw_reset.get_type() != Variant::BOOL) {
						return false;
					}
					effect.reset_on_reapply = bool(raw_reset);
				}
				if (state.has("next_period")) {
					const Variant raw_phase = state["next_period"];
					if ((raw_phase.get_type() != Variant::INT && raw_phase.get_type() != Variant::FLOAT) ||
							period <= 0.0 || !Math::is_finite(double(raw_phase)) ||
							double(raw_phase) <= 0.0 || double(raw_phase) > period) {
						return false;
					}
					effect.next_period = double(raw_phase);
				}
			} else if (state.has("next_period") || state.has("reset_on_reapply")) {
				return false; // Phase and policy require an explicit period.
			}
			validated.push_back(effect);
		} else if (state.has("period") || state.has("next_period") || state.has("reset_on_reapply")) {
			// Expired effects cannot carry a hidden periodic configuration.
			return false;
		}
	}
	// Transaction commit: invalid entries never partially remove prior effects.
	effects = validated;
	pending_pulses.clear(); // Drop pulses superseded by an authoritative snapshot.
	return true;
}

// Exact tags and descendants match, never lookalike prefixes.
static bool _timeline_effect_in_branch(const StringName &p_tag, const StringName &p_branch) {
	const String tag = p_tag;
	const String branch = p_branch;
	return tag == branch || (tag.length() > branch.length() && tag.begins_with(branch) && tag[branch.length()] == '.');
}

bool GameplayEffectTimeline::_replace_effect_branch(const StringName &p_branch, const Dictionary &p_effects, bool p_preserve_pending) {
	if (!_valid_tag(p_branch) || p_effects.size() > MAX_EFFECTS) {
		return false;
	}

	// Validate the entire incoming authoritative slice first, including
	// optional periodic phase and normalization collisions, before any commit.
	Vector<Effect> validated;
	Vector<StringName> seen;
	for (const Variant &key : p_effects) {
		if (key.get_type() != Variant::STRING && key.get_type() != Variant::STRING_NAME) {
			return false;
		}
		const StringName tag = key;
		if (!_valid_tag(tag) || !_timeline_effect_in_branch(tag, p_branch) || seen.has(tag)) {
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
			// Preserve periodic phase for existing tags unless explicitly overridden.
			const int prior = _find(tag);
			if (prior >= 0) {
				effect.period = effects[prior].period;
				effect.next_period = effects[prior].next_period;
				effect.reset_on_reapply = effects[prior].reset_on_reapply;
			}
			if (state.has("period")) {
				const Variant raw_period = state["period"];
				if (raw_period.get_type() != Variant::INT && raw_period.get_type() != Variant::FLOAT) {
					return false;
				}
				const double period = double(raw_period);
				if (!Math::is_finite(period) || period < 0.0 ||
						(period != 0.0 && period < MIN_PERIOD) || period > MAX_DURATION) {
					return false;
				}
				if (period != effect.period) {
					effect.next_period = period;
				}
				effect.period = period;
				if (state.has("reset_on_reapply")) {
					const Variant raw_reset = state["reset_on_reapply"];
					if (raw_reset.get_type() != Variant::BOOL) {
						return false;
					}
					effect.reset_on_reapply = bool(raw_reset);
				}
				if (state.has("next_period")) {
					const Variant raw_phase = state["next_period"];
					if ((raw_phase.get_type() != Variant::INT && raw_phase.get_type() != Variant::FLOAT) ||
							period <= 0.0 || !Math::is_finite(double(raw_phase)) ||
							double(raw_phase) <= 0.0 || double(raw_phase) > period) {
						return false;
					}
					effect.next_period = double(raw_phase);
				}
			} else if (state.has("next_period") || state.has("reset_on_reapply")) {
				return false;
			}
			validated.push_back(effect);
		} else if (state.has("period") || state.has("next_period") || state.has("reset_on_reapply")) {
			return false;
		}
	}

	Vector<Effect> next;
	for (const Effect &effect : effects) {
		if (!_timeline_effect_in_branch(effect.tag, p_branch)) {
			next.push_back(effect);
		}
	}
	if (next.size() + validated.size() > MAX_EFFECTS) {
		return false;
	}
	for (const Effect &effect : validated) {
		next.push_back(effect);
	}

	bool unchanged = effects.size() == next.size();
	if (unchanged) {
		for (int i = 0; i < next.size(); ++i) {
			const Effect &a = effects[i];
			const Effect &b = next[i];
			if (a.tag != b.tag || a.remaining != b.remaining || a.stacks != b.stacks ||
					a.period != b.period || a.next_period != b.next_period ||
					a.reset_on_reapply != b.reset_on_reapply) {
				unchanged = false;
				break;
			}
		}
	}
	// Remember only the matching, still-live effects whose periodic interval
	// has not changed. A fresh tag or a rephased period must never inherit
	// another effect instance's pending pulses. This is bounded by MAX_EFFECTS.
	Vector<StringName> continuing_pulses;
	if (p_preserve_pending) {
		for (const Effect &effect : validated) {
			const int prior = _find(effect.tag);
			if (prior >= 0 && effect.period > 0.0 &&
					effects[prior].period == effect.period &&
					effects[prior].next_period == effect.next_period) {
				continuing_pulses.push_back(effect.tag);
			}
		}
	}
	if (!unchanged) {
		effects = next;
	}
	// The original replace_effect_branch still discards every in-branch pulse.
	// Replication reconciliation retains pending pulses for continuing tags,
	// even when authoritative remaining time or stack counts change.
	Vector<StringName> expired_pulses;
	for (const Variant &key : pending_pulses) {
		const StringName tag = key;
		if (_timeline_effect_in_branch(tag, p_branch) &&
				(!p_preserve_pending || !continuing_pulses.has(tag))) {
			expired_pulses.push_back(tag);
		}
	}
	for (const StringName &tag : expired_pulses) {
		pending_pulses.erase(tag);
	}
	return true;
}

bool GameplayEffectTimeline::replace_effect_branch(const StringName &p_branch, const Dictionary &p_effects) {
	return _replace_effect_branch(p_branch, p_effects, false);
}

bool GameplayEffectTimeline::reconcile_effect_branch(const StringName &p_branch, const Dictionary &p_effects) {
	return _replace_effect_branch(p_branch, p_effects, true);
}

Dictionary GameplayEffectTimeline::get_snapshot() const {
	Dictionary result;
	for (const Effect &effect : effects) {
		Dictionary state;
		state["remaining"] = effect.remaining;
		state["stacks"] = effect.stacks;
		if (effect.period > 0.0) {
			state["period"] = effect.period;
			state["next_period"] = effect.next_period;
			state["reset_on_reapply"] = effect.reset_on_reapply;
		}
		result[effect.tag] = state;
	}
	return result;
}

void GameplayEffectTimeline::_advance(double p_delta, PackedStringArray *r_expired) {
	if (!Math::is_finite(p_delta) || p_delta <= 0.0) {
		return;
	}
	int i = 0;
	while (i < effects.size()) {
		Effect &effect = effects.write[i];
		const double elapsed = MIN(p_delta, effect.remaining);
		if (effect.period > 0.0 && elapsed + 1e-9 >= effect.next_period) {
			// Aggregate all due periods in constant time, even after a long pause.
			// Only active-time (up to expiry) can generate a pulse.
			const double after_first = MAX(0.0, elapsed - effect.next_period);
			const int64_t count = 1 + int64_t(std::floor((after_first + 1e-9) / effect.period));
			const int pending = pending_pulses.get(effect.tag, 0);
			pending_pulses[effect.tag] = int(MIN(int64_t(MAX_PENDING_PULSES), int64_t(pending) + count));
			const double remainder = std::fmod(after_first, effect.period);
			effect.next_period = remainder < 1e-9 || effect.period - remainder < 1e-9 ? effect.period : effect.period - remainder;
		} else if (effect.period > 0.0) {
			effect.next_period -= elapsed;
		}
		if (p_delta >= effect.remaining) {
			if (r_expired != nullptr) {
				r_expired->push_back(String(effect.tag));
			}
			effects.remove_at(i);
		} else {
			effect.remaining -= p_delta;
			i++;
		}
	}
	return;
}

PackedStringArray GameplayEffectTimeline::tick(double p_delta) {
	PackedStringArray expired;
	_advance(p_delta, &expired);
	return expired;
}

Dictionary GameplayEffectTimeline::tick_and_take_periodic_pulses(double p_delta) {
	// Cosmetic rendering never uses the expired tag array. Skip that output,
	// but preserve the exact phase, expiry and bounded pulse accumulation.
	_advance(p_delta, nullptr);
	return take_periodic_pulses();
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
	ClassDB::bind_method(D_METHOD("apply_effect_with_tag_requirements", "tag", "seconds", "active_tags", "required_tags", "blocked_tags", "stacks", "stack_limit", "policy"),
			&GameplayEffectTimeline::apply_effect_with_tag_requirements, DEFVAL(PackedStringArray()), DEFVAL(PackedStringArray()),
			DEFVAL(1), DEFVAL(MAX_STACKS), DEFVAL(REAPPLY_REFRESH));
	ClassDB::bind_method(D_METHOD("set_periodic", "tag", "period", "reset_on_reapply"), &GameplayEffectTimeline::set_periodic, DEFVAL(true));
	ClassDB::bind_method(D_METHOD("get_periodic", "tag"), &GameplayEffectTimeline::get_periodic);
	ClassDB::bind_method(D_METHOD("take_periodic_pulses"), &GameplayEffectTimeline::take_periodic_pulses);
	ClassDB::bind_method(D_METHOD("tick_and_take_periodic_pulses", "delta"), &GameplayEffectTimeline::tick_and_take_periodic_pulses);
	ClassDB::bind_method(D_METHOD("remove_effect", "tag"), &GameplayEffectTimeline::remove_effect);
	ClassDB::bind_method(D_METHOD("clear"), &GameplayEffectTimeline::clear);
	ClassDB::bind_method(D_METHOD("replace_snapshot", "effects"), &GameplayEffectTimeline::replace_snapshot);
	ClassDB::bind_method(D_METHOD("replace_effect_branch", "branch", "effects"), &GameplayEffectTimeline::replace_effect_branch);
	ClassDB::bind_method(D_METHOD("reconcile_effect_branch", "branch", "effects"), &GameplayEffectTimeline::reconcile_effect_branch);
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
