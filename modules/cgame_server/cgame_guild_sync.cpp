/**************************************************************************/
/*  cgame_guild_sync.cpp                                                  */
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

#include "cgame_guild_sync.h"

int64_t CgameGuildSync::_ts() const {
	return (int64_t(clock) << 10) | int64_t(server_id);
}

int64_t CgameGuildSync::_ts_clock(int64_t p_ts) {
	return p_ts >> 10;
}

Dictionary CgameGuildSync::_doc(const String &p_gid) {
	if (!guilds.has(p_gid)) {
		Dictionary d;
		d["id"] = p_gid;
		d["members"] = Dictionary();
		Dictionary motd;
		motd["text"] = "";
		motd["ts"] = 0;
		d["motd"] = motd;
		d["treasury"] = Dictionary();
		d["version"] = 0;
		guilds[p_gid] = d;
	}
	return guilds[p_gid];
}

// ------------------------------------------------------------------ local edits

Dictionary CgameGuildSync::_local(const String &p_gid, const String &p_type, const Dictionary &p_args) {
	clock++;
	seq++;
	Dictionary op;
	op["id"] = itos(server_id) + ":" + itos(seq);
	op["origin"] = server_id;
	op["seq"] = seq;
	op["gid"] = p_gid;
	op["type"] = p_type;
	op["args"] = p_args;
	op["ts"] = _ts();
	_apply(op);
	return op;
}

Dictionary CgameGuildSync::join(const String &p_gid, const String &p_pid, int p_rank) {
	int64_t kick_ts = 0;
	Dictionary d = _doc(p_gid);
	Dictionary members = d["members"];
	if (members.has(p_pid)) {
		Dictionary m = members[p_pid];
		kick_ts = int64_t(m["kick_ts"]);
	}
	Dictionary args;
	args["pid"] = p_pid;
	args["rank"] = p_rank;
	args["seen_kick"] = kick_ts;
	return _local(p_gid, "join", args);
}

Dictionary CgameGuildSync::set_rank(const String &p_gid, const String &p_pid, int p_rank) {
	Dictionary args;
	args["pid"] = p_pid;
	args["rank"] = p_rank;
	return _local(p_gid, "rank", args);
}

Dictionary CgameGuildSync::kick(const String &p_gid, const String &p_pid) {
	Dictionary args;
	args["pid"] = p_pid;
	return _local(p_gid, "kick", args);
}

Dictionary CgameGuildSync::set_motd(const String &p_gid, const String &p_text) {
	Dictionary args;
	args["text"] = p_text;
	return _local(p_gid, "motd", args);
}

Dictionary CgameGuildSync::deposit(const String &p_gid, int p_amount) {
	Dictionary args;
	args["amount"] = p_amount;
	return _local(p_gid, "deposit", args);
}

// ------------------------------------------------------------------ replication

// Applies a remote op. Returns true if it was new. Safe to call repeatedly and out of order.
bool CgameGuildSync::receive(const Dictionary &p_op) {
	const String id = String(p_op["id"]);
	if (log.has(id)) {
		return false;
	}
	clock = MAX(int64_t(clock), _ts_clock(int64_t(p_op["ts"])));
	_apply(p_op);
	return true;
}

Array CgameGuildSync::ops_after(const Dictionary &p_remote_vv) const {
	Array out;
	Array ids = log.keys();
	for (int i = 0; i < ids.size(); i++) {
		Dictionary op = log[ids[i]];
		const String origin = itos(int(op["origin"]));
		if (int(op["seq"]) > int(p_remote_vv.get(origin, 0))) {
			out.push_back(op);
		}
	}
	return out;
}

Dictionary CgameGuildSync::_vv_strkeys() const {
	Dictionary out;
	Array keys = vv.keys();
	for (int i = 0; i < keys.size(); i++) {
		out[String(keys[i])] = vv[keys[i]];
	}
	return out;
}

// Pull-based anti-entropy from another replica. Returns the number of new ops applied.
int CgameGuildSync::sync_from(Object *p_other) {
	ERR_FAIL_NULL_V(p_other, 0);
	int n = 0;
	Array ops = p_other->call("ops_after", _vv_strkeys());
	cgame_sort_array(ops, [](const Variant &p_a, const Variant &p_b) {
		Dictionary a = p_a;
		Dictionary b = p_b;
		return int64_t(a["ts"]) < int64_t(b["ts"]);
	});
	for (int i = 0; i < ops.size(); i++) {
		if (receive(ops[i])) {
			n++;
		}
	}
	return n;
}

void CgameGuildSync::_apply(const Dictionary &p_op) {
	const String id = String(p_op["id"]);
	log[id] = p_op;
	const int origin = int(p_op["origin"]);
	const String key = itos(origin);
	int top = int(vv.get(key, 0));
	while (log.has(itos(origin) + ":" + itos(top + 1))) {
		top++;
	}
	vv[key] = top;
	Dictionary d = _doc(String(p_op["gid"]));
	d["version"] = int(d["version"]) + 1;
	const int64_t ts = int64_t(p_op["ts"]);
	Dictionary args = p_op["args"];
	const String type = String(p_op["type"]);
	if (type == "motd") {
		Dictionary motd = d["motd"];
		if (ts > int64_t(motd["ts"])) {
			motd["ts"] = ts;
			motd["text"] = String(args["text"]);
		}
	} else if (type == "deposit") {
		Dictionary tre = d["treasury"];
		tre[id] = int(args["amount"]);
	} else {
		Dictionary m = _member(d, String(args["pid"]));
		if (type == "join") {
			if (ts > int64_t(m["join_ts"])) {
				m["join_ts"] = ts;
				m["join_seen"] = int64_t(args["seen_kick"]);
			}
			_set_rank(m, int(args["rank"]), ts);
		} else if (type == "rank") {
			_set_rank(m, int(args["rank"]), ts);
		} else if (type == "kick") {
			m["kick_ts"] = MAX(int64_t(m["kick_ts"]), ts);
		}
	}
}

Dictionary CgameGuildSync::_member(const Dictionary &p_doc, const String &p_pid) {
	Dictionary members = p_doc["members"];
	if (!members.has(p_pid)) {
		Dictionary m;
		m["rank"] = 0;
		m["rank_ts"] = 0;
		m["join_ts"] = 0;
		m["join_seen"] = 0;
		m["kick_ts"] = 0;
		members[p_pid] = m;
	}
	return members[p_pid];
}

void CgameGuildSync::_set_rank(const Dictionary &p_member, int p_rank, int64_t p_ts) {
	Dictionary m = p_member;
	if (p_ts > int64_t(m["rank_ts"])) {
		m["rank_ts"] = p_ts;
		m["rank"] = p_rank;
	}
}

// ------------------------------------------------------------------ queries

bool CgameGuildSync::_present(const Dictionary &p_member) {
	if (int64_t(p_member["join_ts"]) == 0) {
		return false;
	}
	return int64_t(p_member["kick_ts"]) == 0 || int64_t(p_member["join_seen"]) >= int64_t(p_member["kick_ts"]);
}

bool CgameGuildSync::is_member(const String &p_gid, const String &p_pid) const {
	if (!guilds.has(p_gid)) {
		return false;
	}
	Dictionary g = guilds[p_gid];
	Dictionary members = g["members"];
	if (!members.has(p_pid)) {
		return false;
	}
	return _present(members[p_pid]);
}

int CgameGuildSync::rank_of(const String &p_gid, const String &p_pid) const {
	if (!is_member(p_gid, p_pid)) {
		return -1;
	}
	Dictionary g = guilds[p_gid];
	Dictionary members = g["members"];
	Dictionary m = members[p_pid];
	return int(m["rank"]);
}

Array CgameGuildSync::members(const String &p_gid) const {
	Array out;
	if (guilds.has(p_gid)) {
		Dictionary g = guilds[p_gid];
		Dictionary ms = g["members"];
		Array pids = ms.keys();
		for (int i = 0; i < pids.size(); i++) {
			if (_present(ms[pids[i]])) {
				out.push_back(pids[i]);
			}
		}
	}
	out.sort();
	return out;
}

String CgameGuildSync::motd(const String &p_gid) const {
	if (!guilds.has(p_gid)) {
		return "";
	}
	Dictionary g = guilds[p_gid];
	Dictionary m = g["motd"];
	return String(m["text"]);
}

int CgameGuildSync::treasury(const String &p_gid) const {
	int sum = 0;
	if (guilds.has(p_gid)) {
		Dictionary g = guilds[p_gid];
		Dictionary tre = g["treasury"];
		Array ids = tre.keys();
		for (int i = 0; i < ids.size(); i++) {
			sum += int(tre[ids[i]]);
		}
	}
	return sum;
}

int CgameGuildSync::version(const String &p_gid) const {
	if (!guilds.has(p_gid)) {
		return 0;
	}
	Dictionary g = guilds[p_gid];
	return int(g["version"]);
}

// Canonical string of the player-visible state; equal digests mean converged replicas.
String CgameGuildSync::digest(const String &p_gid) const {
	PackedStringArray parts;
	Array ms = members(p_gid);
	for (int i = 0; i < ms.size(); i++) {
		parts.push_back(String(ms[i]) + "=" + itos(rank_of(p_gid, String(ms[i]))));
	}
	return "m[" + String(",").join(parts) + "]|motd=" + motd(p_gid) + "|gold=" + itos(treasury(p_gid));
}

void CgameGuildSync::_bind_methods() {
	CGAME_BIND_PROPERTY(CgameGuildSync, Variant::INT, server_id)
	CGAME_BIND_PROPERTY(CgameGuildSync, Variant::INT, clock)
	CGAME_BIND_PROPERTY(CgameGuildSync, Variant::DICTIONARY, guilds)
	CGAME_BIND_PROPERTY(CgameGuildSync, Variant::DICTIONARY, log)
	CGAME_BIND_PROPERTY(CgameGuildSync, Variant::DICTIONARY, vv)

	ClassDB::bind_method(D_METHOD("join", "gid", "pid", "rank"), &CgameGuildSync::join);
	ClassDB::bind_method(D_METHOD("set_rank", "gid", "pid", "rank"), &CgameGuildSync::set_rank);
	ClassDB::bind_method(D_METHOD("kick", "gid", "pid"), &CgameGuildSync::kick);
	ClassDB::bind_method(D_METHOD("set_motd", "gid", "text"), &CgameGuildSync::set_motd);
	ClassDB::bind_method(D_METHOD("deposit", "gid", "amount"), &CgameGuildSync::deposit);
	ClassDB::bind_method(D_METHOD("receive", "op"), &CgameGuildSync::receive);
	ClassDB::bind_method(D_METHOD("ops_after", "remote_vv"), &CgameGuildSync::ops_after);
	ClassDB::bind_method(D_METHOD("sync_from", "other"), &CgameGuildSync::sync_from);
	ClassDB::bind_method(D_METHOD("is_member", "gid", "pid"), &CgameGuildSync::is_member);
	ClassDB::bind_method(D_METHOD("rank_of", "gid", "pid"), &CgameGuildSync::rank_of);
	ClassDB::bind_method(D_METHOD("members", "gid"), &CgameGuildSync::members);
	ClassDB::bind_method(D_METHOD("motd", "gid"), &CgameGuildSync::motd);
	ClassDB::bind_method(D_METHOD("treasury", "gid"), &CgameGuildSync::treasury);
	ClassDB::bind_method(D_METHOD("version", "gid"), &CgameGuildSync::version);
	ClassDB::bind_method(D_METHOD("digest", "gid"), &CgameGuildSync::digest);
}
