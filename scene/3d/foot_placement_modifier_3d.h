/**************************************************************************/
/*  foot_placement_modifier_3d.h                                          */
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

#include "scene/3d/skeleton_modifier_3d.h"

#include "core/variant/callable.h"

#include <cstdint>

class FootPlacementModifier3D : public SkeletonModifier3D {
	GDCLASS(FootPlacementModifier3D, SkeletonModifier3D);

public:
	struct Leg {
		String thigh_bone;
		String calf_bone;
		String foot_bone;
		float foot_height_offset = 0.0f;
	};

private:
	String pelvis_bone;
	LocalVector<Leg> legs;

	Callable ground_height_callback;
	bool use_raycast = false;
	uint32_t collision_mask = 1;
	float ray_length = 3.0f;
	float ray_start_height = 1.0f;

	float max_pelvis_offset = 0.4f;
	float pelvis_interp_speed = 12.0f;
	float max_foot_angle = Math::deg_to_rad(40.0f);
	bool align_foot_to_ground = true;
	float normal_sample_distance = 0.15f;

	float pelvis_smoothed = 0.0f;
	bool pelvis_initialized = false;

	// Optional bounded main-thread CPU telemetry. Disabled by default to
	// avoid clock-read overhead for projects not using pose budgets.
	bool profiling_enabled = false;
	int last_process_cost_us = 0;
	int estimated_process_cost_us = 0;
	int process_sample_count = 0;
	void _record_process_sample(uint64_t p_started_us);

	bool _sample_ground(const Skeleton3D *p_skeleton, float p_x, float p_z, float &r_height) const;

protected:
	bool _get(const StringName &p_path, Variant &r_ret) const;
	bool _set(const StringName &p_path, const Variant &p_value);
	void _get_property_list(List<PropertyInfo> *p_list) const;

	static void _bind_methods();

	virtual void _set_active(bool p_active) override;
	virtual void _process_modification(double p_delta) override;

public:
	// Pure math helpers (also used by tests and StrideWarpingModifier3D).

	// Returns (hip_angle, knee_angle) in radians for a two bone chain.
	// hip_angle: angle at the root joint between the root->target line and the upper bone.
	// knee_angle: interior angle at the middle joint between the upper and lower bone (PI when straight).
	// The target distance is clamped to the reachable range.
	static Vector2 solve_two_bone_angles(float p_upper_len, float p_lower_len, float p_target_dist);

	// Returns the (non-positive) pelvis offset: the most negative leg offset, clamped to [-max_offset, 0].
	static float pelvis_offset(const PackedFloat32Array &p_leg_offsets, float p_max_offset);

	// Surface normal from the ground height at the foot and at +step along X and Z.
	static Vector3 ground_normal_from_samples(float p_height_center, float p_height_x, float p_height_z, float p_step);

	// Rotation taking p_from_up to p_normal, limited to p_max_angle radians.
	static Quaternion clamped_alignment(const Vector3 &p_from_up, const Vector3 &p_normal, float p_max_angle);

	// Analytically moves the foot of a thigh/calf/foot chain to p_target (skeleton space), keeping the animated knee direction.
	// Returns false when the chain is degenerate. Rotates thigh and calf only.
	static bool solve_leg(Skeleton3D *p_skeleton, int p_thigh, int p_calf, int p_foot, const Vector3 &p_target);

	void set_pelvis_bone(const String &p_name);
	String get_pelvis_bone() const;

	void set_leg_count(int p_count);
	int get_leg_count() const;
	int add_leg(const String &p_thigh_bone, const String &p_calf_bone, const String &p_foot_bone, float p_foot_height_offset = 0.0f);
	void clear_legs();

	void set_ground_height_callback(const Callable &p_callback);
	Callable get_ground_height_callback() const;
	void set_use_raycast(bool p_enabled);
	bool is_using_raycast() const;
	void set_collision_mask(uint32_t p_mask);
	uint32_t get_collision_mask() const;
	void set_ray_length(float p_length);
	float get_ray_length() const;
	void set_ray_start_height(float p_height);
	float get_ray_start_height() const;

	void set_max_pelvis_offset(float p_offset);
	float get_max_pelvis_offset() const;
	void set_pelvis_interp_speed(float p_speed);
	float get_pelvis_interp_speed() const;
	void set_max_foot_angle(float p_angle);
	float get_max_foot_angle() const;
	void set_align_foot_to_ground(bool p_enabled);
	bool is_aligning_foot_to_ground() const;
	void set_normal_sample_distance(float p_distance);
	float get_normal_sample_distance() const;

	float get_current_pelvis_offset() const;
	void reset();

	// A measured update costs at least 1us and at most 100,000us.
	// Previous estimate 0 denotes an unseen work unit; invalid inputs
	// fail closed. Static helper is used by telemetry and regression tests.
	static int smooth_process_cost_us(int p_previous_us, int p_sample_us);
	void set_profiling_enabled(bool p_enabled);
	bool is_profiling_enabled() const { return profiling_enabled; }
	void reset_process_telemetry();
	int get_last_process_cost_us() const { return last_process_cost_us; }
	int get_estimated_process_cost_us() const { return estimated_process_cost_us; }
	int get_process_sample_count() const { return process_sample_count; }

	FootPlacementModifier3D() {}
};
