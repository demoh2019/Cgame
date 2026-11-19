/**************************************************************************/
/*  drivetrain_model.h                                             */
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

#include "core/math/math_funcs.h"
#include "core/templates/local_vector.h"
#include "core/variant/variant.h"

// Engine, gearbox and final drive of a road vehicle, without any scene or physics code so it can be
// unit tested. The model turns the driver's throttle and the speed of the driven wheels into a
// torque at those wheels.
namespace DrivetrainModel {

struct Config {
	real_t idle_rpm = 900.0;
	real_t max_rpm = 6500.0;
	// Engine speed used to evaluate the torque while the clutch slips at a standstill.
	real_t launch_rpm = 2500.0;
	real_t peak_torque = 300.0; // N*m at the best point of the curve.
	// Torque multiplier sampled evenly from 0 to max_rpm. Empty uses a built-in curve.
	LocalVector<real_t> torque_curve;
	LocalVector<real_t> gear_ratios = { 3.6, 2.2, 1.5, 1.1, 0.85 };
	real_t reverse_ratio = 3.2;
	real_t final_drive = 3.7;
	real_t efficiency = 0.9;
	real_t shift_up_rpm = 5500.0;
	real_t shift_down_rpm = 2200.0;
	real_t shift_time = 0.25; // The clutch is open and no torque flows while shifting.
	// After an automatic shift the gearbox waits this long before shifting again, so a bouncing wheel
	// or a brief rpm spike cannot make it hunt between gears.
	real_t shift_hold = 1.0;
	// Torque at max_rpm that slows the car when the throttle is released (scaled by rpm).
	real_t engine_brake_torque = 40.0;
};

struct State {
	int gear = 1; // 1..n forward, 0 neutral, -1 reverse.
	real_t engine_rpm = 900.0;
	real_t shift_timer = 0.0;
	real_t hold_timer = 0.0;
};

struct Output {
	real_t engine_torque = 0.0; // N*m at the crankshaft.
	real_t wheel_torque = 0.0; // N*m, summed over the driven wheels; negative drives backward.
	real_t engine_rpm = 0.0;
	bool shifted = false;
};

// Torque multiplier at the given fraction (0..1) of max_rpm.
real_t torque_multiplier(const Config &p_config, real_t p_rpm_fraction);
// Total ratio between the engine and the driven wheels in a gear (0 in neutral).
real_t total_ratio(const Config &p_config, int p_gear);

// Advances the model by `p_delta` seconds. `p_wheel_rpm` is the signed average speed of the driven
// wheels (positive when the car moves forward). `p_throttle` is 0..1. `p_automatic` lets the
// gearbox choose forward gears. `p_reverse` selects reverse instead of the forward gears.
Output step(const Config &p_config, State &r_state, real_t p_throttle, real_t p_wheel_rpm, bool p_automatic, bool p_reverse, real_t p_delta);

} // namespace DrivetrainModel
