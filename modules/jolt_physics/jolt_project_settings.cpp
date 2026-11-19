/**************************************************************************/
/*  jolt_project_settings.cpp                                             */
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

#include "jolt_project_settings.h"

#include "core/config/project_settings.h"
#include "core/object/callable_mp.h"

void JoltProjectSettings::register_settings() {
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/jolt_physics_3d/simulation/velocity_steps", PROPERTY_HINT_RANGE, U"2,16,or_greater"), 10);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/jolt_physics_3d/simulation/position_steps", PROPERTY_HINT_RANGE, U"1,16,or_greater"), 2);
	// Jolt subdivides each physics tick into collision + integration passes.
	// One pass preserves the current performance and simulation behavior.
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/jolt_physics_3d/simulation/collision_steps", PROPERTY_HINT_RANGE, U"1,8,1"), 1);
	// 0 disables automatic substepping. Positive values trigger additional passes
	// only when the physics timestep exceeds this duration (seconds).
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/max_collision_step_seconds", PROPERTY_HINT_RANGE, U"0,0.1,0.001,or_greater,suffix:s"), 0.0f);
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/simulation/use_large_island_splitter"), true);
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/simulation/use_manifold_reduction"), true);
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/simulation/use_enhanced_internal_edge_removal"), true);
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/simulation/generate_all_kinematic_contacts"), false);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/penetration_slop", PROPERTY_HINT_RANGE, U"0,1,0.00001,or_greater,suffix:m"), 0.02f);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/speculative_contact_distance", PROPERTY_HINT_RANGE, U"0,1,0.00001,or_greater,suffix:m"), 0.02f);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/max_penetration_correction_distance", PROPERTY_HINT_RANGE, U"0,5,0.001,suffix:m"), 0.2f);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/contact_manifold_merge_angle", PROPERTY_HINT_RANGE, U"0,90,0.1,radians_as_degrees"), Math::deg_to_rad(5.0f));
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/contact_warm_start_distance", PROPERTY_HINT_RANGE, U"0,0.2,0.0001,suffix:m"), 0.01f);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/baumgarte_stabilization_factor", PROPERTY_HINT_RANGE, U"0,1,0.01"), 0.2f);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/soft_body_point_radius", PROPERTY_HINT_RANGE, U"0,1,0.001,or_greater,suffix:m"), 0.01f);
	// Experimental soft-soft CPU particle contacts. Jolt itself supports
	// soft-rigid but not soft-soft contacts. Disabled to preserve performance.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/simulation/soft_body_soft_contacts"), false);
	// More accurate contact with sparse surface meshes. Opt-in and shares
	// the existing global pair-test budget; no cost in the default path.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/simulation/soft_body_soft_vertex_face_contacts"), false);
	// Build a bounded face hierarchy for overlapping soft-body pairs to
	// avoid testing sparse contact queries against every triangle.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/simulation/soft_body_soft_vertex_face_bvh"), false);
	// Catch crossed deformable edges whose endpoints are all far from the
	// opposite surface. Requires soft contacts and vertex-face mode.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/simulation/soft_body_soft_edge_edge_contacts"), false);
	// Approximate linear swept VF contact. This is not rigid-body LinearCast
	// and not exact deforming-triangle CCD. Disabled unless explicitly opted in.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/simulation/soft_body_soft_speculative_ccd"), false);
	// Bounded linearly swept edge-edge contact; reuses the existing sweep
	// horizon and impulse-speed caps. Requires soft-soft EE + VF enabled.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/simulation/soft_body_soft_speculative_edge_ccd"), false);
	// Self-collision operates on non-adjacent vertex/face pairs only; the
	// topology-aware CPU pass is separately budgeted and disabled by default.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/simulation/soft_body_self_contacts"), false);
	// Capture narrow cloth folds where two nonadjacent edges cross even
	// though no point comes close to an opposing triangle.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/simulation/soft_body_self_edge_contacts"), false);
	// Bounded conservative-advancement prediction of nonlocal self
	// edge crossings. Reuses swept contact distance and impulse limits.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/simulation/soft_body_self_speculative_edge_ccd"), false);
	// A bounded, per-step BVH accelerates distant self edge pairs. Keep
	// this default-off until native performance baselines are available.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/simulation/soft_body_self_edge_bvh"), false);
	// Reuse immutable soft-mesh topology and refit deformed edge bounds
	// without re-sorting the BVH every physics step; cache is bounded per space.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/simulation/soft_body_self_persistent_bvh"), false);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/jolt_physics_3d/simulation/soft_body_self_contact_max_checks", PROPERTY_HINT_RANGE, "1024,65536,1024"), 16384);
	// Pre-step XPBD-style Jacobi projection supplements soft self-contact
	// impulses without changing Jolt's native deformable constraint solver.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/simulation/soft_body_self_position_projection"), false);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/soft_body_self_position_compliance", PROPERTY_HINT_RANGE, "0,0.001,0.000001"), 0.000001f);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/soft_body_self_position_max_correction", PROPERTY_HINT_RANGE, "0,0.1,0.001,suffix:m"), 0.02f);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/soft_body_soft_ccd_max_sweep", PROPERTY_HINT_RANGE, "0,4,0.01,suffix:m"), 1.0f);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/soft_body_soft_ccd_max_correction_speed", PROPERTY_HINT_RANGE, "1,256,1,suffix:m/s"), 128.0f);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/soft_body_soft_contact_radius", PROPERTY_HINT_RANGE, "0,1,0.001,suffix:m"), 0.1f);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/soft_body_soft_contact_recovery", PROPERTY_HINT_RANGE, "0,1,0.01"), 0.2f);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/soft_body_soft_contact_friction", PROPERTY_HINT_RANGE, "0,1,0.01"), 0.2f);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/jolt_physics_3d/simulation/soft_body_soft_contact_max_particle_pairs", PROPERTY_HINT_RANGE, "1024,65536,1024"), 32768);
	// Extra XPBD bending is opt-in to preserve existing scene behavior.
	// Applies when creating/rebuilding a soft body, not retroactively.
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/jolt_physics_3d/simulation/soft_body_bend_mode", PROPERTY_HINT_ENUM, "Disabled,Distance,Dihedral"), 0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/soft_body_bend_compliance", PROPERTY_HINT_RANGE, "0,1,0.000001,or_greater"), 0.001f);
	// Ratio 1 keeps isotropic cloth; select local fiber axis for warp/weft.
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/jolt_physics_3d/simulation/soft_body_fiber_axis", PROPERTY_HINT_ENUM, "X,Y,Z"), 0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/soft_body_fiber_compliance_multiplier", PROPERTY_HINT_RANGE, "0.1,10,0.05"), 1.0f);
	// Long-range attachments reduce excessive cloth stretch from pinned points.
	// Geodesic distances follow the mesh rather than cutting through folds.
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/jolt_physics_3d/simulation/soft_body_lra_mode", PROPERTY_HINT_ENUM, "Disabled,Euclidean,Geodesic"), 0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/soft_body_lra_max_distance_multiplier", PROPERTY_HINT_RANGE, "1,10,0.01"), 1.05f);
	// Generate an interior particle and tetrahedral volume constraints only for
	// small, closed, consistently wound convex soft-body surface meshes.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/simulation/soft_body_volume_preservation"), false);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/soft_body_volume_compliance", PROPERTY_HINT_RANGE, "0,0.01,0.000001,or_greater"), 0.00001f);
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/simulation/soft_body_volume_follow_shrinking_factor"), false);
	// Optional volumetric edge springs resist interior-to-surface stretching
	// and add shape support to the convex tetrahedral volume fan.
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/simulation/soft_body_volume_radial_springs"), false);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/soft_body_volume_radial_compliance", PROPERTY_HINT_RANGE, "0,1,0.000001"), 0.0001f);
	// Directional radial elastic response in the original mesh-local frame.
	// A ratio > 1 increases compliance (softer), < 1 reduces it (stiffer).
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/jolt_physics_3d/simulation/soft_body_radial_anisotropy_axis", PROPERTY_HINT_ENUM, "Isotropic,Local X,Local Y,Local Z"), 0);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/soft_body_radial_anisotropy_ratio", PROPERTY_HINT_RANGE, "0.1,10,0.01"), 1.0f);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/bounce_velocity_threshold", PROPERTY_HINT_RANGE, U"0,1,0.001,or_greater,suffix:m/s"), 1.0f);
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/simulation/allow_sleep"), true);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/sleep_velocity_threshold", PROPERTY_HINT_RANGE, U"0,1,0.001,or_greater,suffix:m/s"), 0.03f);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/sleep_time_threshold", PROPERTY_HINT_RANGE, U"0,5,0.01,or_greater,suffix:s"), 0.5f);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/continuous_cd_movement_threshold", PROPERTY_HINT_RANGE, U"0,1,0.01"), 0.75f);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/continuous_cd_max_penetration", PROPERTY_HINT_RANGE, U"0,1,0.01"), 0.25f);
	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/simulation/body_pair_contact_cache_enabled"), true);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/body_pair_contact_cache_distance_threshold", PROPERTY_HINT_RANGE, U"0,0.01,0.00001,or_greater,suffix:m"), 0.001f);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/simulation/body_pair_contact_cache_angle_threshold", PROPERTY_HINT_RANGE, U"0,180,0.01,radians_as_degrees"), Math::deg_to_rad(2.0f));

	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/queries/use_enhanced_internal_edge_removal"), false);
	GLOBAL_DEF_RST(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/queries/enable_ray_cast_face_index"), false);

	GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/jolt_physics_3d/motion_queries/use_enhanced_internal_edge_removal"), true);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/jolt_physics_3d/motion_queries/recovery_iterations", PROPERTY_HINT_RANGE, U"1,8,or_greater"), 4);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/motion_queries/recovery_amount", PROPERTY_HINT_RANGE, U"0,1,0.01"), 0.4f);

	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/collisions/collision_margin_fraction", PROPERTY_HINT_RANGE, U"0,1,0.00001"), 0.08f);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/collisions/active_edge_threshold", PROPERTY_HINT_RANGE, U"0,90,0.01,radians_as_degrees"), Math::deg_to_rad(50.0f));
	// Legacy combination is preserved unless the user opts into Box2D/Rapier rules.
	// Modes mirror built-in GodotPhysics for predictable 3D backend switching.
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/jolt_physics_3d/collisions/friction_combine_mode", PROPERTY_HINT_ENUM, "Legacy Minimum,Geometric Mean,Average,Maximum"), 0);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/jolt_physics_3d/collisions/restitution_combine_mode", PROPERTY_HINT_ENUM, "Legacy Clamped Sum,Maximum,Average,Minimum,Multiply,Geometric Mean"), 0);

	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/jolt_physics_3d/joints/world_node", PROPERTY_HINT_ENUM, U"Node A,Node B"), JOLT_JOINT_WORLD_NODE_A);

	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/jolt_physics_3d/limits/temporary_memory_buffer_size", PROPERTY_HINT_RANGE, U"1,32,or_greater,suffix:MiB"), 32);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/jolt_physics_3d/limits/max_in_flight_body_pairs", PROPERTY_HINT_RANGE, U"1024,262144,1024"), 16384);
	GLOBAL_DEF_RST(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/limits/world_boundary_shape_size", PROPERTY_HINT_RANGE, U"2,2000,0.1,or_greater,suffix:m"), 2000.0f);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/limits/max_linear_velocity", PROPERTY_HINT_RANGE, U"0,500,0.01,or_greater,suffix:m/s"), 500.0f);
	GLOBAL_DEF(PropertyInfo(Variant::FLOAT, "physics/jolt_physics_3d/limits/max_angular_velocity", PROPERTY_HINT_RANGE, U"0,2700,0.01,or_greater,radians_as_degrees,suffix:°/s"), Math::deg_to_rad(2700.0f));
	GLOBAL_DEF_RST(PropertyInfo(Variant::INT, "physics/jolt_physics_3d/limits/max_bodies", PROPERTY_HINT_RANGE, U"1,10240,or_greater"), 10240);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/jolt_physics_3d/limits/max_body_pairs", PROPERTY_HINT_RANGE, U"8,65536,or_greater"), 65536);
	GLOBAL_DEF(PropertyInfo(Variant::INT, "physics/jolt_physics_3d/limits/max_contact_constraints", PROPERTY_HINT_RANGE, U"8,20480,or_greater"), 20480);

	read_settings();

	ProjectSettings::get_singleton()->connect("settings_changed", callable_mp_static(JoltProjectSettings::read_settings));
}

void JoltProjectSettings::read_settings() {
	simulation_velocity_steps = GLOBAL_GET("physics/jolt_physics_3d/simulation/velocity_steps");
	simulation_position_steps = GLOBAL_GET("physics/jolt_physics_3d/simulation/position_steps");
	simulation_collision_steps = GLOBAL_GET("physics/jolt_physics_3d/simulation/collision_steps");
	simulation_max_collision_step_seconds = GLOBAL_GET("physics/jolt_physics_3d/simulation/max_collision_step_seconds");
	simulation_use_large_island_splitter = GLOBAL_GET("physics/jolt_physics_3d/simulation/use_large_island_splitter");
	simulation_use_manifold_reduction = GLOBAL_GET("physics/jolt_physics_3d/simulation/use_manifold_reduction");
	use_enhanced_internal_edge_removal_for_bodies = GLOBAL_GET("physics/jolt_physics_3d/simulation/use_enhanced_internal_edge_removal");
	generate_all_kinematic_contacts = GLOBAL_GET("physics/jolt_physics_3d/simulation/generate_all_kinematic_contacts");
	penetration_slop = GLOBAL_GET("physics/jolt_physics_3d/simulation/penetration_slop");
	speculative_contact_distance = GLOBAL_GET("physics/jolt_physics_3d/simulation/speculative_contact_distance");
	max_penetration_correction_distance = CLAMP((float)GLOBAL_GET("physics/jolt_physics_3d/simulation/max_penetration_correction_distance"), 0.0f, 5.0f);
	const float merge_angle = CLAMP((float)GLOBAL_GET("physics/jolt_physics_3d/simulation/contact_manifold_merge_angle"), 0.0f, (float)Math::PI / 2.0f);
	contact_manifold_merge_normal_cos = Math::cos(merge_angle);
	const float contact_warm_start_distance = CLAMP((float)GLOBAL_GET("physics/jolt_physics_3d/simulation/contact_warm_start_distance"), 0.0f, 0.2f);
	contact_warm_start_distance_sq = contact_warm_start_distance * contact_warm_start_distance;
	baumgarte_stabilization_factor = GLOBAL_GET("physics/jolt_physics_3d/simulation/baumgarte_stabilization_factor");
	soft_body_point_radius = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_point_radius");
	soft_body_bend_mode = CLAMP((int)GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_bend_mode"), 0, 2);
	const float bend_compliance = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_bend_compliance");
	soft_body_bend_compliance = Math::is_finite(bend_compliance) ? MAX(bend_compliance, 0.0f) : 0.001f;
	soft_body_fiber_axis = CLAMP((int)GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_fiber_axis"), 0, 2);
	const float fiber_multiplier = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_fiber_compliance_multiplier");
	soft_body_fiber_compliance_multiplier = Math::is_finite(fiber_multiplier) ? CLAMP(fiber_multiplier, 0.1f, 10.0f) : 1.0f;
	soft_body_lra_mode = CLAMP((int)GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_lra_mode"), 0, 2);
	const float lra_multiplier = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_lra_max_distance_multiplier");
	soft_body_lra_max_distance_multiplier = Math::is_finite(lra_multiplier) ? CLAMP(lra_multiplier, 1.0f, 10.0f) : 1.05f;
	soft_body_volume_preservation = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_volume_preservation");
	const float volume_compliance = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_volume_compliance");
	soft_body_volume_compliance = Math::is_finite(volume_compliance) ? MAX(volume_compliance, 0.0f) : 0.00001f;
	soft_body_volume_follow_shrinking_factor = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_volume_follow_shrinking_factor");
	soft_body_volume_radial_springs = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_volume_radial_springs");
	const float radial_compliance = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_volume_radial_compliance");
	soft_body_volume_radial_compliance = Math::is_finite(radial_compliance) ? CLAMP(radial_compliance, 0.0f, 1.0f) : 0.0001f;
	soft_body_radial_anisotropy_axis = CLAMP((int)GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_radial_anisotropy_axis"), 0, 3);
	const float anisotropy_ratio = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_radial_anisotropy_ratio");
	soft_body_radial_anisotropy_ratio = Math::is_finite(anisotropy_ratio) ? CLAMP(anisotropy_ratio, 0.1f, 10.0f) : 1.0f;
	soft_body_soft_contacts = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_soft_contacts");
	soft_body_soft_vertex_face_contacts = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_soft_vertex_face_contacts");
	soft_body_soft_vertex_face_bvh = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_soft_vertex_face_bvh");
	soft_body_soft_edge_edge_contacts = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_soft_edge_edge_contacts");
	soft_body_soft_speculative_ccd = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_soft_speculative_ccd");
	soft_body_soft_speculative_edge_ccd = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_soft_speculative_edge_ccd");
	soft_body_self_contacts = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_self_contacts");
	soft_body_self_edge_contacts = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_self_edge_contacts");
	soft_body_self_speculative_edge_ccd = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_self_speculative_edge_ccd");
	soft_body_self_edge_bvh = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_self_edge_bvh");
	soft_body_self_persistent_bvh = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_self_persistent_bvh");
	soft_body_self_contact_max_checks = CLAMP((int)GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_self_contact_max_checks"), 1024, 65536);
	soft_body_self_position_projection = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_self_position_projection");
	const float position_compliance = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_self_position_compliance");
	soft_body_self_position_compliance = Math::is_finite(position_compliance) ? CLAMP(position_compliance, 0.0f, 0.001f) : 0.000001f;
	const float max_position_correction = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_self_position_max_correction");
	soft_body_self_position_max_correction = Math::is_finite(max_position_correction) ? CLAMP(max_position_correction, 0.0f, 0.1f) : 0.02f;
	const float ccd_sweep = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_soft_ccd_max_sweep");
	soft_body_soft_ccd_max_sweep = Math::is_finite(ccd_sweep) ? CLAMP(ccd_sweep, 0.0f, 4.0f) : 1.0f;
	const float ccd_correction = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_soft_ccd_max_correction_speed");
	soft_body_soft_ccd_max_correction_speed = Math::is_finite(ccd_correction) ? CLAMP(ccd_correction, 1.0f, 256.0f) : 128.0f;
	const float soft_contact_radius = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_soft_contact_radius");
	soft_body_soft_contact_radius = Math::is_finite(soft_contact_radius) ? CLAMP(soft_contact_radius, 0.0f, 1.0f) : 0.1f;
	const float soft_contact_recovery = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_soft_contact_recovery");
	soft_body_soft_contact_recovery = Math::is_finite(soft_contact_recovery) ? CLAMP(soft_contact_recovery, 0.0f, 1.0f) : 0.2f;
	const float soft_contact_friction = GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_soft_contact_friction");
	soft_body_soft_contact_friction = Math::is_finite(soft_contact_friction) ? CLAMP(soft_contact_friction, 0.0f, 1.0f) : 0.2f;
	soft_body_soft_contact_max_particle_pairs = CLAMP((int)GLOBAL_GET("physics/jolt_physics_3d/simulation/soft_body_soft_contact_max_particle_pairs"), 1024, 65536);
	bounce_velocity_threshold = GLOBAL_GET("physics/jolt_physics_3d/simulation/bounce_velocity_threshold");
	sleep_allowed = GLOBAL_GET("physics/jolt_physics_3d/simulation/allow_sleep");
	sleep_velocity_threshold = GLOBAL_GET("physics/jolt_physics_3d/simulation/sleep_velocity_threshold");
	sleep_time_threshold = GLOBAL_GET("physics/jolt_physics_3d/simulation/sleep_time_threshold");
	ccd_movement_threshold = GLOBAL_GET("physics/jolt_physics_3d/simulation/continuous_cd_movement_threshold");
	ccd_max_penetration = GLOBAL_GET("physics/jolt_physics_3d/simulation/continuous_cd_max_penetration");
	body_pair_contact_cache_enabled = GLOBAL_GET("physics/jolt_physics_3d/simulation/body_pair_contact_cache_enabled");
	float body_pair_cache_distance = GLOBAL_GET("physics/jolt_physics_3d/simulation/body_pair_contact_cache_distance_threshold");
	body_pair_cache_distance_sq = body_pair_cache_distance * body_pair_cache_distance;
	float body_pair_cache_angle = GLOBAL_GET("physics/jolt_physics_3d/simulation/body_pair_contact_cache_angle_threshold");
	body_pair_cache_angle_cos_div2 = Math::cos(body_pair_cache_angle / 2.0f);

	use_enhanced_internal_edge_removal_for_queries = GLOBAL_GET("physics/jolt_physics_3d/queries/use_enhanced_internal_edge_removal");
	enable_ray_cast_face_index = GLOBAL_GET("physics/jolt_physics_3d/queries/enable_ray_cast_face_index");

	use_enhanced_internal_edge_removal_for_motion_queries = GLOBAL_GET("physics/jolt_physics_3d/motion_queries/use_enhanced_internal_edge_removal");
	motion_query_recovery_iterations = GLOBAL_GET("physics/jolt_physics_3d/motion_queries/recovery_iterations");
	motion_query_recovery_amount = GLOBAL_GET("physics/jolt_physics_3d/motion_queries/recovery_amount");

	collision_margin_fraction = GLOBAL_GET("physics/jolt_physics_3d/collisions/collision_margin_fraction");
	float active_edge_threshold = GLOBAL_GET("physics/jolt_physics_3d/collisions/active_edge_threshold");
	active_edge_threshold_cos = Math::cos(active_edge_threshold);
	friction_combine_mode = CLAMP((int)GLOBAL_GET("physics/jolt_physics_3d/collisions/friction_combine_mode"), 0, 3);
	restitution_combine_mode = CLAMP((int)GLOBAL_GET("physics/jolt_physics_3d/collisions/restitution_combine_mode"), 0, 5);

	joint_world_node = (JoltJointWorldNode)(int)GLOBAL_GET("physics/jolt_physics_3d/joints/world_node");

	temp_memory_mib = GLOBAL_GET("physics/jolt_physics_3d/limits/temporary_memory_buffer_size");
	max_in_flight_body_pairs = CLAMP((int)GLOBAL_GET("physics/jolt_physics_3d/limits/max_in_flight_body_pairs"), 1024, 262144);
	temp_memory_b = (int64_t)temp_memory_mib * 1024 * 1024;
	world_boundary_shape_size = GLOBAL_GET("physics/jolt_physics_3d/limits/world_boundary_shape_size");
	max_linear_velocity = GLOBAL_GET("physics/jolt_physics_3d/limits/max_linear_velocity");
	max_angular_velocity = GLOBAL_GET("physics/jolt_physics_3d/limits/max_angular_velocity");
	max_bodies = GLOBAL_GET("physics/jolt_physics_3d/limits/max_bodies");
	max_body_pairs = GLOBAL_GET("physics/jolt_physics_3d/limits/max_body_pairs");
	max_contact_constraints = GLOBAL_GET("physics/jolt_physics_3d/limits/max_contact_constraints");
}
