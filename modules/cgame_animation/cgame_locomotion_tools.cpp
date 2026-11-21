/**************************************************************************/
/*  cgame_locomotion_tools.cpp                                            */
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

#include "cgame_locomotion_tools.h"

#include "core/object/class_db.h"

float CgameLocomotionTools::playback_time_for_distance(const PackedFloat32Array &p_distance_curve, const PackedFloat32Array &p_times, float p_remaining_distance) {
	const int n = MIN(p_distance_curve.size(), p_times.size());
	if (n == 0) {
		return 0.0f;
	}
	if (n == 1) {
		return p_times[0];
	}
	const bool ascending = p_distance_curve[0] <= p_distance_curve[n - 1];
	const float first = p_distance_curve[0];
	const float last = p_distance_curve[n - 1];
	if (ascending) {
		if (p_remaining_distance <= first) {
			return p_times[0];
		}
		if (p_remaining_distance >= last) {
			return p_times[n - 1];
		}
	} else {
		if (p_remaining_distance >= first) {
			return p_times[0];
		}
		if (p_remaining_distance <= last) {
			return p_times[n - 1];
		}
	}
	int lo = 0;
	int hi = n - 1;
	while (hi - lo > 1) {
		const int mid = (lo + hi) / 2;
		const bool go_right = ascending ? p_distance_curve[mid] <= p_remaining_distance : p_distance_curve[mid] >= p_remaining_distance;
		if (go_right) {
			lo = mid;
		} else {
			hi = mid;
		}
	}
	const float d0 = p_distance_curve[lo];
	const float d1 = p_distance_curve[hi];
	if (Math::is_equal_approx(d0, d1)) {
		return p_times[lo];
	}
	const float f = (p_remaining_distance - d0) / (d1 - d0);
	return Math::lerp(p_times[lo], p_times[hi], f);
}

float CgameLocomotionTools::stride_play_rate(float p_actual_speed, float p_authored_speed, float p_min_rate, float p_max_rate) {
	if (p_authored_speed <= 0.001f) {
		return 1.0f;
	}
	return CLAMP(p_actual_speed / p_authored_speed, p_min_rate, p_max_rate);
}

Dictionary CgameLocomotionTools::orientation_warp(const Vector2 &p_velocity_dir, float p_facing_yaw, float p_max_angle) {
	Dictionary out;
	if (p_velocity_dir.length_squared() < 0.0001f) {
		out["lower_body_yaw"] = 0.0f;
		out["upper_body_yaw"] = 0.0f;
		return out;
	}
	const float vel_yaw = Math::atan2(p_velocity_dir.x, p_velocity_dir.y);
	float diff = Math::angle_difference(p_facing_yaw, vel_yaw);
	if (Math::abs(diff) > Math::PI * 0.5f + 0.0001f) {
		diff -= SIGN(diff) * (float)Math::PI;
	}
	const float lower = CLAMP(diff, -p_max_angle, p_max_angle);
	out["lower_body_yaw"] = lower;
	out["upper_body_yaw"] = -lower;
	return out;
}

Dictionary CgameLocomotionTools::motion_warp_solve(const Vector3 &p_origin, const Vector2 &p_direction, float p_reach, const Array &p_targets) {
	Dictionary none;
	if (p_direction.length_squared() < 0.0001f || !p_origin.is_finite()) {
		return none;
	}
	const Vector2 dir = p_direction.normalized();
	bool found = false;
	Vector3 best;
	float best_distance = Math::INF;
	for (int i = 0; i < p_targets.size(); i++) {
		const Vector3 p = p_targets[i];
		if (!p.is_finite()) {
			continue;
		}
		const Vector2 to(p.x - p_origin.x, p.z - p_origin.z);
		const float distance = to.length();
		if (distance < 0.05f || distance > p_reach + SEARCH_EXTRA) {
			continue;
		}
		if (to.normalized().dot(dir) < CONE_DOT) {
			continue;
		}
		if (distance < best_distance) {
			best_distance = distance;
			best = p;
			found = true;
		}
	}
	if (!found) {
		return none;
	}
	const Vector2 to_target(best.x - p_origin.x, best.z - p_origin.z);
	const float slide = CLAMP(best_distance - STOP_SHORT, 0.0f, MAX_SLIDE);
	const Vector2 flat = to_target.normalized() * slide;
	Dictionary out;
	out["offset"] = Vector3(flat.x, 0.0f, flat.y);
	out["yaw"] = Math::atan2(to_target.x, to_target.y);
	return out;
}

float CgameLocomotionTools::pelvis_offset(float p_left_target_y, float p_right_target_y, float p_left_anim_y, float p_right_anim_y) {
	const float left_corr = p_left_target_y - p_left_anim_y;
	const float right_corr = p_right_target_y - p_right_anim_y;
	return CLAMP(MIN(MIN(left_corr, right_corr), 0.0f), -0.25f, 0.0f);
}

void CgameLocomotionTools::_bind_methods() {
	ClassDB::bind_static_method("CgameLocomotionTools", D_METHOD("playback_time_for_distance", "distance_curve", "times", "remaining_distance"), &CgameLocomotionTools::playback_time_for_distance);
	ClassDB::bind_static_method("CgameLocomotionTools", D_METHOD("stride_play_rate", "actual_speed", "authored_speed", "min_rate", "max_rate"), &CgameLocomotionTools::stride_play_rate, DEFVAL(0.75f), DEFVAL(1.35f));
	ClassDB::bind_static_method("CgameLocomotionTools", D_METHOD("orientation_warp", "velocity_dir", "facing_yaw", "max_angle"), &CgameLocomotionTools::orientation_warp, DEFVAL(Math::deg_to_rad(60.0f)));
	ClassDB::bind_static_method("CgameLocomotionTools", D_METHOD("motion_warp_solve", "origin", "direction", "reach", "targets"), &CgameLocomotionTools::motion_warp_solve);
	ClassDB::bind_static_method("CgameLocomotionTools", D_METHOD("pelvis_offset", "left_target_y", "right_target_y", "left_anim_y", "right_anim_y"), &CgameLocomotionTools::pelvis_offset);
}
