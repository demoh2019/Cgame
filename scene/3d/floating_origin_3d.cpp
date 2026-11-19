/**************************************************************************/
/*  floating_origin_3d.cpp                                             */
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

#include "floating_origin_3d.h"

#include "core/config/engine.h"
#include "core/object/class_db.h"
#include "scene/main/scene_tree.h"

Vector3 FloatingOrigin3D::compute_shift(const Vector3 &p_focus_position, real_t p_threshold, real_t p_snap, bool p_shift_vertical) {
	if (!p_focus_position.is_finite() || !(p_snap > 0.0)) {
		return Vector3();
	}
	Vector3 horizontal = p_focus_position;
	if (!p_shift_vertical) {
		horizontal.y = 0.0;
	}
	if (horizontal.length() <= p_threshold) {
		return Vector3();
	}
	Vector3 shift = (p_focus_position / p_snap).round() * p_snap;
	if (!p_shift_vertical) {
		shift.y = 0.0;
	}
	return shift;
}

void FloatingOrigin3D::_update_process() {
	const bool active = is_inside_tree() && !Engine::get_singleton()->is_editor_hint();
	set_physics_process_internal(active && process_callback == PROCESS_PHYSICS);
	set_process_internal(active && process_callback == PROCESS_IDLE);
}

void FloatingOrigin3D::_check_and_shift() {
	Node3D *target = Object::cast_to<Node3D>(get_node_or_null(focus));
	if (!target || !target->is_inside_tree()) {
		return;
	}
	const Vector3 shift = compute_shift(target->get_global_position(), threshold, snap, shift_vertical);
	if (shift != Vector3()) {
		shift_origin(shift);
	}
}

void FloatingOrigin3D::shift_origin(const Vector3 &p_offset) {
	ERR_FAIL_COND(!is_inside_tree());
	ERR_FAIL_COND_MSG(!p_offset.is_finite(), "FloatingOrigin3D: the shift must be finite.");
	if (p_offset == Vector3()) {
		return;
	}
	Node *root = world_root.is_empty() ? get_parent() : get_node_or_null(world_root);
	ERR_FAIL_NULL_MSG(root, "FloatingOrigin3D: world_root is not set and the node has no parent.");

	for (int i = 0; i < root->get_child_count(); i++) {
		Node3D *child = Object::cast_to<Node3D>(root->get_child(i));
		if (!child || child->is_in_group(ignore_group)) {
			continue;
		}
		child->set_global_position(child->get_global_position() - p_offset);
		// Interpolating from the old position to the new one would sweep across the whole world.
		child->reset_physics_interpolation();
	}

	origin_cells += Vector3i((p_offset / snap).round());
	shift_count++;
	emit_signal(SNAME("origin_shifted"), p_offset);
}

void FloatingOrigin3D::set_threshold(real_t p_threshold) {
	threshold = MAX(p_threshold, real_t(0.0));
}

void FloatingOrigin3D::set_snap(real_t p_snap) {
	ERR_FAIL_COND_MSG(!(p_snap > 0.0) || !Math::is_finite(p_snap), "FloatingOrigin3D snap must be a positive finite number.");
	snap = p_snap;
}

void FloatingOrigin3D::set_process_callback(ProcessCallback p_callback) {
	process_callback = p_callback;
	_update_process();
}

void FloatingOrigin3D::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_ENTER_TREE: {
			_update_process();
		} break;
		case NOTIFICATION_EXIT_TREE: {
			set_process_internal(false);
			set_physics_process_internal(false);
		} break;
		case NOTIFICATION_INTERNAL_PHYSICS_PROCESS:
		case NOTIFICATION_INTERNAL_PROCESS: {
			_check_and_shift();
		} break;
	}
}

void FloatingOrigin3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_focus", "focus"), &FloatingOrigin3D::set_focus);
	ClassDB::bind_method(D_METHOD("get_focus"), &FloatingOrigin3D::get_focus);
	ClassDB::bind_method(D_METHOD("set_world_root", "root"), &FloatingOrigin3D::set_world_root);
	ClassDB::bind_method(D_METHOD("get_world_root"), &FloatingOrigin3D::get_world_root);
	ClassDB::bind_method(D_METHOD("set_threshold", "threshold"), &FloatingOrigin3D::set_threshold);
	ClassDB::bind_method(D_METHOD("get_threshold"), &FloatingOrigin3D::get_threshold);
	ClassDB::bind_method(D_METHOD("set_snap", "snap"), &FloatingOrigin3D::set_snap);
	ClassDB::bind_method(D_METHOD("get_snap"), &FloatingOrigin3D::get_snap);
	ClassDB::bind_method(D_METHOD("set_shift_vertical", "enabled"), &FloatingOrigin3D::set_shift_vertical);
	ClassDB::bind_method(D_METHOD("is_shift_vertical"), &FloatingOrigin3D::is_shift_vertical);
	ClassDB::bind_method(D_METHOD("set_process_callback", "callback"), &FloatingOrigin3D::set_process_callback);
	ClassDB::bind_method(D_METHOD("get_process_callback"), &FloatingOrigin3D::get_process_callback);

	ClassDB::bind_method(D_METHOD("shift_origin", "offset"), &FloatingOrigin3D::shift_origin);
	ClassDB::bind_method(D_METHOD("get_origin_cells"), &FloatingOrigin3D::get_origin_cells);
	ClassDB::bind_method(D_METHOD("get_origin_offset"), &FloatingOrigin3D::get_origin_offset);
	ClassDB::bind_method(D_METHOD("get_shift_count"), &FloatingOrigin3D::get_shift_count);
	ClassDB::bind_method(D_METHOD("to_absolute", "local"), &FloatingOrigin3D::to_absolute);
	ClassDB::bind_method(D_METHOD("to_local", "absolute"), &FloatingOrigin3D::to_local);

	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "focus", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "Node3D"), "set_focus", "get_focus");
	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "world_root", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "Node3D,Node"), "set_world_root", "get_world_root");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "threshold", PROPERTY_HINT_RANGE, "0,1000000,1,or_greater,suffix:m"), "set_threshold", "get_threshold");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "snap", PROPERTY_HINT_RANGE, "1,1000000,1,or_greater,suffix:m"), "set_snap", "get_snap");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "shift_vertical"), "set_shift_vertical", "is_shift_vertical");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "process_callback", PROPERTY_HINT_ENUM, "Physics,Idle"), "set_process_callback", "get_process_callback");

	ADD_SIGNAL(MethodInfo("origin_shifted", PropertyInfo(Variant::VECTOR3, "offset")));

	BIND_ENUM_CONSTANT(PROCESS_PHYSICS);
	BIND_ENUM_CONSTANT(PROCESS_IDLE);
}
