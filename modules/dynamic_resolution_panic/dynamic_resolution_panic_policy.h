/**************************************************************************/
/* dynamic_resolution_panic_policy.h                                       */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "core/object/ref_counted.h"

// GPU-only emergency response to repeated expensive frames, inspired by
// Unreal's Dynamic Resolution over-budget panic. Pure, deterministic policy:
// the caller owns timing, cooldown, history, viewport and GPU measurements.
class DynamicResolutionPanicPolicy : public RefCounted {
	GDCLASS(DynamicResolutionPanicPolicy, RefCounted);

protected:
	static void _bind_methods();

public:
	// Returns a proposed scale, unchanged when not over budget, or -1 on
	// malformed inputs. Never increases the scale or crosses the device floor.
	double calculate_scale(double p_current_scale, double p_floor_scale,
			double p_gpu_ms, double p_target_ms,
			int p_consecutive_frames, int p_required_frames = 3) const;
};
