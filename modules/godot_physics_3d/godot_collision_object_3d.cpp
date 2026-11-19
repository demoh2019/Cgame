/**************************************************************************/
/*  godot_collision_object_3d.cpp                                         */
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

#include "godot_collision_object_3d.h"
#include "servers/physics_ccd_rotational_bounds.h"
#include "servers/physics_ccd_tight_rotational_bounds.h"
#include "godot_shape_volume_3d.h"

#include "godot_physics_server_3d.h"
#include "godot_space_3d.h"

void GodotCollisionObject3D::add_shape(GodotShape3D *p_shape, const Transform3D &p_transform, bool p_disabled) {
	Shape s;
	s.shape = p_shape;
	s.xform = p_transform;
	s.xform_inv = s.xform.affine_inverse();
	s.bpid = 0; //needs update
	s.disabled = p_disabled;
	shapes.push_back(s);
	p_shape->add_owner(this);
	++collision_geometry_version;

	if (!pending_shape_update_list.in_list()) {
		GodotPhysicsServer3D::godot_singleton->pending_shape_update_list.add(&pending_shape_update_list);
	}
}

void GodotCollisionObject3D::set_shape(int p_index, GodotShape3D *p_shape) {
	ERR_FAIL_INDEX(p_index, shapes.size());
	shapes[p_index].shape->remove_owner(this);
	shapes.write[p_index].shape = p_shape;

	p_shape->add_owner(this);
	++collision_geometry_version;
	if (!pending_shape_update_list.in_list()) {
		GodotPhysicsServer3D::godot_singleton->pending_shape_update_list.add(&pending_shape_update_list);
	}
}

void GodotCollisionObject3D::set_shape_transform(int p_index, const Transform3D &p_transform) {
	ERR_FAIL_INDEX(p_index, shapes.size());

	shapes.write[p_index].xform = p_transform;
	shapes.write[p_index].xform_inv = p_transform.affine_inverse();
	++collision_geometry_version;
	if (!pending_shape_update_list.in_list()) {
		GodotPhysicsServer3D::godot_singleton->pending_shape_update_list.add(&pending_shape_update_list);
	}
}

void GodotCollisionObject3D::set_shape_disabled(int p_idx, bool p_disabled) {
	ERR_FAIL_INDEX(p_idx, shapes.size());

	GodotCollisionObject3D::Shape &shape = shapes.write[p_idx];
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
			GodotPhysicsServer3D::godot_singleton->pending_shape_update_list.add(&pending_shape_update_list);
		}
	} else if (!p_disabled && shape.bpid == 0) {
		if (!pending_shape_update_list.in_list()) {
			GodotPhysicsServer3D::godot_singleton->pending_shape_update_list.add(&pending_shape_update_list);
		}
	}
}

void GodotCollisionObject3D::remove_shape(GodotShape3D *p_shape) {
	//remove a shape, all the times it appears
	for (int i = 0; i < shapes.size(); i++) {
		if (shapes[i].shape == p_shape) {
			remove_shape(i);
			i--;
		}
	}
}

void GodotCollisionObject3D::remove_shape(int p_index) {
	//remove anything from shape to be erased to end, so subindices don't change
	ERR_FAIL_INDEX(p_index, shapes.size());
	for (int i = p_index; i < shapes.size(); i++) {
		if (shapes[i].bpid == 0) {
			continue;
		}
		//should never get here with a null owner
		space->get_broadphase()->remove(shapes[i].bpid);
		shapes.write[i].bpid = 0;
	}
	shapes[p_index].shape->remove_owner(this);
	shapes.remove_at(p_index);
	++collision_geometry_version;

	if (!pending_shape_update_list.in_list()) {
		GodotPhysicsServer3D::godot_singleton->pending_shape_update_list.add(&pending_shape_update_list);
	}
}

void GodotCollisionObject3D::_set_static(bool p_static) {
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

void GodotCollisionObject3D::_unregister_shapes() {
	for (int i = 0; i < shapes.size(); i++) {
		Shape &s = shapes.write[i];
		if (s.bpid > 0) {
			space->get_broadphase()->remove(s.bpid);
			s.bpid = 0;
		}
	}
}

void GodotCollisionObject3D::_update_shapes() {
	if (!space) {
		return;
	}

	// Register compound shapes before generating pair callbacks. A single-shape
	// object retains the synchronous insertion behavior.
	const bool defer_pair_checks = shapes.size() > 1;
	bool has_deferred_shapes = false;

	for (int i = 0; i < shapes.size(); i++) {
		Shape &s = shapes.write[i];
		if (s.disabled) {
			continue;
		}

		//not quite correct, should compute the next matrix..
		AABB shape_aabb = s.shape->get_aabb();
		Transform3D xform = transform * s.xform;
		shape_aabb = xform.xform(shape_aabb);
		// Base the broadphase margin on the current shape, not a stale cached bound.
		shape_aabb.grow_by((shape_aabb.size.x + shape_aabb.size.y) * 0.5 * 0.05);
		// Skip the BVH lookup and lock if the proxy bounds are unchanged.
		// The swept AABB and ordinary AABB are cached independently per update.
		const bool aabb_changed = s.aabb_cache != shape_aabb;
		s.aabb_cache = shape_aabb;

		// A volume scales by abs(det(basis)), including reflected or sheared
		// transforms. Avoid the polar/length decomposition in get_scale() for
		// each moving physics shape during broadphase updates.
		s.area_cache = s.shape->get_volume() * godot_physics_3d_volume_scale(xform.basis);

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

void GodotCollisionObject3D::_update_shapes_with_motion(const Vector3 &p_motion, const Vector3 &p_angular_velocity, real_t p_step, const Vector3 &p_rotation_pivot) {
	if (!space) {
		return;
	}

	// Only opted-in CCD spaces pay for rotational broadphase bounds. Angular
	// displacement is known before the narrowphase and requires no allocations.
	const real_t rotation_factor = space->is_ccd_rotational_bounds_enabled() ?
			godot_physics_ccd_rotational_factor(p_angular_velocity.length() * p_step) : real_t(0.0);

	// Register compound shapes before generating pair callbacks. A single-shape
	// object retains the synchronous insertion behavior.
	const bool defer_pair_checks = shapes.size() > 1;
	bool has_deferred_shapes = false;

	for (int i = 0; i < shapes.size(); i++) {
		Shape &s = shapes.write[i];
		if (s.disabled) {
			continue;
		}

		//not quite correct, should compute the next matrix..
		AABB shape_aabb = s.shape->get_aabb();
		Transform3D xform = transform * s.xform;
		shape_aabb = xform.xform(shape_aabb);
		// Conservative rotational broadphase envelope about the world COM.
		if (rotation_factor > real_t(0.0) && space->is_ccd_tight_rotational_bounds_enabled()) {
			// Evaluate swept extrema of each world AABB corner around the COM,
			// then apply the linear translation envelope conservatively.
			shape_aabb = godot_physics_ccd_tight_rotational_bounds(
					shape_aabb, p_rotation_pivot, p_angular_velocity * p_step, p_motion);
		} else {
			// Preserve the original chord-padding path, including when disabled.
			const real_t rotation_padding = godot_physics_ccd_rotational_padding(shape_aabb, p_rotation_pivot, rotation_factor);
			shape_aabb.merge_with(AABB(shape_aabb.position + p_motion, shape_aabb.size));
			if (rotation_padding > real_t(0.0)) {
				shape_aabb.grow_by(rotation_padding);
			}
		}
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

void GodotCollisionObject3D::_set_space(GodotSpace3D *p_space) {
	GodotSpace3D *old_space = space;
	space = p_space;
	++collision_geometry_version;

	if (old_space) {
		old_space->remove_object(this);

		for (int i = 0; i < shapes.size(); i++) {
			Shape &s = shapes.write[i];
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

void GodotCollisionObject3D::refresh_collision_pairs() {
	if (!space) {
		return;
	}
	GodotBroadPhase3D *broadphase = space->get_broadphase();
	// Single-shape bodies keep the immediate allocation-free path. When a
	// compound object changes filters, aggregate all of its proxy updates
	// into one full BVH recheck rather than traversing after every shape.
	const bool batch = shapes.size() > 1;
	if (batch) {
		broadphase->begin_batch();
	}
	for (int i = 0; i < shapes.size(); i++) {
		const Shape &shape = shapes[i];
		if (shape.bpid != 0) {
			broadphase->force_collision_check(shape.bpid);
		}
	}
	if (batch) {
		broadphase->end_batch();
	}
}

void GodotCollisionObject3D::_collision_filter_changed() {
	++collision_geometry_version;
	// Layer/mask changes still invalidate cached contacts; collision
	// exceptions only require the lighter refresh_collision_pairs() path.
	refresh_collision_pairs();
	// Preserve wake-up and area monitoring semantics.
	_shapes_changed();
}

void GodotCollisionObject3D::_shape_changed() {
	++collision_geometry_version;
	_update_shapes();
	_shapes_changed();
}

GodotCollisionObject3D::GodotCollisionObject3D(Type p_type) :
		pending_shape_update_list(this) {
	type = p_type;
}
