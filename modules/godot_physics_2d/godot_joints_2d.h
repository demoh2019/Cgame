/**************************************************************************/
/*  godot_joints_2d.h                                                     */
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

#include "godot_body_2d.h"
#include "godot_constraint_2d.h"

class GodotJoint2D : public GodotConstraint2D {
	real_t bias = 0;
	real_t max_bias = 3.40282e+38;
	real_t max_force = 3.40282e+38;

	// Impulse measured over the last solved step (see `solve`).
	uint64_t reaction_stamp = UINT64_MAX;
	real_t reaction_dt = 0.0;
	Vector2 acc_dv[2];
	real_t acc_dw[2] = { 0.0, 0.0 };
	real_t break_force = 0.0;
	real_t break_torque = 0.0;
	bool broken = false;
	Callable break_callback;

protected:
	bool dynamic_A = false;
	bool dynamic_B = false;

	virtual bool _pre_solve_joint(real_t p_step) { return false; }
	virtual void _solve_joint(real_t p_step) {}

	// Starts a new measurement window once per solved step (identified by the island stamp).
	void _begin_reaction(real_t p_step) {
		const uint64_t stamp = get_island_step();
		if (stamp != reaction_stamp) {
			reaction_stamp = stamp;
			reaction_dt = p_step;
			for (int i = 0; i < 2; i++) {
				acc_dv[i] = Vector2();
				acc_dw[i] = 0.0;
			}
		}
	}

public:
	_FORCE_INLINE_ void set_max_force(real_t p_force) { max_force = p_force; }
	_FORCE_INLINE_ real_t get_max_force() const { return max_force; }

	_FORCE_INLINE_ void set_bias(real_t p_bias) { bias = p_bias; }
	_FORCE_INLINE_ real_t get_bias() const { return bias; }

	_FORCE_INLINE_ void set_max_bias(real_t p_bias) { max_bias = p_bias; }
	_FORCE_INLINE_ real_t get_max_bias() const { return max_bias; }

	virtual bool setup(real_t p_step) override { return false; }
	// 2D joints apply their accumulated impulse (warm start) in pre_solve, outside solve(), so
	// the measurement window opens here.
	virtual bool pre_solve(real_t p_step) override final {
		_begin_reaction(p_step);
		GodotBody2D **bodies = get_body_ptr();
		const int count = MIN(get_body_count(), 2);
		Vector2 v_before[2];
		real_t w_before[2] = { 0.0, 0.0 };
		for (int i = 0; i < count; i++) {
			v_before[i] = bodies[i]->get_linear_velocity();
			w_before[i] = bodies[i]->get_angular_velocity();
		}
		const bool result = _pre_solve_joint(p_step);
		for (int i = 0; i < count; i++) {
			acc_dv[i] += bodies[i]->get_linear_velocity() - v_before[i];
			acc_dw[i] += bodies[i]->get_angular_velocity() - w_before[i];
		}
		return result;
	}
	// Every joint solve is wrapped so the impulse the joint applies to its bodies can be
	// measured (reaction force and torque, breaking). Joint types implement `_solve_joint`.
	virtual void solve(real_t p_step) override final {
		if (broken) {
			return;
		}
		_begin_reaction(p_step);
		GodotBody2D **bodies = get_body_ptr();
		const int count = MIN(get_body_count(), 2);
		Vector2 v_before[2];
		real_t w_before[2] = { 0.0, 0.0 };
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
	Vector2 get_reaction_force() const {
		if (reaction_dt <= 0.0 || get_body_count() < 2) {
			return Vector2();
		}
		GodotBody2D *const *bodies = get_body_ptr();
		if (bodies[1]->get_inv_mass() > 0.0 && bodies[1]->get_mode() > PS2DE::BODY_MODE_KINEMATIC) {
			return acc_dv[1] / (bodies[1]->get_inv_mass() * reaction_dt);
		}
		if (bodies[0]->get_inv_mass() > 0.0 && bodies[0]->get_mode() > PS2DE::BODY_MODE_KINEMATIC) {
			return -acc_dv[0] / (bodies[0]->get_inv_mass() * reaction_dt);
		}
		return Vector2();
	}

	real_t get_reaction_torque() const {
		if (reaction_dt <= 0.0 || get_body_count() < 2) {
			return 0.0;
		}
		GodotBody2D *const *bodies = get_body_ptr();
		for (int i = 1; i >= 0; i--) {
			if (bodies[i]->get_mode() > PS2DE::BODY_MODE_KINEMATIC && bodies[i]->get_inv_inertia() > 0.0) {
				const real_t torque = acc_dw[i] / (bodies[i]->get_inv_inertia() * reaction_dt);
				return i == 1 ? torque : -torque;
			}
		}
		return 0.0;
	}

	_FORCE_INLINE_ void set_break_force(real_t p_force) { break_force = MAX(p_force, real_t(0.0)); }
	_FORCE_INLINE_ real_t get_break_force() const { return break_force; }
	_FORCE_INLINE_ void set_break_torque(real_t p_torque) { break_torque = MAX(p_torque, real_t(0.0)); }
	_FORCE_INLINE_ real_t get_break_torque() const { return break_torque; }
	_FORCE_INLINE_ bool is_broken() const { return broken; }
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
		return break_torque > 0.0 && Math::abs(get_reaction_torque()) > break_torque;
	}

	// Detaches the joint from its bodies and wakes them. The joint object stays valid so the
	// RID can still be queried and freed.
	void break_joint() {
		if (broken) {
			return;
		}
		broken = true;
		for (int i = 0; i < get_body_count(); i++) {
			GodotBody2D *body = get_body_ptr()[i];
			if (body) {
				body->remove_constraint(this, i);
				if (body->get_mode() > PS2DE::BODY_MODE_KINEMATIC) {
					body->set_active(true);
				}
			}
		}
	}

	void copy_settings_from(GodotJoint2D *p_joint);

	virtual PS2DE::JointType get_type() const { return PS2DE::JOINT_TYPE_MAX; }
	GodotJoint2D(GodotBody2D **p_body_ptr = nullptr, int p_body_count = 0) :
			GodotConstraint2D(p_body_ptr, p_body_count) {}

	virtual ~GodotJoint2D() {
		for (int i = 0; i < get_body_count(); i++) {
			GodotBody2D *body = get_body_ptr()[i];
			if (body) {
				body->remove_constraint(this, i);
			}
		}
	}
};

class GodotPinJoint2D : public GodotJoint2D {
	union {
		struct {
			GodotBody2D *A;
			GodotBody2D *B;
		};

		GodotBody2D *_arr[2] = { nullptr, nullptr };
	};

	Transform2D M;
	Vector2 rA, rB;
	Vector2 anchor_A;
	Vector2 anchor_B;
	Vector2 bias;
	real_t initial_angle = 0.0;
	real_t bias_velocity = 0.0;
	real_t jn_max = 0.0;
	real_t j_acc = 0.0;
	real_t i_sum = 0.0;
	Vector2 P;
	real_t softness = 0.0;
	real_t angular_limit_lower = 0.0;
	real_t angular_limit_upper = 0.0;
	real_t motor_target_velocity = 0.0;
	bool is_joint_at_limit = false;
	bool motor_enabled = false;
	bool angular_limit_enabled = false;

public:
	virtual PS2DE::JointType get_type() const override { return PS2DE::JOINT_TYPE_PIN; }

	virtual bool setup(real_t p_step) override;
	virtual bool _pre_solve_joint(real_t p_step) override;
	virtual void _solve_joint(real_t p_step) override;

	void set_param(PS2DE::PinJointParam p_param, real_t p_value);
	real_t get_param(PS2DE::PinJointParam p_param) const;

	void set_flag(PS2DE::PinJointFlag p_flag, bool p_enabled);
	bool get_flag(PS2DE::PinJointFlag p_flag) const;

	GodotPinJoint2D(const Vector2 &p_pos, GodotBody2D *p_body_a, GodotBody2D *p_body_b = nullptr);
};

class GodotGrooveJoint2D : public GodotJoint2D {
	union {
		struct {
			GodotBody2D *A;
			GodotBody2D *B;
		};

		GodotBody2D *_arr[2] = { nullptr, nullptr };
	};

	Vector2 A_groove_1;
	Vector2 A_groove_2;
	Vector2 A_groove_normal;
	Vector2 B_anchor;
	Vector2 jn_acc;
	Vector2 gbias;
	real_t jn_max = 0.0;
	real_t clamp = 0.0;
	Vector2 xf_normal;
	Vector2 rA, rB;
	Vector2 k1, k2;

	bool correct = false;

public:
	virtual PS2DE::JointType get_type() const override { return PS2DE::JOINT_TYPE_GROOVE; }

	virtual bool setup(real_t p_step) override;
	virtual bool _pre_solve_joint(real_t p_step) override;
	virtual void _solve_joint(real_t p_step) override;

	GodotGrooveJoint2D(const Vector2 &p_a_groove1, const Vector2 &p_a_groove2, const Vector2 &p_b_anchor, GodotBody2D *p_body_a, GodotBody2D *p_body_b);
};

class GodotDampedSpringJoint2D : public GodotJoint2D {
	union {
		struct {
			GodotBody2D *A;
			GodotBody2D *B;
		};

		GodotBody2D *_arr[2] = { nullptr, nullptr };
	};

	Vector2 anchor_A;
	Vector2 anchor_B;

	real_t rest_length = 0.0;
	real_t damping = 1.5;
	real_t stiffness = 20.0;

	Vector2 rA, rB;
	Vector2 n;
	Vector2 j;
	real_t n_mass = 0.0;
	real_t target_vrn = 0.0;
	real_t v_coef = 0.0;

public:
	virtual PS2DE::JointType get_type() const override { return PS2DE::JOINT_TYPE_DAMPED_SPRING; }

	virtual bool setup(real_t p_step) override;
	virtual bool _pre_solve_joint(real_t p_step) override;
	virtual void _solve_joint(real_t p_step) override;

	void set_param(PS2DE::DampedSpringParam p_param, real_t p_value);
	real_t get_param(PS2DE::DampedSpringParam p_param) const;

	GodotDampedSpringJoint2D(const Vector2 &p_anchor_a, const Vector2 &p_anchor_b, GodotBody2D *p_body_a, GodotBody2D *p_body_b);
};
