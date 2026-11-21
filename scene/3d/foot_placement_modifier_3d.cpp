/**************************************************************************/
/*  foot_placement_modifier_3d.cpp                                        */
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

#include "foot_placement_modifier_3d.h"

#include "core/object/class_db.h"
#include "core/os/time.h"
#include "scene/3d/skeleton_3d.h"
#include "scene/resources/3d/world_3d.h"

#ifndef PHYSICS_3D_DISABLED
#include "servers/physics_3d/physics_server_3d.h"
#endif // PHYSICS_3D_DISABLED

// Static math.

Vector2 FootPlacementModifier3D::solve_two_bone_angles(float p_upper_len, float p_lower_len, float p_target_dist) {
	if (p_upper_len <= (float)CMP_EPSILON || p_lower_len <= (float)CMP_EPSILON) {
		return Vector2(0, (float)Math::PI);
	}
	float max_reach = p_upper_len + p_lower_len;
	float min_reach = MIN(Math::abs(p_upper_len - p_lower_len) + 0.0001f, max_reach);
	float d = CLAMP(p_target_dist, min_reach, max_reach);
	float cos_hip = (p_upper_len * p_upper_len + d * d - p_lower_len * p_lower_len) / (2.0f * p_upper_len * d);
	float cos_knee = (p_upper_len * p_upper_len + p_lower_len * p_lower_len - d * d) / (2.0f * p_upper_len * p_lower_len);
	return Vector2(Math::acos(CLAMP(cos_hip, -1.0f, 1.0f)), Math::acos(CLAMP(cos_knee, -1.0f, 1.0f)));
}

float FootPlacementModifier3D::pelvis_offset(const PackedFloat32Array &p_leg_offsets, float p_max_offset) {
	float lowest = 0.0f;
	for (int i = 0; i < p_leg_offsets.size(); i++) {
		lowest = MIN(lowest, p_leg_offsets[i]);
	}
	return MAX(lowest, -Math::abs(p_max_offset));
}

Vector3 FootPlacementModifier3D::ground_normal_from_samples(float p_height_center, float p_height_x, float p_height_z, float p_step) {
	if (p_step <= (float)CMP_EPSILON) {
		return Vector3(0, 1, 0);
	}
	// Tangents (step, dx, 0) and (0, dz, step); normal = tz x tx = (-step * dx, step * step, -step * dz).
	float dx = p_height_x - p_height_center;
	float dz = p_height_z - p_height_center;
	return Vector3(-dx * p_step, p_step * p_step, -dz * p_step).normalized();
}

Quaternion FootPlacementModifier3D::clamped_alignment(const Vector3 &p_from_up, const Vector3 &p_normal, float p_max_angle) {
	Vector3 from = p_from_up.normalized();
	Vector3 to = p_normal.normalized();
	Vector3 axis = from.cross(to);
	float sin_a = axis.length();
	float angle = Math::atan2(sin_a, from.dot(to));
	if (sin_a <= 0.00001f || angle <= 0.00001f) {
		return Quaternion();
	}
	angle = MIN(angle, MAX(p_max_angle, 0.0f));
	return Quaternion(axis / sin_a, angle);
}

bool FootPlacementModifier3D::solve_leg(Skeleton3D *p_skeleton, int p_thigh, int p_calf, int p_foot, const Vector3 &p_target) {
	ERR_FAIL_NULL_V(p_skeleton, false);
	if (p_thigh < 0 || p_calf < 0 || p_foot < 0) {
		return false;
	}

	Vector3 root = p_skeleton->get_bone_global_pose(p_thigh).origin;
	Vector3 mid = p_skeleton->get_bone_global_pose(p_calf).origin;
	Vector3 end = p_skeleton->get_bone_global_pose(p_foot).origin;

	float upper = (mid - root).length();
	float lower = (end - mid).length();
	Vector3 to_target = p_target - root;
	float dist = to_target.length();
	if (upper <= (float)CMP_EPSILON || lower <= (float)CMP_EPSILON || dist <= (float)CMP_EPSILON) {
		return false;
	}
	Vector3 dir = to_target / dist;

	float max_reach = upper + lower;
	float min_reach = MIN(Math::abs(upper - lower) + 0.0001f, max_reach);
	float reach = CLAMP(dist, min_reach, max_reach);
	Vector2 angles = solve_two_bone_angles(upper, lower, reach);
	float hip = angles.x;

	// Keep the animated knee direction as the pole.
	Vector3 knee = mid - root;
	Vector3 pole = knee - dir * knee.dot(dir);
	if (pole.length_squared() < 0.000001f) {
		pole = dir.cross(Vector3(1, 0, 0));
		if (pole.length_squared() < 0.000001f) {
			pole = dir.cross(Vector3(0, 0, 1));
		}
	}
	pole.normalize();

	Vector3 new_mid = root + dir * (upper * Math::cos(hip)) + pole * (upper * Math::sin(hip));
	Vector3 new_end = root + dir * reach;

	// Thigh.
	Vector3 from = (mid - root).normalized();
	Vector3 to = (new_mid - root).normalized();
	Quaternion rot = Quaternion(from, to);
	Quaternion thigh_global = (rot * p_skeleton->get_bone_global_pose(p_thigh).basis.get_rotation_quaternion()).normalized();
	p_skeleton->set_bone_pose_rotation(p_thigh, get_local_pose_rotation(p_skeleton, p_thigh, thigh_global));

	// Calf (read the updated chain).
	Vector3 mid_cur = p_skeleton->get_bone_global_pose(p_calf).origin;
	Vector3 end_cur = p_skeleton->get_bone_global_pose(p_foot).origin;
	Vector3 from2 = end_cur - mid_cur;
	Vector3 to2 = new_end - mid_cur;
	if (from2.length_squared() > 0.000001f && to2.length_squared() > 0.000001f) {
		Quaternion rot2 = Quaternion(from2.normalized(), to2.normalized());
		Quaternion calf_global = (rot2 * p_skeleton->get_bone_global_pose(p_calf).basis.get_rotation_quaternion()).normalized();
		p_skeleton->set_bone_pose_rotation(p_calf, get_local_pose_rotation(p_skeleton, p_calf, calf_global));
	}
	return true;
}

// Ground sampling.

bool FootPlacementModifier3D::_sample_ground(const Skeleton3D *p_skeleton, float p_x, float p_z, float &r_height) const {
	if (ground_height_callback.is_valid()) {
		Variant x = p_x;
		Variant z = p_z;
		const Variant *args[2] = { &x, &z };
		Variant ret;
		Callable::CallError ce;
		ground_height_callback.callp(args, 2, ret, ce);
		if (ce.error != Callable::CallError::CALL_OK) {
			return false;
		}
		if (ret.get_type() == Variant::FLOAT || ret.get_type() == Variant::INT) {
			r_height = ret;
			return true;
		}
		return false;
	}

#ifndef PHYSICS_3D_DISABLED
	if (use_raycast && p_skeleton->is_inside_tree()) {
		Ref<World3D> w3d = p_skeleton->get_world_3d();
		if (w3d.is_null() || PhysicsServer3D::get_singleton() == nullptr) {
			return false;
		}
		PhysicsDirectSpaceState3D *dss = PhysicsServer3D::get_singleton()->space_get_direct_state(w3d->get_space());
		if (dss == nullptr) {
			return false;
		}
		float origin_y = p_skeleton->get_global_transform().origin.y;
		PS3DT::RayParameters params;
		params.from = Vector3(p_x, origin_y + ray_start_height, p_z);
		params.to = Vector3(p_x, origin_y + ray_start_height - ray_length, p_z);
		params.collision_mask = collision_mask;
		PS3DT::RayResult result;
		if (dss->intersect_ray(params, result)) {
			r_height = result.position.y;
			return true;
		}
	}
#endif // PHYSICS_3D_DISABLED
	return false;
}

// Processing.

void FootPlacementModifier3D::_set_active(bool p_active) {
	if (p_active) {
		reset();
	}
}

void FootPlacementModifier3D::reset() {
	pelvis_smoothed = 0.0f;
	pelvis_initialized = false;
}

int FootPlacementModifier3D::smooth_process_cost_us(int p_previous_us, int p_sample_us) {
	ERR_FAIL_COND_V_MSG(p_previous_us < 0 || p_previous_us > 100000 ||
					p_sample_us <= 0 || p_sample_us > 100000, -1,
			"Foot IK CPU telemetry samples must be in 1..100000us; the previous sample may be zero.");
	return p_previous_us == 0 ? p_sample_us : (3 * p_previous_us + p_sample_us + 2) / 4;
}

void FootPlacementModifier3D::reset_process_telemetry() {
	last_process_cost_us = 0;
	estimated_process_cost_us = 0;
	process_sample_count = 0;
}

void FootPlacementModifier3D::set_profiling_enabled(bool p_enabled) {
	if (profiling_enabled == p_enabled) {
		return;
	}
	profiling_enabled = p_enabled;
	reset_process_telemetry();
}

void FootPlacementModifier3D::_record_process_sample(uint64_t p_started_us) {
	if (!profiling_enabled) {
		return;
	}
	const uint64_t now_us = Time::get_singleton()->get_ticks_usec();
	const uint64_t measured_us = now_us >= p_started_us ? now_us - p_started_us : 1;
	const int bounded_us = int(CLAMP(measured_us, uint64_t(1), uint64_t(100000)));
	last_process_cost_us = bounded_us;
	estimated_process_cost_us = smooth_process_cost_us(estimated_process_cost_us, bounded_us);
	process_sample_count = MIN(process_sample_count + 1, 1000000);
}

void FootPlacementModifier3D::_process_modification(double p_delta) {
	Skeleton3D *skeleton = get_skeleton();
	if (!skeleton || legs.is_empty() || influence <= 0.0) {
		return;
	}
	if (!ground_height_callback.is_valid() && !use_raycast) {
		return;
	}
	const uint64_t started_us = profiling_enabled ? Time::get_singleton()->get_ticks_usec() : 0;

	const Transform3D skel_xf = skeleton->get_global_transform();
	const Transform3D skel_inv = skel_xf.affine_inverse();

	float root_ground = 0.0f;
	if (!_sample_ground(skeleton, skel_xf.origin.x, skel_xf.origin.z, root_ground)) {
		_record_process_sample(started_us);
		return;
	}

	struct LegState {
		int thigh = -1;
		int calf = -1;
		int foot = -1;
		Vector3 foot_world;
		float delta = 0.0f;
		float ground = 0.0f;
		bool valid = false;
	};
	LocalVector<LegState> states;
	states.resize(legs.size());

	PackedFloat32Array offsets;
	for (uint32_t i = 0; i < legs.size(); i++) {
		LegState &st = states[i];
		st.thigh = skeleton->find_bone(legs[i].thigh_bone);
		st.calf = skeleton->find_bone(legs[i].calf_bone);
		st.foot = skeleton->find_bone(legs[i].foot_bone);
		if (st.thigh < 0 || st.calf < 0 || st.foot < 0) {
			continue;
		}
		st.foot_world = skel_xf.xform(skeleton->get_bone_global_pose(st.foot).origin);
		float ground = 0.0f;
		if (!_sample_ground(skeleton, st.foot_world.x, st.foot_world.z, ground)) {
			continue;
		}
		st.ground = ground;
		st.delta = (ground - root_ground) * (float)influence;
		st.valid = true;
		offsets.push_back(st.delta);
	}
	if (offsets.is_empty()) {
		_record_process_sample(started_us);
		return;
	}

	// Pelvis.
	int pelvis = pelvis_bone.is_empty() ? -1 : skeleton->find_bone(pelvis_bone);
	float pelvis_target = pelvis_offset(offsets, max_pelvis_offset);
	if (!pelvis_initialized || pelvis_interp_speed <= 0.0f) {
		pelvis_smoothed = pelvis_target;
		pelvis_initialized = true;
	} else {
		float t = 1.0f - Math::exp(-pelvis_interp_speed * (float)p_delta);
		pelvis_smoothed = Math::lerp(pelvis_smoothed, pelvis_target, t);
	}
	if (pelvis >= 0) {
		Vector3 skel_delta = skel_inv.basis.xform(Vector3(0, pelvis_smoothed, 0));
		int parent = skeleton->get_bone_parent(pelvis);
		Basis parent_basis;
		if (parent >= 0) {
			parent_basis = skeleton->get_bone_global_pose(parent).basis;
		}
		Vector3 local_delta = parent_basis.inverse().xform(skel_delta);
		skeleton->set_bone_pose_position(pelvis, skeleton->get_bone_pose_position(pelvis) + local_delta);
	}

	// Legs.
	for (uint32_t i = 0; i < legs.size(); i++) {
		const LegState &st = states[i];
		if (!st.valid) {
			continue;
		}
		Vector3 target_world = st.foot_world;
		target_world.y += st.delta + legs[i].foot_height_offset;
		Vector3 target_skel = skel_inv.xform(target_world);
		if (!solve_leg(skeleton, st.thigh, st.calf, st.foot, target_skel)) {
			continue;
		}

		if (align_foot_to_ground) {
			float hx = st.ground;
			float hz = st.ground;
			bool ok_x = _sample_ground(skeleton, st.foot_world.x + normal_sample_distance, st.foot_world.z, hx);
			bool ok_z = _sample_ground(skeleton, st.foot_world.x, st.foot_world.z + normal_sample_distance, hz);
			if (ok_x && ok_z) {
				Vector3 normal_world = ground_normal_from_samples(st.ground, hx, hz, normal_sample_distance);
				Vector3 normal_skel = skel_inv.basis.xform(normal_world).normalized();
				Vector3 up_skel = skel_inv.basis.xform(Vector3(0, 1, 0)).normalized();
				Quaternion align = clamped_alignment(up_skel, normal_skel, max_foot_angle);
				align = Quaternion().slerp(align, (float)influence);
				Quaternion foot_global = (align * skeleton->get_bone_global_pose(st.foot).basis.get_rotation_quaternion()).normalized();
				skeleton->set_bone_pose_rotation(st.foot, get_local_pose_rotation(skeleton, st.foot, foot_global));
			}
		}
	}
	_record_process_sample(started_us);
}

// Properties.

bool FootPlacementModifier3D::_set(const StringName &p_path, const Variant &p_value) {
	String path = p_path;
	if (path.begins_with("legs/")) {
		int which = path.get_slicec('/', 1).to_int();
		String what = path.get_slicec('/', 2);
		ERR_FAIL_INDEX_V(which, (int)legs.size(), false);
		if (what == "thigh_bone") {
			legs[which].thigh_bone = p_value;
		} else if (what == "calf_bone") {
			legs[which].calf_bone = p_value;
		} else if (what == "foot_bone") {
			legs[which].foot_bone = p_value;
		} else if (what == "foot_height_offset") {
			legs[which].foot_height_offset = p_value;
		} else {
			return false;
		}
		return true;
	}
	return false;
}

bool FootPlacementModifier3D::_get(const StringName &p_path, Variant &r_ret) const {
	String path = p_path;
	if (path.begins_with("legs/")) {
		int which = path.get_slicec('/', 1).to_int();
		String what = path.get_slicec('/', 2);
		ERR_FAIL_INDEX_V(which, (int)legs.size(), false);
		if (what == "thigh_bone") {
			r_ret = legs[which].thigh_bone;
		} else if (what == "calf_bone") {
			r_ret = legs[which].calf_bone;
		} else if (what == "foot_bone") {
			r_ret = legs[which].foot_bone;
		} else if (what == "foot_height_offset") {
			r_ret = legs[which].foot_height_offset;
		} else {
			return false;
		}
		return true;
	}
	return false;
}

void FootPlacementModifier3D::_get_property_list(List<PropertyInfo> *p_list) const {
	String enum_hint;
	Skeleton3D *skeleton = get_skeleton();
	if (skeleton) {
		enum_hint = skeleton->get_concatenated_bone_names();
	}
	for (uint32_t i = 0; i < legs.size(); i++) {
		String prefix = vformat("%s/%d/", "legs", i);
		p_list->push_back(PropertyInfo(Variant::STRING, prefix + "thigh_bone", PROPERTY_HINT_ENUM_SUGGESTION, enum_hint));
		p_list->push_back(PropertyInfo(Variant::STRING, prefix + "calf_bone", PROPERTY_HINT_ENUM_SUGGESTION, enum_hint));
		p_list->push_back(PropertyInfo(Variant::STRING, prefix + "foot_bone", PROPERTY_HINT_ENUM_SUGGESTION, enum_hint));
		p_list->push_back(PropertyInfo(Variant::FLOAT, prefix + "foot_height_offset", PROPERTY_HINT_RANGE, "-1,1,0.001,or_less,or_greater,suffix:m"));
	}
}

void FootPlacementModifier3D::_bind_methods() {
	ClassDB::bind_static_method("FootPlacementModifier3D", D_METHOD("solve_two_bone_angles", "upper_len", "lower_len", "target_dist"), &FootPlacementModifier3D::solve_two_bone_angles);
	ClassDB::bind_static_method("FootPlacementModifier3D", D_METHOD("pelvis_offset", "leg_offsets", "max_offset"), &FootPlacementModifier3D::pelvis_offset);

	ClassDB::bind_method(D_METHOD("set_pelvis_bone", "bone_name"), &FootPlacementModifier3D::set_pelvis_bone);
	ClassDB::bind_method(D_METHOD("get_pelvis_bone"), &FootPlacementModifier3D::get_pelvis_bone);

	ClassDB::bind_method(D_METHOD("set_leg_count", "count"), &FootPlacementModifier3D::set_leg_count);
	ClassDB::bind_method(D_METHOD("get_leg_count"), &FootPlacementModifier3D::get_leg_count);
	ClassDB::bind_method(D_METHOD("add_leg", "thigh_bone", "calf_bone", "foot_bone", "foot_height_offset"), &FootPlacementModifier3D::add_leg, DEFVAL(0.0f));
	ClassDB::bind_method(D_METHOD("clear_legs"), &FootPlacementModifier3D::clear_legs);

	ClassDB::bind_method(D_METHOD("set_ground_height_callback", "callback"), &FootPlacementModifier3D::set_ground_height_callback);
	ClassDB::bind_method(D_METHOD("get_ground_height_callback"), &FootPlacementModifier3D::get_ground_height_callback);
	ClassDB::bind_method(D_METHOD("set_use_raycast", "enabled"), &FootPlacementModifier3D::set_use_raycast);
	ClassDB::bind_method(D_METHOD("is_using_raycast"), &FootPlacementModifier3D::is_using_raycast);
	ClassDB::bind_method(D_METHOD("set_collision_mask", "mask"), &FootPlacementModifier3D::set_collision_mask);
	ClassDB::bind_method(D_METHOD("get_collision_mask"), &FootPlacementModifier3D::get_collision_mask);
	ClassDB::bind_method(D_METHOD("set_ray_length", "length"), &FootPlacementModifier3D::set_ray_length);
	ClassDB::bind_method(D_METHOD("get_ray_length"), &FootPlacementModifier3D::get_ray_length);
	ClassDB::bind_method(D_METHOD("set_ray_start_height", "height"), &FootPlacementModifier3D::set_ray_start_height);
	ClassDB::bind_method(D_METHOD("get_ray_start_height"), &FootPlacementModifier3D::get_ray_start_height);

	ClassDB::bind_method(D_METHOD("set_max_pelvis_offset", "offset"), &FootPlacementModifier3D::set_max_pelvis_offset);
	ClassDB::bind_method(D_METHOD("get_max_pelvis_offset"), &FootPlacementModifier3D::get_max_pelvis_offset);
	ClassDB::bind_method(D_METHOD("set_pelvis_interp_speed", "speed"), &FootPlacementModifier3D::set_pelvis_interp_speed);
	ClassDB::bind_method(D_METHOD("get_pelvis_interp_speed"), &FootPlacementModifier3D::get_pelvis_interp_speed);
	ClassDB::bind_method(D_METHOD("set_max_foot_angle", "angle"), &FootPlacementModifier3D::set_max_foot_angle);
	ClassDB::bind_method(D_METHOD("get_max_foot_angle"), &FootPlacementModifier3D::get_max_foot_angle);
	ClassDB::bind_method(D_METHOD("set_align_foot_to_ground", "enabled"), &FootPlacementModifier3D::set_align_foot_to_ground);
	ClassDB::bind_method(D_METHOD("is_aligning_foot_to_ground"), &FootPlacementModifier3D::is_aligning_foot_to_ground);
	ClassDB::bind_method(D_METHOD("set_normal_sample_distance", "distance"), &FootPlacementModifier3D::set_normal_sample_distance);
	ClassDB::bind_method(D_METHOD("get_normal_sample_distance"), &FootPlacementModifier3D::get_normal_sample_distance);

	ClassDB::bind_method(D_METHOD("get_current_pelvis_offset"), &FootPlacementModifier3D::get_current_pelvis_offset);
	ClassDB::bind_method(D_METHOD("reset"), &FootPlacementModifier3D::reset);
	ClassDB::bind_static_method("FootPlacementModifier3D", D_METHOD("smooth_process_cost_us", "previous_us", "sample_us"), &FootPlacementModifier3D::smooth_process_cost_us);
	ClassDB::bind_method(D_METHOD("set_profiling_enabled", "enabled"), &FootPlacementModifier3D::set_profiling_enabled);
	ClassDB::bind_method(D_METHOD("is_profiling_enabled"), &FootPlacementModifier3D::is_profiling_enabled);
	ClassDB::bind_method(D_METHOD("get_last_process_cost_us"), &FootPlacementModifier3D::get_last_process_cost_us);
	ClassDB::bind_method(D_METHOD("get_estimated_process_cost_us"), &FootPlacementModifier3D::get_estimated_process_cost_us);
	ClassDB::bind_method(D_METHOD("get_process_sample_count"), &FootPlacementModifier3D::get_process_sample_count);
	ClassDB::bind_method(D_METHOD("reset_process_telemetry"), &FootPlacementModifier3D::reset_process_telemetry);

	ADD_PROPERTY(PropertyInfo(Variant::STRING, "pelvis_bone"), "set_pelvis_bone", "get_pelvis_bone");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "profiling_enabled"), "set_profiling_enabled", "is_profiling_enabled");
	ADD_PROPERTY(PropertyInfo(Variant::CALLABLE, "ground_height_callback"), "set_ground_height_callback", "get_ground_height_callback");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "use_raycast"), "set_use_raycast", "is_using_raycast");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "collision_mask", PROPERTY_HINT_LAYERS_3D_PHYSICS), "set_collision_mask", "get_collision_mask");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "ray_length", PROPERTY_HINT_RANGE, "0.1,10,0.01,or_greater,suffix:m"), "set_ray_length", "get_ray_length");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "ray_start_height", PROPERTY_HINT_RANGE, "0,5,0.01,or_greater,suffix:m"), "set_ray_start_height", "get_ray_start_height");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_pelvis_offset", PROPERTY_HINT_RANGE, "0,2,0.001,or_greater,suffix:m"), "set_max_pelvis_offset", "get_max_pelvis_offset");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "pelvis_interp_speed", PROPERTY_HINT_RANGE, "0,60,0.1,or_greater"), "set_pelvis_interp_speed", "get_pelvis_interp_speed");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_foot_angle", PROPERTY_HINT_RANGE, "0,90,0.1,radians_as_degrees"), "set_max_foot_angle", "get_max_foot_angle");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "align_foot_to_ground"), "set_align_foot_to_ground", "is_aligning_foot_to_ground");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "normal_sample_distance", PROPERTY_HINT_RANGE, "0.01,1,0.01,or_greater,suffix:m"), "set_normal_sample_distance", "get_normal_sample_distance");
	ADD_ARRAY_COUNT("Legs", "leg_count", "set_leg_count", "get_leg_count", "legs/");
}

void FootPlacementModifier3D::set_pelvis_bone(const String &p_name) {
	pelvis_bone = p_name;
}

String FootPlacementModifier3D::get_pelvis_bone() const {
	return pelvis_bone;
}

void FootPlacementModifier3D::set_leg_count(int p_count) {
	ERR_FAIL_COND(p_count < 0);
	legs.resize(p_count);
	notify_property_list_changed();
}

int FootPlacementModifier3D::get_leg_count() const {
	return legs.size();
}

int FootPlacementModifier3D::add_leg(const String &p_thigh_bone, const String &p_calf_bone, const String &p_foot_bone, float p_foot_height_offset) {
	Leg leg;
	leg.thigh_bone = p_thigh_bone;
	leg.calf_bone = p_calf_bone;
	leg.foot_bone = p_foot_bone;
	leg.foot_height_offset = p_foot_height_offset;
	legs.push_back(leg);
	notify_property_list_changed();
	return legs.size() - 1;
}

void FootPlacementModifier3D::clear_legs() {
	legs.clear();
	notify_property_list_changed();
}

void FootPlacementModifier3D::set_ground_height_callback(const Callable &p_callback) {
	ground_height_callback = p_callback;
}

Callable FootPlacementModifier3D::get_ground_height_callback() const {
	return ground_height_callback;
}

void FootPlacementModifier3D::set_use_raycast(bool p_enabled) {
	use_raycast = p_enabled;
}

bool FootPlacementModifier3D::is_using_raycast() const {
	return use_raycast;
}

void FootPlacementModifier3D::set_collision_mask(uint32_t p_mask) {
	collision_mask = p_mask;
}

uint32_t FootPlacementModifier3D::get_collision_mask() const {
	return collision_mask;
}

void FootPlacementModifier3D::set_ray_length(float p_length) {
	ray_length = p_length;
}

float FootPlacementModifier3D::get_ray_length() const {
	return ray_length;
}

void FootPlacementModifier3D::set_ray_start_height(float p_height) {
	ray_start_height = p_height;
}

float FootPlacementModifier3D::get_ray_start_height() const {
	return ray_start_height;
}

void FootPlacementModifier3D::set_max_pelvis_offset(float p_offset) {
	max_pelvis_offset = MAX(p_offset, 0.0f);
}

float FootPlacementModifier3D::get_max_pelvis_offset() const {
	return max_pelvis_offset;
}

void FootPlacementModifier3D::set_pelvis_interp_speed(float p_speed) {
	pelvis_interp_speed = MAX(p_speed, 0.0f);
}

float FootPlacementModifier3D::get_pelvis_interp_speed() const {
	return pelvis_interp_speed;
}

void FootPlacementModifier3D::set_max_foot_angle(float p_angle) {
	max_foot_angle = MAX(p_angle, 0.0f);
}

float FootPlacementModifier3D::get_max_foot_angle() const {
	return max_foot_angle;
}

void FootPlacementModifier3D::set_align_foot_to_ground(bool p_enabled) {
	align_foot_to_ground = p_enabled;
}

bool FootPlacementModifier3D::is_aligning_foot_to_ground() const {
	return align_foot_to_ground;
}

void FootPlacementModifier3D::set_normal_sample_distance(float p_distance) {
	normal_sample_distance = MAX(p_distance, 0.001f);
}

float FootPlacementModifier3D::get_normal_sample_distance() const {
	return normal_sample_distance;
}

float FootPlacementModifier3D::get_current_pelvis_offset() const {
	return pelvis_smoothed;
}
