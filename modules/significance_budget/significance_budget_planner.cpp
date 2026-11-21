/**************************************************************************/
/*  significance_budget_planner.cpp                                        */
/*                         This file is part of: GODOT ENGINE              */
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* SPDX-License-Identifier: MIT                                           */
/**************************************************************************/

#include "significance_budget_planner.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/templates/vector.h"

namespace {

constexpr int MAX_CANDIDATES = 16384;
constexpr int MAX_VIEWERS = 16;
constexpr int MAX_BUDGET = 128;
constexpr double MAX_RANGE = 1000000.0;

struct Candidate {
	int priority = 0;
	double distance = 0.0; // squared for world queries; direct for precomputed.
	int index = 0;
};

static bool better(const Candidate &p_a, const Candidate &p_b) {
	if (p_a.priority != p_b.priority) {
		return p_a.priority > p_b.priority;
	}
	if (p_a.distance != p_b.distance) {
		return p_a.distance < p_b.distance;
	}
	return p_a.index < p_b.index;
}

// Bounded insertion instead of sorting an entire crowd; O(N * budget)
// time and O(budget) memory. Original-index ties make replays stable.
static void insert_best(Vector<Candidate> &r_best, const Candidate &p_candidate, int p_budget) {
	if (p_budget <= 0) {
		return;
	}
	if (r_best.size() == p_budget && !better(p_candidate, r_best[r_best.size() - 1])) {
		return;
	}
	int at = 0;
	while (at < r_best.size() && !better(p_candidate, r_best[at])) {
		at++;
	}
	r_best.insert(at, p_candidate);
	if (r_best.size() > p_budget) {
		r_best.resize(p_budget);
	}
}

static PackedInt32Array as_indices(const Vector<Candidate> &p_best) {
	PackedInt32Array result;
	result.resize(p_best.size());
	for (int i = 0; i < p_best.size(); ++i) {
		result.set(i, p_best[i].index);
	}
	return result;
}

static bool valid_budget(int p_budget) {
	return p_budget >= 0 && p_budget <= MAX_BUDGET;
}

static bool valid_priority(uint8_t p_priority) {
	return p_priority <= 3;
}

} // namespace

PackedInt32Array SignificanceBudgetPlanner::select_top(const PackedFloat64Array &p_distances,
		const PackedByteArray &p_priorities, int p_budget) const {
	PackedInt32Array empty;
	const int count = p_distances.size();
	ERR_FAIL_COND_V_MSG(count != p_priorities.size() || count > MAX_CANDIDATES ||
			!valid_budget(p_budget), empty, "Invalid significance array sizes or budget.");
	for (int i = 0; i < count; ++i) {
		ERR_FAIL_COND_V_MSG(!Math::is_finite(p_distances[i]) || p_distances[i] < 0.0 ||
			!valid_priority(p_priorities[i]), empty, "Significance inputs must be finite and priorities 0..3.");
	}
	Vector<Candidate> best;
	for (int i = 0; i < count; ++i) {
		insert_best(best, { p_priorities[i], p_distances[i], i }, p_budget);
	}
	return as_indices(best);
}

PackedInt32Array SignificanceBudgetPlanner::select_world(const PackedVector3Array &p_positions,
		const PackedVector3Array &p_viewers, const PackedByteArray &p_priorities,
		int p_budget, double p_max_distance) const {
	PackedInt32Array empty;
	const int count = p_positions.size();
	ERR_FAIL_COND_V_MSG(count != p_priorities.size() || count > MAX_CANDIDATES ||
			p_viewers.is_empty() || p_viewers.size() > MAX_VIEWERS ||
			!valid_budget(p_budget) || !Math::is_finite(p_max_distance) ||
			p_max_distance < 0.0 || p_max_distance > MAX_RANGE,
			empty, "Invalid world-significance inputs.");
	for (int v = 0; v < p_viewers.size(); ++v) {
		ERR_FAIL_COND_V_MSG(!p_viewers[v].is_finite(), empty, "Viewer positions must be finite.");
	}
	for (int i = 0; i < count; ++i) {
		ERR_FAIL_COND_V_MSG(!p_positions[i].is_finite() || !valid_priority(p_priorities[i]),
				empty, "World candidates must be finite with priorities 0..3.");
	}

	const double max_distance_squared = p_max_distance * p_max_distance;
	Vector<Candidate> best;
	for (int i = 0; i < count; ++i) {
		double nearest_squared = Math::INF;
		for (int v = 0; v < p_viewers.size(); ++v) {
			const double distance_squared = (p_positions[i] - p_viewers[v]).length_squared();
			ERR_FAIL_COND_V_MSG(!Math::is_finite(distance_squared), empty, "World distance overflow.");
			nearest_squared = MIN(nearest_squared, distance_squared);
		}
		if (nearest_squared <= max_distance_squared) {
			insert_best(best, { p_priorities[i], nearest_squared, i }, p_budget);
		}
	}
	return as_indices(best);
}

void SignificanceBudgetPlanner::_bind_methods() {
	ClassDB::bind_method(D_METHOD("select_top", "distances", "priorities", "budget"),
			&SignificanceBudgetPlanner::select_top);
	ClassDB::bind_method(D_METHOD("select_world", "positions", "viewers", "priorities", "budget", "max_distance"),
			&SignificanceBudgetPlanner::select_world, DEFVAL(1000.0));
}
