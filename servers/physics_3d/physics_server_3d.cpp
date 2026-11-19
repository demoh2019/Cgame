/**************************************************************************/
/*  physics_server_3d.cpp                                                 */
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

#include "physics_server_3d.h"

#include "core/config/project_settings.h"
#include "core/object/class_db.h"
#include "core/object/ref_counted.h"

PhysicsServer3D *PhysicsServer3D::singleton = nullptr;

PhysicsServer3D *PhysicsServer3D::get_singleton() {
	return singleton;
}

void PhysicsServer3D::debug_set_enabled(bool p_enabled) {
#ifdef DEBUG_ENABLED
	if (debug_enabled == p_enabled) {
		return;
	}
	debug_enabled = p_enabled;
	emit_signal("_debug_changed");
#endif
}

bool PhysicsServer3D::debug_is_enabled() const {
#ifdef DEBUG_ENABLED
	return debug_enabled;
#else
	return false;
#endif
}

bool PhysicsServer3D::_body_test_motion(RID p_body, RequiredParam<PhysicsTestMotionParameters3D> p_parameters, const Ref<PhysicsTestMotionResult3D> &p_result) {
	EXTRACT_PARAM_OR_FAIL_V(parameters, p_parameters, false);

	PS3DT::MotionResult *result_ptr = nullptr;
	if (p_result.is_valid()) {
		result_ptr = p_result->get_result_ptr();
	}

	return body_test_motion(p_body, parameters->get_parameters(), result_ptr);
}

RID PhysicsServer3D::shape_create(PS3DE::ShapeType p_shape) {
	switch (p_shape) {
		case PS3DE::SHAPE_WORLD_BOUNDARY:
			return world_boundary_shape_create();
		case PS3DE::SHAPE_SEPARATION_RAY:
			return separation_ray_shape_create();
		case PS3DE::SHAPE_SPHERE:
			return sphere_shape_create();
		case PS3DE::SHAPE_BOX:
			return box_shape_create();
		case PS3DE::SHAPE_CAPSULE:
			return capsule_shape_create();
		case PS3DE::SHAPE_CYLINDER:
			return cylinder_shape_create();
		case PS3DE::SHAPE_CONVEX_POLYGON:
			return convex_polygon_shape_create();
		case PS3DE::SHAPE_CONCAVE_POLYGON:
			return concave_polygon_shape_create();
		case PS3DE::SHAPE_HEIGHTMAP:
			return heightmap_shape_create();
		case PS3DE::SHAPE_CUSTOM:
			return custom_shape_create();
		default:
			return RID();
	}
}

void PhysicsServer3D::_bind_methods() {
#ifndef _3D_DISABLED

	ClassDB::bind_method(D_METHOD("world_boundary_shape_create"), &PhysicsServer3D::world_boundary_shape_create);
	ClassDB::bind_method(D_METHOD("separation_ray_shape_create"), &PhysicsServer3D::separation_ray_shape_create);
	ClassDB::bind_method(D_METHOD("sphere_shape_create"), &PhysicsServer3D::sphere_shape_create);
	ClassDB::bind_method(D_METHOD("box_shape_create"), &PhysicsServer3D::box_shape_create);
	ClassDB::bind_method(D_METHOD("capsule_shape_create"), &PhysicsServer3D::capsule_shape_create);
	ClassDB::bind_method(D_METHOD("cylinder_shape_create"), &PhysicsServer3D::cylinder_shape_create);
	ClassDB::bind_method(D_METHOD("convex_polygon_shape_create"), &PhysicsServer3D::convex_polygon_shape_create);
	ClassDB::bind_method(D_METHOD("concave_polygon_shape_create"), &PhysicsServer3D::concave_polygon_shape_create);
	ClassDB::bind_method(D_METHOD("heightmap_shape_create"), &PhysicsServer3D::heightmap_shape_create);
	ClassDB::bind_method(D_METHOD("custom_shape_create"), &PhysicsServer3D::custom_shape_create);

	ClassDB::bind_method(D_METHOD("shape_set_data", "shape", "data"), &PhysicsServer3D::shape_set_data);
	ClassDB::bind_method(D_METHOD("shape_set_margin", "shape", "margin"), &PhysicsServer3D::shape_set_margin);

	ClassDB::bind_method(D_METHOD("shape_get_type", "shape"), &PhysicsServer3D::shape_get_type);
	ClassDB::bind_method(D_METHOD("shape_get_data", "shape"), &PhysicsServer3D::shape_get_data);
	ClassDB::bind_method(D_METHOD("shape_get_margin", "shape"), &PhysicsServer3D::shape_get_margin);

	ClassDB::bind_method(D_METHOD("space_create"), &PhysicsServer3D::space_create);
	ClassDB::bind_method(D_METHOD("space_set_active", "space", "active"), &PhysicsServer3D::space_set_active);
	ClassDB::bind_method(D_METHOD("space_is_active", "space"), &PhysicsServer3D::space_is_active);
	ClassDB::bind_method(D_METHOD("space_set_param", "space", "param", "value"), &PhysicsServer3D::space_set_param);
	ClassDB::bind_method(D_METHOD("space_get_param", "space", "param"), &PhysicsServer3D::space_get_param);
	ClassDB::bind_method(D_METHOD("space_get_direct_state", "space"), &PhysicsServer3D::space_get_direct_state);

	ClassDB::bind_method(D_METHOD("area_create"), &PhysicsServer3D::area_create);
	ClassDB::bind_method(D_METHOD("area_set_space", "area", "space"), &PhysicsServer3D::area_set_space);
	ClassDB::bind_method(D_METHOD("area_get_space", "area"), &PhysicsServer3D::area_get_space);

	ClassDB::bind_method(D_METHOD("area_add_shape", "area", "shape", "transform", "disabled"), &PhysicsServer3D::area_add_shape, DEFVAL(Transform3D()), DEFVAL(false));
	ClassDB::bind_method(D_METHOD("area_set_shape", "area", "shape_idx", "shape"), &PhysicsServer3D::area_set_shape);
	ClassDB::bind_method(D_METHOD("area_set_shape_transform", "area", "shape_idx", "transform"), &PhysicsServer3D::area_set_shape_transform);
	ClassDB::bind_method(D_METHOD("area_set_shape_disabled", "area", "shape_idx", "disabled"), &PhysicsServer3D::area_set_shape_disabled);

	ClassDB::bind_method(D_METHOD("area_get_shape_count", "area"), &PhysicsServer3D::area_get_shape_count);
	ClassDB::bind_method(D_METHOD("area_get_shape", "area", "shape_idx"), &PhysicsServer3D::area_get_shape);
	ClassDB::bind_method(D_METHOD("area_get_shape_transform", "area", "shape_idx"), &PhysicsServer3D::area_get_shape_transform);

	ClassDB::bind_method(D_METHOD("area_remove_shape", "area", "shape_idx"), &PhysicsServer3D::area_remove_shape);
	ClassDB::bind_method(D_METHOD("area_clear_shapes", "area"), &PhysicsServer3D::area_clear_shapes);

	ClassDB::bind_method(D_METHOD("area_set_collision_layer", "area", "layer"), &PhysicsServer3D::area_set_collision_layer);
	ClassDB::bind_method(D_METHOD("area_get_collision_layer", "area"), &PhysicsServer3D::area_get_collision_layer);

	ClassDB::bind_method(D_METHOD("area_set_collision_mask", "area", "mask"), &PhysicsServer3D::area_set_collision_mask);
	ClassDB::bind_method(D_METHOD("area_get_collision_mask", "area"), &PhysicsServer3D::area_get_collision_mask);

	ClassDB::bind_method(D_METHOD("area_set_param", "area", "param", "value"), &PhysicsServer3D::area_set_param);
	ClassDB::bind_method(D_METHOD("area_set_transform", "area", "transform"), &PhysicsServer3D::area_set_transform);

	ClassDB::bind_method(D_METHOD("area_get_param", "area", "param"), &PhysicsServer3D::area_get_param);
	ClassDB::bind_method(D_METHOD("area_get_transform", "area"), &PhysicsServer3D::area_get_transform);

	ClassDB::bind_method(D_METHOD("area_attach_object_instance_id", "area", "id"), &PhysicsServer3D::area_attach_object_instance_id);
	ClassDB::bind_method(D_METHOD("area_get_object_instance_id", "area"), &PhysicsServer3D::area_get_object_instance_id);

	ClassDB::bind_method(D_METHOD("area_set_monitor_callback", "area", "callback"), &PhysicsServer3D::area_set_monitor_callback);
	ClassDB::bind_method(D_METHOD("area_set_area_monitor_callback", "area", "callback"), &PhysicsServer3D::area_set_area_monitor_callback);
	ClassDB::bind_method(D_METHOD("area_set_monitorable", "area", "monitorable"), &PhysicsServer3D::area_set_monitorable);

	ClassDB::bind_method(D_METHOD("area_set_ray_pickable", "area", "enable"), &PhysicsServer3D::area_set_ray_pickable);

	ClassDB::bind_method(D_METHOD("body_create"), &PhysicsServer3D::body_create);

	ClassDB::bind_method(D_METHOD("body_set_space", "body", "space"), &PhysicsServer3D::body_set_space);
	ClassDB::bind_method(D_METHOD("body_get_space", "body"), &PhysicsServer3D::body_get_space);

	ClassDB::bind_method(D_METHOD("body_set_mode", "body", "mode"), &PhysicsServer3D::body_set_mode);
	ClassDB::bind_method(D_METHOD("body_get_mode", "body"), &PhysicsServer3D::body_get_mode);

	ClassDB::bind_method(D_METHOD("body_set_collision_layer", "body", "layer"), &PhysicsServer3D::body_set_collision_layer);
	ClassDB::bind_method(D_METHOD("body_get_collision_layer", "body"), &PhysicsServer3D::body_get_collision_layer);

	ClassDB::bind_method(D_METHOD("body_set_collision_mask", "body", "mask"), &PhysicsServer3D::body_set_collision_mask);
	ClassDB::bind_method(D_METHOD("body_get_collision_mask", "body"), &PhysicsServer3D::body_get_collision_mask);

	ClassDB::bind_method(D_METHOD("body_set_collision_priority", "body", "priority"), &PhysicsServer3D::body_set_collision_priority);
	ClassDB::bind_method(D_METHOD("body_get_collision_priority", "body"), &PhysicsServer3D::body_get_collision_priority);

	ClassDB::bind_method(D_METHOD("body_add_shape", "body", "shape", "transform", "disabled"), &PhysicsServer3D::body_add_shape, DEFVAL(Transform3D()), DEFVAL(false));
	ClassDB::bind_method(D_METHOD("body_set_shape", "body", "shape_idx", "shape"), &PhysicsServer3D::body_set_shape);
	ClassDB::bind_method(D_METHOD("body_set_shape_transform", "body", "shape_idx", "transform"), &PhysicsServer3D::body_set_shape_transform);
	ClassDB::bind_method(D_METHOD("body_set_shape_disabled", "body", "shape_idx", "disabled"), &PhysicsServer3D::body_set_shape_disabled);

	ClassDB::bind_method(D_METHOD("body_get_shape_count", "body"), &PhysicsServer3D::body_get_shape_count);
	ClassDB::bind_method(D_METHOD("body_get_shape", "body", "shape_idx"), &PhysicsServer3D::body_get_shape);
	ClassDB::bind_method(D_METHOD("body_get_shape_transform", "body", "shape_idx"), &PhysicsServer3D::body_get_shape_transform);

	ClassDB::bind_method(D_METHOD("body_remove_shape", "body", "shape_idx"), &PhysicsServer3D::body_remove_shape);
	ClassDB::bind_method(D_METHOD("body_clear_shapes", "body"), &PhysicsServer3D::body_clear_shapes);

	ClassDB::bind_method(D_METHOD("body_attach_object_instance_id", "body", "id"), &PhysicsServer3D::body_attach_object_instance_id);
	ClassDB::bind_method(D_METHOD("body_get_object_instance_id", "body"), &PhysicsServer3D::body_get_object_instance_id);

	ClassDB::bind_method(D_METHOD("body_set_enable_continuous_collision_detection", "body", "enable"), &PhysicsServer3D::body_set_enable_continuous_collision_detection);
	ClassDB::bind_method(D_METHOD("body_is_continuous_collision_detection_enabled", "body"), &PhysicsServer3D::body_is_continuous_collision_detection_enabled);

	ClassDB::bind_method(D_METHOD("body_set_param", "body", "param", "value"), &PhysicsServer3D::body_set_param);
	ClassDB::bind_method(D_METHOD("body_get_param", "body", "param"), &PhysicsServer3D::body_get_param);
	ClassDB::bind_method(D_METHOD("body_set_solver_priority", "body", "priority"), &PhysicsServer3D::body_set_solver_priority);
	ClassDB::bind_method(D_METHOD("body_get_solver_priority", "body"), &PhysicsServer3D::body_get_solver_priority);
	ClassDB::bind_method(D_METHOD("body_set_max_depenetration_velocity", "body", "value"), &PhysicsServer3D::body_set_max_depenetration_velocity);
	ClassDB::bind_method(D_METHOD("body_get_max_depenetration_velocity", "body"), &PhysicsServer3D::body_get_max_depenetration_velocity);
	ClassDB::bind_method(D_METHOD("body_set_max_angular_velocity", "body", "value"), &PhysicsServer3D::body_set_max_angular_velocity);
	ClassDB::bind_method(D_METHOD("body_get_max_angular_velocity", "body"), &PhysicsServer3D::body_get_max_angular_velocity);
	ClassDB::bind_method(D_METHOD("body_set_max_linear_velocity", "body", "value"), &PhysicsServer3D::body_set_max_linear_velocity);
	ClassDB::bind_method(D_METHOD("body_get_max_linear_velocity", "body"), &PhysicsServer3D::body_get_max_linear_velocity);

	ClassDB::bind_method(D_METHOD("body_reset_mass_properties", "body"), &PhysicsServer3D::body_reset_mass_properties);

	ClassDB::bind_method(D_METHOD("body_set_state", "body", "state", "value"), &PhysicsServer3D::body_set_state);
	ClassDB::bind_method(D_METHOD("body_get_state", "body", "state"), &PhysicsServer3D::body_get_state);

	ClassDB::bind_method(D_METHOD("body_apply_central_impulse", "body", "impulse"), &PhysicsServer3D::body_apply_central_impulse);
	ClassDB::bind_method(D_METHOD("body_apply_impulse", "body", "impulse", "position"), &PhysicsServer3D::body_apply_impulse, Vector3());
	ClassDB::bind_method(D_METHOD("body_apply_torque_impulse", "body", "impulse"), &PhysicsServer3D::body_apply_torque_impulse);

	ClassDB::bind_method(D_METHOD("body_apply_central_force", "body", "force"), &PhysicsServer3D::body_apply_central_force);
	ClassDB::bind_method(D_METHOD("body_apply_force", "body", "force", "position"), &PhysicsServer3D::body_apply_force, Vector3());
	ClassDB::bind_method(D_METHOD("body_apply_torque", "body", "torque"), &PhysicsServer3D::body_apply_torque);

	ClassDB::bind_method(D_METHOD("body_add_constant_central_force", "body", "force"), &PhysicsServer3D::body_add_constant_central_force);
	ClassDB::bind_method(D_METHOD("body_add_constant_force", "body", "force", "position"), &PhysicsServer3D::body_add_constant_force, Vector3());
	ClassDB::bind_method(D_METHOD("body_add_constant_torque", "body", "torque"), &PhysicsServer3D::body_add_constant_torque);

	ClassDB::bind_method(D_METHOD("body_set_constant_force", "body", "force"), &PhysicsServer3D::body_set_constant_force);
	ClassDB::bind_method(D_METHOD("body_get_constant_force", "body"), &PhysicsServer3D::body_get_constant_force);

	ClassDB::bind_method(D_METHOD("body_set_constant_torque", "body", "torque"), &PhysicsServer3D::body_set_constant_torque);
	ClassDB::bind_method(D_METHOD("body_get_constant_torque", "body"), &PhysicsServer3D::body_get_constant_torque);

	ClassDB::bind_method(D_METHOD("body_set_axis_velocity", "body", "axis_velocity"), &PhysicsServer3D::body_set_axis_velocity);

	ClassDB::bind_method(D_METHOD("body_set_axis_lock", "body", "axis", "lock"), &PhysicsServer3D::body_set_axis_lock);
	ClassDB::bind_method(D_METHOD("body_is_axis_locked", "body", "axis"), &PhysicsServer3D::body_is_axis_locked);

	ClassDB::bind_method(D_METHOD("body_add_collision_exception", "body", "excepted_body"), &PhysicsServer3D::body_add_collision_exception);
	ClassDB::bind_method(D_METHOD("body_remove_collision_exception", "body", "excepted_body"), &PhysicsServer3D::body_remove_collision_exception);

	ClassDB::bind_method(D_METHOD("body_set_max_contacts_reported", "body", "amount"), &PhysicsServer3D::body_set_max_contacts_reported);
	ClassDB::bind_method(D_METHOD("body_get_max_contacts_reported", "body"), &PhysicsServer3D::body_get_max_contacts_reported);

	ClassDB::bind_method(D_METHOD("body_set_omit_force_integration", "body", "enable"), &PhysicsServer3D::body_set_omit_force_integration);
	ClassDB::bind_method(D_METHOD("body_is_omitting_force_integration", "body"), &PhysicsServer3D::body_is_omitting_force_integration);

	ClassDB::bind_method(D_METHOD("body_set_state_sync_callback", "body", "callable"), &PhysicsServer3D::body_set_state_sync_callback);

	ClassDB::bind_method(D_METHOD("body_set_force_integration_callback", "body", "callable", "userdata"), &PhysicsServer3D::body_set_force_integration_callback, DEFVAL(Variant()));

	ClassDB::bind_method(D_METHOD("body_set_ray_pickable", "body", "enable"), &PhysicsServer3D::body_set_ray_pickable);

	ClassDB::bind_method(D_METHOD("body_test_motion", "body", "parameters", "result"), &PhysicsServer3D::_body_test_motion, DEFVAL(Variant()));

	ClassDB::bind_method(D_METHOD("body_get_direct_state", "body"), &PhysicsServer3D::body_get_direct_state);

	/* SOFT BODY API */

	ClassDB::bind_method(D_METHOD("soft_body_create"), &PhysicsServer3D::soft_body_create);

	ClassDB::bind_method(D_METHOD("soft_body_update_rendering_server", "body", "rendering_server_handler"), &PhysicsServer3D::soft_body_update_rendering_server);

	ClassDB::bind_method(D_METHOD("soft_body_set_space", "body", "space"), &PhysicsServer3D::soft_body_set_space);
	ClassDB::bind_method(D_METHOD("soft_body_get_space", "body"), &PhysicsServer3D::soft_body_get_space);

	ClassDB::bind_method(D_METHOD("soft_body_set_mesh", "body", "mesh"), &PhysicsServer3D::soft_body_set_mesh);
	ClassDB::bind_method(D_METHOD("soft_body_set_tetrahedral_indices", "body", "tetrahedral_indices"), &PhysicsServer3D::soft_body_set_tetrahedral_indices);
	ClassDB::bind_method(D_METHOD("soft_body_set_tetrahedral_interior_positions", "body", "positions"), &PhysicsServer3D::soft_body_set_tetrahedral_interior_positions);

	ClassDB::bind_method(D_METHOD("soft_body_get_bounds", "body"), &PhysicsServer3D::soft_body_get_bounds);

	ClassDB::bind_method(D_METHOD("soft_body_set_collision_layer", "body", "layer"), &PhysicsServer3D::soft_body_set_collision_layer);
	ClassDB::bind_method(D_METHOD("soft_body_get_collision_layer", "body"), &PhysicsServer3D::soft_body_get_collision_layer);

	ClassDB::bind_method(D_METHOD("soft_body_set_collision_mask", "body", "mask"), &PhysicsServer3D::soft_body_set_collision_mask);
	ClassDB::bind_method(D_METHOD("soft_body_get_collision_mask", "body"), &PhysicsServer3D::soft_body_get_collision_mask);

	ClassDB::bind_method(D_METHOD("soft_body_add_collision_exception", "body", "body_b"), &PhysicsServer3D::soft_body_add_collision_exception);
	ClassDB::bind_method(D_METHOD("soft_body_remove_collision_exception", "body", "body_b"), &PhysicsServer3D::soft_body_remove_collision_exception);

	ClassDB::bind_method(D_METHOD("soft_body_set_state", "body", "state", "variant"), &PhysicsServer3D::soft_body_set_state);
	ClassDB::bind_method(D_METHOD("soft_body_get_state", "body", "state"), &PhysicsServer3D::soft_body_get_state);

	ClassDB::bind_method(D_METHOD("soft_body_set_transform", "body", "transform"), &PhysicsServer3D::soft_body_set_transform);

	ClassDB::bind_method(D_METHOD("soft_body_set_ray_pickable", "body", "enable"), &PhysicsServer3D::soft_body_set_ray_pickable);

	ClassDB::bind_method(D_METHOD("soft_body_set_simulation_precision", "body", "simulation_precision"), &PhysicsServer3D::soft_body_set_simulation_precision);
	ClassDB::bind_method(D_METHOD("soft_body_get_simulation_precision", "body"), &PhysicsServer3D::soft_body_get_simulation_precision);

	ClassDB::bind_method(D_METHOD("soft_body_set_total_mass", "body", "total_mass"), &PhysicsServer3D::soft_body_set_total_mass);
	ClassDB::bind_method(D_METHOD("soft_body_get_total_mass", "body"), &PhysicsServer3D::soft_body_get_total_mass);

	ClassDB::bind_method(D_METHOD("soft_body_set_linear_stiffness", "body", "stiffness"), &PhysicsServer3D::soft_body_set_linear_stiffness);
	ClassDB::bind_method(D_METHOD("soft_body_get_linear_stiffness", "body"), &PhysicsServer3D::soft_body_get_linear_stiffness);

	ClassDB::bind_method(D_METHOD("soft_body_set_shrinking_factor", "body", "shrinking_factor"), &PhysicsServer3D::soft_body_set_shrinking_factor);
	ClassDB::bind_method(D_METHOD("soft_body_get_shrinking_factor", "body"), &PhysicsServer3D::soft_body_get_shrinking_factor);

	ClassDB::bind_method(D_METHOD("soft_body_set_pressure_coefficient", "body", "pressure_coefficient"), &PhysicsServer3D::soft_body_set_pressure_coefficient);
	ClassDB::bind_method(D_METHOD("soft_body_get_pressure_coefficient", "body"), &PhysicsServer3D::soft_body_get_pressure_coefficient);

	ClassDB::bind_method(D_METHOD("soft_body_set_damping_coefficient", "body", "damping_coefficient"), &PhysicsServer3D::soft_body_set_damping_coefficient);
	ClassDB::bind_method(D_METHOD("soft_body_get_damping_coefficient", "body"), &PhysicsServer3D::soft_body_get_damping_coefficient);

	ClassDB::bind_method(D_METHOD("soft_body_set_drag_coefficient", "body", "drag_coefficient"), &PhysicsServer3D::soft_body_set_drag_coefficient);
	ClassDB::bind_method(D_METHOD("soft_body_get_drag_coefficient", "body"), &PhysicsServer3D::soft_body_get_drag_coefficient);

	ClassDB::bind_method(D_METHOD("soft_body_move_point", "body", "point_index", "global_position"), &PhysicsServer3D::soft_body_move_point);
	ClassDB::bind_method(D_METHOD("soft_body_get_point_global_position", "body", "point_index"), &PhysicsServer3D::soft_body_get_point_global_position);

	ClassDB::bind_method(D_METHOD("soft_body_remove_all_pinned_points", "body"), &PhysicsServer3D::soft_body_remove_all_pinned_points);

	ClassDB::bind_method(D_METHOD("soft_body_pin_point", "body", "point_index", "pin"), &PhysicsServer3D::soft_body_pin_point);

	ClassDB::bind_method(D_METHOD("soft_body_is_point_pinned", "body", "point_index"), &PhysicsServer3D::soft_body_is_point_pinned);

	ClassDB::bind_method(D_METHOD("soft_body_apply_point_impulse", "body", "point_index", "impulse"), &PhysicsServer3D::soft_body_apply_point_impulse);
	ClassDB::bind_method(D_METHOD("soft_body_apply_point_force", "body", "point_index", "force"), &PhysicsServer3D::soft_body_apply_point_force);
	ClassDB::bind_method(D_METHOD("soft_body_apply_central_impulse", "body", "impulse"), &PhysicsServer3D::soft_body_apply_central_impulse);
	ClassDB::bind_method(D_METHOD("soft_body_apply_central_force", "body", "force"), &PhysicsServer3D::soft_body_apply_central_force);

	/* JOINT API */

	ClassDB::bind_method(D_METHOD("joint_create"), &PhysicsServer3D::joint_create);
	ClassDB::bind_method(D_METHOD("joint_clear", "joint"), &PhysicsServer3D::joint_clear);

	BIND_ENUM_CONSTANT(PS3DE::JOINT_TYPE_PIN);
	BIND_ENUM_CONSTANT(PS3DE::JOINT_TYPE_HINGE);
	BIND_ENUM_CONSTANT(PS3DE::JOINT_TYPE_SLIDER);
	BIND_ENUM_CONSTANT(PS3DE::JOINT_TYPE_CONE_TWIST);
	BIND_ENUM_CONSTANT(PS3DE::JOINT_TYPE_6DOF);
	BIND_ENUM_CONSTANT(PS3DE::JOINT_TYPE_MAX);

	ClassDB::bind_method(D_METHOD("joint_make_pin", "joint", "body_A", "local_A", "body_B", "local_B"), &PhysicsServer3D::joint_make_pin);
	ClassDB::bind_method(D_METHOD("pin_joint_set_param", "joint", "param", "value"), &PhysicsServer3D::pin_joint_set_param);
	ClassDB::bind_method(D_METHOD("pin_joint_get_param", "joint", "param"), &PhysicsServer3D::pin_joint_get_param);

	ClassDB::bind_method(D_METHOD("pin_joint_set_local_a", "joint", "local_A"), &PhysicsServer3D::pin_joint_set_local_a);
	ClassDB::bind_method(D_METHOD("pin_joint_get_local_a", "joint"), &PhysicsServer3D::pin_joint_get_local_a);

	ClassDB::bind_method(D_METHOD("pin_joint_set_local_b", "joint", "local_B"), &PhysicsServer3D::pin_joint_set_local_b);
	ClassDB::bind_method(D_METHOD("pin_joint_get_local_b", "joint"), &PhysicsServer3D::pin_joint_get_local_b);

	BIND_ENUM_CONSTANT(PS3DE::PIN_JOINT_BIAS);
	BIND_ENUM_CONSTANT(PS3DE::PIN_JOINT_DAMPING);
	BIND_ENUM_CONSTANT(PS3DE::PIN_JOINT_IMPULSE_CLAMP);

	BIND_ENUM_CONSTANT(PS3DE::HINGE_JOINT_BIAS);
	BIND_ENUM_CONSTANT(PS3DE::HINGE_JOINT_LIMIT_UPPER);
	BIND_ENUM_CONSTANT(PS3DE::HINGE_JOINT_LIMIT_LOWER);
	BIND_ENUM_CONSTANT(PS3DE::HINGE_JOINT_LIMIT_BIAS);
	BIND_ENUM_CONSTANT(PS3DE::HINGE_JOINT_LIMIT_SOFTNESS);
	BIND_ENUM_CONSTANT(PS3DE::HINGE_JOINT_LIMIT_RELAXATION);
	BIND_ENUM_CONSTANT(PS3DE::HINGE_JOINT_MOTOR_TARGET_VELOCITY);
	BIND_ENUM_CONSTANT(PS3DE::HINGE_JOINT_MOTOR_MAX_IMPULSE);

	BIND_ENUM_CONSTANT(PS3DE::HINGE_JOINT_FLAG_USE_LIMIT);
	BIND_ENUM_CONSTANT(PS3DE::HINGE_JOINT_FLAG_ENABLE_MOTOR);

	ClassDB::bind_method(D_METHOD("joint_make_hinge", "joint", "body_A", "hinge_A", "body_B", "hinge_B"), &PhysicsServer3D::joint_make_hinge);

	ClassDB::bind_method(D_METHOD("hinge_joint_set_param", "joint", "param", "value"), &PhysicsServer3D::hinge_joint_set_param);
	ClassDB::bind_method(D_METHOD("hinge_joint_get_param", "joint", "param"), &PhysicsServer3D::hinge_joint_get_param);

	ClassDB::bind_method(D_METHOD("hinge_joint_set_flag", "joint", "flag", "enabled"), &PhysicsServer3D::hinge_joint_set_flag);
	ClassDB::bind_method(D_METHOD("hinge_joint_get_flag", "joint", "flag"), &PhysicsServer3D::hinge_joint_get_flag);

	ClassDB::bind_method(D_METHOD("joint_make_slider", "joint", "body_A", "local_ref_A", "body_B", "local_ref_B"), &PhysicsServer3D::joint_make_slider);

	ClassDB::bind_method(D_METHOD("slider_joint_set_param", "joint", "param", "value"), &PhysicsServer3D::slider_joint_set_param);
	ClassDB::bind_method(D_METHOD("slider_joint_get_param", "joint", "param"), &PhysicsServer3D::slider_joint_get_param);

	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_LINEAR_LIMIT_UPPER);
	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_LINEAR_LIMIT_LOWER);
	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_LINEAR_LIMIT_SOFTNESS);
	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_LINEAR_LIMIT_RESTITUTION);
	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_LINEAR_LIMIT_DAMPING);
	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_LINEAR_MOTION_SOFTNESS);
	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_LINEAR_MOTION_RESTITUTION);
	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_LINEAR_MOTION_DAMPING);
	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_LINEAR_ORTHOGONAL_SOFTNESS);
	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_LINEAR_ORTHOGONAL_RESTITUTION);
	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_LINEAR_ORTHOGONAL_DAMPING);

	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_ANGULAR_LIMIT_UPPER);
	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_ANGULAR_LIMIT_LOWER);
	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_ANGULAR_LIMIT_SOFTNESS);
	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_ANGULAR_LIMIT_RESTITUTION);
	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_ANGULAR_LIMIT_DAMPING);
	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_ANGULAR_MOTION_SOFTNESS);
	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_ANGULAR_MOTION_RESTITUTION);
	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_ANGULAR_MOTION_DAMPING);
	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_ANGULAR_ORTHOGONAL_SOFTNESS);
	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_ANGULAR_ORTHOGONAL_RESTITUTION);
	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_ANGULAR_ORTHOGONAL_DAMPING);
	BIND_ENUM_CONSTANT(PS3DE::SLIDER_JOINT_MAX);

	ClassDB::bind_method(D_METHOD("joint_make_cone_twist", "joint", "body_A", "local_ref_A", "body_B", "local_ref_B"), &PhysicsServer3D::joint_make_cone_twist);

	ClassDB::bind_method(D_METHOD("cone_twist_joint_set_param", "joint", "param", "value"), &PhysicsServer3D::cone_twist_joint_set_param);
	ClassDB::bind_method(D_METHOD("cone_twist_joint_get_param", "joint", "param"), &PhysicsServer3D::cone_twist_joint_get_param);

	BIND_ENUM_CONSTANT(PS3DE::CONE_TWIST_JOINT_SWING_SPAN);
	BIND_ENUM_CONSTANT(PS3DE::CONE_TWIST_JOINT_TWIST_SPAN);
	BIND_ENUM_CONSTANT(PS3DE::CONE_TWIST_JOINT_BIAS);
	BIND_ENUM_CONSTANT(PS3DE::CONE_TWIST_JOINT_SOFTNESS);
	BIND_ENUM_CONSTANT(PS3DE::CONE_TWIST_JOINT_RELAXATION);

	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_LINEAR_LOWER_LIMIT);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_LINEAR_UPPER_LIMIT);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_LINEAR_LIMIT_SOFTNESS);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_LINEAR_RESTITUTION);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_LINEAR_DAMPING);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_LINEAR_MOTOR_TARGET_VELOCITY);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_LINEAR_MOTOR_FORCE_LIMIT);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_LINEAR_SPRING_STIFFNESS);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_LINEAR_SPRING_DAMPING);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_LINEAR_SPRING_EQUILIBRIUM_POINT);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_ANGULAR_LOWER_LIMIT);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_ANGULAR_UPPER_LIMIT);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_ANGULAR_LIMIT_SOFTNESS);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_ANGULAR_DAMPING);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_ANGULAR_RESTITUTION);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_ANGULAR_FORCE_LIMIT);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_ANGULAR_ERP);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_ANGULAR_MOTOR_TARGET_VELOCITY);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_ANGULAR_MOTOR_FORCE_LIMIT);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_ANGULAR_SPRING_STIFFNESS);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_ANGULAR_SPRING_DAMPING);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_ANGULAR_SPRING_EQUILIBRIUM_POINT);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_LINEAR_DRIVE_FORCE_LIMIT);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_ANGULAR_DRIVE_TORQUE_LIMIT);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_MAX);

	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_FLAG_ENABLE_LINEAR_LIMIT);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_FLAG_ENABLE_ANGULAR_LIMIT);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_FLAG_ENABLE_ANGULAR_SPRING);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_FLAG_ENABLE_LINEAR_SPRING);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_FLAG_ENABLE_ANGULAR_MOTOR);
#ifndef DISABLE_DEPRECATED
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_FLAG_ENABLE_MOTOR);
#endif // DISABLE_DEPRECATED
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_FLAG_ENABLE_LINEAR_MOTOR);
	BIND_ENUM_CONSTANT(PS3DE::G6DOF_JOINT_FLAG_MAX);

	ClassDB::bind_method(D_METHOD("joint_get_type", "joint"), &PhysicsServer3D::joint_get_type);

	ClassDB::bind_method(D_METHOD("joint_set_solver_priority", "joint", "priority"), &PhysicsServer3D::joint_set_solver_priority);
	ClassDB::bind_method(D_METHOD("joint_get_solver_priority", "joint"), &PhysicsServer3D::joint_get_solver_priority);

	ClassDB::bind_method(D_METHOD("joint_disable_collisions_between_bodies", "joint", "disable"), &PhysicsServer3D::joint_disable_collisions_between_bodies);
	ClassDB::bind_method(D_METHOD("joint_set_break_force", "joint", "force"), &PhysicsServer3D::joint_set_break_force);
	ClassDB::bind_method(D_METHOD("joint_get_break_force", "joint"), &PhysicsServer3D::joint_get_break_force);
	ClassDB::bind_method(D_METHOD("joint_set_break_torque", "joint", "torque"), &PhysicsServer3D::joint_set_break_torque);
	ClassDB::bind_method(D_METHOD("joint_get_break_torque", "joint"), &PhysicsServer3D::joint_get_break_torque);
	ClassDB::bind_method(D_METHOD("joint_get_reaction_force", "joint"), &PhysicsServer3D::joint_get_reaction_force);
	ClassDB::bind_method(D_METHOD("joint_get_reaction_torque", "joint"), &PhysicsServer3D::joint_get_reaction_torque);
	ClassDB::bind_method(D_METHOD("joint_is_broken", "joint"), &PhysicsServer3D::joint_is_broken);
	ClassDB::bind_method(D_METHOD("joint_set_break_callback", "joint", "callable"), &PhysicsServer3D::joint_set_break_callback);
	ClassDB::bind_method(D_METHOD("joint_is_disabled_collisions_between_bodies", "joint"), &PhysicsServer3D::joint_is_disabled_collisions_between_bodies);

	ClassDB::bind_method(D_METHOD("joint_make_generic_6dof", "joint", "body_A", "local_ref_A", "body_B", "local_ref_B"), &PhysicsServer3D::joint_make_generic_6dof);

	ClassDB::bind_method(D_METHOD("generic_6dof_joint_set_param", "joint", "axis", "param", "value"), &PhysicsServer3D::generic_6dof_joint_set_param);
	ClassDB::bind_method(D_METHOD("generic_6dof_joint_get_param", "joint", "axis", "param"), &PhysicsServer3D::generic_6dof_joint_get_param);

	ClassDB::bind_method(D_METHOD("generic_6dof_joint_set_flag", "joint", "axis", "flag", "enable"), &PhysicsServer3D::generic_6dof_joint_set_flag);
	ClassDB::bind_method(D_METHOD("generic_6dof_joint_get_flag", "joint", "axis", "flag"), &PhysicsServer3D::generic_6dof_joint_get_flag);

	ClassDB::bind_method(D_METHOD("generic_6dof_joint_set_angular_target_rotation", "joint", "target_rotation"), &PhysicsServer3D::generic_6dof_joint_set_angular_target_rotation);
	ClassDB::bind_method(D_METHOD("generic_6dof_joint_get_angular_target_rotation", "joint"), &PhysicsServer3D::generic_6dof_joint_get_angular_target_rotation);

	ClassDB::bind_method(D_METHOD("free_rid", "rid"), &PhysicsServer3D::free_rid);

	ClassDB::bind_method(D_METHOD("set_active", "active"), &PhysicsServer3D::set_active);

	ClassDB::bind_method(D_METHOD("get_process_info", "process_info"), &PhysicsServer3D::get_process_info);

	BIND_ENUM_CONSTANT(PS3DE::SHAPE_WORLD_BOUNDARY);
	BIND_ENUM_CONSTANT(PS3DE::SHAPE_SEPARATION_RAY);
	BIND_ENUM_CONSTANT(PS3DE::SHAPE_SPHERE);
	BIND_ENUM_CONSTANT(PS3DE::SHAPE_BOX);
	BIND_ENUM_CONSTANT(PS3DE::SHAPE_CAPSULE);
	BIND_ENUM_CONSTANT(PS3DE::SHAPE_CYLINDER);
	BIND_ENUM_CONSTANT(PS3DE::SHAPE_CONVEX_POLYGON);
	BIND_ENUM_CONSTANT(PS3DE::SHAPE_CONCAVE_POLYGON);
	BIND_ENUM_CONSTANT(PS3DE::SHAPE_HEIGHTMAP);
	BIND_ENUM_CONSTANT(PS3DE::SHAPE_SOFT_BODY);
	BIND_ENUM_CONSTANT(PS3DE::SHAPE_CUSTOM);

	BIND_ENUM_CONSTANT(PS3DE::AREA_PARAM_GRAVITY_OVERRIDE_MODE);
	BIND_ENUM_CONSTANT(PS3DE::AREA_PARAM_GRAVITY);
	BIND_ENUM_CONSTANT(PS3DE::AREA_PARAM_GRAVITY_VECTOR);
	BIND_ENUM_CONSTANT(PS3DE::AREA_PARAM_GRAVITY_IS_POINT);
	BIND_ENUM_CONSTANT(PS3DE::AREA_PARAM_GRAVITY_POINT_UNIT_DISTANCE);
	BIND_ENUM_CONSTANT(PS3DE::AREA_PARAM_LINEAR_DAMP_OVERRIDE_MODE);
	BIND_ENUM_CONSTANT(PS3DE::AREA_PARAM_LINEAR_DAMP);
	BIND_ENUM_CONSTANT(PS3DE::AREA_PARAM_ANGULAR_DAMP_OVERRIDE_MODE);
	BIND_ENUM_CONSTANT(PS3DE::AREA_PARAM_ANGULAR_DAMP);
	BIND_ENUM_CONSTANT(PS3DE::AREA_PARAM_PRIORITY);
	BIND_ENUM_CONSTANT(PS3DE::AREA_PARAM_WIND_FORCE_MAGNITUDE);
	BIND_ENUM_CONSTANT(PS3DE::AREA_PARAM_WIND_SOURCE);
	BIND_ENUM_CONSTANT(PS3DE::AREA_PARAM_WIND_DIRECTION);
	BIND_ENUM_CONSTANT(PS3DE::AREA_PARAM_WIND_ATTENUATION_FACTOR);

	BIND_ENUM_CONSTANT(PS3DE::AREA_SPACE_OVERRIDE_DISABLED);
	BIND_ENUM_CONSTANT(PS3DE::AREA_SPACE_OVERRIDE_COMBINE);
	BIND_ENUM_CONSTANT(PS3DE::AREA_SPACE_OVERRIDE_COMBINE_REPLACE);
	BIND_ENUM_CONSTANT(PS3DE::AREA_SPACE_OVERRIDE_REPLACE);
	BIND_ENUM_CONSTANT(PS3DE::AREA_SPACE_OVERRIDE_REPLACE_COMBINE);

	BIND_ENUM_CONSTANT(PS3DE::BODY_MODE_STATIC);
	BIND_ENUM_CONSTANT(PS3DE::BODY_MODE_KINEMATIC);
	BIND_ENUM_CONSTANT(PS3DE::BODY_MODE_RIGID);
	BIND_ENUM_CONSTANT(PS3DE::BODY_MODE_RIGID_LINEAR);

	BIND_ENUM_CONSTANT(PS3DE::BODY_PARAM_BOUNCE);
	BIND_ENUM_CONSTANT(PS3DE::BODY_PARAM_FRICTION);
	BIND_ENUM_CONSTANT(PS3DE::BODY_PARAM_MASS);
	BIND_ENUM_CONSTANT(PS3DE::BODY_PARAM_INERTIA);
	BIND_ENUM_CONSTANT(PS3DE::BODY_PARAM_CENTER_OF_MASS);
	BIND_ENUM_CONSTANT(PS3DE::BODY_PARAM_GRAVITY_SCALE);
	BIND_ENUM_CONSTANT(PS3DE::BODY_PARAM_LINEAR_DAMP_MODE);
	BIND_ENUM_CONSTANT(PS3DE::BODY_PARAM_ANGULAR_DAMP_MODE);
	BIND_ENUM_CONSTANT(PS3DE::BODY_PARAM_LINEAR_DAMP);
	BIND_ENUM_CONSTANT(PS3DE::BODY_PARAM_ANGULAR_DAMP);
	BIND_ENUM_CONSTANT(PS3DE::BODY_PARAM_MAX);

	BIND_ENUM_CONSTANT(PS3DE::BODY_DAMP_MODE_COMBINE);
	BIND_ENUM_CONSTANT(PS3DE::BODY_DAMP_MODE_REPLACE);

	BIND_ENUM_CONSTANT(PS3DE::BODY_STATE_TRANSFORM);
	BIND_ENUM_CONSTANT(PS3DE::BODY_STATE_LINEAR_VELOCITY);
	BIND_ENUM_CONSTANT(PS3DE::BODY_STATE_ANGULAR_VELOCITY);
	BIND_ENUM_CONSTANT(PS3DE::BODY_STATE_SLEEPING);
	BIND_ENUM_CONSTANT(PS3DE::BODY_STATE_CAN_SLEEP);

	BIND_ENUM_CONSTANT(PS3DE::AREA_BODY_ADDED);
	BIND_ENUM_CONSTANT(PS3DE::AREA_BODY_REMOVED);

	BIND_ENUM_CONSTANT(PS3DE::INFO_ACTIVE_OBJECTS);
	BIND_ENUM_CONSTANT(PS3DE::INFO_COLLISION_PAIRS);
	BIND_ENUM_CONSTANT(PS3DE::INFO_ISLAND_COUNT);

	BIND_ENUM_CONSTANT(PS3DE::SPACE_PARAM_CONTACT_RECYCLE_RADIUS);
	BIND_ENUM_CONSTANT(PS3DE::SPACE_PARAM_CONTACT_MAX_SEPARATION);
	BIND_ENUM_CONSTANT(PS3DE::SPACE_PARAM_CONTACT_MAX_ALLOWED_PENETRATION);
	BIND_ENUM_CONSTANT(PS3DE::SPACE_PARAM_CONTACT_DEFAULT_BIAS);
	BIND_ENUM_CONSTANT(PS3DE::SPACE_PARAM_BODY_LINEAR_VELOCITY_SLEEP_THRESHOLD);
	BIND_ENUM_CONSTANT(PS3DE::SPACE_PARAM_BODY_ANGULAR_VELOCITY_SLEEP_THRESHOLD);
	BIND_ENUM_CONSTANT(PS3DE::SPACE_PARAM_BODY_TIME_TO_SLEEP);
	BIND_ENUM_CONSTANT(PS3DE::SPACE_PARAM_SOLVER_ITERATIONS);

	BIND_ENUM_CONSTANT(PS3DE::BODY_AXIS_LINEAR_X);
	BIND_ENUM_CONSTANT(PS3DE::BODY_AXIS_LINEAR_Y);
	BIND_ENUM_CONSTANT(PS3DE::BODY_AXIS_LINEAR_Z);
	BIND_ENUM_CONSTANT(PS3DE::BODY_AXIS_ANGULAR_X);
	BIND_ENUM_CONSTANT(PS3DE::BODY_AXIS_ANGULAR_Y);
	BIND_ENUM_CONSTANT(PS3DE::BODY_AXIS_ANGULAR_Z);
#endif

#ifdef DEBUG_ENABLED
	ADD_SIGNAL(MethodInfo("_debug_changed"));
#endif
}

PhysicsServer3D::PhysicsServer3D() {
	singleton = this;

	// World3D physics space
	GLOBAL_DEF_BASIC(PropertyInfo(Variant::FLOAT, "physics/3d/default_gravity", PROPERTY_HINT_RANGE, U"-32,32,0.001,or_less,or_greater,suffix:m/s\u00B2"), 9.8);
	GLOBAL_DEF_BASIC(PropertyInfo(Variant::VECTOR3, "physics/3d/default_gravity_vector", PROPERTY_HINT_RANGE, "-10,10,0.001,or_less,or_greater"), Vector3(0, -1, 0));
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/default_linear_damp", PROPERTY_HINT_RANGE, "0,100,0.001,or_greater"), 0.1);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/default_angular_damp", PROPERTY_HINT_RANGE, "0,100,0.001,or_greater"), 0.1);

	// PhysicsServer3D
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/sleep_threshold_linear", PROPERTY_HINT_RANGE, "0,1,0.001,or_greater,suffix:m/s"), 0.1);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/sleep_threshold_angular", PROPERTY_HINT_RANGE, U"0,90,0.1,radians_as_degrees,suffix:°/s"), Math::deg_to_rad(8.0));
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/time_before_sleep", PROPERTY_HINT_RANGE, "0,5,0.01,or_greater,suffix:s"), 0.5);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/3d/solver/solver_iterations", PROPERTY_HINT_RANGE, "1,32,1,or_greater"), 16);
	// Experimental 3D extension of Box2D's two-point normal LCP solver.
	// Disabled until stability and cross-platform performance are validated.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/3d/solver/block_solver_enabled"), false);
	// Parallelize independent constraints inside a single large rigid-body island.
	// Off by default because color-by-color iteration changes the solver order.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/3d/solver/parallel_large_islands"), false);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/3d/solver/substeps", PROPERTY_HINT_RANGE, "1,16,1"), 1);
	// Jolt-style contact patch coverage while retaining the deepest point.
	// Disabled by default; manifold choice affects convergence and determinism.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/3d/solver/manifold_spread_reduction"), false);
	// XPBD compliant stretch/bend distance links for deformable soft bodies.
	// Zero selects the legacy Bullet-style projection; nonzero compliance
	// enables a per-link Lagrange multiplier across iterations of each step.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_xpbd_compliance", PROPERTY_HINT_RANGE, "0,0.01,0.000001,or_greater"), 0.0);
	// Direction-dependent stretch for fabric/rope. The axis is in the
	// undeformed soft mesh LOCAL space (not world space), and follows rotation.
	// Ratio 1 preserves isotropic XPBD; <1 means stiffer along the fiber.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_xpbd_parallel_compliance_ratio", PROPERTY_HINT_RANGE, "0.01,100,0.01,or_greater"), 1.0);
	GLOBAL_DEF(PropertyInfo(Variant::VECTOR3, "physics/3d/solver/soft_body_xpbd_material_axis"), Vector3(1, 0, 0));
	// Optional nonlinear tensile XPBD springs for deformable cloth/ropes.
	// Stiffen beyond yield; zero preserves the original linear XPBD solver.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_xpbd_tension_hardening", PROPERTY_HINT_RANGE, "0,100,0.1,or_greater"), 0.0);
	// Additional compression-only edge stiffening for foams and crushable solids.
	// Only applies to the XPBD stretch solver; 0 is bit-for-bit legacy behavior.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_xpbd_compression_hardening", PROPERTY_HINT_RANGE, "0,100,0.1,or_greater"), 0.0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_xpbd_compression_yield_strain", PROPERTY_HINT_RANGE, "0,1,0.01"), 0.1);
	// Phenomenological fatigue weakening after repeated strain excursions.
	// An XPBD-only material state: 0 rate preserves legacy behavior and
	// allocates no damage storage; cap < 1 avoids singular zero stiffness.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_fatigue_damage_rate", PROPERTY_HINT_RANGE, "0,100,0.1,or_greater,suffix:1/s"), 0.0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_fatigue_yield_strain", PROPERTY_HINT_RANGE, "0,5,0.01,or_greater"), 0.3);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_fatigue_max_damage", PROPERTY_HINT_RANGE, "0,0.99,0.01"), 0.9);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_xpbd_tension_yield_strain", PROPERTY_HINT_RANGE, "0,3,0.01,or_greater"), 0.1);
	// Independent unilateral XPBD limits prevent excessively stretching or
	// compressing a soft-body link while permitting normal elastic motion
	// inside the allowed interval. Zero ratios disable the solver entirely.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_xpbd_strain_max_stretch_ratio", PROPERTY_HINT_RANGE, "0,10,0.01,or_greater"), 0.0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_xpbd_strain_min_compression_ratio", PROPERTY_HINT_RANGE, "0,1,0.01"), 0.0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_xpbd_strain_limit_compliance", PROPERTY_HINT_RANGE, "0,0.01,0.000001,or_greater"), 0.0);
	// Optional viscoplastic rest-length creep for cloth, rope and deformable meshes.
	// Yield is the allowed elastic strain; creep rate 0 keeps legacy behavior.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_plastic_yield_strain", PROPERTY_HINT_RANGE, "0,1,0.001"), 0.1);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_plastic_creep_rate", PROPERTY_HINT_RANGE, "0,100,0.1,or_greater,suffix:1/s"), 0.0);
	// Longitudinal viscous damping of relative soft-body link velocities.
	// Zero preserves legacy behavior; finite positive rates use exponential
	// relaxation while conserving link momentum and keeping pins fixed.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_link_damping", PROPERTY_HINT_RANGE, "0,1000,0.1,or_greater,suffix:1/s"), 0.0);
	// Nonlinear viscous dashpot for fast link compression/stretching, which
	// reacts to strain rate rather than applying the same damping at all speeds.
	// 0 keeps the legacy simulation and avoids extra O(links) work.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_strain_rate_damping", PROPERTY_HINT_RANGE, "0,100,0.1,or_greater"), 0.0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_strain_rate_yield", PROPERTY_HINT_RANGE, "0,100,0.1,or_greater,suffix:1/s"), 0.0);
	// Optional Bullet-style aerodynamic lift for deformable surfaces.
	// Computed from mean face velocity through still air; disabled by default.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_lift_coefficient", PROPERTY_HINT_RANGE, "0,10,0.01,or_greater"), 0.0);
	// Opt-in sealed shell gas response: pressure = pressure_coefficient *
	// (V_rest / V)^gamma. 1 is isothermal; ~1.4 approximates adiabatic air.
	// Requires a manifold closed mesh and pressure_coefficient > 0.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_gas_pressure_gamma", PROPERTY_HINT_RANGE, "0,5,0.1"), 0.0);
	// Apply water-plane hydrostatic pressure to closed deformable surfaces.
	// Uses physics/3d/fluid_plane surface/density, default disabled. Face
	// triangles are clipped against the surface and pressure integrated.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/3d/solver/soft_body_hydrostatic_pressure"), false);
	// Jolt-style water flow drag, but distributed across deformable mesh
	// vertices and energy-limited per immersed face. Unlike hydrostatic
	// pressure this also applies to open cloth below the waterline.
	// Reuses fluid_plane/density, drag_coefficient and flow_velocity.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/3d/solver/soft_body_hydrodynamic_drag"), false);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_hydrodynamic_tangent_ratio", PROPERTY_HINT_RANGE, "0,5,0.05"), 0.25);
	// Optional tangential aerodynamic skin drag for cloth. Multiplies the
	// SoftBody3D drag coefficient; zero preserves the normal-only model.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_tangential_drag_ratio", PROPERTY_HINT_RANGE, "0,10,0.01,or_greater"), 0.0);
	// Optional per-triangle surface-area preservation for deformable cloth.
	// Zero disables all extra area constraints and associated lambda buffers.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_xpbd_area_compliance", PROPERTY_HINT_RANGE, "0,0.01,0.000001,or_greater"), 0.0);
	// Optional nonlinear St. Venant-Kirchhoff membrane strain energy.
	// One coupled plane-stress constraint per triangle captures extension,
	// compression, shear and Poisson coupling. This is NOT volumetric FEM.
	// Both buffers and work are disabled by default with zero compliance.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_xpbd_membrane_compliance", PROPERTY_HINT_RANGE, "0,0.01,0.000001,or_greater"), 0.0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_membrane_poisson_ratio", PROPERTY_HINT_RANGE, "-0.49,0.49,0.01"), 0.3);
	// Experimental convex closed-shell Neo-Hookean FEM, cooked into multiple
	// tetrahedra; arbitrary concave/imported tetra networks require a separate API.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_tetra_fem_compliance", PROPERTY_HINT_RANGE, "0,0.01,0.000001,or_greater"), 0.0);
	// Mass-lump the *rest tetra volume* to its four vertices, instead of
	// the legacy equal-per-vertex soft-body mass. Disabled for compatibility.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/3d/solver/soft_body_tetra_fem_lumped_mass"), false);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_tetra_fem_poisson_ratio", PROPERTY_HINT_RANGE, "0,0.49,0.01"), 0.3);
	// Optional large-deformation Mooney-Rivlin rubber-like material, with
	// two isochoric invariants and separate volumetric compression response.
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/3d/solver/soft_body_tetra_fem_material_model", PROPERTY_HINT_ENUM, "Neo-Hookean,Mooney-Rivlin,Ogden"), 0);
	// One-term principal-stretch Ogden hyperelastic material, normalized to
	// unit Young modulus. Enabled only with material_model=2; default is 3.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_tetra_ogden_exponent", PROPERTY_HINT_RANGE, "1,8,0.1"), 3.0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_tetra_mooney_rivlin_fraction", PROPERTY_HINT_RANGE, "0,1,0.01"), 0.5);
	// Experimental tension-only reinforcing fibers transported in a tetra's
	// undeformed material frame. Independent of isotropic Neo-Hookean FEM.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_tetra_fiber_compliance", PROPERTY_HINT_RANGE, "0,0.01,0.000001,or_greater"), 0.0);
	GLOBAL_DEF(PropertyInfo(Variant::VECTOR3, "physics/3d/solver/soft_body_tetra_fiber_axis"), Vector3(1, 0, 0));
	// Experimental irreversible tensile creep of the FEM material fiber.
	// Plastic rest stretch is allocated only while creep rate is positive.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_tetra_fiber_plastic_yield_ratio", PROPERTY_HINT_RANGE, "0,2,0.01,or_greater"), 0.15);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_tetra_fiber_plastic_creep_rate", PROPERTY_HINT_RANGE, "0,100,0.1,or_greater,suffix:1/s"), 0.0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_tetra_fiber_plastic_max_stretch", PROPERTY_HINT_RANGE, "1,16,0.1"), 3.0);
	// Objective Kelvin-Voigt strain-rate stress for each tetrahedral FEM element.
	// Independent from the global breathing-mode viscosity, off by default.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_tetra_fem_viscosity", PROPERTY_HINT_RANGE, "0,1000,0.1,or_greater"), 0.0);
	// Optional local isotropic volume viscoplasticity for tetrahedral FEM.
	// Modifies each element rest matrix (not mesh connectivity); disabled by
	// default. Distinct from the global closed-shell volume creep setting.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_tetra_volume_plastic_rate", PROPERTY_HINT_RANGE, "0,100,0.1,or_greater,suffix:1/s"), 0.0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_tetra_volume_plastic_yield", PROPERTY_HINT_RANGE, "0,2,0.01"), 0.15);
	// Optional objective tensorial isochoric plasticity: accumulate Hencky
	// deviatoric principal strains beyond a J2-like yield threshold. This
	// updates the FEM rest inverse matrix, but neither its volume nor mass.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_tetra_shear_plastic_rate", PROPERTY_HINT_RANGE, "0,100,0.1,or_greater,suffix:1/s"), 0.0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_tetra_shear_plastic_yield", PROPERTY_HINT_RANGE, "0,2,0.01"), 0.2);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_tetra_shear_plastic_max_strain", PROPERTY_HINT_RANGE, "0.01,4,0.01"), 2.0);
	// Local XPBD-style volume projection recovers inverted FEM tetrahedra
	// before the logarithmic Neo-Hookean energy solver (which rejects J<=0).
	// Disabled by default to preserve legacy behavior and solver ordering.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/3d/solver/soft_body_tetra_inversion_recovery"), false);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_tetra_inversion_min_j", PROPERTY_HINT_RANGE, "0.001,0.5,0.001"), 0.05);
	// Scalar material damage is irreversible; it does not split topology.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_tetra_damage_yield_strain", PROPERTY_HINT_RANGE, "0,5,0.01,or_greater"), 0.25);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_tetra_damage_rate", PROPERTY_HINT_RANGE, "0,1000,0.1,or_greater,suffix:1/s"), 0.0);
	// Intrinsic membrane viscoelastic damping of normal and shear strain rates.
	// Zero disables the extra face pass, all other projects remain unchanged.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_membrane_damping_rate", PROPERTY_HINT_RANGE, "0,1000,0.1,or_greater,suffix:1/s"), 0.0);
	// Opt-in XPBD triangle-angle shear preservation, independent of edge
	// stretch and area constraints. Default off, no per-face runtime buffers.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_xpbd_shear_compliance", PROPERTY_HINT_RANGE, "0,0.01,0.000001,or_greater"), 0.0);
	// Opt-in XPBD hinge dihedral bending for adjacent cloth triangles.
	// Zero disables setup, solver work and all persistent hinge buffers.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_xpbd_dihedral_compliance", PROPERTY_HINT_RANGE, "0,0.01,0.000001,or_greater"), 0.0);
	// Meshless shape matching fits a proper rigid rotation to the entire soft
	// mesh and pulls movable vertices toward the fitted rest shape. Unlike
	// volumetric FEM, this is a global visual-elasticity constraint.
	// Zero skips computation and all additional per-node allocations.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_shape_matching_stiffness", PROPERTY_HINT_RANGE, "0,1,0.01"), 0.0);
	// 0 retains whole-body shape matching; 3..64 enables overlapping local
	// one-ring clusters and spatially varying deformation.
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/3d/solver/soft_body_shape_matching_cluster_size", PROPERTY_HINT_RANGE, "0,64,1"), 0);
	// Hinge-local viscous bend damping; requires XPBD dihedral constraints.
	// Zero skips the O(hinges) velocity pass and preserves legacy results.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_dihedral_damping", PROPERTY_HINT_RANGE, "0,1000,0.1,or_greater,suffix:1/s"), 0.0);
	// Optional permanent cloth creases after bending beyond an angular yield.
	// Zero rate disables the pass, even when the XPBD hinge solver is enabled.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_bending_plastic_yield_angle", PROPERTY_HINT_RANGE, "0,3.14159265,0.01,suffix:rad"), 0.2);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_bending_plastic_creep_rate", PROPERTY_HINT_RANGE, "0,100,0.1,or_greater,suffix:1/s"), 0.0);
	// Optional Bullet-style vertex/triangle soft-body self contacts.
	// Zero thickness disables BVH candidate generation and all buffers.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_self_collision_thickness", PROPERTY_HINT_RANGE, "0,1,0.001,or_greater,suffix:m"), 0.0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_self_collision_compliance", PROPERTY_HINT_RANGE, "0,0.01,0.000001,or_greater"), 0.000001);
	// Optional contact-point tangential response for folded SoftBody3D cloth.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_self_collision_friction", PROPERTY_HINT_RANGE, "0,2,0.01,or_greater"), 0.0);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/3d/solver/soft_body_self_collision_max_contacts_per_vertex", PROPERTY_HINT_RANGE, "1,32,1"), 8);
	// Optional edge/edge contacts for folds missed by vertex/triangle contacts.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/3d/solver/soft_body_self_collision_edge_edge"), false);
	// Optional swept vertex/triangle tests for fast motion through thin cloth.
	// Off by default: the swept BVH and cubic narrowphase are more expensive.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/3d/solver/soft_body_self_collision_ccd"), false);
	// Experimental Bullet-style TWO-WAY soft-body vertex/triangle contacts.
	// Zero thickness disables the pair stage and all its extra runtime work.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_pair_collision_thickness", PROPERTY_HINT_RANGE, "0,1,0.001,or_greater,suffix:m"), 0.0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_pair_collision_compliance", PROPERTY_HINT_RANGE, "0,0.01,0.000001,or_greater"), 0.000001);
	// Coulomb-limited velocity friction between DISTINCT soft bodies.
	// Zero is free slip; no friction pass or additional persistent storage.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_pair_collision_friction", PROPERTY_HINT_RANGE, "0,4,0.01,or_greater"), 0.0);
	// Extra continuous vertex/triangle crossing detection for different soft bodies.
	// False preserves discrete-only behavior and allocates no history buffers.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/3d/solver/soft_body_pair_collision_ccd"), false);
	// Opt-in contacts between structural mesh edges of DIFFERENT soft bodies.
	// Reuses the self-edge XPBD row but has its own lazy per-body edge BVH.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/3d/solver/soft_body_pair_collision_edge_edge"), false);
	// Continuous inter-body edge proximity: requires pair CCD history and edge contacts.
	// Off by default; bounded conservative-advancement narrowphase costs extra CPU.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/3d/solver/soft_body_pair_collision_edge_ccd"), false);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/3d/solver/soft_body_pair_max_contacts", PROPERTY_HINT_RANGE, "1,2048,1"), 256);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/3d/solver/soft_body_pair_max_pairs", PROPERTY_HINT_RANGE, "1,512,1"), 128);
	// Jolt-style long-range cloth tethers limit distance from pinned
	// particles along the original structural mesh. 0 keeps them off.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_xpbd_tether_compliance", PROPERTY_HINT_RANGE, "0,0.01,0.000001,or_greater"), 0.0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_xpbd_tether_slack", PROPERTY_HINT_RANGE, "0,1,0.01,or_greater"), 0.05);
	// Closed, consistently oriented soft meshes can preserve enclosed volume.
	// Zero disables the extra XPBD constraint and its node-gradient buffer.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_xpbd_volume_compliance", PROPERTY_HINT_RANGE, "0,0.01,0.000001,or_greater"), 0.0);
	// Bulk viscosity removes only the breathing/compression mode of a valid
	// closed soft body while preserving its free translation and rotation.
	// Zero skips the O(faces + nodes) velocity projection and scratch setup.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_volume_damping_rate", PROPERTY_HINT_RANGE, "0,1000,0.1,or_greater,suffix:1/s"), 0.0);
	// Closed-mesh viscoplastic volume creep after sufficiently strong crushing
	// or expansion. Requires XPBD volume compliance; a zero rate is legacy.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_volume_plastic_yield_strain", PROPERTY_HINT_RANGE, "0,0.95,0.01"), 0.15);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/soft_body_volume_plastic_creep_rate", PROPERTY_HINT_RANGE, "0,100,0.1,or_greater,suffix:1/s"), 0.0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/contact_recycle_radius", PROPERTY_HINT_RANGE, "0,0.1,0.001,or_greater,suffix:m"), 0.01);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/contact_max_separation", PROPERTY_HINT_RANGE, "0,0.1,0.001,or_greater,suffix:m"), 0.05);
	// Experimental sphere-only speculative contacts for existing broadphase pairs.
	// 0 preserves legacy behavior; wider gaps can produce ghost interactions.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/speculative_sphere_distance", PROPERTY_HINT_RANGE, "0,1,0.001,or_greater,suffix:m"), 0.0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/contact_max_allowed_penetration", PROPERTY_HINT_RANGE, "0.001,0.1,0.001,or_greater,suffix:m"), 0.01);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/default_contact_bias", PROPERTY_HINT_RANGE, "0,1,0.01"), 0.8);
	// Zero disables the clamp for backwards-compatible penetration recovery.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/max_contact_push_speed", PROPERTY_HINT_RANGE, "0,1000,1,or_greater,suffix:m/s"), 0.0);
	// Rapier-style bounded dynamic linear speed; legacy behavior is unlimited.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/max_linear_velocity", PROPERTY_HINT_RANGE, "0,10000,1,or_greater,suffix:m/s"), 0.0);
	// Jolt-style maximum dynamic angular velocity, 0 means unlimited.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/max_angular_velocity", PROPERTY_HINT_RANGE, U"0,3600,1,radians_as_degrees,or_greater,suffix:°/s"), 0.0);
	// Rapier-style optional per-step rotation cap for CCD dynamic bodies only.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/ccd_max_angular_motion", PROPERTY_HINT_RANGE, U"0,360,1,radians_as_degrees,or_greater,suffix:°"), 0.0);
	// Rapier-style cached contact impulse reuse, opt-in damping (1.0 is legacy).
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/warm_start_coefficient", PROPERTY_HINT_RANGE, "0,1,0.01"), 1.0);
	// Box2D-style Pade damping remains opt-in for backwards-compatible motion.
	// Account for rotating CCD shapes in broadphase candidate generation.
	// Conservative only: narrowphase angular time-of-impact remains separate.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/3d/solver/ccd_rotational_bounds"), false);
	// Exact arc extrema for every AABB corner, instead of radial padding.
	// Opt-in for scenes where fewer broadphase pairs amortize extra math.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/3d/solver/ccd_tight_rotational_bounds"), false);
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/3d/solver/implicit_damping"), false);
	// Optional uniform fully submerged fluid approximation, inspired by
	// Jolt's buoyancy/drag: 1 = neutral buoyancy, >1 floats. All effects
	// are off by default. Drag coefficients are mass/inertia normalized.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/fluid_linear_drag", PROPERTY_HINT_RANGE, "0,100,0.01,or_greater"), 0.0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/fluid_angular_drag", PROPERTY_HINT_RANGE, "0,100,0.01,or_greater"), 0.0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/fluid_buoyancy", PROPERTY_HINT_RANGE, "0,2,0.01,or_greater"), 0.0);
	GLOBAL_DEF(PropertyInfo(Variant::VECTOR3, "physics/3d/solver/fluid_flow_velocity"), Vector3());
	// Jolt-style per-shape buoyancy: approximate partial immersion below a
	// horizontal liquid surface; opt-in and independent from legacy damping.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/3d/fluid_plane/enabled"), false);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/fluid_plane/surface_height", PROPERTY_HINT_RANGE, "-100000,100000,0.01,or_less,or_greater,suffix:m"), 0.0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/fluid_plane/density", PROPERTY_HINT_RANGE, "0,2000,1,or_greater,suffix:kg/m³"), 1000.0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/fluid_plane/drag_coefficient", PROPERTY_HINT_RANGE, "0,5,0.01,or_greater"), 0.8);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/fluid_plane/angular_drag", PROPERTY_HINT_RANGE, "0,20,0.01,or_greater"), 0.1);
	GLOBAL_DEF(PropertyInfo(Variant::VECTOR3, "physics/3d/fluid_plane/flow_velocity"), Vector3());
	// Reproduce free rotation of asymmetric bodies (Jolt-style gyroscopic term).
	// Off by default because it changes angular motion and costs extra math.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/3d/solver/gyroscopic_forces"), false);
	// Midpoint preserves both angular momentum magnitude and rotational energy
	// in torque-free free rigid-body motion; normalized Euler remains default.
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/3d/solver/gyroscopic_integration_mode", PROPERTY_HINT_ENUM, "Normalized Euler,Implicit Midpoint"), 0);
	// Optional Bullet-style rolling and torsional contact friction, off by default.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/rolling_friction", PROPERTY_HINT_RANGE, "0,1,0.01,or_greater"), 0.0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/spinning_friction", PROPERTY_HINT_RANGE, "0,1,0.01,or_greater"), 0.0);
	// Suppress tiny bounces at contacts so stacked bodies can settle (meters per second).
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/restitution_velocity_threshold", PROPERTY_HINT_RANGE, "0,10,0.01,or_greater,suffix:m/s"), 1.0);
	// Keep historical friction mixing unless a project opts into another model.
	// PhysX-style static coefficient = combined material friction * multiplier;
	// default 1.0 keeps the historic single-Coulomb-cone solver unchanged.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/static_friction_multiplier", PROPERTY_HINT_RANGE, "1,5,0.01,or_greater"), 1.0);
	// Optional Stribeck-like smooth static-to-kinetic friction transition
	// in rigid/rigid and rigid/soft contacts. 0 disables extra math.
	// Uses the static friction multiplier to define low-speed friction.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/stribeck_transition_velocity", PROPERTY_HINT_RANGE, "0,10,0.01,or_greater,suffix:m/s"), 0.0);
	// Opt-in Bullet-inspired anisotropic tangential contact resistance.
	// The preferred axis is WORLD-space; only its projection into the
	// contact plane matters. 1.0 preserves the existing isotropic solver.
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/3d/solver/friction_anisotropy_ratio", PROPERTY_HINT_RANGE, "0.01,1,0.01"), 1.0);
	GLOBAL_DEF(PropertyInfo(Variant::VECTOR3, "physics/3d/solver/friction_anisotropy_axis"), Vector3(1, 0, 0));
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/3d/solver/friction_combine_mode", PROPERTY_HINT_ENUM, "Legacy Minimum,Geometric Mean,Average,Maximum"), 0);
	// Default preserves the historic clamped sum. Other modes match common
	// game-physics coefficient combination rules (Box2D / Rapier).
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/3d/solver/restitution_combine_mode", PROPERTY_HINT_ENUM, "Legacy Clamped Sum,Maximum,Average,Minimum,Multiply,Geometric Mean"), 0);
}

PhysicsServer3D::~PhysicsServer3D() {
	singleton = nullptr;
}
