/**************************************************************************/
/*  cgame_retargeter.h                                                    */
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

class Skeleton3D;

// Humanoid bone-name canonicalization, source-to-target bone mapping and pose transfer between
// rigs with different proportions. A "rig" is a Dictionary with "names" (PackedStringArray),
// "parents" (PackedInt32Array), "rest" (PackedVector3Array global rest positions) and optional
// "rest_rot" (Array of local rest Quaternions). Mirrors scripts/client/rig_retarget.gd and adds a
// direct Skeleton3D-to-Skeleton3D transfer.
class CgameRetargeter : public RefCounted {
	GDCLASS(CgameRetargeter, RefCounted);

	static Quaternion _local_rest(const Dictionary &p_rig, int p_index);
	static Quaternion _local_pose_from(const Dictionary &p_rig, int p_index, const Quaternion &p_parent_global, const Quaternion &p_new_global);
	static float _leg_length(const PackedVector3Array &p_rest, int p_hips, int p_foot);

protected:
	static void _bind_methods();

public:
	static String canonical(const String &p_bone_name, const Dictionary &p_aliases = Dictionary());
	static Dictionary build_map(const PackedStringArray &p_source_names, const PackedStringArray &p_target_names, const Dictionary &p_aliases = Dictionary());
	static int find_bone(const PackedStringArray &p_names, const String &p_key, const Dictionary &p_aliases = Dictionary());

	static Dictionary fk(const Dictionary &p_rig, const Array &p_rotations, int p_hips_bone, const Vector3 &p_hips);
	static Dictionary retarget_pose(const Dictionary &p_source_rest, const Dictionary &p_source_pose, const Dictionary &p_target_rest, const Dictionary &p_map);
	static Dictionary ik_correct_feet(const Dictionary &p_target_rig, const Dictionary &p_pose, const Dictionary &p_foot_targets);

	// Direct skeleton helpers.
	static Dictionary rig_from_skeleton(const Skeleton3D *p_skeleton);
	static Dictionary build_skeleton_map(const Skeleton3D *p_source, const Skeleton3D *p_target, const Dictionary &p_aliases = Dictionary());
	static int transfer_pose(const Skeleton3D *p_source, Skeleton3D *p_target, const Dictionary &p_map, bool p_scale_hips = true);
};
