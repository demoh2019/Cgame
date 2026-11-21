/**************************************************************************/
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                 */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#include "gameplay_effect_application_gate.h"

#include "core/object/class_db.h"

bool GameplayEffectApplicationGate::_valid_tag(const StringName &p_tag) {
	const String name = p_tag;
	if (name.is_empty() || name.length() > MAX_TAG_LENGTH || name.begins_with(".") || name.ends_with(".")) {
		return false;
	}
	bool last_dot = false;
	for (int i = 0; i < name.length(); ++i) {
		const char32_t c = name[i];
		const bool dot = c == '.';
		if (dot && last_dot) {
			return false;
		}
		if (!dot && !(c >= 'a' && c <= 'z') && !(c >= 'A' && c <= 'Z') &&
				!(c >= '0' && c <= '9') && c != '_') {
			return false;
		}
		last_dot = dot;
	}
	return true;
}

bool GameplayEffectApplicationGate::_valid_conditions(const PackedStringArray &p_conditions) {
	if (p_conditions.size() > MAX_CONDITIONS) {
		return false;
	}
	for (int i = 0; i < p_conditions.size(); ++i) {
		if (!_valid_tag(StringName(p_conditions[i]))) {
			return false;
		}
		for (int j = 0; j < i; ++j) {
			if (p_conditions[i] == p_conditions[j]) {
				return false;
			}
		}
	}
	return true;
}

bool GameplayEffectApplicationGate::_matches(const StringName &p_effect, const StringName &p_rule) {
	const String effect = p_effect;
	const String rule = p_rule;
	return effect == rule || effect.begins_with(rule + ".");
}

bool GameplayEffectApplicationGate::_has_tag(const PackedStringArray &p_tags, const String &p_requirement) {
	for (int i = 0; i < p_tags.size(); ++i) {
		const String tag = p_tags[i];
		if (tag == p_requirement || tag.begins_with(p_requirement + ".")) {
			return true;
		}
	}
	return false;
}

bool GameplayEffectApplicationGate::_valid_target_tags(const PackedStringArray &p_tags) {
	if (p_tags.size() > MAX_TARGET_TAGS) {
		return false;
	}
	for (const String &tag : p_tags) {
		if (!_valid_tag(StringName(tag))) {
			return false;
		}
	}
	return true;
}

int GameplayEffectApplicationGate::_find_rule(const StringName &p_effect) const {
	for (int i = 0; i < rules.size(); ++i) {
		if (rules[i].effect == p_effect) {
			return i;
		}
	}
	return -1;
}

bool GameplayEffectApplicationGate::set_rule(const StringName &p_effect, const PackedStringArray &p_required, const PackedStringArray &p_blocked) {
	if (!_valid_tag(p_effect) || !_valid_conditions(p_required) || !_valid_conditions(p_blocked)) {
		return false;
	}
	Rule rule;
	rule.effect = p_effect;
	rule.required = p_required;
	rule.blocked = p_blocked;
	const int index = _find_rule(p_effect);
	if (index >= 0) {
		rules.write[index] = rule;
		return true;
	}
	if (rules.size() >= MAX_RULES) {
		return false;
	}
	rules.push_back(rule);
	return true;
}

bool GameplayEffectApplicationGate::remove_rule(const StringName &p_effect) {
	const int index = _find_rule(p_effect);
	if (index < 0) {
		return false;
	}
	rules.remove_at(index);
	return true;
}

void GameplayEffectApplicationGate::clear() {
	rules.clear();
}

String GameplayEffectApplicationGate::get_failure_reason(const StringName &p_effect, const PackedStringArray &p_target_tags) const {
	if (!_valid_tag(p_effect) || !_valid_target_tags(p_target_tags)) {
		return "invalid_tags";
	}
	bool has_match = false;
	for (const Rule &rule : rules) {
		if (!_matches(p_effect, rule.effect)) {
			continue;
		}
		has_match = true;
		for (const String &required : rule.required) {
			if (!_has_tag(p_target_tags, required)) {
				return "missing_required";
			}
		}
		for (const String &blocked : rule.blocked) {
			if (_has_tag(p_target_tags, blocked)) {
				return "blocked";
			}
		}
	}
	return has_match ? "allowed" : "unknown_effect";
}

bool GameplayEffectApplicationGate::can_apply(const StringName &p_effect, const PackedStringArray &p_target_tags) const {
	return get_failure_reason(p_effect, p_target_tags) == "allowed";
}

Dictionary GameplayEffectApplicationGate::get_snapshot() const {
	Dictionary snapshot;
	for (const Rule &rule : rules) {
		Dictionary entry;
		entry["required"] = rule.required;
		entry["blocked"] = rule.blocked;
		snapshot[rule.effect] = entry;
	}
	return snapshot;
}

bool GameplayEffectApplicationGate::replace_snapshot(const Dictionary &p_snapshot) {
	if (p_snapshot.size() > MAX_RULES) {
		return false;
	}
	Vector<Rule> validated;
	for (const Variant &raw_tag : p_snapshot) {
		if (raw_tag.get_type() != Variant::STRING && raw_tag.get_type() != Variant::STRING_NAME) {
			return false;
		}
		const StringName tag = raw_tag;
		if (!_valid_tag(tag)) {
			return false;
		}
		for (const Rule &previous : validated) {
			if (previous.effect == tag) {
				return false; // String/StringName aliases are not accepted.
			}
		}
		const Variant raw_rule = p_snapshot[raw_tag];
		if (raw_rule.get_type() != Variant::DICTIONARY) {
			return false;
		}
		const Dictionary entry = raw_rule;
		if (!entry.has("required") || !entry.has("blocked")) {
			return false;
		}
		const Variant raw_required = entry["required"];
		const Variant raw_blocked = entry["blocked"];
		if (raw_required.get_type() != Variant::PACKED_STRING_ARRAY || raw_blocked.get_type() != Variant::PACKED_STRING_ARRAY) {
			return false;
		}
		Rule rule;
		rule.effect = tag;
		rule.required = raw_required;
		rule.blocked = raw_blocked;
		if (!_valid_conditions(rule.required) || !_valid_conditions(rule.blocked)) {
			return false;
		}
		validated.push_back(rule);
	}
	rules = validated;
	return true;
}

void GameplayEffectApplicationGate::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_rule", "effect", "required", "blocked"), &GameplayEffectApplicationGate::set_rule);
	ClassDB::bind_method(D_METHOD("remove_rule", "effect"), &GameplayEffectApplicationGate::remove_rule);
	ClassDB::bind_method(D_METHOD("clear"), &GameplayEffectApplicationGate::clear);
	ClassDB::bind_method(D_METHOD("can_apply", "effect", "target_tags"), &GameplayEffectApplicationGate::can_apply);
	ClassDB::bind_method(D_METHOD("get_failure_reason", "effect", "target_tags"), &GameplayEffectApplicationGate::get_failure_reason);
	ClassDB::bind_method(D_METHOD("get_snapshot"), &GameplayEffectApplicationGate::get_snapshot);
	ClassDB::bind_method(D_METHOD("replace_snapshot", "snapshot"), &GameplayEffectApplicationGate::replace_snapshot);
	ClassDB::bind_method(D_METHOD("get_rule_count"), &GameplayEffectApplicationGate::get_rule_count);
}
