/**************************************************************************/
/*  stride_warping_modifier_3d.cpp                                        */
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

#include "stride_warping_modifier_3d.h"

#include "core/object/class_db.h"
#include "scene/3d/foot_placement_modifier_3d.h"
#include "scene/3d/skeleton_3d.h"

float StrideWarpingModifier3D::compute_stride_scale(float p_actual_speed, float p_animation_speed, float p_min_scale, float p_max_scale) {
	if (Math::abs(p_animation_speed) <= (float)CMP_EPSILON) {
		return 1.0f;
	}
	float lo = MIN(p_min_scale, p_max_scale);
	float hi = MAX(p_min_scale, p_max_scale);
	return CLAMP(p_actual_speed / p_animation_speed, lo, hi);
}

Vector3 StrideWarpingModifier3D::warp_foot_position(const Vector3 &p_foot, const Vector3 &p_pelvis, float p_scale) {
	return Vector3(
			p_pelvis.x + (p_foot.x - p_pelvis.x) * p_scale,
			p_foot.y,
			p_pelvis.z + (p_foot.z - p_pelvis.z) * p_scale);
}

void StrideWarpingModifier3D::_process_modification(double p_delta) {
	Skeleton3D *skeleton = get_skeleton();
	if (!skeleton || legs.is_empty() || influence <= 0.0) {
		return;
	}
	int pelvis = pelvis_bone.is_empty() ? -1 : skeleton->find_bone(pelvis_bone);
	if (pelvis < 0) {
		return;
	}
	float scale = Math::lerp(1.0f, CLAMP(stride_scale, MIN(min_stride_scale, max_stride_scale), MAX(min_stride_scale, max_stride_scale)), (float)influence);
	if (Math::is_equal_approx(scale, 1.0f)) {
		return;
	}

	// Skeleton space; the skeleton Y axis is assumed to be up.
	Vector3 pelvis_pos = skeleton->get_bone_global_pose(pelvis).origin;

	// Read all targets first, so the solve order does not matter.
	LocalVector<Vector3> targets;
	targets.resize(legs.size());
	for (uint32_t i = 0; i < legs.size(); i++) {
		int foot = skeleton->find_bone(legs[i].foot_bone);
		if (foot < 0) {
			targets[i] = Vector3(NAN, NAN, NAN);
			continue;
		}
		targets[i] = warp_foot_position(skeleton->get_bone_global_pose(foot).origin, pelvis_pos, scale);
	}
	for (uint32_t i = 0; i < legs.size(); i++) {
		if (Math::is_nan(targets[i].x)) {
			continue;
		}
		int thigh = skeleton->find_bone(legs[i].thigh_bone);
		int calf = skeleton->find_bone(legs[i].calf_bone);
		int foot = skeleton->find_bone(legs[i].foot_bone);
		FootPlacementModifier3D::solve_leg(skeleton, thigh, calf, foot, targets[i]);
	}
}

bool StrideWarpingModifier3D::_set(const StringName &p_path, const Variant &p_value) {
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
		} else {
			return false;
		}
		return true;
	}
	return false;
}

bool StrideWarpingModifier3D::_get(const StringName &p_path, Variant &r_ret) const {
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
		} else {
			return false;
		}
		return true;
	}
	return false;
}

void StrideWarpingModifier3D::_get_property_list(List<PropertyInfo> *p_list) const {
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
	}
}

void StrideWarpingModifier3D::_bind_methods() {
	ClassDB::bind_static_method("StrideWarpingModifier3D", D_METHOD("compute_stride_scale", "actual_speed", "animation_speed", "min_scale", "max_scale"), &StrideWarpingModifier3D::compute_stride_scale);
	ClassDB::bind_static_method("StrideWarpingModifier3D", D_METHOD("warp_foot_position", "foot", "pelvis", "scale"), &StrideWarpingModifier3D::warp_foot_position);

	ClassDB::bind_method(D_METHOD("set_pelvis_bone", "bone_name"), &StrideWarpingModifier3D::set_pelvis_bone);
	ClassDB::bind_method(D_METHOD("get_pelvis_bone"), &StrideWarpingModifier3D::get_pelvis_bone);

	ClassDB::bind_method(D_METHOD("set_leg_count", "count"), &StrideWarpingModifier3D::set_leg_count);
	ClassDB::bind_method(D_METHOD("get_leg_count"), &StrideWarpingModifier3D::get_leg_count);
	ClassDB::bind_method(D_METHOD("add_leg", "thigh_bone", "calf_bone", "foot_bone"), &StrideWarpingModifier3D::add_leg);
	ClassDB::bind_method(D_METHOD("clear_legs"), &StrideWarpingModifier3D::clear_legs);

	ClassDB::bind_method(D_METHOD("set_stride_scale", "scale"), &StrideWarpingModifier3D::set_stride_scale);
	ClassDB::bind_method(D_METHOD("get_stride_scale"), &StrideWarpingModifier3D::get_stride_scale);
	ClassDB::bind_method(D_METHOD("set_min_stride_scale", "scale"), &StrideWarpingModifier3D::set_min_stride_scale);
	ClassDB::bind_method(D_METHOD("get_min_stride_scale"), &StrideWarpingModifier3D::get_min_stride_scale);
	ClassDB::bind_method(D_METHOD("set_max_stride_scale", "scale"), &StrideWarpingModifier3D::set_max_stride_scale);
	ClassDB::bind_method(D_METHOD("get_max_stride_scale"), &StrideWarpingModifier3D::get_max_stride_scale);
	ClassDB::bind_method(D_METHOD("set_speeds", "actual_speed", "animation_speed"), &StrideWarpingModifier3D::set_speeds);

	ADD_PROPERTY(PropertyInfo(Variant::STRING, "pelvis_bone"), "set_pelvis_bone", "get_pelvis_bone");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "stride_scale", PROPERTY_HINT_RANGE, "0,4,0.01,or_greater"), "set_stride_scale", "get_stride_scale");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "min_stride_scale", PROPERTY_HINT_RANGE, "0,4,0.01,or_greater"), "set_min_stride_scale", "get_min_stride_scale");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_stride_scale", PROPERTY_HINT_RANGE, "0,4,0.01,or_greater"), "set_max_stride_scale", "get_max_stride_scale");
	ADD_ARRAY_COUNT("Legs", "leg_count", "set_leg_count", "get_leg_count", "legs/");
}

void StrideWarpingModifier3D::set_pelvis_bone(const String &p_name) {
	pelvis_bone = p_name;
}

String StrideWarpingModifier3D::get_pelvis_bone() const {
	return pelvis_bone;
}

void StrideWarpingModifier3D::set_leg_count(int p_count) {
	ERR_FAIL_COND(p_count < 0);
	legs.resize(p_count);
	notify_property_list_changed();
}

int StrideWarpingModifier3D::get_leg_count() const {
	return legs.size();
}

int StrideWarpingModifier3D::add_leg(const String &p_thigh_bone, const String &p_calf_bone, const String &p_foot_bone) {
	Leg leg;
	leg.thigh_bone = p_thigh_bone;
	leg.calf_bone = p_calf_bone;
	leg.foot_bone = p_foot_bone;
	legs.push_back(leg);
	notify_property_list_changed();
	return legs.size() - 1;
}

void StrideWarpingModifier3D::clear_legs() {
	legs.clear();
	notify_property_list_changed();
}

void StrideWarpingModifier3D::set_stride_scale(float p_scale) {
	stride_scale = MAX(p_scale, 0.0f);
}

float StrideWarpingModifier3D::get_stride_scale() const {
	return stride_scale;
}

void StrideWarpingModifier3D::set_min_stride_scale(float p_scale) {
	min_stride_scale = MAX(p_scale, 0.0f);
}

float StrideWarpingModifier3D::get_min_stride_scale() const {
	return min_stride_scale;
}

void StrideWarpingModifier3D::set_max_stride_scale(float p_scale) {
	max_stride_scale = MAX(p_scale, 0.0f);
}

float StrideWarpingModifier3D::get_max_stride_scale() const {
	return max_stride_scale;
}

void StrideWarpingModifier3D::set_speeds(float p_actual_speed, float p_animation_speed) {
	stride_scale = compute_stride_scale(p_actual_speed, p_animation_speed, min_stride_scale, max_stride_scale);
}
