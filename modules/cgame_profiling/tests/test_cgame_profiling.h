/**************************************************************************/
/*  test_cgame_profiling.h                                                */
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

#include "../cgame_cpu_budget.h"
#include "../cgame_hitch_correlator.h"
#include "../cgame_perf_capture.h"
#include "../cgame_profiled_mutex.h"
#include "../cgame_shader_stall_analyzer.h"
#include "../cgame_task_graph.h"
#include "../cgame_trace.h"

#include "core/io/json.h"
#include "core/object/callable_mp.h"
#include "core/os/os.h"
#include "core/os/thread.h"
#include "tests/test_macros.h"
#include "tests/test_utils.h"

namespace TestCgameProfiling {

// Small helpers ------------------------------------------------------------------------------

static bool delay_task(int p_ms) {
	OS::get_singleton()->delay_usec(p_ms * 1000);
	return true;
}

static int sum_range(int p_from, int p_to) {
	int s = 0;
	for (int i = p_from; i < p_to; i++) {
		s += i;
	}
	return s;
}

static CgameTaskGraph *aggregate_graph = nullptr;
static PackedStringArray aggregate_names;

static int aggregate_total() {
	int s = 0;
	for (const String &n : aggregate_names) {
		s += (int)aggregate_graph->result_of(n);
	}
	return s;
}

static bool fail_task() {
	return false;
}

static void emit_many_counters(void *) {
	for (int i = 0; i < 100; i++) {
		CgameTrace::get_singleton()->counter("burst", i);
	}
}

static CgameProfiledMutex *shared_mutex = nullptr;

static void locked_work(void *) {
	shared_mutex->lock();
	OS::get_singleton()->delay_usec(1000);
	shared_mutex->unlock();
}

// Returns the "traceEvents" array of the current export, or an empty array when the JSON is invalid.
static Array export_events(CgameTrace *p_trace) {
	Variant parsed = JSON::parse_string(p_trace->export_chrome_json());
	if (parsed.get_type() != Variant::DICTIONARY) {
		return Array();
	}
	return Dictionary(parsed).get("traceEvents", Array());
}

static Dictionary find_event(const Array &p_events, const String &p_phase, const String &p_name) {
	for (int i = 0; i < p_events.size(); i++) {
		const Dictionary e = p_events[i];
		if (String(e.get("ph", "")) == p_phase && String(e.get("name", "")) == p_name) {
			return e;
		}
	}
	return Dictionary();
}

static Dictionary make_frame(double p_ms, const Dictionary &p_scopes, const Dictionary &p_counters = Dictionary()) {
	Dictionary f;
	f["ms"] = p_ms;
	f["scopes"] = p_scopes;
	f["counters"] = p_counters;
	return f;
}

// CgameTrace ---------------------------------------------------------------------------------

TEST_CASE("[CgameTrace] Disabled records no events") {
	CgameTrace *trace = memnew(CgameTrace);
	trace->set_enabled(false);
	trace->clear();
	trace->begin("a");
	trace->end();
	trace->counter("c", 1.0);
	trace->instant("i");
	trace->flow_start(1, "f");
	trace->frame_marker(0);
	{
		CGAME_TRACE_SCOPE("native");
		CGAME_TRACE_COUNTER("native_counter", 3);
	}
	CHECK(trace->event_count() == 0);
	CHECK(Dictionary(trace->frame_stats())["frames"] == Variant(0));
	memdelete(trace);
}

TEST_CASE("[CgameTrace] Nested scopes enclose each other and export valid JSON") {
	CgameTrace *trace = memnew(CgameTrace);
	trace->clear();
	trace->set_enabled(true);
	trace->begin("outer");
	OS::get_singleton()->delay_usec(1000);
	trace->begin("inner", "physics");
	OS::get_singleton()->delay_usec(1000);
	trace->end();
	OS::get_singleton()->delay_usec(1000);
	trace->end();
	trace->end(); // Unbalanced end is ignored.
	trace->set_enabled(false);

	CHECK(trace->event_count() == 2);
	const Array events = export_events(trace);
	CHECK(events.size() >= 3); // process metadata + thread metadata + scopes.
	const Dictionary outer = find_event(events, "X", "outer");
	const Dictionary inner = find_event(events, "X", "inner");
	REQUIRE(!outer.is_empty());
	REQUIRE(!inner.is_empty());
	CHECK(String(inner["cat"]) == "physics");
	CHECK((int64_t)inner["ts"] >= (int64_t)outer["ts"]);
	CHECK((int64_t)inner["ts"] + (int64_t)inner["dur"] <= (int64_t)outer["ts"] + (int64_t)outer["dur"]);
	CHECK((int64_t)outer["dur"] >= 3000);
	CHECK((int64_t)inner["dur"] >= 1000);
	// Parents are emitted before the children they enclose.
	int outer_pos = -1;
	int inner_pos = -1;
	for (int i = 0; i < events.size(); i++) {
		const Dictionary e = events[i];
		if (String(e.get("name", "")) == "outer") {
			outer_pos = i;
		} else if (String(e.get("name", "")) == "inner") {
			inner_pos = i;
		}
	}
	CHECK(outer_pos < inner_pos);
	trace->clear();
	memdelete(trace);
}

TEST_CASE("[CgameTrace] Counters, instants and flows use the Chrome phases") {
	CgameTrace *trace = memnew(CgameTrace);
	trace->clear();
	trace->set_enabled(true);
	trace->counter("entities", 42.0);
	Dictionary args;
	args["who"] = "player \"one\"";
	trace->instant("spawn", args);
	trace->flow_start(7, "handoff");
	trace->flow_end(7, "handoff");
	trace->set_thread_name("test-main");
	trace->set_enabled(false);

	const Array events = export_events(trace);
	const Dictionary c = find_event(events, "C", "entities");
	REQUIRE(!c.is_empty());
	CHECK((double)Dictionary(c["args"])["entities"] == 42.0);
	const Dictionary i = find_event(events, "i", "spawn");
	REQUIRE(!i.is_empty());
	CHECK(String(Dictionary(i["args"])["who"]) == "player \"one\"");
	CHECK(!find_event(events, "s", "handoff").is_empty());
	const Dictionary f = find_event(events, "f", "handoff");
	REQUIRE(!f.is_empty());
	CHECK(String(f["bp"]) == "e");
	CHECK((int64_t)f["id"] == 7);
	const Dictionary meta = find_event(events, "M", "thread_name");
	REQUIRE(!meta.is_empty());
	CHECK(String(Dictionary(meta["args"])["name"]) == "test-main");
	trace->clear();
	memdelete(trace);
}

TEST_CASE("[CgameTrace] C++ scope macro records a complete event") {
	CgameTrace *trace = memnew(CgameTrace);
	trace->clear();
	trace->set_enabled(true);
	{
		CGAME_TRACE_SCOPE("native_scope");
		CGAME_TRACE_COUNTER("native_counter", 5);
		CGAME_TRACE_INSTANT("native_instant");
	}
	trace->set_enabled(false);
	CHECK(trace->event_count() == 3);
	const Array events = export_events(trace);
	CHECK(!find_event(events, "X", "native_scope").is_empty());
	CHECK(!find_event(events, "C", "native_counter").is_empty());
	CHECK(!find_event(events, "i", "native_instant").is_empty());
	trace->clear();
	memdelete(trace);
}

TEST_CASE("[CgameTrace] Frame markers aggregate scopes and counters per frame") {
	CgameTrace *trace = memnew(CgameTrace);
	trace->clear();
	trace->set_enabled(true);
	trace->frame_marker(0); // Establishes the baseline.
	for (int f = 1; f <= 3; f++) {
		trace->begin("physics");
		OS::get_singleton()->delay_usec(500 * f);
		trace->end();
		trace->counter("bodies", 10.0 * f);
		trace->frame_marker(f);
	}
	trace->set_enabled(false);

	const TypedArray<Dictionary> frames = trace->frames();
	REQUIRE(frames.size() == 3);
	const Dictionary last = frames[2];
	CHECK((int64_t)last["index"] == 3);
	CHECK((double)Dictionary(last["counters"])["bodies"] == 30.0);
	CHECK((double)Dictionary(last["scopes"])["physics"] >= 1500.0);

	const Dictionary stats = trace->frame_stats();
	CHECK((int64_t)stats["frames"] == 3);
	const Dictionary physics = Dictionary(stats["scopes"])["physics"];
	CHECK((double)physics["max"] >= 1500.0);
	CHECK((double)physics["total"] >= (double)physics["max"]);
	CHECK((double)physics["avg"] == doctest::Approx((double)physics["total"] / 3.0));
	CHECK(!find_event(export_events(trace), "i", "frame").is_empty());
	trace->clear();
	memdelete(trace);
}

TEST_CASE("[CgameTrace] Engine frame hook respects auto_frame_markers") {
	CgameTrace *trace = memnew(CgameTrace);
	trace->clear();
	trace->set_enabled(true);
	trace->on_engine_frame(1);
	trace->on_engine_frame(2);
	CHECK(trace->frames().size() == 1);
	trace->set_auto_frame_markers(false);
	trace->on_engine_frame(3);
	CHECK(trace->frames().size() == 1);
	trace->set_enabled(false);
	trace->clear();
	memdelete(trace);
}

TEST_CASE("[CgameTrace] Ring buffer keeps only the newest events of a thread") {
	CgameTrace *trace = memnew(CgameTrace);
	trace->clear();
	trace->set_max_events(16);
	trace->set_enabled(true);
	Thread thread;
	thread.start(emit_many_counters, nullptr);
	thread.wait_to_finish();
	trace->set_enabled(false);
	CHECK(trace->event_count() == 16);
	const Array events = export_events(trace);
	double max_value = -1.0;
	int counters = 0;
	for (int i = 0; i < events.size(); i++) {
		const Dictionary e = events[i];
		if (String(e.get("ph", "")) == "C") {
			counters++;
			max_value = MAX(max_value, (double)Dictionary(e["args"])["burst"]);
		}
	}
	CHECK(counters == 16);
	CHECK(max_value == 99.0);
	trace->set_max_events(16384);
	trace->clear();
	memdelete(trace);
}

TEST_CASE("[CgameTrace] compare reports regressions worst first") {
	Dictionary base_scopes;
	Dictionary cur_scopes;
	auto scope = [](double p_avg) {
		Dictionary d;
		d["avg"] = p_avg;
		return d;
	};
	base_scopes["ai"] = scope(100.0);
	base_scopes["physics"] = scope(100.0);
	base_scopes["zero"] = scope(0.0);
	base_scopes["stable"] = scope(100.0);
	cur_scopes["ai"] = scope(150.0);
	cur_scopes["physics"] = scope(300.0);
	cur_scopes["zero"] = scope(50.0);
	cur_scopes["stable"] = scope(105.0);
	cur_scopes["brand_new"] = scope(999.0);
	Dictionary base;
	base["scopes"] = base_scopes;
	Dictionary cur;
	cur["scopes"] = cur_scopes;

	const Array report = CgameTrace::compare(base, cur, 10.0);
	REQUIRE(report.size() == 2);
	CHECK(String(Dictionary(report[0])["scope"]) == "physics");
	CHECK((double)Dictionary(report[0])["pct"] == doctest::Approx(200.0));
	CHECK(String(Dictionary(report[1])["scope"]) == "ai");
}

// CgameTaskGraph -----------------------------------------------------------------------------

TEST_CASE("[CgameTaskGraph] Deterministic order, waves and timing") {
	Ref<CgameTaskGraph> g;
	g.instantiate();
	(void)g->add_task("a", callable_mp_static(&delay_task).bind(5));
	(void)g->add_task("b", callable_mp_static(&delay_task).bind(5), PackedStringArray({ "a" }));
	(void)g->add_task("c", callable_mp_static(&delay_task).bind(5), PackedStringArray({ "a" }));
	(void)g->add_task("d", callable_mp_static(&delay_task).bind(5), PackedStringArray({ "b", "c" }), false);
	const Dictionary res = g->run();
	CHECK((bool)res["ok"]);
	CHECK(PackedStringArray(res["order"]) == PackedStringArray({ "a", "b", "c", "d" }));
	CHECK((int)res["waves"] == 3);
	const Dictionary ta = g->timing("a");
	const Dictionary tb = g->timing("b");
	const Dictionary tc = g->timing("c");
	const Dictionary td = g->timing("d");
	CHECK((int64_t)ta["end_us"] <= (int64_t)tb["start_us"]);
	CHECK((int64_t)ta["end_us"] <= (int64_t)tc["start_us"]);
	CHECK((int64_t)tb["end_us"] <= (int64_t)td["start_us"]);
	CHECK((int64_t)tc["end_us"] <= (int64_t)td["start_us"]);
	CHECK((uint64_t)(int64_t)td["thread_id"] == Thread::get_caller_id());
	CHECK((double)tb["duration_ms"] >= 4.0);
}

TEST_CASE("[CgameTaskGraph] Parallel chunks aggregate correctly") {
	Ref<CgameTaskGraph> g;
	g.instantiate();
	aggregate_graph = g.ptr();
	aggregate_names.clear();
	for (int i = 0; i < 16; i++) {
		const String n = vformat("chunk%d", i);
		(void)g->add_task(n, callable_mp_static(&sum_range).bind(i * 1000, (i + 1) * 1000));
		aggregate_names.push_back(n);
	}
	(void)g->add_task("total", callable_mp_static(&aggregate_total), aggregate_names);
	const Dictionary res = g->run();
	CHECK((bool)res["ok"]);
	CHECK((int)g->result_of("total") == sum_range(0, 16000));
	CHECK((int)res["waves"] == 2);
	CHECK(Array(g->results().keys())[16] == Variant("total"));
	aggregate_graph = nullptr;
}

TEST_CASE("[CgameTaskGraph] Cycles and unknown dependencies are rejected") {
	ERR_PRINT_OFF;
	Ref<CgameTaskGraph> g;
	g.instantiate();
	(void)g->add_task("x", callable_mp_static(&delay_task).bind(0));
	(void)g->add_task("y", callable_mp_static(&delay_task).bind(0), PackedStringArray({ "x" }));
	CHECK(!g->add_dependency("x", "y"));
	CHECK(g->add_task("self", callable_mp_static(&delay_task).bind(0), PackedStringArray({ "self" })) == "");

	Ref<CgameTaskGraph> fwd;
	fwd.instantiate();
	(void)fwd->add_task("p", callable_mp_static(&delay_task).bind(0), PackedStringArray({ "q" }));
	CHECK(fwd->add_task("q", callable_mp_static(&delay_task).bind(0), PackedStringArray({ "p" })) == "");
	CHECK(fwd->add_task("dup", callable_mp_static(&delay_task).bind(0)) == "dup");
	CHECK(fwd->add_task("dup", callable_mp_static(&delay_task).bind(0)) == "");
	CHECK(!(bool)fwd->run()["ok"]);
	CHECK(fwd->validate().size() == 1);
	ERR_PRINT_ON;
}

TEST_CASE("[CgameTaskGraph] Failure cancels transitive dependants only") {
	Ref<CgameTaskGraph> g;
	g.instantiate();
	(void)g->add_task("ok1", callable_mp_static(&delay_task).bind(0));
	(void)g->add_task("bad", callable_mp_static(&fail_task), PackedStringArray({ "ok1" }));
	(void)g->add_task("after", callable_mp_static(&delay_task).bind(0), PackedStringArray({ "bad" }));
	(void)g->add_task("after2", callable_mp_static(&delay_task).bind(0), PackedStringArray({ "after" }));
	(void)g->add_task("indep", callable_mp_static(&delay_task).bind(0), PackedStringArray({ "ok1" }));
	const Dictionary res = g->run();
	CHECK(!(bool)res["ok"]);
	CHECK(PackedStringArray(res["failed"]) == PackedStringArray({ "bad" }));
	CHECK(PackedStringArray(res["cancelled"]) == PackedStringArray({ "after", "after2" }));
	CHECK(g->state_of("indep") == CgameTaskGraph::DONE);
	CHECK(g->state_of("after") == CgameTaskGraph::CANCELLED);
	CHECK(g->state_of("bad") == CgameTaskGraph::FAILED);
	CHECK(g->error_of("bad") == "task returned false");
}

TEST_CASE("[CgameTaskGraph] Critical path follows the slowest chain and exports DOT") {
	Ref<CgameTaskGraph> g;
	g.instantiate();
	(void)g->add_task("root", callable_mp_static(&delay_task).bind(2));
	(void)g->add_task("fast", callable_mp_static(&delay_task).bind(2), PackedStringArray({ "root" }));
	(void)g->add_task("slow", callable_mp_static(&delay_task).bind(30), PackedStringArray({ "root" }));
	(void)g->add_task("end", callable_mp_static(&delay_task).bind(2), PackedStringArray({ "fast", "slow" }));
	g->run();
	CHECK(g->critical_path() == PackedStringArray({ "root", "slow", "end" }));
	CHECK(g->critical_path_ms() >= 33.0);
	const String dot = g->to_dot();
	CHECK(dot.begins_with("digraph TaskGraph"));
	CHECK(dot.contains("\"root\" -> \"slow\" [color=red]"));
	CHECK(dot.contains("\"root\" -> \"fast\";"));
}

TEST_CASE("[CgameTaskGraph] Tasks appear in the trace with dependency flows") {
	CgameTrace *trace = memnew(CgameTrace);
	trace->clear();
	trace->set_enabled(true);
	Ref<CgameTaskGraph> g;
	g.instantiate();
	(void)g->add_task("first", callable_mp_static(&delay_task).bind(1));
	(void)g->add_task("second", callable_mp_static(&delay_task).bind(1), PackedStringArray({ "first" }));
	g->run();
	trace->set_enabled(false);
	const Array events = export_events(trace);
	CHECK(!find_event(events, "X", "first").is_empty());
	CHECK(!find_event(events, "X", "second").is_empty());
	CHECK(!find_event(events, "s", "dependency").is_empty());
	CHECK(!find_event(events, "f", "dependency").is_empty());
	trace->clear();
	memdelete(trace);
}

// CgameCPUBudget -----------------------------------------------------------------------------

static double sum_allocation(const Dictionary &p_allocation) {
	double total = 0.0;
	for (const Variant &k : p_allocation.get_key_list()) {
		total += (double)p_allocation[k];
	}
	return total;
}

TEST_CASE("[CgameCPUBudget] Allocation honours minima, priority and demand caps") {
	Ref<CgameCPUBudget> b;
	b.instantiate();
	b->register_system("physics", 4.0, 2.0, 8.0);
	b->register_system("ai", 2.0, 1.0, 6.0);
	b->register_system("audio", 1.0, 0.5, 1.0);
	Dictionary a = b->allocate(12.0);
	CHECK(sum_allocation(a) == doctest::Approx(12.0));
	CHECK((double)a["physics"] >= 2.0);
	CHECK((double)a["ai"] >= 1.0);
	CHECK((double)a["audio"] >= 0.5);
	CHECK((double)a["audio"] == doctest::Approx(1.0));
	CHECK((double)a["physics"] > (double)a["ai"]);

	const Dictionary small = b->allocate(3.0);
	CHECK(sum_allocation(small) == doctest::Approx(3.0));
	CHECK((double)small["physics"] / (double)small["ai"] == doctest::Approx(2.0));

	const Dictionary roomy = b->allocate(100.0);
	CHECK((double)roomy["physics"] == doctest::Approx(8.0));
	CHECK(b->allocation_ms("physics") == doctest::Approx(8.0));
}

TEST_CASE("[CgameCPUBudget] Demand adapts to smoothed usage") {
	Ref<CgameCPUBudget> c;
	c.instantiate();
	c->register_system("ai", 1.0, 0.5, 6.0);
	c->register_system("fx", 1.0, 0.5, 6.0);
	for (int i = 0; i < 30; i++) {
		c->report_usage("ai", 1.0);
		c->report_usage("fx", 5.0);
	}
	const Dictionary ca = c->allocate(8.0);
	CHECK((double)ca["ai"] < (double)ca["fx"]);
	CHECK((double)ca["ai"] == doctest::Approx(1.25).epsilon(0.05));
	CHECK((double)ca["fx"] == doctest::Approx(6.0));
	c->report_usage("ai", 4.0);
	CHECK(c->smoothed_usage_ms("ai") > 1.0);
	CHECK(c->smoothed_usage_ms("ai") < 4.0);
	for (int i = 0; i < 30; i++) {
		c->report_usage("fx", 7.5);
	}
	CHECK(c->over_budget().has("fx"));
	c->unregister_system("fx");
	CHECK(c->system_count() == 1);
}

// CgameProfiledMutex -------------------------------------------------------------------------

TEST_CASE("[CgameProfiledMutex] Counts acquisitions, contention and registry order") {
	CgameProfiledMutex::clear_registry();
	Ref<CgameProfiledMutex> m = CgameProfiledMutex::create("contended");
	Ref<CgameProfiledMutex> quiet = CgameProfiledMutex::create("quiet");
	quiet->lock();
	quiet->unlock();
	shared_mutex = m.ptr();
	m->lock();
	Thread thread;
	thread.start(locked_work, nullptr);
	OS::get_singleton()->delay_usec(30000);
	m->unlock();
	thread.wait_to_finish();
	const Dictionary st = m->stats();
	CHECK((int64_t)st["acquisitions"] == 2);
	CHECK((int64_t)st["contended"] == 1);
	CHECK((double)st["total_wait_ms"] >= 15.0);
	CHECK((double)st["total_hold_ms"] >= 25.0);
	CHECK((int64_t)st["owner_thread_id"] != 0);
	const Array rep = CgameProfiledMutex::report();
	REQUIRE(rep.size() == 2);
	CHECK(String(Dictionary(rep[0])["name"]) == "contended");
	CHECK((int64_t)Dictionary(rep[1])["contended"] == 0);
	CHECK(m->try_lock());
	m->unlock();
	shared_mutex = nullptr;
	CgameProfiledMutex::clear_registry();
}

TEST_CASE("[CgameProfiledMutex] Sync points flag only long stalls") {
	CgameProfiledMutex::clear_registry();
	CgameProfiledMutex::set_long_sync_threshold_ms(5.0);
	CgameProfiledMutex::record_sync("slow_readback", 12000);
	CgameProfiledMutex::record_sync("fast", 100);
	CHECK(CgameProfiledMutex::long_syncs() == PackedStringArray({ "slow_readback" }));
	CHECK(String(Dictionary(CgameProfiledMutex::sync_report()[0])["name"]) == "slow_readback");
	CgameProfiledMutex::set_long_sync_threshold_ms(2.0);
	CgameProfiledMutex::clear_registry();
}

// CgameHitchCorrelator -----------------------------------------------------------------------

TEST_CASE("[CgameHitchCorrelator] Names the scope that grew and the counters that jumped") {
	Array frames;
	for (int i = 0; i < 20; i++) {
		Dictionary scopes;
		scopes["physics"] = 1000.0;
		scopes["ai"] = 500.0;
		Dictionary counters;
		counters["entities"] = 100.0;
		frames.push_back(make_frame(16.0, scopes, counters));
	}
	Dictionary hitch_scopes;
	hitch_scopes["physics"] = 1000.0;
	hitch_scopes["ai"] = 20000.0;
	Dictionary hitch_counters;
	hitch_counters["entities"] = 900.0;
	frames.push_back(make_frame(60.0, hitch_scopes, hitch_counters));

	const Array hitches = CgameHitchCorrelator::correlate(frames, 30.0);
	REQUIRE(hitches.size() == 1);
	const Dictionary h = hitches[0];
	CHECK((int)h["index"] == 20);
	CHECK((double)h["baseline_ms"] == doctest::Approx(16.0));
	const Array culprits = h["culprits"];
	REQUIRE(culprits.size() >= 1);
	CHECK(String(Dictionary(culprits[0])["scope"]) == "ai");
	CHECK((double)Dictionary(culprits[0])["growth_usec"] == doctest::Approx(19500.0));
	const Array jumped = h["counters"];
	REQUIRE(jumped.size() == 1);
	CHECK(String(Dictionary(jumped[0])["name"]) == "entities");
	CHECK(CgameHitchCorrelator::correlate(frames, 100.0).is_empty());
}

TEST_CASE("[CgameHitchCorrelator] Live sampling attributes hitches to the counter that moved") {
	Ref<CgameHitchCorrelator> h;
	h.instantiate();
	Dictionary counters;
	counters["compiles"] = 0;
	counters["cells"] = 0;
	counters["vram"] = 0.0;
	for (int i = 0; i < 40; i++) {
		CHECK(h->sample(0.016, counters).is_empty());
	}
	Dictionary compiled = counters.duplicate();
	compiled["compiles"] = 3;
	const Dictionary hit = h->sample(0.2, compiled);
	REQUIRE(!hit.is_empty());
	CHECK(String(hit["cause"]) == "shader_compile");
	CHECK((int64_t)h->get_counts()["shader_compile"] == 1);
	Dictionary streamed = compiled.duplicate();
	streamed["cells"] = 2;
	CHECK(String(h->sample(0.2, streamed)["cause"]) == "streaming");
	CHECK(String(h->sample(0.2, streamed)["cause"]) == "cpu");
	CHECK(h->describe().contains("shaders 1"));
}

// CgamePerfCapture ---------------------------------------------------------------------------

TEST_CASE("[CgamePerfCapture] Capture validates and round-trips in binary and JSON") {
	Dictionary cap = CgamePerfCapture::new_capture("unit");
	CHECK(CgamePerfCapture::validate(cap).is_empty());
	Dictionary scopes;
	scopes["physics"] = 1200.0;
	CgamePerfCapture::add_frame(cap, 1, 16.5, scopes);
	CgamePerfCapture::add_frame(cap, 2, 17.5, scopes);
	Dictionary ev;
	ev["cell"] = 3;
	CgamePerfCapture::add_event(cap, "streaming_events", ev);
	CgamePerfCapture::add_event(cap, "not_a_section", ev);
	CHECK(!cap.has("not_a_section"));
	CHECK(CgamePerfCapture::frame_times(cap).size() == 2);

	for (const String &suffix : { String("cap.cgperf"), String("cap.json") }) {
		const String path = TestUtils::get_temp_path(suffix);
		CHECK(CgamePerfCapture::write(path, cap));
		const Dictionary back = CgamePerfCapture::read(path);
		REQUIRE(!back.is_empty());
		CHECK(String(back["label"]) == "unit");
		CHECK(Array(back["frames"]).size() == 2);
		CHECK(Array(back["streaming_events"]).size() == 1);
		CHECK(CgamePerfCapture::validate(back).is_empty());
	}
	CHECK(CgamePerfCapture::read(TestUtils::get_temp_path("missing.cgperf")).is_empty());

	Dictionary bad = cap.duplicate(true);
	bad["version"] = CgamePerfCapture::VERSION + 1;
	bad["magic"] = "nope";
	CHECK(CgamePerfCapture::validate(bad).size() == 2);
}

TEST_CASE("[CgamePerfCapture] Merge concatenates sections and sorts frames") {
	Dictionary a = CgamePerfCapture::new_capture("a");
	Dictionary b = CgamePerfCapture::new_capture("b");
	CgamePerfCapture::add_frame(a, 5, 10.0);
	CgamePerfCapture::add_frame(b, 2, 11.0);
	CgamePerfCapture::add_frame(b, 9, 12.0);
	const Dictionary merged = CgamePerfCapture::merge(a, b);
	const Array frames = merged["frames"];
	REQUIRE(frames.size() == 3);
	CHECK((int64_t)Dictionary(frames[0])["index"] == 2);
	CHECK((int64_t)Dictionary(frames[2])["index"] == 9);
	CHECK(String(merged["label"]) == "a");
	CHECK(Array(a["frames"]).size() == 1); // Inputs stay untouched.
}

TEST_CASE("[CgamePerfCapture] Run comparison is noise aware and subsystems regress by scope") {
	auto run = [](double p50, double p95) {
		Dictionary d;
		d["frame_time_p50"] = p50;
		d["frame_time_p95"] = p95;
		return d;
	};
	Dictionary baseline = run(10.0, 20.0);
	Dictionary current = run(10.2, 30.0);
	Dictionary thresholds;
	thresholds["default"] = 10.0;
	Dictionary cmp = CgamePerfCapture::compare_runs(baseline, current, thresholds);
	CHECK(!(bool)cmp["ok"]);
	CHECK(PackedStringArray(cmp["regressions"]) == PackedStringArray({ "frame_time_p95" }));
	CHECK(!(bool)Dictionary(Dictionary(cmp["metrics"])["frame_time_p50"])["regressed"]);

	// Spread between repeated baseline runs widens the allowed limit.
	Dictionary noisy_base;
	Array runs;
	runs.push_back(run(10.0, 20.0));
	runs.push_back(run(14.0, 20.0));
	runs.push_back(run(12.0, 20.0));
	noisy_base["runs"] = runs;
	Dictionary slightly_slower = run(13.0, 20.0);
	const Dictionary noisy = CgamePerfCapture::compare_runs(noisy_base, slightly_slower, thresholds);
	CHECK((bool)noisy["ok"]);

	Dictionary base_cap = CgamePerfCapture::new_capture("base");
	Dictionary cur_cap = CgamePerfCapture::new_capture("cur");
	for (int i = 0; i < 4; i++) {
		Dictionary bs;
		bs["ai"] = 100.0;
		bs["physics"] = 200.0;
		Dictionary cs;
		cs["ai"] = 100.0;
		cs["physics"] = 400.0;
		CgamePerfCapture::add_frame(base_cap, i, 16.0, bs);
		CgamePerfCapture::add_frame(cur_cap, i, 16.0, cs);
	}
	const Array sub = CgamePerfCapture::compare_subsystems(base_cap, cur_cap, 10.0);
	REQUIRE(sub.size() == 1);
	CHECK(String(Dictionary(sub[0])["scope"]) == "physics");
	CHECK((double)Dictionary(sub[0])["pct"] == doctest::Approx(100.0));
}

TEST_CASE("[CgamePerfCapture] Memory leak detector uses a linear fit") {
	PackedFloat32Array growing;
	PackedFloat32Array flat;
	for (int i = 0; i < 50; i++) {
		growing.push_back(1000.0f + 20.0f * i);
		flat.push_back(1000.0f + ((i % 2) ? 1.0f : -1.0f));
	}
	const Dictionary leak = CgamePerfCapture::memory_leak_trend(growing);
	CHECK((bool)leak["leak"]);
	CHECK((double)leak["slope"] == doctest::Approx(20.0));
	CHECK((double)leak["r2"] > 0.99);
	CHECK(!(bool)CgamePerfCapture::memory_leak_trend(flat)["leak"]);
	CHECK(!(bool)CgamePerfCapture::memory_leak_trend(PackedFloat32Array())["leak"]);
}

// CgameShaderStallAnalyzer -------------------------------------------------------------------

TEST_CASE("[CgameShaderStallAnalyzer] Attributes spikes to compiling materials") {
	Ref<CgameShaderStallAnalyzer> a;
	a.instantiate();
	for (int i = 0; i < 30; i++) {
		a->feed(i, 16.0, 0);
	}
	a->feed(30, 60.0, 2, PackedStringArray({ "rock", "water" }));
	a->feed(31, 55.0, 0); // Spike without compiles stays unrelated.
	a->feed(32, 40.0, 1, PackedStringArray({ "rock" }));
	const Dictionary r = a->analyze();
	CHECK((double)r["baseline_ms"] == doctest::Approx(16.0));
	const Array stalls = r["stalls"];
	REQUIRE(stalls.size() == 2);
	CHECK((double)Dictionary(stalls[0])["extra_ms"] == doctest::Approx(44.0));
	CHECK(Array(r["unrelated_spikes"]).size() == 1);
	const Array culprits = r["culprits"];
	REQUIRE(culprits.size() == 2);
	CHECK(String(Dictionary(culprits[0])["material"]) == "rock");
	CHECK((int64_t)Dictionary(culprits[0])["stalls"] == 2);
}

TEST_CASE("[CgameShaderStallAnalyzer] Cumulative counters become per-frame deltas") {
	Ref<CgameShaderStallAnalyzer> a;
	a.instantiate();
	a->feed_cumulative(0, 16.0, 10);
	a->feed_cumulative(1, 16.0, 10);
	a->feed_cumulative(2, 80.0, 13, PackedStringArray({ "lava" }));
	const Dictionary r = a->analyze();
	const Array stalls = r["stalls"];
	REQUIRE(stalls.size() == 1);
	CHECK((int64_t)Dictionary(stalls[0])["compiles"] == 3);
	CHECK(CgameShaderStallAnalyzer::live_compile_total() >= 0);
}

TEST_CASE("[CgameShaderStallAnalyzer] Auto sampling consumes noted materials each frame") {
	Ref<CgameShaderStallAnalyzer> a;
	a.instantiate();
	a->start_auto_sampling();
	CHECK(a->is_auto_sampling());
	CgameShaderStallAnalyzer::tick_all(1, 1000000);
	CgameShaderStallAnalyzer::tick_all(2, 1016000);
	a->note_material("grass");
	CgameShaderStallAnalyzer::tick_all(3, 1032000);
	CHECK(a->frame_count() == 2);
	a->stop_auto_sampling();
	CgameShaderStallAnalyzer::tick_all(4, 1048000);
	CHECK(a->frame_count() == 2);
}

} // namespace TestCgameProfiling
