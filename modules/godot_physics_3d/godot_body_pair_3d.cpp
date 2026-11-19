/**************************************************************************/
/*  godot_body_pair_3d.cpp                                                */
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

#include "godot_body_pair_3d.h"

#include "godot_collision_solver_3d.h"
#include "godot_contact_normal_3d.h"
#include "godot_space_3d.h"
#include "servers/physics_manifold_reduction_3d.h"
#include "servers/physics_ccd_sphere_toi.h"

#include <cfloat> // FLT_MAX

#define MIN_VELOCITY 0.0001
#define MAX_BIAS_ROTATION (Math::PI / 8)

void GodotBodyPair3D::_contact_added_callback(const Vector3 &p_point_A, int p_index_A, const Vector3 &p_point_B, int p_index_B, const Vector3 &normal, void *p_userdata) {
	GodotBodyPair3D *pair = static_cast<GodotBodyPair3D *>(p_userdata);
	pair->contact_added_callback(p_point_A, p_index_A, p_point_B, p_index_B, normal);
}

void GodotBodyPair3D::contact_added_callback(const Vector3 &p_point_A, int, const Vector3 &p_point_B, int p_index_B, const Vector3 &normal) {
	Vector3 local_A = A->get_inv_transform().basis.xform(p_point_A);
	Vector3 local_B = B->get_inv_transform().basis.xform(p_point_B - offset_B);

	int new_index = contact_count;

	ERR_FAIL_COND(new_index >= (MAX_CONTACTS + 1));

	Contact contact;

	contact.index_B = p_index_B;
	contact.local_A = local_A;
	contact.local_B = local_B;
	contact.normal = godot_physics_3d_contact_normal(p_point_A, p_point_B, normal);
	contact.used = true;

	// Match each new manifold point to the closest UNUSED old contact.
	// A first-match search can recycle the same impulse into multiple nearby
	// points when a box slides or rotates. Keep the per-contact search bounded
	// by MAX_CONTACTS (4), without extra allocations.
	const real_t contact_recycle_radius = space->get_contact_recycle_radius();
	const real_t contact_recycle_radius_squared = contact_recycle_radius * contact_recycle_radius;
	int best_match = -1;
	real_t best_distance_squared = 0.0;

	for (int i = 0; i < contact_count; i++) {
		const Contact &previous = contacts[i];
		if (previous.used || previous.normal.dot(contact.normal) < real_t(0.98)) {
			// Face/edge transitions can produce geometrically close anchors
			// with incompatible normals. Keep searching for a valid contact.
			continue;
		}

		const real_t distance_A_squared = previous.local_A.distance_squared_to(local_A);
		if (distance_A_squared >= contact_recycle_radius_squared) {
			continue;
		}
		const real_t distance_B_squared = previous.local_B.distance_squared_to(local_B);
		if (distance_B_squared >= contact_recycle_radius_squared) {
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
		// Do not reuse impulses after the normal changes sharply at an edge.
		if (previous.normal.dot(contact.normal) >= real_t(0.98)) {
			contact.acc_normal_impulse = previous.acc_normal_impulse;
			contact.acc_bias_impulse = previous.acc_bias_impulse;
			contact.acc_bias_impulse_center_of_mass = previous.acc_bias_impulse_center_of_mass;
			// Friction must remain tangent when the manifold normal rotates.
			contact.acc_tangent_impulse = previous.acc_tangent_impulse - contact.normal * previous.acc_tangent_impulse.dot(contact.normal);
		}
		previous = contact;
		return;
	}

	// Figure out if the contact amount must be reduced to fit the new contact.
	if (new_index == MAX_CONTACTS) {
		if (space->is_manifold_spread_reduction_enabled()) {
			// When five candidates compete for four slots, preserve the
			// deepest point and maximize patch coverage on a common plane.
			// Coordinates are relative to body A to reduce floating-point
			// error in large worlds. This path allocates no heap memory.
			const Basis &basis_A = A->get_transform().basis;
			const Basis &basis_B = B->get_transform().basis;
			Vector3 candidate_points[MAX_CONTACTS + 1];
			Vector3 candidate_normals[MAX_CONTACTS + 1];
			real_t candidate_depths[MAX_CONTACTS + 1];
			for (int i = 0; i <= MAX_CONTACTS; i++) {
				const Contact &c = i == MAX_CONTACTS ? contact : contacts[i];
				const Vector3 point_A = basis_A.xform(c.local_A);
				const Vector3 point_B = basis_B.xform(c.local_B) + offset_B;
				candidate_points[i] = point_A;
				candidate_normals[i] = c.normal;
				candidate_depths[i] = (point_A - point_B).dot(c.normal);
			}
			const int replacement = GodotPhysicsManifoldReduction3D::choose_replacement(candidate_points, candidate_depths, candidate_normals);
			if (replacement >= 0) {
				contacts[replacement] = contact;
			}
			return;
		}
		// Legacy: remove the contact with the minimum depth.

		const Basis &basis_A = A->get_transform().basis;
		const Basis &basis_B = B->get_transform().basis;

		int least_deep = -1;
		real_t min_depth;

		// Start with depth for new contact.
		{
			Vector3 global_A = basis_A.xform(contact.local_A);
			Vector3 global_B = basis_B.xform(contact.local_B) + offset_B;

			Vector3 axis = global_A - global_B;
			min_depth = axis.dot(contact.normal);
		}

		for (int i = 0; i < contact_count; i++) {
			const Contact &c = contacts[i];
			Vector3 global_A = basis_A.xform(c.local_A);
			Vector3 global_B = basis_B.xform(c.local_B) + offset_B;

			Vector3 axis = global_A - global_B;
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

void GodotBodyPair3D::validate_contacts() {
	// Make sure to erase contacts that are no longer valid.
	real_t max_separation = space->get_contact_max_separation();
	real_t max_separation2 = max_separation * max_separation;

	const Basis &basis_A = A->get_transform().basis;
	const Basis &basis_B = B->get_transform().basis;

	for (int i = 0; i < contact_count; i++) {
		Contact &c = contacts[i];

		bool erase = false;
		if (!c.used) {
			// Was left behind in previous frame.
			erase = true;
		} else {
			c.used = false;

			Vector3 global_A = basis_A.xform(c.local_A);
			Vector3 global_B = basis_B.xform(c.local_B) + offset_B;
			Vector3 axis = global_A - global_B;
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
bool GodotBodyPair3D::_test_ccd(real_t p_step, GodotBody3D *p_A, int p_shape_A, const Transform3D &p_xform_A, GodotBody3D *p_B, int p_shape_B, const Transform3D &p_xform_B) {
	if (p_step <= 0.0) {
		return false;
	}

	GodotShape3D *shape_A_ptr = p_A->get_shape(p_shape_A);
	GodotShape3D *shape_B_ptr = p_B->get_shape(p_shape_B);

	const Vector3 velocity_A = p_A->get_linear_velocity();
	const Vector3 motion_A = velocity_A * p_step;
	if (motion_A.length_squared() == 0.0) {
		return false;
	}

	// A static body may use a surface velocity for contact friction while
	// its geometry remains stationary. CCD must use geometry motion.
	const Vector3 velocity_B = p_B->get_mode() == PS3DE::BODY_MODE_STATIC ? Vector3() : p_B->get_linear_velocity();
	const Vector3 relative_motion = motion_A - velocity_B * p_step;
	const real_t motion_length = relative_motion.length();
	if (motion_length < CMP_EPSILON || motion_A.dot(relative_motion) <= 0.0) {
		// Co-moving shapes do not close. B's own CCD can handle an
		// obstacle approaching A from behind.
		return false;
	}
	const Vector3 direction = relative_motion / motion_length;

	real_t min_projection = 0.0;
	real_t max_projection = 0.0;
	shape_A_ptr->project_range(direction, p_xform_A, min_projection, max_projection);
	const real_t extent = max_projection - min_projection;
	if (motion_length <= extent * real_t(0.3)) {
		return false;
	}

	// A ray through the leading sphere support can miss an oblique
	// sphere/sphere collision, even though the swept volumes overlap.
	// For true spheres (not ellipsoids), solve the exact linear TOI first.
	if (shape_A_ptr->get_type() == PS3DE::SHAPE_SPHERE && shape_B_ptr->get_type() == PS3DE::SHAPE_SPHERE &&
			p_A->get_angular_velocity() == Vector3() && p_B->get_angular_velocity() == Vector3()) {
		const double scale_A = physics_ccd_uniform_sphere_scale(p_xform_A);
		const double scale_B = physics_ccd_uniform_sphere_scale(p_xform_B);
		if (scale_A > 0.0 && scale_B > 0.0) {
			const double radius_A = double(static_cast<GodotSphereShape3D *>(shape_A_ptr)->get_radius()) * scale_A;
			const double radius_B = double(static_cast<GodotSphereShape3D *>(shape_B_ptr)->get_radius()) * scale_B;
			const Vector3 center_delta = p_xform_A.origin - p_xform_B.origin;
			double impact_fraction = 0.0;
			if (!physics_ccd_sphere_toi(center_delta, relative_motion, radius_A + radius_B, impact_fraction)) {
				return false;
			}

			const real_t allowed_distance = CLAMP(real_t(impact_fraction * double(motion_length)) + extent * real_t(0.01), real_t(0.0), motion_length);
			const Vector3 desired_velocity = velocity_B + direction * (allowed_distance / p_step);
			const real_t initial_speed = velocity_A.length();
			const Vector3 travel_direction = velocity_A / initial_speed;
			const real_t clipped_speed = CLAMP(desired_velocity.dot(travel_direction), real_t(0.0), initial_speed);
			p_A->set_linear_velocity(travel_direction * clipped_speed);
			return true;
		}
		// Affine shear/nonuniform scale yields an ellipsoid; retain the
		// generic support cast rather than using an incorrect sphere TOI.
	}

	// A leading face may have several support vertices. The target
	// transform is shared by all rays and is inverted only once.
	if (p_xform_B.basis.determinant() == 0.0) {
		return false;
	}
	const Transform3D inverse_B = p_xform_B.affine_inverse();
	static const int MAX_CCD_SUPPORTS = 16;
	Vector3 supports[MAX_CCD_SUPPORTS];
	int support_count = 0;
	GodotShape3D::FeatureType support_type = GodotShape3D::FEATURE_POINT;
	shape_A_ptr->get_supports(p_xform_A.basis.xform_inv(direction).normalized(),
			MAX_CCD_SUPPORTS, supports, support_count, support_type);
	if (support_count == 0) {
		return false;
	}

	bool found_hit = false;
	real_t best_hit_distance = 0.0;
	for (int i = 0; i < support_count; ++i) {
		const Vector3 from = p_xform_A.xform(supports[i]);
		const Vector3 local_from = inverse_B.xform(from - relative_motion * real_t(0.1));
		const Vector3 local_to = inverse_B.xform(from + relative_motion);
		Vector3 hit_point;
		Vector3 hit_normal;
		int face_index = -1;
		if (!shape_B_ptr->intersect_segment(local_from, local_to, hit_point, hit_normal, face_index, true)) {
			continue;
		}

		// A local-space length is not comparable between supports under
		// an affine target scale or shear. Rank by world-space progress.
		const real_t hit_distance = direction.dot(p_xform_B.xform(hit_point) - from);
		if (!found_hit || hit_distance < best_hit_distance) {
			found_hit = true;
			best_hit_distance = hit_distance;
		}
	}

	if (!found_hit) {
		return false;
	}

	// Legacy cast-ray CCD limits velocity, not time of impact. Preserve
	// the original travel direction and never accelerate or reverse A.
	const real_t allowed_distance = CLAMP(best_hit_distance + extent * real_t(0.01), real_t(0.0), motion_length);
	const Vector3 desired_velocity = velocity_B + direction * (allowed_distance / p_step);
	const real_t initial_speed = velocity_A.length();
	const Vector3 travel_direction = velocity_A / initial_speed;
	const real_t clipped_speed = CLAMP(desired_velocity.dot(travel_direction), real_t(0.0), initial_speed);
	p_A->set_linear_velocity(travel_direction * clipped_speed);
	return true;
}

bool GodotBodyPair3D::setup(real_t p_step) {
	check_ccd = false;

	if (!A->interacts_with(B) || A->has_exception(B->get_self()) || B->has_exception(A->get_self())) {
		collided = false;
		return false;
	}

	collide_A = (A->get_mode() > PS3DE::BODY_MODE_KINEMATIC) && A->collides_with(B);
	collide_B = (B->get_mode() > PS3DE::BODY_MODE_KINEMATIC) && B->collides_with(A);

	report_contacts_only = false;
	if (!collide_A && !collide_B) {
		if ((A->get_max_contacts_reported() > 0) || (B->get_max_contacts_reported() > 0)) {
			report_contacts_only = true;
		} else {
			collided = false;
			return false;
		}
	}

	const Vector3 new_offset_B = B->get_transform().get_origin() - A->get_transform().get_origin();
	// Translate both rigid bodies together without redoing SAT/GJK. The
	// contact anchors and world normal are unchanged if the relative offset
	// and both shape orientations match exactly. Do not approximate poses.
	const bool relative_translation_unchanged = offset_B == new_offset_B;
	offset_B = new_offset_B;

	// Geometry versions still change on local shape edits, rotation, scaling,
	// shearing, filters and space changes. CCD always uses the narrow phase.
	const bool ccd_enabled = A->is_continuous_collision_detection_enabled() || B->is_continuous_collision_detection_enabled();
	const uint64_t geometry_version_a = A->get_collision_geometry_version();
	const uint64_t geometry_version_b = B->get_collision_geometry_version();
	// Reuse a separating narrowphase result for persistent broadphase
	// pairs only if their *exact* relative shape pose is unchanged.
	// Geometry revisions cover orientation and shape mutations; CCD bypasses.
	if (relative_translation_unchanged && contact_recycling.can_reuse_separation(geometry_version_a, geometry_version_b, ccd_enabled)) {
		collided = false;
		return false;
	}
	if (relative_translation_unchanged && contact_recycling.can_reuse(geometry_version_a, geometry_version_b, collided, contact_count, ccd_enabled)) {
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

	validate_contacts();

	const Vector3 &offset_A = A->get_transform().get_origin();
	Transform3D xform_Au = Transform3D(A->get_transform().basis, Vector3());
	Transform3D xform_A = xform_Au * A->get_shape_transform(shape_A);

	Transform3D xform_Bu = B->get_transform();
	xform_Bu.origin -= offset_A;
	Transform3D xform_B = xform_Bu * B->get_shape_transform(shape_B);

	GodotShape3D *shape_A_ptr = A->get_shape(shape_A);
	GodotShape3D *shape_B_ptr = B->get_shape(shape_B);

	collided = GodotCollisionSolver3D::solve_static(shape_A_ptr, xform_A, shape_B_ptr, xform_B, _contact_added_callback, this, &sep_axis);
	contact_recycling.remember(geometry_version_a, geometry_version_b, collided);

	if (!collided) {
		if (A->is_continuous_collision_detection_enabled() && collide_A) {
			check_ccd = true;
			return true;
		}

		if (B->is_continuous_collision_detection_enabled() && collide_B) {
			check_ccd = true;
			return true;
		}

		return false;
	}

	return true;
}

bool GodotBodyPair3D::pre_solve(real_t p_step) {
	if (!collided) {
		if (check_ccd) {
			const Vector3 &offset_A = A->get_transform().get_origin();
			Transform3D xform_Au = Transform3D(A->get_transform().basis, Vector3());
			Transform3D xform_A = xform_Au * A->get_shape_transform(shape_A);

			Transform3D xform_Bu = B->get_transform();
			xform_Bu.origin -= offset_A;
			Transform3D xform_B = xform_Bu * B->get_shape_transform(shape_B);

			if (A->is_continuous_collision_detection_enabled() && collide_A) {
				_test_ccd(p_step, A, shape_A, xform_A, B, shape_B, xform_B);
			}

			if (B->is_continuous_collision_detection_enabled() && collide_B) {
				_test_ccd(p_step, B, shape_B, xform_B, A, shape_A, xform_A);
			}
		}

		return false;
	}

	real_t max_penetration = space->get_contact_max_allowed_penetration();

	real_t bias = 0.8;

	GodotShape3D *shape_A_ptr = A->get_shape(shape_A);
	GodotShape3D *shape_B_ptr = B->get_shape(shape_B);

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

	const Vector3 &offset_A = A->get_transform().get_origin();

	const Basis &basis_A = A->get_transform().basis;
	const Basis &basis_B = B->get_transform().basis;

	Basis zero_basis;
	zero_basis.set_zero();

	const Basis &inv_inertia_tensor_A = collide_A ? A->get_inv_inertia_tensor() : zero_basis;
	const Basis &inv_inertia_tensor_B = collide_B ? B->get_inv_inertia_tensor() : zero_basis;

	real_t inv_mass_A = collide_A ? A->get_inv_mass() : 0.0;
	real_t inv_mass_B = collide_B ? B->get_inv_mass() : 0.0;
	// Materials may change between frames. Compute once before warm starting,
	// instead of re-mixing them for every solver iteration.
	mixed_friction = space->mix_friction(A->get_friction(), B->get_friction());
	// Materials are shared by the entire manifold; combine restitution once
	// per constraint setup, not once per contact point.
	const real_t mixed_restitution = space->mix_restitution(A->get_bounce(), B->get_bounce());
	const bool has_friction = mixed_friction > 0.0;

	// Warm-start impulses represent force integrated over the previous step.
	// Match their magnitude to a new tick duration, as in the 2D solver.
	// A large timing discontinuity invalidates the cache instead.
	const real_t previous_step = space->get_previous_step();
	const bool step_changed = previous_step > 0.0 && !Math::is_equal_approx(previous_step, p_step);
	const real_t timestep_ratio = step_changed ? p_step / previous_step : real_t(1.0);
	const bool can_scale_impulses = timestep_ratio >= real_t(0.5) && timestep_ratio <= real_t(2.0);
	// Rapier-style optional damping, defaulting to complete warm-start reuse.
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
				c.acc_tangent_impulse = Vector3();
				c.acc_bias_impulse = 0.0;
				c.acc_bias_impulse_center_of_mass = 0.0;
			}
		}

		Vector3 global_A = basis_A.xform(c.local_A);
		Vector3 global_B = basis_B.xform(c.local_B) + offset_B;

		Vector3 axis = global_A - global_B;
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
			Vector3 inertia_A = inv_inertia_tensor_A.xform(c.rA.cross(c.normal));
			Vector3 inertia_B = inv_inertia_tensor_B.xform(c.rB.cross(c.normal));
			real_t kNormal = inv_mass_A + inv_mass_B;
			kNormal += c.normal.dot(inertia_A.cross(c.rA)) + c.normal.dot(inertia_B.cross(c.rB));
			c.mass_normal = kNormal > 0.0 ? 1.0f / kNormal : 0.0f;

			// Cap deep-overlap recovery so embedded bodies cannot be violently
			// pushed out in a single tick (Box2D-style contact tuning).
			c.bias = space->limit_contact_bias(-bias * inv_dt * MIN(0.0f, -depth + max_penetration));
		}

		c.depth = depth;

		// Keep previous-frame friction inside the CURRENT material's Coulomb
		// cone. Otherwise lowering friction can still apply a too-large
		// tangential impulse during the warm start.
		if (has_friction) {
			const real_t cached_tangent_limit = mixed_friction * c.acc_normal_impulse;
			if (cached_tangent_limit <= 0.0) {
				// No normal impulse means no admissible tangent impulse.
				c.acc_tangent_impulse = Vector3();
			} else {
				// Most warm-start contacts already lie inside the Coulomb cone.
				// Avoid a square root unless a cached impulse must be clamped.
				const real_t cached_tangent_length_squared = c.acc_tangent_impulse.length_squared();
				if (cached_tangent_length_squared > cached_tangent_limit * cached_tangent_limit) {
					c.acc_tangent_impulse *= cached_tangent_limit / Math::sqrt(cached_tangent_length_squared);
				}
			}
		} else {
			c.acc_tangent_impulse = Vector3();
		}
		Vector3 j_vec = c.normal * c.acc_normal_impulse + c.acc_tangent_impulse;

		c.acc_impulse -= j_vec;

		// contact query reporting...

		if (A->can_report_contacts() || B->can_report_contacts()) {
			Vector3 crB = B->get_angular_velocity().cross(c.rB) + B->get_linear_velocity();
			Vector3 crA = A->get_angular_velocity().cross(c.rA) + A->get_linear_velocity();

			if (A->can_report_contacts()) {
				A->add_contact(global_A + offset_A, -c.normal, depth, shape_A, crA, global_B + offset_A, shape_B, B->get_instance_id(), B->get_self(), crB, c.acc_impulse);
			}

			if (B->can_report_contacts()) {
				B->add_contact(global_B + offset_A, c.normal, depth, shape_B, crB, global_A + offset_A, shape_A, A->get_instance_id(), A->get_self(), crA, -c.acc_impulse);
			}
		}

		if (report_contacts_only) {
			collided = false;
			continue;
		}

		c.active = true;
		do_process = true;

		if (collide_A) {
			A->apply_impulse(-j_vec, c.rA + A->get_center_of_mass());
		}
		if (collide_B) {
			B->apply_impulse(j_vec, c.rB + B->get_center_of_mass());
		}

		c.bounce = mixed_restitution;
		if (c.bounce) {
			Vector3 crA = A->get_prev_angular_velocity().cross(c.rA);
			Vector3 crB = B->get_prev_angular_velocity().cross(c.rB);
			Vector3 dv = B->get_prev_linear_velocity() + crB - A->get_prev_linear_velocity() - crA;
			const real_t normal_velocity = dv.dot(c.normal);
			// Suppress low-speed restitution: resting stacks should not keep
			// bouncing due to tiny solver corrections or contact jitter.
			c.bounce = normal_velocity < -space->get_restitution_velocity_threshold() ? c.bounce * normal_velocity : 0.0;
		}
	}

	return do_process;
}

void GodotBodyPair3D::solve(real_t p_step) {
	if (!collided) {
		return;
	}

	const real_t max_bias_av = MAX_BIAS_ROTATION / p_step;

	Basis zero_basis;
	zero_basis.set_zero();

	const Basis &inv_inertia_tensor_A = collide_A ? A->get_inv_inertia_tensor() : zero_basis;
	const Basis &inv_inertia_tensor_B = collide_B ? B->get_inv_inertia_tensor() : zero_basis;

	real_t inv_mass_A = collide_A ? A->get_inv_mass() : 0.0;
	real_t inv_mass_B = collide_B ? B->get_inv_mass() : 0.0;
	// Mixing is independent of contact point; compute once per solver pass.
	const real_t friction = mixed_friction;

	// Box2D's two-contact block LCP generalized to 3D tensor inertia.
	// Only solve a well-conditioned pair with nearly parallel contact normals;
	// every other manifold retains the existing sequential solver.
	bool block_solved = false;
	bool block_normal_updated[2] = { false, false };
	if (space->is_block_solver_enabled() && contact_count == 2 &&
			contacts[0].active && contacts[1].active &&
			contacts[0].normal.dot(contacts[1].normal) > real_t(0.9999)) {
		Contact &c0 = contacts[0];
		Contact &c1 = contacts[1];
		const Vector3 &normal = c0.normal;
		const Vector3 ra0 = c0.rA.cross(normal);
		const Vector3 ra1 = c1.rA.cross(normal);
		const Vector3 rb0 = c0.rB.cross(normal);
		const Vector3 rb1 = c1.rB.cross(normal);
		const Vector3 ia0 = inv_inertia_tensor_A.xform(ra0);
		const Vector3 ia1 = inv_inertia_tensor_A.xform(ra1);
		const Vector3 ib0 = inv_inertia_tensor_B.xform(rb0);
		const Vector3 ib1 = inv_inertia_tensor_B.xform(rb1);
		const real_t inv_mass = inv_mass_A + inv_mass_B;
		const real_t k00 = inv_mass + ra0.dot(ia0) + rb0.dot(ib0);
		const real_t k01 = inv_mass + ra0.dot(ia1) + rb0.dot(ib1);
		const real_t k11 = inv_mass + ra1.dot(ia1) + rb1.dot(ib1);
		const real_t det = k00 * k11 - k01 * k01;
		const real_t largest = MAX(k00, k11);

		// Prevent a nearly singular two-point system from amplifying errors.
		if (Math::is_finite(k00) && Math::is_finite(k01) &&
				Math::is_finite(k11) && Math::is_finite(det) &&
				k00 > 0.0 && k11 > 0.0 && det > CMP_EPSILON &&
				largest * largest < real_t(100.0) * det) {
			const Vector3 rel_linear = B->get_linear_velocity() - A->get_linear_velocity();
			const Vector3 angular_A = A->get_angular_velocity();
			const Vector3 angular_B = B->get_angular_velocity();
			// (omega x r) dot n = omega dot (r x n); reuse lever arms
			// from the 2x2 mass matrix instead of recomputing cross products.
			const real_t normal_linear_velocity = rel_linear.dot(normal);
			const real_t vn0 = normal_linear_velocity + angular_B.dot(rb0) - angular_A.dot(ra0);
			const real_t vn1 = normal_linear_velocity + angular_B.dot(rb1) - angular_A.dot(ra1);
			const real_t old0 = c0.acc_normal_impulse;
			const real_t old1 = c1.acc_normal_impulse;
			const real_t b0 = vn0 + c0.bounce - k00 * old0 - k01 * old1;
			const real_t b1 = vn1 + c1.bounce - k01 * old0 - k11 * old1;
			const real_t inv_det = real_t(1.0) / det;
			real_t next0 = -(k11 * b0 - k01 * b1) * inv_det;
			real_t next1 = -(k00 * b1 - k01 * b0) * inv_det;
			bool valid = Math::is_finite(next0) && Math::is_finite(next1) &&
					next0 >= 0.0 && next1 >= 0.0;
			// Complementarity: both loaded, one loaded, or neither loaded.
			if (!valid) {
				next0 = 0.0;
				next1 = -b1 / k11;
				valid = Math::is_finite(next1) && next1 >= 0.0 && k01 * next1 + b0 >= 0.0;
			}
			if (!valid) {
				next1 = 0.0;
				next0 = -b0 / k00;
				valid = Math::is_finite(next0) && next0 >= 0.0 && k01 * next0 + b1 >= 0.0;
			}
			if (!valid) {
				next0 = 0.0;
				next1 = 0.0;
				valid = b0 >= 0.0 && b1 >= 0.0;
			}
			if (valid) {
				const real_t d0 = next0 - old0;
				const real_t d1 = next1 - old1;
				c0.acc_normal_impulse = next0;
				c1.acc_normal_impulse = next1;
				if (d0 != 0.0) {
					const Vector3 impulse = normal * d0;
					if (collide_A) {
						A->apply_impulse(-impulse, c0.rA + A->get_center_of_mass());
					}
					if (collide_B) {
						B->apply_impulse(impulse, c0.rB + B->get_center_of_mass());
					}
					c0.acc_impulse -= impulse;
					block_normal_updated[0] = true;
				}
				if (d1 != 0.0) {
					const Vector3 impulse = normal * d1;
					if (collide_A) {
						A->apply_impulse(-impulse, c1.rA + A->get_center_of_mass());
					}
					if (collide_B) {
						B->apply_impulse(impulse, c1.rB + B->get_center_of_mass());
					}
					c1.acc_impulse -= impulse;
					block_normal_updated[1] = true;
				}
				block_solved = true;
			}
		}
	}

	for (int i = 0; i < contact_count; i++) {
		Contact &c = contacts[i];
		if (!c.active) {
			continue;
		}

		c.active = false; //try to deactivate, will activate itself if still needed

		//bias impulse

		Vector3 crbA = A->get_biased_angular_velocity().cross(c.rA);
		Vector3 crbB = B->get_biased_angular_velocity().cross(c.rB);
		Vector3 dbv = B->get_biased_linear_velocity() + crbB - A->get_biased_linear_velocity() - crbA;

		real_t vbn = dbv.dot(c.normal);

		if (Math::abs(-vbn + c.bias) > MIN_VELOCITY) {
			real_t jbn = (-vbn + c.bias) * c.mass_normal;
			real_t jbnOld = c.acc_bias_impulse;
			c.acc_bias_impulse = MAX(jbnOld + jbn, 0.0f);

			// Most warm-started contacts have no further bias correction.
			const real_t bias_delta = c.acc_bias_impulse - jbnOld;
			if (bias_delta != 0.0) {
				const Vector3 jb = c.normal * bias_delta;
				if (collide_A) {
					A->apply_bias_impulse(-jb, c.rA + A->get_center_of_mass(), max_bias_av);
				}
				if (collide_B) {
					B->apply_bias_impulse(jb, c.rB + B->get_center_of_mass(), max_bias_av);
				}
				// Re-evaluate the bias velocity only when the impulse changed it.
				crbA = A->get_biased_angular_velocity().cross(c.rA);
				crbB = B->get_biased_angular_velocity().cross(c.rB);
				dbv = B->get_biased_linear_velocity() + crbB - A->get_biased_linear_velocity() - crbA;
				vbn = dbv.dot(c.normal);
			}

			const real_t total_inverse_mass = inv_mass_A + inv_mass_B;
			if (total_inverse_mass > 0.0 && Math::abs(-vbn + c.bias) > MIN_VELOCITY) {
				real_t jbn_com = (-vbn + c.bias) / total_inverse_mass;
				real_t jbnOld_com = c.acc_bias_impulse_center_of_mass;
				c.acc_bias_impulse_center_of_mass = MAX(jbnOld_com + jbn_com, 0.0f);

				const Vector3 jb_com = c.normal * (c.acc_bias_impulse_center_of_mass - jbnOld_com);
				if (jb_com != Vector3()) {
					if (collide_A) {
						A->apply_bias_impulse(-jb_com, A->get_center_of_mass(), 0.0f);
					}
					if (collide_B) {
						B->apply_bias_impulse(jb_com, B->get_center_of_mass(), 0.0f);
					}
				}
			}

			c.active = true;
		}

		Vector3 crA = A->get_angular_velocity().cross(c.rA);
		Vector3 crB = B->get_angular_velocity().cross(c.rB);
		Vector3 dv = B->get_linear_velocity() + crB - A->get_linear_velocity() - crA;

		//normal impulse
		real_t vn = dv.dot(c.normal);

		if (block_solved) {
			// Joint normal impulses were already applied together.
			if (block_normal_updated[i]) {
				c.active = true;
			}
		} else if (Math::abs(vn) > MIN_VELOCITY) {
			real_t jn = -(c.bounce + vn) * c.mass_normal;
			real_t jnOld = c.acc_normal_impulse;
			c.acc_normal_impulse = MAX(jnOld + jn, 0.0f);

			const Vector3 j = c.normal * (c.acc_normal_impulse - jnOld);
			if (j != Vector3()) {
				if (collide_A) {
					A->apply_impulse(-j, c.rA + A->get_center_of_mass());
				}
				if (collide_B) {
					B->apply_impulse(j, c.rB + B->get_center_of_mass());
				}
				c.acc_impulse -= j;
			}

			c.active = true;
		}

		// Frictionless contacts need neither tangential velocities nor inertia
		// calculations. Their cached tangent impulse was cleared in pre_solve().
		if (friction == 0.0) {
			continue;
		}

		//friction impulse

		Vector3 lvA = A->get_linear_velocity() + A->get_angular_velocity().cross(c.rA);
		Vector3 lvB = B->get_linear_velocity() + B->get_angular_velocity().cross(c.rB);

		Vector3 dtv = lvB - lvA;
		real_t tn = c.normal.dot(dtv);

		// tangential velocity
		Vector3 tv = dtv - c.normal * tn;
		const real_t tangent_speed_squared = tv.length_squared();
		// Most resting contacts need no friction correction. Only take the
		// square root when the tangent speed exceeds the solver tolerance.
		if (tangent_speed_squared > MIN_VELOCITY * MIN_VELOCITY) {
			const real_t tvl = Math::sqrt(tangent_speed_squared);
			tv /= tvl;

			Vector3 temp1 = inv_inertia_tensor_A.xform(c.rA.cross(tv));
			Vector3 temp2 = inv_inertia_tensor_B.xform(c.rB.cross(tv));

			// Degenerate or locked contacts cannot sustain a tangent impulse.
			const real_t tangent_mass = inv_mass_A + inv_mass_B + tv.dot(temp1.cross(c.rA) + temp2.cross(c.rB));
			if (tangent_mass <= 0.0) {
				continue;
			}
			const real_t t = -tvl / tangent_mass;

			Vector3 jt = t * tv;

			Vector3 jtOld = c.acc_tangent_impulse;
			c.acc_tangent_impulse += jt;

			const real_t fi_len_squared = c.acc_tangent_impulse.length_squared();
			const real_t jtMax = c.acc_normal_impulse * friction;

			// Only compute sqrt for impulses outside the friction cone.
			if (fi_len_squared > CMP_EPSILON * CMP_EPSILON && fi_len_squared > jtMax * jtMax) {
				c.acc_tangent_impulse *= jtMax / Math::sqrt(fi_len_squared);
			}

			jt = c.acc_tangent_impulse - jtOld;
			if (jt != Vector3()) {
				if (collide_A) {
					A->apply_impulse(-jt, c.rA + A->get_center_of_mass());
				}
				if (collide_B) {
					B->apply_impulse(jt, c.rB + B->get_center_of_mass());
				}
				c.acc_impulse -= jt;
			}

			c.active = true;
		}
	}
}

GodotBodyPair3D::GodotBodyPair3D(GodotBody3D *p_A, int p_shape_A, GodotBody3D *p_B, int p_shape_B) :
		GodotBodyContact3D(_arr, 2) {
	A = p_A;
	B = p_B;
	shape_A = p_shape_A;
	shape_B = p_shape_B;
	space = A->get_space();
	A->add_constraint(this, 0);
	B->add_constraint(this, 1);
}

GodotBodyPair3D::~GodotBodyPair3D() {
	A->remove_constraint(this, 0);
	B->remove_constraint(this, 1);
}

void GodotBodySoftBodyPair3D::_contact_added_callback(const Vector3 &p_point_A, int p_index_A, const Vector3 &p_point_B, int p_index_B, const Vector3 &normal, void *p_userdata) {
	GodotBodySoftBodyPair3D *pair = static_cast<GodotBodySoftBodyPair3D *>(p_userdata);
	pair->contact_added_callback(p_point_A, p_index_A, p_point_B, p_index_B, normal);
}

void GodotBodySoftBodyPair3D::contact_added_callback(const Vector3 &p_point_A, int, const Vector3 &p_point_B, int p_index_B, const Vector3 &normal) {
	const Vector3 local_A = body->get_inv_transform().xform(p_point_A);
	const Vector3 local_B = p_point_B - soft_body->get_node_position(p_index_B);

	Contact contact;
	contact.index_B = p_index_B;
	contact.local_A = local_A;
	contact.local_B = local_B;
	// Soft-body contacts need a unit, nonzero normal even for degenerate
	// triangle/vertex data or coincident narrowphase support points.
	contact.normal = godot_physics_3d_soft_contact_normal(p_point_A, p_point_B, normal);
	contact.used = true;

	// Direct node-ID lookup for dense soft-body contact patches. Below the
	// threshold, a linear scan avoids allocating the hash table entirely.
	const uint32_t contact_count = contacts.size();
	contact_index.maybe_build(contacts);
	int existing_index = contact_index.find(p_index_B);
	if (!contact_index.is_active()) {
		for (uint32_t i = 0; i < contact_count; ++i) {
			if (contacts[i].index_B == p_index_B) {
				existing_index = int(i);
				break;
			}
		}
	}

	if (existing_index != -1) {
		Contact &previous = contacts[existing_index];
		const real_t recycle_radius = space->get_contact_recycle_radius();
		const real_t recycle_radius_squared = recycle_radius * recycle_radius;
		if (previous.local_A.distance_squared_to(local_A) < recycle_radius_squared &&
				previous.local_B.distance_squared_to(local_B) < recycle_radius_squared &&
				previous.normal.dot(contact.normal) >= real_t(0.98)) {
			contact.acc_normal_impulse = previous.acc_normal_impulse;
			contact.acc_bias_impulse = previous.acc_bias_impulse;
			contact.acc_bias_impulse_center_of_mass = previous.acc_bias_impulse_center_of_mass;
			// A rotating soft-body surface changes the contact normal. Reproject
			// the cached friction so it never injects a normal impulse.
			contact.acc_tangent_impulse = previous.acc_tangent_impulse - contact.normal * previous.acc_tangent_impulse.dot(contact.normal);
		}
		previous = contact;
		return;
	}

	contacts.push_back(contact);
	contact_index.appended(p_index_B, contact_count);
}

void GodotBodySoftBodyPair3D::validate_contacts() {
	// Make sure to erase contacts that are no longer valid.
	real_t max_separation = space->get_contact_max_separation();
	real_t max_separation2 = max_separation * max_separation;

	const Transform3D &transform_A = body->get_transform();

	uint32_t contact_count = contacts.size();
	for (uint32_t contact_index = 0; contact_index < contact_count; ++contact_index) {
		Contact &c = contacts[contact_index];

		bool erase = false;
		if (!c.used) {
			// Was left behind in previous frame.
			erase = true;
		} else {
			c.used = false;

			Vector3 global_A = transform_A.xform(c.local_A);
			Vector3 global_B = soft_body->get_node_position(c.index_B) + c.local_B;
			Vector3 axis = global_A - global_B;
			real_t depth = axis.dot(c.normal);

			if (depth < -max_separation || (global_B + c.normal * depth - global_A).length_squared() > max_separation2) {
				erase = true;
			}
		}

		if (erase) {
			// The node map stores vector indices. Update the relocated node
			// after swap-removal, then release the map when sparse again.
			const int removed_node = c.index_B;
			const bool has_moved_contact = (contact_index + 1) < contact_count;
			const int moved_node = has_moved_contact ? contacts[contact_count - 1].index_B : removed_node;
			if (has_moved_contact) {
				SWAP(c, contacts[contact_count - 1]);
			}
			contact_count--;
			this->contact_index.swap_removed(removed_node, moved_node, contact_index, contact_count);
			contact_index--;
		}
	}

	contacts.resize(contact_count);
}

bool GodotBodySoftBodyPair3D::setup(real_t p_step) {
	if (!body->interacts_with(soft_body) || body->has_exception(soft_body->get_self()) || soft_body->has_exception(body->get_self())) {
		collided = false;
		return false;
	}

	body_collides = (body->get_mode() > PS3DE::BODY_MODE_KINEMATIC) && body->collides_with(soft_body);
	soft_body_collides = soft_body->collides_with(body);

	if (!body_collides && !soft_body_collides) {
		if (body->get_max_contacts_reported() > 0) {
			report_contacts_only = true;
		} else {
			collided = false;
			return false;
		}
	}

	const Transform3D &xform_Au = body->get_transform();
	Transform3D xform_A = xform_Au * body->get_shape_transform(body_shape);

	Transform3D xform_Bu = soft_body->get_transform();
	Transform3D xform_B = xform_Bu * soft_body->get_shape_transform(0);

	validate_contacts();

	GodotShape3D *shape_A_ptr = body->get_shape(body_shape);
	GodotShape3D *shape_B_ptr = soft_body->get_shape(0);

	collided = GodotCollisionSolver3D::solve_static(shape_A_ptr, xform_A, shape_B_ptr, xform_B, _contact_added_callback, this, &sep_axis);

	return collided;
}

bool GodotBodySoftBodyPair3D::pre_solve(real_t p_step) {
	if (!collided) {
		return false;
	}

	real_t max_penetration = space->get_contact_max_allowed_penetration();

	real_t bias = space->get_contact_bias();

	GodotShape3D *shape_A_ptr = body->get_shape(body_shape);

	if (shape_A_ptr->get_custom_bias()) {
		bias = shape_A_ptr->get_custom_bias();
	}

	real_t inv_dt = 1.0 / p_step;

	bool do_process = false;

	const Transform3D &transform_A = body->get_transform();
	const real_t friction = body->get_friction();
	const bool has_friction = friction != 0.0;
	// Soft/rigid manifolds also persist between timesteps. Reuse their
	// impulses consistently with the rigid/rigid contact solver.
	const real_t previous_step = space->get_previous_step();
	const bool step_changed = previous_step > 0.0 && !Math::is_equal_approx(previous_step, p_step);
	const real_t timestep_ratio = step_changed ? p_step / previous_step : real_t(1.0);
	const bool can_scale_impulses = timestep_ratio >= real_t(0.5) && timestep_ratio <= real_t(2.0);
	const real_t warm_start_coefficient = space->get_warm_start_coefficient();
	const bool rescale_impulses = step_changed || warm_start_coefficient != real_t(1.0);
	const real_t impulse_scale = timestep_ratio * warm_start_coefficient;

	Basis zero_basis;
	zero_basis.set_zero();

	const Basis &body_inv_inertia_tensor = body_collides ? body->get_inv_inertia_tensor() : zero_basis;

	real_t body_inv_mass = body_collides ? body->get_inv_mass() : 0.0;

	uint32_t contact_count = contacts.size();
	for (uint32_t contact_index = 0; contact_index < contact_count; ++contact_index) {
		Contact &c = contacts[contact_index];
		c.active = false;
		if (rescale_impulses) {
			if (can_scale_impulses) {
				c.acc_normal_impulse *= impulse_scale;
				c.acc_tangent_impulse *= impulse_scale;
				c.acc_bias_impulse *= impulse_scale;
				c.acc_bias_impulse_center_of_mass *= impulse_scale;
			} else {
				c.acc_normal_impulse = 0.0;
				c.acc_tangent_impulse = Vector3();
				c.acc_bias_impulse = 0.0;
				c.acc_bias_impulse_center_of_mass = 0.0;
			}
		}

		real_t node_inv_mass = soft_body_collides ? soft_body->get_node_inv_mass(c.index_B) : 0.0;
		if ((node_inv_mass == 0.0) && (body_inv_mass == 0.0)) {
			continue;
		}

		Vector3 global_A = transform_A.xform(c.local_A);
		Vector3 global_B = soft_body->get_node_position(c.index_B) + c.local_B;
		Vector3 axis = global_A - global_B;
		real_t depth = axis.dot(c.normal);

		if (depth <= 0.0) {
			continue;
		}

#ifdef DEBUG_ENABLED
		if (space->is_debugging_contacts()) {
			space->add_debug_contact(global_A);
			space->add_debug_contact(global_B);
		}
#endif

		c.rA = global_A - transform_A.origin - body->get_center_of_mass();
		c.rB = global_B;

		// Precompute normal mass, tangent mass, and bias.
		Vector3 inertia_A = body_inv_inertia_tensor.xform(c.rA.cross(c.normal));
		real_t kNormal = body_inv_mass + node_inv_mass;
		kNormal += c.normal.dot(inertia_A.cross(c.rA));
		// Degenerate or locked contacts must not generate infinite impulses.
		c.mass_normal = kNormal > 0.0 ? 1.0f / kNormal : 0.0f;

		// Soft-body node contacts use the same recovery-speed cap as rigid contacts.
		c.bias = space->limit_contact_bias(-bias * inv_dt * MIN(0.0f, -depth + max_penetration));
		c.depth = depth;

		// The material can become frictionless after a contact was cached.
		// Do not apply its obsolete tangential warm-start impulse.
		if (!has_friction) {
			c.acc_tangent_impulse = Vector3();
		} else if (friction > 0.0) {
			// Material changes must shrink the cached friction impulse to the
			// current Coulomb cone before it is applied to either body.
			const real_t tangent_limit = friction * c.acc_normal_impulse;
			const real_t tangent_length_squared = c.acc_tangent_impulse.length_squared();
			if (tangent_length_squared > tangent_limit * tangent_limit) {
				c.acc_tangent_impulse *= tangent_limit / Math::sqrt(tangent_length_squared);
			}
		}
		Vector3 j_vec = c.normal * c.acc_normal_impulse + c.acc_tangent_impulse;
		if (body_collides) {
			body->apply_impulse(-j_vec, c.rA + body->get_center_of_mass());
		}
		if (soft_body_collides) {
			soft_body->apply_node_impulse(c.index_B, j_vec);
		}
		c.acc_impulse -= j_vec;

		if (body->can_report_contacts()) {
			Vector3 crA = body->get_angular_velocity().cross(c.rA) + body->get_linear_velocity();
			Vector3 crB = soft_body->get_node_velocity(c.index_B);
			body->add_contact(global_A, -c.normal, depth, body_shape, crA, global_B, 0, soft_body->get_instance_id(), soft_body->get_self(), crB, c.acc_impulse);
		}
		if (report_contacts_only) {
			collided = false;
			continue;
		}

		c.active = true;
		do_process = true;

		if (body_collides) {
			body->set_active(true);
		}

		c.bounce = body->get_bounce();

		if (c.bounce) {
			Vector3 crA = body->get_angular_velocity().cross(c.rA);
			Vector3 dv = soft_body->get_node_velocity(c.index_B) - body->get_linear_velocity() - crA;

			// Use the same restitution threshold for rigid/soft contacts.
			const real_t normal_velocity = dv.dot(c.normal);
			c.bounce = normal_velocity < -space->get_restitution_velocity_threshold() ? c.bounce * normal_velocity : 0.0;
		}
	}

	return do_process;
}

void GodotBodySoftBodyPair3D::solve(real_t p_step) {
	if (!collided) {
		return;
	}

	const real_t max_bias_av = MAX_BIAS_ROTATION / p_step;
	// Material friction is constant during the constraint solve.
	const real_t friction = body->get_friction();

	Basis zero_basis;
	zero_basis.set_zero();

	const Basis &body_inv_inertia_tensor = body_collides ? body->get_inv_inertia_tensor() : zero_basis;

	real_t body_inv_mass = body_collides ? body->get_inv_mass() : 0.0;

	uint32_t contact_count = contacts.size();
	for (uint32_t contact_index = 0; contact_index < contact_count; ++contact_index) {
		Contact &c = contacts[contact_index];
		if (!c.active) {
			continue;
		}

		c.active = false;

		real_t node_inv_mass = soft_body_collides ? soft_body->get_node_inv_mass(c.index_B) : 0.0;

		// Bias impulse.
		Vector3 crbA = body->get_biased_angular_velocity().cross(c.rA);
		Vector3 dbv = soft_body->get_node_biased_velocity(c.index_B) - body->get_biased_linear_velocity() - crbA;

		real_t vbn = dbv.dot(c.normal);

		if (Math::abs(-vbn + c.bias) > MIN_VELOCITY) {
			real_t jbn = (-vbn + c.bias) * c.mass_normal;
			real_t jbnOld = c.acc_bias_impulse;
			c.acc_bias_impulse = MAX(jbnOld + jbn, 0.0f);

			const real_t bias_delta = c.acc_bias_impulse - jbnOld;
			if (bias_delta != 0.0) {
				const Vector3 jb = c.normal * bias_delta;
				if (body_collides) {
					body->apply_bias_impulse(-jb, c.rA + body->get_center_of_mass(), max_bias_av);
				}
				if (soft_body_collides) {
					soft_body->apply_node_bias_impulse(c.index_B, jb);
				}
				// Avoid rereading soft-body node velocities when no bias changed.
				crbA = body->get_biased_angular_velocity().cross(c.rA);
				dbv = soft_body->get_node_biased_velocity(c.index_B) - body->get_biased_linear_velocity() - crbA;
				vbn = dbv.dot(c.normal);
			}

			const real_t total_inverse_mass = body_inv_mass + node_inv_mass;
			if (total_inverse_mass > 0.0 && Math::abs(-vbn + c.bias) > MIN_VELOCITY) {
				real_t jbn_com = (-vbn + c.bias) / total_inverse_mass;
				real_t jbnOld_com = c.acc_bias_impulse_center_of_mass;
				c.acc_bias_impulse_center_of_mass = MAX(jbnOld_com + jbn_com, 0.0f);

				const Vector3 jb_com = c.normal * (c.acc_bias_impulse_center_of_mass - jbnOld_com);
				if (jb_com != Vector3()) {
					if (body_collides) {
						body->apply_bias_impulse(-jb_com, body->get_center_of_mass(), 0.0f);
					}
					if (soft_body_collides) {
						soft_body->apply_node_bias_impulse(c.index_B, jb_com);
					}
				}
			}

			c.active = true;
		}

		Vector3 crA = body->get_angular_velocity().cross(c.rA);
		Vector3 dv = soft_body->get_node_velocity(c.index_B) - body->get_linear_velocity() - crA;

		// Normal impulse.
		real_t vn = dv.dot(c.normal);

		if (Math::abs(vn) > MIN_VELOCITY) {
			real_t jn = -(c.bounce + vn) * c.mass_normal;
			real_t jnOld = c.acc_normal_impulse;
			c.acc_normal_impulse = MAX(jnOld + jn, 0.0f);

			const Vector3 j = c.normal * (c.acc_normal_impulse - jnOld);
			if (j != Vector3()) {
				if (body_collides) {
					body->apply_impulse(-j, c.rA + body->get_center_of_mass());
				}
				if (soft_body_collides) {
					soft_body->apply_node_impulse(c.index_B, j);
				}
				c.acc_impulse -= j;
			}

			c.active = true;
		}

		// A frictionless contact has no tangent constraint. Avoid the extra
		// two velocities, length calculations and inertia transform.
		if (friction == 0.0) {
			continue;
		}

		// Friction impulse.

		Vector3 lvA = body->get_linear_velocity() + body->get_angular_velocity().cross(c.rA);
		Vector3 lvB = soft_body->get_node_velocity(c.index_B);
		Vector3 dtv = lvB - lvA;

		real_t tn = c.normal.dot(dtv);

		// Tangential velocity.
		Vector3 tv = dtv - c.normal * tn;
		const real_t tangent_speed_squared = tv.length_squared();
		// Most resting contacts need no friction correction. Only take the
		// square root when the tangent speed exceeds the solver tolerance.
		if (tangent_speed_squared > MIN_VELOCITY * MIN_VELOCITY) {
			const real_t tvl = Math::sqrt(tangent_speed_squared);
			tv /= tvl;

			Vector3 temp1 = body_inv_inertia_tensor.xform(c.rA.cross(tv));

			const real_t tangent_mass = body_inv_mass + node_inv_mass + tv.dot(temp1.cross(c.rA));
			if (tangent_mass <= 0.0) {
				continue;
			}
			real_t t = -tvl / tangent_mass;

			Vector3 jt = t * tv;

			Vector3 jtOld = c.acc_tangent_impulse;
			c.acc_tangent_impulse += jt;

			const real_t fi_len_squared = c.acc_tangent_impulse.length_squared();
			const real_t jtMax = c.acc_normal_impulse * friction;

			// Only compute sqrt for impulses outside the friction cone.
			if (fi_len_squared > CMP_EPSILON * CMP_EPSILON && (jtMax < 0.0 || fi_len_squared > jtMax * jtMax)) {
				c.acc_tangent_impulse *= jtMax / Math::sqrt(fi_len_squared);
			}

			jt = c.acc_tangent_impulse - jtOld;
			if (jt != Vector3()) {
				if (body_collides) {
					body->apply_impulse(-jt, c.rA + body->get_center_of_mass());
				}
				if (soft_body_collides) {
					soft_body->apply_node_impulse(c.index_B, jt);
				}
				c.acc_impulse -= jt;
			}

			c.active = true;
		}
	}
}

GodotBodySoftBodyPair3D::GodotBodySoftBodyPair3D(GodotBody3D *p_A, int p_shape_A, GodotSoftBody3D *p_B) :
		GodotBodyContact3D(&body, 1) {
	body = p_A;
	soft_body = p_B;
	body_shape = p_shape_A;
	space = p_A->get_space();
	body->add_constraint(this, 0);
	soft_body->add_constraint(this);
}

GodotBodySoftBodyPair3D::~GodotBodySoftBodyPair3D() {
	body->remove_constraint(this, 0);
	soft_body->remove_constraint(this);
}
