/**************************************************************************/
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/
#include "gameplay_effect_stack_policy.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

GameplayEffectStackPolicy::GameplayEffectStackPolicy() {
	stack_factors.push_back(1.0f);
}

bool GameplayEffectStackPolicy::_valid_duration(double p_duration, bool p_allow_zero) {
	return Math::is_finite(p_duration) && (p_allow_zero ? p_duration >= 0.0 : p_duration > 0.0) && p_duration <= MAX_DURATION;
}

bool GameplayEffectStackPolicy::_valid_target_scale(double p_scale) {
	return Math::is_finite(p_scale) && p_scale >= 0.0 && p_scale <= 8.0;
}

Dictionary GameplayEffectStackPolicy::_result(bool p_accepted, int p_stacks, double p_remaining,
		double p_duration, bool p_overflow, const String &p_reason) {
	Dictionary result;
	result["accepted"] = p_accepted;
	result["stacks"] = p_stacks;
	result["remaining"] = p_remaining;
	result["applied_duration"] = p_duration;
	result["overflow"] = p_overflow;
	result["reason"] = p_reason;
	return result;
}

bool GameplayEffectStackPolicy::configure(int p_max_stacks, const PackedFloat32Array &p_factors,
		int p_overflow, int p_reapply) {
	if (p_max_stacks < 1 || p_max_stacks > MAX_STACKS ||
			p_factors.is_empty() || p_factors.size() > p_max_stacks ||
			p_overflow < OVERFLOW_CLAMP || p_overflow > OVERFLOW_RESET ||
			p_reapply < REAPPLY_IF_STRONGER || p_reapply > REAPPLY_KEEP) {
		return false;
	}
	for (int i = 0; i < p_factors.size(); ++i) {
		const float factor = p_factors[i];
		if (!Math::is_finite(factor) || factor < 0.0f || factor > 8.0f) {
			return false;
		}
	}
	max_stacks = p_max_stacks;
	stack_factors = p_factors;
	overflow_policy = p_overflow;
	reapply_policy = p_reapply;
	return true;
}

double GameplayEffectStackPolicy::calculate_magnitude(double p_base_duration, int p_prior_stacks,
		double p_target_scale) const {
	if (!_valid_duration(p_base_duration) || !_valid_target_scale(p_target_scale)) {
		return 0.0;
	}
	const int index = MIN(MAX(0, p_prior_stacks), stack_factors.size() - 1);
	const double duration = p_base_duration * double(stack_factors[index]) * p_target_scale;
	if (!Math::is_finite(duration)) {
		return 0.0;
	}
	return MIN(MAX_DURATION, duration);
}

Dictionary GameplayEffectStackPolicy::preview_application(double p_base_duration, int p_prior_stacks,
		double p_current_remaining, double p_target_scale) const {
	const int bounded_stacks = CLAMP(p_prior_stacks, 0, max_stacks);
	const double safe_remaining = _valid_duration(p_current_remaining, true) ? p_current_remaining : 0.0;
	if (!_valid_duration(p_base_duration) || !_valid_duration(p_current_remaining, true) ||
			!_valid_target_scale(p_target_scale) || p_prior_stacks < 0) {
		return _result(false, bounded_stacks, safe_remaining, 0.0, false, "invalid_input");
	}
	const bool overflow = p_prior_stacks >= max_stacks;
	if (overflow && overflow_policy == OVERFLOW_REJECT) {
		return _result(false, bounded_stacks, p_current_remaining, 0.0, true, "overflow");
	}
	const int applied_index = (overflow && overflow_policy == OVERFLOW_RESET) ? 0 : bounded_stacks;
	const double duration = calculate_magnitude(p_base_duration, applied_index, p_target_scale);
	if (duration <= 0.0) {
		return _result(false, bounded_stacks, p_current_remaining, 0.0, overflow, "zero_magnitude");
	}
	const int next_stacks = (overflow && overflow_policy == OVERFLOW_RESET) ? 1 : MIN(max_stacks, bounded_stacks + 1);
	double next_remaining = duration;
	switch (reapply_policy) {
		case REAPPLY_IF_STRONGER:
			if (duration <= p_current_remaining) {
				return _result(false, bounded_stacks, p_current_remaining, duration, overflow, "weaker");
			}
			break;
		case REAPPLY_REFRESH:
			break;
		case REAPPLY_EXTEND:
			next_remaining = MIN(MAX_DURATION, p_current_remaining + duration);
			if (next_remaining <= p_current_remaining) {
				return _result(false, bounded_stacks, p_current_remaining, duration, overflow, "saturated");
			}
			break;
		case REAPPLY_KEEP:
			if (p_current_remaining > 0.0) {
				return _result(false, bounded_stacks, p_current_remaining, duration, overflow, "active");
			}
			break;
	}
	return _result(true, next_stacks, next_remaining, duration, overflow, "applied");
}

Dictionary GameplayEffectStackPolicy::get_config() const {
	Dictionary config;
	config["max_stacks"] = max_stacks;
	config["stack_factors"] = stack_factors;
	config["overflow_policy"] = overflow_policy;
	config["reapply_policy"] = reapply_policy;
	return config;
}

bool GameplayEffectStackPolicy::replace_config(const Dictionary &p_config) {
	if (!p_config.has("max_stacks") || !p_config.has("stack_factors") ||
			!p_config.has("overflow_policy") || !p_config.has("reapply_policy")) {
		return false;
	}
	const Variant max = p_config["max_stacks"];
	const Variant factors = p_config["stack_factors"];
	const Variant overflow = p_config["overflow_policy"];
	const Variant reapply = p_config["reapply_policy"];
	if (max.get_type() != Variant::INT || factors.get_type() != Variant::PACKED_FLOAT32_ARRAY ||
			overflow.get_type() != Variant::INT || reapply.get_type() != Variant::INT) {
		return false;
	}
	// Refuse oversized 64-bit values before narrowing to the bound int API.
	const int64_t max_value = int64_t(max);
	const int64_t overflow_value = int64_t(overflow);
	const int64_t reapply_value = int64_t(reapply);
	if (max_value < 1 || max_value > MAX_STACKS ||
			overflow_value < OVERFLOW_CLAMP || overflow_value > OVERFLOW_RESET ||
			reapply_value < REAPPLY_IF_STRONGER || reapply_value > REAPPLY_KEEP) {
		return false;
	}
	const PackedFloat32Array safe_factors = factors;
	return configure(int(max_value), safe_factors, int(overflow_value), int(reapply_value));
}

void GameplayEffectStackPolicy::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "max_stacks", "stack_factors", "overflow_policy", "reapply_policy"),
			&GameplayEffectStackPolicy::configure, DEFVAL(OVERFLOW_CLAMP), DEFVAL(REAPPLY_IF_STRONGER));
	ClassDB::bind_method(D_METHOD("calculate_magnitude", "base_duration", "prior_stacks", "target_scale"),
			&GameplayEffectStackPolicy::calculate_magnitude, DEFVAL(1.0));
	ClassDB::bind_method(D_METHOD("preview_application", "base_duration", "prior_stacks", "current_remaining", "target_scale"),
			&GameplayEffectStackPolicy::preview_application, DEFVAL(1.0));
	ClassDB::bind_method(D_METHOD("get_config"), &GameplayEffectStackPolicy::get_config);
	ClassDB::bind_method(D_METHOD("replace_config", "config"), &GameplayEffectStackPolicy::replace_config);
	ClassDB::bind_method(D_METHOD("get_max_stacks"), &GameplayEffectStackPolicy::get_max_stacks);
	ClassDB::bind_method(D_METHOD("get_overflow_policy"), &GameplayEffectStackPolicy::get_overflow_policy);
	ClassDB::bind_method(D_METHOD("get_reapply_policy"), &GameplayEffectStackPolicy::get_reapply_policy);

	BIND_ENUM_CONSTANT(OVERFLOW_CLAMP);
	BIND_ENUM_CONSTANT(OVERFLOW_REJECT);
	BIND_ENUM_CONSTANT(OVERFLOW_RESET);
	BIND_ENUM_CONSTANT(REAPPLY_IF_STRONGER);
	BIND_ENUM_CONSTANT(REAPPLY_REFRESH);
	BIND_ENUM_CONSTANT(REAPPLY_EXTEND);
	BIND_ENUM_CONSTANT(REAPPLY_KEEP);
}
