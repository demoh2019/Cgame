/**************************************************************************/
/*  adaptive_resolution_3d.cpp                                            */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "adaptive_resolution_3d.h"

#include "core/config/engine.h"
#include "core/object/class_db.h"
#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "scene/main/viewport.h"
#include "servers/rendering/rendering_server.h"

float AdaptiveResolution3D::calculate_next_scale(float p_current_scale, double p_gpu_ms, double p_target_gpu_ms,
		float p_min_scale, float p_max_scale, float p_decrease_step, float p_increase_step) {
	const float minimum = MIN(p_min_scale, p_max_scale);
	const float maximum = MAX(p_min_scale, p_max_scale);
	const float scale = CLAMP(p_current_scale, minimum, maximum);

	if (p_gpu_ms <= 0.0 || p_target_gpu_ms <= 0.0) {
		return scale;
	}

	// Hysteresis prevents rapid changes when the GPU is close to its budget.
	if (p_gpu_ms > p_target_gpu_ms * 1.08) {
		return MAX(minimum, scale - MAX(0.0f, p_decrease_step));
	}
	if (p_gpu_ms < p_target_gpu_ms * 0.78) {
		return MIN(maximum, scale + MAX(0.0f, p_increase_step));
	}
	return scale;
}

void AdaptiveResolution3D::_start_monitoring() {
	if (!enabled || !is_inside_tree() || Engine::get_singleton()->is_editor_hint() || observed_viewport) {
		return;
	}

	observed_viewport = get_viewport();
	if (!observed_viewport) {
		return;
	}

	sample_elapsed = 0.0;
	smoothed_gpu_ms = 0.0;
	valid_samples = 0;
	RenderingServer::get_singleton()->viewport_set_measure_render_time(observed_viewport->get_viewport_rid(), true);
	set_process(true);
}

void AdaptiveResolution3D::_stop_monitoring() {
	set_process(false);
	if (observed_viewport) {
		RenderingServer::get_singleton()->viewport_set_measure_render_time(observed_viewport->get_viewport_rid(), false);
		observed_viewport = nullptr;
	}
	sample_elapsed = 0.0;
	smoothed_gpu_ms = 0.0;
	valid_samples = 0;
}

void AdaptiveResolution3D::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_ENTER_TREE: {
			_start_monitoring();
		} break;
		case NOTIFICATION_EXIT_TREE: {
			_stop_monitoring();
		} break;
		case NOTIFICATION_PROCESS: {
			if (!observed_viewport) {
				return;
			}
			const double delta = get_process_delta_time();
			if (delta <= 0.0) {
				return;
			}

			const double gpu_ms = RenderingServer::get_singleton()->viewport_get_measured_render_time_gpu(observed_viewport->get_viewport_rid());
			if (gpu_ms > 0.0 && gpu_ms < 1000.0) {
				// An exponential moving average suppresses isolated frame spikes.
				const double alpha = CLAMP(delta / 0.5, 0.0, 1.0);
				smoothed_gpu_ms = (valid_samples == 0 && smoothed_gpu_ms == 0.0)
						? gpu_ms
						: smoothed_gpu_ms + alpha * (gpu_ms - smoothed_gpu_ms);
				valid_samples++;
			}

			sample_elapsed += delta;
			if (sample_elapsed < update_interval) {
				return;
			}
			sample_elapsed = 0.0;
			if (valid_samples < 3) {
				valid_samples = 0;
				return; // Unsupported GPU timing: retain existing visual quality.
			}
			valid_samples = 0;

			const double budget_ms = 1000.0 * gpu_budget_fraction / target_fps;
			const float previous_scale = observed_viewport->get_scaling_3d_scale();
			const float next_scale = calculate_next_scale(previous_scale, smoothed_gpu_ms, budget_ms,
					min_scale, max_scale, decrease_step, increase_step);
			if (!Math::is_equal_approx(previous_scale, next_scale)) {
				observed_viewport->set_scaling_3d_scale(next_scale);
				emit_signal(SNAME("scale_changed"), next_scale);
			}
		} break;
	}
}

void AdaptiveResolution3D::set_enabled(bool p_enabled) {
	if (enabled == p_enabled) {
		return;
	}
	enabled = p_enabled;
	if (enabled) {
		_start_monitoring();
	} else {
		_stop_monitoring();
	}
}

bool AdaptiveResolution3D::is_enabled() const {
	return enabled;
}

void AdaptiveResolution3D::set_target_fps(int p_fps) {
	target_fps = CLAMP(p_fps, 15, 240);
}

int AdaptiveResolution3D::get_target_fps() const {
	return target_fps;
}

void AdaptiveResolution3D::set_min_scale(float p_scale) {
	min_scale = CLAMP(p_scale, 0.1f, 2.0f);
	max_scale = MAX(max_scale, min_scale);
}

float AdaptiveResolution3D::get_min_scale() const {
	return min_scale;
}

void AdaptiveResolution3D::set_max_scale(float p_scale) {
	max_scale = CLAMP(p_scale, 0.1f, 2.0f);
	min_scale = MIN(min_scale, max_scale);
}

float AdaptiveResolution3D::get_max_scale() const {
	return max_scale;
}

void AdaptiveResolution3D::set_update_interval(float p_seconds) {
	update_interval = CLAMP(p_seconds, 0.25f, 5.0f);
}

float AdaptiveResolution3D::get_update_interval() const {
	return update_interval;
}

void AdaptiveResolution3D::set_decrease_step(float p_step) {
	decrease_step = CLAMP(p_step, 0.001f, 0.25f);
}

float AdaptiveResolution3D::get_decrease_step() const {
	return decrease_step;
}

void AdaptiveResolution3D::set_increase_step(float p_step) {
	increase_step = CLAMP(p_step, 0.001f, 0.25f);
}

float AdaptiveResolution3D::get_increase_step() const {
	return increase_step;
}

void AdaptiveResolution3D::set_gpu_budget_fraction(float p_fraction) {
	gpu_budget_fraction = CLAMP(p_fraction, 0.5f, 1.0f);
}

float AdaptiveResolution3D::get_gpu_budget_fraction() const {
	return gpu_budget_fraction;
}

float AdaptiveResolution3D::get_current_scale() const {
	return observed_viewport ? observed_viewport->get_scaling_3d_scale() : 1.0f;
}

double AdaptiveResolution3D::get_smoothed_gpu_time_ms() const {
	return smoothed_gpu_ms;
}

void AdaptiveResolution3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_enabled", "enabled"), &AdaptiveResolution3D::set_enabled);
	ClassDB::bind_method(D_METHOD("is_enabled"), &AdaptiveResolution3D::is_enabled);
	ClassDB::bind_method(D_METHOD("set_target_fps", "fps"), &AdaptiveResolution3D::set_target_fps);
	ClassDB::bind_method(D_METHOD("get_target_fps"), &AdaptiveResolution3D::get_target_fps);
	ClassDB::bind_method(D_METHOD("set_min_scale", "scale"), &AdaptiveResolution3D::set_min_scale);
	ClassDB::bind_method(D_METHOD("get_min_scale"), &AdaptiveResolution3D::get_min_scale);
	ClassDB::bind_method(D_METHOD("set_max_scale", "scale"), &AdaptiveResolution3D::set_max_scale);
	ClassDB::bind_method(D_METHOD("get_max_scale"), &AdaptiveResolution3D::get_max_scale);
	ClassDB::bind_method(D_METHOD("set_update_interval", "seconds"), &AdaptiveResolution3D::set_update_interval);
	ClassDB::bind_method(D_METHOD("get_update_interval"), &AdaptiveResolution3D::get_update_interval);
	ClassDB::bind_method(D_METHOD("set_decrease_step", "step"), &AdaptiveResolution3D::set_decrease_step);
	ClassDB::bind_method(D_METHOD("get_decrease_step"), &AdaptiveResolution3D::get_decrease_step);
	ClassDB::bind_method(D_METHOD("set_increase_step", "step"), &AdaptiveResolution3D::set_increase_step);
	ClassDB::bind_method(D_METHOD("get_increase_step"), &AdaptiveResolution3D::get_increase_step);
	ClassDB::bind_method(D_METHOD("set_gpu_budget_fraction", "fraction"), &AdaptiveResolution3D::set_gpu_budget_fraction);
	ClassDB::bind_method(D_METHOD("get_gpu_budget_fraction"), &AdaptiveResolution3D::get_gpu_budget_fraction);
	ClassDB::bind_method(D_METHOD("get_current_scale"), &AdaptiveResolution3D::get_current_scale);
	ClassDB::bind_method(D_METHOD("get_smoothed_gpu_time_ms"), &AdaptiveResolution3D::get_smoothed_gpu_time_ms);

	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enabled"), "set_enabled", "is_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "target_fps", PROPERTY_HINT_RANGE, "15,240,1"), "set_target_fps", "get_target_fps");
	ADD_GROUP("Resolution", "");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_scale", PROPERTY_HINT_RANGE, "0.1,2.0,0.01"), "set_min_scale", "get_min_scale");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_scale", PROPERTY_HINT_RANGE, "0.1,2.0,0.01"), "set_max_scale", "get_max_scale");
	ADD_GROUP("Adaptation", "");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "update_interval", PROPERTY_HINT_RANGE, "0.25,5.0,0.05,suffix:s"), "set_update_interval", "get_update_interval");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "decrease_step", PROPERTY_HINT_RANGE, "0.001,0.25,0.005"), "set_decrease_step", "get_decrease_step");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "increase_step", PROPERTY_HINT_RANGE, "0.001,0.25,0.005"), "set_increase_step", "get_increase_step");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "gpu_budget_fraction", PROPERTY_HINT_RANGE, "0.5,1.0,0.01"), "set_gpu_budget_fraction", "get_gpu_budget_fraction");
	ADD_SIGNAL(MethodInfo("scale_changed", PropertyInfo(Variant::FLOAT, "scale")));
}

AdaptiveResolution3D::AdaptiveResolution3D() {
	set_process(false);
}
