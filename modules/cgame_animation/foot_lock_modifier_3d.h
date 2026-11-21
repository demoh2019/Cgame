/**************************************************************************/
/*  foot_lock_modifier_3d.h                                               */
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

#include "core/variant/callable.h"
#include "scene/3d/skeleton_modifier_3d.h"

// Foot locking with contact phases: plants a foot in world space while its contact signal is high,
// then runs two-bone leg IK to keep it there. Inspired by UE5 Foot Placement and Unity Animation
// Rigging foot pinning. The planting logic is pure (CgameFootLockState) so it can be unit tested.
struct CgameFootLockState {
	struct Params {
		float max_stretch = 0.35f; // Metres the body may pull a locked foot from the animated pose.
		float blend_in = 0.08f; // Seconds to reach full IK weight after plant.
		float blend_out = 0.2f; // Seconds to return to the animation after lift-off or release.
		float plant_threshold = 0.5f;
	};

	struct Output {
		Vector3 target;
		float weight = 0.0f;
		bool locked = false;
	};

	bool locked = false;
	bool released = false; // Stretched out; no re-lock until lift-off.
	Vector3 lock_pos;
	float weight = 0.0f;

	Output update(float p_delta, const Vector3 &p_anim_pos, float p_contact, float p_ground_y, const Params &p_params);
	void reset();
};

class FootLockModifier3D : public SkeletonModifier3D {
	GDCLASS(FootLockModifier3D, SkeletonModifier3D);

	String left_foot_bone;
	String right_foot_bone;
	String pelvis_bone;
	bool pelvis_adjust = true;
	float left_contact = 0.0f;
	float right_contact = 0.0f;
	float ground_height = 0.0f;
	Callable ground_height_callback;
	CgameFootLockState::Params params;

	CgameFootLockState left_state;
	CgameFootLockState right_state;

	float _ground_y(const Vector3 &p_world_pos) const;
	void _apply_leg(Skeleton3D *p_skeleton, int p_foot, const Vector3 &p_target_skeleton, float p_weight);

protected:
	static void _bind_methods();
	virtual void _process_modification(double p_delta) override;
	virtual void _set_active(bool p_active) override;

public:
	void set_left_foot_bone(const String &p_name);
	String get_left_foot_bone() const;
	void set_right_foot_bone(const String &p_name);
	String get_right_foot_bone() const;
	void set_pelvis_bone(const String &p_name);
	String get_pelvis_bone() const;
	void set_pelvis_adjust(bool p_enabled);
	bool is_pelvis_adjust() const;
	void set_left_contact(float p_contact);
	float get_left_contact() const;
	void set_right_contact(float p_contact);
	float get_right_contact() const;
	void set_ground_height(float p_height);
	float get_ground_height() const;
	void set_ground_height_callback(const Callable &p_callback);
	Callable get_ground_height_callback() const;
	void set_max_stretch(float p_value);
	float get_max_stretch() const;
	void set_blend_in(float p_value);
	float get_blend_in() const;
	void set_blend_out(float p_value);
	float get_blend_out() const;
	void set_plant_threshold(float p_value);
	float get_plant_threshold() const;

	bool is_foot_locked(bool p_left) const;
	float get_foot_weight(bool p_left) const;
	void reset_locks();
};
