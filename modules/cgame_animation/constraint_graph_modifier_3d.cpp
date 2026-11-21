/**************************************************************************/
/*  constraint_graph_modifier_3d.cpp                                      */
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

#include "constraint_graph_modifier_3d.h"

#include "cgame_modifier_util.h"
#include "cgame_rig_solvers.h"

#include "core/io/json.h"
#include "core/object/class_db.h"

namespace {

Vector3 _vec(const Variant &p_value, const Vector<Vector3> &p_pos) {
	if (p_value.get_type() == Variant::VECTOR3) {
		return p_value;
	}
	if (p_value.get_type() == Variant::ARRAY) {
		const Array a = p_value;
		if (a.size() >= 3) {
			return Vector3(a[0], a[1], a[2]);
		}
	}
	if (p_value.get_type() == Variant::DICTIONARY) {
		const Dictionary d = p_value;
		if (d.has("bone")) {
			const int b = d["bone"];
			if (b >= 0 && b < p_pos.size()) {
				return p_pos[b];
			}
		}
	}
	return Vector3();
}

Quaternion _quat(const Variant &p_value) {
	if (p_value.get_type() == Variant::QUATERNION) {
		return p_value;
	}
	if (p_value.get_type() == Variant::ARRAY) {
		const Array a = p_value;
		if (a.size() >= 4) {
			return Quaternion(a[0], a[1], a[2], a[3]).normalized();
		}
	}
	return Quaternion();
}

bool _valid(int p_count, const Variant &p_a, const Variant &p_b = -1, const Variant &p_c = -1) {
	const Variant *vals[3] = { &p_a, &p_b, &p_c };
	for (const Variant *v : vals) {
		if (v->get_type() != Variant::INT) {
			return false;
		}
		const int i = *v;
		if (i < 0 || i >= p_count) {
			return false;
		}
	}
	return true;
}

bool _apply(Vector<Vector3> &r_pos, Vector<Quaternion> &r_rots, const Dictionary &p_c, const String &p_type) {
	const int n = r_pos.size();
	const real_t w = CLAMP((real_t)p_c.get("weight", 1.0), (real_t)0.0, (real_t)1.0);
	if (p_type == "two_bone") {
		if (!_valid(n, p_c.get("root", -1), p_c.get("mid", -1), p_c.get("tip", -1))) {
			return false;
		}
		const int r = p_c["root"];
		const int m = p_c["mid"];
		const int t = p_c["tip"];
		const Vector3 target = _vec(p_c.get("target", Variant()), r_pos);
		const Vector3 pole = _vec(p_c.get("pole", r_pos[m]), r_pos);
		const CgameRigSolvers::TwoBoneResult res = CgameRigSolvers::two_bone(r_pos[r], r_pos[m], r_pos[t], target, pole);
		r_pos.write[m] = r_pos[m].lerp(res.mid, w);
		r_pos.write[t] = r_pos[t].lerp(res.tip, w);
		return true;
	}
	if (p_type == "fabrik_chain") {
		const Array bones = p_c.get("bones", Array());
		if (bones.size() < 2) {
			return false;
		}
		Vector<Vector3> chain;
		for (int i = 0; i < bones.size(); i++) {
			if (!_valid(n, bones[i])) {
				return false;
			}
			chain.push_back(r_pos[(int)bones[i]]);
		}
		const Vector3 target = _vec(p_c.get("target", Variant()), r_pos);
		const Vector<Vector3> solved = CgameRigSolvers::fabrik_chain(chain, target, p_c.get("iterations", 16));
		for (int k = 0; k < bones.size(); k++) {
			const int bi = bones[k];
			r_pos.write[bi] = r_pos[bi].lerp(solved[k], w);
		}
		return true;
	}
	if (p_type == "aim") {
		if (!_valid(n, p_c.get("bone", -1))) {
			return false;
		}
		const int bone = p_c["bone"];
		const Vector3 fwd = _vec(p_c.get("forward", Vector3(0, 0, -1)), r_pos);
		const Vector3 target = _vec(p_c.get("target", Variant()), r_pos);
		const Quaternion q = CgameRigSolvers::aim_rotation(r_pos[bone], r_rots[bone].xform(fwd), target, p_c.get("max_angle", Math::PI));
		r_rots.write[bone] = (Quaternion().slerp(q, w) * r_rots[bone]).normalized();
		return true;
	}
	if (p_type == "copy_rotation") {
		if (!_valid(n, p_c.get("src", -1), p_c.get("dst", -1))) {
			return false;
		}
		const int src = p_c["src"];
		const int dst = p_c["dst"];
		const Quaternion goal = r_rots[src] * _quat(p_c.get("offset", Variant()));
		r_rots.write[dst] = r_rots[dst].slerp(goal, w).normalized();
		return true;
	}
	if (p_type == "limit_rotation") {
		if (!_valid(n, p_c.get("bone", -1))) {
			return false;
		}
		const int lb = p_c["bone"];
		const Vector3 lo = _vec(p_c.get("min_deg", Vector3(-180, -180, -180)), r_pos);
		const Vector3 hi = _vec(p_c.get("max_deg", Vector3(180, 180, 180)), r_pos);
		const Vector3 e = r_rots[lb].get_euler();
		const Vector3 deg(Math::rad_to_deg(e.x), Math::rad_to_deg(e.y), Math::rad_to_deg(e.z));
		const Vector3 lim(CLAMP(deg.x, lo.x, hi.x), CLAMP(deg.y, lo.y, hi.y), CLAMP(deg.z, lo.z, hi.z));
		const Quaternion limited = Quaternion::from_euler(Vector3(Math::deg_to_rad(lim.x), Math::deg_to_rad(lim.y), Math::deg_to_rad(lim.z)));
		r_rots.write[lb] = r_rots[lb].slerp(limited, w).normalized();
		return true;
	}
	return false;
}

Variant _to_plain(const Variant &p_value) {
	switch (p_value.get_type()) {
		case Variant::VECTOR3: {
			const Vector3 v = p_value;
			Array a;
			a.push_back(v.x);
			a.push_back(v.y);
			a.push_back(v.z);
			return a;
		}
		case Variant::QUATERNION: {
			const Quaternion q = p_value;
			Array a;
			a.push_back(q.x);
			a.push_back(q.y);
			a.push_back(q.z);
			a.push_back(q.w);
			return a;
		}
		case Variant::NODE_PATH:
		case Variant::STRING_NAME:
			return String(p_value);
		case Variant::ARRAY: {
			const Array in = p_value;
			Array out;
			for (int i = 0; i < in.size(); i++) {
				out.push_back(_to_plain(in[i]));
			}
			return out;
		}
		case Variant::DICTIONARY: {
			const Dictionary in = p_value;
			Dictionary out;
			for (const KeyValue<Variant, Variant> &kv : in) {
				out[kv.key] = _to_plain(kv.value);
			}
			return out;
		}
		default:
			return p_value;
	}
}

} // namespace

Dictionary ConstraintGraphModifier3D::make_pose(const PackedVector3Array &p_positions, const Array &p_rotations) {
	Array rots = p_rotations.duplicate();
	while (rots.size() < p_positions.size()) {
		rots.push_back(Quaternion());
	}
	Dictionary d;
	d["positions"] = p_positions.duplicate();
	d["rotations"] = rots;
	return d;
}

Dictionary ConstraintGraphModifier3D::evaluate_pose(const Dictionary &p_pose, const Array &p_constraints) {
	const PackedVector3Array in_pos = p_pose.get("positions", PackedVector3Array());
	const Array in_rots = p_pose.get("rotations", Array());
	Vector<Vector3> pos;
	Vector<Quaternion> rots;
	for (int i = 0; i < in_pos.size(); i++) {
		pos.push_back(in_pos[i]);
		rots.push_back(i < in_rots.size() ? Quaternion(in_rots[i]) : Quaternion());
	}
	Array log;
	for (int i = 0; i < p_constraints.size(); i++) {
		const Dictionary c = p_constraints[i];
		const String type = c.get("type", "");
		bool applied = false;
		if ((bool)c.get("enabled", true)) {
			applied = _apply(pos, rots, c, type);
		}
		Dictionary entry;
		entry["index"] = i;
		entry["type"] = type;
		entry["applied"] = applied;
		log.push_back(entry);
	}
	PackedVector3Array out_pos;
	out_pos.resize(pos.size());
	Array out_rots;
	for (int i = 0; i < pos.size(); i++) {
		out_pos.write[i] = pos[i];
		out_rots.push_back(rots[i]);
	}
	Dictionary out;
	out["positions"] = out_pos;
	out["rotations"] = out_rots;
	out["log"] = log;
	return out;
}

Variant ConstraintGraphModifier3D::_resolve_bone_ref(Skeleton3D *p_skeleton, const Variant &p_value) const {
	if (p_value.get_type() == Variant::STRING || p_value.get_type() == Variant::STRING_NAME) {
		return p_skeleton->find_bone(String(p_value));
	}
	return p_value;
}

Variant ConstraintGraphModifier3D::_resolve_target(Skeleton3D *p_skeleton, const Variant &p_value) const {
	if (p_value.get_type() == Variant::NODE_PATH) {
		Vector3 pos;
		if (CgameModifierUtil::target_in_skeleton_space(this, p_skeleton, p_value, pos)) {
			return pos;
		}
		return Variant();
	}
	if (p_value.get_type() == Variant::DICTIONARY) {
		Dictionary d = p_value;
		if (d.has("node")) {
			Vector3 pos;
			if (CgameModifierUtil::target_in_skeleton_space(this, p_skeleton, NodePath(d["node"]), pos)) {
				return pos;
			}
			return Variant();
		}
		if (d.has("bone")) {
			Dictionary out = d.duplicate();
			out["bone"] = _resolve_bone_ref(p_skeleton, d["bone"]);
			return out;
		}
	}
	return p_value;
}

Array ConstraintGraphModifier3D::_resolve_constraints(Skeleton3D *p_skeleton) const {
	static const char *bone_keys[] = { "root", "mid", "tip", "bone", "src", "dst" };
	Array out;
	for (int i = 0; i < constraints.size(); i++) {
		Dictionary c = Dictionary(constraints[i]).duplicate();
		for (const char *key : bone_keys) {
			if (c.has(key)) {
				c[key] = _resolve_bone_ref(p_skeleton, c[key]);
			}
		}
		if (c.has("bones")) {
			Array bones = Array(c["bones"]).duplicate();
			for (int k = 0; k < bones.size(); k++) {
				bones[k] = _resolve_bone_ref(p_skeleton, bones[k]);
			}
			c["bones"] = bones;
		}
		for (const char *key : { "target", "pole" }) {
			if (c.has(key)) {
				const Variant resolved = _resolve_target(p_skeleton, c[key]);
				if (resolved.get_type() == Variant::NIL) {
					c.erase(key);
					if (String(key) == "target") {
						c["enabled"] = false; // Missing target: skip this constraint.
					}
				} else {
					c[key] = resolved;
				}
			}
		}
		out.push_back(c);
	}
	return out;
}

void ConstraintGraphModifier3D::_process_modification(double p_delta) {
	Skeleton3D *skeleton = get_skeleton();
	if (!skeleton || influence <= 0.0 || constraints.is_empty()) {
		return;
	}
	const int n = skeleton->get_bone_count();
	PackedVector3Array positions;
	positions.resize(n);
	Array rotations;
	Vector<Quaternion> before;
	for (int i = 0; i < n; i++) {
		const Transform3D gp = skeleton->get_bone_global_pose(i);
		positions.write[i] = gp.origin;
		const Quaternion q = gp.basis.orthonormalized().get_rotation_quaternion();
		rotations.push_back(q);
		before.push_back(q);
	}
	const Dictionary result = evaluate_pose(make_pose(positions, rotations), _resolve_constraints(skeleton));
	last_log = result["log"];
	const PackedVector3Array new_pos = result["positions"];
	const Array new_rots = result["rotations"];

	Vector<Vector3> old_v;
	Vector<Vector3> new_v;
	for (int i = 0; i < n; i++) {
		old_v.push_back(positions[i]);
		new_v.push_back(new_pos[i]);
	}
	CgameRigSolvers::write_positions(skeleton, old_v, new_v, (real_t)influence);

	const Vector<int> order = CgameRigSolvers::bones_parent_first(skeleton);
	for (int k = 0; k < order.size(); k++) {
		const int b = order[k];
		const Quaternion target = Quaternion(new_rots[b]);
		if (Math::abs(target.dot(before[b])) > 0.999999) {
			continue; // Unchanged by the constraints; follows its parent.
		}
		const Quaternion local = get_local_pose_rotation(skeleton, b, target);
		const Quaternion current = skeleton->get_bone_pose_rotation(b);
		skeleton->set_bone_pose_rotation(b, current.slerp(local, CLAMP((real_t)influence, (real_t)0.0, (real_t)1.0)).normalized());
	}
}

void ConstraintGraphModifier3D::set_constraints(const Array &p_constraints) {
	constraints = p_constraints;
}

Array ConstraintGraphModifier3D::get_constraints() const {
	return constraints;
}

int ConstraintGraphModifier3D::add_constraint(const Dictionary &p_constraint) {
	constraints.push_back(p_constraint);
	return constraints.size() - 1;
}

void ConstraintGraphModifier3D::remove_constraint(int p_index) {
	if (p_index >= 0 && p_index < constraints.size()) {
		constraints.remove_at(p_index);
	}
}

void ConstraintGraphModifier3D::move_constraint(int p_from, int p_to) {
	if (p_from < 0 || p_from >= constraints.size()) {
		return;
	}
	const Variant c = constraints[p_from];
	constraints.remove_at(p_from);
	constraints.insert(CLAMP(p_to, 0, constraints.size()), c);
}

void ConstraintGraphModifier3D::clear_constraints() {
	constraints.clear();
}

Array ConstraintGraphModifier3D::get_last_log() const {
	return last_log;
}

String ConstraintGraphModifier3D::to_json() const {
	Array list;
	for (int i = 0; i < constraints.size(); i++) {
		list.push_back(_to_plain(constraints[i]));
	}
	Dictionary root;
	root["version"] = 1;
	root["constraints"] = list;
	return JSON::stringify(root, "\t");
}

bool ConstraintGraphModifier3D::from_json(const String &p_text) {
	const Variant parsed = JSON::parse_string(p_text);
	if (parsed.get_type() != Variant::DICTIONARY) {
		return false;
	}
	const Dictionary d = parsed;
	if (!d.has("constraints") || d["constraints"].get_type() != Variant::ARRAY) {
		return false;
	}
	constraints.clear();
	const Array list = d["constraints"];
	for (int i = 0; i < list.size(); i++) {
		if (list[i].get_type() == Variant::DICTIONARY) {
			constraints.push_back(list[i]);
		}
	}
	return true;
}

void ConstraintGraphModifier3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_constraints", "constraints"), &ConstraintGraphModifier3D::set_constraints);
	ClassDB::bind_method(D_METHOD("get_constraints"), &ConstraintGraphModifier3D::get_constraints);
	ClassDB::bind_method(D_METHOD("add_constraint", "constraint"), &ConstraintGraphModifier3D::add_constraint);
	ClassDB::bind_method(D_METHOD("remove_constraint", "index"), &ConstraintGraphModifier3D::remove_constraint);
	ClassDB::bind_method(D_METHOD("move_constraint", "from_index", "to_index"), &ConstraintGraphModifier3D::move_constraint);
	ClassDB::bind_method(D_METHOD("clear_constraints"), &ConstraintGraphModifier3D::clear_constraints);
	ClassDB::bind_method(D_METHOD("get_last_log"), &ConstraintGraphModifier3D::get_last_log);
	ClassDB::bind_method(D_METHOD("to_json"), &ConstraintGraphModifier3D::to_json);
	ClassDB::bind_method(D_METHOD("from_json", "text"), &ConstraintGraphModifier3D::from_json);
	ClassDB::bind_static_method("ConstraintGraphModifier3D", D_METHOD("make_pose", "positions", "rotations"), &ConstraintGraphModifier3D::make_pose, DEFVAL(Array()));
	ClassDB::bind_static_method("ConstraintGraphModifier3D", D_METHOD("evaluate_pose", "pose", "constraints"), &ConstraintGraphModifier3D::evaluate_pose);

	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "constraints"), "set_constraints", "get_constraints");
}
