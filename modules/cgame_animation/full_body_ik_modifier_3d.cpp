/**************************************************************************/
/*  full_body_ik_modifier_3d.cpp                                          */
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

#include "full_body_ik_modifier_3d.h"

#include "cgame_modifier_util.h"
#include "cgame_rig_solvers.h"

#include "core/object/class_db.h"

void FullBodyIKModifier3D::_process_modification(double p_delta) {
	Skeleton3D *skeleton = get_skeleton();
	if (!skeleton || influence <= 0.0 || effectors.is_empty()) {
		return;
	}
	const int bone_count = skeleton->get_bone_count();
	if (bone_count == 0) {
		return;
	}

	// Collect the subtree below root_bone and map skeleton indices to solver indices.
	const int root = root_bone.is_empty() ? -1 : skeleton->find_bone(root_bone);
	if (!root_bone.is_empty() && root < 0) {
		return;
	}
	const Vector<int> order = CgameRigSolvers::bones_parent_first(skeleton);
	Vector<int> to_solver;
	to_solver.resize(bone_count);
	to_solver.fill(-1);
	Vector<int> from_solver;
	for (int k = 0; k < order.size(); k++) {
		const int b = order[k];
		const int p = skeleton->get_bone_parent(b);
		const bool in_subtree = (root < 0) || b == root || (p >= 0 && to_solver[p] >= 0);
		if (in_subtree) {
			to_solver.write[b] = from_solver.size();
			from_solver.push_back(b);
		}
	}

	Vector<int> parents;
	Vector<Vector3> positions;
	Vector<Vector3> all_old;
	all_old.resize(bone_count);
	for (int b = 0; b < bone_count; b++) {
		all_old.write[b] = skeleton->get_bone_global_pose(b).origin;
	}
	for (int i = 0; i < from_solver.size(); i++) {
		const int b = from_solver[i];
		const int p = skeleton->get_bone_parent(b);
		parents.push_back((b == root || p < 0) ? -1 : to_solver[p]);
		positions.push_back(all_old[b]);
	}

	CgameRigSolvers::FullBodySolver solver;
	solver.setup(parents, positions);
	solver.root_pin = 1.0;

	for (int i = 0; i < effectors.size(); i++) {
		const Dictionary e = effectors[i];
		const int bone = skeleton->find_bone(String(e.get("bone", String())));
		if (bone < 0 || to_solver[bone] < 0) {
			continue;
		}
		Vector3 target;
		bool have = false;
		if (e.has("target_node")) {
			have = CgameModifierUtil::target_in_skeleton_space(this, skeleton, NodePath(e["target_node"]), target);
		} else if (e.has("target")) {
			target = e["target"];
			have = true;
		}
		if (!have) {
			continue;
		}
		solver.set_effector(to_solver[bone], target, CLAMP((real_t)e.get("weight", 1.0), (real_t)0.0, (real_t)1.0) * influence);
	}
	if (solver.effectors.is_empty()) {
		return;
	}
	for (const KeyValue<Variant, Variant> &kv : joint_constraints) {
		const int bone = skeleton->find_bone(String(kv.key));
		if (bone >= 0 && to_solver[bone] >= 0 && kv.value.get_type() == Variant::DICTIONARY) {
			solver.set_constraint(to_solver[bone], CgameRigSolvers::JointConstraint::from_dictionary(kv.value));
		}
	}

	last_error = solver.solve(iterations, tolerance);

	// Only bones on an effector chain are rotated; siblings follow their parents.
	Vector<uint8_t> involved;
	involved.resize_initialized(from_solver.size());
	for (int i = 0; i < solver.effectors.size(); i++) {
		int cur = solver.effectors[i].bone;
		while (cur >= 0 && !involved[cur]) {
			involved.write[cur] = 1;
			cur = parents[cur];
		}
	}
	Vector<Vector3> new_pos = all_old;
	for (int i = 0; i < from_solver.size(); i++) {
		if (involved[i]) {
			new_pos.write[from_solver[i]] = solver.positions[i];
		}
	}
	CgameRigSolvers::write_positions(skeleton, all_old, new_pos, 1.0);
}

void FullBodyIKModifier3D::set_root_bone(const String &p_name) {
	root_bone = p_name;
}
String FullBodyIKModifier3D::get_root_bone() const {
	return root_bone;
}
void FullBodyIKModifier3D::set_effectors(const Array &p_effectors) {
	effectors = p_effectors;
}
Array FullBodyIKModifier3D::get_effectors() const {
	return effectors;
}
void FullBodyIKModifier3D::set_joint_constraints(const Dictionary &p_constraints) {
	joint_constraints = p_constraints;
}
Dictionary FullBodyIKModifier3D::get_joint_constraints() const {
	return joint_constraints;
}
void FullBodyIKModifier3D::set_iterations(int p_iterations) {
	iterations = MAX(p_iterations, 1);
}
int FullBodyIKModifier3D::get_iterations() const {
	return iterations;
}
void FullBodyIKModifier3D::set_tolerance(float p_tolerance) {
	tolerance = MAX(p_tolerance, 0.0f);
}
float FullBodyIKModifier3D::get_tolerance() const {
	return tolerance;
}

void FullBodyIKModifier3D::add_effector(const String &p_bone, const NodePath &p_target_node, float p_weight) {
	Dictionary e;
	e["bone"] = p_bone;
	e["target_node"] = p_target_node;
	e["weight"] = p_weight;
	effectors.push_back(e);
}

void FullBodyIKModifier3D::clear_effectors() {
	effectors.clear();
}

float FullBodyIKModifier3D::get_last_error() const {
	return last_error;
}

void FullBodyIKModifier3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_root_bone", "name"), &FullBodyIKModifier3D::set_root_bone);
	ClassDB::bind_method(D_METHOD("get_root_bone"), &FullBodyIKModifier3D::get_root_bone);
	ClassDB::bind_method(D_METHOD("set_effectors", "effectors"), &FullBodyIKModifier3D::set_effectors);
	ClassDB::bind_method(D_METHOD("get_effectors"), &FullBodyIKModifier3D::get_effectors);
	ClassDB::bind_method(D_METHOD("set_joint_constraints", "constraints"), &FullBodyIKModifier3D::set_joint_constraints);
	ClassDB::bind_method(D_METHOD("get_joint_constraints"), &FullBodyIKModifier3D::get_joint_constraints);
	ClassDB::bind_method(D_METHOD("set_iterations", "iterations"), &FullBodyIKModifier3D::set_iterations);
	ClassDB::bind_method(D_METHOD("get_iterations"), &FullBodyIKModifier3D::get_iterations);
	ClassDB::bind_method(D_METHOD("set_tolerance", "tolerance"), &FullBodyIKModifier3D::set_tolerance);
	ClassDB::bind_method(D_METHOD("get_tolerance"), &FullBodyIKModifier3D::get_tolerance);
	ClassDB::bind_method(D_METHOD("add_effector", "bone", "target_node", "weight"), &FullBodyIKModifier3D::add_effector, DEFVAL(1.0f));
	ClassDB::bind_method(D_METHOD("clear_effectors"), &FullBodyIKModifier3D::clear_effectors);
	ClassDB::bind_method(D_METHOD("get_last_error"), &FullBodyIKModifier3D::get_last_error);

	ADD_PROPERTY(PropertyInfo(Variant::STRING, "root_bone"), "set_root_bone", "get_root_bone");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "effectors"), "set_effectors", "get_effectors");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "joint_constraints"), "set_joint_constraints", "get_joint_constraints");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "iterations", PROPERTY_HINT_RANGE, "1,100,1,or_greater"), "set_iterations", "get_iterations");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "tolerance", PROPERTY_HINT_RANGE, "0.0001,0.1,0.0001,or_greater,suffix:m"), "set_tolerance", "get_tolerance");
}
