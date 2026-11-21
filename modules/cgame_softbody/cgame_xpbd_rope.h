/**************************************************************************/
/*  cgame_xpbd_rope.h                                                     */
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

#include "core/object/ref_counted.h"
#include "core/templates/hash_map.h"
#include "core/templates/local_vector.h"
#include "core/variant/binder_common.h"
#include "core/variant/callable.h"

// XPBD rope: a particle chain with distance (and optional bending) constraints, sphere/plane
// collision, segment-segment self-collision through a spatial hash and a crossing-number knot
// heuristic.
//
// Algorithm: Macklin, Muller, Chentanez, "XPBD: Position-Based Simulation of Compliant
// Constrained Dynamics" (2016); small-steps solver layout after Matthias Muller's "Ten Minute
// Physics" demos. Reference: https://github.com/matthias-research/pages (tenMinutePhysics),
// MIT License, Copyright (c) Matthias Muller / NVIDIA. Clean re-implementation from the
// published algorithm; closest-point-between-segments is the textbook formulation from
// Ericson, "Real-Time Collision Detection".
class CgameXPBDRope : public RefCounted {
	GDCLASS(CgameXPBDRope, RefCounted);

public:
	enum PinMode {
		PIN_FREE = 0,
		PIN_FIXED = 1,
		PIN_CALLABLE = 2,
		PIN_DRIVEN = 3,
	};

private:
	Vector3 gravity = Vector3(0, -9.81, 0);
	Vector3 wind;
	real_t drag = 0.05;
	real_t compliance = 0.0;
	real_t bend_compliance = -1.0;
	int iterations = 1;
	real_t radius = 0.02;
	real_t friction = 0.3;
	bool self_collision_enabled = false;

	Vector<Vector3> pos;
	Vector<Vector3> prev;
	Vector<Vector3> vel;
	Vector<float> inv_mass;
	Vector<float> base_inv_mass;
	Vector<uint8_t> pin_mode;
	Vector<Vector3> pin_pos;
	Vector<Vector3> drive_from;
	Vector<Callable> pin_fn;
	Vector<float> seg_rest;
	real_t rest_len = 0.0;

	Vector<Vector3> sphere_c;
	Vector<float> sphere_r;
	Vector<Vector3> plane_n;
	Vector<float> plane_d;

	HashMap<uint64_t, LocalVector<int>> grid;

	void _integrate(real_t p_sdt, real_t p_drive_t);
	void _project(int p_a, int p_b, real_t p_rest, real_t p_alpha);
	void _solve_distance(real_t p_sdt);
	void _collide();
	void _solve_self_collision();
	void _separate_segments(int p_i, int p_j, real_t p_min_d);
	static bool _proper_cross(const Vector2 &p_a, const Vector2 &p_b, const Vector2 &p_c, const Vector2 &p_d);
	_FORCE_INLINE_ static uint64_t _cell_key(int64_t p_cx, int64_t p_cy, int64_t p_cz) {
		return ((uint64_t(p_cx) & 0x1FFFFF) << 42) | ((uint64_t(p_cy) & 0x1FFFFF) << 21) | (uint64_t(p_cz) & 0x1FFFFF);
	}

protected:
	static void _bind_methods();

public:
	void set_gravity(const Vector3 &p_gravity) { gravity = p_gravity; }
	Vector3 get_gravity() const { return gravity; }
	void set_wind(const Vector3 &p_wind) { wind = p_wind; }
	Vector3 get_wind() const { return wind; }
	void set_drag(real_t p_drag) { drag = p_drag; }
	real_t get_drag() const { return drag; }
	void set_compliance(real_t p_compliance) { compliance = p_compliance; }
	real_t get_compliance() const { return compliance; }
	void set_bend_compliance(real_t p_compliance) { bend_compliance = p_compliance; }
	real_t get_bend_compliance() const { return bend_compliance; }
	void set_iterations(int p_iterations) { iterations = MAX(p_iterations, 1); }
	int get_iterations() const { return iterations; }
	void set_radius(real_t p_radius) { radius = p_radius; }
	real_t get_radius() const { return radius; }
	void set_friction(real_t p_friction) { friction = p_friction; }
	real_t get_friction() const { return friction; }
	void set_self_collision_enabled(bool p_enabled) { self_collision_enabled = p_enabled; }
	bool is_self_collision_enabled() const { return self_collision_enabled; }

	void setup(const Vector3 &p_start, const Vector3 &p_end, int p_segments, real_t p_particle_mass = 0.1);
	void setup_points(const Vector<Vector3> &p_points, real_t p_particle_mass = 0.1);

	int particle_count() const { return pos.size(); }
	int segment_count() const { return MAX(pos.size() - 1, 0); }
	Vector<Vector3> positions() const { return pos; }
	real_t length() const;
	real_t rest_length() const { return rest_len; }

	void pin(int p_index, const Vector3 &p_world_pos);
	void attach(int p_index, const Callable &p_target_fn);
	void drive(int p_index, const Vector3 &p_world_pos);
	void attach_start(const Callable &p_target_fn);
	void attach_end(const Callable &p_target_fn);
	void unpin(int p_index);
	bool is_pinned(int p_index) const;

	int add_sphere(const Vector3 &p_center, real_t p_radius);
	void set_sphere_center(int p_index, const Vector3 &p_center);
	int add_plane(const Vector3 &p_normal, real_t p_offset);
	void clear_colliders();

	void step(real_t p_dt, int p_substeps = 8);

	static Vector2 closest_params(const Vector3 &p_p1, const Vector3 &p_q1, const Vector3 &p_p2, const Vector3 &p_q2);
	real_t segment_distance(int p_i, int p_j) const;
	real_t min_self_distance() const;
	int crossing_number() const;
	int knot_count() const { return crossing_number() / 3; }

	CgameXPBDRope() {}
};
