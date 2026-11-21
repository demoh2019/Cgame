/**************************************************************************/
/*  origin_rebasing.cpp                                                   */
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

#include "origin_rebasing.h"

#include "core/object/class_db.h"

#include "core/math/math_funcs.h"
#include "scene/3d/node_3d.h"

#define EXCLUDE_GROUP "origin_rebase_exclude"

void OriginRebasing::set_threshold(double p_threshold) {
	threshold = p_threshold;
}

double OriginRebasing::get_threshold() const {
	return threshold;
}

void OriginRebasing::set_grid_step(double p_step) {
	ERR_FAIL_COND_MSG(p_step <= 0.0, "grid_step must be positive.");
	grid_step = p_step;
}

double OriginRebasing::get_grid_step() const {
	return grid_step;
}

void OriginRebasing::set_horizontal_only(bool p_enabled) {
	horizontal_only = p_enabled;
}

bool OriginRebasing::is_horizontal_only() const {
	return horizontal_only;
}

void OriginRebasing::set_origin_cells(const Vector3i &p_cells) {
	origin_cells = p_cells;
}

Vector3i OriginRebasing::get_origin_cells() const {
	return origin_cells;
}

int OriginRebasing::get_shift_count() const {
	return shift_count;
}

Vector3 OriginRebasing::check(const Vector3 &p_camera_world_pos) const {
	Vector3 p = p_camera_world_pos;
	if (horizontal_only) {
		p.y = 0.0;
	}
	if (p.length() <= threshold) {
		return Vector3();
	}
	return Vector3(
			-Math::snapped((double)p.x, grid_step),
			horizontal_only ? 0.0 : -Math::snapped((double)p.y, grid_step),
			-Math::snapped((double)p.z, grid_step));
}

int OriginRebasing::apply(Node3D *p_root, const Vector3 &p_shift) {
	ERR_FAIL_NULL_V(p_root, 0);
	if (p_shift == Vector3()) {
		return 0;
	}
	int moved = 0;
	for (int i = 0; i < p_root->get_child_count(); i++) {
		Node3D *n = Object::cast_to<Node3D>(p_root->get_child(i));
		if (n == nullptr || n->is_in_group(EXCLUDE_GROUP)) {
			continue;
		}
		n->set_position(n->get_position() + p_shift);
		moved++;
	}
	commit(p_shift);
	return moved;
}

void OriginRebasing::commit(const Vector3 &p_shift) {
	if (p_shift == Vector3()) {
		return;
	}
	origin_cells -= Vector3i(
			(int32_t)Math::round(p_shift.x / grid_step),
			(int32_t)Math::round(p_shift.y / grid_step),
			(int32_t)Math::round(p_shift.z / grid_step));
	shift_count++;
	LocalVector<Callable> snapshot(listeners);
	for (const Callable &cb : snapshot) {
		if (cb.is_valid()) {
			cb.call(p_shift);
		}
	}
}

void OriginRebasing::add_listener(const Callable &p_callback) {
	if (!listeners.has(p_callback)) {
		listeners.push_back(p_callback);
	}
}

void OriginRebasing::remove_listener(const Callable &p_callback) {
	listeners.erase(p_callback);
}

Vector3 OriginRebasing::to_global_world(const Vector3 &p_pos) const {
	return Vector3(origin_cells) * (float)grid_step + p_pos;
}

Vector3 OriginRebasing::to_local_world(const Vector3 &p_pos) const {
	return p_pos - Vector3(origin_cells) * (float)grid_step;
}

Dictionary OriginRebasing::to_global_split(const Vector3 &p_pos) const {
	double fx = Math::floor(p_pos.x / grid_step);
	double fy = Math::floor(p_pos.y / grid_step);
	double fz = Math::floor(p_pos.z / grid_step);
	Vector3 rem((float)(p_pos.x - fx * grid_step), (float)(p_pos.y - fy * grid_step), (float)(p_pos.z - fz * grid_step));
	Dictionary d;
	d["cell"] = origin_cells + Vector3i((int32_t)fx, (int32_t)fy, (int32_t)fz);
	d["rem"] = rem;
	return d;
}

Vector3 OriginRebasing::from_global_split(const Vector3i &p_cell, const Vector3 &p_rem) const {
	Vector3i d = p_cell - origin_cells;
	return Vector3((float)((double)d.x * grid_step + p_rem.x), (float)((double)d.y * grid_step + p_rem.y), (float)((double)d.z * grid_step + p_rem.z));
}

Vector3 OriginRebasing::noise_offset(double p_period) const {
	return Vector3(
			(float)Math::fposmod((double)origin_cells.x * grid_step, p_period),
			(float)Math::fposmod((double)origin_cells.y * grid_step, p_period),
			(float)Math::fposmod((double)origin_cells.z * grid_step, p_period));
}

void OriginRebasing::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_threshold", "threshold"), &OriginRebasing::set_threshold);
	ClassDB::bind_method(D_METHOD("get_threshold"), &OriginRebasing::get_threshold);
	ClassDB::bind_method(D_METHOD("set_grid_step", "grid_step"), &OriginRebasing::set_grid_step);
	ClassDB::bind_method(D_METHOD("get_grid_step"), &OriginRebasing::get_grid_step);
	ClassDB::bind_method(D_METHOD("set_horizontal_only", "enabled"), &OriginRebasing::set_horizontal_only);
	ClassDB::bind_method(D_METHOD("is_horizontal_only"), &OriginRebasing::is_horizontal_only);
	ClassDB::bind_method(D_METHOD("set_origin_cells", "cells"), &OriginRebasing::set_origin_cells);
	ClassDB::bind_method(D_METHOD("get_origin_cells"), &OriginRebasing::get_origin_cells);
	ClassDB::bind_method(D_METHOD("get_shift_count"), &OriginRebasing::get_shift_count);

	ClassDB::bind_method(D_METHOD("check", "camera_world_pos"), &OriginRebasing::check);
	ClassDB::bind_method(D_METHOD("apply", "root", "shift"), &OriginRebasing::apply);
	ClassDB::bind_method(D_METHOD("commit", "shift"), &OriginRebasing::commit);
	ClassDB::bind_method(D_METHOD("add_listener", "callback"), &OriginRebasing::add_listener);
	ClassDB::bind_method(D_METHOD("remove_listener", "callback"), &OriginRebasing::remove_listener);
	ClassDB::bind_method(D_METHOD("to_global_world", "pos"), &OriginRebasing::to_global_world);
	ClassDB::bind_method(D_METHOD("to_local_world", "pos"), &OriginRebasing::to_local_world);
	ClassDB::bind_method(D_METHOD("to_global_split", "pos"), &OriginRebasing::to_global_split);
	ClassDB::bind_method(D_METHOD("from_global_split", "cell", "rem"), &OriginRebasing::from_global_split);
	ClassDB::bind_method(D_METHOD("noise_offset", "period"), &OriginRebasing::noise_offset);

	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "threshold", PROPERTY_HINT_RANGE, "0,1000000,0.01,or_greater,suffix:m"), "set_threshold", "get_threshold");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "grid_step", PROPERTY_HINT_RANGE, "0.001,1000000,0.001,or_greater,suffix:m"), "set_grid_step", "get_grid_step");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "horizontal_only"), "set_horizontal_only", "is_horizontal_only");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3I, "origin_cells"), "set_origin_cells", "get_origin_cells");

	ClassDB::bind_static_method("OriginRebasing", D_METHOD("get_exclude_group"), &OriginRebasing::get_exclude_group);
}
