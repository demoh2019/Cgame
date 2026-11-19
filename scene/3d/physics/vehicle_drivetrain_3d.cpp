/**************************************************************************/
/*  vehicle_drivetrain_3d.cpp                                             */
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

#include "vehicle_drivetrain_3d.h"

#include "core/config/engine.h"
#include "core/object/class_db.h"
#include "scene/3d/physics/vehicle_body_3d.h"

VehicleDrivetrain3D::VehicleDrivetrain3D() {
	gear_ratios.push_back(3.6);
	gear_ratios.push_back(2.2);
	gear_ratios.push_back(1.5);
	gear_ratios.push_back(1.1);
	gear_ratios.push_back(0.85);
	state.engine_rpm = config.idle_rpm;
}

VehicleBody3D *VehicleDrivetrain3D::_get_vehicle() const {
	if (!vehicle.is_empty()) {
		return Object::cast_to<VehicleBody3D>(get_node_or_null(vehicle));
	}
	return Object::cast_to<VehicleBody3D>(get_parent());
}

void VehicleDrivetrain3D::_sync_config() {
	config.gear_ratios.clear();
	for (const float ratio : gear_ratios) {
		config.gear_ratios.push_back(MAX(real_t(ratio), real_t(0.01)));
	}
	config.torque_curve.clear();
	if (torque_curve.is_valid() && torque_curve->get_point_count() >= 2) {
		const int samples = 17;
		for (int i = 0; i < samples; i++) {
			config.torque_curve.push_back(MAX(torque_curve->sample_baked(real_t(i) / real_t(samples - 1)), real_t(0.0)));
		}
	}
}

DrivetrainModel::Output VehicleDrivetrain3D::update(real_t p_wheel_rpm, real_t p_delta) {
	_sync_config();
	const DrivetrainModel::Output output = DrivetrainModel::step(config, state, throttle, p_wheel_rpm, automatic, reverse, p_delta);
	last_wheel_torque = output.wheel_torque;
	last_engine_torque = output.engine_torque;
	if (output.shifted) {
		emit_signal(SNAME("gear_changed"), state.gear);
	}
	return output;
}

void VehicleDrivetrain3D::_notification(int p_what) {
	switch (p_what) {
		case NOTIFICATION_ENTER_TREE: {
			set_physics_process_internal(!Engine::get_singleton()->is_editor_hint());
		} break;
		case NOTIFICATION_INTERNAL_PHYSICS_PROCESS: {
			VehicleBody3D *body = _get_vehicle();
			if (!body) {
				return;
			}
			LocalVector<VehicleWheel3D *> wheels;
			LocalVector<VehicleWheel3D *> grounded;
			real_t radius_sum = 0.0;
			for (int i = 0; i < body->get_child_count(); i++) {
				VehicleWheel3D *wheel = Object::cast_to<VehicleWheel3D>(body->get_child(i));
				if (wheel && wheel->is_used_as_traction()) {
					wheels.push_back(wheel);
					radius_sum += wheel->get_radius();
					if (wheel->is_in_contact()) {
						grounded.push_back(wheel);
					}
				}
			}
			if (wheels.is_empty()) {
				return;
			}
			// The engine speed follows the ground speed along the direction of travel of the car:
			// VehicleWheel3D.get_rpm() depends on the wheel model and drops when a wheel hops, so it is
			// not a reliable measure. (MODEL_FRONT of a VehicleBody3D is +Z.)
			const real_t forward_speed = body->get_linear_velocity().dot(body->get_global_transform().basis.get_column(2));
			const real_t average_radius = MAX(radius_sum / real_t(wheels.size()), real_t(0.01));
			const real_t wheel_rpm = forward_speed / average_radius * real_t(60.0) / real_t(Math::TAU);
			const DrivetrainModel::Output output = update(wheel_rpm, real_t(get_physics_process_delta_time()));
			if (grounded.is_empty()) {
				for (VehicleWheel3D *wheel : wheels) {
					wheel->set_engine_force(0.0);
				}
				return;
			}
			// An open differential splits the torque evenly between the driven wheels that have grip.
			const real_t torque_per_wheel = output.wheel_torque / real_t(grounded.size());
			for (VehicleWheel3D *wheel : wheels) {
				wheel->set_engine_force(wheel->is_in_contact() ? torque_per_wheel / MAX(wheel->get_radius(), real_t(0.01)) : real_t(0.0));
			}
		} break;
	}
}

void VehicleDrivetrain3D::set_idle_rpm(real_t p_rpm) {
	config.idle_rpm = MAX(p_rpm, real_t(1.0));
}
void VehicleDrivetrain3D::set_max_rpm(real_t p_rpm) {
	config.max_rpm = MAX(p_rpm, config.idle_rpm + real_t(1.0));
}
void VehicleDrivetrain3D::set_launch_rpm(real_t p_rpm) {
	config.launch_rpm = MAX(p_rpm, real_t(0.0));
}
void VehicleDrivetrain3D::set_peak_torque(real_t p_torque) {
	config.peak_torque = MAX(p_torque, real_t(0.0));
}
void VehicleDrivetrain3D::set_torque_curve(const Ref<Curve> &p_curve) {
	torque_curve = p_curve;
}
void VehicleDrivetrain3D::set_gear_ratios(const PackedFloat32Array &p_ratios) {
	gear_ratios = p_ratios;
	state.gear = CLAMP(state.gear, -1, int(gear_ratios.size()));
}
void VehicleDrivetrain3D::set_reverse_ratio(real_t p_ratio) {
	config.reverse_ratio = MAX(p_ratio, real_t(0.01));
}
void VehicleDrivetrain3D::set_final_drive(real_t p_ratio) {
	config.final_drive = MAX(p_ratio, real_t(0.01));
}
void VehicleDrivetrain3D::set_efficiency(real_t p_efficiency) {
	config.efficiency = CLAMP(p_efficiency, real_t(0.0), real_t(1.0));
}
void VehicleDrivetrain3D::set_shift_up_rpm(real_t p_rpm) {
	config.shift_up_rpm = MAX(p_rpm, real_t(1.0));
}
void VehicleDrivetrain3D::set_shift_down_rpm(real_t p_rpm) {
	config.shift_down_rpm = MAX(p_rpm, real_t(1.0));
}
void VehicleDrivetrain3D::set_shift_time(real_t p_seconds) {
	config.shift_time = MAX(p_seconds, real_t(0.0));
}
void VehicleDrivetrain3D::set_shift_hold(real_t p_seconds) {
	config.shift_hold = MAX(p_seconds, real_t(0.0));
}
void VehicleDrivetrain3D::set_engine_brake_torque(real_t p_torque) {
	config.engine_brake_torque = MAX(p_torque, real_t(0.0));
}

void VehicleDrivetrain3D::set_gear(int p_gear) {
	const int gear = CLAMP(p_gear, -1, int(gear_ratios.size()));
	if (gear == state.gear) {
		return;
	}
	state.gear = gear;
	state.shift_timer = config.shift_time;
	emit_signal(SNAME("gear_changed"), state.gear);
}

void VehicleDrivetrain3D::shift_up() {
	if (state.gear < int(gear_ratios.size())) {
		set_gear(state.gear == -1 ? 0 : state.gear + 1);
	}
}

void VehicleDrivetrain3D::shift_down() {
	if (state.gear > -1) {
		set_gear(state.gear - 1);
	}
}

void VehicleDrivetrain3D::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_vehicle", "vehicle"), &VehicleDrivetrain3D::set_vehicle);
	ClassDB::bind_method(D_METHOD("get_vehicle"), &VehicleDrivetrain3D::get_vehicle);
	ClassDB::bind_method(D_METHOD("set_throttle", "throttle"), &VehicleDrivetrain3D::set_throttle);
	ClassDB::bind_method(D_METHOD("get_throttle"), &VehicleDrivetrain3D::get_throttle);
	ClassDB::bind_method(D_METHOD("set_reverse", "reverse"), &VehicleDrivetrain3D::set_reverse);
	ClassDB::bind_method(D_METHOD("is_reverse"), &VehicleDrivetrain3D::is_reverse);
	ClassDB::bind_method(D_METHOD("set_automatic", "automatic"), &VehicleDrivetrain3D::set_automatic);
	ClassDB::bind_method(D_METHOD("is_automatic"), &VehicleDrivetrain3D::is_automatic);
	ClassDB::bind_method(D_METHOD("set_idle_rpm", "rpm"), &VehicleDrivetrain3D::set_idle_rpm);
	ClassDB::bind_method(D_METHOD("get_idle_rpm"), &VehicleDrivetrain3D::get_idle_rpm);
	ClassDB::bind_method(D_METHOD("set_max_rpm", "rpm"), &VehicleDrivetrain3D::set_max_rpm);
	ClassDB::bind_method(D_METHOD("get_max_rpm"), &VehicleDrivetrain3D::get_max_rpm);
	ClassDB::bind_method(D_METHOD("set_launch_rpm", "rpm"), &VehicleDrivetrain3D::set_launch_rpm);
	ClassDB::bind_method(D_METHOD("get_launch_rpm"), &VehicleDrivetrain3D::get_launch_rpm);
	ClassDB::bind_method(D_METHOD("set_peak_torque", "torque"), &VehicleDrivetrain3D::set_peak_torque);
	ClassDB::bind_method(D_METHOD("get_peak_torque"), &VehicleDrivetrain3D::get_peak_torque);
	ClassDB::bind_method(D_METHOD("set_torque_curve", "curve"), &VehicleDrivetrain3D::set_torque_curve);
	ClassDB::bind_method(D_METHOD("get_torque_curve"), &VehicleDrivetrain3D::get_torque_curve);
	ClassDB::bind_method(D_METHOD("set_gear_ratios", "ratios"), &VehicleDrivetrain3D::set_gear_ratios);
	ClassDB::bind_method(D_METHOD("get_gear_ratios"), &VehicleDrivetrain3D::get_gear_ratios);
	ClassDB::bind_method(D_METHOD("set_reverse_ratio", "ratio"), &VehicleDrivetrain3D::set_reverse_ratio);
	ClassDB::bind_method(D_METHOD("get_reverse_ratio"), &VehicleDrivetrain3D::get_reverse_ratio);
	ClassDB::bind_method(D_METHOD("set_final_drive", "ratio"), &VehicleDrivetrain3D::set_final_drive);
	ClassDB::bind_method(D_METHOD("get_final_drive"), &VehicleDrivetrain3D::get_final_drive);
	ClassDB::bind_method(D_METHOD("set_efficiency", "efficiency"), &VehicleDrivetrain3D::set_efficiency);
	ClassDB::bind_method(D_METHOD("get_efficiency"), &VehicleDrivetrain3D::get_efficiency);
	ClassDB::bind_method(D_METHOD("set_shift_up_rpm", "rpm"), &VehicleDrivetrain3D::set_shift_up_rpm);
	ClassDB::bind_method(D_METHOD("get_shift_up_rpm"), &VehicleDrivetrain3D::get_shift_up_rpm);
	ClassDB::bind_method(D_METHOD("set_shift_down_rpm", "rpm"), &VehicleDrivetrain3D::set_shift_down_rpm);
	ClassDB::bind_method(D_METHOD("get_shift_down_rpm"), &VehicleDrivetrain3D::get_shift_down_rpm);
	ClassDB::bind_method(D_METHOD("set_shift_time", "seconds"), &VehicleDrivetrain3D::set_shift_time);
	ClassDB::bind_method(D_METHOD("get_shift_time"), &VehicleDrivetrain3D::get_shift_time);
	ClassDB::bind_method(D_METHOD("set_shift_hold", "seconds"), &VehicleDrivetrain3D::set_shift_hold);
	ClassDB::bind_method(D_METHOD("get_shift_hold"), &VehicleDrivetrain3D::get_shift_hold);
	ClassDB::bind_method(D_METHOD("set_engine_brake_torque", "torque"), &VehicleDrivetrain3D::set_engine_brake_torque);
	ClassDB::bind_method(D_METHOD("get_engine_brake_torque"), &VehicleDrivetrain3D::get_engine_brake_torque);

	ClassDB::bind_method(D_METHOD("get_gear"), &VehicleDrivetrain3D::get_gear);
	ClassDB::bind_method(D_METHOD("set_gear", "gear"), &VehicleDrivetrain3D::set_gear);
	ClassDB::bind_method(D_METHOD("shift_up"), &VehicleDrivetrain3D::shift_up);
	ClassDB::bind_method(D_METHOD("shift_down"), &VehicleDrivetrain3D::shift_down);
	ClassDB::bind_method(D_METHOD("get_engine_rpm"), &VehicleDrivetrain3D::get_engine_rpm);
	ClassDB::bind_method(D_METHOD("is_shifting"), &VehicleDrivetrain3D::is_shifting);
	ClassDB::bind_method(D_METHOD("get_wheel_torque"), &VehicleDrivetrain3D::get_wheel_torque);
	ClassDB::bind_method(D_METHOD("get_engine_torque"), &VehicleDrivetrain3D::get_engine_torque);

	ADD_PROPERTY(PropertyInfo(Variant::NODE_PATH, "vehicle", PROPERTY_HINT_NODE_PATH_VALID_TYPES, "VehicleBody3D"), "set_vehicle", "get_vehicle");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "throttle", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_throttle", "get_throttle");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "reverse"), "set_reverse", "is_reverse");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "automatic"), "set_automatic", "is_automatic");
	ADD_GROUP("Engine", "");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "idle_rpm", PROPERTY_HINT_RANGE, "100,5000,10,or_greater,suffix:rpm"), "set_idle_rpm", "get_idle_rpm");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_rpm", PROPERTY_HINT_RANGE, "1000,20000,10,or_greater,suffix:rpm"), "set_max_rpm", "get_max_rpm");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "launch_rpm", PROPERTY_HINT_RANGE, "0,10000,10,or_greater,suffix:rpm"), "set_launch_rpm", "get_launch_rpm");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "peak_torque", PROPERTY_HINT_RANGE, U"0,5000,1,or_greater,suffix:N\u22C5m"), "set_peak_torque", "get_peak_torque");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "torque_curve", PROPERTY_HINT_RESOURCE_TYPE, "Curve"), "set_torque_curve", "get_torque_curve");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "engine_brake_torque", PROPERTY_HINT_RANGE, U"0,1000,0.1,or_greater,suffix:N\u22C5m"), "set_engine_brake_torque", "get_engine_brake_torque");
	ADD_GROUP("Transmission", "");
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_FLOAT32_ARRAY, "gear_ratios"), "set_gear_ratios", "get_gear_ratios");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "reverse_ratio", PROPERTY_HINT_RANGE, "0.1,10,0.01,or_greater"), "set_reverse_ratio", "get_reverse_ratio");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "final_drive", PROPERTY_HINT_RANGE, "0.1,10,0.01,or_greater"), "set_final_drive", "get_final_drive");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "efficiency", PROPERTY_HINT_RANGE, "0,1,0.01"), "set_efficiency", "get_efficiency");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "shift_up_rpm", PROPERTY_HINT_RANGE, "100,20000,10,or_greater,suffix:rpm"), "set_shift_up_rpm", "get_shift_up_rpm");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "shift_down_rpm", PROPERTY_HINT_RANGE, "100,20000,10,or_greater,suffix:rpm"), "set_shift_down_rpm", "get_shift_down_rpm");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "shift_time", PROPERTY_HINT_RANGE, "0,2,0.01,or_greater,suffix:s"), "set_shift_time", "get_shift_time");

	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "shift_hold", PROPERTY_HINT_RANGE, "0,10,0.01,or_greater,suffix:s"), "set_shift_hold", "get_shift_hold");

	ADD_SIGNAL(MethodInfo("gear_changed", PropertyInfo(Variant::INT, "gear")));
}
