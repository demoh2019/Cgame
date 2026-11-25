/**************************************************************************/
/*  test_cgame_planners.h                                                 */
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

#include "../cgame_goap_planner.h"
#include "../cgame_htn_planner.h"
#include "../cgame_utility_ai.h"
#include "tests/test_macros.h"

namespace TestCgamePlanners {

using namespace CgameAITestUtil;

static Dictionary _raid_htn_domain() {
	return dict({
			{ "boss_turn", arr({
									   dict({ { "preconditions", dict({ { "low_health", true }, { "enraged", false } }) }, { "subtasks", arr({ "enrage_phase" }) } }),
									   dict({ { "preconditions", dict({ { "surrounded", true }, { "adds_alive", false } }) }, { "subtasks", arr({ "summon_adds_phase" }) } }),
									   dict({ { "preconditions", dict({ { "target_far", true } }) }, { "subtasks", arr({ "charge_phase" }) } }),
									   dict({ { "preconditions", Dictionary() }, { "subtasks", arr({ "slam_phase" }) } }),
							   }) },
			{ "enrage_phase", arr({ dict({ { "preconditions", Dictionary() }, { "subtasks", arr({ "roar", "enrage", "slam" }) } }) }) },
			{ "summon_adds_phase", arr({ dict({ { "preconditions", Dictionary() }, { "subtasks", arr({ "roar", "summon_adds" }) } }) }) },
			{ "charge_phase", arr({
									  dict({ { "preconditions", dict({ { "stamina_ok", true } }) }, { "subtasks", arr({ "charge", "slam" }) } }),
									  dict({ { "preconditions", Dictionary() }, { "subtasks", arr({ "roar", "charge" }) } }),
							  }) },
			{ "slam_phase", arr({ dict({ { "preconditions", Dictionary() }, { "subtasks", arr({ "slam" }) } }) }) },
			{ "roar", dict({ { "preconditions", Dictionary() }, { "effects", dict({ { "roared", true } }) } }) },
			{ "enrage", dict({ { "preconditions", dict({ { "enraged", false } }) }, { "effects", dict({ { "enraged", true } }) } }) },
			{ "summon_adds", dict({ { "preconditions", dict({ { "adds_alive", false } }) }, { "effects", dict({ { "adds_alive", true } }) } }) },
			{ "charge", dict({ { "preconditions", dict({ { "target_far", true } }) }, { "effects", dict({ { "target_far", false } }) } }) },
			{ "slam", dict({ { "preconditions", dict({ { "target_far", false } }) }, { "effects", dict({ { "target_hit", true } }) } }) },
	});
}

static Dictionary _action(const char *p_name, double p_cost, const Dictionary &p_pre, const Dictionary &p_eff) {
	return dict({ { "name", p_name }, { "cost", p_cost }, { "preconditions", p_pre }, { "effects", p_eff } });
}

static Array _raid_goap_actions() {
	return arr({
			_action("find_food", 3.0, dict({ { "threatened", false }, { "knows_food", false } }), dict({ { "knows_food", true } })),
			_action("go_to_food", 2.0, dict({ { "knows_food", true }, { "threatened", false } }), dict({ { "at_food", true } })),
			_action("eat", 1.0, dict({ { "at_food", true }, { "threatened", false } }), dict({ { "hungry", false } })),
			_action("scavenge_corpse", 9.0, dict({ { "threatened", false } }), dict({ { "hungry", false } })),
			_action("flee", 1.0, dict({ { "threatened", true } }), dict({ { "threatened", false } })),
	});
}

TEST_CASE("[CgameHTNPlanner] backtracking falls back to the second method") {
	const Dictionary domain = dict({
			{ "root", arr({
							  dict({ { "preconditions", dict({ { "a", true } }) }, { "subtasks", arr({ "need_key", "open" }) } }),
							  dict({ { "preconditions", Dictionary() }, { "subtasks", arr({ "kick" }) } }),
					  }) },
			{ "need_key", dict({ { "preconditions", dict({ { "has_key", true } }) }, { "effects", Dictionary() } }) },
			{ "open", dict({ { "preconditions", Dictionary() }, { "effects", dict({ { "open", true } }) } }) },
			{ "kick", dict({ { "preconditions", Dictionary() }, { "effects", dict({ { "open", true } }) } }) },
	});
	CHECK(CgameHTNPlanner::plan(domain, "root", dict({ { "a", true } })) == psa({ "kick" }));
	CHECK(CgameHTNPlanner::plan(domain, "root", dict({ { "a", true }, { "has_key", true } })) == psa({ "need_key", "open" }));
	CHECK(CgameHTNPlanner::plan(domain, "root", dict({ { "a", true } })) == CgameHTNPlanner::plan(domain, "root", dict({ { "a", true } })));
	CHECK(CgameHTNPlanner::plan(domain, "missing", Dictionary()).is_empty());
	const Dictionary bad = dict({
			{ "root", arr({ dict({ { "preconditions", dict({ { "x", 1 } }) }, { "subtasks", arr({ "p" }) } }) }) },
			{ "p", dict({ { "preconditions", Dictionary() }, { "effects", Dictionary() } }) },
	});
	CHECK(CgameHTNPlanner::plan(bad, "root", dict({ { "x", 2 } })).is_empty());
}

TEST_CASE("[CgameHTNPlanner] effects feed later preconditions and the step cap terminates recursion") {
	const Dictionary seq = dict({
			{ "root", arr({ dict({ { "preconditions", Dictionary() }, { "subtasks", arr({ "a", "b" }) } }) }) },
			{ "a", dict({ { "preconditions", Dictionary() }, { "effects", dict({ { "done_a", true } }) } }) },
			{ "b", dict({ { "preconditions", dict({ { "done_a", true } }) }, { "effects", Dictionary() } }) },
	});
	CHECK(CgameHTNPlanner::plan(seq, "root", Dictionary()) == psa({ "a", "b" }));
	const Dictionary loop = dict({ { "root", arr({ dict({ { "preconditions", Dictionary() }, { "subtasks", arr({ "root" }) } }) }) } });
	CHECK(CgameHTNPlanner::plan(loop, "root", Dictionary()).is_empty());
	CHECK(CgameHTNPlanner::plan(seq, "root", Dictionary(), 1).is_empty());
}

TEST_CASE("[CgameGOAPPlanner] picks the cheapest chain and respects caps") {
	const Array actions = arr({
			_action("buy", 5.0, dict({ { "money", true } }), dict({ { "food", true } })),
			_action("hunt", 2.0, dict({ { "weapon", true } }), dict({ { "food", true } })),
			_action("craft", 1.0, Dictionary(), dict({ { "weapon", true } })),
			_action("steal", 9.0, Dictionary(), dict({ { "money", true } })),
	});
	CHECK(CgameGOAPPlanner::plan(actions, Dictionary(), dict({ { "food", true } })) == psa({ "craft", "hunt" }));
	CHECK(CgameGOAPPlanner::plan(actions, dict({ { "money", true } }), dict({ { "food", true } })) == psa({ "craft", "hunt" }));
	CHECK(CgameGOAPPlanner::plan(actions, dict({ { "food", true } }), dict({ { "food", true } })).is_empty());
	CHECK(CgameGOAPPlanner::plan(actions, Dictionary(), dict({ { "teleport", true } })).is_empty());
	CHECK(CgameGOAPPlanner::plan(actions, Dictionary(), dict({ { "food", true } }), 1).is_empty());
	const Array ties = arr({
			_action("first", 1.0, Dictionary(), dict({ { "g", true } })),
			_action("second", 1.0, Dictionary(), dict({ { "g", true } })),
	});
	CHECK(CgameGOAPPlanner::plan(ties, Dictionary(), dict({ { "g", true } })) == psa({ "first" }));
}

TEST_CASE("[CgameHTNPlanner][CgameGOAPPlanner] infected raid domain") {
	const Dictionary dom = _raid_htn_domain();
	const Dictionary base = dict({ { "low_health", false }, { "enraged", false }, { "surrounded", false }, { "adds_alive", false }, { "target_far", false }, { "stamina_ok", true } });
	CHECK(CgameHTNPlanner::plan(dom, "boss_turn", base) == psa({ "slam" }));
	Dictionary far = base.duplicate();
	far["target_far"] = true;
	CHECK(CgameHTNPlanner::plan(dom, "boss_turn", far) == psa({ "charge", "slam" }));
	Dictionary hurt = base.duplicate();
	hurt["low_health"] = true;
	CHECK(CgameHTNPlanner::plan(dom, "boss_turn", hurt) == psa({ "roar", "enrage", "slam" }));
	Dictionary swarmed = base.duplicate();
	swarmed["surrounded"] = true;
	CHECK(CgameHTNPlanner::plan(dom, "boss_turn", swarmed) == psa({ "roar", "summon_adds" }));

	const Array acts = _raid_goap_actions();
	const Dictionary hungry = dict({ { "hungry", true }, { "threatened", false }, { "knows_food", false }, { "at_food", false } });
	CHECK(CgameGOAPPlanner::plan(acts, hungry, dict({ { "hungry", false } })) == psa({ "find_food", "go_to_food", "eat" }));
	Dictionary scared = hungry.duplicate();
	scared["threatened"] = true;
	CHECK(CgameGOAPPlanner::plan(acts, scared, dict({ { "hungry", false } })) == psa({ "flee", "find_food", "go_to_food", "eat" }));
}

TEST_CASE("[CgameUtilityAI] curves, compensation and best") {
	CHECK(Math::abs(CgameUtilityAI::curve(CgameUtilityAI::LINEAR, 0.4) - 0.4) < 0.0001);
	CHECK(Math::abs(CgameUtilityAI::curve(CgameUtilityAI::QUADRATIC, 0.5) - 0.25) < 0.0001);
	CHECK(Math::abs(CgameUtilityAI::curve(CgameUtilityAI::INVERSE_QUADRATIC, 0.5) - 0.75) < 0.0001);
	CHECK(Math::abs(CgameUtilityAI::curve(CgameUtilityAI::LOGISTIC, 0.5) - 0.5) < 0.0001);
	CHECK(CgameUtilityAI::curve(CgameUtilityAI::STEP, 0.49) == 0.0);
	CHECK(CgameUtilityAI::curve(CgameUtilityAI::LINEAR, 7.0) == 1.0);
	PackedFloat32Array two;
	two.push_back(0.8f);
	two.push_back(0.8f);
	const double combined = CgameUtilityAI::combine(two);
	CHECK(combined > 0.64);
	CHECK(combined < 0.8);
	PackedFloat32Array veto;
	veto.push_back(0.9f);
	veto.push_back(0.0f);
	CHECK(CgameUtilityAI::combine(veto) == 0.0);
	CHECK(CgameUtilityAI::combine(PackedFloat32Array()) == 0.0);
	PackedFloat32Array ties;
	ties.push_back(0.2f);
	ties.push_back(0.7f);
	ties.push_back(0.7f);
	CHECK(CgameUtilityAI::best(ties) == 1);
	PackedFloat32Array zeros;
	zeros.push_back(0.0f);
	zeros.push_back(0.0f);
	CHECK(CgameUtilityAI::best(zeros) == -1);
}

TEST_CASE("[CgameUtilityAI] Invalid scores do not win or propagate") {
	CHECK(CgameUtilityAI::curve(CgameUtilityAI::LINEAR, Math::NaN) == 0.0);
	CHECK(CgameUtilityAI::curve(CgameUtilityAI::LOGISTIC, 0.5, Math::INF) == 0.0);
	PackedFloat32Array scores;
	scores.push_back(Math::INF);
	scores.push_back(0.5);
	scores.push_back(Math::NaN);
	CHECK(CgameUtilityAI::combine(scores) == 0.0);
	CHECK(CgameUtilityAI::best(scores) == 1);
	CHECK(CgameUtilityAI::infected_target_score(1.0, Math::NaN, 1.0, true, false) == 0.0);
	CHECK(CgameUtilityAI::infected_target_score(-1.0, 30.0, 1.0, true, false) == 0.0);
}

TEST_CASE("[CgameUtilityAI] infected prey choice") {
	const double near_healthy = CgameUtilityAI::infected_target_score(5.0, 30.0, 1.0, false, false);
	const double far_healthy = CgameUtilityAI::infected_target_score(12.0, 30.0, 1.0, false, false);
	CHECK(near_healthy > far_healthy);
	const double slightly_far_wounded = CgameUtilityAI::infected_target_score(6.5, 30.0, 0.15, false, false);
	CHECK(slightly_far_wounded > near_healthy);
	const double much_farther_wounded = CgameUtilityAI::infected_target_score(20.0, 30.0, 0.1, false, false);
	CHECK(near_healthy > much_farther_wounded);
	CHECK(CgameUtilityAI::infected_target_score(6.0, 30.0, 1.0, true, false) > CgameUtilityAI::infected_target_score(5.0, 30.0, 1.0, false, false));
	CHECK(CgameUtilityAI::infected_target_score(5.0, 30.0, 1.0, false, true) > near_healthy);
	CHECK(CgameUtilityAI::infected_target_score(40.0, 30.0, 1.0, false, false) == 0.0);
	CHECK(CgameUtilityAI::infected_target_score(40.0, 30.0, 1.0, true, false) > 0.0);
	CHECK(CgameUtilityAI::infected_target_score(Math::INF, 30.0, 1.0, true, false) == 0.0);
}

} // namespace TestCgamePlanners
