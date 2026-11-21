/**************************************************************************/
/*  test_crowd_animation_tier_planner.cpp                                 */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_crowd_animation_tier_planner)

#include "modules/modules_enabled.gen.h"

#ifdef MODULE_CROWD_ANIMATION_TIER_PLANNER_ENABLED

#include "modules/crowd_animation_tier_planner/crowd_animation_tier_planner.h"
#include "modules/crowd_animation_tier_planner/crowd_animation_budget_governor.h"

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



TEST_CASE("[CrowdAnimationTierPlanner] IK retention resists small camera moves but never hides urgent work") {
	Ref<CrowdAnimationTierPlanner> planner;
	planner.instantiate();
	const PackedFloat64Array distances = { 10.0, 10.4, 21.0, 22.0, 50.0 };
	const PackedByteArray priority = { 0, 0, 0, 1, 1 };
	const PackedByteArray all_visible = { 1, 1, 1, 1, 1 };
	const PackedByteArray retained = { 0, 1, 1, 1, 0 };
	const PackedInt32Array stable = planner->plan_visible_tiers_stable(
			distances, priority, all_visible, retained, 1, 1, 1.5);
	REQUIRE(stable.size() == 5);
	CHECK(stable[0] == 1); // Slightly nearer newcomer cannot steal IK.
	CHECK(stable[1] == 0); // Retained 10.4m IK owner keeps the slot.
	CHECK(stable[2] == 1); // Still 21m and eligible, but no spare IK slot.
	CHECK(stable[3] == 1); // 22m is ineligible for IK; combat is full-rate.
	CHECK(stable[4] == 2); // Combat slot already spent on nearer urgent pose.
	const PackedByteArray none_retained = { 0, 0, 0, 0, 0 };
	CHECK(planner->plan_visible_tiers_stable(distances, priority, all_visible,
			none_retained, 1, 1, 1.5) ==
			planner->plan_visible_tiers(distances, priority, all_visible, 1, 1));
	CHECK(planner->plan_visible_tiers_stable(distances, priority, all_visible,
			retained, 1, 1, 0.0) ==
			planner->plan_visible_tiers(distances, priority, all_visible, 1, 1));

	const PackedByteArray lost_visibility = { 1, 0, 1, 1, 1 };
	const PackedInt32Array hidden = planner->plan_visible_tiers_stable(
			distances, priority, lost_visibility, retained, 1, 1);
	REQUIRE(hidden.size() == 5);
	CHECK(hidden[0] == 0); // Invisible previous winner immediately releases IK.
	CHECK(hidden[1] == 2); // No IK and no combat promotion off screen.
	const PackedFloat64Array moved_closer = { 8.0, 10.4, 21.0, 22.0, 50.0 };
	const PackedInt32Array replaced = planner->plan_visible_tiers_stable(
			moved_closer, priority, all_visible, retained, 1, 1);
	REQUIRE(replaced.size() == 5);
	CHECK(replaced[0] == 0); // A materially closer actor still wins.
	CHECK(replaced[1] == 1);
	CHECK(retained[1] == 1); // Input flags are never modified.
}

TEST_CASE("[CrowdAnimationTierPlanner] stable IK validates bounds and ties atomically") {
	Ref<CrowdAnimationTierPlanner> planner;
	planner.instantiate();
	const PackedFloat64Array distances = { 10.0, 11.5, 22.0 };
	const PackedByteArray priorities = { 0, 0, 0 };
	const PackedByteArray visibility = { 1, 1, 1 };
	const PackedByteArray retention = { 0, 1, 1 };
	const PackedInt32Array tied = planner->plan_visible_tiers_stable(
			distances, priorities, visibility, retention, 1, 0, 1.5);
	REQUIRE(tied.size() == 3);
	CHECK(tied[0] == 0); // Equal effective distances break ties by input index.
	CHECK(tied[1] == 1);
	CHECK(tied[2] == 1); // Previous IK owner beyond 22m is still ineligible.
	ERR_PRINT_OFF
	CHECK(planner->plan_visible_tiers_stable(distances, priorities, visibility,
			{ 1 }, 1, 0).is_empty());
	CHECK(planner->plan_visible_tiers_stable(distances, priorities, { 1 },
			retention, 1, 0).is_empty());
	CHECK(planner->plan_visible_tiers_stable(distances, priorities, visibility,
			retention, 1, 0, -0.1).is_empty());
	CHECK(planner->plan_visible_tiers_stable(distances, priorities, visibility,
			retention, 1, 0, 8.1).is_empty());
	CHECK(planner->plan_visible_tiers_stable(distances, priorities, visibility,
			retention, 1, 0, std::numeric_limits<double>::quiet_NaN()).is_empty());
	CHECK(planner->plan_visible_tiers_stable({ -1.0 }, { 0 }, { 1 },
			{ 0 }, 1, 0).is_empty());
	ERR_PRINT_ON
}


TEST_CASE("[CrowdAnimationTierPlanner] Separate combat retention avoids presentation slot thrash") {
	Ref<CrowdAnimationTierPlanner> planner;
	planner.instantiate();
	const PackedFloat64Array distances = { 5.6, 5.4, 60.5, 60.3 };
	const PackedByteArray priority = { 0, 0, 1, 1 };
	const PackedByteArray visible = { 1, 1, 1, 1 };
	const PackedByteArray full_retained = { 1, 0, 0, 0 };
	const PackedByteArray combat_retained = { 0, 0, 1, 0 };
	const PackedInt32Array old = planner->plan_visible_tiers_stable(
			distances, priority, visible, full_retained, 1, 1, 1.5);
	REQUIRE(old.size() == 4);
	CHECK(old[0] == 0);
	CHECK(old[2] == 3);
	CHECK(old[3] == 1);
	const PackedInt32Array stable = planner->plan_visible_tiers_temporal(
			distances, priority, visible, full_retained, combat_retained, 1, 1, 1.5, 1.0);
	REQUIRE(stable.size() == 4);
	CHECK(stable[0] == 0); // Existing IK owner is unchanged.
	CHECK(stable[1] == 1);
	CHECK(stable[2] == 1); // Previously promoted distant telegraph persists.
	CHECK(stable[3] == 3);
	const PackedInt32Array outrun = planner->plan_visible_tiers_temporal(
			{ 7.0, 5.4, 62.0, 60.3 }, priority, visible,
			full_retained, combat_retained, 1, 1, 1.0, 1.0);
	CHECK(outrun[0] == 1);
	CHECK(outrun[1] == 0);
	CHECK(outrun[2] == 3);
	CHECK(outrun[3] == 1);
	CHECK(planner->plan_visible_tiers_temporal(distances, priority, visible,
			full_retained, combat_retained, 1, 1, 1.5, 0.0) == old);
}

TEST_CASE("[CrowdAnimationTierPlanner] Combat retention never crosses hard visibility and radius limits") {
	Ref<CrowdAnimationTierPlanner> planner;
	planner.instantiate();
	const PackedFloat64Array distances = { 21.9, 22.1, 89.9, 90.1, 3.0 };
	const PackedByteArray priority = { 0, 0, 1, 1, 1 };
	const PackedByteArray visible = { 1, 1, 1, 1, 0 };
	const PackedByteArray full_retained = { 1, 1, 0, 0, 1 };
	const PackedByteArray combat_retained = { 0, 0, 1, 1, 1 };
	const PackedInt32Array tiers = planner->plan_visible_tiers_temporal(
			distances, priority, visible, full_retained, combat_retained, 1, 1, 4.0, 4.0);
	REQUIRE(tiers.size() == 5);
	CHECK(tiers[0] == 0);
	CHECK(tiers[1] == 1); // IK remains strictly inside 22m.
	CHECK(tiers[2] == 1); // One in-range visible combat slot.
	CHECK(tiers[3] == 4); // 90m is not extended by hysteresis.
	CHECK(tiers[4] == 2); // Invisible previous winners never use budgets.
	const PackedInt32Array none = planner->plan_visible_tiers_temporal(
			{ 2.0, 4.0 }, { 1, 1 }, { 0, 0 }, { 1, 1 }, { 1, 1 }, 2, 2, 1.5, 2.0);
	const PackedInt32Array expected = { 2, 2 };
	CHECK(none == expected);
	ERR_PRINT_OFF
	CHECK(planner->plan_visible_tiers_temporal({ 5.0 }, { 1 }, { 1 }, { 1 },
			{}, 1, 1, 1.5, 1.0).is_empty());
	CHECK(planner->plan_visible_tiers_temporal({ 5.0 }, { 1 }, { 1 }, { 1 },
			{ 1 }, 1, 1, 1.5, -0.1).is_empty());
	CHECK(planner->plan_visible_tiers_temporal({ 5.0 }, { 1 }, { 1 }, { 1 },
			{ 1 }, 1, 1, 1.5, 4.1).is_empty());
	CHECK(planner->plan_visible_tiers_temporal({ 5.0 }, { 1 }, { 1 }, { 1 },
			{ 1 }, 1, 1, 1.5, std::numeric_limits<double>::quiet_NaN()).is_empty());
	ERR_PRINT_ON
}


TEST_CASE("[CrowdAnimationTierPlanner] CPU gate preserves both prior IK and independent combat scheduling") {
	Ref<CrowdAnimationTierPlanner> planner;
	planner.instantiate();
	const PackedFloat64Array distances = { 5.6, 5.4, 60.5, 60.3 };
	const PackedByteArray priority = { 0, 0, 1, 1 };
	const PackedByteArray visible = { 1, 1, 1, 1 };
	const PackedByteArray retained_full = { 1, 0, 0, 0 };
	const PackedByteArray retained_combat = { 0, 0, 1, 0 };
	const PackedInt32Array estimate = { 800, 90, 0, 0 };
	const PackedInt32Array base = planner->plan_visible_tiers_temporal(
			distances, priority, visible, retained_full, retained_combat, 1, 1, 1.5, 1.0);
	const PackedInt32Array base_expected = { 0, 1, 1, 3 };
	REQUIRE(base == base_expected);
	const PackedInt32Array capped = planner->cap_full_pose_cost(
			base, distances, retained_full, estimate, 100);
	const PackedInt32Array capped_expected = { 1, 1, 1, 3 };
	CHECK(capped == capped_expected); // Cost defers IK, not the 60.5m combat cue.
	CHECK(base == base_expected); // Never mutate the caller's previous tiers.
	CHECK(planner->cap_full_pose_cost(base, distances, retained_full, estimate, 0) == base);

	const PackedInt32Array candidate_tiers = { 0, 0, 0, 1, 2 };
	const PackedFloat64Array candidate_distances = { 2.0, 4.0, 10.0, 18.0, 55.0 };
	const PackedByteArray candidate_retained = { 0, 0, 0, 0, 0 };
	const PackedInt32Array costs = { 500, 100, 100, 100, 0 };
	const PackedInt32Array admitted = planner->cap_full_pose_cost(
			candidate_tiers, candidate_distances, candidate_retained, costs, 250);
	const PackedInt32Array admitted_expected = { 1, 0, 0, 1, 2 };
	CHECK(admitted == admitted_expected);
	CHECK(candidate_tiers[0] == 0);
}

TEST_CASE("[CrowdAnimationTierPlanner] CPU gate validates input and unsampled estimates") {
	Ref<CrowdAnimationTierPlanner> planner;
	planner.instantiate();
	const PackedInt32Array tiers = { 0, 0, 1 };
	const PackedFloat64Array distance = { 10.0, 10.4, 80.0 };
	const PackedByteArray retained = { 0, 1, 0 };
	const PackedInt32Array unknown = { 0, 0, 0 };
	const PackedInt32Array budgeted = planner->cap_full_pose_cost(
			tiers, distance, retained, unknown, 100);
	REQUIRE(budgeted.size() == 3);
	CHECK(budgeted[0] == 1);
	CHECK(budgeted[1] == 0); // Retained 10.4m owner consumes the 100us fallback.
	CHECK(budgeted[2] == 1);
	ERR_PRINT_OFF
	CHECK(planner->cap_full_pose_cost(tiers, distance, { 1 }, unknown, 100).is_empty());
	CHECK(planner->cap_full_pose_cost(tiers, distance, retained, { 0 }, 100).is_empty());
	CHECK(planner->cap_full_pose_cost({ 0, 5, 1 }, distance, retained, unknown, 100).is_empty());
	CHECK(planner->cap_full_pose_cost(tiers, { -1.0, 10.4, 80.0 }, retained, unknown, 100).is_empty());
	CHECK(planner->cap_full_pose_cost(tiers, distance, retained, { 0, -1, 0 }, 100).is_empty());
	CHECK(planner->cap_full_pose_cost(tiers, distance, retained, { 0, 100001, 0 }, 100).is_empty());
	CHECK(planner->cap_full_pose_cost(tiers, distance, retained, unknown, -1).is_empty());
	CHECK(planner->cap_full_pose_cost(tiers, distance, retained, unknown, 1000001).is_empty());
	CHECK(planner->cap_full_pose_cost(tiers, distance, retained, unknown, 100, Math::NaN).is_empty());
	CHECK(planner->cap_full_pose_cost(tiers, distance, retained, unknown, 100, 8.1).is_empty());
	PackedInt32Array too_many;
	PackedFloat64Array many_distances;
	PackedByteArray many_retained;
	PackedInt32Array many_costs;
	too_many.resize(257);
	many_distances.resize(257);
	many_retained.resize(257);
	many_costs.resize(257);
	CHECK(planner->cap_full_pose_cost(too_many, many_distances,
			many_retained, many_costs, 100).is_empty());
	ERR_PRINT_ON
}


TEST_CASE("[CrowdAnimationBudgetGovernor] hysteretic adaptation and gradual recovery") {
	Ref<CrowdAnimationBudgetGovernor> governor;
	governor.instantiate();
	CHECK(governor->get_max_budget_us() == 0);
	CHECK(governor->get_current_budget_us() == 0);
	CHECK(governor->get_frames_observed() == 0);
	REQUIRE(governor->configure(1500, 12500));
	CHECK(governor->get_current_budget_us() == 1500);
	for (int i = 0; i < 12; ++i) {
		CHECK(governor->observe_process_time(25000) == 1500);
	}
	CHECK(governor->get_frames_observed() == 12);
	CHECK(governor->get_pressure_percent() > 95);
	for (int i = 0; i < 12; ++i) {
		governor->observe_process_time(25000);
	}
	CHECK(governor->get_current_budget_us() == 1125); // 25% less after 2 bad windows.
	for (int i = 0; i < 24; ++i) {
		governor->observe_process_time(25000);
	}
	CHECK(governor->get_current_budget_us() == 844);
	// Quiet windows restore quality slowly (1/8 of configured maximum).
	for (int i = 0; i < 72; ++i) {
		governor->observe_process_time(2500);
	}
	CHECK(governor->get_current_budget_us() > 844);
	CHECK(governor->get_current_budget_us() < 1500);
	CHECK(governor->get_smoothed_process_us() <= 3000);
	CHECK(governor->get_frames_observed() == 120);

	// Re-applying identical settings must not discard learned pressure.
	const int previous_budget = governor->get_current_budget_us();
	REQUIRE(governor->configure(1500, 12500));
	CHECK(governor->get_current_budget_us() == previous_budget);
	CHECK(governor->observe_process_time(0) == previous_budget); // No sample.
	CHECK(governor->get_frames_observed() == 120);
}

TEST_CASE("[CrowdAnimationBudgetGovernor] bounds, quality transitions and enable override") {
	Ref<CrowdAnimationBudgetGovernor> governor;
	governor.instantiate();
	REQUIRE(governor->configure(750, 12500));
	for (int i = 0; i < 24; ++i) {
		governor->observe_process_time(50000);
	}
	CHECK(governor->get_current_budget_us() == 563);
	// Invalid configuration must be atomic and not reset evidence.
	const int before_frames = governor->get_frames_observed();
	CHECK_FALSE(governor->configure(-1, 12500));
	CHECK_FALSE(governor->configure(100001, 12500));
	CHECK_FALSE(governor->configure(750, 999));
	CHECK_FALSE(governor->configure(750, 100001));
	CHECK(governor->get_max_budget_us() == 750);
	CHECK(governor->get_current_budget_us() == 563);
	CHECK(governor->get_frames_observed() == before_frames);
	ERR_PRINT_OFF
	CHECK(governor->observe_process_time(-1) == -1);
	CHECK(governor->observe_process_time(1000001) == -1);
	ERR_PRINT_ON
	CHECK(governor->get_frames_observed() == before_frames);

	governor->set_enabled(false);
	CHECK(governor->get_current_budget_us() == 750);
	for (int i = 0; i < 24; ++i) {
		CHECK(governor->observe_process_time(100000) == 750);
	}
	CHECK(governor->get_frames_observed() == before_frames);
	governor->set_enabled(true);
	CHECK(governor->get_current_budget_us() == 750);
	CHECK(governor->get_frames_observed() == 0);
	REQUIRE(governor->configure(2750, 16000));
	CHECK(governor->get_current_budget_us() == 2750);
	CHECK(governor->get_frames_observed() == 0);
	REQUIRE(governor->configure(0, 12500)); // Performance: never admits full IK.
	CHECK(governor->observe_process_time(25000) == 0);
	CHECK(governor->get_frames_observed() == 0);
}

} // namespace TestCrowdAnimationTierPlanner
#endif // MODULE_CROWD_ANIMATION_TIER_PLANNER_ENABLED
