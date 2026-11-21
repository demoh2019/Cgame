/**************************************************************************/
/*  test_crowd_animation_tier_planner.cpp                                 */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_crowd_animation_tier_planner)

#include "modules/modules_enabled.gen.h"

#ifdef MODULE_CROWD_ANIMATION_TIER_PLANNER_ENABLED

#include "modules/crowd_animation_tier_planner/crowd_animation_tier_planner.h"

#include <limits>

namespace TestCrowdAnimationTierPlanner {

TEST_CASE("[CrowdAnimationTierPlanner] Numeric tier boundaries and combat priority") {
	Ref<CrowdAnimationTierPlanner> planner;
	planner.instantiate();
	const PackedFloat64Array distances = { 2.0, 4.0, 30.0, 55.0, 80.0, 100.0 };
	const PackedByteArray flags = { 0, 0, 0, 1, 1, 1 };
	const PackedInt32Array tiers = planner->plan_tiers(distances, flags, 1, 1);
	REQUIRE(tiers.size() == 6);
	CHECK(tiers[0] == 0);
	CHECK(tiers[1] == 1);
	CHECK(tiers[2] == 1);
	CHECK(tiers[3] == 1); // 55m attack tell is prioritized to full-rate, no IK.
	CHECK(tiers[4] == 3); // Lower-ranked 80m attack waits for a priority slot.
	CHECK(tiers[5] == 4); // Beyond 90m never gets combat priority.
	const PackedInt32Array two_priority = planner->plan_tiers(distances, flags, 1, 2);
	CHECK(two_priority[4] == 1);
	CHECK(distances[0] == 2.0); // Inputs remain unchanged.
}

TEST_CASE("[CrowdAnimationTierPlanner] Stable source index ties and zero budgets") {
	Ref<CrowdAnimationTierPlanner> planner;
	planner.instantiate();
	const PackedFloat64Array distances = { 5.0, 5.0, 5.0, 22.0, 38.0, 60.0, 90.0 };
	const PackedByteArray flags = { 1, 1, 1, 1, 1, 1, 1 };
	const PackedInt32Array tiers = planner->plan_tiers(distances, flags, 1, 0);
	REQUIRE(tiers.size() == 7);
	CHECK(tiers[0] == 0);
	CHECK(tiers[1] == 1);
	CHECK(tiers[2] == 1);
	CHECK(tiers[3] == 1);
	CHECK(tiers[4] == 2);
	CHECK(tiers[5] == 3);
	CHECK(tiers[6] == 4);
	const PackedInt32Array zero = planner->plan_tiers(distances, flags, 0, 0);
	CHECK(zero[0] == 1);
	CHECK(zero[1] == 1);
	const PackedInt32Array priority = planner->plan_tiers(distances, flags, 0, 2);
	CHECK(priority[0] == 1);
	CHECK(priority[1] == 1);
	CHECK(priority[5] == 3);
}


TEST_CASE("[CrowdAnimationTierPlanner] Bounded hysteresis prevents tier thrash") {
	Ref<CrowdAnimationTierPlanner> planner;
	planner.instantiate();
	const PackedByteArray no_flags = { 0, 0, 0, 0, 0 };
	const PackedInt32Array prior = { 0, 1, 2, 3, 4 };
	const PackedFloat64Array near_edges = { 22.3, 37.2, 60.6, 89.4, 90.2 };
	const PackedInt32Array held = planner->plan_tiers_stable(near_edges, no_flags, prior, 1, 0, 1.5);
	REQUIRE(held.size() == 5);
	CHECK(held[0] == 0);
	CHECK(held[1] == 1);
	CHECK(held[2] == 2);
	CHECK(held[3] == 3);
	CHECK(held[4] == 4);
	const PackedFloat64Array moved = { 23.6, 39.6, 62.0, 92.0, 87.0 };
	const PackedInt32Array changed = planner->plan_tiers_stable(moved, no_flags, prior, 1, 0, 1.5);
	REQUIRE(changed.size() == 5);
	CHECK(changed[0] == 1);
	CHECK(changed[1] == 2);
	CHECK(changed[2] == 3);
	CHECK(changed[3] == 4);
	CHECK(changed[4] == 3);

	// Hard quotas still apply to every frame despite previous full-pose wins.
	const PackedInt32Array crowd = planner->plan_tiers_stable({ 10.0, 10.4, 10.8 },
			{ 1, 1, 1 }, { 0, 1, 1 }, 1, 1, 1.5);
	REQUIRE(crowd.size() == 3);
	CHECK(crowd[0] == 0);
	CHECK(crowd[1] == 1);
	CHECK(crowd[2] == 1);
	const PackedInt32Array urgent = planner->plan_tiers_stable({ 90.5, 88.0 },
			{ 1, 1 }, { 1, 3 }, 0, 1, 1.5);
	REQUIRE(urgent.size() == 2);
	CHECK(urgent[0] == 1);
	CHECK(urgent[1] == 3);
}

TEST_CASE("[CrowdAnimationTierPlanner] Zero hysteresis preserves legacy tiers and invalid input rejects") {
	Ref<CrowdAnimationTierPlanner> planner;
	planner.instantiate();
	const PackedFloat64Array distances = { 4.0, 22.0, 37.0, 61.0, 90.0 };
	const PackedByteArray priority = { 0, 1, 1, 1, 1 };
	const PackedInt32Array previous = { 4, 0, 3, 2, 1 };
	CHECK(planner->plan_tiers_stable(distances, priority, previous, 1, 2, 0.0) ==
			planner->plan_tiers(distances, priority, 1, 2));
	ERR_PRINT_OFF
	CHECK(planner->plan_tiers_stable({ 3.0 }, { 0 }, PackedInt32Array(), 1, 0, 1.5).is_empty());
	CHECK(planner->plan_tiers_stable({ 3.0 }, { 0 }, { 5 }, 1, 0, 1.5).is_empty());
	CHECK(planner->plan_tiers_stable({ 3.0 }, { 0 }, { 0 }, 1, 0, -1.0).is_empty());
	CHECK(planner->plan_tiers_stable({ 3.0 }, { 0 }, { 0 }, 1, 0, 5.0).is_empty());
	CHECK(planner->plan_tiers_stable({ 3.0 }, { 0 }, { 0 }, 1, 0,
			std::numeric_limits<double>::quiet_NaN()).is_empty());
	CHECK(planner->plan_tiers_stable({ -1.0 }, { 0 }, { 0 }, 1, 0, 1.5).is_empty());
	ERR_PRINT_ON
}

TEST_CASE("[CrowdAnimationTierPlanner] Input validity, allocation limits and empty groups") {
	Ref<CrowdAnimationTierPlanner> planner;
	planner.instantiate();
	ERR_PRINT_OFF
	CHECK(planner->plan_tiers({ 2.0 }, PackedByteArray(), 1, 0).is_empty());
	CHECK(planner->plan_tiers({ -1.0 }, { 1 }, 1, 1).is_empty());
	CHECK(planner->plan_tiers({ std::numeric_limits<double>::infinity() }, { 1 }, 1, 1).is_empty());
	CHECK(planner->plan_tiers({ 1.0 }, { 1 }, -1, 0).is_empty());
	CHECK(planner->plan_tiers({ 1.0 }, { 1 }, 257, 0).is_empty());
	CHECK(planner->plan_tiers({ 1.0 }, { 1 }, 0, 257).is_empty());
	PackedFloat64Array huge;
	PackedByteArray flags;
	huge.resize(16385);
	flags.resize(16385);
	CHECK(planner->plan_tiers(huge, flags, 1, 1).is_empty());
	ERR_PRINT_ON
	CHECK(planner->plan_tiers(PackedFloat64Array(), PackedByteArray(), 0, 0).is_empty());
}

} // namespace TestCrowdAnimationTierPlanner
#endif // MODULE_CROWD_ANIMATION_TIER_PLANNER_ENABLED
