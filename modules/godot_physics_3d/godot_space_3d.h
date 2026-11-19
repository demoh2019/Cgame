/**************************************************************************/
/*  godot_space_3d.h                                                      */
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

#include "godot_area_3d.h"
#include "godot_area_pair_3d.h"
#include "godot_body_3d.h"
#include "godot_body_pair_3d.h"
#include "godot_broad_phase_3d.h"
#include "godot_collision_object_3d.h"
#include "godot_soft_body_3d.h"

#include "core/typedefs.h"
#include "servers/physics_contact_push_speed.h"
#include "servers/physics_friction_combine.h"
#include "servers/physics_restitution_combine.h"
#include "servers/physics_3d/direct_states/physics_direct_space_state_3d.h"

class GodotPhysicsDirectSpaceState3D : public PhysicsDirectSpaceState3D {
	GDCLASS(GodotPhysicsDirectSpaceState3D, PhysicsDirectSpaceState3D);

public:
	GodotSpace3D *space = nullptr;

	virtual int intersect_point(const PS3DT::PointParameters &p_parameters, PS3DT::ShapeResult *r_results, int p_result_max) override;
	virtual bool intersect_ray(const PS3DT::RayParameters &p_parameters, PS3DT::RayResult &r_result) override;
	virtual int intersect_shape(const PS3DT::ShapeParameters &p_parameters, PS3DT::ShapeResult *r_results, int p_result_max) override;
	virtual bool cast_motion(const PS3DT::ShapeParameters &p_parameters, real_t &p_closest_safe, real_t &p_closest_unsafe, PS3DT::ShapeRestInfo *r_info = nullptr) override;
	virtual bool collide_shape(const PS3DT::ShapeParameters &p_parameters, Vector3 *r_results, int p_result_max, int &r_result_count) override;
	virtual bool rest_info(const PS3DT::ShapeParameters &p_parameters, PS3DT::ShapeRestInfo *r_info) override;
	virtual Vector3 get_closest_point_to_object_volume(RID p_object, const Vector3 p_point) const override;

	GodotPhysicsDirectSpaceState3D();
};

class GodotSpace3D {
public:
	enum ElapsedTime {
		ELAPSED_TIME_INTEGRATE_FORCES,
		ELAPSED_TIME_GENERATE_ISLANDS,
		ELAPSED_TIME_SETUP_CONSTRAINTS,
		ELAPSED_TIME_SOLVE_CONSTRAINTS,
		ELAPSED_TIME_INTEGRATE_VELOCITIES,
		ELAPSED_TIME_MAX

	};

private:
	uint64_t elapsed_time[ELAPSED_TIME_MAX] = {};

	GodotPhysicsDirectSpaceState3D *direct_access = nullptr;
	RID self;

	GodotBroadPhase3D *broadphase = nullptr;
	SelfList<GodotBody3D>::List active_list;
	// Bumped whenever a body enters or leaves the active list, so the stepper can
	// reuse one contiguous snapshot of the list instead of re-walking it.
	uint32_t active_list_version = 0;
	// Contiguous copy of the active list, rebuilt lazily when the version changes.
	LocalVector<GodotBody3D *> active_snapshot;
	uint32_t active_snapshot_version = UINT32_MAX;
	SelfList<GodotBody3D>::List mass_properties_update_list;
	SelfList<GodotBody3D>::List state_query_list;
	SelfList<GodotArea3D>::List monitor_query_list;
	SelfList<GodotArea3D>::List area_moved_list;
	SelfList<GodotSoftBody3D>::List active_soft_body_list;

	static void *_broadphase_pair(GodotCollisionObject3D *A, int p_subindex_A, GodotCollisionObject3D *B, int p_subindex_B, void *p_self);
	static void _broadphase_unpair(GodotCollisionObject3D *A, int p_subindex_A, GodotCollisionObject3D *B, int p_subindex_B, void *p_data, void *p_self);

	HashSet<GodotCollisionObject3D *> objects;

	// Broadphase pairs are created and destroyed constantly while bodies move.
	// Pool them per space instead of hitting the general allocator for every
	// pair. Members are destroyed after the destructor body, so the pools
	// outlive the broadphase that releases the remaining pairs. Pages are only
	// allocated on first use, so unused pair kinds cost no memory.
	enum {
		PAIR_POOL_PAGE_SIZE = 256,
		SOFT_BODY_PAIR_POOL_PAGE_SIZE = 32,
	};
	PagedAllocator<GodotBodyPair3D, true, PAIR_POOL_PAGE_SIZE> body_pair_pool;
	PagedAllocator<GodotBodySoftBodyPair3D, true, SOFT_BODY_PAIR_POOL_PAGE_SIZE> body_soft_body_pair_pool;
	PagedAllocator<GodotAreaPair3D, true, PAIR_POOL_PAGE_SIZE> area_pair_pool;
	PagedAllocator<GodotAreaSoftBodyPair3D, true, SOFT_BODY_PAIR_POOL_PAGE_SIZE> area_soft_body_pair_pool;
	PagedAllocator<GodotArea2Pair3D, true, PAIR_POOL_PAGE_SIZE> area2_pair_pool;

	GodotArea3D *area = nullptr;

	int solver_iterations = 0;
	bool block_solver_enabled = false;
	bool parallel_large_islands = false;
	// Sub-stepping: one physics tick is simulated as `substeps` consecutive steps of `full_step / substeps`.
	int substeps = 1;
	int substep_index = 0;
	real_t full_step = 0.0;
	bool manifold_spread_reduction = false; // Opt-in 3D four-point contact patch selection.

	real_t contact_recycle_radius = 0.0;
	real_t contact_max_separation = 0.0;
	real_t air_density = 1.225;
	real_t speculative_sphere_distance = 0.0; // Off unless explicitly enabled.
	real_t soft_body_xpbd_strain_max_stretch_ratio = 0.0; // 0 disables upper limit; >=1 clamps stretch.
	real_t soft_body_xpbd_strain_min_compression_ratio = 0.0; // 0 disables lower limit; 0..1.
	real_t soft_body_xpbd_strain_limit_compliance = 0.0; // 0: hard unilateral constraints.
	real_t soft_body_xpbd_compliance = 0.0; // Legacy PBD remains the default.
	real_t soft_body_xpbd_parallel_compliance_ratio = 1.0; // 1: isotropic; <1: stiffer along local fiber.
	Vector3 soft_body_xpbd_material_axis = Vector3(1, 0, 0); // Undeformed mesh-local fiber axis.
	real_t soft_body_xpbd_tension_hardening = 0.0; // Opt-in nonlinear tensile response.
	real_t soft_body_xpbd_compression_hardening = 0.0; // Opt-in compression stiffening for foams.
	real_t soft_body_xpbd_tension_yield_strain = 0.1;
	real_t soft_body_xpbd_compression_yield_strain = 0.1;
	real_t soft_body_fatigue_damage_rate = 0.0; // Zero disables irreversible softening.
	real_t soft_body_fatigue_yield_strain = 0.3;
	real_t soft_body_fatigue_max_damage = 0.9; // 0..0.99: finite positive stiffness.
	real_t soft_body_plastic_yield_strain = 0.1; // Relative elastic yield limit.
	real_t soft_body_plastic_creep_rate = 0.0; // 1/second; 0 keeps elastic behavior.
	real_t soft_body_link_damping = 0.0; // Optional longitudinal dashpot rate, 1/s.
	real_t soft_body_thermal_conduction_rate = 0.0;
	real_t soft_body_thermal_ambient_exchange_rate = 0.0;
	real_t soft_body_thermal_ambient_temperature = 20.0;
	real_t soft_body_thermal_source_rate = 0.0;
	real_t soft_body_thermal_source_temperature = 100.0;
	Vector3 soft_body_thermal_source_center;
	real_t soft_body_thermal_source_radius = 0.0;
	real_t soft_body_thermal_expansion_coefficient = 0.0;
	real_t soft_body_strain_rate_damping = 0.0; // Optional rate-sensitive longitudinal damping.
	real_t soft_body_strain_rate_yield = 0.0; // Minimum relative link strain rate [1/s].
	real_t soft_body_lift_coefficient = 0.0; // Two-sided aerodynamic cloth lift, opt-in.
	real_t soft_body_gas_pressure_gamma = 0.0; // 0: legacy pressure, >0: sealed gas EOS.
	real_t soft_body_gas_leak_rate = 0.0; // Optional pressure-driven gas loss, 1/s.
	bool soft_body_hydrostatic_pressure = false; // Opt-in hydrostatic loading on closed meshes.
	bool soft_body_hydrodynamic_drag = false; // Opt-in immersed drag on open or closed SoftBody3D surfaces.
	real_t soft_body_hydrodynamic_tangent_ratio = 0.25; // Fraction of normal drag in tangential direction.
	real_t soft_body_tangential_drag_ratio = 0.0; // Optional skin friction on cloth faces.
	real_t soft_body_xpbd_area_compliance = 0.0;
	real_t soft_body_xpbd_membrane_compliance = 0.0; // Optional StVK surface membrane energy.
	real_t soft_body_membrane_poisson_ratio = 0.3; // Plane-stress Poisson coupling.
	real_t soft_body_membrane_damping_rate = 0.0; // Objective viscoelastic strain-rate relaxation, 1/s.
	real_t soft_body_tetra_fem_compliance = 0.0; // Disabled by default.
	bool soft_body_tetra_fem_lumped_mass = false; // Opt-in volume-weighted vertex masses.
	real_t soft_body_tetra_fem_poisson_ratio = 0.3;
	real_t soft_body_tetra_principal_min_stretch = 0.0; // 0: no min singular cap.
	real_t soft_body_tetra_principal_max_stretch = 0.0; // 0: no max singular cap.
	real_t soft_body_tetra_principal_limit_compliance = 0.0; // 0: hard cap.
	int soft_body_tetra_fem_material_model = 0; // 0 Neo-Hookean, 1 Mooney-Rivlin, 2 Ogden.
	real_t soft_body_tetra_ogden_exponent = 3.0; // 1..8, nonlinear principal stretch power.
	real_t soft_body_tetra_mooney_rivlin_fraction = 0.5;
	real_t soft_body_tetra_fiber_compliance = 0.0; // 0: no FEM directional reinforcement.
	Vector3 soft_body_tetra_fiber_axis = Vector3(1, 0, 0); // Undeformed material direction.
	// A second, independent tension-only material fiber family. Its zero
	// compliance disables all extra FEM constraints and persistent memory.
	real_t soft_body_tetra_fiber_secondary_compliance = 0.0;
	Vector3 soft_body_tetra_fiber_secondary_axis = Vector3(0, 1, 0);
	// One-sided plastic rest stretch, off unless creep rate >0.
	real_t soft_body_tetra_fiber_plastic_yield_ratio = 0.15;
	real_t soft_body_tetra_fiber_plastic_creep_rate = 0.0;
	real_t soft_body_tetra_fiber_plastic_max_stretch = 3.0;
	// Secondary family can yield/plastically extend independently of primary.
	real_t soft_body_tetra_fiber_secondary_plastic_yield_ratio = 0.15;
	real_t soft_body_tetra_fiber_secondary_plastic_creep_rate = 0.0;
	real_t soft_body_tetra_fiber_secondary_plastic_max_stretch = 3.0;
	real_t soft_body_tetra_fem_viscosity = 0.0; // Objective Kelvin-Voigt material damping.
	real_t soft_body_tetra_sls_compliance = 0.0; // Zener/Maxwell branch is disabled by default.
	real_t soft_body_tetra_sls_relaxation_time = 0.25; // SLS material memory timescale, seconds.
	real_t soft_body_tetra_prony_fast_compliance = 0.0; // Disable fast arm by default.
	real_t soft_body_tetra_prony_fast_relaxation_time = 0.04;
	real_t soft_body_tetra_prony_slow_compliance = 0.0; // Disable slow arm by default.
	real_t soft_body_tetra_prony_slow_relaxation_time = 2.0;
	real_t soft_body_tetra_volume_plastic_rate = 0.0; // 1/s, opt-in per-tet isotropic plastic rest deformation.
	real_t soft_body_tetra_volume_plastic_yield = 0.15; // Elastic volume strain window in |ln(J)|.
	real_t soft_body_tetra_shear_plastic_rate = 0.0; // 1/s, opt-in J2-like deviatoric rest creep.
	real_t soft_body_tetra_shear_plastic_yield = 0.2; // Equivalent deviatoric Hencky strain threshold.
	real_t soft_body_tetra_shear_plastic_hardening = 0.0; // H=0 preserves old plasticity.
	real_t soft_body_tetra_shear_plastic_max_strain = 2.0; // Cumulative per-tetra plastic strain budget.
	bool soft_body_tetra_inversion_recovery = false; // Recover inverted/collapsed FEM tetrahedra, opt-in.
	real_t soft_body_tetra_inversion_min_j = 0.05; // Minimum positive det(F) after recovery.
	real_t soft_body_tetra_damage_yield_strain = 0.25;
	real_t soft_body_tetra_damage_rate = 0.0;
	// Signed principal-log-strain cycle fatigue (Miner-like), disabled unless
	// fatigue_reference_cycles > 0.0. Uses the shared FEM scalar damage D.
	real_t soft_body_tetra_fatigue_endurance_amplitude = 0.05;
	real_t soft_body_tetra_fatigue_reference_amplitude = 0.3;
	real_t soft_body_tetra_fatigue_reference_cycles = 0.0;
	real_t soft_body_tetra_fatigue_exponent = 3.0;
	real_t soft_body_tetra_fatigue_reversal_deadband = 0.002;
	real_t soft_body_xpbd_shear_compliance = 0.0; // Opt-in angular shear preservation.
	real_t soft_body_xpbd_dihedral_compliance = 0.0; // Opt-in angle-based cloth bending.
	// Optional 3-particle discrete rod centerline curvature on nearly aligned
	// structural mesh-edge chains. Not a Cosserat rod twist/director solver.
	real_t soft_body_xpbd_rod_bend_compliance = 0.0;
	// Geometric torsion between adjacent curved centerline segments (not material twist).
	real_t soft_body_xpbd_rod_torsion_compliance = 0.0;
	real_t soft_body_xpbd_rod_straightness = 0.9;
	real_t soft_body_xpbd_bend_parallel_compliance_ratio = 1.0; // Directional bend about a rest-mesh fiber axis.
	real_t soft_body_shape_matching_stiffness = 0.0; // Optional global shape recovery.
	int soft_body_shape_matching_cluster_size = 0; // 0 global; 3..64 local BFS cores.
	real_t soft_body_dihedral_damping = 0.0; // Opt-in angular dashpot rate, 1/s.
	real_t soft_body_area_rate_damping = 0.0; // Opt-in in-plane area strain-rate dissipation, 1/s.
	real_t soft_body_bending_plastic_yield_angle = 0.2; // Elastic angular tolerance, radians.
	real_t soft_body_bending_plastic_creep_rate = 0.0; // 1/s; no plastic folds by default.
	real_t soft_body_self_collision_thickness = 0.0; // 0: no self-contact work or buffers.
	real_t soft_body_self_collision_compliance = 0.000001;
	real_t soft_body_self_collision_friction = 0.0; // Optional mass-weighted face slip resistance.
	int soft_body_self_collision_max_contacts_per_vertex = 8;
	bool soft_body_self_collision_edge_edge = false; // Separate opt-in edge BVH.
	bool soft_body_self_collision_ccd = false; // Swept vertex/face, off by default.
	// Bullet-style discrete vertex/triangle contacts between separate soft bodies.
	real_t soft_body_pair_collision_thickness = 0.0; // Disabled by default.
	real_t soft_body_pair_collision_compliance = 0.000001;
	real_t soft_body_pair_collision_friction = 0.0; // Tangential Coulomb impulse, opt-in.
	bool soft_body_pair_collision_ccd = false; // Optional swept pair contacts.
	bool soft_body_pair_collision_edge_edge = false; // Opt-in inter-body structural edge pairs.
	bool soft_body_pair_collision_edge_ccd = false; // Extra conservative swept edge/edge TOI.
	int soft_body_pair_max_contacts = 256; // Per pair, temporary bounded scratch.
	int soft_body_pair_max_pairs = 128; // Candidate body-pairs per step.
	real_t soft_body_xpbd_tether_compliance = 0.0; // Zero bypasses tether setup and solver.
	real_t soft_body_xpbd_tether_slack = 0.05; // Opt-in triangle area preservation.
	real_t soft_body_xpbd_volume_compliance = 0.0; // Opt-in enclosed volume preservation.
	real_t soft_body_shape_matching_rate = 0.0; // Global corotational shape-memory rate, 1/s.
	real_t soft_body_volume_damping_rate = 0.0; // 1/s, opt-in global bulk viscosity.
	real_t soft_body_volume_plastic_yield_strain = 0.15; // Relative volume strain threshold.
	real_t soft_body_volume_plastic_creep_rate = 0.0; // 1/s, 0 disables permanent volumetric deformation.
	real_t contact_max_allowed_penetration = 0.0;
	real_t contact_bias = 0.0;
	real_t max_contact_push_speed = 0.0; // 0: unlimited (legacy behavior).
	real_t max_linear_velocity = 0.0; // Opt-in rigid speed limit, 0 disables.
	real_t max_angular_velocity = 0.0; // Opt-in angular speed limit, rad/s; 0 disables.
	real_t ccd_max_angular_motion = 0.0; // Opt-in maximum CCD rotation per physics step, radians.
	real_t warm_start_coefficient = 1.0;
	bool ccd_rotational_bounds = false; // Optional conservative angular sweep broadphase.
	bool ccd_tight_rotational_bounds = false; // Analytical swept arc AABB; opt-in.
	bool implicit_damping = false; // Box2D-style time-step-stable damping; disabled by default.
	real_t fluid_linear_drag = 0.0; // Uniform-medium quadratic drag per unit mass.
	real_t fluid_angular_drag = 0.0; // Uniform-medium quadratic angular resistance.
	real_t fluid_buoyancy = 0.0; // 0 = off; 1 = neutral in the fully submerged model.
	Vector3 fluid_flow_velocity; // Constant ambient current or wind, in world space.
	real_t sphere_magnus_spin_coefficient = 0.0; // Off by default.
	real_t sphere_magnus_medium_density = 1.225; // Air density kg/m^3.
	real_t sphere_magnus_max_lift_coefficient = 1.5;
	Vector3 sphere_magnus_flow_velocity; // Magnus medium velocity, world space.
	real_t rigid_box_aero_pressure_coefficient = 0.0; // 0: off, pressure on windward faces.
	real_t rigid_box_aero_skin_coefficient = 0.0; // 0: off, tangential quadratic drag.
	real_t rigid_box_aero_density = 1.225; // Air density, kg/m^3.
	Vector3 rigid_box_aero_wind_velocity; // Wind in world-space m/s.
	real_t rigid_convex_aero_pressure_coefficient = 0.0; // Windward polygon pressure.
	real_t rigid_convex_aero_skin_coefficient = 0.0; // Tangential polygon drag.
	real_t rigid_convex_aero_density = 1.225; // Approximate air density, kg/m^3.
	Vector3 rigid_convex_aero_wind_velocity; // World-space airflow, m/s.
	// Advanced, opt-in flat water plane: displacement per partly submerged shape.
	bool fluid_plane_enabled = false;
	real_t fluid_plane_surface_height = 0.0;
	real_t fluid_plane_density = 1000.0;
	real_t fluid_plane_drag_coefficient = 0.8;
	real_t fluid_plane_angular_drag = 0.1;
	Vector3 fluid_plane_flow_velocity;
	bool gyroscopic_forces = false; // Jolt-style asymmetric rigid-body rotation; opt-in.
	bool rotating_frame_enabled = false; // Translational rotating reference frame, opt-in.
	Vector3 rotating_frame_origin; // Frame rotation center in simulation/world coordinates.
	Vector3 rotating_frame_angular_velocity; // Frame omega, rad/s.
	Vector3 rotating_frame_angular_acceleration; // Instantaneous omega derivative, rad/s^2.
	int gyroscopic_integration_mode = 0; // 0: normalized Euler, 1: implicit midpoint.
	// Bullet-style resistance about and perpendicular to the contact normal.
	real_t rolling_friction = 0.0;
	real_t spinning_friction = 0.0;
	real_t restitution_velocity_threshold = 0.0;
	real_t static_friction_multiplier = 1.0; // PhysX-style stiction; 1 = legacy friction.
	real_t stribeck_transition_velocity = 0.0; // 0 = legacy, >0 enables velocity weakening (m/s).
	real_t friction_anisotropy_ratio = 1.0; // 1: isotropic legacy; <1 weakens transverse axis.
	Vector3 friction_anisotropy_axis = Vector3(1, 0, 0); // Preferred world-space tangent direction.
	int friction_combine_mode = 0; // 0: legacy, 1: geometric, 2: average, 3: maximum
	int restitution_combine_mode = 0; // 0: legacy sum, 1: max, 2: average, 3: min, 4: multiply, 5: geometric


	real_t body_linear_velocity_sleep_threshold = 0.0;
	real_t body_angular_velocity_sleep_threshold = 0.0;
	real_t body_time_to_sleep = 0.0;

	bool locked = false;

	real_t last_step = 0.001;
	real_t previous_step = 0.0; // Last physics delta, shared by all contact pairs.

	int island_count = 0;
	int active_objects = 0;
	int collision_pairs = 0;

	RID static_global_body;

	Vector<Vector3> contact_debug;
	int contact_debug_count = 0;

	friend class GodotPhysicsDirectSpaceState3D;

	template <typename Visitor>
	void _visit_motion_candidates(GodotBody3D *p_body, const AABB &p_aabb, const PS3DT::MotionParameters &p_parameters, const Visitor &p_callback);

public:
	_FORCE_INLINE_ void set_self(const RID &p_self) { self = p_self; }
	_FORCE_INLINE_ RID get_self() const { return self; }

	void set_default_area(GodotArea3D *p_area) { area = p_area; }
	GodotArea3D *get_default_area() const { return area; }

	const SelfList<GodotBody3D>::List &get_active_body_list() const;
	_FORCE_INLINE_ uint32_t get_active_list_version() const { return active_list_version; }
	// Pointer snapshot of the active bodies; avoids walking the intrusive list (a serial
	// chain of cache misses on huge scenes) when membership did not change.
	const LocalVector<GodotBody3D *> &get_active_bodies();
	void body_add_to_active_list(SelfList<GodotBody3D> *p_body);
	void body_remove_from_active_list(SelfList<GodotBody3D> *p_body);
	void body_add_to_mass_properties_update_list(SelfList<GodotBody3D> *p_body);
	void body_remove_from_mass_properties_update_list(SelfList<GodotBody3D> *p_body);

	void body_add_to_state_query_list(SelfList<GodotBody3D> *p_body);
	void body_remove_from_state_query_list(SelfList<GodotBody3D> *p_body);

	void area_add_to_monitor_query_list(SelfList<GodotArea3D> *p_area);
	void area_remove_from_monitor_query_list(SelfList<GodotArea3D> *p_area);
	void area_add_to_moved_list(SelfList<GodotArea3D> *p_area);
	void area_remove_from_moved_list(SelfList<GodotArea3D> *p_area);
	const SelfList<GodotArea3D>::List &get_moved_area_list() const;

	const SelfList<GodotSoftBody3D>::List &get_active_soft_body_list() const;
	void soft_body_add_to_active_list(SelfList<GodotSoftBody3D> *p_soft_body);
	void soft_body_remove_from_active_list(SelfList<GodotSoftBody3D> *p_soft_body);

	GodotBroadPhase3D *get_broadphase();

	void add_object(GodotCollisionObject3D *p_object);
	void remove_object(GodotCollisionObject3D *p_object);
	const HashSet<GodotCollisionObject3D *> &get_objects() const;

	_FORCE_INLINE_ int get_solver_iterations() const { return solver_iterations; }
	_FORCE_INLINE_ bool is_block_solver_enabled() const { return block_solver_enabled; }
	_FORCE_INLINE_ bool is_parallel_large_islands_enabled() const { return parallel_large_islands; }
	_FORCE_INLINE_ int get_substeps() const { return substeps; }
	_FORCE_INLINE_ bool is_first_substep() const { return substep_index == 0; }
	_FORCE_INLINE_ bool is_final_substep() const { return substep_index + 1 >= substeps; }
	_FORCE_INLINE_ int get_substep_index() const { return substep_index; }
	// Duration of the whole physics tick, as seen by users (PhysicsDirectBodyState3D.get_step()).
	_FORCE_INLINE_ real_t get_full_step() const { return full_step > 0.0 ? full_step : last_step; }
	_FORCE_INLINE_ void begin_substep(int p_index, real_t p_full_step) {
		substep_index = p_index;
		full_step = p_full_step;
	}
	_FORCE_INLINE_ bool is_manifold_spread_reduction_enabled() const { return manifold_spread_reduction; }
	_FORCE_INLINE_ real_t get_contact_recycle_radius() const { return contact_recycle_radius; }
	_FORCE_INLINE_ real_t get_contact_max_separation() const { return contact_max_separation; }
	_FORCE_INLINE_ real_t get_air_density() const { return air_density; }
	_FORCE_INLINE_ real_t get_speculative_sphere_distance() const { return speculative_sphere_distance; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_strain_max_stretch_ratio() const { return soft_body_xpbd_strain_max_stretch_ratio; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_strain_min_compression_ratio() const { return soft_body_xpbd_strain_min_compression_ratio; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_strain_limit_compliance() const { return soft_body_xpbd_strain_limit_compliance; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_compliance() const { return soft_body_xpbd_compliance; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_parallel_compliance_ratio() const { return soft_body_xpbd_parallel_compliance_ratio; }
	_FORCE_INLINE_ const Vector3 &get_soft_body_xpbd_material_axis() const { return soft_body_xpbd_material_axis; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_tension_hardening() const { return soft_body_xpbd_tension_hardening; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_compression_hardening() const { return soft_body_xpbd_compression_hardening; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_tension_yield_strain() const { return soft_body_xpbd_tension_yield_strain; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_compression_yield_strain() const { return soft_body_xpbd_compression_yield_strain; }
	_FORCE_INLINE_ real_t get_soft_body_fatigue_damage_rate() const { return soft_body_fatigue_damage_rate; }
	_FORCE_INLINE_ real_t get_soft_body_fatigue_yield_strain() const { return soft_body_fatigue_yield_strain; }
	_FORCE_INLINE_ real_t get_soft_body_fatigue_max_damage() const { return soft_body_fatigue_max_damage; }
	_FORCE_INLINE_ real_t get_soft_body_plastic_yield_strain() const { return soft_body_plastic_yield_strain; }
	_FORCE_INLINE_ real_t get_soft_body_plastic_creep_rate() const { return soft_body_plastic_creep_rate; }
	_FORCE_INLINE_ real_t get_soft_body_link_damping() const { return soft_body_link_damping; }
	_FORCE_INLINE_ real_t get_soft_body_thermal_conduction_rate() const { return soft_body_thermal_conduction_rate; }
	_FORCE_INLINE_ real_t get_soft_body_thermal_ambient_exchange_rate() const { return soft_body_thermal_ambient_exchange_rate; }
	_FORCE_INLINE_ real_t get_soft_body_thermal_ambient_temperature() const { return soft_body_thermal_ambient_temperature; }
	_FORCE_INLINE_ real_t get_soft_body_thermal_source_rate() const { return soft_body_thermal_source_rate; }
	_FORCE_INLINE_ real_t get_soft_body_thermal_source_temperature() const { return soft_body_thermal_source_temperature; }
	_FORCE_INLINE_ const Vector3 &get_soft_body_thermal_source_center() const { return soft_body_thermal_source_center; }
	_FORCE_INLINE_ real_t get_soft_body_thermal_source_radius() const { return soft_body_thermal_source_radius; }
	_FORCE_INLINE_ real_t get_soft_body_thermal_expansion_coefficient() const { return soft_body_thermal_expansion_coefficient; }
	_FORCE_INLINE_ real_t get_soft_body_strain_rate_damping() const { return soft_body_strain_rate_damping; }
	_FORCE_INLINE_ real_t get_soft_body_strain_rate_yield() const { return soft_body_strain_rate_yield; }
	_FORCE_INLINE_ real_t get_soft_body_lift_coefficient() const { return soft_body_lift_coefficient; }
	_FORCE_INLINE_ real_t get_soft_body_gas_pressure_gamma() const { return soft_body_gas_pressure_gamma; }
	_FORCE_INLINE_ real_t get_soft_body_gas_leak_rate() const { return soft_body_gas_leak_rate; }
	_FORCE_INLINE_ bool is_soft_body_hydrostatic_pressure_enabled() const { return soft_body_hydrostatic_pressure; }
	_FORCE_INLINE_ bool is_soft_body_hydrodynamic_drag_enabled() const { return soft_body_hydrodynamic_drag; }
	_FORCE_INLINE_ real_t get_soft_body_hydrodynamic_tangent_ratio() const { return soft_body_hydrodynamic_tangent_ratio; }
	_FORCE_INLINE_ real_t get_soft_body_tangential_drag_ratio() const { return soft_body_tangential_drag_ratio; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_area_compliance() const { return soft_body_xpbd_area_compliance; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_membrane_compliance() const { return soft_body_xpbd_membrane_compliance; }
	_FORCE_INLINE_ real_t get_soft_body_membrane_poisson_ratio() const { return soft_body_membrane_poisson_ratio; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_fem_compliance() const { return soft_body_tetra_fem_compliance; }
	_FORCE_INLINE_ bool get_soft_body_tetra_fem_lumped_mass() const { return soft_body_tetra_fem_lumped_mass; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_fem_poisson_ratio() const { return soft_body_tetra_fem_poisson_ratio; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_principal_min_stretch() const { return soft_body_tetra_principal_min_stretch; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_principal_max_stretch() const { return soft_body_tetra_principal_max_stretch; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_principal_limit_compliance() const { return soft_body_tetra_principal_limit_compliance; }
	_FORCE_INLINE_ int get_soft_body_tetra_fem_material_model() const { return soft_body_tetra_fem_material_model; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_ogden_exponent() const { return soft_body_tetra_ogden_exponent; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_mooney_rivlin_fraction() const { return soft_body_tetra_mooney_rivlin_fraction; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_fiber_compliance() const { return soft_body_tetra_fiber_compliance; }
	_FORCE_INLINE_ const Vector3 &get_soft_body_tetra_fiber_axis() const { return soft_body_tetra_fiber_axis; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_fiber_secondary_compliance() const { return soft_body_tetra_fiber_secondary_compliance; }
	_FORCE_INLINE_ const Vector3 &get_soft_body_tetra_fiber_secondary_axis() const { return soft_body_tetra_fiber_secondary_axis; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_fiber_plastic_yield_ratio() const { return soft_body_tetra_fiber_plastic_yield_ratio; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_fiber_plastic_creep_rate() const { return soft_body_tetra_fiber_plastic_creep_rate; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_fiber_plastic_max_stretch() const { return soft_body_tetra_fiber_plastic_max_stretch; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_fiber_secondary_plastic_yield_ratio() const { return soft_body_tetra_fiber_secondary_plastic_yield_ratio; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_fiber_secondary_plastic_creep_rate() const { return soft_body_tetra_fiber_secondary_plastic_creep_rate; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_fiber_secondary_plastic_max_stretch() const { return soft_body_tetra_fiber_secondary_plastic_max_stretch; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_fem_viscosity() const { return soft_body_tetra_fem_viscosity; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_sls_compliance() const { return soft_body_tetra_sls_compliance; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_sls_relaxation_time() const { return soft_body_tetra_sls_relaxation_time; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_prony_fast_compliance() const { return soft_body_tetra_prony_fast_compliance; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_prony_fast_relaxation_time() const { return soft_body_tetra_prony_fast_relaxation_time; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_prony_slow_compliance() const { return soft_body_tetra_prony_slow_compliance; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_prony_slow_relaxation_time() const { return soft_body_tetra_prony_slow_relaxation_time; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_volume_plastic_rate() const { return soft_body_tetra_volume_plastic_rate; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_volume_plastic_yield() const { return soft_body_tetra_volume_plastic_yield; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_shear_plastic_rate() const { return soft_body_tetra_shear_plastic_rate; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_shear_plastic_yield() const { return soft_body_tetra_shear_plastic_yield; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_shear_plastic_hardening() const { return soft_body_tetra_shear_plastic_hardening; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_shear_plastic_max_strain() const { return soft_body_tetra_shear_plastic_max_strain; }
	_FORCE_INLINE_ bool is_soft_body_tetra_inversion_recovery_enabled() const { return soft_body_tetra_inversion_recovery; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_inversion_min_j() const { return soft_body_tetra_inversion_min_j; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_damage_rate() const { return soft_body_tetra_damage_rate; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_fatigue_endurance_amplitude() const { return soft_body_tetra_fatigue_endurance_amplitude; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_fatigue_reference_amplitude() const { return soft_body_tetra_fatigue_reference_amplitude; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_fatigue_reference_cycles() const { return soft_body_tetra_fatigue_reference_cycles; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_fatigue_exponent() const { return soft_body_tetra_fatigue_exponent; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_fatigue_reversal_deadband() const { return soft_body_tetra_fatigue_reversal_deadband; }
	_FORCE_INLINE_ real_t get_soft_body_tetra_damage_yield_strain() const { return soft_body_tetra_damage_yield_strain; }
	_FORCE_INLINE_ real_t get_soft_body_membrane_damping_rate() const { return soft_body_membrane_damping_rate; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_shear_compliance() const { return soft_body_xpbd_shear_compliance; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_dihedral_compliance() const { return soft_body_xpbd_dihedral_compliance; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_rod_bend_compliance() const { return soft_body_xpbd_rod_bend_compliance; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_rod_torsion_compliance() const { return soft_body_xpbd_rod_torsion_compliance; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_rod_straightness() const { return soft_body_xpbd_rod_straightness; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_bend_parallel_compliance_ratio() const { return soft_body_xpbd_bend_parallel_compliance_ratio; }
	_FORCE_INLINE_ real_t get_soft_body_shape_matching_stiffness() const { return soft_body_shape_matching_stiffness; }
	_FORCE_INLINE_ int get_soft_body_shape_matching_cluster_size() const { return soft_body_shape_matching_cluster_size; }
	_FORCE_INLINE_ real_t get_soft_body_dihedral_damping() const { return soft_body_dihedral_damping; }
	_FORCE_INLINE_ real_t get_soft_body_area_rate_damping() const { return soft_body_area_rate_damping; }
	_FORCE_INLINE_ real_t get_soft_body_bending_plastic_yield_angle() const { return soft_body_bending_plastic_yield_angle; }
	_FORCE_INLINE_ real_t get_soft_body_bending_plastic_creep_rate() const { return soft_body_bending_plastic_creep_rate; }
	_FORCE_INLINE_ real_t get_soft_body_self_collision_thickness() const { return soft_body_self_collision_thickness; }
	_FORCE_INLINE_ real_t get_soft_body_self_collision_compliance() const { return soft_body_self_collision_compliance; }
	_FORCE_INLINE_ real_t get_soft_body_self_collision_friction() const { return soft_body_self_collision_friction; }
	_FORCE_INLINE_ int get_soft_body_self_collision_max_contacts_per_vertex() const { return soft_body_self_collision_max_contacts_per_vertex; }
	_FORCE_INLINE_ bool is_soft_body_self_collision_edge_edge_enabled() const { return soft_body_self_collision_edge_edge; }
	_FORCE_INLINE_ bool is_soft_body_self_collision_ccd_enabled() const { return soft_body_self_collision_ccd; }
	_FORCE_INLINE_ real_t get_soft_body_pair_collision_thickness() const { return soft_body_pair_collision_thickness; }
	_FORCE_INLINE_ real_t get_soft_body_pair_collision_compliance() const { return soft_body_pair_collision_compliance; }
	_FORCE_INLINE_ real_t get_soft_body_pair_collision_friction() const { return soft_body_pair_collision_friction; }
	_FORCE_INLINE_ bool is_soft_body_pair_collision_ccd_enabled() const { return soft_body_pair_collision_ccd; }
	_FORCE_INLINE_ bool is_soft_body_pair_collision_edge_edge_enabled() const { return soft_body_pair_collision_edge_edge; }
	_FORCE_INLINE_ bool is_soft_body_pair_collision_edge_ccd_enabled() const { return soft_body_pair_collision_edge_ccd; }
	_FORCE_INLINE_ int get_soft_body_pair_max_contacts() const { return soft_body_pair_max_contacts; }
	_FORCE_INLINE_ int get_soft_body_pair_max_pairs() const { return soft_body_pair_max_pairs; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_tether_compliance() const { return soft_body_xpbd_tether_compliance; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_tether_slack() const { return soft_body_xpbd_tether_slack; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_volume_compliance() const { return soft_body_xpbd_volume_compliance; }
	_FORCE_INLINE_ real_t get_soft_body_shape_matching_rate() const { return soft_body_shape_matching_rate; }
	_FORCE_INLINE_ real_t get_soft_body_volume_damping_rate() const { return soft_body_volume_damping_rate; }
	_FORCE_INLINE_ real_t get_soft_body_volume_plastic_yield_strain() const { return soft_body_volume_plastic_yield_strain; }
	_FORCE_INLINE_ real_t get_soft_body_volume_plastic_creep_rate() const { return soft_body_volume_plastic_creep_rate; }
	_FORCE_INLINE_ real_t get_contact_max_allowed_penetration() const { return contact_max_allowed_penetration; }
	_FORCE_INLINE_ real_t get_contact_bias() const { return contact_bias; }
	_FORCE_INLINE_ real_t limit_contact_bias(real_t p_bias) const { return godot_physics_limit_contact_bias(p_bias, max_contact_push_speed); }
	// Pair override: the smaller of the bodies' own limits, else the space default.
	_FORCE_INLINE_ real_t limit_contact_bias(real_t p_bias, real_t p_speed_a, real_t p_speed_b) const {
		real_t limit = max_contact_push_speed;
		if (p_speed_a > 0.0) {
			limit = p_speed_b > 0.0 ? MIN(p_speed_a, p_speed_b) : p_speed_a;
		} else if (p_speed_b > 0.0) {
			limit = p_speed_b;
		}
		return godot_physics_limit_contact_bias(p_bias, limit);
	}
	_FORCE_INLINE_ real_t get_warm_start_coefficient() const { return warm_start_coefficient; }
	_FORCE_INLINE_ real_t get_max_linear_velocity() const { return max_linear_velocity; }
	_FORCE_INLINE_ real_t get_max_angular_velocity() const { return max_angular_velocity; }
	_FORCE_INLINE_ real_t get_ccd_max_angular_motion() const { return ccd_max_angular_motion; }
	_FORCE_INLINE_ bool is_ccd_rotational_bounds_enabled() const { return ccd_rotational_bounds; }
	_FORCE_INLINE_ bool is_ccd_tight_rotational_bounds_enabled() const { return ccd_tight_rotational_bounds; }
	_FORCE_INLINE_ bool is_implicit_damping_enabled() const { return implicit_damping; }
	_FORCE_INLINE_ real_t get_fluid_linear_drag() const { return fluid_linear_drag; }
	_FORCE_INLINE_ real_t get_fluid_angular_drag() const { return fluid_angular_drag; }
	_FORCE_INLINE_ real_t get_fluid_buoyancy() const { return fluid_buoyancy; }
	_FORCE_INLINE_ const Vector3 &get_fluid_flow_velocity() const { return fluid_flow_velocity; }
	_FORCE_INLINE_ real_t get_sphere_magnus_spin_coefficient() const { return sphere_magnus_spin_coefficient; }
	_FORCE_INLINE_ real_t get_sphere_magnus_medium_density() const { return sphere_magnus_medium_density; }
	_FORCE_INLINE_ real_t get_sphere_magnus_max_lift_coefficient() const { return sphere_magnus_max_lift_coefficient; }
	_FORCE_INLINE_ const Vector3 &get_sphere_magnus_flow_velocity() const { return sphere_magnus_flow_velocity; }
	_FORCE_INLINE_ real_t get_rigid_box_aero_pressure_coefficient() const { return rigid_box_aero_pressure_coefficient; }
	_FORCE_INLINE_ real_t get_rigid_box_aero_skin_coefficient() const { return rigid_box_aero_skin_coefficient; }
	_FORCE_INLINE_ real_t get_rigid_box_aero_density() const { return rigid_box_aero_density; }
	_FORCE_INLINE_ const Vector3 &get_rigid_box_aero_wind_velocity() const { return rigid_box_aero_wind_velocity; }
	_FORCE_INLINE_ real_t get_rigid_convex_aero_pressure_coefficient() const { return rigid_convex_aero_pressure_coefficient; }
	_FORCE_INLINE_ real_t get_rigid_convex_aero_skin_coefficient() const { return rigid_convex_aero_skin_coefficient; }
	_FORCE_INLINE_ real_t get_rigid_convex_aero_density() const { return rigid_convex_aero_density; }
	_FORCE_INLINE_ const Vector3 &get_rigid_convex_aero_wind_velocity() const { return rigid_convex_aero_wind_velocity; }
	_FORCE_INLINE_ bool is_fluid_plane_enabled() const { return fluid_plane_enabled; }
	_FORCE_INLINE_ real_t get_fluid_plane_surface_height() const { return fluid_plane_surface_height; }
	_FORCE_INLINE_ real_t get_fluid_plane_density() const { return fluid_plane_density; }
	_FORCE_INLINE_ real_t get_fluid_plane_drag_coefficient() const { return fluid_plane_drag_coefficient; }
	_FORCE_INLINE_ real_t get_fluid_plane_angular_drag() const { return fluid_plane_angular_drag; }
	_FORCE_INLINE_ const Vector3 &get_fluid_plane_flow_velocity() const { return fluid_plane_flow_velocity; }
	_FORCE_INLINE_ bool are_gyroscopic_forces_enabled() const { return gyroscopic_forces; }
	_FORCE_INLINE_ bool is_rotating_frame_enabled() const { return rotating_frame_enabled; }
	_FORCE_INLINE_ const Vector3 &get_rotating_frame_origin() const { return rotating_frame_origin; }
	_FORCE_INLINE_ const Vector3 &get_rotating_frame_angular_velocity() const { return rotating_frame_angular_velocity; }
	_FORCE_INLINE_ const Vector3 &get_rotating_frame_angular_acceleration() const { return rotating_frame_angular_acceleration; }
	_FORCE_INLINE_ int get_gyroscopic_integration_mode() const { return gyroscopic_integration_mode; }
	_FORCE_INLINE_ real_t get_rolling_friction() const { return rolling_friction; }
	_FORCE_INLINE_ real_t get_static_friction_multiplier() const { return static_friction_multiplier; }
	_FORCE_INLINE_ real_t get_stribeck_transition_velocity() const { return stribeck_transition_velocity; }
	_FORCE_INLINE_ real_t get_friction_anisotropy_ratio() const { return friction_anisotropy_ratio; }
	_FORCE_INLINE_ const Vector3 &get_friction_anisotropy_axis() const { return friction_anisotropy_axis; }
	_FORCE_INLINE_ real_t get_spinning_friction() const { return spinning_friction; }
	_FORCE_INLINE_ real_t get_restitution_velocity_threshold() const { return restitution_velocity_threshold; }
	_FORCE_INLINE_ real_t mix_restitution(real_t p_a, real_t p_b) const { return godot_physics_combine_restitution(p_a, p_b, restitution_combine_mode); }
	// Match Box2D's geometric mean when explicitly selected, while keeping
	// the historical GodotPhysics material combination as the default.
	_FORCE_INLINE_ real_t mix_friction(real_t p_a, real_t p_b) const {
		return godot_physics_combine_friction(p_a, p_b, friction_combine_mode);
	}
	_FORCE_INLINE_ real_t get_body_linear_velocity_sleep_threshold() const { return body_linear_velocity_sleep_threshold; }
	_FORCE_INLINE_ real_t get_body_angular_velocity_sleep_threshold() const { return body_angular_velocity_sleep_threshold; }
	_FORCE_INLINE_ real_t get_body_time_to_sleep() const { return body_time_to_sleep; }

	void update();
	void setup();
	void call_queries();

	bool is_locked() const;
	void lock();
	void unlock();

	real_t get_last_step() const { return last_step; }
	real_t get_previous_step() const { return previous_step; }
	void set_last_step(real_t p_step) {
		previous_step = last_step;
		last_step = p_step;
	}

	void set_param(PS3DE::SpaceParameter p_param, real_t p_value);
	real_t get_param(PS3DE::SpaceParameter p_param) const;

	void set_island_count(int p_island_count) { island_count = p_island_count; }
	int get_island_count() const { return island_count; }

	void set_active_objects(int p_active_objects) { active_objects = p_active_objects; }
	int get_active_objects() const { return active_objects; }

	int get_collision_pairs() const { return collision_pairs; }

	GodotPhysicsDirectSpaceState3D *get_direct_state();

	void set_debug_contacts(int p_amount) { contact_debug.resize(p_amount); }
	_FORCE_INLINE_ bool is_debugging_contacts() const { return !contact_debug.is_empty(); }
	_FORCE_INLINE_ void add_debug_contact(const Vector3 &p_contact) {
		if (contact_debug_count < contact_debug.size()) {
			contact_debug.write[contact_debug_count++] = p_contact;
		}
	}
	_FORCE_INLINE_ Vector<Vector3> get_debug_contacts() { return contact_debug; }
	_FORCE_INLINE_ int get_debug_contact_count() { return contact_debug_count; }

	void set_static_global_body(RID p_body) { static_global_body = p_body; }
	RID get_static_global_body() { return static_global_body; }

	void set_elapsed_time(ElapsedTime p_time, uint64_t p_msec) { elapsed_time[p_time] = p_msec; }
	uint64_t get_elapsed_time(ElapsedTime p_time) const { return elapsed_time[p_time]; }

	bool test_body_motion(GodotBody3D *p_body, const PS3DT::MotionParameters &p_parameters, PS3DT::MotionResult *r_result);

	GodotSpace3D();
	~GodotSpace3D();
};
