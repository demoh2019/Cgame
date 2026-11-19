/**************************************************************************/
/*  godot_body_3d.cpp                                                     */
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

#include "godot_body_3d.h"
#include "servers/physics_angular_velocity_cap.h"
#include "servers/physics_linear_velocity_cap.h"

#include "godot_area_3d.h"
#include "godot_body_direct_state_3d.h"
#include "godot_constraint_3d.h"
#include "godot_space_3d.h"

#include "servers/physics_damping.h"
#include "servers/physics_uniform_fluid.h"
#include "servers/physics_gyroscopic_3d.h"
#include "servers/physics_fluid_buoyancy_3d.h"
#include "servers/physics_fluid_convex_hull_3d.h"
#include "servers/physics_fluid_box_3d.h"
#include "servers/physics_fluid_ellipsoid_3d.h"

void GodotBody3D::_mass_properties_changed() {
	if (get_space() && !mass_properties_update_list.in_list()) {
		get_space()->body_add_to_mass_properties_update_list(&mass_properties_update_list);
	}
}

void GodotBody3D::_update_transform_dependent() {
	center_of_mass = get_transform().basis.xform(center_of_mass_local);
	principal_inertia_axes = get_transform().basis * principal_inertia_axes_local;

	// Update inertia tensor.
	Basis tb = principal_inertia_axes;
	Basis tbt = tb.transposed();
	Basis diag;
	diag.scale(_inv_inertia);
	_inv_inertia_tensor = tb * diag * tbt;
}

void GodotBody3D::update_mass_properties() {
	// Update shapes and motions.

	switch (mode) {
		case PS3DE::BODY_MODE_RIGID: {
			real_t total_area = 0;
			for (int i = 0; i < get_shape_count(); i++) {
				if (is_shape_disabled(i)) {
					continue;
				}

				total_area += get_shape_area(i);
			}

			if (calculate_center_of_mass) {
				// We have to recompute the center of mass.
				center_of_mass_local.zero();

				if (total_area != 0.0) {
					for (int i = 0; i < get_shape_count(); i++) {
						if (is_shape_disabled(i)) {
							continue;
						}

						real_t area = get_shape_area(i);

						real_t mass_new = area * mass / total_area;

						// NOTE: we assume that the shape origin is also its center of mass.
						center_of_mass_local += mass_new * get_shape_transform(i).origin;
					}

					center_of_mass_local /= mass;
				}
			}

			if (calculate_inertia) {
				// Recompute the inertia tensor.
				Basis inertia_tensor;
				inertia_tensor.set_zero();
				bool inertia_set = false;

				for (int i = 0; i < get_shape_count(); i++) {
					if (is_shape_disabled(i)) {
						continue;
					}

					real_t area = get_shape_area(i);
					if (area == 0.0) {
						continue;
					}

					inertia_set = true;

					const GodotShape3D *shape = get_shape(i);

					real_t mass_new = area * mass / total_area;

					Basis shape_inertia_tensor = Basis::from_scale(shape->get_moment_of_inertia(mass_new));
					Transform3D shape_transform = get_shape_transform(i);
					Basis shape_basis = shape_transform.basis.orthonormalized();

					// NOTE: we don't take the scale of collision shapes into account when computing the inertia tensor!
					shape_inertia_tensor = shape_basis * shape_inertia_tensor * shape_basis.transposed();

					Vector3 shape_origin = shape_transform.origin - center_of_mass_local;
					inertia_tensor += shape_inertia_tensor + (Basis() * shape_origin.dot(shape_origin) - shape_origin.outer(shape_origin)) * mass_new;
				}

				// Set the inertia to a valid value when there are no valid shapes.
				if (!inertia_set) {
					inertia_tensor = Basis();
				}

				// Handle partial custom inertia.
				if (inertia.x > 0.0) {
					inertia_tensor[0][0] = inertia.x;
				}
				if (inertia.y > 0.0) {
					inertia_tensor[1][1] = inertia.y;
				}
				if (inertia.z > 0.0) {
					inertia_tensor[2][2] = inertia.z;
				}

				// Compute the principal axes of inertia.
				principal_inertia_axes_local = inertia_tensor.diagonalize().transposed();
				_inv_inertia = inertia_tensor.get_main_diagonal().inverse();
			}

			if (mass) {
				_inv_mass = 1.0 / mass;
			} else {
				_inv_mass = 0;
			}

		} break;
		case PS3DE::BODY_MODE_KINEMATIC:
		case PS3DE::BODY_MODE_STATIC: {
			_inv_inertia = Vector3();
			_inv_mass = 0;
		} break;
		case PS3DE::BODY_MODE_RIGID_LINEAR: {
			_inv_inertia_tensor.set_zero();
			_inv_mass = 1.0 / mass;

		} break;
	}

	_update_transform_dependent();
}

void GodotBody3D::reset_mass_properties() {
	calculate_inertia = true;
	calculate_center_of_mass = true;
	_mass_properties_changed();
}

void GodotBody3D::set_active(bool p_active) {
	if (active == p_active) {
		return;
	}

	active = p_active;

	if (active) {
		if (mode == PS3DE::BODY_MODE_STATIC) {
			// Static bodies can't be active.
			active = false;
		} else if (get_space()) {
			get_space()->body_add_to_active_list(&active_list);
		}
	} else if (get_space()) {
		get_space()->body_remove_from_active_list(&active_list);
	}
}

void GodotBody3D::set_param(PS3DE::BodyParameter p_param, const Variant &p_value) {
	switch (p_param) {
		case PS3DE::BODY_PARAM_BOUNCE: {
			bounce = p_value;
		} break;
		case PS3DE::BODY_PARAM_FRICTION: {
			friction = p_value;
		} break;
		case PS3DE::BODY_PARAM_MASS: {
			real_t mass_value = p_value;
			ERR_FAIL_COND(mass_value <= 0);
			mass = mass_value;
			if (mode >= PS3DE::BODY_MODE_RIGID) {
				_mass_properties_changed();
			}
		} break;
		case PS3DE::BODY_PARAM_INERTIA: {
			inertia = p_value;
			if ((inertia.x <= 0.0) || (inertia.y <= 0.0) || (inertia.z <= 0.0)) {
				calculate_inertia = true;
				if (mode == PS3DE::BODY_MODE_RIGID) {
					_mass_properties_changed();
				}
			} else {
				calculate_inertia = false;
				if (mode == PS3DE::BODY_MODE_RIGID) {
					principal_inertia_axes_local = Basis();
					_inv_inertia = inertia.inverse();
					_update_transform_dependent();
				}
			}
		} break;
		case PS3DE::BODY_PARAM_CENTER_OF_MASS: {
			calculate_center_of_mass = false;
			center_of_mass_local = p_value;
			_update_transform_dependent();
		} break;
		case PS3DE::BODY_PARAM_GRAVITY_SCALE: {
			if (Math::is_zero_approx(gravity_scale)) {
				wakeup();
			}
			gravity_scale = p_value;
		} break;
		case PS3DE::BODY_PARAM_LINEAR_DAMP_MODE: {
			int mode_value = p_value;
			linear_damp_mode = (PS3DE::BodyDampMode)mode_value;
		} break;
		case PS3DE::BODY_PARAM_ANGULAR_DAMP_MODE: {
			int mode_value = p_value;
			angular_damp_mode = (PS3DE::BodyDampMode)mode_value;
		} break;
		case PS3DE::BODY_PARAM_LINEAR_DAMP: {
			linear_damp = p_value;
		} break;
		case PS3DE::BODY_PARAM_ANGULAR_DAMP: {
			angular_damp = p_value;
		} break;
		default: {
		}
	}
}

Variant GodotBody3D::get_param(PS3DE::BodyParameter p_param) const {
	switch (p_param) {
		case PS3DE::BODY_PARAM_BOUNCE: {
			return bounce;
		} break;
		case PS3DE::BODY_PARAM_FRICTION: {
			return friction;
		} break;
		case PS3DE::BODY_PARAM_MASS: {
			return mass;
		} break;
		case PS3DE::BODY_PARAM_INERTIA: {
			if (mode == PS3DE::BODY_MODE_RIGID) {
				return _inv_inertia.inverse();
			} else {
				return Vector3();
			}
		} break;
		case PS3DE::BODY_PARAM_CENTER_OF_MASS: {
			return center_of_mass_local;
		} break;
		case PS3DE::BODY_PARAM_GRAVITY_SCALE: {
			return gravity_scale;
		} break;
		case PS3DE::BODY_PARAM_LINEAR_DAMP_MODE: {
			return linear_damp_mode;
		}
		case PS3DE::BODY_PARAM_ANGULAR_DAMP_MODE: {
			return angular_damp_mode;
		}
		case PS3DE::BODY_PARAM_LINEAR_DAMP: {
			return linear_damp;
		} break;
		case PS3DE::BODY_PARAM_ANGULAR_DAMP: {
			return angular_damp;
		} break;

		default: {
		}
	}

	return 0;
}

void GodotBody3D::set_mode(PS3DE::BodyMode p_mode) {
	PS3DE::BodyMode prev = mode;
	mode = p_mode;

	switch (p_mode) {
		case PS3DE::BODY_MODE_STATIC:
		case PS3DE::BODY_MODE_KINEMATIC: {
			_set_inv_transform(get_transform().affine_inverse());
			_inv_mass = 0;
			_inv_inertia = Vector3();
			_set_static(p_mode == PS3DE::BODY_MODE_STATIC);
			set_active(p_mode == PS3DE::BODY_MODE_KINEMATIC && contacts.size());
			linear_velocity = Vector3();
			angular_velocity = Vector3();
			if (mode == PS3DE::BODY_MODE_KINEMATIC && prev != mode) {
				first_time_kinematic = true;
			}
			_update_transform_dependent();

		} break;
		case PS3DE::BODY_MODE_RIGID: {
			_inv_mass = mass > 0 ? (1.0 / mass) : 0;
			if (!calculate_inertia) {
				principal_inertia_axes_local = Basis();
				_inv_inertia = inertia.inverse();
				_update_transform_dependent();
			}
			_mass_properties_changed();
			_set_static(false);
			set_active(true);

		} break;
		case PS3DE::BODY_MODE_RIGID_LINEAR: {
			_inv_mass = mass > 0 ? (1.0 / mass) : 0;
			_inv_inertia = Vector3();
			angular_velocity = Vector3();
			_update_transform_dependent();
			_set_static(false);
			set_active(true);
		}
	}
}

PS3DE::BodyMode GodotBody3D::get_mode() const {
	return mode;
}

void GodotBody3D::_shapes_changed() {
	_mass_properties_changed();
	wakeup();
	wakeup_neighbours();
}

void GodotBody3D::set_state(PS3DE::BodyState p_state, const Variant &p_variant) {
	switch (p_state) {
		case PS3DE::BODY_STATE_TRANSFORM: {
			if (mode == PS3DE::BODY_MODE_KINEMATIC) {
				new_transform = p_variant;
				//wakeup_neighbours();
				set_active(true);
				if (first_time_kinematic) {
					_set_transform(p_variant);
					_set_inv_transform(get_transform().affine_inverse());
					first_time_kinematic = false;
				}

			} else if (mode == PS3DE::BODY_MODE_STATIC) {
				// A repeated identical transform is not a motion event. Avoid
				// broadphase updates, matrix inversion and waking nearby bodies.
				// Shape changes have their own update/wakeup path.
				const Transform3D new_static_transform = p_variant;
				if (new_static_transform == get_transform()) {
					break;
				}
				_set_transform(new_static_transform);
				_set_inv_transform(get_transform().affine_inverse());
				wakeup_neighbours();
			} else {
				Transform3D t = p_variant;
				t.orthonormalize();
				new_transform = get_transform(); //used as old to compute motion
				if (new_transform == t) {
					break;
				}
				_set_transform(t);
				_set_inv_transform(get_transform().inverse());
				_update_transform_dependent();
			}
			wakeup();

		} break;
		case PS3DE::BODY_STATE_LINEAR_VELOCITY: {
			linear_velocity = p_variant;
			constant_linear_velocity = linear_velocity;
			wakeup();
		} break;
		case PS3DE::BODY_STATE_ANGULAR_VELOCITY: {
			angular_velocity = p_variant;
			constant_angular_velocity = angular_velocity;
			wakeup();

		} break;
		case PS3DE::BODY_STATE_SLEEPING: {
			if (mode == PS3DE::BODY_MODE_STATIC || mode == PS3DE::BODY_MODE_KINEMATIC) {
				break;
			}
			bool do_sleep = p_variant;
			if (do_sleep) {
				linear_velocity = Vector3();
				//biased_linear_velocity=Vector3();
				angular_velocity = Vector3();
				//biased_angular_velocity=Vector3();
				set_active(false);
			} else {
				set_active(true);
			}
		} break;
		case PS3DE::BODY_STATE_CAN_SLEEP: {
			can_sleep = p_variant;
			if (mode >= PS3DE::BODY_MODE_RIGID && !active && !can_sleep) {
				set_active(true);
			}

		} break;
	}
}

Variant GodotBody3D::get_state(PS3DE::BodyState p_state) const {
	switch (p_state) {
		case PS3DE::BODY_STATE_TRANSFORM: {
			return get_transform();
		} break;
		case PS3DE::BODY_STATE_LINEAR_VELOCITY: {
			return linear_velocity;
		} break;
		case PS3DE::BODY_STATE_ANGULAR_VELOCITY: {
			return angular_velocity;
		} break;
		case PS3DE::BODY_STATE_SLEEPING: {
			return !is_active();
		} break;
		case PS3DE::BODY_STATE_CAN_SLEEP: {
			return can_sleep;
		} break;
	}

	return Variant();
}

void GodotBody3D::set_space(GodotSpace3D *p_space) {
	if (get_space()) {
		if (mass_properties_update_list.in_list()) {
			get_space()->body_remove_from_mass_properties_update_list(&mass_properties_update_list);
		}
		if (active_list.in_list()) {
			get_space()->body_remove_from_active_list(&active_list);
		}
		if (direct_state_query_list.in_list()) {
			get_space()->body_remove_from_state_query_list(&direct_state_query_list);
		}
	}

	_set_space(p_space);

	if (get_space()) {
		_mass_properties_changed();

		if (active && !active_list.in_list()) {
			get_space()->body_add_to_active_list(&active_list);
		}
	}
}

void GodotBody3D::set_axis_lock(PS3DE::BodyAxis p_axis, bool lock) {
	if (lock) {
		locked_axis |= p_axis;
	} else {
		locked_axis &= ~p_axis;
	}
}

bool GodotBody3D::is_axis_locked(PS3DE::BodyAxis p_axis) const {
	return locked_axis & p_axis;
}

void GodotBody3D::integrate_forces(real_t p_step, bool p_defer_motion) {
	if (mode == PS3DE::BODY_MODE_STATIC) {
		return;
	}

	ERR_FAIL_NULL(get_space());

	int ac = areas.size();

	bool gravity_done = false;
	bool linear_damp_done = false;
	bool angular_damp_done = false;

	bool stopped = false;

	gravity = Vector3(0, 0, 0);

	total_linear_damp = 0.0;
	total_angular_damp = 0.0;

	// Combine gravity and damping from overlapping areas in priority order.
	if (ac) {
		areas.sort();
		const AreaCMP *aa = &areas[0];
		for (int i = ac - 1; i >= 0 && !stopped; i--) {
			if (!gravity_done) {
				PS3DE::AreaSpaceOverrideMode area_gravity_mode = (PS3DE::AreaSpaceOverrideMode)(int)aa[i].area->get_param(PS3DE::AREA_PARAM_GRAVITY_OVERRIDE_MODE);
				if (area_gravity_mode != PS3DE::AREA_SPACE_OVERRIDE_DISABLED) {
					Vector3 area_gravity;
					aa[i].area->compute_gravity(get_transform().get_origin(), area_gravity);
					switch (area_gravity_mode) {
						case PS3DE::AREA_SPACE_OVERRIDE_COMBINE:
						case PS3DE::AREA_SPACE_OVERRIDE_COMBINE_REPLACE: {
							gravity += area_gravity;
							gravity_done = area_gravity_mode == PS3DE::AREA_SPACE_OVERRIDE_COMBINE_REPLACE;
						} break;
						case PS3DE::AREA_SPACE_OVERRIDE_REPLACE:
						case PS3DE::AREA_SPACE_OVERRIDE_REPLACE_COMBINE: {
							gravity = area_gravity;
							gravity_done = area_gravity_mode == PS3DE::AREA_SPACE_OVERRIDE_REPLACE;
						} break;
						default: {
						}
					}
				}
			}
			if (!linear_damp_done) {
				PS3DE::AreaSpaceOverrideMode area_linear_damp_mode = (PS3DE::AreaSpaceOverrideMode)(int)aa[i].area->get_param(PS3DE::AREA_PARAM_LINEAR_DAMP_OVERRIDE_MODE);
				if (area_linear_damp_mode != PS3DE::AREA_SPACE_OVERRIDE_DISABLED) {
					real_t area_linear_damp = aa[i].area->get_linear_damp();
					switch (area_linear_damp_mode) {
						case PS3DE::AREA_SPACE_OVERRIDE_COMBINE:
						case PS3DE::AREA_SPACE_OVERRIDE_COMBINE_REPLACE: {
							total_linear_damp += area_linear_damp;
							linear_damp_done = area_linear_damp_mode == PS3DE::AREA_SPACE_OVERRIDE_COMBINE_REPLACE;
						} break;
						case PS3DE::AREA_SPACE_OVERRIDE_REPLACE:
						case PS3DE::AREA_SPACE_OVERRIDE_REPLACE_COMBINE: {
							total_linear_damp = area_linear_damp;
							linear_damp_done = area_linear_damp_mode == PS3DE::AREA_SPACE_OVERRIDE_REPLACE;
						} break;
						default: {
						}
					}
				}
			}
			if (!angular_damp_done) {
				PS3DE::AreaSpaceOverrideMode area_angular_damp_mode = (PS3DE::AreaSpaceOverrideMode)(int)aa[i].area->get_param(PS3DE::AREA_PARAM_ANGULAR_DAMP_OVERRIDE_MODE);
				if (area_angular_damp_mode != PS3DE::AREA_SPACE_OVERRIDE_DISABLED) {
					real_t area_angular_damp = aa[i].area->get_angular_damp();
					switch (area_angular_damp_mode) {
						case PS3DE::AREA_SPACE_OVERRIDE_COMBINE:
						case PS3DE::AREA_SPACE_OVERRIDE_COMBINE_REPLACE: {
							total_angular_damp += area_angular_damp;
							angular_damp_done = area_angular_damp_mode == PS3DE::AREA_SPACE_OVERRIDE_COMBINE_REPLACE;
						} break;
						case PS3DE::AREA_SPACE_OVERRIDE_REPLACE:
						case PS3DE::AREA_SPACE_OVERRIDE_REPLACE_COMBINE: {
							total_angular_damp = area_angular_damp;
							angular_damp_done = area_angular_damp_mode == PS3DE::AREA_SPACE_OVERRIDE_REPLACE;
						} break;
						default: {
						}
					}
				}
			}
			stopped = gravity_done && linear_damp_done && angular_damp_done;
		}
	}

	// Add default gravity and damping from space area.
	if (!stopped) {
		GodotArea3D *default_area = get_space()->get_default_area();
		ERR_FAIL_NULL(default_area);

		if (!gravity_done) {
			Vector3 default_gravity;
			default_area->compute_gravity(get_transform().get_origin(), default_gravity);
			gravity += default_gravity;
		}

		if (!linear_damp_done) {
			total_linear_damp += default_area->get_linear_damp();
		}

		if (!angular_damp_done) {
			total_angular_damp += default_area->get_angular_damp();
		}
	}

	// Override linear damping with body's value.
	switch (linear_damp_mode) {
		case PS3DE::BODY_DAMP_MODE_COMBINE: {
			total_linear_damp += linear_damp;
		} break;
		case PS3DE::BODY_DAMP_MODE_REPLACE: {
			total_linear_damp = linear_damp;
		} break;
	}

	// Override angular damping with body's value.
	switch (angular_damp_mode) {
		case PS3DE::BODY_DAMP_MODE_COMBINE: {
			total_angular_damp += angular_damp;
		} break;
		case PS3DE::BODY_DAMP_MODE_REPLACE: {
			total_angular_damp = angular_damp;
		} break;
	}

	gravity *= gravity_scale;

	prev_linear_velocity = linear_velocity;
	prev_angular_velocity = angular_velocity;

	Vector3 motion;
	bool do_motion = false;

	if (mode == PS3DE::BODY_MODE_KINEMATIC) {
		//compute motion, angular and etc. velocities from prev transform
		motion = new_transform.origin - get_transform().origin;
		do_motion = is_continuous_collision_detection_enabled();
		linear_velocity = constant_linear_velocity + motion / p_step;

		//compute a FAKE angular velocity, not so easy
		Basis rot = new_transform.basis.orthonormalized() * get_transform().basis.orthonormalized().transposed();
		Vector3 axis;
		real_t angle;

		rot.get_axis_angle(axis, angle);
		axis.normalize();
		angular_velocity = constant_angular_velocity + axis * (angle / p_step);
	} else {
		if (!omit_force_integration) {
			//overridden by direct state query

			Vector3 force = gravity * mass + applied_force + constant_force;
			// Uniform fully submerged buoyancy: force = -buoyancy * mass * gravity.
			// Gravity already includes the body's gravity scale and area
			// overrides. With buoyancy 1, gravity and buoyancy cancel.
			// Zero (the default) preserves the old force calculation.
			if (!get_space()->is_fluid_plane_enabled() && get_space()->get_fluid_buoyancy() > real_t(0.0)) {
				// Uniform buoyancy is the legacy alternative to the new finite
				// liquid-surface model; do not apply both lift terms.
				force -= gravity * (mass * get_space()->get_fluid_buoyancy());
			}
			Vector3 torque = applied_torque + constant_torque;

			// Jolt-style displaced-volume buoyancy for a horizontal liquid
			// surface. The fraction and center of the submerged shape use its
			// cached world AABB as an approximation (not a clipped polyhedron).
			// Disabled by default: the extra shape loop costs nothing unless
			// a project opts into this more complex fluid simulation.
			real_t submerged_volume = 0.0;
			real_t total_fluid_shape_volume = 0.0;
			if (get_space()->is_fluid_plane_enabled() && get_space()->get_fluid_plane_density() > 0.0 && p_step > 0.0) {
				const real_t density = get_space()->get_fluid_plane_density();
				const Vector3 flow_velocity = get_space()->get_fluid_plane_flow_velocity();
				const Vector3 world_center_of_mass = get_transform().origin + center_of_mass;
				const int shape_count = get_shape_count();
				for (int i = 0; i < shape_count; ++i) {
					if (is_shape_disabled(i)) {
						continue;
					}
					const real_t shape_volume = get_shape_area(i);
					if (!(shape_volume > 0.0)) {
						continue;
					}
					total_fluid_shape_volume += shape_volume;
					// The cached broadphase AABB can be padded or swept for
					// CCD. Use it only to reject definitely dry shapes; then
					// compute current transformed bounds for a valid waterline.
					const real_t water_height = get_space()->get_fluid_plane_surface_height();
					if (get_shape_aabb(i).position.y >= water_height) {
						continue;
					}
					const GodotShape3D *shape = get_shape(i);
					const Transform3D shape_world = get_transform() * get_shape_transform(i);
					const AABB bounds = shape_world.xform(shape->get_aabb());
					GodotPhysicsFluidSample3D sample;
					const PS3DE::ShapeType shape_type = shape->get_type();
					real_t uniform_scale;
					// Unlike the AABB approximation, these primitive integrals
					// recover the actual volume and first hydrostatic moment.
					// Only similarity transforms preserve spherical sections.
					if ((shape_type == PS3DE::SHAPE_SPHERE || shape_type == PS3DE::SHAPE_CAPSULE) &&
							godot_physics_fluid_uniform_scale_3d(shape_world.basis, uniform_scale)) {
						if (shape_type == PS3DE::SHAPE_SPHERE) {
							const GodotSphereShape3D *sphere = static_cast<const GodotSphereShape3D *>(shape);
							sample = godot_physics_fluid_sphere_sample_3d(shape_world.origin,
									sphere->get_radius() * uniform_scale, shape_volume, water_height);
						} else if (godot_physics_fluid_capsule_vertical_3d(shape_world.basis, uniform_scale)) {
							const GodotCapsuleShape3D *capsule = static_cast<const GodotCapsuleShape3D *>(shape);
							// Raw PhysicsServer shapes can specify height < 2*radius,
							// which is not a cylinder plus hemispheres. Keep the
							// AABB behavior rather than returning zero displaced volume.
							if (capsule->get_radius() > 0.0 && capsule->get_height() >= real_t(2.0) * capsule->get_radius()) {
								sample = godot_physics_fluid_vertical_capsule_sample_3d(shape_world.origin,
										capsule->get_radius() * uniform_scale,
										capsule->get_height() * uniform_scale, shape_volume, water_height);
							} else {
								sample = godot_physics_fluid_sample_3d(bounds, shape_volume, water_height);
							}
						} else {
							// A tilted capsule has noncircular horizontal slices.
							sample = godot_physics_fluid_sample_3d(bounds, shape_volume, water_height);
						}
					} else if (shape_type == PS3DE::SHAPE_SPHERE) {
						// When a transform is not a similarity, a sphere becomes
						// an affine ellipsoid. Integrating a transformed
						// spherical cap gives exact immersed volume AND the
						// lateral first moment needed for hydrostatic torque.
						// Uniform spheres retain their existing cheap path.
						const GodotSphereShape3D *sphere = static_cast<const GodotSphereShape3D *>(shape);
						real_t ellipsoid_total_volume = 0.0;
						if (godot_physics_fluid_affine_ellipsoid_sample_3d(
									shape_world, sphere->get_radius(), water_height,
									sample, ellipsoid_total_volume)) {
							total_fluid_shape_volume += ellipsoid_total_volume - shape_volume;
						} else {
							sample = godot_physics_fluid_sample_3d(bounds, shape_volume, water_height);
						}
					} else if (shape_type == PS3DE::SHAPE_BOX) {
						// The world AABB overstates the immersed volume of a tilted
						// box. Clip its six fixed tetrahedra instead, without
						// constructing a hull mesh or allocating scratch buffers.
						const GodotBoxShape3D *box = static_cast<const GodotBoxShape3D *>(shape);
						real_t exact_box_volume = 0.0;
						if (godot_physics_fluid_box_sample_3d(box->get_half_extents(),
									shape_world, water_height, sample, exact_box_volume)) {
							// Use the true volume for the immersed-fraction drag
							// denominator, consistent with exact convex hulls.
							total_fluid_shape_volume += exact_box_volume - shape_volume;
						} else {
							sample = godot_physics_fluid_sample_3d(bounds, shape_volume, water_height);
						}
					} else if (shape_type == PS3DE::SHAPE_CONVEX_POLYGON) {
						const GodotConvexPolygonShape3D *convex = static_cast<const GodotConvexPolygonShape3D *>(shape);
						real_t hull_volume = 0.0;
						if (godot_physics_fluid_convex_hull_sample_3d(convex->get_mesh(), shape_world,
									water_height, sample, hull_volume)) {
							// ConvexPolygonShape3D uses AABB volume for its mass;
							// correct both the fluid displacement and the denominator
							// for submerged-fraction angular damping here.
							total_fluid_shape_volume += hull_volume - shape_volume;
						} else {
							// Invalid or extremely complex hulls retain the cheap
							// AABB model rather than suppressing buoyancy entirely.
							sample = godot_physics_fluid_sample_3d(bounds, shape_volume, water_height);
						}
					} else {
						// Shapes without an exact supported solver use the AABB path.
						sample = godot_physics_fluid_sample_3d(bounds, shape_volume, water_height);
					}
					if (!(sample.submerged_volume > 0.0)) {
						continue;
					}
					submerged_volume += sample.submerged_volume;
					const Vector3 lever = sample.center_of_buoyancy - world_center_of_mass;
					const Vector3 lift = -gravity * (density * sample.submerged_volume);
					const Vector3 relative_velocity = linear_velocity + angular_velocity.cross(lever) - flow_velocity;
					Vector3 drag = godot_physics_fluid_quadratic_drag_3d(
							relative_velocity, bounds.size, sample.submerged_fraction,
							density, get_space()->get_fluid_plane_drag_coefficient());
					// Large density and coarse timesteps must not reverse a
					// shape's relative flow solely because of explicit drag.
					const real_t max_impulse = mass * relative_velocity.length() / real_t(MAX(1, shape_count));
					const real_t drag_impulse = drag.length() * p_step;
					if (drag_impulse > max_impulse && drag_impulse > 0.0) {
						drag *= max_impulse / drag_impulse;
					}
					force += lift + drag;
					if (mode == PS3DE::BODY_MODE_RIGID) {
						torque += lever.cross(lift + drag);
					}
				}
			}

			// This per-space option uses Box2D's implicit (Pade) damping
			// for nonnegative coefficients. The default retains the legacy
			// clamped explicit-Euler result exactly.
			const bool implicit_damping = get_space()->is_implicit_damping_enabled();
			const real_t damp = godot_physics_damping_factor(p_step, total_linear_damp, implicit_damping);
			const real_t angular_damp_new = godot_physics_damping_factor(p_step, total_angular_damp, implicit_damping);

			linear_velocity *= damp;
			angular_velocity *= angular_damp_new;

			linear_velocity += _inv_mass * force * p_step;
			angular_velocity += _inv_inertia_tensor.xform(torque) * p_step;
			if (submerged_volume > 0.0 && total_fluid_shape_volume > 0.0) {
				const real_t fraction = CLAMP(submerged_volume / total_fluid_shape_volume, real_t(0.0), real_t(1.0));
				angular_velocity *= godot_physics_fluid_angular_damping_3d(
						get_space()->get_fluid_plane_angular_drag(), fraction, p_step);
			}

			// Free asymmetric rigid bodies precess because their angular
			// momentum and angular velocity are generally not parallel.
			// Box2D's planar rotations have no corresponding gyro term.
			// Keep this separate from the legacy off-path and skip axis-locked
			// bodies, whose constrained rotation needs a different equation.
			if (mode == PS3DE::BODY_MODE_RIGID && get_space()->are_gyroscopic_forces_enabled() &&
					(locked_axis & ((1 << 3) | (1 << 4) | (1 << 5))) == 0 && angular_velocity != Vector3()) {
				const Basis principal_frame = principal_inertia_axes.orthonormalized();
				if (principal_frame.is_finite()) {
					const Vector3 principal_omega = principal_frame.xform_inv(angular_velocity);
					const Vector3 corrected_omega = get_space()->get_gyroscopic_integration_mode() == 1 ?
							GodotPhysicsGyroscopic3D::integrate_principal_midpoint(principal_omega, _inv_inertia, p_step) :
							GodotPhysicsGyroscopic3D::integrate_principal(principal_omega, _inv_inertia, p_step);
					angular_velocity = principal_frame.xform(corrected_omega);
				}
			}
	
			// Quadratic fluid resistance acts after external forces and
			// optional gyroscopic integration. Kinematic bodies and custom
			// force integration remain untouched.
			linear_velocity = godot_physics_fluid_linear_drag(
					linear_velocity, get_space()->get_fluid_flow_velocity(), get_space()->get_fluid_linear_drag(), p_step);
			angular_velocity = godot_physics_fluid_angular_drag(
					angular_velocity, get_space()->get_fluid_angular_drag(), p_step);
		}

		// Limit dynamic angular speed after damping, torque and optional gyro
		// integration. Kinematic bodies retain their requested target rotation.
		angular_velocity = godot_physics_clamp_angular_velocity(angular_velocity, get_effective_max_angular_velocity(get_space()->get_max_angular_velocity()));
		// Rapier-style CCD safeguard: limit the *physical* rotation across
		// one step, not the penetration-correction bias. A joint/contact may
		// change angular velocity after force integration, so apply at both
		// integration boundaries. Disabled by default and for non-CCD bodies.
		if (continuous_cd) {
			angular_velocity = godot_physics_clamp_ccd_angular_velocity(
					angular_velocity, get_space()->get_ccd_max_angular_motion(), p_step);
		}

		// Bound physical velocity before calculating the broadphase CCD sweep.
		// This is skipped by static and kinematic bodies.
		linear_velocity = godot_physics_clamp_linear_velocity(linear_velocity, get_effective_max_linear_velocity(get_space()->get_max_linear_velocity()));

		if (continuous_cd) {
			motion = linear_velocity * p_step;
			do_motion = true;
		}
	}

	applied_force = Vector3();
	applied_torque = Vector3();

	biased_angular_velocity = Vector3();
	biased_linear_velocity = Vector3();

	if (do_motion) { //shapes temporarily extend for raycast
		if (p_defer_motion) {
			deferred_motion = motion;
			has_deferred_motion = true;
		} else {
			_update_shapes_with_motion(motion, angular_velocity, p_step, get_transform().origin + center_of_mass);
		}
	}

	contact_count = 0;
}

void GodotBody3D::integrate_velocities(real_t p_step) {
	if (mode == PS3DE::BODY_MODE_STATIC) {
		return;
	}

	ERR_FAIL_NULL(get_space());

	if (fi_callback_data || body_state_callback.is_valid()) {
		get_space()->body_add_to_state_query_list(&direct_state_query_list);
	}

	//apply axis lock linear
	for (int i = 0; i < 3; i++) {
		if (is_axis_locked((PS3DE::BodyAxis)(1 << i))) {
			linear_velocity[i] = 0;
			biased_linear_velocity[i] = 0;
			new_transform.origin[i] = get_transform().origin[i];
		}
	}
	//apply axis lock angular
	for (int i = 0; i < 3; i++) {
		if (is_axis_locked((PS3DE::BodyAxis)(1 << (i + 3)))) {
			angular_velocity[i] = 0;
			biased_angular_velocity[i] = 0;
		}
	}

	if (mode == PS3DE::BODY_MODE_KINEMATIC) {
		_set_transform(new_transform, !is_continuous_collision_detection_enabled());
		_set_inv_transform(new_transform.affine_inverse());
		if (contacts.is_empty() && linear_velocity == Vector3() && angular_velocity == Vector3()) {
			set_active(false); //stopped moving, deactivate
		}

		return;
	}

	// Contact and joint impulses can add speed after force integration.
	// Cap the physical component before position integration too.
	linear_velocity = godot_physics_clamp_linear_velocity(linear_velocity, get_effective_max_linear_velocity(get_space()->get_max_linear_velocity()));
	// Contacts and joints can increase angular velocity after force integration.
	// Limit physical rotation, leaving penetration-correction bias untouched.
	angular_velocity = godot_physics_clamp_angular_velocity(angular_velocity, get_effective_max_angular_velocity(get_space()->get_max_angular_velocity()));
	// Reapply the CCD-only per-step cap after contact/joint impulses.
	if (continuous_cd) {
		angular_velocity = godot_physics_clamp_ccd_angular_velocity(
				angular_velocity, get_space()->get_ccd_max_angular_motion(), p_step);
	}
	Vector3 total_angular_velocity = angular_velocity + biased_angular_velocity;
	Vector3 total_linear_velocity = linear_velocity + biased_linear_velocity;

	// The mass properties and inertia tensor are already updated when they
	// change. Avoid rebuilding an unchanged transform (and its inverse) for
	// active stationary bodies, which is common in sparse simulations.
	if (total_angular_velocity == Vector3() && total_linear_velocity == Vector3()) {
		return;
	}

	real_t ang_vel = total_angular_velocity.length();
	Transform3D transform_new = get_transform();

	const bool rotated = !Math::is_zero_approx(ang_vel);
	if (rotated) {
		Vector3 ang_vel_axis = total_angular_velocity / ang_vel;
		Basis rot(ang_vel_axis, ang_vel * p_step);
		Basis identity3(1, 0, 0, 0, 1, 0, 0, 0, 1);
		transform_new.origin += ((identity3 - rot) * transform_new.basis).xform(center_of_mass_local);
		transform_new.basis = rot * transform_new.basis;
		transform_new.orthonormalize();
	}

	/*for(int i=0;i<3;i++) {
		if (axis_lock&(1<<i)) {
			transform_new.origin[i]=0.0;
		}
	}*/

	transform_new.origin += total_linear_velocity * p_step;

	_set_transform(transform_new);
	_set_inv_transform(get_transform().inverse());

	// Pure translation does not change the local center of mass orientation
	// or the world inertia tensor. Recompute them only after rotation.
	if (rotated) {
		_update_transform_dependent();
	}
}

void GodotBody3D::add_constraint(GodotConstraint3D *p_constraint, int p_pos) {
	p_constraint->set_body_slot(p_pos, constraint_list.size());
	constraint_list.push_back({ p_constraint, p_pos });
}

void GodotBody3D::remove_constraint(GodotConstraint3D *p_constraint, int p_pos) {
	uint32_t index = p_constraint->get_body_slot(p_pos);
	if (index >= constraint_list.size() || constraint_list[index].first != p_constraint || constraint_list[index].second != p_pos) {
		// The list was cleared or reordered behind the constraint's back.
		index = UINT32_MAX;
		for (uint32_t i = 0; i < constraint_list.size(); i++) {
			if (constraint_list[i].first == p_constraint && constraint_list[i].second == p_pos) {
				index = i;
				break;
			}
		}
		if (index == UINT32_MAX) {
			return;
		}
	}

	const uint32_t last = constraint_list.size() - 1;
	if (index != last) {
		constraint_list[index] = constraint_list[last];
		constraint_list[index].first->set_body_slot(constraint_list[index].second, index);
	}
	constraint_list.resize(last);
}

void GodotBody3D::wakeup_neighbours() {
	for (const Pair<GodotConstraint3D *, int> &E : constraint_list) {
		const GodotConstraint3D *c = E.first;
		GodotBody3D **n = c->get_body_ptr();
		int bc = c->get_body_count();

		for (int i = 0; i < bc; i++) {
			if (i == E.second) {
				continue;
			}
			GodotBody3D *b = n[i];
			if (b->mode < PS3DE::BODY_MODE_RIGID) {
				continue;
			}

			if (!b->is_active()) {
				b->set_active(true);
			}
		}
	}
}

void GodotBody3D::call_queries() {
	Variant direct_state_variant = get_direct_state();

	if (fi_callback_data) {
		if (!fi_callback_data->callable.is_valid()) {
			set_force_integration_callback(Callable());
		} else {
			const Variant *vp[2] = { &direct_state_variant, &fi_callback_data->udata };

			Callable::CallError ce;
			int argc = (fi_callback_data->udata.get_type() == Variant::NIL) ? 1 : 2;
			Variant rv;
			fi_callback_data->callable.callp(vp, argc, rv, ce);
		}
	}

	if (body_state_callback.is_valid()) {
		body_state_callback.call(direct_state_variant);
	}
}

bool GodotBody3D::sleep_test(real_t p_step) {
	if (mode == PS3DE::BODY_MODE_STATIC || mode == PS3DE::BODY_MODE_KINEMATIC) {
		return true;
	} else if (!can_sleep) {
		return false;
	}

	ERR_FAIL_NULL_V(get_space(), true);

	// Squared magnitude avoids a square root for every active body every step.
	// A non-positive threshold must never make angular motion eligible for sleep.
	const real_t angular_sleep_threshold = get_space()->get_body_angular_velocity_sleep_threshold();
	const real_t linear_sleep_threshold = get_space()->get_body_linear_velocity_sleep_threshold();
	if (angular_sleep_threshold > 0.0 && angular_velocity.length_squared() < angular_sleep_threshold * angular_sleep_threshold &&
			Math::abs(linear_velocity.length_squared()) < linear_sleep_threshold * linear_sleep_threshold) {
		still_time += p_step;

		return still_time > get_space()->get_body_time_to_sleep();
	} else {
		still_time = 0; //maybe this should be set to 0 on set_active?
		return false;
	}
}

void GodotBody3D::set_state_sync_callback(const Callable &p_callable) {
	body_state_callback = p_callable;
}

void GodotBody3D::set_force_integration_callback(const Callable &p_callable, const Variant &p_udata) {
	if (p_callable.is_valid()) {
		if (!fi_callback_data) {
			fi_callback_data = memnew(ForceIntegrationCallbackData);
		}
		fi_callback_data->callable = p_callable;
		fi_callback_data->udata = p_udata;
	} else if (fi_callback_data) {
		memdelete(fi_callback_data);
		fi_callback_data = nullptr;
	}
}

GodotPhysicsDirectBodyState3D *GodotBody3D::get_direct_state() {
	if (!direct_state) {
		direct_state = memnew(GodotPhysicsDirectBodyState3D);
		direct_state->body = this;
	}
	return direct_state;
}

GodotBody3D::GodotBody3D() :
		GodotCollisionObject3D(TYPE_BODY),
		active_list(this),
		mass_properties_update_list(this),
		direct_state_query_list(this) {
	_set_static(false);
}

GodotBody3D::~GodotBody3D() {
	memdelete(fi_callback_data);
	memdelete(direct_state);
}
