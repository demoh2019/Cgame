/**************************************************************************/
/*  cgame_rig_ik.h                                                        */
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

#include "core/object/ref_counted.h"
#include "core/variant/typed_array.h"

// Script-facing static wrappers over CgameRigSolvers (mirrors scripts/client/rig_ik.gd).
class CgameRigIK : public RefCounted {
	GDCLASS(CgameRigIK, RefCounted);

protected:
	static void _bind_methods();

public:
	static Dictionary two_bone(const Vector3 &p_root, const Vector3 &p_mid, const Vector3 &p_tip, const Vector3 &p_target, const Vector3 &p_pole);
	static PackedVector3Array fabrik_chain(const PackedVector3Array &p_positions, const Vector3 &p_target, int p_iterations = 16, float p_tolerance = 0.001, const Array &p_constraints = Array());
	static Quaternion aim(const Vector3 &p_bone_pos, const Vector3 &p_forward, const Vector3 &p_target, float p_max_angle = Math::PI);
	static Vector3 limit_direction(const Vector3 &p_prev_dir, const Vector3 &p_dir, const Dictionary &p_constraint);
};
