/**************************************************************************/
/*  cgame_locomotion_tools.h                                              */
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

#include "core/math/vector2.h"
#include "core/math/vector3.h"
#include "core/object/ref_counted.h"
#include "core/variant/dictionary.h"
#include "core/variant/typed_array.h"

// Distance matching, stride/orientation warping and attack motion warping (mirrors
// distance_matching.gd and motion_warp.gd, minus the tween which stays in script).
class CgameLocomotionTools : public RefCounted {
	GDCLASS(CgameLocomotionTools, RefCounted);

protected:
	static void _bind_methods();

public:
	static constexpr float MAX_SLIDE = 0.45f;
	static constexpr float CONE_DOT = 0.5f;
	static constexpr float SEARCH_EXTRA = 1.2f;
	static constexpr float LUNGE_SECONDS = 0.14f;
	static constexpr float RETURN_SECONDS = 0.26f;
	static constexpr float STOP_SHORT = 0.75f;

	static float playback_time_for_distance(const PackedFloat32Array &p_distance_curve, const PackedFloat32Array &p_times, float p_remaining_distance);
	static float stride_play_rate(float p_actual_speed, float p_authored_speed, float p_min_rate = 0.75f, float p_max_rate = 1.35f);
	static Dictionary orientation_warp(const Vector2 &p_velocity_dir, float p_facing_yaw, float p_max_angle = Math::deg_to_rad(60.0f));
	static Dictionary motion_warp_solve(const Vector3 &p_origin, const Vector2 &p_direction, float p_reach, const Array &p_targets);
	static float pelvis_offset(float p_left_target_y, float p_right_target_y, float p_left_anim_y, float p_right_anim_y);
};
