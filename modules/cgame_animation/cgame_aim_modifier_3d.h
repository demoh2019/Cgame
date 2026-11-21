/**************************************************************************/
/*  cgame_aim_modifier_3d.h                                               */
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

// Aims a bone's forward axis at a target with an optional angular limit.
// Named CgameAimModifier3D because the engine already ships an unrelated AimModifier3D
// (a BoneConstraint3D driven by a reference bone).
class CgameAimModifier3D : public SkeletonModifier3D {
	GDCLASS(CgameAimModifier3D, SkeletonModifier3D);

	String bone_name;
	BoneAxis forward_axis = BONE_AXIS_PLUS_Z;
	NodePath target_node;
	Vector3 target_position;
	bool use_target_node = true;
	float max_angle = 180.0f; // Degrees.

protected:
	static void _bind_methods();
	virtual void _process_modification(double p_delta) override;

public:
	void set_bone_name(const String &p_name);
	String get_bone_name() const;
	void set_forward_axis(BoneAxis p_axis);
	BoneAxis get_forward_axis() const;
	void set_target_node(const NodePath &p_path);
	NodePath get_target_node() const;
	void set_target_position(const Vector3 &p_position);
	Vector3 get_target_position() const;
	void set_use_target_node(bool p_enabled);
	bool is_using_target_node() const;
	void set_max_angle(float p_degrees);
	float get_max_angle() const;
};
