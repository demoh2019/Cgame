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

} // namespace TestSignificanceBudgetPlanner
