/**************************************************************************/
/* test_dynamic_resolution_panic_policy.h                                  */
/* SPDX-License-Identifier: MIT                                            */
/**************************************************************************/
#pragma once

#include "../dynamic_resolution_panic_policy.h"
#include "core/math/math_funcs.h"
#include "tests/test_macros.h"

namespace TestDynamicResolutionPanicPolicy {

TEST_CASE("[DynamicResolutionPanicPolicy] strict multi-frame GPU-only panic") {
	Ref<DynamicResolutionPanicPolicy> policy;
	policy.instantiate();
	CHECK(policy->calculate_scale(0.90, 0.65, 40.0, 20.0, 0) == doctest::Approx(0.90));
	CHECK(policy->calculate_scale(0.90, 0.65, 40.0, 20.0, 1) == doctest::Approx(0.90));
	CHECK(policy->calculate_scale(0.90, 0.65, 40.0, 20.0, 2) == doctest::Approx(0.90));
	CHECK(policy->calculate_scale(0.90, 0.65, 37.0, 20.0, 9) == doctest::Approx(0.90));
	CHECK(policy->calculate_scale(0.90, 0.65, 0.0, 20.0, 9) == doctest::Approx(0.90));
	CHECK(policy->calculate_scale(0.90, 0.65, 40.0, 20.0, 3) == doctest::Approx(0.78));
	CHECK(policy->calculate_scale(0.77, 0.71, 55.0, 20.0, 3) == doctest::Approx(0.71));
	CHECK(policy->calculate_scale(0.71, 0.71, 55.0, 20.0, 3) == doctest::Approx(0.71));
	CHECK(policy->calculate_scale(0.59, 0.52, 70.0, 20.0, 3) == doctest::Approx(0.52));
}

TEST_CASE("[DynamicResolutionPanicPolicy] invalid and hostile timing never resizes") {
	Ref<DynamicResolutionPanicPolicy> policy;
	policy.instantiate();
	CHECK(policy->calculate_scale(Math::NaN, 0.65, 40, 20, 3) == -1.0);
	CHECK(policy->calculate_scale(0.77, Math::INF, 40, 20, 3) == -1.0);
	CHECK(policy->calculate_scale(0.77, 0.78, 40, 20, 3) == -1.0);
	CHECK(policy->calculate_scale(0.77, 0.65, Math::NaN, 20, 3) == -1.0);
	CHECK(policy->calculate_scale(0.77, 0.65, 100, 20, 3) == -1.0);
	CHECK(policy->calculate_scale(0.77, 0.65, 40, 0, 3) == -1.0);
	CHECK(policy->calculate_scale(0.77, 0.65, 40, 20, -1) == -1.0);
	CHECK(policy->calculate_scale(0.77, 0.65, 40, 20, 1001) == -1.0);
	CHECK(policy->calculate_scale(0.77, 0.65, 40, 20, 3, 0) == -1.0);
	CHECK(policy->calculate_scale(0.77, 0.65, 40, 20, 3, 11) == -1.0);
}

TEST_CASE("[DynamicResolutionPanicPolicy] strictly monotone, bounded and deterministic") {
	Ref<DynamicResolutionPanicPolicy> policy;
	policy.instantiate();
	for (int floor_pct = 52; floor_pct <= 90; floor_pct += 7) {
		const double floor = floor_pct / 100.0;
		for (int current_pct = floor_pct; current_pct <= 100; current_pct += 3) {
			const double current = current_pct / 100.0;
			for (double gpu = 38.0; gpu <= 78.0; gpu += 4.0) {
				const double next = policy->calculate_scale(current, floor, gpu, 20.0, 3);
				CHECK(next <= current + 0.000001);
				CHECK(next >= floor - 0.000001);
				CHECK(next >= current - 0.120001);
				CHECK(next == policy->calculate_scale(current, floor, gpu, 20.0, 3));
			}
		}
	}
}
} // namespace TestDynamicResolutionPanicPolicy
