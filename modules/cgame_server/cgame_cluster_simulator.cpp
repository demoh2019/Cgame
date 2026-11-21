/**************************************************************************/
/*  cgame_cluster_simulator.cpp                                           */
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

#include "cgame_cluster_simulator.h"

#include "core/math/vector2.h"

static CgameItemLedger *_ledger_at(const Array &p_array, int p_i) {
	return Object::cast_to<CgameItemLedger>(static_cast<Object *>(p_array[p_i]));
}

static CgameGuildSync *_guild_at(const Array &p_array, int p_i) {
	return Object::cast_to<CgameGuildSync>(static_cast<Object *>(p_array[p_i]));
}

static CgamePartyMigration *_party_at(const Array &p_array, int p_i) {
	return Object::cast_to<CgamePartyMigration>(static_cast<Object *>(p_array[p_i]));
}

CgameClusterSimulator::CgameClusterSimulator() {
	rng.instantiate();
	coordinator.instantiate();
	sharding.instantiate();
	leases.instantiate();
	fenced.instantiate();
	stats["moves_committed"] = 0;
	stats["moves_aborted"] = 0;
	stats["moves_crashed"] = 0;
	stats["migrations"] = 0;
	stats["failovers"] = 0;
	stats["server_crashes"] = 0;
	stats["coord_crashes"] = 0;
	stats["region_moves"] = 0;
}

void CgameClusterSimulator::_bump_stat(const String &p_key) {
	stats[p_key] = int(stats[p_key]) + 1;
}

void CgameClusterSimulator::setup(int p_servers, int64_t p_seed, int p_cols, int p_rows, double p_cell) {
	n = p_servers;
	rng->set_seed(p_seed);
	alive.clear();
	ledgers.clear();
	guild_replicas.clear();
	party_dirs.clear();
	for (int i = 0; i < n; i++) {
		alive.push_back(true);
		Ref<CgameItemLedger> l;
		l.instantiate();
		l->set_server_id(i);
		ledgers.push_back(l);
		Ref<CgameGuildSync> g;
		g.instantiate();
		g->set_server_id(i);
		guild_replicas.push_back(g);
		Ref<CgamePartyMigration> p;
		p.instantiate();
		p->set_server_id(i);
		party_dirs.push_back(p);
		coordinator->add_participant("s" + itos(i),
				Callable(this, "_prepare").bind(i),
				Callable(this, "_commit").bind(i),
				Callable(this, "_abort").bind(i));
	}
	sharding->setup(p_cols, p_rows, p_cell, n);
	sharding->assign_initial(Array());
	PackedInt32Array owners = sharding->get_region_owner();
	for (int r = 0; r < sharding->region_count(); r++) {
		_claim_region(r, owners[r]);
	}
}

// Drops the participant callables so nothing outlives the simulator.
void CgameClusterSimulator::teardown() {
	coordinator->clear_participants();
}

Ref<CgameItemLedger> CgameClusterSimulator::ledger(int p_i) const {
	return Ref<CgameItemLedger>(_ledger_at(ledgers, p_i));
}

Ref<CgameGuildSync> CgameClusterSimulator::guilds(int p_i) const {
	return Ref<CgameGuildSync>(_guild_at(guild_replicas, p_i));
}

Ref<CgamePartyMigration> CgameClusterSimulator::parties(int p_i) const {
	return Ref<CgamePartyMigration>(_party_at(party_dirs, p_i));
}

bool CgameClusterSimulator::is_alive(int p_i) const {
	return p_i >= 0 && p_i < alive.size() && bool(alive[p_i]);
}

// ------------------------------------------------------------------ messaging

void CgameClusterSimulator::_send(int p_to, const String &p_kind, const Variant &p_data) {
	msg_seq++;
	Dictionary msg;
	msg["at"] = tick + rng->randi_range(min_latency, max_latency);
	msg["seq"] = msg_seq;
	msg["to"] = p_to;
	msg["kind"] = p_kind;
	msg["data"] = p_data;
	queue.push_back(msg);
}

bool CgameClusterSimulator::_prepare(const String &p_tx_id, const Variant &p_op, int p_server) {
	if (!is_alive(p_server)) {
		return false;
	}
	return _ledger_at(ledgers, p_server)->prepare(p_tx_id, p_op);
}

void CgameClusterSimulator::_commit(const String &p_tx_id, int p_server) {
	_send(p_server, "commit", p_tx_id);
}

void CgameClusterSimulator::_abort(const String &p_tx_id, int p_server) {
	_send(p_server, "abort", p_tx_id);
}

void CgameClusterSimulator::_deliver_due() {
	cgame_sort_array(queue, [](const Variant &p_a, const Variant &p_b) {
		Dictionary a = p_a;
		Dictionary b = p_b;
		const int at_a = a["at"];
		const int at_b = b["at"];
		return at_a < at_b || (at_a == at_b && int(a["seq"]) < int(b["seq"]));
	});
	Array keep;
	for (int i = 0; i < queue.size(); i++) {
		Dictionary msg = queue[i];
		const int to = msg["to"];
		if (int(msg["at"]) > tick || !is_alive(to)) {
			keep.push_back(msg);
			continue;
		}
		const String kind = msg["kind"];
		if (kind == "commit") {
			_ledger_at(ledgers, to)->commit(String(msg["data"]));
		} else if (kind == "abort") {
			_ledger_at(ledgers, to)->abort(String(msg["data"]));
		} else if (kind == "guild_op") {
			_guild_at(guild_replicas, to)->receive(msg["data"]);
		} else if (kind == "party_doc") {
			_party_at(party_dirs, to)->apply_replica(msg["data"]);
		}
	}
	queue = keep;
}

// ------------------------------------------------------------------ world setup

String CgameClusterSimulator::mint_item(int p_server, const String &p_owner, const String &p_def) {
	minted++;
	return _ledger_at(ledgers, p_server)->mint(p_owner, p_def);
}

void CgameClusterSimulator::add_player(const String &p_pid, const Vector2 &p_pos, int p_items_count) {
	const int srv = sharding->owner_at(p_pos);
	sharding->track_player(p_pid, p_pos, srv);
	player_ids.push_back(p_pid);
	for (int i = 0; i < p_items_count; i++) {
		(void)mint_item(srv, p_pid);
	}
}

int CgameClusterSimulator::player_server(const String &p_pid) const {
	return sharding->owner_of(p_pid);
}

void CgameClusterSimulator::create_party(const String &p_party_id, const String &p_leader, const Array &p_members) {
	const int home = player_server(p_leader);
	CgamePartyMigration *dir = _party_at(party_dirs, home);
	dir->create(p_party_id, p_leader);
	for (int i = 0; i < p_members.size(); i++) {
		dir->add_member(p_party_id, String(p_members[i]), player_server(String(p_members[i])));
	}
	party_ids.push_back(p_party_id);
	_broadcast_party(p_party_id, home);
}

void CgameClusterSimulator::_broadcast_party(const String &p_party_id, int p_from) {
	Dictionary snap = _party_at(party_dirs, p_from)->snapshot(p_party_id);
	if (snap.is_empty()) {
		return;
	}
	for (int i = 0; i < n; i++) {
		if (i != p_from) {
			_send(i, "party_doc", snap.duplicate(true));
		}
	}
}

// ------------------------------------------------------------------ item moves (2PC)

// Moves items between servers atomically. Returns "committed" | "aborted" | "crashed" |
// "rejected" (precondition failed, nothing started).
String CgameClusterSimulator::move_items(int p_from, int p_to, const Array &p_ids, const Dictionary &p_meta) {
	if (p_from == p_to || coordinator->is_crashed() || !is_alive(p_from) || !is_alive(p_to)) {
		return "rejected";
	}
	CgameItemLedger *src = _ledger_at(ledgers, p_from);
	for (int i = 0; i < p_ids.size(); i++) {
		if (!src->is_active(String(p_ids[i]))) {
			return "rejected";
		}
	}
	Dictionary out_op;
	out_op["kind"] = "out";
	out_op["ids"] = p_ids.duplicate();
	Dictionary in_op;
	in_op["kind"] = "in";
	in_op["recs"] = src->snapshot(p_ids);
	Dictionary ops;
	ops["s" + itos(p_from)] = out_op;
	ops["s" + itos(p_to)] = in_op;
	const String tx = coordinator->begin(ops);
	if (!p_meta.is_empty()) {
		tx_meta[tx] = p_meta;
	}
	const String res = coordinator->run(tx);
	if (res == "crashed") {
		_bump_stat("moves_crashed");
		coord_recover_at = tick + rng->randi_range(3, 10);
		return "crashed";
	}
	_finish_tx(tx, res);
	return res;
}

void CgameClusterSimulator::_finish_tx(const String &p_tx, const String &p_result) {
	if (p_result == "committed") {
		_bump_stat("moves_committed");
	} else {
		_bump_stat("moves_aborted");
	}
	if (!tx_meta.has(p_tx)) {
		return;
	}
	Dictionary meta = tx_meta[p_tx];
	tx_meta.erase(p_tx);
	const String tid = String(meta["tid"]);
	if (p_result == "committed") {
		sharding->ack_transfer(tid);
		sharding->release_transfer(tid);
		_bump_stat("migrations");
	} else {
		sharding->abort_transfer(tid);
	}
}

// Player handoff: freeze (sharding), move the player's items with a 2PC, then flip ownership.
String CgameClusterSimulator::migrate_player(const String &p_pid, int p_dest) {
	const int from = player_server(p_pid);
	if (from == p_dest || coordinator->is_crashed() || !is_alive(from) || !is_alive(p_dest)) {
		return "rejected";
	}
	msg_seq++;
	const String tid = "t" + itos(msg_seq);
	if (sharding->begin_transfer(p_pid, p_dest, tid).is_empty()) {
		return "rejected";
	}
	CgameItemLedger *src = _ledger_at(ledgers, from);
	Array ids = src->items_of(p_pid);
	Dictionary state;
	state["items"] = ids.size();
	sharding->send_state(tid, state);
	Dictionary out_op;
	out_op["kind"] = "out";
	out_op["ids"] = ids;
	Dictionary in_op;
	in_op["kind"] = "in";
	in_op["recs"] = src->snapshot(ids);
	Dictionary ops;
	ops["s" + itos(from)] = out_op;
	ops["s" + itos(p_dest)] = in_op;
	const String tx = coordinator->begin(ops);
	Dictionary meta;
	meta["pid"] = p_pid;
	meta["tid"] = tid;
	tx_meta[tx] = meta;
	const String res = coordinator->run(tx);
	if (res == "crashed") {
		_bump_stat("moves_crashed");
		coord_recover_at = tick + rng->randi_range(3, 10);
		return "crashed";
	}
	_finish_tx(tx, res);
	return res;
}

// ------------------------------------------------------------------ guilds

Dictionary CgameClusterSimulator::guild_op(int p_server, const String &p_gid, const String &p_type, const String &p_pid, int p_arg, const String &p_text) {
	if (!is_alive(p_server)) {
		return Dictionary();
	}
	CgameGuildSync *g = _guild_at(guild_replicas, p_server);
	Dictionary op;
	if (p_type == "join") {
		op = g->join(p_gid, p_pid, p_arg);
	} else if (p_type == "rank") {
		op = g->set_rank(p_gid, p_pid, p_arg);
	} else if (p_type == "kick") {
		op = g->kick(p_gid, p_pid);
	} else if (p_type == "motd") {
		op = g->set_motd(p_gid, p_text);
	} else {
		op = g->deposit(p_gid, p_arg);
	}
	for (int i = 0; i < n; i++) {
		if (i != p_server) {
			_send(i, "guild_op", op);
		}
	}
	return op;
}

void CgameClusterSimulator::gossip_pair(int p_a, int p_b) {
	if (is_alive(p_a) && is_alive(p_b)) {
		_guild_at(guild_replicas, p_a)->sync_from(_guild_at(guild_replicas, p_b));
		_guild_at(guild_replicas, p_b)->sync_from(_guild_at(guild_replicas, p_a));
	}
}

// ------------------------------------------------------------------ leases and regions

bool CgameClusterSimulator::_claim_region(int p_region, int p_server) {
	const String key = "region:" + itos(p_region);
	Dictionary res = leases->acquire(key, "s" + itos(p_server), double(tick), lease_ttl);
	if (!bool(res["ok"])) {
		return false;
	}
	region_token[p_region] = int(res["token"]);
	fenced->write(key, int(res["token"]), "s" + itos(p_server));
	return true;
}

void CgameClusterSimulator::_renew_leases() {
	for (int r = 0; r < sharding->region_count(); r++) {
		const int o = sharding->get_region_owner()[r];
		if (!is_alive(o)) {
			continue;
		}
		const String key = "region:" + itos(r);
		if (!leases->renew(key, "s" + itos(o), int(region_token.get(r, 0)), double(tick), lease_ttl)) {
			_claim_region(r, o);
		}
	}
}

// Regions of dead servers whose lease expired move to the least-loaded live server.
void CgameClusterSimulator::_failover() {
	for (int r = 0; r < sharding->region_count(); r++) {
		PackedInt32Array owners = sharding->get_region_owner();
		const int o = owners[r];
		if (is_alive(o) || !leases->holder_of("region:" + itos(r), double(tick)).is_empty()) {
			continue;
		}
		int best = -1;
		int best_count = 1 << 30;
		for (int s = 0; s < n; s++) {
			if (!is_alive(s)) {
				continue;
			}
			int cnt = 0;
			for (int rr = 0; rr < sharding->region_count(); rr++) {
				if (owners[rr] == s) {
					cnt++;
				}
			}
			if (cnt < best_count) {
				best_count = cnt;
				best = s;
			}
		}
		if (best >= 0 && _claim_region(r, best)) {
			owners.write[r] = best;
			sharding->set_region_owner(owners);
			_bump_stat("failovers");
		}
	}
}

Array CgameClusterSimulator::region_loads() const {
	Array loads;
	loads.resize(sharding->region_count());
	loads.fill(0.0);
	Dictionary players = sharding->get_players();
	for (int i = 0; i < player_ids.size(); i++) {
		Dictionary p = players[player_ids[i]];
		const int r = sharding->region_of(p["pos"]);
		loads[r] = double(loads[r]) + 1.0;
	}
	return loads;
}

Array CgameClusterSimulator::server_load_report() const {
	return sharding->server_loads(region_loads());
}

// Servers report load; hot regions are reassigned (lease handed over with a fresh fencing token)
// and the players standing in them migrate to the new owner. Returns the region moves.
Array CgameClusterSimulator::rebalance() {
	Array moves = sharding->rebalance(region_loads());
	for (int i = 0; i < moves.size(); i++) {
		Dictionary mv = moves[i];
		const int r = mv["region"];
		const String key = "region:" + itos(r);
		leases->release(key, "s" + itos(int(mv["from"])), int(region_token.get(r, 0)));
		_claim_region(r, int(mv["to"]));
		_bump_stat("region_moves");
	}
	migrate_misplaced_players();
	return moves;
}

// Players whose region is owned by another server move there.
int CgameClusterSimulator::migrate_misplaced_players() {
	int count = 0;
	Dictionary players = sharding->get_players();
	for (int i = 0; i < player_ids.size(); i++) {
		const String pid = player_ids[i];
		Dictionary p = players[pid];
		const int want = sharding->owner_at(p["pos"]);
		if (want != player_server(pid) && migrate_player(pid, want) == "committed") {
			count++;
		}
	}
	return count;
}

// ------------------------------------------------------------------ parties

// Newest replica of a party across all directories (by epoch, then version).
Dictionary CgameClusterSimulator::_newest_doc(const String &p_party_id) const {
	Dictionary best;
	for (int i = 0; i < n; i++) {
		Dictionary d = _party_at(party_dirs, i)->get_doc(p_party_id);
		if (d.is_empty()) {
			continue;
		}
		if (best.is_empty() || int64_t(d["epoch"]) * 1000000 + int64_t(d["version"]) > int64_t(best["epoch"]) * 1000000 + int64_t(best["version"])) {
			best = d;
		}
	}
	return best;
}

// The home server reconciles the party doc with where its members really are.
void CgameClusterSimulator::_sync_party(const String &p_party_id) {
	Dictionary newest = _newest_doc(p_party_id);
	if (newest.is_empty()) {
		return;
	}
	const int home = newest["home"];
	if (!is_alive(home)) {
		return;
	}
	CgamePartyMigration *dir = _party_at(party_dirs, home);
	Dictionary doc = dir->get_doc(p_party_id);
	if (doc.is_empty() || int(doc["epoch"]) < int(newest["epoch"]) || int(doc["version"]) < int(newest["version"])) {
		return; // The snapshot has not reached the new home yet.
	}
	const int ls = player_server(String(doc["leader"]));
	if (ls != home) {
		if (is_alive(ls) && !dir->leader_handoff(p_party_id, ls).is_empty()) {
			_broadcast_party(p_party_id, home);
		}
		return;
	}
	bool changed = false;
	Dictionary ms = doc["members"];
	Array members = ms.keys();
	for (int i = 0; i < members.size(); i++) {
		if (dir->set_member_server(p_party_id, String(members[i]), player_server(String(members[i])))) {
			changed = true;
		}
	}
	if (changed) {
		_broadcast_party(p_party_id, home);
	}
}

void CgameClusterSimulator::_party_followers() {
	for (int i = 0; i < party_ids.size(); i++) {
		const String pp = party_ids[i];
		Dictionary doc = _newest_doc(pp);
		if (doc.is_empty()) {
			continue;
		}
		const int ls = player_server(String(doc["leader"]));
		Array plan = _party_at(party_dirs, int(doc["home"]))->follow_plan(pp, ls);
		for (int j = 0; j < plan.size(); j++) {
			Dictionary s = plan[j];
			(void)migrate_player(String(s["player"]), int(s["to"]));
		}
	}
}

bool CgameClusterSimulator::parties_settled() const {
	for (int i = 0; i < party_ids.size(); i++) {
		Dictionary doc = _newest_doc(String(party_ids[i]));
		if (doc.is_empty()) {
			continue;
		}
		const int ls = player_server(String(doc["leader"]));
		Dictionary ms = doc["members"];
		Array members = ms.keys();
		for (int j = 0; j < members.size(); j++) {
			if (player_server(String(members[j])) != ls || int(ms[members[j]]) != ls) {
				return false;
			}
		}
		if (int(doc["home"]) != ls) {
			return false;
		}
	}
	return true;
}

// ------------------------------------------------------------------ faults

void CgameClusterSimulator::crash_server(int p_i, int p_down_for) {
	if (!is_alive(p_i)) {
		return;
	}
	alive[p_i] = false;
	restart_at[p_i] = tick + p_down_for;
	_bump_stat("server_crashes");
}

void CgameClusterSimulator::restart_server(int p_i) {
	alive[p_i] = true;
	restart_at.erase(p_i);
}

int CgameClusterSimulator::live_count() const {
	int c = 0;
	for (int i = 0; i < n; i++) {
		if (is_alive(i)) {
			c++;
		}
	}
	return c;
}

void CgameClusterSimulator::recover_coordinator() {
	Dictionary res = coordinator->recover();
	coord_recover_at = -1;
	Array txs = res.keys();
	for (int i = 0; i < txs.size(); i++) {
		_finish_tx(String(txs[i]), String(res[txs[i]]));
	}
}

// ------------------------------------------------------------------ time

void CgameClusterSimulator::step() {
	tick++;
	Array restarts = restart_at.keys();
	for (int i = 0; i < restarts.size(); i++) {
		if (tick >= int(restart_at[restarts[i]])) {
			restart_server(int(restarts[i]));
		}
	}
	if (coordinator->is_crashed() && coord_recover_at >= 0 && tick >= coord_recover_at) {
		recover_coordinator();
	}
	_deliver_due();
	if (tick % 5 == 0) {
		_renew_leases();
	}
	_failover();
	if (tick % 3 == 0) {
		for (int i = 0; i < party_ids.size(); i++) {
			_sync_party(String(party_ids[i]));
		}
		_party_followers();
	}
	if (gossip_every > 0 && tick % gossip_every == 0 && n >= 2) {
		const int a = rng->randi_range(0, n - 1);
		const int b = rng->randi_range(0, n - 1);
		gossip_pair(a, b);
	}
}

// Random workload with faults. Deterministic for a given seed: every draw from the generator
// happens in the same order as the reference GDScript simulator.
void CgameClusterSimulator::run_random(int p_ticks) {
	for (int t = 0; t < p_ticks; t++) {
		const double roll = rng->randf();
		if (roll < 0.30) {
			const int a = rng->randi_range(0, n - 1);
			const int b = rng->randi_range(0, n - 1);
			Array ids = _ledger_at(ledgers, a)->ids_sorted();
			if (!ids.is_empty()) {
				Array take;
				take.push_back(ids[rng->randi_range(0, ids.size() - 1)]);
				if (rng->randf() < 0.4 && ids.size() > 1) {
					take.push_back(ids[rng->randi_range(0, ids.size() - 1)]);
				}
				Array uniq;
				for (int i = 0; i < take.size(); i++) {
					if (!uniq.has(take[i])) {
						uniq.push_back(take[i]);
					}
				}
				(void)move_items(a, b, uniq);
			}
		} else if (roll < 0.42) {
			const int s = rng->randi_range(0, n - 1);
			static const char *kinds[5] = { "join", "rank", "kick", "motd", "deposit" };
			const String k = kinds[rng->randi_range(0, 4)];
			const int gnum = rng->randi_range(0, 1);
			const int pnum = rng->randi_range(0, 5);
			const int arg = rng->randi_range(0, 5);
			const int mnum = rng->randi_range(0, 99);
			guild_op(s, "g" + itos(gnum), k, "p" + itos(pnum), arg, "m" + itos(mnum));
		} else if (roll < 0.47 && live_count() > 1) {
			const int victim = rng->randi_range(0, n - 1);
			const int down_for = rng->randi_range(4, 15);
			crash_server(victim, down_for);
		} else if (roll < 0.51 && !coordinator->is_crashed()) {
			coordinator->set_crash_point(rng->randf() < 0.5 ? "before_decision" : "after_decision");
			_bump_stat("coord_crashes");
		} else if (roll < 0.62 && !player_ids.is_empty()) {
			const String pid = player_ids[rng->randi_range(0, player_ids.size() - 1)];
			const int dest = rng->randi_range(0, n - 1);
			(void)migrate_player(pid, dest);
		} else if (roll < 0.65 && !party_ids.is_empty()) {
			const String pp = party_ids[rng->randi_range(0, party_ids.size() - 1)];
			for (int i = 0; i < n; i++) {
				CgamePartyMigration *dir = _party_at(party_dirs, i);
				if (dir->has_party(pp)) {
					const String leader = dir->get_doc(pp)["leader"];
					(void)migrate_player(leader, rng->randi_range(0, n - 1));
					break;
				}
			}
		} else if (roll < 0.68 && live_count() == n) {
			rebalance();
		}
		step();
	}
}

bool CgameClusterSimulator::idle() const {
	if (!queue.is_empty() || coordinator->is_crashed()) {
		return false;
	}
	for (int i = 0; i < n; i++) {
		if (!_ledger_at(ledgers, i)->get_pending().is_empty()) {
			return false;
		}
	}
	return true;
}

// Heals everything: restarts servers, recovers the coordinator, drains queues, runs anti-entropy
// and lets parties re-converge. Returns false if it did not settle.
bool CgameClusterSimulator::quiesce(int p_max_ticks) {
	coordinator->set_crash_point("");
	for (int i = 0; i < n; i++) {
		restart_server(i);
	}
	for (int t = 0; t < p_max_ticks; t++) {
		if (coordinator->is_crashed()) {
			recover_coordinator();
		}
		step();
		if (idle() && parties_settled()) {
			break;
		}
	}
	for (int i = 0; i < 6; i++) {
		step(); // A few quiet ticks so lease renewals catch up.
	}
	for (int round = 0; round < 2; round++) {
		for (int a = 0; a < n; a++) {
			for (int b = 0; b < n; b++) {
				gossip_pair(a, b);
			}
		}
	}
	return idle() && parties_settled();
}

// ------------------------------------------------------------------ invariants

// Returns human-readable violations (empty = all good). Call after quiesce().
Array CgameClusterSimulator::check_invariants() const {
	Array bad;
	int total = 0;
	for (int i = 0; i < n; i++) {
		CgameItemLedger *led = _ledger_at(ledgers, i);
		total += led->total_count();
		if (led->active_count() != led->total_count()) {
			bad.push_back(vformat("server %d holds non-active items", i));
		}
	}
	if (total != minted) {
		bad.push_back(vformat("items not conserved: %d present, %d minted", total, minted));
	}
	Dictionary dups = CgameItemLedger::find_duplicates(ledgers);
	if (!dups.is_empty()) {
		bad.push_back(vformat("duplicate item ids: %s", String(Variant(dups.keys()))));
	}
	Dictionary txs = coordinator->get_txs();
	Array tx_ids = txs.keys();
	for (int i = 0; i < tx_ids.size(); i++) {
		Dictionary rec = txs[tx_ids[i]];
		if (String(rec["state"]) != "done") {
			bad.push_back(vformat("tx %s not finished", String(tx_ids[i])));
		}
	}
	Dictionary players = sharding->get_players();
	for (int i = 0; i < player_ids.size(); i++) {
		Dictionary p = players[player_ids[i]];
		if (String(p["state"]) != "stable") {
			bad.push_back(vformat("player %s not stable", String(player_ids[i])));
		}
	}
	for (const char *gid : { "g0", "g1" }) {
		for (int i = 1; i < n; i++) {
			if (_guild_at(guild_replicas, i)->digest(gid) != _guild_at(guild_replicas, 0)->digest(gid)) {
				bad.push_back(vformat("guild %s diverged on server %d", gid, i));
			}
		}
	}
	for (int k = 0; k < party_ids.size(); k++) {
		for (int i = 1; i < n; i++) {
			if (!_party_at(party_dirs, i)->same_as(_party_at(party_dirs, 0), String(party_ids[k]))) {
				bad.push_back(vformat("party %s diverged on server %d", String(party_ids[k]), i));
			}
		}
	}
	PackedInt32Array owners = sharding->get_region_owner();
	for (int r = 0; r < sharding->region_count(); r++) {
		const int o = owners[r];
		if (leases->holder_of("region:" + itos(r), double(tick)) != "s" + itos(o)) {
			bad.push_back(vformat("region %d lease/owner mismatch", r));
		}
	}
	return bad;
}

void CgameClusterSimulator::_bind_methods() {
	CGAME_BIND_PROPERTY(CgameClusterSimulator, Variant::INT, n)
	CGAME_BIND_PROPERTY(CgameClusterSimulator, Variant::INT, tick)
	CGAME_BIND_PROPERTY(CgameClusterSimulator, Variant::INT, min_latency)
	CGAME_BIND_PROPERTY(CgameClusterSimulator, Variant::INT, max_latency)
	CGAME_BIND_PROPERTY(CgameClusterSimulator, Variant::FLOAT, lease_ttl)
	CGAME_BIND_PROPERTY(CgameClusterSimulator, Variant::INT, gossip_every)
	CGAME_BIND_PROPERTY(CgameClusterSimulator, Variant::ARRAY, alive)
	CGAME_BIND_PROPERTY(CgameClusterSimulator, Variant::ARRAY, ledgers)
	CGAME_BIND_PROPERTY(CgameClusterSimulator, Variant::ARRAY, guild_replicas)
	CGAME_BIND_PROPERTY(CgameClusterSimulator, Variant::ARRAY, party_dirs)
	CGAME_BIND_PROPERTY(CgameClusterSimulator, Variant::ARRAY, queue)
	CGAME_BIND_PROPERTY(CgameClusterSimulator, Variant::DICTIONARY, restart_at)
	CGAME_BIND_PROPERTY(CgameClusterSimulator, Variant::INT, coord_recover_at)
	CGAME_BIND_PROPERTY(CgameClusterSimulator, Variant::DICTIONARY, tx_meta)
	CGAME_BIND_PROPERTY(CgameClusterSimulator, Variant::ARRAY, player_ids)
	CGAME_BIND_PROPERTY(CgameClusterSimulator, Variant::ARRAY, party_ids)
	CGAME_BIND_PROPERTY(CgameClusterSimulator, Variant::DICTIONARY, region_token)
	CGAME_BIND_PROPERTY(CgameClusterSimulator, Variant::INT, minted)
	CGAME_BIND_PROPERTY(CgameClusterSimulator, Variant::DICTIONARY, stats)

	ClassDB::bind_method(D_METHOD("get_rng"), &CgameClusterSimulator::get_rng);
	ClassDB::bind_method(D_METHOD("get_coordinator"), &CgameClusterSimulator::get_coordinator);
	ClassDB::bind_method(D_METHOD("get_sharding"), &CgameClusterSimulator::get_sharding);
	ClassDB::bind_method(D_METHOD("get_leases"), &CgameClusterSimulator::get_leases);
	ClassDB::bind_method(D_METHOD("get_fenced"), &CgameClusterSimulator::get_fenced);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "rng", PROPERTY_HINT_RESOURCE_TYPE, "RandomNumberGenerator", PROPERTY_USAGE_NONE), "", "get_rng");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "coordinator", PROPERTY_HINT_RESOURCE_TYPE, "CgameTransactionCoordinator", PROPERTY_USAGE_NONE), "", "get_coordinator");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "sharding", PROPERTY_HINT_RESOURCE_TYPE, "CgameWorldSharding", PROPERTY_USAGE_NONE), "", "get_sharding");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "leases", PROPERTY_HINT_RESOURCE_TYPE, "CgameOwnershipLeases", PROPERTY_USAGE_NONE), "", "get_leases");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "fenced", PROPERTY_HINT_RESOURCE_TYPE, "CgameFencedStore", PROPERTY_USAGE_NONE), "", "get_fenced");

	ClassDB::bind_method(D_METHOD("setup", "servers", "seed_value", "cols", "rows", "cell"), &CgameClusterSimulator::setup, DEFVAL(4), DEFVAL(4), DEFVAL(100.0));
	ClassDB::bind_method(D_METHOD("teardown"), &CgameClusterSimulator::teardown);
	ClassDB::bind_method(D_METHOD("ledger", "i"), &CgameClusterSimulator::ledger);
	ClassDB::bind_method(D_METHOD("guilds", "i"), &CgameClusterSimulator::guilds);
	ClassDB::bind_method(D_METHOD("parties", "i"), &CgameClusterSimulator::parties);
	ClassDB::bind_method(D_METHOD("is_alive", "i"), &CgameClusterSimulator::is_alive);
	ClassDB::bind_method(D_METHOD("mint_item", "server", "owner", "def"), &CgameClusterSimulator::mint_item, DEFVAL("item"));
	ClassDB::bind_method(D_METHOD("add_player", "pid", "pos", "items_count"), &CgameClusterSimulator::add_player, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("player_server", "pid"), &CgameClusterSimulator::player_server);
	ClassDB::bind_method(D_METHOD("create_party", "party_id", "leader", "members"), &CgameClusterSimulator::create_party, DEFVAL(Array()));
	ClassDB::bind_method(D_METHOD("move_items", "from", "to", "ids", "meta"), &CgameClusterSimulator::move_items, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("migrate_player", "pid", "dest"), &CgameClusterSimulator::migrate_player);
	ClassDB::bind_method(D_METHOD("guild_op", "server", "gid", "type", "pid", "arg", "text"), &CgameClusterSimulator::guild_op, DEFVAL(""), DEFVAL(0), DEFVAL(""));
	ClassDB::bind_method(D_METHOD("gossip_pair", "a", "b"), &CgameClusterSimulator::gossip_pair);
	ClassDB::bind_method(D_METHOD("region_loads"), &CgameClusterSimulator::region_loads);
	ClassDB::bind_method(D_METHOD("server_load_report"), &CgameClusterSimulator::server_load_report);
	ClassDB::bind_method(D_METHOD("rebalance"), &CgameClusterSimulator::rebalance);
	ClassDB::bind_method(D_METHOD("migrate_misplaced_players"), &CgameClusterSimulator::migrate_misplaced_players);
	ClassDB::bind_method(D_METHOD("parties_settled"), &CgameClusterSimulator::parties_settled);
	ClassDB::bind_method(D_METHOD("crash_server", "i", "down_for"), &CgameClusterSimulator::crash_server);
	ClassDB::bind_method(D_METHOD("restart_server", "i"), &CgameClusterSimulator::restart_server);
	ClassDB::bind_method(D_METHOD("live_count"), &CgameClusterSimulator::live_count);
	ClassDB::bind_method(D_METHOD("recover_coordinator"), &CgameClusterSimulator::recover_coordinator);
	ClassDB::bind_method(D_METHOD("step"), &CgameClusterSimulator::step);
	ClassDB::bind_method(D_METHOD("run_random", "ticks"), &CgameClusterSimulator::run_random);
	ClassDB::bind_method(D_METHOD("idle"), &CgameClusterSimulator::idle);
	ClassDB::bind_method(D_METHOD("quiesce", "max_ticks"), &CgameClusterSimulator::quiesce, DEFVAL(600));
	ClassDB::bind_method(D_METHOD("check_invariants"), &CgameClusterSimulator::check_invariants);

	// Callback targets for the coordinator's participants (bound with the server index).
	ClassDB::bind_method(D_METHOD("_prepare", "tx_id", "op", "server"), &CgameClusterSimulator::_prepare);
	ClassDB::bind_method(D_METHOD("_commit", "tx_id", "server"), &CgameClusterSimulator::_commit);
	ClassDB::bind_method(D_METHOD("_abort", "tx_id", "server"), &CgameClusterSimulator::_abort);
}
