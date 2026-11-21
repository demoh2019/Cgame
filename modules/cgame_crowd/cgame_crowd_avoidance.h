/**************************************************************************/
/*  cgame_crowd_avoidance.h                                               */
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

#pragma once

#include "core/math/vector2.h"
#include "core/object/ref_counted.h"
#include "core/templates/local_vector.h"
#include "core/variant/variant.h"

// ORCA (Optimal Reciprocal Collision Avoidance) in 2D for large crowds.
//
// Native port of the algorithm from the RVO2 Library (Agent::computeNewVelocity,
// linearProgram1/2/3). RVO2: Copyright 2008 University of North Carolina at
// Chapel Hill; authors Jur van den Berg, Stephen J. Guy, Jamie Snape, Ming C. Lin
// and Dinesh Manocha; licensed under Apache-2.0 (see LICENSE-RVO2.txt).
// Neighbour search uses a uniform spatial hash instead of the RVO2 k-d tree.
//
// Every agent is computed independently from read-only inputs, so the result is
// identical for any worker thread count (deterministic).
class CgameCrowdAvoidance : public RefCounted {
	GDCLASS(CgameCrowdAvoidance, RefCounted);

public:
	struct Params {
		real_t radius = 0.5;
		real_t max_speed = 1.5;
		real_t time_horizon = 3.0;
		real_t neighbor_dist = 10.0;
		int max_neighbors = 10;
		real_t time_step = 0.1;
	};

private:
	struct Line {
		Vector2 point;
		Vector2 direction;
	};

	static constexpr real_t EPSILON = 0.00001;
	static constexpr uint32_t PARALLEL_THRESHOLD = 256;
	static constexpr uint32_t AGENTS_PER_TASK = 64;

	struct Grid;
	struct ThreadData;

	static real_t _det(const Vector2 &p_a, const Vector2 &p_b) { return p_a.x * p_b.y - p_a.y * p_b.x; }
	static bool _linear_program1(const LocalVector<Line> &p_lines, uint32_t p_line_no, real_t p_radius, const Vector2 &p_opt, bool p_direction_opt, Vector2 &r_result);
	static uint32_t _linear_program2(const LocalVector<Line> &p_lines, real_t p_radius, const Vector2 &p_opt, bool p_direction_opt, Vector2 &r_result);
	static void _linear_program3(const LocalVector<Line> &p_lines, uint32_t p_begin, real_t p_radius, Vector2 &r_result);
	static void _compute_range(const ThreadData &p_data, uint32_t p_begin, uint32_t p_end);
	static void _task(void *p_userdata, uint32_t p_task);

protected:
	static void _bind_methods();

public:
	// Computes new velocities for p_count agents. Arrays are indexed alike; r_out
	// must have room for p_count entries and must not alias the inputs.
	static void compute(const Vector2 *p_positions, const Vector2 *p_velocities, const Vector2 *p_preferred, uint32_t p_count, const Params &p_params, Vector2 *r_out);

	static PackedVector2Array compute_velocities(const PackedVector2Array &p_positions, const PackedVector2Array &p_velocities, const PackedVector2Array &p_preferred, real_t p_radius, real_t p_max_speed, real_t p_time_horizon, real_t p_neighbor_dist, int p_max_neighbors, real_t p_time_step = 0.1);
};
