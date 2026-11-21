/**************************************************************************/
/*  cgame_world_sharding.cpp                                              */
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

#include "cgame_world_sharding.h"

#include "core/math/math_funcs.h"

#include <algorithm>
#include <vector>

double CgameWorldSharding::_load(const Array &p_loads, int p_region) {
	return p_region < p_loads.size() ? double(p_loads[p_region]) : 0.0;
}

void CgameWorldSharding::setup(int p_cols, int p_rows, double p_cell, int p_servers) {
	cols = p_cols;
	rows = p_rows;
	cell_size = p_cell;
	server_count = MAX(1, p_servers);
	region_owner = PackedInt32Array();
	region_owner.resize(cols * rows);
	region_owner.fill(0);
}

int CgameWorldSharding::region_count() const {
	return cols * rows;
}

int CgameWorldSharding::region_of(const Vector2 &p_pos) const {
	const int cx = CLAMP(int(Math::floor(p_pos.x / cell_size)), 0, cols - 1);
	const int cy = CLAMP(int(Math::floor(p_pos.y / cell_size)), 0, rows - 1);
	return cy * cols + cx;
}

int CgameWorldSharding::owner_at(const Vector2 &p_pos) const {
	return region_owner[region_of(p_pos)];
}

Array CgameWorldSharding::server_loads(const Array &p_loads) const {
	std::vector<double> sums(server_count, 0.0);
	for (int r = 0; r < region_count(); r++) {
		const int s = region_owner[r];
		sums[s] += _load(p_loads, r);
	}
	Array out;
	for (double v : sums) {
		out.push_back(v);
	}
	return out;
}

// Greedy LPT: heaviest regions first onto the least-loaded server (ties: fewest regions).
void CgameWorldSharding::assign_initial(const Array &p_loads) {
	std::vector<int> order;
	for (int r = 0; r < region_count(); r++) {
		order.push_back(r);
	}
	std::sort(order.begin(), order.end(), [&](int a, int b) {
		const double la = _load(p_loads, a);
		const double lb = _load(p_loads, b);
		if (la != lb) {
			return la > lb;
		}
		return a < b;
	});
	std::vector<double> sload(server_count, 0.0);
	std::vector<int> scount(server_count, 0);
	for (int r : order) {
		int best = 0;
		for (int s = 1; s < server_count; s++) {
			if (sload[s] < sload[best] || (sload[s] == sload[best] && scount[s] < scount[best])) {
				best = s;
			}
		}
		region_owner.write[r] = best;
		sload[best] += _load(p_loads, r);
		scount[best] += 1;
	}
}

// Moves a region only when that strictly lowers the peak load, and not at all while the loads are
// within the hysteresis band.
Array CgameWorldSharding::rebalance(const Array &p_loads) {
	Array moves;
	for (int i = 0; i < max_moves; i++) {
		Array sl = server_loads(p_loads);
		int hot = 0;
		int cold = 0;
		for (int s = 0; s < server_count; s++) {
			if (double(sl[s]) > double(sl[hot])) {
				hot = s;
			}
			if (double(sl[s]) < double(sl[cold])) {
				cold = s;
			}
		}
		const double hl = sl[hot];
		const double cl = sl[cold];
		if (hot == cold || hl <= cl * imbalance_ratio || hl <= 0.0) {
			break;
		}
		const double gap = hl - cl;
		int pick = -1;
		double pick_err = Math::INF;
		for (int r = 0; r < region_count(); r++) {
			if (region_owner[r] != hot) {
				continue;
			}
			const double rl = _load(p_loads, r);
			if (rl <= 0.0 || rl >= gap) {
				continue;
			}
			const double err = Math::abs(rl - gap * 0.5);
			if (err < pick_err) {
				pick_err = err;
				pick = r;
			}
		}
		if (pick < 0) {
			break;
		}
		region_owner.write[pick] = cold;
		Dictionary move;
		move["region"] = pick;
		move["from"] = hot;
		move["to"] = cold;
		moves.push_back(move);
	}
	return moves;
}

// ------------------------------------------------------------------ ownership/ghosts

void CgameWorldSharding::claim_entity(const String &p_entity_id, int p_server) {
	entity_owner[p_entity_id] = p_server;
}

int CgameWorldSharding::owner_of(const String &p_entity_id) const {
	return int(entity_owner.get(p_entity_id, -1));
}

Array CgameWorldSharding::entities_on(int p_server) const {
	Array out;
	Array ids = entity_owner.keys();
	for (int i = 0; i < ids.size(); i++) {
		if (int(entity_owner[ids[i]]) == p_server) {
			out.push_back(ids[i]);
		}
	}
	return out;
}

// Servers (other than the owner) whose regions fall within border_margin of the position.
Array CgameWorldSharding::ghost_servers(const Vector2 &p_pos, int p_owner) const {
	Array out;
	const int x0 = CLAMP(int(Math::floor((p_pos.x - border_margin) / cell_size)), 0, cols - 1);
	const int x1 = CLAMP(int(Math::floor((p_pos.x + border_margin) / cell_size)), 0, cols - 1);
	const int y0 = CLAMP(int(Math::floor((p_pos.y - border_margin) / cell_size)), 0, rows - 1);
	const int y1 = CLAMP(int(Math::floor((p_pos.y + border_margin) / cell_size)), 0, rows - 1);
	for (int cy = y0; cy <= y1; cy++) {
		for (int cx = x0; cx <= x1; cx++) {
			const int s = region_owner[cy * cols + cx];
			if (s != p_owner && !out.has(s)) {
				out.push_back(s);
			}
		}
	}
	out.sort();
	return out;
}

int CgameWorldSharding::handoff_needed(const Vector2 &p_player_pos, int p_current_server) const {
	const int target = owner_at(p_player_pos);
	if (target == p_current_server) {
		return -1;
	}
	const Vector2 offsets[4] = {
		Vector2(handoff_hysteresis, 0), Vector2(-handoff_hysteresis, 0),
		Vector2(0, handoff_hysteresis), Vector2(0, -handoff_hysteresis)
	};
	for (const Vector2 &off : offsets) {
		if (owner_at(p_player_pos + off) == p_current_server) {
			return -1; // Still hugging the old border: avoid ping-pong.
		}
	}
	return target;
}

void CgameWorldSharding::track_player(const String &p_player_id, const Vector2 &p_pos, int p_server) {
	Dictionary p;
	p["pos"] = p_pos;
	p["state"] = "stable";
	p["transfer"] = "";
	p["ghosts"] = ghost_servers(p_pos, p_server);
	players[p_player_id] = p;
	entity_owner[p_player_id] = p_server;
}

Dictionary CgameWorldSharding::update_player(const String &p_player_id, const Vector2 &p_pos) {
	Dictionary result;
	if (!players.has(p_player_id)) {
		result["ghosts"] = Array();
		result["handoff_to"] = -1;
		return result;
	}
	Dictionary p = players[p_player_id];
	p["pos"] = p_pos;
	const int srv = owner_of(p_player_id);
	p["ghosts"] = ghost_servers(p_pos, srv);
	int target = -1;
	if (String(p["state"]) == "stable") {
		target = handoff_needed(p_pos, srv);
	}
	result["ghosts"] = p["ghosts"];
	result["handoff_to"] = target;
	return result;
}

// ------------------------------------------------------------ two-step handoff
// stable -> frozen (begin) -> transferring (send_state) -> acked (ack) -> stable on new owner (release)

// Freezes the player. Idempotent per transfer id; returns the id or "" if rejected.
String CgameWorldSharding::begin_transfer(const String &p_player_id, int p_to_server, const String &p_transfer_id) {
	if (transfers.has(p_transfer_id)) {
		return p_transfer_id; // Duplicate request: ignored, no state change.
	}
	if (!players.has(p_player_id)) {
		return "";
	}
	Dictionary p = players[p_player_id];
	if (String(p["state"]) != "stable") {
		return "";
	}
	const int from = owner_of(p_player_id);
	if (from == p_to_server) {
		return "";
	}
	Dictionary tr;
	tr["player"] = p_player_id;
	tr["from"] = from;
	tr["to"] = p_to_server;
	tr["state"] = "frozen";
	tr["payload"] = Dictionary();
	transfers[p_transfer_id] = tr;
	p["state"] = "frozen";
	p["transfer"] = p_transfer_id;
	return p_transfer_id;
}

bool CgameWorldSharding::send_state(const String &p_transfer_id, const Dictionary &p_payload) {
	if (!transfers.has(p_transfer_id)) {
		return false;
	}
	Dictionary tr = transfers[p_transfer_id];
	if (String(tr["state"]) != "frozen") {
		return String(tr["state"]) != "aborted"; // Already past this step: idempotent.
	}
	tr["payload"] = p_payload.duplicate(true);
	tr["state"] = "transferring";
	return true;
}

// The destination confirms it has the state.
bool CgameWorldSharding::ack_transfer(const String &p_transfer_id) {
	if (!transfers.has(p_transfer_id)) {
		return false;
	}
	Dictionary tr = transfers[p_transfer_id];
	const String st = tr["state"];
	if (st == "transferring") {
		tr["state"] = "acked";
		return true;
	}
	return st == "acked" || st == "done";
}

// The source releases authority; ownership flips to the destination. Idempotent.
bool CgameWorldSharding::release_transfer(const String &p_transfer_id) {
	if (!transfers.has(p_transfer_id)) {
		return false;
	}
	Dictionary tr = transfers[p_transfer_id];
	const String st = tr["state"];
	if (st == "done") {
		return true;
	}
	if (st != "acked") {
		return false;
	}
	const String pid = tr["player"];
	entity_owner[pid] = int(tr["to"]);
	Dictionary p = players[pid];
	p["state"] = "stable";
	p["transfer"] = "";
	p["ghosts"] = ghost_servers(p["pos"], int(tr["to"]));
	tr["state"] = "done";
	return true;
}

// Cancels an unfinished transfer (e.g. destination timeout); the player unfreezes on the source.
bool CgameWorldSharding::abort_transfer(const String &p_transfer_id) {
	if (!transfers.has(p_transfer_id)) {
		return false;
	}
	Dictionary tr = transfers[p_transfer_id];
	const String st = tr["state"];
	if (st == "done" || st == "aborted") {
		return false;
	}
	tr["state"] = "aborted";
	Dictionary p = players[String(tr["player"])];
	p["state"] = "stable";
	p["transfer"] = "";
	return true;
}

void CgameWorldSharding::_bind_methods() {
	CGAME_BIND_PROPERTY(CgameWorldSharding, Variant::FLOAT, cell_size)
	CGAME_BIND_PROPERTY(CgameWorldSharding, Variant::INT, cols)
	CGAME_BIND_PROPERTY(CgameWorldSharding, Variant::INT, rows)
	CGAME_BIND_PROPERTY(CgameWorldSharding, Variant::INT, server_count)
	CGAME_BIND_PROPERTY(CgameWorldSharding, Variant::FLOAT, border_margin)
	CGAME_BIND_PROPERTY(CgameWorldSharding, Variant::FLOAT, handoff_hysteresis)
	CGAME_BIND_PROPERTY(CgameWorldSharding, Variant::FLOAT, imbalance_ratio)
	CGAME_BIND_PROPERTY(CgameWorldSharding, Variant::INT, max_moves)
	CGAME_BIND_PROPERTY(CgameWorldSharding, Variant::PACKED_INT32_ARRAY, region_owner)
	CGAME_BIND_PROPERTY(CgameWorldSharding, Variant::DICTIONARY, entity_owner)
	CGAME_BIND_PROPERTY(CgameWorldSharding, Variant::DICTIONARY, players)
	CGAME_BIND_PROPERTY(CgameWorldSharding, Variant::DICTIONARY, transfers)

	ClassDB::bind_method(D_METHOD("setup", "cols", "rows", "cell", "servers"), &CgameWorldSharding::setup);
	ClassDB::bind_method(D_METHOD("region_count"), &CgameWorldSharding::region_count);
	ClassDB::bind_method(D_METHOD("region_of", "pos"), &CgameWorldSharding::region_of);
	ClassDB::bind_method(D_METHOD("owner_at", "pos"), &CgameWorldSharding::owner_at);
	ClassDB::bind_method(D_METHOD("server_loads", "loads"), &CgameWorldSharding::server_loads);
	ClassDB::bind_method(D_METHOD("assign_initial", "loads"), &CgameWorldSharding::assign_initial);
	ClassDB::bind_method(D_METHOD("rebalance", "loads"), &CgameWorldSharding::rebalance);
	ClassDB::bind_method(D_METHOD("claim_entity", "entity_id", "server"), &CgameWorldSharding::claim_entity);
	ClassDB::bind_method(D_METHOD("owner_of", "entity_id"), &CgameWorldSharding::owner_of);
	ClassDB::bind_method(D_METHOD("entities_on", "server"), &CgameWorldSharding::entities_on);
	ClassDB::bind_method(D_METHOD("ghost_servers", "pos", "owner"), &CgameWorldSharding::ghost_servers);
	ClassDB::bind_method(D_METHOD("handoff_needed", "player_pos", "current_server"), &CgameWorldSharding::handoff_needed);
	ClassDB::bind_method(D_METHOD("track_player", "player_id", "pos", "server"), &CgameWorldSharding::track_player);
	ClassDB::bind_method(D_METHOD("update_player", "player_id", "pos"), &CgameWorldSharding::update_player);
	ClassDB::bind_method(D_METHOD("begin_transfer", "player_id", "to_server", "transfer_id"), &CgameWorldSharding::begin_transfer);
	ClassDB::bind_method(D_METHOD("send_state", "transfer_id", "payload"), &CgameWorldSharding::send_state);
	ClassDB::bind_method(D_METHOD("ack_transfer", "transfer_id"), &CgameWorldSharding::ack_transfer);
	ClassDB::bind_method(D_METHOD("release_transfer", "transfer_id"), &CgameWorldSharding::release_transfer);
	ClassDB::bind_method(D_METHOD("abort_transfer", "transfer_id"), &CgameWorldSharding::abort_transfer);
}
