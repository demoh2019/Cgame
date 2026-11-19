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
#include "godot_space_2d.h"

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
	contact.normal = (p_point_A - p_point_B).normalized();
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
		if (c.used) {
			// Already matched to a contact generated during this setup pass.
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
			contact.acc_tangent_impulse = previous.acc_tangent_impulse;
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

// `_test_ccd` prevents tunneling by slowing down a high velocity body that is about to collide so
// that next frame it will be at an appropriate location to collide (i.e. slight overlap).
// WARNING: The way velocity is adjusted down to cause a collision means the momentum will be
// weaker than it should for a bounce!
// Process: Only proceed if body A's motion is high relative to its size.
// Cast forward along motion vector to see if A is going to enter/pass B's collider next frame, only proceed if it does.
// Adjust the velocity of A down so that it will just slightly intersect the collider instead of blowing right past it.
bool GodotBodyPair2D::_test_ccd(real_t p_step, GodotBody2D *p_A, int p_shape_A, const Transform2D &p_xform_A, GodotBody2D *p_B, int p_shape_B, const Transform2D &p_xform_B) {
	Vector2 motion = p_A->get_linear_velocity() * p_step;
	real_t mlen = motion.length();
	if (mlen < CMP_EPSILON) {
		return false;
	}

	Vector2 mnormal = motion / mlen;

	real_t min = 0.0, max = 0.0;
	p_A->get_shape(p_shape_A)->project_rangev(mnormal, p_xform_A, min, max);

	// Did it move enough in this direction to even attempt raycast?
	// Let's say it should move more than 1/3 the size of the object in that axis.
	bool fast_object = mlen > (max - min) * 0.3;
	if (!fast_object) {
		return false;
	}

	// A is moving fast enough that tunneling might occur. See if it's really about to collide.

	// Roughly predict body B's position in the next frame (ignoring collisions).
	Transform2D predicted_xform_B = p_xform_B.translated(p_B->get_linear_velocity() * p_step);

	// CCD cast-ray uses the leading support feature, which may contain two
	// vertices (a box face, capsule side, or polygon edge). Test both ends:
	// a single support ray can miss a narrow obstacle hit by the other end.
	GodotShape2D *shape_A_ptr = p_A->get_shape(p_shape_A);
	GodotShape2D *shape_B_ptr = p_B->get_shape(p_shape_B);
	Vector2 supports_A[2];
	int support_count_A = 0;
	shape_A_ptr->get_supports(p_xform_A.basis_xform_inv(mnormal).normalized(), supports_A, support_count_A);
	if (support_count_A == 0) {
		return false;
	}

	// All rays share the same target transform and direction. Compare squared
	// hit distances in target-local space to avoid a square root for each hit.
	const Transform2D predicted_inv_B = predicted_xform_B.affine_inverse();
	bool found_hit = false;
	real_t hit_distance_squared = 0.0;
	Vector2 hit_local;
	Vector2 hit_support_from;
	for (int support_idx = 0; support_idx < support_count_A; ++support_idx) {
		const Vector2 from = p_xform_A.xform(supports_A[support_idx]);
		const Vector2 local_from = predicted_inv_B.xform(from - motion * 0.1);
		const Vector2 local_to = predicted_inv_B.xform(from + motion);
		Vector2 rpos, rnorm;
		if (!shape_B_ptr->intersect_segment(local_from, local_to, rpos, rnorm)) {
			continue;
		}

		const real_t candidate_distance_squared = local_from.distance_squared_to(rpos);
		if (!found_hit || candidate_distance_squared < hit_distance_squared) {
			found_hit = true;
			hit_distance_squared = candidate_distance_squared;
			hit_local = rpos;
			hit_support_from = from;
		}
	}
	if (!found_hit) {
		return false;
	}

	// Check one-way collision based on motion direction.
	if (p_A->get_shape(p_shape_A)->allows_one_way_collision() && p_B->is_shape_set_as_one_way_collision(p_shape_B)) {
		Vector2 direction = predicted_xform_B.basis_xform(p_B->get_shape_one_way_collision_direction(p_shape_B)).normalized();

		if (direction.dot(mnormal) < CMP_EPSILON) {
			collided = false;
			oneway_disabled = true;
			return false;
		}
	}

	// Shorten the linear velocity so it does not hit, but gets close enough,
	// next frame will hit softly or soft enough.
	Vector2 hitpos = predicted_xform_B.xform(hit_local);

	real_t newlen = hitpos.distance_to(hit_support_from) + (max - min) * 0.01; // adding 1% of body length to the distance between collision and support point should cause body A's support point to arrive just within B's collider next frame.
	p_A->set_linear_velocity(mnormal * (newlen / p_step));

	return true;
}

real_t combine_bounce(GodotBody2D *A, GodotBody2D *B) {
	return CLAMP(A->get_bounce() + B->get_bounce(), 0, 1);
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
	offset_B = B->get_transform().get_origin() - A->get_transform().get_origin();

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
	const bool has_friction = mixed_friction > 0.0;

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
			c.bias = -bias * inv_dt * MIN(0.0f, -depth + max_penetration);
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

		c.bounce = combine_bounce(A, B);
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

		real_t jbn = (c.bias - vbn) * c.mass_normal;
		real_t jbnOld = c.acc_bias_impulse;
		c.acc_bias_impulse = MAX(jbnOld + jbn, 0.0f);

		Vector2 jb = c.normal * (c.acc_bias_impulse - jbnOld);

		if (collide_A) {
			A->apply_bias_impulse(-jb, c.rA + A->get_center_of_mass(), max_bias_av);
		}
		if (collide_B) {
			B->apply_bias_impulse(jb, c.rB + B->get_center_of_mass(), max_bias_av);
		}

		crbA = Vector2(-A->get_biased_angular_velocity() * c.rA.y, A->get_biased_angular_velocity() * c.rA.x);
		crbB = Vector2(-B->get_biased_angular_velocity() * c.rB.y, B->get_biased_angular_velocity() * c.rB.x);
		dbv = B->get_biased_linear_velocity() + crbB - A->get_biased_linear_velocity() - crbA;

		vbn = dbv.dot(c.normal);

		if (Math::abs(-vbn + c.bias) > MIN_VELOCITY) {
			real_t jbn_com = (-vbn + c.bias) / (inv_mass_A + inv_mass_B);
			real_t jbnOld_com = c.acc_bias_impulse_center_of_mass;
			c.acc_bias_impulse_center_of_mass = MAX(jbnOld_com + jbn_com, 0.0f);

			Vector2 jb_com = c.normal * (c.acc_bias_impulse_center_of_mass - jbnOld_com);

			if (collide_A) {
				A->apply_bias_impulse(-jb_com, A->get_center_of_mass(), 0.0f);
			}
			if (collide_B) {
				B->apply_bias_impulse(jb_com, B->get_center_of_mass(), 0.0f);
			}
		}

		real_t jn = -(c.bounce + vn) * c.mass_normal;
		real_t jnOld = c.acc_normal_impulse;
		c.acc_normal_impulse = MAX(jnOld + jn, 0.0f);

		Vector2 j = c.normal * (c.acc_normal_impulse - jnOld);
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

		if (collide_A) {
			A->apply_impulse(-j, c.rA + A->get_center_of_mass());
		}
		if (collide_B) {
			B->apply_impulse(j, c.rB + B->get_center_of_mass());
		}
		c.acc_impulse -= j;
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
