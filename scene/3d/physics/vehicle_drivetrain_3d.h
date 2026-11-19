/**************************************************************************/
/*  vehicle_drivetrain_3d.h                                             */
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

#include "scene/3d/physics/drivetrain_model.h"
#include "scene/main/node.h"
#include "scene/resources/curve.h"

class VehicleBody3D;

// Engine, gearbox and final drive for a VehicleBody3D. Set `throttle` (and `reverse`) every frame;
// the node works out the engine speed from the driven wheels, picks gears if `automatic`, and sets
// the engine force of every traction wheel so the car accelerates as a real one does: strong in low
// gears, limited by the rev limiter in each gear, no drive during gear changes.
class VehicleDrivetrain3D : public Node {
	GDCLASS(VehicleDrivetrain3D, Node);

private:
	NodePath vehicle;
	DrivetrainModel::Config config;
	DrivetrainModel::State state;
	PackedFloat32Array gear_ratios;
	Ref<Curve> torque_curve;
	real_t throttle = 0.0;
	bool reverse = false;
	bool automatic = true;
	real_t last_wheel_torque = 0.0;
	real_t last_engine_torque = 0.0;

	VehicleBody3D *_get_vehicle() const;
	void _sync_config();

protected:
	void _notification(int p_what);
	static void _bind_methods();

public:
	// Computes one step for a given speed of the driven wheels; the node calls this every physics
	// frame and tests use it directly.
	DrivetrainModel::Output update(real_t p_wheel_rpm, real_t p_delta);

	void set_vehicle(const NodePath &p_vehicle) { vehicle = p_vehicle; }
	NodePath get_vehicle() const { return vehicle; }
	void set_throttle(real_t p_throttle) { throttle = CLAMP(p_throttle, real_t(0.0), real_t(1.0)); }
	real_t get_throttle() const { return throttle; }
	void set_reverse(bool p_reverse) { reverse = p_reverse; }
	bool is_reverse() const { return reverse; }
	void set_automatic(bool p_automatic) { automatic = p_automatic; }
	bool is_automatic() const { return automatic; }

	void set_idle_rpm(real_t p_rpm);
	real_t get_idle_rpm() const { return config.idle_rpm; }
	void set_max_rpm(real_t p_rpm);
	real_t get_max_rpm() const { return config.max_rpm; }
	void set_launch_rpm(real_t p_rpm);
	real_t get_launch_rpm() const { return config.launch_rpm; }
	void set_peak_torque(real_t p_torque);
	real_t get_peak_torque() const { return config.peak_torque; }
	void set_torque_curve(const Ref<Curve> &p_curve);
	Ref<Curve> get_torque_curve() const { return torque_curve; }
	void set_gear_ratios(const PackedFloat32Array &p_ratios);
	PackedFloat32Array get_gear_ratios() const { return gear_ratios; }
	void set_reverse_ratio(real_t p_ratio);
	real_t get_reverse_ratio() const { return config.reverse_ratio; }
	void set_final_drive(real_t p_ratio);
	real_t get_final_drive() const { return config.final_drive; }
	void set_efficiency(real_t p_efficiency);
	real_t get_efficiency() const { return config.efficiency; }
	void set_shift_up_rpm(real_t p_rpm);
	real_t get_shift_up_rpm() const { return config.shift_up_rpm; }
	void set_shift_down_rpm(real_t p_rpm);
	real_t get_shift_down_rpm() const { return config.shift_down_rpm; }
	void set_shift_time(real_t p_seconds);
	real_t get_shift_time() const { return config.shift_time; }
	void set_shift_hold(real_t p_seconds);
	real_t get_shift_hold() const { return config.shift_hold; }
	void set_engine_brake_torque(real_t p_torque);
	real_t get_engine_brake_torque() const { return config.engine_brake_torque; }

	int get_gear() const { return state.gear; }
	void set_gear(int p_gear);
	void shift_up();
	void shift_down();
	real_t get_engine_rpm() const { return state.engine_rpm; }
	bool is_shifting() const { return state.shift_timer > 0.0; }
	real_t get_wheel_torque() const { return last_wheel_torque; }
	real_t get_engine_torque() const { return last_engine_torque; }

	VehicleDrivetrain3D();
};
