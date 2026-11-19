/**************************************************************************/
/*  godot_collision_object_2d.cpp                                         */
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

#include "godot_collision_object_2d.h"

#include "godot_physics_server_2d.h"
#include "godot_space_2d.h"

void GodotCollisionObject2D::add_shape(GodotShape2D *p_shape, const Transform2D &p_transform, bool p_disabled) {
	Shape s;
	s.shape = p_shape;
	s.xform = p_transform;
	s.xform_inv = s.xform.affine_inverse();
	s.bpid = 0; //needs update
	s.disabled = p_disabled;
	s.one_way_collision = false;
	s.one_way_collision_margin = 0;
	s.one_way_collision_direction = Vector2(0, 1);
	shapes.push_back(s);
	p_shape->add_owner(this);
	++collision_geometry_version;

	if (!pending_shape_update_list.in_list()) {
		GodotPhysicsServer2D::godot_singleton->pending_shape_update_list.add(&pending_shape_update_list);
	}
}

void GodotCollisionObject2D::set_shape(int p_index, GodotShape2D *p_shape) {
	ERR_FAIL_INDEX(p_index, (int)shapes.size());
	shapes[p_index].shape->remove_owner(this);
	shapes[p_index].shape = p_shape;

	p_shape->add_owner(this);
	++collision_geometry_version;

	if (!pending_shape_update_list.in_list()) {
		GodotPhysicsServer2D::godot_singleton->pending_shape_update_list.add(&pending_shape_update_list);
	}
}

void GodotCollisionObject2D::set_shape_transform(int p_index, const Transform2D &p_transform) {
	ERR_FAIL_INDEX(p_index, (int)shapes.size());

	shapes[p_index].xform = p_transform;
	shapes[p_index].xform_inv = p_transform.affine_inverse();
	++collision_geometry_version;

	if (!pending_shape_update_list.in_list()) {
		GodotPhysicsServer2D::godot_singleton->pending_shape_update_list.add(&pending_shape_update_list);
	}
}

void GodotCollisionObject2D::set_shape_disabled(int p_idx, bool p_disabled) {
	ERR_FAIL_INDEX(p_idx, (int)shapes.size());

	GodotCollisionObject2D::Shape &shape = shapes[p_idx];
	if (shape.disabled == p_disabled) {
		return;
	}

	shape.disabled = p_disabled;
	++collision_geometry_version;

	if (!space) {
		return;
	}

	if (p_disabled && shape.bpid != 0) {
		space->get_broadphase()->remove(shape.bpid);
		shape.bpid = 0;
		if (!pending_shape_update_list.in_list()) {
			GodotPhysicsServer2D::godot_singleton->pending_shape_update_list.add(&pending_shape_update_list);
		}
	} else if (!p_disabled && shape.bpid == 0) {
		if (!pending_shape_update_list.in_list()) {
			GodotPhysicsServer2D::godot_singleton->pending_shape_update_list.add(&pending_shape_update_list);
		}
	}
}

void GodotCollisionObject2D::remove_shape(GodotShape2D *p_shape) {
	//remove a shape, all the times it appears
	for (int i = 0; i < (int)shapes.size(); i++) {
		if (shapes[i].shape == p_shape) {
			remove_shape(i);
			i--;
		}
	}
}

void GodotCollisionObject2D::remove_shape(int p_index) {
	//remove anything from shape to be erased to end, so subindices don't change
	ERR_FAIL_INDEX(p_index, (int)shapes.size());
	for (int i = p_index; i < (int)shapes.size(); i++) {
		if (shapes[i].bpid == 0) {
			continue;
		}
		//should never get here with a null owner
		space->get_broadphase()->remove(shapes[i].bpid);
		shapes[i].bpid = 0;
	}
	shapes[p_index].shape->remove_owner(this);
	shapes.remove_at(p_index);
	++collision_geometry_version;

	if (!pending_shape_update_list.in_list()) {
		GodotPhysicsServer2D::godot_singleton->pending_shape_update_list.add(&pending_shape_update_list);
	}
	// _update_shapes();
	// _shapes_changed();
}

void GodotCollisionObject2D::_set_static(bool p_static) {
	if (_static == p_static) {
		return;
	}
	_static = p_static;
	++collision_geometry_version;

	if (!space) {
		return;
	}
	for (int i = 0; i < get_shape_count(); i++) {
		const Shape &s = shapes[i];
		if (s.bpid > 0) {
			space->get_broadphase()->set_static(s.bpid, _static);
		}
	}
}

void GodotCollisionObject2D::_unregister_shapes() {
	for (int i = 0; i < (int)shapes.size(); i++) {
		Shape &s = shapes[i];
		if (s.bpid > 0) {
			space->get_broadphase()->remove(s.bpid);
			s.bpid = 0;
		}
	}
}

void GodotCollisionObject2D::_update_shapes() {
	if (!space) {
		return;
	}

	// Register compound shapes before generating pair callbacks. A single-shape
	// object retains the synchronous insertion behavior.
	const bool defer_pair_checks = shapes.size() > 1;
	bool has_deferred_shapes = false;

	for (int i = 0; i < (int)shapes.size(); i++) {
		Shape &s = shapes[i];
		if (s.disabled) {
			continue;
		}

		//not quite correct, should compute the next matrix..
		Rect2 shape_aabb = s.shape->get_aabb();
		Transform2D xform = transform * s.xform;
		shape_aabb = xform.xform(shape_aabb);
		// Base the broadphase margin on the current shape, not a stale cached bound.
		shape_aabb.grow_by((shape_aabb.size.x + shape_aabb.size.y) * 0.5 * 0.05);
		// Skip the BVH lookup and lock if the proxy bounds are unchanged.
		// The swept AABB and ordinary AABB are cached independently per update.
		const bool aabb_changed = s.aabb_cache != shape_aabb;
		s.aabb_cache = shape_aabb;

		if (s.bpid == 0) {
			// create() already registers the AABB in the requested static/dynamic tree.
			if (defer_pair_checks) {
				s.bpid = space->get_broadphase()->create_deferred(this, i, shape_aabb, _static);
				has_deferred_shapes = true;
			} else {
				s.bpid = space->get_broadphase()->create(this, i, shape_aabb, _static);
			}
		} else if (aabb_changed) {
			space->get_broadphase()->move(s.bpid, shape_aabb);
		}
	}
	if (has_deferred_shapes) {
		space->get_broadphase()->flush_pending_pairs();
	}

}

void GodotCollisionObject2D::_update_shapes_with_motion(const Vector2 &p_motion) {
	if (!space) {
		return;
	}

	// Register compound shapes before generating pair callbacks. A single-shape
	// object retains the synchronous insertion behavior.
	const bool defer_pair_checks = shapes.size() > 1;
	bool has_deferred_shapes = false;

	for (int i = 0; i < (int)shapes.size(); i++) {
		Shape &s = shapes[i];
		if (s.disabled) {
			continue;
		}

		//not quite correct, should compute the next matrix..
		Rect2 shape_aabb = s.shape->get_aabb();
		Transform2D xform = transform * s.xform;
		shape_aabb = xform.xform(shape_aabb);
		shape_aabb = shape_aabb.merge(Rect2(shape_aabb.position + p_motion, shape_aabb.size)); //use motion
		// Skip the BVH lookup and lock if the proxy bounds are unchanged.
		// The swept AABB and ordinary AABB are cached independently per update.
		const bool aabb_changed = s.aabb_cache != shape_aabb;
		s.aabb_cache = shape_aabb;

		if (s.bpid == 0) {
			// create() already registers the AABB in the requested static/dynamic tree.
			if (defer_pair_checks) {
				s.bpid = space->get_broadphase()->create_deferred(this, i, shape_aabb, _static);
				has_deferred_shapes = true;
			} else {
				s.bpid = space->get_broadphase()->create(this, i, shape_aabb, _static);
			}
		} else if (aabb_changed) {
			space->get_broadphase()->move(s.bpid, shape_aabb);
		}
	}
	if (has_deferred_shapes) {
		space->get_broadphase()->flush_pending_pairs();
	}

}

void GodotCollisionObject2D::_set_space(GodotSpace2D *p_space) {
	GodotSpace2D *old_space = space;
	space = p_space;
	++collision_geometry_version;

	if (old_space) {
		old_space->remove_object(this);

		for (int i = 0; i < (int)shapes.size(); i++) {
			Shape &s = shapes[i];
			if (s.bpid) {
				old_space->get_broadphase()->remove(s.bpid);
				s.bpid = 0;
			}
		}
	}

	if (space) {
		space->add_object(this);
		_update_shapes();
	}
}

void GodotCollisionObject2D::_collision_filter_changed() {
	++collision_geometry_version;
	// Layer/mask changes do not alter shape geometry or AABBs.
	if (space) {
		GodotBroadPhase2D *broadphase = space->get_broadphase();
		for (int i = 0; i < shapes.size(); i++) {
			const Shape &shape = shapes[i];
			if (shape.bpid != 0) {
				broadphase->force_collision_check(shape.bpid);
			}
		}
	}
	// Preserve wake-up and area monitoring semantics.
	_shapes_changed();
}

void GodotCollisionObject2D::_shape_changed() {
	++collision_geometry_version;
	_update_shapes();
	_shapes_changed();
}

GodotCollisionObject2D::GodotCollisionObject2D(Type p_type) :
		pending_shape_update_list(this) {
	type = p_type;
}
