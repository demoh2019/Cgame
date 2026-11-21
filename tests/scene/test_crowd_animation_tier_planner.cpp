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


TEST_CASE("[CrowdAnimationTierPlanner] Visibility reallocates expensive IK and protects camera-facing attacks") {
	Ref<CrowdAnimationTierPlanner> planner;
	planner.instantiate();
	const PackedFloat64Array distances = { 2.0, 4.0, 6.0, 55.0, 80.0, 100.0 };
	const PackedByteArray priority = { 1, 0, 0, 1, 1, 1 };
	const PackedByteArray visible = { 0, 1, 1, 1, 0, 1 };
	const PackedInt32Array tiers = planner->plan_visible_tiers(distances, priority, visible, 1, 1);
	REQUIRE(tiers.size() == 6);
	CHECK(tiers[0] == 2); // An off-screen nearest actor cannot claim IK.
	CHECK(tiers[1] == 0); // The first visible nearby actor gets the IK slot.
	CHECK(tiers[2] == 1); // Another visible near actor runs without IK.
	CHECK(tiers[3] == 1); // Visible combat telegraph retains full-rate pose.
	CHECK(tiers[4] == 3); // Off-screen combat flags never receive priority.
	CHECK(tiers[5] == 4); // Far distance tier remains unchanged.
	const PackedByteArray all_visible = { 1, 1, 1, 1, 1, 1 };
	CHECK(planner->plan_visible_tiers(distances, priority, all_visible, 1, 1) ==
			planner->plan_tiers(distances, priority, 1, 1));
	const PackedByteArray none_visible = { 0, 0, 0, 0, 0, 0 };
	const PackedInt32Array all_throttled = planner->plan_visible_tiers(distances, priority, none_visible, 16, 16);
	REQUIRE(all_throttled.size() == 6);
	CHECK(all_throttled[0] == 2);
	CHECK(all_throttled[1] == 2);
	CHECK(all_throttled[2] == 2);
	CHECK(all_throttled[3] == 2);
	CHECK(all_throttled[4] == 3);
	CHECK(all_throttled[5] == 4);
}

TEST_CASE("[CrowdAnimationTierPlanner] Visibility input validation and stable ties") {
	Ref<CrowdAnimationTierPlanner> planner;
	planner.instantiate();
	const PackedFloat64Array distances = { 5.0, 5.0, 5.0, 22.0, 38.0 };
	const PackedByteArray priority = { 1, 1, 1, 1, 1 };
	const PackedByteArray visible = { 0, 1, 1, 1, 1 };
	const PackedInt32Array tiers = planner->plan_visible_tiers(distances, priority, visible, 1, 0);
	REQUIRE(tiers.size() == 5);
	CHECK(tiers[0] == 2);
	CHECK(tiers[1] == 0); // Stable ties select earliest visible index.
	CHECK(tiers[2] == 1);
	CHECK(tiers[3] == 1);
	CHECK(tiers[4] == 2);
	ERR_PRINT_OFF
	CHECK(planner->plan_visible_tiers(distances, priority, { 1 }, 1, 1).is_empty());
	CHECK(planner->plan_visible_tiers(distances, priority, visible, -1, 0).is_empty());
	CHECK(planner->plan_visible_tiers(distances, priority, visible, 0, 257).is_empty());
	CHECK(planner->plan_visible_tiers({ Math::NaN }, { 0 }, { 1 }, 1, 1).is_empty());
	CHECK(planner->plan_visible_tiers({ -1.0 }, { 0 }, { 1 }, 1, 1).is_empty());
	ERR_PRINT_ON
	const PackedFloat64Array empty_distances;
	const PackedByteArray empty_flags;
	CHECK(planner->plan_visible_tiers(empty_distances, empty_flags, empty_flags, 1, 1).is_empty());
}


} // namespace TestCrowdAnimationTierPlanner
#endif // MODULE_CROWD_ANIMATION_TIER_PLANNER_ENABLED
