/**************************************************************************/
/*  adaptive_resolution_3d.h                                              */
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

#pragma once

#include "scene/main/node.h"

class Viewport;

/**
 * GPU-time-driven dynamic 3D render resolution.
 *
 * This node is opt-in and never changes lighting, effects, or UI resolution.
 * Add exactly one instance under each Viewport to manage.
 */
class AdaptiveResolution3D : public Node {
	GDCLASS(AdaptiveResolution3D, Node);

	Viewport *observed_viewport = nullptr;
	bool enabled = true;
	int target_fps = 60;
	float min_scale = 0.67f;
	float max_scale = 1.0f;
	float update_interval = 0.75f;
	float decrease_step = 0.05f;
	float increase_step = 0.025f;
	float gpu_budget_fraction = 0.9f;

	double sample_elapsed = 0.0;
	double smoothed_gpu_ms = 0.0;
	int valid_samples = 0;

	void _start_monitoring();
	void _stop_monitoring();

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	void set_enabled(bool p_enabled);
	bool is_enabled() const;

	void set_target_fps(int p_fps);
	int get_target_fps() const;

	void set_min_scale(float p_scale);
	float get_min_scale() const;

	void set_max_scale(float p_scale);
	float get_max_scale() const;

	void set_update_interval(float p_seconds);
	float get_update_interval() const;

	void set_decrease_step(float p_step);
	float get_decrease_step() const;

	void set_increase_step(float p_step);
	float get_increase_step() const;

	void set_gpu_budget_fraction(float p_fraction);
	float get_gpu_budget_fraction() const;

	float get_current_scale() const;
	double get_smoothed_gpu_time_ms() const;

	// Pure function for deterministic tests; GPU timing may be unsupported.
	static float calculate_next_scale(float p_current_scale, double p_gpu_ms, double p_target_gpu_ms,
			float p_min_scale, float p_max_scale, float p_decrease_step, float p_increase_step);

	AdaptiveResolution3D();
};
