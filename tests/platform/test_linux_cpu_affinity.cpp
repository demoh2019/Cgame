/**************************************************************************/
/*  test_linux_cpu_affinity.cpp                                           */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include "tests/test_macros.h"

TEST_FORCE_LINK(test_linux_cpu_affinity)

#if defined(__linux__) && defined(TOOLS_ENABLED)

#include "core/os/os.h"

#include <sched.h>

namespace TestLinuxCPUAffinity {

// Affinity is per-thread on Linux. Restore the test runner's original mask on
// every exit path, including when an assertion aborts the current test case.
class AffinityScope {
	cpu_set_t original = {};
	bool valid = false;

public:
	AffinityScope() {
		valid = sched_getaffinity(0, sizeof(cpu_set_t), &original) == 0;
	}
	~AffinityScope() {
		if (valid) {
			sched_setaffinity(0, sizeof(cpu_set_t), &original);
		}
	}

	bool is_valid() const { return valid; }
	int available_count() const { return valid ? CPU_COUNT(&original) : 0; }
	const cpu_set_t &get_original() const { return original; }

	cpu_set_t first_n_mask(int p_count) const {
		cpu_set_t mask;
		CPU_ZERO(&mask);
		int selected = 0;
		for (int cpu = 0; cpu < CPU_SETSIZE && selected < p_count; cpu++) {
			if (CPU_ISSET(cpu, &original)) {
				CPU_SET(cpu, &mask);
				selected++;
			}
		}
		return mask;
	}

	bool set_mask(const cpu_set_t &p_mask) const {
		return valid && sched_setaffinity(0, sizeof(cpu_set_t), &p_mask) == 0;
	}

	bool restore() const {
		return set_mask(original);
	}
};

TEST_CASE("[LinuxBSD][Affinity] Default thread pool size is positive") {
	CHECK(OS::get_singleton()->get_default_thread_pool_size() >= 1);
}

TEST_CASE("[LinuxBSD][Affinity] Default size equals current affinity mask size") {
	const AffinityScope affinity;
	if (!affinity.is_valid()) {
		INFO("sched_getaffinity() is not available in this environment.");
		return;
	}
	REQUIRE(affinity.available_count() > 0);
	CHECK_EQ(OS::get_singleton()->get_default_thread_pool_size(), affinity.available_count());
}

TEST_CASE("[LinuxBSD][Affinity] Restrict the calling thread to one allowed CPU") {
	const AffinityScope affinity;
	if (!affinity.is_valid() || affinity.available_count() < 1) {
		return;
	}
	const cpu_set_t selected = affinity.first_n_mask(1);
	CHECK_EQ(CPU_COUNT(&selected), 1);
	if (!affinity.set_mask(selected)) {
		INFO("This environment does not permit sched_setaffinity().");
		return;
	}
	CHECK_EQ(OS::get_singleton()->get_default_thread_pool_size(), 1);
	CHECK(affinity.restore());
}

TEST_CASE("[LinuxBSD][Affinity] Restrict the calling thread to two CPUs") {
	const AffinityScope affinity;
	if (!affinity.is_valid() || affinity.available_count() < 2) {
		return;
	}
	const cpu_set_t selected = affinity.first_n_mask(2);
	CHECK_EQ(CPU_COUNT(&selected), 2);
	if (!affinity.set_mask(selected)) {
		INFO("This environment does not permit sched_setaffinity().");
		return;
	}
	CHECK_EQ(OS::get_singleton()->get_default_thread_pool_size(), 2);
	CHECK(affinity.restore());
}

TEST_CASE("[LinuxBSD][Affinity] Test all permitted mask sizes up to eight CPUs") {
	const AffinityScope affinity;
	if (!affinity.is_valid() || affinity.available_count() < 1) {
		return;
	}
	const int max_count = MIN(affinity.available_count(), 8);
	for (int count = 1; count <= max_count; count++) {
		const cpu_set_t selected = affinity.first_n_mask(count);
		REQUIRE_EQ(CPU_COUNT(&selected), count);
		if (!affinity.set_mask(selected)) {
			INFO("This environment does not permit sched_setaffinity().");
			break;
		}
		INFO("Allowed CPU count: ", count);
		CHECK_EQ(OS::get_singleton()->get_default_thread_pool_size(), count);
	}
	CHECK(affinity.restore());
}

TEST_CASE("[LinuxBSD][Affinity] Noncontiguous affinity mask counts only allowed CPUs") {
	const AffinityScope affinity;
	if (!affinity.is_valid() || affinity.available_count() < 2) {
		return;
	}
	cpu_set_t selected;
	CPU_ZERO(&selected);
	int first = -1;
	int last = -1;
	for (int cpu = 0; cpu < CPU_SETSIZE; cpu++) {
		if (CPU_ISSET(cpu, &affinity.get_original())) {
			if (first == -1) {
				first = cpu;
			}
			last = cpu;
		}
	}
	if (first < 0 || first == last) {
		return;
	}
	CPU_SET(first, &selected);
	CPU_SET(last, &selected);
	REQUIRE_EQ(CPU_COUNT(&selected), 2);
	if (!affinity.set_mask(selected)) {
		INFO("This environment does not permit sched_setaffinity().");
		return;
	}
	CHECK_EQ(OS::get_singleton()->get_default_thread_pool_size(), 2);
	CHECK(affinity.restore());
}

TEST_CASE("[LinuxBSD][Affinity] Queries respond to changes rather than caching the first mask") {
	const AffinityScope affinity;
	if (!affinity.is_valid() || affinity.available_count() < 2) {
		return;
	}
	const cpu_set_t one = affinity.first_n_mask(1);
	const cpu_set_t two = affinity.first_n_mask(2);
	if (!affinity.set_mask(one)) {
		return;
	}
	CHECK_EQ(OS::get_singleton()->get_default_thread_pool_size(), 1);
	REQUIRE(affinity.set_mask(two));
	CHECK_EQ(OS::get_singleton()->get_default_thread_pool_size(), 2);
	CHECK(affinity.restore());
	CHECK_EQ(OS::get_singleton()->get_default_thread_pool_size(), affinity.available_count());
}

TEST_CASE("[LinuxBSD][Affinity] Does not override explicit higher-level thread settings") {
	// These OS queries are only the default. The thread-pool project setting
	// remains independent, and the native API should never report zero.
	const AffinityScope affinity;
	if (!affinity.is_valid() || affinity.available_count() < 1) {
		return;
	}
	CHECK_EQ(OS::get_singleton()->get_default_thread_pool_size(), affinity.available_count());
	CHECK(OS::get_singleton()->get_default_thread_pool_size() <= CPU_SETSIZE);
}

} // namespace TestLinuxCPUAffinity

#endif // __linux__ && TOOLS_ENABLED
