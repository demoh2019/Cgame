/**************************************************************************/
/*  jolt_project_settings.h                                               */
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

#include <cstdint>

enum JoltJointWorldNode : int {
	JOLT_JOINT_WORLD_NODE_A,
	JOLT_JOINT_WORLD_NODE_B,
};

class JoltProjectSettings {
public:
	inline static int simulation_velocity_steps;
	inline static int simulation_position_steps;
	inline static int simulation_collision_steps;
	inline static float simulation_max_collision_step_seconds;
	inline static bool simulation_use_large_island_splitter;
	inline static bool simulation_use_manifold_reduction;
	inline static bool use_enhanced_internal_edge_removal_for_bodies;
	inline static bool generate_all_kinematic_contacts;
	inline static float penetration_slop;
	inline static float speculative_contact_distance;
	inline static float max_penetration_correction_distance;
	inline static float contact_manifold_merge_normal_cos;
	inline static float contact_warm_start_distance_sq;
	inline static float baumgarte_stabilization_factor;
	inline static float soft_body_point_radius;
	// Opt-in, bounded CPU soft-soft particle contacts; independent of Jolt's
	// built-in soft-rigid contact pipeline. These settings apply per step.
	inline static bool soft_body_soft_contacts = false;
	// Optional vertex-versus-triangle soft contacts; replaces the cheaper
	// vertex-versus-vertex method when enabled. Requires soft_contacts=true.
	inline static bool soft_body_soft_vertex_face_contacts = false;
	// Optional bounded per-pair dynamic-face BVH; only applies in vertex-face mode.
	inline static bool soft_body_soft_vertex_face_bvh = false;
	// Independently budgeted segment-segment soft-body contacts.
	// Requires both soft_body_soft_contacts and vertex_face_contacts.
	inline static bool soft_body_soft_edge_edge_contacts = false;
	// Approximate linear swept point-vs-face prediction, only in VF mode.
	inline static bool soft_body_soft_speculative_ccd = false;
	// Optional conservative-advancement CCD for deformable segment pairs;
	// requires the existing soft-soft edge-edge collision pass.
	inline static bool soft_body_soft_speculative_edge_ccd = false;
	// Opt-in soft body self collision: non-neighboring vertices against the
	// body's own deformable triangles. Uses a separate per-space CPU budget.
	inline static bool soft_body_self_contacts = false;
	// Opt-in conservative-advancement point/face CCD *inside* one soft
	// body; independent of inter-body speculative CCD and self edge CCD.
	inline static bool soft_body_self_speculative_vertex_face_ccd = false;
	// Optional nonlocal self edge/edge collisions, separate quota within
	// the existing global self-contact budget. Requires self_contacts=true.
	inline static bool soft_body_self_edge_contacts = false;
	// Experimental time-swept nonlocal self edge-edge contact prediction.
	// Requires self_contacts and self_edge_contacts; off by default.
	inline static bool soft_body_self_speculative_edge_ccd = false;
	// Rebuild a bounded local-space BVH of deformed edges when self EE is on.
	// Disabled by default, preserving the original linear edge-pair scan.
	inline static bool soft_body_self_edge_bvh = false;
	// Opt-in persistent per-body adjacency and incremental edge-BVH refits.
	// Requires self and self-edge collisions + the edge BVH. Default false.
	inline static bool soft_body_self_persistent_bvh = false;
	// Independently cache and refit the self vertex-face triangle BVH;
	// works without enabling edge collision or persistent edge BVH.
	inline static bool soft_body_self_face_bvh_refit = false;
	inline static int soft_body_self_contact_max_checks = 16384;
	// Opt-in Jacobi XPBD-style position projection of nonadjacent
	// vertex-face and edge-edge self contacts. Velocity impulses remain.
	inline static bool soft_body_self_position_projection = false;
	inline static float soft_body_self_position_compliance = 0.000001f;
	inline static float soft_body_self_position_max_correction = 0.02f;
	inline static float soft_body_soft_ccd_max_sweep = 1.0f;
	inline static float soft_body_soft_ccd_max_correction_speed = 128.0f;
	inline static float soft_body_soft_contact_radius = 0.1f;
	inline static float soft_body_soft_contact_recovery = 0.2f;
	inline static float soft_body_soft_contact_friction = 0.2f;
	inline static int soft_body_soft_contact_max_particle_pairs = 32768;
	// Used when constructing a soft body; existing bodies retain their constraints.
	inline static int soft_body_bend_mode = 0;
	inline static float soft_body_bend_compliance = 0.001f;
	// Opt-in direction-dependent textile XPBD compliance at mesh creation.
	inline static int soft_body_fiber_axis = 0;
	inline static float soft_body_fiber_compliance_multiplier = 1.0f;
	// Opt-in long-range cloth attachments to pinned vertices; new meshes only.
	inline static int soft_body_lra_mode = 0;
	inline static float soft_body_lra_max_distance_multiplier = 1.05f;
	// Opt-in convex, closed-mesh tetrahedral volume constraints.
	inline static bool soft_body_volume_preservation = false;
	inline static float soft_body_volume_compliance = 0.00001f;
	// Restore opt-in cubically scaling tetrahedral rest volume during shrink.
	inline static bool soft_body_volume_follow_shrinking_factor = false;
	// Adds center-to-surface XPBD stretch springs to the convex tetra fan.
	inline static bool soft_body_volume_radial_springs = false;
	inline static float soft_body_volume_radial_compliance = 0.0001f;
	// 0 = isotropic; 1/2/3 = local X/Y/Z directional radial compliance.
	inline static int soft_body_radial_anisotropy_axis = 0;
	inline static float soft_body_radial_anisotropy_ratio = 1.0f;
	inline static float bounce_velocity_threshold;
	inline static bool sleep_allowed;
	inline static float sleep_velocity_threshold;
	inline static float sleep_time_threshold;
	inline static float ccd_movement_threshold;
	inline static float ccd_max_penetration;
	inline static bool body_pair_contact_cache_enabled;
	inline static float body_pair_cache_distance_sq;
	inline static float body_pair_cache_angle_cos_div2;

	inline static bool use_enhanced_internal_edge_removal_for_queries;
	inline static bool enable_ray_cast_face_index;

	inline static bool use_enhanced_internal_edge_removal_for_motion_queries;
	inline static int motion_query_recovery_iterations;
	inline static float motion_query_recovery_amount;

	inline static float collision_margin_fraction;
	inline static float active_edge_threshold_cos;
	// Snapshot when a physics space is created; never mutate active Jolt callbacks.
	inline static int friction_combine_mode = 0;
	inline static int restitution_combine_mode = 0;

	inline static JoltJointWorldNode joint_world_node;

	inline static int temp_memory_mib;
	inline static int64_t temp_memory_b;
	inline static int max_in_flight_body_pairs;
	inline static float world_boundary_shape_size;
	inline static float max_linear_velocity;
	inline static float max_angular_velocity;
	inline static int max_bodies;
	inline static int max_body_pairs;
	inline static int max_contact_constraints;

	static void register_settings();
	static void read_settings();
};
