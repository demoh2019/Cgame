/**************************************************************************/
/*  test_stream_infra.h                                                   */
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

#include "../origin_rebasing.h"
#include "../stream_readiness_gate.h"
#include "../stream_replication.h"
#include "../stream_request_queue.h"

#include "core/math/math_funcs.h"
#include "core/object/callable_mp.h"
#include "scene/3d/node_3d.h"
#include "tests/test_macros.h"

namespace TestStreamInfra {

static int shift_hits = 0;
static void on_shift(const Vector3 &p_shift) {
	shift_hits++;
}

static Vector<Vector2i> baked_cells;
static bool bake_ok(const Vector2i &p_cell) {
	baked_cells.push_back(p_cell);
	return true;
}

static bool bake_fail(const Vector2i &p_cell) {
	return false;
}

static bool probe_true(const Vector2i &p_cell) {
	return true;
}

static bool gpu_flag = false;
static bool probe_gpu(const Vector2i &p_cell) {
	return gpu_flag;
}

TEST_CASE("[OriginRebasing] Shifts are grid multiples and exact") {
	Ref<OriginRebasing> o;
	o.instantiate();
	o->set_threshold(1000.0);
	o->set_grid_step(256.0);
	o->set_horizontal_only(true);
	CHECK(o->check(Vector3(500, 40, 300)) == Vector3());
	Vector3 s = o->check(Vector3(1500, 90, -1300));
	CHECK(s != Vector3());
	CHECK(Math::fposmod((double)s.x, 256.0) == doctest::Approx(0.0));
	CHECK(Math::fposmod((double)s.z, 256.0) == doctest::Approx(0.0));
	CHECK(s.y == 0.0f);

	Node3D *root = memnew(Node3D);
	Node3D *a = memnew(Node3D);
	a->set_position(Vector3(1500, 5, -1300));
	Node3D *keep = memnew(Node3D);
	keep->set_position(Vector3(1, 2, 3));
	keep->add_to_group(OriginRebasing::get_exclude_group());
	Node *not_3d = memnew(Node);
	root->add_child(a);
	root->add_child(keep);
	root->add_child(not_3d);
	shift_hits = 0;
	Callable cb = callable_mp_static(&on_shift);
	o->add_listener(cb);
	CHECK(o->apply(root, s) == 1);
	CHECK(shift_hits == 1);
	CHECK(keep->get_position() == Vector3(1, 2, 3));
	CHECK(a->get_position().length() < 300.0f);
	CHECK(o->to_global_world(a->get_position()) == Vector3(1500, 5, -1300));
	CHECK(o->to_local_world(Vector3(1500, 5, -1300)) == a->get_position());
	CHECK(o->apply(root, Vector3()) == 0);
	o->remove_listener(cb);
	memdelete(root);
}

TEST_CASE("[OriginRebasing] No drift after thousands of rebases") {
	Ref<OriginRebasing> o2;
	o2.instantiate();
	o2->set_threshold(1500.0);
	o2->set_grid_step(512.0);
	Vector3 cam(0.5, 1.0, 0.25);
	for (int i = 0; i < 5000; i++) {
		cam.x += 1000.0f;
		Vector3 sh = o2->check(cam);
		if (sh != Vector3()) {
			cam += sh;
			o2->commit(sh);
		}
	}
	Dictionary g = o2->to_global_split(cam);
	Vector3i gc = g["cell"];
	Vector3 gr = g["rem"];
	CHECK((double)gc.x * 512.0 + gr.x == doctest::Approx(5000000.5).epsilon(0.0001));
	CHECK((double)gc.z * 512.0 + gr.z == doctest::Approx(0.25).epsilon(0.001));
	CHECK(Math::abs(cam.x) < 2600.0f);
	CHECK(o2->get_shift_count() > 1000);
	CHECK(o2->from_global_split(gc, gr) == cam);
	CHECK(o2->noise_offset(128.0).x == doctest::Approx(0.0));
}

TEST_CASE("[StreamRequestQueue] Priority then FIFO order") {
	Ref<StreamRequestQueue> q;
	q.instantiate();
	q->request(Vector2i(0, 0), 1.0, 1);
	q->request(Vector2i(1, 0), 5.0, 1);
	q->request(Vector2i(2, 0), 3.0, 1);
	q->request(Vector2i(3, 0), 5.0, 1);
	TypedArray<Vector2i> b = q->next_batch(3);
	CHECK(b.size() == 3);
	CHECK(Vector2i(b[0]) == Vector2i(1, 0));
	CHECK(Vector2i(b[1]) == Vector2i(3, 0));
	CHECK(Vector2i(b[2]) == Vector2i(2, 0));
	TypedArray<Vector2i> rest = q->next_batch(5);
	CHECK(rest.size() == 1);
	CHECK(Vector2i(rest[0]) == Vector2i(0, 0));
	CHECK(q->next_batch(5).size() == 0);
}

TEST_CASE("[StreamRequestQueue] Invalid priorities cannot supersede valid generations") {
	Ref<StreamRequestQueue> queue;
	queue.instantiate();
	CHECK_FALSE(queue->request(Vector2i(1, 0), Math::NaN, 99));
	CHECK_FALSE(queue->request(Vector2i(2, 0), Math::INF, 99));
	CHECK(queue->get_newest_generation() == 0);
	CHECK(int(queue->stats()["rejected_invalid"]) == 2);
	CHECK(queue->request(Vector2i(3, 0), 1.0, 1));
	TypedArray<Vector2i> batch = queue->next_batch(1);
	REQUIRE(batch.size() == 1);
	CHECK(Vector2i(batch[0]) == Vector2i(3, 0));
	queue->clear();
	CHECK(int(queue->stats()["rejected_invalid"]) == 0);
}

TEST_CASE("[StreamRequestQueue] Bounded selection matches full ranking") {
	for (int budget : { 1, 5, 128, 129, 350 }) {
		Ref<StreamRequestQueue> q;
		q.instantiate();
		for (int i = 0; i < 300; i++) {
			q->request(Vector2i(i, 0), (double)(i % 7), 1);
		}
		q->request(Vector2i(3, 0), 100.0, 1);
		Vector<Vector2i> expected;
		expected.push_back(Vector2i(3, 0));
		for (int priority = 6; priority >= 0; priority--) {
			for (int i = priority; i < 300; i += 7) {
				if (i != 3) {
					expected.push_back(Vector2i(i, 0));
				}
			}
		}
		TypedArray<Vector2i> batch = q->next_batch(budget);
		REQUIRE(batch.size() == MIN(budget, 300));
		for (int i = 0; i < batch.size(); i++) {
			CHECK(Vector2i(batch[i]) == expected[i]);
		}
		CHECK(q->in_flight_count() == batch.size());
		CHECK(q->queued_count() == 300 - batch.size());
	}
}

TEST_CASE("[StreamRequestQueue] Generations cancel stale requests") {
	Ref<StreamRequestQueue> q2;
	q2.instantiate();
	q2->request(Vector2i(0, 0), 1.0, 1);
	q2->request(Vector2i(1, 0), 1.0, 1);
	q2->request(Vector2i(2, 0), 1.0, 1);
	q2->next_batch(1); // (0,0) in flight
	TypedArray<Vector2i> keep;
	keep.push_back(Vector2i(1, 0));
	CHECK(q2->cancel_stale(2, keep) == 2);
	CHECK_FALSE(q2->has_request(Vector2i(2, 0)));
	CHECK(q2->state_of(Vector2i(0, 0)) == StreamRequestQueue::STATE_CANCELLED);
	CHECK_FALSE(q2->complete(Vector2i(0, 0), "late"));
	CHECK(q2->take_completed().size() == 0);
	CHECK_FALSE(q2->request(Vector2i(9, 9), 1.0, 1));
	TypedArray<Vector2i> again = q2->next_batch(4);
	CHECK(again.size() == 1);
	CHECK(Vector2i(again[0]) == Vector2i(1, 0));
	CHECK(q2->complete(Vector2i(1, 0), "ok"));
	TypedArray<Dictionary> done = q2->take_completed();
	CHECK(done.size() == 1);
	CHECK(String(Dictionary(done[0])["result"]) == "ok");
	Dictionary st = q2->stats();
	CHECK((int)st["dropped_late"] == 1);
	CHECK((int)st["cancelled_queued"] == 1);
	CHECK((int)st["cancelled_inflight"] == 1);
	CHECK((int)st["completed"] == 1);
}

TEST_CASE("[StreamRequestQueue] In-flight cap and revive") {
	Ref<StreamRequestQueue> q3;
	q3.instantiate();
	q3->set_max_in_flight(2);
	for (int i = 0; i < 5; i++) {
		q3->request(Vector2i(i, 0), (double)i, 1);
	}
	CHECK(q3->next_batch(10).size() == 2);
	CHECK(q3->next_batch(10).size() == 0);
	q3->request(Vector2i(4, 0), 0.0, 2);
	CHECK(q3->complete(Vector2i(4, 0), 1));
	q3->request(Vector2i(0, 0), 1.0, 3);
	CHECK_FALSE(q3->complete(Vector2i(4, 0), 1));
}

TEST_CASE("[StreamReadinessGate] Prerequisites and reveal") {
	Ref<StreamReadinessGate> r;
	r.instantiate();
	Vector2i c(4, 4);
	r->begin(c, 0.0);
	r->mark(c, StreamReadinessGate::STAGE_NAVMESH_READY);
	CHECK_FALSE(r->is_revealable(c));
	CHECK(r->waiting_stage(c) == StreamReadinessGate::STAGE_DATA_LOADED);
	CHECK(r->ready_mask(c) == 0);
	r->mark(c, StreamReadinessGate::STAGE_DATA_LOADED);
	CHECK(r->waiting_stage(c) == StreamReadinessGate::STAGE_GPU_UPLOADED);
	CHECK_FALSE(r->is_stage_ready(c, StreamReadinessGate::STAGE_NAVMESH_READY));
	r->mark(c, StreamReadinessGate::STAGE_GPU_UPLOADED);
	r->mark(c, StreamReadinessGate::STAGE_PHYSICS_READY);
	CHECK(r->is_revealable(c));
	TypedArray<Vector2i> revealed = r->update(1.0);
	CHECK(revealed.size() == 1);
	CHECK(Vector2i(revealed[0]) == c);
	CHECK(r->update(2.0).size() == 0);
	CHECK(r->is_revealed(c));
}

TEST_CASE("[StreamReadinessGate] Probes and stuck detection") {
	Ref<StreamReadinessGate> r2;
	r2.instantiate();
	r2->set_default_timeout(5.0);
	Dictionary timeouts;
	timeouts[(int)StreamReadinessGate::STAGE_GPU_UPLOADED] = 2.0;
	r2->set_stage_timeouts(timeouts);
	gpu_flag = false;
	r2->set_probe(StreamReadinessGate::STAGE_DATA_LOADED, callable_mp_static(&probe_true));
	r2->set_probe(StreamReadinessGate::STAGE_GPU_UPLOADED, callable_mp_static(&probe_gpu));
	r2->set_probe(StreamReadinessGate::STAGE_PHYSICS_READY, callable_mp_static(&probe_true));
	r2->set_probe(StreamReadinessGate::STAGE_NAVMESH_READY, callable_mp_static(&probe_true));
	Vector2i d(1, 1);
	r2->begin(d, 0.0);
	CHECK(r2->update(0.5).size() == 0);
	CHECK(r2->get_stuck_log().size() == 0);
	r2->update(2.6);
	CHECK(r2->get_stuck_log().size() == 1);
	Dictionary rep = r2->get_stuck_log()[0];
	CHECK(String(rep["stage_name"]) == "gpu_uploaded");
	CHECK(Vector2i(rep["cell"]) == d);
	r2->update(9.0);
	CHECK(r2->get_stuck_log().size() == 1);
	gpu_flag = true;
	TypedArray<Vector2i> done = r2->update(10.0);
	CHECK(done.size() == 1);
	CHECK(Vector2i(done[0]) == d);
	CHECK_FALSE(StreamReadinessGate::probe_rids_valid(Array()));
	Array bad;
	bad.push_back(RID());
	CHECK_FALSE(StreamReadinessGate::probe_rids_valid(bad));
}

TEST_CASE("[StreamReadinessGate] Navmesh warmup budget and failure") {
	Ref<StreamReadinessGate> r3;
	r3.instantiate();
	baked_cells.clear();
	Callable bake = callable_mp_static(&bake_ok);
	for (int i = 0; i < 5; i++) {
		Vector2i cell(i, 0);
		r3->begin(cell, 0.0);
		r3->warmup_navmesh(cell, bake);
	}
	CHECK(r3->process_warmup(10) == 0);
	for (int i = 0; i < 5; i++) {
		r3->mark(Vector2i(i, 0), StreamReadinessGate::STAGE_DATA_LOADED);
		r3->mark(Vector2i(i, 0), StreamReadinessGate::STAGE_PHYSICS_READY);
	}
	CHECK(r3->process_warmup(2) == 2);
	CHECK(baked_cells.size() == 2);
	CHECK(r3->pending_warmups() == 3);
	r3->process_warmup(10);
	CHECK(r3->pending_warmups() == 0);
	CHECK(r3->is_stage_ready(Vector2i(4, 0), StreamReadinessGate::STAGE_NAVMESH_READY));

	Ref<StreamReadinessGate> r4;
	r4.instantiate();
	baked_cells.clear();
	r4->set_auto_warmup(bake);
	Vector2i e(7, 7);
	r4->mark(e, StreamReadinessGate::STAGE_DATA_LOADED);
	CHECK(r4->pending_warmups() == 0);
	r4->mark(e, StreamReadinessGate::STAGE_PHYSICS_READY);
	CHECK(r4->pending_warmups() == 1);
	r4->process_warmup(4);
	CHECK(baked_cells.size() == 1);
	CHECK(r4->is_stage_ready(e, StreamReadinessGate::STAGE_NAVMESH_READY));

	Ref<StreamReadinessGate> r5;
	r5.instantiate();
	r5->set_max_warmup_attempts(2);
	Vector2i f(2, 2);
	r5->mark(f, StreamReadinessGate::STAGE_DATA_LOADED);
	r5->mark(f, StreamReadinessGate::STAGE_PHYSICS_READY);
	r5->warmup_navmesh(f, callable_mp_static(&bake_fail));
	r5->process_warmup(1);
	r5->process_warmup(1);
	CHECK(r5->get_warmup_failed().size() == 1);
	CHECK(Vector2i(r5->get_warmup_failed()[0]) == f);
	CHECK(r5->pending_warmups() == 0);
}

static int count_bits(const PackedByteArray &p_bits) {
	int ones = 0;
	for (int i = 0; i < p_bits.size(); i++) {
		for (int k = 0; k < 8; k++) {
			ones += (p_bits[i] >> k) & 1;
		}
	}
	return ones;
}

TEST_CASE("[StreamReplication] Full report, delta, interest and loss") {
	Ref<StreamReplication> srv;
	srv.instantiate();
	srv->set_allowed_radius(4);
	srv->set_max_center_error(1);
	Ref<StreamReplicationClient> cl;
	cl.instantiate();
	cl->set_radius(5);
	srv->set_client_position("p1", Vector2i(10, 10));
	cl->set_ready(Vector2i(10, 10), true);
	cl->set_ready(Vector2i(11, 9), true);
	cl->set_ready(Vector2i(8, 12), true);
	Dictionary p1 = cl->build_report(Vector2i(10, 10));
	CHECK((int)p1["base"] == 0);
	PackedByteArray bits1 = p1["bits"];
	CHECK(bits1.size() == StreamReplication::bytes_for(5));
	PackedByteArray wire = StreamReplication::serialize(p1);
	Dictionary back = StreamReplication::deserialize(wire);
	CHECK(Vector2i(back["center"]) == Vector2i(10, 10));
	CHECK(PackedByteArray(back["bits"]) == bits1);
	CHECK(StreamReplication::deserialize(wire.slice(0, 5)).size() == 0);
	Dictionary r1 = srv->apply_report("p1", back);
	CHECK((bool)r1["ok"]);
	CHECK((int)r1["ack"] == 1);
	CHECK(srv->is_ready("p1", Vector2i(11, 9)));
	CHECK_FALSE(srv->is_ready("p1", Vector2i(9, 9)));
	cl->on_ack(1);

	// delta: add one, drop one, move the window by one cell
	cl->set_ready(Vector2i(12, 10), true);
	cl->set_ready(Vector2i(8, 12), false);
	srv->set_client_position("p1", Vector2i(11, 10));
	Dictionary p2 = cl->build_report(Vector2i(11, 10));
	CHECK((int)p2["base"] == 1);
	CHECK(count_bits(p2["bits"]) == 2);
	Dictionary r2 = srv->apply_report("p1", p2);
	CHECK((bool)r2["ok"]);
	CHECK(srv->ready_set("p1").size() == 3);
	CHECK(srv->is_ready("p1", Vector2i(12, 10)));
	CHECK_FALSE(srv->is_ready("p1", Vector2i(8, 12)));

	TypedArray<Vector2i> interest;
	interest.push_back(Vector2i(12, 10));
	interest.push_back(Vector2i(0, 0));
	interest.push_back(Vector2i(10, 10));
	TypedArray<Vector2i> rel = srv->server_relevant("p1", interest);
	CHECK(rel.size() == 2);
	CHECK(Vector2i(rel[0]) == Vector2i(12, 10));
	CHECK(Vector2i(rel[1]) == Vector2i(10, 10));
	TypedArray<Vector2i> miss = srv->server_missing("p1", interest);
	CHECK(miss.size() == 1);
	CHECK(Vector2i(miss[0]) == Vector2i(0, 0));

	// p2's ack is lost: the next report is still relative to acked v1.
	cl->set_ready(Vector2i(13, 10), true);
	Dictionary p3 = cl->build_report(Vector2i(11, 10));
	CHECK((int)p3["base"] == 1);
	Dictionary r3 = srv->apply_report("p1", p3);
	CHECK((bool)r3["ok"]);
	CHECK(srv->is_ready("p1", Vector2i(13, 10)));
	CHECK(srv->is_ready("p1", Vector2i(12, 10)));

	Dictionary dup = srv->apply_report("p1", p2);
	CHECK_FALSE((bool)dup["ok"]);
	CHECK(String(dup["reason"]) == "old");
	CHECK((int)dup["ack"] == 3);
	cl->on_ack(3);
	CHECK(cl->get_acked_version() == 3);

	// server lost history -> need_full -> full resync
	srv->set_history_size(1);
	cl->set_ready(Vector2i(9, 10), true);
	Dictionary p4 = cl->build_report(Vector2i(11, 10));
	srv->apply_report("p1", p4);
	Dictionary p5 = cl->build_report(Vector2i(11, 10));
	Dictionary r5 = srv->apply_report("p1", p5);
	CHECK((bool)r5["need_full"]);
	cl->request_full();
	Dictionary p6 = cl->build_report(Vector2i(11, 10));
	CHECK((int)p6["base"] == 0);
	Dictionary r6 = srv->apply_report("p1", p6);
	CHECK((bool)r6["ok"]);
	CHECK(srv->ready_set("p1").size() == 5);
}

TEST_CASE("[StreamReplication] Anti-cheat") {
	Ref<StreamReplication> srv2;
	srv2.instantiate();
	srv2->set_allowed_radius(2);
	srv2->set_max_center_error(1);
	srv2->set_max_report_radius(6);
	srv2->set_violation_limit(2);
	srv2->set_client_position("evil", Vector2i(0, 0));
	Ref<StreamReplicationClient> bad;
	bad.instantiate();
	bad->set_radius(6);
	bad->set_ready(Vector2i(1, 1), true);
	bad->set_ready(Vector2i(6, 6), true);
	Dictionary rb = srv2->apply_report("evil", bad->build_report(Vector2i(0, 0)));
	CHECK((int)rb["stripped"] == 1);
	CHECK(srv2->is_ready("evil", Vector2i(1, 1)));
	CHECK_FALSE(srv2->is_ready("evil", Vector2i(6, 6)));
	CHECK(srv2->violations("evil") == 1);

	Ref<StreamReplicationClient> far_client;
	far_client.instantiate();
	far_client->set_radius(3);
	far_client->build_report(Vector2i(0, 0));
	Dictionary rf = srv2->apply_report("evil", far_client->build_report(Vector2i(50, 50)));
	CHECK_FALSE((bool)rf["ok"]);
	CHECK(String(rf["reason"]) == "center");
	CHECK(srv2->is_flagged("evil"));

	Ref<StreamReplicationClient> huge;
	huge.instantiate();
	huge->set_radius(9);
	CHECK_FALSE((bool)srv2->apply_report("evil", huge->build_report(Vector2i(0, 0)))["ok"]);

	Ref<StreamReplication> nopos;
	nopos.instantiate();
	CHECK(String(nopos->apply_report("ghost", far_client->build_report(Vector2i(0, 0)))["reason"]) == "no_position");
}

} //namespace TestStreamInfra
