/**************************************************************************/
/*  flock_3d.h                                                            */
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

#include "core/math/random_pcg.h"
#include "core/templates/local_vector.h"
#include "scene/3d/multimesh_instance_3d.h"

// Native boids flock (Reynolds 1987; UE Niagara "Boids", Unity DOTS flocking):
// cohesion, alignment, separation and a soft home sphere. Agents are written
// straight into the MultiMesh instance transforms, so a whole flock of birds,
// fish or bats costs one draw call and no per-agent nodes or script work.
class Flock3D : public MultiMeshInstance3D {
	GDCLASS(Flock3D, MultiMeshInstance3D);

	int agent_count = 16;
	bool active = true;
	float speed = 6.0f;
	float cohesion = 0.35f;
	float alignment = 0.5f;
	float separation = 2.5f;
	float separation_radius = 1.6f;
	float neighbor_radius = 8.0f;
	float home_radius = 18.0f;
	float orbit = 1.2f;
	float bank = 0.08f;
	float agent_scale = 1.0f;
	Vector3 home_offset;

	LocalVector<Vector3> positions;
	LocalVector<Vector3> velocities;
	RandomPCG rng;
	// Optional deterministic reset seed; ordinary Flock3D scenes keep
	// their historical evolving RNG until explicitly opted in.
	uint64_t simulation_seed = 0x5eed1234u;
	bool seeded_simulation = false;

	void _reset_agents();
	void _update_process();

protected:
	static void _bind_methods();
	void _notification(int p_what);

public:
	// One steering step for agent p_index, in flock-local space. Exposed for tests.
	static Vector3 compute_steering(int p_index, const LocalVector<Vector3> &p_positions, const LocalVector<Vector3> &p_velocities, int p_count, const Vector3 &p_home, float p_neighbor_radius, float p_separation_radius, float p_cohesion, float p_alignment, float p_separation, float p_orbit);

	void step(double p_delta);

	void set_agent_count(int p_count);
	int get_agent_count() const;
	void set_simulation_seed(uint64_t p_seed);
	uint64_t get_simulation_seed() const { return simulation_seed; }
	void set_active(bool p_active);
	bool is_active() const;
	void set_speed(float p_speed);
	float get_speed() const;
	void set_cohesion(float p_value);
	float get_cohesion() const;
	void set_alignment(float p_value);
	float get_alignment() const;
	void set_separation(float p_value);
	float get_separation() const;
	void set_separation_radius(float p_value);
	float get_separation_radius() const;
	void set_neighbor_radius(float p_value);
	float get_neighbor_radius() const;
	void set_home_radius(float p_value);
	float get_home_radius() const;
	void set_orbit(float p_value);
	float get_orbit() const;
	void set_bank(float p_value);
	float get_bank() const;
	void set_agent_scale(float p_value);
	float get_agent_scale() const;
	void set_home_offset(const Vector3 &p_offset);
	Vector3 get_home_offset() const;

	Vector3 get_agent_position(int p_index) const;
	void scatter_from(const Vector3 &p_global_point, float p_strength, float p_radius);

	Flock3D();
};
