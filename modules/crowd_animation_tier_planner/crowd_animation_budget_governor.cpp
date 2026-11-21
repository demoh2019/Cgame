/**************************************************************************/
/*  crowd_animation_budget_governor.cpp                                   */
/*  This file is part of the Godot Engine (MIT License).                   */
/**************************************************************************/

#include "crowd_animation_budget_governor.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void CrowdAnimationBudgetGovernor::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "max_budget_us", "target_process_us"),
			&CrowdAnimationBudgetGovernor::configure, DEFVAL(12500));
	ClassDB::bind_method(D_METHOD("set_enabled", "enabled"), &CrowdAnimationBudgetGovernor::set_enabled);
	ClassDB::bind_method(D_METHOD("is_enabled"), &CrowdAnimationBudgetGovernor::is_enabled);
	ClassDB::bind_method(D_METHOD("observe_process_time", "elapsed_us"),
			&CrowdAnimationBudgetGovernor::observe_process_time);
	ClassDB::bind_method(D_METHOD("get_current_budget_us"), &CrowdAnimationBudgetGovernor::get_current_budget_us);
	ClassDB::bind_method(D_METHOD("get_max_budget_us"), &CrowdAnimationBudgetGovernor::get_max_budget_us);
	ClassDB::bind_method(D_METHOD("get_target_process_us"), &CrowdAnimationBudgetGovernor::get_target_process_us);
	ClassDB::bind_method(D_METHOD("get_smoothed_process_us"), &CrowdAnimationBudgetGovernor::get_smoothed_process_us);
	ClassDB::bind_method(D_METHOD("get_frames_observed"), &CrowdAnimationBudgetGovernor::get_frames_observed);
	ClassDB::bind_method(D_METHOD("get_pressure_percent"), &CrowdAnimationBudgetGovernor::get_pressure_percent);
	ClassDB::bind_method(D_METHOD("reset"), &CrowdAnimationBudgetGovernor::reset);
}

bool CrowdAnimationBudgetGovernor::configure(int p_max_budget_us, int p_target_process_us) {
	if (p_max_budget_us < 0 || p_max_budget_us > 100000 ||
			p_target_process_us < 1000 || p_target_process_us > 100000) {
		return false; // Atomic: do not partially replace budgets on failure.
	}
	if (p_max_budget_us == max_budget_us && p_target_process_us == target_process_us) {
		return true;
	}
	max_budget_us = p_max_budget_us;
	target_process_us = p_target_process_us;
	reset();
	return true;
}

void CrowdAnimationBudgetGovernor::set_enabled(bool p_enabled) {
	if (enabled == p_enabled) {
		return;
	}
	enabled = p_enabled;
	if (enabled) {
		reset(); // Never reuse stale pressure after a pause.
	}
}

void CrowdAnimationBudgetGovernor::reset() {
	current_budget_us = max_budget_us;
	smoothed_process_us = 0;
	frames_observed = 0;
	window_frames = 0;
	high_streak = 0;
	low_streak = 0;
}

int CrowdAnimationBudgetGovernor::get_pressure_percent() const {
	return MIN(1000, (smoothed_process_us * 100) / target_process_us);
}

int CrowdAnimationBudgetGovernor::observe_process_time(int64_t p_elapsed_us) {
	ERR_FAIL_COND_V_MSG(p_elapsed_us < 0 || p_elapsed_us > 1000000, -1,
			"Main-thread process duration must be between 0 and 1000000 microseconds.");
	if (!enabled || p_elapsed_us == 0 || max_budget_us == 0) {
		return get_current_budget_us();
	}
	const int sample = int(p_elapsed_us);
	smoothed_process_us = smoothed_process_us == 0 ? sample :
			(3 * smoothed_process_us + sample + 2) / 4;
	frames_observed = MIN(frames_observed + 1, 1000000);
	window_frames++;
	if (window_frames < WINDOW_FRAMES) {
		return current_budget_us;
	}
	window_frames = 0;
	// Two high-pressure windows reduce optional IK quickly; three quiet
	// windows replenish it in small increments. The wide neutral band
	// prevents chattering on camera turns or short combat spikes.
	if (int64_t(smoothed_process_us) * 100 > int64_t(target_process_us) * 95) {
		high_streak = MIN(high_streak + 1, 2);
		low_streak = 0;
	} else if (int64_t(smoothed_process_us) * 100 < int64_t(target_process_us) * 70) {
		low_streak = MIN(low_streak + 1, 3);
		high_streak = 0;
	} else {
		high_streak = 0;
		low_streak = 0;
	}
	if (high_streak >= 2) {
		const int floor_us = MAX(1, (max_budget_us + 3) / 4);
		current_budget_us = MAX(floor_us, (current_budget_us * 3 + 2) / 4);
		high_streak = 0;
	} else if (low_streak >= 3) {
		current_budget_us = MIN(max_budget_us,
				current_budget_us + MAX(1, max_budget_us / 8));
		low_streak = 0;
	}
	return current_budget_us;
}
