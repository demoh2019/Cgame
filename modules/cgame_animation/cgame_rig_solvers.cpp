/**************************************************************************/
/*  cgame_rig_solvers.cpp                                                 */
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

#include "cgame_rig_solvers.h"

#include "scene/3d/skeleton_3d.h"
#include "scene/3d/skeleton_modifier_3d.h"

CgameRigSolvers::JointConstraint CgameRigSolvers::JointConstraint::from_dictionary(const Dictionary &p_dict) {
	JointConstraint c;
	String kind = p_dict.get("type", "");
	if (kind == "cone") {
		c.type = TYPE_CONE;
		c.angle = p_dict.get("angle", Math::PI);
	} else if (kind == "hinge") {
		c.type = TYPE_HINGE;
		c.axis = p_dict.get("axis", Vector3(1, 0, 0));
		c.min_angle = p_dict.get("min", -Math::PI);
		c.max_angle = p_dict.get("max", Math::PI);
	}
	c.ref = p_dict.get("ref", Vector3());
	return c;
}

Quaternion CgameRigSolvers::arc(const Vector3 &p_from, const Vector3 &p_to) {
	if (p_from.dot(p_to) < -0.99999) {
		Vector3 axis = p_from.cross(Vector3(0, 1, 0));
		if (axis.length_squared() < EPS) {
			axis = p_from.cross(Vector3(1, 0, 0));
		}
		return Quaternion(axis.normalized(), Math::PI);
	}
	return Quaternion(p_from, p_to);
}

CgameRigSolvers::TwoBoneResult CgameRigSolvers::two_bone(const Vector3 &p_root, const Vector3 &p_mid, const Vector3 &p_tip, const Vector3 &p_target, const Vector3 &p_pole) {
	const real_t l1 = p_root.distance_to(p_mid);
	const real_t l2 = p_mid.distance_to(p_tip);
	const Vector3 to_target = p_target - p_root;
	const real_t dist = to_target.length();
	Vector3 u = Vector3(0, 0, -1);
	if (dist > EPS) {
		u = to_target / dist;
	}
	const real_t min_d = Math::abs(l1 - l2) + EPS;
	const real_t max_d = l1 + l2;
	TwoBoneResult res;
	res.reached = dist <= max_d && dist >= min_d;
	const real_t d = CLAMP(dist, min_d, MAX(max_d, min_d));
	const Vector3 pole_vec = p_pole - p_root;
	Vector3 perp = pole_vec - u * pole_vec.dot(u);
	if (perp.length_squared() < EPS) {
		perp = (p_mid - p_root) - u * (p_mid - p_root).dot(u);
	}
	if (perp.length_squared() < EPS) {
		perp = u.cross(Vector3(0, 1, 0));
		if (perp.length_squared() < EPS) {
			perp = u.cross(Vector3(1, 0, 0));
		}
	}
	perp = perp.normalized();
	const real_t a = (l1 * l1 - l2 * l2 + d * d) / (2.0 * d);
	const real_t h = Math::sqrt(MAX(l1 * l1 - a * a, (real_t)0.0));
	res.mid = p_root + u * a + perp * h;
	res.tip = p_root + u * d;
	return res;
}

Vector3 CgameRigSolvers::limit_direction(const Vector3 &p_prev_dir, const Vector3 &p_dir, const JointConstraint &p_constraint) {
	if (p_prev_dir.length_squared() < EPS || p_dir.length_squared() < EPS) {
		return p_dir;
	}
	const Vector3 pd = p_prev_dir.normalized();
	const Vector3 dn = p_dir.normalized();
	if (p_constraint.type == JointConstraint::TYPE_CONE) {
		if (pd.angle_to(dn) <= p_constraint.angle) {
			return dn;
		}
		Vector3 axis = pd.cross(dn);
		if (axis.length_squared() < EPS) {
			axis = pd.cross(Vector3(0, 1, 0));
			if (axis.length_squared() < EPS) {
				axis = pd.cross(Vector3(1, 0, 0));
			}
		}
		return pd.rotated(axis.normalized(), p_constraint.angle).normalized();
	}
	if (p_constraint.type == JointConstraint::TYPE_HINGE) {
		const Vector3 hinge = p_constraint.axis.normalized();
		Vector3 pp = pd - hinge * pd.dot(hinge);
		if (pp.length_squared() < EPS) {
			return dn;
		}
		pp = pp.normalized();
		Vector3 dp = dn - hinge * dn.dot(hinge);
		if (dp.length_squared() < EPS) {
			dp = pp;
		}
		dp = dp.normalized();
		const real_t ang = CLAMP(pp.signed_angle_to(dp, hinge), p_constraint.min_angle, p_constraint.max_angle);
		return pp.rotated(hinge, ang).normalized();
	}
	return dn;
}

Vector<Vector3> CgameRigSolvers::fabrik_chain(const Vector<Vector3> &p_positions, const Vector3 &p_target, int p_iterations, real_t p_tolerance, const Vector<JointConstraint> &p_constraints) {
	const int n = p_positions.size();
	Vector<Vector3> out = p_positions;
	if (n < 2) {
		return out;
	}
	Vector<real_t> lens;
	lens.resize(n - 1);
	for (int i = 0; i < n - 1; i++) {
		lens.write[i] = p_positions[i].distance_to(p_positions[i + 1]);
	}
	const Vector3 root = p_positions[0];
	for (int it = 0; it < p_iterations; it++) {
		if (out[n - 1].distance_to(p_target) <= p_tolerance) {
			break;
		}
		out.write[n - 1] = p_target;
		for (int i = n - 2; i >= 0; i--) {
			Vector3 dir = out[i] - out[i + 1];
			if (dir.length_squared() < EPS) {
				dir = p_positions[i] - p_positions[i + 1];
			}
			out.write[i] = out[i + 1] + dir.normalized() * lens[i];
		}
		out.write[0] = root;
		for (int i = 0; i < n - 1; i++) {
			Vector3 dir2 = out[i + 1] - out[i];
			if (dir2.length_squared() < EPS) {
				dir2 = p_positions[i + 1] - p_positions[i];
			}
			dir2 = dir2.normalized();
			if (i < p_constraints.size() && p_constraints[i].type != JointConstraint::TYPE_NONE) {
				const Vector3 prev = (i > 0) ? out[i] - out[i - 1] : p_constraints[i].ref;
				dir2 = limit_direction(prev, dir2, p_constraints[i]);
			}
			out.write[i + 1] = out[i] + dir2 * lens[i];
		}
	}
	return out;
}

Quaternion CgameRigSolvers::aim_rotation(const Vector3 &p_bone_pos, const Vector3 &p_forward, const Vector3 &p_target, real_t p_max_angle) {
	const Vector3 to_t = p_target - p_bone_pos;
	if (to_t.length_squared() < EPS || p_forward.length_squared() < EPS) {
		return Quaternion();
	}
	Quaternion q = arc(p_forward.normalized(), to_t.normalized());
	const real_t ang = q.get_angle();
	if (ang > p_max_angle) {
		q = Quaternion(q.get_axis(), MAX(p_max_angle, (real_t)0.0));
	}
	return q;
}

Vector<int> CgameRigSolvers::bones_parent_first(Skeleton3D *p_skeleton) {
	const int n = p_skeleton->get_bone_count();
	Vector<int> order;
	Vector<uint8_t> done;
	done.resize_initialized(n);
	int guard = 0;
	while (order.size() < n && guard <= n) {
		guard++;
		for (int i = 0; i < n; i++) {
			if (done[i]) {
				continue;
			}
			const int p = p_skeleton->get_bone_parent(i);
			if (p < 0 || done[p]) {
				done.write[i] = 1;
				order.push_back(i);
			}
		}
	}
	return order;
}

void CgameRigSolvers::aim_bone_at(Skeleton3D *p_skeleton, int p_bone, int p_child, const Vector3 &p_desired_child_pos, real_t p_weight) {
	ERR_FAIL_NULL(p_skeleton);
	ERR_FAIL_INDEX(p_bone, p_skeleton->get_bone_count());
	ERR_FAIL_INDEX(p_child, p_skeleton->get_bone_count());
	const Transform3D gp = p_skeleton->get_bone_global_pose(p_bone);
	const Transform3D cp = p_skeleton->get_bone_global_pose(p_child);
	const Vector3 cur = cp.origin - gp.origin;
	const Vector3 des = p_desired_child_pos - gp.origin;
	if (cur.length_squared() < EPS || des.length_squared() < EPS) {
		return;
	}
	const Quaternion rot = arc(cur.normalized(), des.normalized());
	const Quaternion new_global = (rot * gp.basis.orthonormalized().get_rotation_quaternion()).normalized();
	const Quaternion local = SkeletonModifier3D::get_local_pose_rotation(p_skeleton, p_bone, new_global);
	const Quaternion cur_local = p_skeleton->get_bone_pose_rotation(p_bone);
	p_skeleton->set_bone_pose_rotation(p_bone, cur_local.slerp(local, CLAMP(p_weight, (real_t)0.0, (real_t)1.0)).normalized());
}

void CgameRigSolvers::write_positions(Skeleton3D *p_skeleton, const Vector<Vector3> &p_old, const Vector<Vector3> &p_new, real_t p_weight, real_t p_epsilon) {
	ERR_FAIL_NULL(p_skeleton);
	const int n = p_skeleton->get_bone_count();
	ERR_FAIL_COND(p_old.size() != n || p_new.size() != n);
	const Vector<int> order = bones_parent_first(p_skeleton);
	for (int k = 0; k < order.size(); k++) {
		const int c = order[k];
		const int p = p_skeleton->get_bone_parent(c);
		if (p < 0 || p_old[c].distance_squared_to(p_new[c]) <= p_epsilon * p_epsilon) {
			continue;
		}
		aim_bone_at(p_skeleton, p, c, p_new[c], p_weight);
	}
}

// ---- FullBodySolver ----

void CgameRigSolvers::FullBodySolver::setup(const Vector<int> &p_parents, const Vector<Vector3> &p_rest) {
	ERR_FAIL_COND(p_parents.size() != p_rest.size());
	parents = p_parents;
	rest = p_rest;
	positions = p_rest;
	lengths.resize(parents.size());
	for (int i = 0; i < parents.size(); i++) {
		lengths.write[i] = parents[i] < 0 ? 0.0 : rest[i].distance_to(rest[parents[i]]);
	}
}

void CgameRigSolvers::FullBodySolver::reset() {
	positions = rest;
}

void CgameRigSolvers::FullBodySolver::set_effector(int p_bone, const Vector3 &p_target, real_t p_weight) {
	for (int i = 0; i < effectors.size(); i++) {
		if (effectors[i].bone == p_bone) {
			effectors.write[i].target = p_target;
			effectors.write[i].weight = p_weight;
			return;
		}
	}
	Effector e;
	e.bone = p_bone;
	e.target = p_target;
	e.weight = p_weight;
	effectors.push_back(e);
}

void CgameRigSolvers::FullBodySolver::set_constraint(int p_bone, const JointConstraint &p_constraint) {
	constraints[p_bone] = p_constraint;
}

real_t CgameRigSolvers::FullBodySolver::effector_error() const {
	real_t worst = 0.0;
	for (const Effector &e : effectors) {
		if (e.weight < 0.999 || e.bone < 0 || e.bone >= positions.size()) {
			continue;
		}
		worst = MAX(worst, positions[e.bone].distance_to(e.target));
	}
	return worst;
}

Vector<int> CgameRigSolvers::FullBodySolver::_topo_order() const {
	const int n = parents.size();
	Vector<int> order;
	Vector<uint8_t> done;
	done.resize_initialized(n);
	int guard = 0;
	while (order.size() < n && guard <= n) {
		guard++;
		for (int i = 0; i < n; i++) {
			if (!done[i] && (parents[i] < 0 || done[parents[i]])) {
				done.write[i] = 1;
				order.push_back(i);
			}
		}
	}
	return order;
}

real_t CgameRigSolvers::FullBodySolver::solve(int p_iterations, real_t p_tolerance) {
	const int n = parents.size();
	if (effectors.is_empty() || n == 0) {
		return 0.0;
	}
	const Vector<int> order = _topo_order();
	Vector<uint8_t> involved;
	involved.resize_initialized(n);
	HashMap<int, int> eff_at; // Bone -> effector index.
	for (int k = 0; k < effectors.size(); k++) {
		const int b = effectors[k].bone;
		if (b < 0 || b >= n) {
			continue;
		}
		eff_at[b] = k;
		int cur = b;
		while (cur >= 0 && !involved[cur]) {
			involved.write[cur] = 1;
			cur = parents[cur];
		}
	}
	const Vector<Vector3> anchor = positions;
	real_t err = effector_error();
	for (int it = 0; it < p_iterations; it++) {
		if (err <= p_tolerance) {
			break;
		}
		Vector<Vector3> acc;
		acc.resize_initialized(n);
		Vector<real_t> wsum;
		wsum.resize_initialized(n);
		Vector<Vector3> np = positions;
		// Backward pass: leaves to roots.
		for (int k = order.size() - 1; k >= 0; k--) {
			const int i = order[k];
			if (!involved[i]) {
				continue;
			}
			if (eff_at.has(i)) {
				const Effector &e = effectors[eff_at[i]];
				np.write[i] = positions[i].lerp(e.target, e.weight);
			} else if (wsum[i] > 0.0) {
				np.write[i] = acc[i] / wsum[i];
			}
			const int par = parents[i];
			if (par >= 0) {
				Vector3 dir = positions[par] - np[i];
				if (dir.length_squared() < EPS) {
					dir = rest[par] - rest[i];
				}
				acc.write[par] += np[i] + dir.normalized() * lengths[i];
				wsum.write[par] += 1.0;
			}
		}
		Vector<Vector3> fp = positions;
		// Forward pass: roots to leaves.
		for (int k = 0; k < order.size(); k++) {
			const int c = order[k];
			const int p = parents[c];
			if (p < 0) {
				fp.write[c] = np[c].lerp(anchor[c], root_pin);
				continue;
			}
			if (involved[c]) {
				Vector3 d = np[c] - fp[p];
				if (d.length_squared() < EPS) {
					d = positions[c] - positions[p];
				}
				d = d.normalized();
				if (constraints.has(p)) {
					const JointConstraint &con = constraints[p];
					const int pp = parents[p];
					const Vector3 prev = pp >= 0 ? fp[p] - fp[pp] : con.ref;
					d = limit_direction(prev, d, con);
				}
				fp.write[c] = fp[p] + d * lengths[c];
			} else {
				fp.write[c] = fp[p] + (positions[c] - positions[p]);
			}
		}
		positions = fp;
		err = effector_error();
	}
	return err;
}
