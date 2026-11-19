/**************************************************************************/
/*  drivetrain_model.cpp                                             */
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

#include "drivetrain_model.h"

namespace DrivetrainModel {

real_t torque_multiplier(const Config &p_config, real_t p_rpm_fraction) {
	const real_t f = CLAMP(p_rpm_fraction, real_t(0.0), real_t(1.0));
	if (p_config.torque_curve.size() >= 2) {
		const real_t position = f * real_t(p_config.torque_curve.size() - 1);
		const uint32_t index = MIN(uint32_t(position), uint32_t(p_config.torque_curve.size() - 2));
		return Math::lerp(p_config.torque_curve[index], p_config.torque_curve[index + 1], position - real_t(index));
	}
	// A flat-topped hump peaking in the middle of the range, never below 0.6.
	return real_t(0.6) + real_t(1.6) * f * (real_t(1.0) - f);
}

real_t total_ratio(const Config &p_config, int p_gear) {
	if (p_gear == 0) {
		return 0.0;
	}
	if (p_gear < 0) {
		return p_config.reverse_ratio * p_config.final_drive;
	}
	const int index = CLAMP(p_gear, 1, int(p_config.gear_ratios.size())) - 1;
	if (p_config.gear_ratios.is_empty()) {
		return 0.0;
	}
	return p_config.gear_ratios[index] * p_config.final_drive;
}

Output step(const Config &p_config, State &r_state, real_t p_throttle, real_t p_wheel_rpm, bool p_automatic, bool p_reverse, real_t p_delta) {
	Output out;
	const int gear_count = int(p_config.gear_ratios.size());
	const real_t throttle = CLAMP(p_throttle, real_t(0.0), real_t(1.0));
	const int previous_gear = r_state.gear;

	// Direction selection: reverse only when the car is (nearly) stopped, so a driver cannot slam it into reverse at speed.
	if (p_reverse) {
		if (r_state.gear > 0 && Math::abs(p_wheel_rpm) < real_t(30.0)) {
			r_state.gear = -1;
			r_state.shift_timer = p_config.shift_time;
		}
	} else if (r_state.gear < 0 && Math::abs(p_wheel_rpm) < real_t(30.0)) {
		r_state.gear = 1;
		r_state.shift_timer = p_config.shift_time;
	}

	if (r_state.shift_timer > 0.0) {
		r_state.shift_timer = MAX(r_state.shift_timer - p_delta, real_t(0.0));
	}
	if (r_state.hold_timer > 0.0) {
		r_state.hold_timer = MAX(r_state.hold_timer - p_delta, real_t(0.0));
	}

	// Engine speed follows the wheels through the gear, never dropping below idle.
	real_t ratio = total_ratio(p_config, r_state.gear);
	const real_t wheel_speed = Math::abs(p_wheel_rpm);
	real_t rpm = CLAMP(wheel_speed * ratio, p_config.idle_rpm, p_config.max_rpm * real_t(1.05));

	if (p_automatic && r_state.gear > 0 && r_state.shift_timer <= 0.0 && r_state.hold_timer <= 0.0 && gear_count > 0) {
		if (rpm >= p_config.shift_up_rpm && r_state.gear < gear_count) {
			r_state.gear++;
			r_state.shift_timer = p_config.shift_time;
			r_state.hold_timer = p_config.shift_hold;
		} else if (r_state.gear > 1) {
			// Would the next lower gear still stay below the upshift point? Then it is safe to downshift.
			const real_t lower_rpm = wheel_speed * total_ratio(p_config, r_state.gear - 1);
			if (rpm <= p_config.shift_down_rpm && lower_rpm < p_config.shift_up_rpm * real_t(0.9)) {
				r_state.gear--;
				r_state.shift_timer = p_config.shift_time;
				r_state.hold_timer = p_config.shift_hold;
			}
		}
		ratio = total_ratio(p_config, r_state.gear);
		rpm = CLAMP(wheel_speed * ratio, p_config.idle_rpm, p_config.max_rpm * real_t(1.05));
	}
	out.shifted = r_state.gear != previous_gear;
	r_state.engine_rpm = rpm;
	out.engine_rpm = rpm;

	if (ratio == 0.0 || r_state.shift_timer > 0.0) {
		return out; // Neutral or mid-shift: the clutch is open.
	}
	const real_t direction = r_state.gear < 0 ? real_t(-1.0) : real_t(1.0);

	// A slipping clutch lets the engine run at launch_rpm while the car is slow.
	const real_t evaluation_rpm = MAX(rpm, p_config.launch_rpm);
	if (throttle > 0.0) {
		if (rpm >= p_config.max_rpm) {
			return out; // Rev limiter.
		}
		out.engine_torque = p_config.peak_torque * torque_multiplier(p_config, evaluation_rpm / p_config.max_rpm) * throttle;
	} else if (wheel_speed > real_t(1.0)) {
		// Engine braking pulls against the direction of travel (whichever way the car rolls),
		// stronger at higher rpm.
		out.engine_torque = -p_config.engine_brake_torque * (rpm / p_config.max_rpm);
		out.wheel_torque = out.engine_torque * ratio * p_config.efficiency * (p_wheel_rpm >= 0.0 ? real_t(1.0) : real_t(-1.0));
		return out;
	}
	out.wheel_torque = out.engine_torque * ratio * p_config.efficiency * direction;
	return out;
}

} // namespace DrivetrainModel
