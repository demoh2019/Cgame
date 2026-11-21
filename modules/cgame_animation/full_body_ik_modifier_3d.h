/**************************************************************************/
/*  full_body_ik_modifier_3d.h                                            */
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

#include "scene/3d/skeleton_modifier_3d.h"

// Multi-effector FABRIK solved over the whole bone subtree below root_bone, so effectors that share
// ancestors (both legs, spine and arms) pull on the same joints. Solved positions are written back
// as bone rotations. The root of the solved subtree is pinned; hips translation is not modified.
// Branching bones receive one aim per solved child, so very asymmetric poses converge to
// approximately (not exactly) the effector targets; raise iterations or add extra effectors.
class FullBodyIKModifier3D : public SkeletonModifier3D {
	GDCLASS(FullBodyIKModifier3D, SkeletonModifier3D);

	String root_bone;
	// Each entry: { "bone": String, "target_node": NodePath | "target": Vector3 (skeleton space), "weight": float }.
	Array effectors;
	// Bone name -> { "type": "cone"|"hinge", ... } joint limit applied to the direction leaving that bone.
	Dictionary joint_constraints;
	int iterations = 20;
	float tolerance = 0.001f;
	float last_error = 0.0f;

protected:
	static void _bind_methods();
	virtual void _process_modification(double p_delta) override;

public:
	void set_root_bone(const String &p_name);
	String get_root_bone() const;
	void set_effectors(const Array &p_effectors);
	Array get_effectors() const;
	void set_joint_constraints(const Dictionary &p_constraints);
	Dictionary get_joint_constraints() const;
	void set_iterations(int p_iterations);
	int get_iterations() const;
	void set_tolerance(float p_tolerance);
	float get_tolerance() const;

	void add_effector(const String &p_bone, const NodePath &p_target_node, float p_weight = 1.0f);
	void clear_effectors();
	float get_last_error() const;
};
