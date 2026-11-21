/**************************************************************************/
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/* SPDX-License-Identifier: MIT                                              */
/**************************************************************************/
#pragma once

#include "core/object/ref_counted.h"
#include "core/string/string_name.h"
#include "core/templates/vector.h"
#include "core/variant/dictionary.h"
#include "core/variant/variant.h"

// A reusable deterministic timeline: time moves only when tick(delta) is called.
// Authoritative gameplay must still be evaluated by the server, not client visuals.
class GameplayEffectTimeline : public RefCounted {
	GDCLASS(GameplayEffectTimeline, RefCounted);

public:
	enum ReapplyPolicy {
		REAPPLY_REFRESH,
		REAPPLY_EXTEND,
		REAPPLY_KEEP,
	};
	static constexpr int MAX_EFFECTS = 256;
	static constexpr int MAX_STACKS = 65535;
	static constexpr double MAX_DURATION = 604800.0;

private:
	struct Effect {
		StringName tag;
		double remaining = 0.0;
		int stacks = 1;
	};
	Vector<Effect> effects;
	int _find(const StringName &p_tag) const;
	static bool _valid_tag(const StringName &p_tag);
	static bool _valid_duration(double p_seconds);
	static bool _valid_stacks(int p_stacks);

protected:
	static void _bind_methods();

public:
	bool set_effect(const StringName &p_tag, double p_seconds, int p_stacks = 1);
	bool apply_effect(const StringName &p_tag, double p_seconds, int p_stacks = 1, int p_stack_limit = MAX_STACKS, ReapplyPolicy p_policy = REAPPLY_REFRESH);
	bool remove_effect(const StringName &p_tag);
	void clear();
	bool replace_snapshot(const Dictionary &p_effects);
	Dictionary get_snapshot() const;
	PackedStringArray tick(double p_delta);
	double get_remaining(const StringName &p_tag) const;
	int get_stacks(const StringName &p_tag) const;
	bool has_effect(const StringName &p_tag) const;
	int get_effect_count() const { return effects.size(); }
	bool is_empty() const { return effects.is_empty(); }
};

VARIANT_ENUM_CAST(GameplayEffectTimeline::ReapplyPolicy);
