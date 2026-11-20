/**************************************************************************/
/*  spring_damper.cpp                                                     */
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

#include "spring_damper.h"

#include "core/object/class_db.h"
#include "core/variant/type_info.h"

SpringDamper::Coefficients SpringDamper::compute(real_t p_frequency, real_t p_damping_ratio, real_t p_delta) {
	Coefficients c;
	const real_t epsilon = 0.0001;
	const real_t omega = real_t(Math::TAU) * MAX(p_frequency, real_t(0.0));
	const real_t zeta = MAX(p_damping_ratio, real_t(0.0));
	const real_t t = MAX(p_delta, real_t(0.0));

	if (omega < epsilon || t <= real_t(0.0)) {
		// No spring: keep coasting with the current velocity.
		c.pos_vel = t;
		return c;
	}

	if (zeta > real_t(1.0) + epsilon) {
		// Over-damped.
		const real_t za = -omega * zeta;
		const real_t zb = omega * Math::sqrt(zeta * zeta - real_t(1.0));
		const real_t z1 = za - zb;
		const real_t z2 = za + zb;
		const real_t e1 = Math::exp(z1 * t);
		const real_t e2 = Math::exp(z2 * t);
		const real_t inv_two_zb = real_t(1.0) / (real_t(2.0) * zb);
		const real_t e1_over = e1 * inv_two_zb;
		const real_t e2_over = e2 * inv_two_zb;
		const real_t z1e1 = z1 * e1_over;
		const real_t z2e2 = z2 * e2_over;
		c.pos_pos = e1_over * z2 - z2e2 + e2;
		c.pos_vel = -e1_over + e2_over;
		c.vel_pos = (z1e1 - z2e2 + e2) * z2;
		c.vel_vel = -z1e1 + z2e2;
	} else if (zeta < real_t(1.0) - epsilon) {
		// Under-damped.
		const real_t omega_zeta = omega * zeta;
		const real_t alpha = omega * Math::sqrt(real_t(1.0) - zeta * zeta);
		const real_t exp_term = Math::exp(-omega_zeta * t);
		const real_t cos_term = Math::cos(alpha * t);
		const real_t sin_term = Math::sin(alpha * t);
		const real_t inv_alpha = real_t(1.0) / alpha;
		const real_t exp_sin = exp_term * sin_term;
		const real_t exp_cos = exp_term * cos_term;
		const real_t exp_omega_zeta_sin_over_alpha = exp_term * omega_zeta * sin_term * inv_alpha;
		c.pos_pos = exp_cos + exp_omega_zeta_sin_over_alpha;
		c.pos_vel = exp_sin * inv_alpha;
		c.vel_pos = -exp_sin * alpha - omega_zeta * exp_omega_zeta_sin_over_alpha;
		c.vel_vel = exp_cos - exp_omega_zeta_sin_over_alpha;
	} else {
		// Critically damped.
		const real_t exp_term = Math::exp(-omega * t);
		const real_t time_exp = t * exp_term;
		const real_t time_exp_freq = time_exp * omega;
		c.pos_pos = time_exp_freq + exp_term;
		c.pos_vel = time_exp;
		c.vel_pos = -omega * time_exp_freq;
		c.vel_vel = -time_exp_freq + exp_term;
	}
	return c;
}

template <typename T>
static T _spring_apply(const SpringDamper::Coefficients &p_c, const T &p_current, const T &p_target, T &r_velocity) {
	const T offset = p_current - p_target;
	const T new_offset = offset * p_c.pos_pos + r_velocity * p_c.pos_vel;
	r_velocity = offset * p_c.vel_pos + r_velocity * p_c.vel_vel;
	return p_target + new_offset;
}

template <typename T>
static Variant _spring_step(const SpringDamper::Coefficients &p_c, const Variant &p_current, const Variant &p_target, Variant &r_velocity) {
	T velocity = r_velocity.get_type() == GetTypeInfo<T>::VARIANT_TYPE ? T(r_velocity) : T();
	const T result = _spring_apply<T>(p_c, T(p_current), T(p_target), velocity);
	r_velocity = velocity;
	return result;
}

Variant SpringDamper::step(const Variant &p_current, const Variant &p_target, real_t p_delta) {
	const Coefficients c = compute(frequency, damping_ratio, p_delta);
	switch (p_current.get_type()) {
		case Variant::INT:
		case Variant::FLOAT: {
			real_t vel = (velocity.get_type() == Variant::FLOAT || velocity.get_type() == Variant::INT) ? real_t(velocity) : real_t(0.0);
			const real_t result = _spring_apply<real_t>(c, real_t(p_current), real_t(p_target), vel);
			velocity = vel;
			return result;
		}
		case Variant::VECTOR2:
			return _spring_step<Vector2>(c, p_current, p_target, velocity);
		case Variant::VECTOR3:
			return _spring_step<Vector3>(c, p_current, p_target, velocity);
		case Variant::VECTOR4:
			return _spring_step<Vector4>(c, p_current, p_target, velocity);
		default:
			ERR_FAIL_V_MSG(p_current, "SpringDamper.step() supports float, Vector2, Vector3 and Vector4.");
	}
}

void SpringDamper::add_impulse(const Variant &p_impulse) {
	if (velocity.get_type() == Variant::NIL) {
		velocity = p_impulse;
		return;
	}
	bool valid = false;
	Variant result;
	Variant::evaluate(Variant::OP_ADD, velocity, p_impulse, result, valid);
	ERR_FAIL_COND_MSG(!valid, "SpringDamper.add_impulse(): impulse type does not match the current velocity.");
	velocity = result;
}

void SpringDamper::reset() {
	velocity = Variant();
}

void SpringDamper::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_frequency", "frequency"), &SpringDamper::set_frequency);
	ClassDB::bind_method(D_METHOD("get_frequency"), &SpringDamper::get_frequency);
	ClassDB::bind_method(D_METHOD("set_damping_ratio", "damping_ratio"), &SpringDamper::set_damping_ratio);
	ClassDB::bind_method(D_METHOD("get_damping_ratio"), &SpringDamper::get_damping_ratio);
	ClassDB::bind_method(D_METHOD("set_velocity", "velocity"), &SpringDamper::set_velocity);
	ClassDB::bind_method(D_METHOD("get_velocity"), &SpringDamper::get_velocity);

	ClassDB::bind_method(D_METHOD("step", "current", "target", "delta"), &SpringDamper::step);
	ClassDB::bind_method(D_METHOD("add_impulse", "impulse"), &SpringDamper::add_impulse);
	ClassDB::bind_method(D_METHOD("reset"), &SpringDamper::reset);

	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "frequency", PROPERTY_HINT_RANGE, "0,30,0.01,or_greater,suffix:Hz"), "set_frequency", "get_frequency");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "damping_ratio", PROPERTY_HINT_RANGE, "0,4,0.01,or_greater"), "set_damping_ratio", "get_damping_ratio");
	ADD_PROPERTY(PropertyInfo(Variant::NIL, "velocity", PROPERTY_HINT_NONE, "", PROPERTY_USAGE_NIL_IS_VARIANT | PROPERTY_USAGE_EDITOR), "set_velocity", "get_velocity");
}

real_t PIDController::step(real_t p_current, real_t p_target, real_t p_delta) {
	const real_t error = p_target - p_current;
	real_t derivative = 0.0;
	if (p_delta > real_t(0.0)) {
		integral += error * p_delta;
		if (integral_limit > real_t(0.0)) {
			integral = CLAMP(integral, -integral_limit, integral_limit);
		}
		if (has_previous) {
			derivative = -(p_current - previous_measurement) / p_delta;
		}
	}
	previous_measurement = p_current;
	has_previous = true;

	real_t output = proportional_gain * error + integral_gain * integral + derivative_gain * derivative;
	if (output_limit > real_t(0.0)) {
		output = CLAMP(output, -output_limit, output_limit);
	}
	return output;
}

void PIDController::reset() {
	integral = 0.0;
	previous_measurement = 0.0;
	has_previous = false;
}

void PIDController::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_proportional_gain", "gain"), &PIDController::set_proportional_gain);
	ClassDB::bind_method(D_METHOD("get_proportional_gain"), &PIDController::get_proportional_gain);
	ClassDB::bind_method(D_METHOD("set_integral_gain", "gain"), &PIDController::set_integral_gain);
	ClassDB::bind_method(D_METHOD("get_integral_gain"), &PIDController::get_integral_gain);
	ClassDB::bind_method(D_METHOD("set_derivative_gain", "gain"), &PIDController::set_derivative_gain);
	ClassDB::bind_method(D_METHOD("get_derivative_gain"), &PIDController::get_derivative_gain);
	ClassDB::bind_method(D_METHOD("set_integral_limit", "limit"), &PIDController::set_integral_limit);
	ClassDB::bind_method(D_METHOD("get_integral_limit"), &PIDController::get_integral_limit);
	ClassDB::bind_method(D_METHOD("set_output_limit", "limit"), &PIDController::set_output_limit);
	ClassDB::bind_method(D_METHOD("get_output_limit"), &PIDController::get_output_limit);
	ClassDB::bind_method(D_METHOD("get_integral"), &PIDController::get_integral);

	ClassDB::bind_method(D_METHOD("step", "current", "target", "delta"), &PIDController::step);
	ClassDB::bind_method(D_METHOD("reset"), &PIDController::reset);

	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "proportional_gain"), "set_proportional_gain", "get_proportional_gain");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "integral_gain"), "set_integral_gain", "get_integral_gain");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "derivative_gain"), "set_derivative_gain", "get_derivative_gain");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "integral_limit", PROPERTY_HINT_RANGE, "0,1000,0.01,or_greater"), "set_integral_limit", "get_integral_limit");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "output_limit", PROPERTY_HINT_RANGE, "0,1000,0.01,or_greater"), "set_output_limit", "get_output_limit");
}
