/**************************************************************************/
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#pragma once

#include "core/object/ref_counted.h"
#include "core/variant/variant.h"
#include "core/variant/binder_common.h"

// Stateless and deterministic Gameplay Effect stacking decisions.
// Explicit durations and prior stack counts are supplied by authoritative
// callers. This component never advances clocks, mutates combat, or reads time.
class GameplayEffectStackPolicy : public RefCounted {
	GDCLASS(GameplayEffectStackPolicy, RefCounted);

public:
	enum OverflowPolicy {
		OVERFLOW_CLAMP = 0, // Continue refreshing, without adding more stacks.
		OVERFLOW_REJECT = 1, // Reject new applications once the stack cap is reached.
		OVERFLOW_RESET = 2, // New application starts a new stack cycle.
	};
	enum ReapplyPolicy {
		REAPPLY_IF_STRONGER = 0, // Never replace a stronger, still-active effect.
		REAPPLY_REFRESH = 1,
		REAPPLY_EXTEND = 2,
		REAPPLY_KEEP = 3,
	};
	static constexpr int MAX_STACKS = 32;
	static constexpr double MAX_DURATION = 604800.0;

private:
	int max_stacks = 1;
	int overflow_policy = OVERFLOW_CLAMP;
	int reapply_policy = REAPPLY_IF_STRONGER;
	PackedFloat32Array stack_factors;

	static bool _valid_duration(double p_duration, bool p_allow_zero = false);
	static bool _valid_target_scale(double p_scale);
	static Dictionary _result(bool p_accepted, int p_stacks, double p_remaining,
			double p_duration, bool p_overflow, const String &p_reason);

protected:
	static void _bind_methods();

public:
	GameplayEffectStackPolicy();

	// Factor index is the number of previously applied stacks. The last
	// factor is held when the number of applications exceeds the table.
	bool configure(int p_max_stacks, const PackedFloat32Array &p_factors,
			int p_overflow = OVERFLOW_CLAMP, int p_reapply = REAPPLY_IF_STRONGER);
	double calculate_magnitude(double p_base_duration, int p_prior_stacks,
			double p_target_scale = 1.0) const;
	Dictionary preview_application(double p_base_duration, int p_prior_stacks,
			double p_current_remaining, double p_target_scale = 1.0) const;
	Dictionary get_config() const;
	bool replace_config(const Dictionary &p_config);
	int get_max_stacks() const { return max_stacks; }
	int get_overflow_policy() const { return overflow_policy; }
	int get_reapply_policy() const { return reapply_policy; }
};

VARIANT_ENUM_CAST(GameplayEffectStackPolicy::OverflowPolicy);
VARIANT_ENUM_CAST(GameplayEffectStackPolicy::ReapplyPolicy);
