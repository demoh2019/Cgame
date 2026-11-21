/**************************************************************************/
/*  cgame_cluster_simulator.h                                             */
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

#include "cgame_server_macros.h"

#include "cgame_guild_sync.h"
#include "cgame_item_ledger.h"
#include "cgame_ownership_leases.h"
#include "cgame_party_migration.h"
#include "cgame_transaction_coordinator.h"
#include "cgame_world_sharding.h"

#include "core/math/random_number_generator.h"
#include "core/math/vector2.h"
#include "core/object/ref_counted.h"
#include "core/variant/array.h"
#include "core/variant/dictionary.h"

// In-process simulation of N game servers: message queues with random latency and reordering,
// server crashes (durable state, held messages) and coordinator crashes, driving item moves via
// CgameTransactionCoordinator 2PC, guild op replication, party migration, region leases with
// fencing and load-based region reassignment with player migration.
//
// Model assumptions: each server's ledger/guild/party state is durable across a crash (a crash
// only stops processing; messages addressed to a down server are held and delivered after
// restart); 2PC prepare is a synchronous call that fails if the server is down; commit/abort
// decisions travel as queued messages and are idempotent at the receiver. Everything derives from
// one seeded RandomNumberGenerator, so a run is deterministic for a given seed.
class CgameClusterSimulator : public RefCounted {
	GDCLASS(CgameClusterSimulator, RefCounted);

	Ref<RandomNumberGenerator> rng;
	int n = 3;
	int tick = 0;
	int min_latency = 1;
	int max_latency = 4;
	double lease_ttl = 20.0;
	int gossip_every = 25;

	Array alive;
	Array ledgers;
	Array guild_replicas;
	Array party_dirs;
	Ref<CgameTransactionCoordinator> coordinator;
	Ref<CgameWorldSharding> sharding;
	Ref<CgameOwnershipLeases> leases;
	Ref<CgameFencedStore> fenced;

	Array queue;
	Dictionary restart_at;
	int coord_recover_at = -1;
	Dictionary tx_meta;
	Array player_ids;
	Array party_ids;
	Dictionary region_token;
	int minted = 0;
	Dictionary stats;
	int msg_seq = 0;

	void _send(int p_to, const String &p_kind, const Variant &p_data);
	bool _prepare(const String &p_tx_id, const Variant &p_op, int p_server);
	void _commit(const String &p_tx_id, int p_server);
	void _abort(const String &p_tx_id, int p_server);
	void _deliver_due();
	void _bump_stat(const String &p_key);
	void _broadcast_party(const String &p_party_id, int p_from);
	void _finish_tx(const String &p_tx, const String &p_result);
	bool _claim_region(int p_region, int p_server);
	void _renew_leases();
	void _failover();
	Dictionary _newest_doc(const String &p_party_id) const;
	void _sync_party(const String &p_party_id);
	void _party_followers();

protected:
	static void _bind_methods();

public:
	CgameClusterSimulator();

	CGAME_ACCESSORS(int, n)
	CGAME_ACCESSORS(int, tick)
	CGAME_ACCESSORS(int, min_latency)
	CGAME_ACCESSORS(int, max_latency)
	CGAME_ACCESSORS(double, lease_ttl)
	CGAME_ACCESSORS(int, gossip_every)
	CGAME_ACCESSORS(Array, alive)
	CGAME_ACCESSORS(Array, ledgers)
	CGAME_ACCESSORS(Array, guild_replicas)
	CGAME_ACCESSORS(Array, party_dirs)
	CGAME_ACCESSORS(Array, queue)
	CGAME_ACCESSORS(Dictionary, restart_at)
	CGAME_ACCESSORS(int, coord_recover_at)
	CGAME_ACCESSORS(Dictionary, tx_meta)
	CGAME_ACCESSORS(Array, player_ids)
	CGAME_ACCESSORS(Array, party_ids)
	CGAME_ACCESSORS(Dictionary, region_token)
	CGAME_ACCESSORS(int, minted)
	CGAME_ACCESSORS(Dictionary, stats)
	Ref<RandomNumberGenerator> get_rng() const { return rng; }
	Ref<CgameTransactionCoordinator> get_coordinator() const { return coordinator; }
	Ref<CgameWorldSharding> get_sharding() const { return sharding; }
	Ref<CgameOwnershipLeases> get_leases() const { return leases; }
	Ref<CgameFencedStore> get_fenced() const { return fenced; }

	void setup(int p_servers, int64_t p_seed, int p_cols = 4, int p_rows = 4, double p_cell = 100.0);
	void teardown();
	Ref<CgameItemLedger> ledger(int p_i) const;
	Ref<CgameGuildSync> guilds(int p_i) const;
	Ref<CgamePartyMigration> parties(int p_i) const;
	bool is_alive(int p_i) const;

	String mint_item(int p_server, const String &p_owner, const String &p_def = "item");
	void add_player(const String &p_pid, const Vector2 &p_pos, int p_items_count = 0);
	int player_server(const String &p_pid) const;
	void create_party(const String &p_party_id, const String &p_leader, const Array &p_members = Array());

	String move_items(int p_from, int p_to, const Array &p_ids, const Dictionary &p_meta = Dictionary());
	String migrate_player(const String &p_pid, int p_dest);

	Dictionary guild_op(int p_server, const String &p_gid, const String &p_type, const String &p_pid = "", int p_arg = 0, const String &p_text = "");
	void gossip_pair(int p_a, int p_b);

	Array region_loads() const;
	Array server_load_report() const;
	Array rebalance();
	int migrate_misplaced_players();
	bool parties_settled() const;

	void crash_server(int p_i, int p_down_for);
	void restart_server(int p_i);
	int live_count() const;
	void recover_coordinator();

	void step();
	void run_random(int p_ticks);
	bool idle() const;
	bool quiesce(int p_max_ticks = 600);
	Array check_invariants() const;
};
