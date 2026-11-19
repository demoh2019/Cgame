/**************************************************************************/
/*  godot_joint_3d.h                                                      */
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

#include "godot_body_3d.h"
#include "godot_constraint_3d.h"
#include "servers/physics_joint_fatigue.h"

class GodotJoint3D : public GodotConstraint3D {
	// Impulse measured over the last solved step (see `solve`).
	uint64_t reaction_stamp = UINT64_MAX;
	real_t reaction_dt = 0.0;
	Vector3 acc_dv[2];
	Vector3 acc_dw[2];
	real_t break_force = 0.0;
	real_t break_torque = 0.0;
	real_t fatigue_rate = 0.0; // Accumulated damage per second under normalized reaction stress.
	real_t fatigue_yield_ratio = 0.5; // Fraction of instantaneous break limit below which fatigue is zero.
	double fatigue_damage = 0.0; // Irreversible Miner-like cycle accumulation, 0..1.
	uint64_t fatigue_reaction_stamp = UINT64_MAX; // Prevent stale / duplicate per-step damage.
	bool broken = false;
	Callable break_callback;

protected:
	bool dynamic_A = false;
	bool dynamic_B = false;

	virtual void _solve_joint(real_t p_step) {}

	void plane_space(const Vector3 &n, Vector3 &p, Vector3 &q) {
		if (Math::abs(n.z) > Math::SQRT12) {
			// choose p in y-z plane
			real_t a = n[1] * n[1] + n[2] * n[2];
			real_t k = 1.0 / Math::sqrt(a);
			p = Vector3(0, -n[2] * k, n[1] * k);
			// set q = n x p
			q = Vector3(a * k, -n[0] * p[2], n[0] * p[1]);
		} else {
			// choose p in x-y plane
			real_t a = n.x * n.x + n.y * n.y;
			real_t k = 1.0 / Math::sqrt(a);
			p = Vector3(-n.y * k, n.x * k, 0);
			// set q = n x p
			q = Vector3(-n.z * p.y, n.z * p.x, a * k);
		}
	}

	_FORCE_INLINE_ real_t atan2fast(real_t y, real_t x) {
		real_t coeff_1 = Math::PI / 4.0f;
		real_t coeff_2 = 3.0f * coeff_1;
		real_t abs_y = Math::abs(y);
		real_t angle;
		if (x >= 0.0f) {
			real_t r = (x - abs_y) / (x + abs_y);
			angle = coeff_1 - coeff_1 * r;
		} else {
			real_t r = (x + abs_y) / (abs_y - x);
			angle = coeff_2 - coeff_1 * r;
		}
		return (y < 0.0f) ? -angle : angle;
	}

public:
	virtual bool setup(real_t p_step) override { return false; }
	virtual bool pre_solve(real_t p_step) override { return true; }

	// Every joint solve is wrapped so the impulse the joint applies to its bodies can be
	// measured (reaction force and torque, breaking). Joint types implement `_solve_joint`.
	virtual void solve(real_t p_step) override final {
		if (broken) {
			return;
		}
		const uint64_t stamp = get_island_step();
		if (stamp != reaction_stamp) {
			reaction_stamp = stamp;
			reaction_dt = p_step;
			for (int i = 0; i < 2; i++) {
				acc_dv[i] = Vector3();
				acc_dw[i] = Vector3();
			}
		}
		GodotBody3D **bodies = get_body_ptr();
		const int count = MIN(get_body_count(), 2);
		Vector3 v_before[2];
		Vector3 w_before[2];
		for (int i = 0; i < count; i++) {
			v_before[i] = bodies[i]->get_linear_velocity();
			w_before[i] = bodies[i]->get_angular_velocity();
		}
		_solve_joint(p_step);
		for (int i = 0; i < count; i++) {
			acc_dv[i] += bodies[i]->get_linear_velocity() - v_before[i];
			acc_dw[i] += bodies[i]->get_angular_velocity() - w_before[i];
		}
	}

	// Force and torque (about the body's center of mass) the joint applied to the second
	// body during the last step it was solved. Falls back to the first body, negated.
	Vector3 get_reaction_force() const {
		if (reaction_dt <= 0.0 || get_body_count() < 2) {
			return Vector3();
		}
		GodotBody3D *const *bodies = get_body_ptr();
		if (bodies[1]->get_inv_mass() > 0.0 && bodies[1]->get_mode() > PS3DE::BODY_MODE_KINEMATIC) {
			return acc_dv[1] / (bodies[1]->get_inv_mass() * reaction_dt);
		}
		if (bodies[0]->get_inv_mass() > 0.0 && bodies[0]->get_mode() > PS3DE::BODY_MODE_KINEMATIC) {
			return -acc_dv[0] / (bodies[0]->get_inv_mass() * reaction_dt);
		}
		return Vector3();
	}

	Vector3 get_reaction_torque() const {
		if (reaction_dt <= 0.0 || get_body_count() < 2) {
			return Vector3();
		}
		GodotBody3D *const *bodies = get_body_ptr();
		for (int i = 1; i >= 0; i--) {
			if (bodies[i]->get_mode() > PS3DE::BODY_MODE_KINEMATIC) {
				const Basis inv_inertia = bodies[i]->get_inv_inertia_tensor();
				if (Math::abs(inv_inertia.determinant()) <= CMP_EPSILON2) {
					continue;  // Rotation locked or no inertia.
				}
				const Vector3 torque = inv_inertia.inverse().xform(acc_dw[i]) / reaction_dt;
				return i == 1 ? torque : -torque;
			}
		}
		return Vector3();
	}

	_FORCE_INLINE_ void set_break_force(real_t p_force) { break_force = MAX(p_force, real_t(0.0)); }
	_FORCE_INLINE_ real_t get_break_force() const { return break_force; }
	_FORCE_INLINE_ void set_break_torque(real_t p_torque) { break_torque = MAX(p_torque, real_t(0.0)); }
	_FORCE_INLINE_ real_t get_break_torque() const { return break_torque; }
	_FORCE_INLINE_ void set_fatigue_rate(real_t p_rate) { fatigue_rate = Math::is_finite(p_rate) ? MAX(p_rate, real_t(0.0)) : real_t(0.0); }
	_FORCE_INLINE_ real_t get_fatigue_rate() const { return fatigue_rate; }
	_FORCE_INLINE_ void set_fatigue_yield_ratio(real_t p_ratio) { fatigue_yield_ratio = Math::is_finite(p_ratio) ? CLAMP(p_ratio, real_t(0.0), real_t(0.99)) : real_t(0.5); }
	_FORCE_INLINE_ real_t get_fatigue_yield_ratio() const { return fatigue_yield_ratio; }
	_FORCE_INLINE_ real_t get_fatigue_damage() const { return real_t(fatigue_damage); }
	_FORCE_INLINE_ bool is_broken() const { return broken; }

	// Once per *completed* physics tick: reactions are recorded by the solver,
	// and fatigue consumes the newest island solution only once. Sleeping /
	// inactive joints must not accumulate damage from stale reactions.
	bool accumulate_fatigue(real_t p_delta) {
		if (broken || fatigue_rate <= 0.0 || !can_break() ||
				reaction_stamp == UINT64_MAX || reaction_stamp == fatigue_reaction_stamp ||
				!(p_delta > 0.0) || !Math::is_finite(p_delta)) {
			return false;
		}
		fatigue_reaction_stamp = reaction_stamp;
		const Vector3 force = get_reaction_force();
		const Vector3 torque = get_reaction_torque();
		if (!force.is_finite() || !torque.is_finite()) {
			return false;
		}
		const double force_magnitude = Math::sqrt(double(force.x) * double(force.x) +
				double(force.y) * double(force.y) + double(force.z) * double(force.z));
		const double torque_magnitude = Math::sqrt(double(torque.x) * double(torque.x) +
				double(torque.y) * double(torque.y) + double(torque.z) * double(torque.z));
		return physics_joint_accumulate_fatigue_damage(force_magnitude, torque_magnitude,
				double(break_force), double(break_torque), double(fatigue_yield_ratio),
				double(fatigue_rate), double(p_delta), fatigue_damage);
	}
	_FORCE_INLINE_ bool is_fatigue_broken() const { return fatigue_damage >= 1.0; }
	_FORCE_INLINE_ bool can_break() const { return !broken && (break_force > 0.0 || break_torque > 0.0); }
	_FORCE_INLINE_ void set_break_callback(const Callable &p_callback) { break_callback = p_callback; }
	_FORCE_INLINE_ const Callable &get_break_callback() const { return break_callback; }

	// Whether the last solved step exceeded a break threshold.
	bool exceeds_break_threshold() const {
		if (!can_break()) {
			return false;
		}
		if (break_force > 0.0 && get_reaction_force().length_squared() > break_force * break_force) {
			return true;
		}
		return break_torque > 0.0 && get_reaction_torque().length_squared() > break_torque * break_torque;
	}

	// Detaches the joint from its bodies and wakes them. The joint object stays valid so the
	// RID can still be queried and freed.
	void break_joint() {
		if (broken) {
			return;
		}
		broken = true;
		for (int i = 0; i < get_body_count(); i++) {
			GodotBody3D *body = get_body_ptr()[i];
			if (body) {
				body->remove_constraint(this, i);
				if (body->get_mode() > PS3DE::BODY_MODE_KINEMATIC) {
					body->set_active(true);
				}
			}
		}
	}

	void copy_settings_from(GodotJoint3D *p_joint) {
		set_self(p_joint->get_self());
		set_priority(p_joint->get_priority());
		disable_collisions_between_bodies(p_joint->is_disabled_collisions_between_bodies());
		break_force = p_joint->break_force;
		break_torque = p_joint->break_torque;
		fatigue_rate = p_joint->fatigue_rate;
		fatigue_yield_ratio = p_joint->fatigue_yield_ratio;
		// Rebuilt connections start with a new material fatigue history.
		break_callback = p_joint->break_callback;
	}

	virtual PS3DE::JointType get_type() const { return PS3DE::JOINT_TYPE_MAX; }
	_FORCE_INLINE_ GodotJoint3D(GodotBody3D **p_body_ptr = nullptr, int p_body_count = 0) :
			GodotConstraint3D(p_body_ptr, p_body_count) {
	}

	virtual ~GodotJoint3D() {
		for (int i = 0; i < get_body_count(); i++) {
			GodotBody3D *body = get_body_ptr()[i];
			if (body) {
				body->remove_constraint(this, i);
			}
		}
	}
};
