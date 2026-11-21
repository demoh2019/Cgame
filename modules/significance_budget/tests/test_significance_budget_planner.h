/**************************************************************************/
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#pragma once

#include "../significance_budget_planner.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestSignificanceBudgetPlanner {

TEST_CASE("[SignificanceBudget] ranked top K keeps special actors and stable ties") {
	Ref<SignificanceBudgetPlanner> planner;
	planner.instantiate();
	PackedFloat64Array distances;
	PackedByteArray priorities;
	const double positions[] = { 2.0, 1.0, 4.0, 4.0, 0.5, 8.0 };
	const uint8_t importance[] = { 0, 0, 3, 3, 2, 1 };
	for (int i = 0; i < 6; ++i) {
		distances.push_back(positions[i]);
		priorities.push_back(importance[i]);
	}
	PackedInt32Array indices = planner->select_top(distances, priorities, 4);
	REQUIRE(indices.size() == 4);
	CHECK(indices[0] == 2);
	CHECK(indices[1] == 3); // Identical boss distances: original index wins.
	CHECK(indices[2] == 4);
	CHECK(indices[3] == 5);
	CHECK(planner->select_top(distances, priorities, 0).is_empty());
	CHECK(planner->select_top(distances, priorities, 128).size() == 6);
	CHECK(distances[0] == 2.0); // Pure: caller array remains untouched.
}

TEST_CASE("[SignificanceBudget] reject malformed input without a partial selection") {
	Ref<SignificanceBudgetPlanner> planner;
	planner.instantiate();
	PackedFloat64Array distances;
	PackedByteArray priorities;
	distances.push_back(1.0);
	priorities.push_back(3);
	CHECK(planner->select_top(distances, priorities, -1).is_empty());
	CHECK(planner->select_top(distances, priorities, 129).is_empty());
	priorities.push_back(0);
	CHECK(planner->select_top(distances, priorities, 1).is_empty());
	priorities.resize(1);
	priorities.set(0, 4);
	CHECK(planner->select_top(distances, priorities, 1).is_empty());
	priorities.set(0, 3);
	distances.set(0, Math::INF);
	CHECK(planner->select_top(distances, priorities, 1).is_empty());
	distances.set(0, Math::NaN);
	CHECK(planner->select_top(distances, priorities, 1).is_empty());
	distances.set(0, -1.0);
	CHECK(planner->select_top(distances, priorities, 1).is_empty());
	distances.set(0, 1.0);
	REQUIRE(planner->select_top(distances, priorities, 1).size() == 1);
}

TEST_CASE("[SignificanceBudget] multi-viewer selection, inclusive distance and validation") {
	Ref<SignificanceBudgetPlanner> planner;
	planner.instantiate();
	PackedVector3Array positions;
	positions.push_back(Vector3(1, 0, 0));
	positions.push_back(Vector3(99, 0, 0));
	positions.push_back(Vector3(50, 0, 0));
	positions.push_back(Vector3(200, 0, 0));
	PackedVector3Array viewers;
	viewers.push_back(Vector3(0, 0, 0));
	viewers.push_back(Vector3(100, 0, 0));
	PackedByteArray priorities;
	priorities.push_back(0);
	priorities.push_back(0);
	priorities.push_back(3); // Important but outside a 10m interest radius.
	priorities.push_back(3);
	PackedInt32Array result = planner->select_world(positions, viewers, priorities, 2, 10.0);
	REQUIRE(result.size() == 2);
	CHECK(result[0] == 0);
	CHECK(result[1] == 1);
	CHECK(planner->select_world(positions, viewers, priorities, 2, 0.0).is_empty());
	CHECK(planner->select_world(positions, PackedVector3Array(), priorities, 2).is_empty());
	viewers.set(0, Vector3(Math::INF, 0, 0));
	CHECK(planner->select_world(positions, viewers, priorities, 2).is_empty());
	viewers.set(0, Vector3(0, 0, 0));
	CHECK(planner->select_world(positions, viewers, priorities, 2, -1).is_empty());
	CHECK(planner->select_world(positions, viewers, priorities, 2, Math::NaN).is_empty());
	CHECK(planner->select_world(positions, viewers, priorities, 2, 1000001).is_empty());
	positions.set(0, Vector3(Math::INF, 0, 0));
	CHECK(planner->select_world(positions, viewers, priorities, 2).is_empty());
}


TEST_CASE("[SignificanceBudget] stable IDs and hysteresis keep nearby light slots") {
	Ref<SignificanceBudgetPlanner> planner;
	planner.instantiate();
	PackedFloat64Array distances;
	PackedInt64Array ids;
	for (double d : { 5.0, 6.0, 6.0, 14.0 }) {
		distances.push_back(d);
	}
	for (int64_t id : { 9, 5, 4, 12 }) {
		ids.push_back(id);
	}
	PackedInt64Array retained;
	PackedInt32Array order = planner->select_top_stable(distances, ids, retained, 2, 10.0);
	REQUIRE(order.size() == 2);
	CHECK(order[0] == 0);
	CHECK(order[1] == 2); // Equal distances are ordered by stable ID.
	retained.push_back(5);
	order = planner->select_top_stable(distances, ids, retained, 2, 10.0, 2.0);
	REQUIRE(order.size() == 2);
	CHECK(order[0] == 1);
	CHECK(order[1] == 0);
	retained.clear();
	retained.push_back(12); // Previously enabled but now outside radius.
	order = planner->select_top_stable(distances, ids, retained, 2, 10.0, 10.0);
	REQUIRE(order.size() == 2);
	CHECK(order[0] == 0);
	CHECK(order[1] == 2);
	CHECK(planner->select_top_stable(distances, ids, retained, 0, 10.0).is_empty());
	CHECK(planner->select_top_stable(distances, ids, retained, 4, 10.0).size() == 3);
}

TEST_CASE("[SignificanceBudget] stable selection rejects malformed input atomically") {
	Ref<SignificanceBudgetPlanner> planner;
	planner.instantiate();
	PackedFloat64Array distances;
	PackedInt64Array ids;
	PackedInt64Array retained;
	distances.push_back(3.0);
	ids.push_back(42);
	CHECK(planner->select_top_stable(distances, ids, retained, 1, 10.0).size() == 1);
	CHECK(planner->select_top_stable(distances, ids, retained, -1, 10.0).is_empty());
	CHECK(planner->select_top_stable(distances, ids, retained, 129, 10.0).is_empty());
	CHECK(planner->select_top_stable(distances, ids, retained, 1, 10.0, 11.0).is_empty());
	CHECK(planner->select_top_stable(distances, ids, retained, 1, Math::NaN).is_empty());
	distances.push_back(Math::INF);
	ids.push_back(45);
	CHECK(planner->select_top_stable(distances, ids, retained, 1, 10.0).is_empty());
	distances.set(1, 5.0);
	ids.set(1, 42);
	CHECK(planner->select_top_stable(distances, ids, retained, 1, 10.0).is_empty());
	ids.set(1, 45);
	distances.push_back(7.0);
	CHECK(planner->select_top_stable(distances, ids, retained, 1, 10.0).is_empty());
}


TEST_CASE("[SignificanceBudget] category caps protect critical VFX during crowd storms") {
	Ref<SignificanceBudgetPlanner> planner;
	planner.instantiate();
	const PackedFloat64Array distances = { 2.0, 1.0, 3.0, 5.0, 4.0, 120.0, 1.0, 2.0 };
	const PackedByteArray priorities = { 0, 0, 1, 3, 2, 3, 2, 2 };
	const PackedByteArray categories = { 0, 0, 1, 3, 2, 3, 2, 2 };
	const PackedInt32Array caps = { 1, 2, 2, 1 };
	const PackedInt32Array expected = { 3, 6, 7, 2, 1 };
	const PackedInt32Array minimal = { 3, 6 };
	const PackedInt32Array edge = { 6, 1 };
	CHECK(planner->select_effects(distances, priorities, categories, caps, 5, 100.0) == expected);
	CHECK(planner->select_effects(distances, priorities, categories, caps, 2, 100.0) == minimal);
	CHECK(planner->select_effects(distances, priorities, categories, caps, 8, 1.0) == edge);
	CHECK(planner->select_effects(distances, priorities, categories, caps, 0, 100.0).is_empty());
	CHECK(distances[0] == 2.0);
}

TEST_CASE("[SignificanceBudget] frustum-aware effects honor strict priority and caps") {
	Ref<SignificanceBudgetPlanner> planner;
	planner.instantiate();
	const PackedFloat64Array distances = { 5.0, 8.0, 1.0, 2.0, 11.0 };
	const PackedByteArray priorities = { 1, 1, 2, 1, 3 };
	const PackedByteArray categories = { 0, 0, 1, 0, 1 };
	const PackedByteArray visible = { 0, 1, 0, 1, 1 };
	const PackedInt32Array caps = { 2, 1, 0, 0 };
	const PackedInt32Array selected = { 2, 3, 1 };
	CHECK(planner->select_effects_visible(distances, priorities, categories, visible,
			caps, 3, 10.0) == selected);
	CHECK(planner->select_effects_visible(distances, priorities, categories, visible,
			caps, 0, 10.0).is_empty());
	const PackedInt32Array near_only = { 2 };
	CHECK(planner->select_effects_visible(distances, priorities, categories, visible,
			caps, 3, 1.0) == near_only);
	CHECK(planner->select_effects_visible(distances, priorities, categories, { 1, 1 },
			caps, 3, 10.0).is_empty());
	CHECK(planner->select_effects_visible(distances, priorities, categories,
			{ 0, 1, 2, 1, 1 }, caps, 3, 10.0).is_empty());
	CHECK(planner->select_effects_visible(distances, priorities, categories, visible,
			{ 2, -1, 0, 0 }, 3, 10.0).is_empty());
	CHECK(planner->select_effects_visible({ Math::NaN }, { 1 }, { 0 }, { 1 },
			caps, 1, 10.0).is_empty());
}

TEST_CASE("[SignificanceBudget] ranged effect categories protect distant milestones") {
	Ref<SignificanceBudgetPlanner> planner;
	planner.instantiate();
	const PackedFloat64Array distances = { 40.0, 40.01, 80.0, 80.01, 120.0, 120.01, 140.0, 140.01 };
	const PackedByteArray priorities = { 0, 0, 1, 1, 2, 2, 3, 3 };
	const PackedByteArray categories = { 0, 0, 1, 1, 2, 2, 3, 3 };
	const PackedByteArray visible = { 1, 1, 1, 1, 1, 1, 1, 1 };
	const PackedInt32Array caps = { 4, 4, 4, 4 };
	const PackedFloat64Array ranges = { 40.0, 80.0, 120.0, 140.0 };
	CHECK(planner->select_effects_visible_ranged(distances, priorities, categories,
			visible, caps, ranges, 8) == PackedInt32Array({ 6, 4, 2, 0 }));
	CHECK(planner->select_effects_visible_ranged(distances, priorities, categories,
			visible, caps, ranges, 2) == PackedInt32Array({ 6, 4 }));
	CHECK(planner->select_effects_visible_ranged(distances, priorities, categories,
			visible, caps, ranges, 0).is_empty());
	CHECK(distances[0] == 40.0);
	// Off-screen critical effect outranks visible nearby dust.
	CHECK(planner->select_effects_visible_ranged({ 1.0, 20.0 }, { 0, 3 },
			{ 0, 3 }, { 1, 0 }, caps, ranges, 2) == PackedInt32Array({ 1, 0 }));
	// Zero range admits only exact-zero distance.
	CHECK(planner->select_effects_visible_ranged({ 0.0, 0.01 }, { 0, 0 },
			{ 0, 0 }, { 1, 1 }, caps, { 0.0, 80.0, 120.0, 140.0 }, 2)
			== PackedInt32Array({ 0 }));
	CHECK(planner->select_effects_visible_ranged(distances, priorities, categories,
			visible, { 0, 0, 0, 1 }, ranges, 8) == PackedInt32Array({ 6 }));
}


TEST_CASE("[SignificanceBudget] soft category minimums protect battle feedback after urgency") {
	Ref<SignificanceBudgetPlanner> planner;
	planner.instantiate();
	const PackedFloat64Array distances = { 1, 2, 3, 4, 5, 6, 7, 8 };
	const PackedByteArray priority = { 2, 2, 2, 2, 1, 1, 0, 3 };
	const PackedByteArray categories = { 2, 2, 2, 2, 1, 1, 0, 3 };
	const PackedByteArray visible = { 1, 1, 1, 1, 1, 1, 1, 1 };
	const PackedInt32Array caps = { 4, 4, 4, 4 };
	const PackedFloat64Array ranges = { 40, 80, 120, 140 };
	const PackedInt32Array minimums = { 0, 1, 1, 0 };
	const PackedInt32Array wanted = { 7, 4, 0, 1 };
	CHECK(planner->select_effects_visible_fair(distances, priority, categories,
			visible, caps, ranges, minimums, 4) == wanted);
	// The old global-rank method would starve ordinary hit effects.
	const PackedInt32Array old = { 7, 0, 1, 2 };
	CHECK(planner->select_effects_visible_ranged(distances, priority, categories,
			visible, caps, ranges, 4) == old);
	CHECK(planner->select_effects_visible_fair(distances, priority, categories,
			visible, caps, ranges, { 0, 0, 0, 0 }, 4) == old);
	const PackedByteArray emergency = { 3, 3, 3, 3, 1, 1, 0, 3 };
	const PackedInt32Array emergency_expected = { 0, 1, 2, 3 };
	CHECK(planner->select_effects_visible_fair(distances, emergency, categories,
			visible, caps, ranges, minimums, 4) == emergency_expected);
	CHECK(distances[0] == 1.0); // No mutation of caller input.
}

TEST_CASE("[SignificanceBudget] VFX minimums are soft, within strict category caps and range gates") {
	Ref<SignificanceBudgetPlanner> planner;
	planner.instantiate();
	const PackedFloat64Array distance = { 5, 10, 30, 30.01, 100 };
	const PackedByteArray priorities = { 0, 1, 2, 2, 3 };
	const PackedByteArray categories = { 0, 1, 2, 2, 3 };
	const PackedByteArray visible = { 1, 1, 1, 0, 0 };
	const PackedInt32Array caps = { 2, 2, 1, 2 };
	const PackedFloat64Array ranges = { 5, 20, 30, 90 };
	const PackedInt32Array mins = { 0, 1, 1, 0 };
	const PackedInt32Array expected = { 2, 1, 0 };
	CHECK(planner->select_effects_visible_fair(distance, priorities, categories,
			visible, caps, ranges, mins, 4) == expected);
	// Category 2 is absent: its reserved slot returns to eligible work.
	const PackedInt32Array no_combat = { 1, 0 };
	CHECK(planner->select_effects_visible_fair({ 5, 10, 90, 91, 100 }, priorities,
			categories, visible, caps, ranges, mins, 4) == no_combat);
	const PackedInt32Array all_dust = { 0 };
	CHECK(planner->select_effects_visible_fair({ 1 }, { 0 }, { 0 }, { 1 },
			caps, ranges, mins, 3) == all_dust);
}

TEST_CASE("[SignificanceBudget] VFX soft reservations reject malformed input before selection") {
	Ref<SignificanceBudgetPlanner> planner;
	planner.instantiate();
	const PackedFloat64Array d = { 1, 2 };
	const PackedByteArray pri = { 1, 2 };
	const PackedByteArray cat = { 1, 2 };
	const PackedByteArray visible = { 1, 1 };
	const PackedInt32Array caps = { 2, 2, 2, 2 };
	const PackedFloat64Array ranges = { 10, 20, 30, 40 };
	const PackedInt32Array minimums = { 0, 1, 1, 0 };
	CHECK(planner->select_effects_visible_fair(d, pri, cat, visible, caps, ranges,
			minimums, 2).size() == 2);
	CHECK(planner->select_effects_visible_fair(d, pri, cat, visible, caps, ranges,
			{ 0, 1, 1 }, 2).is_empty());
	CHECK(planner->select_effects_visible_fair(d, pri, cat, visible, caps, ranges,
			{ 0, -1, 1, 0 }, 2).is_empty());
	CHECK(planner->select_effects_visible_fair(d, pri, cat, visible, caps, ranges,
			{ 0, 3, 0, 0 }, 3).is_empty());
	CHECK(planner->select_effects_visible_fair(d, pri, cat, visible, caps, ranges,
			minimums, 1).is_empty()); // Sum of minimums exceeds total budget.
	CHECK(planner->select_effects_visible_fair(d, { 1 }, cat, visible, caps, ranges,
			minimums, 2).is_empty());
	CHECK(planner->select_effects_visible_fair(d, pri, cat, { 1, 2 }, caps, ranges,
			minimums, 2).is_empty());
	CHECK(planner->select_effects_visible_fair({ Math::NaN, 2 }, pri, cat, visible,
			caps, ranges, minimums, 2).is_empty());
	CHECK(planner->select_effects_visible_fair(d, pri, cat, visible, caps,
			{ Math::INF, 20, 30, 40 }, minimums, 2).is_empty());
	CHECK(planner->select_effects_visible_fair(d, pri, cat, visible, caps,
			ranges, minimums, 129).is_empty());
}

TEST_CASE("[SignificanceBudget] ranged effect inputs fail closed") {
	Ref<SignificanceBudgetPlanner> planner;
	planner.instantiate();
	const PackedFloat64Array distances = { 1.0 };
	const PackedByteArray priorities = { 1 };
	const PackedByteArray categories = { 0 };
	const PackedByteArray visible = { 1 };
	const PackedInt32Array caps = { 1, 1, 1, 1 };
	const PackedFloat64Array ranges = { 40.0, 80.0, 120.0, 140.0 };
	CHECK(planner->select_effects_visible_ranged(distances, priorities, categories,
			visible, caps, ranges, 1).size() == 1);
	CHECK(planner->select_effects_visible_ranged({ Math::NaN }, priorities, categories,
			visible, caps, ranges, 1).is_empty());
	CHECK(planner->select_effects_visible_ranged(distances, { 4 }, categories,
			visible, caps, ranges, 1).is_empty());
	CHECK(planner->select_effects_visible_ranged(distances, priorities, { 4 },
			visible, caps, ranges, 1).is_empty());
	CHECK(planner->select_effects_visible_ranged(distances, priorities, categories,
			{ 2 }, caps, ranges, 1).is_empty());
	CHECK(planner->select_effects_visible_ranged(distances, priorities, categories,
			{}, caps, ranges, 1).is_empty());
	CHECK(planner->select_effects_visible_ranged(distances, priorities, categories,
			visible, caps, { 10.0, 20.0 }, 1).is_empty());
	CHECK(planner->select_effects_visible_ranged(distances, priorities, categories,
			visible, caps, { 10.0, Math::INF, 20.0, 30.0 }, 1).is_empty());
	CHECK(planner->select_effects_visible_ranged(distances, priorities, categories,
			visible, caps, { -1.0, 20.0, 30.0, 40.0 }, 1).is_empty());
	CHECK(planner->select_effects_visible_ranged(distances, priorities, categories,
			visible, { 129, 1, 1, 1 }, ranges, 1).is_empty());
	CHECK(planner->select_effects_visible_ranged(distances, priorities, categories,
			visible, caps, ranges, 129).is_empty());
}

TEST_CASE("[SignificanceBudget] invalid category input is rejected atomically") {
	Ref<SignificanceBudgetPlanner> planner;
	planner.instantiate();
	const PackedFloat64Array distances = { 1.0, 2.0 };
	const PackedByteArray priorities = { 3, 0 };
	const PackedByteArray groups = { 2, 0 };
	const PackedInt32Array caps = { 2, 2, 2, 2 };
	CHECK(planner->select_effects(distances, priorities, groups, caps, 2, 90.0).size() == 2);
	CHECK(planner->select_effects({ 1.0 }, priorities, groups, caps, 2, 90.0).is_empty());
	CHECK(planner->select_effects({ 1.0, Math::NaN }, priorities, groups, caps, 2, 90.0).is_empty());
	CHECK(planner->select_effects({ 1.0, -1.0 }, priorities, groups, caps, 2, 90.0).is_empty());
	CHECK(planner->select_effects(distances, { 3, 4 }, groups, caps, 2, 90.0).is_empty());
	CHECK(planner->select_effects(distances, priorities, { 2, 4 }, caps, 2, 90.0).is_empty());
	CHECK(planner->select_effects(distances, priorities, groups, { 1, 2 }, 2, 90.0).is_empty());
	CHECK(planner->select_effects(distances, priorities, groups, { -1, 2, 2, 2 }, 2, 90.0).is_empty());
	CHECK(planner->select_effects(distances, priorities, groups, caps, 129, 90.0).is_empty());
	CHECK(planner->select_effects(distances, priorities, groups, caps, 2, Math::INF).is_empty());
}


TEST_CASE("[SignificanceBudget] priority-stable HUD protects bosses, retained peers, and hard range") {
	Ref<SignificanceBudgetPlanner> p;
	p.instantiate();
	const PackedFloat64Array distance = { 7.0, 6.0, 5.0, 13.0, 8.0 };
	const PackedByteArray priority = { 0, 0, 3, 2, 2 };
	const PackedInt64Array ids = { 100, 101, 50, 52, 55 };
	const PackedInt64Array kept = { 100, 55 };
	const PackedInt32Array expected = { 2, 4, 0 };
	CHECK(p->select_top_priority_stable(distance, priority, ids, kept, 3, 10.0, 2.0) == expected);
	CHECK(p->select_top_priority_stable(distance, priority, ids, kept, 0, 10.0, 2.0).is_empty());
	CHECK(p->select_top_priority_stable(distance, priority, ids, kept, 5, 10.0, 2.0).size() == 4);
	CHECK(ids[0] == 100); // Pure inputs.
	const PackedFloat64Array ties = { 6.0, 6.0 };
	const PackedByteArray equal_priority = { 1, 1 };
	const PackedInt64Array tie_ids = { 90, 7 };
	const PackedInt32Array tie_by_id = { 1, 0 };
	const PackedInt32Array retained_first = { 0 };
	CHECK(p->select_top_priority_stable(ties, equal_priority, tie_ids, {}, 2, 10.0) == tie_by_id);
	CHECK(p->select_top_priority_stable(ties, equal_priority, tie_ids, { 90 }, 1, 10.0, 1.5) == retained_first);
	const PackedInt32Array in_range = { 1 };
	CHECK(p->select_top_priority_stable({ 10.01, 2.0 }, { 3, 0 }, { 777, 7 },
			{ 777 }, 2, 10.0, 2.0) == in_range);
}

TEST_CASE("[SignificanceBudget] priority-stable malformed inputs reject atomically") {
	Ref<SignificanceBudgetPlanner> p;
	p.instantiate();
	const PackedFloat64Array distances = { 1.0, 2.0 };
	const PackedByteArray pri = { 3, 0 };
	const PackedInt64Array ids = { 12, 13 };
	CHECK(p->select_top_priority_stable(distances, pri, ids, {}, 2, 10.0).size() == 2);
	CHECK(p->select_top_priority_stable(distances, { 3 }, ids, {}, 2, 10.0).is_empty());
	CHECK(p->select_top_priority_stable(distances, pri, { 12 }, {}, 2, 10.0).is_empty());
	CHECK(p->select_top_priority_stable({ 1.0, Math::NaN }, pri, ids, {}, 2, 10.0).is_empty());
	CHECK(p->select_top_priority_stable({ -1.0, 2.0 }, pri, ids, {}, 2, 10.0).is_empty());
	CHECK(p->select_top_priority_stable(distances, { 3, 4 }, ids, {}, 2, 10.0).is_empty());
	CHECK(p->select_top_priority_stable(distances, pri, { 12, 12 }, {}, 2, 10.0).is_empty());
	CHECK(p->select_top_priority_stable(distances, pri, { 0, 13 }, {}, 2, 10.0).is_empty());
	CHECK(p->select_top_priority_stable(distances, pri, ids, { 12, 12 }, 2, 10.0).is_empty());
	CHECK(p->select_top_priority_stable(distances, pri, ids, { -1 }, 2, 10.0).is_empty());
	CHECK(p->select_top_priority_stable(distances, pri, ids, {}, -1, 10.0).is_empty());
	CHECK(p->select_top_priority_stable(distances, pri, ids, {}, 129, 10.0).is_empty());
	CHECK(p->select_top_priority_stable(distances, pri, ids, {}, 2, Math::NaN).is_empty());
	CHECK(p->select_top_priority_stable(distances, pri, ids, {}, 2, 10.0, -1.0).is_empty());
	CHECK(p->select_top_priority_stable(distances, pri, ids, {}, 2, 10.0, 11.0).is_empty());
}


TEST_CASE("[SignificanceBudget] HLOD shadow significance preserves structures and active hysteresis") {
	Ref<SignificanceBudgetPlanner> planner;
	planner.instantiate();
	PackedVector3Array low;
	PackedVector3Array high;
	PackedByteArray roles;
	PackedByteArray active;
	const double distances[] = { 10.0, 1.0, 60.0, 9.0, 0.0 };
	const uint8_t kinds[] = { 1, 0, 2, 1, 3 };
	const uint8_t states[] = { 0, 0, 0, 1, 0 };
	for (int i = 0; i < 5; i++) {
		low.push_back(Vector3(distances[i], 100.0, 0.0));
		high.push_back(Vector3(distances[i] + 2.0, 150.0, 3.0));
		roles.push_back(kinds[i]);
		active.push_back(states[i]);
	}
	PackedFloat64Array radii;
	radii.push_back(26.0);
	radii.push_back(48.0);
	radii.push_back(68.0);
	const PackedInt32Array chosen = planner->select_shadow_casters(
			low, high, roles, active, Vector3(0, 0, 0), radii, 3);
	REQUIRE(chosen.size() == 3);
	CHECK(chosen[0] == 2); // Landmark structures before disposable bushes.
	CHECK(chosen[1] == 3); // Existing caster receives a 5 m retention bonus.
	CHECK(chosen[2] == 0);
	CHECK(planner->select_shadow_casters(low, high, roles, active,
			Vector3(0, 0, 0), radii, 0).is_empty());
	CHECK(planner->select_shadow_casters(low, high, roles, active,
			Vector3(0, 0, 0), radii, 128).size() == 4);
	// Camera altitude does not cause a surface shadow to be lost.
	low.set(0, Vector3(0, 100, 0));
	high.set(0, Vector3(10, 150, 10));
	const PackedInt32Array vertical = planner->select_shadow_casters(
			low, high, roles, active, Vector3(5, 1000, 5), radii, 3);
	CHECK(vertical.size() == 3);
	CHECK(vertical[1] == 0);
}

TEST_CASE("[SignificanceBudget] HLOD shadow margins include boundaries without flickering") {
	Ref<SignificanceBudgetPlanner> planner;
	planner.instantiate();
	PackedVector3Array low;
	PackedVector3Array high;
	PackedByteArray roles;
	PackedByteArray active;
	for (int i = 0; i < 5; ++i) {
		const double x[] = { 44, 52, 53, 54, 43 };
		low.push_back(Vector3(x[i], 0, 0));
		high.push_back(Vector3(x[i], 1, 1));
		roles.push_back(1);
		active.push_back(i == 1 || i == 2 || i == 3 ? 1 : 0);
	}
	PackedFloat64Array radii;
	radii.push_back(26.0);
	radii.push_back(48.0);
	radii.push_back(68.0);
	const PackedInt32Array chosen = planner->select_shadow_casters(
			low, high, roles, active, Vector3(), radii, 3, 5.0);
	REQUIRE(chosen.size() == 3);
	CHECK(chosen[0] == 4); // Inactive 43 m is exactly at the threshold.
	CHECK(chosen[1] == 1); // Active 52 m retained to 53 m boundary.
	CHECK(chosen[2] == 2); // Exact active 53 m boundary included.
	radii.set(1, 0.0);
	CHECK(planner->select_shadow_casters(low, high, roles, active, Vector3(),
			radii, 3).is_empty()); // Quality 0 disables even retained shadows.
}

TEST_CASE("[SignificanceBudget] HLOD shadow planning rejects malformed batches atomically") {
	Ref<SignificanceBudgetPlanner> planner;
	planner.instantiate();
	PackedVector3Array low;
	PackedVector3Array high;
	low.push_back(Vector3(1, 0, 1));
	high.push_back(Vector3(2, 1, 2));
	PackedByteArray roles;
	roles.push_back(1);
	PackedByteArray active;
	active.push_back(0);
	PackedFloat64Array radii;
	radii.push_back(26.0);
	radii.push_back(48.0);
	radii.push_back(68.0);
	CHECK(planner->select_shadow_casters(low, high, roles, active, Vector3(),
			radii, 1).size() == 1);
	CHECK(planner->select_shadow_casters(low, high, roles, active, Vector3(),
			radii, -1).is_empty());
	CHECK(planner->select_shadow_casters(low, high, roles, active, Vector3(),
			radii, 129).is_empty());
	CHECK(planner->select_shadow_casters(low, high, roles, active,
			Vector3(Math::INF, 0, 0), radii, 1).is_empty());
	radii.set(0, Math::NaN);
	CHECK(planner->select_shadow_casters(low, high, roles, active, Vector3(),
			radii, 1).is_empty());
	radii.set(0, 26.0);
	roles.set(0, 4);
	CHECK(planner->select_shadow_casters(low, high, roles, active, Vector3(),
			radii, 1).is_empty());
	roles.set(0, 1);
	active.set(0, 2);
	CHECK(planner->select_shadow_casters(low, high, roles, active, Vector3(),
			radii, 1).is_empty());
	active.set(0, 0);
	low.push_back(Vector3(Math::NaN, 0, 1)); // Invalid late candidate.
	high.push_back(Vector3(3, 1, 2));
	roles.push_back(1);
	active.push_back(0);
	CHECK(planner->select_shadow_casters(low, high, roles, active, Vector3(),
			radii, 1).is_empty());
	low.set(1, Vector3(3, 0, 1));
	high.set(1, Vector3(2, 1, 2)); // Reversed AABB.
	CHECK(planner->select_shadow_casters(low, high, roles, active, Vector3(),
			radii, 1).is_empty());
	high.remove_at(1);
	CHECK(planner->select_shadow_casters(low, high, roles, active, Vector3(),
			radii, 1).is_empty()); // Mismatched arrays.
}

TEST_CASE("[SignificanceBudget] HLOD shadow cap returns stable 128 of 512 groups") {
	Ref<SignificanceBudgetPlanner> planner;
	planner.instantiate();
	PackedVector3Array low;
	PackedVector3Array high;
	PackedByteArray roles;
	PackedByteArray active;
	for (int i = 0; i < 512; ++i) {
		low.push_back(Vector3(1, 0, 1));
		high.push_back(Vector3(2, 1, 2));
		roles.push_back(1);
		active.push_back(0);
	}
	PackedFloat64Array radii;
	radii.push_back(26.0);
	radii.push_back(48.0);
	radii.push_back(68.0);
	const PackedInt32Array chosen = planner->select_shadow_casters(
			low, high, roles, active, Vector3(), radii, 128);
	REQUIRE(chosen.size() == 128);
	for (int i = 0; i < chosen.size(); ++i) {
		CHECK(chosen[i] == i);
	}
}


TEST_CASE("[SignificanceBudget] stable multi-viewer priority, hard range and retention") {
	Ref<SignificanceBudgetPlanner> p;
	p.instantiate();
	const PackedVector3Array positions = { Vector3(7, 0, 0), Vector3(94, 0, 0),
			Vector3(300, 0, 0), Vector3(9, 0, 0) };
	const PackedVector3Array viewers = { Vector3(0, 0, 0), Vector3(100, 0, 0) };
	const PackedByteArray priorities = { 1, 1, 3, 2 };
	const PackedInt64Array ids = { 11, 22, 33, 44 };
	const PackedInt32Array retained_order = { 3, 0, 1 };
	const PackedInt32Array nearest_order = { 3, 1, 0 };
	CHECK(p->select_world_priority_stable(positions, viewers, priorities, ids,
			{ 11 }, 3, 10.0, 3.0) == retained_order);
	CHECK(p->select_world_priority_stable(positions, viewers, priorities, ids,
			{}, 3, 10.0, 3.0) == nearest_order);
	CHECK(p->select_world_priority_stable(positions, viewers, priorities, ids,
			{ 33 }, 3, 10.0, 3.0) == nearest_order);
	CHECK(p->select_world_priority_stable(positions, viewers, priorities, ids,
			{}, 0, 10.0).is_empty());
	CHECK(positions[0] == Vector3(7, 0, 0));
	const PackedInt32Array tie_order = { 1, 0 };
	CHECK(p->select_world_priority_stable({ Vector3(5, 0, 0), Vector3(95, 0, 0) },
			viewers, { 1, 1 }, { 30, 3 }, {}, 2, 10.0) == tie_order);
}

TEST_CASE("[SignificanceBudget] stable multi-viewer inputs reject atomically") {
	Ref<SignificanceBudgetPlanner> p;
	p.instantiate();
	const PackedVector3Array positions = { Vector3(1, 0, 0), Vector3(2, 0, 0) };
	const PackedVector3Array viewers = { Vector3(0, 0, 0) };
	const PackedByteArray priorities = { 1, 2 };
	const PackedInt64Array ids = { 1, 2 };
	CHECK(p->select_world_priority_stable(positions, viewers, priorities, ids,
			{}, 2, 10.0).size() == 2);
	CHECK(p->select_world_priority_stable(positions, {}, priorities, ids,
			{}, 2, 10.0).is_empty());
	CHECK(p->select_world_priority_stable(positions, viewers, { 1 }, ids,
			{}, 2, 10.0).is_empty());
	CHECK(p->select_world_priority_stable(positions, viewers, priorities, { 1, 1 },
			{}, 2, 10.0).is_empty());
	CHECK(p->select_world_priority_stable(positions, viewers, priorities, ids,
			{ 1, 1 }, 2, 10.0).is_empty());
	CHECK(p->select_world_priority_stable(positions, viewers, { 4, 2 }, ids,
			{}, 2, 10.0).is_empty());
	CHECK(p->select_world_priority_stable(positions, viewers, priorities, ids,
			{}, 129, 10.0).is_empty());
	CHECK(p->select_world_priority_stable(positions, viewers, priorities, ids,
			{}, 2, Math::INF).is_empty());
	CHECK(p->select_world_priority_stable(positions, viewers, priorities, ids,
			{}, 2, 10.0, 11.0).is_empty());
	CHECK(p->select_world_priority_stable({ Vector3(Math::INF, 0, 0) },
			viewers, { 1 }, { 1 }, {}, 1, 10.0).is_empty());
	CHECK(p->select_world_priority_stable(positions, { Vector3(Math::NaN, 0, 0) },
			priorities, ids, {}, 2, 10.0).is_empty());
	PackedVector3Array too_many_viewers;
	for (int i = 0; i < 17; ++i) {
		too_many_viewers.push_back(Vector3(i, 0, 0));
	}
	CHECK(p->select_world_priority_stable(positions, too_many_viewers,
			priorities, ids, {}, 2, 10.0).is_empty());
}

TEST_CASE("[SignificanceBudget] stable multi-viewer world selection protects priority and range") {
	Ref<SignificanceBudgetPlanner> p;
	p.instantiate();
	const PackedVector3Array positions = { Vector3(4, 0, 0), Vector3(6, 0, 0), Vector3(96, 0, 0), Vector3(200, 0, 0) };
	const PackedVector3Array viewers = { Vector3(), Vector3(100, 0, 0) };
	const PackedByteArray priorities = { 0, 0, 2, 3 };
	const PackedInt64Array ids = { 42, 43, 44, 45 };
	const PackedInt64Array retained = { 43, 45 };
	const PackedInt32Array expected = { 2, 1 };
	CHECK(p->select_world_priority_stable(positions, viewers, priorities, ids, retained, 2, 10.0, 3.0) == expected);
	CHECK(p->select_world_priority_stable(positions, viewers, priorities, ids, retained, 4, 10.0, 3.0).size() == 3);
	CHECK(p->select_world_priority_stable(positions, viewers, priorities, ids, retained, 0, 10.0).is_empty());
	const PackedInt32Array ties = { 1, 0 };
	CHECK(p->select_world_priority_stable({ Vector3(6, 0, 0), Vector3(6, 0, 0) },
			{ Vector3() }, { 0, 0 }, { 9, 7 }, {}, 2, 10.0) == ties);
	const PackedInt32Array in_range = { 1 };
	CHECK(p->select_world_priority_stable({ Vector3(11, 0, 0), Vector3(1, 0, 0) },
			{ Vector3() }, { 3, 0 }, { 9, 7 }, { 9 }, 2, 10.0, 2.0) == in_range);
	CHECK(ids[0] == 42);
}

TEST_CASE("[SignificanceBudget] stable world input validation is atomic") {
	Ref<SignificanceBudgetPlanner> p;
	p.instantiate();
	const PackedVector3Array positions = { Vector3(1, 0, 0), Vector3(2, 0, 0) };
	const PackedVector3Array viewers = { Vector3() };
	const PackedByteArray pri = { 1, 0 };
	const PackedInt64Array ids = { 4, 5 };
	CHECK(p->select_world_priority_stable(positions, viewers, pri, ids, {}, 2, 10.0).size() == 2);
	CHECK(p->select_world_priority_stable(positions, {}, pri, ids, {}, 2, 10.0).is_empty());
	CHECK(p->select_world_priority_stable(positions, { Vector3(Math::INF, 0, 0) }, pri, ids, {}, 2, 10.0).is_empty());
	CHECK(p->select_world_priority_stable({ Vector3(Math::INF, 0, 0) }, viewers, { 1 }, { 4 }, {}, 2, 10.0).is_empty());
	CHECK(p->select_world_priority_stable(positions, viewers, { 1 }, ids, {}, 2, 10.0).is_empty());
	CHECK(p->select_world_priority_stable(positions, viewers, { 1, 4 }, ids, {}, 2, 10.0).is_empty());
	CHECK(p->select_world_priority_stable(positions, viewers, pri, { 4, 4 }, {}, 2, 10.0).is_empty());
	CHECK(p->select_world_priority_stable(positions, viewers, pri, { 0, 5 }, {}, 2, 10.0).is_empty());
	CHECK(p->select_world_priority_stable(positions, viewers, pri, ids, { 4, 4 }, 2, 10.0).is_empty());
	CHECK(p->select_world_priority_stable(positions, viewers, pri, ids, { -4 }, 2, 10.0).is_empty());
	CHECK(p->select_world_priority_stable(positions, viewers, pri, ids, {}, -1, 10.0).is_empty());
	CHECK(p->select_world_priority_stable(positions, viewers, pri, ids, {}, 129, 10.0).is_empty());
	CHECK(p->select_world_priority_stable(positions, viewers, pri, ids, {}, 2, Math::NaN).is_empty());
	CHECK(p->select_world_priority_stable(positions, viewers, pri, ids, {}, 2, 10.0, -1.0).is_empty());
	CHECK(p->select_world_priority_stable(positions, viewers, pri, ids, {}, 2, 10.0, 11.0).is_empty());
}

TEST_CASE("[SignificanceBudget] view cone skips distant off-screen points but preserves near field") {
	Ref<SignificanceBudgetPlanner> planner;
	planner.instantiate();
	const PackedVector3Array points = {
		Vector3(0, 0, -4), Vector3(0, 0, 10), Vector3(1, 0, -8),
		Vector3(0, 0, -12), Vector3(0, 0, 2), Vector3(0, 0, -26)
	};
	const PackedByteArray priorities = { 0, 1, 0, 0, 0, 3 };
	const PackedInt64Array ids = { 101, 102, 103, 104, 105, 106 };
	const PackedInt32Array expected = { 4, 0, 2, 3 };
	CHECK(planner->select_world_priority_stable_cone(points, Vector3(),
			Vector3(0, 0, -1), priorities, ids, {}, 6, 20.0, 2.0,
			55.0, 3.0) == expected);
	// An off-screen high-priority point never steals a visual slot,
	// even when its stable ID was retained on the previous frame.
	CHECK(planner->select_world_priority_stable_cone(points, Vector3(),
			Vector3(0, 0, -1), priorities, ids, { 102, 106 }, 6,
			20.0, 2.0, 55.0, 3.0) == expected);
	CHECK(planner->select_world_priority_stable_cone(points, Vector3(),
			Vector3(0, 0, -5), priorities, ids, {}, 6, 20.0, 2.0,
			55.0, 3.0) == expected);
	CHECK(planner->select_world_priority_stable_cone(points, Vector3(),
			Vector3(0, 0, -1), priorities, ids, {}, 6, 20.0, 0.0,
			0.0, 3.0) == PackedInt32Array({ 4, 0, 3 }));
	CHECK(points[0] == Vector3(0, 0, -4));
}

TEST_CASE("[SignificanceBudget] full cone matches legacy world ranking and tiered hysteresis") {
	Ref<SignificanceBudgetPlanner> planner;
	planner.instantiate();
	const PackedVector3Array points = {
		Vector3(0, 0, 8), Vector3(0, 0, -8.8),
		Vector3(0, 0, -10), Vector3(0, 0, -2)
	};
	const PackedByteArray priorities = { 1, 1, 2, 0 };
	const PackedInt64Array ids = { 10, 11, 12, 13 };
	const PackedInt64Array retained = { 10, 11 };
	const PackedInt32Array old = planner->select_world_priority_stable(
			points, { Vector3() }, priorities, ids, retained, 3, 20.0, 2.0);
	CHECK(planner->select_world_priority_stable_cone(points, Vector3(),
			Vector3(1, 0, 0), priorities, ids, retained, 3, 20.0,
			2.0, 180.0, 0.0) == old);
	const PackedInt32Array front = planner->select_world_priority_stable_cone(
			points, Vector3(), Vector3(0, 0, -1), priorities,
			ids, retained, 3, 20.0, 2.0, 60.0, 3.0);
	CHECK(front == PackedInt32Array({ 2, 1, 3 }));
	const PackedVector3Array competing = {
		Vector3(0, 0, -8), Vector3(0, 0, -8.8)
	};
	const PackedByteArray equal_priority = { 0, 0 };
	CHECK(planner->select_world_priority_stable_cone(competing, Vector3(),
			Vector3(0, 0, -1), equal_priority, { 11, 12 }, { 12 }, 1,
			20.0, 2.0, 75.0, 3.0) == PackedInt32Array({ 1 }));
	CHECK(planner->select_world_priority_stable_cone(competing, Vector3(),
			Vector3(0, 0, -1), equal_priority, { 11, 12 }, {}, 1,
			20.0, 2.0, 75.0, 3.0) == PackedInt32Array({ 0 }));
	CHECK(planner->select_world_priority_stable_cone(
			{ Vector3(0, 0, 0), Vector3(0, 0, 0.1) }, Vector3(),
			Vector3(0, 0, -1), { 0, 0 }, { 4, 5 }, {}, 2,
			0.0, 0.0, 0.0, 0.0) == PackedInt32Array({ 0 }));
}

TEST_CASE("[SignificanceBudget] view-cone validation fails atomically") {
	Ref<SignificanceBudgetPlanner> planner;
	planner.instantiate();
	const PackedVector3Array points = {
		Vector3(0, 0, -1), Vector3(0, 0, -2)
	};
	const PackedByteArray priorities = { 0, 0 };
	const PackedInt64Array ids = { 11, 12 };
	const Vector3 origin;
	const Vector3 facing(0, 0, -1);
	CHECK(planner->select_world_priority_stable_cone(points, origin,
			Vector3(), priorities, ids, {}, 2).is_empty());
	CHECK(planner->select_world_priority_stable_cone(points, origin,
			Vector3(Math::NaN, 0, 1), priorities, ids, {}, 2).is_empty());
	CHECK(planner->select_world_priority_stable_cone(points,
			Vector3(Math::INF, 0, 0), facing, priorities, ids, {}, 2).is_empty());
	CHECK(planner->select_world_priority_stable_cone(points, origin,
			facing, { 0 }, ids, {}, 2).is_empty());
	CHECK(planner->select_world_priority_stable_cone(points, origin,
			facing, priorities, { 11 }, {}, 2).is_empty());
	CHECK(planner->select_world_priority_stable_cone(points, origin,
			facing, priorities, { 11, 11 }, {}, 2).is_empty());
	CHECK(planner->select_world_priority_stable_cone(points, origin,
			facing, priorities, ids, { 12, 12 }, 2).is_empty());
	CHECK(planner->select_world_priority_stable_cone(points, origin,
			facing, priorities, ids, {}, 129).is_empty());
	CHECK(planner->select_world_priority_stable_cone(points, origin,
			facing, priorities, ids, {}, 2, -1.0).is_empty());
	CHECK(planner->select_world_priority_stable_cone(points, origin,
			facing, priorities, ids, {}, 2, 1000001.0).is_empty());
	CHECK(planner->select_world_priority_stable_cone(points, origin,
			facing, priorities, ids, {}, 2, 10.0, -1.0).is_empty());
	CHECK(planner->select_world_priority_stable_cone(points, origin,
			facing, priorities, ids, {}, 2, 10.0, 11.0).is_empty());
	CHECK(planner->select_world_priority_stable_cone(points, origin,
			facing, priorities, ids, {}, 2, 10.0, 0.0, Math::NaN).is_empty());
	CHECK(planner->select_world_priority_stable_cone(points, origin,
			facing, priorities, ids, {}, 2, 10.0, 0.0, 181.0).is_empty());
	CHECK(planner->select_world_priority_stable_cone(points, origin,
			facing, priorities, ids, {}, 2, 10.0, 0.0, 75.0, -1.0).is_empty());
	CHECK(planner->select_world_priority_stable_cone(points, origin,
			facing, priorities, ids, {}, 2, 10.0, 0.0, 75.0, 11.0).is_empty());
	CHECK(planner->select_world_priority_stable_cone(
			{ Vector3(0, 0, -1), Vector3(0, Math::NaN, -2) },
			origin, facing, priorities, ids, {}, 2).is_empty());
	PackedVector3Array too_many;
	PackedByteArray many_priorities;
	PackedInt64Array many_ids;
	for (int i = 0; i < 16385; ++i) {
		too_many.push_back(Vector3(0, 0, -i));
		many_priorities.push_back(0);
		many_ids.push_back(i + 1);
	}
	CHECK(planner->select_world_priority_stable_cone(too_many, origin,
			facing, many_priorities, many_ids, {}, 2).is_empty());
}

} // namespace TestSignificanceBudgetPlanner
