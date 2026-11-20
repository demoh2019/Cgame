/**************************************************************************/
/*  stride_warping_modifier_3d.h                                          */
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

class StrideWarpingModifier3D : public SkeletonModifier3D {
	GDCLASS(StrideWarpingModifier3D, SkeletonModifier3D);

public:
	struct Leg {
		String thigh_bone;
		String calf_bone;
		String foot_bone;
	};

private:
	String pelvis_bone;
	LocalVector<Leg> legs;

	float stride_scale = 1.0f;
	float min_stride_scale = 0.5f;
	float max_stride_scale = 2.0f;

protected:
	bool _get(const StringName &p_path, Variant &r_ret) const;
	bool _set(const StringName &p_path, const Variant &p_value);
	void _get_property_list(List<PropertyInfo> *p_list) const;

	static void _bind_methods();

	virtual void _process_modification(double p_delta) override;

public:
	// stride_scale = actual_speed / animation_speed, clamped to [min_scale, max_scale]. Returns 1 when animation_speed is ~0.
	static float compute_stride_scale(float p_actual_speed, float p_animation_speed, float p_min_scale, float p_max_scale);

	// Scales the horizontal (XZ) offset of p_foot from p_pelvis by p_scale and keeps the foot height.
	static Vector3 warp_foot_position(const Vector3 &p_foot, const Vector3 &p_pelvis, float p_scale);

	void set_pelvis_bone(const String &p_name);
	String get_pelvis_bone() const;

	void set_leg_count(int p_count);
	int get_leg_count() const;
	int add_leg(const String &p_thigh_bone, const String &p_calf_bone, const String &p_foot_bone);
	void clear_legs();

	void set_stride_scale(float p_scale);
	float get_stride_scale() const;
	void set_min_stride_scale(float p_scale);
	float get_min_stride_scale() const;
	void set_max_stride_scale(float p_scale);
	float get_max_stride_scale() const;
	void set_speeds(float p_actual_speed, float p_animation_speed);

	StrideWarpingModifier3D() {}
};
