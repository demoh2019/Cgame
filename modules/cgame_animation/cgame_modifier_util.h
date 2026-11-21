/**************************************************************************/
/*  cgame_modifier_util.h                                                 */
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

#include "scene/3d/node_3d.h"
#include "scene/3d/skeleton_3d.h"

// Helpers shared by the Cgame skeleton modifiers.
namespace CgameModifierUtil {

// Resolves a Node3D at p_path (relative to p_from) and returns its global origin in skeleton space.
// Returns false when the node is missing or is not a Node3D.
inline bool target_in_skeleton_space(const Node *p_from, const Skeleton3D *p_skeleton, const NodePath &p_path, Vector3 &r_position) {
	if (p_path.is_empty() || !p_from || !p_skeleton || !p_from->is_inside_tree()) {
		return false;
	}
	const Node3D *target = Object::cast_to<Node3D>(p_from->get_node_or_null(p_path));
	if (!target || !target->is_inside_tree() || !p_skeleton->is_inside_tree()) {
		return false;
	}
	r_position = p_skeleton->get_global_transform().affine_inverse().xform(target->get_global_transform().origin);
	return true;
}

} // namespace CgameModifierUtil
