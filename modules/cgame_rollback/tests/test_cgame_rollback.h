/**************************************************************************/
/*  test_cgame_rollback.h                                                 */
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

#include "../cgame_client_prediction.h"
#include "../cgame_deterministic_physics.h"
#include "../cgame_net_conditioner.h"
#include "../cgame_physics_rollback.h"
#include "../cgame_physics_timeline.h"
#include "../cgame_rollback_debugger.h"
#include "../cgame_rollback_netcode.h"

#include "core/io/json.h"
#include "core/math/math_funcs.h"
#include "core/math/random_pcg.h"
#include "core/object/callable_mp.h"
#include "core/templates/hash_set.h"
#include "tests/test_macros.h"

#include <cstring>

namespace TestCgameRollback {

static const double DT = 1.0 / 60.0;

// --- deterministic toy simulation -------------------------------------------------------------

static Dictionary toy_initial() {
	Dictionary x;
	x[1] = 0;
	x[2] = 0;
	Dictionary s;
	s["tick"] = 0;
	s["acc"] = 0;
	s["x"] = x;
	return s;
}

static Dictionary toy_step(Dictionary p_state, Dictionary p_inputs, double p_dt) {
	Dictionary x = p_state["x"];
	int64_t acc = p_state["acc"];
	Array keys = p_inputs.keys();
	for (int i = 0; i < keys.size(); i++) {
		int64_t pid = keys[i];
		Dictionary inp = p_inputs[pid];
		int64_t dx = inp.get("dx", 0);
		int64_t nx = int64_t(x[pid]) + dx;
		x[pid] = nx;
		acc = (acc * 31 + dx * pid + nx) % 1000003;
	}
	p_state["acc"] = acc;
	p_state["tick"] = int64_t(p_state["tick"]) + 1;
	return p_state;
}

// Deliberately non-deterministic relative to the clean peer.
static Dictionary toy_biased_step(Dictionary p_state, Dictionary p_inputs, double p_dt) {
	if (int64_t(p_state["tick"]) == 5) {
		p_state["acc"] = int64_t(p_state["acc"]) + 1;
	}
	return toy_step(p_state, p_inputs, p_dt);
}

static Dictionary toy_input(int64_t p_pid, int64_t p_n) {
	Dictionary d;
	d["dx"] = ((p_n * 7 + p_pid * 3) % 5) - 2;
	return d;
}

static int64_t toy_reference_checksum(int64_t p_frame, int64_t p_delay) {
	Dictionary s = toy_initial();
	for (int64_t f = 0; f < p_frame; f++) {
		Dictionary inputs;
		for (int64_t pid = 1; pid <= 2; pid++) {
			inputs[pid] = f < p_delay ? Dictionary() : toy_input(pid, f - p_delay);
		}
		s = toy_step(s, inputs, DT);
	}
	return CgameRollbackNetcode::state_checksum(s);
}

static Array ids2(int64_t p_a, int64_t p_b) {
	Array a;
	a.push_back(p_a);
	a.push_back(p_b);
	return a;
}

static Array ids1(int64_t p_a) {
	Array a;
	a.push_back(p_a);
	return a;
}

static Ref<CgameRollbackNetcode> make_net(int64_t p_local_pid, int64_t p_delay, int64_t p_max_pred, bool p_biased = false) {
	Ref<CgameRollbackNetcode> nc;
	nc.instantiate();
	Callable step = p_biased ? callable_mp_static(&toy_biased_step) : callable_mp_static(&toy_step);
	nc->setup(step, toy_initial(), ids2(1, 2), ids1(p_local_pid), DT, p_delay, p_max_pred);
	return nc;
}

struct WireMessage {
	int64_t at = 0;
	int to = 0;
	bool is_input = false;
	int64_t player = 0;
	int64_t frame = 0;
	Dictionary input;
	int64_t checksum = 0;
};

// Runs two peers over a link with `latency` ticks.
static void run_peers(Ref<CgameRollbackNetcode> r_peers[2], int p_ticks, int p_latency, int p_delay, int p_max_pred, bool p_bias_b,
		bool p_jitter, int64_t &r_max_snapshots) {
	r_peers[0] = make_net(1, p_delay, p_max_pred);
	r_peers[1] = make_net(2, p_delay, p_max_pred, p_bias_b);
	int64_t counters[2] = { 0, 0 };
	Vector<WireMessage> wire;
	r_max_snapshots = 0;
	for (int tick = 0; tick < p_ticks; tick++) {
		Vector<WireMessage> due;
		Vector<WireMessage> rest;
		for (const WireMessage &m : wire) {
			if (m.at <= tick) {
				due.push_back(m);
			} else {
				rest.push_back(m);
			}
		}
		wire = rest;
		for (const WireMessage &m : due) {
			Ref<CgameRollbackNetcode> peer = r_peers[m.to];
			if (m.is_input) {
				peer->add_remote_input(m.player, m.frame, m.input);
			} else {
				peer->add_remote_checksum(m.frame, m.checksum);
			}
		}
		for (int i = 0; i < 2; i++) {
			Ref<CgameRollbackNetcode> peer = r_peers[i];
			int64_t pid = i + 1;
			peer->add_local_input(pid, toy_input(pid, counters[i]));
			counters[i]++;
			int lat = p_latency + (p_jitter ? tick % 3 : 0);
			Array out = peer->drain_outgoing();
			for (int k = 0; k < out.size(); k++) {
				Dictionary entry = out[k];
				WireMessage m;
				m.at = tick + lat;
				m.to = 1 - i;
				m.is_input = true;
				m.player = entry["player"];
				m.frame = entry["frame"];
				m.input = entry["input"];
				wire.push_back(m);
			}
			Array reports = peer->get_checksum_report();
			for (int k = 0; k < reports.size(); k++) {
				Dictionary rep = reports[k];
				WireMessage m;
				m.at = tick + p_latency;
				m.to = 1 - i;
				m.frame = rep["frame"];
				m.checksum = rep["checksum"];
				wire.push_back(m);
			}
			peer->advance();
			r_max_snapshots = MAX(r_max_snapshots, peer->snapshot_count());
		}
	}
}

TEST_CASE("[CgameRollbackNetcode] Two peers with latency converge to the lockstep reference") {
	const int configs[4][2] = { { 0, 0 }, { 3, 0 }, { 4, 2 }, { 6, 1 } };
	for (int c = 0; c < 4; c++) {
		int latency = configs[c][0];
		int delay = configs[c][1];
		Ref<CgameRollbackNetcode> peers[2];
		int64_t max_snapshots = 0;
		run_peers(peers, 120, latency, delay, 12, false, latency > 3, max_snapshots);
		Ref<CgameRollbackNetcode> a = peers[0];
		Ref<CgameRollbackNetcode> b = peers[1];
		int64_t f = MIN(MIN(a->get_confirmed_frame(), b->get_confirmed_frame()) + 1, MIN(a->get_frame(), b->get_frame()));
		CHECK_MESSAGE(f > 60, "confirmed far enough");
		CHECK(a->checksum_of(f) == b->checksum_of(f));
		CHECK(a->checksum_of(f) == toy_reference_checksum(f, delay));
		CHECK(!a->has_desync());
		CHECK(!b->has_desync());
		if (latency > 0 && delay < latency) {
			CHECK_MESSAGE(a->get_rollbacks() > 0, "prediction misses cause rollbacks");
		}
		CHECK(max_snapshots <= a->get_snapshot_capacity());
		CHECK(a->snapshot_count() <= a->get_snapshot_capacity());
	}
}

TEST_CASE("[CgameRollbackNetcode] Late input triggers a rollback that reproduces the reference bytes") {
	Ref<CgameRollbackNetcode> nc = make_net(1, 0, 12);
	for (int n = 0; n < 10; n++) {
		nc->add_local_input(1, toy_input(1, n));
		CHECK(nc->advance());
	}
	CHECK(nc->get_frame() == 10);
	CHECK(nc->get_confirmed_frame() == -1);
	CHECK(nc->get_rollbacks() == 0);
	for (int f = 0; f < 10; f++) {
		nc->add_remote_input(2, f, toy_input(2, f));
	}
	CHECK(nc->get_confirmed_frame() == 9);
	nc->process();
	CHECK(nc->get_rollbacks() >= 1);
	CHECK(nc->get_resimulated_frames() > 0);
	CHECK(nc->get_frame() == 10);
	CHECK(CgameRollbackNetcode::state_checksum(nc->get_state()) == toy_reference_checksum(10, 0));

	// Duplicate and stale deliveries are harmless.
	int64_t before = nc->get_rollbacks();
	Dictionary bogus;
	bogus["dx"] = 99;
	nc->add_remote_input(2, 3, bogus);
	nc->process();
	CHECK(nc->get_rollbacks() == before);
	CHECK(!nc->rollback_to(500));
	CHECK(!nc->rollback_to(-5));

	// Matching prediction needs no rollback.
	Ref<CgameRollbackNetcode> quiet = make_net(1, 0, 12);
	for (int n = 0; n < 5; n++) {
		quiet->add_local_input(1, Dictionary());
		quiet->advance();
	}
	for (int f = 0; f < 5; f++) {
		quiet->add_remote_input(2, f, Dictionary());
	}
	quiet->process();
	CHECK(quiet->get_rollbacks() == 0);
}

TEST_CASE("[CgameRollbackNetcode] Desync detection") {
	Ref<CgameRollbackNetcode> peers[2];
	int64_t max_snapshots = 0;
	run_peers(peers, 80, 2, 0, 12, true, false, max_snapshots);
	CHECK(peers[0]->has_desync());
	CHECK(peers[1]->has_desync());
	if (peers[0]->has_desync()) {
		Array frames = peers[0]->get_desync_frames();
		CHECK(int64_t(frames[0]) == 6);
	}
	Ref<CgameRollbackNetcode> clean[2];
	run_peers(clean, 80, 2, 0, 12, false, false, max_snapshots);
	CHECK(!clean[0]->has_desync());
}

TEST_CASE("[CgameRollbackNetcode] Prediction window stalls and lockstep mode") {
	Ref<CgameRollbackNetcode> nc = make_net(1, 0, 4);
	int advanced = 0;
	for (int n = 0; n < 10; n++) {
		nc->add_local_input(1, toy_input(1, n));
		if (nc->advance()) {
			advanced++;
		}
	}
	CHECK(advanced == 4);
	CHECK(nc->get_frame() == 4);
	CHECK(nc->is_stalled());
	CHECK(nc->get_stall_count() > 0);
	for (int f = 0; f < 4; f++) {
		nc->add_remote_input(2, f, toy_input(2, f));
	}
	CHECK(!nc->is_stalled());
	while (nc->advance()) {
	}
	CHECK(nc->get_frame() == 8);

	Ref<CgameRollbackNetcode> lock = make_net(1, 0, 0);
	lock->add_local_input(1, Dictionary());
	CHECK(!lock->advance());
	lock->add_remote_input(2, 0, Dictionary());
	CHECK(lock->advance());
	CHECK(lock->get_rollbacks() == 0);
	CHECK(nc->snapshot_count() <= nc->get_snapshot_capacity());
}

TEST_CASE("[CgameRollbackNetcode] Input delay prefill and outgoing queue") {
	Ref<CgameRollbackNetcode> nc = make_net(1, 2, 8);
	Array out = nc->drain_outgoing();
	CHECK(out.size() == 2); // Delay prefill frames 0 and 1.
	CHECK(nc->add_local_input(1, Dictionary()) == 2);
	CHECK(nc->drain_outgoing().size() == 1);
	CHECK(nc->drain_outgoing().size() == 0);
	CHECK(nc->add_local_input(2, Dictionary()) == -1); // Not a local player.
}

// --- client prediction ------------------------------------------------------------------------

static Dictionary move_apply(Dictionary p_state, Dictionary p_input, double p_dt) {
	Vector2 dir = p_input.get("dir", Vector2());
	p_state["pos"] = Vector2(p_state["pos"]) + dir * 100.0 * p_dt;
	return p_state;
}

static Dictionary server_move(Dictionary p_state, Dictionary p_input, double p_dt) {
	Vector2 dir = p_input.get("dir", Vector2());
	p_state["pos"] = Vector2(p_state["pos"]) + dir * 90.0 * p_dt; // The server is slightly slower.
	return p_state;
}

static Dictionary move_input(const Vector2 &p_dir) {
	Dictionary d;
	d["dir"] = p_dir;
	return d;
}

static Dictionary pos_state(const Variant &p_pos) {
	Dictionary d;
	d["pos"] = p_pos;
	return d;
}

TEST_CASE("[CgameClientPrediction] Reconcile replays pending inputs and smooths the correction") {
	Ref<CgameClientPrediction> cp;
	cp.instantiate();
	cp->setup(callable_mp_static(&move_apply), pos_state(Vector2()), "pos", 50.0, 10.0);
	Dictionary server = pos_state(Vector2());
	Vector<Dictionary> inputs;
	for (int n = 0; n < 12; n++) {
		Dictionary inp = move_input(Vector2(1, n < 6 ? 0.0 : 1.0));
		inputs.push_back(inp);
		CHECK(cp->predict(inp, DT) == n + 1);
	}
	CHECK(cp->pending_count() == 12);
	CHECK(Vector2(Dictionary(cp->get_state())["pos"]).x == doctest::Approx(12 * 100.0 * DT).epsilon(0.001));
	Vector2 predicted = Dictionary(cp->get_state())["pos"];
	for (int n = 0; n < 6; n++) {
		server = server_move(server, inputs[n], DT);
	}
	double err = cp->reconcile(server, 6);
	CHECK(err > 0.0);
	CHECK(cp->pending_count() == 6);
	Dictionary expected = server.duplicate(true);
	for (int n = 6; n < 12; n++) {
		expected = move_apply(expected, inputs[n], DT);
	}
	CHECK(Vector2(Dictionary(cp->get_state())["pos"]).distance_to(Vector2(expected["pos"])) < 0.0001);
	Vector2 vis = cp->visual_state()["pos"];
	CHECK_MESSAGE(vis.distance_to(predicted) < 0.001, "no visible pop");
	CHECK(cp->offset_magnitude() > 0.0);
	double before = cp->offset_magnitude();
	cp->update(0.05);
	CHECK(cp->offset_magnitude() < before);
	CHECK(cp->offset_magnitude() == doctest::Approx(before * Math::exp(-0.5)).epsilon(0.001));
	for (int k = 0; k < 60; k++) {
		cp->update(DT);
	}
	CHECK(cp->offset_magnitude() < 0.01);
	for (int n = 6; n < 12; n++) {
		server = server_move(server, inputs[n], DT);
	}
	cp->reconcile(server, 12);
	CHECK(cp->pending_count() == 0);
	CHECK(Vector2(Dictionary(cp->get_state())["pos"]).distance_to(Vector2(server["pos"])) < 0.0001);
	CHECK(cp->reconcile(server, 5) == 0.0);
	CHECK(cp->get_last_acked_seq() == 12);
}

TEST_CASE("[CgameClientPrediction] Large errors snap and scalar positions work") {
	Ref<CgameClientPrediction> snap;
	snap.instantiate();
	snap->setup(callable_mp_static(&move_apply), pos_state(Vector2()), "pos", 1.0, 10.0);
	snap->predict(move_input(Vector2(1, 0)), DT);
	double big = snap->reconcile(pos_state(Vector2(40, 0)), 1);
	CHECK(big > 1.0);
	CHECK(snap->get_snaps() == 1);
	CHECK(snap->offset_magnitude() == 0.0);
	CHECK(Vector2(Dictionary(snap->get_state())["pos"]).x == doctest::Approx(40.0).epsilon(0.0001));

	Ref<CgameClientPrediction> scalar;
	scalar.instantiate();
	scalar->setup(callable_mp_static(&move_apply), pos_state(0.0), "pos", 10.0, 5.0);
	CHECK(scalar->offset_magnitude() == 0.0);
}

// --- rollback debugger ------------------------------------------------------------------------

static Dictionary dbg_step(Dictionary p_state, Dictionary p_inputs, double p_dt) {
	Dictionary pos = p_state["pos"];
	Array keys = p_inputs.keys();
	for (int i = 0; i < keys.size(); i++) {
		Dictionary inp = p_inputs[keys[i]];
		pos[keys[i]] = int64_t(pos.get(keys[i], 0)) + int64_t(inp.get("dx", 0));
	}
	p_state["pos"] = pos;
	return p_state;
}

static Dictionary dbg_bad_step(Dictionary p_state, Dictionary p_inputs, double p_dt) {
	Dictionary s = dbg_step(p_state, p_inputs, p_dt);
	Dictionary pos = s["pos"];
	pos[2] = int64_t(pos.get(2, 0)) + 1;
	return s;
}

static Ref<CgameRollbackNetcode> make_dbg_net(const Callable &p_step) {
	Ref<CgameRollbackNetcode> n;
	n.instantiate();
	Dictionary pos;
	pos[1] = 0;
	pos[2] = 0;
	Dictionary init;
	init["pos"] = pos;
	n->setup(p_step, init, ids2(1, 2), ids1(1), DT, 0, 8, 0);
	return n;
}

static Dictionary dx_input(int64_t p_dx) {
	Dictionary d;
	d["dx"] = p_dx;
	return d;
}

TEST_CASE("[CgameRollbackDebugger] Records rollbacks, cause and miss rate") {
	Ref<CgameRollbackNetcode> net = make_dbg_net(callable_mp_static(&dbg_step));
	Ref<CgameRollbackDebugger> dbg;
	dbg.instantiate();
	dbg->attach(net);
	for (int i = 0; i < 5; i++) {
		dbg->add_local_input(1, dx_input(1));
		dbg->advance();
	}
	CHECK(dbg->get_rollbacks().size() == 0);
	// Remote player 2 actually moved; the prediction (empty) was wrong for frame 1, right for frame 0.
	dbg->add_remote_input(2, 0, Dictionary());
	dbg->add_remote_input(2, 1, dx_input(3));
	dbg->process();
	REQUIRE(dbg->get_rollbacks().size() == 1);
	Dictionary r = dbg->get_rollbacks()[0];
	CHECK(int64_t(r["from_frame"]) == 1);
	CHECK(int64_t(r["to_frame"]) == 5);
	CHECK(int64_t(r["frames_resimulated"]) == 4);
	CHECK(int64_t(r["cause"]) == 2);
	CHECK(dbg->miss_rate(2) == doctest::Approx(0.5).epsilon(0.001));
	Dictionary pos = net->get_state()["pos"];
	CHECK(int64_t(pos[2]) == 12);
	CHECK(dbg->report().contains("rollbacks=1"));
}

TEST_CASE("[CgameRollbackDebugger] Desync diff names the diverged key path") {
	Ref<CgameRollbackNetcode> na = make_dbg_net(callable_mp_static(&dbg_step));
	Ref<CgameRollbackNetcode> nb = make_dbg_net(callable_mp_static(&dbg_bad_step));
	Ref<CgameRollbackDebugger> da;
	Ref<CgameRollbackDebugger> db;
	da.instantiate();
	db.instantiate();
	da->attach(na);
	db->attach(nb);
	for (int i = 0; i < 4; i++) {
		Ref<CgameRollbackNetcode> both[2] = { na, nb };
		for (int k = 0; k < 2; k++) {
			both[k]->add_local_input(1, dx_input(1));
			both[k]->add_remote_input(2, i, dx_input(0));
		}
		da->advance();
		db->advance();
	}
	Array reports = nb->get_checksum_report();
	for (int i = 0; i < reports.size(); i++) {
		Dictionary e = reports[i];
		na->add_remote_checksum(e["frame"], e["checksum"]);
	}
	CHECK(na->has_desync());
	REQUIRE(da->get_desyncs().size() > 0);
	int64_t fr = Dictionary(da->get_desyncs()[0])["frame"];
	Array diff = da->attach_remote_state(fr, db->state_history(fr));
	CHECK(diff.has("pos.2"));
	CHECK(!diff.has("pos.1"));

	Dictionary inner_a;
	inner_a["b"] = 1;
	Array arr_a;
	arr_a.push_back(1);
	arr_a.push_back(2);
	inner_a["c"] = arr_a;
	Dictionary a;
	a["a"] = inner_a;
	Dictionary inner_b;
	inner_b["b"] = 2;
	Array arr_b;
	arr_b.push_back(1);
	arr_b.push_back(3);
	inner_b["c"] = arr_b;
	Dictionary b;
	b["a"] = inner_b;
	b["d"] = 1;
	Array paths = CgameRollbackDebugger::diff_states(a, b);
	REQUIRE(paths.size() == 3);
	CHECK(String(paths[0]) == "a.b");
	CHECK(String(paths[1]) == "a.c[1]");
	CHECK(String(paths[2]) == "d");
	CHECK(da->report().contains("DESYNC"));
}

// --- net conditioner --------------------------------------------------------------------------

static PackedByteArray make_bytes(int p_n) {
	PackedByteArray p;
	p.resize(p_n);
	p.fill(0);
	return p;
}

static Dictionary conditioner_config(double p_latency, double p_jitter, double p_loss, double p_dup, double p_reorder, double p_bw, double p_queue, int64_t p_seed) {
	Dictionary cfg;
	cfg["latency_ms"] = p_latency;
	cfg["jitter_ms"] = p_jitter;
	cfg["loss"] = p_loss;
	cfg["duplicate"] = p_dup;
	cfg["reorder"] = p_reorder;
	cfg["bandwidth_kbps"] = p_bw;
	cfg["max_queue_ms"] = p_queue;
	cfg["seed"] = p_seed;
	return cfg;
}

TEST_CASE("[CgameNetConditioner] Latency and jitter stay within bounds") {
	Ref<CgameNetConditioner> nc;
	nc.instantiate();
	nc->configure(conditioner_config(100.0, 20.0, 0.0, 0.0, 0.0, 0.0, 1000.0, 7));
	for (int i = 0; i < 200; i++) {
		PackedByteArray b;
		b.push_back(uint8_t(i % 256));
		nc->send(0, b, double(i) * 0.01);
	}
	double lo = 1e9;
	double hi = 0.0;
	Array tl = nc->timeline(0.0, 100.0);
	for (int i = 0; i < tl.size(); i++) {
		Dictionary d = tl[i];
		double ms = (double(d["delivered_at"]) - double(d["sent_at"])) * 1000.0;
		lo = MIN(lo, ms);
		hi = MAX(hi, ms);
	}
	CHECK(lo >= 79.99);
	CHECK(hi <= 120.01);
	CHECK(hi - lo > 5.0);
	CHECK(nc->receive(0.05).size() < 200);
	CHECK(nc->receive(1000.0).size() > 0);
}

TEST_CASE("[CgameNetConditioner] Loss rate for a fixed seed") {
	Ref<CgameNetConditioner> lossy;
	lossy.instantiate();
	lossy->configure(conditioner_config(0.0, 0.0, 0.2, 0.0, 0.0, 0.0, 1000.0, 3));
	for (int i = 0; i < 2000; i++) {
		lossy->send(1, make_bytes(3), 0.0);
	}
	Dictionary st = lossy->stats();
	CHECK(Math::abs(double(int64_t(st["dropped"])) / 2000.0 - 0.2) < 0.04);
	CHECK(int64_t(st["dropped"]) + int64_t(st["delivered"]) == 2000);

	// The same seed reproduces the exact same drops.
	Ref<CgameNetConditioner> again;
	again.instantiate();
	again->configure(conditioner_config(0.0, 0.0, 0.2, 0.0, 0.0, 0.0, 1000.0, 3));
	for (int i = 0; i < 2000; i++) {
		again->send(1, make_bytes(3), 0.0);
	}
	CHECK((again->timeline(0.0, 10.0) == lossy->timeline(0.0, 10.0)));
}

TEST_CASE("[CgameNetConditioner] Duplicate and reorder") {
	Ref<CgameNetConditioner> dr;
	dr.instantiate();
	dr->configure(conditioner_config(50.0, 0.0, 0.0, 0.2, 0.2, 0.0, 1000.0, 11));
	for (int i = 0; i < 300; i++) {
		PackedByteArray b;
		b.push_back(uint8_t(i % 256));
		dr->send(0, b, double(i) * 0.005);
	}
	Array got = dr->receive(100.0);
	Dictionary ds = dr->stats();
	CHECK(int64_t(ds["duplicated"]) > 0);
	CHECK(got.size() > 300);
	CHECK(int64_t(ds["reordered"]) > 0);
	bool inverted = false;
	int64_t last_id = -1;
	HashSet<int64_t> seen;
	for (int i = 0; i < got.size(); i++) {
		Dictionary gd = got[i];
		int64_t gid = gd["id"];
		if (!seen.has(gid)) {
			if (gid < last_id) {
				inverted = true;
			}
			last_id = MAX(last_id, gid);
			seen.insert(gid);
		}
	}
	CHECK_MESSAGE(inverted, "receive order differs from send order");
}

TEST_CASE("[CgameNetConditioner] Bandwidth cap queues and drops") {
	Ref<CgameNetConditioner> bw;
	bw.instantiate();
	bw->configure(conditioner_config(10.0, 0.0, 0.0, 0.0, 0.0, 80.0, 150.0, 1));
	Vector<int64_t> ids;
	for (int i = 0; i < 30; i++) {
		ids.push_back(bw->send(0, make_bytes(100), 0.0));
	}
	Dictionary bst = bw->stats();
	CHECK(int64_t(bst["dropped_bandwidth"]) > 0);
	Dictionary first = bw->packet(ids[0]);
	Dictionary queued = bw->packet(ids[10]);
	CHECK(double(queued["queue_ms"]) == doctest::Approx(100.0).epsilon(0.001));
	CHECK(double(queued["delivered_at"]) > double(first["delivered_at"]));
	CHECK(bw->delay_cause(ids[10]).contains("queued"));
	CHECK(bw->delay_cause(ids[29]).contains("dropped"));
	CHECK(bw->delay_cause(ids[0]).contains("base latency"));
}

TEST_CASE("[CgameNetConditioner] Determinism") {
	Dictionary cfg = conditioner_config(60.0, 30.0, 0.1, 0.1, 0.1, 200.0, 1000.0, 99);
	Ref<CgameNetConditioner> a;
	Ref<CgameNetConditioner> b;
	a.instantiate();
	b.instantiate();
	a->configure(cfg);
	b->configure(cfg);
	for (int i = 0; i < 100; i++) {
		a->send(0, make_bytes(50), double(i) * 0.01);
		b->send(0, make_bytes(50), double(i) * 0.01);
	}
	CHECK((a->timeline(0.0, 100.0) == b->timeline(0.0, 100.0)));
	CHECK((a->stats() == b->stats()));
	CHECK(double(a->stats()["throughput_bps"]) > 0.0);
}

// --- deterministic physics --------------------------------------------------------------------

static bool bytes_equal(const PackedByteArray &p_a, const PackedByteArray &p_b) {
	return p_a.size() == p_b.size() && (p_a.is_empty() || memcmp(p_a.ptr(), p_b.ptr(), p_a.size()) == 0);
}

static void add_ground(const Ref<CgameDeterministicPhysics> &p_w) {
	p_w->add_body(0, CgameDeterministicPhysics::SHAPE_BOX, 0.0, Vector3(0, -1, 0), Vector3(50, 1, 50), Quaternion(), 0.6, 0.0);
}

static void add_pile(const Ref<CgameDeterministicPhysics> &p_w) {
	add_ground(p_w);
	RandomPCG rng(1234);
	for (int i = 0; i < 8; i++) {
		Vector3 pos(rng.random(-1.0, 1.0), 1.0 + double(i) * 1.1, rng.random(-1.0, 1.0));
		Vector3 axis = Vector3(rng.randf(), rng.randf(), rng.randf()).normalized();
		Quaternion rot(axis, rng.random(0.0, 3.0));
		if (i % 2 == 0) {
			p_w->add_body(i + 1, CgameDeterministicPhysics::SHAPE_BOX, 1.0, pos, Vector3(0.5, 0.4, 0.3), rot, 0.5, 0.1);
		} else {
			p_w->add_body(i + 1, CgameDeterministicPhysics::SHAPE_SPHERE, 1.0, pos, Vector3(0.45, 0, 0), rot, 0.4, 0.3);
		}
	}
}

static Ref<CgameDeterministicPhysics> run_pile(int p_steps) {
	Ref<CgameDeterministicPhysics> w;
	w.instantiate();
	add_pile(w);
	for (int i = 0; i < p_steps; i++) {
		w->step(DT);
	}
	return w;
}

TEST_CASE("[CgameDeterministicPhysics] A box stack settles and sleeps") {
	Ref<CgameDeterministicPhysics> w;
	w.instantiate();
	add_ground(w);
	for (int i = 0; i < 4; i++) {
		w->add_body(i + 1, CgameDeterministicPhysics::SHAPE_BOX, 1.0, Vector3(0, 0.5 + i, 0), Vector3(0.5, 0.5, 0.5), Quaternion(), 0.6, 0.0);
	}
	int slept_at = -1;
	for (int s = 0; s < 600; s++) {
		w->step(DT);
		if (slept_at < 0 && w->sleeping_count() == 4) {
			slept_at = s;
		}
	}
	CHECK_MESSAGE(slept_at >= 0, "all four boxes fall asleep");
	bool ok_pos = true;
	for (int i = 0; i < 4; i++) {
		Vector3 p = w->get_position(i + 1);
		double expect_y = 0.5 + i;
		if (Math::abs(p.y - expect_y) > 0.06 || Math::abs(p.x) > 0.1 || Math::abs(p.z) > 0.1) {
			ok_pos = false;
		}
	}
	CHECK_MESSAGE(ok_pos, "stack stays upright at ~1 m spacing");
	CHECK(w->get_velocity(4) == Vector3());
	w->apply_impulse(4, Vector3(0, 5, 0));
	CHECK_MESSAGE(!w->is_asleep(4), "impulse wakes a sleeper");
}

TEST_CASE("[CgameDeterministicPhysics] Restitution bounce") {
	Ref<CgameDeterministicPhysics> wb;
	wb.instantiate();
	add_ground(wb);
	wb->add_body(1, CgameDeterministicPhysics::SHAPE_SPHERE, 1.0, Vector3(0, 5.5, 0), Vector3(0.5, 0, 0), Quaternion(), 0.3, 0.8);
	double impact = 0.0;
	double peak_up = 0.0;
	double apex = 0.0;
	bool bounced = false;
	for (int i = 0; i < 200; i++) {
		double vy_before = wb->get_velocity(1).y;
		wb->step(DT);
		double vy = wb->get_velocity(1).y;
		if (!bounced && vy_before < -1.0 && vy > 0.0) {
			bounced = true;
			impact = -vy_before;
			peak_up = vy;
		} else if (bounced) {
			apex = MAX(apex, double(wb->get_position(1).y));
		}
	}
	CHECK(bounced);
	CHECK(peak_up > 0.6 * impact);
	CHECK(peak_up < 0.95 * impact);
	CHECK(apex > 2.5);
	CHECK(apex < 3.9);
}

TEST_CASE("[CgameDeterministicPhysics] Determinism and snapshot restore") {
	Ref<CgameDeterministicPhysics> w1 = run_pile(240);
	Ref<CgameDeterministicPhysics> w2 = run_pile(240);
	CHECK(w1->checksum() == w2->checksum());
	CHECK(bytes_equal(w1->snapshot(), w2->snapshot()));
	Ref<CgameDeterministicPhysics> w3 = run_pile(241);
	CHECK(w3->checksum() != w1->checksum());
	bool moved = false;
	for (int i = 1; i <= 8; i++) {
		if (w1->get_position(i).y < 6.0) {
			moved = true;
		}
	}
	CHECK_MESSAGE(moved, "pile fell");

	Ref<CgameDeterministicPhysics> ws = run_pile(60);
	PackedByteArray snap = ws->snapshot();
	for (int i = 0; i < 60; i++) {
		ws->step(DT);
	}
	int64_t cs_a = ws->checksum();
	CHECK(ws->restore(snap));
	CHECK(bytes_equal(ws->snapshot(), snap));
	for (int i = 0; i < 60; i++) {
		ws->step(DT);
	}
	CHECK(ws->checksum() == cs_a);
	Ref<CgameDeterministicPhysics> fresh;
	fresh.instantiate();
	CHECK(fresh->restore(snap));
	for (int i = 0; i < 60; i++) {
		fresh->step(DT);
	}
	CHECK(fresh->checksum() == cs_a);
	CHECK(!fresh->restore(PackedByteArray()));
}

TEST_CASE("[CgameDeterministicPhysics] Raycast against boxes and spheres") {
	Ref<CgameDeterministicPhysics> wr;
	wr.instantiate();
	wr->add_body(1, CgameDeterministicPhysics::SHAPE_BOX, 0.0, Vector3(0, 0, 0), Vector3(1, 1, 1));
	Dictionary hr = wr->raycast(Vector3(-5, 0, 0), Vector3(1, 0, 0));
	CHECK(bool(hr["hit"]));
	CHECK(Math::abs(double(hr["t"]) - 4.0) < 0.001);
	CHECK(!bool(wr->raycast(Vector3(-5, 3, 0), Vector3(1, 0, 0))["hit"]));
	wr->add_body(2, CgameDeterministicPhysics::SHAPE_SPHERE, 0.0, Vector3(10, 0, 0), Vector3(1, 0, 0));
	Dictionary hs = wr->raycast(Vector3(5, 0, 0), Vector3(1, 0, 0));
	CHECK(int(hs["id"]) == 2);
	CHECK(Math::abs(double(hs["t"]) - 4.0) < 0.001);
}

// --- physics rollback -------------------------------------------------------------------------

static Ref<CgamePhysicsRollback> make_rollback_world() {
	Ref<CgamePhysicsRollback> pr;
	pr.instantiate();
	Ref<CgameDeterministicPhysics> w = pr->get_world();
	w->add_body(0, CgameDeterministicPhysics::SHAPE_BOX, 0.0, Vector3(0, -1, 0), Vector3(50, 1, 50), Quaternion(), 0.6, 0.0);
	w->add_body(1, CgameDeterministicPhysics::SHAPE_SPHERE, 1.0, Vector3(-2, 0.5, 0), Vector3(0.5, 0, 0), Quaternion(), 0.4, 0.2);
	w->add_body(2, CgameDeterministicPhysics::SHAPE_SPHERE, 1.0, Vector3(2, 0.5, 0), Vector3(0.5, 0, 0), Quaternion(), 0.4, 0.2);
	w->add_body(3, CgameDeterministicPhysics::SHAPE_BOX, 1.0, Vector3(0, 0.5, 0), Vector3(0.5, 0.5, 0.5), Quaternion(), 0.5, 0.0);
	pr->bind_player(10, 1);
	pr->bind_player(20, 2);
	return pr;
}

static Dictionary force_input(const Vector3 &p_f) {
	Dictionary d;
	d["force"] = p_f;
	return d;
}

static Dictionary in_a(int p_f) {
	return p_f % 5 != 0 ? force_input(Vector3(30.0, 0.0, Math::sin(double(p_f) * 0.3) * 10.0)) : Dictionary();
}

static Dictionary in_b(int p_f) {
	return p_f % 7 < 4 ? force_input(Vector3(-30.0, 0.0, 0.0)) : force_input(Vector3(0.0, 0.0, 15.0));
}

TEST_CASE("[CgamePhysicsRollback] A late input rolls back to the lockstep reference bytes (native step)") {
	const int frames = 40;
	Ref<CgamePhysicsRollback> ref = make_rollback_world();
	Dictionary ref_state = ref->initial_state();
	for (int f = 0; f < frames; f++) {
		Dictionary inputs;
		inputs[10] = in_a(f);
		inputs[20] = in_b(f);
		ref_state = ref->step_state(ref_state, inputs, DT);
	}
	Ref<CgamePhysicsRollback> pr = make_rollback_world();
	Ref<CgameRollbackNetcode> net;
	net.instantiate();
	pr->setup_net(net, ids2(10, 20), ids1(10), DT, 0, 8);
	CHECK(net->has_native_step());
	for (int f = 0; f < frames; f++) {
		net->add_local_input(10, in_a(f));
		net->advance();
		if (f - 3 >= 0) {
			net->add_remote_input(20, f - 3, in_b(f - 3));
		}
	}
	for (int f = frames - 3; f < frames; f++) {
		net->add_remote_input(20, f, in_b(f));
	}
	net->process();
	CHECK(net->get_frame() == frames);
	CHECK(net->get_rollbacks() > 0);
	CHECK(pr->state_checksum(net->get_state()) == ref->state_checksum(ref_state));
	CHECK(bytes_equal(net->get_state()["phys"], ref_state["phys"]));
}

TEST_CASE("[CgamePhysicsRollback] Rewind query hits the past position and misses the present one") {
	Ref<CgamePhysicsRollback> lc;
	lc.instantiate();
	Ref<CgameDeterministicPhysics> w = lc->get_world();
	w->set_gravity(Vector3());
	w->add_body(1, CgameDeterministicPhysics::SHAPE_SPHERE, 1.0, Vector3(0, 0, 0), Vector3(0.5, 0, 0));
	w->set_velocity(1, Vector3(10, 0, 0));
	Dictionary st = lc->initial_state();
	for (int i = 0; i < 60; i++) {
		st = lc->step_state(st, Dictionary(), DT);
	}
	double now_x = w->get_position(1).x;
	CHECK(now_x == doctest::Approx(10.0).epsilon(0.02));
	Vector3 down(0, 0, -1);
	Dictionary past = lc->rewind_query(0.0, Vector3(0, 0, 5), down);
	CHECK((bool(past["hit"]) && int(past["id"]) == 1));
	Dictionary present = lc->rewind_query(lc->newest_time(), Vector3(0, 0, 5), down);
	CHECK(!bool(present["hit"]));
	Dictionary present_hit = lc->rewind_query(lc->newest_time(), Vector3(now_x, 0, 5), down);
	CHECK(bool(present_hit["hit"]));
	Dictionary past_miss = lc->rewind_query(0.0, Vector3(now_x, 0, 5), down);
	CHECK(!bool(past_miss["hit"]));
	Dictionary mid = lc->rewind_query(0.5 + DT * 0.5, Vector3(5.0 + 10.0 * DT * 0.5, 0, 5), down);
	CHECK_MESSAGE(bool(mid["hit"]), "sub-frame time interpolates between snapshots");
	CHECK(double(past["t"]) == doctest::Approx(4.5).epsilon(0.01));
}

// --- physics timeline -------------------------------------------------------------------------

TEST_CASE("[CgamePhysicsTimeline] Records phases, reports and exports a Chrome trace") {
	Ref<CgamePhysicsTimeline> tl;
	tl.instantiate();
	Ref<CgameDeterministicPhysics> wt;
	wt.instantiate();
	add_pile(wt);
	wt->set_timeline(tl);
	for (int i = 0; i < 30; i++) {
		wt->step(DT);
	}
	CHECK(tl->record_count() == 30);
	Array records = tl->records();
	Dictionary rec = records[29];
	PackedStringArray phases = CgamePhysicsTimeline::get_phases();
	for (const String &phase : phases) {
		bool seen = false;
		Array evs = rec["phases"];
		for (int i = 0; i < evs.size(); i++) {
			Dictionary ev = evs[i];
			if (String(ev["name"]) == phase) {
				seen = true;
			}
		}
		CHECK_MESSAGE(seen, "every phase is recorded");
	}
	CHECK(int64_t(rec["bodies"]) == 9);
	Dictionary rep = tl->report();
	CHECK(int64_t(rep["steps"]) == 30);
	CHECK(Dictionary(rep["phases"]).has("narrowphase"));
	CHECK(int64_t(rep["max_contacts"]) > 0);
	CHECK(tl->report_text().begins_with("physics:"));
	Variant parsed = JSON::parse_string(tl->export_json());
	REQUIRE(parsed.get_type() == Variant::DICTIONARY);
	Dictionary pd = parsed;
	CHECK(pd.has("traceEvents"));
	Array evs = pd["traceEvents"];
	bool has_x = false;
	for (int i = 0; i < evs.size(); i++) {
		Dictionary e = evs[i];
		if (String(e["ph"]) == "X" && String(e["name"]) == "solve") {
			has_x = true;
		}
	}
	CHECK_MESSAGE(has_x, "trace has complete events for phases");
	tl->set_capacity(10);
	wt->step(DT);
	CHECK(tl->record_count() <= 10);
}

} // namespace TestCgameRollback
