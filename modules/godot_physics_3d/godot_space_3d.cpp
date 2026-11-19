/**************************************************************************/
/*  godot_space_3d.cpp                                                    */
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

#include "godot_space_3d.h"

#include "godot_area_pair_3d.h"
#include "godot_body_pair_3d.h"
#include "godot_collision_solver_3d.h"
#include "godot_physics_server_3d.h"

#include "core/config/project_settings.h"
#include "servers/physics_cast_motion_pruning.h"

#define TEST_MOTION_MARGIN_MIN_VALUE 0.0001
#define TEST_MOTION_MIN_CONTACT_DEPTH_FACTOR 0.05

_FORCE_INLINE_ static bool _can_collide_with(GodotCollisionObject3D *p_object, uint32_t p_collision_mask, bool p_collide_with_bodies, bool p_collide_with_areas) {
	if (!(p_object->get_collision_layer() & p_collision_mask)) {
		return false;
	}

	if (p_object->get_type() == GodotCollisionObject3D::TYPE_AREA && !p_collide_with_areas) {
		return false;
	}

	if (p_object->get_type() == GodotCollisionObject3D::TYPE_BODY && !p_collide_with_bodies) {
		return false;
	}

	if (p_object->get_type() == GodotCollisionObject3D::TYPE_SOFT_BODY && !p_collide_with_bodies) {
		return false;
	}

	return true;
}

int GodotPhysicsDirectSpaceState3D::intersect_point(const PS3DT::PointParameters &p_parameters, PS3DT::ShapeResult *r_results, int p_result_max) {
	ERR_FAIL_COND_V(space->locked, 0);
	if (p_result_max <= 0) {
		return 0;
	}

	// The previous fixed 2048-candidate array could be filled by excluded
	// or masked-out bodies before a matching body was ever examined.
	struct PointQuery {
		const PS3DT::PointParameters &params;
		PS3DT::ShapeResult *results;
		int max_results;
		int count = 0;
	};
	PointQuery query = { p_parameters, r_results, p_result_max };

	auto visitor = [](GodotCollisionObject3D *p_object, int p_shape, void *p_userdata) -> bool {
		PointQuery &data = *static_cast<PointQuery *>(p_userdata);
		if (!_can_collide_with(p_object, data.params.collision_mask, data.params.collide_with_bodies, data.params.collide_with_areas) ||
				data.params.exclude.has(p_object->get_self())) {
			return true;
		}

		// Both inverses are cached and maintained when transforms change.
		// Transforming the point in two steps avoids recomputing the affine
		// inverse of the composed body and shape transforms per candidate.
		const Vector3 local_point = p_object->get_shape_inv_transform(p_shape).xform(p_object->get_inv_transform().xform(data.params.position));
		if (!p_object->get_shape(p_shape)->intersect_point(local_point)) {
			return true;
		}

		PS3DT::ShapeResult &result = data.results[data.count++];
		result.collider_id = p_object->get_instance_id();
		result.rid = p_object->get_self();
		result.shape = p_shape;
		return data.count < data.max_results;
	};

	space->broadphase->visit_point(p_parameters.position, visitor, &query);
	return query.count;
}

bool GodotPhysicsDirectSpaceState3D::intersect_ray(const PS3DT::RayParameters &p_parameters, PS3DT::RayResult &r_result) {
	ERR_FAIL_COND_V(space->locked, false);

	const Vector3 begin = p_parameters.from;
	const Vector3 end = p_parameters.to;
	const Vector3 motion = end - begin;
	const double motion_x = double(motion.x);
	const double motion_y = double(motion.y);
	const double motion_z = double(motion.z);
	const double length_squared = motion_x * motion_x + motion_y * motion_y + motion_z * motion_z;
	if (length_squared == 0.0) {
		return false;
	}

	// Box2D/Jolt-style streaming BVH traversal. The narrowphase callback
	// clips the segment to the nearest exact hit, without a 2048-result cap.
	struct RayCastData {
		const PS3DT::RayParameters &params;
		PS3DT::RayResult &result;
		Vector3 from;
		Vector3 motion;
		double motion_x;
		double motion_y;
		double motion_z;
		double inv_motion_length_squared;
		bool hit = false;
	};
	RayCastData state = { p_parameters, r_result, begin, motion, motion_x, motion_y, motion_z, 1.0 / length_squared };

	auto visitor = [] (GodotCollisionObject3D *object, int p_shape, real_t p_max_fraction, void *p_userdata) -> real_t {
		RayCastData &data = *static_cast<RayCastData *>(p_userdata);
		if (!_can_collide_with(object, data.params.collision_mask, data.params.collide_with_bodies, data.params.collide_with_areas)) {
			return p_max_fraction;
		}
		if (data.params.pick_ray && !object->is_ray_pickable()) {
			return p_max_fraction;
		}
		if (data.params.exclude.has(object->get_self())) {
			return p_max_fraction;
		}

		const Transform3D inv_xform = object->get_shape_inv_transform(p_shape) * object->get_inv_transform();
		const Vector3 local_from = inv_xform.xform(data.from);
		const Vector3 local_to = inv_xform.xform(data.from + data.motion * p_max_fraction);
		const GodotShape3D *shape = object->get_shape(p_shape);

		Vector3 world_point;
		Vector3 world_normal;
		real_t fraction = 0.0;
		int face_index = -1;
		if (shape->intersect_point(local_from)) {
			if (!data.params.hit_from_inside) {
				return p_max_fraction;
			}
			// Hit from inside has no well-defined surface normal or face.
			world_point = data.from;
			world_normal = Vector3();
			fraction = 0.0;
		} else {
			Vector3 shape_point;
			Vector3 shape_normal;
			if (!shape->intersect_segment(local_from, local_to, shape_point, shape_normal, face_index, data.params.hit_back_faces)) {
				return p_max_fraction;
			}
			const Transform3D xform = object->get_transform() * object->get_shape_transform(p_shape);
			world_point = xform.xform(shape_point);
			world_normal = inv_xform.basis.xform_inv(shape_normal).normalized();
			// Calculate the nearest-hit fraction in double: a finite long ray
			// can have a squared length that overflows float32.
			const double hit_x = double(world_point.x) - double(data.from.x);
			const double hit_y = double(world_point.y) - double(data.from.y);
			const double hit_z = double(world_point.z) - double(data.from.z);
			fraction = real_t((data.motion_x * hit_x + data.motion_y * hit_y + data.motion_z * hit_z) * data.inv_motion_length_squared);
		}

		// The broadphase may visit objects in any order. A closer exact hit
		// controls both the result and the clipped ray for subsequent nodes.
		if (!(fraction >= 0.0 && fraction <= p_max_fraction) || (data.hit && fraction >= p_max_fraction)) {
			return p_max_fraction;
		}
		data.hit = true;
		data.result.collider_id = object->get_instance_id();
		data.result.normal = world_normal;
		data.result.position = world_point;
		data.result.rid = object->get_self();
		data.result.shape = p_shape;
		data.result.face_index = face_index;
		return fraction;
	};
	space->broadphase->cast_segment(begin, end, visitor, &state);
	return state.hit;
}

int GodotPhysicsDirectSpaceState3D::intersect_shape(const PS3DT::ShapeParameters &p_parameters, PS3DT::ShapeResult *r_results, int p_result_max) {
	if (p_result_max <= 0) {
		return 0;
	}

	GodotShape3D *shape = GodotPhysicsServer3D::godot_singleton->shape_owner.get_or_null(p_parameters.shape_rid);
	ERR_FAIL_NULL_V(shape, 0);

	// The SAT narrowphase accepts the query shape's collision margin. Its
	// broadphase bounds must conservatively include that margin as well,
	// otherwise near-but-disjoint shapes never reach the exact solver.
	const AABB aabb = p_parameters.transform.xform(shape->get_aabb()).grow(MAX(p_parameters.margin, real_t(0.0)));

	// Consume BVH candidates only after narrowphase has found a real hit.
	struct ShapeQuery {
		const PS3DT::ShapeParameters &params;
		PS3DT::ShapeResult *results;
		GodotShape3D *shape;
		int max_results;
		int count = 0;
	};
	ShapeQuery query = { p_parameters, r_results, shape, p_result_max };
	auto visitor = [](GodotCollisionObject3D *p_object, int p_shape, void *p_userdata) -> bool {
		ShapeQuery &data = *static_cast<ShapeQuery *>(p_userdata);
		if (!_can_collide_with(p_object, data.params.collision_mask, data.params.collide_with_bodies, data.params.collide_with_areas) ||
				data.params.exclude.has(p_object->get_self())) {
			return true;
		}
		if (!GodotCollisionSolver3D::solve_static(data.shape, data.params.transform,
					p_object->get_shape(p_shape), p_object->get_transform() * p_object->get_shape_transform(p_shape),
					nullptr, nullptr, nullptr, data.params.margin, 0)) {
			return true;
		}
		if (data.results) {
			PS3DT::ShapeResult &result = data.results[data.count];
			result.collider_id = p_object->get_instance_id();
			result.rid = p_object->get_self();
			result.shape = p_shape;
		}
		data.count++;
		return data.count < data.max_results;
	};
	space->broadphase->visit_aabb(aabb, visitor, &query);
	return query.count;
}

bool GodotPhysicsDirectSpaceState3D::cast_motion(const PS3DT::ShapeParameters &p_parameters, real_t &p_closest_safe, real_t &p_closest_unsafe, PS3DT::ShapeRestInfo *r_info) {
	GodotShape3D *shape = GodotPhysicsServer3D::godot_singleton->shape_owner.get_or_null(p_parameters.shape_rid);
	ERR_FAIL_NULL_V(shape, false);

	const AABB start_aabb = p_parameters.transform.xform(shape->get_aabb());
	AABB aabb = start_aabb.merge(AABB(start_aabb.position + p_parameters.motion, start_aabb.size)); //motion
	aabb = aabb.grow(p_parameters.margin);

	real_t best_safe = 1;
	real_t best_unsafe = 1;

	Transform3D xform_inv = p_parameters.transform.affine_inverse();
	GodotMotionShape3D mshape;
	mshape.shape = shape;
	mshape.motion = xform_inv.basis.xform(p_parameters.motion);

	bool best_first = true;

	Vector3 motion_normal = p_parameters.motion.normalized();

	Vector3 closest_A, closest_B;

	// Jolt/Box2D-style streaming traversal: rejected proxies must not exhaust
	// the fixed-size candidate array before we find the nearest collision.
	struct CastMotionData {
		const PS3DT::ShapeParameters &params;
		const AABB &query_aabb;
		const AABB &start_aabb;
		AABB clipped_aabb;
		GodotMotionShape3D &motion_shape;
		const Transform3D &xform_inv;
		const Vector3 &motion_normal;
		Vector3 full_motion;
		real_t &best_safe;
		real_t &best_unsafe;
		bool &best_first;
		Vector3 &closest_A;
		Vector3 &closest_B;
		PS3DT::ShapeRestInfo *info;
	};
	CastMotionData data = { p_parameters, aabb, start_aabb, aabb, mshape, xform_inv, motion_normal, mshape.motion,
		best_safe, best_unsafe, best_first, closest_A, closest_B, r_info };
	auto visitor = [](GodotCollisionObject3D *p_object, int p_shape, void *p_userdata) -> bool {
		CastMotionData &data = *static_cast<CastMotionData *>(p_userdata);
		if (!_can_collide_with(p_object, data.params.collision_mask, data.params.collide_with_bodies, data.params.collide_with_areas)) {
			return true;
		}

		if (data.params.exclude.has(p_object->get_self())) {
			return true; //ignore excluded
		}

		// An earlier hit can only be improved by another collider inside
		// the shortened swept bounds. The cached broadphase proxy bounds
		// conservatively cover the current shape and any CCD expansion.
		if (data.best_unsafe < 1.0 &&
				!data.clipped_aabb.intersects(p_object->get_shape_aabb(p_shape))) {
			return true;
		}

		const GodotCollisionObject3D *col_obj = p_object;
		int shape_idx = p_shape;

		Vector3 point_A, point_B;
		Vector3 sep_axis = data.motion_normal;

		Transform3D col_obj_xform = col_obj->get_transform() * col_obj->get_shape_transform(shape_idx);
		// Binary-search fractions modify the sweep; restore full motion for each new candidate.
		data.motion_shape.motion = data.full_motion;
		//test initial overlap, does it collide if going all the way?
		if (GodotCollisionSolver3D::solve_distance(&data.motion_shape, data.params.transform, col_obj->get_shape(shape_idx), col_obj_xform, point_A, point_B, data.query_aabb, &sep_axis)) {
			return true;
		}

		//test initial overlap, ignore objects it's inside of.
		sep_axis = data.motion_normal;

		if (!GodotCollisionSolver3D::solve_distance(data.motion_shape.shape, data.params.transform, col_obj->get_shape(shape_idx), col_obj_xform, point_A, point_B, data.query_aabb, &sep_axis)) {
			return true;
		}

		//just do kinematic solving
		real_t low = 0.0;
		real_t hi = 1.0;
		real_t fraction_coeff = 0.5;
		for (int j = 0; j < 8; j++) { //steps should be customizable..
			real_t fraction = low + (hi - low) * fraction_coeff;

			data.motion_shape.motion = data.full_motion * fraction;

			Vector3 lA, lB;
			Vector3 sep = data.motion_normal; //important optimization for this to work fast enough
			bool collided = !GodotCollisionSolver3D::solve_distance(&data.motion_shape, data.params.transform, col_obj->get_shape(shape_idx), col_obj_xform, lA, lB, data.query_aabb, &sep);

			if (collided) {
				hi = fraction;
				if ((j == 0) || (low > 0.0)) { // Did it not collide before?
					// When alternating or first iteration, use dichotomy.
					fraction_coeff = 0.5;
				} else {
					// When colliding again, converge faster towards low fraction
					// for more accurate results with long motions that collide near the start.
					fraction_coeff = 0.25;
				}
			} else {
				point_A = lA;
				point_B = lB;
				low = fraction;
				if ((j == 0) || (hi < 1.0)) { // Did it collide before?
					// When alternating or first iteration, use dichotomy.
					fraction_coeff = 0.5;
				} else {
					// When not colliding again, converge faster towards high fraction
					// for more accurate results with long motions that collide near the end.
					fraction_coeff = 0.75;
				}
			}
		}

		if (low < data.best_safe) {
			data.best_first = true; //force reset
			data.best_safe = low;
			data.best_unsafe = hi;
			data.clipped_aabb = godot_physics_cast_motion_clipped_aabb(data.start_aabb,
					data.params.motion, data.best_unsafe, data.params.margin);
		}

		if (data.info && (data.best_first || (point_A.distance_squared_to(point_B) < data.closest_A.distance_squared_to(data.closest_B) && low <= data.best_safe))) {
			data.closest_A = point_A;
			data.closest_B = point_B;
			data.info->collider_id = col_obj->get_instance_id();
			data.info->rid = col_obj->get_self();
			data.info->shape = shape_idx;
			data.info->point = data.closest_B;
			data.info->normal = (data.closest_A - data.closest_B).normalized();
			data.best_first = false;
			if (col_obj->get_type() == GodotCollisionObject3D::TYPE_BODY) {
				const GodotBody3D *body = static_cast<const GodotBody3D *>(col_obj);
				Vector3 rel_vec = data.closest_B - (body->get_transform().origin + body->get_center_of_mass());
				data.info->linear_velocity = body->get_linear_velocity() + (body->get_angular_velocity()).cross(rel_vec);
			}
		}
		return true;
	};
	space->broadphase->visit_aabb(aabb, visitor, &data);

	p_closest_safe = best_safe;
	p_closest_unsafe = best_unsafe;

	return true;
}

bool GodotPhysicsDirectSpaceState3D::collide_shape(const PS3DT::ShapeParameters &p_parameters, Vector3 *r_results, int p_result_max, int &r_result_count) {
	if (p_result_max <= 0) {
		return false;
	}
	GodotShape3D *shape = GodotPhysicsServer3D::godot_singleton->shape_owner.get_or_null(p_parameters.shape_rid);
	ERR_FAIL_NULL_V(shape, false);

	AABB aabb = p_parameters.transform.xform(shape->get_aabb());
	aabb = aabb.grow(p_parameters.margin);

	GodotPhysicsServer3D::CollCbkData cbk;
	cbk.max = p_result_max;
	cbk.amount = 0;
	cbk.ptr = r_results;
	struct CollisionQuery {
		const PS3DT::ShapeParameters &params;
		GodotShape3D *shape;
		GodotPhysicsServer3D::CollCbkData &callback;
		bool collided = false;
	};
	CollisionQuery query = { p_parameters, shape, cbk };
	auto visitor = [](GodotCollisionObject3D *p_object, int p_shape, void *p_userdata) -> bool {
		CollisionQuery &data = *static_cast<CollisionQuery *>(p_userdata);
		if (!_can_collide_with(p_object, data.params.collision_mask, data.params.collide_with_bodies, data.params.collide_with_areas) ||
				data.params.exclude.has(p_object->get_self())) {
			return true;
		}
		if (GodotCollisionSolver3D::solve_static(data.shape, data.params.transform,
					p_object->get_shape(p_shape), p_object->get_transform() * p_object->get_shape_transform(p_shape),
					GodotPhysicsServer3D::_shape_col_cbk, &data.callback, nullptr, data.params.margin)) {
			data.collided = true;
		}
		return data.callback.amount < data.callback.max;
	};
	space->broadphase->visit_aabb(aabb, visitor, &query);
	r_result_count = cbk.amount;
	return query.collided;
}

struct _RestResultData {
	const GodotCollisionObject3D *object = nullptr;
	int local_shape = 0;
	int shape = 0;
	Vector3 contact;
	Vector3 normal;
	real_t len = 0.0;
};

struct _RestCallbackData {
	const GodotCollisionObject3D *object = nullptr;
	int local_shape = 0;
	int shape = 0;

	real_t min_allowed_depth = 0.0;

	_RestResultData best_result;

	int max_results = 0;
	int result_count = 0;
	_RestResultData *other_results = nullptr;
};

static void _rest_cbk_result(const Vector3 &p_point_A, int p_index_A, const Vector3 &p_point_B, int p_index_B, const Vector3 &normal, void *p_userdata) {
	_RestCallbackData *rd = static_cast<_RestCallbackData *>(p_userdata);

	Vector3 contact_rel = p_point_B - p_point_A;
	real_t len = contact_rel.length();
	if (len < rd->min_allowed_depth) {
		return;
	}

	bool is_best_result = (len > rd->best_result.len);

	if (rd->other_results && rd->result_count > 0) {
		// Consider as new result by default.
		int prev_result_count = rd->result_count++;

		int result_index = 0;
		real_t tested_len = is_best_result ? rd->best_result.len : len;
		for (; result_index < prev_result_count - 1; ++result_index) {
			if (tested_len > rd->other_results[result_index].len) {
				// Reusing a previous result.
				rd->result_count--;
				break;
			}
		}

		if (result_index < rd->max_results - 1) {
			_RestResultData &result = rd->other_results[result_index];

			if (is_best_result) {
				// Keep the previous best result as separate result.
				result = rd->best_result;
			} else {
				// Keep this result as separate result.
				result.len = len;
				result.contact = p_point_B;
				result.normal = normal;
				result.object = rd->object;
				result.shape = rd->shape;
				result.local_shape = rd->local_shape;
			}
		} else {
			// Discarding this result.
			rd->result_count--;
		}
	} else if (is_best_result) {
		rd->result_count = 1;
	}

	if (!is_best_result) {
		return;
	}

	rd->best_result.len = len;
	rd->best_result.contact = p_point_B;
	rd->best_result.normal = normal;
	rd->best_result.object = rd->object;
	rd->best_result.shape = rd->shape;
	rd->best_result.local_shape = rd->local_shape;
}

bool GodotPhysicsDirectSpaceState3D::rest_info(const PS3DT::ShapeParameters &p_parameters, PS3DT::ShapeRestInfo *r_info) {
	GodotShape3D *shape = GodotPhysicsServer3D::godot_singleton->shape_owner.get_or_null(p_parameters.shape_rid);
	ERR_FAIL_NULL_V(shape, false);

	const real_t margin = MAX(p_parameters.margin, TEST_MOTION_MARGIN_MIN_VALUE);
	AABB aabb = p_parameters.transform.xform(shape->get_aabb());
	aabb = aabb.grow(margin);

	_RestCallbackData rcd;
	const real_t motion_length = p_parameters.motion.length();
	const real_t min_contact_depth = margin * TEST_MOTION_MIN_CONTACT_DEPTH_FACTOR;
	rcd.min_allowed_depth = MIN(motion_length, min_contact_depth);

	struct RestQuery {
		const PS3DT::ShapeParameters &params;
		GodotShape3D *shape;
		_RestCallbackData &callback;
		real_t margin;
	};
	RestQuery query = { p_parameters, shape, rcd, margin };
	auto visitor = [](GodotCollisionObject3D *p_object, int p_shape, void *p_userdata) -> bool {
		RestQuery &data = *static_cast<RestQuery *>(p_userdata);
		if (!_can_collide_with(p_object, data.params.collision_mask, data.params.collide_with_bodies, data.params.collide_with_areas) ||
				data.params.exclude.has(p_object->get_self())) {
			return true;
		}
		data.callback.object = p_object;
		data.callback.shape = p_shape;
		GodotCollisionSolver3D::solve_static(data.shape, data.params.transform,
				p_object->get_shape(p_shape), p_object->get_transform() * p_object->get_shape_transform(p_shape),
				_rest_cbk_result, &data.callback, nullptr, data.margin);
		return true;
	};
	// A rest contact is the best of ALL exact contacts, not only the first
	// 2048 broadphase candidates (which may all be excluded by the mask).
	space->broadphase->visit_aabb(aabb, visitor, &query);

	if (rcd.best_result.len == 0 || !rcd.best_result.object) {
		return false;
	}

	r_info->collider_id = rcd.best_result.object->get_instance_id();
	r_info->shape = rcd.best_result.shape;
	r_info->normal = rcd.best_result.normal;
	r_info->point = rcd.best_result.contact;
	r_info->rid = rcd.best_result.object->get_self();
	if (rcd.best_result.object->get_type() == GodotCollisionObject3D::TYPE_BODY) {
		const GodotBody3D *body = static_cast<const GodotBody3D *>(rcd.best_result.object);
		Vector3 rel_vec = rcd.best_result.contact - (body->get_transform().origin + body->get_center_of_mass());
		r_info->linear_velocity = body->get_linear_velocity() + (body->get_angular_velocity()).cross(rel_vec);
	} else {
		r_info->linear_velocity = Vector3();
	}
	return true;
}

Vector3 GodotPhysicsDirectSpaceState3D::get_closest_point_to_object_volume(RID p_object, const Vector3 p_point) const {
	GodotCollisionObject3D *obj = GodotPhysicsServer3D::godot_singleton->area_owner.get_or_null(p_object);
	if (!obj) {
		obj = GodotPhysicsServer3D::godot_singleton->body_owner.get_or_null(p_object);
	}
	ERR_FAIL_NULL_V(obj, Vector3());

	ERR_FAIL_COND_V(obj->get_space() != space, Vector3());

	real_t min_distance = 1e20;
	Vector3 min_point;

	bool shapes_found = false;

	for (int i = 0; i < obj->get_shape_count(); i++) {
		if (obj->is_shape_disabled(i)) {
			continue;
		}

		Transform3D shape_xform = obj->get_transform() * obj->get_shape_transform(i);
		GodotShape3D *shape = obj->get_shape(i);

		Vector3 point = shape->get_closest_point_to(shape_xform.affine_inverse().xform(p_point));
		point = shape_xform.xform(point);

		real_t dist = point.distance_to(p_point);
		if (dist < min_distance) {
			min_distance = dist;
			min_point = point;
		}
		shapes_found = true;
	}

	if (!shapes_found) {
		return obj->get_transform().origin; //no shapes found, use distance to origin.
	} else {
		return min_point;
	}
}

GodotPhysicsDirectSpaceState3D::GodotPhysicsDirectSpaceState3D() {
	space = nullptr;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

template <typename Visitor>
void GodotSpace3D::_visit_motion_candidates(GodotBody3D *p_body, const AABB &p_aabb, const PS3DT::MotionParameters &p_parameters, const Visitor &p_callback) {
	// Traverse the broadphase directly. A dense compound shape should not
	// require a per-space allocation proportional to the number of proxies.
	struct MotionVisit {
		GodotBody3D *body;
		const PS3DT::MotionParameters &params;
		const Visitor &callback;
	};
	MotionVisit data = { p_body, p_parameters, p_callback };
	auto visitor = [](GodotCollisionObject3D *p_object, int p_subindex, void *p_userdata) -> bool {
		MotionVisit &query = *static_cast<MotionVisit *>(p_userdata);
		if (p_object == query.body || p_object->get_type() != GodotCollisionObject3D::TYPE_BODY) {
			return true;
		}
		if (query.params.exclude_bodies.has(p_object->get_self()) ||
				query.params.exclude_objects.has(p_object->get_instance_id())) {
			return true;
		}
		GodotBody3D *other = static_cast<GodotBody3D *>(p_object);
		if (!query.body->collides_with(other) ||
				other->has_exception(query.body->get_self()) ||
				query.body->has_exception(other->get_self())) {
			return true;
		}
		return query.callback(p_object, p_subindex);
	};
	broadphase->visit_aabb(p_aabb, visitor, &data);
}

bool GodotSpace3D::test_body_motion(GodotBody3D *p_body, const PS3DT::MotionParameters &p_parameters, PS3DT::MotionResult *r_result) {
	//give me back regular physics engine logic
	//this is madness
	//and most people using this function will think
	//what it does is simpler than using physics
	//this took about a week to get right..
	//but is it right? who knows at this point..

	ERR_FAIL_COND_V(p_parameters.max_collisions < 0 || p_parameters.max_collisions > PS3DT::MotionResult::MAX_COLLISIONS, false);

	if (r_result) {
		*r_result = PS3DT::MotionResult();
	}

	AABB body_aabb;
	bool shapes_found = false;

	for (int i = 0; i < p_body->get_shape_count(); i++) {
		if (p_body->is_shape_disabled(i)) {
			continue;
		}

		if (!shapes_found) {
			body_aabb = p_body->get_shape_aabb(i);
			shapes_found = true;
		} else {
			body_aabb = body_aabb.merge(p_body->get_shape_aabb(i));
		}
	}

	if (!shapes_found) {
		if (r_result) {
			r_result->travel = p_parameters.motion;
		}

		return false;
	}

	real_t margin = MAX(p_parameters.margin, TEST_MOTION_MARGIN_MIN_VALUE);

	// Undo the currently transform the physics server is aware of and apply the provided one
	body_aabb = p_parameters.from.xform(p_body->get_inv_transform().xform(body_aabb));
	body_aabb = body_aabb.grow(margin);

	real_t min_contact_depth = margin * TEST_MOTION_MIN_CONTACT_DEPTH_FACTOR;

	const real_t motion_length = p_parameters.motion.length();
	// Stationary recovery queries must not divide by zero.
	const Vector3 motion_normal = motion_length > 0.0 ? p_parameters.motion / motion_length : Vector3();

	Transform3D body_transform = p_parameters.from;

	bool recovered = false;

	{
		//STEP 1, FREE BODY IF STUCK

		const int max_results = 32;
		int recover_attempts = 4;
		Vector3 sr[max_results * 2];
		real_t priorities[max_results];

		do {
			GodotPhysicsServer3D::CollCbkData cbk;
			cbk.max = max_results;
			cbk.amount = 0;
			cbk.ptr = sr;

			GodotPhysicsServer3D::CollCbkData *cbkptr = &cbk;
			GodotCollisionSolver3D::CallbackResult cbkres = GodotPhysicsServer3D::_shape_col_cbk;
			int priority_amount = 0;

			bool collided = false;

			for (int j = 0; j < p_body->get_shape_count(); j++) {
				if (p_body->is_shape_disabled(j)) {
					continue;
				}

				Transform3D body_shape_xform = body_transform * p_body->get_shape_transform(j);
				GodotShape3D *body_shape = p_body->get_shape(j);
				// Jolt/Box2D-style shape-level broadphase query: a distant shape
				// in the same compound body must not widen this collision test.
				const AABB shape_query_aabb = body_shape_xform.xform(body_shape->get_aabb()).grow(margin);

				_visit_motion_candidates(p_body, shape_query_aabb, p_parameters, [&](const GodotCollisionObject3D *col_obj, int shape_idx) -> bool {

					if (GodotCollisionSolver3D::solve_static(body_shape, body_shape_xform, col_obj->get_shape(shape_idx), col_obj->get_transform() * col_obj->get_shape_transform(shape_idx), cbkres, cbkptr, nullptr, margin)) {
						collided = cbk.amount > 0;
					}
					while (cbk.amount > priority_amount) {
						priorities[priority_amount] = col_obj->get_collision_priority();
						priority_amount++;
					}
				
				return true;
			});
			}

			if (!collided) {
				break;
			}

			real_t inv_total_weight = 0.0;
			for (int i = 0; i < cbk.amount; i++) {
				inv_total_weight += priorities[i];
			}
			inv_total_weight = Math::is_zero_approx(inv_total_weight) ? 1.0 : (real_t)cbk.amount / inv_total_weight;

			recovered = true;

			Vector3 recover_motion;
			for (int i = 0; i < cbk.amount; i++) {
				Vector3 a = sr[i * 2 + 0];
				Vector3 b = sr[i * 2 + 1];

				// Compute plane on b towards a.
				Vector3 n = (a - b).normalized();
				real_t d = n.dot(b);

				// Compute depth on recovered motion.
				real_t depth = n.dot(a + recover_motion) - d;
				if (depth > min_contact_depth + CMP_EPSILON) {
					// Only recover if there is penetration.
					recover_motion -= n * (depth - min_contact_depth) * 0.4 * priorities[i] * inv_total_weight;
				}
			}

			if (recover_motion == Vector3()) {
				collided = false;
				break;
			}

			body_transform.origin += recover_motion;
			body_aabb.position += recover_motion;

			recover_attempts--;

		} while (recover_attempts);
	}

	real_t safe = 1.0;
	real_t unsafe = 1.0;
	int best_shape = -1;

	{
		// STEP 2 ATTEMPT MOTION

		for (int j = 0; j < p_body->get_shape_count(); j++) {
			if (p_body->is_shape_disabled(j)) {
				continue;
			}

			GodotShape3D *body_shape = p_body->get_shape(j);

			// Colliding separation rays allows to properly snap to the ground,
			// otherwise it's not needed in regular motion.
			if (!p_parameters.collide_separation_ray && (body_shape->get_type() == PS3DE::SHAPE_SEPARATION_RAY)) {
				// When slide on slope is on, separation ray shape acts like a regular shape.
				if (!static_cast<GodotSeparationRayShape3D *>(body_shape)->get_slide_on_slope()) {
					continue;
				}
			}

			Transform3D body_shape_xform = body_transform * p_body->get_shape_transform(j);

			Transform3D body_shape_xform_inv = body_shape_xform.affine_inverse();
			GodotMotionShape3D mshape;
			mshape.shape = body_shape;
			const Vector3 full_motion_local = body_shape_xform_inv.basis.xform(p_parameters.motion);
			mshape.motion = full_motion_local;

			bool stuck = false;

			real_t best_safe = 1;
			real_t best_unsafe = 1;

			// Sweep the current shape's tight AABB and use the same conservative
			// world-space hint for concave-mesh triangle culling in solve_distance.
			// A large compound AABB would otherwise traverse unrelated triangles.
			AABB shape_motion_aabb = body_shape_xform.xform(body_shape->get_aabb()).grow(margin);
			AABB shape_end_aabb = shape_motion_aabb;
			shape_end_aabb.position += p_parameters.motion;
			shape_motion_aabb = shape_motion_aabb.merge(shape_end_aabb);

			_visit_motion_candidates(p_body, shape_motion_aabb, p_parameters, [&](const GodotCollisionObject3D *col_obj, int shape_idx) -> bool {

				//test initial overlap, does it collide if going all the way?
				Vector3 point_A, point_B;
				Vector3 sep_axis = motion_normal;

				Transform3D col_obj_xform = col_obj->get_transform() * col_obj->get_shape_transform(shape_idx);
				// The preceding candidate's binary search changes this sweep length.
				// Restore the full displacement before testing the next obstacle.
				mshape.motion = full_motion_local;
				//test initial overlap, does it collide if going all the way?
				if (GodotCollisionSolver3D::solve_distance(&mshape, body_shape_xform, col_obj->get_shape(shape_idx), col_obj_xform, point_A, point_B, shape_motion_aabb, &sep_axis)) {
					return true;
				}
				sep_axis = motion_normal;

				if (!GodotCollisionSolver3D::solve_distance(body_shape, body_shape_xform, col_obj->get_shape(shape_idx), col_obj_xform, point_A, point_B, shape_motion_aabb, &sep_axis)) {
					stuck = true;
					return false;
				}

				//just do kinematic solving
				real_t low = 0.0;
				real_t hi = 1.0;
				real_t fraction_coeff = 0.5;
				for (int k = 0; k < 8; k++) { //steps should be customizable..
					real_t fraction = low + (hi - low) * fraction_coeff;

					// A basis transform is linear: reuse the swept vector already
					// computed for this shape rather than repeating a matrix-vector
					// multiply on every CCD/dichotomy iteration and candidate.
					mshape.motion = full_motion_local * fraction;

					Vector3 lA, lB;
					Vector3 sep = motion_normal; //important optimization for this to work fast enough
					bool collided = !GodotCollisionSolver3D::solve_distance(&mshape, body_shape_xform, col_obj->get_shape(shape_idx), col_obj_xform, lA, lB, shape_motion_aabb, &sep);

					if (collided) {
						hi = fraction;
						if ((k == 0) || (low > 0.0)) { // Did it not collide before?
							// When alternating or first iteration, use dichotomy.
							fraction_coeff = 0.5;
						} else {
							// When colliding again, converge faster towards low fraction
							// for more accurate results with long motions that collide near the start.
							fraction_coeff = 0.25;
						}
					} else {
						point_A = lA;
						point_B = lB;
						low = fraction;
						if ((k == 0) || (hi < 1.0)) { // Did it collide before?
							// When alternating or first iteration, use dichotomy.
							fraction_coeff = 0.5;
						} else {
							// When not colliding again, converge faster towards high fraction
							// for more accurate results with long motions that collide near the end.
							fraction_coeff = 0.75;
						}
					}
				}

				if (low < best_safe) {
					best_safe = low;
					best_unsafe = hi;
				}
			
				return true;
			});

			if (stuck) {
				safe = 0;
				unsafe = 0;
				best_shape = j; //sadly it's the best
				break;
			}
			if (best_safe == 1.0) {
				continue;
			}
			if (best_safe < safe) {
				safe = best_safe;
				unsafe = best_unsafe;
				best_shape = j;
			}
		}
	}

	bool collided = false;
	if ((p_parameters.recovery_as_collision && recovered) || (safe < 1)) {
		if (safe >= 1) {
			best_shape = -1; //no best shape with cast, reset to -1
		}

		//it collided, let's get the rest info in unsafe advance
		Transform3D ugt = body_transform;
		ugt.origin += p_parameters.motion * unsafe;

		_RestResultData results[PS3DT::MotionResult::MAX_COLLISIONS];

		_RestCallbackData rcd;
		if (p_parameters.max_collisions > 1) {
			rcd.max_results = p_parameters.max_collisions;
			rcd.other_results = results;
		}

		// Allowed depth can't be lower than motion length, in order to handle contacts at low speed.
		rcd.min_allowed_depth = MIN(motion_length, min_contact_depth);

		body_aabb.position += p_parameters.motion * unsafe;
		int from_shape = best_shape != -1 ? best_shape : 0;
		int to_shape = best_shape != -1 ? best_shape + 1 : p_body->get_shape_count();

		for (int j = from_shape; j < to_shape; j++) {
			if (p_body->is_shape_disabled(j)) {
				continue;
			}

			Transform3D body_shape_xform = ugt * p_body->get_shape_transform(j);
			GodotShape3D *body_shape = p_body->get_shape(j);
			const AABB shape_rest_aabb = body_shape_xform.xform(body_shape->get_aabb()).grow(margin);

			_visit_motion_candidates(p_body, shape_rest_aabb, p_parameters, [&](const GodotCollisionObject3D *col_obj, int shape_idx) -> bool {

				rcd.object = col_obj;
				rcd.shape = shape_idx;
				rcd.local_shape = j;
				bool sc = GodotCollisionSolver3D::solve_static(body_shape, body_shape_xform, col_obj->get_shape(shape_idx), col_obj->get_transform() * col_obj->get_shape_transform(shape_idx), _rest_cbk_result, &rcd, nullptr, margin);
				if (!sc) {
					return true;
				}
			
				return true;
			});
		}

		if (rcd.result_count > 0) {
			if (r_result) {
				for (int collision_index = 0; collision_index < rcd.result_count; ++collision_index) {
					const _RestResultData &result = (collision_index > 0) ? rcd.other_results[collision_index - 1] : rcd.best_result;

					PS3DT::MotionCollision &collision = r_result->collisions[collision_index];

					collision.collider = result.object->get_self();
					collision.collider_id = result.object->get_instance_id();
					collision.collider_shape = result.shape;
					collision.local_shape = result.local_shape;
					collision.normal = result.normal;
					collision.position = result.contact;
					collision.depth = result.len;

					const GodotBody3D *body = static_cast<const GodotBody3D *>(result.object);

					Vector3 rel_vec = result.contact - (body->get_transform().origin + body->get_center_of_mass());
					collision.collider_velocity = body->get_linear_velocity() + (body->get_angular_velocity()).cross(rel_vec);
					collision.collider_angular_velocity = body->get_angular_velocity();
				}

				r_result->travel = safe * p_parameters.motion;
				r_result->remainder = p_parameters.motion - safe * p_parameters.motion;
				r_result->travel += (body_transform.get_origin() - p_parameters.from.get_origin());

				r_result->collision_safe_fraction = safe;
				r_result->collision_unsafe_fraction = unsafe;

				r_result->collision_count = rcd.result_count;
				r_result->collision_depth = rcd.best_result.len;
			}

			collided = true;
		}
	}

	if (!collided && r_result) {
		r_result->travel = p_parameters.motion;
		r_result->remainder = Vector3();
		r_result->travel += (body_transform.get_origin() - p_parameters.from.get_origin());

		r_result->collision_safe_fraction = 1.0;
		r_result->collision_unsafe_fraction = 1.0;
		r_result->collision_depth = 0.0;
	}

	return collided;
}

// Assumes a valid collision pair, this should have been checked beforehand in the BVH or octree.
void *GodotSpace3D::_broadphase_pair(GodotCollisionObject3D *A, int p_subindex_A, GodotCollisionObject3D *B, int p_subindex_B, void *p_self) {
	GodotCollisionObject3D::Type type_A = A->get_type();
	GodotCollisionObject3D::Type type_B = B->get_type();
	if (type_A > type_B) {
		SWAP(A, B);
		SWAP(p_subindex_A, p_subindex_B);
		SWAP(type_A, type_B);
	}

	GodotSpace3D *self = static_cast<GodotSpace3D *>(p_self);

	self->collision_pairs++;

	if (type_A == GodotCollisionObject3D::TYPE_AREA) {
		GodotArea3D *area = static_cast<GodotArea3D *>(A);
		if (type_B == GodotCollisionObject3D::TYPE_AREA) {
			GodotArea3D *area_b = static_cast<GodotArea3D *>(B);
			return self->area2_pair_pool.alloc(area_b, p_subindex_B, area, p_subindex_A);
		} else if (type_B == GodotCollisionObject3D::TYPE_SOFT_BODY) {
			GodotSoftBody3D *softbody = static_cast<GodotSoftBody3D *>(B);
			return self->area_soft_body_pair_pool.alloc(softbody, p_subindex_B, area, p_subindex_A);
		} else {
			GodotBody3D *body = static_cast<GodotBody3D *>(B);
			return self->area_pair_pool.alloc(body, p_subindex_B, area, p_subindex_A);
		}
	} else if (type_A == GodotCollisionObject3D::TYPE_BODY) {
		if (type_B == GodotCollisionObject3D::TYPE_SOFT_BODY) {
			return self->body_soft_body_pair_pool.alloc(static_cast<GodotBody3D *>(A), p_subindex_A, static_cast<GodotSoftBody3D *>(B));
		} else {
			return self->body_pair_pool.alloc(static_cast<GodotBody3D *>(A), p_subindex_A, static_cast<GodotBody3D *>(B), p_subindex_B);
		}
	} else {
		// Soft Body/Soft Body, not supported.
	}

	return nullptr;
}

void GodotSpace3D::_broadphase_unpair(GodotCollisionObject3D *A, int p_subindex_A, GodotCollisionObject3D *B, int p_subindex_B, void *p_data, void *p_self) {
	if (!p_data) {
		return;
	}

	GodotSpace3D *self = static_cast<GodotSpace3D *>(p_self);
	self->collision_pairs--;

	// Return the pair to the pool it came from; the pair type is fully
	// determined by the object types, exactly as in `_broadphase_pair`.
	GodotCollisionObject3D::Type type_A = A->get_type();
	GodotCollisionObject3D::Type type_B = B->get_type();
	if (type_A > type_B) {
		SWAP(type_A, type_B);
	}

	if (type_A == GodotCollisionObject3D::TYPE_AREA) {
		if (type_B == GodotCollisionObject3D::TYPE_AREA) {
			self->area2_pair_pool.free(static_cast<GodotArea2Pair3D *>(p_data));
		} else if (type_B == GodotCollisionObject3D::TYPE_SOFT_BODY) {
			self->area_soft_body_pair_pool.free(static_cast<GodotAreaSoftBodyPair3D *>(p_data));
		} else {
			self->area_pair_pool.free(static_cast<GodotAreaPair3D *>(p_data));
		}
	} else if (type_B == GodotCollisionObject3D::TYPE_SOFT_BODY) {
		self->body_soft_body_pair_pool.free(static_cast<GodotBodySoftBodyPair3D *>(p_data));
	} else {
		self->body_pair_pool.free(static_cast<GodotBodyPair3D *>(p_data));
	}
}

const SelfList<GodotBody3D>::List &GodotSpace3D::get_active_body_list() const {
	return active_list;
}

const LocalVector<GodotBody3D *> &GodotSpace3D::get_active_bodies() {
	if (active_snapshot_version != active_list_version) {
		active_snapshot.clear();
		for (const SelfList<GodotBody3D> *b = active_list.first(); b; b = b->next()) {
			active_snapshot.push_back(b->self());
		}
		active_snapshot_version = active_list_version;
	}
	return active_snapshot;
}

void GodotSpace3D::body_add_to_active_list(SelfList<GodotBody3D> *p_body) {
	active_list.add(p_body);
	active_list_version++;
}

void GodotSpace3D::body_remove_from_active_list(SelfList<GodotBody3D> *p_body) {
	active_list.remove(p_body);
	active_list_version++;
}

void GodotSpace3D::body_add_to_mass_properties_update_list(SelfList<GodotBody3D> *p_body) {
	mass_properties_update_list.add(p_body);
}

void GodotSpace3D::body_remove_from_mass_properties_update_list(SelfList<GodotBody3D> *p_body) {
	mass_properties_update_list.remove(p_body);
}

GodotBroadPhase3D *GodotSpace3D::get_broadphase() {
	return broadphase;
}

void GodotSpace3D::add_object(GodotCollisionObject3D *p_object) {
	ERR_FAIL_COND(objects.has(p_object));
	objects.insert(p_object);
}

void GodotSpace3D::remove_object(GodotCollisionObject3D *p_object) {
	ERR_FAIL_COND(!objects.has(p_object));
	objects.erase(p_object);
}

const HashSet<GodotCollisionObject3D *> &GodotSpace3D::get_objects() const {
	return objects;
}

void GodotSpace3D::body_add_to_state_query_list(SelfList<GodotBody3D> *p_body) {
	state_query_list.add(p_body);
}

void GodotSpace3D::body_remove_from_state_query_list(SelfList<GodotBody3D> *p_body) {
	state_query_list.remove(p_body);
}

void GodotSpace3D::area_add_to_monitor_query_list(SelfList<GodotArea3D> *p_area) {
	monitor_query_list.add(p_area);
}

void GodotSpace3D::area_remove_from_monitor_query_list(SelfList<GodotArea3D> *p_area) {
	monitor_query_list.remove(p_area);
}

void GodotSpace3D::area_add_to_moved_list(SelfList<GodotArea3D> *p_area) {
	area_moved_list.add(p_area);
}

void GodotSpace3D::area_remove_from_moved_list(SelfList<GodotArea3D> *p_area) {
	area_moved_list.remove(p_area);
}

const SelfList<GodotArea3D>::List &GodotSpace3D::get_moved_area_list() const {
	return area_moved_list;
}

const SelfList<GodotSoftBody3D>::List &GodotSpace3D::get_active_soft_body_list() const {
	return active_soft_body_list;
}

void GodotSpace3D::soft_body_add_to_active_list(SelfList<GodotSoftBody3D> *p_soft_body) {
	active_soft_body_list.add(p_soft_body);
}

void GodotSpace3D::soft_body_remove_from_active_list(SelfList<GodotSoftBody3D> *p_soft_body) {
	active_soft_body_list.remove(p_soft_body);
}

void GodotSpace3D::call_queries() {
	while (state_query_list.first()) {
		GodotBody3D *b = state_query_list.first()->self();
		state_query_list.remove(state_query_list.first());
		b->call_queries();
	}

	while (monitor_query_list.first()) {
		GodotArea3D *a = monitor_query_list.first()->self();
		monitor_query_list.remove(monitor_query_list.first());
		a->call_queries();
	}
}

void GodotSpace3D::setup() {
	contact_debug_count = 0;
	while (mass_properties_update_list.first()) {
		mass_properties_update_list.first()->self()->update_mass_properties();
		mass_properties_update_list.remove(mass_properties_update_list.first());
	}
}

void GodotSpace3D::update() {
	broadphase->update();
}

void GodotSpace3D::set_param(PS3DE::SpaceParameter p_param, real_t p_value) {
	switch (p_param) {
		case PS3DE::SPACE_PARAM_CONTACT_RECYCLE_RADIUS:
			contact_recycle_radius = p_value;
			break;
		case PS3DE::SPACE_PARAM_CONTACT_MAX_SEPARATION:
			contact_max_separation = p_value;
			break;
		case PS3DE::SPACE_PARAM_CONTACT_MAX_ALLOWED_PENETRATION:
			contact_max_allowed_penetration = p_value;
			break;
		case PS3DE::SPACE_PARAM_CONTACT_DEFAULT_BIAS:
			contact_bias = p_value;
			break;
		case PS3DE::SPACE_PARAM_BODY_LINEAR_VELOCITY_SLEEP_THRESHOLD:
			body_linear_velocity_sleep_threshold = p_value;
			break;
		case PS3DE::SPACE_PARAM_BODY_ANGULAR_VELOCITY_SLEEP_THRESHOLD:
			body_angular_velocity_sleep_threshold = p_value;
			break;
		case PS3DE::SPACE_PARAM_BODY_TIME_TO_SLEEP:
			body_time_to_sleep = p_value;
			break;
		case PS3DE::SPACE_PARAM_SOLVER_ITERATIONS:
			solver_iterations = p_value;
			break;
	}
}

real_t GodotSpace3D::get_param(PS3DE::SpaceParameter p_param) const {
	switch (p_param) {
		case PS3DE::SPACE_PARAM_CONTACT_RECYCLE_RADIUS:
			return contact_recycle_radius;
		case PS3DE::SPACE_PARAM_CONTACT_MAX_SEPARATION:
			return contact_max_separation;
		case PS3DE::SPACE_PARAM_CONTACT_MAX_ALLOWED_PENETRATION:
			return contact_max_allowed_penetration;
		case PS3DE::SPACE_PARAM_CONTACT_DEFAULT_BIAS:
			return contact_bias;
		case PS3DE::SPACE_PARAM_BODY_LINEAR_VELOCITY_SLEEP_THRESHOLD:
			return body_linear_velocity_sleep_threshold;
		case PS3DE::SPACE_PARAM_BODY_ANGULAR_VELOCITY_SLEEP_THRESHOLD:
			return body_angular_velocity_sleep_threshold;
		case PS3DE::SPACE_PARAM_BODY_TIME_TO_SLEEP:
			return body_time_to_sleep;
		case PS3DE::SPACE_PARAM_SOLVER_ITERATIONS:
			return solver_iterations;
	}
	return 0;
}

void GodotSpace3D::lock() {
	locked = true;
}

void GodotSpace3D::unlock() {
	locked = false;
}

bool GodotSpace3D::is_locked() const {
	return locked;
}

GodotPhysicsDirectSpaceState3D *GodotSpace3D::get_direct_state() {
	return direct_access;
}

GodotSpace3D::GodotSpace3D() {
	body_linear_velocity_sleep_threshold = GLOBAL_GET("physics/3d/sleep_threshold_linear");
	body_angular_velocity_sleep_threshold = GLOBAL_GET("physics/3d/sleep_threshold_angular");
	body_time_to_sleep = GLOBAL_GET("physics/3d/time_before_sleep");
	solver_iterations = GLOBAL_GET("physics/3d/solver/solver_iterations");
	block_solver_enabled = GLOBAL_GET("physics/3d/solver/block_solver_enabled");
	parallel_large_islands = GLOBAL_GET("physics/3d/solver/parallel_large_islands");
	substeps = CLAMP(int(GLOBAL_GET("physics/3d/solver/substeps")), 1, 16);
	manifold_spread_reduction = GLOBAL_GET("physics/3d/solver/manifold_spread_reduction");
	contact_recycle_radius = GLOBAL_GET("physics/3d/solver/contact_recycle_radius");
	contact_max_separation = GLOBAL_GET("physics/3d/solver/contact_max_separation");
	speculative_sphere_distance = MAX(real_t(0.0), (real_t)GLOBAL_GET("physics/3d/solver/speculative_sphere_distance"));
	const real_t configured_strain_max_ratio = GLOBAL_GET("physics/3d/solver/soft_body_xpbd_strain_max_stretch_ratio");
	soft_body_xpbd_strain_max_stretch_ratio = Math::is_finite(configured_strain_max_ratio) && configured_strain_max_ratio > 0.0 ?
			MAX(real_t(1.0), configured_strain_max_ratio) : real_t(0.0);
	const real_t configured_strain_min_ratio = GLOBAL_GET("physics/3d/solver/soft_body_xpbd_strain_min_compression_ratio");
	soft_body_xpbd_strain_min_compression_ratio = Math::is_finite(configured_strain_min_ratio) ?
			CLAMP(configured_strain_min_ratio, real_t(0.0), real_t(1.0)) : real_t(0.0);
	const real_t configured_strain_compliance = GLOBAL_GET("physics/3d/solver/soft_body_xpbd_strain_limit_compliance");
	soft_body_xpbd_strain_limit_compliance = Math::is_finite(configured_strain_compliance) ?
			MAX(real_t(0.0), configured_strain_compliance) : real_t(0.0);
	const real_t configured_xpbd_compliance = GLOBAL_GET("physics/3d/solver/soft_body_xpbd_compliance");
	soft_body_xpbd_compliance = Math::is_finite(configured_xpbd_compliance) ? MAX(real_t(0.0), configured_xpbd_compliance) : real_t(0.0);
	const real_t configured_parallel_ratio = GLOBAL_GET("physics/3d/solver/soft_body_xpbd_parallel_compliance_ratio");
	soft_body_xpbd_parallel_compliance_ratio = Math::is_finite(configured_parallel_ratio) ?
			CLAMP(configured_parallel_ratio, real_t(0.01), real_t(100.0)) : real_t(1.0);
	const Vector3 configured_material_axis = GLOBAL_GET("physics/3d/solver/soft_body_xpbd_material_axis");
	// Do not normalize in float32 when inputs could overflow the squared length.
	const double material_ax = double(configured_material_axis.x);
	const double material_ay = double(configured_material_axis.y);
	const double material_az = double(configured_material_axis.z);
	const double material_axis_sq = material_ax * material_ax + material_ay * material_ay + material_az * material_az;
	soft_body_xpbd_material_axis = configured_material_axis.is_finite() &&
			Math::is_finite(material_axis_sq) && material_axis_sq > 1e-24 ?
			configured_material_axis : Vector3(1, 0, 0);
	const real_t configured_tension_hardening = GLOBAL_GET("physics/3d/solver/soft_body_xpbd_tension_hardening");
	soft_body_xpbd_tension_hardening = Math::is_finite(configured_tension_hardening) ? MAX(real_t(0.0), configured_tension_hardening) : real_t(0.0);
	const real_t configured_compression_hardening = GLOBAL_GET("physics/3d/solver/soft_body_xpbd_compression_hardening");
	soft_body_xpbd_compression_hardening = Math::is_finite(configured_compression_hardening) ? MAX(real_t(0.0), configured_compression_hardening) : real_t(0.0);
	const real_t configured_tension_yield = GLOBAL_GET("physics/3d/solver/soft_body_xpbd_tension_yield_strain");
	soft_body_xpbd_tension_yield_strain = Math::is_finite(configured_tension_yield) ? MAX(real_t(0.0), configured_tension_yield) : real_t(0.1);
	const real_t configured_compression_yield = GLOBAL_GET("physics/3d/solver/soft_body_xpbd_compression_yield_strain");
	const real_t configured_fatigue_rate = GLOBAL_GET("physics/3d/solver/soft_body_fatigue_damage_rate");
	soft_body_fatigue_damage_rate = Math::is_finite(configured_fatigue_rate) ?
			MAX(real_t(0.0), configured_fatigue_rate) : real_t(0.0);
	const real_t configured_fatigue_yield = GLOBAL_GET("physics/3d/solver/soft_body_fatigue_yield_strain");
	soft_body_fatigue_yield_strain = Math::is_finite(configured_fatigue_yield) ?
			MAX(real_t(0.0), configured_fatigue_yield) : real_t(0.3);
	const real_t configured_fatigue_cap = GLOBAL_GET("physics/3d/solver/soft_body_fatigue_max_damage");
	soft_body_fatigue_max_damage = Math::is_finite(configured_fatigue_cap) ?
			CLAMP(configured_fatigue_cap, real_t(0.0), real_t(0.99)) : real_t(0.9);
	soft_body_xpbd_compression_yield_strain = Math::is_finite(configured_compression_yield) ?
			CLAMP(configured_compression_yield, real_t(0.0), real_t(1.0)) : real_t(0.1);
	const real_t configured_plastic_yield = GLOBAL_GET("physics/3d/solver/soft_body_plastic_yield_strain");
	soft_body_plastic_yield_strain = Math::is_finite(configured_plastic_yield) ? CLAMP(configured_plastic_yield, real_t(0.0), real_t(1.0)) : real_t(0.1);
	const real_t configured_plastic_creep_rate = GLOBAL_GET("physics/3d/solver/soft_body_plastic_creep_rate");
	soft_body_plastic_creep_rate = Math::is_finite(configured_plastic_creep_rate) ? MAX(real_t(0.0), configured_plastic_creep_rate) : real_t(0.0);
	const real_t configured_link_damping = GLOBAL_GET("physics/3d/solver/soft_body_link_damping");
	soft_body_link_damping = Math::is_finite(configured_link_damping) ? MAX(real_t(0.0), configured_link_damping) : real_t(0.0);
	const real_t configured_strain_rate_damping = GLOBAL_GET("physics/3d/solver/soft_body_strain_rate_damping");
	soft_body_strain_rate_damping = Math::is_finite(configured_strain_rate_damping) ?
			MAX(real_t(0.0), configured_strain_rate_damping) : real_t(0.0);
	const real_t configured_strain_rate_yield = GLOBAL_GET("physics/3d/solver/soft_body_strain_rate_yield");
	soft_body_strain_rate_yield = Math::is_finite(configured_strain_rate_yield) ?
			MAX(real_t(0.0), configured_strain_rate_yield) : real_t(0.0);
	const real_t configured_lift_coefficient = GLOBAL_GET("physics/3d/solver/soft_body_lift_coefficient");
	soft_body_lift_coefficient = Math::is_finite(configured_lift_coefficient) ? MAX(real_t(0.0), configured_lift_coefficient) : real_t(0.0);
	const real_t configured_gas_gamma = GLOBAL_GET("physics/3d/solver/soft_body_gas_pressure_gamma");
	soft_body_gas_pressure_gamma = Math::is_finite(configured_gas_gamma) ? CLAMP(configured_gas_gamma, real_t(0.0), real_t(5.0)) : real_t(0.0);
	soft_body_hydrostatic_pressure = bool(GLOBAL_GET("physics/3d/solver/soft_body_hydrostatic_pressure"));
	soft_body_hydrodynamic_drag = bool(GLOBAL_GET("physics/3d/solver/soft_body_hydrodynamic_drag"));
	const real_t configured_tangent_ratio = GLOBAL_GET("physics/3d/solver/soft_body_hydrodynamic_tangent_ratio");
	soft_body_hydrodynamic_tangent_ratio = Math::is_finite(configured_tangent_ratio) ?
			CLAMP(configured_tangent_ratio, real_t(0.0), real_t(5.0)) : real_t(0.25);
	const real_t configured_tangential_drag = GLOBAL_GET("physics/3d/solver/soft_body_tangential_drag_ratio");
	soft_body_tangential_drag_ratio = Math::is_finite(configured_tangential_drag) ? MAX(real_t(0.0), configured_tangential_drag) : real_t(0.0);
	const real_t configured_area_compliance = GLOBAL_GET("physics/3d/solver/soft_body_xpbd_area_compliance");
	soft_body_xpbd_area_compliance = Math::is_finite(configured_area_compliance) ? MAX(real_t(0.0), configured_area_compliance) : real_t(0.0);
	const real_t configured_membrane_compliance = GLOBAL_GET("physics/3d/solver/soft_body_xpbd_membrane_compliance");
	soft_body_xpbd_membrane_compliance = Math::is_finite(configured_membrane_compliance) ?
			MAX(real_t(0.0), configured_membrane_compliance) : real_t(0.0);
	const real_t configured_membrane_poisson = GLOBAL_GET("physics/3d/solver/soft_body_membrane_poisson_ratio");
	soft_body_membrane_poisson_ratio = Math::is_finite(configured_membrane_poisson) ?
			CLAMP(configured_membrane_poisson, real_t(-0.49), real_t(0.49)) : real_t(0.3);
	const real_t configured_tetra_compliance = GLOBAL_GET("physics/3d/solver/soft_body_tetra_fem_compliance");
	soft_body_tetra_fem_compliance = Math::is_finite(configured_tetra_compliance) ? MAX(real_t(0.0), configured_tetra_compliance) : real_t(0.0);
	soft_body_tetra_fem_lumped_mass = bool(GLOBAL_GET("physics/3d/solver/soft_body_tetra_fem_lumped_mass"));
	const real_t configured_tetra_poisson = GLOBAL_GET("physics/3d/solver/soft_body_tetra_fem_poisson_ratio");
	soft_body_tetra_fem_poisson_ratio = Math::is_finite(configured_tetra_poisson) ? CLAMP(configured_tetra_poisson, real_t(0.0), real_t(0.49)) : real_t(0.3);
	const int configured_tetra_material_model = GLOBAL_GET("physics/3d/solver/soft_body_tetra_fem_material_model");
	soft_body_tetra_fem_material_model = CLAMP(configured_tetra_material_model, 0, 2);
	const real_t configured_tetra_ogden_exponent = GLOBAL_GET("physics/3d/solver/soft_body_tetra_ogden_exponent");
	soft_body_tetra_ogden_exponent = Math::is_finite(configured_tetra_ogden_exponent) ? CLAMP(configured_tetra_ogden_exponent, real_t(1.0), real_t(8.0)) : real_t(3.0);
	const real_t configured_tetra_mooney_fraction = GLOBAL_GET("physics/3d/solver/soft_body_tetra_mooney_rivlin_fraction");
	soft_body_tetra_mooney_rivlin_fraction = Math::is_finite(configured_tetra_mooney_fraction) ?
			CLAMP(configured_tetra_mooney_fraction, real_t(0.0), real_t(1.0)) : real_t(0.5);
	const real_t configured_fem_fiber_compliance = GLOBAL_GET("physics/3d/solver/soft_body_tetra_fiber_compliance");
	soft_body_tetra_fiber_compliance = Math::is_finite(configured_fem_fiber_compliance) ? MAX(real_t(0.0), configured_fem_fiber_compliance) : real_t(0.0);
	const Vector3 configured_fem_fiber_axis = GLOBAL_GET("physics/3d/solver/soft_body_tetra_fiber_axis");
	soft_body_tetra_fiber_axis = configured_fem_fiber_axis.is_finite() && configured_fem_fiber_axis.length_squared() > real_t(0.0) ? configured_fem_fiber_axis : Vector3(1, 0, 0);
	const real_t fiber_plastic_yield = GLOBAL_GET("physics/3d/solver/soft_body_tetra_fiber_plastic_yield_ratio");
	soft_body_tetra_fiber_plastic_yield_ratio = Math::is_finite(fiber_plastic_yield) ? CLAMP(fiber_plastic_yield, real_t(0.0), real_t(10.0)) : real_t(0.15);
	const real_t fiber_plastic_creep = GLOBAL_GET("physics/3d/solver/soft_body_tetra_fiber_plastic_creep_rate");
	soft_body_tetra_fiber_plastic_creep_rate = Math::is_finite(fiber_plastic_creep) ? MAX(real_t(0.0), fiber_plastic_creep) : real_t(0.0);
	const real_t fiber_plastic_max_stretch = GLOBAL_GET("physics/3d/solver/soft_body_tetra_fiber_plastic_max_stretch");
	soft_body_tetra_fiber_plastic_max_stretch = Math::is_finite(fiber_plastic_max_stretch) ? CLAMP(fiber_plastic_max_stretch, real_t(1.0), real_t(16.0)) : real_t(3.0);
	const real_t configured_tetra_viscosity = GLOBAL_GET("physics/3d/solver/soft_body_tetra_fem_viscosity");
	soft_body_tetra_fem_viscosity = Math::is_finite(configured_tetra_viscosity) ? MAX(real_t(0.0), configured_tetra_viscosity) : real_t(0.0);
	const real_t configured_tetra_plastic_rate = GLOBAL_GET("physics/3d/solver/soft_body_tetra_volume_plastic_rate");
	soft_body_tetra_volume_plastic_rate = Math::is_finite(configured_tetra_plastic_rate) ? MAX(real_t(0.0), configured_tetra_plastic_rate) : real_t(0.0);
	const real_t configured_tetra_plastic_yield = GLOBAL_GET("physics/3d/solver/soft_body_tetra_volume_plastic_yield");
	soft_body_tetra_volume_plastic_yield = Math::is_finite(configured_tetra_plastic_yield) ?
			CLAMP(configured_tetra_plastic_yield, real_t(0.0), real_t(2.0)) : real_t(0.15);
	const real_t configured_tetra_shear_plastic_rate = GLOBAL_GET("physics/3d/solver/soft_body_tetra_shear_plastic_rate");
	soft_body_tetra_shear_plastic_rate = Math::is_finite(configured_tetra_shear_plastic_rate) ?
			MAX(real_t(0.0), configured_tetra_shear_plastic_rate) : real_t(0.0);
	const real_t configured_tetra_shear_plastic_yield = GLOBAL_GET("physics/3d/solver/soft_body_tetra_shear_plastic_yield");
	soft_body_tetra_shear_plastic_yield = Math::is_finite(configured_tetra_shear_plastic_yield) ?
			CLAMP(configured_tetra_shear_plastic_yield, real_t(0.0), real_t(2.0)) : real_t(0.2);
	const real_t configured_tetra_shear_plastic_max = GLOBAL_GET("physics/3d/solver/soft_body_tetra_shear_plastic_max_strain");
	soft_body_tetra_shear_plastic_max_strain = Math::is_finite(configured_tetra_shear_plastic_max) ?
			CLAMP(configured_tetra_shear_plastic_max, real_t(0.01), real_t(4.0)) : real_t(2.0);
	soft_body_tetra_inversion_recovery = GLOBAL_GET("physics/3d/solver/soft_body_tetra_inversion_recovery");
	const real_t configured_tetra_min_j = GLOBAL_GET("physics/3d/solver/soft_body_tetra_inversion_min_j");
	soft_body_tetra_inversion_min_j = Math::is_finite(configured_tetra_min_j) ?
			CLAMP(configured_tetra_min_j, real_t(0.001), real_t(0.5)) : real_t(0.05);
	const real_t damage_rate = GLOBAL_GET("physics/3d/solver/soft_body_tetra_damage_rate");
	soft_body_tetra_damage_rate = Math::is_finite(damage_rate) ? MAX(real_t(0.0), damage_rate) : real_t(0.0);
	const real_t damage_yield = GLOBAL_GET("physics/3d/solver/soft_body_tetra_damage_yield_strain");
	soft_body_tetra_damage_yield_strain = Math::is_finite(damage_yield) ? MAX(real_t(0.0), damage_yield) : real_t(0.25);
	const real_t configured_membrane_damping = GLOBAL_GET("physics/3d/solver/soft_body_membrane_damping_rate");
	soft_body_membrane_damping_rate = Math::is_finite(configured_membrane_damping) ?
			MAX(real_t(0.0), configured_membrane_damping) : real_t(0.0);
	const real_t configured_shear_compliance = GLOBAL_GET("physics/3d/solver/soft_body_xpbd_shear_compliance");
	soft_body_xpbd_shear_compliance = Math::is_finite(configured_shear_compliance) ? MAX(real_t(0.0), configured_shear_compliance) : real_t(0.0);
	const real_t configured_dihedral_compliance = GLOBAL_GET("physics/3d/solver/soft_body_xpbd_dihedral_compliance");
	soft_body_xpbd_dihedral_compliance = Math::is_finite(configured_dihedral_compliance) ? MAX(real_t(0.0), configured_dihedral_compliance) : real_t(0.0);
	const real_t configured_shape_stiffness = GLOBAL_GET("physics/3d/solver/soft_body_shape_matching_stiffness");
	soft_body_shape_matching_stiffness = Math::is_finite(configured_shape_stiffness) ? CLAMP(configured_shape_stiffness, real_t(0.0), real_t(1.0)) : real_t(0.0);
	const int configured_shape_cluster_size = GLOBAL_GET("physics/3d/solver/soft_body_shape_matching_cluster_size");
	soft_body_shape_matching_cluster_size = configured_shape_cluster_size > 0 ? CLAMP(configured_shape_cluster_size, 3, 64) : 0;
	const real_t configured_dihedral_damping = GLOBAL_GET("physics/3d/solver/soft_body_dihedral_damping");
	soft_body_dihedral_damping = Math::is_finite(configured_dihedral_damping) ? MAX(real_t(0.0), configured_dihedral_damping) : real_t(0.0);
	const real_t configured_bending_yield = GLOBAL_GET("physics/3d/solver/soft_body_bending_plastic_yield_angle");
	soft_body_bending_plastic_yield_angle = Math::is_finite(configured_bending_yield) ? CLAMP(configured_bending_yield, real_t(0.0), real_t(Math::PI)) : real_t(0.2);
	const real_t configured_bending_creep = GLOBAL_GET("physics/3d/solver/soft_body_bending_plastic_creep_rate");
	soft_body_bending_plastic_creep_rate = Math::is_finite(configured_bending_creep) ? MAX(real_t(0.0), configured_bending_creep) : real_t(0.0);
	const real_t configured_self_thickness = GLOBAL_GET("physics/3d/solver/soft_body_self_collision_thickness");
	soft_body_self_collision_thickness = Math::is_finite(configured_self_thickness) ? MAX(real_t(0.0), configured_self_thickness) : real_t(0.0);
	const real_t configured_self_compliance = GLOBAL_GET("physics/3d/solver/soft_body_self_collision_compliance");
	soft_body_self_collision_compliance = Math::is_finite(configured_self_compliance) ? MAX(real_t(0.0), configured_self_compliance) : real_t(0.000001);
	const real_t configured_self_friction = GLOBAL_GET("physics/3d/solver/soft_body_self_collision_friction");
	soft_body_self_collision_friction = Math::is_finite(configured_self_friction) ? MAX(real_t(0.0), configured_self_friction) : real_t(0.0);
	soft_body_self_collision_max_contacts_per_vertex = CLAMP((int)GLOBAL_GET("physics/3d/solver/soft_body_self_collision_max_contacts_per_vertex"), 1, 32);
	soft_body_self_collision_edge_edge = GLOBAL_GET("physics/3d/solver/soft_body_self_collision_edge_edge");
	soft_body_self_collision_ccd = GLOBAL_GET("physics/3d/solver/soft_body_self_collision_ccd");
	const real_t configured_pair_thickness = GLOBAL_GET("physics/3d/solver/soft_body_pair_collision_thickness");
	soft_body_pair_collision_thickness = Math::is_finite(configured_pair_thickness) ? MAX(real_t(0.0), configured_pair_thickness) : real_t(0.0);
	const real_t configured_pair_compliance = GLOBAL_GET("physics/3d/solver/soft_body_pair_collision_compliance");
	soft_body_pair_collision_compliance = Math::is_finite(configured_pair_compliance) ? MAX(real_t(0.0), configured_pair_compliance) : real_t(0.000001);
	const real_t configured_pair_friction = GLOBAL_GET("physics/3d/solver/soft_body_pair_collision_friction");
	soft_body_pair_collision_friction = Math::is_finite(configured_pair_friction) ? MAX(real_t(0.0), configured_pair_friction) : real_t(0.0);
	soft_body_pair_collision_ccd = GLOBAL_GET("physics/3d/solver/soft_body_pair_collision_ccd");
	soft_body_pair_collision_edge_edge = GLOBAL_GET("physics/3d/solver/soft_body_pair_collision_edge_edge");
	soft_body_pair_collision_edge_ccd = GLOBAL_GET("physics/3d/solver/soft_body_pair_collision_edge_ccd");
	soft_body_pair_max_contacts = CLAMP(int(GLOBAL_GET("physics/3d/solver/soft_body_pair_max_contacts")), 1, 2048);
	soft_body_pair_max_pairs = CLAMP(int(GLOBAL_GET("physics/3d/solver/soft_body_pair_max_pairs")), 1, 512);
	const real_t configured_tether_compliance = GLOBAL_GET("physics/3d/solver/soft_body_xpbd_tether_compliance");
	soft_body_xpbd_tether_compliance = Math::is_finite(configured_tether_compliance) ? MAX(real_t(0.0), configured_tether_compliance) : real_t(0.0);
	const real_t configured_tether_slack = GLOBAL_GET("physics/3d/solver/soft_body_xpbd_tether_slack");
	soft_body_xpbd_tether_slack = Math::is_finite(configured_tether_slack) ? MAX(real_t(0.0), configured_tether_slack) : real_t(0.05);
	const real_t configured_volume_compliance = GLOBAL_GET("physics/3d/solver/soft_body_xpbd_volume_compliance");
	soft_body_xpbd_volume_compliance = Math::is_finite(configured_volume_compliance) ? MAX(real_t(0.0), configured_volume_compliance) : real_t(0.0);
	const real_t configured_volume_damping = GLOBAL_GET("physics/3d/solver/soft_body_volume_damping_rate");
	soft_body_volume_damping_rate = Math::is_finite(configured_volume_damping) ? MAX(real_t(0.0), configured_volume_damping) : real_t(0.0);
	const real_t configured_volume_yield = GLOBAL_GET("physics/3d/solver/soft_body_volume_plastic_yield_strain");
	soft_body_volume_plastic_yield_strain = Math::is_finite(configured_volume_yield) ? CLAMP(configured_volume_yield, real_t(0.0), real_t(0.95)) : real_t(0.15);
	const real_t configured_volume_creep = GLOBAL_GET("physics/3d/solver/soft_body_volume_plastic_creep_rate");
	soft_body_volume_plastic_creep_rate = Math::is_finite(configured_volume_creep) ? MAX(real_t(0.0), configured_volume_creep) : real_t(0.0);
	contact_max_allowed_penetration = GLOBAL_GET("physics/3d/solver/contact_max_allowed_penetration");
	contact_bias = GLOBAL_GET("physics/3d/solver/default_contact_bias");
	// Cache the per-space push speed limit; no project-setting lookup on contacts.
	max_contact_push_speed = MAX((real_t)0.0, (real_t)GLOBAL_GET("physics/3d/solver/max_contact_push_speed"));
	max_linear_velocity = MAX((real_t)0.0, (real_t)GLOBAL_GET("physics/3d/solver/max_linear_velocity"));
	max_angular_velocity = MAX((real_t)0.0, (real_t)GLOBAL_GET("physics/3d/solver/max_angular_velocity"));
	ccd_max_angular_motion = MAX(real_t(0.0), (real_t)GLOBAL_GET("physics/3d/solver/ccd_max_angular_motion"));
	warm_start_coefficient = CLAMP((real_t)GLOBAL_GET("physics/3d/solver/warm_start_coefficient"), real_t(0.0), real_t(1.0));
	ccd_rotational_bounds = GLOBAL_GET("physics/3d/solver/ccd_rotational_bounds");
	ccd_tight_rotational_bounds = GLOBAL_GET("physics/3d/solver/ccd_tight_rotational_bounds");
	implicit_damping = GLOBAL_GET("physics/3d/solver/implicit_damping");
	fluid_linear_drag = MAX(real_t(0.0), (real_t)GLOBAL_GET("physics/3d/solver/fluid_linear_drag"));
	fluid_angular_drag = MAX(real_t(0.0), (real_t)GLOBAL_GET("physics/3d/solver/fluid_angular_drag"));
	fluid_buoyancy = MAX(real_t(0.0), (real_t)GLOBAL_GET("physics/3d/solver/fluid_buoyancy"));
	fluid_flow_velocity = GLOBAL_GET("physics/3d/solver/fluid_flow_velocity");
	fluid_plane_enabled = GLOBAL_GET("physics/3d/fluid_plane/enabled");
	fluid_plane_surface_height = GLOBAL_GET("physics/3d/fluid_plane/surface_height");
	fluid_plane_density = MAX(real_t(0.0), (real_t)GLOBAL_GET("physics/3d/fluid_plane/density"));
	fluid_plane_drag_coefficient = MAX(real_t(0.0), (real_t)GLOBAL_GET("physics/3d/fluid_plane/drag_coefficient"));
	fluid_plane_angular_drag = MAX(real_t(0.0), (real_t)GLOBAL_GET("physics/3d/fluid_plane/angular_drag"));
	fluid_plane_flow_velocity = GLOBAL_GET("physics/3d/fluid_plane/flow_velocity");
	gyroscopic_forces = GLOBAL_GET("physics/3d/solver/gyroscopic_forces");
	gyroscopic_integration_mode = CLAMP((int)GLOBAL_GET("physics/3d/solver/gyroscopic_integration_mode"), 0, 1);
	rolling_friction = MAX(real_t(0.0), (real_t)GLOBAL_GET("physics/3d/solver/rolling_friction"));
	spinning_friction = MAX(real_t(0.0), (real_t)GLOBAL_GET("physics/3d/solver/spinning_friction"));
	static_friction_multiplier = MAX(real_t(1.0), (real_t)GLOBAL_GET("physics/3d/solver/static_friction_multiplier"));
	const real_t configured_stribeck_velocity = GLOBAL_GET("physics/3d/solver/stribeck_transition_velocity");
	stribeck_transition_velocity = Math::is_finite(configured_stribeck_velocity) ? MAX(real_t(0.0), configured_stribeck_velocity) : real_t(0.0);
	const real_t configured_anisotropy_ratio = GLOBAL_GET("physics/3d/solver/friction_anisotropy_ratio");
	friction_anisotropy_ratio = Math::is_finite(configured_anisotropy_ratio) ? CLAMP(configured_anisotropy_ratio, real_t(0.01), real_t(1.0)) : real_t(1.0);
	const Vector3 configured_anisotropy_axis = GLOBAL_GET("physics/3d/solver/friction_anisotropy_axis");
	const real_t axis_length_squared = configured_anisotropy_axis.length_squared();
	friction_anisotropy_axis = configured_anisotropy_axis.is_finite() && Math::is_finite(axis_length_squared) && axis_length_squared > real_t(1e-12) ?
			configured_anisotropy_axis.normalized() : Vector3(1, 0, 0);
	friction_combine_mode = CLAMP((int)GLOBAL_GET("physics/3d/solver/friction_combine_mode"), 0, 3);
	restitution_combine_mode = CLAMP((int)GLOBAL_GET("physics/3d/solver/restitution_combine_mode"), 0, 5);
	// Read once at space creation, avoiding ProjectSettings lookups in the hot contact loop.
	const real_t configured_restitution_threshold = GLOBAL_GET("physics/3d/solver/restitution_velocity_threshold");
	restitution_velocity_threshold = MAX((real_t)0.0, configured_restitution_threshold);

	broadphase = GodotBroadPhase3D::create_func();
	broadphase->set_pair_callback(_broadphase_pair, this);
	broadphase->set_unpair_callback(_broadphase_unpair, this);

	direct_access = memnew(GodotPhysicsDirectSpaceState3D);
	direct_access->space = this;
}

GodotSpace3D::~GodotSpace3D() {
	memdelete(broadphase);
	memdelete(direct_access);
}
