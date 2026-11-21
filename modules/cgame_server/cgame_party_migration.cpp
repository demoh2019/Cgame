/**************************************************************************/
/*  cgame_party_migration.cpp                                             */
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

#include "cgame_party_migration.h"

#include "core/io/json.h"

bool CgamePartyMigration::has_party(const String &p_id) const {
	return parties.has(p_id);
}

Dictionary CgamePartyMigration::get_doc(const String &p_id) const {
	if (!parties.has(p_id)) {
		return Dictionary();
	}
	return parties[p_id];
}

Dictionary CgamePartyMigration::snapshot(const String &p_id) const {
	return get_doc(p_id).duplicate(true);
}

// Creates a party led by the leader, who is hosted on this server (this server becomes home).
bool CgamePartyMigration::create(const String &p_id, const String &p_leader) {
	if (parties.has(p_id)) {
		return false;
	}
	Dictionary doc;
	doc["id"] = p_id;
	doc["leader"] = p_leader;
	doc["home"] = server_id;
	doc["epoch"] = 1;
	doc["version"] = 1;
	Dictionary members;
	members[p_leader] = server_id;
	doc["members"] = members;
	parties[p_id] = doc;
	return true;
}

bool CgamePartyMigration::_mutable(const String &p_id) const {
	if (!parties.has(p_id)) {
		return false;
	}
	Dictionary doc = parties[p_id];
	return int(doc["home"]) == server_id;
}

void CgamePartyMigration::_bump(const Dictionary &p_doc) {
	Dictionary doc = p_doc;
	doc["version"] = int(doc["version"]) + 1;
}

bool CgamePartyMigration::add_member(const String &p_id, const String &p_pid, int p_server) {
	if (!_mutable(p_id)) {
		return false;
	}
	Dictionary doc = parties[p_id];
	Dictionary ms = doc["members"];
	if (ms.has(p_pid)) {
		return false;
	}
	ms[p_pid] = p_server;
	_bump(doc);
	return true;
}

// Removing the leader promotes the lowest-sorted remaining member; an empty party disbands.
bool CgamePartyMigration::remove_member(const String &p_id, const String &p_pid) {
	if (!_mutable(p_id)) {
		return false;
	}
	Dictionary doc = parties[p_id];
	Dictionary ms = doc["members"];
	if (!ms.has(p_pid)) {
		return false;
	}
	ms.erase(p_pid);
	if (ms.is_empty()) {
		parties.erase(p_id);
		return true;
	}
	if (String(doc["leader"]) == p_pid) {
		Array rest = ms.keys();
		rest.sort();
		doc["leader"] = rest[0];
		doc["home"] = int(ms[rest[0]]);
		doc["epoch"] = int(doc["epoch"]) + 1;
	}
	_bump(doc);
	return true;
}

bool CgamePartyMigration::set_member_server(const String &p_id, const String &p_pid, int p_server) {
	if (!_mutable(p_id)) {
		return false;
	}
	Dictionary doc = parties[p_id];
	Dictionary ms = doc["members"];
	if (!ms.has(p_pid) || int(ms[p_pid]) == p_server) {
		return false;
	}
	ms[p_pid] = p_server;
	_bump(doc);
	return true;
}

// The leader moved to the destination: authority (home) follows and the epoch is bumped. Must be
// called on the current home. Returns the snapshot to replicate (empty if refused).
Dictionary CgamePartyMigration::leader_handoff(const String &p_id, int p_dest) {
	if (!_mutable(p_id)) {
		return Dictionary();
	}
	Dictionary doc = parties[p_id];
	Dictionary ms = doc["members"];
	ms[String(doc["leader"])] = p_dest;
	doc["home"] = p_dest;
	doc["epoch"] = int(doc["epoch"]) + 1;
	_bump(doc);
	return doc.duplicate(true);
}

// Members that should follow the leader to the destination. An optional `nearby` list restricts
// the plan to members close enough to follow; empty means everyone.
Array CgamePartyMigration::follow_plan(const String &p_id, int p_dest, const Array &p_nearby) const {
	Array out;
	if (!parties.has(p_id)) {
		return out;
	}
	Dictionary doc = parties[p_id];
	Dictionary ms = doc["members"];
	Array ids = ms.keys();
	ids.sort();
	for (int i = 0; i < ids.size(); i++) {
		const Variant pid = ids[i];
		if (pid == doc["leader"] || int(ms[pid]) == p_dest) {
			continue;
		}
		if (p_nearby.is_empty() || p_nearby.has(pid)) {
			Dictionary step;
			step["player"] = pid;
			step["from"] = int(ms[pid]);
			step["to"] = p_dest;
			out.push_back(step);
		}
	}
	return out;
}

bool CgamePartyMigration::_newer(const Dictionary &p_a, const Dictionary &p_b) {
	if (int(p_a["epoch"]) != int(p_b["epoch"])) {
		return int(p_a["epoch"]) > int(p_b["epoch"]);
	}
	return int(p_a["version"]) > int(p_b["version"]);
}

// Installs a snapshot if it is newer by (epoch, version). Returns true if it changed anything.
bool CgamePartyMigration::apply_replica(const Dictionary &p_doc) {
	const String id = String(p_doc["id"]);
	if (parties.has(id) && !_newer(p_doc, parties[id])) {
		return false;
	}
	parties[id] = p_doc.duplicate(true);
	return true;
}

// Every server that hosts a member (plus the home), sorted.
Array CgamePartyMigration::servers_of(const String &p_id) const {
	Dictionary seen;
	if (parties.has(p_id)) {
		Dictionary doc = parties[p_id];
		seen[int(doc["home"])] = true;
		Dictionary ms = doc["members"];
		Array pids = ms.keys();
		for (int i = 0; i < pids.size(); i++) {
			seen[int(ms[pids[i]])] = true;
		}
	}
	Array out = seen.keys();
	out.sort();
	return out;
}

bool CgamePartyMigration::same_as(Object *p_other, const String &p_id) const {
	ERR_FAIL_NULL_V(p_other, false);
	return JSON::stringify(get_doc(p_id)) == JSON::stringify(p_other->call("get_doc", p_id));
}

void CgamePartyMigration::_bind_methods() {
	CGAME_BIND_PROPERTY(CgamePartyMigration, Variant::INT, server_id)
	CGAME_BIND_PROPERTY(CgamePartyMigration, Variant::DICTIONARY, parties)

	ClassDB::bind_method(D_METHOD("has_party", "id"), &CgamePartyMigration::has_party);
	ClassDB::bind_method(D_METHOD("get_doc", "id"), &CgamePartyMigration::get_doc);
	ClassDB::bind_method(D_METHOD("snapshot", "id"), &CgamePartyMigration::snapshot);
	ClassDB::bind_method(D_METHOD("create", "id", "leader"), &CgamePartyMigration::create);
	ClassDB::bind_method(D_METHOD("add_member", "id", "pid", "server"), &CgamePartyMigration::add_member);
	ClassDB::bind_method(D_METHOD("remove_member", "id", "pid"), &CgamePartyMigration::remove_member);
	ClassDB::bind_method(D_METHOD("set_member_server", "id", "pid", "server"), &CgamePartyMigration::set_member_server);
	ClassDB::bind_method(D_METHOD("leader_handoff", "id", "dest"), &CgamePartyMigration::leader_handoff);
	ClassDB::bind_method(D_METHOD("follow_plan", "id", "dest", "nearby"), &CgamePartyMigration::follow_plan, DEFVAL(Array()));
	ClassDB::bind_method(D_METHOD("apply_replica", "doc"), &CgamePartyMigration::apply_replica);
	ClassDB::bind_method(D_METHOD("servers_of", "id"), &CgamePartyMigration::servers_of);
	ClassDB::bind_method(D_METHOD("same_as", "other", "id"), &CgamePartyMigration::same_as);
}
