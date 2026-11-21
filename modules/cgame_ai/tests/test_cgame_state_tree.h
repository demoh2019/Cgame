/**************************************************************************/
/*  test_cgame_state_tree.h                                               */
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

#include "test_cgame_ai_helpers.h"

#include "../cgame_state_tree.h"
#include "core/object/callable_mp.h"
#include "tests/test_macros.h"

namespace TestCgameStateTree {

using namespace CgameAITestUtil;

static Vector<String> g_log;

static void work_enter(Dictionary p_ctx, Dictionary p_params) {
	g_log.push_back("enter:" + String(p_params["_state"]));
}

static int work_tick(Dictionary p_ctx, double p_dt, Dictionary p_params) {
	p_ctx["work_done"] = int(p_ctx.get("work_done", 0)) + 1;
	return int(p_ctx["work_done"]) >= int(p_ctx.get("work_ticks", 1)) ? int(CgameStateTree::SUCCEEDED) : int(CgameStateTree::RUNNING);
}

static void work_exit(Dictionary p_ctx, Dictionary p_params) {
	g_log.push_back("exit:" + String(p_params["_state"]));
}

static int fail_tick(Dictionary p_ctx, double p_dt, Dictionary p_params) {
	return int(CgameStateTree::FAILED);
}

static bool has_ammo(Dictionary p_ctx, Dictionary p_args) {
	return int(p_ctx.get("ammo", 0)) > 0;
}

static bool flag_cond(Dictionary p_ctx, Dictionary p_args) {
	return bool(p_ctx.get(String(p_args["name"]), false));
}

static Dictionary clock_eval(Dictionary p_ctx, double p_dt, Dictionary p_args) {
	return dict({ { "time", double(p_ctx.get("time", 0.0)) + p_dt }, { "step", p_args["step"] } });
}

// "work" completes after ctx.work_ticks ticks, "fail_task" fails at once, "idle" never ends.
static Ref<CgameStateTree> make_tree() {
	Ref<CgameStateTree> st;
	st.instantiate();
	g_log.clear();
	st->register_task("work", callable_mp_static(&work_enter), callable_mp_static(&work_tick), callable_mp_static(&work_exit));
	st->register_task("fail_task", Callable(), callable_mp_static(&fail_tick));
	st->register_task("idle", callable_mp_static(&work_enter), Callable(), callable_mp_static(&work_exit));
	st->register_condition("has_ammo", callable_mp_static(&has_ammo));
	st->register_condition("flag", callable_mp_static(&flag_cond));
	return st;
}

static Dictionary state_def(std::initializer_list<std::pair<const char *, Variant>> p_items) {
	return dict(p_items);
}

static Dictionary basic_asset() {
	return dict({
			{ "root", "root" },
			{ "states", dict({
								{ "root", state_def({ { "children", arr({ "combat", "patrol", "rest" }) } }) },
								{ "combat", state_def({ { "conditions", arr({ "has_ammo" }) }, { "tasks", arr({ "idle" }) } }) },
								{ "patrol", state_def({ { "children", arr({ "walk", "look" }) }, { "conditions", arr({ dict({ { "key", "alert" }, { "op", "<" }, { "value", 5 } }) }) } }) },
								{ "walk", state_def({ { "tasks", arr({ "work" }) }, { "transitions", arr({ dict({ { "trigger", "on_completed" }, { "target", "look" } }) }) } }) },
								{ "look", state_def({ { "tasks", arr({ "idle" }) } }) },
								{ "rest", state_def({ { "tasks", arr({ "idle" }) } }) },
						}) },
	});
}

TEST_CASE("[CgameStateTree] selection is depth-first over enter conditions") {
	Ref<CgameStateTree> st = make_tree();
	CHECK(st->set_asset(basic_asset()));
	Dictionary ctx = dict({ { "alert", 0 } });
	CHECK(st->start(ctx));
	CHECK(st->debug_path() == "root/patrol/walk");
	st->stop(ctx);
	ctx = dict({ { "alert", 0 }, { "ammo", 3 } });
	st->start(ctx);
	CHECK(st->debug_path() == "root/combat");
	st->stop(ctx);
	ctx = dict({ { "alert", 9 } });
	st->start(ctx);
	CHECK(st->debug_path() == "root/rest");
	CHECK_FALSE(st->is_active("patrol"));
	CHECK(st->current_state() == "rest");
}

TEST_CASE("[CgameStateTree] transitions: completion, failure priority, events and tick conditions") {
	Ref<CgameStateTree> st = make_tree();
	st->set_asset(basic_asset());
	Dictionary ctx = dict({ { "alert", 0 }, { "work_ticks", 2 } });
	st->start(ctx);
	st->tick(0.1, ctx);
	CHECK(st->debug_path() == "root/patrol/walk");
	st->tick(0.1, ctx);
	CHECK(st->debug_path() == "root/patrol/look");

	// on_failed and priority resolution
	st = make_tree();
	st->set_asset(dict({
			{ "root", "r" },
			{ "states", dict({
								{ "r", state_def({ { "children", arr({ "a", "b", "c" }) } }) },
								{ "a", state_def({ { "tasks", arr({ "fail_task" }) },
												   { "transitions", arr({
																			   dict({ { "trigger", "on_failed" }, { "target", "b" }, { "priority", 1 } }),
																			   dict({ { "trigger", "on_failed" }, { "target", "c" }, { "priority", 5 } }),
																	   }) } }) },
								{ "b", state_def({ { "tasks", arr({ "idle" }) } }) },
								{ "c", state_def({ { "tasks", arr({ "idle" }) } }) },
						}) },
	}));
	ctx = Dictionary();
	st->start(ctx);
	st->tick(0.1, ctx);
	CHECK(st->debug_path() == "r/c");

	// events and conditions
	st = make_tree();
	st->set_asset(dict({
			{ "root", "r" },
			{ "states", dict({
								{ "r", state_def({ { "children", arr({ "a", "b", "c" }) } }) },
								{ "a", state_def({ { "tasks", arr({ "idle" }) },
												   { "transitions", arr({
																			   dict({ { "trigger", "on_event" }, { "event", "alarm" }, { "target", "b" } }),
																			   dict({ { "trigger", "on_tick" }, { "condition", dict({ { "fn", "flag" }, { "args", dict({ { "name", "go_c" } }) } }) }, { "target", "c" } }),
																	   }) } }) },
								{ "b", state_def({ { "tasks", arr({ "idle" }) } }) },
								{ "c", state_def({ { "tasks", arr({ "idle" }) } }) },
						}) },
	}));
	ctx = Dictionary();
	st->start(ctx);
	st->send_event("noise");
	st->tick(0.1, ctx);
	CHECK(st->current_state() == "a");
	st->send_event("alarm", dict({ { "x", 1 } }));
	st->tick(0.1, ctx);
	CHECK(st->current_state() == "b");
	st->stop(ctx);
	st->start(ctx);
	ctx["go_c"] = true;
	st->tick(0.1, ctx);
	CHECK(st->current_state() == "c");

	// unselectable target is skipped, tree finishes when nothing handles completion
	st = make_tree();
	st->set_asset(dict({
			{ "root", "r" },
			{ "states", dict({
								{ "r", state_def({ { "children", arr({ "a", "b" }) } }) },
								{ "a", state_def({ { "tasks", arr({ "work" }) },
												   { "transitions", arr({ dict({ { "trigger", "on_completed" }, { "target", "b" }, { "priority", 9 }, { "condition", "has_ammo" } }) }) } }) },
								{ "b", state_def({ { "tasks", arr({ "idle" }) } }) },
						}) },
	}));
	ctx = dict({ { "work_ticks", 1 } });
	st->start(ctx);
	st->tick(0.1, ctx);
	CHECK(st->get_tree_status() == CgameStateTree::SUCCEEDED);
	CHECK_FALSE(st->is_running());
	CHECK(st->debug_path() == "(inactive)");
}

TEST_CASE("[CgameStateTree] enter and exit order") {
	Ref<CgameStateTree> st = make_tree();
	st->set_asset(dict({
			{ "root", "root" },
			{ "states", dict({
								{ "root", state_def({ { "children", arr({ "p", "q" }) } }) },
								{ "p", state_def({ { "children", arr({ "p1", "p2" }) }, { "tasks", arr({ "idle" }) } }) },
								{ "p1", state_def({ { "tasks", arr({ "work" }) }, { "transitions", arr({ dict({ { "trigger", "on_completed" }, { "target", "p2" } }) }) } }) },
								{ "p2", state_def({ { "tasks", arr({ "work" }) }, { "transitions", arr({ dict({ { "trigger", "on_completed" }, { "target", "q" } }) }) } }) },
								{ "q", state_def({ { "tasks", arr({ "idle" }) } }) },
						}) },
	}));
	Dictionary ctx = dict({ { "work_ticks", 1 } });
	st->start(ctx);
	CHECK(g_log == psa({ "enter:p", "enter:p1" }));
	g_log.clear();
	ctx["work_done"] = 0;
	st->tick(0.1, ctx);
	CHECK(g_log == psa({ "exit:p1", "enter:p2" }));
	g_log.clear();
	ctx["work_done"] = 0;
	st->tick(0.1, ctx);
	CHECK(g_log == psa({ "exit:p2", "exit:p", "enter:q" }));
	g_log.clear();
	st->stop(ctx);
	CHECK(g_log == psa({ "exit:q" }));

	// re-entering the already active state restarts it
	st = make_tree();
	st->set_asset(dict({
			{ "root", "r" },
			{ "states", dict({
								{ "r", state_def({ { "children", arr({ "a" }) } }) },
								{ "a", state_def({ { "tasks", arr({ "idle" }) }, { "transitions", arr({ dict({ { "trigger", "on_event" }, { "event", "again" }, { "target", "a" } }) }) } }) },
						}) },
	}));
	ctx = Dictionary();
	st->start(ctx);
	g_log.clear();
	st->send_event("again");
	st->tick(0.1, ctx);
	CHECK(g_log == psa({ "exit:a", "enter:a" }));
}

TEST_CASE("[CgameStateTree] evaluators and linked subtrees") {
	Ref<CgameStateTree> st = make_tree();
	st->register_evaluator("clock", callable_mp_static(&clock_eval));
	st->register_subtree("hunt", dict({
										 { "root", "h" },
										 { "states", dict({
															 { "h", state_def({ { "children", arr({ "chase", "search" }) } }) },
															 { "chase", state_def({ { "conditions", arr({ dict({ { "key", "seen" }, { "op", "==" }, { "value", true } }) }) }, { "tasks", arr({ "idle" }) } }) },
															 { "search", state_def({ { "tasks", arr({ "idle" }) }, { "transitions", arr({ dict({ { "trigger", "on_event" }, { "event", "done" }, { "target", "$succeeded" } }) }) } }) },
													 }) },
								 }));
	CHECK(st->set_asset(dict({
			{ "root", "r" },
			{ "evaluators", arr({ dict({ { "fn", "clock" }, { "args", dict({ { "step", 7 } }) } }) }) },
			{ "states", dict({
								{ "r", state_def({ { "children", arr({ "wait", "hunting" }) } }) },
								{ "wait", state_def({ { "conditions", arr({ dict({ { "key", "time" }, { "op", "<" }, { "value", 0.25 } }) }) }, { "tasks", arr({ "idle" }) } }) },
								{ "hunting", state_def({ { "link", "hunt" } }) },
						}) },
	})));
	Dictionary ctx = dict({ { "time", 0.0 }, { "seen", false } });
	st->start(ctx);
	CHECK(st->current_state() == "wait");
	st->tick(0.1, ctx);
	CHECK(Math::abs(double(ctx["time"]) - 0.1) < 0.0001);
	CHECK(int(ctx["step"]) == 7);
	st->stop(ctx);
	ctx["time"] = 1.0;
	ctx["seen"] = true;
	st->start(ctx);
	CHECK(st->debug_path() == "r/hunting/hunting/h/hunting/chase");
	CHECK(st->is_active("hunting/chase"));
	st->stop(ctx);
	ctx["seen"] = false;
	st->start(ctx);
	CHECK(st->current_state() == "hunting/search");
	st->send_event("done");
	st->tick(0.1, ctx);
	CHECK(st->get_tree_status() == CgameStateTree::SUCCEEDED);
}

static bool mentions(const PackedStringArray &p_errs, const String &p_text) {
	return !p_errs.is_empty() && p_errs[0].contains(p_text);
}

TEST_CASE("[CgameStateTree] validation rejects malformed assets") {
	Ref<CgameStateTree> st = make_tree();
	CHECK(st->validate(basic_asset()).is_empty());
	CHECK_FALSE(st->validate(Dictionary()).is_empty());
	CHECK_FALSE(st->validate(dict({ { "root", "x" }, { "states", dict({ { "a", Dictionary() } }) } })).is_empty());
	CHECK(mentions(st->validate(dict({ { "root", "a" }, { "states", dict({ { "a", dict({ { "children", arr({ "ghost" }) } }) } }) } })), "ghost"));
	CHECK(mentions(st->validate(dict({ { "root", "a" }, { "states", dict({ { "a", dict({ { "tasks", arr({ "rm_rf" }) } }) } }) } })), "rm_rf"));
	CHECK_FALSE(st->validate(dict({ { "root", "a" }, { "states", dict({ { "a", dict({ { "conditions", arr({ "nope" }) } }) } }) } })).is_empty());
	CHECK_FALSE(st->validate(dict({ { "root", "a" }, { "states", dict({ { "a", dict({ { "transitions", arr({ dict({ { "trigger", "on_whim" }, { "target", "a" } }) }) } }) } }) } })).is_empty());
	CHECK_FALSE(st->validate(dict({ { "root", "a" }, { "states", dict({ { "a", dict({ { "transitions", arr({ dict({ { "trigger", "on_event" }, { "target", "a" } }) }) } }) } }) } })).is_empty());
	CHECK_FALSE(st->validate(dict({ { "root", "a" }, { "states", dict({ { "a", dict({ { "transitions", arr({ dict({ { "trigger", "on_tick" }, { "target", "zzz" } }) }) } }) } }) } })).is_empty());
	CHECK_FALSE(st->validate(dict({ { "root", "a" }, { "states", dict({ { "a", dict({ { "children", arr({ "b" }) } }) }, { "b", dict({ { "children", arr({ "a" }) } }) } }) } })).is_empty());
	CHECK_FALSE(st->validate(dict({ { "root", "a" }, { "states", dict({ { "a", dict({ { "link", "missing" } }) } }) } })).is_empty());
	st->register_subtree("loop", dict({ { "root", "x" }, { "states", dict({ { "x", dict({ { "link", "loop" } }) } }) } }));
	CHECK_FALSE(st->validate(dict({ { "root", "a" }, { "states", dict({ { "a", dict({ { "link", "loop" } }) } }) } })).is_empty());
	CHECK_FALSE(st->set_asset(dict({ { "root", "q" }, { "states", Dictionary() } })));
	CHECK_FALSE(st->get_errors().is_empty());
	CHECK_FALSE(st->start(Dictionary()));
}

TEST_CASE("[CgameStateTree] debug trace records enter and exit") {
	Ref<CgameStateTree> st = make_tree();
	st->set_asset(basic_asset());
	Dictionary ctx = dict({ { "alert", 9 } });
	st->start(ctx);
	st->stop(ctx);
	CHECK(st->get_trace() == psa({ "enter:root", "enter:rest", "exit:rest", "exit:root" }));
	st->clear_trace();
	CHECK(st->get_trace().is_empty());
}

} // namespace TestCgameStateTree
