/**************************************************************************/
/* dynamic_resolution_panic_policy.cpp                                     */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#include "dynamic_resolution_panic_policy.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"

void DynamicResolutionPanicPolicy::_bind_methods() {
	ClassDB::bind_method(D_METHOD("calculate_scale", "current_scale", "floor_scale",
					"gpu_ms", "target_ms", "consecutive_frames", "required_frames"),
			&DynamicResolutionPanicPolicy::calculate_scale, DEFVAL(3));
}

double DynamicResolutionPanicPolicy::calculate_scale(double p_current_scale,
		double p_floor_scale, double p_gpu_ms, double p_target_ms,
		int p_consecutive_frames, int p_required_frames) const {
	// Invalid data must not request a resize. -1 is distinguishable from
	// a legitimate floor (0.5), or unchanged scale (1.0).
	if (!Math::is_finite(p_current_scale) || !Math::is_finite(p_floor_scale) ||
			!Math::is_finite(p_gpu_ms) || !Math::is_finite(p_target_ms) ||
			p_current_scale < 0.5 || p_current_scale > 1.0 ||
			p_floor_scale < 0.5 || p_floor_scale > p_current_scale ||
			p_gpu_ms < 0.0 || p_gpu_ms > 80.0 ||
			p_target_ms < 5.0 || p_target_ms > 40.0 ||
			p_required_frames < 1 || p_required_frames > 10 ||
			p_consecutive_frames < 0 || p_consecutive_frames > 1000) {
		return -1.0;
	}
	// A missing (zero) GPU timer or one transient expensive frame is never
	// evidence of a GPU bottleneck. Leave CPU stalls to other policies.
	if (p_gpu_ms < MAX(38.0, p_target_ms * 1.75) ||
			p_consecutive_frames < p_required_frames ||
			p_current_scale <= p_floor_scale) {
		return p_current_scale;
	}
	// Screen pixel count scales quadratically with linear resolution.
	// Cap a single resize at 12 percentage points to avoid excessive jitter.
	// Never cross a hardware scaler's minimum (e.g. MetalFX).
	const double projected = p_current_scale * Math::sqrt(p_target_ms / p_gpu_ms);
	const double step_limited = MAX(p_current_scale - 0.12, projected);
	const double quantized = Math::round(step_limited * 100.0) / 100.0;
	return MIN(p_current_scale, MAX(p_floor_scale, quantized));
}
