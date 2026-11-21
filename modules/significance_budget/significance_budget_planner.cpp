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
#include "core/templates/hash_set.h"

namespace {

constexpr int MAX_CANDIDATES = 16384;
constexpr int MAX_VIEWERS = 16;
constexpr int MAX_BUDGET = 128;
constexpr double MAX_RANGE = 1000000.0;

struct Candidate {
	int priority = 0;
	double distance = 0.0; // squared for world queries; direct for precomputed.
	int index = 0;
	int visible = 0; // Defaults to neutral for existing distance-only selectors.
};

static bool better(const Candidate &p_a, const Candidate &p_b) {
	if (p_a.priority != p_b.priority) {
		return p_a.priority > p_b.priority;
	}
	if (p_a.visible != p_b.visible) {
		return p_a.visible > p_b.visible;
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

PackedInt32Array SignificanceBudgetPlanner::select_effects(
		const PackedFloat64Array &p_distances, const PackedByteArray &p_priorities,
		const PackedByteArray &p_categories, const PackedInt32Array &p_category_caps,
		int p_budget, double p_max_distance) const {
	PackedInt32Array empty;
	const int count = p_distances.size();
	ERR_FAIL_COND_V_MSG(count != p_priorities.size() || count != p_categories.size() ||
			count > MAX_CANDIDATES || p_category_caps.size() != 4 ||
			!valid_budget(p_budget) || !Math::is_finite(p_max_distance) ||
			p_max_distance < 0.0 || p_max_distance > MAX_RANGE,
			empty, "Invalid effect significance arrays or budget.");
	for (int group = 0; group < 4; group++) {
		ERR_FAIL_COND_V_MSG(p_category_caps[group] < 0 || p_category_caps[group] > MAX_BUDGET,
				empty, "Category caps must be between 0 and 128.");
	}
	for (int i = 0; i < count; i++) {
		ERR_FAIL_COND_V_MSG(!Math::is_finite(p_distances[i]) ||
				p_distances[i] < 0.0 || !valid_priority(p_priorities[i]) ||
				p_categories[i] > 3, empty, "Invalid effect position, priority or category.");
	}
	if (p_budget == 0) {
		return empty;
	}

	// Keep only the best K in each category: O(N*K), O(4*K) scratch.
	// The result never depends on unordered hash iteration or frame state.
	Vector<Candidate> by_category[4];
	for (int i = 0; i < count; i++) {
		const int group = p_categories[i];
		if (p_distances[i] <= p_max_distance) {
			insert_best(by_category[group], { p_priorities[i], p_distances[i], i },
					MIN(p_budget, p_category_caps[group]));
		}
	}
	int cursors[4] = { 0, 0, 0, 0 };
	PackedInt32Array output;
	while (output.size() < p_budget) {
		int winner = -1;
		for (int group = 0; group < 4; group++) {
			if (cursors[group] >= by_category[group].size()) {
				continue;
			}
			if (winner < 0 || better(by_category[group][cursors[group]],
					by_category[winner][cursors[winner]])) {
				winner = group;
			}
		}
		if (winner < 0) {
			break;
		}
		output.push_back(by_category[winner][cursors[winner]].index);
		cursors[winner]++;
	}
	return output;
}


PackedInt32Array SignificanceBudgetPlanner::select_effects_visible(
		const PackedFloat64Array &p_distances, const PackedByteArray &p_priorities,
		const PackedByteArray &p_categories, const PackedByteArray &p_visible,
		const PackedInt32Array &p_category_caps, int p_budget, double p_max_distance) const {
	PackedInt32Array empty;
	const int count = p_distances.size();
	ERR_FAIL_COND_V_MSG(count != p_priorities.size() || count != p_categories.size() ||
			count != p_visible.size() || count > MAX_CANDIDATES ||
			p_category_caps.size() != 4 || !valid_budget(p_budget) ||
			!Math::is_finite(p_max_distance) || p_max_distance < 0.0 ||
			p_max_distance > MAX_RANGE,
			empty, "Invalid visible-effect significance arrays or budget.");
	for (int group = 0; group < 4; ++group) {
		ERR_FAIL_COND_V_MSG(p_category_caps[group] < 0 ||
				p_category_caps[group] > MAX_BUDGET,
				empty, "Visible-effect category caps must be between 0 and 128.");
	}
	for (int i = 0; i < count; ++i) {
		ERR_FAIL_COND_V_MSG(!Math::is_finite(p_distances[i]) ||
				p_distances[i] < 0.0 || !valid_priority(p_priorities[i]) ||
				p_categories[i] > 3 || p_visible[i] > 1,
				empty, "Invalid visible-effect distance, priority, category or visibility.");
	}
	if (p_budget == 0) {
		return empty;
	}

	// Work is bounded to category caps and the global budget. Important
	// off-screen hit feedback is never discarded simply for being off-screen.
	Vector<Candidate> by_category[4];
	for (int i = 0; i < count; ++i) {
		const int group = p_categories[i];
		if (p_distances[i] <= p_max_distance) {
			insert_best(by_category[group],
					{ p_priorities[i], p_distances[i], i, p_visible[i] },
					MIN(p_budget, p_category_caps[group]));
		}
	}
	int cursors[4] = { 0, 0, 0, 0 };
	PackedInt32Array output;
	while (output.size() < p_budget) {
		int winner = -1;
		for (int group = 0; group < 4; ++group) {
			if (cursors[group] >= by_category[group].size()) {
				continue;
			}
			if (winner < 0 || better(by_category[group][cursors[group]],
						by_category[winner][cursors[winner]])) {
				winner = group;
			}
		}
		if (winner < 0) {
			break;
		}
		output.push_back(by_category[winner][cursors[winner]].index);
		++cursors[winner];
	}
	return output;
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


namespace {

struct StableCandidate {
	double adjusted_distance = 0.0;
	double raw_distance = 0.0;
	int64_t id = 0;
	int index = 0;
};

static bool stable_better(const StableCandidate &p_a, const StableCandidate &p_b) {
	if (p_a.adjusted_distance != p_b.adjusted_distance) {
		return p_a.adjusted_distance < p_b.adjusted_distance;
	}
	if (p_a.raw_distance != p_b.raw_distance) {
		return p_a.raw_distance < p_b.raw_distance;
	}
	if (p_a.id != p_b.id) {
		return p_a.id < p_b.id;
	}
	return p_a.index < p_b.index;
}

// Reuse the stable-ID distance and deterministic tie comparator.
struct PriorityStableCandidate {
	int priority = 0;
	StableCandidate candidate;
};
static bool priority_stable_better(const PriorityStableCandidate &p_a, const PriorityStableCandidate &p_b) {
	return p_a.priority != p_b.priority ? p_a.priority > p_b.priority :
			stable_better(p_a.candidate, p_b.candidate);
}

} // namespace

PackedInt32Array SignificanceBudgetPlanner::select_top_priority_stable(
		const PackedFloat64Array &p_distances, const PackedByteArray &p_priorities,
		const PackedInt64Array &p_ids, const PackedInt64Array &p_retained_ids,
		int p_budget, double p_max_distance, double p_hysteresis) const {
	PackedInt32Array empty;
	const int count = p_distances.size();
	ERR_FAIL_COND_V_MSG(count != p_priorities.size() || count != p_ids.size() ||
			count > MAX_CANDIDATES || p_retained_ids.size() > MAX_BUDGET ||
			!valid_budget(p_budget) || !Math::is_finite(p_max_distance) ||
			p_max_distance < 0.0 || p_max_distance > MAX_RANGE ||
			!Math::is_finite(p_hysteresis) || p_hysteresis < 0.0 ||
			p_hysteresis > p_max_distance,
			empty, "Invalid priority-stable significance arrays or bounds.");

	HashSet<int64_t> ids;
	for (int i = 0; i < count; ++i) {
		ERR_FAIL_COND_V_MSG(!Math::is_finite(p_distances[i]) || p_distances[i] < 0.0 ||
				!valid_priority(p_priorities[i]) || p_ids[i] <= 0 || ids.has(p_ids[i]),
				empty, "Priority-stable significance requires finite distance, valid priority, and unique positive IDs.");
		ids.insert(p_ids[i]);
	}
	HashSet<int64_t> retained;
	for (int i = 0; i < p_retained_ids.size(); ++i) {
		const int64_t id = p_retained_ids[i];
		ERR_FAIL_COND_V_MSG(id <= 0 || retained.has(id), empty,
				"Retained significance IDs must be unique and positive.");
		retained.insert(id);
	}
	if (p_budget == 0) {
		return empty;
	}

	// Bounded insertion O(N*K), scratch O(K) plus O(N) ID-validation hash.
	Vector<PriorityStableCandidate> best;
	for (int i = 0; i < count; ++i) {
		if (p_distances[i] > p_max_distance) {
			continue; // Never extend the hard visual radius by hysteresis.
		}
		PriorityStableCandidate candidate;
		candidate.priority = p_priorities[i];
		candidate.candidate.adjusted_distance =
			MAX(0.0, p_distances[i] - (retained.has(p_ids[i]) ? p_hysteresis : 0.0));
		candidate.candidate.raw_distance = p_distances[i];
		candidate.candidate.id = p_ids[i];
		candidate.candidate.index = i;
		if (best.size() == p_budget && !priority_stable_better(candidate, best[best.size() - 1])) {
			continue;
		}
		int at = 0;
		while (at < best.size() && !priority_stable_better(candidate, best[at])) {
			++at;
		}
		best.insert(at, candidate);
		if (best.size() > p_budget) {
			best.resize(p_budget);
		}
	}
	PackedInt32Array result;
	for (const PriorityStableCandidate &entry : best) {
		result.push_back(entry.candidate.index);
	}
	return result;
}

PackedInt32Array SignificanceBudgetPlanner::select_top_stable(
		const PackedFloat64Array &p_distances, const PackedInt64Array &p_ids,
		const PackedInt64Array &p_retained_ids, int p_budget,
		double p_max_distance, double p_hysteresis) const {
	PackedInt32Array empty;
	const int count = p_distances.size();
	ERR_FAIL_COND_V_MSG(count != p_ids.size() || count > MAX_CANDIDATES ||
					p_retained_ids.size() > MAX_BUDGET || !valid_budget(p_budget) ||
					!Math::is_finite(p_max_distance) || p_max_distance < 0.0 ||
					p_max_distance > MAX_RANGE || !Math::is_finite(p_hysteresis) ||
					p_hysteresis < 0.0 || p_hysteresis > p_max_distance,
			empty, "Stable significance requires bounded arrays, budget, distance, and hysteresis.");

	HashSet<int64_t> ids;
	for (int i = 0; i < count; ++i) {
		ERR_FAIL_COND_V_MSG(!Math::is_finite(p_distances[i]) ||
						p_distances[i] < 0.0 || p_ids[i] <= 0 || ids.has(p_ids[i]),
				empty, "Stable significance requires finite distances and unique positive IDs.");
		ids.insert(p_ids[i]);
	}
	HashSet<int64_t> retained;
	for (int i = 0; i < p_retained_ids.size(); ++i) {
		if (p_retained_ids[i] > 0) {
			retained.insert(p_retained_ids[i]);
		}
	}
	if (p_budget == 0) {
		return empty;
	}

	// O(N * K) time and O(K) ranking memory, no scene queries or full sort.
	Vector<StableCandidate> best;
	for (int i = 0; i < count; ++i) {
		const double distance = p_distances[i];
		if (distance > p_max_distance) {
			continue; // Hysteresis never extends the actual visibility radius.
		}
		const StableCandidate candidate = {
			MAX(0.0, distance - (retained.has(p_ids[i]) ? p_hysteresis : 0.0)),
			distance, p_ids[i], i
		};
		if (best.size() == p_budget && !stable_better(candidate, best[best.size() - 1])) {
			continue;
		}
		int at = 0;
		while (at < best.size() && !stable_better(candidate, best[at])) {
			++at;
		}
		best.insert(at, candidate);
		if (best.size() > p_budget) {
			best.resize(p_budget);
		}
	}
	PackedInt32Array result;
	for (const StableCandidate &candidate : best) {
		result.push_back(candidate.index);
	}
	return result;
}


PackedInt32Array SignificanceBudgetPlanner::select_shadow_casters(
		const PackedVector3Array &p_bounds_min, const PackedVector3Array &p_bounds_max,
		const PackedByteArray &p_roles, const PackedByteArray &p_current,
		const Vector3 &p_camera, const PackedFloat64Array &p_role_radii,
		int p_budget, double p_hysteresis) const {
	PackedInt32Array empty;
	const int count = p_bounds_min.size();
	if (count != p_bounds_max.size() || count != p_roles.size() ||
			count != p_current.size() || count > MAX_CANDIDATES ||
			p_role_radii.size() != 3 || !valid_budget(p_budget) ||
			!p_camera.is_finite() || !Math::is_finite(p_hysteresis) ||
			p_hysteresis < 0.0 || p_hysteresis > 1000.0) {
		return empty;
	}
	for (int i = 0; i < 3; i++) {
		if (!Math::is_finite(p_role_radii[i]) || p_role_radii[i] < 0.0 ||
				p_role_radii[i] > MAX_RANGE) {
			return empty;
		}
	}
	// Validate every row before selecting anything; an invalid *late* box
	// never yields a partially filled GPU shadow plan.
	for (int i = 0; i < count; i++) {
		const Vector3 lo = p_bounds_min[i];
		const Vector3 hi = p_bounds_max[i];
		if (!lo.is_finite() || !hi.is_finite() ||
				lo.x > hi.x || lo.y > hi.y || lo.z > hi.z ||
				p_roles[i] > 3 || p_current[i] > 1 ||
				Math::abs(double(lo.x)) > MAX_RANGE ||
				Math::abs(double(lo.z)) > MAX_RANGE ||
				Math::abs(double(hi.x)) > MAX_RANGE ||
				Math::abs(double(hi.z)) > MAX_RANGE) {
			return empty;
		}
	}
	if (p_budget == 0) {
		return empty;
	}
	struct ShadowCandidate {
		int index = 0;
		int priority = 0;
		double adjusted = 0.0;
		double raw = 0.0;
	};
	// Reuse the same bounded top-K principle as the other significance
	// selectors: O(N * K), O(K) additional storage, deterministic ties.
	Vector<ShadowCandidate> best;
	for (int i = 0; i < count; i++) {
		const int role = p_roles[i];
		if (role == 3 || p_role_radii[role] <= 0.0) {
			continue;
		}
		const Vector3 lo = p_bounds_min[i];
		const Vector3 hi = p_bounds_max[i];
		const double dx = MAX(MAX(double(lo.x) - double(p_camera.x),
				double(p_camera.x) - double(hi.x)), 0.0);
		const double dz = MAX(MAX(double(lo.z) - double(p_camera.z),
				double(p_camera.z) - double(hi.z)), 0.0);
		const double distance = Math::sqrt(dx * dx + dz * dz);
		const bool already = p_current[i] != 0;
		const double allowed = MAX(0.0, p_role_radii[role] +
				(already ? p_hysteresis : -p_hysteresis));
		if (distance > allowed) {
			continue;
		}
		const ShadowCandidate candidate = {
			i, role, MAX(0.0, distance - (already ? p_hysteresis : 0.0)), distance
		};
		auto better_shadow = [](const ShadowCandidate &p_a, const ShadowCandidate &p_b) {
			if (p_a.priority != p_b.priority) {
				return p_a.priority > p_b.priority;
			}
			if (p_a.adjusted != p_b.adjusted) {
				return p_a.adjusted < p_b.adjusted;
			}
			if (p_a.raw != p_b.raw) {
				return p_a.raw < p_b.raw;
			}
			return p_a.index < p_b.index;
		};
		if (best.size() == p_budget && !better_shadow(candidate, best[best.size() - 1])) {
			continue;
		}
		int at = 0;
		while (at < best.size() && !better_shadow(candidate, best[at])) {
			at++;
		}
		best.insert(at, candidate);
		if (best.size() > p_budget) {
			best.resize(p_budget);
		}
	}
	PackedInt32Array selected;
	for (const ShadowCandidate &candidate : best) {
		selected.push_back(candidate.index);
	}
	return selected;
}

PackedInt32Array SignificanceBudgetPlanner::select_world_priority_stable(
		const PackedVector3Array &p_positions, const PackedVector3Array &p_viewers,
		const PackedByteArray &p_priorities, const PackedInt64Array &p_ids,
		const PackedInt64Array &p_retained_ids, int p_budget,
		double p_max_distance, double p_hysteresis) const {
	PackedInt32Array empty;
	const int count = p_positions.size();
	ERR_FAIL_COND_V_MSG(count != p_priorities.size() || count != p_ids.size() ||
			count > MAX_CANDIDATES || p_viewers.is_empty() ||
			p_viewers.size() > MAX_VIEWERS || p_retained_ids.size() > MAX_BUDGET ||
			!valid_budget(p_budget) || !Math::is_finite(p_max_distance) ||
			p_max_distance < 0.0 || p_max_distance > MAX_RANGE ||
			!Math::is_finite(p_hysteresis) || p_hysteresis < 0.0 ||
			p_hysteresis > p_max_distance,
			empty, "Invalid multi-viewer stable significance arrays or bounds.");

	for (int v = 0; v < p_viewers.size(); ++v) {
		ERR_FAIL_COND_V_MSG(!p_viewers[v].is_finite(), empty, "Viewer coordinates must be finite.");
	}
	HashSet<int64_t> ids;
	for (int i = 0; i < count; ++i) {
		ERR_FAIL_COND_V_MSG(!p_positions[i].is_finite() ||
				!valid_priority(p_priorities[i]) || p_ids[i] <= 0 ||
				ids.has(p_ids[i]), empty,
				"World candidates require finite positions, priority 0..3 and unique positive IDs.");
		ids.insert(p_ids[i]);
	}
	HashSet<int64_t> retained;
	for (int i = 0; i < p_retained_ids.size(); ++i) {
		const int64_t id = p_retained_ids[i];
		ERR_FAIL_COND_V_MSG(id <= 0 || retained.has(id), empty,
				"Retained world-significance IDs must be unique and positive.");
		retained.insert(id);
	}
	if (p_budget == 0) {
		return empty;
	}

	const double max_squared = p_max_distance * p_max_distance;
	Vector<PriorityStableCandidate> best;
	// At most 16 viewer-distance checks and 128 bounded insertions per actor.
	// Never let a retained low-priority actor displace a higher-priority one.
	for (int i = 0; i < count; ++i) {
		double nearest_squared = Math::INF;
		for (int v = 0; v < p_viewers.size(); ++v) {
			const double squared = (p_positions[i] - p_viewers[v]).length_squared();
			ERR_FAIL_COND_V_MSG(!Math::is_finite(squared), empty, "World distance overflow.");
			nearest_squared = MIN(nearest_squared, squared);
		}
		if (nearest_squared > max_squared) {
			continue; // A retention bonus must never extend the visible radius.
		}
		const double distance = Math::sqrt(nearest_squared);
		PriorityStableCandidate candidate;
		candidate.priority = p_priorities[i];
		candidate.candidate.adjusted_distance =
				MAX(0.0, distance - (retained.has(p_ids[i]) ? p_hysteresis : 0.0));
		candidate.candidate.raw_distance = distance;
		candidate.candidate.id = p_ids[i];
		candidate.candidate.index = i;
		if (best.size() == p_budget &&
				!priority_stable_better(candidate, best[best.size() - 1])) {
			continue;
		}
		int at = 0;
		while (at < best.size() && !priority_stable_better(candidate, best[at])) {
			++at;
		}
		best.insert(at, candidate);
		if (best.size() > p_budget) {
			best.resize(p_budget);
		}
	}
	PackedInt32Array result;
	for (const PriorityStableCandidate &entry : best) {
		result.push_back(entry.candidate.index);
	}
	return result;
}

void SignificanceBudgetPlanner::_bind_methods() {
	ClassDB::bind_method(D_METHOD("select_top", "distances", "priorities", "budget"),
			&SignificanceBudgetPlanner::select_top);
	ClassDB::bind_method(D_METHOD("select_effects", "distances", "priorities", "categories", "category_caps", "budget", "max_distance"),
			&SignificanceBudgetPlanner::select_effects);
	ClassDB::bind_method(D_METHOD("select_effects_visible", "distances", "priorities", "categories", "visible", "category_caps", "budget", "max_distance"),
			&SignificanceBudgetPlanner::select_effects_visible);
	ClassDB::bind_method(D_METHOD("select_top_priority_stable", "distances", "priorities", "ids", "retained_ids", "budget", "max_distance", "hysteresis"),
			&SignificanceBudgetPlanner::select_top_priority_stable, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("select_top_stable", "distances", "ids", "retained_ids", "budget", "max_distance", "hysteresis"),
			&SignificanceBudgetPlanner::select_top_stable, DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("select_shadow_casters", "bounds_min", "bounds_max", "roles", "current", "camera", "role_radii", "budget", "hysteresis"), &SignificanceBudgetPlanner::select_shadow_casters, DEFVAL(16), DEFVAL(5.0));
	ClassDB::bind_method(D_METHOD("select_world_priority_stable", "positions", "viewers", "priorities", "ids", "retained_ids", "budget", "max_distance", "hysteresis"),
			&SignificanceBudgetPlanner::select_world_priority_stable, DEFVAL(1000.0), DEFVAL(0.0));
	ClassDB::bind_method(D_METHOD("select_world", "positions", "viewers", "priorities", "budget", "max_distance"),
			&SignificanceBudgetPlanner::select_world, DEFVAL(1000.0));
}
