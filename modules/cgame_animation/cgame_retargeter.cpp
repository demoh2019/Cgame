/**************************************************************************/
/*  cgame_retargeter.cpp                                                  */
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

#include "cgame_retargeter.h"

#include "cgame_rig_solvers.h"

#include "core/object/class_db.h"
#include "scene/3d/skeleton_3d.h"

namespace {

struct BaseAlias {
	const char *alias;
	const char *base;
};

const BaseAlias BASE_ALIASES[] = {
	{ "hips", "hips" }, { "pelvis", "hips" }, { "hip", "hips" },
	{ "spine", "spine" }, { "spine01", "spine" }, { "abdomen", "spine" },
	{ "spine1", "spine1" }, { "spine02", "spine1" }, { "torso", "spine1" },
	{ "spine2", "spine2" }, { "spine03", "spine2" }, { "chest", "spine2" },
	{ "neck", "neck" }, { "neck01", "neck" }, { "neck1", "neck" },
	{ "head", "head" },
	{ "shoulder", "shoulder" }, { "clavicle", "shoulder" },
	{ "upperarm", "upperarm" }, { "arm", "upperarm" },
	{ "forearm", "lowerarm" }, { "lowerarm", "lowerarm" },
	{ "hand", "hand" }, { "fist", "hand" },
	{ "upleg", "upperleg" }, { "thigh", "upperleg" }, { "upperleg", "upperleg" },
	{ "leg", "lowerleg" }, { "calf", "lowerleg" }, { "lowerleg", "lowerleg" }, { "shin", "lowerleg" },
	{ "foot", "foot" },
	{ "toebase", "toe" }, { "toe", "toe" }, { "toes", "toe" }, { "ball", "toe" },
};

const char *PREFIXES[] = { "mixamorig", "bip001", "bip01", "def", "j_bip" };

String trim_leading_underscore(const String &p_s) {
	return p_s.begins_with("_") ? p_s.substr(1) : p_s;
}

} // namespace

String CgameRetargeter::canonical(const String &p_bone_name, const Dictionary &p_aliases) {
	if (p_aliases.has(p_bone_name)) {
		return p_aliases[p_bone_name];
	}
	String s = p_bone_name;
	for (const char *sep : { ":", "|" }) {
		const int k = s.rfind(sep);
		if (k >= 0) {
			s = s.substr(k + 1);
		}
	}
	s = s.to_lower().replace(".", "_").replace(" ", "_").replace("-", "_");
	for (const char *prefix : PREFIXES) {
		if (s.begins_with(prefix)) {
			s = trim_leading_underscore(s.substr(String(prefix).length()));
			break;
		}
	}
	String side;
	if (s.begins_with("left")) {
		side = "l";
		s = trim_leading_underscore(s.substr(4));
	} else if (s.begins_with("right")) {
		side = "r";
		s = trim_leading_underscore(s.substr(5));
	} else if (s.begins_with("l_")) {
		side = "l";
		s = s.substr(2);
	} else if (s.begins_with("r_")) {
		side = "r";
		s = s.substr(2);
	} else {
		for (const char *suffix : { "_left", "_right", "_l", "_r" }) {
			if (s.ends_with(suffix)) {
				const String sfx = suffix;
				side = (sfx == "_left" || sfx == "_l") ? "l" : "r";
				s = s.substr(0, s.length() - sfx.length());
				break;
			}
		}
	}
	s = s.replace("_", "");
	const String suffix_side = side.is_empty() ? String() : "|" + side;
	if (p_aliases.has(s)) {
		return String(p_aliases[s]) + suffix_side;
	}
	for (const BaseAlias &a : BASE_ALIASES) {
		if (s == a.alias) {
			return String(a.base) + suffix_side;
		}
	}
	return "";
}

Dictionary CgameRetargeter::build_map(const PackedStringArray &p_source_names, const PackedStringArray &p_target_names, const Dictionary &p_aliases) {
	HashMap<String, int> target_by_key;
	HashMap<String, int> target_by_raw;
	for (int j = 0; j < p_target_names.size(); j++) {
		target_by_raw[p_target_names[j]] = j;
		const String key = canonical(p_target_names[j], p_aliases);
		if (!key.is_empty() && !target_by_key.has(key)) {
			target_by_key[key] = j;
		}
	}
	Dictionary map;
	HashSet<int> used;
	for (int i = 0; i < p_source_names.size(); i++) {
		const String key = canonical(p_source_names[i], p_aliases);
		int j = -1;
		if (!key.is_empty() && target_by_key.has(key)) {
			j = target_by_key[key];
		} else if (target_by_raw.has(p_source_names[i])) {
			j = target_by_raw[p_source_names[i]];
		}
		if (j >= 0 && !used.has(j)) {
			map[i] = j;
			used.insert(j);
		}
	}
	return map;
}

int CgameRetargeter::find_bone(const PackedStringArray &p_names, const String &p_key, const Dictionary &p_aliases) {
	for (int i = 0; i < p_names.size(); i++) {
		if (canonical(p_names[i], p_aliases) == p_key) {
			return i;
		}
	}
	return -1;
}

Quaternion CgameRetargeter::_local_rest(const Dictionary &p_rig, int p_index) {
	const Array rr = p_rig.get("rest_rot", Array());
	if (p_index >= 0 && p_index < rr.size()) {
		return rr[p_index];
	}
	return Quaternion();
}

Quaternion CgameRetargeter::_local_pose_from(const Dictionary &p_rig, int p_index, const Quaternion &p_parent_global, const Quaternion &p_new_global) {
	return _local_rest(p_rig, p_index).inverse() * p_parent_global.inverse() * p_new_global;
}

float CgameRetargeter::_leg_length(const PackedVector3Array &p_rest, int p_hips, int p_foot) {
	if (p_hips < 0 || p_foot < 0) {
		return 0.0f;
	}
	return p_rest[p_hips].distance_to(p_rest[p_foot]);
}

Dictionary CgameRetargeter::fk(const Dictionary &p_rig, const Array &p_rotations, int p_hips_bone, const Vector3 &p_hips) {
	const PackedInt32Array parents = p_rig["parents"];
	const PackedVector3Array rest = p_rig["rest"];
	const int n = parents.size();
	PackedVector3Array pos;
	pos.resize(n);
	Vector<Quaternion> glob;
	glob.resize(n);
	Vector<Quaternion> rest_glob;
	rest_glob.resize(n);
	for (int i = 0; i < n; i++) {
		const int p = parents[i];
		const Quaternion lr = _local_rest(p_rig, i);
		Quaternion pose_q;
		if (i < p_rotations.size()) {
			pose_q = p_rotations[i];
		}
		if (p < 0) {
			rest_glob.write[i] = lr;
			glob.write[i] = lr * pose_q;
			pos.write[i] = rest[i];
		} else {
			const Quaternion rgp = rest_glob[p];
			const Quaternion gp = glob[p];
			rest_glob.write[i] = rgp * lr;
			glob.write[i] = gp * lr * pose_q;
			pos.write[i] = pos[p] + gp.xform(rgp.inverse().xform(rest[i] - rest[p]));
		}
		if (i == p_hips_bone) {
			pos.write[i] = p_hips;
		}
	}
	Array rot_out;
	for (int i = 0; i < n; i++) {
		rot_out.push_back(glob[i]);
	}
	Dictionary out;
	out["pos"] = pos;
	out["rot"] = rot_out;
	return out;
}

Dictionary CgameRetargeter::retarget_pose(const Dictionary &p_source_rest, const Dictionary &p_source_pose, const Dictionary &p_target_rest, const Dictionary &p_map) {
	const PackedStringArray s_names = p_source_rest["names"];
	const PackedStringArray t_names = p_target_rest["names"];
	const PackedVector3Array s_rest = p_source_rest["rest"];
	const PackedVector3Array t_rest = p_target_rest["rest"];
	const Array src_rot = p_source_pose["rot"];
	Array rots;
	for (int j = 0; j < t_names.size(); j++) {
		rots.push_back(Quaternion());
	}
	for (const KeyValue<Variant, Variant> &kv : p_map) {
		const int si = kv.key;
		const int ti = kv.value;
		if (si >= 0 && si < src_rot.size() && ti >= 0 && ti < rots.size()) {
			rots[ti] = src_rot[si];
		}
	}
	const int s_hips = find_bone(s_names, "hips");
	const int t_hips = find_bone(t_names, "hips");
	float ratio = 1.0f;
	const float s_leg = _leg_length(s_rest, s_hips, find_bone(s_names, "foot|l"));
	const float t_leg = _leg_length(t_rest, t_hips, find_bone(t_names, "foot|l"));
	if (s_leg > 0.0001f && t_leg > 0.0001f) {
		ratio = t_leg / s_leg;
	}
	Vector3 hips;
	if (t_hips >= 0) {
		hips = t_rest[t_hips];
	}
	if (s_hips >= 0 && t_hips >= 0) {
		const Vector3 sh = p_source_pose.get("hips", s_rest[s_hips]);
		hips = t_rest[t_hips] + (sh - s_rest[s_hips]) * ratio;
	}
	Dictionary out;
	out["rot"] = rots;
	out["hips"] = hips;
	out["ratio"] = ratio;
	return out;
}

Dictionary CgameRetargeter::ik_correct_feet(const Dictionary &p_target_rig, const Dictionary &p_pose, const Dictionary &p_foot_targets) {
	const PackedInt32Array parents = p_target_rig["parents"];
	const PackedStringArray names = p_target_rig["names"];
	Array rots = Array(p_pose["rot"]).duplicate();
	const Vector3 hips = p_pose["hips"];
	const int hips_bone = find_bone(names, "hips");
	Dictionary state = fk(p_target_rig, rots, hips_bone, hips);
	for (const KeyValue<Variant, Variant> &kv : p_foot_targets) {
		const int foot = kv.key;
		const Vector3 goal = kv.value;
		if (foot < 0 || foot >= parents.size()) {
			continue;
		}
		const int lower = parents[foot];
		if (lower < 0) {
			continue;
		}
		const int upper = parents[lower];
		if (upper < 0) {
			continue;
		}
		const PackedVector3Array pos = state["pos"];
		const Array glob = state["rot"];
		const CgameRigSolvers::TwoBoneResult res = CgameRigSolvers::two_bone(pos[upper], pos[lower], pos[foot], goal, pos[lower]);
		const Quaternion gu = glob[upper];
		const Quaternion gl = glob[lower];
		const Quaternion gf = glob[foot];
		const Quaternion du = CgameRigSolvers::aim_rotation(Vector3(), pos[lower] - pos[upper], res.mid - pos[upper]);
		const Quaternion new_gu = du * gu;
		const Quaternion dl = CgameRigSolvers::aim_rotation(Vector3(), du.xform(pos[foot] - pos[lower]), res.tip - res.mid);
		const Quaternion new_gl = dl * du * gl;
		Quaternion upper_parent;
		if (parents[upper] >= 0) {
			upper_parent = glob[parents[upper]];
		}
		rots[upper] = _local_pose_from(p_target_rig, upper, upper_parent, new_gu);
		rots[lower] = _local_pose_from(p_target_rig, lower, new_gu, new_gl);
		rots[foot] = _local_pose_from(p_target_rig, foot, new_gl, gf);
		state = fk(p_target_rig, rots, hips_bone, hips);
	}
	real_t worst = 0.0;
	const PackedVector3Array final_pos = state["pos"];
	for (const KeyValue<Variant, Variant> &kv : p_foot_targets) {
		const int f2 = kv.key;
		if (f2 >= 0 && f2 < final_pos.size()) {
			worst = MAX(worst, final_pos[f2].distance_to(kv.value));
		}
	}
	Dictionary out;
	out["rot"] = rots;
	out["hips"] = hips;
	out["pos"] = state["pos"];
	out["error"] = worst;
	return out;
}

Dictionary CgameRetargeter::rig_from_skeleton(const Skeleton3D *p_skeleton) {
	ERR_FAIL_NULL_V(p_skeleton, Dictionary());
	const int n = p_skeleton->get_bone_count();
	PackedStringArray names;
	PackedInt32Array parents;
	PackedVector3Array rest;
	Array rest_rot;
	for (int i = 0; i < n; i++) {
		names.push_back(p_skeleton->get_bone_name(i));
		parents.push_back(p_skeleton->get_bone_parent(i));
		rest.push_back(p_skeleton->get_bone_global_rest(i).origin);
		rest_rot.push_back(p_skeleton->get_bone_rest(i).basis.orthonormalized().get_rotation_quaternion());
	}
	Dictionary d;
	d["names"] = names;
	d["parents"] = parents;
	d["rest"] = rest;
	d["rest_rot"] = rest_rot;
	return d;
}

Dictionary CgameRetargeter::build_skeleton_map(const Skeleton3D *p_source, const Skeleton3D *p_target, const Dictionary &p_aliases) {
	ERR_FAIL_NULL_V(p_source, Dictionary());
	ERR_FAIL_NULL_V(p_target, Dictionary());
	PackedStringArray s_names;
	for (int i = 0; i < p_source->get_bone_count(); i++) {
		s_names.push_back(p_source->get_bone_name(i));
	}
	PackedStringArray t_names;
	for (int i = 0; i < p_target->get_bone_count(); i++) {
		t_names.push_back(p_target->get_bone_name(i));
	}
	return build_map(s_names, t_names, p_aliases);
}

int CgameRetargeter::transfer_pose(const Skeleton3D *p_source, Skeleton3D *p_target, const Dictionary &p_map, bool p_scale_hips) {
	ERR_FAIL_NULL_V(p_source, 0);
	ERR_FAIL_NULL_V(p_target, 0);
	int transferred = 0;
	int src_hips = -1;
	int dst_hips = -1;
	for (const KeyValue<Variant, Variant> &kv : p_map) {
		const int si = kv.key;
		const int ti = kv.value;
		if (si < 0 || si >= p_source->get_bone_count() || ti < 0 || ti >= p_target->get_bone_count()) {
			continue;
		}
		// Express the source pose as a rotation relative to its own rest, then re-apply on the target rest.
		const Quaternion src_rest = p_source->get_bone_rest(si).basis.orthonormalized().get_rotation_quaternion();
		const Quaternion delta = src_rest.inverse() * p_source->get_bone_pose_rotation(si);
		const Quaternion dst_rest = p_target->get_bone_rest(ti).basis.orthonormalized().get_rotation_quaternion();
		p_target->set_bone_pose_rotation(ti, (dst_rest * delta).normalized());
		transferred++;
		const String key = canonical(p_source->get_bone_name(si));
		if (key == "hips") {
			src_hips = si;
			dst_hips = ti;
		}
	}
	if (p_scale_hips && src_hips >= 0 && dst_hips >= 0) {
		float ratio = 1.0f;
		int s_foot_bone = -1;
		int t_foot_bone = -1;
		for (int i = 0; i < p_source->get_bone_count() && s_foot_bone < 0; i++) {
			if (canonical(p_source->get_bone_name(i)) == "foot|l") {
				s_foot_bone = i;
			}
		}
		for (int i = 0; i < p_target->get_bone_count() && t_foot_bone < 0; i++) {
			if (canonical(p_target->get_bone_name(i)) == "foot|l") {
				t_foot_bone = i;
			}
		}
		if (s_foot_bone >= 0 && t_foot_bone >= 0) {
			const float s_leg = p_source->get_bone_global_rest(src_hips).origin.distance_to(p_source->get_bone_global_rest(s_foot_bone).origin);
			const float t_leg = p_target->get_bone_global_rest(dst_hips).origin.distance_to(p_target->get_bone_global_rest(t_foot_bone).origin);
			if (s_leg > 0.0001f && t_leg > 0.0001f) {
				ratio = t_leg / s_leg;
			}
		}
		const Vector3 d = p_source->get_bone_pose_position(src_hips) - p_source->get_bone_rest(src_hips).origin;
		p_target->set_bone_pose_position(dst_hips, p_target->get_bone_rest(dst_hips).origin + d * ratio);
	}
	return transferred;
}

void CgameRetargeter::_bind_methods() {
	const StringName c = "CgameRetargeter";
	ClassDB::bind_static_method(c, D_METHOD("canonical", "bone_name", "aliases"), &CgameRetargeter::canonical, DEFVAL(Dictionary()));
	ClassDB::bind_static_method(c, D_METHOD("build_map", "source_names", "target_names", "aliases"), &CgameRetargeter::build_map, DEFVAL(Dictionary()));
	ClassDB::bind_static_method(c, D_METHOD("find_bone", "names", "key", "aliases"), &CgameRetargeter::find_bone, DEFVAL(Dictionary()));
	ClassDB::bind_static_method(c, D_METHOD("fk", "rig", "rotations", "hips_bone", "hips"), &CgameRetargeter::fk);
	ClassDB::bind_static_method(c, D_METHOD("retarget_pose", "source_rest", "source_pose", "target_rest", "map"), &CgameRetargeter::retarget_pose);
	ClassDB::bind_static_method(c, D_METHOD("ik_correct_feet", "target_rig", "pose", "foot_targets"), &CgameRetargeter::ik_correct_feet);
	ClassDB::bind_static_method(c, D_METHOD("rig_from_skeleton", "skeleton"), &CgameRetargeter::rig_from_skeleton);
	ClassDB::bind_static_method(c, D_METHOD("build_skeleton_map", "source", "target", "aliases"), &CgameRetargeter::build_skeleton_map, DEFVAL(Dictionary()));
	ClassDB::bind_static_method(c, D_METHOD("transfer_pose", "source", "target", "map", "scale_hips"), &CgameRetargeter::transfer_pose, DEFVAL(true));
}
