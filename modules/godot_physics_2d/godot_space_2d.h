/**************************************************************************/
/*  godot_space_2d.h                                                      */
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

#include "godot_area_2d.h"
#include "godot_area_pair_2d.h"
#include "godot_body_2d.h"
#include "godot_body_pair_2d.h"
#include "godot_broad_phase_2d.h"
#include "godot_collision_object_2d.h"

#include "core/templates/hashfuncs.h"
#include "core/templates/paged_allocator.h"
#include "core/typedefs.h"
#include "servers/physics_contact_push_speed.h"
#include "servers/physics_restitution_combine.h"
#include "servers/physics_2d/direct_states/physics_direct_space_state_2d.h"

class GodotPhysicsDirectSpaceState2D : public PhysicsDirectSpaceState2D {
	GDCLASS(GodotPhysicsDirectSpaceState2D, PhysicsDirectSpaceState2D);

public:
	GodotSpace2D *space = nullptr;

	virtual int intersect_point(const PS2DT::PointParameters &p_parameters, PS2DT::ShapeResult *r_results, int p_result_max) override;
	virtual bool intersect_ray(const PS2DT::RayParameters &p_parameters, PS2DT::RayResult &r_result) override;
	virtual int intersect_shape(const PS2DT::ShapeParameters &p_parameters, PS2DT::ShapeResult *r_results, int p_result_max) override;
	virtual bool cast_motion(const PS2DT::ShapeParameters &p_parameters, real_t &p_closest_safe, real_t &p_closest_unsafe) override;
	virtual bool collide_shape(const PS2DT::ShapeParameters &p_parameters, Vector2 *r_results, int p_result_max, int &r_result_count) override;
	virtual bool rest_info(const PS2DT::ShapeParameters &p_parameters, PS2DT::ShapeRestInfo *r_info) override;

	GodotPhysicsDirectSpaceState2D() {}
};

class GodotSpace2D {
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
	struct ExcludedShapeSW {
		// A compound body may reuse the same Shape2D resource multiple times.
		// Match the individual local shape slot, not the shared shape pointer.
		int local_shape_index = 0;
		const GodotCollisionObject2D *against_object = nullptr;
		int against_shape_index = 0;

		_FORCE_INLINE_ uint32_t hash() const {
			uint32_t result = hash_murmur3_one_64(uint64_t(reinterpret_cast<uintptr_t>(against_object)));
			result = hash_murmur3_one_32(uint32_t(local_shape_index), result);
			return hash_fmix32(hash_murmur3_one_32(uint32_t(against_shape_index), result));
		}
		_FORCE_INLINE_ bool operator==(const ExcludedShapeSW &p_other) const {
			return local_shape_index == p_other.local_shape_index &&
					against_object == p_other.against_object &&
					against_shape_index == p_other.against_shape_index;
		}
	};

	uint64_t elapsed_time[ELAPSED_TIME_MAX] = {};

	GodotPhysicsDirectSpaceState2D *direct_access = nullptr;
	RID self;

	GodotBroadPhase2D *broadphase = nullptr;
	SelfList<GodotBody2D>::List active_list;
	SelfList<GodotBody2D>::List mass_properties_update_list;
	SelfList<GodotBody2D>::List state_query_list;
	SelfList<GodotArea2D>::List monitor_query_list;
	SelfList<GodotArea2D>::List area_moved_list;

	static void *_broadphase_pair(GodotCollisionObject2D *A, int p_subindex_A, GodotCollisionObject2D *B, int p_subindex_B, void *p_self);
	static void _broadphase_unpair(GodotCollisionObject2D *A, int p_subindex_A, GodotCollisionObject2D *B, int p_subindex_B, void *p_data, void *p_self);

	HashSet<GodotCollisionObject2D *> objects;

	// Broadphase pairs are created and destroyed constantly while bodies move.
	// Pool them per space instead of hitting the general allocator for every
	// pair. Members are destroyed after the destructor body, so the pools
	// outlive the broadphase that releases the remaining pairs.
	enum {
		PAIR_POOL_PAGE_SIZE = 256,
	};
	PagedAllocator<GodotBodyPair2D, true, PAIR_POOL_PAGE_SIZE> body_pair_pool;
	PagedAllocator<GodotAreaPair2D, true, PAIR_POOL_PAGE_SIZE> area_pair_pool;
	PagedAllocator<GodotArea2Pair2D, true, PAIR_POOL_PAGE_SIZE> area2_pair_pool;

	GodotArea2D *area = nullptr;

	int solver_iterations = 0;
	bool block_solver_enabled = false;
	bool parallel_large_islands = false;
	bool manifold_spread_reduction = false; // Opt-in stable two-contact patch selection.

	real_t contact_recycle_radius = 0.0;
	real_t contact_max_separation = 0.0;
	real_t contact_max_allowed_penetration = 0.0;
	real_t contact_bias = 0.0;
	real_t max_contact_push_speed = 0.0; // 0: unlimited (legacy behavior).
	real_t max_linear_velocity = 0.0; // Opt-in rigid speed limit, 0 disables.
	real_t max_angular_velocity = 0.0; // Opt-in angular speed limit, rad/s; 0 disables.
	real_t warm_start_coefficient = 1.0;
	bool implicit_damping = false; // Box2D-style time-step-stable damping; disabled by default.
	// Bullet-style angular rolling resistance; zero leaves the classic solver unchanged.
	real_t rolling_friction = 0.0;
	real_t constraint_bias = 0.0;
	real_t restitution_velocity_threshold = 0.0;
	real_t static_friction_multiplier = 1.0; // PhysX-style stiction; 1 = legacy friction.
	int friction_combine_mode = 0; // 0: legacy, 1: geometric, 2: average, 3: maximum
	int restitution_combine_mode = 0; // 0: legacy sum, 1: max, 2: average, 3: min, 4: multiply, 5: geometric


	real_t body_linear_velocity_sleep_threshold = 0.0;
	real_t body_angular_velocity_sleep_threshold = 0.0;
	real_t body_time_to_sleep = 0.0;

	bool locked = false;

	real_t last_step = 0.001;
	real_t previous_step = 0.0; // Shared by all contacts; no per-pair timestep storage.

	int island_count = 0;
	int active_objects = 0;
	int collision_pairs = 0;

	template <typename Visitor>
	void _visit_motion_candidates(GodotBody2D *p_body, const Rect2 &p_aabb, const PS2DT::MotionParameters &p_parameters, const Visitor &p_callback);

	Vector<Vector2> contact_debug;
	int contact_debug_count = 0;

	friend class GodotPhysicsDirectSpaceState2D;

public:
	_FORCE_INLINE_ void set_self(const RID &p_self) { self = p_self; }
	_FORCE_INLINE_ RID get_self() const { return self; }

	void set_default_area(GodotArea2D *p_area) { area = p_area; }
	GodotArea2D *get_default_area() const { return area; }

	const SelfList<GodotBody2D>::List &get_active_body_list() const;
	void body_add_to_active_list(SelfList<GodotBody2D> *p_body);
	void body_remove_from_active_list(SelfList<GodotBody2D> *p_body);
	void body_add_to_mass_properties_update_list(SelfList<GodotBody2D> *p_body);
	void body_remove_from_mass_properties_update_list(SelfList<GodotBody2D> *p_body);
	void area_add_to_moved_list(SelfList<GodotArea2D> *p_area);
	void area_remove_from_moved_list(SelfList<GodotArea2D> *p_area);
	const SelfList<GodotArea2D>::List &get_moved_area_list() const;

	void body_add_to_state_query_list(SelfList<GodotBody2D> *p_body);
	void body_remove_from_state_query_list(SelfList<GodotBody2D> *p_body);

	void area_add_to_monitor_query_list(SelfList<GodotArea2D> *p_area);
	void area_remove_from_monitor_query_list(SelfList<GodotArea2D> *p_area);

	GodotBroadPhase2D *get_broadphase();

	void add_object(GodotCollisionObject2D *p_object);
	void remove_object(GodotCollisionObject2D *p_object);
	const HashSet<GodotCollisionObject2D *> &get_objects() const;

	_FORCE_INLINE_ int get_solver_iterations() const { return solver_iterations; }
	_FORCE_INLINE_ bool is_block_solver_enabled() const { return block_solver_enabled; }
	_FORCE_INLINE_ bool is_parallel_large_islands_enabled() const { return parallel_large_islands; }
	_FORCE_INLINE_ bool is_manifold_spread_reduction_enabled() const { return manifold_spread_reduction; }
	_FORCE_INLINE_ real_t get_contact_recycle_radius() const { return contact_recycle_radius; }
	_FORCE_INLINE_ real_t get_contact_max_separation() const { return contact_max_separation; }
	_FORCE_INLINE_ real_t get_contact_max_allowed_penetration() const { return contact_max_allowed_penetration; }
	_FORCE_INLINE_ real_t get_contact_bias() const { return contact_bias; }
	_FORCE_INLINE_ real_t limit_contact_bias(real_t p_bias) const { return godot_physics_limit_contact_bias(p_bias, max_contact_push_speed); }
	_FORCE_INLINE_ real_t get_warm_start_coefficient() const { return warm_start_coefficient; }
	_FORCE_INLINE_ real_t get_max_linear_velocity() const { return max_linear_velocity; }
	_FORCE_INLINE_ real_t get_max_angular_velocity() const { return max_angular_velocity; }
	_FORCE_INLINE_ bool is_implicit_damping_enabled() const { return implicit_damping; }
	_FORCE_INLINE_ real_t get_rolling_friction() const { return rolling_friction; }
	_FORCE_INLINE_ real_t get_static_friction_multiplier() const { return static_friction_multiplier; }
	_FORCE_INLINE_ real_t get_restitution_velocity_threshold() const { return restitution_velocity_threshold; }
	_FORCE_INLINE_ real_t mix_restitution(real_t p_a, real_t p_b) const { return godot_physics_combine_restitution(p_a, p_b, restitution_combine_mode); }
	// Match Box2D's geometric mean when explicitly selected, while keeping
	// the historical GodotPhysics material combination as the default.
	_FORCE_INLINE_ real_t mix_friction(real_t p_a, real_t p_b) const {
		if (friction_combine_mode == 0) {
			return Math::abs(MIN(p_a, p_b));
		}
		const real_t a = Math::abs(p_a);
		const real_t b = Math::abs(p_b);
		switch (friction_combine_mode) {
			case 1:
				return Math::sqrt(a * b);
			case 2:
				return (a + b) * (real_t)0.5;
			case 3:
				return MAX(a, b);
			default:
				return Math::abs(MIN(p_a, p_b));
		}
	}
	_FORCE_INLINE_ real_t get_constraint_bias() const { return constraint_bias; }
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

	void set_param(PS2DE::SpaceParameter p_param, real_t p_value);
	real_t get_param(PS2DE::SpaceParameter p_param) const;

	void set_island_count(int p_island_count) { island_count = p_island_count; }
	int get_island_count() const { return island_count; }

	void set_active_objects(int p_active_objects) { active_objects = p_active_objects; }
	int get_active_objects() const { return active_objects; }

	int get_collision_pairs() const { return collision_pairs; }

	bool test_body_motion(GodotBody2D *p_body, const PS2DT::MotionParameters &p_parameters, PS2DT::MotionResult *r_result);

	void set_debug_contacts(int p_amount) { contact_debug.resize(p_amount); }
	_FORCE_INLINE_ bool is_debugging_contacts() const { return !contact_debug.is_empty(); }
	_FORCE_INLINE_ void add_debug_contact(const Vector2 &p_contact) {
		if (contact_debug_count < contact_debug.size()) {
			contact_debug.write[contact_debug_count++] = p_contact;
		}
	}
	_FORCE_INLINE_ Vector<Vector2> get_debug_contacts() { return contact_debug; }
	_FORCE_INLINE_ int get_debug_contact_count() { return contact_debug_count; }

	GodotPhysicsDirectSpaceState2D *get_direct_state();

	void set_elapsed_time(ElapsedTime p_time, uint64_t p_msec) { elapsed_time[p_time] = p_msec; }
	uint64_t get_elapsed_time(ElapsedTime p_time) const { return elapsed_time[p_time]; }

	GodotSpace2D();
	~GodotSpace2D();
};
