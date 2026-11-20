/**************************************************************************/
/*  spring_damper.h                                                       */
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

#include "core/object/ref_counted.h"
#include "core/variant/variant.h"

// Damped harmonic oscillator driven toward a target (UE SpringDamper /
// Ryan Juckett closed-form). Unlike SmoothDamp it can overshoot and wobble,
// which suits recoil, UI bounce, hanging props and procedural camera sway.
class SpringDamper : public RefCounted {
	GDCLASS(SpringDamper, RefCounted);

	real_t frequency = 4.0; // Hz.
	real_t damping_ratio = 0.5; // 1 = critical, <1 bouncy, >1 sluggish.
	Variant velocity;

protected:
	static void _bind_methods();

public:
	struct Coefficients {
		real_t pos_pos = 1.0;
		real_t pos_vel = 0.0;
		real_t vel_pos = 0.0;
		real_t vel_vel = 1.0;
	};

	// Exact over any delta, so behaviour is frame-rate independent.
	static Coefficients compute(real_t p_frequency, real_t p_damping_ratio, real_t p_delta);

	void set_frequency(real_t p_frequency) { frequency = MAX(p_frequency, real_t(0.0)); }
	real_t get_frequency() const { return frequency; }

	void set_damping_ratio(real_t p_ratio) { damping_ratio = MAX(p_ratio, real_t(0.0)); }
	real_t get_damping_ratio() const { return damping_ratio; }

	void set_velocity(const Variant &p_velocity) { velocity = p_velocity; }
	Variant get_velocity() const { return velocity; }

	Variant step(const Variant &p_current, const Variant &p_target, real_t p_delta);
	void add_impulse(const Variant &p_impulse);
	void reset();
};

// Proportional-integral-derivative controller (common in Unity/UE gameplay
// code for steering, hover, turret aim and thermostat-like systems).
class PIDController : public RefCounted {
	GDCLASS(PIDController, RefCounted);

	real_t proportional_gain = 1.0;
	real_t integral_gain = 0.0;
	real_t derivative_gain = 0.0;
	real_t integral_limit = 0.0; // 0 or less: unlimited (anti-windup clamp otherwise).
	real_t output_limit = 0.0; // 0 or less: unlimited.

	real_t integral = 0.0;
	real_t previous_measurement = 0.0;
	bool has_previous = false;

protected:
	static void _bind_methods();

public:
	void set_proportional_gain(real_t p_gain) { proportional_gain = p_gain; }
	real_t get_proportional_gain() const { return proportional_gain; }
	void set_integral_gain(real_t p_gain) { integral_gain = p_gain; }
	real_t get_integral_gain() const { return integral_gain; }
	void set_derivative_gain(real_t p_gain) { derivative_gain = p_gain; }
	real_t get_derivative_gain() const { return derivative_gain; }
	void set_integral_limit(real_t p_limit) { integral_limit = p_limit; }
	real_t get_integral_limit() const { return integral_limit; }
	void set_output_limit(real_t p_limit) { output_limit = p_limit; }
	real_t get_output_limit() const { return output_limit; }

	real_t get_integral() const { return integral; }

	// Derivative is taken on the measurement, so changing the target does not
	// produce a derivative kick.
	real_t step(real_t p_current, real_t p_target, real_t p_delta);
	void reset();
};
