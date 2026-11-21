/**************************************************************************/
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                 */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

#include "core/object/ref_counted.h"
#include "core/string/string_name.h"
#include "core/templates/vector.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// Server-safe, data-driven Gameplay Effect application requirements.
// Inspired by Unreal GAS granted/required/blocked Gameplay Tags.
// A rule applies to its exact effect tag and all of its descendants;
// all matching ancestor rules must pass. Unknown effects fail closed.
class GameplayEffectApplicationGate : public RefCounted {
	GDCLASS(GameplayEffectApplicationGate, RefCounted);

public:
	static constexpr int MAX_RULES = 64;
	static constexpr int MAX_CONDITIONS = 16;
	static constexpr int MAX_TARGET_TAGS = 64;
	static constexpr int MAX_TAG_LENGTH = 96;

private:
	struct Rule {
		StringName effect;
		PackedStringArray required;
		PackedStringArray blocked;
	};
	Vector<Rule> rules;

	static bool _valid_tag(const StringName &p_tag);
	static bool _valid_conditions(const PackedStringArray &p_conditions);
	static bool _matches(const StringName &p_effect, const StringName &p_rule);
	static bool _has_tag(const PackedStringArray &p_tags, const String &p_requirement);
	static bool _valid_target_tags(const PackedStringArray &p_tags);
	int _find_rule(const StringName &p_effect) const;

protected:
	static void _bind_methods();

public:
	bool set_rule(const StringName &p_effect, const PackedStringArray &p_required, const PackedStringArray &p_blocked);
	bool remove_rule(const StringName &p_effect);
	void clear();
	bool can_apply(const StringName &p_effect, const PackedStringArray &p_target_tags) const;
	// Useful for diagnostic UI and tests: "allowed", "unknown_effect",
	// "invalid_tags", "missing_required", "blocked".
	String get_failure_reason(const StringName &p_effect, const PackedStringArray &p_target_tags) const;
	Dictionary get_snapshot() const;
	bool replace_snapshot(const Dictionary &p_snapshot);
	int get_rule_count() const { return rules.size(); }
};
