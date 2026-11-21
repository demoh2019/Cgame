/**************************************************************************/
/*  cgame_replay_recorder.cpp                                             */
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

#include "cgame_replay_recorder.h"

#include "core/io/file_access.h"
#include "core/io/json.h"

void CgameReplayRecorder::add_initial_player(int p_peer, const String &p_name) {
	Dictionary info;
	info["id"] = p_peer;
	info["name"] = p_name;
	players.push_back(info);
}

// Queues a command for the tick being recorded. Refused methods return false.
bool CgameReplayRecorder::record_command(int p_peer, const String &p_method, const Array &p_args) {
	if (!is_allowed_method(p_method)) {
		return false;
	}
	Dictionary cmd;
	cmd["peer"] = p_peer;
	cmd["method"] = p_method;
	cmd["args"] = p_args.duplicate(true);
	pending.push_back(cmd);
	return true;
}

// Closes the current tick with the delta passed to server.tick().
void CgameReplayRecorder::end_tick(double p_delta) {
	Dictionary frame;
	frame["tick"] = tick;
	frame["delta"] = p_delta;
	frame["commands"] = pending;
	frames.push_back(frame);
	pending = Array();
	tick++;
}

bool CgameReplayRecorder::is_allowed_method(const String &p_method) {
	return p_method.begins_with("cmd_") || p_method == "submit_input";
}

Dictionary CgameReplayRecorder::to_dict() const {
	Dictionary d;
	d["format"] = FORMAT_VERSION;
	d["seed"] = seed_value;
	d["world_seed"] = world_seed;
	d["players"] = players.duplicate(true);
	d["frames"] = frames.duplicate(true);
	return d;
}

bool CgameReplayRecorder::save(const String &p_path) const {
	Ref<FileAccess> file = FileAccess::open(p_path, FileAccess::WRITE);
	if (file.is_null()) {
		return false;
	}
	file->store_var(to_dict(), false); // No objects: a replay file can never instantiate scripts.
	return true;
}

// Returns the replay Dictionary, or an empty one when the file is missing or malformed.
Dictionary CgameReplayRecorder::load_replay(const String &p_path) {
	if (!FileAccess::exists(p_path)) {
		return Dictionary();
	}
	Ref<FileAccess> file = FileAccess::open(p_path, FileAccess::READ);
	if (file.is_null()) {
		return Dictionary();
	}
	const Variant value = file->get_var(false);
	if (value.get_type() != Variant::DICTIONARY) {
		return Dictionary();
	}
	Dictionary data = value;
	if (int(data.get("format", 0)) != FORMAT_VERSION || data.get("frames", Variant()).get_type() != Variant::ARRAY ||
			data.get("players", Variant()).get_type() != Variant::ARRAY) {
		return Dictionary();
	}
	return data;
}

// Re-runs a replay on make_server.call(seed, world_seed) -> server object. After every tick the
// state is hashed with hash_fn(server): an int result is used as-is, any other value is hashed
// through hash_variant(). Without a hash_fn the server's `capture_state()` result is hashed.
// Returns {"hashes": Array (one int per tick), "rejected": Array[String], "ok": bool}.
Dictionary CgameReplayRecorder::play(const Dictionary &p_replay, const Callable &p_make_server, const Callable &p_hash_fn) {
	Array hashes;
	TypedArray<String> rejected;
	Dictionary result;
	result["hashes"] = hashes;
	result["rejected"] = rejected;
	result["ok"] = false;
	if (p_replay.is_empty() || !p_make_server.is_valid()) {
		return result;
	}
	const Variant server_var = p_make_server.call(int64_t(p_replay.get("seed", 0)), int64_t(p_replay.get("world_seed", 0)));
	if (server_var.get_type() != Variant::OBJECT) {
		return result;
	}
	Object *server = server_var;
	if (!server) {
		return result;
	}
	Array initial = p_replay.get("players", Array());
	for (int i = 0; i < initial.size(); i++) {
		Dictionary info = initial[i];
		server->call("add_player", int(info.get("id", 0)), String(info.get("name", "")));
	}
	Array replay_frames = p_replay.get("frames", Array());
	for (int i = 0; i < replay_frames.size(); i++) {
		Dictionary frame = replay_frames[i];
		Array commands = frame.get("commands", Array());
		for (int j = 0; j < commands.size(); j++) {
			Dictionary cmd = commands[j];
			const String method = String(cmd.get("method", ""));
			if (!is_allowed_method(method) || !server->has_method(method)) {
				rejected.push_back(vformat("tick %d: %s", int(frame.get("tick", -1)), method));
				continue;
			}
			Array call_args;
			call_args.push_back(int(cmd.get("peer", 0)));
			call_args.append_array(cmd.get("args", Array()));
			server->callv(method, call_args);
		}
		server->call("tick", double(frame.get("delta", 0.0)));
		Variant projection;
		if (p_hash_fn.is_valid()) {
			projection = p_hash_fn.call(server_var);
		} else if (server->has_method("capture_state")) {
			projection = server->call("capture_state");
		}
		hashes.push_back(projection.get_type() == Variant::INT ? int64_t(projection) : hash_variant(projection));
	}
	result["ok"] = rejected.is_empty();
	return result;
}

// 64-bit FNV-1a (public domain, Fowler/Noll/Vo) over the UTF-8 bytes of the text.
int64_t CgameReplayRecorder::fnv1a(const String &p_text) {
	uint64_t h = FNV_OFFSET;
	const CharString utf8 = p_text.utf8();
	for (int i = 0; i < utf8.length(); i++) {
		h = (h ^ uint64_t(uint8_t(utf8[i]))) * FNV_PRIME; // Modular multiply: wraparound intended.
	}
	return int64_t(h);
}

// FNV-1a over the canonical (sorted-key) JSON text of any value.
int64_t CgameReplayRecorder::hash_variant(const Variant &p_value) {
	return fnv1a(JSON::stringify(p_value, "", true));
}

// First tick index at which two hash lists differ (a length mismatch counts), else -1.
int CgameReplayRecorder::compare(const Array &p_a_hashes, const Array &p_b_hashes) {
	const int shared = MIN(p_a_hashes.size(), p_b_hashes.size());
	for (int i = 0; i < shared; i++) {
		if (int64_t(p_a_hashes[i]) != int64_t(p_b_hashes[i])) {
			return i;
		}
	}
	if (p_a_hashes.size() != p_b_hashes.size()) {
		return shared;
	}
	return -1;
}

void CgameReplayRecorder::_bind_methods() {
	CGAME_BIND_PROPERTY(CgameReplayRecorder, Variant::INT, seed_value)
	CGAME_BIND_PROPERTY(CgameReplayRecorder, Variant::INT, world_seed)
	CGAME_BIND_PROPERTY(CgameReplayRecorder, Variant::ARRAY, players)
	CGAME_BIND_PROPERTY(CgameReplayRecorder, Variant::ARRAY, frames)

	ClassDB::bind_method(D_METHOD("add_initial_player", "peer", "name"), &CgameReplayRecorder::add_initial_player);
	ClassDB::bind_method(D_METHOD("record_command", "peer", "method", "args"), &CgameReplayRecorder::record_command, DEFVAL(Array()));
	ClassDB::bind_method(D_METHOD("end_tick", "delta"), &CgameReplayRecorder::end_tick);
	ClassDB::bind_static_method("CgameReplayRecorder", D_METHOD("is_allowed_method", "method"), &CgameReplayRecorder::is_allowed_method);
	ClassDB::bind_method(D_METHOD("to_dict"), &CgameReplayRecorder::to_dict);
	ClassDB::bind_method(D_METHOD("save", "path"), &CgameReplayRecorder::save);
	ClassDB::bind_static_method("CgameReplayRecorder", D_METHOD("load", "path"), &CgameReplayRecorder::load_replay);
	ClassDB::bind_static_method("CgameReplayRecorder", D_METHOD("play", "replay", "make_server", "hash_fn"), &CgameReplayRecorder::play, DEFVAL(Callable()));
	ClassDB::bind_static_method("CgameReplayRecorder", D_METHOD("fnv1a", "text"), &CgameReplayRecorder::fnv1a);
	ClassDB::bind_static_method("CgameReplayRecorder", D_METHOD("hash_variant", "value"), &CgameReplayRecorder::hash_variant);
	ClassDB::bind_static_method("CgameReplayRecorder", D_METHOD("compare", "a_hashes", "b_hashes"), &CgameReplayRecorder::compare);
}
