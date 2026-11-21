/**************************************************************************/
/*  cgame_physics_rollback.cpp                                            */
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

#include "cgame_physics_rollback.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/templates/hashfuncs.h"

CgamePhysicsRollback::CgamePhysicsRollback() {
	world.instantiate();
	scratch_a.instantiate();
	scratch_b.instantiate();
}

void CgamePhysicsRollback::bind_player(int64_t p_pid, int64_t p_body_id) {
	player_bodies[p_pid] = p_body_id;
}

Dictionary CgamePhysicsRollback::get_player_bodies() const {
	Dictionary out;
	for (const KeyValue<int64_t, int64_t> &E : player_bodies) {
		out[E.key] = E.value;
	}
	return out;
}

// Initial netcode state from the current world; also seeds the lag-compensation ring.
Dictionary CgamePhysicsRollback::initial_state() {
	history.clear();
	newest_tick = -1;
	PackedByteArray bytes = world->snapshot();
	_record(0, bytes);
	Dictionary state;
	state["phys"] = bytes;
	state["tick"] = 0;
	return state;
}

// Configures a CgameRollbackNetcode instance to run this physics world with the native step.
void CgamePhysicsRollback::setup_net(const Ref<CgameRollbackNetcode> &p_net, const Array &p_players, const Array &p_local_players,
		double p_dt, int64_t p_input_delay, int64_t p_max_prediction) {
	ERR_FAIL_COND_MSG(p_net.is_null(), "CgamePhysicsRollback: netcode is null.");
	dt = p_dt;
	p_net->setup(Callable(), initial_state(), p_players, p_local_players, p_dt, p_input_delay, p_max_prediction);
	p_net->set_step_provider(this, Ref<RefCounted>(this));
}

Dictionary CgamePhysicsRollback::rollback_step(const Dictionary &p_state, const Dictionary &p_inputs, double p_dt) {
	return step_state(p_state, p_inputs, p_dt);
}

// The netcode step: restore, apply player forces in sorted player order, step, snapshot.
Dictionary CgamePhysicsRollback::step_state(const Dictionary &p_state, const Dictionary &p_inputs, double p_dt) {
	Dictionary state = p_state;
	Variant phys = state.get("phys", Variant());
	ERR_FAIL_COND_V_MSG(phys.get_type() != Variant::PACKED_BYTE_ARRAY, state, "CgamePhysicsRollback: state has no 'phys' snapshot.");
	world->restore(PackedByteArray(phys));
	Vector<int64_t> pids;
	Array keys = p_inputs.keys();
	for (int i = 0; i < keys.size(); i++) {
		pids.push_back(int64_t(keys[i]));
	}
	pids.sort();
	for (int64_t pid : pids) {
		auto *B = player_bodies.find(pid);
		if (!B) {
			continue;
		}
		Variant input = p_inputs[pid];
		if (input.get_type() != Variant::DICTIONARY) {
			continue;
		}
		Dictionary inp = input;
		Variant fv = inp.get("force", Vector3());
		if (fv.get_type() != Variant::VECTOR3) {
			continue;
		}
		Vector3 f = fv;
		if (f != Vector3()) {
			if (f.length() > max_force) {
				f = f.normalized() * max_force;
			}
			world->apply_force(int(B->get()), f);
		}
	}
	world->step(p_dt);
	int64_t tick = int64_t(state.get("tick", 0)) + 1;
	PackedByteArray bytes = world->snapshot();
	state["phys"] = bytes;
	state["tick"] = tick;
	_record(tick, bytes);
	return state;
}

int64_t CgamePhysicsRollback::state_checksum(const Dictionary &p_state) const {
	PackedByteArray bytes = p_state.get("phys", PackedByteArray());
	return int64_t(hash_murmur3_buffer(bytes.ptr(), int(bytes.size())));
}

void CgamePhysicsRollback::_record(int64_t p_tick, const PackedByteArray &p_bytes) {
	history[p_tick] = p_bytes;
	newest_tick = MAX(newest_tick, p_tick);
	// A rollback rewrote older ticks: anything newer is stale until resimulated, but is replaced as the
	// resimulation proceeds. Only trim by age.
	int64_t cutoff = newest_tick - history_capacity;
	while (history.size() > history_capacity + 1 && history.front()->key() < cutoff) {
		history.erase(history.front());
	}
}

double CgamePhysicsRollback::oldest_time() const {
	int64_t oldest = newest_tick;
	if (!history.is_empty()) {
		oldest = MIN(oldest, history.front()->key());
	}
	return double(oldest) * dt;
}

double CgamePhysicsRollback::newest_time() const {
	return double(newest_tick) * dt;
}

// Casts a ray against the world as it was at `time` (seconds of simulation time). `time` is clamped to the
// stored history. Result: {"hit", "id", "t", "point", "alpha", "tick"}.
Dictionary CgamePhysicsRollback::rewind_query(double p_time, const Vector3 &p_ray_origin, const Vector3 &p_ray_dir, double p_max_dist) {
	Dictionary out;
	out["hit"] = false;
	out["id"] = -1;
	out["t"] = p_max_dist;
	out["point"] = Vector3();
	out["alpha"] = 0.0;
	out["tick"] = -1;
	if (history.is_empty()) {
		return out;
	}
	int64_t oldest = MIN(newest_tick, history.front()->key());
	double ft = CLAMP(p_time / dt, double(oldest), double(newest_tick));
	int64_t lo_tick = int64_t(Math::floor(ft));
	double alpha = ft - double(lo_tick);
	int64_t hi_tick = lo_tick + 1;
	auto *lo = history.find(lo_tick);
	if (!lo) {
		return out;
	}
	scratch_a->restore(lo->get());
	auto *hi = history.find(hi_tick);
	if (alpha > 1e-9 && hi) {
		scratch_b->restore(hi->get());
		CgamePhysicsCore::World &wa = scratch_a->get_core();
		const CgamePhysicsCore::World &wb = scratch_b->get_core();
		for (CgamePhysicsCore::Body &b : wa.bodies) {
			const CgamePhysicsCore::Body *other = wb.get_body(b.id);
			if (other && !b.is_static()) {
				b.pos = b.pos.lerp(other->pos, alpha);
				b.rot = b.rot.slerp(other->rot, alpha).normalized();
				b.update_derived();
			}
		}
	} else {
		alpha = 0.0;
	}
	Dictionary res = scratch_a->raycast(p_ray_origin, p_ray_dir, p_max_dist);
	res["alpha"] = alpha;
	res["tick"] = lo_tick;
	return res;
}

void CgamePhysicsRollback::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_world"), &CgamePhysicsRollback::get_world);
	ClassDB::bind_method(D_METHOD("set_max_force", "max_force"), &CgamePhysicsRollback::set_max_force);
	ClassDB::bind_method(D_METHOD("get_max_force"), &CgamePhysicsRollback::get_max_force);
	ClassDB::bind_method(D_METHOD("set_history_capacity", "capacity"), &CgamePhysicsRollback::set_history_capacity);
	ClassDB::bind_method(D_METHOD("get_history_capacity"), &CgamePhysicsRollback::get_history_capacity);
	ClassDB::bind_method(D_METHOD("get_dt"), &CgamePhysicsRollback::get_dt);
	ClassDB::bind_method(D_METHOD("bind_player", "player_id", "body_id"), &CgamePhysicsRollback::bind_player);
	ClassDB::bind_method(D_METHOD("get_player_bodies"), &CgamePhysicsRollback::get_player_bodies);
	ClassDB::bind_method(D_METHOD("initial_state"), &CgamePhysicsRollback::initial_state);
	ClassDB::bind_method(D_METHOD("setup_net", "net", "players", "local_players", "dt", "input_delay", "max_prediction"), &CgamePhysicsRollback::setup_net, DEFVAL(1.0 / 60.0), DEFVAL(0), DEFVAL(8));
	ClassDB::bind_method(D_METHOD("step_state", "state", "inputs", "dt"), &CgamePhysicsRollback::step_state);
	ClassDB::bind_method(D_METHOD("state_checksum", "state"), &CgamePhysicsRollback::state_checksum);
	ClassDB::bind_method(D_METHOD("history_size"), &CgamePhysicsRollback::history_size);
	ClassDB::bind_method(D_METHOD("oldest_time"), &CgamePhysicsRollback::oldest_time);
	ClassDB::bind_method(D_METHOD("newest_time"), &CgamePhysicsRollback::newest_time);
	ClassDB::bind_method(D_METHOD("rewind_query", "time", "ray_origin", "ray_direction", "max_distance"), &CgamePhysicsRollback::rewind_query, DEFVAL(1000.0));

	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "world", PROPERTY_HINT_RESOURCE_TYPE, "CgameDeterministicPhysics", PROPERTY_USAGE_NONE), "", "get_world");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "max_force", PROPERTY_HINT_RANGE, "0,10000,0.01,or_greater"), "set_max_force", "get_max_force");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "history_capacity", PROPERTY_HINT_RANGE, "1,100000,1,or_greater"), "set_history_capacity", "get_history_capacity");
}
