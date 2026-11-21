/**************************************************************************/
/*  cgame_rollback_netcode.cpp                                            */
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

#include "cgame_rollback_netcode.h"

#include "core/io/marshalls.h"
#include "core/object/class_db.h"
#include "core/templates/hashfuncs.h"

#include <algorithm>

Vector<int64_t> CgameRollbackNetcode::_to_sorted_ids(const Array &p_array) {
	Vector<int64_t> ids;
	for (int i = 0; i < p_array.size(); i++) {
		int64_t id = p_array[i];
		if (!ids.has(id)) {
			ids.push_back(id);
		}
	}
	ids.sort();
	return ids;
}

void CgameRollbackNetcode::setup(const Callable &p_step, const Dictionary &p_initial_state, const Array &p_players, const Array &p_local_players,
		double p_dt, int64_t p_input_delay, int64_t p_max_prediction, int64_t p_snapshot_capacity) {
	step = p_step;
	if (p_step.is_valid()) {
		provider = nullptr;
		provider_owner.unref();
	}
	dt = p_dt;
	input_delay = MAX(int64_t(0), p_input_delay);
	max_prediction = MAX(int64_t(0), p_max_prediction);
	snapshot_capacity = MAX(p_snapshot_capacity, max_prediction + 3);
	players = _to_sorted_ids(p_players);
	local_players.clear();
	for (int64_t pid : _to_sorted_ids(p_local_players)) {
		if (players.has(pid)) {
			local_players.push_back(pid);
		} else {
			WARN_PRINT("CgameRollbackNetcode: local player is not part of the player list and was ignored.");
		}
	}
	state = p_initial_state.duplicate(true);
	frame = 0;
	confirmed_frame = -1;
	rollbacks = 0;
	resimulated_frames = 0;
	stall_count = 0;
	desync_frames.clear();
	snapshots.clear();
	final_checksums.clear();
	player_data.clear();
	outgoing.clear();
	remote_checksums.clear();
	pending_rollback = -1;
	report_next = 0;
	for (int64_t pid : players) {
		player_data.insert(pid, PlayerData());
	}
	snapshots.insert(0, state.duplicate(true));
	// Delay prefill: the first `input_delay` frames carry empty inputs for local players.
	for (int64_t pid : local_players) {
		auto *E = player_data.find(pid);
		E->get().is_local = true;
		for (int64_t f = 0; f < input_delay; f++) {
			_store_input(pid, f, Dictionary(), true);
		}
		E->get().local_next = input_delay;
	}
	_recompute_confirmed();
}

void CgameRollbackNetcode::set_step_provider(CgameRollbackStepProvider *p_provider, const Ref<RefCounted> &p_owner) {
	provider = p_provider;
	provider_owner = p_provider ? p_owner : Ref<RefCounted>();
	if (p_provider) {
		step = Callable();
	}
}

int64_t CgameRollbackNetcode::state_checksum(const Dictionary &p_state) {
	Variant v = p_state;
	int len = 0;
	Error err = encode_variant(v, nullptr, len, false);
	ERR_FAIL_COND_V(err != OK || len <= 0, 0);
	Vector<uint8_t> buf;
	buf.resize(len);
	err = encode_variant(v, buf.ptrw(), len, false);
	ERR_FAIL_COND_V(err != OK, 0);
	return int64_t(hash_murmur3_buffer(buf.ptr(), len));
}

// Schedules `input` for frame (current local frame + input_delay). Returns that frame.
int64_t CgameRollbackNetcode::add_local_input(int64_t p_pid, const Dictionary &p_input) {
	auto *E = player_data.find(p_pid);
	ERR_FAIL_NULL_V_MSG(E, -1, "CgameRollbackNetcode: unknown player.");
	ERR_FAIL_COND_V_MSG(!E->get().is_local, -1, "CgameRollbackNetcode: player is not local.");
	int64_t f = E->get().local_next;
	E->get().local_next = f + 1;
	_store_input(p_pid, f, p_input.duplicate(true), true);
	_recompute_confirmed();
	return f;
}

void CgameRollbackNetcode::add_remote_input(int64_t p_pid, int64_t p_frame, const Dictionary &p_input) {
	auto *E = player_data.find(p_pid);
	if (!E || p_frame < E->get().floor) {
		return;
	}
	if (E->get().inputs.has(p_frame)) {
		return;
	}
	_store_input(p_pid, p_frame, p_input.duplicate(true), false);
	_recompute_confirmed();
}

Array CgameRollbackNetcode::drain_outgoing() {
	Array out = outgoing;
	outgoing = Array();
	return out;
}

void CgameRollbackNetcode::add_remote_checksum(int64_t p_frame, int64_t p_checksum) {
	remote_checksums[p_frame] = p_checksum;
	process();
	_verify_checksums();
}

Array CgameRollbackNetcode::get_checksum_report() {
	process(); // Reports must come from corrected, not mispredicted, snapshots.
	Array out;
	while (report_next <= confirmed_frame + 1 && report_next <= frame) {
		if (!snapshots.has(report_next) && !final_checksums.has(report_next)) {
			break;
		}
		Dictionary entry;
		entry["frame"] = report_next;
		entry["checksum"] = checksum_of(report_next);
		out.push_back(entry);
		report_next++;
	}
	return out;
}

bool CgameRollbackNetcode::advance() {
	process();
	if (is_stalled()) {
		stall_count++;
		return false;
	}
	if (!_simulate_one()) {
		return false;
	}
	_prune();
	_verify_checksums();
	return true;
}

void CgameRollbackNetcode::process() {
	if (pending_rollback >= 0) {
		int64_t target = pending_rollback;
		pending_rollback = -1;
		rollback_to(target);
		_prune();
		_verify_checksums();
	}
}

bool CgameRollbackNetcode::is_stalled() const {
	return frame - (confirmed_frame + 1) >= max_prediction;
}

bool CgameRollbackNetcode::rollback_to(int64_t p_frame) {
	if (p_frame > frame || !snapshots.has(p_frame)) {
		return false;
	}
	if (p_frame == frame) {
		return true;
	}
	int64_t target = frame;
	state = snapshots[p_frame].duplicate(true);
	frame = p_frame;
	rollbacks++;
	resimulated_frames += target - p_frame;
	while (frame < target) {
		if (!_simulate_one()) {
			break;
		}
	}
	return true;
}

int64_t CgameRollbackNetcode::checksum_of(int64_t p_frame) const {
	auto *S = snapshots.find(p_frame);
	if (S) {
		return state_checksum(S->get());
	}
	auto *F = final_checksums.find(p_frame);
	if (F) {
		return F->get();
	}
	return 0;
}

// Input that was/will be used for (pid, f): real if known, else predicted (repeat last).
Dictionary CgameRollbackNetcode::input_for(int64_t p_pid, int64_t p_frame) const {
	auto *E = player_data.find(p_pid);
	if (!E) {
		return Dictionary();
	}
	const PlayerData &pd = E->get();
	auto *I = pd.inputs.find(p_frame);
	if (I) {
		return I->get();
	}
	int64_t lo = MAX(pd.floor, p_frame - MAX_SCAN_BACK);
	for (int64_t g = p_frame - 1; g >= lo; g--) {
		I = pd.inputs.find(g);
		if (I) {
			return I->get();
		}
	}
	return pd.base;
}

bool CgameRollbackNetcode::has_real_input(int64_t p_pid, int64_t p_frame) const {
	auto *E = player_data.find(p_pid);
	return E && E->get().inputs.has(p_frame);
}

bool CgameRollbackNetcode::has_used_input(int64_t p_pid, int64_t p_frame) const {
	auto *E = player_data.find(p_pid);
	return E && E->get().used.has(p_frame);
}

Dictionary CgameRollbackNetcode::get_used_input(int64_t p_pid, int64_t p_frame) const {
	auto *E = player_data.find(p_pid);
	if (E) {
		auto *U = E->get().used.find(p_frame);
		if (U) {
			return U->get();
		}
	}
	return Dictionary();
}

int64_t CgameRollbackNetcode::get_input_floor(int64_t p_pid) const {
	auto *E = player_data.find(p_pid);
	return E ? E->get().floor : 0;
}

Dictionary CgameRollbackNetcode::get_snapshot(int64_t p_frame) const {
	auto *S = snapshots.find(p_frame);
	return S ? S->get().duplicate(true) : Dictionary();
}

Array CgameRollbackNetcode::get_desync_frames() const {
	Array out;
	for (int64_t f : desync_frames) {
		out.push_back(f);
	}
	return out;
}

Array CgameRollbackNetcode::get_players() const {
	Array out;
	for (int64_t p : players) {
		out.push_back(p);
	}
	return out;
}

Array CgameRollbackNetcode::get_local_players() const {
	Array out;
	for (int64_t p : local_players) {
		out.push_back(p);
	}
	return out;
}

void CgameRollbackNetcode::_store_input(int64_t p_pid, int64_t p_frame, const Dictionary &p_input, bool p_is_local) {
	auto *E = player_data.find(p_pid);
	PlayerData &pd = E->get();
	pd.inputs[p_frame] = p_input;
	if (p_is_local) {
		Dictionary entry;
		entry["player"] = p_pid;
		entry["frame"] = p_frame;
		entry["input"] = p_input;
		outgoing.push_back(entry);
	}
	// Late real input for an already simulated frame: rollback if the prediction was wrong.
	if (p_frame < frame) {
		auto *U = pd.used.find(p_frame);
		if (U && !U->get().recursive_equal(p_input, 0)) {
			if (pending_rollback < 0 || p_frame < pending_rollback) {
				pending_rollback = p_frame;
			}
		}
	}
	int64_t c = pd.contiguous;
	while (pd.inputs.has(c + 1)) {
		c++;
	}
	pd.contiguous = c;
}

void CgameRollbackNetcode::_recompute_confirmed() {
	int64_t m = int64_t(1) << 40;
	for (const KeyValue<int64_t, PlayerData> &E : player_data) {
		m = MIN(m, E.value.contiguous);
	}
	confirmed_frame = m;
}

bool CgameRollbackNetcode::_simulate_one() {
	Dictionary inputs;
	for (int64_t pid : players) {
		Dictionary inp = input_for(pid, frame);
		inputs[pid] = inp;
		player_data.find(pid)->get().used[frame] = inp;
	}
	Dictionary next;
	if (provider) {
		next = provider->rollback_step(state.duplicate(true), inputs.duplicate(true), dt);
	} else {
		ERR_FAIL_COND_V_MSG(!step.is_valid(), false, "CgameRollbackNetcode: no valid step callable or native step provider.");
		Variant args[3] = { state.duplicate(true), inputs.duplicate(true), dt };
		const Variant *argp[3] = { &args[0], &args[1], &args[2] };
		Variant ret;
		Callable::CallError ce;
		step.callp(argp, 3, ret, ce);
		ERR_FAIL_COND_V_MSG(ce.error != Callable::CallError::CALL_OK, false, "CgameRollbackNetcode: step callable failed.");
		ERR_FAIL_COND_V_MSG(ret.get_type() != Variant::DICTIONARY, false, "CgameRollbackNetcode: step callable must return a Dictionary.");
		next = ret;
	}
	state = next;
	frame += 1;
	snapshots[frame] = state.duplicate(true);
	return true;
}

void CgameRollbackNetcode::_prune() {
	// Snapshots older than the oldest frame that can still need rollback are dropped.
	int64_t keep_from = MIN(confirmed_frame + 1, frame);
	Vector<int64_t> keys;
	for (const KeyValue<int64_t, Dictionary> &E : snapshots) {
		keys.push_back(E.key);
	}
	for (int64_t f : keys) {
		if (f < keep_from || snapshots.size() > snapshot_capacity) {
			_retire_snapshot(f);
		}
	}
	int64_t in_floor = MIN(confirmed_frame, frame) - 1;
	for (KeyValue<int64_t, PlayerData> &E : player_data) {
		PlayerData &pd = E.value;
		int64_t fl = pd.floor;
		while (fl < in_floor) {
			auto *I = pd.inputs.find(fl);
			if (I) {
				pd.base = I->get();
				pd.inputs.erase(I);
			}
			pd.used.erase(fl);
			fl++;
		}
		pd.floor = fl;
	}
}

void CgameRollbackNetcode::_retire_snapshot(int64_t p_frame) {
	auto *S = snapshots.find(p_frame);
	if (!S) {
		return;
	}
	if (p_frame <= confirmed_frame + 1) {
		final_checksums[p_frame] = state_checksum(S->get());
		while (final_checksums.size() > MAX_FINAL_CHECKSUMS) {
			final_checksums.erase(final_checksums.front());
		}
	}
	snapshots.erase(S);
}

void CgameRollbackNetcode::_verify_checksums() {
	if (pending_rollback >= 0) {
		return; // Snapshots may still hold mispredicted states.
	}
	Vector<int64_t> done;
	struct Mismatch {
		int64_t frame;
		int64_t local;
		int64_t remote;
	};
	Vector<Mismatch> mismatches;
	for (const KeyValue<int64_t, int64_t> &E : remote_checksums) {
		int64_t f = E.key;
		if (f > confirmed_frame + 1 || f > frame) {
			continue;
		}
		if (!snapshots.has(f) && !final_checksums.has(f)) {
			if (f < frame - snapshot_capacity - MAX_FINAL_CHECKSUMS) {
				done.push_back(f);
			}
			continue;
		}
		int64_t local = checksum_of(f);
		int64_t remote = E.value;
		if (local != remote) {
			desync_frames.push_back(f);
			mismatches.push_back({ f, local, remote });
		}
		done.push_back(f);
	}
	for (int64_t f : done) {
		remote_checksums.erase(f);
	}
	for (const Mismatch &m : mismatches) {
		emit_signal(SNAME("desync_detected"), m.frame, m.local, m.remote);
	}
}

void CgameRollbackNetcode::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "step", "initial_state", "players", "local_players", "dt", "input_delay", "max_prediction", "snapshot_capacity"), &CgameRollbackNetcode::setup, DEFVAL(1.0 / 60.0), DEFVAL(0), DEFVAL(8), DEFVAL(0));
	ClassDB::bind_static_method("CgameRollbackNetcode", D_METHOD("state_checksum", "state"), &CgameRollbackNetcode::state_checksum);
	ClassDB::bind_method(D_METHOD("add_local_input", "player_id", "input"), &CgameRollbackNetcode::add_local_input);
	ClassDB::bind_method(D_METHOD("add_remote_input", "player_id", "frame", "input"), &CgameRollbackNetcode::add_remote_input);
	ClassDB::bind_method(D_METHOD("drain_outgoing"), &CgameRollbackNetcode::drain_outgoing);
	ClassDB::bind_method(D_METHOD("add_remote_checksum", "frame", "checksum"), &CgameRollbackNetcode::add_remote_checksum);
	ClassDB::bind_method(D_METHOD("get_checksum_report"), &CgameRollbackNetcode::get_checksum_report);
	ClassDB::bind_method(D_METHOD("advance"), &CgameRollbackNetcode::advance);
	ClassDB::bind_method(D_METHOD("process"), &CgameRollbackNetcode::process);
	ClassDB::bind_method(D_METHOD("is_stalled"), &CgameRollbackNetcode::is_stalled);
	ClassDB::bind_method(D_METHOD("rollback_to", "frame"), &CgameRollbackNetcode::rollback_to);
	ClassDB::bind_method(D_METHOD("snapshot_count"), &CgameRollbackNetcode::snapshot_count);
	ClassDB::bind_method(D_METHOD("get_state"), &CgameRollbackNetcode::get_state);
	ClassDB::bind_method(D_METHOD("checksum_of", "frame"), &CgameRollbackNetcode::checksum_of);
	ClassDB::bind_method(D_METHOD("has_desync"), &CgameRollbackNetcode::has_desync);
	ClassDB::bind_method(D_METHOD("input_for", "player_id", "frame"), &CgameRollbackNetcode::input_for);
	ClassDB::bind_method(D_METHOD("has_real_input", "player_id", "frame"), &CgameRollbackNetcode::has_real_input);
	ClassDB::bind_method(D_METHOD("has_used_input", "player_id", "frame"), &CgameRollbackNetcode::has_used_input);
	ClassDB::bind_method(D_METHOD("get_used_input", "player_id", "frame"), &CgameRollbackNetcode::get_used_input);
	ClassDB::bind_method(D_METHOD("get_input_floor", "player_id"), &CgameRollbackNetcode::get_input_floor);
	ClassDB::bind_method(D_METHOD("get_pending_rollback"), &CgameRollbackNetcode::get_pending_rollback);
	ClassDB::bind_method(D_METHOD("has_snapshot", "frame"), &CgameRollbackNetcode::has_snapshot);
	ClassDB::bind_method(D_METHOD("get_snapshot", "frame"), &CgameRollbackNetcode::get_snapshot);
	ClassDB::bind_method(D_METHOD("has_native_step"), &CgameRollbackNetcode::has_native_step);

	ClassDB::bind_method(D_METHOD("get_dt"), &CgameRollbackNetcode::get_dt);
	ClassDB::bind_method(D_METHOD("get_input_delay"), &CgameRollbackNetcode::get_input_delay);
	ClassDB::bind_method(D_METHOD("get_max_prediction"), &CgameRollbackNetcode::get_max_prediction);
	ClassDB::bind_method(D_METHOD("get_snapshot_capacity"), &CgameRollbackNetcode::get_snapshot_capacity);
	ClassDB::bind_method(D_METHOD("get_frame"), &CgameRollbackNetcode::get_frame);
	ClassDB::bind_method(D_METHOD("get_confirmed_frame"), &CgameRollbackNetcode::get_confirmed_frame);
	ClassDB::bind_method(D_METHOD("get_rollbacks"), &CgameRollbackNetcode::get_rollbacks);
	ClassDB::bind_method(D_METHOD("get_resimulated_frames"), &CgameRollbackNetcode::get_resimulated_frames);
	ClassDB::bind_method(D_METHOD("get_stall_count"), &CgameRollbackNetcode::get_stall_count);
	ClassDB::bind_method(D_METHOD("get_desync_frames"), &CgameRollbackNetcode::get_desync_frames);
	ClassDB::bind_method(D_METHOD("get_players"), &CgameRollbackNetcode::get_players);
	ClassDB::bind_method(D_METHOD("get_local_players"), &CgameRollbackNetcode::get_local_players);

	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "dt"), "", "get_dt");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "input_delay"), "", "get_input_delay");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_prediction"), "", "get_max_prediction");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "snapshot_capacity"), "", "get_snapshot_capacity");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "frame"), "", "get_frame");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "confirmed_frame"), "", "get_confirmed_frame");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "rollbacks"), "", "get_rollbacks");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "resimulated_frames"), "", "get_resimulated_frames");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "stall_count"), "", "get_stall_count");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "desync_frames"), "", "get_desync_frames");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "players"), "", "get_players");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "local_players"), "", "get_local_players");

	ADD_SIGNAL(MethodInfo("desync_detected", PropertyInfo(Variant::INT, "frame"), PropertyInfo(Variant::INT, "local_checksum"), PropertyInfo(Variant::INT, "remote_checksum")));
}
