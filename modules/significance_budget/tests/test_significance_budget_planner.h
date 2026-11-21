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

} // namespace TestSignificanceBudgetPlanner
