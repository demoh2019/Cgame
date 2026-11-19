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
	bool manifold_spread_reduction = false; // Opt-in 3D four-point contact patch selection.

	real_t contact_recycle_radius = 0.0;
	real_t contact_max_separation = 0.0;
	real_t speculative_sphere_distance = 0.0; // Off unless explicitly enabled.
	real_t soft_body_xpbd_compliance = 0.0; // Legacy PBD remains the default.
	real_t soft_body_plastic_yield_strain = 0.1; // Relative elastic yield limit.
	real_t soft_body_plastic_creep_rate = 0.0; // 1/second; 0 keeps elastic behavior.
	real_t soft_body_link_damping = 0.0; // Optional longitudinal dashpot rate, 1/s.
	real_t soft_body_lift_coefficient = 0.0; // Two-sided aerodynamic cloth lift, opt-in.
	real_t soft_body_xpbd_area_compliance = 0.0;
	real_t soft_body_xpbd_shear_compliance = 0.0; // Opt-in angular shear preservation.
	real_t soft_body_xpbd_dihedral_compliance = 0.0; // Opt-in angle-based cloth bending.
	real_t soft_body_dihedral_damping = 0.0; // Opt-in angular dashpot rate, 1/s.
	real_t soft_body_bending_plastic_yield_angle = 0.2; // Elastic angular tolerance, radians.
	real_t soft_body_bending_plastic_creep_rate = 0.0; // 1/s; no plastic folds by default.
	real_t soft_body_self_collision_thickness = 0.0; // 0: no self-contact work or buffers.
	real_t soft_body_self_collision_compliance = 0.000001;
	real_t soft_body_self_collision_friction = 0.0; // Optional mass-weighted face slip resistance.
	int soft_body_self_collision_max_contacts_per_vertex = 8;
	bool soft_body_self_collision_edge_edge = false; // Separate opt-in edge BVH.
	bool soft_body_self_collision_ccd = false; // Swept vertex/face, off by default.
	real_t soft_body_xpbd_tether_compliance = 0.0; // Zero bypasses tether setup and solver.
	real_t soft_body_xpbd_tether_slack = 0.05; // Opt-in triangle area preservation.
	real_t soft_body_xpbd_volume_compliance = 0.0; // Opt-in enclosed volume preservation.
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
	// Advanced, opt-in flat water plane: displacement per partly submerged shape.
	bool fluid_plane_enabled = false;
	real_t fluid_plane_surface_height = 0.0;
	real_t fluid_plane_density = 1000.0;
	real_t fluid_plane_drag_coefficient = 0.8;
	real_t fluid_plane_angular_drag = 0.1;
	Vector3 fluid_plane_flow_velocity;
	bool gyroscopic_forces = false; // Jolt-style asymmetric rigid-body rotation; opt-in.
	int gyroscopic_integration_mode = 0; // 0: normalized Euler, 1: implicit midpoint.
	// Bullet-style resistance about and perpendicular to the contact normal.
	real_t rolling_friction = 0.0;
	real_t spinning_friction = 0.0;
	real_t restitution_velocity_threshold = 0.0;
	real_t static_friction_multiplier = 1.0; // PhysX-style stiction; 1 = legacy friction.
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
	_FORCE_INLINE_ bool is_manifold_spread_reduction_enabled() const { return manifold_spread_reduction; }
	_FORCE_INLINE_ real_t get_contact_recycle_radius() const { return contact_recycle_radius; }
	_FORCE_INLINE_ real_t get_contact_max_separation() const { return contact_max_separation; }
	_FORCE_INLINE_ real_t get_speculative_sphere_distance() const { return speculative_sphere_distance; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_compliance() const { return soft_body_xpbd_compliance; }
	_FORCE_INLINE_ real_t get_soft_body_plastic_yield_strain() const { return soft_body_plastic_yield_strain; }
	_FORCE_INLINE_ real_t get_soft_body_plastic_creep_rate() const { return soft_body_plastic_creep_rate; }
	_FORCE_INLINE_ real_t get_soft_body_link_damping() const { return soft_body_link_damping; }
	_FORCE_INLINE_ real_t get_soft_body_lift_coefficient() const { return soft_body_lift_coefficient; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_area_compliance() const { return soft_body_xpbd_area_compliance; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_shear_compliance() const { return soft_body_xpbd_shear_compliance; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_dihedral_compliance() const { return soft_body_xpbd_dihedral_compliance; }
	_FORCE_INLINE_ real_t get_soft_body_dihedral_damping() const { return soft_body_dihedral_damping; }
	_FORCE_INLINE_ real_t get_soft_body_bending_plastic_yield_angle() const { return soft_body_bending_plastic_yield_angle; }
	_FORCE_INLINE_ real_t get_soft_body_bending_plastic_creep_rate() const { return soft_body_bending_plastic_creep_rate; }
	_FORCE_INLINE_ real_t get_soft_body_self_collision_thickness() const { return soft_body_self_collision_thickness; }
	_FORCE_INLINE_ real_t get_soft_body_self_collision_compliance() const { return soft_body_self_collision_compliance; }
	_FORCE_INLINE_ real_t get_soft_body_self_collision_friction() const { return soft_body_self_collision_friction; }
	_FORCE_INLINE_ int get_soft_body_self_collision_max_contacts_per_vertex() const { return soft_body_self_collision_max_contacts_per_vertex; }
	_FORCE_INLINE_ bool is_soft_body_self_collision_edge_edge_enabled() const { return soft_body_self_collision_edge_edge; }
	_FORCE_INLINE_ bool is_soft_body_self_collision_ccd_enabled() const { return soft_body_self_collision_ccd; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_tether_compliance() const { return soft_body_xpbd_tether_compliance; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_tether_slack() const { return soft_body_xpbd_tether_slack; }
	_FORCE_INLINE_ real_t get_soft_body_xpbd_volume_compliance() const { return soft_body_xpbd_volume_compliance; }
	_FORCE_INLINE_ real_t get_contact_max_allowed_penetration() const { return contact_max_allowed_penetration; }
	_FORCE_INLINE_ real_t get_contact_bias() const { return contact_bias; }
	_FORCE_INLINE_ real_t limit_contact_bias(real_t p_bias) const { return godot_physics_limit_contact_bias(p_bias, max_contact_push_speed); }
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
	_FORCE_INLINE_ bool is_fluid_plane_enabled() const { return fluid_plane_enabled; }
	_FORCE_INLINE_ real_t get_fluid_plane_surface_height() const { return fluid_plane_surface_height; }
	_FORCE_INLINE_ real_t get_fluid_plane_density() const { return fluid_plane_density; }
	_FORCE_INLINE_ real_t get_fluid_plane_drag_coefficient() const { return fluid_plane_drag_coefficient; }
	_FORCE_INLINE_ real_t get_fluid_plane_angular_drag() const { return fluid_plane_angular_drag; }
	_FORCE_INLINE_ const Vector3 &get_fluid_plane_flow_velocity() const { return fluid_plane_flow_velocity; }
	_FORCE_INLINE_ bool are_gyroscopic_forces_enabled() const { return gyroscopic_forces; }
	_FORCE_INLINE_ int get_gyroscopic_integration_mode() const { return gyroscopic_integration_mode; }
	_FORCE_INLINE_ real_t get_rolling_friction() const { return rolling_friction; }
	_FORCE_INLINE_ real_t get_static_friction_multiplier() const { return static_friction_multiplier; }
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
