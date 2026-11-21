/**************************************************************************/
/*  test_ai_encounter_budget.h                                            */
/**************************************************************************/

#pragma once

#include "../ai_encounter_budget.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestAIEncounterBudget {

TEST_CASE("[AIEncounterBudget] Quiet, dense, wounded and world capacity") {
	Ref<AIEncounterBudget> policy;
	policy.instantiate();
	CHECK(policy->get_global_limit() == 150);
	CHECK(policy->get_local_hard_limit() == 20);
	CHECK(policy->get_spawn_budget(0, 0, 1.0, 0) == 7);
	CHECK(policy->get_spawn_budget(0, 0, 1.0, 3) == 10);
	CHECK(policy->get_spawn_budget(0, 8, 1.0, 3) == 4);
	CHECK(policy->get_spawn_budget(0, 12, 1.0, 3) == 2);
	CHECK(policy->get_spawn_budget(0, 20, 1.0, 3) == 0);
	CHECK(policy->get_spawn_budget(0, 0, 0.20, 3) == 2);
	CHECK(policy->get_spawn_budget(0, 0, 0.50, 3) == 4);
	CHECK(policy->get_spawn_budget(149, 0, 1.0, 3) == 1);
	CHECK(policy->get_spawn_budget(150, 0, 1.0, 3) == 0);
	CHECK(policy->get_spawn_budget(0, 0, 2.0, 3) == 10);
	CHECK(policy->get_spawn_budget(0, 0, -4.0, 3) == 2);
	CHECK(policy->get_spawn_budget(0, 0, 1.0, -2) == 7);
	CHECK(policy->get_spawn_budget(0, 0, 1.0, 500) == 10);
}

TEST_CASE("[AIEncounterBudget] Pressure respite can never shorten original recovery") {
	Ref<AIEncounterBudget> policy;
	policy.instantiate();
	CHECK(policy->get_respite_seconds(100.0, 0, 1.0) == 100.0);
	CHECK(policy->get_respite_seconds(100.0, 8, 1.0) == 120.0);
	CHECK(policy->get_respite_seconds(100.0, 12, 0.20) == 175.0);
	CHECK(policy->get_respite_seconds(0.0, 12, 0.20) == 75.0);
	CHECK(policy->get_respite_seconds(100.0, 12, 0.50) == 160.0);
	CHECK(policy->get_respite_seconds(100.0, 3, 0.5) == 115.0);
}

TEST_CASE("[AIEncounterBudget] Invalid state rejects spawns and invalid config rolls back") {
	Ref<AIEncounterBudget> policy;
	policy.instantiate();
	CHECK_FALSE(policy->configure_limits(10, 8, 12, 20, 7, 10, 3));
	CHECK(policy->get_global_limit() == 150);
	CHECK(policy->configure_limits(300, 4, 6, 12, 3, 7, 4));
	CHECK(policy->get_global_limit() == 300);
	CHECK(policy->get_soft_density() == 4);
	CHECK(policy->get_dense_density() == 6);
	CHECK(policy->get_local_hard_limit() == 12);
	CHECK(policy->get_spawn_budget(0, 0, 1.0, 0) == 3);
	CHECK(policy->get_spawn_budget(0, 0, 1.0, 4) == 7);
	CHECK(policy->get_spawn_budget(0, 4, 1.0, 4) == 4);
	CHECK(policy->get_spawn_budget(0, 6, 1.0, 4) == 2);
	CHECK(policy->get_spawn_budget(0, 12, 1.0, 4) == 0);
	ERR_PRINT_OFF;
	CHECK_FALSE(policy->configure_limits(300, 6, 4, 12, 3, 7, 4));
	CHECK_FALSE(policy->configure_limits(300, 4, 6, 6, 3, 7, 4));
	CHECK_FALSE(policy->configure_limits(300, 4, 6, 12, 8, 7, 4));
	CHECK_FALSE(policy->configure_limits(300, 4, 6, 12, 3, 7, 11));
	ERR_PRINT_ON;
	CHECK(policy->get_global_limit() == 300);
	CHECK(policy->get_soft_density() == 4);
	CHECK(policy->get_local_hard_limit() == 12);
	CHECK(policy->get_spawn_budget(-1, 0, 1.0, 3) == 0);
	CHECK(policy->get_spawn_budget(0, -1, 1.0, 3) == 0);
	CHECK(policy->get_spawn_budget(0, 0, Math::NaN, 3) == 0);
	CHECK(policy->get_spawn_budget(0, 0, Math::INF, 3) == 0);
	CHECK(policy->get_respite_seconds(Math::NaN, 8, 0.5) == 0.0);
	CHECK(policy->get_respite_seconds(-1.0, 8, 0.5) == 0.0);
	CHECK(policy->get_respite_seconds(90.0, 8, Math::NaN) == 0.0);
}

} // namespace TestAIEncounterBudget
