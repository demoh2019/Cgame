/**************************************************************************/
/*  cgame_aim_modifier_3d.cpp                                             */
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

#include "cgame_aim_modifier_3d.h"

#include "cgame_modifier_util.h"
#include "cgame_rig_solvers.h"

#include "core/object/class_db.h"

void CgameAimModifier3D::_process_modification(double p_delta) {
	Skeleton3D *skeleton = get_skeleton();
	if (!skeleton || influence <= 0.0) {
		return;
	}
	const int bone = skeleton->find_bone(bone_name);
	if (bone < 0) {
		return;
	}
	Vector3 target = target_position; // Skeleton space.
	if (use_target_node && !CgameModifierUtil::target_in_skeleton_space(this, skeleton, target_node, target)) {
		return;
	}
	const Transform3D gp = skeleton->get_bone_global_pose(bone);
	const Quaternion gq = gp.basis.orthonormalized().get_rotation_quaternion();
	const Vector3 forward = gq.xform(get_vector_from_bone_axis(forward_axis));
	const Quaternion delta = CgameRigSolvers::aim_rotation(gp.origin, forward, target, Math::deg_to_rad(max_angle));
	const Quaternion local = get_local_pose_rotation(skeleton, bone, (delta * gq).normalized());
	const Quaternion current = skeleton->get_bone_pose_rotation(bone);
	skeleton->set_bone_pose_rotation(bone, current.slerp(local, CLAMP((real_t)influence, (real_t)0.0, (real_t)1.0)).normalized());
}

void CgameAimModifier3D::set_bone_name(const String &p_name) {
	bone_name = p_name;
}
String CgameAimModifier3D::get_bone_name() const {
	return bone_name;
}
void CgameAimModifier3D::set_forward_axis(BoneAxis p_axis) {
	forward_axis = p_axis;
}
SkeletonModifier3D::BoneAxis CgameAimModifier3D::get_forward_axis() const {
	return forward_axis;
}
void CgameAimModifier3D::set_target_node(const NodePath &p_path) {
	target_node = p_path;
}
NodePath CgameAimModifier3D::get_target_node() const {
	return target_node;
}
void CgameAimModifier3D::set_target_position(const Vector3 &p_position) {
	target_position = p_position;
}
Vector3 CgameAimModifier3D::get_target_position() const {
	return target_position;
}
void CgameAimModifier3D::set_use_target_node(bool p_enabled) {
	use_target_node = p_enabled;
}
bool CgameAimModifier3D::is_using_target_node() const {
	return use_target_node;
}
void CgameAimModifier3D::set_max_angle(float p_degrees) {
	max_angle = CLAMP(p_degrees, 0.0f, 180.0f);
}
float CgameAimModifier3D::get_max_angle() const {
	return max_angle;
}

void CgameAimModifier3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_bone_name", "name"), &CgameAimModifier3D::set_bone_name);
	ClassDB::bind_method(D_METHOD("get_bone_name"), &CgameAimModifier3D::get_bone_name);
	ClassDB::bind_method(D_METHOD("set_forward_axis", "axis"), &CgameAimModifier3D::set_forward_axis);
	ClassDB::bind_method(D_METHOD("get_forward_axis"), &CgameAimModifier3D::get_forward_axis);
	ClassDB::bind_method(D_METHOD("set_target_node", "path"), &CgameAimModifier3D::set_target_node);
	ClassDB::bind_method(D_METHOD("get_target_node"), &CgameAimModifier3D::get_target_node);
	ClassDB::bind_method(D_METHOD("set_target_position", "position"), &CgameAimModifier3D::set_target_position);
	ClassDB::bind_method(D_METHOD("get_target_position"), &CgameAimModifier3D::get_target_position);
	ClassDB::bind_method(D_METHOD("set_use_target_node", "enabled"), &CgameAimModifier3D::set_use_target_node);
	ClassDB::bind_method(D_METHOD("is_using_target_node"), &CgameAimModifier3D::is_using_target_node);
	ClassDB::bind_method(D_METHOD("set_max_angle", "degrees"), &CgameAimModifier3D::set_max_angle);
	ClassDB::bind_method(D_METHOD("get_max_angle"), &CgameAimModifier3D::get_max_angle);

	ADD_PROPERTY(PropertyInfo(Variant::STRING, "bone_name"), "set_bone_name", "get_bone_name");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "forward_axis", PROPERTY_HINT_ENUM, "+X,-X,+Y,-Y,+Z,-Z"), "set_forward_axis", "get_forward_axis");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "use_target_node"), "set_use_target_node", "is_using_target_node");
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "target_node", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "Node3D"), "set_target_node", "get_target_node");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "target_position", PROPERTY_HINT_NONE, "suffix:m"), "set_target_position", "get_target_position");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_angle", PROPERTY_HINT_RANGE, "0.0,180.0,0.1,degrees"), "set_max_angle", "get_max_angle");
}
