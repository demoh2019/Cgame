/**************************************************************************/
/*  foot_lock_modifier_3d.cpp                                             */
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

#include "foot_lock_modifier_3d.h"

#include "cgame_rig_solvers.h"

#include "core/object/class_db.h"

CgameFootLockState::Output CgameFootLockState::update(float p_delta, const Vector3 &p_anim_pos, float p_contact, float p_ground_y, const Params &p_params) {
	const bool planted = p_contact > p_params.plant_threshold;
	if (!planted) {
		locked = false;
		released = false;
	} else if (!locked && !released) {
		lock_pos = Vector3(p_anim_pos.x, p_ground_y, p_anim_pos.z);
		locked = true;
	} else if (locked && lock_pos.distance_to(p_anim_pos) > p_params.max_stretch) {
		locked = false;
		released = true;
	}
	if (locked) {
		weight = MIN(1.0f, weight + p_delta / MAX(p_params.blend_in, 0.0001f));
	} else {
		weight = MAX(0.0f, weight - p_delta / MAX(p_params.blend_out, 0.0001f));
	}
	Output out;
	out.target = weight > 0.0f ? lock_pos : p_anim_pos;
	out.weight = weight;
	out.locked = locked;
	return out;
}

void CgameFootLockState::reset() {
	locked = false;
	released = false;
	lock_pos = Vector3();
	weight = 0.0f;
}

float FootLockModifier3D::_ground_y(const Vector3 &p_world_pos) const {
	if (ground_height_callback.is_valid()) {
		const Variant x = p_world_pos.x;
		const Variant z = p_world_pos.z;
		const Variant *args[2] = { &x, &z };
		Variant ret;
		Callable::CallError ce;
		ground_height_callback.callp(args, 2, ret, ce);
		if (ce.error == Callable::CallError::CALL_OK && (ret.get_type() == Variant::FLOAT || ret.get_type() == Variant::INT)) {
			return ret;
		}
	}
	return ground_height;
}

void FootLockModifier3D::_apply_leg(Skeleton3D *p_skeleton, int p_foot, const Vector3 &p_target_skeleton, float p_weight) {
	const int lower = p_skeleton->get_bone_parent(p_foot);
	if (lower < 0) {
		return;
	}
	const int upper = p_skeleton->get_bone_parent(lower);
	if (upper < 0) {
		return;
	}
	const Vector3 root = p_skeleton->get_bone_global_pose(upper).origin;
	const Vector3 mid = p_skeleton->get_bone_global_pose(lower).origin;
	const Vector3 tip = p_skeleton->get_bone_global_pose(p_foot).origin;
	const CgameRigSolvers::TwoBoneResult res = CgameRigSolvers::two_bone(root, mid, tip, p_target_skeleton, mid);
	CgameRigSolvers::aim_bone_at(p_skeleton, upper, lower, res.mid, p_weight);
	CgameRigSolvers::aim_bone_at(p_skeleton, lower, p_foot, res.tip, p_weight);
}

void FootLockModifier3D::_process_modification(double p_delta) {
	Skeleton3D *skeleton = get_skeleton();
	if (!skeleton) {
		return;
	}
	const int left = skeleton->find_bone(left_foot_bone);
	const int right = skeleton->find_bone(right_foot_bone);
	if (left < 0 && right < 0) {
		return;
	}
	const Transform3D to_world = skeleton->get_global_transform();
	const Transform3D to_local = to_world.affine_inverse();

	struct FootJob {
		int bone = -1;
		CgameFootLockState *state = nullptr;
		float contact = 0.0f;
		Vector3 anim_world;
		CgameFootLockState::Output out;
	};
	FootJob jobs[2];
	jobs[0].bone = left;
	jobs[0].state = &left_state;
	jobs[0].contact = left_contact;
	jobs[1].bone = right;
	jobs[1].state = &right_state;
	jobs[1].contact = right_contact;

	for (FootJob &job : jobs) {
		if (job.bone < 0) {
			continue;
		}
		job.anim_world = to_world.xform(skeleton->get_bone_global_pose(job.bone).origin);
		job.out = job.state->update((float)p_delta, job.anim_world, job.contact, _ground_y(job.anim_world), params);
	}

	// Lower the pelvis by the larger negative correction so the lower foot can reach.
	if (pelvis_adjust && left >= 0 && right >= 0) {
		const int pelvis = skeleton->find_bone(pelvis_bone);
		if (pelvis >= 0) {
			const float lw = jobs[0].out.weight * (float)influence;
			const float rw = jobs[1].out.weight * (float)influence;
			const float left_corr = (jobs[0].out.target.y - jobs[0].anim_world.y) * lw;
			const float right_corr = (jobs[1].out.target.y - jobs[1].anim_world.y) * rw;
			const float offset = CLAMP(MIN(MIN(left_corr, right_corr), 0.0f), -0.25f, 0.0f);
			if (offset < -0.0001f) {
				const Vector3 delta_skel = to_local.basis.xform(Vector3(0, offset, 0));
				const int parent = skeleton->get_bone_parent(pelvis);
				Vector3 local_delta = delta_skel;
				if (parent >= 0) {
					local_delta = skeleton->get_bone_global_pose(parent).basis.inverse().xform(delta_skel);
				}
				skeleton->set_bone_pose_position(pelvis, skeleton->get_bone_pose_position(pelvis) + local_delta);
			}
		}
	}

	for (FootJob &job : jobs) {
		if (job.bone < 0) {
			continue;
		}
		const float w = job.out.weight * (float)influence;
		if (w <= 0.0001f) {
			continue;
		}
		_apply_leg(skeleton, job.bone, to_local.xform(job.out.target), w);
	}
}

void FootLockModifier3D::_set_active(bool p_active) {
	SkeletonModifier3D::_set_active(p_active);
	if (!p_active) {
		reset_locks();
	}
}

bool FootLockModifier3D::is_foot_locked(bool p_left) const {
	return (p_left ? left_state : right_state).locked;
}

float FootLockModifier3D::get_foot_weight(bool p_left) const {
	return (p_left ? left_state : right_state).weight;
}

void FootLockModifier3D::reset_locks() {
	left_state.reset();
	right_state.reset();
}

void FootLockModifier3D::set_left_foot_bone(const String &p_name) {
	left_foot_bone = p_name;
}
String FootLockModifier3D::get_left_foot_bone() const {
	return left_foot_bone;
}
void FootLockModifier3D::set_right_foot_bone(const String &p_name) {
	right_foot_bone = p_name;
}
String FootLockModifier3D::get_right_foot_bone() const {
	return right_foot_bone;
}
void FootLockModifier3D::set_pelvis_bone(const String &p_name) {
	pelvis_bone = p_name;
}
String FootLockModifier3D::get_pelvis_bone() const {
	return pelvis_bone;
}
void FootLockModifier3D::set_pelvis_adjust(bool p_enabled) {
	pelvis_adjust = p_enabled;
}
bool FootLockModifier3D::is_pelvis_adjust() const {
	return pelvis_adjust;
}
void FootLockModifier3D::set_left_contact(float p_contact) {
	left_contact = p_contact;
}
float FootLockModifier3D::get_left_contact() const {
	return left_contact;
}
void FootLockModifier3D::set_right_contact(float p_contact) {
	right_contact = p_contact;
}
float FootLockModifier3D::get_right_contact() const {
	return right_contact;
}
void FootLockModifier3D::set_ground_height(float p_height) {
	ground_height = p_height;
}
float FootLockModifier3D::get_ground_height() const {
	return ground_height;
}
void FootLockModifier3D::set_ground_height_callback(const Callable &p_callback) {
	ground_height_callback = p_callback;
}
Callable FootLockModifier3D::get_ground_height_callback() const {
	return ground_height_callback;
}
void FootLockModifier3D::set_max_stretch(float p_value) {
	params.max_stretch = MAX(p_value, 0.0f);
}
float FootLockModifier3D::get_max_stretch() const {
	return params.max_stretch;
}
void FootLockModifier3D::set_blend_in(float p_value) {
	params.blend_in = MAX(p_value, 0.0f);
}
float FootLockModifier3D::get_blend_in() const {
	return params.blend_in;
}
void FootLockModifier3D::set_blend_out(float p_value) {
	params.blend_out = MAX(p_value, 0.0f);
}
float FootLockModifier3D::get_blend_out() const {
	return params.blend_out;
}
void FootLockModifier3D::set_plant_threshold(float p_value) {
	params.plant_threshold = p_value;
}
float FootLockModifier3D::get_plant_threshold() const {
	return params.plant_threshold;
}

void FootLockModifier3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_left_foot_bone", "name"), &FootLockModifier3D::set_left_foot_bone);
	ClassDB::bind_method(D_METHOD("get_left_foot_bone"), &FootLockModifier3D::get_left_foot_bone);
	ClassDB::bind_method(D_METHOD("set_right_foot_bone", "name"), &FootLockModifier3D::set_right_foot_bone);
	ClassDB::bind_method(D_METHOD("get_right_foot_bone"), &FootLockModifier3D::get_right_foot_bone);
	ClassDB::bind_method(D_METHOD("set_pelvis_bone", "name"), &FootLockModifier3D::set_pelvis_bone);
	ClassDB::bind_method(D_METHOD("get_pelvis_bone"), &FootLockModifier3D::get_pelvis_bone);
	ClassDB::bind_method(D_METHOD("set_pelvis_adjust", "enabled"), &FootLockModifier3D::set_pelvis_adjust);
	ClassDB::bind_method(D_METHOD("is_pelvis_adjust"), &FootLockModifier3D::is_pelvis_adjust);
	ClassDB::bind_method(D_METHOD("set_left_contact", "contact"), &FootLockModifier3D::set_left_contact);
	ClassDB::bind_method(D_METHOD("get_left_contact"), &FootLockModifier3D::get_left_contact);
	ClassDB::bind_method(D_METHOD("set_right_contact", "contact"), &FootLockModifier3D::set_right_contact);
	ClassDB::bind_method(D_METHOD("get_right_contact"), &FootLockModifier3D::get_right_contact);
	ClassDB::bind_method(D_METHOD("set_ground_height", "height"), &FootLockModifier3D::set_ground_height);
	ClassDB::bind_method(D_METHOD("get_ground_height"), &FootLockModifier3D::get_ground_height);
	ClassDB::bind_method(D_METHOD("set_ground_height_callback", "callback"), &FootLockModifier3D::set_ground_height_callback);
	ClassDB::bind_method(D_METHOD("get_ground_height_callback"), &FootLockModifier3D::get_ground_height_callback);
	ClassDB::bind_method(D_METHOD("set_max_stretch", "max_stretch"), &FootLockModifier3D::set_max_stretch);
	ClassDB::bind_method(D_METHOD("get_max_stretch"), &FootLockModifier3D::get_max_stretch);
	ClassDB::bind_method(D_METHOD("set_blend_in", "blend_in"), &FootLockModifier3D::set_blend_in);
	ClassDB::bind_method(D_METHOD("get_blend_in"), &FootLockModifier3D::get_blend_in);
	ClassDB::bind_method(D_METHOD("set_blend_out", "blend_out"), &FootLockModifier3D::set_blend_out);
	ClassDB::bind_method(D_METHOD("get_blend_out"), &FootLockModifier3D::get_blend_out);
	ClassDB::bind_method(D_METHOD("set_plant_threshold", "threshold"), &FootLockModifier3D::set_plant_threshold);
	ClassDB::bind_method(D_METHOD("get_plant_threshold"), &FootLockModifier3D::get_plant_threshold);
	ClassDB::bind_method(D_METHOD("is_foot_locked", "left"), &FootLockModifier3D::is_foot_locked);
	ClassDB::bind_method(D_METHOD("get_foot_weight", "left"), &FootLockModifier3D::get_foot_weight);
	ClassDB::bind_method(D_METHOD("reset_locks"), &FootLockModifier3D::reset_locks);

	ADD_PROPERTY(PropertyInfo(Variant::STRING, "left_foot_bone"), "set_left_foot_bone", "get_left_foot_bone");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "right_foot_bone"), "set_right_foot_bone", "get_right_foot_bone");
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "pelvis_bone"), "set_pelvis_bone", "get_pelvis_bone");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "pelvis_adjust"), "set_pelvis_adjust", "is_pelvis_adjust");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "left_contact", PROPERTY_HINT_RANGE, "0.0,1.0,0.01"), "set_left_contact", "get_left_contact");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "right_contact", PROPERTY_HINT_RANGE, "0.0,1.0,0.01"), "set_right_contact", "get_right_contact");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "ground_height", PROPERTY_HINT_NONE, "suffix:m"), "set_ground_height", "get_ground_height");
	ADD_PROPERTY(PropertyInfo(Variant::CALLABLE, "ground_height_callback", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NONE), "set_ground_height_callback", "get_ground_height_callback");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_stretch", PROPERTY_HINT_RANGE, "0.0,2.0,0.01,or_greater,suffix:m"), "set_max_stretch", "get_max_stretch");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "blend_in", PROPERTY_HINT_RANGE, "0.0,2.0,0.01,or_greater,suffix:s"), "set_blend_in", "get_blend_in");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "blend_out", PROPERTY_HINT_RANGE, "0.0,2.0,0.01,or_greater,suffix:s"), "set_blend_out", "get_blend_out");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "plant_threshold", PROPERTY_HINT_RANGE, "0.0,1.0,0.01"), "set_plant_threshold", "get_plant_threshold");
}
