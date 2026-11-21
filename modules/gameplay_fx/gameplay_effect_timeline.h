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
	static constexpr double MIN_PERIOD = 0.05;
	static constexpr int MAX_PENDING_PULSES = 32;
	static constexpr int MAX_ACTIVE_TAG_CONTEXTS = 128;
	static constexpr int MAX_TAG_REQUIREMENTS = 32;

private:
	struct Effect {
		StringName tag;
		double remaining = 0.0;
		int stacks = 1;
		double period = 0.0;
		double next_period = 0.0;
		bool reset_on_reapply = true;
	};
	Vector<Effect> effects;
	Dictionary pending_pulses; // Aggregated and capped: no unbounded backlog.
	int _find(const StringName &p_tag) const;
	static bool _valid_tag(const StringName &p_tag);
	static bool _valid_duration(double p_seconds);
	static bool _valid_stacks(int p_stacks);
	static bool _tag_matches(const String &p_active, const String &p_requirement);

protected:
	static void _bind_methods();

public:
	bool set_effect(const StringName &p_tag, double p_seconds, int p_stacks = 1);
	bool apply_effect(const StringName &p_tag, double p_seconds, int p_stacks = 1, int p_stack_limit = MAX_STACKS, ReapplyPolicy p_policy = REAPPLY_REFRESH);
	// Unreal GAS-style target-tag admission gate; this is a non-allocating
	// validation step before calling the existing reapply/stack policy.
	// Caller is responsible for providing trusted current target tags.
	bool apply_effect_with_tag_requirements(const StringName &p_tag, double p_seconds,
			const PackedStringArray &p_active_tags,
			const PackedStringArray &p_required_tags = PackedStringArray(),
			const PackedStringArray &p_blocked_tags = PackedStringArray(),
			int p_stacks = 1, int p_stack_limit = MAX_STACKS, ReapplyPolicy p_policy = REAPPLY_REFRESH);
	// A zero period disables periodic execution; changing the period resets phase.
	// If enabled, reapply may either restart the period or preserve elapsed phase.
	bool set_periodic(const StringName &p_tag, double p_period, bool p_reset_on_reapply = true);
	double get_periodic(const StringName &p_tag) const;
	// Return and clear pulse counts for effects advanced by tick(). Counts are
	// coalesced per tag (max 32), not individual per-frame allocations.
	Dictionary take_periodic_pulses();
	bool remove_effect(const StringName &p_tag);
	void clear();
	bool replace_snapshot(const Dictionary &p_effects);
	// Atomically refresh one authoritative tag namespace; preserve other timers and pulses.
	bool replace_effect_branch(const StringName &p_branch, const Dictionary &p_effects);
	Dictionary get_snapshot() const;
	PackedStringArray tick(double p_delta);
	double get_remaining(const StringName &p_tag) const;
	int get_stacks(const StringName &p_tag) const;
	bool has_effect(const StringName &p_tag) const;
	int get_effect_count() const { return effects.size(); }
	bool is_empty() const { return effects.is_empty(); }
};

VARIANT_ENUM_CAST(GameplayEffectTimeline::ReapplyPolicy);
