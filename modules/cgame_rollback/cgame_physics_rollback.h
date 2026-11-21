/**************************************************************************/
/*  cgame_physics_rollback.h                                              */
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

#include "cgame_deterministic_physics.h"
#include "cgame_rollback_netcode.h"

#include "core/math/vector3.h"
#include "core/object/ref_counted.h"
#include "core/templates/rb_map.h"
#include "core/variant/dictionary.h"

// Adapter between CgameDeterministicPhysics and CgameRollbackNetcode, plus server-side lag compensation for
// moving physics objects.
//
// State handed to the netcode is {"phys": PackedByteArray (solver snapshot), "tick": int}. Player inputs are
// Dictionaries {"force": Vector3}; each player owns one body (bind_player) and the input is applied as a clamped
// force for that step. This class is also a native step provider: setup_net() lets the netcode step the
// physics without any script call.
//
// Lag compensation: every simulated state is also kept in a bounded ring (tick -> snapshot) so rewind_query()
// can pose all bodies as they were at a time (interpolating between the two bracketing snapshots, lerp position
// and slerp rotation) and ray cast against that past world. The ring is keyed by tick, so resimulation after a
// rollback overwrites mispredicted entries with corrected ones.
class CgamePhysicsRollback : public RefCounted, public CgameRollbackStepProvider {
	GDCLASS(CgamePhysicsRollback, RefCounted);

	Ref<CgameDeterministicPhysics> world;
	RBMap<int64_t, int64_t> player_bodies; // player id -> body id
	double max_force = 60.0;
	int64_t history_capacity = 120;
	double dt = 1.0 / 60.0;

	RBMap<int64_t, PackedByteArray> history; // tick -> snapshot
	Ref<CgameDeterministicPhysics> scratch_a;
	Ref<CgameDeterministicPhysics> scratch_b;
	int64_t newest_tick = -1;

	void _record(int64_t p_tick, const PackedByteArray &p_bytes);

protected:
	static void _bind_methods();

public:
	CgamePhysicsRollback();

	// CgameRollbackStepProvider
	Dictionary rollback_step(const Dictionary &p_state, const Dictionary &p_inputs, double p_dt) override;

	Ref<CgameDeterministicPhysics> get_world() const { return world; }

	void set_max_force(double p_force) { max_force = p_force; }
	double get_max_force() const { return max_force; }
	void set_history_capacity(int64_t p_capacity) { history_capacity = MAX(p_capacity, int64_t(1)); }
	int64_t get_history_capacity() const { return history_capacity; }
	double get_dt() const { return dt; }

	void bind_player(int64_t p_pid, int64_t p_body_id);
	Dictionary get_player_bodies() const;

	Dictionary initial_state();
	void setup_net(const Ref<CgameRollbackNetcode> &p_net, const Array &p_players, const Array &p_local_players,
			double p_dt = 1.0 / 60.0, int64_t p_input_delay = 0, int64_t p_max_prediction = 8);
	Dictionary step_state(const Dictionary &p_state, const Dictionary &p_inputs, double p_dt);
	int64_t state_checksum(const Dictionary &p_state) const;

	int64_t history_size() const { return history.size(); }
	double oldest_time() const;
	double newest_time() const;
	Dictionary rewind_query(double p_time, const Vector3 &p_ray_origin, const Vector3 &p_ray_dir, double p_max_dist = 1000.0);
};
