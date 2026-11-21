/**************************************************************************/
/*  cgame_rollback_debugger.cpp                                           */
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

#include "cgame_rollback_debugger.h"

#include "core/object/callable_mp.h"
#include "core/object/class_db.h"

void CgameRollbackDebugger::attach(const Ref<CgameRollbackNetcode> &p_net) {
	Callable on_desync = callable_mp(this, &CgameRollbackDebugger::_on_desync);
	if (net.is_valid() && net->is_connected(SNAME("desync_detected"), on_desync)) {
		net->disconnect(SNAME("desync_detected"), on_desync);
	}
	net = p_net;
	if (net.is_valid()) {
		net->connect(SNAME("desync_detected"), on_desync);
	}
}

void CgameRollbackDebugger::add_remote_input(int64_t p_pid, int64_t p_frame, const Dictionary &p_input) {
	ERR_FAIL_COND_MSG(net.is_null(), "CgameRollbackDebugger: no netcode attached.");
	bool fresh = !net->has_real_input(p_pid, p_frame) && p_frame >= net->get_input_floor(p_pid);
	bool was_used = fresh && p_frame < net->get_frame() && net->has_used_input(p_pid, p_frame);
	bool missed = was_used && !net->get_used_input(p_pid, p_frame).recursive_equal(p_input, 0);
	int64_t pending_before = net->get_pending_rollback();
	net->add_remote_input(p_pid, p_frame, p_input);
	if (was_used) {
		late_inputs[p_pid] = int64_t(late_inputs.get(p_pid, 0)) + 1;
		if (missed) {
			mispredictions[p_pid] = int64_t(mispredictions.get(p_pid, 0)) + 1;
		}
	}
	int64_t pending_after = net->get_pending_rollback();
	if (pending_after >= 0 && pending_after != pending_before) {
		cause_by_frame[pending_after] = p_pid;
	}
}

int64_t CgameRollbackDebugger::add_local_input(int64_t p_pid, const Dictionary &p_input) {
	ERR_FAIL_COND_V_MSG(net.is_null(), -1, "CgameRollbackDebugger: no netcode attached.");
	return net->add_local_input(p_pid, p_input);
}

bool CgameRollbackDebugger::advance() {
	_before_and_run(false);
	return last_advanced;
}

void CgameRollbackDebugger::process() {
	_before_and_run(true);
}

void CgameRollbackDebugger::_before_and_run(bool p_only_process) {
	ERR_FAIL_COND_MSG(net.is_null(), "CgameRollbackDebugger: no netcode attached.");
	int64_t rb = net->get_rollbacks();
	int64_t resim = net->get_resimulated_frames();
	int64_t pending = net->get_pending_rollback();
	int64_t frame_before = net->get_frame();
	if (p_only_process) {
		net->process();
	} else {
		last_advanced = net->advance();
		history[net->get_frame()] = net->get_state().duplicate(true);
		history.erase(net->get_frame() - HISTORY_LIMIT);
	}
	if (net->get_rollbacks() > rb) {
		int64_t cause = -1;
		auto *C = cause_by_frame.find(pending);
		if (C) {
			cause = C->get();
		}
		Dictionary entry;
		entry["from_frame"] = pending >= 0 ? pending : frame_before;
		entry["to_frame"] = frame_before;
		entry["frames_resimulated"] = net->get_resimulated_frames() - resim;
		entry["cause"] = cause;
		rollbacks.push_back(entry);
		if (C) {
			cause_by_frame.erase(C);
		}
	}
}

// Miss rate for a player: mispredicted / late inputs (0.0 when none arrived late).
double CgameRollbackDebugger::miss_rate(int64_t p_pid) const {
	int64_t late = late_inputs.get(p_pid, 0);
	if (late == 0) {
		return 0.0;
	}
	return double(int64_t(mispredictions.get(p_pid, 0))) / double(late);
}

// Provide the remote peer's state for a desync frame to compute the key-path diff.
Array CgameRollbackDebugger::attach_remote_state(int64_t p_frame, const Dictionary &p_remote_state) {
	for (int i = 0; i < desyncs.size(); i++) {
		Dictionary e = desyncs[i];
		if (int64_t(e["frame"]) == p_frame) {
			Array diff = diff_states(e["local_state"], p_remote_state);
			e["diff"] = diff;
			return diff;
		}
	}
	return Array();
}

void CgameRollbackDebugger::_on_desync(int64_t p_frame, int64_t p_local_checksum, int64_t p_remote_checksum) {
	Dictionary snap;
	if (net.is_valid() && net->has_snapshot(p_frame)) {
		snap = net->get_snapshot(p_frame);
	} else {
		auto *H = history.find(p_frame);
		if (H) {
			snap = H->get();
		}
	}
	Dictionary entry;
	entry["frame"] = p_frame;
	entry["local_checksum"] = p_local_checksum;
	entry["remote_checksum"] = p_remote_checksum;
	entry["local_state"] = snap.duplicate(true);
	entry["diff"] = Array();
	desyncs.push_back(entry);
}

bool CgameRollbackDebugger::_variants_equal(const Variant &p_a, const Variant &p_b) {
	if (p_a.get_type() != p_b.get_type()) {
		return false;
	}
	Variant r;
	bool valid = false;
	Variant::evaluate(Variant::OP_EQUAL, p_a, p_b, r, valid);
	return valid && bool(r);
}

void CgameRollbackDebugger::_diff(const Variant &p_a, const Variant &p_b, const String &p_path, Vector<String> &r_out) {
	if (p_a.get_type() == Variant::DICTIONARY && p_b.get_type() == Variant::DICTIONARY) {
		Dictionary da = p_a;
		Dictionary db = p_b;
		Array keys = da.keys();
		Array keys_b = db.keys();
		for (int i = 0; i < keys_b.size(); i++) {
			if (!da.has(keys_b[i])) {
				keys.push_back(keys_b[i]);
			}
		}
		for (int i = 0; i < keys.size(); i++) {
			const Variant &k = keys[i];
			String key_str = k.operator String();
			String path = p_path.is_empty() ? key_str : p_path + "." + key_str;
			if (!da.has(k) || !db.has(k)) {
				r_out.push_back(path);
			} else {
				_diff(da[k], db[k], path, r_out);
			}
		}
	} else if (p_a.get_type() == Variant::ARRAY && p_b.get_type() == Variant::ARRAY) {
		Array aa = p_a;
		Array ab = p_b;
		for (int i = 0; i < MAX(aa.size(), ab.size()); i++) {
			String path = vformat("%s[%d]", p_path, i);
			if (i >= aa.size() || i >= ab.size()) {
				r_out.push_back(path);
			} else {
				_diff(aa[i], ab[i], path, r_out);
			}
		}
	} else if (!_variants_equal(p_a, p_b)) {
		r_out.push_back(p_path);
	}
}

// Key paths (e.g. "players.1.x", "items[2]") at which a and b differ, sorted.
Array CgameRollbackDebugger::diff_states(const Variant &p_a, const Variant &p_b, const String &p_path) {
	Vector<String> out;
	_diff(p_a, p_b, p_path, out);
	out.sort();
	Array result;
	for (const String &s : out) {
		result.push_back(s);
	}
	return result;
}

String CgameRollbackDebugger::report() const {
	ERR_FAIL_COND_V_MSG(net.is_null(), String(), "CgameRollbackDebugger: no netcode attached.");
	Vector<String> lines;
	lines.push_back(vformat("frame=%d confirmed=%d rollbacks=%d resimulated=%d stalls=%d",
			net->get_frame(), net->get_confirmed_frame(), net->get_rollbacks(), net->get_resimulated_frames(), net->get_stall_count()));
	for (int i = 0; i < rollbacks.size(); i++) {
		Dictionary d = rollbacks[i];
		lines.push_back(vformat("  rollback %d -> %d (%d frames) cause=%s",
				int64_t(d["from_frame"]), int64_t(d["to_frame"]), int64_t(d["frames_resimulated"]), String(d["cause"])));
	}
	Array pids = late_inputs.keys();
	pids.sort();
	for (int i = 0; i < pids.size(); i++) {
		int64_t pid = pids[i];
		lines.push_back(vformat("  player %d: %d late inputs, %d mispredicted (miss rate %.0f%%)",
				pid, int64_t(late_inputs[pid]), int64_t(mispredictions.get(pid, 0)), miss_rate(pid) * 100.0));
	}
	if (desyncs.is_empty()) {
		lines.push_back("no desyncs");
	}
	for (int i = 0; i < desyncs.size(); i++) {
		Dictionary e = desyncs[i];
		lines.push_back(vformat("  DESYNC frame %d local=%d remote=%d diff=%s",
				int64_t(e["frame"]), int64_t(e["local_checksum"]), int64_t(e["remote_checksum"]), String(Variant(e["diff"]))));
	}
	return String("\n").join(lines);
}

// State recorded when `frame` was reached (may be mispredicted if a rollback followed), or {}.
Dictionary CgameRollbackDebugger::state_history(int64_t p_frame) const {
	auto *H = history.find(p_frame);
	return H ? H->get().duplicate(true) : Dictionary();
}

void CgameRollbackDebugger::_bind_methods() {
	ClassDB::bind_method(D_METHOD("attach", "net"), &CgameRollbackDebugger::attach);
	ClassDB::bind_method(D_METHOD("get_net"), &CgameRollbackDebugger::get_net);
	ClassDB::bind_method(D_METHOD("add_remote_input", "player_id", "frame", "input"), &CgameRollbackDebugger::add_remote_input);
	ClassDB::bind_method(D_METHOD("add_local_input", "player_id", "input"), &CgameRollbackDebugger::add_local_input);
	ClassDB::bind_method(D_METHOD("advance"), &CgameRollbackDebugger::advance);
	ClassDB::bind_method(D_METHOD("process"), &CgameRollbackDebugger::process);
	ClassDB::bind_method(D_METHOD("miss_rate", "player_id"), &CgameRollbackDebugger::miss_rate);
	ClassDB::bind_method(D_METHOD("attach_remote_state", "frame", "remote_state"), &CgameRollbackDebugger::attach_remote_state);
	ClassDB::bind_static_method("CgameRollbackDebugger", D_METHOD("diff_states", "a", "b", "path"), &CgameRollbackDebugger::diff_states, DEFVAL(""));
	ClassDB::bind_method(D_METHOD("report"), &CgameRollbackDebugger::report);
	ClassDB::bind_method(D_METHOD("state_history", "frame"), &CgameRollbackDebugger::state_history);
	ClassDB::bind_method(D_METHOD("get_rollbacks"), &CgameRollbackDebugger::get_rollbacks);
	ClassDB::bind_method(D_METHOD("get_desyncs"), &CgameRollbackDebugger::get_desyncs);
	ClassDB::bind_method(D_METHOD("get_late_inputs"), &CgameRollbackDebugger::get_late_inputs);
	ClassDB::bind_method(D_METHOD("get_mispredictions"), &CgameRollbackDebugger::get_mispredictions);

	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "net", PROPERTY_HINT_RESOURCE_TYPE, "CgameRollbackNetcode", PROPERTY_USAGE_NONE), "attach", "get_net");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "rollbacks"), "", "get_rollbacks");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "desyncs"), "", "get_desyncs");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "late_inputs"), "", "get_late_inputs");
	ADD_PROPERTY(PropertyInfo(Variant::DICTIONARY, "mispredictions"), "", "get_mispredictions");
}
