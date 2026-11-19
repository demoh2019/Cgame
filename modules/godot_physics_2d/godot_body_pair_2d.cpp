/**************************************************************************/
/*  godot_body_pair_2d.cpp                                                */
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

#include "godot_body_pair_2d.h"

#include "godot_collision_solver_2d.h"
#include "godot_contact_normal_2d.h"
#include "godot_space_2d.h"
#include "servers/physics_rolling_resistance.h"
#include "servers/physics_ccd_sphere_toi.h"

#define ACCUMULATE_IMPULSES

#define MIN_VELOCITY 0.001
#define MAX_BIAS_ROTATION (Math::PI / 8)

void GodotBodyPair2D::_add_contact(const Vector2 &p_point_A, const Vector2 &p_point_B, void *p_self) {
	GodotBodyPair2D *self = static_cast<GodotBodyPair2D *>(p_self);

	self->_contact_added_callback(p_point_A, p_point_B);
}

void GodotBodyPair2D::_contact_added_callback(const Vector2 &p_point_A, const Vector2 &p_point_B) {
	Vector2 local_A = A->get_inv_transform().basis_xform(p_point_A);
	Vector2 local_B = B->get_inv_transform().basis_xform(p_point_B - offset_B);

	int new_index = contact_count;

	ERR_FAIL_COND(new_index >= (MAX_CONTACTS + 1));

	Contact contact;
	contact.local_A = local_A;
	contact.local_B = local_B;
	// Contact normals point from B toward A. Use the reverse body-center
	// direction when coincident support points cannot define a contact axis.
	contact.normal = godot_physics_2d_contact_normal(p_point_A, p_point_B, -offset_B);
	contact.used = true;

	// Match persistent contacts by the closest *unused* pair of local
	// anchors, not the first contact inside the recycling radius. This keeps
	// the two manifold points from inheriting the same cached impulse when
	// their positions become close during rotation or sliding.
	const real_t recycle_radius = space->get_contact_recycle_radius();
	const real_t recycle_radius_2 = recycle_radius * recycle_radius;
	int best_match = -1;
	real_t best_distance_squared = 0.0;
	for (int i = 0; i < contact_count; i++) {
		const Contact &c = contacts[i];
		if (c.used || c.normal.dot(contact.normal) < real_t(0.98)) {
			// Match only unused points on a compatible contact plane.
			// A closer point from another face must not mask a valid match.
			continue;
		}

		const real_t distance_A_squared = c.local_A.distance_squared_to(local_A);
		if (distance_A_squared >= recycle_radius_2) {
			continue;
		}
		const real_t distance_B_squared = c.local_B.distance_squared_to(local_B);
		if (distance_B_squared >= recycle_radius_2) {
			continue;
		}

		const real_t total_distance_squared = distance_A_squared + distance_B_squared;
		if (best_match == -1 || total_distance_squared < best_distance_squared) {
			best_match = i;
			best_distance_squared = total_distance_squared;
		}
	}

	if (best_match != -1) {
		Contact &previous = contacts[best_match];
		// Keep warm-start impulses only when the contact normal still agrees
		// with its previous direction (e.g. not after crossing a sharp edge).
		if (previous.normal.dot(contact.normal) >= real_t(0.98)) {
			contact.acc_normal_impulse = previous.acc_normal_impulse;
			// Reproject cached tangent friction as the contact normal rotates.
			contact.acc_tangent_impulse = previous.acc_tangent_impulse * previous.normal.dot(contact.normal);
			contact.acc_bias_impulse = previous.acc_bias_impulse;
			contact.acc_bias_impulse_center_of_mass = previous.acc_bias_impulse_center_of_mass;
		}
		previous = contact;
		return;
	}

	// Figure out if the contact amount must be reduced to fit the new contact.
	if (new_index == MAX_CONTACTS) {
		// Remove the contact with the minimum depth.

		const Transform2D &transform_A = A->get_transform();
		const Transform2D &transform_B = B->get_transform();

		int least_deep = -1;
		real_t min_depth;

		// Start with depth for new contact.
		{
			Vector2 global_A = transform_A.basis_xform(contact.local_A);
			Vector2 global_B = transform_B.basis_xform(contact.local_B) + offset_B;

			Vector2 axis = global_A - global_B;
			min_depth = axis.dot(contact.normal);
		}

		for (int i = 0; i < contact_count; i++) {
			const Contact &c = contacts[i];
			Vector2 global_A = transform_A.basis_xform(c.local_A);
			Vector2 global_B = transform_B.basis_xform(c.local_B) + offset_B;

			Vector2 axis = global_A - global_B;
			real_t depth = axis.dot(c.normal);

			if (depth < min_depth) {
				min_depth = depth;
				least_deep = i;
			}
		}

		if (least_deep > -1) {
			// Replace the least deep contact by the new one.
			contacts[least_deep] = contact;
		}

		return;
	}

	contacts[new_index] = contact;
	contact_count++;
}

void GodotBodyPair2D::_validate_contacts() {
	// Make sure to erase contacts that are no longer valid.
	real_t max_separation = space->get_contact_max_separation();
	real_t max_separation2 = max_separation * max_separation;

	const Transform2D &transform_A = A->get_transform();
	const Transform2D &transform_B = B->get_transform();

	for (int i = 0; i < contact_count; i++) {
		Contact &c = contacts[i];

		bool erase = false;
		if (!c.used) {
			// Was left behind in previous frame.
			erase = true;
		} else {
			c.used = false;

			Vector2 global_A = transform_A.basis_xform(c.local_A);
			Vector2 global_B = transform_B.basis_xform(c.local_B) + offset_B;
			Vector2 axis = global_A - global_B;
			real_t depth = axis.dot(c.normal);

			if (depth < -max_separation || (global_B + c.normal * depth - global_A).length_squared() > max_separation2) {
				erase = true;
			}
		}

		if (erase) {
			// Contact no longer needed, remove.

			if ((i + 1) < contact_count) {
				// Swap with the last one.
				SWAP(contacts[i], contacts[contact_count - 1]);
			}

			i--;
			contact_count--;
		}
	}
}

// Cast-ray CCD clips the moving body's velocity if its leading support would
// tunnel through the other body in one physics step. Cast in relative-motion
// space, so co-moving or approaching bodies are not tested against a target
// frozen at its *future* position. This is still an approximate CCD response:
// shortening velocity can change the momentum of an ensuing bounce.
bool GodotBodyPair2D::_test_ccd(real_t p_step, GodotBody2D *p_A, int p_shape_A, const Transform2D &p_xform_A, GodotBody2D *p_B, int p_shape_B, const Transform2D &p_xform_B) {
	if (p_step <= 0.0) {
		return false;
	}
	const Vector2 motion_A = p_A->get_linear_velocity() * p_step;
	if (motion_A.length_squared() == 0.0) {
		return false;
	}
	// Static bodies can have a constant surface velocity for friction, but
	// their collision geometry does not move between physics steps.
	const Vector2 velocity_B = p_B->get_mode() == PS2DE::BODY_MODE_STATIC ? Vector2() : p_B->get_linear_velocity();
	const Vector2 relative_motion = motion_A - velocity_B * p_step;
	const real_t mlen = relative_motion.length();
	if (mlen < CMP_EPSILON || motion_A.dot(relative_motion) <= 0.0) {
		// Co-moving bodies cannot meet along this sweep. Also avoid changing A
		// when only B is closing from behind; B's own CCD handles that case.
		return false;
	}

	const Vector2 mnormal = relative_motion / mlen;

	real_t min = 0.0, max = 0.0;
	p_A->get_shape(p_shape_A)->project_rangev(mnormal, p_xform_A, min, max);

	// Did it move enough in this direction to even attempt raycast?
	// Let's say it should move more than 1/3 the size of the object in that axis.
	bool fast_object = mlen > (max - min) * 0.3;
	if (!fast_object) {
		return false;
	}

	// A is moving fast relative to B, so test the relative sweep against
	// B's current shape. Using B's predicted end position produces false
	// collisions for equally fast co-moving bodies.

	// CCD cast-ray uses the leading support feature, which may contain two
	// vertices (a box face, capsule side, or polygon edge). Test both ends:
	// a single support ray can miss a narrow obstacle hit by the other end.
	GodotShape2D *shape_A_ptr = p_A->get_shape(p_shape_A);
	GodotShape2D *shape_B_ptr = p_B->get_shape(p_shape_B);

	// A single support ray can miss a glancing circle/circle impact.
	// With uniform-scale transforms the Minkowski sum is another circle,
	// so solve its first linear time of impact analytically in O(1).
	if (shape_A_ptr->get_type() == PS2DE::SHAPE_CIRCLE && shape_B_ptr->get_type() == PS2DE::SHAPE_CIRCLE) {
		const double scale_A = physics_ccd_uniform_sphere_scale(p_xform_A);
		const double scale_B = physics_ccd_uniform_sphere_scale(p_xform_B);
		if (scale_A > 0.0 && scale_B > 0.0) {
			const double radius_A = double(static_cast<GodotCircleShape2D *>(shape_A_ptr)->get_radius()) * scale_A;
			const double radius_B = double(static_cast<GodotCircleShape2D *>(shape_B_ptr)->get_radius()) * scale_B;
			const Vector2 center_delta = p_xform_A.get_origin() - p_xform_B.get_origin();
			double impact_fraction = 0.0;
			if (!physics_ccd_sphere_toi(center_delta, relative_motion, radius_A + radius_B, impact_fraction)) {
				return false;
			}

			// Leave the same 1% overlap allowance as the legacy support
			// casts. CCD only limits A's speed; it never reverses or boosts it.
			const real_t allowed_distance = CLAMP(real_t(impact_fraction * double(mlen)) + (max - min) * real_t(0.01), real_t(0.0), mlen);
			const Vector2 desired_velocity = velocity_B + mnormal * (allowed_distance / p_step);
			const Vector2 velocity_A = p_A->get_linear_velocity();
			const real_t initial_speed = velocity_A.length();
			const Vector2 travel_direction = velocity_A / initial_speed;
			const real_t clipped_speed = CLAMP(desired_velocity.dot(travel_direction), real_t(0.0), initial_speed);
			p_A->set_linear_velocity(travel_direction * clipped_speed);
			return true;
		}
		// Nonuniform scales turn circles into ellipses; retain the existing
		// support-ray fallback rather than applying a wrong circular TOI.
	}

	Vector2 supports_A[2];
	int support_count_A = 0;
	shape_A_ptr->get_supports(p_xform_A.basis_xform_inv(mnormal).normalized(), supports_A, support_count_A);
	if (support_count_A == 0) {
		return false;
	}

	// All rays share the same target transform and direction. Compare squared
	// hit distances in target-local space to avoid a square root for each hit.
	if (p_xform_B.determinant() == 0.0) {
		return false;
	}
	const Transform2D inv_B = p_xform_B.affine_inverse();
	bool found_hit = false;
	real_t best_hit_distance = 0.0;
	for (int support_idx = 0; support_idx < support_count_A; ++support_idx) {
		const Vector2 from = p_xform_A.xform(supports_A[support_idx]);
		const Vector2 local_from = inv_B.xform(from - relative_motion * 0.1);
		const Vector2 local_to = inv_B.xform(from + relative_motion);
		Vector2 rpos, rnorm;
		if (!shape_B_ptr->intersect_segment(local_from, local_to, rpos, rnorm)) {
			continue;
		}

		// Compare world-space distances along the *relative* sweep, not
		// squared lengths after an arbitrary affine transform of B.
		const real_t hit_distance = mnormal.dot(p_xform_B.xform(rpos) - from);
		if (!found_hit || hit_distance < best_hit_distance) {
			found_hit = true;
			best_hit_distance = hit_distance;
		}
	}
	if (!found_hit) {
		return false;
	}

	// Check one-way collision based on motion direction.
	if (p_A->get_shape(p_shape_A)->allows_one_way_collision() && p_B->is_shape_set_as_one_way_collision(p_shape_B)) {
		Vector2 direction = p_xform_B.basis_xform(p_B->get_shape_one_way_collision_direction(p_shape_B)).normalized();

		if (direction.dot(mnormal) < CMP_EPSILON) {
			collided = false;
			oneway_disabled = true;
			return false;
		}
	}

	// Shorten the linear velocity so it does not hit, but gets close enough,
	// next frame will hit softly or soft enough.
	// Move A no farther than the first relative contact plus a small
	// penetration allowance. Preserve B's velocity when converting this
	// relative motion back to the world frame.
	const real_t newlen = CLAMP(best_hit_distance + (max - min) * real_t(0.01), real_t(0.0), mlen);
	const Vector2 corrected_velocity = velocity_B + mnormal * (newlen / p_step);
	// This CCD mode is a velocity clamp, not an impulse solver. Do not
	// reverse or accelerate A just because B is approaching quickly.
	// B's own CCD handles fast inbound motion when enabled.
	const Vector2 velocity_A = p_A->get_linear_velocity();
	const real_t initial_speed = velocity_A.length();
	const Vector2 travel_direction = velocity_A / initial_speed;
	const real_t clamped_speed = CLAMP(corrected_velocity.dot(travel_direction), real_t(0.0), initial_speed);
	p_A->set_linear_velocity(travel_direction * clamped_speed);

	return true;
}

bool GodotBodyPair2D::setup(real_t p_step) {
	check_ccd = false;

	if (!A->interacts_with(B) || A->has_exception(B->get_self()) || B->has_exception(A->get_self())) {
		collided = false;
		return false;
	}

	collide_A = (A->get_mode() > PS2DE::BODY_MODE_KINEMATIC) && A->collides_with(B);
	collide_B = (B->get_mode() > PS2DE::BODY_MODE_KINEMATIC) && B->collides_with(A);

	report_contacts_only = false;
	if (!collide_A && !collide_B) {
		if ((A->get_max_contacts_reported() > 0) || (B->get_max_contacts_reported() > 0)) {
			report_contacts_only = true;
		} else {
			collided = false;
			return false;
		}
	}

	//use local A coordinates to avoid numerical issues on collision detection
	const Vector2 new_offset_B = B->get_transform().get_origin() - A->get_transform().get_origin();
	// Translate both rigid bodies together without redoing SAT/GJK. The
	// contact anchors and world normal are unchanged if the relative offset
	// and both shape orientations match exactly. Do not approximate poses.
	const bool relative_translation_unchanged = offset_B == new_offset_B;
	offset_B = new_offset_B;

	// Geometry versions still change on local shape edits, rotation, scaling,
	// shearing, filters and space changes. CCD always uses the narrow phase.
	const bool ccd_enabled = A->get_continuous_collision_detection_mode() != PS2DE::CCD_MODE_DISABLED ||
			B->get_continuous_collision_detection_mode() != PS2DE::CCD_MODE_DISABLED;
	const uint64_t geometry_version_a = A->get_collision_geometry_version();
	const uint64_t geometry_version_b = B->get_collision_geometry_version();
	// The broadphase AABBs may overlap even when the actual shapes are
	// separated. Reuse that exact negative SAT/GJK result while neither
	// relative translation nor either body's shape/orientation has changed.
	// Previous results obtained through one-way filtering are never cached.
	if (relative_translation_unchanged && contact_recycling.can_reuse_separation(geometry_version_a, geometry_version_b, ccd_enabled)) {
		collided = false;
		oneway_disabled = false;
		return false;
	}
	if (relative_translation_unchanged && contact_recycling.can_reuse(geometry_version_a, geometry_version_b, collided && !oneway_disabled, contact_count, ccd_enabled)) {
		// SAT may have emitted a new manifold with fewer points, leaving
		// old (unused) contacts to be pruned on the next frame. Never recycle
		// such a mixed manifold indefinitely without validating the points.
		bool all_contacts_used = true;
		for (int i = 0; i < contact_count; i++) {
			if (!contacts[i].used) {
				all_contacts_used = false;
				break;
			}
		}
		if (all_contacts_used) {
			// pre_solve still refreshes masses, bias, friction and velocities.
			return true;
		}
	}

	_validate_contacts();

	const Vector2 &offset_A = A->get_transform().get_origin();
	Transform2D xform_Au = A->get_transform().untranslated();
	Transform2D xform_A = xform_Au * A->get_shape_transform(shape_A);

	Transform2D xform_Bu = B->get_transform();
	xform_Bu.columns[2] -= offset_A;
	Transform2D xform_B = xform_Bu * B->get_shape_transform(shape_B);

	GodotShape2D *shape_A_ptr = A->get_shape(shape_A);
	GodotShape2D *shape_B_ptr = B->get_shape(shape_B);

	Vector2 motion_A, motion_B;

	if (A->get_continuous_collision_detection_mode() == PS2DE::CCD_MODE_CAST_SHAPE) {
		motion_A = A->get_motion();
	}
	if (B->get_continuous_collision_detection_mode() == PS2DE::CCD_MODE_CAST_SHAPE) {
		motion_B = B->get_motion();
	}

	bool prev_collided = collided;

	collided = GodotCollisionSolver2D::solve(shape_A_ptr, xform_A, motion_A, shape_B_ptr, xform_B, motion_B, _add_contact, this, &sep_axis);
	contact_recycling.remember(geometry_version_a, geometry_version_b, collided);
	if (!collided) {
		oneway_disabled = false;

		if (A->get_continuous_collision_detection_mode() == PS2DE::CCD_MODE_CAST_RAY && collide_A) {
			check_ccd = true;
			return true;
		}

		if (B->get_continuous_collision_detection_mode() == PS2DE::CCD_MODE_CAST_RAY && collide_B) {
			check_ccd = true;
			return true;
		}

		return false;
	}

	if (oneway_disabled) {
		return false;
	}

	if (!prev_collided) {
		if (shape_B_ptr->allows_one_way_collision() && A->is_shape_set_as_one_way_collision(shape_A)) {
			Vector2 direction = xform_A.basis_xform(A->get_shape_one_way_collision_direction(shape_A)).normalized();

			bool valid = false;
			for (int i = 0; i < contact_count; i++) {
				Contact &c = contacts[i];
				if (c.normal.dot(direction) > -CMP_EPSILON) { // Greater (normal inverted).
					continue;
				}
				valid = true;
				break;
			}
			if (!valid) {
				collided = false;
				oneway_disabled = true;
				return false;
			}
		}

		if (shape_A_ptr->allows_one_way_collision() && B->is_shape_set_as_one_way_collision(shape_B)) {
			Vector2 direction = xform_B.basis_xform(B->get_shape_one_way_collision_direction(shape_B)).normalized();

			bool valid = false;
			for (int i = 0; i < contact_count; i++) {
				Contact &c = contacts[i];
				if (c.normal.dot(direction) < CMP_EPSILON) { // Less (normal ok).
					continue;
				}
				valid = true;
				break;
			}
			if (!valid) {
				collided = false;
				oneway_disabled = true;
				return false;
			}
		}
	}

	return true;
}

bool GodotBodyPair2D::pre_solve(real_t p_step) {
	block_normal_valid = false;
	rolling_impulse = 0.0;
	rolling_impulse_scale = 0.0;
	if (oneway_disabled) {
		return false;
	}

	if (!collided) {
		if (check_ccd) {
			const Vector2 &offset_A = A->get_transform().get_origin();
			Transform2D xform_Au = A->get_transform().untranslated();
			Transform2D xform_A = xform_Au * A->get_shape_transform(shape_A);

			Transform2D xform_Bu = B->get_transform();
			xform_Bu.columns[2] -= offset_A;
			Transform2D xform_B = xform_Bu * B->get_shape_transform(shape_B);

			if (A->get_continuous_collision_detection_mode() == PS2DE::CCD_MODE_CAST_RAY && collide_A) {
				_test_ccd(p_step, A, shape_A, xform_A, B, shape_B, xform_B);
			}

			if (B->get_continuous_collision_detection_mode() == PS2DE::CCD_MODE_CAST_RAY && collide_B) {
				_test_ccd(p_step, B, shape_B, xform_B, A, shape_A, xform_A);
			}
		}

		return false;
	}

	real_t max_penetration = space->get_contact_max_allowed_penetration();

	real_t bias = space->get_contact_bias();

	GodotShape2D *shape_A_ptr = A->get_shape(shape_A);
	GodotShape2D *shape_B_ptr = B->get_shape(shape_B);

	if (shape_A_ptr->get_custom_bias() || shape_B_ptr->get_custom_bias()) {
		if (shape_A_ptr->get_custom_bias() == 0) {
			bias = shape_B_ptr->get_custom_bias();
		} else if (shape_B_ptr->get_custom_bias() == 0) {
			bias = shape_A_ptr->get_custom_bias();
		} else {
			bias = (shape_B_ptr->get_custom_bias() + shape_A_ptr->get_custom_bias()) * 0.5;
		}
	}

	real_t inv_dt = 1.0 / p_step;

	bool do_process = false;

	const Vector2 &offset_A = A->get_transform().get_origin();
	const Transform2D &transform_A = A->get_transform();
	const Transform2D &transform_B = B->get_transform();

	real_t inv_inertia_A = collide_A ? A->get_inv_inertia() : 0.0;
	real_t inv_inertia_B = collide_B ? B->get_inv_inertia() : 0.0;

	real_t inv_mass_A = collide_A ? A->get_inv_mass() : 0.0;
	real_t inv_mass_B = collide_B ? B->get_inv_mass() : 0.0;
	// Materials may change between frames. Compute once before warm starting,
	// instead of re-mixing them for every solver iteration.
	mixed_friction = space->mix_friction(A->get_friction(), B->get_friction());
	// Materials are shared by the entire manifold; combine restitution once
	// per constraint setup, not once per contact point.
	const real_t mixed_restitution = space->mix_restitution(A->get_bounce(), B->get_bounce());
	const bool has_friction = mixed_friction > 0.0;

	// Opt-in Box2D-style resistance to rolling. Only angularly dynamic
	// circles contribute a rolling radius; boxes cannot receive this drag.
	const real_t rolling_resistance = space->get_rolling_resistance();
	if (rolling_resistance > 0.0 && !report_contacts_only) {
		real_t radius = 0.0;
		if (inv_inertia_A > 0.0 && shape_A_ptr->get_type() == PS2DE::SHAPE_CIRCLE) {
			const Transform2D xform = transform_A * A->get_shape_transform(shape_A);
			const double scale = physics_ccd_uniform_sphere_scale(xform);
			if (scale > 0.0) {
				radius = static_cast<GodotCircleShape2D *>(shape_A_ptr)->get_radius() * real_t(scale);
			}
		}
		if (inv_inertia_B > 0.0 && shape_B_ptr->get_type() == PS2DE::SHAPE_CIRCLE) {
			const Transform2D xform = transform_B * B->get_shape_transform(shape_B);
			const double scale = physics_ccd_uniform_sphere_scale(xform);
			if (scale > 0.0) {
				const real_t radius_B = static_cast<GodotCircleShape2D *>(shape_B_ptr)->get_radius() * real_t(scale);
				radius = radius > 0.0 ? MIN(radius, radius_B) : radius_B;
			}
		}
		rolling_impulse_scale = rolling_resistance * radius;
	}

	// A cached impulse has force*time units. Preserve its equivalent force
	// when the physics tick rate changes, rather than reusing the old impulse.
	// Discard the cache after unusually large timestep jumps.
	const real_t previous_step = space->get_previous_step();
	const bool step_changed = previous_step > 0.0 && !Math::is_equal_approx(previous_step, p_step);
	const real_t timestep_ratio = step_changed ? p_step / previous_step : real_t(1.0);
	const bool can_scale_impulses = timestep_ratio >= real_t(0.5) && timestep_ratio <= real_t(2.0);
	// Configurable like Rapier; default 1.0 preserves the old fixed-step path.
	const real_t warm_start_coefficient = space->get_warm_start_coefficient();
	const bool rescale_impulses = step_changed || warm_start_coefficient != real_t(1.0);
	const real_t impulse_scale = timestep_ratio * warm_start_coefficient;

	for (int i = 0; i < contact_count; i++) {
		Contact &c = contacts[i];
		c.active = false;

		if (rescale_impulses) {
			if (can_scale_impulses) {
				c.acc_normal_impulse *= impulse_scale;
				c.acc_tangent_impulse *= impulse_scale;
				c.acc_bias_impulse *= impulse_scale;
				c.acc_bias_impulse_center_of_mass *= impulse_scale;
			} else {
				c.acc_normal_impulse = 0.0;
				c.acc_tangent_impulse = 0.0;
				c.acc_bias_impulse = 0.0;
				c.acc_bias_impulse_center_of_mass = 0.0;
			}
		}

		Vector2 global_A = transform_A.basis_xform(c.local_A);
		Vector2 global_B = transform_B.basis_xform(c.local_B) + offset_B;

		Vector2 axis = global_A - global_B;
		real_t depth = axis.dot(c.normal);

		if (depth <= 0.0) {
			continue;
		}

#ifdef DEBUG_ENABLED
		if (space->is_debugging_contacts()) {
			space->add_debug_contact(global_A + offset_A);
			space->add_debug_contact(global_B + offset_A);
		}
#endif

		c.rA = global_A - A->get_center_of_mass();
		c.rB = global_B - B->get_center_of_mass() - offset_B;

		if (!report_contacts_only) {
			// Precompute normal mass, tangent mass, and bias.
			real_t rnA = c.rA.dot(c.normal);
			real_t rnB = c.rB.dot(c.normal);
			real_t kNormal = inv_mass_A + inv_mass_B;
			kNormal += inv_inertia_A * (c.rA.dot(c.rA) - rnA * rnA) + inv_inertia_B * (c.rB.dot(c.rB) - rnB * rnB);
			c.mass_normal = kNormal > 0.0 ? 1.0f / kNormal : 0.0f;
		}

		Vector2 P = c.acc_normal_impulse * c.normal;
		if (has_friction) {
			// Friction can change between frames. Restrict the cached total
			// tangent impulse to the *current* Coulomb cone before applying it.
			const real_t cached_tangent_limit = mixed_friction * c.acc_normal_impulse;
			c.acc_tangent_impulse = CLAMP(c.acc_tangent_impulse, -cached_tangent_limit, cached_tangent_limit);
			const Vector2 tangent = c.normal.orthogonal();
			if (!report_contacts_only) {
				const real_t rtA = c.rA.dot(tangent);
				const real_t rtB = c.rB.dot(tangent);
				real_t kTangent = inv_mass_A + inv_mass_B;
				kTangent += inv_inertia_A * (c.rA.dot(c.rA) - rtA * rtA) + inv_inertia_B * (c.rB.dot(c.rB) - rtB * rtB);
				c.mass_tangent = kTangent > 0.0 ? 1.0f / kTangent : 0.0f;
			}

			P += c.acc_tangent_impulse * tangent;
		} else {
			// Friction may have changed since the previous step. Drop cached
			// tangential impulses instead of applying then cancelling them.
			c.mass_tangent = 0.0;
			c.acc_tangent_impulse = 0.0;
		}

		if (!report_contacts_only) {
			// Cap deep-overlap recovery so embedded bodies cannot be violently
			// pushed out in a single tick (Box2D-style contact tuning).
			c.bias = space->limit_contact_bias(-bias * inv_dt * MIN(0.0f, -depth + max_penetration));
		}
		c.depth = depth;

		c.acc_impulse -= P;

		if (A->can_report_contacts() || B->can_report_contacts()) {
			Vector2 crB = Vector2(-B->get_angular_velocity() * c.rB.y, B->get_angular_velocity() * c.rB.x) + B->get_linear_velocity();
			Vector2 crA = Vector2(-A->get_angular_velocity() * c.rA.y, A->get_angular_velocity() * c.rA.x) + A->get_linear_velocity();
			if (A->can_report_contacts()) {
				A->add_contact(global_A + offset_A, -c.normal, depth, shape_A, crA, global_B + offset_A, shape_B, B->get_instance_id(), B->get_self(), crB, c.acc_impulse);
			}
			if (B->can_report_contacts()) {
				B->add_contact(global_B + offset_A, c.normal, depth, shape_B, crB, global_A + offset_A, shape_A, A->get_instance_id(), A->get_self(), crA, c.acc_impulse);
			}
		}

		if (report_contacts_only) {
			collided = false;
			continue;
		}

#ifdef ACCUMULATE_IMPULSES
		{
			// Apply normal + friction impulse
			if (collide_A) {
				A->apply_impulse(-P, c.rA + A->get_center_of_mass());
			}
			if (collide_B) {
				B->apply_impulse(P, c.rB + B->get_center_of_mass());
			}
		}
#endif

		c.bounce = mixed_restitution;
		if (c.bounce) {
			Vector2 crA(-A->get_prev_angular_velocity() * c.rA.y, A->get_prev_angular_velocity() * c.rA.x);
			Vector2 crB(-B->get_prev_angular_velocity() * c.rB.y, B->get_prev_angular_velocity() * c.rB.x);
			Vector2 dv = B->get_prev_linear_velocity() + crB - A->get_prev_linear_velocity() - crA;
			const real_t normal_velocity = dv.dot(c.normal);
			// Following Box2D/Jolt, suppress restitution for slow or separating
			// contacts. Use pre-solve velocity so accumulated impulses do not
			// spuriously trigger another bounce on a resting contact.
			c.bounce = normal_velocity < -space->get_restitution_velocity_threshold() ? c.bounce * normal_velocity : 0.0;
		}

		c.active = true;
		do_process = true;
	}

	// Precompute the two-contact effective mass matrix once per timestep.
	// Contact anchors and mass properties are fixed throughout the solve.
	if (do_process && space->is_block_solver_enabled() && contact_count == 2 &&
			contacts[0].active && contacts[1].active &&
			contacts[0].normal.dot(contacts[1].normal) > real_t(0.9999)) {
		const Contact &c0 = contacts[0];
		const Contact &c1 = contacts[1];
		const Vector2 &normal = c0.normal;
		const real_t rA0 = c0.rA.cross(normal);
		const real_t rA1 = c1.rA.cross(normal);
		const real_t rB0 = c0.rB.cross(normal);
		const real_t rB1 = c1.rB.cross(normal);
		const real_t inv_mass = inv_mass_A + inv_mass_B;
		const real_t k00 = inv_mass + inv_inertia_A * rA0 * rA0 + inv_inertia_B * rB0 * rB0;
		const real_t k01 = inv_mass + inv_inertia_A * rA0 * rA1 + inv_inertia_B * rB0 * rB1;
		const real_t k11 = inv_mass + inv_inertia_A * rA1 * rA1 + inv_inertia_B * rB1 * rB1;
		const real_t determinant = k00 * k11 - k01 * k01;
		const real_t largest_diagonal = MAX(k00, k11);

		// Singular and poorly conditioned pairs use per-contact PGS instead.
		if (k00 > 0.0 && k11 > 0.0 && determinant > CMP_EPSILON &&
				largest_diagonal * largest_diagonal < real_t(100.0) * determinant) {
			block_k00 = k00;
			block_k01 = k01;
			block_k11 = k11;
			block_inv_determinant = real_t(1.0) / determinant;
			block_normal_valid = true;
		}
	}

	return do_process;
}

void GodotBodyPair2D::solve(real_t p_step) {
	if (!collided || oneway_disabled) {
		return;
	}

	const real_t max_bias_av = MAX_BIAS_ROTATION / p_step;

	real_t inv_mass_A = collide_A ? A->get_inv_mass() : 0.0;
	real_t inv_mass_B = collide_B ? B->get_inv_mass() : 0.0;
	// Material properties are constant during this constraint solve.
	const real_t friction = mixed_friction;

	// Solve the two-point LCP with the conditioned matrix cached in pre_solve.
	// Only relative contact velocities need updating on every iteration.
	bool block_solved = false;
	if (block_normal_valid && contacts[0].active && contacts[1].active) {
		Contact &c0 = contacts[0];
		Contact &c1 = contacts[1];
		const Vector2 &normal = c0.normal;
		const real_t rA0 = c0.rA.cross(normal);
		const real_t rA1 = c1.rA.cross(normal);
		const real_t rB0 = c0.rB.cross(normal);
		const real_t rB1 = c1.rB.cross(normal);
		const real_t relative_normal_velocity = (B->get_linear_velocity() - A->get_linear_velocity()).dot(normal);
		const real_t angular_A = A->get_angular_velocity();
		const real_t angular_B = B->get_angular_velocity();
		const real_t vn0 = relative_normal_velocity - angular_A * rA0 + angular_B * rB0;
		const real_t vn1 = relative_normal_velocity - angular_A * rA1 + angular_B * rB1;
		const real_t old0 = c0.acc_normal_impulse;
		const real_t old1 = c1.acc_normal_impulse;

		const real_t b0 = vn0 + c0.bounce - block_k00 * old0 - block_k01 * old1;
		const real_t b1 = vn1 + c1.bounce - block_k01 * old0 - block_k11 * old1;
		real_t next0 = -(block_k11 * b0 - block_k01 * b1) * block_inv_determinant;
		real_t next1 = -(block_k00 * b1 - block_k01 * b0) * block_inv_determinant;
		bool valid = next0 >= 0.0 && next1 >= 0.0;

		// Complementarity: both active, one active, or both inactive.
		if (!valid) {
			next0 = 0.0;
			next1 = -b1 / block_k11;
			valid = next1 >= 0.0 && block_k01 * next1 + b0 >= 0.0;
		}
		if (!valid) {
			next1 = 0.0;
			next0 = -b0 / block_k00;
			valid = next0 >= 0.0 && block_k01 * next0 + b1 >= 0.0;
		}
		if (!valid) {
			next0 = 0.0;
			next1 = 0.0;
			valid = b0 >= 0.0 && b1 >= 0.0;
		}

		if (valid) {
			const real_t delta0 = next0 - old0;
			const real_t delta1 = next1 - old1;
			const Vector2 impulse0 = normal * delta0;
			const Vector2 impulse1 = normal * delta1;
			c0.acc_normal_impulse = next0;
			c1.acc_normal_impulse = next1;
			// After convergence the block LCP often returns the previous
			// impulse for either or both points. Do not invoke no-op transforms.
			if (delta0 != 0.0) {
				if (collide_A) {
					A->apply_impulse(-impulse0, c0.rA + A->get_center_of_mass());
				}
				if (collide_B) {
					B->apply_impulse(impulse0, c0.rB + B->get_center_of_mass());
				}
				c0.acc_impulse -= impulse0;
			}
			if (delta1 != 0.0) {
				if (collide_A) {
					A->apply_impulse(-impulse1, c1.rA + A->get_center_of_mass());
				}
				if (collide_B) {
					B->apply_impulse(impulse1, c1.rB + B->get_center_of_mass());
				}
				c1.acc_impulse -= impulse1;
			}
			block_solved = true;
		}
	}

	for (int i = 0; i < contact_count; ++i) {
		Contact &c = contacts[i];

		if (!c.active) {
			continue;
		}

		// Relative velocity at contact

		Vector2 crA(-A->get_angular_velocity() * c.rA.y, A->get_angular_velocity() * c.rA.x);
		Vector2 crB(-B->get_angular_velocity() * c.rB.y, B->get_angular_velocity() * c.rB.x);
		Vector2 dv = B->get_linear_velocity() + crB - A->get_linear_velocity() - crA;

		Vector2 crbA(-A->get_biased_angular_velocity() * c.rA.y, A->get_biased_angular_velocity() * c.rA.x);
		Vector2 crbB(-B->get_biased_angular_velocity() * c.rB.y, B->get_biased_angular_velocity() * c.rB.x);
		Vector2 dbv = B->get_biased_linear_velocity() + crbB - A->get_biased_linear_velocity() - crbA;

		real_t vn = dv.dot(c.normal);
		real_t vbn = dbv.dot(c.normal);

		const real_t jbn = (c.bias - vbn) * c.mass_normal;
		const real_t jbnOld = c.acc_bias_impulse;
		c.acc_bias_impulse = MAX(jbnOld + jbn, 0.0f);

		// Once the accumulated bias impulse converges, avoid two no-op
		// body updates (especially expensive for dense resting contacts).
		const real_t bias_delta = c.acc_bias_impulse - jbnOld;
		if (bias_delta != 0.0) {
			const Vector2 jb = c.normal * bias_delta;
			if (collide_A) {
				A->apply_bias_impulse(-jb, c.rA + A->get_center_of_mass(), max_bias_av);
			}
			if (collide_B) {
				B->apply_bias_impulse(jb, c.rB + B->get_center_of_mass(), max_bias_av);
			}
			// Bias velocity is unchanged when no incremental impulse was applied.
			crbA = Vector2(-A->get_biased_angular_velocity() * c.rA.y, A->get_biased_angular_velocity() * c.rA.x);
			crbB = Vector2(-B->get_biased_angular_velocity() * c.rB.y, B->get_biased_angular_velocity() * c.rB.x);
			dbv = B->get_biased_linear_velocity() + crbB - A->get_biased_linear_velocity() - crbA;
			vbn = dbv.dot(c.normal);
		}

		const real_t total_inverse_mass = inv_mass_A + inv_mass_B;
		if (total_inverse_mass > 0.0 && Math::abs(-vbn + c.bias) > MIN_VELOCITY) {
			real_t jbn_com = (-vbn + c.bias) / total_inverse_mass;
			real_t jbnOld_com = c.acc_bias_impulse_center_of_mass;
			c.acc_bias_impulse_center_of_mass = MAX(jbnOld_com + jbn_com, 0.0f);

			const Vector2 jb_com = c.normal * (c.acc_bias_impulse_center_of_mass - jbnOld_com);
			if (jb_com != Vector2()) {
				if (collide_A) {
					A->apply_bias_impulse(-jb_com, A->get_center_of_mass(), 0.0f);
				}
				if (collide_B) {
					B->apply_bias_impulse(jb_com, B->get_center_of_mass(), 0.0f);
				}
			}
		}

		Vector2 j;
		if (block_solved) {
			// Normal impulses were applied together above; solve friction
			// against the resulting velocity and updated normal impulse.
			j = Vector2();
		} else {
			const real_t jn = -(c.bounce + vn) * c.mass_normal;
			const real_t old_normal = c.acc_normal_impulse;
			c.acc_normal_impulse = MAX(old_normal + jn, 0.0f);
			j = c.normal * (c.acc_normal_impulse - old_normal);
		}
		if (friction > 0.0) {
			const Vector2 tangent = c.normal.orthogonal();
			const real_t vt = dv.dot(tangent);
			const real_t jt_max = friction * c.acc_normal_impulse;
			const real_t jt = -vt * c.mass_tangent;
			const real_t jt_old = c.acc_tangent_impulse;
			c.acc_tangent_impulse = CLAMP(jt_old + jt, -jt_max, jt_max);
			j += tangent * (c.acc_tangent_impulse - jt_old);
		} else {
			c.acc_tangent_impulse = 0.0;
		}

		// The projected Gauss-Seidel impulse is often exactly zero once a
		// resting contact converges. Skipping it does not alter velocities.
		if (j != Vector2()) {
			if (collide_A) {
				A->apply_impulse(-j, c.rA + A->get_center_of_mass());
			}
			if (collide_B) {
				B->apply_impulse(j, c.rB + B->get_center_of_mass());
			}
			c.acc_impulse -= j;
		}
	}

	// Solve one Coulomb-limited angular constraint for the entire manifold.
	// Use the summed normal impulse so neither extra contacts nor solver
	// iterations multiply the resistance torque.
	if (rolling_impulse_scale > 0.0) {
		const real_t inverse_inertia_A = collide_A ? A->get_inv_inertia() : 0.0;
		const real_t inverse_inertia_B = collide_B ? B->get_inv_inertia() : 0.0;
		const real_t inverse_angular_mass = inverse_inertia_A + inverse_inertia_B;
		if (inverse_angular_mass > 0.0) {
			real_t normal_impulse = 0.0;
			for (int i = 0; i < contact_count; ++i) {
				if (contacts[i].active) {
					normal_impulse += contacts[i].acc_normal_impulse;
				}
			}
			const real_t previous_impulse = rolling_impulse;
			rolling_impulse = godot_physics_accumulate_rolling_impulse(
					rolling_impulse, B->get_angular_velocity() - A->get_angular_velocity(),
					inverse_angular_mass, normal_impulse, rolling_impulse_scale);
			const real_t delta_impulse = rolling_impulse - previous_impulse;
			if (delta_impulse != 0.0) {
				if (collide_A) {
					A->apply_torque_impulse(-delta_impulse);
				}
				if (collide_B) {
					B->apply_torque_impulse(delta_impulse);
				}
			}
		}
	}
}

GodotBodyPair2D::GodotBodyPair2D(GodotBody2D *p_A, int p_shape_A, GodotBody2D *p_B, int p_shape_B) :
		GodotConstraint2D(_arr, 2) {
	A = p_A;
	B = p_B;
	shape_A = p_shape_A;
	shape_B = p_shape_B;
	space = A->get_space();
	A->add_constraint(this, 0);
	B->add_constraint(this, 1);
}

GodotBodyPair2D::~GodotBodyPair2D() {
	A->remove_constraint(this, 0);
	B->remove_constraint(this, 1);
}
