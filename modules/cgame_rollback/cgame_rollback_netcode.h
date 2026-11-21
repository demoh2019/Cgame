/**************************************************************************/
/*  cgame_rollback_netcode.h                                              */
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
#include "core/templates/rb_map.h"
#include "core/templates/vector.h"
#include "core/variant/array.h"
#include "core/variant/callable.h"
#include "core/variant/dictionary.h"

// Native step provider: lets a C++ simulation (for example CgamePhysicsRollback) be stepped by the
// netcode without going through the script Callable machinery.
class CgameRollbackStepProvider {
public:
	virtual ~CgameRollbackStepProvider() {}

	// Pure, deterministic step. `p_state` is a private deep copy that may be mutated and returned;
	// `p_inputs` maps player id (int) -> input Dictionary in sorted player order.
	virtual Dictionary rollback_step(const Dictionary &p_state, const Dictionary &p_inputs, double p_dt) = 0;
};

// GGPO-style rollback netcode core: input ring buffers, local prediction, confirmed-frame tracking,
// rollback + resimulation, bounded snapshot ring, per-frame checksums with desync detection, input delay and a
// max prediction window (stalls when exceeded).
//
// Frame semantics: snapshot[f] is the state at the START of frame f (before f's inputs). advance() simulates
// the current frame f -> f+1. A frame is "confirmed" once real inputs of every player are known for it and all
// earlier frames. Player ids are integers.
class CgameRollbackNetcode : public RefCounted {
	GDCLASS(CgameRollbackNetcode, RefCounted);

public:
	static constexpr int64_t MAX_FINAL_CHECKSUMS = 256;
	static constexpr int64_t MAX_SCAN_BACK = 512;

private:
	struct PlayerData {
		RBMap<int64_t, Dictionary> inputs; // frame -> real or local input
		RBMap<int64_t, Dictionary> used; // frame -> input actually simulated
		int64_t contiguous = -1; // highest frame with real inputs for all frames <= it
		int64_t floor = 0; // first frame still stored
		Dictionary base; // last pruned real input (prediction fallback)
		bool is_local = false;
		int64_t local_next = 0; // next frame a local input is scheduled for
	};

	Callable step;
	CgameRollbackStepProvider *provider = nullptr;
	Ref<RefCounted> provider_owner;
	double dt = 1.0 / 60.0;
	int64_t input_delay = 0;
	int64_t max_prediction = 8;
	int64_t snapshot_capacity = 16;

	int64_t frame = 0;
	int64_t confirmed_frame = -1;
	Dictionary state;

	Vector<int64_t> players;
	Vector<int64_t> local_players;

	int64_t rollbacks = 0;
	int64_t resimulated_frames = 0;
	int64_t stall_count = 0;
	Vector<int64_t> desync_frames;

	RBMap<int64_t, Dictionary> snapshots; // frame -> state
	RBMap<int64_t, int64_t> final_checksums; // frame -> checksum of pruned final frames
	RBMap<int64_t, PlayerData> player_data;
	Array outgoing;
	int64_t pending_rollback = -1;
	RBMap<int64_t, int64_t> remote_checksums; // frame -> checksum
	int64_t report_next = 0;

	static Vector<int64_t> _to_sorted_ids(const Array &p_array);
	void _store_input(int64_t p_pid, int64_t p_frame, const Dictionary &p_input, bool p_is_local);
	void _recompute_confirmed();
	bool _simulate_one();
	void _prune();
	void _retire_snapshot(int64_t p_frame);
	void _verify_checksums();

protected:
	static void _bind_methods();

public:
	void setup(const Callable &p_step, const Dictionary &p_initial_state, const Array &p_players, const Array &p_local_players,
			double p_dt = 1.0 / 60.0, int64_t p_input_delay = 0, int64_t p_max_prediction = 8, int64_t p_snapshot_capacity = 0);

	// Native step. Call after setup(); the owner reference keeps the provider alive. Pass nullptr to clear.
	void set_step_provider(CgameRollbackStepProvider *p_provider, const Ref<RefCounted> &p_owner);
	bool has_native_step() const { return provider != nullptr; }

	static int64_t state_checksum(const Dictionary &p_state);

	int64_t add_local_input(int64_t p_pid, const Dictionary &p_input);
	void add_remote_input(int64_t p_pid, int64_t p_frame, const Dictionary &p_input);
	Array drain_outgoing();
	void add_remote_checksum(int64_t p_frame, int64_t p_checksum);
	Array get_checksum_report();

	bool advance();
	void process();
	bool is_stalled() const;
	bool rollback_to(int64_t p_frame);

	int64_t snapshot_count() const { return snapshots.size(); }
	Dictionary get_state() const { return state; }
	int64_t checksum_of(int64_t p_frame) const;
	bool has_desync() const { return !desync_frames.is_empty(); }

	Dictionary input_for(int64_t p_pid, int64_t p_frame) const;
	bool has_real_input(int64_t p_pid, int64_t p_frame) const;
	bool has_used_input(int64_t p_pid, int64_t p_frame) const;
	Dictionary get_used_input(int64_t p_pid, int64_t p_frame) const;
	int64_t get_input_floor(int64_t p_pid) const;
	int64_t get_pending_rollback() const { return pending_rollback; }
	bool has_snapshot(int64_t p_frame) const { return snapshots.has(p_frame); }
	Dictionary get_snapshot(int64_t p_frame) const;

	double get_dt() const { return dt; }
	int64_t get_input_delay() const { return input_delay; }
	int64_t get_max_prediction() const { return max_prediction; }
	int64_t get_snapshot_capacity() const { return snapshot_capacity; }
	int64_t get_frame() const { return frame; }
	int64_t get_confirmed_frame() const { return confirmed_frame; }
	int64_t get_rollbacks() const { return rollbacks; }
	int64_t get_resimulated_frames() const { return resimulated_frames; }
	int64_t get_stall_count() const { return stall_count; }
	Array get_desync_frames() const;
	Array get_players() const;
	Array get_local_players() const;
};
