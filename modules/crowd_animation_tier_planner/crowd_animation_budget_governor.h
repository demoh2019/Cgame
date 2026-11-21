/**************************************************************************/
/*  crowd_animation_budget_governor.h                                     */
/*  This file is part of the Godot Engine (MIT License).                   */
/**************************************************************************/

#pragma once

#include "core/object/ref_counted.h"

// Stateless with respect to scene objects; only keeps bounded CPU time evidence.
// Optional full-pose IK budget pressure controller, following the general
// feedback principle of Unreal's Animation Budget Allocator.
class CrowdAnimationBudgetGovernor : public RefCounted {
	GDCLASS(CrowdAnimationBudgetGovernor, RefCounted);

	static constexpr int WINDOW_FRAMES = 12;
	int max_budget_us = 0;
	int current_budget_us = 0;
	int target_process_us = 12500;
	int smoothed_process_us = 0;
	int frames_observed = 0;
	int window_frames = 0;
	int high_streak = 0;
	int low_streak = 0;
	bool enabled = true;

protected:
	static void _bind_methods();

public:
	// 0..100000us maximum optional IK work; process target 1000..100000us.
	// Returns false and preserves all previous settings if malformed.
	bool configure(int p_max_budget_us, int p_target_process_us = 12500);
	void set_enabled(bool p_enabled);
	bool is_enabled() const { return enabled; }
	// Observes last completed frame's main-thread process CPU duration.
	// Zero is "not measured", ignored; invalid samples return -1.
	int observe_process_time(int64_t p_elapsed_us);
	int get_current_budget_us() const { return enabled ? current_budget_us : max_budget_us; }
	int get_max_budget_us() const { return max_budget_us; }
	int get_target_process_us() const { return target_process_us; }
	int get_smoothed_process_us() const { return smoothed_process_us; }
	int get_frames_observed() const { return frames_observed; }
	int get_pressure_percent() const;
	void reset();
};
