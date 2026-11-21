/**************************************************************************/
/*  constraint_graph_modifier_3d.h                                        */
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

// Data-driven ordered list of constraints (two_bone, fabrik_chain, aim, copy_rotation,
// limit_rotation), evaluated top to bottom on the skeleton pose. Mirrors
// scripts/client/constraint_graph.gd. The evaluation itself is a pure function over a pose
// dictionary ({"positions": PackedVector3Array, "rotations": Array[Quaternion]}) so it can also be
// used offline through evaluate().
//
// Bones may be referenced by name or index, targets by Vector3 (skeleton space), [x, y, z],
// {"bone": name_or_index} or a NodePath / {"node": NodePath} to a Node3D.
class ConstraintGraphModifier3D : public SkeletonModifier3D {
	GDCLASS(ConstraintGraphModifier3D, SkeletonModifier3D);

	Array constraints;
	Array last_log;

	Variant _resolve_bone_ref(Skeleton3D *p_skeleton, const Variant &p_value) const;
	Variant _resolve_target(Skeleton3D *p_skeleton, const Variant &p_value) const;
	Array _resolve_constraints(Skeleton3D *p_skeleton) const;

protected:
	static void _bind_methods();
	virtual void _process_modification(double p_delta) override;

public:
	void set_constraints(const Array &p_constraints);
	Array get_constraints() const;
	int add_constraint(const Dictionary &p_constraint);
	void remove_constraint(int p_index);
	void move_constraint(int p_from, int p_to);
	void clear_constraints();
	Array get_last_log() const;

	String to_json() const;
	bool from_json(const String &p_text);

	static Dictionary make_pose(const PackedVector3Array &p_positions, const Array &p_rotations = Array());
	static Dictionary evaluate_pose(const Dictionary &p_pose, const Array &p_constraints);
};
