/**************************************************************************/
/*  test_cgame_server_distribution.h                                      */
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

#include "../cgame_cluster_simulator.h"
#include "../cgame_guild_sync.h"
#include "../cgame_item_ledger.h"
#include "../cgame_ownership_leases.h"
#include "../cgame_party_migration.h"
#include "../cgame_transaction_coordinator.h"
#include "../cgame_world_sharding.h"

#include "core/io/dir_access.h"
#include "core/io/file_access.h"
#include "core/io/json.h"
#include "core/object/callable_mp.h"
#include "core/os/os.h"
#include "tests/test_macros.h"

namespace TestCgameServerDistribution {

// ---------------------------------------------------------------- 2PC fixtures

struct ParticipantLog {
	HashMap<String, int> counts;
	String refuse;
};
static ParticipantLog g_log;

static bool participant_prepare(const String &p_tx, const Variant &p_ops, const String &p_name) {
	return p_name != g_log.refuse;
}

static void participant_commit(const String &p_tx, const String &p_name) {
	g_log.counts["commit_" + p_name] += 1;
}

static void participant_abort(const String &p_tx, const String &p_name) {
	g_log.counts["abort_" + p_name] += 1;
}

static int count(const String &p_key) {
	return g_log.counts.has(p_key) ? g_log.counts[p_key] : 0;
}

static void wire(const Ref<CgameTransactionCoordinator> &p_coordinator, const String &p_refuse = "") {
	g_log.refuse = p_refuse;
	for (const String name : { String("a"), String("b") }) {
		p_coordinator->add_participant(name,
				callable_mp_static(&participant_prepare).bind(name),
				callable_mp_static(&participant_commit).bind(name),
				callable_mp_static(&participant_abort).bind(name));
	}
}

static String store_path(const String &p_tag) {
	return "user://cgame_server_" + p_tag + "_" + itos(OS::get_singleton()->get_process_id()) + ".json";
}

static void cleanup(const String &p_path) {
	for (const String &p : { p_path, p_path + ".tmp" }) {
		if (FileAccess::exists(p)) {
			DirAccess::remove_absolute(p);
		}
	}
}

static Dictionary ops_of(const Variant &p_a, const Variant &p_b) {
	Dictionary ops;
	ops["a"] = p_a;
	ops["b"] = p_b;
	return ops;
}

template <typename... Args>
static Array arr(Args... p_args) {
	Array out;
	(out.push_back(p_args), ...);
	return out;
}

static bool same(const Variant &p_a, const Variant &p_b) {
	return p_a == p_b;
}

TEST_CASE("[CgameTransactionCoordinator] Commit when all prepare, idempotent re-run") {
	g_log.counts.clear();
	Ref<CgameTransactionCoordinator> c;
	c.instantiate();
	wire(c);
	Dictionary gold;
	gold["gold"] = -5;
	Dictionary item;
	item["item"] = 1;
	const String id = c->begin(ops_of(gold, item));
	CHECK(c->run(id) == "committed");
	CHECK(count("commit_a") + count("commit_b") == 2);
	CHECK(c->run(id) == "committed");
	CHECK(count("commit_a") == 1);
	CHECK(c->get_status(id) == "done");
	CHECK(c->run("nope") == "aborted");
	CHECK(c->get_status("nope") == "unknown");
}

TEST_CASE("[CgameTransactionCoordinator] Abort when one participant refuses") {
	g_log.counts.clear();
	Ref<CgameTransactionCoordinator> c;
	c.instantiate();
	wire(c, "b");
	const String id = c->begin(ops_of(1, 2));
	CHECK(c->run(id) == "aborted");
	CHECK(count("commit_a") + count("commit_b") == 0);
	CHECK(count("abort_a") == 1);
}

TEST_CASE("[CgameTransactionCoordinator] Crash after decision recovers to commit exactly once") {
	const String path = store_path("after");
	cleanup(path);
	g_log.counts.clear();
	Ref<CgameTransactionCoordinator> c;
	c.instantiate();
	c->set_path(path);
	wire(c);
	c->set_crash_point("after_decision");
	const String id = c->begin(ops_of(1, 2));
	CHECK(c->run(id) == "crashed");
	CHECK(c->is_crashed());
	CHECK(count("commit_a") == 0);

	Ref<CgameTransactionCoordinator> r;
	r.instantiate();
	r->set_path(path);
	CHECK(r->load_store());
	wire(r);
	Dictionary res = r->recover();
	CHECK(String(res.get(id, "")) == "committed");
	CHECK(count("commit_a") == 1);
	CHECK(count("commit_b") == 1);
	CHECK(r->recover().is_empty());
	CHECK(count("commit_a") == 1);
	cleanup(path);
}

TEST_CASE("[CgameTransactionCoordinator] Crash before decision recovers to presumed abort") {
	const String path = store_path("before");
	cleanup(path);
	g_log.counts.clear();
	Ref<CgameTransactionCoordinator> c;
	c.instantiate();
	c->set_path(path);
	wire(c);
	c->set_crash_point("before_decision");
	const String id = c->begin(ops_of(1, 2));
	CHECK(c->run(id) == "crashed");
	CHECK(c->run(id) == "crashed");

	Ref<CgameTransactionCoordinator> r;
	r.instantiate();
	r->set_path(path);
	r->load_store();
	wire(r);
	Dictionary res = r->recover();
	CHECK(String(res.get(id, "")) == "aborted");
	CHECK(count("commit_a") + count("commit_b") == 0);
	CHECK(r->get_status(id) == "done");
	cleanup(path);
}

TEST_CASE("[CgameTransactionCoordinator] Store is written atomically and tolerates corruption") {
	const String path = store_path("atomic");
	cleanup(path);
	Ref<CgameTransactionCoordinator> c;
	c.instantiate();
	c->set_path(path);
	CHECK_FALSE(c->load_store()); // Missing file.
	c->place_order("alice", "sell", "wood", 10.0, 5);
	CHECK(FileAccess::exists(path));
	CHECK_FALSE(FileAccess::exists(path + ".tmp"));
	Ref<FileAccess> f = FileAccess::open(path, FileAccess::WRITE);
	f->store_string("{not json");
	f.unref();
	Ref<CgameTransactionCoordinator> r;
	r.instantiate();
	r->set_path(path);
	CHECK_FALSE(r->load_store());
	CHECK(r->get_txs().is_empty());
	cleanup(path);
}

TEST_CASE("[CgameTransactionCoordinator] Persistent order book survives restart and matches by price-time") {
	const String path = store_path("orders");
	cleanup(path);
	Ref<CgameTransactionCoordinator> ob;
	ob.instantiate();
	ob->set_path(path);
	ob->load_store();
	const String sell1 = ob->place_order("alice", "sell", "wood", 10.0, 5);
	const String buy1 = ob->place_order("bob", "buy", "wood", 8.0, 3);
	CHECK(ob->match_orders("wood").size() == 0);
	const String buy2 = ob->place_order("carol", "buy", "wood", 12.0, 4);

	Ref<CgameTransactionCoordinator> restarted;
	restarted.instantiate();
	restarted->set_path(path);
	CHECK(restarted->load_store());
	CHECK(restarted->get_persistent_orders().size() == 3);
	Array trades = restarted->match_orders("wood");
	REQUIRE(trades.size() == 1);
	Dictionary tr = trades[0];
	CHECK(String(tr["buyer"]) == "carol");
	CHECK(int(tr["qty"]) == 4);
	CHECK(double(tr["price"]) == doctest::Approx(10.0));
	Array left = restarted->open_orders("wood", "sell");
	Dictionary rem = left[0];
	CHECK(int(rem["qty"]) == 1);
	CHECK(restarted->cancel_order(buy1));
	CHECK_FALSE(restarted->cancel_order(buy1));
	CHECK(sell1 != buy2);
	cleanup(path);
}

// ---------------------------------------------------------------- sharding

TEST_CASE("[CgameWorldSharding] Assignment balances regions") {
	Ref<CgameWorldSharding> w;
	w.instantiate();
	w->setup(4, 4, 100.0, 4);
	Array loads;
	for (int i = 0; i < 16; i++) {
		loads.push_back(double(10 + (i % 4) * 5));
	}
	w->assign_initial(loads);
	Array sl = w->server_loads(loads);
	double mx = 0.0;
	double mn = 1e30;
	for (int s = 0; s < sl.size(); s++) {
		mx = MAX(mx, double(sl[s]));
		mn = MIN(mn, double(sl[s]));
	}
	CHECK(mx <= mn * 1.2);
	HashMap<int, int> counts;
	PackedInt32Array owners = w->get_region_owner();
	for (int r = 0; r < 16; r++) {
		counts[owners[r]] += 1;
	}
	CHECK(counts.size() == 4);
}

TEST_CASE("[CgameWorldSharding] Rebalance has hysteresis and does not thrash") {
	Ref<CgameWorldSharding> w;
	w.instantiate();
	w->setup(4, 4, 100.0, 4);
	Array loads;
	for (int i = 0; i < 16; i++) {
		loads.push_back(double(10 + (i % 4) * 5));
	}
	w->assign_initial(loads);
	CHECK(w->rebalance(loads.duplicate()).size() == 0);
	Array hot = loads.duplicate();
	PackedInt32Array owners = w->get_region_owner();
	for (int r = 0; r < 16; r++) {
		if (owners[r] == 0) {
			hot[r] = double(hot[r]) * 4.0;
		}
	}
	Array moves = w->rebalance(hot);
	REQUIRE(moves.size() > 0);
	Dictionary m0 = moves[0];
	CHECK(int(m0["from"]) == 0);
	CHECK(w->rebalance(hot).size() == 0);
	Array nudged = hot.duplicate();
	nudged[0] = double(nudged[0]) * 1.02;
	CHECK(w->rebalance(nudged).size() == 0);
}

TEST_CASE("[CgameWorldSharding] Two-step handoff is idempotent") {
	Ref<CgameWorldSharding> h;
	h.instantiate();
	h->setup(2, 1, 100.0, 2);
	PackedInt32Array owners;
	owners.push_back(0);
	owners.push_back(1);
	h->set_region_owner(owners);
	CHECK(h->handoff_needed(Vector2(50, 50), 0) == -1);
	CHECK(h->handoff_needed(Vector2(99.0, 50), 0) == -1);
	CHECK(h->handoff_needed(Vector2(150, 50), 0) == 1);
	CHECK(same(h->ghost_servers(Vector2(90, 50), 0), arr(1)));
	CHECK(h->ghost_servers(Vector2(30, 50), 0).is_empty());
	h->track_player("p1", Vector2(90, 50), 0);
	Dictionary upd = h->update_player("p1", Vector2(150, 50));
	CHECK(int(upd["handoff_to"]) == 1);
	CHECK(h->begin_transfer("p1", 1, "t-1") == "t-1");
	Dictionary pl = h->get_players()["p1"];
	CHECK(String(pl["state"]) == "frozen");
	CHECK(h->begin_transfer("p1", 1, "t-2") == "");
	CHECK(h->begin_transfer("p1", 1, "t-1") == "t-1");
	CHECK_FALSE(h->release_transfer("t-1"));
	Dictionary payload;
	payload["hp"] = 80;
	CHECK(h->send_state("t-1", payload));
	CHECK(h->ack_transfer("t-1"));
	CHECK(h->release_transfer("t-1"));
	CHECK(h->owner_of("p1") == 1);
	CHECK(String(pl["state"]) == "stable");
	CHECK(h->begin_transfer("p1", 1, "t-1") == "t-1");
	CHECK(h->owner_of("p1") == 1);
	CHECK(h->release_transfer("t-1"));
	const String tid2 = h->begin_transfer("p1", 0, "t-3");
	CHECK(h->abort_transfer(tid2));
	CHECK(h->owner_of("p1") == 1);
	CHECK(same(h->entities_on(1), arr("p1")));
}

// ---------------------------------------------------------------- cluster fixtures

static void drain(const Ref<CgameClusterSimulator> &p_sim, int p_ticks = 30) {
	for (int i = 0; i < p_ticks; i++) {
		p_sim->step();
	}
}

static Array holders(const Ref<CgameClusterSimulator> &p_sim, const String &p_id) {
	Array out;
	for (int i = 0; i < p_sim->get_n(); i++) {
		if (p_sim->ledger(i)->has_item(p_id)) {
			out.push_back(i);
		}
	}
	return out;
}

static Ref<CgameClusterSimulator> make_sim(int p_servers, int64_t p_seed) {
	Ref<CgameClusterSimulator> sim;
	sim.instantiate();
	sim->setup(p_servers, p_seed);
	return sim;
}

TEST_CASE("[CgameClusterSimulator] Item move exactly once") {
	Ref<CgameClusterSimulator> sim = make_sim(2, 11);
	const String id = sim->mint_item(0, "alice", "sword");
	CHECK(id.begins_with("i0-"));
	CHECK(sim->mint_item(0, "alice") != id);
	CHECK(sim->move_items(0, 1, arr(id)) == "committed");
	CHECK(sim->ledger(0)->state_of(id) == "locked");
	drain(sim);
	CHECK(same(holders(sim, id), arr(1)));
	CHECK(sim->ledger(1)->epoch_of(id) == 1);
	CHECK(sim->ledger(1)->owner_of(id) == "alice");

	// Replayed decisions are idempotent.
	sim->ledger(1)->commit("tx1");
	sim->ledger(0)->commit("tx1");
	Dictionary empty_in;
	empty_in["kind"] = "in";
	empty_in["recs"] = Array();
	sim->ledger(1)->prepare("tx1", empty_in);
	CHECK(same(holders(sim, id), arr(1)));
	CHECK(sim->move_items(0, 1, arr(id)) == "rejected");

	const String other = sim->mint_item(1, "bob");
	CHECK(sim->move_items(1, 0, arr(id, other)) == "committed");
	drain(sim);
	CHECK(sim->ledger(0)->total_count() == 3);

	// A destination that already holds the id votes no: the whole transaction aborts, nothing lost.
	const String dup = sim->mint_item(1, "carol");
	Dictionary items0 = sim->ledger(0)->get_items();
	Dictionary items1 = sim->ledger(1)->get_items();
	items0[dup] = Dictionary(items1[dup]).duplicate(true);
	sim->set_minted(sim->get_minted() - 1); // The injected copy is not a mint.
	CHECK(sim->move_items(1, 0, arr(dup)) == "aborted");
	drain(sim);
	CHECK(sim->ledger(1)->is_active(dup));
	sim->teardown();
}

TEST_CASE("[CgameClusterSimulator] Crash mid-transfer and recovery") {
	Ref<CgameClusterSimulator> sim = make_sim(3, 5);
	const String a = sim->mint_item(0, "p");
	sim->get_coordinator()->set_crash_point("before_decision");
	CHECK(sim->move_items(0, 2, arr(a)) == "crashed");
	CHECK(sim->ledger(0)->state_of(a) == "locked");
	CHECK(same(holders(sim, a), arr(0)));
	CHECK(sim->move_items(0, 1, arr(a)) == "rejected");
	sim->recover_coordinator();
	drain(sim);
	CHECK(sim->ledger(0)->is_active(a));
	CHECK(same(holders(sim, a), arr(0)));

	const String b = sim->mint_item(0, "p");
	sim->get_coordinator()->set_crash_point("after_decision");
	CHECK(sim->move_items(0, 2, arr(b)) == "crashed");
	CHECK(sim->ledger(0)->state_of(b) == "locked");
	sim->recover_coordinator();
	drain(sim);
	CHECK(same(holders(sim, b), arr(2)));
	CHECK(sim->ledger(2)->is_active(b));

	const String c = sim->mint_item(0, "p");
	sim->crash_server(1, 50);
	CHECK(sim->move_items(0, 1, arr(c)) == "rejected");
	Array alive = sim->get_alive();
	alive[1] = true;
	sim->ledger(1)->get_items().clear();

	// Target crashes between prepare and commit delivery: the commit is held, then applied once.
	const String d = sim->mint_item(0, "p");
	CHECK(sim->move_items(0, 1, arr(d)) == "committed");
	sim->crash_server(1, 12);
	drain(sim, 8);
	CHECK_FALSE(sim->ledger(1)->has_item(d));
	drain(sim, 12);
	CHECK(same(holders(sim, d), arr(1)));
	sim->teardown();
}

TEST_CASE("[CgameClusterSimulator] Coordinator durability across instances") {
	const String path = store_path("durable");
	cleanup(path);
	Ref<CgameItemLedger> l0;
	l0.instantiate();
	l0->set_server_id(0);
	Ref<CgameItemLedger> l1;
	l1.instantiate();
	l1->set_server_id(1);
	const String id = l0->mint("zed", "bow");

	Ref<CgameTransactionCoordinator> c1;
	c1.instantiate();
	c1->set_path(path);
	c1->add_participant("s0", Callable(l0.ptr(), "prepare"), Callable(l0.ptr(), "commit"), Callable(l0.ptr(), "abort"));
	c1->add_participant("s1", Callable(l1.ptr(), "prepare"), Callable(l1.ptr(), "commit"), Callable(l1.ptr(), "abort"));
	Dictionary out_op;
	out_op["kind"] = "out";
	out_op["ids"] = arr(id);
	Dictionary in_op;
	in_op["kind"] = "in";
	in_op["recs"] = l0->snapshot(arr(id));
	Dictionary ops;
	ops["s0"] = out_op;
	ops["s1"] = in_op;
	const String tx = c1->begin(ops);
	c1->set_crash_point("after_decision");
	CHECK(c1->run(tx) == "crashed");
	CHECK(l0->state_of(id) == "locked");

	Ref<CgameTransactionCoordinator> c2;
	c2.instantiate();
	c2->set_path(path);
	CHECK(c2->load_store());
	c2->add_participant("s0", Callable(l0.ptr(), "prepare"), Callable(l0.ptr(), "commit"), Callable(l0.ptr(), "abort"));
	c2->add_participant("s1", Callable(l1.ptr(), "prepare"), Callable(l1.ptr(), "commit"), Callable(l1.ptr(), "abort"));
	Dictionary res = c2->recover();
	CHECK(String(res[tx]) == "committed");
	CHECK_FALSE(l0->has_item(id));
	CHECK(l1->is_active(id));
	CHECK(l1->epoch_of(id) == 1);
	c2->recover();
	CHECK(l1->total_count() == 1);
	cleanup(path);

	Ref<CgameItemLedger> l1b;
	l1b.instantiate();
	l1b->from_dict(JSON::parse_string(JSON::stringify(l1->to_dict())));
	CHECK(l1b->is_active(id));
	CHECK(l1b->get_server_id() == 1);
}

TEST_CASE("[CgameItemLedger] Duplicate detection and quarantine") {
	Ref<CgameItemLedger> l0;
	l0.instantiate();
	l0->set_server_id(0);
	Ref<CgameItemLedger> l1;
	l1.instantiate();
	l1->set_server_id(1);
	const String id = l0->mint("eve", "gem");
	const String fine = l1->mint("eve", "ring");
	Dictionary copy;
	copy["id"] = id;
	copy["owner"] = "eve";
	copy["def"] = "gem";
	copy["epoch"] = 3;
	copy["state"] = "active";
	copy["lock_tx"] = "";
	l1->get_items()[id] = copy;

	Array ledgers;
	ledgers.push_back(l0);
	ledgers.push_back(l1);
	Dictionary dups = CgameItemLedger::find_duplicates(ledgers);
	CHECK(dups.size() == 1);
	CHECK(dups.has(id));
	CHECK(same(dups[id], arr(0, 1)));
	CHECK(same(CgameItemLedger::quarantine_duplicates(ledgers), arr(id)));
	CHECK(l0->state_of(id) == "quarantined");
	CHECK(l1->state_of(id) == "quarantined");
	CHECK(l1->is_active(fine));
	Dictionary out_op;
	out_op["kind"] = "out";
	out_op["ids"] = arr(id);
	CHECK_FALSE(l0->prepare("x", out_op));
	CHECK(l0->items_of("eve").size() == 0);
	CHECK(CgameItemLedger::resolve_duplicate(ledgers, id) == 1);
	CHECK_FALSE(l0->has_item(id));
	CHECK(l1->is_active(id));
	CHECK(CgameItemLedger::find_duplicates(ledgers).size() == 0);
	Dictionary rec;
	rec["id"] = id;
	rec["owner"] = "eve";
	rec["def"] = "gem";
	rec["epoch"] = 1;
	Dictionary in_op;
	in_op["kind"] = "in";
	in_op["recs"] = arr(rec);
	CHECK_FALSE(l1->prepare("y", in_op));
}

// ---------------------------------------------------------------- guilds

TEST_CASE("[CgameGuildSync] Replicas converge regardless of delivery order") {
	Ref<CgameGuildSync> a;
	Ref<CgameGuildSync> b;
	Ref<CgameGuildSync> c;
	Ref<CgameGuildSync> c2;
	for (Ref<CgameGuildSync> *r : { &a, &b, &c, &c2 }) {
		r->instantiate();
	}
	b->set_server_id(1);
	c->set_server_id(2);
	c2->set_server_id(3);
	Dictionary o1 = a->join("g", "p1", 1);
	Dictionary o2 = a->join("g", "p2", 1);
	for (const Dictionary &op : { o1, o2 }) {
		b->receive(op);
		c->receive(op);
	}
	CHECK(same(c->members("g"), arr("p1", "p2")));

	// Concurrent: an officer on A promotes p1 while an officer on B kicks p1.
	Dictionary rank = a->set_rank("g", "p1", 5);
	Dictionary kick = b->kick("g", "p1");
	a->receive(kick);
	b->receive(rank);
	c->receive(rank);
	c->receive(kick);
	c2->receive(o1);
	c2->receive(kick);
	c2->receive(rank); // Opposite order on a fresh replica.
	c2->receive(o2);
	CHECK(same(a->members("g"), arr("p2")));
	CHECK(same(b->members("g"), arr("p2")));
	CHECK(same(c->members("g"), arr("p2")));
	CHECK(same(c2->members("g"), arr("p2")));
	CHECK(a->digest("g") == b->digest("g"));
	CHECK(b->digest("g") == c->digest("g"));
	CHECK(c->digest("g") == c2->digest("g"));
	CHECK(a->rank_of("g", "p1") == -1);

	// A kick beats a concurrent join, but a re-invite that observed the kick restores the member.
	Dictionary stale_join = c->join("g", "p9", 1);
	Dictionary stale_kick = a->kick("g", "p9");
	a->receive(stale_join);
	c->receive(stale_kick);
	CHECK_FALSE(a->is_member("g", "p9"));
	Dictionary rejoin = a->join("g", "p9", 2);
	c->receive(rejoin);
	b->receive(stale_join);
	b->receive(stale_kick);
	b->receive(rejoin);
	CHECK(a->is_member("g", "p9"));
	CHECK(b->is_member("g", "p9"));
	CHECK(c->is_member("g", "p9"));

	// Last-writer-wins rank, idempotent treasury, motd.
	Dictionary r1 = a->set_rank("g", "p2", 3);
	Dictionary r2 = b->set_rank("g", "p2", 4);
	a->receive(r2);
	b->receive(r1);
	CHECK(a->rank_of("g", "p2") == b->rank_of("g", "p2"));
	Dictionary dep = a->deposit("g", 100);
	b->receive(dep);
	b->receive(dep);
	CHECK(b->treasury("g") == 100);
	a->set_motd("g", "hello");

	// Pull-based anti-entropy brings stragglers up to date.
	c2->sync_from(a.ptr());
	c2->sync_from(b.ptr());
	c->sync_from(a.ptr());
	c->sync_from(b.ptr());
	a->sync_from(c.ptr());
	b->sync_from(c.ptr());
	CHECK(c2->motd("g") == "hello");
	CHECK(a->digest("g") == c2->digest("g"));
	CHECK(b->digest("g") == c->digest("g"));
	CHECK(a->digest("g") == b->digest("g"));
	CHECK(int(c2->get_vv()["0"]) == int(a->get_vv()["0"]));
}

// ---------------------------------------------------------------- parties

TEST_CASE("[CgamePartyMigration] Party follows its leader across servers") {
	Ref<CgameClusterSimulator> sim = make_sim(3, 21);
	sim->add_player("lead", Vector2(50, 50), 2);
	sim->add_player("m1", Vector2(150, 50), 1);
	sim->add_player("m2", Vector2(250, 50), 1);
	sim->create_party("pt", "lead", arr("m1", "m2"));
	drain(sim, 10);
	CHECK(String(sim->parties(2)->get_doc("pt")["leader"]) == "lead");
	CHECK(sim->migrate_player("lead", 2) == "committed");
	CHECK(sim->quiesce());
	for (const String p : { String("lead"), String("m1"), String("m2") }) {
		CHECK(sim->player_server(p) == 2);
	}
	Dictionary doc = sim->parties(0)->get_doc("pt");
	CHECK(String(doc["leader"]) == "lead");
	Dictionary ms = doc["members"];
	Array names = ms.keys();
	names.sort();
	CHECK(same(names, arr("lead", "m1", "m2")));
	CHECK(int(doc["home"]) == 2);
	CHECK(sim->parties(1)->same_as(sim->parties(2).ptr(), "pt"));
	CHECK(sim->parties(0)->same_as(sim->parties(2).ptr(), "pt"));
	CHECK(sim->ledger(2)->items_of("lead").size() == 2);
	CHECK(sim->check_invariants().is_empty());

	// Fencing by epoch: stale snapshots and stale-home writes are refused.
	Dictionary old = sim->parties(2)->snapshot("pt");
	Ref<CgamePartyMigration> home = sim->parties(2);
	CHECK_FALSE(home->leader_handoff("pt", 1).is_empty());
	CHECK_FALSE(home->add_member("pt", "x", 2));
	CHECK_FALSE(home->apply_replica(old));
	CHECK(int(home->get_doc("pt")["epoch"]) > int(old["epoch"]));

	Ref<CgamePartyMigration> p0;
	p0.instantiate();
	p0->create("q", "a");
	p0->add_member("q", "b", 0);
	CHECK(p0->remove_member("q", "a"));
	CHECK(String(p0->get_doc("q")["leader"]) == "b");
	sim->teardown();
}

// ---------------------------------------------------------------- leases

TEST_CASE("[CgameOwnershipLeases] Fencing tokens reject stale holders") {
	Ref<CgameOwnershipLeases> lt;
	lt.instantiate();
	Ref<CgameFencedStore> store;
	store.instantiate();
	Dictionary g1 = lt->acquire("zone", "A", 0.0, 10.0);
	CHECK(bool(g1["ok"]));
	CHECK(int(g1["token"]) == 1);
	CHECK(store->write("zone", int(g1["token"]), "A-v1"));
	CHECK_FALSE(bool(lt->acquire("zone", "B", 5.0, 10.0)["ok"]));
	CHECK(lt->renew("zone", "A", 1, 6.0, 10.0));
	CHECK_FALSE(bool(lt->acquire("zone", "B", 12.0, 10.0)["ok"]));

	// A stalls past expiry; B takes over with a higher token.
	CHECK(lt->holder_of("zone", 20.0) == "");
	Dictionary g2 = lt->acquire("zone", "B", 20.0, 10.0);
	CHECK(int(g2["token"]) == 2);
	CHECK_FALSE(lt->renew("zone", "A", 1, 21.0, 10.0));
	CHECK(store->write("zone", int(g2["token"]), "B-v1"));
	CHECK_FALSE(store->write("zone", 1, "A-stale"));
	CHECK(String(store->read("zone")) == "B-v1");
	CHECK(store->get_rejected() == 1);
	CHECK_FALSE(lt->is_valid("zone", "A", 1, 21.0));
	CHECK(lt->is_valid("zone", "B", 2, 21.0));
	CHECK_FALSE(lt->release("zone", "A", 1));
	CHECK(lt->release("zone", "B", 2));
	CHECK(int(lt->acquire("zone", "A", 22.0, 10.0)["token"]) == 3);
	CHECK_FALSE(CgameOwnershipLeases::client_valid(30.0, 29.0, 2.0));
	CHECK(CgameOwnershipLeases::client_valid(30.0, 27.0, 2.0));
	lt->acquire("other", "C", 22.0, 1.0);
	CHECK(lt->reap(100.0).size() == 2);
	CHECK(lt->token_of("zone") == 3);
}

// ---------------------------------------------------------------- balancing and failover

TEST_CASE("[CgameClusterSimulator] Load balancing moves regions and players, failover reassigns") {
	Ref<CgameClusterSimulator> sim = make_sim(3, 33);
	Array owned0;
	PackedInt32Array owners = sim->get_sharding()->get_region_owner();
	for (int r = 0; r < sim->get_sharding()->region_count(); r++) {
		if (owners[r] == 0) {
			owned0.push_back(r);
		}
	}
	int k = 0;
	for (int i = 0; i < MIN(4, owned0.size()); i++) {
		const int r = owned0[i];
		const int cx = r % 4;
		const int cy = r / 4;
		for (int j = 0; j < 3; j++) {
			sim->add_player("pl" + itos(k), Vector2(cx * 100.0 + 20.0 + j * 20.0, cy * 100.0 + 50.0), 2);
			k++;
		}
	}
	Array before = sim->server_load_report();
	CHECK(double(before[0]) == doctest::Approx(12.0));
	CHECK(double(before[1]) == doctest::Approx(0.0));
	Array moves = sim->rebalance();
	CHECK(moves.size() > 0);
	CHECK(sim->quiesce());
	Array after = sim->server_load_report();
	CHECK(double(after[0]) < 12.0);
	CHECK(double(after[0]) <= double(after[1]) * 3.0 + 3.0);
	int lost = 0;
	Dictionary players = sim->get_sharding()->get_players();
	for (int i = 0; i < sim->get_player_ids().size(); i++) {
		const String pid = sim->get_player_ids()[i];
		Dictionary p = players[pid];
		if (sim->player_server(pid) != sim->get_sharding()->owner_at(p["pos"])) {
			lost++;
		}
		if (sim->ledger(sim->player_server(pid))->items_of(pid).size() != 2) {
			lost++;
		}
	}
	CHECK(lost == 0);
	CHECK(sim->check_invariants().is_empty());
	Dictionary mv = moves[0];
	CHECK(int(sim->get_region_token()[int(mv["region"])]) >= 2);
	CHECK(sim->get_leases()->holder_of("region:" + itos(int(mv["region"])), double(sim->get_tick())) == "s" + itos(int(mv["to"])));

	// Failover: a long outage expires the leases and the regions move to live servers.
	sim->crash_server(1, 500);
	drain(sim, 40);
	int on_dead = 0;
	owners = sim->get_sharding()->get_region_owner();
	for (int r = 0; r < sim->get_sharding()->region_count(); r++) {
		if (owners[r] == 1) {
			on_dead++;
		}
	}
	CHECK(on_dead == 0);
	CHECK(int(sim->get_stats()["failovers"]) > 0);
	CHECK(sim->get_fenced()->get_rejected() == 0);
	sim->teardown();
}

// ---------------------------------------------------------------- randomized fault runs

TEST_CASE("[CgameClusterSimulator] Seeded fault runs conserve items and converge") {
	int crashes = 0;
	int committed = 0;
	for (const int64_t seed_value : { 1, 7, 42 }) {
		Ref<CgameClusterSimulator> sim = make_sim(4, seed_value);
		Ref<RandomNumberGenerator> rng = sim->get_rng();
		for (int i = 0; i < 8; i++) {
			const float x = rng->randf_range(5, 395);
			const float y = rng->randf_range(5, 395);
			sim->add_player("p" + itos(i), Vector2(x, y), 3);
		}
		for (int s = 0; s < 4; s++) {
			for (int j = 0; j < 4; j++) {
				sim->mint_item(s, "p" + itos(rng->randi_range(0, 7)));
			}
		}
		sim->create_party("pa", "p0", arr("p1", "p2"));
		for (int i = 0; i < 4; i++) {
			sim->guild_op(i, "g0", "join", "p" + itos(i), 1);
		}
		sim->run_random(350);
		CHECK_MESSAGE(sim->quiesce(), "seed ", seed_value, " settles");
		Array bad = sim->check_invariants();
		CHECK_MESSAGE(bad.is_empty(), "seed ", seed_value, " invariants: ", String(Variant(bad)).utf8().get_data());
		int total = 0;
		for (int i = 0; i < 4; i++) {
			total += sim->ledger(i)->total_count();
		}
		CHECK(total == 8 * 3 + 16);
		Dictionary d = sim->parties(0)->get_doc("pa");
		CHECK(String(d["leader"]) == "p0");
		Dictionary members = d["members"];
		CHECK(members.size() == 3);
		crashes += int(sim->get_stats()["server_crashes"]) + int(sim->get_stats()["coord_crashes"]);
		committed += int(sim->get_stats()["moves_committed"]);
		sim->teardown();
	}
	CHECK(crashes > 0);
	CHECK(committed > 10);
}

TEST_CASE("[CgameClusterSimulator] Runs are deterministic for a fixed seed") {
	Ref<CgameClusterSimulator> sa = make_sim(3, 99);
	Ref<CgameClusterSimulator> sb = make_sim(3, 99);
	for (const Ref<CgameClusterSimulator> &s : { sa, sb }) {
		for (int i = 0; i < 3; i++) {
			s->add_player("q" + itos(i), Vector2(50 + i * 100, 50), 2);
		}
		s->run_random(120);
	}
	CHECK(JSON::stringify(sa->get_stats()) == JSON::stringify(sb->get_stats()));
	sa->teardown();
	sb->teardown();
}

} // namespace TestCgameServerDistribution
