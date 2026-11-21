/**************************************************************************/
/*  crowd_animation_tier_planner.cpp                                      */
/*  This file is part of the Godot Engine (MIT License).                   */
/**************************************************************************/

#include "crowd_animation_tier_planner.h"

#include "core/math/math_funcs.h"
#include "core/object/class_db.h"
#include "core/templates/vector.h"

#include <cstdint>

namespace {

struct RankedCandidate {
	double distance = 0.0;
	int index = 0;
};

static bool better(const RankedCandidate &p_a, const RankedCandidate &p_b) {
	return p_a.distance < p_b.distance ||
			(p_a.distance == p_b.distance && p_a.index < p_b.index);
}

// A bounded stable top-K: O(actors * slots), O(slots) metadata, no full sort
// of the crowd, and deterministic original-index ties.
static void insert_top(Vector<RankedCandidate> &r_best, const RankedCandidate &p_candidate, int p_limit) {
	if (p_limit <= 0) {
		return;
	}
	if (r_best.size() == p_limit && !better(p_candidate, r_best[r_best.size() - 1])) {
		return;
	}
	int at = 0;
	while (at < r_best.size() && !better(p_candidate, r_best[at])) {
		at++;
	}
	r_best.insert(at, p_candidate);
	if (r_best.size() > p_limit) {
		r_best.resize(p_limit);
	}
}

static int distance_tier(double p_distance) {
	if (p_distance < 22.0) {
		return 0;
	}
	if (p_distance < 38.0) {
		return 1;
	}
	if (p_distance < 60.0) {
		return 2;
	}
	if (p_distance < 90.0) {
		return 3;
	}
	return 4;
}

} // namespace

void CrowdAnimationTierPlanner::_bind_methods() {
	ClassDB::bind_method(D_METHOD("plan_tiers", "distances", "priority_flags", "full_budget", "priority_budget"),
			&CrowdAnimationTierPlanner::plan_tiers);
	ClassDB::bind_method(D_METHOD("plan_visible_tiers", "distances", "priority_flags", "visible_flags", "full_budget", "priority_budget"),
			&CrowdAnimationTierPlanner::plan_visible_tiers);
	ClassDB::bind_method(D_METHOD("plan_visible_tiers_stable", "distances", "priority_flags", "visible_flags", "retained_full_flags", "full_budget", "priority_budget", "hysteresis"),
			&CrowdAnimationTierPlanner::plan_visible_tiers_stable, DEFVAL(1.5));
	ClassDB::bind_method(D_METHOD("plan_visible_tiers_temporal", "distances", "priority_flags", "visible_flags", "retained_full_flags", "retained_priority_flags", "full_budget", "priority_budget", "full_hysteresis", "priority_hysteresis"),
			&CrowdAnimationTierPlanner::plan_visible_tiers_temporal);
}

// Shared budget planner: no second sorting pass and no additional per-actor
// visibility metadata for legacy callers. Pure data; no scene-tree queries.
static PackedInt32Array plan_tiers_internal(
		const PackedFloat64Array &p_distances, const PackedByteArray &p_priority_flags,
		const PackedByteArray *p_visible_flags, const PackedByteArray *p_retained_full_flags,
		int p_full_budget, int p_priority_budget, double p_hysteresis,
		const PackedByteArray *p_retained_priority_flags, double p_priority_hysteresis) {
	PackedInt32Array output;
	const int count = p_distances.size();
	ERR_FAIL_COND_V_MSG(count != p_priority_flags.size(), output, "Distance and priority arrays must match.");
	ERR_FAIL_COND_V_MSG(p_visible_flags != nullptr && p_visible_flags->size() != count, output,
			"Visibility flags must match crowd distances.");
	ERR_FAIL_COND_V_MSG(p_retained_full_flags != nullptr && p_retained_full_flags->size() != count, output,
			"Retained full-IK flags must match crowd distances.");
	ERR_FAIL_COND_V_MSG(p_retained_priority_flags != nullptr && p_retained_priority_flags->size() != count, output,
			"Retained combat-priority flags must match crowd distances.");
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_hysteresis) || p_hysteresis < 0.0 || p_hysteresis > 8.0, output,
			"Full-IK retention hysteresis must be finite and within 0..8 metres.");
	ERR_FAIL_COND_V_MSG(!Math::is_finite(p_priority_hysteresis) ||
			p_priority_hysteresis < 0.0 || p_priority_hysteresis > 4.0, output,
			"Combat animation retention must be finite and within 0..4 metres.");
	ERR_FAIL_COND_V_MSG(count > 16384, output, "Crowd tier planning is limited to 16384 actors.");
	ERR_FAIL_COND_V_MSG(p_full_budget < 0 || p_full_budget > 256 ||
					p_priority_budget < 0 || p_priority_budget > 256,
			output, "Crowd tier budgets must be between 0 and 256.");
	// Validate every value before writing a partial result.
	for (int i = 0; i < count; i++) {
		ERR_FAIL_COND_V_MSG(!Math::is_finite(p_distances[i]) || p_distances[i] < 0.0,
				output, "Crowd distance must be finite and nonnegative.");
	}
	output.resize(count);
	int32_t *tiers = output.ptrw();
	Vector<RankedCandidate> nearest_full;
	Vector<RankedCandidate> nearest_critical;
	for (int i = 0; i < count; i++) {
		const double distance = p_distances[i];
		const int tier = distance_tier(distance);
		const bool visible = p_visible_flags == nullptr || (*p_visible_flags)[i] != 0;
		// Off-camera actors keep playing at a reduced rate, but never spend
		// full-IK or combat-priority slots reserved for visible characters.
		tiers[i] = visible ? (tier == 0 ? 1 : tier) : MAX(tier, 2);
		if (!visible) {
			continue;
		}
		if (tier == 0) {
			// Only within the original 22m threshold: retention never makes
			// hidden or out-of-range characters eligible for expensive IK.
			const bool retained = p_retained_full_flags != nullptr && (*p_retained_full_flags)[i] != 0;
			const RankedCandidate ik_candidate = { MAX(0.0, distance - (retained ? p_hysteresis : 0.0)), i };
			insert_top(nearest_full, ik_candidate, p_full_budget);
		}
		if (p_priority_flags[i] != 0 && distance < 90.0) {
			// Only the combat queue receives this secondary retention hint.
			// Eligibility and actual camera distance remain unchanged; IK
			// and combat budgets have independent deterministic rankings.
			const bool retained_priority = p_retained_priority_flags != nullptr &&
					(*p_retained_priority_flags)[i] != 0;
			const RankedCandidate combat_candidate = {
				MAX(0.0, distance - (retained_priority ? p_priority_hysteresis : 0.0)), i
			};
			insert_top(nearest_critical, combat_candidate, p_priority_budget);
		}
	}
	for (int i = 0; i < nearest_full.size(); i++) {
		tiers[nearest_full[i].index] = 0;
	}
	for (int i = 0; i < nearest_critical.size(); i++) {
		const int index = nearest_critical[i].index;
		tiers[index] = MIN(tiers[index], 1);
	}
	return output;
}


PackedInt32Array CrowdAnimationTierPlanner::plan_tiers(
		const PackedFloat64Array &p_distances, const PackedByteArray &p_priority_flags,
		int p_full_budget, int p_priority_budget) const {
	return plan_tiers_internal(p_distances, p_priority_flags, nullptr, nullptr, p_full_budget, p_priority_budget, 0.0, nullptr, 0.0);
}

PackedInt32Array CrowdAnimationTierPlanner::plan_visible_tiers(
		const PackedFloat64Array &p_distances, const PackedByteArray &p_priority_flags,
		const PackedByteArray &p_visible_flags, int p_full_budget, int p_priority_budget) const {
	return plan_tiers_internal(p_distances, p_priority_flags, &p_visible_flags, nullptr, p_full_budget, p_priority_budget, 0.0, nullptr, 0.0);
}

PackedInt32Array CrowdAnimationTierPlanner::plan_visible_tiers_stable(
		const PackedFloat64Array &p_distances, const PackedByteArray &p_priority_flags,
		const PackedByteArray &p_visible_flags, const PackedByteArray &p_retained_full_flags,
		int p_full_budget, int p_priority_budget, double p_hysteresis) const {
	return plan_tiers_internal(p_distances, p_priority_flags, &p_visible_flags, &p_retained_full_flags,
			p_full_budget, p_priority_budget, p_hysteresis, nullptr, 0.0);
}

PackedInt32Array CrowdAnimationTierPlanner::plan_visible_tiers_temporal(
		const PackedFloat64Array &p_distances, const PackedByteArray &p_priority_flags,
		const PackedByteArray &p_visible_flags, const PackedByteArray &p_retained_full_flags,
		const PackedByteArray &p_retained_priority_flags, int p_full_budget,
		int p_priority_budget, double p_full_hysteresis, double p_priority_hysteresis) const {
	return plan_tiers_internal(p_distances, p_priority_flags, &p_visible_flags,
			&p_retained_full_flags, p_full_budget, p_priority_budget, p_full_hysteresis,
			&p_retained_priority_flags, p_priority_hysteresis);
}
