/**************************************************************************/
/*  cgame_rig_solvers.h                                                   */
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

#pragma once

#include "core/math/math_funcs.h"
#include "core/math/quaternion.h"
#include "core/math/vector3.h"
#include "core/templates/hash_map.h"
#include "core/templates/vector.h"
#include "core/variant/dictionary.h"

class Skeleton3D;

// Pure-math rig solvers shared by the animation modifiers and the script-facing wrappers.
struct CgameRigSolvers {
	static constexpr real_t EPS = 0.000001;

	struct JointConstraint {
		enum Type {
			TYPE_NONE,
			TYPE_CONE,
			TYPE_HINGE,
		};
		Type type = TYPE_NONE;
		real_t angle = Math::PI; // Cone half angle.
		Vector3 axis = Vector3(1, 0, 0); // Hinge axis.
		real_t min_angle = -Math::PI;
		real_t max_angle = Math::PI;
		Vector3 ref; // Reference direction for the root joint of a chain.

		static JointConstraint from_dictionary(const Dictionary &p_dict);
	};

	struct TwoBoneResult {
		Vector3 mid;
		Vector3 tip;
		bool reached = false;
	};

	static TwoBoneResult two_bone(const Vector3 &p_root, const Vector3 &p_mid, const Vector3 &p_tip, const Vector3 &p_target, const Vector3 &p_pole);
	static Vector3 limit_direction(const Vector3 &p_prev_dir, const Vector3 &p_dir, const JointConstraint &p_constraint);
	static Vector<Vector3> fabrik_chain(const Vector<Vector3> &p_positions, const Vector3 &p_target, int p_iterations = 16, real_t p_tolerance = 0.001, const Vector<JointConstraint> &p_constraints = Vector<JointConstraint>());
	static Quaternion arc(const Vector3 &p_from, const Vector3 &p_to);
	static Quaternion aim_rotation(const Vector3 &p_bone_pos, const Vector3 &p_forward, const Vector3 &p_target, real_t p_max_angle = Math::PI);

	// Skeleton write-back helpers (skeleton-space positions).
	static void aim_bone_at(Skeleton3D *p_skeleton, int p_bone, int p_child, const Vector3 &p_desired_child_pos, real_t p_weight);
	static void write_positions(Skeleton3D *p_skeleton, const Vector<Vector3> &p_old, const Vector<Vector3> &p_new, real_t p_weight, real_t p_epsilon = 0.00001);
	static Vector<int> bones_parent_first(Skeleton3D *p_skeleton);

	// Multi-effector FABRIK over a bone tree. Parents may appear in any order.
	struct FullBodySolver {
		struct Effector {
			int bone = -1;
			Vector3 target;
			real_t weight = 1.0;
		};

		Vector<int> parents;
		Vector<Vector3> rest;
		Vector<Vector3> positions;
		Vector<real_t> lengths;
		Vector<Effector> effectors;
		HashMap<int, JointConstraint> constraints;
		real_t root_pin = 0.0;

		void setup(const Vector<int> &p_parents, const Vector<Vector3> &p_rest);
		void reset();
		void set_effector(int p_bone, const Vector3 &p_target, real_t p_weight = 1.0);
		void set_constraint(int p_bone, const JointConstraint &p_constraint);
		real_t effector_error() const;
		real_t solve(int p_iterations = 20, real_t p_tolerance = 0.001);

	private:
		Vector<int> _topo_order() const;
	};
};
