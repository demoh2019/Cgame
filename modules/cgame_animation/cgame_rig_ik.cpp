/**************************************************************************/
/*  cgame_rig_ik.cpp                                                      */
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

#include "cgame_rig_ik.h"

#include "cgame_rig_solvers.h"

#include "core/object/class_db.h"

Dictionary CgameRigIK::two_bone(const Vector3 &p_root, const Vector3 &p_mid, const Vector3 &p_tip, const Vector3 &p_target, const Vector3 &p_pole) {
	const CgameRigSolvers::TwoBoneResult r = CgameRigSolvers::two_bone(p_root, p_mid, p_tip, p_target, p_pole);
	Dictionary d;
	d["mid"] = r.mid;
	d["tip"] = r.tip;
	d["reached"] = r.reached;
	return d;
}

PackedVector3Array CgameRigIK::fabrik_chain(const PackedVector3Array &p_positions, const Vector3 &p_target, int p_iterations, float p_tolerance, const Array &p_constraints) {
	Vector<CgameRigSolvers::JointConstraint> cons;
	for (int i = 0; i < p_constraints.size(); i++) {
		const Dictionary d = p_constraints[i];
		cons.push_back(CgameRigSolvers::JointConstraint::from_dictionary(d));
	}
	Vector<Vector3> in;
	in.resize(p_positions.size());
	for (int i = 0; i < p_positions.size(); i++) {
		in.write[i] = p_positions[i];
	}
	const Vector<Vector3> out = CgameRigSolvers::fabrik_chain(in, p_target, p_iterations, p_tolerance, cons);
	PackedVector3Array res;
	res.resize(out.size());
	for (int i = 0; i < out.size(); i++) {
		res.write[i] = out[i];
	}
	return res;
}

Quaternion CgameRigIK::aim(const Vector3 &p_bone_pos, const Vector3 &p_forward, const Vector3 &p_target, float p_max_angle) {
	return CgameRigSolvers::aim_rotation(p_bone_pos, p_forward, p_target, p_max_angle);
}

Vector3 CgameRigIK::limit_direction(const Vector3 &p_prev_dir, const Vector3 &p_dir, const Dictionary &p_constraint) {
	return CgameRigSolvers::limit_direction(p_prev_dir, p_dir, CgameRigSolvers::JointConstraint::from_dictionary(p_constraint));
}

void CgameRigIK::_bind_methods() {
	ClassDB::bind_static_method("CgameRigIK", D_METHOD("two_bone", "root", "mid", "tip", "target", "pole"), &CgameRigIK::two_bone);
	ClassDB::bind_static_method("CgameRigIK", D_METHOD("fabrik_chain", "positions", "target", "iterations", "tolerance", "constraints"), &CgameRigIK::fabrik_chain, DEFVAL(16), DEFVAL(0.001), DEFVAL(Array()));
	ClassDB::bind_static_method("CgameRigIK", D_METHOD("aim", "bone_position", "forward", "target", "max_angle"), &CgameRigIK::aim, DEFVAL(Math::PI));
	ClassDB::bind_static_method("CgameRigIK", D_METHOD("limit_direction", "previous_direction", "direction", "constraint"), &CgameRigIK::limit_direction);
}
