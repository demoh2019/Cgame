// Standalone runtime tests for the Linux cgroup-v2 quota parser.
// Build from the repository root: c++ -std=c++17 -O2 -Wall -Wextra -Werror
// -I. misc/scripts/benchmarks/test_cgroup_cpu_quota.cpp -o /tmp/cgroup_test
#include "platform/linuxbsd/cgroup_cpu_quota.h"

#include <cassert>
#include <climits>
#include <cstdio>

int main() {
	using CgroupCPUQuota::parse_cpu_max;
	assert(parse_cpu_max("max 100000\n") == 0);
	assert(parse_cpu_max("max 100000") == 0);
	assert(parse_cpu_max("100000 100000\n") == 1);
	assert(parse_cpu_max("200000 100000\n") == 2);
	assert(parse_cpu_max("250000 100000\n") == 3);
	assert(parse_cpu_max("50000 100000\n") == 1);
	assert(parse_cpu_max("1 1000000\n") == 1);
	assert(parse_cpu_max("100000 100000") == 1);
	assert(parse_cpu_max("100000\t100000\r\n") == 1);
	assert(parse_cpu_max("100000    100000   \n") == 1);
	assert(parse_cpu_max("0 100000\n") == 0);
	assert(parse_cpu_max("100000 0\n") == 0);
	assert(parse_cpu_max("100000") == 0);
	assert(parse_cpu_max("100000 100000 trailing") == 0);
	assert(parse_cpu_max("100000 / 100000") == 0);
	assert(parse_cpu_max("-100000 100000") == 0);
	assert(parse_cpu_max("+100000 100000") == 0);
	assert(parse_cpu_max("100000 -100000") == 0);
	assert(parse_cpu_max("100000 +100000") == 0);
	assert(parse_cpu_max("garbage") == 0);
	assert(parse_cpu_max("") == 0);
	assert(parse_cpu_max(nullptr) == 0);
	assert(parse_cpu_max("18446744073709551615 1") == INT_MAX);
	assert(parse_cpu_max("18446744073709551616 1") == 0);
	assert(parse_cpu_max("1 18446744073709551616") == 0);
	assert(parse_cpu_max("18446744073709551615 18446744073709551615") == 1);
	assert(CgroupCPUQuota::effective_thread_count(64, 2) == 2);
	assert(CgroupCPUQuota::effective_thread_count(8, 0) == 8);
	assert(CgroupCPUQuota::effective_thread_count(2, 8) == 2);
	assert(CgroupCPUQuota::effective_thread_count(0, 0) == 1);
	assert(CgroupCPUQuota::effective_thread_count(-10, 3) == 1);
	assert(CgroupCPUQuota::read_cpu_max_file("/a/nonexistent/cgroup/file") == 0);
	const int active_quota = CgroupCPUQuota::read_cpu_max_file();
	assert(active_quota >= 0);
	std::printf("cgroup v2 parser: 32 checks passed; active quota: %d\n", active_quota);
}
